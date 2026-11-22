# The JIT compiler

## Enabling and configuring

```go
L := lua.NewState(lua.Options{
    JIT: lua.JITOptions{
        Enabled:           true,
        Threshold:         50,       // loop iterations before a loop is compiled (default 50)
        MaxCodeBytes:      16 << 20, // executable memory per state (default 16 MiB)
        SafePointInterval: 65536,    // loop iterations between returns to Go (default 65536)
        Log:               os.Stderr, // optional: one line per JIT event
    },
})
```

- The JIT is **off by default**. `JITOptions.Enabled` is ignored where the
  JIT cannot run (unsupported OS or architecture, x86-64 CPUs without
  SSE4.1, or when executable memory cannot be mapped – for instance in a
  macOS hardened-runtime process without the JIT entitlement). The
  interpreter is used instead; `L.JITStats().Enabled` / `.Supported` tell
  which case applies.
- Results are the same with and without the JIT. Any difference is a bug.
- Enabling the JIT also enables unboxed array parts for the tables of that
  state (see [architecture.md](architecture.md)); this is invisible to Lua
  code and to the Go API.

## Diagnostics

```go
st := L.JITStats()
fmt.Println(st)          // one line summary
st.Compiled              // units compiled so far
st.CompileFailed         // compilation attempts rejected
st.Invalidated           // units discarded (recompilation, cache flush)
st.Blacklisted           // loops permanently left to the interpreter
st.CacheFlushes          // how often MaxCodeBytes was reached
st.LiveUnits, st.CodeBytes, st.MaxCodeBytes
st.Entries, st.Deopts, st.Callouts, st.SafePoints
st.CompileTime           // total time spent compiling
L.JITFlush()             // discard all compiled code of the state
```

`JITOptions.Log` receives lines such as

```
jit: compiled bench.lua:2@5: 764 bytes, 4 blocks, 46 values, 0 spills, 8 exits, 0 callout sites
jit: discard unit at pc 5: guard at pc 8 fails too often
jit: blacklist loop at pc 17: loop is dominated by interpreter callouts
```

Setting the environment variable `GOPHERLUA_JIT_DUMP=1` additionally logs
the SSA of every compiled unit. `cmd/glua` has `-jit`, `-jit-threshold`,
`-jitstats` and `-jitlog`.

## What runs natively

Compiled natively inside hot loops (both profiles):

- arithmetic on integers and floats (`+ - * / // % ^2 ^0.5`, unary minus),
  bitwise operators (Lua 5.5), comparisons, `not`, `and`/`or`, conditionals;
- numeric `for` loops (integer and float, constant step), `while`,
  `repeat`, `break`, `goto` loops, nested loops;
- reads and writes of array elements with integer keys on tables whose
  array part holds only integers or only floats, including appends that fit
  the capacity; reads of numbers from mixed arrays; the length operator on
  such tables;
- truth tests and comparisons with `nil` on arbitrary values;
- `math.sqrt`, `math.floor`, `math.ceil`, `math.abs` when reached through
  the unmodified `math` table.

Executed by the interpreter on behalf of native code (a *callout*; correct
but with a fixed overhead of a few dozen nanoseconds each):

- everything involving strings, hash-table field access (`t.name`),
  upvalue access, table creation, closures, metamethods;
- calls: Go functions run directly, Lua functions run in a nested
  interpreter loop (and may enter native code themselves).

Not compiled (the loop stays in the interpreter):

- generic `for` loops (`pairs`, `ipairs`, custom iterators), vararg
  expressions, calls with a variable number of arguments or results,
  tail calls and returns inside the loop body end the compiled region;
- loops that mostly consist of callouts – the JIT measures this at run time
  and hands such loops back to the interpreter;
- functions without loops. There is no function inlining and no native
  call/return, so recursion (`fib`) is not accelerated.

## Resource bounds

- **Code memory**: each state maps at most `MaxCodeBytes` of executable
  memory (page granular; a unit occupies at least one page). When the limit
  is reached all units of the state are discarded and compilation starts
  over; after eight such flushes the state stops compiling. A loop whose
  code alone exceeds the limit is left to the interpreter.
  `L.Close()` on the state returned by `NewState` unmaps the code (threads
  that are still used afterwards run in the interpreter); the memory of a
  state that is dropped without `Close` is unmapped by a finalizer.
- **Compilation**: a loop is compiled at most six times (recompilation
  happens when type guards keep failing); regions are limited to 3000
  basic blocks. A compiler failure of any kind, including an internal
  panic, only blacklists the loop.
- **Native run time**: native code returns to Go at least every
  `SafePointInterval` loop iterations (at most 2^24, whatever is
  configured). At these points context cancellation and deadlines
  (`L.SetContext`) take effect.
- **Nesting**: at most 64 nested native activations per thread; deeper
  nesting runs in the interpreter.

## Safety model and limitations

The rules native code follows to coexist with the Go runtime are listed in
[architecture.md](architecture.md#runtime-safety-contract). What has and has
not been verified:

- Verified by tests on darwin/amd64, linux/amd64 and linux/arm64 (under
  QEMU user emulation): generated code against a reference interpreter of
  the IR, the upstream test-suite and the Lua 5.5 conformance scripts with
  the JIT at threshold 1, randomly generated programs (interpreter versus
  JIT), concurrent states under garbage collection pressure, the race
  detector, stack growth around native calls, cancellation, code cache
  limits. Go 1.23, 1.25 and 1.27 were used.
- **Not verified**: darwin/arm64 (no hardware was available; the code is
  the same as for linux/arm64 apart from page size and cache flushing) and
  real arm64 hardware in general. QEMU does not model instruction cache
  coherency, so the explicit cache flush is exercised but its necessity is
  not.
- The design depends on properties of the Go runtime that hold for all
  current releases but are not part of the language specification: heap
  objects do not move, interface values and slices have their documented
  two- and three-word layouts (checked at start-up; the JIT disables itself
  if the check fails), and a goroutine executing code outside Go's text
  segment is not asynchronously preempted. A Go release that changes one of
  these would require an update of this package.
- While native code runs, a stop-the-world phase of the garbage collector
  waits for the next safe point (microseconds with the default interval,
  longer if the loop body is slow and the interval is raised).
- CPU profiles attribute native code to "external code"; Go stack traces
  taken while native code runs do not show Lua frames.
- Debugger access to a frame that runs native code: `debug.setlocal` /
  `L.SetLocal` take effect (the frame continues in the interpreter), but
  `debug.getlocal` / `L.GetLocal` may show an outdated value for a local
  that is not read again later, because native code only writes back the
  variables that are still live.
- Compiled code is per state. A pool of states compiles hot loops once per
  state.

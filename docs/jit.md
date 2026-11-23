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
- numeric `for` loops (integer and float, with a constant or a variable
  step), `while`, `repeat`, `break`, `goto` loops, nested loops;
- reads and writes of array elements with integer keys on tables whose
  array part holds only integers, only floats or only booleans, including
  appends that fit the capacity; reads of numbers from mixed arrays; the
  length operator on such tables;
- reads and writes of **number fields** (`p.x = p.x + p.y`): the position
  of the field is cached per access and guarded by the identity of the key;
- reads of **tables, strings and functions** from array elements and
  fields (`objs[i].pos.x`, `for _, o in ipairs(objs)`): the register
  refers to the value where it is stored instead of copying it, so chains
  of field accesses, arrays of objects and linked structures need no
  interpreter. `ipairs` over such arrays advances natively as well;
- the length of strings and of arrays (`#s`, `#t`);
- **integer indexes in the Lua 5.1 profile**, where every number is a
  float: the index of a numeric `for` loop is also kept as a machine
  integer, and so are sums, differences and products of such values and
  small constants, `math.floor(i / c)`, `i % n` and lengths. Using them
  as table keys or as operands of `%` (`t[i + 1]`, `t[2 * i]`,
  `t[n - i + 1]`, `t[math.floor((lo + hi) / 2)]`, `t[i % n + 1]`) needs
  no conversion and no check per use. This applies to loops whose start,
  limit and step are integers below 2^31 in magnitude (2^52 with less
  room for index arithmetic); other loops use the general float code;
- reads of **global variables**, and writes of a number to a global that
  holds a number (`count = count + 1`): an existing global is a field of
  the environment table and is accessed like one. A global that does not
  exist is looked up by the interpreter, which may consult a metatable;
- reads of **upvalues**: numbers are unboxed, functions and tables are
  constants, any other value (a string, a boolean, nil) is used where it
  is stored. A table
  found in an upvalue or in a global variable (a module-level `local t`
  used inside functions, a global `config`) is indexed natively like a
  table in a local variable: array elements, fields, length, methods and
  `ipairs` all work on it;
- **calls of small Lua functions**: a callee made of simple instructions
  (arithmetic, comparisons, field and array access, upvalue reads, further
  such calls, tail calls) and forward branches (`if`, `and`/`or`, several
  `return` statements) is translated in place of the call, up to three
  levels deep. No frame is created unless native code is left inside the
  callee. The paths through the callee must agree on the kind of each
  result (a function that returns a number on one path and `nil` on
  another is called through the interpreter);
- **method calls** (`obj:name(...)`) on tables: the method is found in
  the object itself or through the `__index` tables of its metatable
  (classes, up to four levels of inheritance) and then inlined like any
  other small function. Objects with more than eight string keys, or
  whose `__index` is a function, are looked up by the interpreter;
- generic `for` loops: the loop body is compiled; `ipairs` over a table
  without metatable advances natively, every other iterator (`pairs`,
  custom iterators) is called through the interpreter once per iteration;
- truth tests and comparisons with `nil` on arbitrary values;
- **string equality** (`==`, `~=`): strings of different length differ,
  strings that share their bytes are equal, and the bytes of any other
  pair are compared in native code (up to 64 bytes; longer ones by the
  interpreter);
- **string methods**: `s:name(...)` finds the function in the `string`
  table without the interpreter; `s:byte(i)` / `string.byte(s, i)` with a
  position inside the string and `s:len()` / `string.len(s)` are
  translated in place, other string functions are called through the
  interpreter;
- `math.sqrt`, `math.floor`, `math.ceil`, `math.abs`, `math.max` and
  `math.min` (up to four numbers of one kind), `type` and `tonumber` of a
  number, whether they are called through the unmodified library tables
  or through a local variable or upvalue (`local floor = math.floor`).
  The result of `type` is a constant for the compiler, so
  `type(v) == "number"` costs a type check of `v` and no string
  comparison; comparisons of two known strings are decided when the loop
  is compiled.

Executed by the interpreter on behalf of native code (a *callout*; correct
but with a fixed overhead of a few dozen nanoseconds each). Before a
callout only the registers its instruction uses are written back; the
other numbers of the loop stay in machine registers, so a loop with
callouts allocates less than the interpreter does for the same code:

- string operations other than length, equality and `byte`; ordering
  comparisons of strings; stores of strings, tables or
  functions into tables, writes to upvalues, table creation, closures,
  metamethods;
- calls of Go functions, and calls of Lua functions that are not inlined
  (those with loops, varargs, more than 40 instructions or instructions
  from this list):
  they run in a nested interpreter loop and may enter native code
  themselves.

Not compiled (the loop stays in the interpreter):

- vararg expressions, tail calls and returns inside the loop body end the
  compiled region;
- loops that mostly consist of callouts – the JIT measures this at run time
  and hands such loops back to the interpreter;
- functions without loops. There is no native call/return, so recursion
  (`fib`) is not accelerated.

## Resource bounds

- **Code memory**: each state maps at most `MaxCodeBytes` of executable
  memory (page granular; a unit occupies at least one page). When the limit
  is reached all units of the state are discarded and compilation starts
  over; after eight such flushes the state stops compiling. A loop whose
  code alone exceeds the limit is left to the interpreter.
  `L.Close()` on the state returned by `NewState` unmaps the code (threads
  that are still used afterwards run in the interpreter); the memory of a
  state that is dropped without `Close` is unmapped by a finalizer.
- **Compilation**: a loop is compiled at most six times; regions are
  limited to 3000 basic blocks. Recompilation happens when a guard keeps
  failing. A guard that fails rarely (less than once per 32 iterations)
  is tolerated. One that fails often records what it met, so that the
  next translation fits better; if the instruction it belongs to makes a
  unit fail again, or meets values of several kinds, or has nothing to
  learn from (a table key that is not an integer), that one instruction
  is executed by the interpreter from then on and the rest of the loop
  stays native. A compiler failure of any kind, including an internal
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

- Verified by tests on linux/amd64, linux/arm64, darwin/arm64 (Apple
  Silicon) and darwin/amd64: generated code against a reference interpreter of
  the IR, the upstream test-suite and the Lua 5.5 conformance scripts with
  the JIT at threshold 1, randomly generated programs (interpreter versus
  JIT), concurrent states under garbage collection pressure, the race
  detector, stack growth around native calls, cancellation, code cache
  limits. Go 1.23, 1.25 and 1.27 were used.
- The arm64 platforms are tested in CI on GitHub-hosted runners only (no
  arm64 development machine was available), which covers one CPU model per
  operating system. On macOS the instruction cache is flushed with fixed
  64-byte lines because user space cannot read the cache type register
  there. Benchmarks were only run on amd64.
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
  `L.SetLocal` take effect (the frame continues in the interpreter), and
  `debug.getlocal` / `L.GetLocal` first make the registers of the frame
  complete. They may still show an outdated value for a local that is
  not read again later, because native code only writes back the
  variables that are still live.
- Compiled code is per state. A pool of states compiles hot loops once per
  state.

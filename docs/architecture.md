# Architecture

This document describes how the runtime is put together and which
invariants its parts rely on. It is written for people who want to change
the runtime or need to judge its safety.

```
source ──parse──▶ AST ──compile──▶ bytecode (FunctionProto) ──▶ interpreter (vm.go)
                                          │                        │  hot loop
                                          ▼                        ▼
                                 bytecode analysis ──▶ JIT front end ──▶ SSA IR
                                 (CFG, liveness)        (type speculation)   │
                                                                             ▼
                                              optimizer ─▶ register allocation ─▶ machine code
                                                                             │
                                             interpreter ◀── deopt / callout ┘ (executable memory)
```

## Packages

| Path | Contents |
|---|---|
| `.` (package `lua`) | values, tables, state, bytecode compiler, interpreter, standard libraries, JIT front end and driver |
| `ast`, `parse` | AST and the hand-written lexer / recursive descent parser for both language profiles |
| `pm` | Lua pattern matching |
| `internal/jit` | SSA IR, optimizer, linear scan register allocator, code emitter, amd64 and arm64 macro assemblers |
| `internal/jit/asm/amd64`, `internal/jit/asm/arm64` | machine code encoders, verified against the Go assembler |
| `internal/jit/codecache` | executable memory (W^X) and the assembly trampolines that enter native code |
| `cmd/glua` | command line interpreter |
| `benchmarks` | separate module with the benchmark kernels |
| `_glua-tests`, `_lua5.1-tests` | upstream test scripts (Lua 5.1 profile) |
| `_lua55-tests` | Lua 5.5 conformance scripts, checked against the reference interpreter |

`vm.go` and `state.go` are generated from `_vm.go` and `_state.go` by
`_tools/go-inline` (`make generate`); edit the underscore files.

## Language profiles

A state runs one of two profiles (`Options.LanguageVersion`):

- **Lua51** (default): GopherLua semantics. All numbers are `LNumber`
  (float64). Globals are resolved through the function environment
  (`OP_GETGLOBAL`).
- **Lua55**: numbers are `LInteger` (int64) or `LNumber` (float64) with the
  Lua 5.3+ conversion rules. Globals are resolved through the `_ENV` upvalue
  (`OP_GETENV`/`OP_SETENV`). The parser accepts the Lua 5.5 grammar, the
  compiler implements attributes (`<const>`, `<close>`), `global`
  declarations and named vararg tables, and the standard libraries are the
  Lua 5.5 ones.

The profile is fixed per state (`LState.lang55`) and recorded in every
`FunctionProto` (`Version`). Both profiles share one bytecode format and one
interpreter; profile specific behaviour is selected where it differs
(number formatting, metamethod rules, error messages, library sets).

### Numbers

`LNumber` is unchanged from GopherLua. `LInteger` is a new `LValue` whose
`Type()` is also `LTNumber`. Arithmetic lives in `vmnum.go`
(`numberArith55`, comparison helpers in `number.go`): integer operations
wrap, `/` and `^` always produce floats, `//` and `%` floor, comparisons
between integers and floats are exact. Boxing into the `LValue` interface
uses the bulk allocator of GopherLua (`alloc.go`), extended to integers.

### Tables

`LTable` has an array part, a part for string keys and a generic map with
an insertion ordered key list for all other keys. Both parts are allocated
on first use. Compared with GopherLua:

- **String keys** are stored as one insertion ordered slice of key/value
  entries (`fields`). Tables with up to eight string keys are searched
  linearly; larger ones get a compact open-addressing index of entry
  positions (`fieldIndex`). Removed entries keep their position with a nil
  value, so positions are stable. This replaces two Go maps and one boxed
  key per entry and is what makes creating many small tables cheap.


- **Unboxed array parts.** When enabled for a table (it is for states with
  the JIT on), an array part that only holds integers or only floats is
  stored as `[]int64` or `[]float64` (`akind`). Storing any other value
  converts it back to `[]LValue`. This representation contains no pointers,
  so the garbage collector does not scan it and JIT code can read and write
  elements directly.
- **A version counter** that is bumped when a string-keyed entry holding a
  function or table is replaced, once the table is "watched". JIT code uses
  it to treat library functions (`math.floor`) as guarded constants.

## Interpreter

The interpreter is GopherLua's register machine: one handler function per
opcode, dispatched through `jumpTable`. New opcodes cover integer division,
bitwise operators, `_ENV` access, to-be-closed variables and vararg tables.
Numeric `for` loops check their bounds in `OP_FORPREP` and use an overflow
safe test for integer loops.

Errors are Go panics carrying `*ApiError`, caught by `LState.PCall`.
Coroutines are separate `LState` values run by nested interpreter loops on
the same goroutine. Because of that a coroutine cannot yield while Go code
(a metamethod call, `pcall`, an iterator call, a library callback) is on
the stack between it and its resume point; this is detected
(`LState.nny`) and reported as an error.

## JIT compiler

### What is compiled

The unit of compilation is a **loop**. The interpreter counts loop
back-edges (`OP_FORLOOP`, backward `OP_JMP`) per state. When a loop reaches
the threshold, the JIT compiles the natural loop of that header – including
nested loops – for the types the registers hold *at that moment*
(on-stack replacement at the loop header). Control leaving the loop returns
to the interpreter.

### Front end (`jit_analysis.go`, `jit_frontend.go`)

1. Bytecode analysis (cached per prototype, shareable): instruction
   effects, basic blocks, register liveness, registers captured by closures.
2. Translation to SSA. The front end tracks, per Lua register, how native
   code holds it:
   - *home*: the boxed value in the registry slot (always valid for the
     interpreter),
   - *unboxed int / float / bool* in an SSA value, with a *dirty* flag when
     the registry slot is stale,
   - *nil*, a pending *boxed copy* of another slot, or a pending *boxed
     constant*.
3. Speculation is guarded: unboxing a register checks its dynamic type;
   table accesses check the table type, the array representation and the
   bounds; library functions are assumed unchanged as long as the version
   counters of the tables they were found in are unchanged; the step of the
   entered `for` loop is assumed constant.
4. Joins use phis for registers that have the same unboxed kind on all
   incoming edges. Other registers are written back on the edges and stay
   boxed. Translation is repeated until these decisions are stable.

Instructions without a native translation are executed by the interpreter
through a **callout**: native code returns to Go, the driver writes the
dirty registers back, runs the ordinary instruction handler, and resumes
native code. Calls of Lua functions are callouts too (the callee runs in a
nested interpreter loop and may itself enter native code).

### Middle and back end (`internal/jit`)

- IR: typed SSA (64-bit integers and floats), explicit guards, callouts and
  safe points, each carrying a snapshot of the values Go needs at that exit.
- Optimizer: unreachable code removal, constant folding, algebraic
  simplification and strength reduction (`x*2^k`, `x//2^k`, `x%2^k`,
  `x/2^k`), common subexpression elimination along the dominator tree, phi
  simplification, dead code elimination.
- Register allocation: linear scan over live intervals with spill slots in
  the context frame; phis are resolved by parallel moves on (split) edges.
- Code emission through a small macro assembler interface with an amd64 and
  an arm64 implementation. Compare-and-branch fusion and immediate operands
  are selected at this level.

### Runtime (`jit_driver.go`, `internal/jit/codecache`)

Native code is entered through an assembly trampoline with one argument,
the *context frame*: a `[]uint64` owned by the thread that holds the exit
code, the resume address, the address of the Lua register window, the fuel
counter, the register save areas and the spill slots.

Every exit stores an exit id, dumps the allocatable registers into the save
area and returns to Go. The driver then:

- **deoptimization** (failed guard, loop exit, unsupported instruction):
  writes the registers described by the snapshot back to the registry, sets
  the bytecode pc and returns to the interpreter, which re-executes the
  instruction;
- **callout**: writes back, runs the instruction handler, resumes;
- **safe point** (fuel exhausted): checks the context for cancellation and
  resumes.

Failed type guards record the observed type; a unit whose guards keep
failing is discarded and the loop is recompiled with that feedback, up to a
limit, after which the loop is left to the interpreter. Units that spend
their time in callouts are discarded as well.

### Runtime safety contract

Native code is not Go code, so it must not need anything from the Go
runtime while it runs. The backends guarantee:

1. **No stack use.** Native code never moves the stack pointer and never
   touches stack memory. It runs inside the fixed frame of a `NOSPLIT`
   assembly function, so stack growth and stack scanning see an ordinary Go
   stack.
2. **No calls into Go.** Allocation, table growth, metamethods, errors and
   calls are done by Go code after an exit.
3. **No pointer writes.** Native code only writes numbers into pointer-free
   memory (the context frame, `[]int64`/`[]float64` array parts, a slice
   length word). It never stores a pointer into the Go heap, so no write
   barrier is needed. Boxed values are never copied by native code; they
   stay in their registry slot and moves are replayed by Go.
4. **No hidden roots.** Every Go object native code reads is reachable from
   GC visible memory for the whole native run (the registry, tables
   referenced from it, and the unit's keep-alive list for tables whose
   version word is read through an absolute address). Addresses derived
   from Go objects are not kept across callouts. The collector does not
   move heap objects.
5. **Reserved registers.** The stack pointer, the frame pointer, the `g`
   register (R14 / R28), the arm64 platform register R18 and the arm64 link
   register are never modified.
6. **Bounded native time.** A goroutine in native code cannot be preempted
   asynchronously; the runtime's signal handler sees an unknown program
   counter and leaves the goroutine alone. Loops therefore decrement a fuel
   counter on every back-edge and return to Go when it reaches zero
   (default: every 65536 iterations). This bounds how long a
   stop-the-world phase can be delayed by native code.
7. **W^X.** Code is written to a private read/write mapping, then switched
   to read/execute. It is never modified afterwards; discarding a unit
   unmaps it. On arm64 the instruction cache is flushed explicitly.

Go code keeps the interpreter state authoritative: at every callout and
every exit the registry holds the complete, boxed state of the frame, so an
error (panic) raised during a callout unwinds like in the interpreter, and
`PCall` drops the abandoned native activations.

### Concurrency

A `LState` and everything reachable from it (including its coroutines and
its JIT state) must be used by one goroutine at a time. Independent states
run concurrently without shared locks. `FunctionProto` values are immutable
after compilation and can be shared between states; their bytecode analysis
is computed once under `sync.Once`. Compiled native code belongs to the
state that produced it.

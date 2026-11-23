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
   counters of the tables they were found in are unchanged, or, when they
   are called through a register, as long as the register holds the same
   function (`jit_intrinsic.go`); the step of the entered `for` loop is
   assumed constant.
4. Joins use phis for registers that have the same unboxed kind on all
   incoming edges. Other registers are written back on the edges and stay
   boxed. Translation is repeated until these decisions are stable.

Instructions without a native translation are executed by the interpreter
through a **callout**: native code returns to Go, the driver writes the
dirty registers back, runs the ordinary instruction handler, and resumes
native code. Calls of Lua functions that are not inlined are callouts too
(the callee runs in a nested interpreter loop and may itself enter native
code).

Several kinds of speculation go beyond registers (`jit_frontend.go`,
`jit_inline.go`):

- **Number fields.** A string-keyed table entry stores numbers unboxed
  next to a cached boxed value (`tableField`). `p.x` compiles to a guarded
  load from the entry at the position the field had when the code was
  compiled: the entry must exist, carry that key (compared by the address
  of its bytes; string constants are interned so that every function uses
  the same copy) and hold a number. A store writes the number and marks
  the cached box stale; the interpreter rebuilds it on its next read.
  Sites that see several table layouts are left to the interpreter.
- **References into tables.** A table, string or function read from an
  array element or a field is not copied into the register (that would
  be a pointer write). The register state records the address of the
  value inside the table; further accesses load the type and data words
  from there. The address is valid until Go code runs again, so every
  callout and exit first copies the referenced values into their
  registers, reading them before anything is written. At the header of a
  loop that replaces a boxed variable (`node = node.next`) the variable
  is a reference whose address is a phi over the places the value can
  be in, including the variable's own home slot.
- **Integer twins (Lua 5.1 profile, `jit_narrow.go`).** All numbers of
  the profile are floats, but a table key has to be an integer: without
  further knowledge every `t[i]` converts the key and checks that nothing
  was lost. The front end therefore gives float values that are known to
  be integers of a limited magnitude a second SSA value, their *twin*,
  computed with integer arithmetic: the control values of a numeric `for`
  loop (checked once when the loop is entered: integral start and step,
  all three below 2^31, or 2^52 if they are larger), phis of values with
  twins, sums, differences and products whose result is certainly below
  2^53 (so the float operation is exact), `math.floor` of a quotient by a
  constant, remainders and lengths. A twin is recorded for the SSA value,
  not for a register, and is always defined together with its float or
  before it, so it is valid wherever the float is. Table accesses and the
  integer path of `%` use the twin if there is one; twins nobody uses are
  dead code. The index of a loop keeps its bound because the loop only
  continues while the index has not passed the limit. If the values of a
  loop turn out not to be small integers, the failed check turns
  narrowing off for that loop.
- **Upvalues and globals.** A closed upvalue is read from its cell, an
  open one from the register of the waiting function it belongs to;
  numbers are unboxed, functions and tables become constants guarded by
  identity. A global that holds a function or a table is a constant as
  long as the version counter of the environment table is unchanged; any
  other global that exists is read, and a number global written, like a
  field of the environment table (see number fields). An
  open upvalue of an inlined callee that refers to a register of the
  running activation is that register. A constant table is a location
  like a home slot or a reference: its type and data words are known at
  compile time, so the type check of a table access folds away and the
  access itself uses the same code as for a table in a register.
- **Methods.** `obj:name()` resolves at compile time to the function the
  object's class provides. The code checks that the object still has
  exactly the string keys it had (so the name is not among them) and the
  same metatable; the metatable and the class tables behind it are
  constants whose version counter changes when a function or table entry
  is replaced or a key is added.
- **Inlined calls.** The callee's instructions are translated in place
  with its registers relocated to the slots behind the function value,
  where its frame would be. Exits inside the callee name the chain of
  inlined calls; the driver then pushes the callee frames (a tail call
  replaces its caller) and the interpreter continues inside the callee, so
  errors and tracebacks are unchanged. Only short functions without loops
  whose instructions need no callout are inlined; their forward branches
  are joined again with phis for registers that are unboxed on all paths.

### Middle and back end (`internal/jit`)

- IR: typed SSA (64-bit integers and floats), explicit guards, callouts and
  safe points, each carrying a snapshot of the values Go needs at that exit.
- Optimizer: unreachable code removal, constant folding, algebraic
  simplification and strength reduction (`x*2^k`, `x//2^k`, `x%2^k`,
  `x/2^k`), common subexpression elimination along the dominator tree,
  redundant load and guard elimination, phi simplification, dead code
  elimination.
- Memory is described to the optimizer by classes, not by an alias
  analysis. The front end marks every load and store with what it touches:
  memory that compiled code never writes (table headers, metatables, the
  data pointers and capacities of slices, closures, boxed values), the length word of an unboxed array, an
  unboxed array element, or the number and kind words of a table field.
  Inside a block a load is replaced by an earlier load of the same address
  until something could have changed that word: a store of the same class
  (other than to a different word of the same object), an unclassified
  store, or a callout or safe point, after which nothing is assumed. A
  stored number is forwarded to a later load of the same word, and a guard
  on a condition that an earlier guard of the block established is dropped.
  This removes the repeated metatable, kind and bounds checks of code such
  as `p.x = p.x + p.y` or `t[i] = t[i] + t[i-1]`.
- Register allocation: linear scan over live intervals with spill slots in
  the context frame; phis are resolved by parallel moves on (split) edges.
- Code emission through a small macro assembler interface with an amd64 and
  an arm64 implementation. Compare-and-branch fusion and immediate operands
  are selected at this level.

### Runtime (`jit_driver.go`, `internal/jit/codecache`)

Native code is entered through an assembly trampoline with one argument,
the *context frame*: a `[]uint64` owned by the thread that holds the exit
code, the resume address, the address of the Lua register window, the fuel
counter, the address of the running closure, the registry index of its
first register, the address of the thread's registry, the register save
areas and the spill slots.

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
3. **No pointer writes.** Native code only writes numbers into words that
   hold no pointer (the context frame, `[]int64`/`[]float64` array parts,
   a slice length word, the number and kind words of a table field). It
   never stores a pointer into the Go heap, so no write barrier is needed.
   Boxed values are never copied by native code; they stay where they
   are (a registry slot, a table) and moves are replayed by Go.
4. **No hidden roots.** Every Go object native code reads is reachable from
   GC visible memory for the whole native run: the registry and what it
   refers to, and the unit's keep-alive lists for everything addressed
   through a constant (tables whose version word is read, inlined callees
   and their upvalue cells, key strings). Addresses derived from Go
   objects are not kept across callouts. The collector does not move heap
   objects.
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

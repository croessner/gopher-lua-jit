# Compatibility report

This report distinguishes what is **implemented and tested**, **partially
implemented**, and **not implemented**. "Oracle" means the reference
interpreter Lua 5.5.1 (`lua5.5`), which the conformance scripts are also
run against.

## 1. GopherLua Go API

Baseline: GopherLua v1.1.2 (commit `75f4976`). All of its tests pass
unchanged (`go test .` runs the upstream Go tests and the upstream Lua
scripts in `_glua-tests` and `_lua5.1-tests`), with and without the JIT.

| API | Status |
|---|---|
| `LState`, `LValue`, `LTable`, `LFunction`, `LUserData`, `LNumber`, `LString`, `LBool`, `LNil`, `LGFunction`, `LChannel` | unchanged |
| `NewState`, `Options` (existing fields), `Close` | unchanged; `Options` gained `LanguageVersion` and `JIT` |
| `DoString`, `DoFile`, `Load`, `LoadString`, `LoadFile` | unchanged |
| `SetGlobal`, `GetGlobal`, `SetField`, `GetField`, `SetTable`, `GetTable`, `RawGet*`, `RawSet*` | unchanged |
| `NewFunction`, `NewClosure`, `NewTypeMetatable`, `SetMetatable`, `GetMetatable`, `NewUserData` | unchanged |
| `Call`, `PCall`, `CallByParam`, `GPCall` | unchanged |
| `PreloadModule`, `Register*`, `OpenLibs`, `SetFuncs` | unchanged |
| `SetContext`, `RemoveContext`, `Context` | unchanged; honored by native code at safe points |
| `Check*`, `Opt*`, `To*`, `ArgError`, `TypeError` | unchanged in the Lua 5.1 profile; accept integers in the Lua 5.5 profile |
| `NewThread`, `Resume`, `Yield`, `Status` | unchanged |
| `Compile`, `FunctionProto`, `NewFunctionFromProto` | unchanged; prototypes gained `Version` and `EnvUpvalue` |
| package `parse`: `Parse`, `Dump`, `Error`, `Scanner`, `Lexer`, `TokenName`, token constants | kept. The goyacc internals (`yyParse`, `yySymType`, `yyLex`, …) are gone |
| package `ast` | kept; new nodes and fields for Lua 5.5 syntax |

Behavioural differences in the default profile are limited to the bug
fixes listed in [migration.md](migration.md).

Not verified: third-party libraries were not run as part of this work;
compatibility is argued from the unchanged API and the upstream tests.

## 2. Lua 5.5 language (profile `lua.Lua55`)

Tested by `_lua55-tests/core` (57 scripts, about 4000 assertions plus a
data-driven operator matrix of about 43000 checks), each of which also
passes on the oracle.

### Implemented and tested

- Integer and float subtypes: literals (decimal, hexadecimal, hex floats),
  wrap-around integer arithmetic, `//`, `%`, `/`, `^`, bitwise operators,
  conversions, exact integer/float comparison, string coercions, number
  formatting, table key normalization.
- Lexical conventions: escapes (`\x`, `\z`, `\u{}`, decimal), long
  strings/comments, all operators.
- Statements: `goto` and labels with the Lua 5.4 visibility rules, integer
  and float `for` loops (overflow safe, read-only loop variable), generic
  `for` with four control values (closing value), `break`, `repeat`
  scoping.
- `local` attributes `<const>` and `<close>` (closing on normal exit,
  `break`, `goto`, `return` and errors, with the error object).
- `global` declarations (`global x`, `global <const> *`,
  `global function`), including the compile time checks.
- `_ENV` as upvalue, local and parameter.
- Functions: varargs, named vararg tables (`...name`), multiple assignment
  and results, tail calls, closures with per-iteration loop variables.
- Metamethods: `__index`, `__newindex`, `__call`, arithmetic and bitwise
  events, `__concat`, `__len`, `__eq` (Lua 5.4 rules), `__lt`, `__le`
  (no `__lt` fallback), `__close`, `__tostring`, `__name`, `__metatable`,
  `__pairs`.
- Error handling: `error` with any value, levels, `pcall`, `xpcall` with
  arguments, errors in message handlers.
- Coroutines: `create`, `resume`, `yield`, `wrap`, `status`, `running`,
  `isyieldable`, `close`.

### Standard library

| Library | Status | Tests |
|---|---|---|
| base (`assert` … `xpcall`, `load` with mode/env, `warn`, `rawlen`, …) | implemented | `_lua55-tests/base` |
| `coroutine` | implemented, see yield limitation below | `_lua55-tests/base` |
| `package` (`searchers`, `searchpath`, `preload`, `require` with loader data) | implemented; C loaders are stubs | `_lua55-tests/base` |
| `string` incl. `pack`/`unpack`/`packsize`, `format` (`%a`, `%q`, …), 5.4 pattern rules | implemented; `string.dump` raises an error | `_lua55-tests/strings` (about 1200 generated checks; differential fuzzing against the oracle was run during development) |
| `utf8` | implemented | `_lua55-tests/strings` |
| `math` incl. `tointeger`, `type`, `ult`, xoshiro256** `random` with the oracle's sequences | implemented | `_lua55-tests/mtio` |
| `table` incl. `move`, `pack`, `unpack`, `create`, the reference sort | implemented | `_lua55-tests/mtio` |
| `os` | implemented | `_lua55-tests/mtio` |
| `io` | implemented | `_lua55-tests/mtio` |
| `debug` | partial: `getinfo`, `traceback`, `getlocal`, `setlocal`, upvalue functions, metatables; hooks are recorded but never called | `_lua55-tests/base` |

Scripts named `*_gopher.lua` assert the intentional deviations of each
library.

### Partially implemented or deviating

These are covered by `_lua55-tests/core-pending` (10 scripts that pass on
the oracle and are expected to fail here; `go test` only checks them
against the oracle).

- **Yield across `pcall`, `xpcall`, metamethods, iterators of generic
  `for`, `__close` handlers and library callbacks is not supported.** It
  raises `attempt to yield across a C-call boundary`. (Lua 5.1 has the same
  restriction; Lua 5.2 and later allow it.) Yielding from Lua functions
  called by the coroutine body, however deeply nested, works.
- **Error messages carry no variable information.** The oracle says
  `attempt to index a nil value (local 'x')`; this runtime names the key
  instead (`(field 'y')`) for index errors and omits the suffix for
  arithmetic, call and concatenation errors. Some texts differ
  (`attempt to perform arithmetic on a string value` instead of
  `attempt to add a 'string' with a 'number'`).
- **Callable tables as metamethod handlers** (`__add = callableTable`),
  `__call` chains (a table whose `__call` is itself a callable table) and
  a non-callable `__len` are not handled like the oracle.
- **String arithmetic** is done by the VM, not by metamethods of the string
  metatable; `getmetatable("").__add` is `nil`.
- **`^`** uses Go's `math.Pow`; results can differ from C `pow` in the last
  bit (`10^64` prints `1.0000000000000002e+64`). The same holds for other
  transcendental functions of `math`.
- **Limits**: a function can use about 200 registers (the oracle: 255), so
  very long argument lists fail to compile; more than 255 upvalues are not
  rejected.

### Not implemented

- Garbage collector control and semantics: `__gc` finalizers are never
  called, weak tables (`__mode`) are ordinary tables, `collectgarbage`
  only maps `collect`/`step` to Go's collector and reports its options.
- Binary chunks: `string.dump`, `load` of precompiled code.
- C libraries (`package.loadlib`, C searchers).
- Debug hooks (`debug.sethook` records, nothing is called), userdata user
  values.

## 3. Lua 5.1 profile

GopherLua's Lua 5.1 implementation with its documented differences from
PUC-Rio Lua 5.1 (see the original README), plus the fixes in
[migration.md](migration.md). `goto` is accepted as in upstream.

## 4. JIT

See [jit.md](jit.md). Summary of verification:

| Check | darwin/amd64 | linux/amd64 | linux/arm64 (QEMU) | darwin/arm64 |
|---|---|---|---|---|
| encoder golden tests (vs. Go assembler) | pass | pass | pass | host independent |
| native execution under GC pressure, `-race` | pass | pass | pass | not run |
| IR pipeline vs. reference interpreter | pass | pass | pass | not run |
| upstream suite and conformance scripts with JIT | pass | pass | pass | not run |
| random differential programs, fuzzing | pass | pass | pass (short mode) | not run |

## 5. How to reproduce

```bash
go test -count=1 ./...          # everything, including oracle checks if lua5.5 is installed
go test -count=1 -race -short ./...
make test-linux-amd64 test-linux-arm64
for f in _lua55-tests/core-pending/*.lua; do lua5.5 "$f"; go run ./cmd/glua -lua 5.5 "$f"; done
```

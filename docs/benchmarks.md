# Benchmarks

## Methodology

- **Kernels.** `benchmarks/scripts/*.lua` are small programs written in the
  common subset of Lua 5.1 and 5.5, so the *same source* runs on upstream
  GopherLua, on both profiles of this runtime, on PUC-Rio Lua 5.5 and on
  LuaJIT. Each returns a function `run(n)`.
- **Go benchmarks.** `benchmarks/bench_test.go` only uses the GopherLua API.
  The implementation under test is selected by the module file:
  `go.mod` replaces `github.com/yuin/gopher-lua` with this repository,
  `go.upstream.mod` requires the upstream release v1.1.2. A state is created,
  the kernel is loaded and called twice to warm up (this is where the JIT
  compiles), then `run(n)` is timed with `testing.B`.
  Configurations: `upstream` (GopherLua v1.1.2), `interp 5.1` / `interp 5.5`
  (this runtime, interpreter only), `JIT 5.1` / `JIT 5.5` (this runtime with
  `JITOptions{Enabled: true}`, default threshold). In the Lua 5.5
  configurations the problem size is passed as an integer.
- **Stand-alone interpreters.** `benchmarks/harness.lua` runs the same
  kernels with the same `n` on `lua5.5` and `luajit` and reports the best of
  five timed calls after one warm-up call. These numbers come from a
  different harness (`os.clock`, no Go call overhead) and are meant as an
  orientation, not as a like-for-like comparison. In `go_callback` the
  stand-alone interpreters call a Lua function instead of a Go function.
- **Other benchmarks.** `Cold` creates a fresh state per iteration and runs
  a kernel once with a tenth of the problem size (state creation, parsing,
  compilation and, for the JIT, native code generation are all included).
  `GoToLua` calls a two-argument Lua function from Go. `NewState` creates
  and closes a state with all libraries. `Pool` takes a prepared state from
  a `sync.Pool` on all CPUs and calls a function that loops 200 times.
- **Reproduce.**

  ```bash
  cd benchmarks
  go test -run xxx -bench . -benchtime=500ms -count=3 -benchmem . > results/fork.txt
  GOFLAGS=-mod=mod go test -modfile=go.upstream.mod -tags upstream -run xxx -bench . -benchtime=500ms -count=3 -benchmem . > results/upstream.txt
  lua5.5 harness.lua > results/lua55.txt
  luajit harness.lua > results/luajit.txt
  python3 summarize.py > results/summary.md
  ```

  The raw outputs of the run reported below are in `benchmarks/results/`.

## Environment of the reported run

| | |
|---|---|
| CPU | Intel Core i9-9880H @ 2.30 GHz (8 cores / 16 threads), laptop |
| Memory | 32 GB |
| OS | macOS 26 (Darwin 25.6.0), amd64 |
| Go | 1.27.4 |
| Upstream | github.com/yuin/gopher-lua v1.1.2 |
| Reference interpreters | Lua 5.5.1, LuaJIT 2.1 (rolling release build) |
| Settings | `-benchtime=500ms -count=3`, median of the three runs |

The machine is a laptop and was not otherwise isolated; run-to-run variation
of individual results was in the order of 5 to 10 percent. Differences
smaller than that should not be read as real.

## Results

### Kernels: time per call in milliseconds (median of 3 runs)

| kernel | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | lua5.5 | luajit |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 310.86 | 291.63 | 19.28 | 95.22 | 16.46 | 42.65 | 4.41 |
| arith_float | 86.29 | 78.40 | 2.85 | 87.08 | 3.20 | 15.89 | 2.97 |
| loop_nested | 35.05 | 31.26 | 1.38 | 25.38 | 1.64 | 5.62 | 0.99 |
| calls | 33.06 | 28.80 | 30.30 | 28.83 | 30.17 | 6.96 | 0.29 |
| fib | 13.88 | 13.44 | 13.08 | 13.55 | 12.85 | 3.30 | 0.48 |
| table_array | 61.76 | 53.59 | 5.69 | 53.09 | 4.86 | 8.81 | 2.79 |
| table_hash | 88.28 | 89.71 | 89.52 | 87.31 | 88.01 | 11.94 | 0.58 |
| strings | 27.02 | 27.27 | 27.38 | 14.84 | 13.27 | 17.23 | 3.69 |
| metamethods | 104.84 | 108.65 | 118.87 | 110.22 | 119.99 | 41.24 | 0.12 |
| closures | 42.41 | 40.89 | 48.31 | 40.08 | 43.95 | 59.49 | 17.89 |
| mandelbrot | 67.49 | 54.58 | 0.86 | 56.02 | 0.85 | 12.43 | 0.85 |
| sieve | 61.04 | 59.14 | 70.42 | 54.58 | 68.53 | 7.24 | 3.22 |
| math_calls | 138.69 | 133.94 | 1.37 | 143.00 | 1.89 | 34.78 | 1.36 |
| go_callback | 39.36 | 36.54 | 40.17 | 36.55 | 38.85 | 8.06 | 0.28 |

### Kernels: speedup relative to upstream GopherLua (higher is better)

| kernel | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|
| arith_int | 1.07x | 16.13x | 3.26x | 18.88x |
| arith_float | 1.10x | 30.25x | 0.99x | 26.97x |
| loop_nested | 1.12x | 25.43x | 1.38x | 21.39x |
| calls | 1.15x | 1.09x | 1.15x | 1.10x |
| fib | 1.03x | 1.06x | 1.02x | 1.08x |
| table_array | 1.15x | 10.85x | 1.16x | 12.70x |
| table_hash | 0.98x | 0.99x | 1.01x | 1.00x |
| strings | 0.99x | 0.99x | 1.82x | 2.04x |
| metamethods | 0.96x | 0.88x | 0.95x | 0.87x |
| closures | 1.04x | 0.88x | 1.06x | 0.97x |
| mandelbrot | 1.24x | 78.91x | 1.20x | 79.34x |
| sieve | 1.03x | 0.87x | 1.12x | 0.89x |
| math_calls | 1.04x | 101.45x | 0.97x | 73.39x |
| go_callback | 1.08x | 0.98x | 1.08x | 1.01x |

### Kernels: heap allocations per call

| kernel | upstream allocs | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | upstream bytes | JIT 5.5 bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 156234 | 124992 | 5 | 124895 | 2 | 39995720 | 22 |
| arith_float | 187490 | 156247 | 5 | 156216 | 2 | 47997076 | 56 |
| loop_nested | 31867 | 71563 | 9 | 31531 | 2 | 8157885 | 31 |
| calls | 28117 | 18750 | 18750 | 18718 | 18718 | 7197885 | 4791484 |
| fib | 20 | 20 | 20 | 1 | 1 | 4877 | 428 |
| table_array | 87488 | 56281 | 63 | 56122 | 45 | 40332337 | 8371333 |
| table_hash | 37499 | 28132 | 28132 | 28045 | 28045 | 9596884 | 7176384 |
| strings | 230383 | 229767 | 231009 | 138708 | 139894 | 3780710 | 3059833 |
| metamethods | 1112510 | 1109392 | 1109393 | 1109320 | 1112413 | 83198195 | 87973225 |
| closures | 624989 | 618746 | 618746 | 618686 | 618687 | 30396908 | 28783340 |
| mandelbrot | 100565 | 74863 | 5 | 74633 | 0 | 25744474 | 104 |
| sieve | 60181 | 68179 | 80671 | 67916 | 80353 | 33341692 | 29018734 |
| math_calls | 946861 | 937493 | 7 | 871160 | 3 | 19196756 | 40 |
| go_callback | 328117 | 318750 | 337492 | 318719 | 337405 | 9597920 | 11975405 |

### JIT code size and compilation time per kernel (Lua 5.5 profile)

| kernel | units | executable memory (bytes) | total compile time (µs) |
|---|---:|---:|---:|
| arith_int | 1 | 4096 | 104 |
| arith_float | 1 | 4096 | 107 |
| loop_nested | 2 | 8192 | 265 |
| calls | 1 | 0 | 108 |
| fib | 0 | 0 | 0 |
| table_array | 3 | 12288 | 601 |
| table_hash | 1 | 0 | 119 |
| strings | 1 | 4096 | 178 |
| metamethods | 1 | 4096 | 95 |
| closures | 1 | 0 | 117 |
| mandelbrot | 3 | 8192 | 669 |
| sieve | 13 | 4096 | 1609 |
| math_calls | 1 | 4096 | 196 |
| go_callback | 1 | 4096 | 119 |

### Other benchmarks (ns per operation, allocations per operation)

| benchmark | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|---:|
| Cold/arith_int | 26988876 ns, 16602 allocs | 27033832 ns, 13509 allocs | 2327945 ns, 1882 allocs | 9944380 ns, 13483 allocs | 1825647 ns, 1630 allocs |
| Cold/mandelbrot | 800246 ns, 2314 allocs | 766087 ns, 2177 allocs | 973635 ns, 4260 allocs | 793596 ns, 2187 allocs | 1003354 ns, 4306 allocs |
| Cold/strings | 2792157 ns, 23587 allocs | 3002999 ns, 23547 allocs | 3278817 ns, 24932 allocs | 1586344 ns, 14931 allocs | 1791141 ns, 16044 allocs |
| GoToLua | 120 ns, 2 allocs | 120 ns, 2 allocs | 132 ns, 2 allocs | 115 ns, 1 allocs | 123 ns, 1 allocs |
| NewState | 73108 ns, 782 allocs | 75730 ns, 801 allocs | 74029 ns, 805 allocs | 88899 ns, 890 allocs | 83763 ns, 894 allocs |
| Pool | 3876 ns, 10 allocs | 3939 ns, 12 allocs | 426 ns, 5 allocs | 1094 ns, 0 allocs | 280 ns, 0 allocs |

## Reading the results

- **Interpreter.** The interpreter is GopherLua's design and performs like
  it: between 0.95x and 1.25x of upstream in the Lua 5.1 profile. The Lua
  5.5 profile is faster where integer arithmetic replaces float arithmetic
  (`arith_int`, about 3x) and in `strings` (the Lua 5.5 string library is a
  new implementation, about 1.8x); otherwise it is on par. No broader
  interpreter redesign (value representation, dispatch) was attempted.
- **JIT, where it applies.** Loops over integers, floats and number arrays
  run 10 to 100 times faster than upstream GopherLua (`arith_int`,
  `arith_float`, `loop_nested`, `table_array`, `mandelbrot`, `math_calls`),
  with essentially no heap allocation. On these kernels the JIT is faster
  than the PUC-Rio Lua 5.5 interpreter and within a factor of 1 to 4 of
  LuaJIT (`mandelbrot` and `math_calls` are on par; `arith_int` is 4x
  behind, `table_array` 2x).
- **JIT, where it does not apply.** `calls`, `fib`, `table_hash`,
  `metamethods`, `closures`, `sieve` (a boolean array), `go_callback` and
  the 5.1 `strings` kernel are not accelerated: function calls, string
  operations, hash-table field access, metamethods and non-number arrays
  are executed by the interpreter. With the JIT enabled these kernels run
  at interpreter speed, in some cases up to about 10 percent slower
  because loop back-edges are instrumented and compilation is attempted
  before the loop is handed back to the interpreter. On such workloads
  this runtime, like GopherLua, is several times slower than PUC-Rio Lua
  and one to two orders of magnitude slower than LuaJIT.
- **Cold start.** Compiling a loop costs about 0.1 ms; a state that only
  runs a short script once does not benefit (`Cold/mandelbrot`,
  `Cold/strings`), a longer numeric run does (`Cold/arith_int`).
- **State creation** is 5 to 20 percent slower than upstream (more library
  functions are registered in the Lua 5.5 profile).
- **Pooled states**: the pooled handler with a 200-iteration loop is 3.5x
  (Lua 5.5 interpreter) to 14x (JIT) faster than upstream.
- **Code cache.** Each compiled unit occupies one page of executable
  memory (4 KiB on this machine); the kernels need one to three live units.

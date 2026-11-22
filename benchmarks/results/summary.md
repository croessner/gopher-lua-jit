### Kernels: time per call in milliseconds (median of 3 runs)

| kernel | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | lua5.5 | luajit |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 324.94 | 291.11 | 21.07 | 93.52 | 16.15 | 45.46 | 5.45 |
| arith_float | 99.33 | 75.07 | 2.80 | 77.16 | 3.14 | 19.41 | 3.58 |
| loop_nested | 33.33 | 31.51 | 1.27 | 25.01 | 1.54 | 6.58 | 1.20 |
| calls | 38.21 | 27.57 | 31.51 | 27.43 | 31.06 | 8.16 | 0.35 |
| fib | 14.10 | 13.38 | 13.36 | 11.90 | 13.13 | 3.86 | 0.56 |
| table_array | 64.47 | 56.18 | 5.70 | 54.76 | 4.87 | 10.28 | 3.38 |
| table_hash | 89.26 | 86.16 | 91.45 | 81.36 | 86.66 | 13.95 | 0.41 |
| strings | 31.07 | 26.90 | 28.80 | 13.51 | 13.04 | 19.95 | 4.14 |
| metamethods | 115.07 | 108.95 | 109.65 | 109.27 | 112.84 | 48.23 | 0.15 |
| closures | 42.22 | 40.00 | 44.02 | 40.67 | 45.71 | 69.96 | 20.99 |
| mandelbrot | 65.15 | 57.13 | 0.85 | 57.13 | 0.88 | 15.25 | 1.02 |
| sieve | 69.40 | 64.24 | 71.93 | 59.99 | 63.36 | 8.68 | 3.80 |
| math_calls | 146.22 | 139.69 | 1.47 | 148.21 | 2.16 | 41.57 | 1.63 |
| go_callback | 42.24 | 44.60 | 47.71 | 44.81 | 43.80 | 9.30 | 0.35 |

### Kernels: speedup relative to upstream GopherLua (higher is better)

| kernel | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|
| arith_int | 1.12x | 15.42x | 3.47x | 20.12x |
| arith_float | 1.32x | 35.47x | 1.29x | 31.67x |
| loop_nested | 1.06x | 26.24x | 1.33x | 21.70x |
| calls | 1.39x | 1.21x | 1.39x | 1.23x |
| fib | 1.05x | 1.06x | 1.18x | 1.07x |
| table_array | 1.15x | 11.32x | 1.18x | 13.25x |
| table_hash | 1.04x | 0.98x | 1.10x | 1.03x |
| strings | 1.15x | 1.08x | 2.30x | 2.38x |
| metamethods | 1.06x | 1.05x | 1.05x | 1.02x |
| closures | 1.06x | 0.96x | 1.04x | 0.92x |
| mandelbrot | 1.14x | 76.74x | 1.14x | 73.62x |
| sieve | 1.08x | 0.96x | 1.16x | 1.10x |
| math_calls | 1.05x | 99.68x | 0.99x | 67.68x |
| go_callback | 0.95x | 0.89x | 0.94x | 0.96x |

### Kernels: heap allocations per call

| kernel | upstream allocs | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | upstream bytes | JIT 5.5 bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 156234 | 124992 | 5 | 124895 | 2 | 39995720 | 22 |
| arith_float | 187489 | 156247 | 5 | 156216 | 2 | 47997028 | 56 |
| loop_nested | 31867 | 71563 | 9 | 31531 | 2 | 8157880 | 31 |
| calls | 28117 | 18750 | 18750 | 18718 | 18718 | 7197865 | 4791484 |
| fib | 20 | 20 | 20 | 1 | 1 | 4878 | 432 |
| table_array | 87488 | 56282 | 63 | 56122 | 46 | 40332312 | 8371360 |
| table_hash | 37499 | 28132 | 28132 | 28045 | 28045 | 9596816 | 7176384 |
| strings | 230384 | 229767 | 231010 | 138708 | 139894 | 3780787 | 3059836 |
| metamethods | 1112510 | 1109393 | 1109393 | 1109319 | 1112412 | 83198195 | 87973158 |
| closures | 624989 | 618747 | 618746 | 618686 | 618687 | 30396917 | 28783342 |
| mandelbrot | 100565 | 74863 | 5 | 74633 | 0 | 25744400 | 103 |
| sieve | 60181 | 68179 | 80671 | 67916 | 80352 | 33341708 | 29018725 |
| math_calls | 946861 | 937493 | 7 | 871160 | 3 | 19196728 | 39 |
| go_callback | 328117 | 318750 | 337492 | 318719 | 337405 | 9597912 | 11975397 |

### JIT code size and compilation time per kernel (Lua 5.5 profile)

| kernel | units | executable memory (bytes) | total compile time (µs) |
|---|---:|---:|---:|
| arith_int | 1 | 4096 | 96 |
| arith_float | 1 | 4096 | 112 |
| loop_nested | 2 | 8192 | 237 |
| calls | 1 | 0 | 97 |
| fib | 0 | 0 | 0 |
| table_array | 3 | 12288 | 682 |
| table_hash | 1 | 0 | 112 |
| strings | 1 | 4096 | 181 |
| metamethods | 1 | 4096 | 95 |
| closures | 1 | 0 | 134 |
| mandelbrot | 3 | 8192 | 795 |
| sieve | 13 | 4096 | 1423 |
| math_calls | 1 | 4096 | 256 |
| go_callback | 1 | 4096 | 128 |

### Other benchmarks (ns per operation, allocations per operation)

| benchmark | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|---:|
| Cold/arith_int | 30074263 ns, 16602 allocs | 28981673 ns, 13511 allocs | 2642904 ns, 1886 allocs | 10727357 ns, 13483 allocs | 2092033 ns, 1632 allocs |
| Cold/mandelbrot | 894984 ns, 2314 allocs | 882706 ns, 2177 allocs | 1056287 ns, 4261 allocs | 830460 ns, 2187 allocs | 1098055 ns, 4308 allocs |
| Cold/strings | 3209520 ns, 23587 allocs | 3422841 ns, 23547 allocs | 3581185 ns, 24934 allocs | 1853330 ns, 14931 allocs | 2007202 ns, 16046 allocs |
| GoToLua | 136 ns, 2 allocs | 139 ns, 2 allocs | 133 ns, 2 allocs | 122 ns, 1 allocs | 127 ns, 1 allocs |
| NewState | 74641 ns, 782 allocs | 78468 ns, 801 allocs | 83681 ns, 806 allocs | 88750 ns, 890 allocs | 88030 ns, 895 allocs |
| Pool | 4936 ns, 10 allocs | 4826 ns, 12 allocs | 463 ns, 5 allocs | 1312 ns, 0 allocs | 348 ns, 0 allocs |

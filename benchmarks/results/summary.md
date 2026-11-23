### Kernels: time per call in milliseconds (median of 3 runs)

| kernel | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | lua5.5 | luajit |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 420.37 | 398.03 | 24.83 | 122.71 | 22.10 | 60.84 | 5.75 |
| arith_float | 102.38 | 102.80 | 3.74 | 93.19 | 3.75 | 25.55 | 3.81 |
| loop_nested | 38.98 | 38.43 | 1.60 | 39.08 | 2.18 | 8.54 | 1.27 |
| calls | 45.27 | 36.86 | 0.85 | 41.15 | 1.16 | 10.71 | 0.38 |
| fib | 17.24 | 18.43 | 16.80 | 15.58 | 15.85 | 5.06 | 0.47 |
| table_array | 72.85 | 76.02 | 5.76 | 76.82 | 5.20 | 14.44 | 3.60 |
| table_hash | 105.60 | 66.42 | 2.27 | 60.87 | 2.78 | 18.32 | 0.44 |
| strings | 35.06 | 37.23 | 37.48 | 18.38 | 18.21 | 25.00 | 4.44 |
| metamethods | 134.80 | 87.17 | 87.96 | 78.30 | 78.84 | 59.59 | 0.16 |
| closures | 53.42 | 57.81 | 53.71 | 58.84 | 56.99 | 92.81 | 22.56 |
| mandelbrot | 80.94 | 77.52 | 1.16 | 74.46 | 1.06 | 18.62 | 1.09 |
| sieve | 89.06 | 74.85 | 5.80 | 85.00 | 6.87 | 12.06 | 4.09 |
| math_calls | 179.16 | 183.40 | 1.06 | 209.09 | 1.69 | 49.51 | 1.73 |
| go_callback | 51.38 | 52.22 | 57.12 | 61.19 | 47.51 | 11.50 | 0.38 |
| objects | 201.43 | 178.88 | 5.39 | 184.50 | 5.11 | 43.93 | 2.19 |
| module_state | 804.02 | 841.04 | 31.56 | 532.01 | 20.91 | 159.97 | 8.48 |
| linked_list | 20.63 | 15.19 | 2.40 | 13.48 | 2.32 | 5.23 | 1.28 |
| string_scan | 100.79 | 135.75 | 5.73 | 90.77 | 4.97 | 30.89 | 1.55 |
| stencil | 214.64 | 222.27 | 12.27 | 204.65 | 10.92 | 37.51 | 6.66 |
| binary_search | 254.94 | 276.88 | 12.69 | 265.32 | 13.67 | 63.04 | 12.73 |

### Kernels: speedup relative to upstream GopherLua (higher is better)

| kernel | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|
| arith_int | 1.06x | 16.93x | 3.43x | 19.02x |
| arith_float | 1.00x | 27.37x | 1.10x | 27.27x |
| loop_nested | 1.01x | 24.43x | 1.00x | 17.89x |
| calls | 1.23x | 53.10x | 1.10x | 39.02x |
| fib | 0.94x | 1.03x | 1.11x | 1.09x |
| table_array | 0.96x | 12.64x | 0.95x | 14.01x |
| table_hash | 1.59x | 46.60x | 1.73x | 37.96x |
| strings | 0.94x | 0.94x | 1.91x | 1.93x |
| metamethods | 1.55x | 1.53x | 1.72x | 1.71x |
| closures | 0.92x | 0.99x | 0.91x | 0.94x |
| mandelbrot | 1.04x | 69.70x | 1.09x | 76.13x |
| sieve | 1.19x | 15.37x | 1.05x | 12.97x |
| math_calls | 0.98x | 168.97x | 0.86x | 105.74x |
| go_callback | 0.98x | 0.90x | 0.84x | 1.08x |
| objects | 1.13x | 37.37x | 1.09x | 39.46x |
| module_state | 0.96x | 25.47x | 1.51x | 38.45x |
| linked_list | 1.36x | 8.60x | 1.53x | 8.89x |
| string_scan | 0.74x | 17.60x | 1.11x | 20.27x |
| stencil | 0.97x | 17.49x | 1.05x | 19.66x |
| binary_search | 0.92x | 20.09x | 0.96x | 18.65x |

### Kernels: heap allocations per call

| kernel | upstream allocs | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | upstream bytes | JIT 5.5 bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 156234 | 124993 | 5 | 124896 | 2 | 39995720 | 16 |
| arith_float | 187489 | 156247 | 5 | 156216 | 2 | 47996988 | 56 |
| loop_nested | 31867 | 71563 | 9 | 31531 | 2 | 8157874 | 31 |
| calls | 28117 | 18750 | 5 | 18718 | 2 | 7197869 | 23 |
| fib | 20 | 20 | 20 | 1 | 1 | 4879 | 428 |
| table_array | 87488 | 56285 | 63 | 56125 | 48 | 40332340 | 8371643 |
| table_hash | 37499 | 28120 | 8 | 28033 | 5 | 9596838 | 360 |
| strings | 230384 | 229766 | 229551 | 138708 | 138496 | 3780720 | 2701829 |
| metamethods | 1112510 | 209374 | 209374 | 209301 | 209301 | 83198208 | 31180164 |
| closures | 624989 | 618746 | 618747 | 618687 | 618686 | 30396917 | 28783336 |
| mandelbrot | 100565 | 74864 | 5 | 74633 | 0 | 25744432 | 99 |
| sieve | 60181 | 68182 | 45 | 67919 | 35 | 33341680 | 8370131 |
| math_calls | 946861 | 937493 | 7 | 871160 | 3 | 19196720 | 39 |
| go_callback | 328117 | 318750 | 309376 | 318719 | 309345 | 9597899 | 4791840 |
| objects | 51111 | 57567 | 223 | 49628 | 379 | 12745653 | 57276 |
| module_state | 2140608 | 2109367 | 9 | 1108536 | 4 | 51995920 | 32 |
| linked_list | 17307 | 8288 | 2070 | 8252 | 2031 | 2415134 | 295642 |
| string_scan | 216242 | 210000 | 6 | 9885 | 2 | 5757872 | 55 |
| stencil | 140397 | 109194 | 95 | 80870 | 64 | 53877050 | 8373734 |
| binary_search | 1042555 | 1039418 | 21 | 811705 | 15 | 31207360 | 25435 |

### JIT code size and compilation time per kernel (Lua 5.5 profile)

| kernel | units | executable memory (bytes) | total compile time (µs) |
|---|---:|---:|---:|
| arith_int | 1 | 4096 | 170 |
| arith_float | 1 | 4096 | 157 |
| loop_nested | 2 | 8192 | 372 |
| calls | 1 | 4096 | 285 |
| fib | 0 | 0 | 0 |
| table_array | 3 | 12288 | 742 |
| table_hash | 1 | 4096 | 302 |
| strings | 1 | 4096 | 268 |
| metamethods | 1 | 0 | 159 |
| closures | 4 | 0 | 880 |
| mandelbrot | 3 | 8192 | 978 |
| sieve | 3 | 12288 | 1025 |
| math_calls | 1 | 4096 | 252 |
| go_callback | 1 | 4096 | 178 |
| objects | 5 | 8192 | 4288 |
| module_state | 2 | 8192 | 846 |
| linked_list | 5 | 4096 | 1002 |
| string_scan | 1 | 4096 | 584 |
| stencil | 3 | 12288 | 1168 |
| binary_search | 3 | 12288 | 1019 |

### Other benchmarks (ns per operation, allocations per operation)

| benchmark | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|---:|
| Cold/arith_int | 40402247 ns, 16602 allocs | 38828900 ns, 13002 allocs | 3573625 ns, 1508 allocs | 15706591 ns, 12925 allocs | 2921964 ns, 1111 allocs |
| Cold/mandelbrot | 1083251 ns, 2314 allocs | 1105876 ns, 1668 allocs | 1305927 ns, 4151 allocs | 1175976 ns, 1629 allocs | 1116777 ns, 3535 allocs |
| Cold/strings | 3937848 ns, 23587 allocs | 5050671 ns, 23045 allocs | 5315996 ns, 24430 allocs | 2569615 ns, 14380 allocs | 2800155 ns, 15508 allocs |
| GoToLua | 167 ns, 2 allocs | 184 ns, 2 allocs | 177 ns, 2 allocs | 170 ns, 1 allocs | 226 ns, 1 allocs |
| NewState | 88638 ns, 782 allocs | 65762 ns, 302 allocs | 65728 ns, 307 allocs | 60878 ns, 334 allocs | 66148 ns, 339 allocs |
| Pool | 7427 ns, 10 allocs | 5906 ns, 12 allocs | 694 ns, 5 allocs | 2320 ns, 0 allocs | 673 ns, 0 allocs |

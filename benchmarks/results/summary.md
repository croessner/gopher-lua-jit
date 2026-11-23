### Kernels: time per call in milliseconds (median of 3 runs)

| kernel | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | lua5.5 | luajit |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 328.88 | 318.00 | 16.51 | 97.48 | 17.30 | 52.99 | 5.12 |
| arith_float | 92.52 | 78.92 | 3.06 | 84.22 | 3.02 | 21.68 | 3.38 |
| loop_nested | 33.82 | 30.03 | 1.42 | 25.98 | 1.50 | 7.20 | 1.13 |
| calls | 37.11 | 29.35 | 0.45 | 28.51 | 0.48 | 8.58 | 0.34 |
| fib | 14.27 | 14.05 | 13.47 | 13.54 | 13.06 | 4.11 | 0.42 |
| table_array | 64.98 | 63.52 | 3.95 | 57.43 | 4.26 | 12.06 | 3.27 |
| table_hash | 94.51 | 48.31 | 0.90 | 52.53 | 0.91 | 14.36 | 0.39 |
| strings | 30.95 | 28.29 | 28.72 | 15.30 | 14.21 | 20.17 | 3.84 |
| metamethods | 119.50 | 62.39 | 63.85 | 59.72 | 61.80 | 47.38 | 0.14 |
| closures | 43.84 | 43.29 | 44.63 | 40.07 | 42.11 | 67.48 | 20.72 |
| mandelbrot | 67.23 | 53.52 | 0.86 | 52.96 | 0.90 | 14.44 | 0.97 |
| sieve | 66.08 | 62.98 | 5.23 | 73.78 | 6.76 | 8.21 | 3.67 |
| math_calls | 152.84 | 180.42 | 1.05 | 181.03 | 1.43 | 39.23 | 1.55 |
| go_callback | 39.70 | 48.00 | 46.72 | 46.41 | 40.66 | 8.81 | 0.34 |
| objects | 172.88 | 147.08 | 3.57 | 149.17 | 4.22 | 33.78 | 1.95 |
| module_state | 719.36 | 653.91 | 16.79 | 428.32 | 7.19 | 134.09 | 7.88 |
| linked_list | 14.01 | 11.38 | 2.25 | 11.03 | 2.27 | 3.76 | 1.15 |
| string_scan | 92.54 | 107.23 | 4.29 | 62.74 | 3.97 | 25.72 | 1.75 |
| stencil | 171.25 | 171.46 | 8.58 | 181.85 | 7.46 | 33.50 | 5.67 |
| binary_search | 168.35 | 189.70 | 8.76 | 192.75 | 10.02 | 51.26 | 10.99 |

### Kernels: speedup relative to upstream GopherLua (higher is better)

| kernel | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|
| arith_int | 1.03x | 19.92x | 3.37x | 19.01x |
| arith_float | 1.17x | 30.25x | 1.10x | 30.63x |
| loop_nested | 1.13x | 23.85x | 1.30x | 22.54x |
| calls | 1.26x | 82.76x | 1.30x | 77.34x |
| fib | 1.02x | 1.06x | 1.05x | 1.09x |
| table_array | 1.02x | 16.47x | 1.13x | 15.27x |
| table_hash | 1.96x | 104.94x | 1.80x | 103.82x |
| strings | 1.09x | 1.08x | 2.02x | 2.18x |
| metamethods | 1.92x | 1.87x | 2.00x | 1.93x |
| closures | 1.01x | 0.98x | 1.09x | 1.04x |
| mandelbrot | 1.26x | 77.97x | 1.27x | 75.02x |
| sieve | 1.05x | 12.63x | 0.90x | 9.77x |
| math_calls | 0.85x | 145.13x | 0.84x | 106.58x |
| go_callback | 0.83x | 0.85x | 0.86x | 0.98x |
| objects | 1.18x | 48.36x | 1.16x | 40.93x |
| module_state | 1.10x | 42.84x | 1.68x | 100.12x |
| linked_list | 1.23x | 6.21x | 1.27x | 6.18x |
| string_scan | 0.86x | 21.56x | 1.48x | 23.31x |
| stencil | 1.00x | 19.95x | 0.94x | 22.94x |
| binary_search | 0.89x | 19.23x | 0.87x | 16.81x |

### Kernels: heap allocations per call

| kernel | upstream allocs | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 | upstream bytes | JIT 5.5 bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| arith_int | 156234 | 124992 | 5 | 124895 | 2 | 39995664 | 23 |
| arith_float | 187489 | 156247 | 5 | 156216 | 2 | 47996981 | 56 |
| loop_nested | 31867 | 71563 | 9 | 31531 | 2 | 8157879 | 31 |
| calls | 28117 | 18750 | 5 | 18718 | 2 | 7197873 | 23 |
| fib | 20 | 20 | 20 | 1 | 1 | 4877 | 428 |
| table_array | 87488 | 56285 | 61 | 56125 | 48 | 40332325 | 8372091 |
| table_hash | 37499 | 28120 | 8 | 28033 | 5 | 9596816 | 408 |
| strings | 230383 | 229767 | 229552 | 138708 | 138496 | 3780663 | 2701826 |
| metamethods | 1112510 | 209374 | 209374 | 209301 | 209302 | 83198262 | 35980352 |
| closures | 624989 | 618746 | 618747 | 618686 | 618687 | 30396945 | 28783360 |
| mandelbrot | 100565 | 74864 | 5 | 74633 | 0 | 25744416 | 100 |
| sieve | 60181 | 68182 | 45 | 67919 | 35 | 33341738 | 8370177 |
| math_calls | 946861 | 937493 | 7 | 871160 | 3 | 19196794 | 39 |
| go_callback | 328117 | 318750 | 309376 | 318719 | 309345 | 9597912 | 4791842 |
| objects | 51111 | 57567 | 223 | 49629 | 365 | 12745644 | 60056 |
| module_state | 2140607 | 2109366 | 9 | 1108535 | 4 | 51995808 | 43 |
| linked_list | 17307 | 8288 | 2071 | 8252 | 2032 | 2415135 | 343942 |
| string_scan | 216242 | 210000 | 6 | 9885 | 2 | 5757864 | 56 |
| stencil | 140397 | 109194 | 88 | 80870 | 62 | 53877050 | 8374288 |
| binary_search | 1042554 | 1039416 | 21 | 811706 | 15 | 31207290 | 25483 |

### JIT code size and compilation time per kernel (Lua 5.5 profile)

| kernel | units | executable memory (bytes) | total compile time (µs) |
|---|---:|---:|---:|
| arith_int | 1 | 4096 | 185 |
| arith_float | 1 | 4096 | 199 |
| loop_nested | 2 | 8192 | 615 |
| calls | 1 | 4096 | 249 |
| fib | 0 | 0 | 0 |
| table_array | 3 | 12288 | 1125 |
| table_hash | 1 | 4096 | 433 |
| strings | 1 | 4096 | 258 |
| metamethods | 1 | 0 | 121 |
| closures | 4 | 0 | 544 |
| mandelbrot | 3 | 8192 | 1467 |
| sieve | 3 | 12288 | 2191 |
| math_calls | 1 | 4096 | 371 |
| go_callback | 1 | 4096 | 182 |
| objects | 5 | 8192 | 3888 |
| module_state | 2 | 8192 | 1183 |
| linked_list | 5 | 4096 | 1176 |
| string_scan | 1 | 4096 | 918 |
| stencil | 3 | 12288 | 1465 |
| binary_search | 3 | 12288 | 1643 |

### Other benchmarks (ns per operation, allocations per operation)

| benchmark | upstream | interp 5.1 | JIT 5.1 | interp 5.5 | JIT 5.5 |
|---|---:|---:|---:|---:|---:|
| Cold/arith_int | 28396313 ns, 16602 allocs | 29467738 ns, 13002 allocs | 2386620 ns, 2243 allocs | 9783340 ns, 12925 allocs | 2095556 ns, 1384 allocs |
| Cold/mandelbrot | 842493 ns, 2314 allocs | 724582 ns, 1668 allocs | 1352761 ns, 5461 allocs | 725136 ns, 1629 allocs | 1290971 ns, 4842 allocs |
| Cold/strings | 2811597 ns, 23587 allocs | 3152422 ns, 23045 allocs | 3482536 ns, 24757 allocs | 1576379 ns, 14380 allocs | 2051289 ns, 15776 allocs |
| GoToLua | 133 ns, 2 allocs | 129 ns, 2 allocs | 132 ns, 2 allocs | 123 ns, 1 allocs | 134 ns, 1 allocs |
| NewState | 79640 ns, 782 allocs | 50299 ns, 302 allocs | 44833 ns, 307 allocs | 50983 ns, 334 allocs | 50855 ns, 339 allocs |
| Pool | 4392 ns, 10 allocs | 4437 ns, 12 allocs | 476 ns, 5 allocs | 1388 ns, 0 allocs | 337 ns, 0 allocs |

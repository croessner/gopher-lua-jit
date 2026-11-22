-- Runs the benchmark kernels with a stand-alone Lua interpreter and
-- prints nanoseconds per call. Usage: <lua> harness.lua [name ...]
-- The same kernels are used by the Go benchmarks in bench_test.go.
local kernels = {
  {"arith_int", 1000000}, {"arith_float", 1000000}, {"loop_nested", 10000},
  {"calls", 300000}, {"fib", 24}, {"table_array", 200000}, {"table_hash", 300000},
  {"strings", 20000}, {"metamethods", 100000}, {"closures", 200000},
  {"mandelbrot", 100}, {"sieve", 200000}, {"math_calls", 300000}, {"go_callback", 300000},
}
gofn = function(i) return i + 1 end -- stand-in for the host function
local dir = arg and arg[0] and arg[0]:match("^(.*)/[^/]*$") or "."
local only = {}
for i = 1, #(arg or {}) do only[arg[i]] = true end
for _, k in ipairs(kernels) do
  local name, n = k[1], k[2]
  if next(only) == nil or only[name] then
    local run = assert(loadfile(dir .. "/scripts/" .. name .. ".lua"))()
    run(n) -- warm up
    local best = math.huge
    for round = 1, 5 do
      local t0 = os.clock()
      run(n)
      local dt = os.clock() - t0
      if dt < best then best = dt end
    end
    print(string.format("%-14s n=%-8d %12.0f ns/op", name, n, best * 1e9))
  end
end

-- Coroutines: creation, resume/yield value passing, status and wrap.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## a coroutine that is waiting for another one ("normal") cannot be resumed
do
local a, b
local res
a = coroutine.create(function() coroutine.resume(b) end)
b = coroutine.create(function() res = {coroutine.resume(a)} end)
coroutine.resume(a)
assert(res[1] == false)
assert(type(res[2]) == "string")
end

-- ## a generator stored in a local used directly as iterator
do
local gen = coroutine.wrap(function() for i = 1, 3 do coroutine.yield(i) end end)
local sum = 0
for v in gen do sum = sum + v end
assert(sum == 6)
end

-- ## returning the results of yield directly from the coroutine body
do
local co = coroutine.wrap(function() return coroutine.yield("y") end)
assert(co() == "y")
assert(co("back") == "back")
local co2 = coroutine.wrap(function(...) return coroutine.yield(...) end)
assert(co2(1, 2) == 1)
assert(select("#", co2("a", "b", "c")) == 3)
end

-- ## a chain of tail calls ending in yield
do
local function tail_yield(n)
  if n == 0 then return coroutine.yield("tail") end
  return tail_yield(n - 1)
end
local co = coroutine.wrap(function() return tail_yield(1000) end)
assert(co() == "tail")
assert(co("back") == "back")
end

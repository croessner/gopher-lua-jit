-- Coroutines: yielding across pcall, metamethods, iterators and other
-- call boundaries.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## yield across pcall
do
local co = coroutine.create(function()
  local ok, v = pcall(function()
    local x = coroutine.yield("in pcall")
    return x * 2
  end)
  return ok, v
end)
assert(show(coroutine.resume(co)) == "true,in pcall")
assert(show(coroutine.resume(co, 21)) == "true,true,42")
end

-- ## an error after a yield inside pcall is still caught
do
local co = coroutine.create(function()
  local ok, e = pcall(function()
    coroutine.yield("before error")
    error("after yield", 0)
  end)
  coroutine.yield("caught:" .. tostring(e))
  return "finished"
end)
assert(show(coroutine.resume(co)) == "true,before error")
assert(show(coroutine.resume(co)) == "true,caught:after yield")
assert(show(coroutine.resume(co)) == "true,finished")
end

-- ## yield across nested pcalls
do
local co = coroutine.wrap(function()
  return pcall(pcall, function()
    return pcall(function()
      return coroutine.yield("deep") .. "!"
    end)
  end)
end)
assert(co() == "deep")
assert(show(co("resumed")) == "true,true,true,resumed!")
end

-- ## yield across xpcall
do
local co = coroutine.wrap(function()
  local ok, v = xpcall(function()
    local x = coroutine.yield("in xpcall")
    error("err:" .. x, 0)
  end, function(m) return "handled " .. m end)
  return ok, v
end)
assert(co() == "in xpcall")
assert(show(co("v")) == "false,handled err:v")
end

-- ## yield inside a generic for iterator function
do
local function iter(state, control)
  local nextval = coroutine.yield("iter:" .. tostring(control))
  if control < 2 then return control + 1 end
end
local co = coroutine.wrap(function()
  local out = {}
  for i in iter, nil, 0, nil do out[#out + 1] = i end
  return table.concat(out, ",")
end)
assert(co() == "iter:0")
assert(co() == "iter:1")
assert(co() == "iter:2")
assert(co() == "1,2")
end

-- ## yield inside a function called by table.sort is rejected or works
do
local co = coroutine.create(function()
  local t = {3, 1, 2}
  table.sort(t, function(a, b) coroutine.yield("cmp"); return a < b end)
  return "sorted"
end)
local ok, v = coroutine.resume(co)
assert((ok == false) or v == "cmp")
end

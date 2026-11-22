-- Coroutines: yielding across pcall, metamethods, iterators and other
-- call boundaries.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## yield inside the loop body of a generic for
do
local co = coroutine.wrap(function()
  for k, v in pairs({a = 1}) do coroutine.yield(k, v) end
  for i, v in ipairs({"x", "y"}) do coroutine.yield(v) end
  return "end"
end)
local k, v = co()
assert(k == "a" and v == 1)
assert(co() == "x")
assert(co() == "y")
assert(co() == "end")
end

-- ## yield across a method call chain and varargs
do
local obj = {}
function obj:step(...) return coroutine.yield(select("#", ...)) end
local co = coroutine.wrap(function(...)
  local a = obj:step(...)
  local b = obj:step(a, a)
  return a, b
end)
assert(co(1, 2, 3) == 3)
assert(co("A") == 2)
assert(show(co("B")) == "A,B")
end

-- ## values survive across a yield
do
local co = coroutine.wrap(function()
  local a, b, c = 1, "two", {3}
  local t = {x = 1}
  coroutine.yield()
  t.x = t.x + 1
  coroutine.yield()
  return a, b, c[1], t.x
end)
co(); co()
assert(show(co()) == "1,two,3,2")
end

-- ## errors cross coroutine boundaries through wrap
do
local inner = coroutine.wrap(function() error({code = 42}) end)
local outer = coroutine.create(function() inner() end)
local ok, e = coroutine.resume(outer)
assert(ok == false and type(e) == "table" and e.code == 42)
local lvl1 = coroutine.wrap(function()
  local lvl2 = coroutine.wrap(function()
    local lvl3 = coroutine.wrap(function() error("three levels", 0) end)
    lvl3()
  end)
  lvl2()
end)
local ok, e = pcall(lvl1)
assert(ok == false)
assert(tostring(e):find("three levels"))
end

-- ## pcall inside a coroutine catches errors of nested resumes
do
local co = coroutine.wrap(function()
  local inner = coroutine.create(function() error("inner", 0) end)
  local ok, e = coroutine.resume(inner)
  coroutine.yield(tostring(ok) .. ":" .. e)
  local ok2, e2 = pcall(coroutine.wrap(function() error("wrapped", 0) end))
  return tostring(ok2) .. ":" .. tostring(e2)
end)
assert(co() == "false:inner")
local r = co()
assert(r:find("^false:") and r:find("wrapped"))
end

-- ## to-be-closed variables are closed when a coroutine finishes normally
do
local log = {}
local co = coroutine.wrap(function()
  local x <close> = setmetatable({}, {__close = function() log[#log + 1] = "closed" end})
  coroutine.yield("y")
  return "r"
end)
assert(co() == "y")
assert(#log == 0)
assert(co() == "r")
assert(log[1] == "closed")
end

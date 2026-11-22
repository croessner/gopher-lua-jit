-- Coroutines: yielding inside metamethods, one section per event.
-- The metamethods and coroutine bodies avoid tail calls on purpose so each
-- section exercises exactly one mechanism.

-- builds a metatable whose handler for the event yields its name and
-- returns the value passed to the next resume
local function yielding(event)
  return {[event] = function()
    local v = coroutine.yield(event)
    return v
  end}
end

-- ## yield inside __add
do
local v = setmetatable({}, yielding("__add"))
local co = coroutine.wrap(function()
  local r = v + 1
  return r
end)
assert(co() == "__add")
assert(co("resumed") == "resumed")
end

-- ## yield inside __add with the object as right operand
do
local v = setmetatable({}, yielding("__add"))
local co = coroutine.wrap(function()
  local r = 1 + v
  return r
end)
assert(co() == "__add")
assert(co("resumed") == "resumed")
end

-- ## yield inside __sub
do
local v = setmetatable({}, yielding("__sub"))
local co = coroutine.wrap(function()
  local r = v - 1
  return r
end)
assert(co() == "__sub")
assert(co("resumed") == "resumed")
end

-- ## yield inside __sub with the object as right operand
do
local v = setmetatable({}, yielding("__sub"))
local co = coroutine.wrap(function()
  local r = 1 - v
  return r
end)
assert(co() == "__sub")
assert(co("resumed") == "resumed")
end

-- ## yield inside __mul
do
local v = setmetatable({}, yielding("__mul"))
local co = coroutine.wrap(function()
  local r = v * 1
  return r
end)
assert(co() == "__mul")
assert(co("resumed") == "resumed")
end

-- ## yield inside __mul with the object as right operand
do
local v = setmetatable({}, yielding("__mul"))
local co = coroutine.wrap(function()
  local r = 1 * v
  return r
end)
assert(co() == "__mul")
assert(co("resumed") == "resumed")
end

-- ## yield inside __div
do
local v = setmetatable({}, yielding("__div"))
local co = coroutine.wrap(function()
  local r = v / 1
  return r
end)
assert(co() == "__div")
assert(co("resumed") == "resumed")
end

-- ## yield inside __div with the object as right operand
do
local v = setmetatable({}, yielding("__div"))
local co = coroutine.wrap(function()
  local r = 1 / v
  return r
end)
assert(co() == "__div")
assert(co("resumed") == "resumed")
end

-- ## yield inside __mod
do
local v = setmetatable({}, yielding("__mod"))
local co = coroutine.wrap(function()
  local r = v % 1
  return r
end)
assert(co() == "__mod")
assert(co("resumed") == "resumed")
end

-- ## yield inside __mod with the object as right operand
do
local v = setmetatable({}, yielding("__mod"))
local co = coroutine.wrap(function()
  local r = 1 % v
  return r
end)
assert(co() == "__mod")
assert(co("resumed") == "resumed")
end

-- ## yield inside __pow
do
local v = setmetatable({}, yielding("__pow"))
local co = coroutine.wrap(function()
  local r = v ^ 1
  return r
end)
assert(co() == "__pow")
assert(co("resumed") == "resumed")
end

-- ## yield inside __pow with the object as right operand
do
local v = setmetatable({}, yielding("__pow"))
local co = coroutine.wrap(function()
  local r = 1 ^ v
  return r
end)
assert(co() == "__pow")
assert(co("resumed") == "resumed")
end

-- ## yield inside __idiv
do
local v = setmetatable({}, yielding("__idiv"))
local co = coroutine.wrap(function()
  local r = v // 1
  return r
end)
assert(co() == "__idiv")
assert(co("resumed") == "resumed")
end

-- ## yield inside __idiv with the object as right operand
do
local v = setmetatable({}, yielding("__idiv"))
local co = coroutine.wrap(function()
  local r = 1 // v
  return r
end)
assert(co() == "__idiv")
assert(co("resumed") == "resumed")
end

-- ## yield inside __band
do
local v = setmetatable({}, yielding("__band"))
local co = coroutine.wrap(function()
  local r = v & 1
  return r
end)
assert(co() == "__band")
assert(co("resumed") == "resumed")
end

-- ## yield inside __band with the object as right operand
do
local v = setmetatable({}, yielding("__band"))
local co = coroutine.wrap(function()
  local r = 1 & v
  return r
end)
assert(co() == "__band")
assert(co("resumed") == "resumed")
end

-- ## yield inside __bor
do
local v = setmetatable({}, yielding("__bor"))
local co = coroutine.wrap(function()
  local r = v | 1
  return r
end)
assert(co() == "__bor")
assert(co("resumed") == "resumed")
end

-- ## yield inside __bor with the object as right operand
do
local v = setmetatable({}, yielding("__bor"))
local co = coroutine.wrap(function()
  local r = 1 | v
  return r
end)
assert(co() == "__bor")
assert(co("resumed") == "resumed")
end

-- ## yield inside __bxor
do
local v = setmetatable({}, yielding("__bxor"))
local co = coroutine.wrap(function()
  local r = v ~ 1
  return r
end)
assert(co() == "__bxor")
assert(co("resumed") == "resumed")
end

-- ## yield inside __bxor with the object as right operand
do
local v = setmetatable({}, yielding("__bxor"))
local co = coroutine.wrap(function()
  local r = 1 ~ v
  return r
end)
assert(co() == "__bxor")
assert(co("resumed") == "resumed")
end

-- ## yield inside __shl
do
local v = setmetatable({}, yielding("__shl"))
local co = coroutine.wrap(function()
  local r = v << 1
  return r
end)
assert(co() == "__shl")
assert(co("resumed") == "resumed")
end

-- ## yield inside __shl with the object as right operand
do
local v = setmetatable({}, yielding("__shl"))
local co = coroutine.wrap(function()
  local r = 1 << v
  return r
end)
assert(co() == "__shl")
assert(co("resumed") == "resumed")
end

-- ## yield inside __shr
do
local v = setmetatable({}, yielding("__shr"))
local co = coroutine.wrap(function()
  local r = v >> 1
  return r
end)
assert(co() == "__shr")
assert(co("resumed") == "resumed")
end

-- ## yield inside __shr with the object as right operand
do
local v = setmetatable({}, yielding("__shr"))
local co = coroutine.wrap(function()
  local r = 1 >> v
  return r
end)
assert(co() == "__shr")
assert(co("resumed") == "resumed")
end

-- ## yield inside __concat
do
local v = setmetatable({}, yielding("__concat"))
local co = coroutine.wrap(function()
  local r = v .. "x"
  return r
end)
assert(co() == "__concat")
assert(co("resumed") == "resumed")
end

-- ## yield inside __concat with the object as right operand
do
local v = setmetatable({}, yielding("__concat"))
local co = coroutine.wrap(function()
  local r = 1 .. v
  return r
end)
assert(co() == "__concat")
assert(co("resumed") == "resumed")
end

-- ## yield inside __unm
do
local v = setmetatable({}, yielding("__unm"))
local co = coroutine.wrap(function()
  local r = -v
  return r
end)
assert(co() == "__unm")
assert(co("resumed") == "resumed")
end

-- ## yield inside __bnot
do
local v = setmetatable({}, yielding("__bnot"))
local co = coroutine.wrap(function()
  local r = ~v
  return r
end)
assert(co() == "__bnot")
assert(co("resumed") == "resumed")
end

-- ## yield inside __len
do
local v = setmetatable({}, yielding("__len"))
local co = coroutine.wrap(function()
  local r = #v
  return r
end)
assert(co() == "__len")
assert(co("resumed") == "resumed")
end

-- ## yield inside __index
do
local v = setmetatable({}, yielding("__index"))
local co = coroutine.wrap(function()
  local r = v.field
  return r
end)
assert(co() == "__index")
assert(co("resumed") == "resumed")
end

-- ## yield inside __lt evaluating a < b
do
local mt = yielding("__lt")
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local co = coroutine.wrap(function()
  local r = a < b
  return r
end)
assert(co() == "__lt")
assert(co(true) == true)
local co2 = coroutine.wrap(function()
  if a < b then return "then" else return "else" end
end)
assert(co2() == "__lt")
assert(co2(false) == "else")
end

-- ## yield inside __le evaluating a <= b
do
local mt = yielding("__le")
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local co = coroutine.wrap(function()
  local r = a <= b
  return r
end)
assert(co() == "__le")
assert(co(true) == true)
local co2 = coroutine.wrap(function()
  if a <= b then return "then" else return "else" end
end)
assert(co2() == "__le")
assert(co2(false) == "else")
end

-- ## yield inside __eq evaluating a == b
do
local mt = yielding("__eq")
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local co = coroutine.wrap(function()
  local r = a == b
  return r
end)
assert(co() == "__eq")
assert(co(true) == true)
local co2 = coroutine.wrap(function()
  if a == b then return "then" else return "else" end
end)
assert(co2() == "__eq")
assert(co2(false) == "else")
end

-- ## yield inside __lt evaluating a > b
do
local mt = yielding("__lt")
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local co = coroutine.wrap(function()
  local r = a > b
  return r
end)
assert(co() == "__lt")
assert(co(true) == true)
local co2 = coroutine.wrap(function()
  if a > b then return "then" else return "else" end
end)
assert(co2() == "__lt")
assert(co2(false) == "else")
end

-- ## yield inside __le evaluating a >= b
do
local mt = yielding("__le")
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local co = coroutine.wrap(function()
  local r = a >= b
  return r
end)
assert(co() == "__le")
assert(co(true) == true)
local co2 = coroutine.wrap(function()
  if a >= b then return "then" else return "else" end
end)
assert(co2() == "__le")
assert(co2(false) == "else")
end

-- ## yield inside __eq evaluating a ~= b
do
local mt = yielding("__eq")
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local co = coroutine.wrap(function()
  local r = a ~= b
  return r
end)
assert(co() == "__eq")
assert(co(true) == false)
local co2 = coroutine.wrap(function()
  if a ~= b then return "then" else return "else" end
end)
assert(co2() == "__eq")
assert(co2(false) == "then")
end

-- ## yield inside __newindex
do
local store = {}
local t = setmetatable({}, {__newindex = function(_, k, v)
  local override = coroutine.yield("__newindex")
  store[k] = override
end})
local co = coroutine.wrap(function()
  t.a = 1
  return "assigned"
end)
assert(co() == "__newindex")
assert(co("override") == "assigned")
assert(store.a == "override")
end

-- ## yield inside __index reached through a method call
do
local t = setmetatable({}, {__index = function(_, k)
  local f = coroutine.yield("__index")
  return f
end})
local co = coroutine.wrap(function()
  local r = t:method("arg")
  return r
end)
assert(co() == "__index")
assert(co(function(self, a) return a .. "!" end) == "arg!")
end

-- ## yield inside __index of the global environment
do
local env = setmetatable({}, {__index = function(_, k)
  local v = coroutine.yield("env:" .. k)
  return v
end})
local co = coroutine.wrap(function()
  local _ENV = env
  local r = some_global
  return r
end)
assert(co() == "env:some_global")
assert(co("value") == "value")
end

-- ## yield inside __close
do
local log = {}
local co = coroutine.wrap(function()
  do
    local x <close> = setmetatable({}, {__close = function()
      local v = coroutine.yield("__close")
      log[#log + 1] = v
    end})
  end
  log[#log + 1] = "after"
  return "done"
end)
assert(co() == "__close")
assert(#log == 0)
assert(co("closed") == "done")
assert(log[1] == "closed" and log[2] == "after")
end

-- ## several yields inside one metamethod
do
local v = setmetatable({}, {__add = function(a, b)
  local x = coroutine.yield("first")
  local y = coroutine.yield("second")
  return x + y
end})
local co = coroutine.wrap(function()
  local r = v + 1
  return r
end)
assert(co() == "first")
assert(co(10) == "second")
assert(co(5) == 15)
end

-- ## metamethod yields in the middle of a larger expression
do
local v = setmetatable({}, {__mul = function(a, b)
  local x = coroutine.yield("mul")
  return x
end})
local co = coroutine.wrap(function()
  local r = 1 + v * 2 + 3
  return r
end)
assert(co() == "mul")
assert(co(10) == 14)
end

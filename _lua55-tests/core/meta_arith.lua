-- Metatables: arithmetic and bitwise metamethods.
local T = tostring

-- builds a value whose metamethods record the event and operands
local function tracker()
  local log = {}
  local mt = {}
  for _, ev in ipairs{"add", "sub", "mul", "div", "mod", "pow", "idiv",
                      "band", "bor", "bxor", "shl", "shr"} do
    mt["__" .. ev] = function(a, b)
      log[#log + 1] = ev
      return ev, a, b
    end
  end
  mt.__unm = function(a, b) log[#log + 1] = "unm"; return "unm", a, b end
  mt.__bnot = function(a, b) log[#log + 1] = "bnot"; return "bnot", a, b end
  return setmetatable({}, mt), log, mt
end

-- ## every arithmetic operator has its metamethod
do
local v = tracker()
assert(v + 1 == "add")
assert(v - 1 == "sub")
assert(v * 1 == "mul")
assert(v / 1 == "div")
assert(v % 1 == "mod")
assert(v ^ 1 == "pow")
assert(v // 1 == "idiv")
assert(-v == "unm")
end

-- ## every bitwise operator has its metamethod
do
local v = tracker()
assert(v & 1 == "band")
assert(v | 1 == "bor")
assert(v ~ 1 == "bxor")
assert(v << 1 == "shl")
assert(v >> 1 == "shr")
assert(~v == "bnot")
end

-- ## the metamethod is found on the right operand too
do
local v = tracker()
assert(1 + v == "add")
assert(1 - v == "sub")
assert(1 * v == "mul")
assert(1 / v == "div")
assert(1 % v == "mod")
assert(1 ^ v == "pow")
assert(1 // v == "idiv")
assert(1 & v == "band")
assert(1 | v == "bor")
assert(1 ~ v == "bxor")
assert(1 << v == "shl")
assert(1 >> v == "shr")
assert("str" + v == "add")
assert(1.5 & v == "band")
assert("str" | v == "bor")
end

-- ## operands are passed in their original order
do
local mt = {__sub = function(a, b) return {a, b} end, __shl = function(a, b) return {a, b} end,
            __idiv = function(a, b) return {a, b} end}
local v = setmetatable({}, mt)
local r = v - 5
assert(r[1] == v and r[2] == 5)
r = 5 - v
assert(r[1] == 5 and r[2] == v)
r = v << "x"
assert(r[1] == v and r[2] == "x")
r = 2.5 << v
assert(r[1] == 2.5 and r[2] == v)
r = nil // v
assert(r[1] == nil and r[2] == v)
r = v // nil
assert(r[1] == v and r[2] == nil)
end

-- ## the first operand's metamethod has priority
do
local a = setmetatable({}, {__add = function() return "a" end})
local b = setmetatable({}, {__add = function() return "b" end})
local c = setmetatable({}, {})
assert(a + b == "a")
assert(b + a == "b")
assert(a + c == "a")
assert(c + a == "a")
assert(c + b == "b")
assert(not pcall(function() return c + c end))
assert(not pcall(function() return c + 1 end))
end

-- ## unary metamethods receive the operand twice
do
local got = {}
local v = setmetatable({}, {
  __unm = function(...) got.unm = {n = select("#", ...), ...}; return 1 end,
  __bnot = function(...) got.bnot = {n = select("#", ...), ...}; return 2 end,
})
assert(-v == 1)
assert(~v == 2)
assert(got.unm.n == 2 and got.unm[1] == v and got.unm[2] == v)
assert(got.bnot.n == 2 and got.bnot[1] == v and got.bnot[2] == v)
end

-- ## results are adjusted to one value
do
local v = setmetatable({}, {__add = function() return 1, 2, 3 end, __sub = function() end,
                            __unm = function() return 1, 2 end})
assert(select("#", v + 1) == 1)
local x, y = v + 1
assert(x == 1 and y == nil)
assert(v - 1 == nil)
assert(select("#", v - 1) == 1)
assert(select("#", -v) == 1)
local t = {v + 1, v + 1}
assert(#t == 2)
end

-- ## metamethods can return any value
do
local v = setmetatable({}, {__add = function() return false end, __mul = function() return v end,
                            __band = function() return "string" end, __div = function() return nil end})
assert((v + 1) == false)
assert((v & 1) == "string")
assert((v / 1) == nil)
end

-- ## numbers never use metamethods when both operands are numbers
do
local calls = 0
local v = setmetatable({}, {__add = function(a, b) calls = calls + 1; return 0 end})
assert(1 + 2 == 3)
assert(calls == 0)
assert(v + 2 == 0)
assert(calls == 1)
end

-- ## strings convertible to numbers do not reach the other operand's arithmetic metamethod
do
-- only when both are numbers or numeric strings
local v = setmetatable({}, {__add = function(a, b) return "meta" end})
assert("10" + 1 == 11)
assert("10" + v == "meta")
assert(v + "10" == "meta")
assert("abc" + v == "meta")
end

-- ## bitwise metamethods are used for non-integral floats and strings
do
local v = setmetatable({}, {__band = function(a, b) return "band" end, __shl = function() return "shl" end,
                            __bnot = function() return "bnot" end})
assert(1.5 & v == "band")
assert(v & 1.5 == "band")
assert("3" & v == "band")
assert(v << "x" == "shl")
assert(~v == "bnot")
end

-- ## missing metamethods raise an error
do
local plain = setmetatable({}, {})
assert(not pcall(function() return plain + 1 end))
assert(not pcall(function() return plain - 1 end))
assert(not pcall(function() return plain * 1 end))
assert(not pcall(function() return plain / 1 end))
assert(not pcall(function() return plain % 1 end))
assert(not pcall(function() return plain ^ 1 end))
assert(not pcall(function() return plain // 1 end))
assert(not pcall(function() return -plain end))
assert(not pcall(function() return plain & 1 end))
assert(not pcall(function() return plain | 1 end))
assert(not pcall(function() return plain ~ 1 end))
assert(not pcall(function() return plain << 1 end))
assert(not pcall(function() return plain >> 1 end))
assert(not pcall(function() return ~plain end))
local onlyadd = setmetatable({}, {__add = function() return 1 end})
assert(not pcall(function() return onlyadd - 1 end))
assert(not pcall(function() return onlyadd // 1 end))
assert(not pcall(function() return onlyadd & 1 end))
assert(not pcall(function() return -onlyadd end))
end

-- ## __idiv, __mod, __div and __pow are independent
do
local v = setmetatable({}, {__div = function() return "div" end})
assert(v / 2 == "div")
assert(not pcall(function() return v // 2 end))
assert(not pcall(function() return v % 2 end))
local w = setmetatable({}, {__idiv = function() return "idiv" end})
assert(w // 2 == "idiv")
assert(not pcall(function() return w / 2 end))
local s = setmetatable({}, {__sub = function() return "sub" end})
assert(s - 1 == "sub")
assert(not pcall(function() return -s end))
local sh = setmetatable({}, {__shl = function() return "shl" end})
assert(sh << 1 == "shl")
assert(not pcall(function() return sh >> 1 end))
local bx = setmetatable({}, {__bxor = function() return "bxor" end})
assert(bx ~ 1 == "bxor")
assert(not pcall(function() return ~bx end))
end

-- ## metamethods that are not functions
do
local callable = setmetatable({}, {__call = function(self, a, b) return "called" end})
local v = setmetatable({}, {__add = callable, __sub = 42})
assert(not pcall(function() return v - 1 end))
end

-- ## errors inside metamethods propagate
do
local v = setmetatable({}, {__add = function() error("add failed", 0) end})
local ok, err = pcall(function() return v + 1 end)
assert(not ok and err == "add failed")
end

-- ## a small value type: 2D vectors
do
local Vec = {}
Vec.__index = Vec
local function vec(x, y) return setmetatable({x = x, y = y}, Vec) end
Vec.__add = function(a, b) return vec(a.x + b.x, a.y + b.y) end
Vec.__sub = function(a, b) return vec(a.x - b.x, a.y - b.y) end
Vec.__mul = function(a, b)
  if type(a) == "number" then return vec(a * b.x, a * b.y) end
  if type(b) == "number" then return vec(a.x * b, a.y * b) end
  return a.x * b.x + a.y * b.y
end
Vec.__unm = function(a) return vec(-a.x, -a.y) end
Vec.__idiv = function(a, n) return vec(a.x // n, a.y // n) end
Vec.__mod = function(a, n) return vec(a.x % n, a.y % n) end
local a, b = vec(1, 2), vec(3, 4)
local s = a + b
assert(s.x == 4 and s.y == 6)
local d = b - a
assert(d.x == 2 and d.y == 2)
assert(a * b == 11)
local m = 2 * a
assert(m.x == 2 and m.y == 4)
local m2 = a * 3
assert(m2.x == 3 and m2.y == 6)
local n = -a
assert(n.x == -1 and n.y == -2)
local q = vec(7, 9) // 2
assert(T(q.x) == "3" and T(q.y) == "4")
local r = vec(7, 9) % 4
assert(r.x == 3 and r.y == 1)
local chain = a + b + a + b
assert(chain.x == 8 and chain.y == 12)
local mix = (a + b) * 2 - a
assert(mix.x == 7 and mix.y == 10)
end

-- ## metamethods on the string metatable
do
local smt = getmetatable("")
local old_shl = smt.__shl
smt.__shl = function(a, b) return "str-shl" end
local ok, res = pcall(function() return "a" << 1 end)
local ok2, res2 = pcall(function() return 1 << "a" end)
smt.__shl = old_shl
assert(ok and res == "str-shl")
assert(ok2 and res2 == "str-shl")
end

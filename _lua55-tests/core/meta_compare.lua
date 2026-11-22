-- Metatables: __eq, __lt and __le.

-- ## __eq is used for two different tables
do
local calls = 0
local mt = {__eq = function(a, b) calls = calls + 1; return a.v == b.v end}
local a, b, c = setmetatable({v = 1}, mt), setmetatable({v = 1}, mt), setmetatable({v = 2}, mt)
assert(a == b)
assert(calls == 1)
assert(a ~= c)
assert(calls == 2)
assert(not (a ~= b))
assert(not (a == c))
assert(calls == 4)
end

-- ## __eq is not called for raw-equal values
do
local calls = 0
local a = setmetatable({}, {__eq = function() calls = calls + 1; return false end})
assert(a == a)
assert(not (a ~= a))
assert(calls == 0)
local alias = a
assert(a == alias)
assert(calls == 0)
end

-- ## __eq is not called when the types differ or for non-tables
do
local calls = 0
local a = setmetatable({}, {__eq = function() calls = calls + 1; return true end})
assert(a ~= 1)
assert(1 ~= a)
assert(a ~= "x")
assert(a ~= nil)
assert(nil ~= a)
assert(a ~= true)
assert(a ~= print)
assert(not (a == 1))
assert(not (a == nil))
assert(calls == 0)
end

-- ## __eq is tried on the first operand, then on the second
do
local order = {}
local a = setmetatable({}, {__eq = function() order[#order + 1] = "a"; return true end})
local b = setmetatable({}, {__eq = function() order[#order + 1] = "b"; return true end})
local plain = {}
assert(a == b)
assert(b == a)
assert(a == plain)
assert(plain == a)
assert(plain == b)
assert(table.concat(order, ",") == "a,b,a,a,b")
assert(plain ~= {})
end

-- ## different metatables with different __eq still compare
do
local a = setmetatable({}, {__eq = function() return true end})
local b = setmetatable({}, {__eq = function() return false end})
assert(a == b)
assert(not (b == a))
assert(b ~= a)
end

-- ## the result of __eq is converted to a boolean
do
local function eqmt(result) return {__eq = function() return result end} end
local function eqres(result)
  local a, b = setmetatable({}, eqmt(result)), setmetatable({}, eqmt(result))
  return a == b, a ~= b
end
local e, n = eqres(1)
assert(e == true and n == false)
e, n = eqres("string")
assert(e == true and n == false)
e, n = eqres({})
assert(e == true and n == false)
e, n = eqres(0)
assert(e == true and n == false)
e, n = eqres(nil)
assert(e == false and n == true)
e, n = eqres(false)
assert(e == false and n == true)
local a, b = setmetatable({}, {__eq = function() return 1, 2, 3 end}), {}
assert((a == b) == true)
assert(select("#", a == b) == 1)
end

-- ## __eq receives the operands in order
do
local got
local mt = {__eq = function(x, y) got = {x, y}; return true end}
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local _ = a == b
assert(got[1] == a and got[2] == b)
_ = b == a
assert(got[1] == b and got[2] == a)
_ = a ~= b
assert(got[1] == a and got[2] == b)
end

-- ## __eq does not affect table keys or rawequal
do
local mt = {__eq = function() return true end}
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local t = {}
t[a] = "a"
assert(t[b] == nil)
assert(not rawequal(a, b))
assert(a == b)
end

-- ## __lt
do
local mt = {__lt = function(a, b) return a.v < b.v end}
local one, two = setmetatable({v = 1}, mt), setmetatable({v = 2}, mt)
assert(one < two)
assert(not (two < one))
assert(two > one)
assert(not (one > two))
assert(not (one < one))
end

-- ## __le is independent of __lt
do
local lt_only = {__lt = function(a, b) return a.v < b.v end}
local a, b = setmetatable({v = 1}, lt_only), setmetatable({v = 2}, lt_only)
assert(a < b)
assert(not pcall(function() return a <= b end))
assert(not pcall(function() return a >= b end))
local le_only = {__le = function(a, b) return a.v <= b.v end}
local c, d = setmetatable({v = 1}, le_only), setmetatable({v = 2}, le_only)
assert(c <= d)
assert(d >= c)
assert(c <= c)
assert(not (d <= c))
assert(not pcall(function() return c < d end))
assert(not pcall(function() return c > d end))
end

-- ## a > b is b < a and a >= b is b <= a
do
local got
local mt = {
  __lt = function(x, y) got = {"lt", x, y}; return true end,
  __le = function(x, y) got = {"le", x, y}; return true end,
}
local a, b = setmetatable({}, mt), setmetatable({}, mt)
local _ = a < b
assert(got[1] == "lt" and got[2] == a and got[3] == b)
_ = a > b
assert(got[1] == "lt" and got[2] == b and got[3] == a)
_ = a <= b
assert(got[1] == "le" and got[2] == a and got[3] == b)
_ = a >= b
assert(got[1] == "le" and got[2] == b and got[3] == a)
end

-- ## order metamethods work with mixed operand types
do
local mt = {
  __lt = function(x, y)
    local xv = type(x) == "table" and x.v or x
    local yv = type(y) == "table" and y.v or y
    return xv < yv
  end,
  __le = function(x, y)
    local xv = type(x) == "table" and x.v or x
    local yv = type(y) == "table" and y.v or y
    return xv <= yv
  end,
}
local five = setmetatable({v = 5}, mt)
assert(five < 10)
assert(1 < five)
assert(not (five < 5))
assert(five <= 5)
assert(5 <= five)
assert(five > 1)
assert(10 > five)
assert(five >= 5)
assert(not (five >= 6))
assert(not (10 < five))
end

-- ## the first operand's order metamethod has priority
do
local a = setmetatable({}, {__lt = function() return true end})
local b = setmetatable({}, {__lt = function() return false end})
assert(a < b)
assert(not (b < a))
assert(b > a)
assert(not (a > b))
assert(a < {})
assert({} < a)
assert(not ({} < b))
end

-- ## results of order metamethods are converted to booleans
do
local mt = {__lt = function() return "yes" end, __le = function() return nil end}
local a, b = setmetatable({}, mt), setmetatable({}, mt)
assert((a < b) == true)
assert((a <= b) == false)
assert((a > b) == true)
assert((a >= b) == false)
local mt0 = {__lt = function() return 0 end, __le = function() return false, true end}
local c, d = setmetatable({}, mt0), setmetatable({}, mt0)
assert((c < d) == true)
assert((c <= d) == false)
end

-- ## numbers and strings never use order metamethods among themselves
do
local calls = 0
local smt = getmetatable("")
smt.__lt = function() calls = calls + 1; return true end
local ok1, r1 = pcall(function() return "b" < "a" end)
local ok2 = pcall(function() return "a" < 1 end)
smt.__lt = nil
assert(ok1 and r1 == false)
assert(calls == 1)
assert(ok2)
end

-- ## missing order metamethods raise an error
do
local plain = setmetatable({}, {})
assert(not pcall(function() return plain < plain end))
assert(not pcall(function() return plain <= plain end))
assert(not pcall(function() return plain < 1 end))
assert(not pcall(function() return 1 < plain end))
assert(not pcall(function() return plain > "x" end))
assert(not pcall(function() return {} < {} end))
assert(not pcall(function() return {} >= {} end))
local eq_only = setmetatable({}, {__eq = function() return true end})
assert(not pcall(function() return eq_only < eq_only end))
assert(not pcall(function() return eq_only <= eq_only end))
end

-- ## comparisons in conditions and loops
do
local mt = {__lt = function(a, b) return a.v < b.v end, __le = function(a, b) return a.v <= b.v end,
            __eq = function(a, b) return a.v == b.v end}
local function num(v) return setmetatable({v = v}, mt) end
local items = {num(3), num(1), num(2)}
local min = items[1]
for i = 2, #items do
  if items[i] < min then min = items[i] end
end
assert(min.v == 1)
local count = 0
local i = num(0)
while i < num(3) do count = count + 1; i = num(i.v + 1) end
assert(count == 3)
assert(num(2) == num(2) and num(2) ~= num(3))
local r = (num(1) < num(2)) and "lt" or "ge"
assert(r == "lt")
local function max(a, b) if a >= b then return a else return b end end
assert(max(num(4), num(9)).v == 9)
end

-- ## sorting with a comparison that uses __lt
do
local mt = {__lt = function(a, b) return a.v < b.v end}
local list = {}
for _, v in ipairs{5, 2, 8, 1, 9, 3} do list[#list + 1] = setmetatable({v = v}, mt) end
table.sort(list)
local out = {}
for i, x in ipairs(list) do out[i] = x.v end
assert(table.concat(out, ",") == "1,2,3,5,8,9")
end

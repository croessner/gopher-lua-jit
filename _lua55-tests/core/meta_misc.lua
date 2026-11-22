-- Metatables: __concat, __len, __tostring, __name, __gc and __mode.
local T = tostring

-- ## __concat with a table on either side
do
local mt = {__concat = function(a, b)
  local av = type(a) == "table" and a.v or a
  local bv = type(b) == "table" and b.v or b
  return av .. "|" .. bv
end}
local x, y = setmetatable({v = "x"}, mt), setmetatable({v = "y"}, mt)
assert(x .. y == "x|y")
assert(x .. "s" == "x|s")
assert("s" .. x == "s|x")
assert(x .. 1 == "x|1")
assert(1 .. x == "1|x")
assert(1.5 .. x == "1.5|x")
end

-- ## concatenation is right associative when metamethods are involved
do
local log = {}
local mt = {}
mt.__concat = function(a, b)
  local av = type(a) == "table" and a.v or a
  local bv = type(b) == "table" and b.v or b
  log[#log + 1] = av .. "+" .. bv
  return setmetatable({v = "(" .. av .. bv .. ")"}, mt)
end
local a, b, c = setmetatable({v = "a"}, mt), setmetatable({v = "b"}, mt), setmetatable({v = "c"}, mt)
local r = a .. b .. c
assert(r.v == "(a(bc))")
assert(log[1] == "b+c" and log[2] == "a+(bc)")
log = {}
r = "s" .. "t" .. a
assert(r.v == "(s(ta))")
log = {}
r = a .. "s" .. "t"
assert(r.v == "(ast)")
assert(#log == 1)
end

-- ## __concat results and operand order
do
local got
local v = setmetatable({}, {__concat = function(l, r) got = {l, r}; return 1, 2 end})
local res = v .. "right"
assert(res == 1)
assert(got[1] == v and got[2] == "right")
res = "left" .. v
assert(got[1] == "left" and got[2] == v)
assert(select("#", v .. "x") == 1)
local nilres = setmetatable({}, {__concat = function() end})
assert((nilres .. "x") == nil)
end

-- ## the first operand's __concat has priority
do
local a = setmetatable({}, {__concat = function() return "a" end})
local b = setmetatable({}, {__concat = function() return "b" end})
assert(a .. b == "a")
assert(b .. a == "b")
assert({} .. a == "a")
assert(a .. {} == "a")
end

-- ## __concat is not used for strings and numbers
do
local calls = 0
local smt = getmetatable("")
smt.__concat = function() calls = calls + 1; return "meta" end
local ok, r = pcall(function() return "a" .. "b" .. 1 end)
smt.__concat = nil
assert(ok and r == "ab1")
assert(calls == 0)
end

-- ## missing __concat raises an error
do
assert(not pcall(function() return {} .. "x" end))
assert(not pcall(function() return "x" .. {} end))
assert(not pcall(function() return setmetatable({}, {}) .. "x" end))
assert(not pcall(function() return nil .. "x" end))
assert(not pcall(function() return "x" .. true end))
end

-- ## __len
do
local v = setmetatable({1, 2, 3}, {__len = function(self) return 42 end})
assert(#v == 42)
assert(rawlen == nil or rawlen(v) == 3)
local got
local w = setmetatable({}, {__len = function(...) got = {n = select("#", ...), ...}; return 0 end})
assert(#w == 0)
assert(got[1] == w)
end

-- ## __len may return any value, adjusted to one result
do
local s = setmetatable({}, {__len = function() return "long" end})
assert(#s == "long")
local n = setmetatable({}, {__len = function() return nil end})
assert(#n == nil)
local m = setmetatable({}, {__len = function() return 1, 2, 3 end})
assert(#m == 1)
assert(select("#", #m) == 1)
local f = setmetatable({}, {__len = function() return 2.5 end})
assert(#f == 2.5)
local e = setmetatable({}, {__len = function() end})
assert(#e == nil)
end

-- ## __len on values that have no primitive length
do
local smt = getmetatable("")
smt.__len = function() return "ignored" end
local ok, len = pcall(function() return #"abc" end)
smt.__len = nil
assert(ok and len == 3)
end

-- ## __len and ipairs/table functions are independent of the raw contents
do
local proxy = setmetatable({}, {__len = function() return 3 end, __index = function(_, i) return i * 10 end})
assert(#proxy == 3)
local sum = 0
for i = 1, #proxy do sum = sum + proxy[i] end
assert(sum == 60)
end

-- ## __tostring
do
local v = setmetatable({}, {__tostring = function(self) return "custom" end})
assert(tostring(v) == "custom")
local got
local w = setmetatable({}, {__tostring = function(...) got = select("#", ...); return "w" end})
assert(tostring(w) == "w")
assert(got == 1)
assert(not pcall(tostring, setmetatable({}, {__tostring = function() return nil end})))
assert(not pcall(tostring, setmetatable({}, {__tostring = function() return {} end})))
assert(not pcall(tostring, setmetatable({}, {__tostring = function() error("x") end})))
assert(tostring(setmetatable({}, {__tostring = function() return "a", "b" end})) == "a")
end

-- ## __tostring is not used by concatenation
do
local v = setmetatable({}, {__tostring = function() return "custom" end})
assert(not pcall(function() return "x" .. v end))
assert(not pcall(function() return v .. "x" end))
end

-- ## __name appears in the default string form
do
local v = setmetatable({}, {__name = "MyType"})
assert(tostring(v):sub(1, 8) == "MyType: ")
local plain = {}
assert(tostring(plain):sub(1, 7) == "table: ")
local non_string_name = setmetatable({}, {__name = 42})
assert(tostring(non_string_name):sub(1, 7) == "table: ")
local both = setmetatable({}, {__name = "N", __tostring = function() return "T" end})
assert(tostring(both) == "T")
end

-- ## default string forms
do
assert(tostring(nil) == "nil")
assert(tostring(true) == "true")
assert(tostring(false) == "false")
assert(tostring(12) == "12")
assert(tostring(12.0) == "12.0")
assert(tostring("s") == "s")
assert(tostring(print):sub(1, 9) == "function:" or tostring(print):sub(1, 8) == "builtin:")
assert(tostring(function() end):sub(1, 10) == "function: ")
assert(tostring(coroutine.create(function() end)):sub(1, 8) == "thread: ")
local t1, t2 = {}, {}
assert(tostring(t1) ~= tostring(t2))
assert(tostring(t1) == tostring(t1))
end

-- ## __gc and __mode fields do not disturb normal operation
do
local log = {}
local v = setmetatable({}, {__gc = function() log[#log + 1] = "gc" end})
v.x = 1
assert(v.x == 1)
v = nil
local weak = setmetatable({}, {__mode = "k"})
local key = {}
weak[key] = "value"
assert(weak[key] == "value")
local weakv = setmetatable({}, {__mode = "v"})
weakv[1] = key
assert(weakv[1] == key)
local weakkv = setmetatable({}, {__mode = "kv"})
weakkv.a = 1
assert(weakkv.a == 1)
local odd = setmetatable({}, {__gc = 42, __mode = 7})
odd.x = 1
assert(odd.x == 1)
end

-- ## unknown fields in a metatable are ignored
do
local v = setmetatable({}, {__unknown = function() error("never") end, __foo = 1, other = 2})
v.a = 1
assert(v.a == 1 and v.b == nil)
assert(getmetatable(v).other == 2)
end

-- ## a metatable shared by a family of values
do
local mt = {}
mt.__index = mt
mt.__tostring = function(self) return "obj#" .. self.id end
mt.__eq = function(a, b) return a.id == b.id end
mt.__lt = function(a, b) return a.id < b.id end
mt.__le = function(a, b) return a.id <= b.id end
mt.__len = function(self) return self.id end
mt.__call = function(self, x) return self.id + x end
mt.__concat = function(a, b) return tostring(a) .. tostring(b) end
mt.__add = function(a, b) return setmetatable({id = a.id + b.id}, mt) end
mt.__unm = function(a) return setmetatable({id = -a.id}, mt) end
local function obj(id) return setmetatable({id = id}, mt) end
local o1, o2 = obj(1), obj(2)
assert(tostring(o1) == "obj#1")
assert(o1 == obj(1) and o1 ~= o2)
assert(o1 < o2 and o1 <= o2 and o2 > o1 and o2 >= o1)
assert(#o2 == 2)
assert(o2(10) == 12)
assert(o1 .. o2 == "obj#1obj#2")
assert(o1 .. "!" == "obj#1!")
assert(tostring(o1 + o2) == "obj#3")
assert(tostring(-o2) == "obj#-2")
assert(#(o1 + o2 + o2) == 5)
end

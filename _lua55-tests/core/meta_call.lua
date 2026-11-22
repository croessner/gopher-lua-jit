-- Metatables: __call.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## a table with __call can be called
do
local obj = setmetatable({}, {__call = function(self, a, b) return a + b end})
assert(obj(1, 2) == 3)
assert(type(obj) == "table")
end

-- ## the called object is passed as first argument
do
local got
local obj = setmetatable({}, {__call = function(...) got = {n = select("#", ...), ...}; return "r" end})
assert(obj() == "r")
assert(got.n == 1 and got[1] == obj)
obj("a", nil, "c")
assert(got.n == 4 and got[1] == obj and got[2] == "a" and got[3] == nil and got[4] == "c")
end

-- ## all results are returned
do
local obj = setmetatable({}, {__call = function(self, ...) return ... end})
assert(show(obj()) == "")
assert(show(obj(1, 2, 3)) == "1,2,3")
assert(show(obj(nil, nil)) == "nil,nil")
assert(show((obj(1, 2, 3))) == "1")
assert(#{obj(1, 2, 3)} == 3)
local a, b = obj(1, 2, 3)
assert(a == 1 and b == 2)
end

-- ## varargs and multiple results as arguments
do
local obj = setmetatable({}, {__call = function(self, ...) return select("#", ...) end})
local function mr() return 1, 2, 3 end
assert(obj(mr()) == 3)
assert(obj(mr(), mr()) == 4)
assert(obj((mr())) == 1)
local function fwd(...) return obj(...) end
assert(fwd() == 0)
assert(fwd(nil, nil) == 2)
end

-- ## method call syntax on callable fields
do
local holder = {callable = setmetatable({}, {__call = function(self, recv, x) return recv, x end})}
local r, x = holder:callable(5)
assert(r == holder and x == 5)
assert(holder.callable(1, 2) == 1)
end

-- ## callable objects in tail calls
do
local counter = setmetatable({}, {__call = function(self, n, acc)
  if n == 0 then return acc end
  return self(n - 1, acc + 1)
end})
assert(counter(100000, 0) == 100000)
local function tail(o, ...) return o(...) end
assert(tail(counter, 10, 0) == 10)
end

-- ## callable objects where functions are expected
do
local adder = setmetatable({}, {__call = function(self, a, b) return a + b end})
local ok, res = pcall(adder, 2, 3)
assert(ok and res == 5)
local co = coroutine.wrap(function(...) return adder(...) end)
assert(co(4, 5) == 9)
local keyfn = setmetatable({}, {__call = function(self, a, b) return a > b end})
local list = {3, 1, 2}
table.sort(list, function(a, b) return keyfn(a, b) end)
assert(list[1] == 3 and list[3] == 1)
end

-- ## callable objects used as metamethod handlers
do
local idx = setmetatable({}, {__call = function(self, tbl, key) return "idx:" .. key end})
local t = setmetatable({}, {__index = function(tbl, key) return idx(tbl, key) end})
assert(t.foo == "idx:foo")
end

-- ## values without __call cannot be called
do
assert(not pcall(function() local t = {}; t() end))
assert(not pcall(function() local t = setmetatable({}, {}); t() end))
assert(not pcall(function() local t = setmetatable({}, {__call = 5}); t() end))
assert(not pcall(function() local t = setmetatable({}, {__call = "str"}); t() end))
assert(not pcall(function() local t = setmetatable({}, {__index = {__call = print}}); t() end))
assert(not pcall(function() local n = 1; n() end))
assert(not pcall(function() ("str")() end))
assert(not pcall(function() local b = true; b() end))
end

-- ## a __call loop does not crash
do
local loop = setmetatable({}, {})
getmetatable(loop).__call = loop
assert(not pcall(function() loop() end))
end

-- ## errors inside __call propagate
do
local bad = setmetatable({}, {__call = function() error("call failed", 0) end})
local ok, err = pcall(bad)
assert(not ok and err == "call failed")
ok, err = pcall(function() return bad() end)
assert(not ok and err == "call failed")
end

-- ## constructors implemented with __call
do
local Point = setmetatable({}, {__call = function(cls, x, y)
  return setmetatable({x = x, y = y}, cls)
end})
Point.__index = Point
function Point:sum() return self.x + self.y end
local p = Point(3, 4)
assert(p.x == 3 and p.y == 4)
assert(p:sum() == 7)
assert(getmetatable(p) == Point)
end

-- ## functions with metatables are still called directly
do
local mt = getmetatable(print)
assert(mt == nil)
local s = setmetatable({}, {__call = function(self, x) return x * 2 end})
assert(s(21) == 42)
assert((s)(1) == 2)
assert(({s})[1](5) == 10)
end

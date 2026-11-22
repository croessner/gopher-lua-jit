-- Functions: method calls, self and call syntax.
local load = loadstring or load

-- ## colon definitions add an implicit self parameter
do
local obj = {value = 10}
function obj:get() return self.value end
function obj:add(n) self.value = self.value + n; return self end
function obj.static(x) return x end
assert(obj:get() == 10)
assert(obj.get(obj) == 10)
assert(obj:add(5):add(5):get() == 20)
assert(obj.static(7) == 7)
assert(obj:static() == obj)
assert(obj.get({value = "other"}) == "other")
end

-- ## the receiver is evaluated once
do
local obj = {value = 10}
function obj:get() return self.value end
function obj:add(n) self.value = self.value + n; return self end
local evals = 0
local function recv() evals = evals + 1; return obj end
recv():get()
assert(evals == 1)
recv():add(1):add(1)
assert(evals == 2)
end

-- ## methods found through __index
do
local Class = {}
Class.__index = Class
function Class.new(v) return setmetatable({v = v}, Class) end
function Class:get() return self.v end
function Class:set(v) self.v = v; return self end
local a, b = Class.new(1), Class.new(2)
assert(a:get() == 1)
assert(b:get() == 2)
assert(a:set(10):get() == 10)
assert(b:get() == 2)
assert(rawget(a, "get") == nil)
end

-- ## inheritance chains
do
local Base = {}
Base.__index = Base
function Base:name() return "base" end
function Base:hello() return "hello from " .. self:name() end
local Derived = setmetatable({}, {__index = Base})
Derived.__index = Derived
function Derived:name() return "derived" end
local d = setmetatable({}, Derived)
assert(d:hello() == "hello from derived")
assert(setmetatable({}, Base):hello() == "hello from base")
end

-- ## method calls on strings
do
local s = "hello"
assert(s:len() == 5)
assert(s:upper() == "HELLO")
assert(("x"):rep(3) == "xxx")
assert(s:sub(2, 3) == "el")
assert(#s:rep(2) == 10)
assert(("%d"):format(5) == "5")
end

-- ## call syntax with string and table literals
do
local function id(...) return ... end
assert(id"a" == "a")
assert(id'a' == "a")
assert(id[[a]] == "a")
assert(id{1, 2}[2] == 2)
local o = {m = function(self, arg) return arg end}
assert(o:m"str" == "str")
assert(o:m{5}[1] == 5)
assert(o:m[[long]] == "long")
assert(id"a" .. id"b" == "ab")
end

-- ## chained calls and indexing
do
local function ret_t() return {f = function() return {g = function() return "deep" end} end} end
assert(ret_t().f().g() == "deep")
assert(ret_t()["f"]()["g"]() == "deep")
local curry = function(a) return function(b) return function(c) return a + b + c end end end
assert(curry(1)(2)(3) == 6)
assert(({10, 20, 30})[2] == 20)
assert(({f = function() return 1 end}).f() == 1)
assert(("abc"):len() == 3)
end

-- ## self is an ordinary local
do
local t = {}
function t:m()
  local old = self
  self = "replaced"
  return old, self
end
local r1, r2 = t:m()
assert(r1 == t and r2 == "replaced")
local function plain(self, x) return self, x end
assert(select("#", plain(1, 2)) == 2)
end

-- ## method call on values without that method raises an error
do
assert(not pcall(function() local t = {}; t:nope() end))
assert(not pcall(function() local n = 5; n:nope() end))
assert(not pcall(function() local n = nil; n:nope() end))
assert(not pcall(function() ("x"):nope() end))
assert(not pcall(function() local b = true; b:nope() end))
end

-- ## method call syntax
do
assert(load("a:b()") ~= nil)
assert(load("a:b'x'") ~= nil)
assert(load("a:b{}") ~= nil)
assert(load("a.b:c():d()") ~= nil)
assert(load("a:b") == nil)
assert(load("a:b.c()") == nil)
assert(load("a:1()") == nil)
assert(load("a::b()") == nil)
assert(load("local x = a:b") == nil)
assert(load("a:end()") == nil)
assert(load("return ('x'):rep(2)") ~= nil)
assert(load("return 'x':rep(2)") == nil)
assert(load("return {}:m()") == nil)
assert(load("return 5:m()") == nil)
end

-- ## __index on the receiver is consulted for the method only
do
local log = {}
local proxy = setmetatable({}, {__index = function(t, k)
  log[#log + 1] = k
  return function(self, x) return k .. ":" .. tostring(x) end
end})
assert(proxy:foo(1) == "foo:1")
assert(proxy:bar(2) == "bar:2")
assert(table.concat(log, ",") == "foo,bar")
end

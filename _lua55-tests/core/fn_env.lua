-- Functions: _ENV as upvalue, local and parameter.
local load = loadstring or load

-- ## free names are fields of _ENV
do
ENV_TEST_A = 5
assert(_ENV.ENV_TEST_A == 5)
_ENV.ENV_TEST_B = 6
assert(ENV_TEST_B == 6)
assert(_ENV["ENV_TEST_A"] == 5)
ENV_TEST_A, ENV_TEST_B = nil, nil
assert(_ENV.ENV_TEST_A == nil)
assert(_ENV == _G)
assert(_ENV._G == _G)
assert(_G._G == _G)
assert(type(_ENV) == "table")
assert(_ENV.print == print)
assert(_ENV.undefined_name_xyz == nil)
assert(undefined_name_xyz == nil)
end

-- ## a local _ENV redirects free names
do
local print, assert, tostring = print, assert, tostring
do
  local _ENV = {x = 1}
  assert(x == 1)
  y = 2
  assert(_ENV.y == 2)
  assert(type == nil)
  x = x + 10
  assert(_ENV.x == 11)
end
assert(y == nil)
assert(x == nil)
end

-- ## functions capture the _ENV visible at their definition
do
local assert, setmetatable = assert, setmetatable
local env1, env2 = {v = "one"}, {v = "two"}
local f1, f2
do
  local _ENV = env1
  f1 = function() return v end
end
do
  local _ENV = env2
  f2 = function() return v end
end
assert(f1() == "one")
assert(f2() == "two")
env1.v = "uno"
assert(f1() == "uno")
end

-- ## _ENV as a parameter
do
local assert = assert
local function getv(_ENV) return v end
assert(getv({v = 1}) == 1)
assert(getv({v = "x"}) == "x")
assert(getv({}) == nil)
local function setv(_ENV, val) v = val end
local e = {}
setv(e, 42)
assert(e.v == 42)
local function both(_ENV) a = 1; b = a + 1; return b end
local e2 = {}
assert(both(e2) == 2)
assert(e2.a == 1 and e2.b == 2)
end

-- ## assigning to _ENV changes the environment of later code
do
local assert, G = assert, _G
local function swap_env()
  local saved = _ENV
  _ENV = {marker = "new"}
  local m = marker
  _ENV = saved
  return m
end
assert(swap_env() == "new")
assert(marker == nil)
end

-- ## an upvalue _ENV shared between closures
do
local assert = assert
local function make()
  local _ENV = {count = 0}
  local function inc() count = count + 1 end
  local function get() return count end
  local function reset(e) _ENV = e end
  return inc, get, reset
end
local inc, get, reset = make()
inc()
inc()
assert(get() == 2)
reset({count = 100})
inc()
assert(get() == 101)
end

-- ## _ENV with a metatable
do
local assert, setmetatable, rawget, G = assert, setmetatable, rawget, _G
do
  local log = {}
  local _ENV = setmetatable({}, {
    __index = function(_, k) log[#log + 1] = "get:" .. k; return G[k] end,
    __newindex = function(t, k, v) log[#log + 1] = "set:" .. k; rawset(t, k, v) end,
  })
  newvar = 1
  local _ = newvar
  local _ = othervar
  assert(log[1] == "set:newvar")
  assert(log[2] == "get:othervar")
  assert(#log == 2)
  assert(rawget(_ENV, "newvar") == 1)
end
end

-- ## setting _ENV to a non-table makes global access fail
do
local assert, pcall = assert, pcall
assert(not pcall(function() local _ENV = nil; return x end))
assert(not pcall(function() local _ENV = nil; x = 1 end))
assert(not pcall(function() local _ENV = 5; return x end))
assert(pcall(function() local _ENV = {}; return x end))
assert(pcall(function() local _ENV = "str"; return len end))
assert((function() local _ENV = "str"; return len end)() == string.len)
end

-- ## chunks loaded with load share the global environment
do
ENV_SHARED = "shared"
local f = load("return ENV_SHARED")
assert(f() == "shared")
local g = load("ENV_SHARED2 = 'set by chunk'")
g()
assert(ENV_SHARED2 == "set by chunk")
ENV_SHARED, ENV_SHARED2 = nil, nil
local h = load("local _ENV = {z = 3}; return z")
assert(h() == 3)
local k = load("return _ENV")
assert(k() == _G)
end

-- ## _ENV is an ordinary name
do
local assert = assert
local function f()
  local _ENV <const> = {a = 1}
  return a
end
assert(f() == 1)
do
  local e = _ENV
  local _ENV = {e = e}
  e.assert(_ENV.e == e)
end
assert(load("local _ENV <const> = {}; _ENV = nil") == nil)
assert(load("_ENV = {}") ~= nil)
assert(load("local function f(_ENV, _ENV) end") ~= nil)
assert(load("for _ENV in pairs({}) do x = 1 end") ~= nil)
end

-- ## _ENV as a for loop variable
do
local assert, pairs = assert, pairs
local seen = {}
for _, _ENV in pairs({{id = "a"}, {id = "b"}}) do
  seen[#seen + 1] = id
end
assert(#seen == 2)
assert((seen[1] == "a" and seen[2] == "b") or (seen[1] == "b" and seen[2] == "a"))
end

-- ## global functions are stored in _ENV
do
local assert = assert
do
  local _ENV = {}
  function defined_here() return "here" end
  assert(_ENV.defined_here() == "here")
  function _ENV.also_here() return 1 end
  assert(also_here() == 1)
end
assert(defined_here == nil)
end

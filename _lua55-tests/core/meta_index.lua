-- Metatables: __index, __newindex and metatable management.

-- ## setmetatable and getmetatable
do
local t, mt = {}, {}
assert(getmetatable(t) == nil)
assert(setmetatable(t, mt) == t)
assert(getmetatable(t) == mt)
assert(setmetatable(t, nil) == t)
assert(getmetatable(t) == nil)
assert(not pcall(setmetatable, t, 1))
assert(not pcall(setmetatable, t, "x"))
assert(getmetatable("").__index == string)
assert(getmetatable(1) == nil)
assert(getmetatable(nil) == nil)
assert(getmetatable(print) == nil)
assert(getmetatable(true) == nil)
end

-- ## __metatable protects the metatable
do
local t = setmetatable({}, {__metatable = "locked"})
assert(getmetatable(t) == "locked")
assert(not pcall(setmetatable, t, {}))
assert(not pcall(setmetatable, t, nil))
local t2 = setmetatable({}, {__metatable = false})
assert(getmetatable(t2) == false)
assert(not pcall(setmetatable, t2, {}))
end

-- ## __index as a table
do
local base = {a = 1, b = 2}
local t = setmetatable({b = "own"}, {__index = base})
assert(t.a == 1)
assert(t.b == "own")
assert(t.c == nil)
assert(rawget(t, "a") == nil)
base.c = 3
assert(t.c == 3)
t.a = "shadow"
assert(t.a == "shadow")
assert(base.a == 1)
end

-- ## __index as a function
do
local log = {}
local t = setmetatable({present = 1}, {__index = function(tbl, key)
  log[#log + 1] = key
  return "dyn:" .. tostring(key)
end})
assert(t.present == 1)
assert(#log == 0)
assert(t.missing == "dyn:missing")
assert(t[1] == "dyn:1")
assert(t[2.5] == "dyn:2.5")
assert(#log == 3)
local recv
local t3 = setmetatable({}, {__index = function(tbl, key) recv = tbl; return nil end})
assert(t3.x == nil)
assert(recv == t3)
end

-- ## __index function results are adjusted to one value
do
local t = setmetatable({}, {__index = function() return 1, 2, 3 end})
local a, b = t.x
assert(a == 1 and b == nil)
local t = setmetatable({}, {__index = function() end})
assert(t.x == nil)
assert(select("#", t.x) == 1)
end

-- ## __index chains
do
local a = {x = "a"}
local b = setmetatable({y = "b"}, {__index = a})
local c = setmetatable({z = "c"}, {__index = b})
local d = setmetatable({}, {__index = c})
assert(d.x == "a" and d.y == "b" and d.z == "c" and d.w == nil)
local e = setmetatable({}, {__index = setmetatable({}, {__index = function(_, k) return k .. "!" end})})
assert(e.foo == "foo!")
end

-- ## __index with a stored false or nil value
do
local t = setmetatable({f = false}, {__index = function() return "meta" end})
assert(t.f == false)
t.f = nil
assert(t.f == "meta")
end

-- ## __index on non-table values through a shared metatable
do
local smt = getmetatable("")
local old = smt.__index
smt.__index = function(s, k) return k == "twice" and (s .. s) or old[k] end
local ok, v = pcall(function() return ("ab").twice end)
local ok2, len = pcall(function() return ("ab"):len() end)
smt.__index = old
assert(ok and v == "abab")
assert(ok2 and len == 2)
end

-- ## __newindex as a function
do
local store = {}
local t = setmetatable({existing = 1}, {__newindex = function(tbl, k, v) store[k] = v end})
t.new = "value"
assert(rawget(t, "new") == nil)
assert(store.new == "value")
t.existing = 2
assert(t.existing == 2)
assert(store.existing == nil)
t[1] = "one"
assert(store[1] == "one")
assert(#t == 0)
end

-- ## __newindex as a table
do
local target = {}
local t = setmetatable({}, {__newindex = target})
t.a = 1
assert(rawget(t, "a") == nil)
assert(target.a == 1)
local final = {}
local mid = setmetatable({}, {__newindex = final})
local top = setmetatable({}, {__newindex = mid})
top.k = "v"
assert(rawget(top, "k") == nil and rawget(mid, "k") == nil and final.k == "v")
end

-- ## __newindex is skipped for existing keys but not for nil-valued ones
do
local calls = 0
local t = setmetatable({a = 1}, {__newindex = function(tbl, k, v) calls = calls + 1; rawset(tbl, k, v) end})
t.a = 2
assert(calls == 0)
t.b = 1
assert(calls == 1)
t.b = 2
assert(calls == 1)
t.b = nil
t.b = 3
assert(calls == 2)
end

-- ## read-only tables and default values
do
local function readonly(tbl)
  return setmetatable({}, {__index = tbl, __newindex = function() error("read-only table", 2) end})
end
local ro = readonly({x = 1})
assert(ro.x == 1)
assert(not pcall(function() ro.x = 2 end))
assert(not pcall(function() ro.y = 2 end))
assert(ro.x == 1)
local defaults = setmetatable({}, {__index = function() return 0 end})
defaults.a = defaults.a + 1
defaults.a = defaults.a + 1
assert(defaults.a == 2)
assert(defaults.b == 0)
end

-- ## proxies and tracking
do
local reads, writes = 0, 0
local backing = {}
local proxy = setmetatable({}, {
  __index = function(_, k) reads = reads + 1; return backing[k] end,
  __newindex = function(_, k, v) writes = writes + 1; backing[k] = v end,
})
proxy.a = 1
proxy.b = 2
proxy.a = proxy.a + proxy.b
assert(backing.a == 3)
assert(reads == 2)
assert(writes == 3)
end

-- ## metamethods looked up with raw access in the metatable
do
local mt = setmetatable({}, {__index = function(_, k)
  if k == "__index" then return function() return "should not be used" end end
end})
local t = setmetatable({}, mt)
assert(t.x == nil)
end

-- ## a metatable can be its own __index
do
local Class = {}
Class.__index = Class
function Class.new() return setmetatable({}, Class) end
function Class:hello() return "hello" end
local obj = Class.new()
assert(obj:hello() == "hello")
assert(getmetatable(obj) == Class)
assert(obj.__index == Class)
end

-- ## __index loops are detected
do
local a = {}
setmetatable(a, {__index = a})
assert(not pcall(function() return a.x end))
local n1, n2 = {}, {}
setmetatable(n1, {__index = n2})
setmetatable(n2, {__index = n1})
assert(not pcall(function() return n1.x end))
local w = {}
setmetatable(w, {__newindex = w})
assert(pcall(function() w.x = 1 end) == false or rawget(w, "x") == 1)
end

-- ## indexing with __index on values that are not tables
do
assert(not pcall(function() local n = 5; return n.x end))
assert(not pcall(function() local n = 5; n.x = 1 end))
end

-- ## metatables are shared between tables
do
local mt = {__index = {shared = true}}
local a, b = setmetatable({}, mt), setmetatable({}, mt)
assert(a.shared and b.shared)
mt.__index.shared = "changed"
assert(a.shared == "changed" and b.shared == "changed")
mt.__index = nil
assert(a.shared == nil)
end

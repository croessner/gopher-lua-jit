-- getmetatable and setmetatable.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

-- getmetatable
assert(getmetatable({}) == nil)
assert(getmetatable(1) == nil and getmetatable(print) == nil and getmetatable(nil) == nil)
assert(getmetatable("").__index == string)
local mt = {}
local obj = setmetatable({}, mt)
assert(getmetatable(obj) == mt)
checkerr("value expected", getmetatable)

-- __metatable hides the real metatable
assert(getmetatable(setmetatable({}, {__metatable = "locked"})) == "locked")
assert(getmetatable(setmetatable({}, {__metatable = false})) == false)
assert(getmetatable(setmetatable({}, {__metatable = 0})) == 0)

-- setmetatable returns its first argument and accepts nil
assert(setmetatable(obj, nil) == obj and getmetatable(obj) == nil)
assert(setmetatable(obj, mt) == obj and getmetatable(obj) == mt)
local t = {}
assert(select("#", setmetatable(t, {}, {})) == 1)   -- extra arguments are ignored

-- a protected metatable cannot be changed
local protected = setmetatable({}, {__metatable = 1})
checkerr("cannot change a protected metatable", setmetatable, protected, {})
checkerr("cannot change a protected metatable", setmetatable, protected, nil)
assert(getmetatable(protected) == 1)
-- a false __metatable field also protects
checkerr("cannot change a protected metatable", setmetatable, setmetatable({}, {__metatable = false}), {})

-- argument checks
checkerr("nil or table expected", setmetatable, {}, 1)
checkerr("nil or table expected", setmetatable, {})
checkerr("table expected, got number", setmetatable, 1, {})
checkerr("table expected, got string", setmetatable, "str", {})
checkerr("table expected, got nil", setmetatable, nil, {})
checkerr("table expected, got no value", setmetatable)

-- metamethods installed through setmetatable are honoured
local v = setmetatable({}, {
  __index = function(_, k) return k .. "!" end,
  __call = function(_, x) return x * 2 end,
  __len = function() return 42 end,
  __unm = function() return "neg" end,
  __concat = function(a, b) return "cat" end,
})
assert(v.key == "key!" and v(21) == 42 and #v == 42 and -v == "neg" and v .. "x" == "cat")

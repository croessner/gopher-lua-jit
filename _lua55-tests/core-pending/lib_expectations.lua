-- Standard library behaviour the core language tests would like to rely
-- on. These checks concern the library (not the language core); the failing
-- ones are recorded in core-pending for the library owners.
local T = tostring

-- ## load accepts a string chunk
do
local f = load("return 1 + 1")
assert(f() == 2)
end

-- ## math.huge is positive infinity
do
assert(math.huge == 1 / 0)
assert(-math.huge == -1 / 0)
assert(math.huge > 1.7976931348623157e308)
assert(T(math.huge) == "inf")
end

-- ## math.floor returns an integer when the result fits
do
assert(T(math.floor(3.7)) == "3")
assert(T(math.floor(-3.7)) == "-4")
assert(T(math.floor(5)) == "5")
end

-- ## tonumber keeps the integer subtype
do
assert(T(tonumber("10")) == "10")
assert(T(tonumber(5)) == "5")
assert(T(tonumber("0x10")) == "16")
assert(T(tonumber("  12  ")) == "12")
assert(T(tonumber("1e1")) == "10.0")
end

-- ## string arithmetic coercion is provided by string metamethods
do
local mt = getmetatable("")
assert(type(mt.__add) == "function")
assert(type(mt.__unm) == "function")
assert(type(mt.__idiv) == "function")
end

-- ## _VERSION names the language version
do
assert(_VERSION == "Lua 5.5")
end

-- ## integer limits are exported by the math library
do
assert(math.maxinteger == 9223372036854775807)
assert(math.mininteger == -9223372036854775807 - 1)
assert(math.type(1) == "integer")
assert(math.type(1.0) == "float")
assert(math.type("1") == nil)
end

-- ## rawequal compares numbers by value across subtypes
do
assert(rawequal(1, 1.0))
assert(rawequal(2^53, 9007199254740992))
end

-- ## ipairs yields integer indices
do
for i, v in ipairs({"a", "b"}) do
  assert(T(i) == (v == "a" and "1" or "2"))
end
end

-- ## select with a numeric index
do
assert(select(1, "a", "b", "c") == "a")
assert((select(2, "a", "b", "c")) == "b")
assert(select(3, "a", "b", "c") == "c")
assert(select("#", select(2, "a", "b", "c")) == 2)
assert(select(-1, "a", "b", "c") == "c")
assert(select(-2, "a", "b", "c") == "b")
assert(not pcall(select, 0, "a"))
assert(not pcall(select, -2, "a"))
end

-- ## select("#") returns an integer
do
assert(T(select("#", 1, 2)) == "2")
end

-- ## setmetatable only accepts tables as first argument
do
assert(not pcall(setmetatable, 1, {}))
assert(not pcall(setmetatable, "s", {}))
end

-- ## rawset returns the table
do
local t = {}
assert(rawset(t, "y", 2) == t)
end

-- ## next rejects keys that are not in the table
do
assert(not pcall(next, {}, "missing key"))
end

-- ## table.concat handles long lists
do
local t = {}
for i = 1, 6000 do t[i] = "x" end
assert(#table.concat(t) == 6000)
end

-- ## tostring accepts a number returned by __tostring
do
assert(tostring(setmetatable({}, {__tostring = function() return 1 end})) == "1")
end

-- ## coroutine.running returns the main coroutine and a flag
do
local main, ismain = coroutine.running()
assert(type(main) == "thread")
assert(ismain == true)
local co
co = coroutine.create(function()
  local running, m = coroutine.running()
  return running == co, m
end)
local ok, same, m = coroutine.resume(co)
assert(ok and same == true and m == false)
end

-- ## tonumber accepts exponents without a fractional part
do
assert(tonumber("1e1") == 10)
assert(tonumber("1e+64") == 1e64)
assert(tonumber("5e-324") == 5e-324)
assert(tonumber("1E2") == 100)
end

-- ## pairs honours __pairs
do
local t = setmetatable({}, {__pairs = function(tbl)
  return function(_, k) if not k then return 1, "one" end end, tbl, nil
end})
local n = 0
for k, v in pairs(t) do n = n + 1; assert(k == 1 and v == "one") end
assert(n == 1)
end

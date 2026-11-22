-- Standard library behaviour the core language tests would like to rely
-- on. These checks concern the library (not the language core); the failing
-- ones are recorded in core-pending for the library owners.
local T = tostring

-- ## tonumber keeps the integer subtype
do
assert(T(tonumber("10.0")) == "10.0")
assert(T(tonumber(5.0)) == "5.0")
end

-- ## string arithmetic coercion is provided by string metamethods
do
local mt = getmetatable("")
assert(mt.__band == nil)
assert(mt.__index == string)
end

-- ## rawequal compares numbers by value across subtypes
do
assert(not rawequal(1, 1.5))
end

-- ## select with a numeric index
do
assert(select("#", select(4, "a", "b", "c")) == 0)
end

-- ## setmetatable only accepts tables as first argument
do
assert(not pcall(setmetatable, nil, {}))
end

-- ## tonumber accepts exponents without a fractional part
do
assert(tonumber(".5e1") == 5)
end

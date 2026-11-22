-- Arithmetic: integer versus float results of the arithmetic operators.
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1
local inf = 1 / 0

-- ## addition, subtraction and multiplication keep integers
do
assert(T(1 + 2) == "3")
assert(T(1 - 2) == "-1")
assert(T(3 * 4) == "12")
assert(T(-3 * 4) == "-12")
assert(T(0 * -1) == "0")
assert(T(1 + 2.0) == "3.0")
assert(T(1.0 + 2) == "3.0")
assert(T(1.5 + 1.5) == "3.0")
assert(T(1 - 2.0) == "-1.0")
assert(T(3 * 4.0) == "12.0")
assert(T(3.0 * 4) == "12.0")
assert(T(0.5 * 4) == "2.0")
assert(T(0 * -1.0) == "-0.0")
assert(T(0.0 * -1) == "-0.0")
end

-- ## float division and exponentiation always produce floats
do
assert(T(4 / 2) == "2.0")
assert(T(1 / 2) == "0.5")
assert(T(7 / 2) == "3.5")
assert(T(-7 / 2) == "-3.5")
assert(T(0 / 5) == "0.0")
assert(T(4.0 / 2.0) == "2.0")
assert(T(2 ^ 2) == "4.0")
assert(T(2 ^ 0) == "1.0")
assert(T(2 ^ -1) == "0.5")
assert(T(4 ^ 0.5) == "2.0")
assert(T(0 ^ 0) == "1.0")
assert(T((-2) ^ 2) == "4.0")
assert(T((-2) ^ 3) == "-8.0")
assert(T(2 ^ 62) == "4.6116860184273879e+18")
assert(T(10 ^ 2) == "100.0")
assert(2 ^ 53 == 9007199254740992)
assert(T(2 ^ 1024) == "inf")
assert(T(-(2 ^ 1024)) == "-inf")
end

-- ## floor division and modulo keep integers
do
assert(T(7 // 2) == "3")
assert(T(7 % 2) == "1")
assert(T(7 // 2.0) == "3.0")
assert(T(7.0 // 2) == "3.0")
assert(T(7 % 2.0) == "1.0")
assert(T(7.0 % 2) == "1.0")
assert(T(7.5 // 2) == "3.0")
assert(T(7.5 % 2) == "1.5")
assert(T(6 // 3) == "2")
assert(T(6 % 3) == "0")
assert(T(6.0 % 3) == "0.0")
end

-- ## unary minus
do
assert(T(-(1)) == "-1")
assert(T(-(1.0)) == "-1.0")
assert(T(-(0)) == "0")
assert(T(-(0.0)) == "-0.0")
assert(T(- -1) == "1")
assert(T(-(-1.5)) == "1.5")
local i, f = 5, 5.0
assert(T(-i) == "-5")
assert(T(-f) == "-5.0")
assert(T(-inf) == "-inf")
assert(T(-(-inf)) == "inf")
end

-- ## integer wrap-around
do
assert(maxint + 1 == minint)
assert(minint - 1 == maxint)
assert(maxint * 2 == -2)
assert(minint * 2 == 0)
assert(minint * -1 == minint)
assert(-minint == minint)
assert(maxint + maxint == -2)
assert(minint + minint == 0)
assert(T(maxint + 1) == "-9223372036854775808")
assert(T(maxint * maxint) == "1")
assert(T(minint * minint) == "0")
assert(T(maxint * 3) == "9223372036854775805")
assert(4611686018427387904 * 2 == minint)
assert(4611686018427387904 * 4 == 0)
assert(3037000500 * 3037000500 == -9223372036709301616)
assert(maxint - (-1) == minint)
assert(0 - minint == minint)
end

-- ## wrap-around with runtime operands (no constant folding)
do
local a, b = maxint, 1
assert(a + b == minint)
assert(T(a + b) == "-9223372036854775808")
local c = minint
assert(c - b == maxint)
assert(-c == c)
assert(c * -1 == c)
assert(a * a == 1)
assert(a * 2 == -2)
assert(c // -1 == c)
assert(c % -1 == 0)
end

-- ## mixed operations convert the integer operand to float
do
assert(maxint + 0.0 == 2 ^ 63)
assert(T(maxint + 0.0) == "9.2233720368547758e+18")
assert(minint + 0.0 == -(2 ^ 63))
assert(maxint + 1.0 == 2 ^ 63)
assert(T(maxint * 1.0) == "9.2233720368547758e+18")
assert(maxint / 1 == 2 ^ 63)
assert(T(maxint / 1) == "9.2233720368547758e+18")
assert(T(2 ^ 63) == "9.2233720368547758e+18")
assert(T(9007199254740993 + 0.0) == "9007199254740992.0")
end

-- ## the float value of an operation
do
assert(0.1 + 0.2 ~= 0.3)
assert(0.1 + 0.2 == 0.30000000000000004)
assert(T(0.1 + 0.2) == "0.30000000000000004")
assert(0.5 + 0.25 == 0.75)
assert(1e308 * 10 == inf)
assert(-1e308 * 10 == -inf)
assert(1e-320 / 1e10 == 0)
assert(T(1 / 3) == "0.33333333333333331")
assert(T(2 / 3) == "0.66666666666666663")
assert(T(100 / 3) == "33.333333333333336")
assert(T(1e15 + 0.5) == "1000000000000000.5")
assert(T(3.14) == "3.14")
end

-- ## float formatting through tostring
do
assert(T(1.0) == "1.0")
assert(T(-1.0) == "-1.0")
assert(T(1.5) == "1.5")
assert(T(1e15) == "1e+15")
assert(T(1e14) == "100000000000000.0")
assert(T(123456789012345.0) == "123456789012345.0")
assert(T(1e16) == "1e+16")
assert(T(1e-5) == "1e-05")
assert(T(0.0001) == "0.0001")
assert(T(1e-4) == "0.0001")
assert(T(5e-324) == "4.94065645841247e-324")
assert(T(1.7976931348623157e308) == "1.7976931348623157e+308")
assert(T(2^24) == "16777216.0")
assert(T(-0.0) == "-0.0")
assert(T(0.0) == "0.0")
assert(T(inf) == "inf")
assert(T(-inf) == "-inf")
assert(T(255 // 1) == "255")
assert(T(1e2 // 1) == "100.0")
end

-- ## infinities and NaN
do
local nan = 0 / 0
assert(nan ~= nan)
assert(not (nan == nan))
assert(not (nan < nan))
assert(not (nan <= nan))
assert(not (nan > 0))
assert(not (nan < 0))
assert(not (nan >= 0))
assert(not (nan == 0))
assert(nan ~= 0)
assert(inf == inf)
assert(inf > maxint)
assert(-inf < minint)
assert(inf + 1 == inf)
assert(inf - inf ~= inf - inf)
assert(inf * 0 ~= inf * 0)
assert(inf / inf ~= inf / inf)
assert(1 / inf == 0)
assert(1 / -inf == 0)
assert(T(1 / -inf) == "-0.0")
assert(-0.0 == 0.0)
assert(0.0 == -0.0)
assert(1 / 0.0 == inf)
assert(1 / -0.0 == -inf)
assert(1 / 0 == inf)
assert(-1 / 0 == -inf)
assert(0.0 / 0.0 ~= 0.0 / 0.0)
assert(2 ^ inf == inf)
assert(2 ^ -inf == 0)
assert(1 ^ inf == 1)
assert((0 / 0) ^ 0 == 1)
local n2 = nan + 1
assert(n2 ~= n2)
end

-- ## arithmetic on non-numbers raises an error
do
assert(not pcall(function() return 1 + nil end))
assert(not pcall(function() return nil + 1 end))
assert(not pcall(function() return {} + 1 end))
assert(not pcall(function() return 1 - true end))
assert(not pcall(function() return "a" + 1 end))
assert(not pcall(function() return 1 * "x" end))
assert(not pcall(function() return -{} end))
assert(not pcall(function() return -"abc" end))
assert(not pcall(function() return -nil end))
assert(not pcall(function() return 2 ^ {} end))
assert(not pcall(function() return print / 2 end))
assert(not pcall(function() return 1 // false end))
assert(not pcall(function() return 1 % {} end))
end

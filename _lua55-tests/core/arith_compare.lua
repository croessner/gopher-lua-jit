-- Arithmetic: comparison of integers and floats, including the 2^53 and
-- 2^63 boundaries where a float cannot represent every integer.
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1
local inf = 1 / 0
local nan = 0 / 0

-- ## equality across subtypes
do
assert(1 == 1.0)
assert(1.0 == 1)
assert(0 == 0.0)
assert(0 == -0.0)
assert(-1 == -1.0)
assert(not (1 ~= 1.0))
assert(1 ~= 1.5)
assert(2^53 == 9007199254740992)
assert(9007199254740992 == 2^53)
assert(1e15 == 1000000000000000)
assert(255 == 0xff)
assert(255.0 == 0xff)
assert(16 == 0x1p4)
assert(not rawequal(1, 1.5))
assert(not rawequal(1, "1"))
end

-- ## equality near 2^53 is exact
do
assert(9007199254740993 ~= 2^53)
assert(2^53 ~= 9007199254740993)
assert(9007199254740993 ~= 9007199254740992.0)
assert(9007199254740993 ~= 9007199254740994.0)
assert(9007199254740993 ~= 9007199254740993.0)
assert(9007199254740992 == 9007199254740993.0)
assert(9007199254740993 + 0.0 == 2^53)
assert(-9007199254740993 ~= -(2^53))
assert(2^53 + 1 == 2^53)
assert(9007199254740992 + 1 ~= 9007199254740992)
end

-- ## order near 2^53 is exact
do
assert(9007199254740993 > 2^53)
assert(2^53 < 9007199254740993)
assert(9007199254740993 >= 2^53)
assert(2^53 <= 9007199254740993)
assert(not (9007199254740993 <= 2^53))
assert(not (2^53 >= 9007199254740993))
assert(9007199254740993 < 9007199254740994.0)
assert(9007199254740994.0 > 9007199254740993)
assert(-9007199254740993 < -(2^53))
assert(-(2^53) > -9007199254740993)
assert(9007199254740991 < 2^53)
assert(not (9007199254740992 < 2^53))
assert(9007199254740992 <= 2^53)
end

-- ## equality near 2^63
do
assert(maxint ~= 2^63)
assert(2^63 ~= maxint)
assert(maxint + 0.0 == 2^63)
assert(minint == -(2^63))
assert(-(2^63) == minint)
assert(minint + 0.0 == -(2^63))
assert(maxint ~= maxint + 0.0)
assert(maxint - 1023 ~= 2^63)
assert(9223372036854774784 == 9223372036854774784.0)
assert(9223372036854774785 ~= 9223372036854774784.0)
end

-- ## order near 2^63
do
assert(maxint < 2^63)
assert(2^63 > maxint)
assert(maxint <= 2^63)
assert(2^63 >= maxint)
assert(not (maxint >= 2^63))
assert(not (2^63 <= maxint))
assert(not (maxint > 2^63))
assert(not (2^63 < maxint))
assert(maxint < maxint + 0.0)
assert(maxint + 0.0 > maxint)
assert(minint <= -(2^63))
assert(minint >= -(2^63))
assert(not (minint < -(2^63)))
assert(not (minint > -(2^63)))
assert(minint > -(2^63) - 2048)
assert(-(2^63) - 2048 < minint)
assert(minint + 1 > -(2^63))
assert(maxint < 2^64)
assert(minint > -(2^64))
assert(maxint < 1e300)
assert(minint > -1e300)
assert(9223372036854774784.0 < maxint)
assert(maxint > 9223372036854774784.0)
end

-- ## order near 2^63 with runtime operands
do
local big, fbig = maxint, 2^63
assert(big < fbig)
assert(big <= fbig)
assert(not (big >= fbig))
assert(not (big > fbig))
assert(fbig > big)
assert(fbig >= big)
assert(big ~= fbig)
local small, fsmall = minint, -(2^63)
assert(small == fsmall)
assert(small <= fsmall)
assert(small >= fsmall)
assert(not (small < fsmall))
end

-- ## infinities and NaN against integers
do
assert(maxint < inf)
assert(minint > -inf)
assert(inf > maxint)
assert(-inf < minint)
assert(maxint <= inf)
assert(not (maxint >= inf))
assert(not (maxint == inf))
assert(maxint ~= inf)
assert(not (1 < nan))
assert(not (1 > nan))
assert(not (1 <= nan))
assert(not (1 >= nan))
assert(not (1 == nan))
assert(1 ~= nan)
assert(not (nan < 1))
assert(not (nan > 1))
assert(not (maxint < nan))
assert(not (minint > nan))
assert(not (nan <= maxint))
assert(not (nan >= minint))
end

-- ## ordinary order
do
assert(1 < 2)
assert(1 < 2.0)
assert(1.0 < 2)
assert(1.5 < 2)
assert(2 > 1.5)
assert(-1 < 1)
assert(-1.5 < -1)
assert(1 <= 1.0)
assert(1.0 >= 1)
assert(not (1 < 1.0))
assert(not (1.0 > 1))
assert(0 <= -0.0)
assert(0 >= -0.0)
assert(not (0 < -0.0))
assert(minint < maxint)
assert(minint < 0)
assert(maxint > 0)
assert(0.1 < 1)
assert(-0.1 > -1)
assert(1 > 0.9999999999999999)
end

-- ## mixed type comparisons
do
assert(1 ~= "1")
assert("1" ~= 1)
assert(0 ~= false)
assert(nil ~= false)
assert(0 ~= nil)
assert("" ~= nil)
assert({} ~= {})
assert(not pcall(function() return 1 < "2" end))
assert(not pcall(function() return "1" < 2 end))
assert(not pcall(function() return nil < 1 end))
assert(not pcall(function() return 1 < nil end))
assert(not pcall(function() return {} < {} end))
assert(not pcall(function() return true < false end))
assert(not pcall(function() return 1 <= {} end))
assert(not pcall(function() return print > print end))
assert(not pcall(function() return nil >= nil end))
assert(not pcall(function() return 1.5 < "x" end))
end

-- ## comparisons as values
do
local lt, eq = 1 < 2, 1 == 2
assert(lt == true)
assert(eq == false)
assert(type(1 < 2) == "boolean")
assert((1 < 2) ~= (2 < 1))
local function cmp(a, b) return a < b, a <= b, a > b, a >= b, a == b, a ~= b end
local a, b, c, d, e, f = cmp(1, 2.0)
assert(a and b and not c and not d and not e and f)
a, b, c, d, e, f = cmp(2^53, 9007199254740993)
assert(a and b and not c and not d and not e and f)
a, b, c, d, e, f = cmp(3, 3.0)
assert(not a and b and not c and d and e and not f)
end

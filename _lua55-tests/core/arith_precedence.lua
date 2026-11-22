-- Arithmetic: operator precedence and associativity.
-- Precedence, lowest to highest:
--   or; and; comparison; |; ~; &; shift; ..; + -; * / // %; unary; ^
local load = loadstring or load
local T = tostring

-- ## multiplicative binds tighter than additive
do
assert(1 + 2 * 3 == 7)
assert(2 * 3 + 1 == 7)
assert(10 - 4 / 2 == 8)
assert(10 - 7 // 2 == 7)
assert(10 + 7 % 4 == 13)
assert((1 + 2) * 3 == 9)
assert(2 * 3 % 4 == 2)
assert(2 * (3 % 4) == 6)
assert(7 // 2 * 2 == 6)
assert(7 // (2 * 2) == 1)
assert(8 / 2 / 2 == 2)
assert(8 / (2 / 2) == 8)
assert(10 - 3 - 2 == 5)
assert(10 - (3 - 2) == 9)
assert(100 // 7 // 2 == 7)
assert(100 % 7 % 2 == 0)
end

-- ## exponentiation is right associative and binds tighter than unary
do
assert(2 ^ 3 ^ 2 == 512)
assert((2 ^ 3) ^ 2 == 64)
assert(-2 ^ 2 == -4)
assert((-2) ^ 2 == 4)
assert(2 ^ -1 == 0.5)
assert(2 ^ -2 ^ 2 == 2 ^ -4)
assert(-2 ^ -2 == -0.25)
assert(2 * 3 ^ 2 == 18)
assert(2 ^ 2 * 3 == 12)
assert(not 2 ^ 2 == false)
assert(not pcall(function() return #"ab" ^ 2 end))
assert(-3 ^ 2 == -9)
assert(~2 ^ 2 == -5)
assert(- - 2 ^ 2 == 4)
assert(2 ^ 3 ^ 0 == 2)
end

-- ## unary operators bind tighter than binary ones (except ^)
do
assert(-2 + 3 == 1)
assert(-2 * 3 == -6)
assert(- 2 - 3 == -5)
assert(-2 // 3 == -1)
assert(-7 % 3 == 2)
assert(not 1 == 2 == false)
assert(not (1 == 2))
assert(#"abc" + 1 == 4)
assert(#"abc" * 2 == 6)
assert(-#"abc" == -3)
assert(~1 + 1 == -1)
assert(~(1 + 1) == -3)
assert(not nil == true)
assert(not not nil == false)
assert(- - - 1 == -1)
assert(~ ~ ~ 1 == -2)
assert(-~1 == 2)
assert(~-1 == 0)
assert(#"abc" .. "d" == "3d")
end

-- ## concatenation is right associative, below additive, above shifts
do
assert("a" .. "b" .. "c" == "abc")
assert(1 + 2 .. "" == "3")
assert("" .. 1 + 2 == "3")
assert(1 .. 2 + 3 == "15")
assert(2 * 3 .. 4 * 5 == "620")
assert("1" .. "2" + 1 == "13")
assert(T(1 .. 2 == "12") == "true")
assert("a" .. "b" == "a" .. "b")
assert(not pcall(function() return 1 .. 0 << 1 end))
assert(not pcall(function() return 1 << 1 .. 0 end))
assert(-1 .. -1 == "-1-1")
end

-- ## shifts are left associative, below additive and concatenation
do
assert(1 << 2 + 1 == 8)
assert((1 << 2) + 1 == 5)
assert(1 + 1 << 2 == 8)
assert(1 << 2 << 3 == 32)
assert(256 >> 2 >> 1 == 32)
assert(256 >> (2 >> 1) == 128)
assert(1 << 3 >> 1 == 4)
assert(2 * 2 << 1 == 8)
assert(1 << 2 * 2 == 16)
assert(16 >> 1 - 1 == 16)
end

-- ## & binds tighter than ~, which binds tighter than |
do
assert(1 | 2 & 3 == 3)
assert((1 | 2) & 3 == 3)
assert(1 | 2 ~ 3 == 1)
assert((1 | 2) ~ 3 == 0)
assert(6 ~ 3 & 5 == 7)
assert((6 ~ 3) & 5 == 5)
assert(4 | 2 ~ 2 & 3 == 4)
assert(1 & 3 << 1 == 0)
assert((1 & 3) << 1 == 2)
assert(1 | 1 << 1 == 3)
assert(7 ~ 1 << 2 == 3)
assert(8 | 4 | 2 | 1 == 15)
assert(15 & 7 & 3 == 3)
assert(15 ~ 7 ~ 3 == 11)
assert(1 & 2 + 1 == 1)
assert(5 & 3 * 2 == 4)
assert(~0 & 1 == 1)
assert(- 1 & 3 == 3)
end

-- ## comparison is below the bitwise operators
do
assert(1 | 2 == 3)
assert(3 & 1 == 1)
assert(1 ~ 1 == 0)
assert((1 | 2 == 3) == true)
assert(1 << 2 == 4)
assert(1 + 1 == 2)
assert(1 .. 1 == "11")
assert(2 < 1 + 2)
assert(1 + 2 > 2)
assert(1 | 2 < 4)
assert(4 > 1 | 2)
assert(1 ~= 1 | 2)
assert(3 >= 1 | 2)
assert(1 << 1 <= 2)
end

-- ## comparison chains are left associative
do
assert((1 < 2) == true)
assert(1 < 2 == true)
assert((1 == 1) ~= false)
assert(1 == 1 ~= false)
assert(1 == 1 == true)
assert((1 > 2 == false) == true)
assert(not pcall(function() return 1 < 2 < 3 end))
assert(true == (1 < 2))
end

-- ## and binds tighter than or; both short-circuit
do
assert((true or false and false) == true)
assert(((true or false) and false) == false)
assert((false and false or true) == true)
assert((false and (false or true)) == false)
assert((nil or 1 and 2) == 2)
assert((1 and nil or 3) == 3)
assert((1 or error("not evaluated")) == 1)
assert((nil and error("not evaluated")) == nil)
assert((false or nil) == nil)
assert((nil or false) == false)
assert((1 and 2 and 3) == 3)
assert((1 and false and 3) == false)
assert((nil or nil or 3) == 3)
assert((1 == 1 and 2 == 2) == true)
assert((1 == 2 or 2 == 2) == true)
assert((not nil and 1) == 1)
assert((not 1 or 2) == 2)
assert((1 < 2 and 2 < 3) == true)
assert((1 + 1 == 2 and "yes" or "no") == "yes")
assert((1 + 1 == 3 and "yes" or "no") == "no")
end

-- ## and/or return their operands unchanged
do
local t = {}
assert((t and 1) == 1)
assert((nil and t) == nil)
assert((t or 1) == t)
assert((false or t) == t)
assert((0 and "zero is true") == "zero is true")
assert(("" and "empty string is true") == "empty string is true")
assert(T(0 or 1) == "0")
assert(T(0.0 and 1.0) == "1.0")
assert(T(false or 2.0) == "2.0")
end

-- ## a full mix
do
assert(1 + 2 * 3 ^ 2 // 4 % 5 - 6 == -1)
assert(2 ^ 3 * 4 // 5 + 6 % 7 == 12.0)
assert(T(2 ^ 3 * 4 // 5 + 6 % 7) == "12.0")
assert(1 | 2 ~ 3 & 4 << 1 + 1 == 3)
assert(("a" .. 1 + 1 == "a2") and not (1 > 2 or nil))
assert(-2 ^ 2 + 3 * 4 .. "" == "8.0")
assert(#"abc" + -1 * ~0 == 4)
assert(5 // 2 * 2 + 5 % 2 == 5)
assert(3 - -3 == 6)
assert(3 - - - 3 == 0)
assert(2 - ~2 == 5)
end

-- ## parenthesised expressions truncate multiple results
do
local function mr() return 1, 2, 3 end
local t1 = {mr()}
local t2 = {(mr())}
assert(#t1 == 3)
assert(#t2 == 1)
assert(select("#", mr()) == 3)
assert(select("#", (mr())) == 1)
assert((mr()) == 1)
end

-- ## operators that are not associative in a chain are rejected or valid
do
assert(load("return 1 + + 2") == nil)
assert(load("return 1 * / 2") == nil)
assert(load("return 1 - - 2") ~= nil)
assert(load("return 1 ~ ~ 2") ~= nil)
assert(load("return not not not 1") ~= nil)
assert(load("return 2 ^ - 2") ~= nil)
assert(load("return 2 ^ not 2") ~= nil)
assert(load("return 2 ^ # 'a'") ~= nil)
assert(load("return 1 ..") == nil)
assert(load("return .. 1") == nil)
assert(load("return and 1") == nil)
assert(load("return 1 or") == nil)
assert(load("return ()") == nil)
assert(load("return (1") == nil)
assert(load("return 1)") == nil)
end

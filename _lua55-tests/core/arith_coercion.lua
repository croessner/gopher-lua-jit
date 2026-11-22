-- Arithmetic: string/number coercions.
local T = tostring

-- ## strings are converted to numbers by arithmetic operators
do
assert("10" + 1 == 11)
assert(1 + "10" == 11)
assert("10" + "5" == 15)
assert("10" - 1 == 9)
assert("10" * "2" == 20)
assert("10" / 4 == 2.5)
assert("7" // 2 == 3)
assert("7" % 2 == 1)
assert("2" ^ 3 == 8)
assert(-"2" == -2)
assert("0x10" + 0 == 16)
assert(" 10 " + 0 == 10)
assert("1e1" + 0 == 10)
assert("-3" + 0 == -3)
assert(".5" + 0 == 0.5)
assert("5." + 0 == 5)
assert("\t7\n" * 1 == 7)
end

-- ## the subtype of a coerced string follows the string contents
do
assert(T("10" + 1) == "11")
assert(T("10" + 1.0) == "11.0")
assert(T("10.0" + 1) == "11.0")
assert(T("1e1" + 1) == "11.0")
assert(T("10" * "2") == "20")
assert(T("10" // "3") == "3")
assert(T("10" % "3") == "1")
assert(T("10" / "2") == "5.0")
assert(T("2" ^ "2") == "4.0")
assert(T(-"2") == "-2")
assert(T(-"2.0") == "-2.0")
assert(T("0x10" + 0) == "16")
assert(T("0x1p4" + 0) == "16.0")
assert(T("9223372036854775807" + 0) == "9223372036854775807")
assert(T("9223372036854775808" + 0) == "9.2233720368547758e+18")
assert(T("9223372036854775807" + 1) == "-9223372036854775808")
assert(T("0xffffffffffffffff" + 0) == "-1")
end

-- ## strings that are not numerals raise an error
do
assert(not pcall(function() return "abc" + 1 end))
assert(not pcall(function() return "" + 1 end))
assert(not pcall(function() return " " + 1 end))
assert(not pcall(function() return "1 2" + 1 end))
assert(not pcall(function() return "1e" + 1 end))
assert(not pcall(function() return "0x" + 1 end))
assert(not pcall(function() return "1." .. "." + 1 end))
assert(not pcall(function() return "--1" + 1 end))
assert(not pcall(function() return "1_0" + 1 end))
assert(not pcall(function() return "inf" + 1 end))
assert(not pcall(function() return "nan" + 1 end))
assert(not pcall(function() return "10" + "a" end))
assert(not pcall(function() return -"x" end))
assert(not pcall(function() return "1\0" + 1 end))
end

-- ## comparison operators never coerce
do
assert("10" ~= 10)
assert(not ("10" == 10))
assert("1" ~= 1.0)
assert(not pcall(function() return "10" < 5 end))
assert(not pcall(function() return 5 < "10" end))
assert(not pcall(function() return "10" <= 5 end))
assert(not pcall(function() return 5 >= "10" end))
assert("10" < "5")
assert("a" < "b")
assert("" < "a")
assert("a" < "aa")
assert("Z" < "a")
assert("a" <= "a")
assert(not ("a" < "a"))
assert("b" > "a")
assert("b" >= "b")
assert("a\0b" > "a\0a")
assert("a\0" > "a")
end

-- ## numbers are converted to strings by concatenation
do
assert(1 .. "" == "1")
assert(1.0 .. "" == "1.0")
assert(1.5 .. "" == "1.5")
assert(-1 .. "" == "-1")
assert(1 .. 2 == "12")
assert(1 .. 2.0 == "12.0")
assert(1.0 .. 2 == "1.02")
assert("a" .. 1 == "a1")
assert(1 .. "a" == "1a")
assert(2^53 .. "" == "9007199254740992.0")
assert(2^63 .. "" == "9.2233720368547758e+18")
assert(9223372036854775807 .. "" == "9223372036854775807")
assert(1e100 .. "" == "1e+100")
assert((1/0) .. "" == "inf")
assert(-(1/0) .. "" == "-inf")
assert(-0.0 .. "" == "-0.0")
assert(10 // 3 .. "" == "3")
assert(10 / 2 .. "" == "5.0")
assert(type(1 .. 2) == "string")
assert(#(12 .. 34) == 4)
end

-- ## concatenation of non-string, non-number values raises an error
do
assert(not pcall(function() return "a" .. nil end))
assert(not pcall(function() return nil .. "a" end))
assert(not pcall(function() return "a" .. {} end))
assert(not pcall(function() return "a" .. true end))
assert(not pcall(function() return false .. "a" end))
assert(not pcall(function() return print .. "a" end))
assert(not pcall(function() return 1 .. nil end))
assert(not pcall(function() return "a" .. "b" .. {} .. "c" end))
end

-- ## tonumber and tostring basics
do
assert(tonumber("10") == 10)
assert(tonumber("abc") == nil)
assert(tonumber("") == nil)
assert(tostring(10) == "10")
assert(tostring(-0) == "0")
assert(tostring(true) == "true")
assert(tostring(nil) == "nil")
assert(tostring("x") == "x")
end

-- Lexer: numeric literals of the Lua 5.5 profile.
-- Integer/float discrimination is done through tostring ("3" vs "3.0").
local load = loadstring or load
local T = tostring

-- ## decimal integers
do
assert(T(0) == "0")
assert(T(7) == "7")
assert(T(0007) == "7")
assert(T(123456789) == "123456789")
assert(T(9223372036854775807) == "9223372036854775807")
assert(T(-9223372036854775807) == "-9223372036854775807")
assert(T(-9223372036854775807 - 1) == "-9223372036854775808")
end

-- ## decimal floats
do
assert(T(3.0) == "3.0")
assert(T(3.) == "3.0")
assert(T(.5) == "0.5")
assert(T(0.5) == "0.5")
assert(T(3.25) == "3.25")
assert(T(1e2) == "100.0")
assert(T(1E2) == "100.0")
assert(T(1e+2) == "100.0")
assert(T(1e-2) == "0.01")
assert(T(.5e1) == "5.0")
assert(T(5.e-1) == "0.5")
assert(T(12.5e1) == "125.0")
assert(T(0e0) == "0.0")
assert(T(0.0) == "0.0")
assert(1e2 == 100)
assert(3.0 == 3)
end

-- ## decimal integer overflow becomes a float
do
assert(T(9223372036854775808) == "9.2233720368547758e+18")
assert(9223372036854775808 == 2^63)
assert(T(18446744073709551616) == "1.8446744073709552e+19")
assert(100000000000000000000 == 1e20)
assert(T(-9223372036854775808) == "-9.2233720368547758e+18")
assert(-9223372036854775808 == -(2^63))
assert(9223372036854775807 + 0.0 == 2^63)
end

-- ## hexadecimal integers
do
assert(0x0 == 0)
assert(0x10 == 16)
assert(0X10 == 16)
assert(0xff == 255)
assert(0xFF == 255)
assert(0xfF == 255)
assert(0xabcdef == 11259375)
assert(0xABCDEF == 11259375)
assert(T(0x10) == "16")
assert(T(0x7fffffffffffffff) == "9223372036854775807")
assert(0x00000000000000000001 == 1)
end

-- ## hexadecimal integers wrap around modulo 2^64
do
assert(T(0xffffffffffffffff) == "-1")
assert(T(0x8000000000000000) == "-9223372036854775808")
assert(T(0x10000000000000000) == "0")
assert(T(0x1ffffffffffffffff) == "-1")
assert(T(0xfffffffffffffffe) == "-2")
assert(T(0x123456789abcdef01) == "2541551405711093505")
assert(0xffffffffffffffff == -1)
assert(0x7fffffffffffffff + 1 == 0x8000000000000000)
end

-- ## hexadecimal floats
do
assert(T(0x1p0) == "1.0")
assert(T(0x1p4) == "16.0")
assert(T(0x1P4) == "16.0")
assert(T(0x1p+4) == "16.0")
assert(T(0x1p-1) == "0.5")
assert(T(0x.8) == "0.5")
assert(T(0x.8p1) == "1.0")
assert(T(0xA.8) == "10.5")
assert(T(0xa.8p0) == "10.5")
assert(T(0x10.) == "16.0")
assert(T(0x.1p4) == "1.0")
assert(T(0x1.8p1) == "3.0")
assert(T(0xff.ffp0) == "255.99609375")
assert(0x1p63 == 2^63)
assert(0x1p-1074 > 0)
assert(0x1p-1075 == 0)
assert(0x1p1024 == (1/0))
assert(0x.0p10 == 0)
assert(T(0x1e2) == "482")
assert(T(0xep1) == "28.0")
end

-- ## float literal limits
do
assert(1e308 < (1/0))
assert(1e309 == (1/0))
assert(-1e309 == -(1/0))
assert(1e-400 == 0)
assert(T(1e-400) == "0.0")
assert(4.9e-324 > 0)
assert(T(1e15) == "1e+15")
assert(T(1e100) == "1e+100")
assert(T(123456.789e3) == "123456789.0")
assert(T(2^53) == "9007199254740992.0")
assert(T(0.1) == "0.1")
end

-- ## numbers adjacent to other tokens
do
assert(1 .. 2 == "12")
assert(1. .. 2 == "1.02")
assert(1 ..2 == "12")
assert(2-1 == 1)
assert(2 -1 == 1)
assert(- -2 == 2)
assert(1--[[comment]]+1 == 2)
assert(0xap1 == 20)
assert(0xa .. "" == "10")
end

-- ## malformed numbers are rejected
do
assert(load("return 1e") == nil)
assert(load("return 1e+") == nil)
assert(load("return 0x") == nil)
assert(load("return 0xg") == nil)
assert(load("return 1.2.3") == nil)
assert(load("return 1..2") == nil)
assert(load("return 3x") == nil)
assert(load("return 0x1p") == nil)
assert(load("return 0x1pz") == nil)
assert(load("return 1e1e1") == nil)
assert(load("return 12abc") == nil)
assert(load("return 0x.p1") == nil)
assert(load("return .e1") == nil)
assert(load("return 1_000") == nil)
assert(load("return 0b101") == nil)
assert(load("return 0o17") == nil)
assert(load("return 1e2.5") == nil)
assert(load("return 0x1.2.3") == nil)
assert(load("return 08") ~= nil)
assert(load("return 1 .. 2") ~= nil)
end

-- Arithmetic: bitwise operators on integers and floats with integral values.
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1

-- ## and, or, xor, not
do
assert(0xF0 & 0x3C == 0x30)
assert(0xF0 | 0x3C == 0xFC)
assert(0xF0 ~ 0x3C == 0xCC)
assert(~0 == -1)
assert(~-1 == 0)
assert(~0xF0 == -241)
assert(~maxint == minint)
assert(~minint == maxint)
assert(-1 & 0xFF == 0xFF)
assert(-1 | 0 == -1)
assert(-1 ~ -1 == 0)
assert(-1 ~ 0 == -1)
assert(5 & -5 == 1)
assert(maxint & minint == 0)
assert(maxint | minint == -1)
assert(maxint ~ minint == -1)
assert(0xAAAAAAAAAAAAAAAA & 0x5555555555555555 == 0)
assert(0xAAAAAAAAAAAAAAAA | 0x5555555555555555 == -1)
assert(T(1 & 1) == "1")
assert(T(~0) == "-1")
end

-- ## shifts are logical and fill with zeros
do
assert(1 << 0 == 1)
assert(1 << 1 == 2)
assert(1 << 62 == 4611686018427387904)
assert(1 << 63 == minint)
assert(1 << 64 == 0)
assert(1 << 65 == 0)
assert(1 << 1000 == 0)
assert(-1 << 1 == -2)
assert(-1 << 63 == minint)
assert(-1 << 64 == 0)
assert(256 >> 4 == 16)
assert(1 >> 1 == 0)
assert(-1 >> 1 == maxint)
assert(-1 >> 63 == 1)
assert(-1 >> 64 == 0)
assert(-1 >> 1000 == 0)
assert(minint >> 63 == 1)
assert(minint >> 1 == 4611686018427387904)
assert(0xFF >> 4 == 0xF)
assert(3 << 62 == -4611686018427387904)
end

-- ## negative shift counts shift in the opposite direction
do
assert(1 << -1 == 0)
assert(2 << -1 == 1)
assert(16 << -4 == 1)
assert(1 >> -1 == 2)
assert(1 >> -63 == minint)
assert(1 >> -64 == 0)
assert(-1 << -1 == maxint)
assert(-1 >> -1 == -2)
assert(1 << -64 == 0)
assert(1 << -63 == 0)
assert(minint << -63 == 1)
assert(1 << minint == 0)
assert(1 >> minint == 0)
assert(1 << maxint == 0)
assert(1 >> maxint == 0)
assert(-1 >> minint == 0)
end

-- ## shifts with runtime operands
do
local one, n63, n64 = 1, 63, 64
assert(one << n63 == minint)
assert(one << n64 == 0)
assert(-one >> n63 == 1)
assert(-one >> n64 == 0)
assert(one << -n63 == 0)
assert(one >> -n63 == minint)
for i = 0, 62 do
  assert(1 << i == 2 ^ i, "shl")
  assert((1 << i) >> i == 1, "shr")
end
end

-- ## floats with integral values are converted
do
assert(3.0 & 1 == 1)
assert(1 | 2.0 == 3)
assert(3.0 ~ 1.0 == 2)
assert(~0.0 == -1)
assert(1.0 << 2 == 4)
assert(1 << 2.0 == 4)
assert(8.0 >> 1.0 == 4)
assert(T(3.0 & 1) == "1")
assert(T(1.0 | 2.0) == "3")
assert(T(~0.0) == "-1")
assert(T(1.0 << 2.0) == "4")
assert(2^53 | 0 == 9007199254740992)
assert(-(2^63) | 0 == minint)
assert(T(-(2^63) | 0) == "-9223372036854775808")
assert(1e15 & -1 == 1000000000000000)
assert(-0.0 | 0 == 0)
assert(T(-0.0 | 0) == "0")
end

-- ## floats without an integer representation raise an error
do
assert(not pcall(function() return 1.5 & 1 end))
assert(not pcall(function() return 1 | 2.5 end))
assert(not pcall(function() return 1 ~ 0.1 end))
assert(not pcall(function() return ~1.5 end))
assert(not pcall(function() return 1.5 << 1 end))
assert(not pcall(function() return 1 << 1.5 end))
assert(not pcall(function() return 1 >> 0.5 end))
assert(not pcall(function() return 2^63 | 0 end))
assert(not pcall(function() return 2^64 & 1 end))
assert(not pcall(function() return -(2^63) - 1025 | 0 end))
assert(not pcall(function() return (1/0) | 0 end))
assert(not pcall(function() return -(1/0) & 0 end))
assert(not pcall(function() return (0/0) ~ 0 end))
assert(not pcall(function() return 1e100 | 0 end))
assert(not pcall(function() return ~(1/0) end))
local half = 0.5
assert(not pcall(function() return half & 1 end))
assert(not pcall(function() return 1 << half end))
assert(not pcall(function() return ~half end))
end

-- ## bitwise operators on non-numbers raise an error
do
assert(not pcall(function() return nil & 1 end))
assert(not pcall(function() return 1 | {} end))
assert(not pcall(function() return true ~ 1 end))
assert(not pcall(function() return ~{} end))
assert(not pcall(function() return ~nil end))
assert(not pcall(function() return 1 << print end))
assert(not pcall(function() return "abc" & 1 end))
assert(not pcall(function() return ~"abc" end))
end

-- ## identities
do
local vals = {0, 1, -1, 2, 255, -256, maxint, minint, 0x5555555555555555, 123456789}
for _, a in ipairs(vals) do
  assert(~~a == a, "double not")
  assert(a & a == a, "and self")
  assert(a | a == a, "or self")
  assert(a ~ a == 0, "xor self")
  assert(a & 0 == 0, "and zero")
  assert(a | 0 == a, "or zero")
  assert(a ~ 0 == a, "xor zero")
  assert(a & -1 == a, "and ones")
  assert(a ~ -1 == ~a, "xor ones")
  assert(-a == ~a + 1, "two's complement")
  for _, b in ipairs(vals) do
    assert(a & b == b & a, "and commutes")
    assert(a | b == b | a, "or commutes")
    assert(a ~ b == b ~ a, "xor commutes")
    assert(~(a & b) == ~a | ~b, "de Morgan")
    assert(a ~ b == (a | b) & ~(a & b), "xor definition")
  end
end
end

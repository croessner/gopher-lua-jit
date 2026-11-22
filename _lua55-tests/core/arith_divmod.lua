-- Arithmetic: floor division and modulo for integers and floats.
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1
local inf = 1 / 0

-- ## integer floor division rounds towards minus infinity
do
assert(7 // 2 == 3)
assert(-7 // 2 == -4)
assert(7 // -2 == -4)
assert(-7 // -2 == 3)
assert(6 // 2 == 3)
assert(-6 // 2 == -3)
assert(6 // -2 == -3)
assert(0 // 5 == 0)
assert(0 // -5 == 0)
assert(1 // 2 == 0)
assert(-1 // 2 == -1)
assert(1 // -2 == -1)
assert(T(-7 // 2) == "-4")
assert(T(0 // -5) == "0")
end

-- ## integer modulo takes the sign of the divisor
do
assert(7 % 2 == 1)
assert(-7 % 2 == 1)
assert(7 % -2 == -1)
assert(-7 % -2 == -1)
assert(6 % 2 == 0)
assert(-6 % 2 == 0)
assert(6 % -2 == 0)
assert(5 % 3 == 2)
assert(-5 % 3 == 1)
assert(5 % -3 == -1)
assert(-5 % -3 == -2)
assert(0 % 5 == 0)
assert(0 % -5 == 0)
assert(T(-6 % 2) == "0")
assert(T(7 % -2) == "-1")
end

-- ## integer division identities with runtime operands
do
for a = -7, 7 do
  for b = -3, 3 do
    if b ~= 0 then
      local q, r = a // b, a % b
      assert(q * b + r == a, "identity")
      assert(r == 0 or (r < 0) == (b < 0), "sign")
      assert(q == math.floor(a / b), "floor")
    end
  end
end
end

-- ## integer division by zero raises an error
do
assert(not pcall(function() return 1 // 0 end))
assert(not pcall(function() return 1 % 0 end))
assert(not pcall(function() return 0 // 0 end))
assert(not pcall(function() return 0 % 0 end))
assert(not pcall(function() return minint // 0 end))
local zero = 0
assert(not pcall(function() return 1 // zero end))
assert(not pcall(function() return 1 % zero end))
assert(not pcall(function() local a = 5 return a // zero end))
assert(not pcall(function() local a = 5 return a % zero end))
end

-- ## integer division at the limits
do
assert(minint // -1 == minint)
assert(minint % -1 == 0)
assert(minint // 1 == minint)
assert(minint % 1 == 0)
assert(maxint // -1 == -maxint)
assert(maxint % -1 == 0)
assert(minint // minint == 1)
assert(minint % minint == 0)
assert(maxint // maxint == 1)
assert(maxint // minint == -1)
assert(maxint % minint == -1)
assert(minint // maxint == -2)
assert(minint % maxint == maxint - 1)
assert(maxint % 2 == 1)
assert(minint % 2 == 0)
assert(minint // 2 == -4611686018427387904)
assert(maxint // 2 == 4611686018427387903)
assert(minint % 3 == 1)
assert(minint % -3 == -2)
assert(maxint % -2 == -1)
end

-- ## float floor division
do
assert(7.0 // 2 == 3.0)
assert(-7.0 // 2 == -4.0)
assert(7 // -2.0 == -4.0)
assert(-7.0 // -2.0 == 3.0)
assert(7.5 // 2 == 3.0)
assert(-7.5 // 2 == -4.0)
assert(T(-7.5 // 2) == "-4.0")
assert(1 // 0.3 == 3.0)
assert(-1 // 0.3 == -4.0)
assert(0.0 // 5 == 0)
assert(T(-0.0 // 5) == "-0.0")
assert(T(0.0 // -5) == "-0.0")
assert(3.5 // 0.5 == 7.0)
end

-- ## float modulo
do
assert(7.0 % 2 == 1.0)
assert(-7.0 % 2 == 1.0)
assert(7 % -2.0 == -1.0)
assert(-7.0 % -2.0 == -1.0)
assert(5.5 % 2 == 1.5)
assert(-5.5 % 2 == 0.5)
assert(5.5 % -2 == -0.5)
assert(-5.5 % -2 == -1.5)
assert(T(5.3 % -2) == "-0.70000000000000018")
assert(T(-5.3 % 2) == "0.70000000000000018")
assert(T(6.0 % 2) == "0.0")
assert(T(-6.0 % 2) == "-0.0")
assert(T(6.0 % -2) == "0.0")
assert(T(-6.0 % -2) == "-0.0")
assert(3.5 % 0.5 == 0)
assert(1e308 % 3 == 2.0)
end

-- ## float division and modulo by zero
do
assert(1.0 // 0 == inf)
assert(-1.0 // 0 == -inf)
assert(1 // 0.0 == inf)
assert(-1 // 0.0 == -inf)
assert(1 // -0.0 == -inf)
local z = 0.0 // 0
assert(z ~= z)
local m = 1.0 % 0
assert(m ~= m)
local m2 = 1 % 0.0
assert(m2 ~= m2)
local m3 = 0.0 % 0
assert(m3 ~= m3)
assert(1 / 0 == inf)
assert(5.0 // 0 == inf)
end

-- ## float division and modulo with infinities
do
assert(5 % inf == 5.0)
assert(T(5 % inf) == "5.0")
assert(-5 % inf == inf)
assert(5 % -inf == -inf)
assert(-5 % -inf == -5.0)
assert(5.5 % inf == 5.5)
assert(-5.5 % -inf == -5.5)
assert(0 % inf == 0)
assert(5 // inf == 0)
assert(T(5 // inf) == "0.0")
assert(-5 // inf == 0)
assert(T(-5 // inf) == "-0.0")
assert(5 // -inf == 0)
assert(T(5 // -inf) == "-0.0")
assert(-5 // -inf == 0)
assert(inf // 1 == inf)
assert(-inf // 1 == -inf)
local r = inf % 2
assert(r ~= r)
local r2 = inf // inf
assert(r2 ~= r2)
end

-- ## float division identities with runtime operands
do
for _, a in ipairs{-7.5, -3.0, -0.5, 0.5, 2.25, 9.75} do
  for _, b in ipairs{-2.5, -1.0, 0.5, 3.0} do
    local q, r = a // b, a % b
    assert(q == math.floor(a / b), "floor")
    assert(q * b + r == a, "identity")
    assert(r == 0 or (r < 0) == (b < 0), "sign")
  end
end
end

-- ## mixed integer and float operands
do
assert(T(7 // 2.0) == "3.0")
assert(T(7 % 2.0) == "1.0")
assert(T(-7 // 2.0) == "-4.0")
assert(T(-7 % 2.0) == "1.0")
assert(T(7.0 // 2) == "3.0")
assert(T(maxint // 1.0) == "9.2233720368547758e+18")
assert(T(maxint % 2.0) == "0.0")
assert(T(minint // -1.0) == "9.2233720368547758e+18")
assert(T(minint % -1.0) == "-0.0")
end

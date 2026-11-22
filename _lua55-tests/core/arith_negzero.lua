-- Arithmetic: negative zero.
local T = tostring

-- ## negative zero literals and constants
do
assert(T(-0.0) == "-0.0")
assert(T(0.0) == "0.0")
assert(T(-0) == "0")
assert(1 / -0.0 == -1 / 0)
assert(1 / 0.0 == 1 / 0)
assert(-0.0 == 0.0)
assert(-0.0 == 0)
assert(not (-0.0 < 0.0))
assert(T(0.0 * -1) == "-0.0")
assert(T(-0.0 * -1) == "0.0")
assert(T(0 * -1.0) == "-0.0")
end

-- ## negative zero survives being stored and passed around
do
local nz = -0.0
local function id(...) return ... end
assert(T(nz) == "-0.0")
assert(T(id(nz)) == "-0.0")
assert(T(({nz})[1]) == "-0.0")
assert(1 / nz == -1 / 0)
assert(T((function() return nz end)()) == "-0.0")
assert(nz .. "" == "-0.0")
end

-- ## run-time arithmetic that keeps negative zero
do
local nz, pz, one = -0.0, 0.0, 1.0
assert(T(nz * 5) == "-0.0")
assert(T(nz / 5) == "-0.0")
end

-- ## run-time arithmetic that produces negative zero
do
local pz, neg, pos, big = 0.0, -1.5, 2.0, 1e308
assert(T(pz // neg) == "-0.0")
assert(T(-1e-200 * 1e-200) == "-0.0")
assert(T(-1 / (big * 10)) == "-0.0")
assert(T(0 * neg) == "-0.0")
assert(T(neg * 0) == "-0.0")
assert(T(0 / neg) == "-0.0")
end

-- ## run-time arithmetic that yields positive zero
do
local nz, pz = -0.0, 0.0
assert(T(nz + pz) == "0.0")
assert(T(pz + nz) == "0.0")
assert(T(pz - pz) == "0.0")
assert(T(nz - nz) == "0.0")
assert(T(nz * nz) == "0.0")
assert(T(-nz) == "0.0")
assert(T(nz + 0) == "0.0")
assert(T(pz * 5) == "0.0")
end

-- ## negative zero in integer contexts
do
local nz = -0.0
assert(T(nz | 0) == "0")
assert(T(nz // 1) == "-0.0")
assert(T(~nz) == "-1")
local t = {}
t[nz] = "zero"
assert(t[0] == "zero")
assert(next(t) == 0)
assert(T(next(t)) == "0")
local n = 0
for i = nz, 0 do n = n + 1 end
assert(n == 1)
end

-- ## the sign of zero in division
do
local nz, pz = -0.0, 0.0
assert(1 / nz == -(1 / 0))
assert(-1 / nz == 1 / 0)
assert(1 / (nz + pz) == 1 / 0)
end

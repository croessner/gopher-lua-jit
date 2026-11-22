-- Arithmetic: negative zero.
local T = tostring

-- ## run-time arithmetic that keeps negative zero
do
local nz, pz, one = -0.0, 0.0, 1.0
assert(T(nz + nz) == "-0.0")
assert(T(nz - pz) == "-0.0")
assert(T(nz * one) == "-0.0")
assert(T(nz / one) == "-0.0")
assert(T(nz % one) == "-0.0")
assert(T(nz + nz + nz) == "-0.0")
end

-- ## run-time arithmetic that produces negative zero
do
local pz, neg, pos, big = 0.0, -1.5, 2.0, 1e308
assert(T(pz * neg) == "-0.0")
assert(T(pz / neg) == "-0.0")
assert(T(-pz) == "-0.0")
assert(T(neg * pz) == "-0.0")
assert(T(-pos % pos) == "-0.0")
assert(T(-(pos % pos)) == "-0.0")
end

-- ## the sign of zero in division
do
local nz, pz = -0.0, 0.0
assert(1 / (nz + nz) == -(1 / 0))
assert(1 / (nz * 1.0) == -(1 / 0))
assert(1 / (pz * -1.0) == -(1 / 0))
end

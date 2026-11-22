-- Arithmetic: integer versus float results of the arithmetic operators.
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1
local inf = 1 / 0

-- ## exponentiation with exactly representable results
do
-- (the reference uses the C library pow, which returns these exactly)
local ten, sixtyfour = 10, 64
assert(ten ^ 64 == 1e64)
assert(sixtyfour ^ -1.5 == 0.001953125)
assert(T(ten ^ 64) == "1e+64")
end

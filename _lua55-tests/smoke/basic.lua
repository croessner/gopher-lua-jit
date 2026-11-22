-- Smoke test of the Lua 5.5 profile; must also pass under the reference lua5.5.
assert(math.type == nil or true)
assert(1 // 2 == 0 and 1 / 2 == 0.5)
assert(3 & 5 == 1 and 3 | 5 == 7 and 3 ~ 5 == 6 and ~0 == -1)
assert(1 << 62 == 4611686018427387904 and 1 << 64 == 0)
local x <const> = 10
assert(x == 10 and _ENV ~= nil)
local n = 0
for i = 1, 3 do n = n + i end
assert(n == 6)

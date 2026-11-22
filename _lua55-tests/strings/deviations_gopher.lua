-- Intentional deviations of the Lua 5.5 string library of this runtime
-- from the reference interpreter (lua5.5). This script is not run by the
-- reference; every block explains why the behaviour differs.

local function fails(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error")
  assert(string.find(tostring(msg), expected, 1, true), tostring(msg))
end

-- 1. Size guard. The reference only detects arithmetic overflow and then
-- relies on the allocator ("not enough memory"). A failed Go allocation
-- cannot be converted into a Lua error, so strings built by string.rep and
-- string.pack are limited to 2^31 - 1 bytes and the limit is reported up
-- front.
fails("resulting string too large", string.rep, "x", 1 << 31)
fails("resulting string too large", string.rep, "ab", 1 << 30)
fails("resulting string too large", string.rep, "x", 1 << 40, ", ")
fails("result too long", string.pack, "c99999999999999999999", "x")
fails("result too long", string.pack, "c2147483648", "x")
assert(string.packsize("c2147483648") == 2147483648) -- only a size, no allocation

-- 2. string.dump. This runtime has no binary chunk format: Lua functions
-- cannot be dumped (the reference returns a binary chunk). Non-Lua values
-- are rejected exactly like in the reference.
fails("unable to dump given function", string.dump, function() end)
fails("Lua function expected", string.dump, print)

-- 3. The string metatable only carries __index. The reference also stores
-- arithmetic metamethods (__add, __sub, ...) there; in this runtime the
-- coercion of strings in arithmetic is implemented by the VM itself.
local mt = getmetatable("")
assert(mt.__index == string)
local fields = 0
for _ in pairs(mt) do fields = fields + 1 end
assert(fields == 1)
assert("10" + 5 == 15)

-- 4. Rounding of "%a" with a precision. The digits are rounded to nearest,
-- ties to even (ISO C, as glibc does). The libc of the local reference
-- build (macOS) truncates most ties, e.g. it prints 0x1p+0 for the first
-- value below.
assert(string.format("%.0a", 1.5) == "0x2p+0")
assert(string.format("%.1a", 1.09375) == "0x1.2p+0")
assert(string.format("%.1a", 1.03125) == "0x1.0p+0")
assert(string.format("%.1a", 1.96875) == "0x2.0p+0")

-- 5. "%p" of a string. Strings have no stable address in this runtime; the
-- identity is derived from the contents, so equal strings always have the
-- same identity (in the reference two long strings with equal contents
-- may differ).
local long1 = string.rep("long string ", 10)
local long2 = string.rep("long string ", 5) .. string.rep("long string ", 5)
assert(string.format("%p", long1) == string.format("%p", long2))
assert(string.format("%p", long1):find("^0x%x+$"))

-- 6. Number of results. Values are returned on the registry of the
-- state, which is smaller than the stack of the reference (1,000,000
-- slots), so huge result lists fail earlier - with an error, not a crash.
local big = string.rep("x", 100000)
fails("stack overflow (string slice too long)", string.byte, big, 1, -1)
fails("stack overflow (string slice too long)", utf8.codepoint, big, 1, -1)
fails("stack overflow (too many results)", string.unpack, string.rep("b", 100000), big)
assert(#{string.byte(string.rep("x", 1000), 1, -1)} == 1000)

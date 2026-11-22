-- Arithmetic: bitwise operators do not convert strings to numbers (unlike
-- the arithmetic operators, whose coercion is provided for strings).
local T = tostring

-- ## strings are rejected by bitwise operators even if they hold numerals
do
assert(not pcall(function() return "3" & 1 end))
assert(not pcall(function() return 1 | "2" end))
assert(not pcall(function() return "3" ~ "1" end))
assert(not pcall(function() return ~"0" end))
assert(not pcall(function() return "1" << 2 end))
assert(not pcall(function() return 8 >> "1" end))
assert(not pcall(function() return "0x10" | 0 end))
assert(not pcall(function() return "3.0" & 1 end))
assert(not pcall(function() return "1.5" & 1 end))
assert(not pcall(function() return "abc" | 1 end))
assert(not pcall(function() return ~"x" end))
assert(not pcall(function() return "" << 1 end))
end

-- ## with runtime operands
do
local s, n = "3", 1
assert(not pcall(function() return s & n end))
assert(not pcall(function() return n | s end))
assert(not pcall(function() return s ~ s end))
assert(not pcall(function() return ~s end))
assert(not pcall(function() return s << n end))
assert(not pcall(function() return n >> s end))
end

-- ## the same strings are accepted by arithmetic operators
do
local s = "3"
assert(s + 1 == 4)
assert(T(s * 2) == "6")
assert(T(s // 1) == "3")
assert((s + 0) & 1 == 1)
assert(~(s + 0) == -4)
end

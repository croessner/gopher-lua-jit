-- Lexer: string literals, escapes, long strings and comments.
local load = loadstring or load

-- ## a long bracket opener without second bracket starts a short comment
do
local x = 4
--[==== [ short comment
x = 5
assert(x == 5)
--[==
x = 6
assert(x == 6)
--[=
x = 7
assert(x == 7)
end

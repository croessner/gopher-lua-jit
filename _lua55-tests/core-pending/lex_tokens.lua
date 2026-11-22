-- Lexer: operator tokens, names, keywords and token boundaries.
local load = loadstring or load

-- ## line terminators and whitespace
do
local f = load("local a = 1\r\nlocal b = 2\rlocal c = 3\n\rreturn a + b + c")
local g = load("return\t1\v+\f2")
assert(g() == 3)
end

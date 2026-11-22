-- Lexer: operator tokens, names, keywords and token boundaries.
local load = loadstring or load

-- ## operator tokens
do
assert(1 + 2 == 3)
assert(5 - 2 == 3)
assert(2 * 3 == 6)
assert(7 / 2 == 3.5)
assert(7 // 2 == 3)
assert(7 % 2 == 1)
assert(2 ^ 3 == 8)
assert(6 & 3 == 2)
assert(6 | 3 == 7)
assert(6 ~ 3 == 5)
assert(~6 == -7)
assert(1 << 4 == 16)
assert(16 >> 4 == 1)
assert(1 == 1)
assert(1 ~= 2)
assert(1 < 2)
assert(1 <= 1)
assert(2 > 1)
assert(2 >= 2)
assert("a" .. "b" == "ab")
assert(#"abc" == 3)
assert(not nil)
end

-- ## tokens without separating whitespace
do
assert(1+2==3)
assert(7//2==3)
assert(1<<4==16)
assert(16>>4==1)
assert(6~3==5)
assert(1~=2)
assert(~6==-7)
assert(~~6==6)
assert(- - 1==1)
assert(-~1==2)
assert(~-1==0)
assert(#"abc"..#"de"=="32")
assert(1<2==true)
assert(2>=2==true)
assert(not not true)
local a,b,c=1,2,3 assert(a+b+c==6)
local t={1,2;3} assert(#t==3)
end

-- ## names
do
local _ = 1
local _a1 = 2
local A_B_c9 = 3
local __ = 4
local _ENVx = 5
local nil_ = 6
local endx = 7
local and1 = 8
local Local = 9
local globalx = 10
assert(_ + _a1 + A_B_c9 + __ + _ENVx + nil_ + endx + and1 + Local + globalx == 55)
end

-- ## keywords cannot be names
do
for _, kw in ipairs{"and", "break", "do", "else", "elseif", "end", "false", "for",
                    "function", "goto", "if", "in", "local", "nil", "not", "or",
                    "repeat", "return", "then", "true", "until", "while"} do
  assert(load("local " .. kw .. " = 1") == nil, kw)
  assert(load("local t = {} t." .. kw .. " = 1") == nil, kw)
  assert(load("local t = {" .. kw .. " = 1}") == nil, kw)
end
end

-- ## keywords are case sensitive
do
local And, Break, Do, End, If, Nil, True, False, Not, Or, While = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
assert(And + Break + Do + End + If + Nil + True + False + Not + Or + While == 66)
end

-- ## 'global' is a soft keyword usable as a name
do
local global = 5
assert(global == 5)
global = global + 1
assert(global == 6)
local t = {global = 1}
assert(t.global == 1)
local function f(global) return global end
assert(f(3) == 3)
end

-- ## keywords as string keys still work
do
local t = {["end"] = 1, ["nil"] = 2, ["for"] = 3}
assert(t["end"] == 1)
assert(t["nil"] == 2)
assert(t["for"] == 3)
end

-- ## invalid tokens are rejected
do
assert(load("return 1 ! 2") == nil)
assert(load("return 1 != 2") == nil)
assert(load("return 1 @ 2") == nil)
assert(load("return 1 $ 2") == nil)
assert(load("return 1 ? 2") == nil)
assert(load("return a ` b") == nil)
assert(load("return 1 && 2") == nil)
assert(load("return 1 || 2") == nil)
assert(load("x += 1") == nil)
assert(load("x++") == nil)
assert(load("return 1 <> 2") == nil)
assert(load("return 1 === 1") == nil)
assert(load("return \\") == nil)
assert(load("local a\x80 = 1") == nil)
assert(load("return 1 ~ = 2") == nil)
assert(load("return 1 = = 2") == nil)
assert(load("return 1 < = 2") == nil)
assert(load("return 1 / / 2") == nil)
assert(load("return 1 < < 2") == nil)
end

-- ## statement separators and empty statements
do
;;;
local x = 1; ; ; local y = 2;
assert(x + y == 3)
do ; end
assert(load(";") ~= nil)
assert(load(";;;return 1;") ~= nil)
assert(load("return 1;;") == nil)
assert(load("return;") ~= nil)
assert(load("") ~= nil)
assert(load("   \n\t  ") ~= nil)
end

-- ## line terminators and whitespace
do
local f = load("local a = 1\r\nlocal b = 2\rlocal c = 3\n\rreturn a + b + c")
assert(f() == 6)
local g = load("return\t1\v+\f2")
end

-- ## ambiguous-looking but valid syntax
do
local s = "x"
assert(s:upper() == "X")
assert(("x"):upper() == "X")
assert(#{1, 2, 3} == 3)
local t = {f = function() return 1 end}
assert(t.f() == 1)
assert(t["f"]() == 1)
local function id(...) return ... end
assert(id"str" == "str")
assert(id[[long]] == "long")
assert(id{1}[1] == 1)
assert(type(id{}) == "table")
assert(id "a" .. "b" == "ab")
end

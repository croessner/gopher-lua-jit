-- Lexer: string literals, escapes, long strings and comments.
local load = loadstring or load

-- ## quotes
do
assert("a" == 'a')
assert("'" == '\'')
assert('"' == "\"")
assert(#"" == 0)
assert(#'' == 0)
assert("a'b" == 'a\'b')
assert('a"b' == "a\"b")
end

-- ## simple escapes
do
assert(#"\a\b\f\n\r\t\v\\\"\'" == 10)
assert(("\a"):byte() == 7)
assert(("\b"):byte() == 8)
assert(("\f"):byte() == 12)
assert(("\n"):byte() == 10)
assert(("\r"):byte() == 13)
assert(("\t"):byte() == 9)
assert(("\v"):byte() == 11)
assert(("\\"):byte() == 92)
assert(("\""):byte() == 34)
assert(("\'"):byte() == 39)
end

-- ## decimal escapes
do
assert("\65" == "A")
assert("\065" == "A")
assert("\0651" == "A1")
assert(#"\0" == 1)
assert(("\0"):byte() == 0)
assert(#"\0\0\0" == 3)
assert(("\255"):byte() == 255)
assert("\9" == "\t")
assert("\10" == "\n")
assert("a\0b" ~= "a")
assert(#"a\0b" == 3)
assert("\1234" == "{4")
assert("\00" == "\0")
assert("\000123" == "\0" .. "123")
end

-- ## hexadecimal escapes
do
assert("\x41" == "A")
assert("\x4a" == "J")
assert("\x4A" == "J")
assert("\x414" == "A4")
assert(("\x00"):byte() == 0)
assert(("\xff"):byte() == 255)
assert(("\xFF"):byte() == 255)
assert("\x41\x42\x43" == "ABC")
assert(#"\x00\x00" == 2)
end

-- ## \z skips following whitespace
do
assert("abc\z
        def" == "abcdef")
assert("abc\z   def" == "abcdef")
assert("abc\z


  def" == "abcdef")
assert("abc\zdef" == "abcdef")
assert("\z" == "")
assert("a\z	b" == "ab")
assert("\z  a" == "a")
end

-- ## escaped line breaks
do
assert("a\
b" == "a\nb")
assert('a\
b' == 'a\nb')
assert(#"\
" == 1)
assert("line1\
line2\
line3" == "line1\nline2\nline3")
end

-- ## UTF-8 escapes
do
assert("\u{41}" == "A")
assert("\u{0}" == "\0")
assert("\u{7F}" == "\x7f")
assert("\u{80}" == "\xC2\x80")
assert("\u{e9}" == "\xC3\xA9")
assert("\u{7FF}" == "\xDF\xBF")
assert("\u{800}" == "\xE0\xA0\x80")
assert("\u{20AC}" == "\xE2\x82\xAC")
assert("\u{FFFF}" == "\xEF\xBF\xBF")
assert("\u{10000}" == "\xF0\x90\x80\x80")
assert("\u{10FFFF}" == "\xF4\x8F\xBF\xBF")
assert("\u{000041}" == "A")
assert("\u{1F600}" == "\xF0\x9F\x98\x80")
assert(#"\u{10FFFF}" == 4)
end

-- ## UTF-8 escapes beyond Unicode (up to 2^31 - 1)
do
assert("\u{200000}" == "\xF8\x88\x80\x80\x80")
assert("\u{3FFFFFF}" == "\xFB\xBF\xBF\xBF\xBF")
assert("\u{4000000}" == "\xFC\x84\x80\x80\x80\x80")
assert("\u{7FFFFFFF}" == "\xFD\xBF\xBF\xBF\xBF\xBF")
assert(#"\u{7FFFFFFF}" == 6)
assert("\u{D800}" == "\xED\xA0\x80")
end

-- ## long strings
do
assert([[abc]] == "abc")
assert([[
abc]] == "abc")
assert([[

abc]] == "\nabc")
assert([[a
b]] == "a\nb")
assert([[a\nb]] == "a\\nb")
assert(#[[\]] == 1)
assert([==[a]]b]==] == "a]]b")
assert([==[a]=]b]==] == "a]=]b")
assert([=[a]]]=] == "a]]")
assert([[a]b]] == "a]b")
assert([[]] == "")
assert([==[]==] == "")
assert([[[]] == "[")
assert([=[[[x]]]=] == "[[x]]")
assert([===[
]===] == "")
assert([[ "quoted" 'single' ]] == " \"quoted\" 'single' ")
assert([====[x]===]y]====] == "x]===]y")
end

-- ## long string line ending normalisation
do
local f = load("return [[a\r\nb]]")
assert(f() == "a\nb")
local g = load("return [[a\rb]]")
assert(g() == "a\nb")
local h = load("return [[\r\nab]]")
assert(h() == "ab")
local k = load("return [[a\n\rb]]")
assert(k() == "a\nb")
local m = load("return 'a\\\r\nb'")
assert(m() == "a\nb")
end

-- ## comments
do
local x = 1 -- short comment
assert(x == 1)
--[[ long
comment ]] x = 2
assert(x == 2)
--[==[ level two ]] still comment
]==] x = 3
assert(x == 3)
--[ not a long comment
x = 4
assert(x == 4)
---[[ short comment because of the third dash
x = 6
--]]
assert(x == 6)
x = 7 --[[ inline ]] + 1
assert(x == 8)
assert(load("return 1 --") ~= nil)
assert(load("--") ~= nil)
assert(load("--[[ ]]") ~= nil)
assert(load("#!shebang is not skipped by load\nreturn 1") == nil)
end

-- ## malformed strings are rejected
do
assert(load("return 'abc") == nil)
assert(load('return "abc') == nil)
assert(load("return 'abc\n'") == nil)
assert(load("return '\\q'") == nil)
assert(load("return '\\256'") == nil)
assert(load("return '\\999'") == nil)
assert(load("return '\\xg0'") == nil)
assert(load("return '\\x4'") == nil)
assert(load("return '\\x'") == nil)
assert(load("return '\\u{110000000}'") == nil)
assert(load("return '\\u{80000000}'") == nil)
assert(load("return '\\u{}'") == nil)
assert(load("return '\\u{41'") == nil)
assert(load("return '\\u41'") == nil)
assert(load("return '\\u{xyz}'") == nil)
assert(load("return [[abc") == nil)
assert(load("return [==[abc]]") == nil)
assert(load("return [=[abc]==]") == nil)
assert(load("--[[ unfinished") == nil)
assert(load("--[==[ unfinished ]]") == nil)
assert(load("return [=abc]=]") == nil)
assert(load("return '\\u{7FFFFFFF}'") ~= nil)
assert(load("return '\\255'") ~= nil)
end

-- ## strings are compared and hashed by content
do
local t = {}
t["a\0b"] = 1
t["a\0c"] = 2
assert(t["a\0b"] == 1)
assert(t["a\x00c"] == 2)
assert(t["a"] == nil)
assert("a\0b" < "a\0c")
assert("a" < "a\0")
assert("\u{48}\101\x6c\108o" == "Hello")
end

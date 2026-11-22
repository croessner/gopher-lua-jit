-- Syntax: statements and expressions that load must accept or reject.
local load = loadstring or load
local function ok(src) return load(src) ~= nil end
local function bad(src) return load(src) == nil end

-- ## chunks
do
assert(ok(""))
assert(ok("return"))
assert(ok("return nil"))
assert(ok("local x"))
assert(ok("local x; local y; return x, y"))
assert(ok("-- only a comment"))
assert(ok("--[[ long comment ]]"))
assert(ok(";"))
assert(bad("return return"))
assert(bad("x"))
assert(bad("local"))
assert(bad("="))
assert(bad("1 + 1"))
assert(bad(")"))
assert(bad("}"))
assert(bad("]"))
end

-- ## expressions
do
assert(ok("return 1 + 2 * 3 - 4 / 5 // 6 % 7 ^ 8"))
assert(ok("return a.b.c[d][e].f"))
assert(ok("return a.b:c(d):e(f)"))
assert(ok("return (a)(b)(c)"))
assert(ok("return {} == {}"))
assert(ok("return #t + -x + ~y + (not z and 1 or 2)"))
assert(ok("return function() end"))
assert(ok("return (function() end)()"))
assert(ok("return ..."))
assert(ok("return a < b == (c > d)"))
assert(ok("return 'a' .. 'b' .. 1 .. 2"))
assert(ok("return - - - 1"))
assert(ok("return not not not nil"))
assert(ok("return ~ ~ ~ 1"))
assert(ok("return # # {}"))
assert(ok("return a or b and c"))
assert(ok("return (nil)"))
assert(ok("return ((1))"))
assert(bad("return 1 +"))
assert(bad("return + 1"))
assert(bad("return * 1"))
assert(bad("return 1 1"))
assert(bad("return a b"))
assert(bad("return a."))
assert(bad("return a.1"))
assert(bad("return a:b"))
assert(bad("return a["))
assert(bad("return a[]"))
assert(bad("return a[1"))
assert(bad("return f("))
assert(bad("return f(,)"))
assert(bad("return f(1,)"))
assert(bad("return function end"))
assert(bad("return function()"))
assert(bad("return not"))
assert(bad("return #"))
assert(bad("return 1 not 2"))
assert(bad("return a = b"))
assert(bad("return {} {}"))
assert(bad("return nil nil"))
assert(bad("return true false"))
end

-- ## prefix expressions
do
assert(ok("f()"))
assert(ok("f.g()"))
assert(ok("f:g()"))
assert(ok("f[1]()"))
assert(ok("f()()"))
assert(ok("f{}{}"))
assert(ok("f''''"))
assert(ok("(f or g)()"))
assert(ok("('x'):f()"))
assert(ok("({}).x = 1"))
assert(ok("(a).b = 1"))
assert(ok("a.b.c.d = 1"))
assert(ok("a[b][c] = 1"))
assert(ok("a.b[c].d, e = 1, 2"))
assert(bad("'x':f()"))
assert(bad("{}.x = 1"))
assert(bad("1.x = 1"))
assert(bad("f() = 1"))
assert(bad("a:b = 1"))
assert(bad("a.b() = 1"))
assert(bad("nil = 1"))
assert(bad("true = 1"))
assert(bad("... = 1"))
end

-- ## local statements
do
assert(ok("local a"))
assert(ok("local a, b, c"))
assert(ok("local a, b, c = 1"))
assert(ok("local a = 1, 2, 3"))
assert(ok("local a <const> = 1"))
assert(ok("local function f() end"))
assert(ok("local function f(a, b, ...) end"))
assert(bad("local a b"))
assert(bad("local a,"))
assert(bad("local a = "))
assert(bad("local (a) = 1"))
assert(bad("local a.b"))
assert(bad("local a[1] = 1"))
assert(bad("local function"))
assert(bad("local function f"))
assert(bad("local function f.g() end"))
assert(bad("local 'a' = 1"))
assert(bad("local nil"))
assert(bad("local ... = 1"))
end

-- ## table constructors
do
assert(ok("return {}"))
assert(ok("return {1, 2, 3}"))
assert(ok("return {a = 1, b = 2}"))
assert(ok("return {[1] = 1, [2] = 2}"))
assert(ok("return {1; 2; 3}"))
assert(ok("return {f(), g()}"))
assert(ok("return {...}"))
assert(ok("return {a = {b = {c = {}}}}"))
assert(ok("return {[{}] = {}}"))
assert(ok("return {function() end}"))
assert(ok("return {a = function() end, b = function() end}"))
assert(ok("return {[f()] = g()}"))
assert(ok("return {a, b = c, [d] = e; f}"))
assert(bad("return {a = 1 b = 2}"))
assert(bad("return {[a = 1}"))
assert(bad("return {a] = 1}"))
assert(bad("return {1 = 1}"))
assert(bad("return {'a' = 1}"))
assert(bad("return {a.b = 1}"))
assert(bad("return {a = }"))
assert(bad("return {,}"))
assert(bad("return {"))
end

-- ## strings and calls without parentheses
do
assert(ok("f 'a'"))
assert(ok('f "a"'))
assert(ok("f [[a]]"))
assert(ok("f {a = 1}"))
assert(ok("f 'a' 'b'"))
assert(ok("f 'a' {b}"))
assert(ok("o:m 'a'"))
assert(ok("o:m {a}"))
assert(ok("return f 'a' .. 'b'"))
assert(bad("f 1"))
assert(bad("f a"))
assert(bad("f nil"))
assert(bad("f function() end"))
assert(bad("f true"))
end

-- ## reserved words in wrong places
do
assert(bad("local t = {}; t.if = 1"))
assert(bad("local t = {}; t.end = 1"))
assert(bad("local t = {}; t:while()"))
assert(bad("function end() end"))
assert(bad("function f(local) end"))
assert(bad("function f(function) end"))
assert(bad("for while = 1, 2 do end"))
assert(bad("goto if"))
assert(bad("::for::"))
assert(ok("local t = {}; t['if'] = 1"))
assert(ok("local t = {['end'] = 1}"))
end

-- ## statements can be separated by nothing but whitespace
do
local f = load("local a = 1 local b = 2 local c = a + b return c")
assert(f() == 3)
local g = load("local t = {} t.x = 1 t.y = 2 return t.x + t.y")
assert(g() == 3)
local h = load("local s = 0 for i = 1, 3 do s = s + i end return s")
assert(h() == 6)
local k = load("local a local b a = 1 b = 2 return a + b")
assert(k() == 3)
end

-- ## a call may continue on the next line
do
local id = function(x) return x end
local r = id
(5)
assert(r == 5)
local s = id
"str"
assert(s == "str")
local t = id
{1}
assert(t[1] == 1)
end

-- ## long expressions spanning lines and comments
do
local v = 1 +
  2 -- comment
  * 3 --[[ another ]] - 4
assert(v == 3)
local w = (
  1
  +
  2
)
assert(w == 3)
local tbl = {
  -- comment inside a constructor
  1, --[[ x ]] 2,
  3 -- last
}
assert(#tbl == 3)
end

-- ## integer and float syntax in statements
do
assert(ok("local a = 0x10 + 0xA.8p0 + 1e2 + .5 + 5. + 3"))
assert(ok("return 1 .. 2"))
assert(ok("return 1. .. 2"))
assert(ok("return 0xep1"))
assert(ok("return 0x.1"))
assert(ok("return 1//2"))
assert(ok("return 1--[[c]]//2"))
assert(bad("return 1..2"))
assert(bad("return 0x"))
assert(bad("return 1e"))
assert(bad("return 1.5.2"))
assert(bad("return 0xg"))
end

-- ## attribs and 5.5 additions
do
assert(ok("local x <const> = 1"))
assert(ok("local x <close> = nil"))
assert(ok("global x"))
assert(ok("global <const> x"))
assert(ok("global *"))
assert(ok("global <const> *"))
assert(ok("global function f() end"))
assert(ok("local function f(...t) end"))
assert(ok("local <const> a, b = 1, 2"))
assert(bad("global <close> x"))
assert(bad("global function f.g() end"))
assert(bad("local x <const> = 1; x = 2"))
assert(bad("for i = 1, 2 do i = 1 end"))
assert(bad("global x; y = 1"))
assert(bad("local function f(...t, u) end"))
end

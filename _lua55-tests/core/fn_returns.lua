-- Functions: multiple results, adjustment, recursion and tail calls.
local load = loadstring or load

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end
local function mr() return 1, 2, 3 end
local function none() end
local function one() return "one" end

-- ## number of results
do
assert(select("#", none()) == 0)
assert(select("#", one()) == 1)
assert(select("#", mr()) == 3)
assert(select("#", (function() return end)()) == 0)
assert(select("#", (function() return nil end)()) == 1)
assert(select("#", (function() return nil, nil end)()) == 2)
end

-- ## adjustment in expression lists
do
assert(show(mr()) == "1,2,3")
assert(show(mr(), 10) == "1,10")
assert(show(10, mr()) == "10,1,2,3")
assert(show(mr(), mr()) == "1,1,2,3")
assert(show((mr())) == "1")
assert(show(none()) == "")
assert(show(none(), 1) == "nil,1")
assert(show(1, none()) == "1")
assert(show((none())) == "nil")
assert(show(none(), none()) == "nil")
assert(show(one(), none(), one()) == "one,nil,one")
end

-- ## adjustment in assignments
do
local a, b, c, d = mr()
assert(a == 1 and b == 2 and c == 3 and d == nil)
local e, f = mr()
assert(e == 1 and f == 2)
local g, h, i = 0, mr()
assert(g == 0 and h == 1 and i == 2)
local j, k = mr(), 10
assert(j == 1 and k == 10)
local l, m = none()
assert(l == nil and m == nil)
local n, o = (mr())
assert(n == 1 and o == nil)
local p, q = none(), 5
assert(p == nil and q == 5)
end

-- ## adjustment in table constructors
do
assert(#{mr()} == 3)
assert(#{mr(), mr()} == 4)
assert(#{mr(), 10} == 2)
assert(#{(mr())} == 1)
assert(#{none()} == 0)
assert(#{mr(), none()} == 1)
local t = {mr(), x = mr(), mr()}
assert(#t == 4)
assert(t.x == 1)
assert(t[4] == 3)
local t2 = {[1] = mr()}
assert(t2[1] == 1 and t2[2] == nil)
end

-- ## adjustment in return statements
do
local function r1() return mr() end
local function r2() return mr(), 10 end
local function r3() return (mr()) end
local function r4() return 10, mr() end
local function r5() return none() end
local function r6() return none(), none() end
assert(show(r1()) == "1,2,3")
assert(show(r2()) == "1,10")
assert(show(r3()) == "1")
assert(show(r4()) == "10,1,2,3")
assert(show(r5()) == "")
assert(show(r6()) == "nil")
end

-- ## results used as operands are truncated to one value
do
assert(mr() + 1 == 2)
assert(1 + mr() == 2)
assert(mr() == 1)
assert(-mr() == -1)
assert(mr() .. "" == "1")
assert(not pcall(function() return none() + 1 end))
assert((none()) == nil)
assert(#{mr()} + #{mr()} == 6)
local t = {10, 20, 30}
assert(t[mr()] == 10)
assert(({mr()})[3] == 3)
end

-- ## functions are first-class values
do
local function apply(fn, ...) return fn(...) end
assert(apply(mr) == 1)
assert(show(apply(show, 1, 2)) == "1,2")
local ops = {add = function(a, b) return a + b end, sub = function(a, b) return a - b end}
assert(ops.add(2, 3) == 5)
assert(ops["sub"](2, 3) == -1)
assert((function(x) return x * 2 end)(21) == 42)
local compose = function(f, g) return function(...) return f(g(...)) end end
local inc = function(x) return x + 1 end
local dbl = function(x) return x * 2 end
assert(compose(inc, dbl)(5) == 11)
assert(compose(dbl, inc)(5) == 12)
end

-- ## missing and extra arguments
do
local function args3(a, b, c) return show(a, b, c) end
assert(args3() == "nil,nil,nil")
assert(args3(1) == "1,nil,nil")
assert(args3(1, 2, 3, 4, 5) == "1,2,3")
assert(args3(mr()) == "1,2,3")
assert(args3(mr(), 9) == "1,9,nil")
assert(args3(none()) == "nil,nil,nil")
local function noargs() return "ok" end
assert(noargs(1, 2, 3) == "ok")
end

-- ## parameters are locals
do
local function modify(a, b)
  a = a + 1
  b = nil
  return a, b
end
local x, y = 1, 2
local ra, rb = modify(x, y)
assert(ra == 2 and rb == nil)
assert(x == 1 and y == 2)
local function shadow(a, a) return a end
assert(shadow(1, 2) == 2)
local function tbl(t) t.x = 1; t = nil end
local tt = {}
tbl(tt)
assert(tt.x == 1)
end

-- ## recursion
do
local function fact(n) if n <= 1 then return 1 end return n * fact(n - 1) end
assert(fact(20) == 2432902008176640000)
assert(tostring(fact(20)) == "2432902008176640000")
assert(fact(21) == -4249290049419214848)
local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end
assert(fib(20) == 6765)
local function depth(n) if n == 0 then return 0 end return 1 + depth(n - 1) end
assert(depth(150) == 150)
local function ack(m, n)
  if m == 0 then return n + 1 end
  if n == 0 then return ack(m - 1, 1) end
  return ack(m - 1, ack(m, n - 1))
end
assert(ack(2, 3) == 9)
end

-- ## mutual recursion
do
local is_even, is_odd
function is_even(n) if n == 0 then return true end return is_odd(n - 1) end
function is_odd(n) if n == 0 then return false end return is_even(n - 1) end
assert(is_even(10) == true)
assert(is_odd(7) == true)
assert(is_even(7) == false)
end

-- ## tail calls do not grow the stack
do
local function loop(n, acc)
  if n == 0 then return acc end
  return loop(n - 1, acc + n)
end
assert(loop(1000000, 0) == 500000500000)
local ping, pong
function ping(n) if n == 0 then return "ping" end return pong(n - 1) end
function pong(n) if n == 0 then return "pong" end return ping(n - 1) end
assert(ping(1000001) == "pong")
assert(ping(1000000) == "ping")
local function tail_varargs(n, ...)
  if n == 0 then return select("#", ...) end
  return tail_varargs(n - 1, ...)
end
assert(tail_varargs(200000, 1, 2, 3) == 3)
end

-- ## tail calls through methods and fields
do
local obj = {}
function obj:count(n) if n == 0 then return self end return self:count(n - 1) end
assert(obj:count(300000) == obj)
local tbl = {}
tbl.f = function(n) if n == 0 then return "done" end return tbl.f(n - 1) end
assert(tbl.f(300000) == "done")
end

-- ## tail calls return all results
do
local function many() return 1, 2, 3 end
local function tail() return many() end
local function tail2() return tail() end
assert(show(tail2()) == "1,2,3")
local function nottail() return (many()) end
assert(show(nottail()) == "1")
end

-- ## non-tail recursion overflows with a catchable error
do
local function inf_rec(n) return 1 + inf_rec(n + 1) end
local ok, err = pcall(inf_rec, 1)
assert(ok == false)
assert(err ~= nil)
local function inf_rec2() local x = inf_rec2(); return x end
assert(pcall(inf_rec2) == false)
-- the state is still usable afterwards
local function small(n) if n == 0 then return 0 end return 1 + small(n - 1) end
assert(small(50) == 50)
assert(pcall(inf_rec, 1) == false)
assert(small(50) == 50)
end

-- ## return statement syntax
do
assert(load("return") ~= nil)
assert(load("return;") ~= nil)
assert(load("return 1, 2, 3") ~= nil)
assert(load("return 1, 2, 3;") ~= nil)
assert(load("return return") == nil)
assert(load("return 1,") == nil)
assert(load("return , 1") == nil)
assert(load("do return end") ~= nil)
assert(load("do return 1 end return 2") ~= nil)
assert(load("return 1 print(2)") == nil)
assert(load("if a then return 1 else return 2 end") ~= nil)
assert(load("function f() return end") ~= nil)
end

-- ## function definition syntax
do
assert(load("function f() end") ~= nil)
assert(load("function t.a.b.c() end") ~= nil)
assert(load("function t.a.b:c() end") ~= nil)
assert(load("function t:a.b() end") == nil)
assert(load("function t[1]() end") == nil)
assert(load("function () end") == nil)
assert(load("function f end") == nil)
assert(load("function f( end") == nil)
assert(load("function f(a,) end") == nil)
assert(load("function f(a b) end") == nil)
assert(load("function f(1) end") == nil)
assert(load("function f(a, a) end") ~= nil)
assert(load("local function f.g() end") == nil)
assert(load("local function f:g() end") == nil)
assert(load("local f = function() end") ~= nil)
assert(load("local f = function f() end") == nil)
assert(load("return function() end") ~= nil)
assert(load("function f() return function() return function() end end end") ~= nil)
end

-- ## function statements assign to fields and globals
do
local t = {a = {b = {}}}
function t.f() return "f" end
function t.a.g() return "g" end
function t.a.b.h(x) return x end
function t.a.b:m(x) return self, x end
assert(t.f() == "f")
assert(t.a.g() == "g")
assert(t.a.b.h(1) == 1)
local s, x = t.a.b:m(2)
assert(s == t.a.b and x == 2)
function FN_RETURNS_GLOBAL() return "global" end
assert(FN_RETURNS_GLOBAL() == "global")
FN_RETURNS_GLOBAL = nil
end

-- ## calling non-functions raises an error
do
assert(not pcall(function() local x = nil; x() end))
assert(not pcall(function() local x = 5; x() end))
assert(not pcall(function() local x = "s"; x() end))
assert(not pcall(function() local x = {}; x() end))
assert(not pcall(function() local t = {}; t.missing() end))
assert(not pcall(function() local t = {}; t:missing() end))
assert(not pcall(function() undefined_function_xyz() end))
assert(not pcall(function() return (true)() end))
end

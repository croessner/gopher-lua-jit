-- Functions: assignment, multiple assignment and evaluation order.
local load = loadstring or load

-- ## multiple assignment adjusts the number of values
do
local a, b, c = 1, 2
assert(a == 1 and b == 2 and c == nil)
local d, e = 1, 2, 3
assert(d == 1 and e == 2)
local f, g, h = (function() return 1, 2, 3 end)()
assert(f == 1 and g == 2 and h == 3)
local i, j, k = 0, (function() return 1, 2, 3 end)()
assert(i == 0 and j == 1 and k == 2)
local l, m, n = (function() return 1, 2, 3 end)(), 10
assert(l == 1 and m == 10 and n == nil)
local o, p = ((function() return 1, 2 end)())
assert(o == 1 and p == nil)
local q, r
assert(q == nil and r == nil)
end

-- ## swap and rotation
do
local x, y = 1, 2
x, y = y, x
local a, b, c = 1, 2, 3
a, b, c = b, c, a
local t = {1, 2}
t[1], t[2] = t[2], t[1]
assert(t[1] == 2 and t[2] == 1)
end

-- ## all expressions are evaluated before assignment
do
local i = 1
local t = {}
i, t[i] = i + 1, 20
assert(i == 2)
assert(t[1] == 20)
assert(t[2] == nil)
local a = {}
local idx = 1
idx, a[idx], a[idx + 1] = 5, "one", "two"
assert(idx == 5 and a[1] == "one" and a[2] == "two")
local x, y = 1, 2
x, y = x + y, x - y
end

-- ## assignment to globals, fields and upvalues together
do
local up = 0
local t = {}
local function setall() GLOBAL_ASSIGN_TEST, t.f, up = 1, 2, 3 end
setall()
assert(GLOBAL_ASSIGN_TEST == 1 and t.f == 2 and up == 3)
GLOBAL_ASSIGN_TEST = nil
assert(GLOBAL_ASSIGN_TEST == nil)
end

-- ## excess values are evaluated and discarded
do
local calls = 0
local function tick() calls = calls + 1; return calls end
local a = tick(), tick(), tick()
assert(a == 1)
assert(calls == 3)
local b
b = tick(), tick()
assert(b == 4)
assert(calls == 5)
end

-- ## evaluation order of function arguments and operands is left to right
do
local order = {}
local function mark(v) order[#order + 1] = v; return v end
local function three(a, b, c) return a, b, c end
three(mark(1), mark(2), mark(3))
assert(table.concat(order, ",") == "1,2,3")
order = {}
local _ = mark(1) + mark(2) * mark(3)
assert(table.concat(order, ",") == "1,2,3")
order = {}
local _ = {mark(1), mark(2), k = mark(3), mark(4)}
assert(table.concat(order, ",") == "1,2,3,4")
order = {}
local _ = mark("a") .. mark("b") .. mark("c")
assert(table.concat(order, ",") == "a,b,c")
end

-- ## nested table assignment
do
local t = {a = {b = {c = 1}}}
t.a.b.c = 2
assert(t.a.b.c == 2)
t.a.b.d, t.a.e = 3, 4
assert(t.a.b.d == 3 and t.a.e == 4)
t["a"]["b"]["c"] = t.a.b.c + 1
assert(t.a.b.c == 3)
local k = "a"
t[k].b = nil
assert(t.a.b == nil)
end

-- ## local declarations: scope starts after the statement
do
local x = 10
local x = x + 1
assert(x == 11)
do
  local x = x * 2
  assert(x == 22)
end
assert(x == 11)
local function f() return x end
local x = 0
assert(f() == 11)
local y = y
assert(y == nil)
end

-- ## local function versus local assignment and recursion
do
local function fact(n) if n <= 1 then return 1 else return n * fact(n - 1) end end
assert(fact(10) == 3628800)
local fib
fib = function(n) if n < 2 then return n else return fib(n - 1) + fib(n - 2) end end
assert(fib(15) == 610)
local notrec = function(n) return notrec end
end

-- ## assignment syntax errors
do
assert(load("1 = 2") == nil)
assert(load("a, 1 = 2") == nil)
assert(load("f() = 1") == nil)
assert(load("a + b = 1") == nil)
assert(load("a = ") == nil)
assert(load("a, = 1") == nil)
assert(load("local a, = 1") == nil)
assert(load("local 1") == nil)
assert(load("local a.b = 1") == nil)
assert(load("a.b, c[1], d = 1, 2, 3") ~= nil)
assert(load("f().x = 1") ~= nil)
assert(load("f()[1] = 1") ~= nil)
assert(load("('x').y = 1") ~= nil)
assert(load("a") == nil)
assert(load("a.b") == nil)
assert(load("'x'") == nil)
assert(load("1") == nil)
assert(load("nil") == nil)
assert(load("a:b") == nil)
end

-- ## expression statements must be calls
do
assert(load("f()") ~= nil)
assert(load("f() g()") ~= nil)
assert(load("a.b.c()") ~= nil)
assert(load("a:b()") ~= nil)
assert(load("f{}") ~= nil)
assert(load("f''") ~= nil)
assert(load("f[[x]]") ~= nil)
assert(load("(f)()") ~= nil)
assert(load("f()()") ~= nil)
assert(load("f().g()") ~= nil)
assert(load("(f)") == nil)
assert(load("f().g") == nil)
end

-- ## indexing nil in an assignment raises an error
do
local t = {}
assert(not pcall(function() t.a.b = 1 end))
assert(not pcall(function() local n = nil; n.x = 1 end))
assert(not pcall(function() local n = 5; n.x = 1 end))
assert(not pcall(function() undefined_global_xyz.field = 1 end))
end

-- ## multiple assignment to locals reads the old values
do
local a, b = 1, 2
a, b = b, a + b
assert(a == 2)
local p, q, r = 1, 2, 3
p, q, r = r, p, q
assert(p == 3)
local function fibs(n)
  local x, y = 0, 1
  for _ = 1, n do x, y = y, x + y end
  return x
end
local function swap_params(m, n)
  m, n = n, m
  return m, n
end
local s1, s2 = swap_params("m", "n")
assert(s1 == "n")
local function gcd(m, n)
  while n ~= 0 do m, n = n, m % n end
  return m
end
end

-- ## multiple assignment to upvalues and globals reads the old values
do
local u, v = 1, 2
local function swap_up() u, v = v, u end
swap_up()
assert(u == 2 and v == 1)
SWAP_G1, SWAP_G2 = 1, 2
SWAP_G1, SWAP_G2 = SWAP_G2, SWAP_G1
assert(SWAP_G1 == 2 and SWAP_G2 == 1)
SWAP_G1, SWAP_G2 = nil, nil
end

-- ## mixed local and table targets
do
local t = {x = 1}
local l = 2
t.x, l = l, t.x
assert(l == 1)
local a = {1, 2, 3}
local i = 1
i, a[i] = a[i] + 1, i + 10
assert(i == 2)
end

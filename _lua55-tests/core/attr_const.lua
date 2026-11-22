-- Local attributes: <const>.
local load = loadstring or load

-- ## const locals hold any value
do
local a <const> = 1
local b <const> = "str"
local c <const> = {1, 2}
local d <const> = nil
local e <const> = function() return "f" end
local f <const>, g <const> = 10, 20
assert(a == 1 and b == "str" and c[2] == 2 and d == nil and e() == "f")
assert(f + g == 30)
local h <const> = a + f
assert(h == 11)
end

-- ## the contents of a const table can change
do
local t <const> = {}
t.x = 1
t[1] = "one"
assert(t.x == 1 and t[1] == "one")
t.x = nil
assert(t.x == nil)
end

-- ## const values are captured by closures
do
local k <const> = 42
local function get() return k end
assert(get() == 42)
local s <const> = "up"
local function nested() return function() return s .. k end end
assert(nested()() == "up42")
local tbl <const> = {n = 0}
local function inc() tbl.n = tbl.n + 1; return tbl.n end
assert(inc() == 1 and inc() == 2)
end

-- ## compile-time constants fold into expressions
do
local x <const> = 10
local y <const> = x * 2 + 1
assert(y == 21)
local z <const> = 2.5
assert(z * 2 == 5.0)
local flag <const> = true
local r
if flag then r = "yes" else r = "no" end
assert(r == "yes")
local n <const> = nil
assert(n == nil)
local idx <const> = 2
assert(({10, 20, 30})[idx] == 20)
end

-- ## assignment to a const local is a compile-time error
do
assert(load("local x <const> = 1; x = 2") == nil)
assert(load("local x <const> = 1; x, y = 2, 3") == nil)
assert(load("local x <const> = 1; y, x = 2, 3") == nil)
assert(load("local x <const> = 1; local function f() x = 2 end") == nil)
assert(load("local x <const> = 1; return function() return function() x = 2 end end") == nil)
assert(load("local x <const> = 1; function x() end") == nil)
assert(load("local x <const> = 1; for x = 1, 2 do end") ~= nil)
assert(load("local x <const> = {}; x.y = 1") ~= nil)
assert(load("local x <const> = {}; x[1] = 1") ~= nil)
assert(load("local x <const> = {}; function x.f() end") ~= nil)
assert(load("local x <const> = {}; function x:m() end") ~= nil)
assert(load("local x <const> = 1; local x = 2; x = 3") ~= nil)
assert(load("local x <const> = 1; do local x; x = 3 end") ~= nil)
assert(load("local a <const>, b = 1, 2; b = 3") ~= nil)
assert(load("local a <const>, b = 1, 2; a = 3") == nil)
assert(load("local a, b <const> = 1, 2; a = 3") ~= nil)
assert(load("local a, b <const> = 1, 2; b = 3") == nil)
assert(load("local x <const>; x = 1") == nil)
assert(load("local x <const> = 1; x = x") == nil)
end

-- ## attribute syntax
do
assert(load("local x <const> = 1") ~= nil)
assert(load("local x<const> = 1") ~= nil)
assert(load("local x < const > = 1") ~= nil)
assert(load("local x <const>") ~= nil)
assert(load("local x <close> = nil") ~= nil)
assert(load("local x <unknown> = 1") == nil)
assert(load("local x <Const> = 1") == nil)
assert(load("local x <> = 1") == nil)
assert(load("local x <const = 1") == nil)
assert(load("local x const> = 1") == nil)
assert(load("local x <const> <const> = 1") == nil)
assert(load("local x <const, close> = 1") == nil)
assert(load("local <const> x = 1") ~= nil)
assert(load("local <const> x, y = 1, 2; x = 3") == nil)
assert(load("local <const> x, y = 1, 2; y = 3") == nil)
assert(load("local <close> x = nil") ~= nil)
assert(load("local <const> x <close> = nil") ~= nil)
assert(load("local function f <const> () end") == nil)
assert(load("local x <1> = 1") == nil)
assert(load("x <const> = 1") == nil)
assert(load("local function f(a <const>) end") == nil)
assert(load("for i <const> = 1, 2 do end") == nil)
end

-- ## 'const' and 'close' are not reserved words
do
local const, close = 1, 2
assert(const + close == 3)
local const <const> = 5
assert(const == 5)
local t = {const = 1, close = 2}
assert(t.const + t.close == 3)
end

-- ## shadowing a const local
do
local v <const> = 1
do
  local v = 2
  v = 3
  assert(v == 3)
end
assert(v == 1)
local function f(v) v = 10; return v end
assert(f(0) == 10)
assert(v == 1)
end

-- ## const locals in loops are fresh per iteration
do
local fns = {}
for i = 1, 3 do
  local c <const> = i * 2
  fns[i] = function() return c end
end
assert(fns[1]() == 2 and fns[2]() == 4 and fns[3]() == 6)
end

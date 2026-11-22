-- Functions: assignment, multiple assignment and evaluation order.
local load = loadstring or load

-- ## swap and rotation
do
local x, y = 1, 2
x, y = y, x
assert(x == 2 and y == 1)
local a, b, c = 1, 2, 3
a, b, c = b, c, a
assert(a == 2 and b == 3 and c == 1)
local t = {1, 2}
t[1], t[2] = t[2], t[1]
end

-- ## all expressions are evaluated before assignment
do
local i = 1
local t = {}
i, t[i] = i + 1, 20
local a = {}
local idx = 1
idx, a[idx], a[idx + 1] = 5, "one", "two"
local x, y = 1, 2
x, y = x + y, x - y
assert(x == 3 and y == -1)
end

-- ## local function versus local assignment and recursion
do
local function fact(n) if n <= 1 then return 1 else return n * fact(n - 1) end end
local fib
fib = function(n) if n < 2 then return n else return fib(n - 1) + fib(n - 2) end end
local notrec = function(n) return notrec end
assert(notrec() == nil)
end

-- ## assignment syntax errors
do
assert(load("(a) = 1") == nil)
end

-- ## multiple assignment to locals reads the old values
do
local a, b = 1, 2
a, b = b, a + b
assert(b == 3)
local p, q, r = 1, 2, 3
p, q, r = r, p, q
assert(q == 1)
assert(r == 2)
local function fibs(n)
  local x, y = 0, 1
  for _ = 1, n do x, y = y, x + y end
  return x
end
assert(fibs(10) == 55)
local function swap_params(m, n)
  m, n = n, m
  return m, n
end
local s1, s2 = swap_params("m", "n")
assert(s2 == "m")
local function gcd(m, n)
  while n ~= 0 do m, n = n, m % n end
  return m
end
assert(gcd(48, 18) == 6)
end

-- ## mixed local and table targets
do
local t = {x = 1}
local l = 2
t.x, l = l, t.x
assert(t.x == 2)
local a = {1, 2, 3}
local i = 1
i, a[i] = a[i] + 1, i + 10
assert(a[1] == 11)
end

-- ## a local function expression does not see its own local
do
local probe = "outer"
do
  local probe = function() return probe end
  assert(probe() == "outer")
end
local selfref = function() return selfref end
assert(selfref() == nil)
end

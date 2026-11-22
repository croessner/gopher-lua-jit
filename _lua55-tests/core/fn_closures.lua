-- Functions: closures and upvalues.

-- ## counters keep private state
do
local function counter()
  local n = 0
  return function() n = n + 1; return n end
end
local c1, c2 = counter(), counter()
assert(c1() == 1)
assert(c1() == 2)
assert(c2() == 1)
assert(c1() == 3)
assert(c2() == 2)
end

-- ## closures created together share upvalues
do
local function account(balance)
  local function deposit(x) balance = balance + x end
  local function withdraw(x) balance = balance - x end
  local function get() return balance end
  return deposit, withdraw, get
end
local dep, wd, get = account(100)
dep(50)
wd(30)
assert(get() == 120)
local dep2, _, get2 = account(0)
dep2(1)
assert(get2() == 1)
assert(get() == 120)
end

-- ## upvalues are shared while the enclosing function is still running
do
local x = 1
local function getx() return x end
local function setx(v) x = v end
assert(getx() == 1)
x = 2
assert(getx() == 2)
setx(3)
assert(x == 3)
assert(getx() == 3)
end

-- ## numeric for loops create a fresh variable per iteration
do
local fns = {}
for i = 1, 5 do fns[i] = function() return i end end
for i = 1, 5 do assert(fns[i]() == i, "numeric for") end
end

-- ## locals inside loop bodies are fresh per iteration
do
local fns = {}
for i = 1, 3 do
  local j = i * 10
  fns[i] = {get = function() return j end, inc = function() j = j + 1 end}
end
fns[1].inc()
fns[1].inc()
fns[3].inc()
assert(fns[1].get() == 12)
assert(fns[2].get() == 20)
assert(fns[3].get() == 31)
end

-- ## while and repeat loops
do
local fns = {}
local i = 1
while i <= 3 do
  local k = i
  fns[i] = function() return k end
  i = i + 1
end
assert(fns[1]() == 1 and fns[2]() == 2 and fns[3]() == 3)
fns = {}
i = 1
repeat
  local k = i
  fns[i] = function() return k end
  i = i + 1
until k >= 3
assert(fns[1]() == 1 and fns[2]() == 2 and fns[3]() == 3)
end

-- ## a variable declared outside the loop is shared
do
local fns = {}
local shared = 0
for i = 1, 3 do
  shared = shared + 1
  fns[i] = function() return shared end
end
assert(fns[1]() == 3 and fns[2]() == 3 and fns[3]() == 3)
end

-- ## break and return close the upvalues of the loop body
do
local captured
for i = 1, 10 do
  local v = i * 2
  captured = function() return v end
  if i == 3 then break end
end
assert(captured() == 6)
local function early()
  for i = 1, 10 do
    local v = i * 3
    if i == 2 then return function() return v end end
  end
end
assert(early()() == 6)
end

-- ## nested closures over several levels
do
local function level1()
  local a = 1
  return function()
    local b = 2
    return function()
      local c = 3
      return function()
        a = a + 1
        return a + b + c
      end
    end
  end
end
local deep = level1()()()
assert(deep() == 7)
assert(deep() == 8)
end

-- ## an upvalue of an upvalue is the same variable
do
local function outer()
  local v = 0
  local function mid()
    local function inner() v = v + 1; return v end
    return inner
  end
  return mid(), mid(), function() return v end
end
local i1, i2, getv = outer()
assert(i1() == 1)
assert(i2() == 2)
assert(getv() == 2)
end

-- ## closures capture parameters and varargs copies
do
local function adder(n) return function(x) return x + n end end
local add5, add10 = adder(5), adder(10)
assert(add5(1) == 6)
assert(add10(1) == 11)
local function pack_later(...)
  local args = {...}
  return function() return #args, args[1] end
end
local n, first = pack_later("a", "b", "c")()
assert(n == 3 and first == "a")
end

-- ## recursive closures via a local function
do
local function make_fact()
  local function fact(n) if n <= 1 then return 1 end return n * fact(n - 1) end
  return fact
end
assert(make_fact()(6) == 720)
end

-- ## closures stored in tables keep their environment
do
local objs = {}
for i = 1, 3 do
  local state = {id = i}
  objs[i] = {
    id = function() return state.id end,
    set = function(v) state.id = v end,
  }
end
objs[2].set(20)
assert(objs[1].id() == 1)
assert(objs[2].id() == 20)
assert(objs[3].id() == 3)
end

-- ## each evaluation of a function expression with upvalues is a new closure
do
local function mk() local u = {}; return function() return u end end
local f1, f2 = mk(), mk()
assert(f1 ~= f2)
assert(f1() ~= f2())
assert(f1() == f1())
end

-- ## closures over block locals after the block ends
do
local get, set
do
  local hidden = "initial"
  get = function() return hidden end
  set = function(v) hidden = v end
end
assert(get() == "initial")
set("changed")
assert(get() == "changed")
end

-- ## shadowing does not affect captured variables
do
local v = "first"
local function get_first() return v end
local v = "second"
local function get_second() return v end
assert(get_first() == "first")
assert(get_second() == "second")
v = "third"
assert(get_first() == "first")
assert(get_second() == "third")
end

-- ## many closures in a loop
do
local total = 0
local last
for i = 1, 100000 do
  local f = function() return i end
  total = total + f()
  last = f
end
assert(total == 5000050000)
assert(last() == 100000)
end

-- ## many upvalues in one closure
do
local a1, a2, a3, a4, a5, a6, a7, a8, a9, a10 = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
local b1, b2, b3, b4, b5, b6, b7, b8, b9, b10 = 11, 12, 13, 14, 15, 16, 17, 18, 19, 20
local c1, c2, c3, c4, c5, c6, c7, c8, c9, c10 = 21, 22, 23, 24, 25, 26, 27, 28, 29, 30
local function sum_all()
  return a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 + a10
       + b1 + b2 + b3 + b4 + b5 + b6 + b7 + b8 + b9 + b10
       + c1 + c2 + c3 + c4 + c5 + c6 + c7 + c8 + c9 + c10
end
assert(sum_all() == 465)
a1, c10 = 101, 130
assert(sum_all() == 665)
end

-- ## upvalues in coroutines
do
local function gen()
  local n = 0
  return coroutine.wrap(function()
    while true do
      n = n + 1
      coroutine.yield(n)
    end
  end), function() return n end
end
local nextval, peek = gen()
assert(nextval() == 1)
assert(nextval() == 2)
assert(peek() == 2)
end

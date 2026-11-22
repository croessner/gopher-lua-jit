-- Control flow: the numeric for loop.
local load = loadstring or load
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1
local inf = 1 / 0

-- collects the values of a loop as a comma separated string
local function run(a, b, c)
  local out = {}
  if c == nil then
    for i = a, b do out[#out + 1] = T(i) end
  else
    for i = a, b, c do out[#out + 1] = T(i) end
  end
  return table.concat(out, ",")
end

-- ## integer loops
do
assert(run(1, 5) == "1,2,3,4,5")
assert(run(1, 1) == "1")
assert(run(1, 0) == "")
assert(run(0, 0) == "0")
assert(run(-2, 2) == "-2,-1,0,1,2")
assert(run(1, 10, 3) == "1,4,7,10")
assert(run(1, 9, 3) == "1,4,7")
assert(run(10, 1, -3) == "10,7,4,1")
assert(run(5, 1, -1) == "5,4,3,2,1")
assert(run(5, 1) == "")
assert(run(1, 5, -1) == "")
assert(run(1, 5, 10) == "1")
assert(run(5, 5, -1) == "5")
assert(run(3, 1, -5) == "3")
end

-- ## float loops
do
assert(run(1.0, 3) == "1.0,2.0,3.0")
assert(run(1, 3, 1.0) == "1.0,2.0,3.0")
assert(run(1.0, 3.0, 1.0) == "1.0,2.0,3.0")
assert(run(1, 2, 0.5) == "1.0,1.5,2.0")
assert(run(1, 2, 0.25) == "1.0,1.25,1.5,1.75,2.0")
assert(run(2, 1, -0.5) == "2.0,1.5,1.0")
assert(run(0.5, 2.5) == "0.5,1.5,2.5")
assert(run(1.5, 1) == "")
assert(run(-1.0, 1) == "-1.0,0.0,1.0")
assert(run(1.0, 0) == "")
assert(run(3.0, 1.0, -1) == "3.0,2.0,1.0")
end

-- ## an integer loop with a float limit stays an integer loop
do
assert(run(1, 3.0) == "1,2,3")
assert(run(1, 3.9) == "1,2,3")
assert(run(1, 0.9) == "")
assert(run(3, 1.1, -1) == "3,2")
assert(run(3, 0.9, -1) == "3,2,1")
assert(run(-3, -1.5) == "-3,-2")
assert(run(-1, -3.5, -1) == "-1,-2,-3")
assert(run(1, 2.0, 1) == "1,2")
end

-- ## floating point accumulation
do
local n, last = 0, nil
for i = 0.1, 1, 0.1 do n = n + 1; last = i end
assert(n == 10)
assert(T(last) == "0.99999999999999989")
n = 0
for i = 1, 0, -0.1 do n = n + 1 end
assert(n == 10 or n == 11)
n = 0
for i = 0, 1, 0.25 do n = n + 1 end
assert(n == 5)
end

-- ## limits that are infinite or NaN
do
local n, last = 0, nil
for i = 1, inf do n = n + 1; last = i; if i >= 5 then break end end
assert(n == 5)
assert(T(last) == "5")
assert(run(1, -inf) == "")
assert(run(1, inf, -1) == "")
assert(run(1, 0 / 0) == "")
n = 0
for i = 1, -inf, -1 do n = n + 1; if n >= 3 then break end end
assert(n == 3)
n = 0
for i = 1.0, inf do n = n + 1; if n >= 3 then break end end
assert(n == 3)
end

-- ## no overflow at the integer limits
do
assert(run(maxint - 2, maxint) == "9223372036854775805,9223372036854775806,9223372036854775807")
assert(run(maxint, maxint) == "9223372036854775807")
assert(run(minint, minint + 2) == "-9223372036854775808,-9223372036854775807,-9223372036854775806")
assert(run(minint + 2, minint, -1) == "-9223372036854775806,-9223372036854775807,-9223372036854775808")
assert(run(minint, minint, -1) == "-9223372036854775808")
assert(run(maxint - 2, inf) == "9223372036854775805,9223372036854775806,9223372036854775807")
assert(run(minint + 2, -inf, -1) == "-9223372036854775806,-9223372036854775807,-9223372036854775808")
assert(run(maxint - 1, maxint, 2) == "9223372036854775806")
assert(run(maxint - 1, maxint, maxint) == "9223372036854775806")
assert(run(1, 3, maxint) == "1")
assert(run(3, 1, minint) == "3")
assert(run(minint, maxint, maxint) == "-9223372036854775808,-1,9223372036854775806")
assert(run(maxint, minint, minint) == "9223372036854775807,-1")
assert(run(maxint, 1e300) == "9223372036854775807")
assert(run(minint, -1e300, -1) == "-9223372036854775808")
assert(run(maxint, maxint - 1) == "")
assert(run(0, maxint, maxint) == "0,9223372036854775807")
assert(run(-1, minint, minint) == "-1")
assert(run(maxint - 5, maxint, 3) == "9223372036854775802,9223372036854775805")
end

-- ## a zero step raises an error
do
assert(not pcall(function() for i = 1, 10, 0 do end end))
assert(not pcall(function() for i = 1.0, 10, 0 do end end))
assert(not pcall(function() for i = 1, 10, 0.0 do end end))
assert(not pcall(function() for i = 1, 10, -0.0 do end end))
assert(not pcall(function() for i = 10, 1, 0 do end end))
local z = 0
assert(not pcall(function() for i = 1, 10, z do end end))
end

-- ## non-numeric control values raise an error
do
assert(not pcall(function() for i = nil, 10 do end end))
assert(not pcall(function() for i = 1, nil do end end))
assert(not pcall(function() for i = 1, 10, nil do end end))
assert(not pcall(function() for i = {}, 10 do end end))
assert(not pcall(function() for i = 1, {} do end end))
assert(not pcall(function() for i = 1, 10, {} do end end))
assert(not pcall(function() for i = "a", 10 do end end))
assert(not pcall(function() for i = 1, "x" do end end))
assert(not pcall(function() for i = 1, 10, "y" do end end))
assert(not pcall(function() for i = true, 10 do end end))
assert(not pcall(function() for i = 1, print do end end))
end

-- ## a string limit is converted and keeps an integer loop
do
assert(run(1, "3") == "1,2,3")
assert(run(1, "3.5") == "1,2,3")
assert(run(1, " 3 ") == "1,2,3")
assert(run(1, "0x3") == "1,2,3")
assert(run(3, "1", -1) == "3,2,1")
assert(run(1.0, "3") == "1.0,2.0,3.0")
end

-- ## a string initial value or step makes it a float loop
do
assert(run("1.0", 3) == "1.0,2.0,3.0")
assert(run(1, 2, "0.5") == "1.0,1.5,2.0")
end

-- ## the control expressions are evaluated once, before the loop
do
local calls = 0
local function lim() calls = calls + 1; return 3 end
local n = 0
for i = 1, lim() do n = n + 1 end
assert(calls == 1)
assert(n == 3)
local order = {}
local function mark(name, v) order[#order + 1] = name; return v end
for i = mark("init", 1), mark("limit", 2), mark("step", 1) do end
assert(table.concat(order, ",") == "init,limit,step")
local limit = 3
n = 0
for i = 1, limit do limit = 10; n = n + 1 end
assert(n == 3)
end

-- ## the loop variable is local to the body and fresh per iteration
do
local i = "outer"
for i = 1, 3 do end
assert(i == "outer")
local fns = {}
for i = 1, 3 do fns[i] = function() return i end end
assert(fns[1]() == 1)
assert(fns[2]() == 2)
assert(fns[3]() == 3)
local setters, getters = {}, {}
for i = 1, 2 do
  local v = i
  setters[i] = function(x) v = x end
  getters[i] = function() return v end
end
setters[1](10)
assert(getters[1]() == 10)
assert(getters[2]() == 2)
end

-- ## the loop variable cannot be assigned
do
assert(load("for i = 1, 2 do i = 3 end") == nil)
assert(load("for i = 1, 2 do i, x = 3, 4 end") == nil)
assert(load("for i = 1, 2 do x, i = 3, 4 end") == nil)
assert(load("for i = 1, 2 do local function f() i = 3 end end") == nil)
assert(load("for i = 1, 2 do function i() end end") == nil)
assert(load("for i = 1, 2 do for j = 1, 2 do i = j end end") == nil)
assert(load("for i = 1, 2 do local i = 3; i = 4 end") ~= nil)
assert(load("for i = 1, 2 do local j = i; j = 4 end") ~= nil)
assert(load("for i = 1, 2 do i.x = 3 end") ~= nil)
assert(load("for i = 1, 2 do x = i end") ~= nil)
end

-- ## malformed numeric for loops are rejected
do
assert(load("for i = 1 do end") == nil)
assert(load("for i = 1, 2, 3, 4 do end") == nil)
assert(load("for i = do end") == nil)
assert(load("for = 1, 2 do end") == nil)
assert(load("for i = 1, 2 end") == nil)
assert(load("for i = 1, 2 do") == nil)
assert(load("for i, j = 1, 2 do end") == nil)
assert(load("for 1 = 1, 2 do end") == nil)
assert(load("for t.x = 1, 2 do end") == nil)
assert(load("for i = 1, 2, do end") == nil)
end

-- ## break, nested loops and sums
do
local sum = 0
for i = 1, 100 do
  if i > 10 then break end
  sum = sum + i
end
assert(sum == 55)
local pairs_seen = 0
for i = 1, 5 do
  for j = i, 5 do
    pairs_seen = pairs_seen + 1
  end
end
assert(pairs_seen == 15)
local total = 0
for i = 10, 1, -1 do
  for j = 1, i, 2 do total = total + 1 end
end
assert(total == 30)
end

-- ## large iteration counts
do
local n = 0
for i = 1, 100000 do n = n + i end
assert(n == 5000050000)
assert(T(n) == "5000050000")
local f = 0.0
for i = 1, 100000 do f = f + 0.5 end
assert(f == 50000.0)
end

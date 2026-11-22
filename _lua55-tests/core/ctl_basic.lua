-- Control flow: if/elseif/else, while, repeat and their scoping rules.
local load = loadstring or load

-- ## if / elseif / else
do
local function classify(n)
  if n < 0 then
    return "neg"
  elseif n == 0 then
    return "zero"
  elseif n < 10 then
    return "small"
  else
    return "big"
  end
end
assert(classify(-1) == "neg")
assert(classify(0) == "zero")
assert(classify(5) == "small")
assert(classify(10) == "big")
assert(classify(-0.0) == "zero")
assert(classify(9.5) == "small")
end

-- ## truthiness: only nil and false are false
do
local function truthy(v) if v then return true else return false end end
assert(truthy(0) == true)
assert(truthy(0.0) == true)
assert(truthy("") == true)
assert(truthy({}) == true)
assert(truthy(truthy) == true)
assert(truthy(0 / 0) == true)
assert(truthy(true) == true)
assert(truthy(false) == false)
assert(truthy(nil) == false)
assert(truthy() == false)
end

-- ## if without else, empty branches
do
local x = 0
if true then end
if false then x = 1 end
assert(x == 0)
if nil then x = 1 else end
assert(x == 0)
if false then elseif false then else x = 2 end
assert(x == 2)
if x == 2 then x = 3 elseif x == 3 then x = 4 end
assert(x == 3)
end

-- ## conditions with and/or/not and comparisons
do
local a, b = 1, 2
local r
if a < b and b < 3 then r = 1 else r = 2 end
assert(r == 1)
if a > b or b > 3 then r = 1 else r = 2 end
assert(r == 2)
if not (a == b) then r = 3 end
assert(r == 3)
if a == 1 and (b == 3 or b == 2) and not nil then r = 4 end
assert(r == 4)
if nil or false then r = 5 end
assert(r == 4)
if a ~= b and a then r = 6 end
assert(r == 6)
end

-- ## scope of locals in branches
do
local v = "outer"
if true then
  local v = "inner"
  assert(v == "inner")
end
assert(v == "outer")
if false then local w = 1 else local w = 2; v = w end
assert(v == 2)
end

-- ## while
do
local i, sum = 1, 0
while i <= 10 do
  sum = sum + i
  i = i + 1
end
assert(sum == 55)
assert(i == 11)
while false do error("never") end
while nil do error("never") end
local n = 0
while n < 3 do n = n + 1 end
assert(n == 3)
end

-- ## while with break and a complex condition
do
local i = 0
while true do
  i = i + 1
  if i >= 5 then break end
end
assert(i == 5)
local t = {1, 2, 3, nil, 5}
local k = 1
while t[k] and t[k] < 10 do k = k + 1 end
assert(k == 4)
end

-- ## repeat
do
local i = 0
repeat i = i + 1 until i >= 5
assert(i == 5)
local n = 0
repeat n = n + 1 until true
assert(n == 1)
local c = 0
repeat
  c = c + 1
  if c == 3 then break end
until false
assert(c == 3)
end

-- ## the until condition sees the locals of the body
do
local i = 0
repeat
  local done = i >= 3
  i = i + 1
until done
assert(i == 4)
local outer = "outer"
local n = 0
repeat
  local outer = n
  n = n + 1
until outer == 2
assert(n == 3)
assert(outer == "outer")
end

-- ## closures created in the until condition scope
do
local fns = {}
local i = 0
repeat
  local j = i * 10
  fns[#fns + 1] = function() return j end
  i = i + 1
until j >= 20
assert(#fns == 3)
assert(fns[1]() == 0)
assert(fns[2]() == 10)
assert(fns[3]() == 20)
end

-- ## nested loops and break only leaving the innermost loop
do
local count = 0
for i = 1, 3 do
  local j = 0
  while true do
    j = j + 1
    if j > i then break end
    count = count + 1
  end
end
assert(count == 6)
local out = {}
for i = 1, 3 do
  repeat
    if i == 2 then break end
    out[#out + 1] = i
  until true
end
assert(table.concat(out, ",") == "1,3")
end

-- ## break position and syntax
do
assert(load("while true do break end") ~= nil)
assert(load("while true do break; end") ~= nil)
assert(load("while true do break break end") ~= nil)
assert(load("while true do break local x = 1 end") ~= nil)
assert(load("while true do if x then break end end") ~= nil)
assert(load("break") == nil)
assert(load("if true then break end") == nil)
assert(load("do break end") == nil)
assert(load("while true do local f = function() break end end") == nil)
assert(load("repeat break until true") ~= nil)
assert(load("for i = 1, 2 do break end") ~= nil)
end

-- ## malformed control structures are rejected
do
assert(load("if true then") == nil)
assert(load("if true end") == nil)
assert(load("if then end") == nil)
assert(load("if true then else else end") == nil)
assert(load("if true then elseif end") == nil)
assert(load("if true then else elseif true then end") == nil)
assert(load("while true end") == nil)
assert(load("while do end") == nil)
assert(load("while true do") == nil)
assert(load("repeat until") == nil)
assert(load("repeat") == nil)
assert(load("until true") == nil)
assert(load("end") == nil)
assert(load("else") == nil)
assert(load("do") == nil)
assert(load("do end end") == nil)
assert(load("return 1 return 2") == nil)
assert(load("return 1; local x") == nil)
assert(load("do return end local x") ~= nil)
assert(load("if x then return end local y") ~= nil)
end

-- ## do blocks
do
local x = 1
do
  local x = 2
  assert(x == 2)
  do
    local x = 3
    assert(x == 3)
  end
  assert(x == 2)
end
assert(x == 1)
do local y = 5; x = y end
assert(x == 5)
end

-- ## return inside nested blocks
do
local function f(n)
  while true do
    repeat
      for i = 1, 10 do
        if i == n then
          do return i * 2 end
        end
      end
      return -1
    until false
  end
end
assert(f(3) == 6)
assert(f(11) == -1)
end

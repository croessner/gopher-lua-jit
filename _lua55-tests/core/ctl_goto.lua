-- Control flow: goto and labels.
local load = loadstring or load

-- ## forward and backward jumps
do
local i = 0
::top::
i = i + 1
if i < 5 then goto top end
assert(i == 5)
local skipped = true
goto over
skipped = false
::over::
assert(skipped)
end

-- ## the continue idiom
do
local out = {}
for i = 1, 6 do
  if i % 2 == 0 then goto continue end
  out[#out + 1] = i
  ::continue::
end
assert(table.concat(out, ",") == "1,3,5")
out = {}
local i = 0
while i < 6 do
  i = i + 1
  if i % 3 == 0 then goto continue end
  out[#out + 1] = i
  ::continue::
end
assert(table.concat(out, ",") == "1,2,4,5")
out = {}
for _, v in ipairs({1, 2, 3, 4}) do
  if v == 2 then goto continue end
  out[#out + 1] = v
  ::continue::
end
assert(table.concat(out, ",") == "1,3,4")
end

-- ## continue in a repeat loop whose body declares no later local
do
local out = {}
local i = 0
repeat
  i = i + 1
  if i == 2 then goto continue end
  out[#out + 1] = i
  ::continue::
until i >= 4
assert(table.concat(out, ",") == "1,3,4")
end

-- ## leaving nested loops
do
local found
for i = 1, 5 do
  for j = 1, 5 do
    if i * j == 12 then
      found = i .. "x" .. j
      goto done
    end
  end
end
::done::
assert(found == "3x4")
end

-- ## a label at the end of a block is visible although locals precede it
do
do
  goto finish
  local a = 1
  ::finish::
end
do
  goto finish
  local a = 1
  ::finish:: ;
end
do
  goto finish
  local a = 1
  ::finish::
  -- comments and empty statements do not count
  ;;
end
end

-- ## the same label name in different functions and sibling blocks
do
local function f()
  goto l
  ::l::
  return 1
end
local function g()
  goto l
  ::l::
  return 2
end
assert(f() + g() == 3)
do
  goto l
  ::l::
end
do
  goto l
  ::l::
end
end

-- ## goto to a label in an enclosing block
do
local n = 0
do
  ::again::
  n = n + 1
  do
    do
      if n < 3 then goto again end
    end
  end
end
assert(n == 3)
end

-- ## closures capture a fresh local on each backward jump
do
local fns = {}
do
  local i = 1
  ::loop::
  do
    local x = i * 10
    fns[i] = function() return x end
  end
  i = i + 1
  if i <= 3 then goto loop end
end
assert(fns[1]() == 10)
assert(fns[2]() == 20)
assert(fns[3]() == 30)
end

-- ## upvalues are closed when a goto leaves the block
do
local fns = {}
do
  local i = 1
  ::loop::
  local x = i
  fns[i] = function() x = x + 1; return x end
  i = i + 1
  if i <= 2 then goto loop end
end
assert(fns[1]() == 2)
assert(fns[1]() == 3)
assert(fns[2]() == 3)
end

-- ## goto as a state machine
do
local function run(input)
  local pos, out = 1, {}
  ::start::
  if pos > #input then goto finish end
  if input:sub(pos, pos) == "a" then goto in_a end
  goto other
  ::in_a::
  out[#out + 1] = "A"
  pos = pos + 1
  goto start
  ::other::
  out[#out + 1] = "?"
  pos = pos + 1
  goto start
  ::finish::
  return table.concat(out)
end
assert(run("abca") == "A??A")
assert(run("") == "")
end

-- ## goto cannot jump into the scope of a local
do
assert(load("goto x; local a; ::x:: print(a)") == nil)
assert(load("do goto x; local a; ::x:: a = 1 end") == nil)
assert(load("goto x; local a <const> = 1; ::x:: return a") == nil)
assert(load("repeat goto continue; local x; ::continue:: until x") == nil)
assert(load("goto x; local function f() end ::x:: f()") == nil)
assert(load("goto x; local a; ::x::") ~= nil)
assert(load("do goto x; local a; ::x:: end") ~= nil)
assert(load("while true do goto continue; local x; ::continue:: end") ~= nil)
end

-- ## goto cannot jump into a nested block or another function
do
assert(load("goto x; do ::x:: end") == nil)
assert(load("do ::x:: end goto x") == nil)
assert(load("goto x; while true do ::x:: end") == nil)
assert(load("goto x; if a then ::x:: end") == nil)
assert(load("::x:: local f = function() goto x end") == nil)
assert(load("local f = function() ::x:: end goto x") == nil)
assert(load("goto x; for i = 1, 2 do ::x:: end") == nil)
end

-- ## missing labels are rejected
do
assert(load("goto nope") == nil)
assert(load("do goto nope end") == nil)
assert(load("while true do goto nope end") == nil)
assert(load("::a:: goto b") == nil)
assert(load("goto continue") == nil)
assert(load("goto break") == nil)
end

-- ## duplicate labels are rejected
do
assert(load("::x:: ::x::") == nil)
assert(load("::x:: local a ::x::") == nil)
assert(load("do ::x:: goto x ::x:: end") == nil)
assert(load("::x:: do ::y:: end ::y::") ~= nil)
assert(load("do ::x:: end do ::x:: end") ~= nil)
assert(load("::x:: local f = function() ::x:: end") ~= nil)
end

-- ## label and goto syntax
do
assert(load("::x::") ~= nil)
assert(load(":: x ::") ~= nil)
assert(load("::x:: ::y:: ::z::") ~= nil)
assert(load("goto x ::x::") ~= nil)
assert(load("::1::") == nil)
assert(load("::x:") == nil)
assert(load(":x::") == nil)
assert(load("::::") == nil)
assert(load("goto") == nil)
assert(load("goto 1") == nil)
assert(load("::end::") == nil)
assert(load("goto end") == nil)
assert(load("return ::x::") == nil)
assert(load("local goto = 1") == nil)
end

-- ## 'goto' is reserved but label names share no namespace with variables
do
local x = 5
goto x
x = 6
::x::
assert(x == 5)
end

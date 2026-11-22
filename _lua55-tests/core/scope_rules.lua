-- Scoping: visibility of locals, shadowing and block structure.
local load = loadstring or load

-- ## a local is visible only after its declaration statement
do
local x = "outer"
do
  local y = x
  local x = "inner"
  assert(y == "outer")
  assert(x == "inner")
end
assert(x == "outer")
local a = 1
local a, b = a + 1, a + 2
assert(a == 2 and b == 3)
end

-- ## redeclaration in the same block creates a new variable
do
local v = 1
local function get1() return v end
local v = 2
local function get2() return v end
local v = 3
assert(get1() == 1 and get2() == 2 and v == 3)
end

-- ## blocks of control structures are scopes
do
local s = "top"
if true then local s = "if"; assert(s == "if") end
assert(s == "top")
if false then else local s = "else"; assert(s == "else") end
assert(s == "top")
while true do local s = "while"; assert(s == "while"); break end
assert(s == "top")
for i = 1, 1 do local s = "for"; assert(s == "for") end
assert(s == "top")
repeat local s = "repeat" until s == "repeat"
assert(s == "top")
do local s = "do" end
assert(s == "top")
end

-- ## each elseif branch is its own scope
do
local r
local n = 2
if n == 1 then
  local t = "one"; r = t
elseif n == 2 then
  local t = "two"; r = t
else
  local t = "other"; r = t
end
assert(r == "two")
end

-- ## function parameters shadow outer locals and upvalues
do
local p = "outer"
local function f(p) return p end
assert(f("arg") == "arg")
assert(f() == nil)
assert(p == "outer")
local function g(p) p = "changed"; return p end
assert(g("x") == "changed")
assert(p == "outer")
end

-- ## loop variables shadow outer locals
do
local i = "outer i"
for i = 1, 2 do assert(type(i) == "number") end
assert(i == "outer i")
local k, v = "outer k", "outer v"
for k, v in pairs({a = 1}) do assert(k == "a" and v == 1) end
assert(k == "outer k" and v == "outer v")
end

-- ## a local function is visible inside its own body, a local assignment is not
do
local function fact(n) return n <= 1 and 1 or n * fact(n - 1) end
assert(fact(5) == 120)
local fact2 = "outer"
do
  local function fact2(n) return n <= 1 and 1 or n * fact2(n - 1) end
  assert(fact2(4) == 24)
end
assert(fact2 == "outer")
end

-- ## globals and locals with the same name
do
SCOPE_G = "global"
local function read_global() return SCOPE_G end
local SCOPE_G = "local"
assert(SCOPE_G == "local")
assert(read_global() == "global")
assert(_ENV.SCOPE_G == "global")
_ENV.SCOPE_G = nil
assert(read_global() == nil)
assert(SCOPE_G == "local")
end

-- ## assignments inside nested functions reach the enclosing local
do
local counter = 0
local function bump() counter = counter + 1 end
local function bump_twice() bump(); bump() end
bump_twice()
assert(counter == 2)
do
  local counter = 100
  bump()
  assert(counter == 100)
end
assert(counter == 3)
end

-- ## names declared in a nested function do not leak
do
local function declares() local hidden = 1; SCOPE_LEAK = nil; return hidden end
declares()
assert(hidden == nil)
assert(load("local function f() local z = 1 end return z")() == nil)
end

-- ## locals are initialised to nil on every entry of a block
do
local seen = {}
for i = 1, 3 do
  local fresh
  seen[i] = fresh
  fresh = i
end
assert(seen[1] == nil and seen[2] == nil and seen[3] == nil)
local function init()
  local a, b, c
  local r = (a == nil and b == nil and c == nil)
  a, b, c = 1, 2, 3
  return r
end
assert(init() and init())
local j = 0
while j < 3 do
  local w
  assert(w == nil)
  w = j
  j = j + 1
end
end

-- ## deep nesting of scopes
do
local d = 0
do local d = 1
  do local d = 2
    do local d = 3
      do local d = 4
        assert(d == 4)
      end
      assert(d == 3)
    end
    assert(d == 2)
  end
  assert(d == 1)
end
assert(d == 0)
end

-- ## labels do not open scopes; goto respects local scopes
do
do
  local t = {}
  for i = 1, 3 do
    local keep = i
    if i == 2 then goto skip end
    t[#t + 1] = keep
    ::skip::
  end
  assert(#t == 2 and t[1] == 1 and t[2] == 3)
end
end

-- ## the scope of a to-be-closed variable ends with its block
do
local log = {}
do
  local res <close> = setmetatable({}, {__close = function() log[#log + 1] = "closed" end})
  log[#log + 1] = "in"
end
log[#log + 1] = "out"
assert(table.concat(log, ",") == "in,closed,out")
assert(res == nil)
end

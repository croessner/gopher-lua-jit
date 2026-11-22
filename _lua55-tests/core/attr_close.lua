-- Local attributes: <close> (to-be-closed variables).
local load = loadstring or load

-- returns a closable value that appends name (and the error, if any) to log
local function closer(log, name)
  return setmetatable({name = name}, {__close = function(self, err)
    if err == nil then
      log[#log + 1] = name
    else
      log[#log + 1] = name .. "(" .. tostring(err) .. ")"
    end
  end})
end

-- ## closed at the end of the block
do
local log = {}
do
  local x <close> = closer(log, "x")
  log[#log + 1] = "body"
end
log[#log + 1] = "after"
assert(table.concat(log, ",") == "body,x,after")
end

-- ## closed in reverse order of declaration
do
local log = {}
do
  local a <close> = closer(log, "a")
  local b <close> = closer(log, "b")
  local c <close> = closer(log, "c")
end
assert(table.concat(log, ",") == "c,b,a")
end

-- ## nested blocks
do
local log = {}
do
  local a <close> = closer(log, "a")
  do
    local b <close> = closer(log, "b")
    log[#log + 1] = "inner"
  end
  log[#log + 1] = "outer"
end
assert(table.concat(log, ",") == "inner,b,outer,a")
end

-- ## nil and false are allowed and ignored
do
local log = {}
do
  local a <close> = nil
  local b <close> = false
  local c <close> = closer(log, "c")
  assert(a == nil and b == false)
end
assert(table.concat(log, ",") == "c")
do
  local a <close>
  assert(a == nil)
end
end

-- ## values without __close are rejected
do
assert(not pcall(function() local x <close> = {} end))
assert(not pcall(function() local x <close> = 1 end))
assert(not pcall(function() local x <close> = "str" end))
assert(not pcall(function() local x <close> = true end))
assert(not pcall(function() local x <close> = setmetatable({}, {}) end))
assert(not pcall(function() local x <close> = setmetatable({}, {__index = {__close = print}}) end))
assert(pcall(function() local x <close> = setmetatable({}, {__close = function() end}) end))
end

-- ## earlier variables are closed when a later one is rejected
do
local log = {}
local ok = pcall(function()
  local a <close> = closer(log, "a")
  local b <close> = {}
  log[#log + 1] = "not reached"
end)
assert(not ok)
assert(#log == 1)
assert(log[1]:sub(1, 2) == "a(")
end

-- ## the __close metamethod receives the value
do
local got_self, nargs
local v = setmetatable({}, {__close = function(...)
  nargs = select("#", ...)
  got_self = ...
end})
do local x <close> = v end
assert(got_self == v)
assert(nargs == 1 or nargs == 2)
end

-- ## closed on return, after the return values are evaluated
do
local log = {}
local function f()
  local x <close> = closer(log, "x")
  log[#log + 1] = "body"
  return (function() log[#log + 1] = "retval"; return "result" end)()
end
assert(f() == "result")
assert(table.concat(log, ",") == "body,retval,x")
end

-- ## return values are not affected by the closing
do
local function f()
  local t = {v = 1}
  local x <close> = setmetatable({}, {__close = function() t.v = 2 end})
  return t.v, t
end
local v, t = f()
assert(v == 1)
assert(t.v == 2)
local function g()
  local x <close> = setmetatable({}, {__close = function() end})
  return 1, 2, 3
end
local a, b, c = g()
assert(a == 1 and b == 2 and c == 3)
assert(select("#", g()) == 3)
end

-- ## closed on break
do
local log = {}
for i = 1, 3 do
  local x <close> = closer(log, "x" .. i)
  if i == 2 then break end
end
assert(table.concat(log, ",") == "x1,x2")
log = {}
local i = 0
while true do
  i = i + 1
  local x <close> = closer(log, "w" .. i)
  if i == 2 then break end
end
assert(table.concat(log, ",") == "w1,w2")
end

-- ## closed at the end of every loop iteration
do
local log = {}
for i = 1, 3 do
  local x <close> = closer(log, "i" .. i)
  log[#log + 1] = "b" .. i
end
assert(table.concat(log, ",") == "b1,i1,b2,i2,b3,i3")
log = {}
local n = 0
repeat
  n = n + 1
  local x <close> = closer(log, "r" .. n)
until n >= 2
assert(table.concat(log, ",") == "r1,r2")
end

-- ## closed on goto out of the block
do
local log = {}
do
  local a <close> = closer(log, "a")
  do
    local b <close> = closer(log, "b")
    goto out
  end
end
::out::
assert(table.concat(log, ",") == "b,a")
log = {}
for i = 1, 2 do
  local x <close> = closer(log, "c" .. i)
  goto continue
  ::continue::
end
assert(table.concat(log, ",") == "c1,c2")
end

-- ## closed on a backward goto
do
local log = {}
do
  local n = 0
  ::again::
  do
    local x <close> = closer(log, "g" .. n)
    n = n + 1
    if n < 3 then goto again end
  end
end
assert(table.concat(log, ",") == "g0,g1,g2")
end

-- ## closed on error, receiving the error object
do
local log = {}
local ok, err = pcall(function()
  local a <close> = closer(log, "a")
  local b <close> = closer(log, "b")
  error("boom", 0)
end)
assert(not ok and err == "boom")
assert(log[1] == "b(boom)")
log = {}
local errobj = {}
ok, err = pcall(function()
  local a <close> = setmetatable({}, {__close = function(_, e) log[1] = e end})
  error(errobj)
end)
assert(not ok and err == errobj)
assert(log[1] == errobj)
end

-- ## closed when an error passes through several frames
do
local log = {}
local function inner()
  local x <close> = closer(log, "inner")
  error("deep", 0)
end
local function middle()
  local y <close> = closer(log, "middle")
  inner()
  log[#log + 1] = "not reached"
end
local ok, err = pcall(function()
  local z <close> = closer(log, "outer")
  middle()
end)
assert(not ok and err == "deep")
assert(log[1] == "inner(deep)")
end

-- ## an error in __close replaces the original error
do
local ok, err = pcall(function()
  local a <close> = setmetatable({}, {__close = function() error("from close", 0) end})
  error("original", 0)
end)
assert(not ok and err == "from close")
local log = {}
ok, err = pcall(function()
  local a <close> = setmetatable({}, {__close = function(_, e) log[#log + 1] = "a:" .. tostring(e); error("a-err", 0) end})
  local b <close> = setmetatable({}, {__close = function(_, e) log[#log + 1] = "b:" .. tostring(e); error("b-err", 0) end})
  error("body", 0)
end)
assert(not ok and err == "a-err")
assert(table.concat(log, ",") == "b:body,a:b-err")
end

-- ## an error in __close on normal exit propagates, other variables still close
do
local log = {}
local ok, err = pcall(function()
  local a <close> = closer(log, "a")
  local b <close> = setmetatable({}, {__close = function() error("close failed", 0) end})
  local c <close> = closer(log, "c")
  log[#log + 1] = "body"
end)
assert(not ok and err == "close failed")
assert(table.concat(log, ",") == "body,c,a(close failed)")
end

-- ## the variable is constant
do
assert(load("local x <close> = nil; x = 1") == nil)
assert(load("local x <close> = nil; local function f() x = 1 end") == nil)
assert(load("local x <close> = nil; return x") ~= nil)
assert(load("local x <close>, y <close> = nil, nil") == nil)
assert(load("local x <close>, y, z <close> = nil, nil, nil") == nil)
assert(load("local y, x <close> = nil, nil") ~= nil)
assert(load("local x <const>, y <close> = 1, nil") ~= nil)
assert(load("local <close> x, y = nil, nil") == nil)
end

-- ## the value can still be used inside the block and by closures
do
local log = {}
local getname
do
  local x <close> = closer(log, "x")
  assert(x.name == "x")
  getname = function() return x.name end
  assert(getname() == "x")
end
assert(getname() == "x")
assert(log[1] == "x")
end

-- ## metatable changes after declaration
do
local log = {}
do
  local mt = {__close = function() log[#log + 1] = "first" end}
  local x <close> = setmetatable({}, mt)
  mt.__close = function() log[#log + 1] = "second" end
end
assert(log[1] == "second")
local ok = pcall(function()
  local mt = {__close = function() end}
  local x <close> = setmetatable({}, mt)
  mt.__close = nil
end)
assert(not ok)
end

-- ## a function with a to-be-closed variable does not make a tail call
do
local log = {}
local function callee() log[#log + 1] = "callee"; return "v" end
local function caller()
  local x <close> = closer(log, "x")
  return callee()
end
assert(caller() == "v")
assert(table.concat(log, ",") == "callee,x")
end

-- ## closing inside coroutines
do
local log = {}
local co = coroutine.wrap(function()
  local x <close> = closer(log, "x")
  coroutine.yield(1)
  log[#log + 1] = "resumed"
  return 2
end)
assert(co() == 1)
assert(#log == 0)
assert(co() == 2)
assert(table.concat(log, ",") == "resumed,x")
end

-- ## many to-be-closed variables
do
local log = {}
do
  local a1 <close> = closer(log, "1")
  local a2 <close> = closer(log, "2")
  local a3 <close> = closer(log, "3")
  local a4 <close> = closer(log, "4")
  local a5 <close> = closer(log, "5")
  local a6 <close> = closer(log, "6")
  local a7 <close> = closer(log, "7")
  local a8 <close> = closer(log, "8")
end
assert(table.concat(log) == "87654321")
log = {}
local function rec(n)
  if n == 0 then return end
  local x <close> = closer(log, tostring(n))
  rec(n - 1)
end
rec(50)
assert(#log == 50)
assert(log[1] == "1" and log[50] == "50")
end

-- ## to-be-closed variables in the main chunk of a loaded function
do
local log = {}
CLOSE_TEST_LOG = log
local chunk = load([[
  local x <close> = setmetatable({}, {__close = function() CLOSE_TEST_LOG[#CLOSE_TEST_LOG + 1] = "chunk" end})
  return "ret"
]])
assert(chunk() == "ret")
assert(log[1] == "chunk")
CLOSE_TEST_LOG = nil
end

-- assert, error, pcall and xpcall.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

local function pack(...)
  return {n = select("#", ...), ...}
end

-- current source name and line, to check positions in messages
local src = debug.getinfo(1, "S").short_src
local function line() return debug.getinfo(2, "l").currentline end

-- assert returns all its arguments
local r = pack(assert(1, 2, 3))
assert(r.n == 3 and r[1] == 1 and r[2] == 2 and r[3] == 3)
r = pack(assert(true))
assert(r.n == 1)
r = pack(assert("x", nil, nil))
assert(r.n == 3)
assert(assert(0) == 0 and assert("") == "")

-- assert failures
checkerr("value expected", assert)
local ok, msg = pcall(assert, false)
assert(not ok and msg == "assertion failed!")
ok, msg = pcall(assert, nil)
assert(not ok and msg == "assertion failed!")
ok, msg = pcall(assert, nil, "msg")
assert(not ok and msg == "msg")
ok, msg = pcall(assert, false, 12)
assert(not ok and msg == 12)
local errobj = {}
ok, msg = pcall(assert, false, errobj)
assert(not ok and msg == errobj)
ok, msg = pcall(assert, false, nil)
assert(not ok and msg == "<no error object>")
-- a string message gets the position of the caller of assert
local l
ok, msg = pcall(function() l = line() assert(false, "msg") end)
assert(not ok and msg == src .. ":" .. l .. ": msg")
ok, msg = pcall(function() l = line() assert(false) end)
assert(not ok and msg == src .. ":" .. l .. ": assertion failed!")
ok, msg = pcall(function() assert(nil, 12) end)
assert(not ok and msg == 12)

-- error with a string adds the position selected by the level
ok, msg = pcall(function() l = line() error("x") end)
assert(not ok and msg == src .. ":" .. l .. ": x")
ok, msg = pcall(function() l = line() error("x", 1) end)
assert(not ok and msg == src .. ":" .. l .. ": x")
ok, msg = pcall(function() error("x", 0) end)
assert(not ok and msg == "x")
local function thrower() error("lvl2", 2) end
ok, msg = pcall(function() l = line() thrower() end)
assert(not ok and msg == src .. ":" .. l .. ": lvl2")
-- a level pointing to a function that is not a Lua function adds nothing
ok, msg = pcall(function() error("x", 2) end)
assert(not ok and msg == "x")
ok, msg = pcall(error, "m")
assert(not ok and msg == "m")
ok, msg = pcall(error, "m", 0)
assert(not ok and msg == "m")
ok, msg = pcall(error, "m", 1)
assert(not ok and msg == "m")
l = line() ok, msg = pcall(error, "m", 2)
assert(not ok and msg == src .. ":" .. l .. ": m")
l = line() ok, msg = pcall(function() error("x", 3) end)
assert(not ok and msg == src .. ":" .. l .. ": x")
-- a level beyond the stack adds nothing
ok, msg = pcall(function() error("deep", 50) end)
assert(not ok and msg == "deep")

-- error with other values keeps them untouched
ok, msg = pcall(error, errobj)
assert(not ok and msg == errobj)
ok, msg = pcall(error, 12)
assert(not ok and msg == 12 and tostring(msg) == "12")
ok, msg = pcall(error, 12, 2)
assert(not ok and msg == 12)
ok, msg = pcall(error, 1.5)
assert(not ok and msg == 1.5)
ok, msg = pcall(error, true)
assert(not ok and msg == true)
ok, msg = pcall(error, false)
assert(not ok and msg == false)
local withmeta = setmetatable({}, {__tostring = function() return "E!" end})
ok, msg = pcall(error, withmeta)
assert(not ok and msg == withmeta)

-- a nil error value is replaced
r = pack(pcall(error))
assert(r.n == 2 and r[1] == false and r[2] == "<no error object>")
r = pack(pcall(error, nil))
assert(r.n == 2 and r[2] == "<no error object>")
r = pack(pcall(function() error() end))
assert(r.n == 2 and r[2] == "<no error object>")

-- argument checks of error
checkerr("number expected, got string", error, "m", "x")
checkerr("number has no integer representation", error, "m", 1.5)

-- pcall: results
r = pack(pcall(function(...) return ... end, 1, nil, 3))
assert(r.n == 4 and r[1] == true and r[2] == 1 and r[3] == nil and r[4] == 3)
r = pack(pcall(function() end))
assert(r.n == 1 and r[1] == true)
r = pack(pcall(pcall, error, "e"))
assert(r.n == 3 and r[1] == true and r[2] == false and r[3] == "e")
r = pack(pcall(pcall))
assert(r.n == 2 and r[1] == false and r[2]:find("value expected", 1, true))
checkerr("value expected", pcall)

-- pcall: values that cannot be called
for _, value in ipairs({1, "s", true, {}}) do
  ok, msg = pcall(value)
  assert(not ok and msg == "attempt to call a " .. type(value) .. " value")
end
ok, msg = pcall(nil)
assert(not ok and msg == "attempt to call a nil value")
-- __call is honoured
local callable = setmetatable({}, {__call = function(self, a) return "called", a end})
r = pack(pcall(callable, 5))
assert(r.n == 3 and r[1] == true and r[2] == "called" and r[3] == 5)

-- runtime errors carry a position
ok, msg = pcall(function() l = line() local x = nil; return x.y end)
assert(not ok and msg:find(src .. ":" .. l .. ": attempt to index a nil value", 1, true) == 1)
ok, msg = pcall(function() l = line() return 1 + {} end)
assert(not ok and msg:find(src .. ":" .. l .. ": attempt to perform arithmetic on a table value", 1, true) == 1)
ok, msg = pcall(function() l = line() return #5 end)
assert(not ok and msg:find(src .. ":" .. l .. ": attempt to get length of a number value", 1, true) == 1)

-- errors pass through several pcall levels unchanged
ok, msg = pcall(function()
  local ok2, msg2 = pcall(function() error(errobj) end)
  assert(not ok2 and msg2 == errobj)
  error(msg2)
end)
assert(not ok and msg == errobj)

-- xpcall: success passes the extra arguments and returns all results
r = pack(xpcall(function(a, b) return a + b, a, b end, print, 1, 2))
assert(r.n == 4 and r[1] == true and r[2] == 3 and r[3] == 1 and r[4] == 2)
r = pack(xpcall(function() end, print))
assert(r.n == 1 and r[1] == true)
r = pack(xpcall(callable, print, 5))
assert(r.n == 3 and r[2] == "called" and r[3] == 5)

-- xpcall: the handler transforms the error value
r = pack(xpcall(function() l = line() error("e") end, function(m) return "H:" .. m end))
assert(r.n == 2 and r[1] == false and r[2] == "H:" .. src .. ":" .. l .. ": e")
r = pack(xpcall(error, function(m) return m end, "zz"))
assert(r.n == 2 and r[2] == "zz")
r = pack(xpcall(function() error(errobj) end, function(m) return type(m) end))
assert(r[1] == false and r[2] == "table")
-- the handler may return several values, only the first one is kept
r = pack(xpcall(error, function(m) return 1, 2, 3 end, "x"))
assert(r.n == 2 and r[2] == 1)
-- the handler sees a nil error value as nil
r = pack(xpcall(function() error(nil) end, function(m) return type(m) end))
assert(r[1] == false and r[2] == "nil")
-- a handler returning nil yields the placeholder
r = pack(xpcall(function() error() end, function(m) return m end))
assert(r.n == 2 and r[2] == "<no error object>")
-- calling a value that cannot be called goes through the handler too
r = pack(xpcall(1, function(m) return "H:" .. m end))
assert(r.n == 2 and r[1] == false and r[2] == "H:attempt to call a number value")
-- the handler runs before the stack unwinds
local trace = {}
r = pack(xpcall(function() local function inner() error("deep") end inner() end,
                function(m) trace.tb = debug.traceback(m, 1) return m end))
assert(r[1] == false and trace.tb:find("deep", 1, true) and trace.tb:find("stack traceback:", 1, true))
assert(trace.tb:find("'inner'", 1, true), trace.tb)

-- a failing handler is called again with its own error
local calls = {n = 0}
r = pack(xpcall(function() error("a", 0) end, function(m)
  calls.n = calls.n + 1
  if calls.n < 3 then error("again" .. calls.n, 0) end
  return "final:" .. m
end))
assert(r.n == 2 and r[1] == false and r[2] == "final:again2" and calls.n == 3)
r = pack(xpcall(function() error("a") end, function(m) error("b") end))
assert(r.n == 2 and r[1] == false and r[2] == "error in error handling")

-- argument checks of xpcall
checkerr("function expected", xpcall)
checkerr("function expected", xpcall, print)
checkerr("function expected", xpcall, print, 1)
checkerr("function expected", xpcall, print, setmetatable({}, {__call = print}))

-- a to-be-closed variable is closed when an error unwinds a protected call
local log = {}
local function closer(name)
  return setmetatable({}, {__close = function(_, err) log[#log + 1] = name .. ":" .. tostring(err) end})
end
ok, msg = pcall(function()
  local a <close> = closer("a")
  error("boom", 0)
end)
assert(not ok and msg == "boom" and table.concat(log, ",") == "a:boom")

-- tail calls do not count as levels
local function thrower2() error("lvl2", 2) end
local function mid2() return thrower2() end
local function top2() l = line() mid2() end
ok, msg = pcall(top2)
assert(not ok and msg == src .. ":" .. l .. ": lvl2", msg)
local function thrower3() error("lvl3", 3) end
local function mid3() local res = thrower3() return res end
local function top3() return mid3() end
local function outer3() l = line() top3() end
ok, msg = pcall(outer3)
assert(not ok and msg == src .. ":" .. l .. ": lvl3", msg)

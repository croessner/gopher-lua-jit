-- Error handling: error, pcall, xpcall and error values.
local load = loadstring or load

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## pcall returns true plus all results on success
do
assert(show(pcall(function() end)) == "true")
assert(show(pcall(function() return 1, 2, 3 end)) == "true,1,2,3")
assert(show(pcall(function() return nil end)) == "true,nil")
assert(show(pcall(function(...) return ... end, "a", nil, "c")) == "true,a,nil,c")
assert(show(pcall(function(a, b) return a + b end, 1, 2)) == "true,3")
assert(select("#", pcall(function() return nil, nil end)) == 3)
end

-- ## error values of any type are passed through unchanged
do
local function thrown(v) local ok, e = pcall(function() error(v, 0) end); return ok, e end
local ok, e = thrown("message")
assert(ok == false and e == "message")
ok, e = thrown(42)
assert(ok == false and e == 42)
ok, e = thrown(4.5)
assert(e == 4.5)
local tbl = {code = 7}
ok, e = thrown(tbl)
assert(e == tbl and e.code == 7)
ok, e = thrown(true)
assert(e == true)
ok, e = thrown(false)
assert(ok == false and e == false)
local fn = function() end
ok, e = thrown(fn)
assert(e == fn)
local co = coroutine.create(fn)
ok, e = thrown(co)
assert(e == co)
end

-- ## string errors get a position prefix according to the level
do
local function lvl1() error("msg") end
local function lvl2() error("msg", 2) end
local function lvl0() error("msg", 0) end
local ok, e = pcall(lvl1)
assert(not ok and e:find("^[^:]+:%d+: msg$"))
ok, e = pcall(lvl0)
assert(e == "msg")
ok, e = pcall(function() lvl2() end)
assert(e:find("^[^:]+:%d+: msg$"))
end

-- ## the position refers to the line of the call
do
local function line_of(e) return tonumber(e:match(":(%d+):")) end
local function raise_here() error("here") end -- marker line A
local ok, e1 = pcall(raise_here)
local function caller() raise_here() end
local ok, e2 = pcall(caller)
assert(line_of(e1) == line_of(e2))
end

-- ## non-string errors get no position
do
local ok, e = pcall(function() error({}) end)
assert(type(e) == "table")
ok, e = pcall(function() error(12) end)
assert(e == 12)
ok, e = pcall(function() error(12, 2) end)
assert(e == 12)
end

-- ## runtime errors carry a position prefix
do
local ok, e = pcall(function() local x = nil; return x.field end)
assert(not ok and type(e) == "string")
assert(e:find("^[^:]+:%d+: "))
ok, e = pcall(function() return 1 + {} end)
assert(e:find("^[^:]+:%d+: "))
ok, e = pcall(function() return #nil end)
assert(e:find("^[^:]+:%d+: "))
ok, e = pcall(function() undefined_function_xyz() end)
assert(e:find("^[^:]+:%d+: "))
ok, e = pcall(function() return 1 < "x" end)
assert(e:find("^[^:]+:%d+: "))
ok, e = pcall(function() return 1 // 0 end)
assert(e:find("^[^:]+:%d+: "))
end

-- ## nested pcall
do
local ok, a, b = pcall(pcall, error, {"inner"})
assert(ok == true and a == false and b[1] == "inner")
local ok1, ok2, ok3, e = pcall(pcall, pcall, error, 42)
assert(ok1 == true and ok2 == true and ok3 == false and e == 42)
local function nest(n)
  if n == 0 then error("bottom", 0) end
  local ok, e = pcall(nest, n - 1)
  error(e .. "<" .. n, 0)
end
local ok, e = pcall(nest, 3)
assert(e == "bottom<1<2<3")
end

-- ## errors can be rethrown and handled at an outer level
do
local function inner() error({code = 1}) end
local function middle()
  local ok, e = pcall(inner)
  e.code = e.code + 1
  error(e)
end
local ok, e = pcall(middle)
assert(not ok and e.code == 2)
local function finally_like()
  local log = {}
  local ok, e = pcall(function() log[#log + 1] = "try"; error("x", 0) end)
  log[#log + 1] = "cleanup"
  return table.concat(log, ","), ok, e
end
local l, ok2, e2 = finally_like()
assert(l == "try,cleanup" and ok2 == false and e2 == "x")
end

-- ## code after an error is not executed
do
local reached = false
pcall(function() error("stop"); reached = true end)
assert(reached == false)
local count = 0
pcall(function()
  for i = 1, 10 do
    count = i
    if i == 4 then error("stop") end
  end
end)
assert(count == 4)
end

-- ## pcall with non-callable values
do
assert(pcall(nil) == false)
assert(pcall(1) == false)
assert(pcall({}) == false)
assert(pcall("string") == false)
assert(not pcall(pcall))
local callable = setmetatable({}, {__call = function(self, x) return x end})
local ok, v = pcall(callable, "v")
assert(ok and v == "v")
end

-- ## xpcall calls the handler with the error value
do
assert(show(xpcall(function() return 1, 2 end, function() return "handled" end)) == "true,1,2")
assert(show(xpcall(function() error("e", 0) end, function(m) return "handled:" .. m end)) == "false,handled:e")
local errobj = {}
local got
local ok, r = xpcall(function() error(errobj) end, function(m) got = m; return "r" end)
assert(not ok and got == errobj and r == "r")
ok, r = xpcall(function() local x = nil; return x.y end, function(m) return type(m) end)
assert(not ok and r == "string")
end

-- ## the result of the xpcall handler is adjusted to one value
do
assert(show(xpcall(error, function() return 1, 2, 3 end)) == "false,1")
assert(show(xpcall(function() error("x", 0) end, function(m) return m, "second" end)) == "false,x")
assert(show(xpcall(function() error("x", 0) end, function() return false end)) == "false,false")
assert(select("#", xpcall(function() error("x", 0) end, function() end)) == 2)
assert(select("#", xpcall(function() error("x", 0) end, function() return 1, 2 end)) == 2)
end

-- ## the xpcall handler runs before the stack unwinds
do
local depth_at_error, depth_in_handler
local level = 0
local function deep(n)
  level = level + 1
  if n == 0 then depth_at_error = level; error("x") end
  deep(n - 1)
  level = level - 1
end
xpcall(function() deep(5) end, function() depth_in_handler = level end)
assert(depth_at_error == 6 and depth_in_handler == 6)
end

-- ## an error inside the xpcall handler is caught
do
local ok, e = xpcall(function() error("first", 0) end, function() error("second", 0) end)
assert(ok == false)
local ok2 = xpcall(function() error("first", 0) end, function(m) local x = nil; return x.y end)
assert(ok2 == false)
-- the state is still usable
assert(pcall(function() return 1 end) == true)
end

-- ## nested xpcall and pcall
do
local trace = {}
local ok, r = xpcall(function()
  local ok2, r2 = xpcall(function() error("inner", 0) end, function(m) trace[#trace + 1] = "h1:" .. m; return "r1" end)
  trace[#trace + 1] = tostring(ok2) .. ":" .. r2
  error("outer", 0)
end, function(m) trace[#trace + 1] = "h2:" .. m; return "r2" end)
assert(ok == false and r == "r2")
assert(table.concat(trace, ",") == "h1:inner,false:r1,h2:outer")
local ok, e, r = pcall(xpcall, function() error("v", 0) end, function(m) return "handled:" .. m end)
assert(ok == true and e == false and r == "handled:v")
end

-- ## assert
do
assert(assert(1) == 1)
assert(assert("v", "msg") == "v")
local a, b, c = assert(1, 2, 3)
assert(a == 1 and b == 2 and c == 3)
local ok, e = pcall(assert, false)
assert(not ok and type(e) == "string")
ok, e = pcall(assert, nil)
assert(not ok and type(e) == "string")
local tbl = {}
ok, e = pcall(assert, false, tbl)
ok, e = pcall(assert, false, 42)
ok, e = pcall(assert)
assert(not ok)
end

-- ## errors with __tostring and __call objects
do
local errobj = setmetatable({}, {__tostring = function() return "E!" end})
local ok, e = pcall(error, errobj)
assert(e == errobj and tostring(e) == "E!")
ok, e = pcall(function() error(errobj, 2) end)
assert(e == errobj)
end

-- ## errors inside metamethods, iterators and nested calls
do
local t = setmetatable({}, {__index = function(_, k) error("no field " .. k, 0) end})
local ok, e = pcall(function() return t.missing end)
assert(not ok and e == "no field missing")
ok, e = pcall(function() for i in function() error("iter", 0) end, nil, nil, nil do end end)
assert(e == "iter")
ok, e = pcall(function() return (function() return (function() error("3 deep", 0) end)() end)() end)
assert(e == "3 deep")
ok, e = pcall(function() local t = {} ; t[nil] = 1 end)
assert(not ok)
ok, e = pcall(table.sort, {3, 2, 1}, function(a, b) error("cmp", 0) end)
assert(e == "cmp")
end

-- ## load reports syntax errors as nil plus message
do
local f, msg = load("x = = 1")
assert(f == nil and type(msg) == "string")
f, msg = load("return 1")
assert(type(f) == "function" and msg == nil)
f, msg = load("local x <const> = 1; x = 2")
assert(f == nil and type(msg) == "string")
f, msg = load("goto nowhere")
assert(f == nil and type(msg) == "string")
f, msg = load("for")
assert(f == nil and type(msg) == "string")
end

-- ## runtime errors inside loaded chunks
do
local f = load("local x = nil; return x.y")
local ok, e = pcall(f)
assert(not ok and type(e) == "string")
local g = load("error('from chunk', 0)")
ok, e = pcall(g)
assert(e == "from chunk")
local h = load("error({code = 5})")
ok, e = pcall(h)
assert(e.code == 5)
end

-- ## error levels beyond the stack
do
local ok, e = pcall(function() error("far", 50) end)
assert(not ok and type(e) == "string" and e:find("far"))
end

-- ## a nil error value is replaced by a string
do
local ok, e = pcall(error, nil)
ok, e = pcall(function() error(nil) end)
ok, e = pcall(function() error(nil, 2) end)
ok, e = pcall(assert, false, nil)
ok, e = coroutine.resume(coroutine.create(function() error(nil) end))
ok, e = xpcall(function() error("x", 0) end, function() return nil end)
ok, e = pcall(error, false)
assert(ok == false and e == false)
end

-- ## the default assert message
do
local ok, e = pcall(assert, false)
ok, e = pcall(assert, nil)
ok, e = pcall(function() assert(false) end)
assert(e:find("^[^:]+:%d+: assertion failed!$"))
end

-- ## assert adds a position to string messages like error does
do
local ok, e = pcall(function() assert(1 == 2, "custom message") end)
assert(e:find("^[^:]+:%d+: custom message$"))
ok, e = pcall(function() assert(false, 42) end)
end

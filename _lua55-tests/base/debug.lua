-- The debug library.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

local function pack(...)
  return {n = select("#", ...), ...}
end

local function keys(t)
  local list = {}
  for k in pairs(t) do list[#list + 1] = k end
  table.sort(list)
  return table.concat(list, " ")
end

local this = debug.getinfo(1, "S")
local src = this.short_src
-- line returns the line number of its caller
local function line() return debug.getinfo(2, "l").currentline end
-- plain turns a string into a pattern matching it literally
local function plain(str) return (str:gsub("%p", "%%%0")) end

-- getinfo: the main chunk
assert(this.what == "main" and this.source == "@" .. src)
assert(this.linedefined == 0 and this.lastlinedefined == 0)
assert(keys(this) == "lastlinedefined linedefined short_src source what")
local l = line()
assert(debug.getinfo(1, "l").currentline == l + 1)
assert(tostring(debug.getinfo(1, "l").currentline) == tostring(l + 2))

-- getinfo: all fields of a running function
local probe_line = line() + 1
local function probe(a, b, ...)
  return debug.getinfo(1)
end
local info = probe(1, 2)
assert(keys(info) == "currentline extraargs ftransfer func istailcall isvararg lastlinedefined linedefined " ..
                     "name namewhat nparams ntransfer nups short_src source what")
assert(info.what == "Lua" and info.short_src == src and info.source == "@" .. src)
assert(info.linedefined == probe_line and info.lastlinedefined == probe_line + 2)
assert(info.currentline == probe_line + 1)
assert(info.name == "probe" and info.namewhat == "local")
assert(info.nparams == 2 and info.isvararg == true and info.nups == 1)   -- the upvalue is _ENV
assert(info.func == probe and info.istailcall == false)
assert(info.ftransfer == 0 and info.ntransfer == 0 and info.extraargs == 0)

-- getinfo: selected options
local function named(what) return keys(debug.getinfo(1, what)) end
assert(named("n") == "name namewhat")
assert(named("S") == "lastlinedefined linedefined short_src source what")
assert(named("l") == "currentline")
assert(named("u") == "isvararg nparams nups")
assert(named("t") == "extraargs istailcall")
assert(named("r") == "ftransfer ntransfer")
assert(named("f") == "func")
assert(named("L") == "activelines")
assert(named("") == "")
assert(named("Sl") == "currentline lastlinedefined linedefined short_src source what")

-- getinfo: a function value
info = debug.getinfo(probe)
assert(info.func == probe and info.what == "Lua" and info.currentline == -1)
assert(info.name == nil and info.namewhat == "" and info.linedefined == probe_line)
info = debug.getinfo(print)
assert(info.what == "C" and info.short_src == "[C]" and info.source == "=[C]")
assert(info.currentline == -1 and info.linedefined == -1 and info.lastlinedefined == -1)
assert(info.func == print and info.nparams == 0 and info.isvararg == true)
assert(debug.getinfo(print, "L").activelines == nil)
local lines = debug.getinfo(probe, "L").activelines
assert(lines[probe_line + 1] == true and lines[1] == nil)

-- getinfo: names derived from the call site
local function whoami() local i = debug.getinfo(1, "n") return i.name, i.namewhat end
local name, namewhat = whoami()
assert(name == "whoami" and namewhat == "local")
local holder = {method = function(self) local i = debug.getinfo(1, "n") return i.name, i.namewhat end,
                field = whoami}
name, namewhat = holder:method()
assert(name == "method" and namewhat == "method")
name, namewhat = holder.field()
assert(name == "field" and namewhat == "field")
global_whoami_for_debug_test = whoami
name, namewhat = global_whoami_for_debug_test()
assert(name == "global_whoami_for_debug_test" and namewhat == "global")
global_whoami_for_debug_test = nil
local function viaupvalue() return whoami() end
name, namewhat = viaupvalue()
assert(name == nil and namewhat == "")          -- a tail call has no name
local function viaupvalue2() local n, w = whoami() return n, w end
name, namewhat = viaupvalue2()
assert(name == "whoami" and namewhat == "upvalue")
info = setmetatable({}, {__index = function() local i = debug.getinfo(1, "n") return i.namewhat .. ":" .. i.name end})
assert(info.anything == "metamethod:index")
assert(debug.getinfo(0, "n").name == "getinfo" and debug.getinfo(0, "S").what == "C")

-- getinfo: tail calls
local function istail() return debug.getinfo(1, "t").istailcall end
local function tailcaller() return istail() end
assert(tailcaller() == true and istail() == false)

-- getinfo: levels and argument checks
assert(debug.getinfo(100) == nil and debug.getinfo(-1) == nil)
checkerr("invalid option", debug.getinfo, 1, "X")
checkerr("invalid option", debug.getinfo, 1, ">S")
checkerr("number expected", debug.getinfo, "x")
checkerr("number expected", debug.getinfo)
checkerr("number expected", debug.getinfo, {})
checkerr("number has no integer representation", debug.getinfo, 1.5)

-- getinfo: chunk names
assert(debug.getinfo(load("return 1", "=named"), "S").short_src == "named")
assert(debug.getinfo(load("return 1", "=named"), "S").source == "=named")
assert(debug.getinfo(load("return 1", "@file.lua"), "S").short_src == "file.lua")
assert(debug.getinfo(load("return 1", "@file.lua"), "S").source == "@file.lua")
assert(debug.getinfo(load("return 1"), "S").short_src == '[string "return 1"]')
assert(debug.getinfo(load("return 1"), "S").what == "main")

-- getlocal and setlocal on the running function
local function locals(a, b)
  local c = 3
  local r = pack(debug.getlocal(1, 1))
  assert(r.n == 2 and r[1] == "a" and r[2] == 1)
  r = pack(debug.getlocal(1, 2))
  assert(r[1] == "b" and r[2] == 2)
  r = pack(debug.getlocal(1, 3))
  assert(r[1] == "c" and r[2] == 3)
  assert(debug.setlocal(1, 3, 33) == "c" and c == 33)
  assert(debug.setlocal(1, 1, "new a") == "a" and a == "new a")
  r = pack(debug.getlocal(1, 50))
  assert(r.n == 1 and r[1] == nil)
  r = pack(debug.setlocal(1, 50, 1))
  assert(r.n == 1 and r[1] == nil)
  return true
end
assert(locals(1, 2))
checkerr("level out of range", debug.getlocal, 50, 1)
checkerr("level out of range", debug.setlocal, 50, 1, 1)
checkerr("number expected", debug.getlocal, 1)
checkerr("number expected", debug.getlocal, {}, 1)
checkerr("value expected", debug.setlocal, 1, 1)

-- getlocal: extra arguments of a vararg function
local function varargs(a, ...)
  local r = pack(debug.getlocal(1, -1))
  assert(r.n == 2 and r[1] == "(vararg)" and r[2] == "x")
  r = pack(debug.getlocal(1, -2))
  assert(r[1] == "(vararg)" and r[2] == "y")
  r = pack(debug.getlocal(1, -3))
  assert(r.n == 1 and r[1] == nil)
  return true
end
assert(varargs(1, "x", "y"))

-- getlocal: parameter names of a function value
assert(debug.getlocal(locals, 1) == "a" and debug.getlocal(locals, 2) == "b")
assert(debug.getlocal(locals, 3) == nil and debug.getlocal(print, 1) == nil)
assert(select("#", debug.getlocal(locals, 1)) == 1)

-- getinfo, getlocal and setlocal on another coroutine
local yield_line = line() + 3
local co = coroutine.create(function(a, b)
  local c = a + b
  coroutine.yield(c)
  return c
end)
assert(debug.getinfo(co, 0) == nil and debug.getinfo(co, 1) == nil)   -- not started yet
checkerr("level out of range", debug.getlocal, co, 0, 1)
coroutine.resume(co, 1, 2)
info = debug.getinfo(co, 0, "Sn")
assert(info.what == "C" and info.name == "yield")
info = debug.getinfo(co, 1, "Sl")
assert(info.what == "Lua" and info.short_src == src and info.currentline == yield_line)
assert(debug.getinfo(co, 2) == nil)
local r = pack(debug.getlocal(co, 1, 1))
assert(r.n == 2 and r[1] == "a" and r[2] == 1)
r = pack(debug.getlocal(co, 1, 3))
assert(r[1] == "c" and r[2] == 3)
assert(debug.setlocal(co, 1, 3, 99) == "c")
r = pack(coroutine.resume(co))
assert(r[1] == true and r[2] == 99)
checkerr("level out of range", debug.getlocal, co, 5, 1)

-- getupvalue and setupvalue
local up1, up2 = 10, 20
local function sum() return up1 + up2 end
r = pack(debug.getupvalue(sum, 1))
assert(r.n == 2 and r[1] == "up1" and r[2] == 10)
r = pack(debug.getupvalue(sum, 2))
assert(r[1] == "up2" and r[2] == 20)
assert(select("#", debug.getupvalue(sum, 3)) == 0)
assert(select("#", debug.getupvalue(sum, 0)) == 0)
assert(select("#", debug.getupvalue(print, 1)) == 0)
assert(debug.setupvalue(sum, 1, 100) == "up1" and sum() == 120)
assert(select("#", debug.setupvalue(sum, 5, 1)) == 0)
r = pack(debug.getupvalue(load("return some_global"), 1))
assert(r[1] == "_ENV" and r[2] == _G)
local chunk = load("return some_value_in_env")
assert(debug.setupvalue(chunk, 1, {some_value_in_env = "from new env"}) == "_ENV")
assert(chunk() == "from new env")
checkerr("function expected", debug.getupvalue, 1, 1)
checkerr("number expected", debug.getupvalue, sum)
checkerr("value expected", debug.setupvalue, sum, 1)

-- upvalueid and upvaluejoin
local shared, other = 1, 2
local function f1() return shared, other end
local function f2() return other end
assert(type(debug.upvalueid(f1, 1)) == "userdata")
assert(debug.upvalueid(f1, 2) == debug.upvalueid(f2, 1))
assert(debug.upvalueid(f1, 1) ~= debug.upvalueid(f2, 1))
assert(debug.upvalueid(f1, 1) == debug.upvalueid(f1, 1))
assert(debug.upvalueid(f1, 5) == nil and debug.upvalueid(print, 1) == nil)
checkerr("number expected", debug.upvalueid, f1)
checkerr("function expected", debug.upvalueid, 1, 1)
local a1, a2 = "one", "two"
local function u1() return a1 end
local function u2() return a2 end
debug.upvaluejoin(u1, 1, u2, 1)
assert(u1() == "two" and debug.upvalueid(u1, 1) == debug.upvalueid(u2, 1))
assert(debug.setupvalue(u2, 1, "changed") == "a2" and u1() == "changed")
checkerr("invalid upvalue index", debug.upvaluejoin, u1, 2, u2, 1)
checkerr("invalid upvalue index", debug.upvaluejoin, u1, 1, u2, 2)
checkerr("invalid upvalue index", debug.upvaluejoin, print, 1, u2, 1)

-- getmetatable and setmetatable ignore __metatable and work for any type
local t = {}
assert(debug.setmetatable(t, {__index = {z = 1}}) == t and t.z == 1)
local protected = setmetatable({}, {__metatable = "locked"})
assert(debug.getmetatable(protected).__metatable == "locked")
assert(debug.setmetatable(protected, nil) == protected and getmetatable(protected) == nil)
debug.setmetatable(10, {__index = {double = function(n) return n * 2 end}})
assert((5):double() == 10 and getmetatable(1).__index.double ~= nil)
debug.setmetatable(10, nil)
assert(debug.getmetatable(10) == nil)
debug.setmetatable(print, {__index = {tag = "function metatable"}})
assert(print.tag == "function metatable" and (function() end).tag == "function metatable")
debug.setmetatable(print, nil)
checkerr("nil or table expected", debug.setmetatable, {}, 1)
checkerr("nil or table expected", debug.setmetatable, {})
checkerr("value expected", debug.getmetatable)

-- getregistry, getuservalue and setuservalue
assert(type(debug.getregistry()) == "table")
assert(debug.getuservalue(1) == nil and debug.getuservalue({}, 2) == nil)
checkerr("userdata expected", debug.setuservalue, 1, 2)

-- hooks: no hook is installed by default
assert(debug.gethook() == nil and select("#", debug.gethook()) == 1)
assert(select("#", debug.sethook()) == 0)

-- traceback: messages
l = line()
local tb = debug.traceback("msg")
assert(tb:find("^msg\nstack traceback:\n\t"))
assert(tb:find("\n\t" .. src .. ":" .. l + 1 .. ": in main chunk", 1, true), tb)
assert(debug.traceback("msg", 1) == debug.traceback("msg"))
l = line()
tb = debug.traceback()
assert(tb:find("^stack traceback:\n\t" .. plain(src) .. ":" .. l + 1 .. ": in main chunk"))
assert(debug.traceback(12):find("^12\nstack traceback:"))
assert(debug.traceback(1.5):find("^1.5\nstack traceback:"))
assert(debug.traceback("multi\nline"):find("^multi\nline\nstack traceback:"))
assert(debug.traceback(nil):find("^stack traceback:"))
-- values that are neither strings nor nil are returned untouched
assert(debug.traceback(t) == t and debug.traceback(print) == print and debug.traceback(false) == false)
assert(select("#", debug.traceback(t)) == 1)
checkerr("number expected", debug.traceback, "m", "x")

-- traceback: levels
tb = debug.traceback("msg", 0)
assert(tb:find("^msg\nstack traceback:\n\t%[C%]: in "))       -- level 0 is traceback itself
assert(tb:find("'traceback'", 1, true), tb)
assert(debug.traceback("m", 100) == "m\nstack traceback:")
l = line()
local function lvl3() return debug.traceback("deep") end
local function lvl2() local r = lvl3() return r end
local function lvl1() local r = lvl2() return r end
tb = lvl1()
local head = "deep\nstack traceback:" ..
  "\n\t" .. src .. ":" .. l + 1 .. ": in upvalue 'lvl3'" ..
  "\n\t" .. src .. ":" .. l + 2 .. ": in upvalue 'lvl2'" ..
  "\n\t" .. src .. ":" .. l + 3 .. ": in local 'lvl1'" ..
  "\n\t" .. src .. ":" .. l + 4 .. ": in main chunk"
assert(tb:sub(1, #head) == head, tb)
-- anonymous functions are identified by their position
l = line()
tb = (function() local r = debug.traceback("anon") return r end)()
assert(tb:find("in function <" .. src .. ":" .. l + 1 .. ">", 1, true), tb)
-- tail calls are marked
local function tail() return lvl3() end
local function caller() local r = tail() return r end
tb = caller()
assert(tb:find("\n\t(...tail calls...)", 1, true), tb)
-- deep stacks are abbreviated
local function deep(n) if n == 0 then return debug.traceback("d") end return (deep(n - 1)) end
tb = deep(40)
assert(tb:find("\n\t%.%.%.\t%(skipping %d+ levels%)"))
local count = 0
for _ in tb:gmatch("\n") do count = count + 1 end
assert(count >= 22 and count <= 23)

-- traceback: another coroutine
l = line() + 1
co = coroutine.create(function() coroutine.yield() end)
assert(debug.traceback(co) == "stack traceback:")
coroutine.resume(co)
tb = debug.traceback(co)
local where = src .. ":" .. l
assert(tb == "stack traceback:\n\t[C]: in field 'yield'\n\t" .. where .. ": in function <" .. where .. ">", tb)
assert(debug.traceback(co, "comsg") == "comsg\n" .. tb)
assert(debug.traceback(co, nil) == tb and debug.traceback(co, 5) == "5\n" .. tb)
assert(debug.traceback(co, "comsg", 1) ==
       "comsg\nstack traceback:\n\t" .. where .. ": in function <" .. where .. ">")
assert(debug.traceback(co, t) == t)

-- traceback as a message handler sees the stack of the error
l = line() + 1
r = pack(xpcall(function() local x = nil; return x.y end, debug.traceback))
where = src .. ":" .. l
assert(r.n == 2 and r[1] == false)
assert(r[2]:find("^" .. plain(where) .. ": attempt to index a nil value"))
assert(r[2]:find("\nstack traceback:\n\t" .. where .. ": in function <" .. where .. ">", 1, true), r[2])
assert(r[2]:find("'xpcall'", 1, true) and r[2]:find(where .. ": in main chunk", 1, true), r[2])
l = line() + 1
r = pack(xpcall(function() error("E") end, function(m) return debug.traceback(m, 2) end))
assert(r[2]:find("^" .. plain(src .. ":" .. l) .. ": E\nstack traceback:\n\t%[C%]: in "), r[2])
assert(r[2]:find("'error'", 1, true))

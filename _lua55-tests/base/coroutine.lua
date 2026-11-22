-- The coroutine library.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

local function pack(...)
  return {n = select("#", ...), ...}
end

local src = debug.getinfo(1, "S").short_src
local function line() return debug.getinfo(2, "l").currentline end

-- create, resume, yield and status
local co = coroutine.create(function(a, b)
  local c = coroutine.yield(a + b)
  local d, e = coroutine.yield(c * 2)
  return d + e, "end"
end)
assert(type(co) == "thread" and coroutine.status(co) == "suspended")
local r = pack(coroutine.resume(co, 1, 2))
assert(r.n == 2 and r[1] == true and r[2] == 3)
assert(coroutine.status(co) == "suspended")
r = pack(coroutine.resume(co, 10))
assert(r.n == 2 and r[1] == true and r[2] == 20)
r = pack(coroutine.resume(co, 3, 4))
assert(r.n == 3 and r[1] == true and r[2] == 7 and r[3] == "end")
assert(coroutine.status(co) == "dead")
r = pack(coroutine.resume(co))
assert(r.n == 2 and r[1] == false and r[2] == "cannot resume dead coroutine")

-- values pass through unchanged, including nils
r = pack(coroutine.resume(coroutine.create(function(...) return select("#", ...), ... end), nil, nil))
assert(r.n == 4 and r[2] == 2 and r[3] == nil and r[4] == nil)
r = pack(coroutine.resume(coroutine.create(function() end)))
assert(r.n == 1 and r[1] == true)
co = coroutine.create(function() return coroutine.yield() end)
assert(select("#", coroutine.resume(co)) == 1)
r = pack(coroutine.resume(co, 1, 2, 3))
assert(r.n == 4 and r[2] == 1 and r[4] == 3 and coroutine.status(co) == "dead")
co = coroutine.create(function() coroutine.yield(nil, nil) end)
r = pack(coroutine.resume(co))
assert(r.n == 3 and r[1] == true)

-- a coroutine whose body is a library function
co = coroutine.create(print)
r = pack(coroutine.resume(co, "printed", "by a coroutine"))
assert(r.n == 1 and r[1] == true and coroutine.status(co) == "dead")
co = coroutine.create(coroutine.yield)
r = pack(coroutine.resume(co, 5))
assert(r.n == 2 and r[1] == true and r[2] == 5 and coroutine.status(co) == "suspended")
r = pack(coroutine.resume(co, 6))
assert(r.n == 2 and r[1] == true and r[2] == 6 and coroutine.status(co) == "dead")
co = coroutine.create(tostring)
r = pack(coroutine.resume(co, 12))
assert(r.n == 2 and r[2] == "12")

-- running and isyieldable
local main, ismain = coroutine.running()
assert(type(main) == "thread" and ismain == true)
assert(coroutine.running() == main)
assert(coroutine.isyieldable() == false)
assert(coroutine.isyieldable(main) == false)
assert(coroutine.status(main) == "running")
co = coroutine.create(function()
  local th, m = coroutine.running()
  return th, m, coroutine.isyieldable(), coroutine.status(th), coroutine.status(main), coroutine.isyieldable(main)
end)
r = pack(coroutine.resume(co))
assert(r.n == 7 and r[2] == co and r[3] == false and r[4] == true and r[5] == "running")
assert(r[6] == "normal" and r[7] == false)
assert(coroutine.isyieldable(coroutine.create(print)) == true)
assert(tostring(main):find("^thread: ") == 1)

-- status "normal" and resuming threads that are not suspended
local inner_result
local outer
outer = coroutine.create(function()
  local inner = coroutine.create(function()
    return coroutine.status(outer), coroutine.resume(outer)
  end)
  inner_result = pack(coroutine.resume(inner))
end)
coroutine.resume(outer)
assert(inner_result.n == 4 and inner_result[2] == "normal")
assert(inner_result[3] == false and inner_result[4] == "cannot resume non-suspended coroutine")
r = pack(coroutine.resume(coroutine.running()))
assert(r.n == 2 and r[1] == false and r[2] == "cannot resume non-suspended coroutine")
-- the main thread seen from a coroutine
co = coroutine.create(function() return coroutine.resume(main) end)
r = pack(coroutine.resume(co))
assert(r.n == 3 and r[2] == false and r[3] == "cannot resume non-suspended coroutine")

-- errors inside coroutines
local l
co = coroutine.create(function() l = line() error("oops") end)
r = pack(coroutine.resume(co))
assert(r.n == 2 and r[1] == false and r[2] == src .. ":" .. l .. ": oops")
assert(coroutine.status(co) == "dead")
r = pack(coroutine.resume(co))
assert(r[1] == false and r[2] == "cannot resume dead coroutine")
local errobj = {code = 1}
r = pack(coroutine.resume(coroutine.create(function() error(errobj) end)))
assert(r.n == 2 and r[1] == false and r[2] == errobj)
r = pack(coroutine.resume(coroutine.create(function() error() end)))
assert(r.n == 2 and r[1] == false and r[2] == "<no error object>")
r = pack(coroutine.resume(coroutine.create(function() local x = nil; return x.y end)))
assert(r[1] == false and r[2]:find("attempt to index a nil value", 1, true))
-- an error does not close to-be-closed variables; coroutine.close does
local log = {}
local function clearlog()
  for i = #log, 1, -1 do log[i] = nil end
end
co = coroutine.create(function()
  local a <close> = setmetatable({}, {__close = function(_, e) log[#log + 1] = "closed:" .. tostring(e) end})
  error("E", 0)
end)
r = pack(coroutine.resume(co))
assert(r[1] == false and r[2] == "E" and #log == 0)
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == "E" and log[1] == "closed:E")

-- yielding outside a coroutine
r = pack(pcall(coroutine.yield, 1))
assert(r[1] == false and r[2] == "attempt to yield from outside a coroutine")

-- pcall and error handling inside a coroutine, without yielding across them
co = coroutine.create(function()
  local ok, msg = pcall(error, "inner", 0)
  local v = coroutine.yield(ok, msg)
  local ok2, msg2 = xpcall(function() error("second", 0) end, function(m) return "H:" .. m end)
  return v, ok2, msg2
end)
r = pack(coroutine.resume(co))
assert(r.n == 3 and r[2] == false and r[3] == "inner")
r = pack(coroutine.resume(co, "resumed"))
assert(r.n == 4 and r[2] == "resumed" and r[3] == false and r[4] == "H:second")
r = pack(coroutine.wrap(function() return pcall(pcall, error, "e") end)())
assert(r.n == 3 and r[1] == true and r[2] == false and r[3] == "e")

-- wrap
local w = coroutine.wrap(function(a)
  local b = coroutine.yield(a + 1)
  return b * 2
end)
assert(type(w) == "function")
assert(w(1) == 2 and w(5) == 10)
checkerr("cannot resume dead coroutine", w)
-- wrap as a generator
local values = {}
for v in coroutine.wrap(function() for i = 1, 3 do coroutine.yield(i) end end) do
  values[#values + 1] = v
end
assert(table.concat(values, ",") == "1,2,3")
w = coroutine.wrap(function(...) return coroutine.yield(...) end)
r = pack(w(1, 2))
assert(r.n == 2 and r[1] == 1 and r[2] == 2)
r = pack(w(4, 5, 6))
assert(r.n == 3 and r[3] == 6)

-- errors propagate through wrap; string errors get the position of the caller
w = coroutine.wrap(function() error("werr", 0) end)
local ok, msg = pcall(w)
assert(not ok and msg == "werr")
w = coroutine.wrap(function() error("werr", 0) end)
ok, msg = pcall(function() l = line() w() end)
assert(not ok and msg == src .. ":" .. l .. ": werr")
w = coroutine.wrap(function() error(errobj) end)
ok, msg = pcall(function() w() end)
assert(not ok and msg == errobj)
w = coroutine.wrap(function() return 1 end)
w()
ok, msg = pcall(function() l = line() w() end)
assert(not ok and msg == src .. ":" .. l .. ": cannot resume dead coroutine")
-- a wrapped coroutine cannot resume itself
local holder = {}
holder.w = coroutine.wrap(function() return pcall(holder.w) end)
ok, msg = holder.w()
assert(not ok and msg == "cannot resume non-suspended coroutine")
-- an error in a wrapped coroutine closes its to-be-closed variables
clearlog()
w = coroutine.wrap(function()
  local a <close> = setmetatable({}, {__close = function(_, e) log[#log + 1] = "wrap closed:" .. tostring(e) end})
  coroutine.yield(1)
  error("x", 0)
end)
assert(w() == 1)
ok, msg = pcall(w)
assert(not ok and msg == "x" and log[1] == "wrap closed:x")

-- close: a suspended coroutine that never ran
co = coroutine.create(function() coroutine.yield() end)
r = pack(coroutine.close(co))
assert(r.n == 1 and r[1] == true and coroutine.status(co) == "dead")
assert(coroutine.close(coroutine.create(print)) == true)
-- close: a suspended coroutine; closing twice is fine
co = coroutine.create(function() coroutine.yield() end)
coroutine.resume(co)
assert(coroutine.close(co) == true and coroutine.status(co) == "dead")
assert(coroutine.close(co) == true)
r = pack(coroutine.resume(co))
assert(r[1] == false and r[2] == "cannot resume dead coroutine")
-- close: a finished coroutine
co = coroutine.create(function() coroutine.yield() end)
coroutine.resume(co) coroutine.resume(co)
assert(coroutine.status(co) == "dead" and coroutine.close(co) == true)
-- close: a coroutine that died with an error reports it once
co = coroutine.create(function() l = line() error("x") end)
coroutine.resume(co)
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == src .. ":" .. l .. ": x")
r = pack(coroutine.close(co))
assert(r.n == 1 and r[1] == true)

-- close: pending to-be-closed variables are closed in reverse order
clearlog()
local function closer(name, fail)
  return setmetatable({}, {__close = function(_, e)
    log[#log + 1] = name .. ":" .. tostring(e)
    if fail then error(fail, 0) end
  end})
end
co = coroutine.create(function()
  local a <close> = closer("a")
  local b <close> = closer("b")
  coroutine.yield(1)
end)
coroutine.resume(co)
r = pack(coroutine.close(co))
assert(r.n == 1 and r[1] == true)
assert(table.concat(log, ",") == "b:nil,a:nil" and coroutine.status(co) == "dead")
-- an error while closing is reported and passed on to the remaining variables
clearlog()
co = coroutine.create(function()
  local a <close> = closer("a")
  local b <close> = closer("b", "cerr")
  coroutine.yield(1)
end)
coroutine.resume(co)
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == "cerr")
assert(table.concat(log, ",") == "b:nil,a:cerr" and coroutine.status(co) == "dead")

-- close: the main thread and running or normal coroutines
checkerr("cannot close main thread", coroutine.close, coroutine.running())
checkerr("cannot close main thread", coroutine.close)
outer = coroutine.create(function()
  local inner = coroutine.create(function() return pcall(coroutine.close, outer) end)
  return coroutine.resume(inner)
end)
r = pack(coroutine.resume(outer))
assert(r.n == 4 and r[3] == false and r[4]:find("cannot close a normal coroutine", 1, true))
co = coroutine.create(function() return pcall(coroutine.close, main) end)
r = pack(coroutine.resume(co))
assert(r[2] == false and r[3]:find("cannot close a normal coroutine", 1, true))

-- close: a running coroutine may close itself; it terminates immediately
clearlog()
co = coroutine.create(function()
  coroutine.close(coroutine.running())
  log[#log + 1] = "not reached"
end)
r = pack(coroutine.resume(co))
assert(r.n == 1 and r[1] == true and #log == 0 and coroutine.status(co) == "dead")
co = coroutine.create(function()
  local a <close> = closer("self")
  coroutine.close()
  log[#log + 1] = "not reached"
end)
r = pack(coroutine.resume(co))
assert(r.n == 1 and r[1] == true and table.concat(log, ",") == "self:nil")
assert(coroutine.status(co) == "dead")
clearlog()
co = coroutine.create(function()
  local a <close> = closer("self", "close failed")
  coroutine.close()
end)
r = pack(coroutine.resume(co))
assert(r.n == 2 and r[1] == false and r[2] == "close failed" and coroutine.status(co) == "dead")

-- argument checks
checkerr("function expected", coroutine.create)
checkerr("function expected", coroutine.create, 1)
checkerr("function expected", coroutine.wrap)
checkerr("function expected", coroutine.wrap, {})
checkerr("thread expected", coroutine.resume)
checkerr("thread expected", coroutine.resume, 1)
checkerr("thread expected", coroutine.status)
checkerr("thread expected", coroutine.status, 1)
checkerr("thread expected", coroutine.close, 1)
checkerr("thread expected", coroutine.isyieldable, 1)

-- many coroutines, deep resume chains and long runs
local function chain(n)
  if n == 0 then return 0 end
  local c = coroutine.wrap(chain)
  return 1 + c(n - 1)
end
assert(chain(40) == 40)
local sum = 0
local gen = coroutine.wrap(function() for i = 1, 10000 do coroutine.yield(i) end return nil end)
for i = 1, 10000 do sum = sum + gen() end
assert(sum == 50005000)
local threads = {}
for i = 1, 200 do
  threads[i] = coroutine.create(function(x) local y = coroutine.yield(x * 2) return x + y end)
end
for i = 1, 200 do
  local ok1, v = coroutine.resume(threads[i], i)
  assert(ok1 and v == i * 2)
end
for i = 200, 1, -1 do
  local ok1, v = coroutine.resume(threads[i], 1)
  assert(ok1 and v == i + 1 and coroutine.status(threads[i]) == "dead")
end

-- a coroutine closing itself is not stopped by protected calls around the close
clearlog()
co = coroutine.create(function()
  local a <close> = closer("a")
  pcall(coroutine.close)
  log[#log + 1] = "after pcall"
  return "returned"
end)
r = pack(coroutine.resume(co))
assert(r.n == 1 and r[1] == true and coroutine.status(co) == "dead" and table.concat(log, ",") == "a:nil")
clearlog()
co = coroutine.create(function()
  xpcall(coroutine.close, function(m) log[#log + 1] = "handler" return m end)
  log[#log + 1] = "after xpcall"
end)
r = pack(coroutine.resume(co))
assert(r.n == 1 and r[1] == true and coroutine.status(co) == "dead" and #log == 0)
-- ... nor by nested calls or metamethods
co = coroutine.create(function()
  local function deep(n) if n == 0 then coroutine.close() end deep(n - 1) end
  deep(10)
end)
r = pack(coroutine.resume(co))
assert(r.n == 1 and r[1] == true and coroutine.status(co) == "dead")
co = coroutine.create(function()
  local t = setmetatable({}, {__index = function() coroutine.close() end})
  return t.x
end)
r = pack(coroutine.resume(co))
assert(r.n == 1 and r[1] == true and coroutine.status(co) == "dead")
assert(select("#", coroutine.wrap(function() coroutine.close() end)()) == 0)

-- a close handler cannot yield while coroutine.close runs it
clearlog()
co = coroutine.create(function()
  local a <close> = setmetatable({}, {__close = function() coroutine.yield("from close") end})
  coroutine.yield(1)
end)
coroutine.resume(co)
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == "attempt to yield across a C-call boundary")
assert(coroutine.status(co) == "dead")
-- a close handler may use other coroutines
co = coroutine.create(function()
  local a <close> = setmetatable({}, {__close = function()
    log[#log + 1] = coroutine.wrap(function() return "nested ran" end)()
  end})
  coroutine.yield(1)
end)
coroutine.resume(co)
assert(coroutine.close(co) == true and table.concat(log, ",") == "nested ran")
assert(coroutine.running() == main)

-- closing a coroutine from another coroutine
clearlog()
local victim = coroutine.create(function() local a <close> = closer("victim") coroutine.yield() end)
coroutine.resume(victim)
r = pack(coroutine.resume(coroutine.create(function() return coroutine.close(victim) end)))
assert(r.n == 2 and r[2] == true and coroutine.status(victim) == "dead" and log[1] == "victim:nil")

-- error values of any kind are reported by close
co = coroutine.create(function() error(errobj) end)
coroutine.resume(co)
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == errobj)
co = coroutine.create(function() error() end)
coroutine.resume(co)
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == "<no error object>")
-- an error raised while closing a failed coroutine replaces its error
clearlog()
co = coroutine.create(function()
  local a <close> = closer("f", "close err")
  error("body err", 0)
end)
r = pack(coroutine.resume(co))
assert(r[1] == false and r[2] == "body err")
r = pack(coroutine.close(co))
assert(r.n == 2 and r[1] == false and r[2] == "close err" and log[1] == "f:body err")
clearlog()
w = coroutine.wrap(function()
  local a <close> = closer("w", "close err")
  error("body err", 0)
end)
ok, msg = pcall(w)
assert(not ok and msg == "close err" and log[1] == "w:body err")

-- an abandoned generator can be closed
clearlog()
local generator = coroutine.create(function()
  local a <close> = closer("gen")
  for i = 1, 3 do coroutine.yield(i) end
end)
assert(select(2, coroutine.resume(generator)) == 1)
assert(coroutine.close(generator) == true and log[1] == "gen:nil")

-- error levels inside a coroutine: the body has no Lua caller
r = pack(coroutine.resume(coroutine.create(function() error("lvl2", 2) end)))
assert(r[1] == false and r[2] == "lvl2")
r = pack(coroutine.resume(coroutine.create(function() assert(nil) end)))
assert(r[1] == false and r[2]:find(": assertion failed!", 1, true))

-- yields pass through nested coroutines
co = coroutine.wrap(function()
  local inner = coroutine.wrap(function() coroutine.yield("a") coroutine.yield("b") end)
  coroutine.yield(inner())
  coroutine.yield(inner())
end)
assert(co() == "a" and co() == "b")

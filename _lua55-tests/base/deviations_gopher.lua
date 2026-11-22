-- Intentional deviations of this runtime from the reference Lua 5.5
-- interpreter in the base, coroutine, package and debug libraries. This
-- script is not run under the reference interpreter.

local function pack(...)
  return {n = select("#", ...), ...}
end

-- 1. A coroutine cannot yield while a Go function is on its call stack
--    between the yield and the resume: the VM runs protected calls,
--    metamethods and iterators as nested Go calls. The reference
--    implementation supports yields across pcall, xpcall, metamethods and
--    iterators. Here such a yield raises the error that the reference uses
--    for yields across C functions, instead of misbehaving.
local co = coroutine.create(function()
  local ok, msg = pcall(function() coroutine.yield(1) end)
  return ok, msg, coroutine.isyieldable(), pcall(coroutine.isyieldable)
end)
local r = pack(coroutine.resume(co))
assert(r.n == 6 and r[1] == true and r[2] == false)
assert(r[3] == "attempt to yield across a C-call boundary")
assert(r[4] == true)               -- yieldable at the top level of the coroutine
assert(r[5] == true and r[6] == false)   -- ... but not inside a protected call
co = coroutine.wrap(function()
  local obj = setmetatable({}, {__add = function() return coroutine.yield("in metamethod") end})
  return pcall(function() return obj + 1 end)
end)
r = pack(co())
assert(r.n == 2 and r[1] == false and r[2] == "attempt to yield across a C-call boundary")
co = coroutine.wrap(function()
  return pcall(function()
    for _ in function() return coroutine.yield("in iterator") end do end
  end)
end)
r = pack(co())
assert(r.n == 2 and r[1] == false and r[2] == "attempt to yield across a C-call boundary")

-- 2. Hooks are not supported by the VM. debug.sethook records the hook so
--    that debug.gethook reports it, but the hook is never called.
local calls = {n = 0}
local hook = function() calls.n = calls.n + 1 end
debug.sethook(hook, "crl", 5)
local h, mask, count = debug.gethook()
assert(h == hook and mask == "crl" and count == 5)
for i = 1, 100 do local _ = tostring(i) end
debug.sethook()
assert(debug.gethook() == nil)
assert(calls.n == 0)

-- 3. The source of a chunk loaded from a string is reported by its chunk
--    identifier; the reference reports the complete source text.
assert(debug.getinfo(load("return 1"), "S").source == '=[string "return 1"]')

-- 4. A traceback ends with the bottom Lua function. The reference
--    interpreter adds the C function of the host program ("[C]: in ?").
local tb = debug.traceback("m")
assert(tb:find("in main chunk$"), tb)

-- 5. The Go garbage collector cannot be tuned or stepped per Lua state:
--    a step performs a full collection and always reports a finished
--    cycle, the mode and the parameters are only recorded. A new state is
--    in incremental mode (the reference stand-alone interpreter switches
--    to generational mode at start-up).
assert(collectgarbage("step") == true and collectgarbage("step", 1) == true)
assert(collectgarbage("incremental") == "incremental")

-- 6. C libraries cannot be loaded. package.cpath is empty and
--    package.loadlib fails like a reference build without dynamic library
--    support.
assert(package.cpath == "")
r = pack(package.loadlib("anything", "luaopen_anything"))
assert(r.n == 3 and r[1] == nil and r[3] == "absent")
assert(r[2] == "dynamic libraries not enabled; check your Lua installation")

-- 7. Precompiled (binary) chunks are not supported.
r = pack(load("\27Lua", "=bin", "b"))
assert(r.n == 2 and r[1] == nil and r[2] == "bin: bad binary format (precompiled chunks are not supported)")

-- 8. GopherLua extras that stay available in the Lua 5.5 profile.
assert(type(_GOPHER_LUA_VERSION) == "string" and type(_printregs) == "function")

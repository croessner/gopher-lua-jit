-- The set of global names of the Lua 5.5 profile.

assert(_VERSION == "Lua 5.5")
assert(_G._G == _G)
assert(_G._VERSION == _VERSION)

-- every standard global function is present
local functions = {
  "assert", "collectgarbage", "dofile", "error", "getmetatable", "ipairs",
  "load", "loadfile", "next", "pairs", "pcall", "print", "rawequal", "rawget",
  "rawlen", "rawset", "require", "select", "setmetatable", "tonumber",
  "tostring", "type", "warn", "xpcall",
}
for _, name in ipairs(functions) do
  assert(type(_G[name]) == "function", name .. " is missing")
end

-- functions that Lua 5.1 had and later versions removed
local removed = {
  "unpack", "loadstring", "getfenv", "setfenv", "module", "newproxy", "gcinfo",
}
for _, name in ipairs(removed) do
  assert(_G[name] == nil, name .. " must not be defined")
end

-- the standard libraries owned by the base slice
for _, name in ipairs({"coroutine", "package", "debug"}) do
  assert(type(_G[name]) == "table", name .. " is missing")
  assert(package.loaded[name] == _G[name], name .. " is not in package.loaded")
end
assert(package.loaded._G == _G)

local function names(tbl)
  local set = {}
  for k in pairs(tbl) do set[k] = true end
  return set
end

local co = names(coroutine)
for _, name in ipairs({"close", "create", "isyieldable", "resume", "running", "status", "wrap", "yield"}) do
  assert(co[name], "coroutine." .. name .. " is missing")
end

local pkg = names(package)
for _, name in ipairs({"config", "cpath", "loaded", "loadlib", "path", "preload", "searchers", "searchpath"}) do
  assert(pkg[name], "package." .. name .. " is missing")
end
assert(package.loaders == nil and package.seeall == nil)

local dbg = names(debug)
for _, name in ipairs({"gethook", "getinfo", "getlocal", "getmetatable", "getregistry", "getupvalue",
                       "getuservalue", "sethook", "setlocal", "setmetatable", "setupvalue", "setuservalue",
                       "traceback", "upvalueid", "upvaluejoin"}) do
  assert(dbg[name], "debug." .. name .. " is missing")
end
assert(debug.getfenv == nil and debug.setfenv == nil)

-- type
assert(type(nil) == "nil" and type(true) == "boolean" and type(1) == "number")
assert(type(1.5) == "number" and type("s") == "string" and type({}) == "table")
assert(type(print) == "function" and type(coroutine.create(print)) == "thread")
assert(not pcall(type))
assert(select("#", type(nil)) == 1)

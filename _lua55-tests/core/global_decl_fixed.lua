-- Global declarations of Lua 5.5.
local load = loadstring or load

-- runs a chunk and returns its results
local function run(src, ...)
  local f = load(src)
  assert(f, "chunk does not compile: " .. src)
  return f(...)
end
local function compiles(src) return load(src) ~= nil end

-- ## defining a global function whose name already holds a value is a runtime error
do
GD_T = 1
local ok = pcall(load("global function GD_T() end"))
local kept = GD_T
GD_T = nil
assert(not ok)
assert(kept == 1)
end

-- ## defining a global function twice is a runtime error
do
local ok1 = pcall(load("global function GD_U() end"))
local ok2 = pcall(load("global function GD_U() end"))
GD_U = nil
assert(not ok2)
local ok3 = pcall(load("global function GD_U2() end; global function GD_U2() end"))
GD_U2 = nil
assert(not ok3)
end

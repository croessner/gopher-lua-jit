-- Functions: finer points of the named vararg table of Lua 5.5.
local load = loadstring or load

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end
local function pass(...) return ... end

-- ## the name of the vararg table is a read-only variable
do
assert(load("local function f(...t) t.x = 1 end") ~= nil)
assert(load("local function f(...t) local t = 1; t = 2 end") ~= nil)
end

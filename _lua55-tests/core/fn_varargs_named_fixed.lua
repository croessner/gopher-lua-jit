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
assert(load("local function f(...t) t = 1 end") == nil)
assert(load("local function f(...t) t, x = 1, 2 end") == nil)
assert(load("local function f(...t) local function g() t = 1 end end") == nil)
end

-- ## the vararg expression reflects changes made to the vararg table
do
local function h(...v) v[1] = "changed"; return ... end
assert(show(h(1, 2)) == "changed,2")
local function h2(...v) v.n = 1; return ... end
assert(show(h2(1, 2)) == "1")
local function h3(...v) v[3] = "x"; v.n = 3; return ... end
assert(show(h3(1, 2)) == "1,2,x")
local function h4(...v) v.n = 0; return select("#", ...) end
assert(h4(1, 2, 3) == 0)
end

-- ## the vararg table and the vararg expression in the same function
do
local function s(...v) v[2] = "two"; local a, b = ...; return b end
assert(s(1, 2, 3) == "two")
end

-- Metatables: __call.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## __call chains: the handler itself may be a callable table
do
local inner = setmetatable({}, {__call = function(self, ...) return "inner", select("#", ...) end})
local outer = setmetatable({}, {__call = inner})
local name, n = outer(1, 2)
assert(name == "inner")
assert(n == 3)
local level3 = setmetatable({}, {__call = outer})
name, n = level3()
assert(name == "inner")
assert(n == 2)
end

-- ## arguments in a __call chain: each level prepends its object
do
local seen
local f = function(...) seen = {...}; return #seen end
local l1 = setmetatable({}, {__call = f})
local l2 = setmetatable({}, {__call = l1})
assert(l2("x") == 3)
assert(seen[1] == l1 and seen[2] == l2 and seen[3] == "x")
end

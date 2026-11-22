-- Stress-ish semantics: recursion limits, large constructs, many locals.
local load = loadstring or load

-- ## very large table constructor
do
local n = 60000
local t = load("return {" .. string.rep("7,", n) .. "}")()
assert(#t == n)
assert(t[25551] == 7)
assert(t[n] == 7)
end

-- ## the limit of 255 upvalues is enforced
do
local function upvalues(n)
  -- spread the locals over nested functions to stay below the locals limit
  local use = ""
  for i = 1, n do use = use .. "u" .. i .. (i < n and " + " or "") end
  local per = 150
  local k = 0
  local src = ""
  for i = 1, n do
    if (i - 1) % per == 0 then src = src .. "return (function() " ; k = k + 1 end
    src = src .. "local u" .. i .. " = " .. i .. "; "
  end
  src = src .. "return function() return " .. use .. " end " .. string.rep("end)() ", k)
  return load(src)
end
local f255 = upvalues(255)
assert(upvalues(256) == nil)
end

-- ## a call with 240 arguments
do
local function count(...) return select("#", ...) end
local args = string.rep("1,", 239) .. "1"
assert(load("local count = ... ; return count(" .. args .. ")")(count) == 240)
end

-- calls of a small Lua function
local function add(a, b)
  return a + b
end
return function(n)
  local s = 0
  for i = 1, n do
    s = add(s, i)
  end
  return s
end

-- metamethod dispatch (__add and __index)
local mt = {}
mt.__index = mt
mt.__add = function(a, b)
  return setmetatable({x = a.x + b.x, y = a.y + b.y}, mt)
end
function mt.len2(v)
  return v.x * v.x + v.y * v.y
end
return function(n)
  local acc = setmetatable({x = 0, y = 0}, mt)
  local step = setmetatable({x = 1, y = 2}, mt)
  for i = 1, n do
    acc = acc + step
  end
  return acc:len2()
end

-- string keyed field reads and writes
return function(n)
  local p = {x = 0, y = 1, z = 2}
  for i = 1, n do
    p.x = p.x + p.y
    p.z = p.x - p.y
  end
  return p.z
end

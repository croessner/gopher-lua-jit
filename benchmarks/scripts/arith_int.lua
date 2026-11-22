-- integer arithmetic in a tight loop
return function(n)
  local s = 0
  for i = 1, n do
    s = s + (i * 3) % 7 - (i % 5)
  end
  return s
end

-- array access with index arithmetic
return function(n)
  local t = {}
  for i = 1, n do t[i] = i % 17 end
  local s = 0
  for k = 1, 4 do
    for i = 2, n - 1 do
      s = s + t[i - 1] - 2 * t[i] + t[i + 1]
    end
  end
  return s
end

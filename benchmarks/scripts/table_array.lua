-- array writes and reads
return function(n)
  local t = {}
  for i = 1, n do
    t[i] = i
  end
  local s = 0
  for k = 1, 4 do
    for i = 1, #t do
      s = s + t[i]
    end
  end
  return s
end

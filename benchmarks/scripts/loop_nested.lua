-- nested counting loops
return function(n)
  local s = 0
  for i = 1, n do
    for j = 1, 100 do
      s = s + j
    end
  end
  return s
end

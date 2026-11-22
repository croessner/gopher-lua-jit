-- calls of library functions (math.floor, math.sqrt)
return function(n)
  local s = 0
  for i = 1, n do
    s = s + math.floor(i / 3) + math.floor(math.sqrt(i))
  end
  return s
end

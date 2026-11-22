-- floating point arithmetic in a tight loop
return function(n)
  local x = 0.5
  for i = 1, n do
    x = x * 0.9999999 + i / 3.0 - 0.25
  end
  return x
end

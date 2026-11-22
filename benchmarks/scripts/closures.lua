-- closure creation and calls through upvalues
return function(n)
  local total = 0
  for i = 1, n do
    local k = i
    local f = function(x) return x + k end
    total = total + f(1)
  end
  return total
end

-- calls of a Go function registered by the host (global "gofn")
return function(n)
  local s = 0
  for i = 1, n do
    s = s + gofn(i)
  end
  return s
end

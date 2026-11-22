-- sieve of Eratosthenes on a boolean table
return function(n)
  local flags = {}
  for i = 1, n do flags[i] = true end
  local count = 0
  for i = 2, n do
    if flags[i] then
      count = count + 1
      for j = i + i, n, i do
        flags[j] = false
      end
    end
  end
  return count
end

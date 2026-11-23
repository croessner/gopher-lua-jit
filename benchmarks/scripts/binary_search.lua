-- binary search in a sorted array
local floor = math.floor
return function(n)
  local a = {}
  for i = 1, 1024 do a[i] = i * 2 end
  local hits = 0
  for key = 1, n do
    local lo, hi = 1, 1024
    local target = key % 2048
    while lo <= hi do
      local mid = floor((lo + hi) / 2)
      local v = a[mid]
      if v == target then
        hits = hits + 1
        break
      elseif v < target then
        lo = mid + 1
      else
        hi = mid - 1
      end
    end
  end
  return hits
end

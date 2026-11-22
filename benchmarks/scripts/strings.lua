-- string concatenation, formatting and searching
return function(n)
  local count = 0
  for i = 1, n do
    local s = "item" .. i .. ":" .. string.format("%05d", i % 1000)
    if string.find(s, "7", 1, true) then
      count = count + #s
    end
  end
  return count
end

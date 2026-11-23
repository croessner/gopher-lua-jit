-- scanning the bytes of a string and comparing strings
local text = "the quick brown fox jumps over the lazy dog 0123456789"
local words = {"alpha", "beta", "gamma", "delta"}
return function(n)
  local digits, spaces, hits = 0, 0, 0
  local len = #text
  for i = 1, n do
    local b = text:byte(i % len + 1)
    if b >= 48 and b <= 57 then
      digits = digits + 1
    elseif b == 32 then
      spaces = spaces + 1
    end
    if words[i % 4 + 1] == "gamma" then hits = hits + 1 end
  end
  return digits + spaces + hits
end

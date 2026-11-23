-- repeated traversal of a linked list
return function(n)
  local list
  for i = 1, 1000 do list = {value = i, next = list} end
  local s = 0
  for k = 1, n / 1000 do
    local node = list
    while node do
      s = s + node.value
      node = node.next
    end
  end
  return s
end

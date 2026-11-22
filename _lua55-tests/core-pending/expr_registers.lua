-- Expressions: assignments whose value expression reads the variable
-- being assigned. These guard against evaluating a value directly into a
-- target that is still needed.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## multiple assignment: a, b = 3, a
do
local a, b = 1, 2
a, b = 3, a
assert(show(a, b) == "3,1")
end

-- ## multiple assignment: b, a = a, b
do
local a, b = 1, 2
b, a = a, b
assert(show(a, b) == "2,1")
end

-- ## multiple assignment: a, b = c, a
do
local a, b, c = 1, 2, 3
a, b = c, a
assert(show(a, b) == "3,1")
end

-- ## multiple assignment: i, a[i], a[i + 1] = i + 1, a[i + 1], a[i]
do
local a = {10, 20}
local i = 1
i, a[i], a[i + 1] = i + 1, a[i + 1], a[i]
assert(show(i, a[1], a[2]) == "2,20,10")
end

-- ## multiple assignment: a, b = a + b, a * b
do
local a, b = 1, 2
a, b = a + b, a * b
assert(show(a, b) == "3,2")
end

-- ## multiple assignment: a, b = b, a
do
local a, b = 1, 2
a, b = b, a
a, b = b, a
assert(show(a, b) == "1,2")
end

-- ## multiple assignment: x, y = y + 1, x + 10
do
local x = 1
local y = x
x, y = y + 1, x + 10
assert(show(x, y) == "2,11")
end

-- ## multiple assignment: a, b, c = c, b, a
do
local a, b, c = 1, 2, 3
a, b, c = c, b, a
assert(show(a, b, c) == "3,2,1")
end

-- ## multiple assignment: a, b = b .. a, a .. b
do
local a, b = "a", "b"
a, b = b .. a, a .. b
assert(show(a, b) == "ba,ab")
end

-- ## multiple assignment: a, b = b, a + 0
do
local a, b = 1, 2
a, b = b, a + 0
assert(show(a, b) == "2,1")
end

-- ## multiple assignment: a, b = (b), (a)
do
local a, b = 1, 2
a, b = (b), (a)
assert(show(a, b) == "2,1")
end

-- ## multiple assignment: a, b = b + 0, a
do
local a, b = 1, 2
a, b = b + 0, a
assert(show(a, b) == "2,1")
end

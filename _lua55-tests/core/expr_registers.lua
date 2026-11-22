-- Expressions: assignments whose value expression reads the variable
-- being assigned. These guard against evaluating a value directly into a
-- target that is still needed.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## single assignment reading its own target
do
do local a = 1; a = {a, a}; assert(show(a[1], a[2]) == "1,1") end
do local a = "s"; a = a .. a; assert(show(a) == "ss") end
do local function f(x, y) return x + y end local a = 3; a = f(a, a); assert(show(a) == "6") end
do local x, y = 1, nil; x = y or x; assert(show(x) == "1") end
do local x, y = 1, false; x = y and x; assert(show(x) == "false") end
do local x, y = 1, 2; x = y and x; assert(show(x) == "1") end
do local x, y = nil, 2; x = x or y; assert(show(x) == "2") end
do local a = 5; a = -a + a; assert(show(a) == "0") end
do local a = {x = {y = 7}}; a = a.x.y; assert(show(a) == "7") end
do local a = 2; a = a * a + a; assert(show(a) == "6") end
do local a, b = 1, 2; a = b + a * b; assert(show(a) == "4") end
do local a = {1, 2}; a = #a + #a; assert(show(a) == "4") end
do local a = 1; a = (function() return a end)() + a; assert(show(a) == "2") end
do local a, b = 1, 2; a = {b, a, x = a}; assert(show(a[1], a[2], a.x) == "2,1,1") end
do local t = {n = 1}; t = t.n == 1 and t or nil; assert(show(type(t)) == "table") end
do local a, b = 1, 2; a = a < b; assert(show(a) == "true") end
do local a, b = 1, 2; a = not (a == b) and b; assert(show(a) == "2") end
do local a, b, c = 1, 2, 3; a = b or c; b = c and a; c = a and b or c; assert(show(a, b, c) == "2,2,2") end
do local a, b = "x", "y"; a = b .. a .. b; assert(show(a) == "yxy") end
do local s = "abc"; s = s:upper():lower() .. s; assert(show(s) == "abcabc") end
end

-- ## multiple assignment: local c, d = b, a
do
local a, b = 1, 2
local c, d = b, a
assert(show(c, d) == "2,1")
end

-- ## multiple assignment: a, b = b, 3
do
local a, b = 1, 2
a, b = b, 3
assert(show(a, b) == "2,3")
end

-- ## multiple assignment: c, a = a, b
do
local a, b, c = 1, 2, 3
c, a = a, b
assert(show(a, c) == "2,1")
end

-- ## multiple assignment: a, b = b
do
local a, b = 1, 2
a, b = b
assert(show(a, b) == "2,nil")
end

-- ## multiple assignment: a, b = (function() return b, a end)()
do
local a, b = 1, 2
a, b = (function() return b, a end)()
assert(show(a, b) == "2,1")
end

-- ## multiple assignment: a, t[a] = 2, "x"
do
local t = {1, 2}
local a, b = 1, 2
a, t[a] = 2, "x"
assert(show(a, t[1], t[2]) == "2,x,2")
end

-- ## multiple assignment: a.v, b.v = b.v, a.v
do
local a, b = {v = 1}, {v = 2}
a.v, b.v = b.v, a.v
assert(show(a.v, b.v) == "2,1")
end

-- ## multiple assignment: local a, b = 1, 2
do
local a, b = 1, 2
local function f() a, b = b, a end f()
assert(show(a, b) == "2,1")
end

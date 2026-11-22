-- Functions: variadic functions, select and the named vararg table.
local load = loadstring or load

-- packs its arguments into a string, showing nils (select(n, ...) is
-- avoided on purpose; it belongs to the library tests)
local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end
local function pass(...) return ... end

-- ## passing varargs through
do
assert(show(pass()) == "")
assert(show(pass(1)) == "1")
assert(show(pass(1, 2, 3)) == "1,2,3")
assert(show(pass(nil)) == "nil")
assert(show(pass(nil, nil)) == "nil,nil")
assert(show(pass(1, nil, 3, nil)) == "1,nil,3,nil")
assert(select("#", pass()) == 0)
assert(select("#", pass(nil, nil, nil)) == 3)
end

-- ## varargs after fixed parameters
do
local function f(a, b, ...) return show(a, b, "|", ...) end
assert(f() == "nil,nil,|")
assert(f(1) == "1,nil,|")
assert(f(1, 2) == "1,2,|")
assert(f(1, 2, 3) == "1,2,|,3")
assert(f(1, 2, 3, 4, 5) == "1,2,|,3,4,5")
assert(f(nil, nil, nil) == "nil,nil,|,nil")
end

-- ## vararg expression adjustment
do
local function g(...)
  local a, b = ...
  local c = ...
  local t = {...}
  local u = {..., "last"}
  local w = {"first", ...}
  local p = (...)
  return a, b, c, #t, #u, #w, p
end
assert(show(g(1, 2, 3)) == "1,2,1,3,2,4,1")
assert(show(g(7)) == "7,nil,7,1,2,2,7")
local function g0(...)
  local a, b = ...
  local t = {...}
  local w = {"first", ...}
  return a, b, #t, #w, (...)
end
assert(show(g0()) == "nil,nil,0,1,nil")
end

-- ## vararg in the middle of an expression list is truncated
do
local function h(...) return show(..., "x", ...) end
assert(h(1, 2, 3) == "1,x,1,2,3")
assert(h() == "nil,x")
local function h2(...) return show((...)) end
assert(h2(1, 2, 3) == "1")
assert(h2() == "nil")
end

-- ## select with a count
do
assert(select("#") == 0)
assert(select("#", nil) == 1)
assert(select("#", 1, 2, 3) == 3)
assert(select("#", nil, nil) == 2)
assert(select("#", pass()) == 0)
assert(select("#", pass(), pass()) == 1)
assert(select("#", (pass())) == 1)
end

-- ## varargs used in arithmetic and calls
do
local function sum(...)
  local s = 0
  for _, v in ipairs({...}) do s = s + v end
  return s
end
assert(sum() == 0)
assert(sum(1, 2, 3, 4) == 10)
local function first(...) return (...) end
assert(first(5, 6) == 5)
local function count(...) return select("#", ...) end
assert(count(pass(1, 2), pass(3, 4)) == 3)
assert(count(pass(), pass()) == 1)
assert(count((pass(1, 2))) == 1)
local function addfirst(...) return ... + 1 end
assert(addfirst(1, 100) == 2)
end

-- ## many varargs
do
local function nargs(...) return select("#", ...) end
local t = {}
for i = 1, 200 do t[i] = i end
local function unpack200(t, i)
  i = i or 1
  if i <= #t then return t[i], unpack200(t, i + 1) end
end
assert(nargs(unpack200(t)) == 200)
local packed = {unpack200(t)}
assert(#packed == 200)
assert(packed[200] == 200)
local s = 0
for _, v in ipairs(packed) do s = s + v end
assert(s == 20100)
end

-- ## varargs are not visible in nested functions
do
assert(load("local function f(...) return function() return ... end end") == nil)
assert(load("local function f() return ... end") == nil)
assert(load("local function f(a) return ... end") == nil)
assert(load("return ...") ~= nil)
assert(load("local function f(...) return ... end") ~= nil)
assert(load("local function f(...) return function(...) return ... end end") ~= nil)
end

-- ## the main chunk is a vararg function
do
local chunk = load("return select('#', ...), ...")
assert(chunk() == 0)
assert(select("#", chunk()) == 1)
local n, a, b, c = chunk(1, nil, 3)
assert(n == 3 and a == 1 and b == nil and c == 3)
assert(select("#", chunk(1, nil, 3)) == 4)
local chunk2 = load("local a, b = ...; return b, a")
assert(show(chunk2("x", "y")) == "y,x")
end

-- ## vararg parameter syntax
do
assert(load("local function f(..., a) end") == nil)
assert(load("local function f(a, ..., b) end") == nil)
assert(load("local function f(... ...) end") == nil)
assert(load("local function f(a ...) end") == nil)
assert(load("local function f(a, ...) end") ~= nil)
assert(load("local function f(...) end") ~= nil)
assert(load("local x = ... ...") == nil)
end

-- ## named vararg table
do
local function nv(...t) return t.n, t[1], t[2], t[3] end
assert(show(nv()) == "0,nil,nil,nil")
assert(show(nv(1)) == "1,1,nil,nil")
assert(show(nv(1, 2, 3)) == "3,1,2,3")
assert(show(nv(nil, nil)) == "2,nil,nil,nil")
assert(show(nv(1, nil, 3)) == "3,1,nil,3")
local function nv2(a, b, ...rest) return a, b, rest.n, rest[1] end
assert(show(nv2(1, 2, 3, 4)) == "1,2,2,3")
assert(show(nv2(1)) == "1,nil,0,nil")
local function nv3(...t) return type(t), #t, getmetatable(t) end
assert(show(nv3("a", "b")) == "table,2,nil")
local function nv4(...t) return select("#", ...), ... end
local n, a, b = nv4("a", "b")
assert(n == 2 and a == "a" and b == "b")
end

-- ## the named vararg table is a fresh table per call
do
local function nv(...t) return t end
local t1, t2 = nv(1), nv(1)
assert(type(t1) == "table")
assert(t1 ~= t2)
assert(t1.n == 1 and t1[1] == 1)
local t3 = nv()
assert(t3.n == 0)
assert(next(t3) == "n")
end

-- ## named vararg table syntax
do
assert(load("local function f(...t) return t end") ~= nil)
assert(load("local function f(... t) return t end") ~= nil)
assert(load("local function f(a, ...t) return t end") ~= nil)
assert(load("local f = function(...t) return t.n end") ~= nil)
assert(load("local function f(...t, a) end") == nil)
assert(load("local function f(...1) end") == nil)
assert(load("local function f(...t u) end") == nil)
assert(load("local function f(...'x') end") == nil)
assert(load("return ...t") == nil)
assert(load("local function f(...t) return function() return t end end") ~= nil)
assert(load("local function f(...t) return function() return ... end end") == nil)
end

-- ## the named vararg table can be captured and iterated
do
local function capture(...t)
  return function() return t.n end
end
assert(capture(1, 2, 3)() == 3)
local function total(...args)
  local s = 0
  for i = 1, args.n do s = s + args[i] end
  return s
end
assert(total(1, 2, 3, 4) == 10)
assert(total() == 0)
end

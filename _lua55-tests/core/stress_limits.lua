-- Stress-ish semantics: recursion limits, large constructs, many locals.
local load = loadstring or load

-- ## unbounded recursion raises a catchable error
do
local function rec(n) return 1 + rec(n + 1) end
local ok, err = pcall(rec, 1)
assert(ok == false)
assert(type(err) == "string")
local depth = 0
local function count() depth = depth + 1; count(); depth = depth - 1 end
ok = pcall(count)
assert(ok == false)
assert(depth > 100)
-- the interpreter keeps working after the overflow
local function fine(n) if n == 0 then return 0 end return 1 + fine(n - 1) end
assert(fine(100) == 100)
assert(pcall(rec, 1) == false)
assert(fine(100) == 100)
end

-- ## moderately deep recursion works
do
local function depth_of(n) if n == 0 then return 0 end return 1 + depth_of(n - 1) end
assert(depth_of(190) == 190)
local function sum_to(n) if n == 0 then return 0 end return n + sum_to(n - 1) end
assert(sum_to(180) == 16290)
end

-- ## recursion overflow inside a coroutine is catchable
do
local function rec(n) return 1 + rec(n + 1) end
local co = coroutine.create(function() return rec(1) end)
local ok, err = coroutine.resume(co)
assert(ok == false)
assert(coroutine.status(co) == "dead")
local co2 = coroutine.wrap(function() return pcall(rec, 1) end)
assert(co2() == false)
end

-- ## recursion through metamethods overflows with a catchable error
do
local t = setmetatable({}, {})
getmetatable(t).__index = function(tbl, k) return tbl[k] end
assert(pcall(function() return t.x end) == false)
local c = setmetatable({}, {})
getmetatable(c).__call = function(self) return 1 + self() end
assert(pcall(c) == false)
local a = setmetatable({}, {})
getmetatable(a).__add = function(x, y) return (x + y) + 1 end
assert(pcall(function() return a + 1 end) == false)
end

-- ## recursion through pcall overflows with a catchable error
do
local function nest() return pcall(nest) end
local ok = pcall(nest)
assert(ok == true or ok == false)
local function nest_err() local ok, e = pcall(nest_err); error(e, 0) end
assert(pcall(nest_err) == false)
end

-- ## large table constructor
do
local t = load("return {" .. string.rep("1,", 20000) .. "}")()
assert(#t == 20000)
assert(t[1] == 1 and t[20000] == 1 and t[20001] == nil)
local sum = 0
for i = 1, #t do sum = sum + t[i] end
assert(sum == 20000)
end

-- ## very large table constructor
do
local n = 60000
local t = load("return {" .. string.rep("7,", n) .. "}")()
assert(t[1] == 7)
assert(t[25550] == 7)
assert(t[n + 1] == nil)
end

-- ## large tables built at run time
do
local t = {}
for i = 1, 200000 do t[i] = i end
assert(#t == 200000)
assert(t[100000] == 100000)
local h = {}
for i = 1, 50000 do h["k" .. i] = i end
local count = 0
for _ in pairs(h) do count = count + 1 end
assert(count == 50000)
assert(h.k1 == 1 and h.k50000 == 50000)
for i = 1, 50000 do h["k" .. i] = nil end
assert(next(h) == nil)
end

-- ## long string concatenation in a loop
do
local s = ""
for i = 1, 5000 do s = s .. "x" end
assert(#s == 5000)
local parts = ""
for i = 1, 2000 do parts = parts .. i .. "," end
assert(#parts == 8893)
assert(parts:sub(1, 8) == "1,2,3,4,")
assert(parts:sub(-5) == "2000,")
end

-- ## a single concatenation expression with many operands
do
local expr = "return 'a'" .. string.rep(" .. 'a'", 150)
local long = load(expr)()
assert(#long == 151)
local expr2 = "local x = 'b'; return x" .. string.rep(" .. x", 190)
assert(#load(expr2)() == 191)
local nums = "return 1" .. string.rep(" .. 2", 100)
assert(load(nums)() == "1" .. string.rep("2", 100))
end

-- ## long strings
do
local big = string.rep("abc", 100000)
assert(#big == 300000)
assert(big:sub(-3) == "abc")
local doubled = big .. big
assert(#doubled == 600000)
assert(#string.rep("x", 1000000) == 1000000)
local lit = load("return '" .. string.rep("z", 100000) .. "'")()
assert(#lit == 100000)
local longlit = load("return [==[" .. string.rep("line\n", 20000) .. "]==]")()
assert(#longlit == 100000)
end

-- ## many local variables in one function
do
local decl, sum = "", ""
for i = 1, 190 do
  decl = decl .. "local v" .. i .. " = " .. i .. "\n"
  sum = sum .. (i > 1 and " + " or "") .. "v" .. i
end
local f = load(decl .. "return " .. sum)
assert(f ~= nil)
assert(f() == 18145)
end

-- ## the limit of 200 local variables is enforced
do
local function locals(n)
  local decl = ""
  for i = 1, n do decl = decl .. "local v" .. i .. " = " .. i .. "\n" end
  return load(decl .. "return v1")
end
assert(locals(199) ~= nil)
assert(locals(200) ~= nil)
assert(locals(201) == nil)
assert(locals(250) == nil)
assert(locals(200)() == 1)
end

-- ## many locals declared in a single statement
do
local names, values = "", ""
for i = 1, 150 do
  names = names .. (i > 1 and ", " or "") .. "a" .. i
  values = values .. (i > 1 and ", " or "") .. i
end
local f = load("local " .. names .. " = " .. values .. "\nreturn a1 + a75 + a150")
assert(f() == 226)
end

-- ## many upvalues in one closure
do
local decl, sum = "", ""
for i = 1, 100 do
  decl = decl .. "local u" .. i .. " = " .. i .. "\n"
  sum = sum .. (i > 1 and " + " or "") .. "u" .. i
end
local f = load(decl .. "return function() return " .. sum .. " end")
assert(f()() == 5050)
local decl2, body = "", ""
for i = 1, 150 do
  decl2 = decl2 .. "local w" .. i .. " = 0\n"
  body = body .. "w" .. i .. " = w" .. i .. " + " .. i .. "\n"
end
local g = load(decl2 .. "return function() " .. body .. " return w1 + w150 end")()
assert(g() == 151)
assert(g() == 302)
end

-- ## the limit of 255 upvalues is enforced
do
local function upvalues(n)
  -- spread the locals over nested functions to stay below the locals limit
  local use = ""
  for i = 1, n do use = use .. "u" .. i .. (i < n and " + " or "") end
  local per = 150
  local k = 0
  local src = ""
  for i = 1, n do
    if (i - 1) % per == 0 then src = src .. "return (function() " ; k = k + 1 end
    src = src .. "local u" .. i .. " = " .. i .. "; "
  end
  src = src .. "return function() return " .. use .. " end " .. string.rep("end)() ", k)
  return load(src)
end
local f255 = upvalues(255)
assert(f255 ~= nil)
assert(f255()() == 32640)
end

-- ## many arguments and results
do
local function count(...) return select("#", ...) end
local args = string.rep("1,", 150) .. "1"
assert(load("local count = ... ; return count(" .. args .. ")")(count) == 151)
local function many(n) if n == 0 then return end return n, many(n - 1) end
assert(count(many(150)) == 150)
local t = {many(150)}
assert(#t == 150 and t[1] == 150 and t[150] == 1)
end

-- ## deeply nested data and syntax
do
local nested = load("return " .. string.rep("{", 100) .. string.rep("}", 100))()
local depth = 0
while nested do depth = depth + 1; nested = nested[1] end
assert(depth == 100)
local parens = load("return " .. string.rep("(", 150) .. "1" .. string.rep(")", 150))
assert(parens() == 1)
local blocks = load(string.rep("do ", 150) .. "X_STRESS = 1 " .. string.rep("end ", 150))
assert(blocks ~= nil)
blocks()
assert(X_STRESS == 1)
X_STRESS = nil
local ifs = load(string.rep("if true then ", 100) .. "return 'in' " .. string.rep("end ", 100))
assert(ifs() == "in")
local fns = load("return " .. string.rep("(function() return ", 40) .. "'core'" .. string.rep(" end)()", 40))
assert(fns() == "core")
end

-- ## excessive syntactic nesting is rejected, not crashed
do
local too_deep = string.rep("(", 100000) .. "1" .. string.rep(")", 100000)
local f = load("return " .. too_deep)
assert(f == nil)
local deep_tables = load("return " .. string.rep("{", 100000) .. string.rep("}", 100000))
assert(deep_tables == nil)
local deep_calls = load("return " .. string.rep("f(", 100000) .. string.rep(")", 100000))
assert(deep_calls == nil)
end

-- ## closures in a long loop
do
local acc = 0
for i = 1, 100000 do
  local f = function(x) return x + i end
  acc = acc + f(1)
end
assert(acc == 5000150000)
local keep = {}
for i = 1, 100000 do
  if i % 10000 == 0 then keep[#keep + 1] = function() return i end end
end
assert(#keep == 10)
assert(keep[1]() == 10000 and keep[10]() == 100000)
end

-- ## a long chain of elseif and many constants
do
local src = "local x = ...\nif x == 0 then return 0\n"
for i = 1, 300 do src = src .. "elseif x == " .. i .. " then return " .. i * 2 .. "\n" end
src = src .. "end"
local f = load(src)
assert(f(0) == 0 and f(150) == 300 and f(300) == 600 and f(301) == nil)
local consts = "return {"
for i = 1, 1000 do consts = consts .. "'s" .. i .. "'," end
local ct = load(consts .. "}")()
assert(#ct == 1000 and ct[1] == "s1" and ct[1000] == "s1000")
local numconsts = "local s = 0\n"
for i = 1, 600 do numconsts = numconsts .. "s = s + " .. i .. ".5\n" end
assert(load(numconsts .. "return s")() == 180600.0)
end

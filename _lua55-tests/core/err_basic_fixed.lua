-- Error handling: error, pcall, xpcall and error values.
local load = loadstring or load

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## level 2 reports the position of the caller
do
local function line_of(e) return tonumber(e:match(":(%d+):")) end
local function level1() error("lvl1") end -- base line
local function level2() error("lvl2", 2) end
local function calls_level2()
  level2() -- base line + 3
end
local ok, e1 = pcall(level1)
local ok, e2 = pcall(calls_level2)
assert(line_of(e2) == line_of(e1) + 3)
local function level3() error("lvl3", 3) end
local function calls_level3()
  level3()
end
local function calls_calls_level3()
  calls_level3() -- base line + 13
end
local ok, e3 = pcall(calls_calls_level3)
assert(line_of(e3) == line_of(e1) + 13)
end

-- ## xpcall passes extra arguments to the function
do
assert(show(xpcall(function(...) return ... end, print, 1, 2, 3)) == "true,1,2,3")
assert(show(xpcall(function(a, b) return a + b end, print, 10, 20)) == "true,30")
assert(show(xpcall(function(...) return select("#", ...) end, print)) == "true,0")
end

-- ## assert
do
local a, b, c = assert(1, 2, 3)
local ok, e = pcall(assert, false)
ok, e = pcall(assert, nil)
local tbl = {}
ok, e = pcall(assert, false, tbl)
assert(e == tbl)
ok, e = pcall(assert, false, 42)
assert(e == 42)
ok, e = pcall(assert)
end

-- ## a nil error value is replaced by a string
do
local ok, e = pcall(error, nil)
assert(ok == false and e == "<no error object>")
ok, e = pcall(function() error(nil) end)
assert(ok == false and e == "<no error object>")
ok, e = pcall(function() error(nil, 2) end)
assert(e == "<no error object>")
ok, e = pcall(assert, false, nil)
assert(e == "<no error object>")
ok, e = coroutine.resume(coroutine.create(function() error(nil) end))
assert(ok == false and e == "<no error object>")
ok, e = xpcall(function() error("x", 0) end, function() return nil end)
assert(ok == false and e == "<no error object>")
ok, e = pcall(error, false)
end

-- ## error without arguments raises a nil error value
do
local ok, e = pcall(error)
assert(ok == false and e == "<no error object>")
ok, e = coroutine.resume(coroutine.create(function() error() end))
assert(ok == false and e == "<no error object>")
end

-- ## error called directly by pcall adds no position
do
local ok, e = pcall(error, "direct")
assert(e == "direct")
ok, e = pcall(error, "direct", 1)
assert(e == "direct")
local ok, a, b = pcall(pcall, error, "inner")
assert(ok == true and a == false and b == "inner")
end

-- ## the default assert message
do
local ok, e = pcall(assert, false)
assert(not ok and e == "assertion failed!")
ok, e = pcall(assert, nil)
assert(e == "assertion failed!")
ok, e = pcall(function() assert(false) end)
end

-- ## assert adds a position to string messages like error does
do
local ok, e = pcall(function() assert(1 == 2, "custom message") end)
ok, e = pcall(function() assert(false, 42) end)
assert(e == 42)
end

-- ## assert called directly by pcall adds no position
do
local ok, e = pcall(assert, false, "custom")
assert(e == "custom")
ok, e = pcall(assert, nil, "custom", "extra")
assert(e == "custom")
end

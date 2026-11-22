-- Error handling: texts of runtime error messages (without the position
-- prefix). Every text is the one produced by the reference interpreter.
-- For each category there are two sections: the base message, and the
-- message including the variable information ("local 'x'", "field 'y'").
local load = loadstring or load

-- returns the error message of fn without the "chunk:line: " prefix
local function msg(fn)
  local ok, e = pcall(fn)
  assert(not ok, "expected an error")
  return (tostring(e):gsub("^[^:]+:%d+: ", ""))
end
-- like msg, but also strips a trailing variable description
local function base(fn)
  return (msg(fn):gsub(" %(%a[%a ]* '[^']*'%)$", ""))
end

-- ## indexing: base message
do
assert(base(function() local x; return x.field end) == "attempt to index a nil value")
assert(base(function() return undefined_global.field end) == "attempt to index a nil value")
assert(base(function() local t = {}; return t.a.b end) == "attempt to index a nil value")
assert(base((function() local up; return function() return up.x end end)()) == "attempt to index a nil value")
assert(base(function() local n = 1; return n.x end) == "attempt to index a number value")
assert(base(function() local b = true; return b.x end) == "attempt to index a boolean value")
assert(base(function() local f = print; return f.x end) == "attempt to index a function value")
assert(base(function() local x; return x[1] end) == "attempt to index a nil value")
assert(base(function() local x, k; return x[k] end) == "attempt to index a nil value")
assert(base(function() local x; x.field = 1 end) == "attempt to index a nil value")
assert(base(function() local t = {}; t.a.b = 1 end) == "attempt to index a nil value")
assert(base(function() local n = 1; n.x = 1 end) == "attempt to index a number value")
assert(base(function() local x; return x["key"] end) == "attempt to index a nil value")
assert(base(function() local t = {a = {}}; return t.a.b.c end) == "attempt to index a nil value")
assert(base(function() local s = "x"; s.missing() end) == "attempt to call a nil value")
assert(base(function() local o; o:method() end) == "attempt to index a nil value")
assert(base(function() local n = 3; n:method() end) == "attempt to index a number value")
end

-- ## calls: base message
do
assert(base(function() local f; f() end) == "attempt to call a nil value")
assert(base(function() undefined_function() end) == "attempt to call a nil value")
assert(base(function() local t = {}; t.missing() end) == "attempt to call a nil value")
assert(base(function() local t = {}; t:missing() end) == "attempt to call a nil value")
assert(base((function() local up; return function() up() end end)()) == "attempt to call a nil value")
assert(base(function() local n = 5; n() end) == "attempt to call a number value")
assert(base(function() local t = {}; t() end) == "attempt to call a table value")
assert(base(function() local s = "x"; s() end) == "attempt to call a string value")
assert(base(function() local b = true; b() end) == "attempt to call a boolean value")
assert(base(function() for i in nil do end end) == "attempt to call a nil value")
assert(base(function() for i in 5 do end end) == "attempt to call a number value")
assert(msg(function() local function f() end; f()() end) == "attempt to call a nil value")
assert(base((function() local t = {}; return function() t.fn() end end)()) == "attempt to call a nil value")
end

-- ## arithmetic: base message
do
assert(base(function() local x; return x + 1 end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local x; return 1 + x end) == "attempt to perform arithmetic on a nil value")
assert(base(function() return undefined_global + 1 end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local t = {}; return t.x + 1 end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local t = {}; return t * 2 end) == "attempt to perform arithmetic on a table value")
assert(base(function() local b = true; return b - 1 end) == "attempt to perform arithmetic on a boolean value")
assert(base(function() local f = print; return f / 1 end) == "attempt to perform arithmetic on a function value")
assert(msg(function() return nil + 1 end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local x; return -x end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local t = {}; return -t end) == "attempt to perform arithmetic on a table value")
assert(base(function() local x; return x % 2 end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local x; return x ^ 2 end) == "attempt to perform arithmetic on a nil value")
assert(base(function() local t = {}; return t // 2 end) == "attempt to perform arithmetic on a table value")
assert(base((function() local t = {}; return function() return t.n + 1 end end)()) == "attempt to perform arithmetic on a nil value")
end

-- ## concatenation: base message
do
assert(base(function() local x; return "a" .. x end) == "attempt to concatenate a nil value")
assert(base(function() local x; return x .. "a" end) == "attempt to concatenate a nil value")
assert(base(function() local t = {}; return "a" .. t end) == "attempt to concatenate a table value")
assert(base(function() local b = false; return b .. "a" end) == "attempt to concatenate a boolean value")
assert(base(function() return "a" .. undefined_global end) == "attempt to concatenate a nil value")
assert(base(function() local t = {}; return "a" .. t.x end) == "attempt to concatenate a nil value")
assert(base(function() local x; return 1 .. x end) == "attempt to concatenate a nil value")
end

-- ## length: base message
do
assert(base(function() local x; return #x end) == "attempt to get length of a nil value")
assert(base(function() local n = 5; return #n end) == "attempt to get length of a number value")
assert(base(function() local b = true; return #b end) == "attempt to get length of a boolean value")
assert(base(function() return #undefined_global end) == "attempt to get length of a nil value")
end

-- ## comparison: base message
do
assert(msg(function() local a, b = 1, "x"; return a < b end) == "attempt to compare number with string")
assert(msg(function() local a, b = "x", 1; return a < b end) == "attempt to compare string with number")
assert(msg(function() local a, b = nil, 1; return a < b end) == "attempt to compare nil with number")
assert(msg(function() local a, b = {}, {}; return a < b end) == "attempt to compare two table values")
assert(msg(function() local a, b; return a <= b end) == "attempt to compare two nil values")
assert(msg(function() local a, b = {}, 1; return a >= b end) == "attempt to compare number with table")
assert(msg(function() local a, b = true, false; return a > b end) == "attempt to compare two boolean values")
assert(msg(function() local a, b = print, nil; return a < b end) == "attempt to compare function with nil")
assert(msg(function() return 1 < "x" end) == "attempt to compare number with string")
assert(msg(function() local a, b = 1.5, "x"; return a <= b end) == "attempt to compare number with string")
assert(msg(function() local t = setmetatable({}, {}); return t < 1 end) == "attempt to compare table with number")
assert(msg(function() local mt = {__lt = function() return true end}; local a, b = setmetatable({}, mt), setmetatable({}, mt); return a <= b end) == "attempt to compare two table values")
end

-- ## comparison: variable information
do
end

-- ## bitwise operations: base message
do
assert(msg(function() return 1.5 | 1 end) == "number has no integer representation")
assert(base(function() local x; return x & 1 end) == "attempt to perform bitwise operation on a nil value")
assert(base(function() local t = {}; return t | 1 end) == "attempt to perform bitwise operation on a table value")
assert(base(function() local s = "3"; return s & 1 end) == "attempt to perform bitwise operation on a string value")
assert(base(function() return "abc" ~ 1 end) == "attempt to perform bitwise operation on a string value")
assert(base(function() local x; return ~x end) == "attempt to perform bitwise operation on a nil value")
assert(base(function() local x; return 1 >> x end) == "attempt to perform bitwise operation on a nil value")
end

-- ## numeric for: base message
do
assert(msg(function() for i = 1, 2, 0 do end end) == "'for' step is zero")
assert(msg(function() for i = 1.0, 2, 0 do end end) == "'for' step is zero")
end

-- ## table keys: base message
do
assert(msg(function() local t = {}; t[nil] = 1 end) == "table index is nil")
assert(msg(function() local t = {}; t[0/0] = 1 end) == "table index is NaN")
assert(msg(function() local t, k = {}; t[k] = 1 end) == "table index is nil")
end

-- ## metamethods: base message
do
assert(base(function() local t = setmetatable({}, {}); return t .. "x" end) == "attempt to concatenate a table value")
end

-- ## miscellaneous: base message
do
assert(msg(function() return (loadstring or load)("global tostring = 1")() end) == "global 'tostring' already defined")
assert(msg(function() setmetatable({}, 5) end) == "bad argument #2 to 'setmetatable' (nil or table expected, got number)")
assert(msg(function() setmetatable(setmetatable({}, {__metatable = 1}), {}) end) == "cannot change a protected metatable")
assert(msg(function() tostring(setmetatable({}, {__tostring = function() return {} end})) end) == "'__tostring' must return a string")
end

-- ## error and stack overflow
do
assert(msg(function() error("custom") end) == "custom")
assert(msg(function() error("custom", 0) end) == "custom")
assert(msg(function() local function r() return 1 + r() end return r() end):find("stack overflow"))
end

-- ## an error in the xpcall message handler
do
local ok, e = xpcall(function() error("first", 0) end, function() error("second", 0) end)
assert(ok == false)
end

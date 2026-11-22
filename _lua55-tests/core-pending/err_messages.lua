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

-- ## indexing: variable information
do
assert(msg(function() local x; return x.field end) == "attempt to index a nil value (local 'x')")
assert(msg(function() return undefined_global.field end) == "attempt to index a nil value (global 'undefined_global')")
assert(msg(function() local t = {}; return t.a.b end) == "attempt to index a nil value (field 'a')")
assert(msg((function() local up; return function() return up.x end end)()) == "attempt to index a nil value (upvalue 'up')")
assert(msg(function() local n = 1; return n.x end) == "attempt to index a number value (local 'n')")
assert(msg(function() local b = true; return b.x end) == "attempt to index a boolean value (local 'b')")
assert(msg(function() local f = print; return f.x end) == "attempt to index a function value (local 'f')")
assert(msg(function() local x; return x[1] end) == "attempt to index a nil value (local 'x')")
assert(msg(function() local x, k; return x[k] end) == "attempt to index a nil value (local 'x')")
assert(msg(function() local x; x.field = 1 end) == "attempt to index a nil value (local 'x')")
assert(msg(function() local t = {}; t.a.b = 1 end) == "attempt to index a nil value (field 'a')")
assert(msg(function() local n = 1; n.x = 1 end) == "attempt to index a number value (local 'n')")
assert(msg(function() local x; return x["key"] end) == "attempt to index a nil value (local 'x')")
assert(msg(function() local t = {a = {}}; return t.a.b.c end) == "attempt to index a nil value (field 'b')")
assert(msg(function() local s = "x"; s.missing() end) == "attempt to call a nil value (field 'missing')")
assert(msg(function() local o; o:method() end) == "attempt to index a nil value (local 'o')")
assert(msg(function() local n = 3; n:method() end) == "attempt to index a number value (local 'n')")
end

-- ## calls: variable information
do
assert(msg(function() local f; f() end) == "attempt to call a nil value (local 'f')")
assert(msg(function() undefined_function() end) == "attempt to call a nil value (global 'undefined_function')")
assert(msg(function() local t = {}; t.missing() end) == "attempt to call a nil value (field 'missing')")
assert(msg(function() local t = {}; t:missing() end) == "attempt to call a nil value (method 'missing')")
assert(msg((function() local up; return function() up() end end)()) == "attempt to call a nil value (upvalue 'up')")
assert(msg(function() local n = 5; n() end) == "attempt to call a number value (local 'n')")
assert(msg(function() local t = {}; t() end) == "attempt to call a table value (local 't')")
assert(msg(function() local s = "x"; s() end) == "attempt to call a string value (local 's')")
assert(msg(function() local b = true; b() end) == "attempt to call a boolean value (local 'b')")
assert(msg(function() for i in nil do end end) == "attempt to call a nil value (for iterator 'for iterator')")
assert(msg(function() for i in 5 do end end) == "attempt to call a number value (for iterator 'for iterator')")
assert(msg((function() local t = {}; return function() t.fn() end end)()) == "attempt to call a nil value (field 'fn')")
end

-- ## arithmetic: base message
do
assert(msg(function() local s = "abc"; return s + 1 end) == "attempt to add a 'string' with a 'number'")
assert(msg(function() return "abc" + 1 end) == "attempt to add a 'string' with a 'number'")
assert(msg(function() local s = "abc"; return -s end) == "attempt to unm a 'string' with a 'string'")
end

-- ## arithmetic: variable information
do
assert(msg(function() local x; return x + 1 end) == "attempt to perform arithmetic on a nil value (local 'x')")
assert(msg(function() local x; return 1 + x end) == "attempt to perform arithmetic on a nil value (local 'x')")
assert(msg(function() return undefined_global + 1 end) == "attempt to perform arithmetic on a nil value (global 'undefined_global')")
assert(msg(function() local t = {}; return t.x + 1 end) == "attempt to perform arithmetic on a nil value (field 'x')")
assert(msg(function() local t = {}; return t * 2 end) == "attempt to perform arithmetic on a table value (local 't')")
assert(msg(function() local b = true; return b - 1 end) == "attempt to perform arithmetic on a boolean value (local 'b')")
assert(msg(function() local f = print; return f / 1 end) == "attempt to perform arithmetic on a function value (local 'f')")
assert(msg(function() local x; return -x end) == "attempt to perform arithmetic on a nil value (local 'x')")
assert(msg(function() local t = {}; return -t end) == "attempt to perform arithmetic on a table value (local 't')")
assert(msg(function() local x; return x % 2 end) == "attempt to perform arithmetic on a nil value (local 'x')")
assert(msg(function() local x; return x ^ 2 end) == "attempt to perform arithmetic on a nil value (local 'x')")
assert(msg(function() local t = {}; return t // 2 end) == "attempt to perform arithmetic on a table value (local 't')")
assert(msg((function() local t = {}; return function() return t.n + 1 end end)()) == "attempt to perform arithmetic on a nil value (field 'n')")
end

-- ## concatenation: variable information
do
assert(msg(function() local x; return "a" .. x end) == "attempt to concatenate a nil value (local 'x')")
assert(msg(function() local x; return x .. "a" end) == "attempt to concatenate a nil value (local 'x')")
assert(msg(function() local t = {}; return "a" .. t end) == "attempt to concatenate a table value (local 't')")
assert(msg(function() local b = false; return b .. "a" end) == "attempt to concatenate a boolean value (local 'b')")
assert(msg(function() return "a" .. undefined_global end) == "attempt to concatenate a nil value (global 'undefined_global')")
assert(msg(function() local t = {}; return "a" .. t.x end) == "attempt to concatenate a nil value (field 'x')")
assert(msg(function() local x; return 1 .. x end) == "attempt to concatenate a nil value (local 'x')")
end

-- ## length: variable information
do
assert(msg(function() local x; return #x end) == "attempt to get length of a nil value (local 'x')")
assert(msg(function() local n = 5; return #n end) == "attempt to get length of a number value (local 'n')")
assert(msg(function() local b = true; return #b end) == "attempt to get length of a boolean value (local 'b')")
assert(msg(function() return #undefined_global end) == "attempt to get length of a nil value (global 'undefined_global')")
end

-- ## bitwise operations: variable information
do
assert(msg(function() local f = 1.5; return f & 1 end) == "number (local 'f') has no integer representation")
assert(msg(function() local f = 2^63; return f | 0 end) == "number (local 'f') has no integer representation")
assert(msg(function() local x; return x & 1 end) == "attempt to perform bitwise operation on a nil value (local 'x')")
assert(msg(function() local t = {}; return t | 1 end) == "attempt to perform bitwise operation on a table value (local 't')")
assert(msg(function() local s = "3"; return s & 1 end) == "attempt to perform bitwise operation on a string value (local 's')")
assert(msg(function() return "abc" ~ 1 end) == "attempt to perform bitwise operation on a string value (constant 'abc')")
assert(msg(function() local x; return ~x end) == "attempt to perform bitwise operation on a nil value (local 'x')")
assert(msg(function() local f = 2.5; return ~f end) == "number (local 'f') has no integer representation")
assert(msg(function() local f = 0.5; return 1 << f end) == "number (local 'f') has no integer representation")
assert(msg(function() local x; return 1 >> x end) == "attempt to perform bitwise operation on a nil value (local 'x')")
assert(msg(function() local f = 1/0; return f ~ 1 end) == "number (local 'f') has no integer representation")
assert(msg(function() local f = 0/0; return f & 1 end) == "number (local 'f') has no integer representation")
end

-- ## division by zero: base message
do
assert(msg(function() local a, b = 1, 0; return a // b end) == "attempt to divide by zero")
assert(msg(function() return 1 // 0 end) == "attempt to divide by zero")
assert(msg(function() local a, b = 1, 0; return a % b end) == "attempt to perform 'n%0'")
assert(msg(function() return 1 % 0 end) == "attempt to perform 'n%0'")
end

-- ## numeric for: base message
do
assert(msg(function() for i = nil, 1 do end end) == "bad 'for' initial value (number expected, got nil)")
assert(msg(function() for i = 1, nil do end end) == "bad 'for' limit (number expected, got nil)")
assert(msg(function() for i = 1, 2, nil do end end) == "bad 'for' step (number expected, got nil)")
assert(msg(function() for i = "a", 1 do end end) == "bad 'for' initial value (number expected, got string)")
assert(msg(function() for i = 1, {} do end end) == "bad 'for' limit (number expected, got table)")
end

-- ## to-be-closed variables: base message
do
assert(msg(function() local x <close> = {} end) == "variable 'x' got a non-closable value")
assert(msg(function() local x <close> = 42 end) == "variable 'x' got a non-closable value")
assert(msg(function() for i in function() end, nil, nil, {} do end end) == "variable '(for state)' got a non-closable value")
end

-- ## coroutines: base message
do
assert(msg(function() local co = coroutine.create(function() end); coroutine.resume(co); local _, m = coroutine.resume(co); error(m, 0) end) == "cannot resume dead coroutine")
assert(msg(function() local co; co = coroutine.create(function() local _, m = coroutine.resume(co); error(m, 0) end); local _, m = coroutine.resume(co); error(m, 0) end) == "cannot resume non-suspended coroutine")
assert(msg(function() local f = coroutine.wrap(function() end); f(); f() end) == "cannot resume dead coroutine")
assert(msg(function() coroutine.yield() end) == "attempt to yield from outside a coroutine")
end

-- ## metamethods: base message
do
assert(base(function() local t = setmetatable({}, {__len = 5}); return #t end) == "attempt to call a number value")
assert(msg(function() local t = {}; setmetatable(t, {__index = t}); return t.x end) == "'__index' chain too long; possible loop")
assert(base(function() local t = setmetatable({}, {__add = 5}); return t + 1 end) == "attempt to call a number value")
assert(base(function() local t = setmetatable({}, {__call = 5}); t() end) == "attempt to call a number value")
end

-- ## metamethods: variable information
do
assert(msg(function() local t = setmetatable({}, {__len = 5}); return #t end) == "attempt to call a number value (metamethod 'len')")
assert(msg(function() local t = setmetatable({}, {__add = 5}); return t + 1 end) == "attempt to call a number value (metamethod 'add')")
assert(msg(function() local t = setmetatable({}, {__call = 5}); t() end) == "attempt to call a number value (local 't')")
assert(msg(function() local t = setmetatable({}, {}); return t .. "x" end) == "attempt to concatenate a table value (local 't')")
end

-- ## miscellaneous: base message
do
assert(msg(function() local function f(...t) t.n = "x"; return ... end; return f(1) end) == "vararg table has no proper 'n'")
end

-- ## an error in the xpcall message handler
do
local ok, e = xpcall(function() error("first", 0) end, function() error("second", 0) end)
assert(e == "error in error handling")
end

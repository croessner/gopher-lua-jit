-- Control flow: the generic for loop.
-- Most loops here pass four explicit control values; the adjustment of a
-- shorter expression list is covered by the dedicated sections below.
local load = loadstring or load

-- ## stateless iterators
do
local function iter(limit, i)
  if i < limit then return i + 1 end
end
local out = {}
for i in iter, 3, 0, nil do out[#out + 1] = i end
assert(table.concat(out, ",") == "1,2,3")
out = {}
for i in iter, 0, 0, nil do out[#out + 1] = i end
assert(#out == 0)
end

-- ## ipairs and pairs
do
local t = {10, 20, 30, nil, 50}
local n, sum = 0, 0
for i, v in ipairs(t) do n = n + 1; sum = sum + v; assert(t[i] == v) end
assert(n == 3)
assert(sum == 60)
local keys = {}
for k, v in pairs({a = 1, b = 2, c = 3}) do keys[#keys + 1] = k .. v end
table.sort(keys)
assert(table.concat(keys, ",") == "a1,b2,c3")
n = 0
for _ in pairs({}) do n = n + 1 end
assert(n == 0)
n = 0
for _ in ipairs({}) do n = n + 1 end
assert(n == 0)
n = 0
for k, v in next, {1, 2, x = 3}, nil, nil do n = n + 1 end
assert(n == 3)
end

-- ## closures as stateful iterators
do
local function range(a, b)
  local i = a - 1
  return function()
    i = i + 1
    if i <= b then return i end
  end
end
local out = {}
for i in range(3, 6) do out[#out + 1] = i end
assert(table.concat(out, ",") == "3,4,5,6")
end

-- ## several loop variables and missing values
do
local function multi(_, i)
  if i < 2 then return i + 1, "a" .. i, "b" .. i end
end
local out = {}
for i, a, b, c in multi, nil, 0, nil do
  out[#out + 1] = i .. a .. b .. tostring(c)
end
assert(table.concat(out, ",") == "1a0b0nil,2a1b1nil")
out = {}
for i in multi, nil, 0, nil do out[#out + 1] = i end
assert(table.concat(out, ",") == "1,2")
end

-- ## the loop ends when the first value is nil, even if others follow
do
local calls = 0
local function it()
  calls = calls + 1
  if calls == 1 then return 1, 2 end
  return nil, "ignored"
end
local n = 0
for a, b in it, nil, nil, nil do n = n + 1 end
assert(n == 1)
assert(calls == 2)
end

-- ## false as first value does not end the loop
do
local vals = {false, false, nil}
local i = 0
local n = 0
for v in function() i = i + 1; return vals[i] end, nil, nil, nil do
  assert(v == false)
  n = n + 1
end
assert(n == 2)
end

-- ## the iterator receives the state and the previous control value
do
local seen = {}
local state = {}
local function it(s, c)
  seen[#seen + 1] = {s, c}
  if c == nil then return 1 end
  if c < 3 then return c + 1 end
end
for _ in it, state, nil, nil do end
assert(#seen == 4)
assert(seen[1][1] == state and seen[1][2] == nil)
assert(seen[2][2] == 1)
assert(seen[3][2] == 2)
assert(seen[4][2] == 3)
end

-- ## the explist is evaluated once and adjusted to four values
do
local evals = 0
local function gen()
  evals = evals + 1
  return function(s, c) if c < s then return c + 1 end end, 3, 0
end
local n = 0
for i in gen() do n = n + 1 end
assert(evals == 1)
assert(n == 3)
local function gen5()
  return function(s, c) if c < s then return c + 1 end end, 2, 0, nil, "extra"
end
n = 0
for i in gen5() do n = n + 1 end
assert(n == 2)
end

-- ## fresh loop variables per iteration
do
local fns = {}
for i, v in ipairs({"a", "b", "c"}) do
  fns[i] = function() return string.format("%d", i) .. v end
end
assert(fns[1]() == "1a")
assert(fns[2]() == "2b")
assert(fns[3]() == "3c")
end

-- ## break and return leave the loop
do
local last
for i, v in ipairs({1, 2, 3, 4}) do
  last = v
  if v == 2 then break end
end
assert(last == 2)
local function find(t, x)
  for i, v in ipairs(t) do
    if v == x then return i end
  end
  return nil
end
assert(find({"a", "b", "c"}, "b") == 2)
assert(find({"a", "b", "c"}, "z") == nil)
end

-- ## the control variable cannot be assigned, the others can
do
assert(load("for k, v in pairs({}) do k = 1 end") == nil)
assert(load("for k in pairs({}) do k = 1 end") == nil)
assert(load("for k, v in pairs({}) do local function f() k = 1 end end") == nil)
assert(load("for k, v in pairs({}) do v = 1 end") ~= nil)
assert(load("for k, v, w in pairs({}) do v, w = 1, 2 end") ~= nil)
assert(load("for k, v in pairs({}) do local k = 1; k = 2 end") ~= nil)
local out = {}
for i, v in ipairs({1, 2, 3}) do
  v = v * 2
  out[#out + 1] = v
end
assert(table.concat(out, ",") == "2,4,6")
end

-- ## the fourth value is closed when the loop ends normally
do
local log = {}
local function closer(name)
  return setmetatable({}, {__close = function(_, err) log[#log + 1] = name .. ":" .. tostring(err) end})
end
local function it(s, c) if c < 3 then return c + 1 end end
local c1 = closer("c1")
for i in it, nil, 0, c1 do log[#log + 1] = i end
assert(table.concat(log, ",") == "1,2,3,c1:nil")
end

-- ## the fourth value is closed on break
do
local log = {}
local cv = setmetatable({}, {__close = function() log[#log + 1] = "closed" end})
local function it(s, c) if c < 3 then return c + 1 end end
for i in it, nil, 0, cv do
  log[#log + 1] = i
  break
end
log[#log + 1] = "after"
assert(table.concat(log, ",") == "1,closed,after")
end

-- ## the fourth value is closed on return
do
local log = {}
local cv = setmetatable({}, {__close = function() log[#log + 1] = "closed" end})
local function it(s, c) if c < 3 then return c + 1 end end
local function f()
  for i in it, nil, 0, cv do
    log[#log + 1] = i
    if i == 2 then return "ret" end
  end
end
assert(f() == "ret")
assert(table.concat(log, ",") == "1,2,closed")
end

-- ## the fourth value is closed on goto out of the loop
do
local log = {}
local cv = setmetatable({}, {__close = function() log[#log + 1] = "closed" end})
local function it(s, c) if c < 3 then return c + 1 end end
for i in it, nil, 0, cv do
  log[#log + 1] = i
  goto out
end
::out::
log[#log + 1] = "after"
assert(table.concat(log, ",") == "1,closed,after")
end

-- ## the fourth value is closed on error, receiving the error
do
local log = {}
local cv = setmetatable({}, {__close = function(_, err) log[#log + 1] = "closed:" .. tostring(err) end})
local function it(s, c) if c < 3 then return c + 1 end end
local ok, err = pcall(function()
  for i in it, nil, 0, cv do
    error("boom", 0)
  end
end)
assert(not ok)
assert(err == "boom")
assert(table.concat(log, ",") == "closed:boom")
end

-- ## nil and false closing values are ignored, others must be closable
do
local function it(s, c) if c < 2 then return c + 1 end end
local n = 0
for i in it, nil, 0, nil do n = n + 1 end
for i in it, nil, 0, false do n = n + 1 end
assert(n == 4)
assert(not pcall(function() for i in it, nil, 0, {} do end end))
assert(not pcall(function() for i in it, nil, 0, 1 do end end))
assert(not pcall(function() for i in it, nil, 0, "x" do end end))
assert(not pcall(function() for i in it, nil, 0, setmetatable({}, {}) do end end))
end

-- ## calling a non-function iterator raises an error
do
assert(not pcall(function() for i in nil do end end))
assert(not pcall(function() for i in 1 do end end))
assert(not pcall(function() for i in {} do end end))
assert(not pcall(function() for i in "x" do end end))
end

-- ## a table with __call works as an iterator
do
local calls = 0
local callable = setmetatable({}, {__call = function(self, s, c)
  calls = calls + 1
  if c < 3 then return c + 1 end
end})
local n = 0
for i in callable, nil, 0, nil do n = n + 1 end
assert(n == 3)
assert(calls == 4)
end

-- ## modification of existing fields during traversal is allowed
do
local t = {a = 1, b = 2, c = 3}
for k, v in pairs(t) do t[k] = v * 2 end
assert(t.a == 2 and t.b == 4 and t.c == 6)
for k in pairs(t) do t[k] = nil end
assert(next(t) == nil)
end

-- ## malformed generic for loops are rejected
do
assert(load("for in pairs({}) do end") == nil)
assert(load("for k, in pairs({}) do end") == nil)
assert(load("for k in do end") == nil)
assert(load("for k in pairs({}) end") == nil)
assert(load("for k, v pairs({}) do end") == nil)
assert(load("for k v in pairs({}) do end") == nil)
assert(load("for k.x in pairs({}) do end") == nil)
assert(load("for k in pairs({}), do end") == nil)
assert(load("for a, b, c, d, e in f do end") ~= nil)
end

-- ## nested generic loops over the same table
do
local t = {1, 2, 3}
local pairs_count = 0
for _, a in ipairs(t) do
  for _, b in ipairs(t) do
    if a < b then pairs_count = pairs_count + 1 end
  end
end
assert(pairs_count == 3)
end

-- ## more loop variables than control values
do
local function it(s, c)
  if c == nil then return 1, 2, 3, 4, 5 end
end
local n = 0
for a, b, c, d, e in it do
  n = n + 1
  assert(a == 1 and b == 2 and c == 3 and d == 4 and e == 5)
end
assert(n == 1)
end

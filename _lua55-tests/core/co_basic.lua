-- Coroutines: creation, resume/yield value passing, status and wrap.

local function show(...)
  local vals, out = {...}, {}
  for i = 1, select("#", ...) do out[i] = tostring(vals[i]) end
  return table.concat(out, ",")
end

-- ## create and resume
do
local co = coroutine.create(function() return "done" end)
assert(type(co) == "thread")
assert(coroutine.status(co) == "suspended")
assert(show(coroutine.resume(co)) == "true,done")
assert(coroutine.status(co) == "dead")
end

-- ## arguments of the first resume become the function parameters
do
local co = coroutine.create(function(a, b, ...) return a, b, select("#", ...) end)
local ok, a, b, n = coroutine.resume(co, 1, 2, 3, 4, 5)
assert(ok == true and a == 1 and b == 2 and n == 3)
co = coroutine.create(function(...) return ... end)
assert(show(coroutine.resume(co)) == "true")
co = coroutine.create(function(...) return ... end)
assert(show(coroutine.resume(co, nil, nil)) == "true,nil,nil")
end

-- ## yield passes values out, resume passes values in
do
local co = coroutine.create(function(a)
  local b = coroutine.yield(a + 1)
  local c, d = coroutine.yield(b * 2)
  return c + d
end)
assert(show(coroutine.resume(co, 1)) == "true,2")
assert(show(coroutine.resume(co, 10)) == "true,20")
assert(show(coroutine.resume(co, 3, 4)) == "true,7")
assert(coroutine.resume(co) == false)
end

-- ## yield and resume with zero or many values
do
local co = coroutine.create(function()
  local n1 = select("#", coroutine.yield())
  local n2 = select("#", coroutine.yield(1, 2, 3))
  local n3 = select("#", coroutine.yield(nil, nil))
  return n1, n2, n3
end)
assert(show(coroutine.resume(co)) == "true")
assert(show(coroutine.resume(co)) == "true,1,2,3")
assert(show(coroutine.resume(co, "a", "b")) == "true,nil,nil")
local ok, n1, n2, n3 = coroutine.resume(co, nil, nil, nil)
assert(ok and n1 == 0 and n2 == 2 and n3 == 3)
end

-- ## status transitions
do
local co
co = coroutine.create(function()
  assert(coroutine.status(co) == "running")
  coroutine.yield()
  assert(coroutine.status(co) == "running")
end)
assert(coroutine.status(co) == "suspended")
coroutine.resume(co)
assert(coroutine.status(co) == "suspended")
coroutine.resume(co)
assert(coroutine.status(co) == "dead")
end

-- ## a coroutine that resumed another one is "normal"
do
local outer, inner
local seen
inner = coroutine.create(function()
  seen = coroutine.status(outer)
end)
outer = coroutine.create(function()
  coroutine.resume(inner)
end)
coroutine.resume(outer)
assert(seen == "normal")
assert(coroutine.status(outer) == "dead")
assert(coroutine.status(inner) == "dead")
end

-- ## generators
do
local function range(n)
  return coroutine.wrap(function()
    for i = 1, n do coroutine.yield(i) end
  end)
end
local sum = 0
for v in range(10) do sum = sum + v end
assert(sum == 55)
local out = {}
for v in range(3) do out[#out + 1] = v end
assert(table.concat(out, ",") == "1,2,3")
local function chars(s)
  return coroutine.wrap(function()
    for i = 1, #s do coroutine.yield(i, s:sub(i, i)) end
  end)
end
out = {}
for i, c in chars("abc") do out[#out + 1] = c .. string.format("%d", i) end
assert(table.concat(out, ",") == "a1,b2,c3")
end

-- ## wrap
do
local f = coroutine.wrap(function(a)
  local b = coroutine.yield(a * 2)
  return a + b
end)
assert(type(f) == "function")
assert(f(5) == 10)
assert(f(3) == 8)
assert(not pcall(f))
local g = coroutine.wrap(function() return 1, 2, 3 end)
assert(show(g()) == "1,2,3")
local h = coroutine.wrap(function() coroutine.yield() end)
assert(select("#", h()) == 0)
end

-- ## dead coroutines cannot be resumed
do
local co = coroutine.create(function() end)
assert(coroutine.resume(co) == true)
local ok, msg = coroutine.resume(co)
assert(ok == false)
assert(type(msg) == "string")
ok, msg = coroutine.resume(co)
assert(ok == false and type(msg) == "string")
assert(coroutine.status(co) == "dead")
end

-- ## an error inside a coroutine kills it and is returned by resume
do
local co = coroutine.create(function() error("oops", 0) end)
local ok, msg = coroutine.resume(co)
assert(ok == false and msg == "oops")
assert(coroutine.status(co) == "dead")
assert(coroutine.resume(co) == false)
local errobj = {}
co = coroutine.create(function() coroutine.yield(1); error(errobj) end)
assert(coroutine.resume(co))
ok, msg = coroutine.resume(co)
assert(ok == false and msg == errobj)
co = coroutine.create(function() local x = nil; return x.y end)
ok, msg = coroutine.resume(co)
assert(ok == false and type(msg) == "string")
end

-- ## errors propagate through wrap
do
local f = coroutine.wrap(function() error("wrapped", 0) end)
local ok, msg = pcall(f)
assert(ok == false and msg == "wrapped")
local obj = {}
local g = coroutine.wrap(function() error(obj) end)
ok, msg = pcall(g)
assert(msg == obj)
assert(not pcall(g))
end

-- ## a coroutine cannot resume itself or a running coroutine
do
local co
co = coroutine.create(function()
  return coroutine.resume(co)
end)
local ok, inner_ok, msg = coroutine.resume(co)
assert(ok == true and inner_ok == false)
assert(type(msg) == "string")
end

-- ## yield outside a coroutine raises an error
do
assert(not pcall(coroutine.yield))
assert(not pcall(coroutine.yield, 1))
end

-- ## coroutines have independent stacks and locals
do
local function worker(name)
  return coroutine.create(function()
    local count = 0
    while true do
      count = count + 1
      coroutine.yield(name .. count)
    end
  end)
end
local w1, w2 = worker("a"), worker("b")
local _, r1 = coroutine.resume(w1)
local _, r2 = coroutine.resume(w2)
local _, r3 = coroutine.resume(w1)
local _, r4 = coroutine.resume(w1)
local _, r5 = coroutine.resume(w2)
assert(r1 == "a1" and r2 == "b1" and r3 == "a2" and r4 == "a3" and r5 == "b2")
end

-- ## coroutines share upvalues with their creator
do
local shared = 0
local co = coroutine.wrap(function()
  while true do
    shared = shared + 1
    coroutine.yield()
  end
end)
co(); co(); co()
assert(shared == 3)
shared = 10
co()
assert(shared == 11)
end

-- ## yield from nested function calls
do
local function leaf(x) return coroutine.yield(x) end
local function mid(x) local r = leaf(x + 1); return r * 2 end
local co = coroutine.create(function(x)
  local r = mid(x)
  return r + 1
end)
assert(show(coroutine.resume(co, 1)) == "true,2")
assert(show(coroutine.resume(co, 10)) == "true,21")
end

-- ## deep recursion with yields
do
local function walk(n)
  if n == 0 then return end
  coroutine.yield(n)
  walk(n - 1)
end
local co = coroutine.wrap(function() walk(100) end)
local count, last = 0, nil
for v in co, nil, nil, nil do count = count + 1; last = v end
assert(count == 100 and last == 1)
end

-- ## nested coroutines
do
local function gen(n)
  return coroutine.wrap(function()
    for i = 1, n do coroutine.yield(i) end
  end)
end
local outer = coroutine.wrap(function()
  for i in gen(3) do
    for j in gen(i) do
      coroutine.yield(i * 10 + j)
    end
  end
end)
local out = {}
for v in outer, nil, nil, nil do out[#out + 1] = v end
assert(table.concat(out, ",") == "11,21,22,31,32,33")
end

-- ## deeply nested resume chain
do
local function chain(depth)
  if depth == 0 then return "bottom" end
  local co = coroutine.create(chain)
  local ok, v = coroutine.resume(co, depth - 1)
  assert(ok)
  return v
end
assert(chain(50) == "bottom")
local function relay(depth)
  if depth == 0 then
    coroutine.yield("y1")
    coroutine.yield("y2")
    return "end"
  end
  local inner = coroutine.wrap(relay)
  local v = inner(depth - 1)
  while v ~= "end" do
    coroutine.yield(v)
    v = inner()
  end
  return "end"
end
local top = coroutine.wrap(relay)
assert(top(20) == "y1")
assert(top() == "y2")
assert(top() == "end")
end

-- ## producer / consumer
do
local function producer()
  return coroutine.create(function()
    for i = 1, 4 do coroutine.yield("item" .. i) end
    return nil
  end)
end
local function filter(src)
  return coroutine.create(function()
    while true do
      local ok, v = coroutine.resume(src)
      if not v then return nil end
      coroutine.yield(v:upper())
    end
  end)
end
local p = filter(producer())
local got = {}
while true do
  local ok, v = coroutine.resume(p)
  if not v then break end
  got[#got + 1] = v
end
assert(table.concat(got, ",") == "ITEM1,ITEM2,ITEM3,ITEM4")
end

-- ## many coroutines
do
local cos = {}
for i = 1, 1000 do
  cos[i] = coroutine.wrap(function(a)
    local b = coroutine.yield(a + i)
    return a + b
  end)
end
local total = 0
for i = 1, 1000 do total = total + cos[i](1) end
assert(total == 501500)
total = 0
for i = 1, 1000 do total = total + cos[i](2) end
assert(total == 3000)
end

-- ## a long-lived coroutine with many switches
do
local co = coroutine.wrap(function()
  local n = 0
  while true do n = n + coroutine.yield(n) end
end)
co()
local last
for i = 1, 100000 do last = co(1) end
assert(last == 100000)
end

-- ## resume arguments must be coroutines
do
assert(not pcall(coroutine.resume, nil))
assert(not pcall(coroutine.resume, function() end))
assert(not pcall(coroutine.resume, {}))
assert(not pcall(coroutine.status, nil))
assert(not pcall(coroutine.create, nil))
assert(not pcall(coroutine.create, 1))
assert(not pcall(coroutine.wrap, nil))
end

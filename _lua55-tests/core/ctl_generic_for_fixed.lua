-- Control flow: the generic for loop.
-- Most loops here pass four explicit control values; the adjustment of a
-- shorter expression list is covered by the dedicated sections below.
local load = loadstring or load

-- ## a single iterator value: state, control and closing value are nil
do
local got = {}
local function it(s, c)
  got[#got + 1] = tostring(s) .. "/" .. tostring(c)
end
do local a, b, c, d = 1, 2, 3, 4 end
for i in it do end
assert(got[1] == "nil/nil")
end

-- ## two control values: control and closing value are nil
do
local got = {}
local function it(s, c)
  got[#got + 1] = tostring(s) .. "/" .. tostring(c)
end
do local a, b, c, d = 1, 2, 3, 4 end
for i in it, 7 do end
assert(got[1] == "7/nil")
end

-- ## three control values: the closing value is nil
do
local n = 0
local function it(s, c) if c < s then return c + 1 end end
do local a, b, c, d = 1, 2, 3, 4 end
for i in it, 2, 0 do n = n + 1 end
assert(n == 2)
end

-- ## a stale closable value is not closed by a later loop
do
local closed = 0
local function it() end
do
  local a, b, c, d = 1, 2, 3, setmetatable({}, {__close = function() closed = closed + 1 end})
end
for i in it do end
assert(closed == 0)
end

-- ## consecutive loops with short expression lists
do
local function it(s, c) end
for i in it, 0, 0 do end
local dummy = tostring(1)
for i in it, 0 do end
for i in it do end
local t = {}
for k in next, t do end
for k in next, {1, 2} do end
for k in next, {1, 2, 3, 4, 5} do end
end

-- ## table constructors in the expression list
do
local n = 0
for k, v in next, {10, 20, 30} do n = n + v end
assert(n == 60)
end

-- ## control values produced by function calls in non-final positions
do
local function it(s, c) if c < s then return c + 1 end end
local function three() return 3, "dropped" end
local function zero() return 0, "dropped" end
local n = 0
for i in it, three(), 0, nil do n = n + 1 end
assert(n == 3)
n = 0
for i in it, 2, zero(), nil do n = n + 1 end
assert(n == 2)
end

-- ## a closing value produced by a function call
do
local log = {}
local function closer(name)
  return setmetatable({}, {__close = function() log[#log + 1] = name end})
end
local function it(s, c) if c < 2 then return c + 1 end end
for i in it, nil, 0, closer("c1") do log[#log + 1] = i end
assert(table.concat(log, ",") == "1,2,c1")
end

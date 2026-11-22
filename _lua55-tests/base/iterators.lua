-- ipairs, pairs and next.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

-- ipairs returns the iterator, the value and an integer zero
local iter, state, control = ipairs({})
assert(type(iter) == "function" and type(state) == "table" and tostring(control) == "0")
assert(select("#", ipairs({})) == 3)
assert(iter == ipairs({}))            -- always the same iterator function
iter, state, control = ipairs("x")    -- any value is accepted
assert(state == "x" and control == 0)
checkerr("value expected", ipairs)

-- plain traversal stops at the first nil
local seen = {}
for i, v in ipairs({"a", "b", "c"}) do seen[#seen + 1] = i .. "=" .. v end
assert(table.concat(seen, ",") == "1=a,2=b,3=c")
seen = {}
for i, v in ipairs({1, 2, nil, 4}) do seen[#seen + 1] = i end
assert(#seen == 2)
for _ in ipairs({}) do error("empty table must not iterate") end
-- the index is an integer
for i in ipairs({"x"}) do assert(tostring(i) == "1") end

-- ipairs respects __index
local proxy = setmetatable({}, {__index = function(_, i) if i <= 3 then return i * 10 end end})
seen = {}
for i, v in ipairs(proxy) do seen[#seen + 1] = v end
assert(table.concat(seen, ",") == "10,20,30")
-- ... and ignores __len
local count = 0
for _ in ipairs(setmetatable({}, {__index = function(_, i) if i < 3 then return i end end,
                                  __len = function() return 100 end})) do
  count = count + 1
end
assert(count == 2)
-- strings can be indexed through their metatable (and yield nil)
count = 0
for _ in ipairs("abc") do count = count + 1 end
assert(count == 0)

-- the iterator function itself
iter = ipairs({})
assert(select("#", iter({5}, 0)) == 2)
local i, v = iter({5}, 0)
assert(i == 1 and v == 5)
assert(select("#", iter({5}, 1)) == 1 and iter({5}, 1) == nil)
checkerr("number expected", iter)
checkerr("number expected", iter, {}, "x")
checkerr("attempt to index a number value", iter, 5, 0)
checkerr("idx1", iter, setmetatable({}, {__index = function(_, k) error("idx" .. k, 0) end}), 0)

-- pairs returns next, the table, nil and a closing value
local f, s, c, closing = pairs({})
assert(f == next and type(s) == "table" and c == nil and closing == nil)
assert(select("#", pairs({})) == 4)
checkerr("value expected", pairs)

local keys = {}
for k, val in pairs({10, 20, 30, x = 1, y = 2}) do keys[#keys + 1] = tostring(k) end
table.sort(keys)
assert(table.concat(keys, ",") == "1,2,3,x,y")
-- integer keys come back as integers, also when stored through a float
for k in pairs({[1.0] = true}) do assert(tostring(k) == "1") end
for k in pairs({[2^53] = true}) do assert(tostring(k) == "9007199254740992") end
for k in pairs({[1.5] = true}) do assert(tostring(k) == "1.5") end

-- __pairs
local r1, r2, r3, r4 = pairs(setmetatable({}, {__pairs = function(t) return 1, 2, 3, 4, 5 end}))
assert(r1 == 1 and r2 == 2 and r3 == 3 and r4 == 4)
assert(select("#", pairs(setmetatable({}, {__pairs = function() return 1 end}))) == 4)
assert(select("#", pairs(setmetatable({}, {__pairs = function() end}))) == 4)
local custom = setmetatable({}, {__pairs = function(t)
  return function(_, k)
    if not k then return 1, "one" elseif k < 3 then return k + 1, "more" end
  end, t, nil
end})
keys = {}
for k, val in pairs(custom) do keys[#keys + 1] = k .. val end
assert(table.concat(keys, ",") == "1one,2more,3more")
checkerr("pp", pairs, setmetatable({}, {__pairs = function() error("pp", 0) end}))
checkerr("attempt to call a number value", pairs, setmetatable({}, {__pairs = 5}))
-- the metamethod receives the object
local received
local target = setmetatable({}, {__pairs = function(t) received = t return next, {}, nil end})
pairs(target)
assert(received == target)

-- next
assert(next({}) == nil and next({}, nil) == nil)
assert(select("#", next({})) == 1 and select("#", next({1})) == 2)
local k, val = next({10})
assert(k == 1 and val == 10 and tostring(k) == "1")
assert(next({10}, 1) == nil)
k, val = next({a = 1})
assert(k == "a" and val == 1)
k, val = next({1, 2, 3}, 2)
assert(k == 3 and val == 3)
assert(next({1, 2, 3}, 3) == nil)
checkerr("table expected, got no value", next)
checkerr("table expected, got number", next, 1)

-- invalid keys
checkerr("invalid key to 'next'", next, {}, "nokey")
checkerr("invalid key to 'next'", next, {1, 2, 3}, 5)
checkerr("invalid key to 'next'", next, {1, 2, 3}, 0)
checkerr("invalid key to 'next'", next, {a = 1}, "b")
checkerr("invalid key to 'next'", next, {1, 2, 3}, 1.5)
checkerr("invalid key to 'next'", next, {1, 2, 3}, 2.0)   -- floats are not normalized
checkerr("invalid key to 'next'", next, {a = 1}, {})

-- fields may be cleared during a traversal
local tt = {1, 2, 3, a = 1, b = 2, c = 3, [10.5] = true}
count = 0
for key in next, tt, nil, nil do
  count = count + 1
  tt[key] = nil
end
assert(count == 7 and next(tt) == nil)
tt = {}
for n = 1, 100 do tt[n] = n; tt["k" .. n] = n end
count = 0
for key in pairs(tt) do
  count = count + 1
  tt[key] = nil
end
assert(count == 200 and next(tt) == nil)

-- a complete traversal with next visits every pair exactly once
tt = {1, 2, 3, x = "x", y = "y", [0] = "zero", [-1] = "neg", [2.5] = "float", [true] = "bool"}
local total, visited = 0, {}
local key, value = next(tt)
while key ~= nil do
  assert(not visited[key] and tt[key] == value)
  visited[key] = true
  total = total + 1
  key, value = next(tt, key)
end
assert(total == 9)

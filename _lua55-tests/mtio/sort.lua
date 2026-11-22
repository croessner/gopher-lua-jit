-- Lua 5.5 table.sort conformance checks.
-- Every assertion holds for the reference interpreter (lua5.5) as well.
-- Arrays are kept below 100 elements wherever the exact sequence of
-- comparisons matters: above that size the reference implementation may
-- randomize its pivots.

local function checkerr(msg, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. msg)
  assert(string.find(tostring(err), msg, 1, true),
    "unexpected error message: " .. tostring(err))
end

local function sorted(t, lt)
  lt = lt or function(a, b) return a < b end
  for i = 2, #t do
    if lt(t[i], t[i - 1]) then return false end
  end
  return true
end

-- lcg returns a deterministic pseudo-random generator.
local function lcg(seed)
  return function(n)
    seed = (seed * 1103515245 + 12345) % 2147483648
    return seed % n
  end
end

-- basics ----------------------------------------------------------------------
do
  local t = {3, 1, 2}
  assert(#table.pack(table.sort(t)) == 0) -- no results
  assert(table.concat(t, ",") == "1,2,3")
  t = {3, 1, 2}
  table.sort(t, function(a, b) return a > b end)
  assert(table.concat(t, ",") == "3,2,1")
  t = {"b", "a", "c", "B", ""}
  table.sort(t)
  assert(table.concat(t, ",") == ",B,a,b,c")
  t = {5, 3, 1}
  table.sort(t, nil)
  assert(table.concat(t, ",") == "1,3,5")
  t = {1, 2.5, 2, 0.5, -1, 2.0}
  table.sort(t)
  assert(table.concat(t, " ") == "-1 0.5 1 2 2.0 2.5")
  assert(sorted(t))
  t = {math.maxinteger, math.mininteger, 0, 2 ^ 63, -2 ^ 63, 1e308, -1e308}
  table.sort(t)
  assert(sorted(t) and t[1] == -1e308 and t[7] == 1e308 and t[4] == 0)
  -- trivial sizes never call the order function nor check it
  table.sort({})
  table.sort({1})
  table.sort({}, 5)
  table.sort({1}, "not a function")
  table.sort({1}, function() error("not called") end)
  t = {2, 1}
  table.sort(t)
  assert(t[1] == 1 and t[2] == 2)
  t = {1, 2, 3, 4, 5}
  table.sort(t)
  assert(table.concat(t) == "12345")
  t = {5, 4, 3, 2, 1}
  table.sort(t)
  assert(table.concat(t) == "12345")
  t = {2, 2, 2, 2}
  table.sort(t)
  assert(table.concat(t) == "2222")
end

-- various sizes and input shapes -----------------------------------------------
do
  local rnd = lcg(42)
  for _, n in ipairs({2, 3, 4, 5, 7, 8, 16, 31, 50, 99, 100, 101, 150, 500, 2000}) do
    local shapes = {
      function(i) return i end,                 -- ascending
      function(i) return n - i end,             -- descending
      function(i) return rnd(1000000) end,      -- random
      function(i) return rnd(5) end,            -- few distinct values
      function(i) return 7 end,                 -- all equal
      function(i) return i % 2 == 0 and i or -i end,
      function(i) return rnd(1000) / 8 end,     -- floats
    }
    for _, shape in ipairs(shapes) do
      local t, sum = {}, 0
      for i = 1, n do
        t[i] = shape(i)
        sum = sum + t[i]
      end
      table.sort(t)
      assert(#t == n and sorted(t))
      local check = 0
      for i = 1, n do check = check + t[i] end
      assert(check == sum)
      table.sort(t, function(a, b) return a > b end)
      assert(#t == n and sorted(t, function(a, b) return a > b end))
    end
  end
  -- strings
  local t = {}
  for i = 1, 300 do t[i] = "k" .. rnd(100000) end
  table.sort(t)
  assert(sorted(t))
  -- records with an order function
  t = {}
  for i = 1, 300 do t[i] = {key = rnd(50), id = i} end
  local function lt(a, b)
    if a.key ~= b.key then return a.key < b.key end
    return a.id < b.id
  end
  table.sort(t, lt)
  assert(sorted(t, lt))
end

-- the algorithm is the one of the reference implementation ----------------------
do
  -- the order of equal elements shows the exact sequence of swaps
  local y = {}
  for i = 1, 20 do y[i] = {k = i % 4, i = i} end
  table.sort(y, function(a, b) return a.k < b.k end)
  local s = {}
  for i = 1, 20 do s[i] = y[i].i end
  assert(table.concat(s, " ") == "20 12 16 4 8 9 17 13 1 5 14 2 10 18 6 3 15 11 7 19")

  -- ... and so does the number of comparisons
  local cnt = 0
  local z = {}
  for i = 1, 50 do z[i] = (i * 17) % 23 end
  table.sort(z, function(a, b) cnt = cnt + 1; return a < b end)
  assert(cnt == 257)
  assert(table.concat(z, " ") == "0 0 1 1 2 2 3 3 4 4 5 5 5 6 6 7 7 8 8 9 9 10 10 11 11 11 12 12 13 13 14 14 15 15 16 16 17 17 17 18 18 19 19 20 20 21 21 22 22 22")

  cnt = 0
  z = {}
  for i = 1, 99 do z[i] = (i * 37) % 101 end
  table.sort(z, function(a, b) cnt = cnt + 1; return a < b end)
  assert(cnt == 702 and sorted(z))

  -- an order function that always answers false leaves a result that
  -- depends on the exact algorithm
  local t = {}
  for i = 1, 90 do t[i] = (i * 7) % 13 end
  table.sort(t, function() return false end)
  assert(table.concat(t, " ") == "7 4 10 3 9 11 12 5 0 6 7 2 1 5 11 4 8 12 0 6 7 10 1 2 9 2 8 1 3 4 10 5 11 8 7 6 10 3 9 0 4 5 11 12 12 3 2 1 7 0 6 8 9 2 10 3 4 12 11 2 8 1 5 9 10 3 4 9 11 12 6 12 5 11 0 1 7 8 5 4 3 7 0 6 10 1 2 8 9 6")
end

-- errors -----------------------------------------------------------------------
do
  checkerr("attempt to compare", table.sort, {3, "a", 1})
  checkerr("attempt to compare", table.sort, {1, {}, 2})
  checkerr("attempt to compare two table values", table.sort, {{}, {}})
  checkerr("attempt to compare", table.sort, {true, false})
  checkerr("function expected, got number", table.sort, {1, 2, 3}, 1)
  checkerr("bad argument #2", table.sort, {1, 2, 3}, 1)
  checkerr("function expected, got table", table.sort, {1, 2}, setmetatable({}, {__call = function() end}))
  checkerr("function expected, got string", table.sort, {1, 2}, "x")
  checkerr("table expected, got number", table.sort, 1)
  checkerr("table expected, got string", table.sort, "abc")
  checkerr("table expected, got no value", table.sort)
  checkerr("array too big", table.sort, setmetatable({}, {__len = function() return math.maxinteger end}))
  checkerr("bad argument #1", table.sort, setmetatable({}, {__len = function() return 2 ^ 31 end}))
  checkerr("object length is not an integer", table.sort, setmetatable({}, {__len = function() return 2.5 end}))
  checkerr("boom", table.sort, {1, 2, 3}, function() error("boom") end)
  local ok, err = pcall(table.sort, {3, 2, 1}, function() error({code = 7}) end)
  assert(not ok and type(err) == "table" and err.code == 7)

  -- inconsistent order functions are detected (or tolerated) exactly as
  -- the reference implementation does
  local function fill(n, f)
    local t = {}
    for i = 1, n do t[i] = f(i) end
    return t
  end
  local always = function() return true end
  local le = function(a, b) return a <= b end
  local ge = function(a, b) return a >= b end
  checkerr("invalid order function for sorting", table.sort, {3, 2, 1, 4, 5, 6, 7, 8, 9, 10}, always)
  checkerr("invalid order function for sorting", table.sort, fill(90, function(i) return i % 3 end), le)
  checkerr("invalid order function for sorting", table.sort, fill(90, function(i) return 1 end), always)
  checkerr("invalid order function for sorting", table.sort, fill(90, function(i) return i end), always)
  checkerr("invalid order function for sorting", table.sort, fill(90, function(i) return 200 - i end), always)
  checkerr("invalid order function for sorting", table.sort, fill(90, function(i) return (i * 7) % 13 end), ge)
  checkerr("invalid order function for sorting", table.sort, fill(4, function(i) return 1 end), always)
  -- small arrays are sorted without the partition loop that detects it
  table.sort({1, 2, 3}, always)
  table.sort({2, 1}, always)
  local t = {1, 2, 3, 4, 5}
  table.sort(t, le) -- "<=" happens to work for distinct elements
  assert(table.concat(t) == "12345")
  t = fill(90, function(i) return i end)
  table.sort(t, function() return false end)
  assert(t[1] == 1 and t[90] == 90)
  -- an order function that raises errors now and then never corrupts the state
  local calls = 0
  t = fill(60, function(i) return (i * 31) % 61 end)
  ok = pcall(table.sort, t, function(a, b)
    calls = calls + 1
    if calls == 40 then error("stop") end
    return a < b
  end)
  assert(not ok and #t == 60)
  table.sort(t)
  assert(sorted(t))
  local sum = 0
  for i = 1, 60 do sum = sum + t[i] end
  assert(sum == 1830) -- still a permutation of 1..60
end

-- metamethods --------------------------------------------------------------------
do
  -- __lt of the elements
  local mt = {__lt = function(a, b) return a.v < b.v end}
  local t = {}
  for i = 1, 30 do t[i] = setmetatable({v = (i * 7) % 31}, mt) end
  table.sort(t)
  for i = 2, 30 do assert(t[i - 1].v <= t[i].v) end

  -- __len, __index and __newindex of the sorted object
  local store = {5, 3, 4, 1, 2, "ignored"}
  local gets, sets = 0, 0
  local p = setmetatable({}, {
    __len = function() return 5 end,
    __index = function(_, k) gets = gets + 1; return store[k] end,
    __newindex = function(_, k, v) sets = sets + 1; store[k] = v end,
  })
  table.sort(p)
  assert(table.concat(store, " ") == "1 2 3 4 5 ignored")
  assert(gets > 0 and sets > 0 and rawget(p, 1) == nil)

  -- only the first #t elements take part
  t = setmetatable({3, 2, 1, 0}, {__len = function() return 3 end})
  table.sort(t)
  assert(t[1] == 1 and t[2] == 2 and t[3] == 3 and t[4] == 0)

  -- values come back through __index, results are written raw
  local big = setmetatable({}, {
    __len = function() return 3 end,
    __index = function(_, k) return 4 - k end,
  })
  table.sort(big)
  assert(big[1] == 1 and big[2] == 2 and big[3] == 3)
  assert(rawget(big, 1) == 1 and rawget(big, 2) == nil and rawget(big, 3) == 3)

  checkerr("attempt to compare two nil values", table.sort,
    setmetatable({}, {__len = function() return 2 end}))
end

-- the order function may run arbitrary code ---------------------------------------
do
  local t = {}
  for i = 1, 40 do t[i] = (i * 13) % 41 end
  local co = coroutine.wrap(function()
    table.sort(t, function(a, b) return a < b end)
    return "done"
  end)
  assert(co() == "done" and sorted(t))

  -- nested sorts
  local outer = {}
  for i = 1, 10 do
    outer[i] = {}
    for j = 1, 10 do outer[i][j] = (i * j * 7) % 11 end
  end
  table.sort(outer, function(a, b)
    table.sort(a)
    table.sort(b)
    return a[10] + a[1] * 100 < b[10] + b[1] * 100
  end)
  for i = 1, 10 do assert(sorted(outer[i])) end
end

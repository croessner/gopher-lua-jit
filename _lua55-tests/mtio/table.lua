-- Lua 5.5 table library conformance checks (everything except sort).
-- Every assertion holds for the reference interpreter (lua5.5) as well.

local function checkerr(msg, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. msg)
  assert(string.find(tostring(err), msg, 1, true),
    "unexpected error message: " .. tostring(err))
end

local function eq(a, b)
  return a == b and math.type(a) == math.type(b)
end

-- same checks that the array t holds exactly the given values.
local function same(t, ...)
  local want = table.pack(...)
  for i = 1, want.n do
    assert(t[i] == want[i], "element " .. i .. ": " .. tostring(t[i]))
  end
  assert(t[want.n + 1] == nil, "extra element " .. tostring(t[want.n + 1]))
end

local maxi, mini = math.maxinteger, math.mininteger

-- proxy returns a table without raw contents whose accesses are logged and
-- forwarded to store.
local function proxy(store, n, log)
  return setmetatable({}, {
    __len = function() return n end,
    __index = function(_, k)
      log[#log + 1] = "get" .. tostring(k)
      return store[k]
    end,
    __newindex = function(_, k, v)
      log[#log + 1] = "set" .. tostring(k)
      store[k] = v
    end,
  })
end

-- contents of the library ---------------------------------------------------
do
  local expected = {concat = 1, create = 1, insert = 1, move = 1, pack = 1,
    remove = 1, sort = 1, unpack = 1}
  for k, v in pairs(table) do
    assert(expected[k] and type(v) == "function", "unexpected table." .. tostring(k))
    expected[k] = nil
  end
  assert(next(expected) == nil)
  assert(table.getn == nil and table.maxn == nil and table.foreach == nil)
end

-- table.insert --------------------------------------------------------------
do
  local t = {}
  table.insert(t, "a")
  table.insert(t, "c")
  table.insert(t, 2, "b")
  table.insert(t, 1, "z")
  same(t, "z", "a", "b", "c")
  table.insert(t, 5, "end")
  same(t, "z", "a", "b", "c", "end")
  table.insert(t, "2", "s") -- positions may be numeric strings
  same(t, "z", "s", "a", "b", "c", "end")
  table.insert(t, 3.0, "f") -- ... or floats with an integer value
  same(t, "z", "s", "f", "a", "b", "c", "end")

  t = {1, 2, 3}
  table.insert(t, nil) -- appending nil changes nothing
  same(t, 1, 2, 3)
  table.insert(t, 4, nil)
  same(t, 1, 2, 3)
  assert(#table.pack(table.insert(t, 4)) == 0) -- no results

  -- mixed value types keep their subtype
  t = {1, 2, 3}
  table.insert(t, 2, 1.5)
  table.insert(t, 1, "s")
  table.insert(t, {})
  assert(t[1] == "s" and eq(t[2], 1) and eq(t[3], 1.5) and eq(t[4], 2) and eq(t[5], 3))
  assert(type(t[6]) == "table" and #t == 6)

  -- many insertions at the front
  t = {}
  for i = 1, 200 do table.insert(t, 1, i) end
  assert(#t == 200 and t[1] == 200 and t[200] == 1 and t[100] == 101)

  checkerr("wrong number of arguments to 'insert'", table.insert, {})
  checkerr("wrong number of arguments to 'insert'", table.insert, {}, 1, 2, 3)
  checkerr("wrong number of arguments to 'insert'", table.insert, {}, 1, 2, nil)
  checkerr("position out of bounds", table.insert, {}, 0, 1)
  checkerr("bad argument #2", table.insert, {}, 0, 1)
  checkerr("position out of bounds", table.insert, {}, 2, 1)
  checkerr("position out of bounds", table.insert, {1, 2}, 4, 1)
  checkerr("position out of bounds", table.insert, {1, 2}, -1, 1)
  checkerr("position out of bounds", table.insert, {1, 2}, mini, 1)
  checkerr("number has no integer representation", table.insert, {}, 1.5, 1)
  checkerr("number expected, got string", table.insert, {}, "x", 1)
  checkerr("table expected, got number", table.insert, 1, 1)
  checkerr("table expected, got no value", table.insert)
  checkerr("table expected, got string", table.insert, "abc", 1)
  checkerr("table expected, got nil", table.insert, nil, 1)
  checkerr("table expected, got FILE*", table.insert, io.stdout, 1)

  -- metamethods are honored
  local log, store = {}, {10, 20, 30}
  local p = proxy(store, 3, log)
  table.insert(p, 2, "x")
  assert(table.concat(log, " ") == "get3 set4 get2 set3 set2")
  same(store, 10, "x", 20, 30)
  log = {}
  p = proxy(store, 4, log)
  table.insert(p, "y")
  assert(table.concat(log, " ") == "set5")
  same(store, 10, "x", 20, 30, "y")

  -- tables with a metatable (even an incomplete one) are accepted
  t = setmetatable({}, {__index = function() end})
  table.insert(t, 1)
  assert(rawget(t, 1) == 1)

  -- __len results
  checkerr("object length is not an integer", table.insert,
    setmetatable({}, {__len = function() return "x" end}), 1)
  checkerr("object length is not an integer", table.insert,
    setmetatable({}, {__len = function() return 2.5 end}), 1)
  t = setmetatable({}, {__len = function() return 3.0 end})
  table.insert(t, "v")
  assert(rawget(t, 4) == "v")
  t = setmetatable({}, {__len = function() return "2" end})
  table.insert(t, "v")
  assert(rawget(t, 3) == "v")
  t = setmetatable({}, {__len = function() return -5 end})
  table.insert(t, 7)
  assert(rawget(t, -4) == 7)
  t = setmetatable({}, {__len = function() return maxi end})
  table.insert(t, 7) -- the position wraps around
  assert(rawget(t, mini) == 7)
end

-- table.remove --------------------------------------------------------------
do
  local t = {1, 2, 3, 4, 5}
  assert(table.remove(t) == 5)
  same(t, 1, 2, 3, 4)
  assert(table.remove(t, 1) == 1)
  same(t, 2, 3, 4)
  assert(table.remove(t, 2) == 3)
  same(t, 2, 4)
  assert(table.remove(t, 3) == nil) -- #t + 1 is allowed
  same(t, 2, 4)
  assert(table.remove(t, "1") == 2)
  assert(table.remove(t, 1.0) == 4)
  same(t)
  assert(table.remove(t) == nil and table.remove(t, 0) == nil and table.remove(t, 1) == nil)
  assert(table.pack(table.remove({})).n == 1)

  t = {[0] = "z"}
  assert(table.remove(t, 0) == "z" and t[0] == nil) -- #t == 0 allows position 0
  t = {[0] = "z"}
  assert(table.remove(t) == "z" and t[0] == nil)

  t = {"a", 2, 3.5}
  assert(table.remove(t, 2) == 2 and t[1] == "a" and eq(t[2], 3.5) and #t == 2)
  assert(eq(table.remove(t), 3.5) and table.remove(t) == "a" and #t == 0)

  t = {}
  for i = 1, 100 do t[i] = i end
  for i = 1, 50 do assert(table.remove(t, 1) == i) end
  assert(#t == 50 and t[1] == 51 and t[50] == 100)
  assert(table.remove(t, 25) == 75 and t[25] == 76 and #t == 49)

  checkerr("position out of bounds", table.remove, {}, 2)
  checkerr("bad argument #2", table.remove, {}, 2)
  checkerr("position out of bounds", table.remove, {1, 2, 3}, 5)
  checkerr("position out of bounds", table.remove, {1, 2, 3}, 0)
  checkerr("position out of bounds", table.remove, {1, 2, 3}, -1)
  checkerr("number has no integer representation", table.remove, {}, 1.5)
  checkerr("number expected, got string", table.remove, {}, "x")
  checkerr("table expected, got number", table.remove, 5)
  checkerr("table expected, got string", table.remove, "abc")
  checkerr("table expected, got no value", table.remove)

  local log, store = {}, {10, 20, 30}
  local p = proxy(store, 3, log)
  assert(table.remove(p, 1) == 10)
  assert(table.concat(log, " ") == "get1 get2 set1 get3 set2 set3")
  same(store, 20, 30)
  log = {}
  p = proxy(store, 2, log)
  assert(table.remove(p) == 30)
  assert(table.concat(log, " ") == "get2 set2")
  same(store, 20)

  t = setmetatable({}, {__len = function() return -5 end})
  rawset(t, -5, "neg")
  assert(table.remove(t) == "neg" and rawget(t, -5) == nil)
  checkerr("position out of bounds", table.remove, t, -3)
end

-- table.concat --------------------------------------------------------------
do
  assert(table.concat({}) == "" and table.concat({}, "x") == "")
  assert(table.concat({"a"}) == "a" and table.concat({"a"}, ", ") == "a")
  assert(table.concat({"a", "b", "c"}) == "abc")
  assert(table.concat({"a", "b", "c"}, ", ") == "a, b, c")
  assert(table.concat({1, 2.5, "x", 3.0}, " ") == "1 2.5 x 3.0")
  assert(table.concat({2 ^ 63, mini, 1e100, -0.0}, " ") == "9.2233720368547758e+18 -9223372036854775808 1e+100 -0.0")
  assert(table.concat({1, 2, 3}, ",", 2) == "2,3")
  assert(table.concat({1, 2, 3}, ",", 2, 3) == "2,3")
  assert(table.concat({1, 2, 3}, ",", 2, 2) == "2")
  assert(table.concat({1, 2, 3}, ",", 3, 2) == "")
  assert(table.concat({1, 2, 3}, ",", 1, 2.0) == "1,2")
  assert(table.concat({1, 2, 3}, ",", "2", "3") == "2,3")
  assert(table.concat({1, 2, 3}, 5) == "15253") -- numbers are valid separators
  assert(table.concat({1, 2, 3}, 0.5) == "10.520.53")
  assert(table.concat({1, 2, 3}, nil) == "123")
  assert(table.concat({1, 2, 3}, nil, nil, nil) == "123")
  assert(table.concat({1, 2, 3}, nil, 2) == "23")
  assert(table.concat({1, 2, 3}, "", nil, 2) == "12")
  assert(table.concat({[0] = "a", "b"}, "", 0, 1) == "ab")
  assert(table.concat({[-1] = "x", [0] = "a", "b"}, "|", -1, 1) == "x|a|b")
  assert(table.concat({"a"}, ",", maxi, mini) == "")
  assert(table.concat({[maxi] = "m"}, "", maxi, maxi) == "m")
  assert(table.concat({[maxi - 1] = "l", [maxi] = "m"}, "-", maxi - 1, maxi) == "l-m")
  assert(table.concat({[mini] = "m", [mini + 1] = "n"}, "-", mini, mini + 1) == "m-n")
  assert(table.concat({"a", "b"}, "\0") == "a\0b")
  do
    local t = {}
    for i = 1, 1000 do t[i] = i end
    local s = table.concat(t, ",")
    assert(#s == 3892 and string.sub(s, 1, 8) == "1,2,3,4," and string.sub(s, -9) == ",999,1000")
  end

  checkerr("invalid value (table) at index 2 in table for 'concat'", table.concat, {1, {}, 3})
  checkerr("invalid value (nil) at index 3 in table for 'concat'", table.concat, {1, 2}, ",", 1, 3)
  checkerr("invalid value (boolean) at index 2 in table for 'concat'", table.concat, {1, true})
  checkerr("invalid value (nil) at index 1 in table for 'concat'", table.concat, {}, ",", 1, 1)
  checkerr("invalid value (nil) at index 0 in table for 'concat'", table.concat, {1}, ",", 0, 1)
  checkerr("invalid value (nil) at index 9223372036854775807 in table for 'concat'",
    table.concat, {}, "", maxi, maxi)
  checkerr("invalid value (function) at index 1", table.concat, {print})
  checkerr("string expected, got table", table.concat, {1}, {})
  checkerr("bad argument #2", table.concat, {1}, {})
  checkerr("number has no integer representation", table.concat, {1}, ",", 1.5)
  checkerr("number expected, got string", table.concat, {1}, ",", 1, "x")
  checkerr("table expected, got number", table.concat, 1)
  checkerr("table expected, got no value", table.concat)

  -- metamethods
  local t = setmetatable({}, {
    __len = function() return 3 end,
    __index = function(_, k) return k * 10 end,
  })
  assert(table.concat(t, "-") == "10-20-30")
  assert(table.concat(t, "-", 2, 5) == "20-30-40-50")
  t = setmetatable({"a", "b", "c"}, {__len = function() return 2 end})
  assert(table.concat(t, ",") == "a,b")
  -- strings have a length and an index metamethod, so they are accepted
  assert(table.concat("") == "")
  checkerr("invalid value (nil) at index 1 in table for 'concat'", table.concat, "abc")
end

-- table.pack / table.unpack -------------------------------------------------
do
  local t = table.pack()
  assert(eq(t.n, 0) and #t == 0 and next(t) == "n")
  t = table.pack(1, nil, 3, nil)
  assert(eq(t.n, 4) and t[1] == 1 and t[2] == nil and t[3] == 3 and t[4] == nil)
  t = table.pack("a", 2.5, true)
  assert(t.n == 3 and t[1] == "a" and eq(t[2], 2.5) and t[3] == true)
  t = table.pack(nil)
  assert(t.n == 1 and t[1] == nil)
  do
    local big = {}
    for i = 1, 200 do big[i] = i end
    t = table.pack(table.unpack(big))
    assert(t.n == 200 and t[1] == 1 and t[200] == 200)
  end

  local function count(...) return table.pack(...).n end
  local a, b, c, d = table.unpack({1, 2, 3})
  assert(a == 1 and b == 2 and c == 3 and d == nil)
  assert(count(table.unpack({1, 2, 3})) == 3)
  a, b, c = table.unpack({1, 2, 3}, 2)
  assert(a == 2 and b == 3 and c == nil)
  a, b, c = table.unpack({1, 2, 3}, 2, 3)
  assert(a == 2 and b == 3 and c == nil)
  a, b, c, d = table.unpack({1, 2, 3}, 3, 5)
  assert(a == 3 and b == nil and c == nil and count(table.unpack({1, 2, 3}, 3, 5)) == 3)
  a, b, c = table.unpack({1, 2, 3}, 0, 1)
  assert(a == nil and b == 1 and c == nil)
  a, b, c, d = table.unpack({1, 2, 3}, -1, 1)
  assert(a == nil and b == nil and c == 1 and d == nil)
  assert(count(table.unpack({1, 2, 3}, 4)) == 0)
  assert(count(table.unpack({1, 2, 3}, 5, 2)) == 0)
  assert(count(table.unpack({}, 1, 3)) == 3)
  assert(count(table.unpack({})) == 0)
  assert(count(table.unpack({}, maxi, maxi)) == 1)
  assert(count(table.unpack({}, mini, mini)) == 1)
  assert(count(table.unpack({}, maxi, mini)) == 0)
  assert(count(table.unpack({}, "1", "2")) == 2)
  assert(count(table.unpack({1, 2, 3}, nil, 2)) == 2)
  assert(count(table.unpack({1, 2, 3}, 2, nil)) == 2)
  assert(count(table.unpack({1, 2, 3}, 1.0, 2.0)) == 2)
  a, b = table.unpack({[maxi - 1] = "x", [maxi] = "y"}, maxi - 1, maxi)
  assert(a == "x" and b == "y")
  a, b = table.unpack({1, 2.5})
  assert(eq(a, 1) and eq(b, 2.5))
  t = table.pack(table.unpack({1, nil, 3}, 1, 3))
  assert(t.n == 3 and t[1] == 1 and t[2] == nil and t[3] == 3)
  do
    local big = {}
    for i = 1, 150 do big[i] = i * 2 end
    t = {table.unpack(big)}
    assert(#t == 150 and t[150] == 300)
    t = {table.unpack(big, 100, 150)}
    assert(#t == 51 and t[1] == 200 and t[51] == 300)
  end

  checkerr("too many results to unpack", table.unpack, {}, 1, 1e8)
  checkerr("too many results to unpack", table.unpack, {}, 1, maxi)
  checkerr("too many results to unpack", table.unpack, {}, mini, maxi)
  checkerr("too many results to unpack", table.unpack, {}, 0, maxi)
  checkerr("too many results to unpack", table.unpack, {}, mini, 0)
  checkerr("too many results to unpack", table.unpack, {}, 1, 1e7)
  checkerr("number has no integer representation", table.unpack, {}, 1, 1.5)
  checkerr("number has no integer representation", table.unpack, {}, 1.5)
  checkerr("number expected, got string", table.unpack, {}, "x")
  checkerr("table expected, got number", table.unpack, 1)
  checkerr("table expected, got nil", table.unpack, nil)
  checkerr("table expected, got no value", table.unpack)
  checkerr("table expected, got boolean", table.unpack, true, 1, 2)

  -- metamethods
  t = setmetatable({}, {
    __len = function() return 3 end,
    __index = function(_, k) return k * 10 end,
  })
  a, b, c, d = table.unpack(t)
  assert(a == 10 and b == 20 and c == 30 and d == nil)
  a, b = table.unpack(t, 7, 8)
  assert(a == 70 and b == 80)
  checkerr("object length is not an integer", table.unpack,
    setmetatable({}, {__len = function() return 1.5 end}))
  -- strings are indexable and have a length
  assert(count(table.unpack("abc")) == 3 and count(table.unpack("ab", 1, 1)) == 1)
end

-- table.move ----------------------------------------------------------------
do
  local t = table.move({1, 2, 3}, 1, 3, 2)
  same(t, 1, 1, 2, 3)
  t = table.move({1, 2, 3, 4, 5}, 2, 5, 1)
  same(t, 2, 3, 4, 5, 5)
  t = table.move({1, 2, 3, 4, 5}, 1, 4, 2) -- overlapping, moving up
  same(t, 1, 1, 2, 3, 4)
  t = table.move({1, 2, 3, 4, 5}, 3, 5, 1) -- overlapping, moving down
  same(t, 3, 4, 5, 4, 5)
  t = table.move({1, 2, 3}, 1, 3, 1) -- onto itself
  same(t, 1, 2, 3)
  local dst = {}
  local src = {1, 2, 3}
  assert(table.move(src, 1, 3, 1, dst) == dst) -- returns the destination
  same(dst, 1, 2, 3)
  assert(table.move(src, 1, 3, 2) == src)
  t = table.move({1, 2, 3}, 1, 0, 5) -- empty range
  same(t, 1, 2, 3)
  t = table.move({1, 2, 3}, 2, 3, 10, {})
  assert(t[10] == 2 and t[11] == 3 and t[9] == nil and t[12] == nil and t[1] == nil)
  t = table.move({1}, 1, 1, 3)
  assert(t[1] == 1 and t[2] == nil and t[3] == 1)
  t = table.move({[0] = "z", "a"}, 0, 1, 1)
  assert(t[0] == "z" and t[1] == "z" and t[2] == "a")
  t = table.move({"a", "b"}, 1, 2, -1, {})
  assert(t[-1] == "a" and t[0] == "b")
  t = table.move({1, 2.5, "s"}, 1, 3, 1, {})
  assert(eq(t[1], 1) and eq(t[2], 2.5) and t[3] == "s")
  t = table.move({"a", "b", "c"}, 1, 3, 3, {"x", "y"})
  same(t, "x", "y", "a", "b", "c")
  t = table.move({}, 1, 0, 1, {7})
  same(t, 7)
  assert(type(table.move({}, 0, 1, 1)) == "table")
  assert(type(table.move({}, 1, 2, 3, nil)) == "table")
  t = table.move({"a", "b"}, "1", 2.0, "3")
  same(t, "a", "b", "a", "b")
  t = table.move({[maxi - 1] = "p", [maxi] = "q"}, maxi - 1, maxi, 1, {})
  same(t, "p", "q")
  t = table.move({"p", "q"}, 1, 2, maxi - 1, {})
  assert(t[maxi - 1] == "p" and t[maxi] == "q")
  t = table.move({[mini] = "p", [mini + 1] = "q"}, mini, mini + 1, 1, {})
  same(t, "p", "q")
  do
    local big = {}
    for i = 1, 500 do big[i] = i end
    t = table.move(big, 1, 500, 1, {})
    assert(#t == 500 and t[1] == 1 and t[500] == 500)
    table.move(big, 1, 499, 2)
    assert(big[1] == 1 and big[2] == 1 and big[500] == 499)
  end

  checkerr("too many elements to move", table.move, {}, mini, 0, 1)
  checkerr("bad argument #3", table.move, {}, mini, 0, 1)
  checkerr("too many elements to move", table.move, {}, -1, maxi, 1)
  checkerr("too many elements to move", table.move, {}, 0, maxi, 1)
  checkerr("destination wrap around", table.move, {}, 1, maxi, 2)
  checkerr("bad argument #4", table.move, {}, 1, maxi, 2)
  checkerr("destination wrap around", table.move, {}, 1, 10, maxi - 3)
  checkerr("number expected, got no value", table.move, {}, 1, 2)
  checkerr("number expected, got no value", table.move, {})
  checkerr("table expected, got number", table.move, {}, 1, 2, 3, 4)
  checkerr("bad argument #5", table.move, {}, 1, 2, 3, 4)
  checkerr("table expected, got number", table.move, 1, 1, 2, 3)
  checkerr("number has no integer representation", table.move, {}, 1.5, 2, 3)
  checkerr("number expected, got string", table.move, {}, 1, "x", 3)

  -- metamethods and the direction of the copy
  local a = setmetatable({}, {__index = function(_, k) return k * 2 end})
  t = table.move(a, 1, 3, 1, {})
  same(t, 2, 4, 6)
  local sets = {}
  local b = setmetatable({}, {__newindex = function(_, k, v) sets[#sets + 1] = k .. "=" .. v end})
  table.move({1, 2, 3}, 1, 3, 2, b)
  assert(table.concat(sets, " ") == "2=1 3=2 4=3")
  sets = {}
  local c = setmetatable({}, {
    __index = function(_, k) return k end,
    __newindex = function(_, k, v) sets[#sets + 1] = k .. "=" .. v end,
  })
  table.move(c, 1, 3, 2) -- overlap: copied backwards
  assert(table.concat(sets, " ") == "4=3 3=2 2=1")
  sets = {}
  table.move(c, 2, 4, 1) -- no harmful overlap: copied forwards
  assert(table.concat(sets, " ") == "1=2 2=3 3=4")
  sets = {}
  table.move(c, 1, 3, 2, c) -- explicit destination equal to the source
  assert(table.concat(sets, " ") == "4=3 3=2 2=1")
  sets = {}
  table.move(c, 1, 3, 2, b) -- other destination: copied forwards
  assert(table.concat(sets, " ") == "2=1 3=2 4=3")
  -- a string is a valid source
  assert(type(table.move("abc", 1, 2, 1, {})) == "table")
  checkerr("table expected, got string", table.move, {}, 1, 2, 1, "abc")
end

-- table.create --------------------------------------------------------------
do
  local t = table.create(10, 5)
  assert(type(t) == "table" and #t == 0 and next(t) == nil)
  assert(getmetatable(t) == nil)
  for i = 1, 20 do t[i] = i end
  t.x = 1
  assert(#t == 20 and t[20] == 20 and t.x == 1)
  assert(#table.create(0) == 0 and next(table.create(0, 0)) == nil)
  assert(type(table.create("3")) == "table" and type(table.create(3.0, 2.0)) == "table")
  assert(type(table.create(100000, 100000)) == "table")
  assert(table.create(1) ~= table.create(1))
  checkerr("number expected, got no value", table.create)
  checkerr("out of range", table.create, -1)
  checkerr("bad argument #1", table.create, -1)
  checkerr("out of range", table.create, 1, -1)
  checkerr("bad argument #2", table.create, 1, -1)
  checkerr("out of range", table.create, 2 ^ 31)
  checkerr("out of range", table.create, 1, 2 ^ 31)
  checkerr("out of range", table.create, maxi)
  checkerr("out of range", table.create, mini)
  checkerr("number has no integer representation", table.create, 1.5)
  checkerr("number expected, got string", table.create, "a")
  checkerr("number expected, got table", table.create, 1, {})
end

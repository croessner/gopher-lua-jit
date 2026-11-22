-- select and the raw access functions.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

local function pack(...)
  return {n = select("#", ...), ...}
end

-- select('#')
assert(select("#") == 0)
assert(select("#", 1, nil, nil) == 3)
assert(select("#", nil) == 1)
assert(tostring(select("#", 1, 2)) == "2")
assert(select("#", select(2, 1)) == 0)
assert(select("#x", 1, 2) == 2)       -- only the first character matters

-- positive indices
local r = pack(select(2, "a", "b", "c"))
assert(r.n == 2 and r[1] == "b" and r[2] == "c")
r = pack(select(3, 1, 2, 3))
assert(r.n == 1 and r[1] == 3)
r = pack(select(5, "a"))
assert(r.n == 0)
r = pack(select(1))
assert(r.n == 0)
assert(select(2.0, "a", "b") == "b")
assert(select("2", "a", "b") == "b")
assert(select(" 2 ", "a", "b") == "b")
assert(select("0x2", "a", "b") == "b")
r = pack(select(2^53, 1))
assert(r.n == 0)
r = pack(select(9223372036854775807, 1))
assert(r.n == 0)

-- negative indices count from the end
r = pack(select(-1, "a", "b", "c"))
assert(r.n == 1 and r[1] == "c")
r = pack(select(-2, "a", "b", "c"))
assert(r.n == 2 and r[1] == "b" and r[2] == "c")
r = pack(select(-3, "a", "b", "c"))
assert(r.n == 3 and r[1] == "a")

-- errors
checkerr("index out of range", select, -4, "a", "b", "c")
checkerr("index out of range", select, 0, "a")
checkerr("index out of range", select, -2^53, 1)
checkerr("index out of range", select, -9223372036854775807 - 1, 1)
checkerr("number expected, got string", select, "x")
checkerr("number expected, got no value", select)
checkerr("number expected, got table", select, {})
checkerr("number has no integer representation", select, 1.5, "a")

-- rawlen
assert(rawlen({1, 2, 3}) == 3 and rawlen({}) == 0 and rawlen("abcd") == 4 and rawlen("") == 0)
assert(tostring(rawlen({1, 2})) == "2")
assert(rawlen(setmetatable({1, 2}, {__len = function() return 99 end})) == 2)
assert(#setmetatable({1, 2}, {__len = function() return 99 end}) == 99)
assert(rawlen(setmetatable({}, {__index = {1, 2, 3}})) == 0)
checkerr("table or string expected", rawlen, 5)
checkerr("table or string expected", rawlen, nil)
checkerr("table or string expected", rawlen)

-- rawequal
assert(rawequal(1, 1.0) and rawequal("a", "a") and rawequal(nil, nil) and rawequal(0, -0))
assert(rawequal(0.0, -0.0) and rawequal(2^53, 2^53 + 1))
assert(not rawequal({}, {}) and not rawequal(1, 1.5) and not rawequal("1", 1))
assert(not rawequal(0/0, 0/0))
assert(not rawequal(9223372036854775807, 9223372036854775807 + 0.0))
local eq = {__eq = function() return true end}
local a, b = setmetatable({}, eq), setmetatable({}, eq)
assert(a == b and not rawequal(a, b) and rawequal(a, a))
checkerr("value expected", rawequal)
checkerr("value expected", rawequal, 1)

-- rawget
assert(rawget({10}, 1) == 10 and rawget({k = "v"}, "k") == "v" and rawget({}, "x") == nil)
assert(rawget({}, nil) == nil)
assert(rawget(setmetatable({}, {__index = function() return 1 end}), "x") == nil)
assert(rawget({[1] = "int"}, 1.0) == "int")
checkerr("table expected, got number", rawget, 1, 2)
checkerr("table expected, got nil", rawget, nil, 1)
checkerr("value expected", rawget, {})

-- rawset
local t = {}
assert(rawset(t, 1, 2) == t and t[1] == 2)
local guarded = setmetatable({}, {__newindex = function() error("no") end})
assert(rawset(guarded, "k", "v") == guarded and guarded.k == "v")
assert(not pcall(function() guarded.other = 1 end))
rawset(t, 1, nil)
assert(t[1] == nil and next(t) == nil)
rawset(t, 2.0, "float key")
assert(t[2] == "float key")
checkerr("table expected, got number", rawset, 1, 1, 1)
checkerr("value expected", rawset, {}, 1)
checkerr("table index is nil", rawset, {}, nil, 1)
checkerr("table index is NaN", rawset, {}, 0/0, 1)

-- argument errors name the function: by its global name when it is called
-- from a library function, by the name used at the call site otherwise
local ok, msg = pcall(select, 0)
assert(not ok and msg == "bad argument #1 to 'select' (index out of range)", msg)
ok, msg = pcall(rawlen, 5)
assert(not ok and msg == "bad argument #1 to 'rawlen' (table or string expected, got number)", msg)
ok, msg = pcall(setmetatable, {}, 1)
assert(not ok and msg == "bad argument #2 to 'setmetatable' (nil or table expected, got number)", msg)
ok, msg = pcall(tonumber, "1", 99)
assert(not ok and msg == "bad argument #2 to 'tonumber' (base out of range)", msg)
ok, msg = pcall(collectgarbage, "bogus")
assert(not ok and msg == "bad argument #1 to 'collectgarbage' (invalid option 'bogus')", msg)
ok, msg = pcall(debug.getinfo, 1, "X")
assert(not ok and msg == "bad argument #2 to 'debug.getinfo' (invalid option)", msg)
ok, msg = pcall(debug.getlocal, 99, 1)
assert(not ok and msg == "bad argument #1 to 'debug.getlocal' (level out of range)", msg)
local src = debug.getinfo(1, "S").short_src
local function line() return debug.getinfo(2, "l").currentline end
local l
ok, msg = pcall(function() l = line() select(0) end)
assert(not ok and msg == src .. ":" .. l .. ": bad argument #1 to 'select' (index out of range)", msg)
local alias = select
ok, msg = pcall(function() l = line() alias(0) end)
assert(not ok and msg == src .. ":" .. l .. ": bad argument #1 to 'alias' (index out of range)", msg)
local lib = {sel = select}
ok, msg = pcall(function() l = line() lib.sel(0) end)
assert(not ok and msg == src .. ":" .. l .. ": bad argument #1 to 'sel' (index out of range)", msg)

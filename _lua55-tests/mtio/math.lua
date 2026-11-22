-- Lua 5.5 math library conformance checks.
-- Every assertion holds for the reference interpreter (lua5.5) as well.

local function checkerr(msg, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. msg)
  assert(string.find(tostring(err), msg, 1, true),
    "unexpected error message: " .. tostring(err))
end

-- eq compares value and subtype (integer vs float).
local function eq(a, b)
  return a == b and math.type(a) == math.type(b)
end

local function isnan(x) return x ~= x end

local function near(a, b)
  local d = a - b
  if d < 0 then d = -d end
  return d <= 1e-12 * (b < 0 and -b or b) or d <= 1e-300
end

local maxi, mini = math.maxinteger, math.mininteger

-- contents of the library ---------------------------------------------------
do
  local expected = {
    abs = "function", acos = "function", asin = "function", atan = "function",
    ceil = "function", cos = "function", deg = "function", exp = "function",
    floor = "function", fmod = "function", frexp = "function",
    huge = "number", ldexp = "function", log = "function", max = "function",
    maxinteger = "number", min = "function", mininteger = "number",
    modf = "function", pi = "number", rad = "function", random = "function",
    randomseed = "function", sin = "function", sqrt = "function",
    tan = "function", tointeger = "function", type = "function",
    ult = "function",
  }
  local n = 0
  for k, v in pairs(math) do
    assert(expected[k] == type(v), "unexpected math." .. tostring(k))
    n = n + 1
  end
  for k in pairs(expected) do
    assert(math[k] ~= nil, "missing math." .. k)
    n = n - 1
  end
  assert(n == 0)
  -- functions of older versions are gone
  assert(math.pow == nil and math.cosh == nil and math.sinh == nil)
  assert(math.tanh == nil and math.log10 == nil and math.atan2 == nil)
  assert(math.mod == nil)
end

-- constants -----------------------------------------------------------------
assert(math.type(math.pi) == "float" and math.pi > 3.14159 and math.pi < 3.1416)
assert(math.huge == 1 / 0 and -math.huge == -1 / 0)
assert(math.type(math.huge) == "float")
assert(eq(maxi, 9223372036854775807) and eq(mini, -9223372036854775807 - 1))
assert(maxi + 1 == mini and mini - 1 == maxi)
assert(tostring(math.huge) == "inf" and tostring(-math.huge) == "-inf")

-- math.type -----------------------------------------------------------------
assert(math.type(1) == "integer" and math.type(1.0) == "float")
assert(math.type("1") == nil and math.type(nil) == nil and math.type({}) == nil)
assert(math.type(true) == nil and math.type(print) == nil)
checkerr("value expected", math.type)

-- math.tointeger ------------------------------------------------------------
assert(eq(math.tointeger(3.0), 3) and eq(math.tointeger(7), 7))
assert(math.tointeger(3.5) == nil and math.tointeger(0 / 0) == nil)
assert(math.tointeger(math.huge) == nil and math.tointeger(-math.huge) == nil)
assert(eq(math.tointeger("8"), 8) and eq(math.tointeger("8.0"), 8))
assert(eq(math.tointeger("0x10"), 16) and eq(math.tointeger(" 12 "), 12))
assert(math.tointeger("x") == nil and math.tointeger("8.5") == nil)
assert(math.tointeger({}) == nil and math.tointeger(true) == nil)
assert(math.tointeger(nil) == nil)
assert(math.tointeger(2 ^ 63) == nil and eq(math.tointeger(-2 ^ 63), mini))
assert(eq(math.tointeger(2 ^ 53), 9007199254740992))
assert(eq(math.tointeger(-0.0), 0))
checkerr("value expected", math.tointeger)

-- math.abs ------------------------------------------------------------------
assert(eq(math.abs(-3), 3) and eq(math.abs(3), 3) and eq(math.abs(0), 0))
assert(eq(math.abs(-3.5), 3.5) and eq(math.abs(3.5), 3.5))
assert(eq(math.abs(mini), mini)) -- wraps around
assert(eq(math.abs(maxi), maxi) and eq(math.abs(-maxi), maxi))
assert(eq(math.abs("-4"), 4.0)) -- strings are converted to floats
assert(eq(math.abs("-4.5"), 4.5))
assert(tostring(math.abs(-0.0)) == "0.0")
assert(math.abs(-math.huge) == math.huge and isnan(math.abs(0 / 0)))
checkerr("number expected, got nil", math.abs, nil)
checkerr("number expected, got no value", math.abs)
checkerr("number expected, got string", math.abs, "x")

-- math.ceil / math.floor ----------------------------------------------------
assert(eq(math.floor(3.7), 3) and eq(math.floor(-3.7), -4))
assert(eq(math.floor(5), 5) and eq(math.floor(-5), -5) and eq(math.floor(3.0), 3))
assert(eq(math.floor(1e100), 1e100) and eq(math.floor(-1e100), -1e100))
assert(eq(math.floor(-math.huge), -math.huge) and eq(math.floor(math.huge), math.huge))
assert(isnan(math.floor(0 / 0)) and math.type(math.floor(0 / 0)) == "float")
assert(eq(math.floor("3.5"), 3) and eq(math.floor("7"), 7))
assert(eq(math.floor(2 ^ 62), 4611686018427387904))
assert(eq(math.floor(2 ^ 63), 2 ^ 63) and eq(math.floor(-2 ^ 63), mini))
assert(eq(math.floor(-0.0), 0) and eq(math.floor(0.5), 0) and eq(math.floor(-0.5), -1))
assert(eq(math.floor(maxi), maxi) and eq(math.floor(mini), mini))
assert(eq(math.ceil(3.2), 4) and eq(math.ceil(-3.2), -3))
assert(eq(math.ceil(5), 5) and eq(math.ceil(3.0), 3))
assert(eq(math.ceil(1e100), 1e100) and eq(math.ceil(math.huge), math.huge))
assert(eq(math.ceil("3.5"), 4) and eq(math.ceil(-0.5), 0))
assert(eq(math.ceil(2 ^ 63), 2 ^ 63) and eq(math.ceil(-2 ^ 63), mini))
assert(eq(math.ceil(2 ^ 62 + 0.0), 4611686018427387904))
assert(isnan(math.ceil(0 / 0)))
checkerr("number expected, got string", math.floor, "x")
checkerr("number expected, got no value", math.floor)
checkerr("number expected, got table", math.ceil, {})

-- math.fmod -----------------------------------------------------------------
assert(eq(math.fmod(7, 3), 1) and eq(math.fmod(-7, 3), -1))
assert(eq(math.fmod(7, -3), 1) and eq(math.fmod(-7, -3), -1))
assert(eq(math.fmod(6, 2), 0) and eq(math.fmod(-6, 2), 0) and eq(math.fmod(6, -2), 0))
assert(eq(math.fmod(7.5, 2), 1.5) and eq(math.fmod(-7.5, 2), -1.5))
assert(eq(math.fmod(7, 3.0), 1.0) and eq(math.fmod(7.0, 3), 1.0))
assert(eq(math.fmod("7", "3"), 1.0)) -- strings are converted to floats
assert(eq(math.fmod(mini, -1), 0) and eq(math.fmod(maxi, -1), 0))
assert(eq(math.fmod(5, mini), 5) and eq(math.fmod(mini, mini), 0))
assert(eq(math.fmod(mini, maxi), -1) and eq(math.fmod(maxi, mini), maxi))
assert(eq(math.fmod(3, math.huge), 3.0) and eq(math.fmod(-3, math.huge), -3.0))
assert(isnan(math.fmod(1, 0.0)) and isnan(math.fmod(1.0, 0)))
assert(isnan(math.fmod(math.huge, 2)))
assert(tostring(math.fmod(-6.0, 2)) == "-0.0")
checkerr("bad argument #2", math.fmod, 1, 0)
checkerr("zero", math.fmod, 1, 0)
checkerr("zero", math.fmod, mini, 0)
checkerr("number expected, got no value", math.fmod, 1)
checkerr("number expected, got string", math.fmod, "a", 1)

-- math.modf -----------------------------------------------------------------
do
  local function modf(x, ip, fp)
    local a, b = math.modf(x)
    assert(eq(a, ip), "modf integral part of " .. tostring(x))
    assert(eq(b, fp), "modf fractional part of " .. tostring(x))
  end
  modf(3.5, 3, 0.5)
  modf(-3.5, -3, -0.5)
  modf(5, 5, 0.0)
  modf(-7, -7, 0.0)
  modf(4.0, 4, 0.0)
  modf(-0.0, 0, 0.0)
  modf(0.25, 0, 0.25)
  modf(-0.25, 0, -0.25)
  modf(math.huge, math.huge, 0.0)
  modf(-math.huge, -math.huge, 0.0)
  modf(1e100, 1e100, 0.0)
  modf(2 ^ 63, 2 ^ 63, 0.0)
  modf("2.5", 2, 0.5)
  modf(maxi, maxi, 0.0)
  modf(mini, mini, 0.0)
  local a, b = math.modf(0 / 0)
  assert(isnan(a) and isnan(b))
  a, b = math.modf(3.7)
  assert(eq(a, 3) and b > 0.69 and b < 0.71)
  assert(#table.pack(math.modf(1)) == 2)
  checkerr("number expected", math.modf, {})
end

-- math.ult ------------------------------------------------------------------
assert(math.ult(1, 2) == true and math.ult(2, 1) == false and math.ult(1, 1) == false)
assert(math.ult(-1, 2) == false and math.ult(2, -1) == true)
assert(math.ult(maxi, mini) == true and math.ult(mini, maxi) == false)
assert(math.ult(0, -1) == true and math.ult(-2, -1) == true)
assert(math.ult(1.0, 2.0) == true and math.ult("1", "2") == true)
checkerr("number has no integer representation", math.ult, 1.5, 2)
checkerr("number expected, got no value", math.ult, 1)
checkerr("number expected, got nil", math.ult, nil, 1)

-- math.max / math.min -------------------------------------------------------
assert(eq(math.max(1, 2.5), 2.5) and eq(math.max(2, 1), 2))
assert(eq(math.max(1, 2.0), 2.0) and eq(math.max(2.0, 2), 2.0) and eq(math.max(2, 2.0), 2))
assert(eq(math.min(1, 2.5), 1) and eq(math.min(1.0, 1), 1.0) and eq(math.min(1, 1.0), 1))
assert(eq(math.min(3), 3) and eq(math.max(3.5), 3.5))
assert(eq(math.max(1, 5, 3, 4, 2), 5) and eq(math.min(4, 5, 1, 3, 2), 1))
assert(eq(math.max(mini, maxi), maxi) and eq(math.min(mini, maxi), mini))
assert(eq(math.max(maxi, 2 ^ 63), 2 ^ 63) and eq(math.min(mini, -2 ^ 63), mini))
assert(math.max(-math.huge, math.huge) == math.huge)
assert(isnan(math.max(0 / 0, 1)) and eq(math.max(1, 0 / 0), 1))
assert(isnan(math.min(0 / 0, 1)) and eq(math.min(1, 0 / 0), 1))
-- the arguments are compared and returned as they are
assert(math.max("10", "9") == "9" and math.min("10", "9") == "10")
assert(math.max("3") == "3")
do
  local mt = {__lt = function(a, b) return a.v < b.v end}
  local x, y = setmetatable({v = 1}, mt), setmetatable({v = 2}, mt)
  assert(math.max(x, y) == y and math.min(x, y) == x and math.max(y, x) == y)
end
checkerr("value expected", math.max)
checkerr("value expected", math.min)
checkerr("bad argument #1", math.max)
checkerr("attempt to compare number with string", math.max, 1, "x")
checkerr("attempt to compare number with nil", math.max, 1, nil)
checkerr("attempt to compare string with number", math.max, "3", 2)
checkerr("attempt to compare", math.min, 1, {})

-- float functions -----------------------------------------------------------
assert(eq(math.sqrt(4), 2.0) and eq(math.sqrt(16), 4.0) and eq(math.sqrt(0), 0.0))
assert(eq(math.sqrt("9"), 3.0) and near(math.sqrt(2), 1.4142135623730951))
assert(isnan(math.sqrt(-1)) and math.sqrt(math.huge) == math.huge)
assert(eq(math.sin(0), 0.0) and eq(math.cos(0), 1.0) and eq(math.tan(0), 0.0))
assert(eq(math.asin(0), 0.0) and eq(math.acos(1), 0.0) and eq(math.atan(0), 0.0))
assert(near(math.sin(1), 0.8414709848078965) and near(math.cos(1), 0.5403023058681398))
assert(near(math.tan(1), 1.5574077246549023))
assert(near(math.asin(1), math.pi / 2) and near(math.acos(0), math.pi / 2))
assert(near(math.acos(-1), math.pi))
assert(near(math.atan(1), math.pi / 4) and near(math.atan(1, 1), math.pi / 4))
assert(near(math.atan(1, 2), 0.4636476090008061))
assert(near(math.atan(0, -1), math.pi) and near(math.atan(-0.0, -1), -math.pi))
assert(near(math.atan(1, 0), math.pi / 2) and near(math.atan(-1, 0), -math.pi / 2))
assert(eq(math.atan(0, 1), 0.0) and near(math.atan(math.huge), math.pi / 2))
assert(near(math.atan(1, nil), math.pi / 4))
assert(isnan(math.sin(math.huge)) and isnan(math.asin(2)))
assert(eq(math.exp(0), 1.0) and near(math.exp(1), 2.718281828459045))
assert(math.exp(1000) == math.huge and eq(math.exp(-math.huge), 0.0))
assert(eq(math.log(1), 0.0) and math.log(0) == -math.huge and isnan(math.log(-1)))
assert(near(math.log(10), 2.302585092994046) and near(math.log(math.exp(1)), 1.0))
assert(eq(math.log(8, 2), 3.0) and eq(math.log(1024, 2), 10.0) and eq(math.log(0.5, 2), -1.0))
assert(eq(math.log(8, 2.0), 3.0) and eq(math.log(2 ^ 60, 2), 60.0))
assert(near(math.log(100, 10), 2.0) and near(math.log(1000, 10.0), 3.0))
assert(near(math.log(27, 3), 3.0) and near(math.log(2, 10), 0.3010299956639812))
assert(near(math.log(1024, 4), 5.0) and math.log(2, 1) == math.huge)
assert(near(math.log(10, nil), 2.302585092994046))
assert(math.type(math.log(8, 2)) == "float" and math.type(math.exp(0)) == "float")
assert(eq(math.deg(0), 0.0) and near(math.deg(math.pi), 180.0) and near(math.deg(1), 57.29577951308232))
assert(eq(math.rad(0), 0.0) and near(math.rad(180), math.pi) and near(math.rad(1), 0.017453292519943295))
assert(math.type(math.deg(1)) == "float" and math.type(math.rad(180)) == "float")
checkerr("number expected, got table", math.sin, {})
checkerr("number expected, got no value", math.cos)
checkerr("number expected, got string", math.log, "x")
checkerr("number expected, got string", math.log, 2, "x")
checkerr("number expected, got table", math.atan, 1, {})
checkerr("number expected, got boolean", math.sqrt, true)

-- math.frexp / math.ldexp ---------------------------------------------------
do
  local function frexp(x, m, e)
    local a, b = math.frexp(x)
    assert(eq(a, m) and eq(b, e), "frexp of " .. tostring(x))
  end
  frexp(8, 0.5, 4)
  frexp(0, 0.0, 0)
  frexp(-3.5, -0.875, 2)
  frexp(1, 0.5, 1)
  frexp(0.75, 0.75, 0)
  frexp(math.huge, math.huge, 0)
  frexp(-math.huge, -math.huge, 0)
  frexp(1e-320, 0.98828125, -1063)
  frexp(2 ^ 1023, 0.5, 1024)
  local a, b = math.frexp(0 / 0)
  assert(isnan(a) and eq(b, 0))
  assert(eq(math.ldexp(1, 3), 8.0) and eq(math.ldexp(0.5, 4), 8.0))
  assert(eq(math.ldexp(3, -1), 1.5) and eq(math.ldexp(1, 0), 1.0))
  assert(math.ldexp(1, 2000) == math.huge and eq(math.ldexp(1, -2000), 0.0))
  assert(eq(math.ldexp(1, 1023), 2 ^ 1023) and eq(math.ldexp(1, -1074), 2 ^ -1074))
  assert(eq(math.ldexp("2", "3"), 16.0) and eq(math.ldexp(1, 3.0), 8.0))
  -- the exponent is truncated to a C int
  assert(eq(math.ldexp(1, maxi), 0.5) and eq(math.ldexp(1, mini), 1.0))
  checkerr("number has no integer representation", math.ldexp, 1, 1.5)
  checkerr("number expected, got no value", math.ldexp, 1)
  checkerr("number expected, got no value", math.frexp)
end

-- math.random / math.randomseed ---------------------------------------------
do
  -- the generator (xoshiro256**) and its seeding are fully specified
  local a, b = math.randomseed(42)
  assert(eq(a, 42) and eq(b, 0))
  assert(eq(math.random(1, 100), 50))
  assert(eq(math.random(1, 100), 76))
  assert(eq(math.random(1, 100), 86))
  local f = math.random()
  assert(math.type(f) == "float" and f > 0.617317635958 and f < 0.617317635959)
  assert(eq(math.random(0), 177101407732369983))
  assert(eq(math.random(10), 7))

  a, b = math.randomseed(42, 7)
  assert(eq(a, 42) and eq(b, 7))
  assert(eq(math.random(0), -3100642489518372304))
  assert(eq(math.random(0), -513943613097109053))

  math.randomseed(42.0)
  assert(eq(math.random(0), -1276290044721465627))
  a, b = math.randomseed(-1)
  assert(eq(a, -1) and eq(b, 0))
  assert(eq(math.random(0), -6532212821526904015))
  a, b = math.randomseed("12")
  assert(eq(a, 12) and eq(b, 0))
  assert(eq(math.random(0), 7678946592243300471))

  -- same seed, same sequence
  math.randomseed(1234, 5678)
  local seq = {}
  for i = 1, 20 do seq[i] = math.random(mini, maxi) end
  math.randomseed(1234, 5678)
  for i = 1, 20 do assert(seq[i] == math.random(mini, maxi)) end

  -- a call without arguments seeds "randomly" and returns the two seeds
  local r = table.pack(math.randomseed())
  assert(r.n == 2 and math.type(r[1]) == "integer" and math.type(r[2]) == "integer")
  local first = math.random(0)
  math.randomseed(r[1], r[2])
  assert(math.random(0) == first)

  -- ranges
  for _ = 1, 200 do
    local x = math.random()
    assert(math.type(x) == "float" and x >= 0 and x < 1)
    x = math.random(10)
    assert(math.type(x) == "integer" and x >= 1 and x <= 10)
    x = math.random(-5, 5)
    assert(math.type(x) == "integer" and x >= -5 and x <= 5)
    x = math.random(maxi - 3, maxi)
    assert(x >= maxi - 3 and x <= maxi)
    x = math.random(mini, mini + 3)
    assert(x >= mini and x <= mini + 3)
    assert(math.type(math.random(0)) == "integer")
    assert(math.type(math.random(mini, maxi)) == "integer")
  end
  assert(eq(math.random(3, 3), 3) and eq(math.random(maxi, maxi), maxi))
  assert(eq(math.random(mini, mini), mini) and eq(math.random(1), 1))
  assert(math.type(math.random(3.0)) == "integer")
  assert(math.type(math.random(2.0, 4.0)) == "integer")
  local seen = {}
  for _ = 1, 300 do seen[math.random(3)] = true end
  assert(seen[1] and seen[2] and seen[3])

  checkerr("wrong number of arguments", math.random, 0, 1, 2)
  checkerr("interval is empty", math.random, 2, 1)
  checkerr("interval is empty", math.random, -1)
  checkerr("interval is empty", math.random, maxi, mini)
  checkerr("number has no integer representation", math.random, 0.5)
  checkerr("number has no integer representation", math.random, 1, 2.5)
  checkerr("number expected, got string", math.random, "x")
  checkerr("number has no integer representation", math.randomseed, 42.5)
  checkerr("number has no integer representation", math.randomseed, 2 ^ 63)
  checkerr("number expected, got string", math.randomseed, "x")
  checkerr("number has no integer representation", math.randomseed, 1, 2.5)
end

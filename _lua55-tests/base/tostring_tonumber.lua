-- tostring, tonumber and print in the Lua 5.5 profile.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

-- tostring: integers and floats keep their subtype
assert(tostring(1) == "1")
assert(tostring(1.0) == "1.0")
assert(tostring(-0.0) == "-0.0")
assert(tostring(100) == "100")
assert(tostring(12.5) == "12.5")
assert(tostring(0.1) == "0.1")
assert(tostring(1e15) == "1e+15")
assert(tostring(1e100) == "1e+100")
assert(tostring(-1e-7) == "-1e-07")
assert(tostring(2^31) == "2147483648.0")
assert(tostring(2^53) == "9007199254740992.0")
assert(tostring(2^63) == "9.2233720368547758e+18")
assert(tostring(123456789012345678) == "123456789012345678")
assert(tostring(9223372036854775807) == "9223372036854775807")
assert(tostring(-9223372036854775807 - 1) == "-9223372036854775808")
assert(tostring(3.14159265358979) == "3.14159265358979")
assert(tostring(1/0) == "inf" and tostring(-1/0) == "-inf")
assert(tostring(1e300 * 1e10) == "inf")
assert(tostring(3 / 2) == "1.5" and tostring(4 / 2) == "2.0" and tostring(7 // 2) == "3")

-- tostring: other types
assert(tostring(nil) == "nil")
assert(tostring(true) == "true" and tostring(false) == "false")
assert(tostring("s") == "s")
assert(tostring({}):find("^table: ") == 1)
assert(tostring(print):find("^function: ") == 1)
assert(tostring(coroutine.create(print)):find("^thread: ") == 1)
checkerr("value expected", tostring)
assert(select("#", tostring(nil, 2)) == 1)

-- tostring: metamethods
assert(tostring(setmetatable({}, {__tostring = function() return "X" end})) == "X")
local obj = setmetatable({v = 7}, {__tostring = function(self) return "v=" .. self.v end})
assert(tostring(obj) == "v=7")
checkerr("'__tostring' must return a string", tostring, setmetatable({}, {__tostring = function() return {} end}))
checkerr("'__tostring' must return a string", tostring, setmetatable({}, {__tostring = function() return nil end}))
assert(tostring(setmetatable({}, {__name = "MyType"})):find("^MyType: ") == 1)
assert(tostring(setmetatable({}, {__name = 5})):find("^table: ") == 1)
-- __tostring wins over __name
assert(tostring(setmetatable({}, {__name = "N", __tostring = function() return "T" end})) == "T")

-- tonumber: numbers are returned unchanged
assert(tostring(tonumber(5)) == "5" and tostring(tonumber(5.5)) == "5.5" and tostring(tonumber(5.0)) == "5.0")

-- tonumber: decimal strings convert to integers or floats
assert(tostring(tonumber("10")) == "10")
assert(tostring(tonumber("10.0")) == "10.0")
assert(tostring(tonumber("  12  ")) == "12")
assert(tostring(tonumber("\t\n\v\f\r 5 \t\n\v\f\r")) == "5")
assert(tostring(tonumber("1e2")) == "100.0")
assert(tostring(tonumber("1e5")) == "100000.0")
assert(tostring(tonumber(".5")) == "0.5")
assert(tostring(tonumber("5.")) == "5.0")
assert(tostring(tonumber("-.5e-2")) == "-0.005")
assert(tostring(tonumber("+7")) == "7" and tostring(tonumber("-7")) == "-7")
assert(tostring(tonumber("9223372036854775807")) == "9223372036854775807")
assert(tostring(tonumber("-9223372036854775808")) == "-9223372036854775808")
-- decimal integers that do not fit become floats
assert(tostring(tonumber("9223372036854775808")) == "9.2233720368547758e+18")
assert(tostring(tonumber("-9223372036854775809")) == "-9.2233720368547758e+18")
assert(tostring(tonumber("1" .. ("0"):rep(30))) == "1e+30")

-- tonumber: hexadecimal strings
assert(tostring(tonumber("0x10")) == "16")
assert(tostring(tonumber("0X1f")) == "31")
assert(tostring(tonumber("-0x10")) == "-16")
assert(tostring(tonumber("0x7fffffffffffffff")) == "9223372036854775807")
assert(tostring(tonumber("0xffffffffffffffff")) == "-1")   -- wraps around
assert(tostring(tonumber("0x1p4")) == "16.0")
assert(tostring(tonumber("0x1.8p1")) == "3.0")
assert(tostring(tonumber("0x.1")) == "0.0625")
assert(tostring(tonumber(" 0x1p-2 ")) == "0.25")

-- tonumber: rejects
for _, s in ipairs({"", " ", "1 2", "abc", "1e", "1e+", "0x", ".", "- 1", "--5", "5-", "inf", "nan",
                    "1_000", "5\0", "0x1g", "1.2.3", "1,5"}) do
  assert(tonumber(s) == nil, "tonumber should reject '" .. s .. "'")
end
assert(tonumber(nil) == nil)
assert(tonumber({}) == nil and tonumber(true) == nil and tonumber(print) == nil)
checkerr("value expected", tonumber)

-- tonumber with a base
assert(tostring(tonumber("10", 2)) == "2")
assert(tostring(tonumber("ff", 16)) == "255")
assert(tostring(tonumber("FF", 16)) == "255")
assert(tostring(tonumber("zz", 36)) == "1295")
assert(tostring(tonumber("Zz", 36)) == "1295")
assert(tostring(tonumber("-ff", 16)) == "-255")
assert(tostring(tonumber("+5", 10)) == "5")
assert(tostring(tonumber("  -7  ", 8)) == "-7")
assert(tostring(tonumber("\n5\n", 10)) == "5")
assert(tostring(tonumber(" 11 ", 2)) == "3")
assert(tostring(tonumber("7", 10.0)) == "7")
assert(tostring(tonumber("10", 16)) == "16")
assert(tostring(tonumber("8", 9)) == "8")
assert(tostring(tonumber("7fffffffffffffff", 16)) == "9223372036854775807")
assert(tostring(tonumber("ffffffffffffffff", 16)) == "-1")
assert(tostring(tonumber("10000000000000000", 16)) == "0")
for _, case in ipairs({{"8", 8}, {"1.5", 10}, {"", 10}, {"1e1", 10}, {"1 1", 2}, {"-", 10}, {"--5", 10},
                       {"5-", 10}, {"0x10", 16}, {"1e", 10}, {"9", 9}, {"2", 2}, {"g", 16}}) do
  assert(tonumber(case[1], case[2]) == nil, "tonumber('" .. case[1] .. "', " .. case[2] .. ") should fail")
end
assert(tostring(tonumber("1e", 16)) == "30")
checkerr("base out of range", tonumber, "10", 1)
checkerr("base out of range", tonumber, "10", 37)
checkerr("string expected, got number", tonumber, 10, 10)
checkerr("string expected, got nil", tonumber, nil, 10)
checkerr("string expected, got table", tonumber, {}, 10)
checkerr("string expected, got boolean", tonumber, true, 10)
checkerr("number has no integer representation", tonumber, "z", 36.5)
checkerr("number expected, got string", tonumber, "10", "x")

-- print accepts any values and uses __tostring
print()
print(1, 1.0, "a", nil, true, -0.0, 1e100)
print(setmetatable({}, {__tostring = function() return "printed through __tostring" end}))
checkerr("'__tostring' must return a string", print, setmetatable({}, {__tostring = function() return {} end}))

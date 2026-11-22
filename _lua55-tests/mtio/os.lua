-- Lua 5.5 os library conformance checks.
-- Every assertion holds for the reference interpreter (lua5.5) as well.
-- The checks do not depend on the local time zone or locale: fixed dates
-- use UTC ("!" formats), local times are only checked for consistency.

local function checkerr(msg, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. msg)
  assert(string.find(tostring(err), msg, 1, true),
    "unexpected error message: " .. tostring(err))
end

local function eq(a, b)
  return a == b and math.type(a) == math.type(b)
end

local function isint(x) return math.type(x) == "integer" end

local maxi, mini = math.maxinteger, math.mininteger
local DAY = 86400

-- contents of the library ---------------------------------------------------
do
  local expected = {clock = 1, date = 1, difftime = 1, execute = 1, exit = 1,
    getenv = 1, remove = 1, rename = 1, setlocale = 1, time = 1, tmpname = 1}
  for k, v in pairs(os) do
    assert(expected[k] and type(v) == "function", "unexpected os." .. tostring(k))
    expected[k] = nil
  end
  assert(next(expected) == nil)
end

-- os.clock / os.difftime / os.getenv ----------------------------------------
do
  local c = os.clock()
  assert(math.type(c) == "float" and c >= 0)
  assert(os.clock() >= c)

  assert(eq(os.difftime(5, 3), 2.0) and eq(os.difftime(3, 5), -2.0))
  assert(eq(os.difftime(5.0, 2), 3.0) and eq(os.difftime("7", "3"), 4.0))
  assert(eq(os.difftime(0, 0), 0.0))
  local now = os.time()
  assert(eq(os.difftime(now + 60, now), 60.0))
  checkerr("number expected, got no value", os.difftime)
  checkerr("bad argument #2", os.difftime, 5)
  checkerr("number has no integer representation", os.difftime, 1.5, 1)
  checkerr("number expected, got string", os.difftime, "a", 1)

  assert(os.getenv("GOPHER_LUA_SURELY_NOT_SET_VARIABLE") == nil)
  local path = os.getenv("PATH")
  assert(path == nil or type(path) == "string")
  checkerr("string expected, got no value", os.getenv)
  checkerr("string expected, got table", os.getenv, {})
end

-- os.time without arguments -------------------------------------------------
do
  local t = os.time()
  assert(isint(t) and t > 1700000000)
  assert(isint(os.time(nil)))
  assert(table.pack(os.time()).n == 1)
  local t2 = os.time()
  assert(t2 >= t and t2 - t < 60)
end

-- os.date: fixed UTC dates --------------------------------------------------
do
  assert(os.date("!%Y-%m-%d %H:%M:%S", 0) == "1970-01-01 00:00:00")
  assert(os.date("!%c", 0) == "Thu Jan  1 00:00:00 1970")
  assert(os.date("!%x %X", 0) == "01/01/70 00:00:00")
  assert(os.date("!%Y-%m-%d", -DAY) == "1969-12-31")
  assert(os.date("!%Y-%m-%d %H:%M:%S", 1e9 // 1) == "2001-09-09 01:46:40")
  assert(os.date("!%Y-%m-%d %H:%M:%S", 2 ^ 31) == "2038-01-19 03:14:08")
  assert(os.date("!%Y", "86400") == "1970")
  assert(os.date("!%Y", 2 ^ 40) == "36812")
  assert(os.date("!%Y", 253402300800) == "10000")
  assert(os.date("!%Y-%m-%d", 951782400) == "2000-02-29")
  assert(os.date("!%Y-%m-%d %j", 4107542400) == "2100-03-01 060") -- 2100 is not a leap year

  local t = DAY * 200 + 3661 -- Mon Jul 20 01:01:01 1970
  assert(os.date("!%a|%A|%b|%B|%h", t) == "Mon|Monday|Jul|July|Jul")
  assert(os.date("!%d|%e|%j|%m|%y|%Y|%C", t) == "20|20|201|07|70|1970|19")
  assert(os.date("!%H|%I|%M|%S|%p", t) == "01|01|01|01|AM")
  assert(os.date("!%D|%F|%R|%T|%r", t) == "07/20/70|1970-07-20|01:01|01:01:01|01:01:01 AM")
  assert(os.date("!%u|%w|%U|%W|%V|%G|%g", t) == "1|1|29|29|30|1970|70")
  assert(os.date("!%n|%t|%%", t) == "\n|\t|%")
  assert(os.date("!%c", t) == "Mon Jul 20 01:01:01 1970")
  -- E and O modifiers
  assert(os.date("!%Ec|%EC|%Ex|%EX|%Ey|%EY", t) == "Mon Jul 20 01:01:01 1970|19|07/20/70|01:01:01|70|1970")
  assert(os.date("!%Od|%Oe|%OH|%OI|%Om|%OM|%OS|%Ou|%OU|%OV|%Ow|%OW|%Oy", t) == "20|20|01|01|07|01|01|1|29|30|1|29|70")
  -- single digit day, 12-hour clock
  t = DAY * 4 + 13 * 3600 + 5 * 60 + 9 -- Mon Jan 5 13:05:09 1970
  assert(os.date("!%e|%d|%I|%p|%H|%r", t) == " 5|05|01|PM|13|01:05:09 PM")
  assert(os.date("!%c", t) == "Mon Jan  5 13:05:09 1970")
  assert(os.date("!%I %p", 0) == "12 AM" and os.date("!%I %p", 12 * 3600) == "12 PM")
  assert(os.date("!%I %p", 23 * 3600) == "11 PM")

  -- week numbers around new year
  local function weeks(day) return os.date("!%Y-%m-%d %a %j U%U W%W V%V G%G g%g u%u w%w", day * DAY) end
  assert(weeks(0) == "1970-01-01 Thu 001 U00 W00 V01 G1970 g70 u4 w4")
  assert(weeks(3) == "1970-01-04 Sun 004 U01 W00 V01 G1970 g70 u7 w0")
  assert(weeks(4) == "1970-01-05 Mon 005 U01 W01 V02 G1970 g70 u1 w1")
  assert(weeks(364) == "1970-12-31 Thu 365 U52 W52 V53 G1970 g70 u4 w4")
  assert(weeks(365) == "1971-01-01 Fri 001 U00 W00 V53 G1970 g70 u5 w5")
  assert(weeks(367) == "1971-01-03 Sun 003 U01 W00 V53 G1970 g70 u7 w0")
  assert(weeks(368) == "1971-01-04 Mon 004 U01 W01 V01 G1971 g71 u1 w1")
  assert(weeks(730) == "1972-01-01 Sat 001 U00 W00 V52 G1971 g71 u6 w6")
  assert(weeks(732) == "1972-01-03 Mon 003 U01 W01 V01 G1972 g72 u1 w1")
  assert(weeks(1095) == "1972-12-31 Sun 366 U53 W52 V52 G1972 g72 u7 w0")
  assert(weeks(1096) == "1973-01-01 Mon 001 U00 W01 V01 G1973 g73 u1 w1")
  assert(weeks(1102) == "1973-01-07 Sun 007 U01 W01 V01 G1973 g73 u7 w0")

  -- plain text, embedded zeros, empty formats
  assert(os.date("!", 0) == "" and os.date("", 0) == "")
  assert(os.date("!plain text", 0) == "plain text")
  assert(os.date("!%H%%%M", 3600) == "01%00")
  assert(os.date("!%Y\0%Y", 0) == "1970\0001970")
  assert(os.date("!!%Y", 0) == "!1970")
  assert(os.date("!*", 0) == "*" and os.date("!*tx", 0) == "*tx")
  assert(os.date(5, 0) == "5") -- numbers are converted to strings
  assert(os.date("!%Y", 0.0) == "1970")
end

-- os.date: tables -----------------------------------------------------------
do
  local t = os.date("!*t", DAY * 200 + 3661)
  assert(eq(t.year, 1970) and eq(t.month, 7) and eq(t.day, 20))
  assert(eq(t.hour, 1) and eq(t.min, 1) and eq(t.sec, 1))
  assert(eq(t.wday, 2) and eq(t.yday, 201) and t.isdst == false)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  assert(n == 9)
  t = os.date("!*t", 1e9 // 1)
  assert(t.year == 2001 and t.month == 9 and t.day == 9 and t.hour == 1 and t.min == 46)
  assert(t.sec == 40 and t.wday == 1 and t.yday == 252 and t.isdst == false)
  t = os.date("!*t", 0)
  assert(t.year == 1970 and t.month == 1 and t.day == 1 and t.wday == 5 and t.yday == 1)
  t = os.date("!*t", -1)
  assert(t.year == 1969 and t.month == 12 and t.day == 31 and t.hour == 23 and t.sec == 59)
  assert(t.yday == 365 and t.wday == 4)

  t = os.date("*t")
  assert(isint(t.year) and t.year >= 2024 and type(t.isdst) == "boolean")
  assert(t.month >= 1 and t.month <= 12 and t.day >= 1 and t.day <= 31)
  assert(t.hour >= 0 and t.hour <= 23 and t.wday >= 1 and t.wday <= 7)
  assert(t.yday >= 1 and t.yday <= 366)

  -- default format and default time
  assert(type(os.date()) == "string" and #os.date() == 24)
  assert(#os.date("%c") == 24 and os.date("!%c", nil) ~= nil)
  local y = os.date("!%Y")
  assert(#y == 4 and y >= "2024")
end

-- os.date: errors -----------------------------------------------------------
do
  checkerr("invalid conversion specifier '%Q'", os.date, "%Q")
  checkerr("bad argument #1", os.date, "%Q")
  checkerr("invalid conversion specifier '%E'", os.date, "%E")
  checkerr("invalid conversion specifier '%Ez'", os.date, "%Ez")
  checkerr("invalid conversion specifier '%O'", os.date, "%O")
  checkerr("invalid conversion specifier '%Ob'", os.date, "%Ob")
  checkerr("invalid conversion specifier '%'", os.date, "%")
  checkerr("invalid conversion specifier '%'", os.date, "abc%")
  checkerr("invalid conversion specifier '%Qabc'", os.date, "%Qabc")
  checkerr("invalid conversion specifier '%Ez%Y'", os.date, "x%Ez%Y")
  for _, c in ipairs({"k", "l", "P", "+", "v", "s", "f", "i", "J", "K", "L", "N", "o", "q", "1", " ", "E%", "O%"}) do
    checkerr("invalid conversion specifier '%" .. c, os.date, "%" .. c)
  end
  checkerr("number has no integer representation", os.date, "!*t", 1.5)
  checkerr("number expected, got string", os.date, "*t", "x")
  checkerr("bad argument #2", os.date, "*t", "x")
  checkerr("string expected, got table", os.date, {})
  checkerr("date result cannot be represented in this installation", os.date, "!%Y", maxi)
  checkerr("date result cannot be represented in this installation", os.date, "!%Y", mini)
  checkerr("date result cannot be represented in this installation", os.date, "*t", 2 ^ 60)
  checkerr("date result cannot be represented in this installation", os.date, "!*t", 2 ^ 60)
  checkerr("date result cannot be represented in this installation", os.date, "!%Y", 2 ^ 56)
  checkerr("date result cannot be represented in this installation", os.date, "!%Y", 67768036191676800)
  -- the largest and smallest representable years
  assert(os.date("!%Y", 2 ^ 55) == "1141709097")
  assert(os.date("!%Y", 67767976233532799) == "2147483647")
  assert(os.date("!%Y-%m-%d %H:%M:%S", 67768036191676799) == "2147485547-12-31 23:59:59")
  assert(os.date("!*t", 67768036191676799).year == 2147485547)
end

-- os.time with a table ------------------------------------------------------
do
  -- round trips through local time
  local now = os.time()
  local d = os.date("*t", now)
  assert(os.time(d) == now)
  for _, t in ipairs({0, 1e9 // 1, 1234567890, 2 ^ 31, 951782400, now - 180 * DAY, now + 180 * DAY}) do
    assert(os.time(os.date("*t", t)) == t)
  end

  -- the default hour is 12:00:00
  local t1 = os.time({year = 2021, month = 6, day = 15})
  local t2 = os.time({year = 2021, month = 6, day = 15, hour = 12, min = 0, sec = 0})
  assert(isint(t1) and t1 == t2)
  local t3 = os.time({year = 2021, month = 6, day = 15, hour = 13})
  assert(t3 - t1 == 3600)
  assert(os.time({year = 2021, month = 6, day = 15, hour = 12, min = 1, sec = 1}) - t1 == 61)

  -- fields are normalized and written back
  local t = {year = 2021, month = 14, day = 35, hour = 12, min = 61, sec = 61}
  local r = os.time(t)
  assert(isint(r))
  assert(eq(t.year, 2022) and eq(t.month, 3) and eq(t.day, 7))
  assert(eq(t.hour, 13) and eq(t.min, 2) and eq(t.sec, 1))
  assert(eq(t.wday, 2) and eq(t.yday, 66) and type(t.isdst) == "boolean")
  assert(os.time(t) == r)

  t = {year = 2021, month = 3, day = 0, hour = 12}
  os.time(t)
  assert(t.year == 2021 and t.month == 2 and t.day == 28 and t.hour == 12)
  assert(t.min == 0 and t.sec == 0 and t.wday == 1 and t.yday == 59)
  t = {year = 2021, month = 1, day = 1}
  os.time(t)
  assert(t.hour == 12 and t.min == 0 and t.sec == 0 and t.wday == 6 and t.yday == 1)
  t = {year = 2020, month = 12, day = 31, hour = 12, sec = DAY}
  os.time(t)
  assert(t.year == 2021 and t.month == 1 and t.day == 1 and t.hour == 12)
  t = {year = 2021, month = 0, day = 1}
  os.time(t)
  assert(t.year == 2020 and t.month == 12 and t.day == 1)
  t = {year = 2021, month = -11, day = 15}
  os.time(t)
  assert(t.year == 2020 and t.month == 1 and t.day == 15)
  t = {year = 2021, month = 7, day = 15, hour = 12, min = -1}
  os.time(t)
  assert(t.hour == 11 and t.min == 59)
  t = {year = 2020, month = 2, day = 30}
  os.time(t)
  assert(t.month == 3 and t.day == 1 and t.yday == 61) -- leap year

  -- numeric strings and integral floats are accepted
  assert(os.time({year = "2021", month = "6", day = "15"}) == t1)
  assert(os.time({year = 2021.0, month = 6.0, day = 15.0}) == t1)
  -- extra fields are ignored; __index is honored
  assert(os.time({year = 2021, month = 6, day = 15, wday = 99, yday = -1, foo = "x"}) == t1)
  local proxy = setmetatable({}, {__index = function(_, k)
    return ({year = 2021, month = 6, day = 15})[k]
  end})
  assert(os.time(proxy) == t1)
  assert(rawget(proxy, "year") == 2021 and rawget(proxy, "yday") == 166)

  -- differences between days do not depend on the zone (same local hour,
  -- no daylight saving change in between: UTC arithmetic via os.date)
  local base = os.time({year = 2021, month = 1, day = 10, hour = 12})
  assert(os.date("%Y-%m-%d %H:%M:%S", base) == "2021-01-10 12:00:00")
  assert(os.date("%Y-%m-%d %H", os.time({year = 2000, month = 2, day = 29, hour = 5})) == "2000-02-29 05")
  local far = os.time({year = 3000, month = 1, day = 1})
  assert(os.date("%Y-%m-%d %H", far) == "3000-01-01 12")
  local million = os.time({year = 1000000, month = 1, day = 1})
  assert(os.date("%Y", million) == "1000000")
  assert(os.date("%Y", os.time({year = 2000000000, month = 1, day = 1})) == "2000000000")

  -- errors
  checkerr("field 'year' missing in date table", os.time, {})
  checkerr("field 'month' missing in date table", os.time, {year = 2020})
  checkerr("field 'day' missing in date table", os.time, {year = 2020, month = 1})
  checkerr("field 'day' is not an integer", os.time, {year = 2020, month = 1, day = "x"})
  checkerr("field 'month' is not an integer", os.time, {year = 2020, month = 1.5, day = 1})
  checkerr("field 'hour' is not an integer", os.time, {year = 2020, month = 1, day = 1, hour = {}})
  checkerr("field 'min' is not an integer", os.time, {year = 2020, month = 1, day = 1, min = true})
  checkerr("field 'sec' is not an integer", os.time, {year = 2020, month = 1, day = 1, sec = "1.5"})
  checkerr("field 'year' is not an integer", os.time, {year = 2 ^ 63, month = 1, day = 1})
  checkerr("field 'year' is out-of-bound", os.time, {year = 2 ^ 40, month = 1, day = 1})
  checkerr("field 'year' is out-of-bound", os.time, {year = maxi, month = 1, day = 1})
  checkerr("field 'year' is out-of-bound", os.time, {year = mini, month = 1, day = 1})
  checkerr("field 'year' is out-of-bound", os.time, {year = 2 ^ 31 + 1900, month = 1, day = 1})
  checkerr("field 'year' is out-of-bound", os.time, {year = -2 ^ 31 + 1899, month = 1, day = 1})
  checkerr("field 'month' is out-of-bound", os.time, {year = 2020, month = 2 ^ 40, day = 1})
  checkerr("field 'month' is out-of-bound", os.time, {year = 2020, month = mini, day = 1})
  checkerr("field 'month' is out-of-bound", os.time, {year = 2020, month = -2 ^ 31, day = 1})
  checkerr("field 'month' is out-of-bound", os.time, {year = 2020, month = 2 ^ 31 + 1, day = 1})
  checkerr("field 'day' is out-of-bound", os.time, {year = 2020, month = 1, day = 2 ^ 31})
  checkerr("field 'day' is out-of-bound", os.time, {year = 2020, month = 1, day = -2 ^ 31 - 1})
  checkerr("field 'sec' is out-of-bound", os.time, {year = 2020, month = 1, day = 1, sec = 2 ^ 31})
  checkerr("field 'hour' is out-of-bound", os.time, {year = 2020, month = 1, day = 1, hour = 2 ^ 31})
  checkerr("field 'min' is out-of-bound", os.time, {year = 2020, month = 1, day = 1, min = -2 ^ 31 - 1})
  checkerr("table expected, got number", os.time, 5)
  checkerr("table expected, got string", os.time, "x")
  -- the limits of the fields
  assert(isint(os.time({year = 2 ^ 31 + 1899, month = 1, day = 1})))
  assert(isint(os.time({year = 2020, month = 2 ^ 31, day = 1})))
  assert(isint(os.time({year = 2020, month = 1, day = 2 ^ 31 - 1})))
  assert(isint(os.time({year = 2020, month = 1, day = 1, sec = 2 ^ 31 - 1})))
  t = {year = 2020, month = 1, day = 2 ^ 31 - 1}
  os.time(t)
  assert(t.year == 5881630 and t.month == 7 and t.day == 10)
end

-- os.tmpname / os.remove / os.rename ----------------------------------------
do
  local name = os.tmpname()
  assert(type(name) == "string" and #name > 0)
  local second = os.tmpname()
  assert(second ~= name) -- names are unique
  assert(os.remove(second) == true)
  -- the POSIX implementation creates the file
  local f = io.open(name, "w")
  assert(f)
  f:write("content")
  f:close()

  local other = name .. ".renamed"
  assert(os.rename(name, other) == true)
  assert(io.open(name) == nil)
  f = assert(io.open(other))
  assert(f:read("a") == "content")
  f:close()
  local r = table.pack(os.rename(name, other))
  assert(r.n == 3 and r[1] == nil and type(r[2]) == "string" and math.type(r[3]) == "integer" and r[3] ~= 0)
  assert(table.pack(os.remove(other)).n == 1)
  r = table.pack(os.remove(other))
  assert(r.n == 3 and r[1] == nil and math.type(r[3]) == "integer" and r[3] ~= 0)
  -- the message of os.remove starts with the file name
  assert(string.sub(r[2], 1, #other + 2) == other .. ": ")
  -- the message of os.rename does not
  r = table.pack(os.rename(other, name))
  assert(r.n == 3 and r[1] == nil and string.sub(r[2], 1, #other) ~= other)

  -- numbers are accepted as file names
  r = table.pack(os.remove(123456789012))
  assert(r[1] == nil and string.sub(r[2], 1, 14) == "123456789012: ")

  checkerr("string expected, got no value", os.remove)
  checkerr("string expected, got no value", os.rename, "a")
  checkerr("bad argument #2", os.rename, "a")
  checkerr("string expected, got table", os.remove, {})
end

-- os.execute ----------------------------------------------------------------
do
  assert(os.execute() == true) -- a shell is available
  assert(os.execute(nil) == true)
  local function exec(cmd)
    local r = table.pack(os.execute(cmd))
    assert(r.n == 3)
    return r[1], r[2], r[3]
  end
  local a, b, c = exec("true")
  assert(a == true and b == "exit" and eq(c, 0))
  a, b, c = exec("false")
  assert(a == nil and b == "exit" and eq(c, 1))
  a, b, c = exec("exit 3")
  assert(a == nil and b == "exit" and eq(c, 3))
  a, b, c = exec("exit 0")
  assert(a == true and b == "exit" and eq(c, 0))
  a, b, c = exec("kill -9 $$")
  assert(a == nil and b == "signal" and eq(c, 9))
  a, b, c = exec("kill -15 $$")
  assert(a == nil and b == "signal" and eq(c, 15))
  a, b, c = exec("gopher_lua_surely_no_such_command 2>/dev/null")
  assert(a == nil and b == "exit" and eq(c, 127))
  -- the command runs in a shell and sees the environment
  local name = os.tmpname()
  a, b, c = exec("echo from-shell > '" .. name .. "'")
  assert(a == true and c == 0)
  local f = assert(io.open(name))
  assert(f:read("a") == "from-shell\n")
  f:close()
  assert(os.remove(name))
  checkerr("string expected, got table", os.execute, {})
end

-- os.setlocale --------------------------------------------------------------
do
  assert(os.setlocale() == "C" and os.setlocale(nil) == "C")
  assert(os.setlocale("C") == "C" and os.setlocale(nil, "all") == "C")
  for _, cat in ipairs({"all", "collate", "ctype", "monetary", "numeric", "time"}) do
    assert(os.setlocale(nil, cat) == "C")
    assert(os.setlocale("C", cat) == "C")
  end
  assert(os.setlocale("gopher_lua_no_such_locale") == nil)
  assert(os.setlocale("gopher_lua_no_such_locale", "numeric") == nil)
  assert(os.setlocale() == "C")
  -- "POSIX" is an alias of "C" (C libraries differ in the name they report)
  local posix = os.setlocale("POSIX")
  assert(posix == "POSIX" or posix == "C")
  assert(os.setlocale(nil, "numeric") == posix)
  assert(os.setlocale("C") == "C" and os.setlocale(nil, "time") == "C")
  checkerr("invalid option 'bad'", os.setlocale, "C", "bad")
  checkerr("bad argument #2", os.setlocale, "C", "bad")
  checkerr("invalid option '2'", os.setlocale, 1, 2)
  checkerr("string expected, got table", os.setlocale, {})
end

-- os.exit: only the argument checks (the function would end the process) ----
do
  checkerr("number expected, got string", os.exit, "x")
  checkerr("number has no integer representation", os.exit, 1.5)
  checkerr("number expected, got table", os.exit, {})
end

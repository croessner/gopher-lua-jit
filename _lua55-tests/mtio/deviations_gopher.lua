-- Intentional deviations of the math/table/os/io libraries from the
-- reference interpreter (lua5.5). This script only runs under GopherLua.

local function checkerr(msg, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. msg)
  assert(string.find(tostring(err), msg, 1, true),
    "unexpected error message: " .. tostring(err))
end

local name = os.tmpname()

-- table.unpack: the number of results is bounded by the size of the value
-- stack (the registry) of the state, 5120 slots unless Options.RegistrySize
-- or Options.RegistryMaxSize say otherwise. The reference interpreter
-- accepts up to about one million results.
do
  local t = {}
  for i = 1, 3000 do t[i] = i end
  assert(table.pack(table.unpack(t)).n == 3000)
  checkerr("too many results to unpack", table.unpack, {}, 1, 100000)
end

-- os.time: a result whose year does not fit a C int is always rejected.
-- With the reference interpreter this depends on the C library and even
-- on the time zone (macOS accepts it in zones without daylight saving).
checkerr("time result cannot be represented in this installation", os.time,
  {year = 2 ^ 31 + 1899, month = 12, day = 31, hour = 23, min = 59, sec = 2 ^ 31 - 1})
checkerr("time result cannot be represented in this installation", os.time,
  {year = 2 ^ 31 + 1899, month = 2 ^ 31, day = 1})

-- os.time: dates before 1900 work. The reference interpreter fails on
-- macOS ("time result cannot be represented"), but works with glibc.
do
  local t = os.time({year = 1800, month = 6, day = 15})
  assert(math.type(t) == "integer" and t < 0)
  assert(os.date("%Y-%m-%d %H", t) == "1800-06-15 12")
  assert(os.time({year = 1, month = 1, day = 1}) < t)
end

-- os.date: "%z" of a UTC time is "+0000". The reference interpreter on
-- macOS reports the offset of the local zone instead (glibc: "+0000").
assert(os.date("!%z", 0) == "+0000")

-- os.setlocale: only the "C" locale exists; "POSIX" is accepted as an
-- alias and reported under that name, the empty string selects "C".
assert(os.setlocale("") == "C" and os.setlocale("POSIX") == "POSIX")
assert(os.setlocale("C") == "C")

-- file:read(n) with a huge count simply reads what is there. The
-- reference interpreter first allocates a buffer of that size and raises
-- "not enough memory".
do
  local f = assert(io.open(name, "w"))
  f:write("0123456789")
  f:close()
  f = assert(io.open(name))
  assert(f:read(2 ^ 62) == "0123456789")
  f:close()
end

-- Update mode: a write directly after a read (without the intervening
-- seek that C requires) goes to the logical position. This is undefined
-- behavior in C; the reference interpreter on macOS appends "AB" to the
-- end of the file instead.
do
  local f = assert(io.open(name, "r+"))
  assert(f:read(2) == "01")
  assert(f:write("AB") == f)
  assert(f:seek("set") == 0 and f:read("a") == "01AB456789")
  f:close()
end

assert(os.remove(name))

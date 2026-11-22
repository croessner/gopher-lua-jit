-- Lua 5.5 io library conformance checks: files, reading, writing, seeking,
-- default files, processes and the file metatable.
-- Every assertion holds for the reference interpreter (lua5.5) as well.
-- All files live under temporary names and are removed at the end.

local function checkerr(msg, f, ...)
  local ok, err = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. msg)
  assert(string.find(tostring(err), msg, 1, true),
    "unexpected error message: " .. tostring(err))
end

local function eq(a, b)
  return a == b and math.type(a) == math.type(b)
end

-- fails checks the (nil, message, errno) triple of a failed operation.
local function fails(msg, errno, ...)
  local r = table.pack(...)
  assert(r[1] == nil, "expected a failure")
  assert(type(r[2]) == "string" and (msg == nil or string.find(r[2], msg, 1, true)),
    "unexpected message: " .. tostring(r[2]))
  assert(math.type(r[3]) == "integer" and (errno == nil or r[3] == errno),
    "unexpected errno: " .. tostring(r[3]))
  return r
end

local name = os.tmpname()
local other = os.tmpname()

local function writefile(content, mode)
  local f = assert(io.open(name, mode or "w"))
  assert(f:write(content) == f)
  assert(f:close() == true)
end

local function readfile()
  local f = assert(io.open(name, "rb"))
  local s = f:read("a")
  f:close()
  return s
end

-- contents of the library ---------------------------------------------------
do
  local expected = {close = "function", flush = "function", input = "function",
    lines = "function", open = "function", output = "function",
    popen = "function", read = "function", stderr = "userdata",
    stdin = "userdata", stdout = "userdata", tmpfile = "function",
    type = "function", write = "function"}
  for k, v in pairs(io) do
    assert(expected[k] == type(v), "unexpected io." .. tostring(k))
    expected[k] = nil
  end
  assert(next(expected) == nil)
end

-- the file metatable --------------------------------------------------------
do
  local mt = getmetatable(io.stdout)
  assert(mt.__name == "FILE*")
  assert(type(mt.__index) == "table" and mt.__index ~= mt)
  assert(type(mt.__gc) == "function" and type(mt.__close) == "function")
  assert(type(mt.__tostring) == "function")
  local methods = {close = 1, flush = 1, lines = 1, read = 1, seek = 1, setvbuf = 1, write = 1}
  for k, v in pairs(mt.__index) do
    assert(methods[k] and type(v) == "function", "unexpected method " .. tostring(k))
    methods[k] = nil
  end
  assert(next(methods) == nil)
  assert(getmetatable(io.stdin) == mt and getmetatable(io.stderr) == mt)
  assert(io.stdout.write == mt.__index.write and io.stdout.nothing == nil)

  local f = assert(io.open(name, "w"))
  assert(getmetatable(f) == mt)
  local s = tostring(f)
  assert(string.sub(s, 1, 6) == "file (" and string.sub(s, -1) == ")" and s ~= "file (closed)")
  assert(tostring(f) == s and tostring(io.stdout) ~= tostring(io.stderr))
  assert(io.type(f) == "file")
  assert(f:close() == true)
  assert(tostring(f) == "file (closed)" and io.type(f) == "closed file")

  -- __gc and __close close the file and return nothing
  f = assert(io.open(name))
  assert(table.pack(mt.__gc(f)).n == 0 and io.type(f) == "closed file")
  assert(table.pack(mt.__gc(f)).n == 0) -- closing twice is harmless
  f = assert(io.open(name))
  assert(table.pack(mt.__close(f)).n == 0 and io.type(f) == "closed file")
  -- standard files stay open
  mt.__gc(io.stderr)
  assert(io.type(io.stderr) == "file")

  checkerr("FILE* expected, got no value", mt.__tostring)
  checkerr("FILE* expected, got number", mt.__tostring, 1)
  checkerr("FILE* expected, got number", mt.__gc, 1)
  checkerr("FILE* expected, got table", mt.__close, {})

  -- to-be-closed variables
  local keep
  do
    local h <close> = assert(io.open(name))
    keep = h
    assert(io.type(h) == "file")
  end
  assert(io.type(keep) == "closed file")
  local ok = pcall(function()
    local h <close> = assert(io.open(name))
    keep = h
    error("leave the block")
  end)
  assert(not ok and io.type(keep) == "closed file")
end

-- io.type -------------------------------------------------------------------
do
  assert(io.type(io.stdin) == "file" and io.type(io.stdout) == "file" and io.type(io.stderr) == "file")
  assert(io.type(42) == nil and io.type(nil) == nil and io.type("file") == nil)
  assert(io.type({}) == nil and io.type(io) == nil and io.type(print) == nil)
  checkerr("value expected", io.type)
end

-- io.open -------------------------------------------------------------------
do
  writefile("data")
  for _, mode in ipairs({"r", "rb", "r+", "r+b", "rbb", "a", "ab", "a+", "a+b", "w", "wb", "w+", "w+b", "w+bbb"}) do
    local f = assert(io.open(name, mode))
    assert(io.type(f) == "file" and f:close() == true)
  end
  for _, mode in ipairs({"rw", "x", "", "rb+", "r++", "+r", "R", "wr", "br", " r", "r ", "r+ ", "rt", "5", "w+x"}) do
    checkerr("invalid mode", io.open, name, mode)
  end
  checkerr("bad argument #2", io.open, name, "rw")
  checkerr("invalid mode", io.open, name, 5)
  checkerr("string expected, got no value", io.open)
  checkerr("string expected, got table", io.open, {})
  checkerr("string expected, got table", io.open, name, {})
  local f = assert(io.open(name, nil)) -- nil selects the default mode
  assert(f:read("a") == "" and f:close())

  local missing = name .. ".missing/file"
  local r = fails(missing .. ": ", nil, io.open(missing))
  assert(r.n == 3 and r[3] ~= 0)
  fails(missing .. ": ", r[3], io.open(missing, "w"))
  fails(nil, nil, io.open(missing, "a+"))
  -- "r" does not create files, "w" truncates, "a" keeps
  assert(os.remove(name))
  assert(io.open(name, "r") == nil and io.open(name, "r+") == nil)
  writefile("abc")
  writefile("")
  assert(readfile() == "")
  writefile("abc")
  writefile("def", "a")
  assert(readfile() == "abcdef")
  -- numbers are valid file names
  fails("12345678.9: ", nil, io.open(12345678.9))
end

-- write ---------------------------------------------------------------------
do
  local f = assert(io.open(name, "w"))
  assert(f:write() == f) -- no arguments
  assert(f:write("") == f)
  assert(f:write("hello", " ", "world\n") == f)
  assert(f:write(1, " ", -7, " ", 2.5, " ", 3.0, " ", -0.0, "\n") == f)
  assert(f:write(2 ^ 63, " ", math.mininteger, " ", 1e100, " ", 2 ^ 53, " ", 1e15, " ", 0.1, "\n") == f)
  assert(f:write(1 / 0, " ", -1 / 0, " ", 255 // 1, " ", 7 // 2.0, "\n"):write("chained"):write("\0zero\n") == f)
  checkerr("string expected, got table", f.write, f, {})
  checkerr("string expected, got nil", f.write, f, nil)
  checkerr("string expected, got boolean", f.write, f, "partial", true)
  checkerr("string expected, got function", f.write, f, print)
  checkerr("FILE* expected, got no value", f.write)
  checkerr("FILE* expected, got number", f.write, 1)
  checkerr("FILE* expected, got string", f.write, "x", "y")
  assert(f:close() == true)
  assert(readfile() == "hello world\n1 -7 2.5 3.0 -0.0\n"
    .. "9.2233720368547758e+18 -9223372036854775808 1e+100 9007199254740992.0 1e+15 0.1\n"
    .. "inf -inf 255 3.0\nchained\0zero\npartial")

  -- writing to a file opened for reading fails with 4 results: nil, a
  -- message, an error number and the number of bytes written
  f = assert(io.open(name))
  local r = fails(nil, nil, f:write("x"))
  assert(r.n == 4 and eq(r[4], 0))
  assert(f:close())
  checkerr("attempt to use a closed file", f.write, f, "x")
end

-- read formats --------------------------------------------------------------
do
  writefile("hello\n42 3.5\n\nlast line")
  local f = assert(io.open(name))
  assert(f:read() == "hello") -- default: a line
  local a, b = f:read("n", "n")
  assert(eq(a, 42) and eq(b, 3.5))
  assert(f:read("l") == "" and f:read("L") == "\n")
  assert(f:read(0) == "") -- not at the end of the file
  assert(f:read(4) == "last" and f:read(1) == " ")
  assert(f:read(100) == "line") -- short read
  assert(f:read(0) == nil and f:read(1) == nil and f:read("l") == nil)
  assert(f:read("L") == nil and f:read("n") == nil and f:read() == nil)
  assert(f:read("a") == "" and f:read("a") == "") -- "a" never fails
  assert(table.pack(f:read()).n == 1)

  -- several formats; reading stops at the first failure
  assert(f:seek("set") == 0)
  local r = table.pack(f:read(3, "l", "n", "n", "l", "L", "a", "l", "a"))
  assert(r.n == 8)
  assert(r[1] == "hel" and r[2] == "lo" and eq(r[3], 42) and eq(r[4], 3.5))
  assert(r[5] == "" and r[6] == "\n" and r[7] == "last line" and r[8] == nil)
  f:seek("set")
  r = table.pack(f:read("n", "l"))
  assert(r.n == 1 and r[1] == nil)
  assert(f:read(1) == "h") -- a failed "n" does not consume the look-ahead

  -- legacy format names with "*" and long names
  f:seek("set")
  assert(f:read("*l") == "hello" and eq(f:read("*n"), 42))
  assert(f:read("*L") == " 3.5\n" and f:read("*a") == "\nlast line")
  f:seek("set")
  assert(f:read("*line") == "hello" and eq(f:read("number"), 42) and f:read("all") == " 3.5\n\nlast line")
  f:seek("set")
  assert(f:read(2.0) == "he" and f:read("line") == "llo")

  -- counts
  f:seek("set")
  assert(f:read(0) == "" and f:read(0, 0) == "")
  r = table.pack(f:read(0, 5, 0, 1, 0))
  assert(r.n == 5 and r[1] == "" and r[2] == "hello" and r[3] == "" and r[4] == "\n" and r[5] == "")
  assert(#f:read(1000000) == 17 and f:read(1000000) == nil)

  checkerr("invalid format", f.read, f, "x")
  checkerr("invalid format", f.read, f, "*x")
  checkerr("invalid format", f.read, f, "*")
  checkerr("invalid format", f.read, f, "")
  checkerr("invalid format", f.read, f, "5")
  checkerr("invalid format", f.read, f, "N")
  checkerr("invalid format", f.read, f, "**l")
  checkerr("string expected, got table", f.read, f, {})
  checkerr("string expected, got boolean", f.read, f, true)
  checkerr("number has no integer representation", f.read, f, 1.5)
  checkerr("resulting string too large", f.read, f, -1)
  checkerr("resulting string too large", f.read, f, math.mininteger)
  checkerr("FILE* expected, got no value", f.read)
  checkerr("FILE* expected, got table", f.read, {})
  assert(f:close())
  checkerr("attempt to use a closed file", f.read, f)

  -- line endings and embedded zeros
  writefile("a\r\nb\0c\n\n\nlast")
  f = assert(io.open(name))
  assert(f:read("l") == "a\r" and f:read("L") == "b\0c\n")
  assert(f:read("l") == "" and f:read("L") == "\n" and f:read("L") == "last" and f:read("L") == nil)
  assert(f:close())
  writefile("x\n")
  f = assert(io.open(name))
  assert(f:read("l") == "x" and f:read("l") == nil)
  assert(f:close())

  -- long lines and blocks
  local long = string.rep("0123456789", 2000)
  writefile(long .. "\n" .. long .. long)
  f = assert(io.open(name))
  assert(f:read("l") == long and f:read(20000) == long and f:read("L") == long and f:read(1) == nil)
  f:seek("set", 19995)
  assert(f:read(10) == "56789\n0123" and f:seek("cur") == 20005)
  assert(f:close())

  -- an empty file
  writefile("")
  f = assert(io.open(name))
  assert(f:read(0) == nil and f:read("l") == nil and f:read("n") == nil and f:read("a") == "")
  assert(f:close())

  -- reading from a file opened for writing fails
  f = assert(io.open(name, "w"))
  fails(nil, nil, f:read())
  fails(nil, nil, f:read("a"))
  fails(nil, nil, f:read(0))
  r = fails(nil, nil, f:read("n"))
  assert(r.n == 3)
  checkerr("invalid format", f.read, f, "x")
  assert(f:close())
end

-- reading numbers -----------------------------------------------------------
do
  local function rn(content, ...)
    writefile(content)
    local f = assert(io.open(name))
    local r = table.pack(f:read(...))
    r.rest = f:read("a")
    f:close()
    return r
  end
  local r = rn("  12 0x1F -3.5 1e2 .5 5. 0x.8p1 +7 -0x10 0X1P4 1E5 007 0.10",
    "n", "n", "n", "n", "n", "n", "n", "n", "n", "n", "n", "n", "n")
  local want = {12, 31, -3.5, 100.0, 0.5, 5.0, 1.0, 7, -16, 16.0, 100000.0, 7, 0.1}
  assert(r.n == #want)
  for i = 1, #want do assert(eq(r[i], want[i]), "numeral " .. i) end
  r = rn("9223372036854775807 9223372036854775808 -9223372036854775808 0xffffffffffffffffff 12345678901234567890",
    "n", "n", "n", "n", "n")
  assert(eq(r[1], math.maxinteger) and eq(r[2], 2 ^ 63) and eq(r[3], math.mininteger))
  assert(eq(r[4], -1) and eq(r[5], 12345678901234567890.0))
  r = rn("0x1p-2 0x.1 0xA.8 1e400 -1e400", "n", "n", "n", "n", "n")
  assert(eq(r[1], 0.25) and eq(r[2], 0.0625) and eq(r[3], 10.5) and r[4] == 1 / 0 and r[5] == -1 / 0)
  r = rn(" \n\t\v\f\r 7\n", "n", "L")
  assert(eq(r[1], 7) and r[2] == "\n")

  -- the longest prefix that looks like a numeral is consumed
  local function case(content, value, rest)
    local r = rn(content, "n")
    assert(r.n == 1)
    if value == nil then assert(r[1] == nil) else assert(eq(r[1], value)) end
    assert(r.rest == rest, content .. " leaves " .. r.rest)
  end
  case("12abc", 12, "abc")
  case("abc", nil, "abc")
  case("1e", nil, "")
  case("1e+", nil, "")
  case("1e+x", nil, "x")
  case("0x", nil, "")
  case("0xg", nil, "g")
  case("-", nil, "")
  case("--1", nil, "-1")
  case("+-1", nil, "-1")
  case("1,5", 1, ",5")
  case("1e5x", 100000.0, "x")
  case("..5", nil, ".5")
  case(".", nil, "")
  case("+.e1", nil, "e1")
  case("0x10p", nil, "")
  case("inf", nil, "inf")
  case("nan", nil, "nan")
  case(" x", nil, "x")
  case("", nil, "")
  case("   ", nil, "")
  case("5", 5, "")
  case("5 ", 5, " ")
  case("1.5e3", 1500.0, "")
  case("1.5E-1 ", 0.15, " ")
  case("0x1.8", 1.5, "")
  case("1e5e5", 100000.0, "e5")
  case("0xep1", 28.0, "")
  case("1p5", 1, "p5")
  case("0x1e5", 485, "")
  -- numerals are limited to 200 characters
  case(string.rep("1", 250), nil, string.rep("1", 50))
  case(string.rep("0", 199) .. "7 ", 7, " ")
  case(string.rep("0", 200) .. "7", nil, "7")

  r = rn("1.2.3", "n", "n")
  assert(eq(r[1], 1.2) and eq(r[2], 0.3))
  r = rn("1 x 2", "n", "n", "n")
  assert(r.n == 2 and eq(r[1], 1) and r[2] == nil and r.rest == "x 2")
  r = rn("12", "n", "n", "n")
  assert(r.n == 2 and eq(r[1], 12) and r[2] == nil)
  r = rn("1 2", "n", "l")
  assert(eq(r[1], 1) and r[2] == " 2")
end

-- seek ----------------------------------------------------------------------
do
  writefile("0123456789")
  local f = assert(io.open(name, "r+"))
  assert(eq(f:seek(), 0) and eq(f:seek("cur"), 0) and eq(f:seek("end"), 10))
  assert(eq(f:seek("set"), 0) and eq(f:seek("set", 4), 4) and f:read(2) == "45")
  assert(eq(f:seek("cur"), 6) and eq(f:seek("cur", 0), 6) and eq(f:seek("cur", -3), 3))
  assert(f:read(1) == "3" and eq(f:seek("cur", 2), 6) and f:read(1) == "6")
  assert(eq(f:seek("end", -2), 8) and f:read("a") == "89" and eq(f:seek(), 10))
  assert(eq(f:seek("set", "3"), 3) and eq(f:seek("set", 5.0), 5) and eq(f:seek(nil, 1), 6))
  assert(eq(f:seek("end", 0), 10) and f:read(1) == nil)
  -- positions after buffered reads are logical positions
  f:seek("set")
  assert(f:read(1) == "0" and f:seek("cur") == 1 and f:read("n") == 123456789 and f:seek() == 10)
  f:seek("set", 2)
  assert(f:read("l") == "23456789" and f:seek("cur", -4) == 6 and f:read("a") == "6789")
  -- seeking past the end and writing leaves a gap of zeros
  assert(f:seek("set", 12) == 12 and f:read(1) == nil)
  assert(f:seek("set", 12) == 12 and f:write("X") == f and f:seek("cur") == 13)
  assert(f:seek("set", 9) == 9 and f:read("a") == "9\0\0X")
  -- failures
  fails(nil, nil, f:seek("set", -1))
  fails(nil, nil, f:seek("cur", -1000))
  assert(f:seek("cur") == 13) -- a failed seek does not move
  checkerr("invalid option 'bad'", f.seek, f, "bad")
  checkerr("invalid option '1'", f.seek, f, 1)
  checkerr("number has no integer representation", f.seek, f, "set", 1.5)
  checkerr("number expected, got string", f.seek, f, "set", "x")
  checkerr("FILE* expected, got no value", f.seek)
  assert(f:close())
  checkerr("attempt to use a closed file", f.seek, f)
end

-- update modes --------------------------------------------------------------
do
  writefile("abcdef")
  local f = assert(io.open(name, "r+"))
  assert(f:write("12") == f)
  assert(f:seek("set") == 0 and f:read("a") == "12cdef")
  assert(f:seek("set", 1) == 1 and f:read(1) == "2")
  assert(f:seek("cur", 0) == 2 and f:write("Z") == f)
  assert(f:seek("set") == 0 and f:read("a") == "12Zdef")
  assert(f:close())

  f = assert(io.open(name, "w+"))
  assert(f:read("a") == "" and f:write("new\nline") == f)
  assert(f:seek("set") == 0)
  local a, b, c = f:read("l", "l", "l")
  assert(a == "new" and b == "line" and c == nil)
  assert(f:close())

  -- append: every write goes to the end
  writefile("abc")
  f = assert(io.open(name, "a"))
  assert(f:write("def") == f and f:seek("cur") == 6)
  assert(f:seek("set", 0) == 0 and f:write("X") == f)
  assert(f:close())
  assert(readfile() == "abcdefX")
  f = assert(io.open(name, "a+"))
  assert(f:seek("set") == 0 and f:read("a") == "abcdefX")
  assert(f:seek("set", 2) == 2 and f:write("!") == f)
  assert(f:seek("set") == 0 and f:read("a") == "abcdefX!")
  assert(f:close())
  fails(nil, nil, assert(io.open(name, "a")):read())
end

-- flush / setvbuf / close ---------------------------------------------------
do
  local f = assert(io.open(name, "w"))
  assert(f:flush() == true)
  assert(f:setvbuf("no") == true and f:write("a") == f)
  assert(readfile() == "a") -- unbuffered output is visible at once
  assert(f:setvbuf("full", 1024) == true and f:write("b") == f)
  assert(f:flush() == true and readfile() == "ab")
  assert(f:setvbuf("full") == true and f:write("c") == f and f:flush() == true)
  assert(f:setvbuf("line") == true and f:write("d\n") == f)
  assert(f:setvbuf("line", 64) == true and f:setvbuf("no", 0) == true)
  assert(f:setvbuf("full", "16") == true and f:setvbuf("full", 16.0) == true)
  -- a seek flushes
  assert(f:write("e") == f and f:seek("cur") == 6 and readfile() == "abcd\ne")
  checkerr("invalid option 'bad'", f.setvbuf, f, "bad")
  checkerr("bad argument #2", f.setvbuf, f, "bad")
  checkerr("string expected, got no value", f.setvbuf, f)
  checkerr("number expected, got string", f.setvbuf, f, "full", "x")
  checkerr("number has no integer representation", f.setvbuf, f, "full", 1.5)
  checkerr("FILE* expected, got no value", f.setvbuf)
  checkerr("FILE* expected, got no value", f.flush)
  -- close flushes buffered output
  assert(f:setvbuf("full", 4096) == true and f:write(string.rep("z", 100)) == f)
  assert(f:close() == true)
  assert(readfile() == "abcd\ne" .. string.rep("z", 100))
  checkerr("attempt to use a closed file", f.close, f)
  checkerr("attempt to use a closed file", f.flush, f)
  checkerr("attempt to use a closed file", f.setvbuf, f, "no")
  checkerr("attempt to use a closed file", f.lines, f)
  checkerr("attempt to use a closed file", io.close, f)
  checkerr("FILE* expected, got no value", f.close)
  checkerr("FILE* expected, got number", io.close, 1)
  -- flushing a file opened for reading succeeds
  f = assert(io.open(name))
  assert(f:flush() == true and f:setvbuf("no") == true and io.close(f) == true)
  assert(io.type(f) == "closed file")
end

-- standard files ------------------------------------------------------------
do
  local r = table.pack(io.stdout:close())
  assert(r.n == 2 and r[1] == nil and r[2] == "cannot close standard file")
  r = table.pack(io.stderr:close())
  assert(r[1] == nil and r[2] == "cannot close standard file")
  r = table.pack(io.close(io.stdin))
  assert(r[1] == nil and r[2] == "cannot close standard file")
  assert(io.type(io.stdout) == "file" and io.type(io.stdin) == "file")
  assert(io.stdout:write("") == io.stdout and io.stderr:write("") == io.stderr)
  assert(io.stdout:flush() == true and io.stderr:flush() == true)
  assert(io.write() == io.stdout and io.write("") == io.stdout and io.flush() == true)
  assert(io.output() == io.stdout and io.input() == io.stdin)
  checkerr("invalid option 'bad'", io.stdout.seek, io.stdout, "bad")
end

-- io.output / io.write / io.close / io.flush --------------------------------
do
  local stdout = io.output()
  local f = io.output(name) -- opens (and truncates) the file
  assert(io.type(f) == "file" and io.output() == f and f ~= stdout)
  assert(io.write("via default ", 1, " ", 2.0, "\n") == f)
  assert(io.write() == f and io.flush() == true)
  assert(io.close() == true) -- closes the default output
  assert(io.type(f) == "closed file" and io.output() == f)
  checkerr("default output file is closed", io.write, "x")
  checkerr("default output file is closed", io.flush)
  checkerr("attempt to use a closed file", io.close)
  assert(io.output(stdout) == stdout and io.output() == stdout)
  assert(readfile() == "via default 1 2.0\n")

  f = assert(io.open(other, "w"))
  assert(io.output(f) == f and io.write("handle") == f)
  assert(io.output(stdout) == stdout)
  assert(f:close())
  local g = assert(io.open(other))
  assert(g:read("a") == "handle" and g:close())

  checkerr("cannot open file '" .. name .. ".missing/file' (", io.output, name .. ".missing/file")
  checkerr("FILE* expected, got boolean", io.output, true)
  checkerr("FILE* expected, got table", io.output, {})
  checkerr("attempt to use a closed file", io.output, f)
  checkerr("string expected, got table", io.write, {})
  checkerr("bad argument #1", io.write, {})
  checkerr("bad argument #2", io.write, "", {})
  assert(io.output() == stdout)
end

-- io.input / io.read --------------------------------------------------------
do
  local stdin = io.input()
  writefile("line one\n17 rest\ntail")
  local f = io.input(name)
  assert(io.type(f) == "file" and io.input() == f and f ~= stdin)
  assert(io.read() == "line one" and eq(io.read("n"), 17))
  local a, b = io.read(1, "l")
  assert(a == " " and b == "rest")
  assert(io.read("a") == "tail" and io.read("a") == "" and io.read("l") == nil and io.read(0) == nil)
  checkerr("invalid format", io.read, "x")
  checkerr("bad argument #1", io.read, "x")
  checkerr("bad argument #2", io.read, "a", "x")
  assert(io.read(0, "x") == nil) -- formats after a failure are not checked
  assert(io.close(io.input()) == true)
  checkerr("default input file is closed", io.read)
  checkerr("attempt to use a closed file", io.lines)
  assert(io.input(stdin) == stdin)

  f = assert(io.open(name))
  assert(io.input(f) == f and io.read(4) == "line")
  assert(io.input(stdin) == stdin and f:read(4) == " one" and f:close())

  checkerr("cannot open file '" .. name .. ".missing' (", io.input, name .. ".missing")
  checkerr("cannot open file '5' (", io.input, 5)
  checkerr("FILE* expected, got table", io.input, {})
  checkerr("attempt to use a closed file", io.input, f)
  assert(io.input() == stdin)
end

-- io.tmpfile ----------------------------------------------------------------
do
  local f = io.tmpfile()
  assert(io.type(f) == "file")
  assert(f:write("tmp ", 1) == f and f:seek("set") == 0 and f:read("a") == "tmp 1")
  assert(f:seek("end") == 5 and f:close() == true)
  local g = io.tmpfile()
  assert(g:read("a") == "" and g:close())
end

-- io.popen ------------------------------------------------------------------
do
  local p = io.popen("echo hi; exit 3")
  assert(io.type(p) == "file" and string.sub(tostring(p), 1, 6) == "file (")
  assert(p:read("a") == "hi\n")
  local r = table.pack(p:close())
  assert(r.n == 3 and r[1] == nil and r[2] == "exit" and eq(r[3], 3))
  assert(io.type(p) == "closed file" and tostring(p) == "file (closed)")
  checkerr("attempt to use a closed file", p.close, p)
  checkerr("attempt to use a closed file", p.read, p)

  p = io.popen("printf 'a\\nb\\n12 0x10'")
  local a, b, c, d, e = p:read("l", "L", "n", "n", "n")
  assert(a == "a" and b == "b\n" and eq(c, 12) and eq(d, 16) and e == nil)
  r = table.pack(p:close())
  assert(r[1] == true and r[2] == "exit" and eq(r[3], 0))

  p = io.popen("true", "r")
  assert(p:read("a") == "" and p:read(1) == nil)
  fails(nil, nil, p:seek()) -- pipes cannot seek
  assert(io.close(p) == true)

  p = io.popen("kill -9 $$")
  r = table.pack(p:close())
  assert(r[1] == nil and r[2] == "signal" and eq(r[3], 9))

  -- mode "w": the command reads what we write
  p = io.popen("cat > '" .. other .. "'", "w")
  assert(p:write("to the command\n", 42) == p)
  r = table.pack(p:close())
  assert(r[1] == true and r[2] == "exit" and r[3] == 0)
  local g = assert(io.open(other))
  assert(g:read("a") == "to the command\n42" and g:close())
  p = io.popen("exit 5", "w")
  r = table.pack(p:close())
  assert(r[1] == nil and r[2] == "exit" and r[3] == 5)

  -- a to-be-closed process handle
  local keep
  do
    local h <close> = io.popen("echo closing")
    keep = h
    assert(h:read("l") == "closing")
  end
  assert(io.type(keep) == "closed file")

  checkerr("invalid mode", io.popen, "true", "rw")
  checkerr("invalid mode", io.popen, "true", "x")
  checkerr("invalid mode", io.popen, "true", "")
  checkerr("invalid mode", io.popen, "true", "r+")
  checkerr("bad argument #2", io.popen, "true", "a")
  checkerr("string expected, got no value", io.popen)
  checkerr("string expected, got table", io.popen, {})
end

assert(os.remove(name))
assert(os.remove(other))

-- Lua 5.5 io.lines / file:lines conformance checks.
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

local name = os.tmpname()

local function writefile(content)
  local f = assert(io.open(name, "w"))
  assert(f:write(content))
  assert(f:close())
end

-- collect gathers the first value of every iteration.
local function collect(...)
  local t = {}
  for v in ... do t[#t + 1] = v end
  return t
end

writefile("l1\nl2\n\nl4")

-- io.lines(filename) ---------------------------------------------------------
do
  local r = table.pack(io.lines(name))
  -- iterator, state, control and the file as closing value
  assert(r.n == 4 and type(r[1]) == "function" and r[2] == nil and r[3] == nil)
  assert(io.type(r[4]) == "file")
  assert(r[1]() == "l1" and r[1](nil, nil) == "l2" and r[1]("ignored") == "")
  assert(r[1]() == "l4")
  assert(table.pack(r[1]()).n == 0) -- the end: no results, the file is closed
  assert(io.type(r[4]) == "closed file")
  checkerr("file is already closed", r[1])

  local t = collect(io.lines(name))
  assert(#t == 4 and t[1] == "l1" and t[2] == "l2" and t[3] == "" and t[4] == "l4")
  t = collect(io.lines(name, "l"))
  assert(#t == 4 and t[4] == "l4")
  t = collect(io.lines(name, "L"))
  assert(#t == 4 and t[1] == "l1\n" and t[3] == "\n" and t[4] == "l4")
  t = collect(io.lines(name, 2))
  assert(#t == 5 and t[1] == "l1" and t[2] == "\nl" and t[3] == "2\n" and t[4] == "\nl" and t[5] == "4")
  t = collect(io.lines(name, 100))
  assert(#t == 1 and t[1] == "l1\nl2\n\nl4")
  t = collect(io.lines(name, "*l")) -- legacy format name
  assert(#t == 4)

  -- several formats per iteration
  local n = 0
  for a, b, c in io.lines(name, 1, "l", 0) do
    n = n + 1
    if n == 1 then assert(a == "l" and b == "1" and c == "") end
    if n == 3 then assert(a == "\n" and b == "l4" and c == nil) end
  end
  assert(n == 3)

  -- "a" never fails: the loop must be left explicitly
  n = 0
  for all in io.lines(name, "a") do
    n = n + 1
    assert(all == (n == 1 and "l1\nl2\n\nl4" or ""))
    if n == 3 then break end
  end
  assert(n == 3)

  -- 0 only succeeds while there is something to read
  n = 0
  for v in io.lines(name, 0) do
    assert(v == "")
    n = n + 1
    if n == 5 then break end
  end
  assert(n == 5)

  -- the file is closed when the loop ends, breaks or fails
  local it, s, c, file = io.lines(name)
  for l in it, s, c, file do end
  assert(io.type(file) == "closed file")
  it, s, c, file = io.lines(name)
  for l in it, s, c, file do break end
  assert(io.type(file) == "closed file")
  it, s, c, file = io.lines(name)
  assert(not pcall(function()
    for l in it, s, c, file do error("leave") end
  end))
  assert(io.type(file) == "closed file")
  checkerr("file is already closed", it)

  -- numbers
  writefile("1 2 3\n4 5.5 0x10\n7 8")
  local rows = {}
  for a, b, c in io.lines(name, "n", "n", "n") do rows[#rows + 1] = {a, b, c} end
  assert(#rows == 3)
  assert(eq(rows[1][1], 1) and eq(rows[1][2], 2) and eq(rows[1][3], 3))
  assert(eq(rows[2][1], 4) and eq(rows[2][2], 5.5) and eq(rows[2][3], 16))
  assert(eq(rows[3][1], 7) and eq(rows[3][2], 8) and rows[3][3] == nil)
  rows = {}
  for a, b in io.lines(name, "n", "l") do rows[#rows + 1] = {a, b} end
  assert(#rows == 3 and eq(rows[1][1], 1) and rows[1][2] == " 2 3" and rows[3][2] == " 8")

  -- an empty file
  writefile("")
  assert(#collect(io.lines(name)) == 0 and #collect(io.lines(name, "L")) == 0)
  assert(#collect(io.lines(name, 1)) == 0 and #collect(io.lines(name, "n")) == 0)

  -- errors
  checkerr("cannot open file '" .. name .. ".missing' (", io.lines, name .. ".missing")
  checkerr("string expected, got table", io.lines, {})
  checkerr("string expected, got FILE*", io.lines, io.stdin)
  it, s, c, file = io.lines(name, "x") -- formats are checked when reading
  checkerr("invalid format", it)
  assert(file:close())
  it, s, c, file = io.lines(name, {})
  checkerr("string expected, got table", it)
  assert(file:close())
  -- at most 250 formats
  local formats = {}
  for i = 1, 250 do formats[i] = "l" end
  it, s, c, file = io.lines(name, table.unpack(formats))
  assert(type(it) == "function" and file:close())
  formats[251] = "l"
  checkerr("too many arguments", io.lines, name, table.unpack(formats))
  checkerr("bad argument #252", io.lines, name, table.unpack(formats))
end

-- file:lines() ---------------------------------------------------------------
do
  writefile("l1\nl2\n\nl4")
  local f = assert(io.open(name))
  local r = table.pack(f:lines())
  assert(r.n == 1 and type(r[1]) == "function")
  local t = collect(f:lines())
  assert(#t == 4 and t[1] == "l1" and t[4] == "l4")
  assert(io.type(f) == "file") -- file:lines does not close the file
  assert(f:read() == nil and table.pack(f:lines()()).n == 0)
  assert(f:seek("set") == 0)
  t = collect(f:lines("L"))
  assert(#t == 4 and t[2] == "l2\n" and t[4] == "l4")
  f:seek("set")
  t = collect(f:lines(4))
  assert(#t == 3 and t[1] == "l1\nl" and t[2] == "2\n\nl" and t[3] == "4")
  f:seek("set")
  local n = 0
  for a, b in f:lines(2, "L") do
    n = n + 1
    if n == 1 then assert(a == "l1" and b == "\n") end
    if n == 3 then assert(a == "\nl" and b == "4") end
  end
  assert(n == 3)
  -- iterators share the position of the file
  f:seek("set")
  local it1, it2 = f:lines(), f:lines("L")
  assert(it1() == "l1" and it2() == "l2\n" and it1() == "" and it2() == "l4" and it1() == nil)
  -- break and continue reading
  f:seek("set")
  for l in f:lines() do
    if l == "l2" then break end
  end
  assert(f:read("a") == "\nl4")

  local it = f:lines("n")
  f:seek("set")
  assert(it() == nil) -- "l1" is not a number
  it = f:lines("x")
  checkerr("invalid format", it)
  it = f:lines()
  assert(f:close())
  checkerr("file is already closed", it)
  checkerr("attempt to use a closed file", f.lines, f)
  checkerr("FILE* expected, got no value", f.lines)

  f = assert(io.open(name))
  local formats = {}
  for i = 1, 251 do formats[i] = "l" end
  checkerr("too many arguments", f.lines, f, table.unpack(formats))
  formats[251] = nil
  assert(type(f:lines(table.unpack(formats))) == "function")
  assert(f:close())

  -- a file opened for writing cannot be read: the iterator raises the error
  f = assert(io.open(name, "w"))
  it = f:lines()
  assert(not pcall(it))
  assert(f:close())
end

-- io.lines() on the default input -------------------------------------------
do
  writefile("d1\nd2\nd3")
  local stdin = io.input()
  local f = io.input(name)
  local r = table.pack(io.lines())
  assert(r.n == 1 and type(r[1]) == "function")
  assert(r[1]() == "d1")
  local t = collect(io.lines(nil, "L"))
  assert(#t == 2 and t[1] == "d2\n" and t[2] == "d3")
  assert(io.type(f) == "file") -- the default input stays open
  assert(io.read() == nil)
  assert(f:close())
  checkerr("attempt to use a closed file", io.lines)
  io.input(stdin)
end

-- reading and iterating over large files -------------------------------------
do
  local f = assert(io.open(name, "w"))
  for i = 1, 5000 do assert(f:write(i, " line ", i * 0.5, "\n")) end
  assert(f:close())
  local n, sum = 0, 0
  for l in io.lines(name) do
    n = n + 1
    sum = sum + #l
  end
  assert(n == 5000 and sum == 76676)
  n = 0
  for a, word, b in io.lines(name, "n", 6, "n") do
    n = n + 1
    assert(eq(a, n) and word == " line " and eq(b, n * 0.5))
  end
  assert(n == 5000)
  n = 0
  for block in io.lines(name, 4096) do n = n + #block end
  assert(n == 81676)
end

assert(os.remove(name))

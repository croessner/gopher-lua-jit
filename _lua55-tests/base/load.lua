-- load, loadfile and dofile.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

local function pack(...)
  return {n = select("#", ...), ...}
end

-- directory holding the fixture files of this test
local dir = debug.getinfo(1, "S").source:match("^@(.*)[/\\][^/\\]*$") .. "/modules/"

-- load: string chunks
assert(load("return 1 + 1")() == 2)
local r = pack(load("return ...", "c")(1, 2, 3))
assert(r.n == 3 and r[3] == 3)
assert(type(load("")) == "function" and type(load("   ")) == "function")
assert(type(load("-- only a comment")) == "function")
assert(load("return 1", nil, nil, nil)() == 1)
assert(select("#", load("return 1")) == 1)
-- a number is converted to a string chunk
r = pack(load(1))
assert(r.n == 2 and r[1] == nil and r[2] == '[string "1"]:1: unexpected symbol near \'1\'')
-- load does not skip a first line starting with '#'
r = pack(load("# comment\nreturn 1"))
assert(r[1] == nil and r[2]:find("unexpected symbol near '#'", 1, true))

-- load: chunks see the global environment
some_global_for_load = 42
assert(load("return some_global_for_load")() == 42)
load("some_global_for_load = nil")()
assert(some_global_for_load == nil)

-- load: custom environments
assert(load("return x", "c", "t", {x = 42})() == 42)
local env = {}
assert(load("x = 7; return _ENV", "c", "t", env)() == env and env.x == 7)
assert(load("return _ENV", "c", "t", 5)() == 5)
checkerr("attempt to index a number value", load("return x", "c", "t", 5))
-- an explicit nil environment is used as given
checkerr("attempt to index a nil value", load("return x", "c", "t", nil))
-- functions defined by the chunk share its environment
local getter = load("y = 1; return function() return y end", "c", "t", env)()
env.y = "changed"
assert(getter() == "changed")
-- a chunk that uses no globals accepts any environment
assert(load("return 1", "c", "t", nil)() == 1)

-- load: function chunks
local parts = {"return ", "1", " + ", "41"}
local state = {i = 0}
assert(load(function() state.i = state.i + 1 return parts[state.i] end)() == 42)
-- an empty string ends the chunk like nil does
state.i = 0
assert(load(function()
  state.i = state.i + 1
  if state.i == 1 then return "return 5" elseif state.i == 2 then return "" else return " + 1" end
end)() == 5)
assert(type(load(function() return nil end)) == "function")
r = pack(load(function() return {} end))
assert(r.n == 2 and r[1] == nil and r[2]:find("reader function must return a string", 1, true))
r = pack(load(function() error("boom") end))
assert(r.n == 2 and r[1] == nil and r[2]:find("boom", 1, true))
-- the default chunk name of function chunks
state.i = 0
r = pack(load(function() state.i = state.i + 1 if state.i == 1 then return "x = = 1" end end))
assert(r[1] == nil and r[2] == "(load):1: unexpected symbol near '='")

-- load: modes
assert(type(load("return 1", "c", "t")) == "function")
assert(type(load("return 1", "c", "bt")) == "function")
r = pack(load("return 1", "c", "b"))
assert(r.n == 2 and r[1] == nil and r[2] == "attempt to load a text chunk (mode is 'b')")
r = pack(load("return 1", "c", "x"))
assert(r[1] == nil and r[2] == "attempt to load a text chunk (mode is 'x')")
r = pack(load("\27Lua", "c", "t"))
assert(r[1] == nil and r[2] == "attempt to load a binary chunk (mode is 't')")
r = pack(load("\27Lua"))
assert(r.n == 2 and r[1] == nil and type(r[2]) == "string")   -- not a valid precompiled chunk

-- load: argument checks
checkerr("function expected", load)
checkerr("function expected", load, nil)
checkerr("function expected", load, {})
checkerr("string expected, got table", load, "return 1", {})

-- chunk names in messages
local function syntax(code, chunkname)
  local f, msg = load(code, chunkname)
  assert(f == nil)
  return msg
end
assert(syntax("x = = 2") == '[string "x = = 2"]:1: unexpected symbol near \'=\'')
assert(syntax("x = = 2", "=name") == "name:1: unexpected symbol near '='")
assert(syntax("x = = 2", "@file.lua") == "file.lua:1: unexpected symbol near '='")
assert(syntax("x = ", "chunk") == '[string "chunk"]:1: unexpected symbol near <eof>')
assert(syntax("x = 1\ny = = 2\n") == '[string "x = 1..."]:2: unexpected symbol near \'=\'')
assert(syntax("   \n\n  x = = 1", "=n") == "n:3: unexpected symbol near '='")
assert(syntax("x = 3 + * 4", "=(load)") == "(load):1: unexpected symbol near '*'")
assert(syntax("\n\nx = (") == '[string "..."]:3: unexpected symbol near <eof>')

local function runtime(chunkname)
  local ok, msg = pcall(load("error('rt')", chunkname))
  assert(not ok)
  return msg
end
assert(runtime() == "[string \"error('rt')\"]:1: rt")
assert(runtime("=(my)") == "(my):1: rt")
assert(runtime("@a/b.lua") == "a/b.lua:1: rt")
assert(runtime("plain name") == '[string "plain name"]:1: rt')
assert(runtime("=") == ":1: rt")
-- long names are truncated
local long = "a very long chunk name that will be truncated somewhere because it is longer than sixty characters"
assert(runtime(long) == '[string "a very long chunk name that will be truncated..."]:1: rt')
assert(runtime("=" .. long) == "a very long chunk name that will be truncated somewhere bec:1: rt")
assert(runtime("@a/very/long/file/name/that/will/be/truncated/somewhere/because/it/is/longer/than/sixty.lua")
       == ".../truncated/somewhere/because/it/is/longer/than/sixty.lua:1: rt")
local ok, msg = pcall(load("\n\nerror('rt')\n-- a second line"))
assert(not ok and msg == '[string "..."]:3: rt')

-- syntax error messages
local cases = {
  {"for", "<name> expected near <eof>"},
  {"x = 'abc", "unfinished string near <eof>"},
  {"x = 1 1", "unexpected symbol near '1'"},
  {"return return", "unexpected symbol near 'return'"},
  {"x = }", "unexpected symbol near '}'"},
  {"x = 0x", "malformed number near '0x'"},
  {"x = 1e", "malformed number near '1e'"},
  {"x = 3x", "malformed number near '3x'"},
  {"f(", "unexpected symbol near <eof>"},
  {"x = #", "unexpected symbol near <eof>"},
  {"x = ~", "unexpected symbol near <eof>"},
  {"if x then", "'end' expected near <eof>"},
  {"if x then else", "'end' expected near <eof>"},
  {"x = function() ", "'end' expected near <eof>"},
  {"while true do", "'end' expected near <eof>"},
  {"local t = {1, 2", "'}' expected near <eof>"},
  {"x = (1", "')' expected near <eof>"},
  {"a.b:c = 1", "function arguments expected near '='"},
  {"and", "unexpected symbol near 'and'"},
  {"x = y z = 1 =", "unexpected symbol near '='"},
  {"local a <foo> = 1", "unknown attribute 'foo'"},
  {"local x <const> = 1; x = 2", "attempt to assign to const variable 'x'"},
  {"goto nolabel", "no visible label 'nolabel' for <goto> at line 1"},
  {"break", "break outside loop near 'break'"},
  {"x = \1", "unexpected symbol near '<\\1>'"},
  {"x = $", "unexpected symbol near '$'"},
  {"local 1", "<name> expected near '1'"},
  {"x, y", "'=' expected near <eof>"},
  {"function f(a b) end", "')' expected near 'b'"},
  {"for i=1 do end", "',' expected near 'do'"},
  {"x = 1 +", "unexpected symbol near <eof>"},
  {"return x y", "<eof> expected near 'y'"},
  {"if x then\n\n", "'end' expected (to close 'if' at line 1) near <eof>"},
}
for _, case in ipairs(cases) do
  local f, m = load(case[1], "=c")
  assert(f == nil, "expected a syntax error for: " .. case[1])
  assert(m:find(case[2], 1, true), "got '" .. m .. "' for: " .. case[1])
  assert(m:find("^c:%d+: "), "missing position in '" .. m .. "'")
end

-- loadfile
r = pack(loadfile(dir .. "chunk_ok.lua"))
assert(r.n == 1 and type(r[1]) == "function")
r = pack(r[1]("a", "b"))
assert(r.n == 3 and r[1] == "chunk_ok" and r[2] == "a" and r[3] == "b")
-- mode and environment
assert(loadfile(dir .. "chunk_env.lua", "t", {x = "from env"})() == "from env")
assert(loadfile(dir .. "chunk_env.lua", "bt", {x = 1})() == 1)
x_for_loadfile_test = nil
r = pack(loadfile(dir .. "chunk_ok.lua", "b"))
assert(r.n == 2 and r[1] == nil and r[2] == "attempt to load a text chunk (mode is 'b')")
-- a first line starting with '#' is skipped and line numbers are kept
assert(loadfile(dir .. "chunk_shebang.lua")() == 2)
-- a byte order mark is skipped
assert(loadfile(dir .. "chunk_bom.lua")() == "bom")
assert(select("#", loadfile(dir .. "chunk_empty.lua")()) == 0)
-- errors
r = pack(loadfile(dir .. "does_not_exist.lua"))
assert(r.n == 2 and r[1] == nil)
assert(r[2] == "cannot open " .. dir .. "does_not_exist.lua: No such file or directory", r[2])
r = pack(loadfile(dir .. "chunk_syntax.lua"))
assert(r.n == 2 and r[1] == nil)
assert(r[2] == dir .. "chunk_syntax.lua:1: unexpected symbol near '='", r[2])
-- runtime errors use the file name as chunk name
ok, msg = pcall(loadfile(dir .. "chunk_error.lua"))
assert(not ok and msg == dir .. "chunk_error.lua:2: runtime failure")
assert(debug.getinfo(loadfile(dir .. "chunk_ok.lua"), "S").source == "@" .. dir .. "chunk_ok.lua")
checkerr("string expected", loadfile, {})

-- dofile
r = pack(dofile(dir .. "chunk_ok.lua"))
assert(r.n == 1 and r[1] == "chunk_ok")
assert(dofile(dir .. "chunk_shebang.lua") == 2)
assert(select("#", dofile(dir .. "chunk_empty.lua")) == 0)
ok, msg = pcall(dofile, dir .. "does_not_exist.lua")
assert(not ok and msg == "cannot open " .. dir .. "does_not_exist.lua: No such file or directory")
ok, msg = pcall(dofile, dir .. "chunk_syntax.lua")
assert(not ok and msg == dir .. "chunk_syntax.lua:1: unexpected symbol near '='")
ok, msg = pcall(dofile, dir .. "chunk_error.lua")
assert(not ok and msg == dir .. "chunk_error.lua:2: runtime failure")
checkerr("string expected", dofile, {})

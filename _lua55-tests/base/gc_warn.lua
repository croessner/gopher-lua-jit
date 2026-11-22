-- collectgarbage and warn.

local function checkerr(expected, f, ...)
  local ok, msg = pcall(f, ...)
  assert(not ok, "expected an error containing: " .. expected)
  assert(type(msg) == "string" and msg:find(expected, 1, true), "unexpected message: " .. tostring(msg))
end

-- full collection is the default option and returns zero
assert(collectgarbage() == 0)
assert(collectgarbage("collect") == 0)
assert(tostring(collectgarbage("collect")) == "0")
assert(select("#", collectgarbage()) == 1)

-- memory in use: a positive float (kilobytes)
local count = collectgarbage("count")
assert(type(count) == "number" and count > 0)
assert(tostring(count):find("[%.e]"), "count must be a float")

-- stopping and restarting
assert(collectgarbage("isrunning") == true)
assert(collectgarbage("stop") == 0)
assert(collectgarbage("isrunning") == false)
assert(collectgarbage("restart") == 0)
assert(collectgarbage("isrunning") == true)

-- a step returns a boolean
assert(type(collectgarbage("step")) == "boolean")
assert(type(collectgarbage("step", 0)) == "boolean")
assert(type(collectgarbage("step", 100)) == "boolean")
checkerr("number expected, got string", collectgarbage, "step", "x")

-- changing the mode returns the previous mode
local initial = collectgarbage("incremental")
assert(initial == "incremental" or initial == "generational")
assert(collectgarbage("generational") == "incremental")
assert(collectgarbage("generational") == "generational")
assert(collectgarbage("incremental") == "generational")
assert(collectgarbage("incremental") == "incremental")
collectgarbage(initial)

-- collector parameters can be read and changed
local defaults = {minormul = 20, majorminor = 50, minormajor = 68, pause = 250, stepmul = 200, stepsize = 9600}
for name, default in pairs(defaults) do
  local old = collectgarbage("param", name)
  assert(old == default and tostring(old) == tostring(default), name)
  assert(collectgarbage("param", name, 100) == old)   -- returns the previous value
  assert(collectgarbage("param", name) == 100)
  assert(collectgarbage("param", name, 200) == 100)
  assert(collectgarbage("param", name, -1) == 200)     -- negative values only query
  assert(collectgarbage("param", name, old) == 200)
  assert(collectgarbage("param", name) == old)
end
checkerr("invalid option 'x'", collectgarbage, "param", "x")
checkerr("string expected, got no value", collectgarbage, "param")
checkerr("number expected, got string", collectgarbage, "param", "pause", "x")

-- invalid options, including the ones removed after Lua 5.3
checkerr("invalid option 'bogus'", collectgarbage, "bogus")
checkerr("invalid option 'setpause'", collectgarbage, "setpause")
checkerr("invalid option 'setstepmul'", collectgarbage, "setstepmul", 100)
checkerr("invalid option '1'", collectgarbage, 1)
checkerr("string expected, got table", collectgarbage, {})

-- collecting does not disturb live data
local keep = {}
for i = 1, 1000 do keep[i] = {i} end
collectgarbage()
collectgarbage("step")
for i = 1, 1000 do assert(keep[i][1] == i) end

-- warn: argument checks (all arguments must be strings or numbers)
checkerr("string expected, got no value", warn)
checkerr("string expected, got table", warn, "a", {})
checkerr("string expected, got nil", warn, nil)
checkerr("string expected, got boolean", warn, "a", "b", true)

-- warn returns nothing; control messages switch the output on and off
assert(select("#", warn("@off")) == 0)
warn("not shown while warnings are off")
warn("not ", "shown ", "either")
warn("@on")
warn("expected test warning: ", "pieces are concatenated ", 1, " ", 2.5)
warn("@unknown control messages are ignored")
warn("@off")
warn("not shown again")
-- "@on" as the first of several pieces is not a control message
warn("@on", " is not a control message here")
assert(select("#", warn("still off")) == 0)

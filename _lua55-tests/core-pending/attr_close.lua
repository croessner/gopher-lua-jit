-- Local attributes: <close> (to-be-closed variables).
local load = loadstring or load

-- returns a closable value that appends name (and the error, if any) to log
local function closer(log, name)
  return setmetatable({name = name}, {__close = function(self, err)
    if err == nil then
      log[#log + 1] = name
    else
      log[#log + 1] = name .. "(" .. tostring(err) .. ")"
    end
  end})
end

-- ## values without __close are rejected
do
assert(not pcall(function() local x <close> = function() end end))
end

-- ## closed on error, receiving the error object
do
local log = {}
local ok, err = pcall(function()
  local a <close> = closer(log, "a")
  local b <close> = closer(log, "b")
  error("boom", 0)
end)
assert(log[2] == "a(boom)")
log = {}
local errobj = {}
ok, err = pcall(function()
  local a <close> = setmetatable({}, {__close = function(_, e) log[1] = e end})
  error(errobj)
end)
end

-- ## closed when an error passes through several frames
do
local log = {}
local function inner()
  local x <close> = closer(log, "inner")
  error("deep", 0)
end
local function middle()
  local y <close> = closer(log, "middle")
  inner()
  log[#log + 1] = "not reached"
end
local ok, err = pcall(function()
  local z <close> = closer(log, "outer")
  middle()
end)
assert(log[2] == "middle(deep)")
assert(log[3] == "outer(deep)")
end

-- ## the variable is constant
do
assert(load("local x <close>, y = nil, nil") ~= nil)
end

-- ## __close can yield
do
local log = {}
local co = coroutine.wrap(function()
  do
    local x <close> = setmetatable({}, {__close = function()
      log[#log + 1] = "closing"
      coroutine.yield("from close")
      log[#log + 1] = "closed"
    end})
    log[#log + 1] = "body"
  end
  log[#log + 1] = "after"
  return "done"
end)
assert(co() == "from close")
assert(table.concat(log, ",") == "body,closing")
assert(co() == "done")
assert(table.concat(log, ",") == "body,closing,closed,after")
end

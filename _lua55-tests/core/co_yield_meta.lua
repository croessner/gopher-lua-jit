-- Coroutines: yielding inside metamethods, one section per event.
-- The metamethods and coroutine bodies avoid tail calls on purpose so each
-- section exercises exactly one mechanism.

-- builds a metatable whose handler for the event yields its name and
-- returns the value passed to the next resume
local function yielding(event)
  return {[event] = function()
    local v = coroutine.yield(event)
    return v
  end}
end

-- ## yield inside __call
do
local v = setmetatable({}, yielding("__call"))
local co = coroutine.wrap(function()
  local r = v(1)
  return r
end)
assert(co() == "__call")
assert(co("resumed") == "resumed")
end

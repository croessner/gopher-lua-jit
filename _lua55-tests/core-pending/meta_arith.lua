-- Metatables: arithmetic and bitwise metamethods.
local T = tostring

-- builds a value whose metamethods record the event and operands
local function tracker()
  local log = {}
  local mt = {}
  for _, ev in ipairs{"add", "sub", "mul", "div", "mod", "pow", "idiv",
                      "band", "bor", "bxor", "shl", "shr"} do
    mt["__" .. ev] = function(a, b)
      log[#log + 1] = ev
      return ev, a, b
    end
  end
  mt.__unm = function(a, b) log[#log + 1] = "unm"; return "unm", a, b end
  mt.__bnot = function(a, b) log[#log + 1] = "bnot"; return "bnot", a, b end
  return setmetatable({}, mt), log, mt
end

-- ## metamethods that are not functions
do
local callable = setmetatable({}, {__call = function(self, a, b) return "called" end})
local v = setmetatable({}, {__add = callable, __sub = 42})
assert(v + 1 == "called")
end

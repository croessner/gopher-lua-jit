-- objects with number fields and methods
local Point = {}
Point.__index = Point
function Point.new(x, y) return setmetatable({x = x, y = y, vx = 1, vy = 0.5}, Point) end
function Point:step(dt)
  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt
end
function Point:norm2() return self.x * self.x + self.y * self.y end
return function(n)
  local ps = {}
  for i = 1, 100 do ps[i] = Point.new(i, -i) end
  local s = 0
  for k = 1, n / 100 do
    for i = 1, #ps do
      local p = ps[i]
      p:step(0.25)
      s = s + p:norm2()
    end
  end
  return s
end

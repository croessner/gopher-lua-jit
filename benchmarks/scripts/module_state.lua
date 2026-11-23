-- module-level state: tables, counters and library functions that the
-- function reaches through upvalues
local weights = {}
for i = 1, 64 do weights[i] = i % 7 + 1 end
local stats = {hits = 0, total = 0}
local floor, max = math.floor, math.max
return function(n)
  stats.hits, stats.total = 0, 0
  for i = 1, n do
    local w = weights[i % 64 + 1]
    stats.total = stats.total + max(w, 3)
    if floor(i / 3) % 2 == 0 then stats.hits = stats.hits + 1 end
  end
  return stats.total + stats.hits
end

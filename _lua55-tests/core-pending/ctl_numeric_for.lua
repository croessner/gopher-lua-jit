-- Control flow: the numeric for loop.
local load = loadstring or load
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1
local inf = 1 / 0

-- collects the values of a loop as a comma separated string
local function run(a, b, c)
  local out = {}
  if c == nil then
    for i = a, b do out[#out + 1] = T(i) end
  else
    for i = a, b, c do out[#out + 1] = T(i) end
  end
  return table.concat(out, ",")
end

-- ## a string initial value or step makes it a float loop
do
assert(run("1", 3) == "1.0,2.0,3.0")
assert(run(1, 3, "1") == "1.0,2.0,3.0")
assert(run("1", "3", "1") == "1.0,2.0,3.0")
assert(run("0x1", "0x3") == "1.0,2.0,3.0")
assert(run(" 1 ", " 2 ") == "1.0,2.0")
assert(run(3, 1, "-1") == "3.0,2.0,1.0")
end

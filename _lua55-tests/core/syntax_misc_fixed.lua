-- Syntax: statements and expressions that load must accept or reject.
local load = loadstring or load
local function ok(src) return load(src) ~= nil end
local function bad(src) return load(src) == nil end

-- ## prefix expressions
do
assert(bad("(a) = 1"))
assert(bad("(a.b) = 1"))
assert(bad("a, (b) = 1, 2"))
end

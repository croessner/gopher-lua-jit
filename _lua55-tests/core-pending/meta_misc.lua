-- Metatables: __concat, __len, __tostring, __name, __gc and __mode.
local T = tostring

-- ## __len on values that have no primitive length
do
local smt = getmetatable("")
smt.__len = function() return "ignored" end
local ok, len = pcall(function() return #"abc" end)
smt.__len = nil
assert(not pcall(function() return #setmetatable({}, {__len = 5}) end))
end

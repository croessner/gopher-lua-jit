-- Arithmetic: normalisation of float keys with integral values.
local T = tostring
local maxint = 9223372036854775807
local minint = -9223372036854775807 - 1

-- ## float keys with integral values address the integer key
do
local t = {}
t[1] = "a"
assert(t[1.0] == "a")
t[2.0] = "b"
assert(t[2] == "b")
assert(#t == 2)
t[1.0] = "c"
assert(t[1] == "c")
assert(rawget(t, 1.0) == "c")
rawset(t, 3.0, "d")
assert(t[3] == "d")
assert(rawget(t, 3) == "d")
assert(#t == 3)
end

-- ## the stored key is an integer
do
local t = {}
t[1.0] = true
t[2^53] = true
t[-3.0] = true
t[0.0] = true
local seen = {}
for k in pairs(t) do seen[T(k)] = true end
assert(seen["1"])
assert(seen["9007199254740992"])
assert(seen["-3"])
assert(seen["0"])
assert(not seen["1.0"])
assert(not seen["9007199254740992.0"])
assert(next({[5.0] = 1}) == 5)
assert(T(next({[5.0] = 1})) == "5")
end

-- ## negative zero is the same key as zero
do
local t = {}
t[0] = "zero"
assert(t[-0.0] == "zero")
assert(t[0.0] == "zero")
t[-0.0] = "neg"
assert(t[0] == "neg")
local n = 0
for _ in pairs(t) do n = n + 1 end
assert(n == 1)
end

-- ## non-integral floats are distinct keys
do
local t = {}
t[1] = "int"
t[1.5] = "float"
t[1.25] = "quarter"
assert(t[1] == "int")
assert(t[1.5] == "float")
assert(t[3 / 2] == "float")
assert(t[1.25] == "quarter")
assert(t[1.75] == nil)
assert(#t == 1)
end

-- ## large keys
do
local t = {}
t[2^53] = "f53"
assert(t[9007199254740992] == "f53")
t[9007199254740993] = "i53+1"
assert(t[2^53] == "f53")
assert(t[9007199254740993] == "i53+1")
t[2^63] = "f63"
assert(t[maxint] == nil)
t[maxint] = "maxint"
assert(t[2^63] == "f63")
assert(t[maxint] == "maxint")
t[minint] = "minint"
assert(t[-(2^63)] == "minint")
t[-(2^63)] = "again"
assert(t[minint] == "again")
t[1e300] = "huge"
assert(t[1e300] == "huge")
local n = 0
for _ in pairs(t) do n = n + 1 end
assert(n == 6)
end

-- ## infinities are valid keys, NaN is not
do
local inf = 1 / 0
local t = {}
t[inf] = 1
t[-inf] = 2
assert(t[inf] == 1)
assert(t[-inf] == 2)
assert(t[1 / 0] == 1)
assert(not pcall(function() t[0 / 0] = 1 end))
assert(not pcall(rawset, t, 0 / 0, 1))
assert(t[0 / 0] == nil)
assert(rawget(t, 0 / 0) == nil)
assert(not pcall(function() t[nil] = 1 end))
assert(t[nil] == nil)
end

-- ## strings and numbers are different keys
do
local t = {}
t[1] = "number"
t["1"] = "string"
t["1.0"] = "string float"
assert(t[1] == "number")
assert(t["1"] == "string")
assert(t[1.0] == "number")
assert(t["1.0"] == "string float")
local n = 0
for _ in pairs(t) do n = n + 1 end
assert(n == 3)
end

-- ## constructors normalise keys
do
local t = {[1.0] = "a", [2] = "b", [3.0] = "c"}
assert(t[1] == "a")
assert(t[2.0] == "b")
assert(t[3] == "c")
assert(#t == 3)
local t = {"x", [1.0] = "y"}
assert(t[1] == "x")
end

-- ## computed keys
do
local t = {}
for i = 1, 10 do t[i / 1] = i end
assert(#t == 10)
for i = 1, 10 do assert(t[i] == i, "computed float key") end
local t = {}
t[10 // 3] = "int"
assert(t[3] == "int")
t[10 / 2] = "float"
assert(t[5] == "float")
t[2 ^ 2] = "pow"
assert(t[4] == "pow")
t[7 // 2.0] = "fdiv"
assert(t[3] == "fdiv")
end

-- ## length and array growth with float indices
do
local t = {}
for i = 1.0, 5.0 do t[i] = true end
assert(#t == 5)
t[#t + 1.0] = true
assert(#t == 6)
table.insert(t, true)
assert(#t == 7)
assert(t[7.0] == true)
assert(table.remove(t) == true)
assert(#t == 6)
end

-- ## booleans and other values as keys
do
local t = {}
local k1, k2 = {}, function() end
t[true] = 1
t[false] = 2
t[k1] = 3
t[k2] = 4
assert(t[true] == 1)
assert(t[false] == 2)
assert(t[k1] == 3)
assert(t[k2] == 4)
assert(t[{}] == nil)
end

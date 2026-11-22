-- Tables: constructors, indexing and the length operator.
local load = loadstring or load
local T = tostring

-- ## positional fields
do
local t = {10, 20, 30}
assert(t[1] == 10 and t[2] == 20 and t[3] == 30)
assert(#t == 3)
assert(t[0] == nil and t[4] == nil)
assert(#{} == 0)
assert(#{nil} == 0)
assert(#{1} == 1)
assert(#{"a", "b"} == 2)
end

-- ## named and computed fields
do
local k = "key"
local t = {a = 1, ["b"] = 2, [k] = 3, [1 + 1] = "two", [2.5] = "float", [true] = "bool"}
assert(t.a == 1)
assert(t.b == 2)
assert(t.key == 3)
assert(t[2] == "two")
assert(t[2.5] == "float")
assert(t[true] == "bool")
assert(t["a"] == 1)
assert(#t == 0 or #t == 2)
end

-- ## mixed fields: positional items are numbered independently
do
local t = {1, a = "x", 2, [10] = "ten", 3}
assert(t[1] == 1 and t[2] == 2 and t[3] == 3)
assert(t.a == "x")
assert(t[10] == "ten")
assert(#t == 3 or #t == 10)
local t = {[1] = "explicit", "positional"}
assert(t[1] == "positional")
local t = {"positional", [1] = "explicit"}
assert(t[1] == "positional")
end

-- ## separators
do
local t = {1, 2, 3,}
assert(#t == 3)
local t = {1; 2; 3;}
assert(#t == 3)
local t = {1, 2; 3}
assert(#t == 3)
local t = {a = 1; b = 2,}
assert(t.a == 1 and t.b == 2)
local t = {
  1,
  2,
}
assert(#t == 2)
assert(load("return {,}") == nil)
assert(load("return {;}") == nil)
assert(load("return {1,,2}") == nil)
assert(load("return {1;;}") == nil)
assert(load("return {,1}") == nil)
assert(load("return {1 2}") == nil)
assert(load("return {a = }") == nil)
assert(load("return {[1] 2}") == nil)
assert(load("return {[1] = }") == nil)
assert(load("return {= 1}") == nil)
assert(load("return {1") == nil)
assert(load("return {a.b = 1}") == nil)
assert(load("return {[] = 1}") == nil)
assert(load("return {}") ~= nil)
assert(load("return {{}}") ~= nil)
assert(load("return {{},}") ~= nil)
end

-- ## multiple results expand only in the last positional field
do
local function mr() return 1, 2, 3 end
local function none() end
assert(#{mr()} == 3)
assert(#{mr(), mr()} == 4)
assert(#{mr(), "x"} == 2)
assert(#{"x", mr()} == 4)
assert(#{(mr())} == 1)
assert(#{mr(), a = 1} == 1)
assert(#{a = 1, mr()} == 3)
assert(#{a = mr()} == 0)
assert(({a = mr()}).a == 1)
assert(#{[1] = mr()} == 1)
assert(#{none()} == 0)
assert(#{none(), none()} == 0 or #{none(), none()} == 1)
assert(#{mr(), nil} == 1 or #{mr(), nil} == 2)
local function va(...) return {...} end
assert(#va() == 0)
assert(#va(1, 2, 3) == 3)
local function va2(...) return {..., "end"} end
assert(#va2(1, 2, 3) == 2)
assert(va2(1, 2, 3)[2] == "end")
end

-- ## nested constructors
do
local t = {{1, 2}, {3, {4, 5, {6}}}, x = {y = {z = "deep"}}}
assert(t[1][2] == 2)
assert(t[2][2][3][1] == 6)
assert(t.x.y.z == "deep")
assert(#t == 2)
assert(#t[2][2] == 3)
local m = {{1, 0}, {0, 1}}
assert(m[1][1] + m[2][2] == 2)
end

-- ## values of every type
do
local f = function() end
local co = coroutine.create(f)
local t = {nil, false, true, 1, 1.5, "s", {}, f, co}
assert(t[1] == nil and t[2] == false and t[3] == true)
assert(T(t[4]) == "1" and T(t[5]) == "1.5")
assert(t[6] == "s" and type(t[7]) == "table")
assert(t[8] == f and t[9] == co)
end

-- ## each evaluation creates a new table
do
local function mk() return {} end
assert(mk() ~= mk())
local a, b = {}, {}
assert(a ~= b)
local list = {}
for i = 1, 3 do list[i] = {i} end
assert(list[1] ~= list[2] and list[1][1] == 1 and list[3][1] == 3)
end

-- ## nil and NaN keys in constructors raise an error
do
assert(not pcall(function() return {[nil] = 1} end))
assert(not pcall(function() return {[0 / 0] = 1} end))
assert(not pcall(function() local k; return {[k] = 1} end))
assert(pcall(function() return {[1 / 0] = 1} end))
end

-- ## duplicate keys: the last one wins for named fields
do
local t = {a = 1, a = 2}
assert(t.a == 2)
local t = {["x"] = 1, x = 2, ["x"] = 3}
assert(t.x == 3)
end

-- ## large constructors
do
local t = {
  1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
  21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40,
  41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60,
  61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80,
  81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100,
  101, 102, 103, 104, 105, 106, 107, 108, 109, 110,
}
assert(#t == 110)
for i = 1, 110 do assert(t[i] == i, "large constructor") end
local big = load("return {" .. string.rep("7,", 3000) .. "}")()
assert(#big == 3000)
assert(big[1] == 7 and big[1500] == 7 and big[3000] == 7 and big[3001] == nil)
local src = "return {"
for i = 1, 500 do src = src .. "k" .. i .. "=" .. i .. "," end
local bign = load(src .. "}")()
assert(bign.k1 == 1 and bign.k250 == 250 and bign.k500 == 500)
local mixed = load("return {" .. string.rep("1, x = 2, [100000] = 3,", 200) .. "}")()
assert(#mixed == 200 or #mixed == 100000)
assert(mixed[200] == 1 and mixed.x == 2 and mixed[100000] == 3)
end

-- ## indexing forms
do
local t = {a = {b = {c = "v"}}, [1] = "one", ["two words"] = 2}
assert(t.a.b.c == "v")
assert(t["a"]["b"]["c"] == "v")
assert(t.a["b"].c == "v")
assert(t[1] == "one")
assert(t["two words"] == 2)
local k1, k2 = "a", "b"
assert(t[k1][k2].c == "v")
assert(({a = 1}).a == 1)
assert(({10, 20})[2] == 20)
assert(#"abc" == 3)
assert(("abc"):len() == 3)
end

-- ## indexing non-tables raises an error (strings index the string library)
do
assert(not pcall(function() local x = nil; return x.a end))
assert(not pcall(function() local x = 1; return x.a end))
assert(not pcall(function() local x = true; return x.a end))
assert(not pcall(function() local x = print; return x.a end))
assert(not pcall(function() local x = nil; return x[1] end))
assert(not pcall(function() local t = {}; return t.a.b end))
assert(pcall(function() local x = "s"; return x.a end))
assert(("s").a == nil)
assert(("s").len == string.len)
assert(not pcall(function() local x = "s"; x.a = 1 end))
end

-- ## the length operator
do
assert(#"" == 0)
assert(#"abc" == 3)
assert(#"a\0b" == 3)
assert(#{1, 2, 3} == 3)
assert(T(#{1, 2, 3}) == "3")
assert(T(#"abc") == "3")
local t = {}
for i = 1, 100 do t[i] = i end
assert(#t == 100)
t[#t + 1] = 101
assert(#t == 101)
t[#t] = nil
assert(#t == 100)
for i = 100, 1, -1 do t[i] = nil end
assert(#t == 0)
assert(not pcall(function() return #nil end))
assert(not pcall(function() return #5 end))
assert(not pcall(function() return #true end))
assert(not pcall(function() return #print end))
end

-- ## table.insert, table.remove and table.concat
do
local t = {}
table.insert(t, "a")
table.insert(t, "b")
table.insert(t, 1, "first")
assert(table.concat(t, ",") == "first,a,b")
assert(table.remove(t) == "b")
assert(table.remove(t, 1) == "first")
assert(#t == 1 and t[1] == "a")
assert(table.concat({}) == "")
assert(table.concat({1, 2, 3}) == "123")
assert(table.concat({1, 2.5, "x"}, "-") == "1-2.5-x")
assert(table.concat({"a", "b", "c"}, ", ", 2, 3) == "b, c")
end

-- ## next and pairs traverse all entries exactly once
do
local t = {10, 20, 30, a = 1, b = 2, [2.5] = "f", [true] = "t"}
local count, sum = 0, 0
for k, v in pairs(t) do
  count = count + 1
  if type(v) == "number" then sum = sum + v end
end
assert(count == 7)
assert(sum == 63)
assert(next({}) == nil)
local k, v = next({"only"})
assert(k == 1 and v == "only")
assert(next({"only"}, 1) == nil)
end

-- ## rawget, rawset, rawequal ignore metamethods
do
local mt = {__index = function() return "meta" end, __newindex = function() error("blocked") end,
            __eq = function() return true end}
local a, b = setmetatable({}, mt), setmetatable({}, mt)
assert(a.x == "meta")
assert(rawget(a, "x") == nil)
assert(not pcall(function() a.x = 1 end))
rawset(a, "x", 1)
assert(rawget(a, "x") == 1)
assert(a.x == 1)
assert(a == b)
assert(not rawequal(a, b))
assert(rawequal(a, a))
end

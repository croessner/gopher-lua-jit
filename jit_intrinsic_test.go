package lua

import "testing"

// jitIntrinsicPrograms exercise library functions that compiled code
// translates in place (differential: interpreter vs JIT).
var jitIntrinsicPrograms = map[string]string{
	"local aliases": `
		local floor, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
		local s = 0
		for i = 1, 300 do s = s + floor(i / 3) + ceil(i / 7) + abs(i - 150) + sqrt(i) end
		return s`,
	"alias replaced": `
		local f = math.floor
		local s = 0
		for i = 1, 300 do
			if i == 100 then f = math.ceil end
			if i == 200 then f = function(x) return x * 2 end end
			s = s + f(i / 3)
		end
		return s`,
	"alias alternates": `
		local fs = {math.floor, math.ceil, math.abs}
		local s = 0
		for i = 1, 300 do
			local f = fs[i % 3 + 1]
			s = s + f(-i / 4)
		end
		return s`,
	"max and min": `
		local s = 0
		for i = 1, 300 do
			s = s + math.max(i, 100) - math.min(i, 200) + math.max(i % 7, i % 5, 3) + math.min(i, 250, i * 2 - 100, 40)
		end
		return s`,
	"max and min of floats": `
		local s = 0
		for i = 1, 300 do
			local x = i / 8
			s = s + math.max(x, 12.5) + math.min(x, 0.75, x * x) - math.max(-x, -3.25)
		end
		return s`,
	"max and min with nan and zeros": `
		local nan = 0 / 0
		local r = {}
		for i = 1, 60 do
			local z = i - i
			r[#r + 1] = 1 / math.max(z, -z)
			r[#r + 1] = 1 / math.max(-z, z)
			r[#r + 1] = 1 / math.min(z, -z)
			r[#r + 1] = 1 / math.min(-z, z)
			local a, b = math.max(nan, i), math.max(i, nan)
			local c, d = math.min(nan, i), math.min(i, nan)
			r[#r + 1] = (a ~= a) and -1 or a
			r[#r + 1] = (b ~= b) and -1 or b
			r[#r + 1] = (c ~= c) and -1 or c
			r[#r + 1] = (d ~= d) and -1 or d
		end
		local s, inf = 0, 0
		for i = 1, #r do
			if r[i] == math.huge then inf = inf + 1 elseif r[i] == -math.huge then inf = inf + 1000 else s = s + r[i] end
		end
		return s, inf`,
	"max of mixed arguments": `
		local s = 0
		for i = 1, 200 do
			s = s + math.max(i, 50.5) + math.min(i * 1.5, 70) + math.max("10", i) + math.max(i)
		end
		local ok1 = pcall(function() for i = 1, 50 do s = s + math.max() end end)
		local ok2 = pcall(function() for i = 1, 50 do s = s + math.max(i, {}) end end)
		return s, ok1, ok2`,
	"max of many arguments": `
		local s = 0
		for i = 1, 200 do s = s + math.max(i % 3, i % 5, i % 7, i % 11, i % 13, i % 17) - math.min(1, 2, 3, 4, 5, i) end
		return s`,
	"clamped index": `
		local t = {}
		for i = 1, 50 do t[i] = i * i end
		local s = 0
		for i = -20, 80 do s = s + t[math.max(1, math.min(i, #t))] end
		return s`,
	"max replaced": `
		local s, max = 0, math.max
		for i = 1, 300 do
			if i == 150 then math.max = function(a, b) return a + b end end
			s = s + math.max(i, 100)
		end
		math.max = max
		return s`,
	"type of values": `
		local values = {1, 2.5, "s", true, false, {}, print, function() end, coroutine.create(function() end)}
		local counts = {}
		for round = 1, 30 do
			for i = 1, #values + 1 do
				local name = type(values[i])
				counts[name] = (counts[name] or 0) + 1
			end
		end
		local names = {}
		for k, v in pairs(counts) do names[#names + 1] = k .. "=" .. v end
		table.sort(names)
		return table.concat(names, " ")`,
	"type checks": `
		local n, strs, tabs, nils = 0, 0, 0, 0
		local mixed = {1, "a", {}, 2, "b", {}, 3}
		for i = 1, 400 do
			local v = mixed[i % 9 + 1]
			if type(v) == "number" then n = n + v
			elseif type(v) == "string" then strs = strs + 1
			elseif type(v) == "table" then tabs = tabs + 1
			elseif type(v) == "nil" then nils = nils + 1 end
			if type(i) == "number" and type(i) ~= "string" then n = n + 1 end
			if "number" == type(i / 2) then n = n + 1 end
		end
		return n, strs, tabs, nils`,
	"type of a changing local": `
		local v = 1
		local s = 0
		for i = 1, 300 do
			if type(v) == "number" then s = s + v v = "x" .. i
			elseif type(v) == "string" then s = s + #v v = {i}
			else s = s + v[1] v = i end
		end
		return s`,
	"type replaced": `
		local s, t = 0, type
		for i = 1, 300 do
			if i == 150 then type = function() return "number" end end
			if type("x") == "number" then s = s + 1 end
			if type(i) == "number" then s = s + 100 end
		end
		type = t
		return s`,
	"tonumber": `
		local s = 0
		local mixed = {"12", 7, "0x10", "junk", 2.5, " 8 "}
		for i = 1, 300 do
			s = s + tonumber(i) + tonumber(i / 4) + (tonumber(mixed[i % 6 + 1]) or -1)
			s = s + (tonumber("11", 2) or 0) + (tonumber(nil) or 0.5)
		end
		local ok = pcall(function() for i = 1, 50 do s = s + tonumber() end end)
		return s, ok`,
	"constant comparisons": `
		local c = 0
		local kind = "alpha"
		for i = 1, 300 do
			if kind == "alpha" then c = c + 1 end
			if kind ~= "beta" then c = c + 10 end
			if "x" == "x" then c = c + 100 end
			if i == "1" then c = c + 1000 end
			if "1" == i then c = c + 1000 end
			if kind == nil or kind == false or kind == 1 then c = c + 10000 end
			if print == "print" or math == "math" then c = c + 100000 end
			if i == 200 then kind = "beta" end
		end
		return c`,
}

func TestJITIntrinsicPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitIntrinsicPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITIntrinsicsAreNative checks that the library functions with a
// native form do not leave native code.
func TestJITIntrinsicsAreNative(t *testing.T) {
	skipWithoutJIT(t)
	programs := map[string]string{
		"local alias": `local floor = math.floor local s = 0 for i = 1, 20000 do s = s + floor(i / 3) end return s`,
		"max and min": `local s = 0 for i = 1, 20000 do s = s + math.max(i, 10) + math.min(i, 5) end return s`,
		"type":        `local c = 0 for i = 1, 20000 do if type(i) == "number" then c = c + 1 end end return c`,
		"type of a table element": `
			local t = {1, 2, 3}
			local c = 0
			for i = 1, 20000 do if type(t[i % 3 + 1]) == "number" then c = c + 1 end end
			return c`,
		"tonumber": `local s = 0 for i = 1, 20000 do s = s + tonumber(i) end return s`,
	}
	for name, src := range programs {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			_, st := runChunk(jitTestOptions(version, 5), src)
			if st.Compiled == 0 || st.Callouts > 100 || st.Blacklisted != 0 {
				t.Errorf("%s (%v): the call is not native: %s", name, version, st)
			}
		}
	}
}

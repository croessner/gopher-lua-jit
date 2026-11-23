package lua

import "testing"

// jitGlobalPrograms exercise global variables that compiled code reads
// and writes as fields of the environment table (differential:
// interpreter vs JIT).
var jitGlobalPrograms = map[string]string{
	"counter": `
		count, total = 0, 0.5
		for i = 1, 300 do count = count + 1 total = total + count / 4 end
		local c, t = count, total
		count, total = nil, nil
		return c, t`,
	"counter in a function": `
		hits = 0
		local function touch(n) for i = 1, n do hits = hits + i % 3 end end
		touch(200) touch(300)
		local h = hits
		hits = nil
		return h`,
	"string and boolean globals": `
		label, enabled = "abc", true
		local s = 0
		for i = 1, 300 do
			if enabled then s = s + #label end
			if i == 100 then label = "abcdef" end
			if i == 200 then enabled = false end
		end
		label, enabled = nil, nil
		return s`,
	"global changes its type": `
		g = 1
		local s = 0
		for i = 1, 300 do
			if type(g) == "number" then s = s + g end
			if i % 50 == 0 then g = "s" elseif i % 50 == 1 then g = i elseif i % 50 == 25 then g = 0.5 else g = g end
		end
		g = nil
		return s`,
	"global created and removed in the loop": `
		local s = 0
		for i = 1, 300 do
			if i % 20 == 5 then fresh = i end
			if fresh then s = s + fresh end
			if i % 20 == 15 then fresh = nil end
		end
		return s`,
	"undefined global": `
		local c = 0
		for i = 1, 300 do if missing == nil then c = c + 1 end end
		return c`,
	"strict environment": `
		local declared = {x = true, y = true}
		setmetatable(_G, {
			__newindex = function(t, k, v)
				if not declared[k] then error("undeclared " .. k, 2) end
				rawset(t, k, v)
			end,
			__index = function(_, k) error("undefined " .. k, 2) end,
		})
		x, y = 0, 1
		local ok, err
		for i = 1, 300 do
			x = x + y
			if i == 250 then ok, err = pcall(function() z = 1 end) end
		end
		local ok2 = pcall(function() for i = 1, 50 do x = x + undefinedGlobal end end)
		local r = x
		setmetatable(_G, nil)
		x, y = nil, nil
		return r, ok, ok2, (tostring(err):gsub("^.-:%d+: ", ""))`,
	"function with another environment": `
		local env = setmetatable({n = 0}, {__index = _G})
		local function count(k) for i = 1, k do n = n + 1 end return n end
		local r
		if setfenv then
			setfenv(count, env)
			r = count(200) + count(100)
			local other = setmetatable({n = 1000}, {__index = _G})
			setfenv(count, other)
			r = r + count(200) + env.n + other.n
		else
			n = 0
			r = count(200) + count(100)
			n = nil
		end
		return r`,
	"global read by an inlined function": `
		scale = 3
		local function scaled(v) return v * scale end
		local s = 0
		for i = 1, 300 do
			s = s + scaled(i)
			if i == 150 then scale = 0.5 end
		end
		scale = nil
		return s`,
	"global written by an inlined function": `
		acc = 0
		local function add(v) acc = acc + v return acc end
		local s = 0
		for i = 1, 300 do s = s + add(i) % 7 end
		local a = acc
		acc = nil
		return s, a`,
	// (Lua 5.5 profile: globals are fields of the upvalue _ENV)
	"environment replaced, library call":   `local s = 0 for i = 1, 300 do s = s + math.abs(-1) if i == 150 then _ENV = {math = {abs = function() return 100 end}} end end return s`,
	"environment replaced, number read":    `n = 1 local s = 0 for i = 1, 300 do s = s + n if i == 150 then _ENV = {n = 100} end end return s`,
	"environment replaced, number written": `n = 0 local g = _ENV for i = 1, 300 do n = n + 1 if i == 150 then _ENV = {n = 1000} end end return n, g.n`,
	"environment replaced by a function":   `n = 0 local function swap() _ENV = {n = 500} end for i = 1, 300 do n = n + 1 if i == 100 then swap() end end return n`,
	"local environment":                    `local s = 0 do local _ENV = {n = 5} for i = 1, 300 do n = n + 1 s = s + n end end return s`,
	"global shadowed by rawset": `
		v = 1
		local s = 0
		for i = 1, 300 do
			s = s + v
			if i == 100 then rawset(_G, "v", 10) end
			if i == 200 then rawset(_G, "v", nil) rawset(_G, "v", 100) end
		end
		v = nil
		return s`,
}

func TestJITGlobalPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitGlobalPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITNumberGlobalsAreNative checks that a loop that updates a number
// global does not leave native code on every access.
func TestJITNumberGlobalsAreNative(t *testing.T) {
	skipWithoutJIT(t)
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5),
			`count = 0 for i = 1, 20000 do count = count + 1 end local c = count count = nil return c`)
		if st.Compiled == 0 || st.Callouts > 100 || st.Blacklisted != 0 {
			t.Errorf("%v: global access is not native: %s", version, st)
		}
	}
}

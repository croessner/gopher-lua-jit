package lua

import "testing"

// jitStringPrograms exercise string comparisons, string methods and
// string library calls in compiled code (differential: interpreter vs
// JIT).
var jitStringPrograms = map[string]string{
	"equality with constants": `
		local words = {"alpha", "beta", "gamma", "delta", "", "gamma"}
		local c = 0
		for i = 1, 300 do
			local w = words[i % 6 + 1]
			if w == "gamma" then c = c + 1 end
			if w ~= "alpha" then c = c + 10 end
			if w == "" then c = c + 100 end
			if "delta" == w then c = c + 1000 end
		end
		return c`,
	"equality of built strings": `
		local parts = {"ab", "cd", "ef"}
		local built = {}
		for i = 1, 12 do built[i] = parts[i % 3 + 1] .. parts[(i + 1) % 3 + 1] end
		local c = 0
		for i = 1, 300 do
			local x, y = built[i % 12 + 1], built[(i * 5) % 12 + 1]
			if x == y then c = c + 1 end
			if x == "cdef" then c = c + 10 end
			if x ~= y then c = c + 100 end
		end
		return c`,
	"equality of long strings": `
		local a = string.rep("x", 100)
		local b = string.rep("x", 99) .. "x"
		local d = string.rep("x", 99) .. "y"
		local short = string.rep("z", 64)
		local short2 = string.rep("z", 63) .. "z"
		local all = {a, b, d, short, short2}
		local c = 0
		for i = 1, 200 do
			local x, y = all[i % 5 + 1], all[(i * 3) % 5 + 1]
			if x == y then c = c + 1 end
			if x == a then c = c + 10 end
		end
		return c`,
	"equality with embedded zeros": `
		local a, b, d = "a\0b", "a\0" .. "b", "a\0c"
		local all = {a, b, d}
		local c = 0
		for i = 1, 200 do
			if all[i % 3 + 1] == all[(i + 1) % 3 + 1] then c = c + 1 end
			if all[i % 3 + 1] == "a\0b" then c = c + 10 end
		end
		return c`,
	"equality with changing types": `
		local values = {"x", 1, "x", nil, "y", true, {}, "1"}
		local c = 0
		for i = 1, 400 do
			local v = values[i % 8 + 1]
			if v == "x" then c = c + 1 end
			if v == "1" then c = c + 10 end
			if v ~= "y" then c = c + 100 end
		end
		return c`,
	"string upvalues": `
		local mode, flag, missing = "fast", true, nil
		local function run(n)
			local c = 0
			for i = 1, n do
				if mode == "fast" then c = c + 1 else c = c + #mode end
				if flag then c = c + 10 end
				if missing == nil then c = c + 100 end
			end
			return c
		end
		local r = run(200)
		mode, flag, missing = "slower", false, 1
		r = r + run(200)
		mode = 7
		return r + run(200)`,
	"upvalue changed inside the loop": `
		local state = "a"
		local function advance() if state == "a" then state = "bb" elseif state == "bb" then state = false else state = "a" end end
		local c = 0
		for i = 1, 300 do
			if state == "a" then c = c + 1 elseif state then c = c + #state * 10 else c = c + 1000 end
			if i % 7 == 0 then advance() end
		end
		return c`,
	"byte": `
		local s = "the quick brown fox"
		local sum = 0
		for i = 1, 300 do
			sum = sum + s:byte(i % #s + 1) + string.byte(s, (i * 7) % #s + 1)
		end
		return sum`,
	"byte outside the string": `
		local s = "hello"
		local sum, nils = 0, 0
		for i = -8, 12 do
			for round = 1, 12 do
				local b = s:byte(i)
				if b then sum = sum + b else nils = nils + 1 end
			end
		end
		return sum, nils`,
	"byte with other arguments": `
		local s = "hello world"
		local sum = 0
		for i = 1, 200 do
			local a, b, c = s:byte(1, 3)
			sum = sum + a + b + c + s:byte() + select("#", s:byte(2, 5)) + (s:byte(i % 11 + 1.0) or 0)
		end
		local ok = pcall(function() for i = 1, 50 do sum = sum + s:byte(1.5) end end)
		local ok2 = pcall(function() for i = 1, 50 do sum = sum + s:byte("x") end end)
		return sum, ok, ok2`,
	"byte scanner": `
		local text = "a1b22c333 d4444,e55555"
		local digits, letters, other = 0, 0, 0
		for round = 1, 40 do
			for i = 1, #text do
				local b = text:byte(i)
				if b >= 48 and b <= 57 then digits = digits + b - 48
				elseif b >= 97 and b <= 122 then letters = letters + 1
				else other = other + 1 end
			end
		end
		return digits, letters, other`,
	"len": `
		local words = {"a", "bb", "", "dddd"}
		local n = 0
		for i = 1, 300 do
			local w = words[i % 4 + 1]
			n = n + w:len() + string.len(w) + #w + string.len(i)
		end
		return n`,
	"methods of changing receivers": `
		local values = {"abc", "de", 5, "f"}
		local n = 0
		for i = 1, 200 do
			local v = values[i % 4 + 1]
			if type(v) == "string" then n = n + v:len() + v:byte(1) else n = n + v end
		end
		local ok = pcall(function() for i = 1, 50 do n = n + values[i % 4 + 1]:len() end end)
		return n, ok`,
	"method replaced": `
		local s = "hello"
		local n = 0
		local len, byte = string.len, string.byte
		for i = 1, 300 do
			n = n + s:len() + s:byte(1)
			if i == 100 then string.len = function() return 1000 end end
			if i == 200 then string.byte = function() return 5 end end
		end
		string.len, string.byte = len, byte
		return n`,
	"method added and index replaced": `
		local s = "hello"
		local n = 0
		for i = 1, 300 do
			if i == 100 then string.twice = function(x) return #x * 2 end end
			if i >= 100 then n = n + s:twice() end
			n = n + s:len()
			if i == 200 then getmetatable("").__index = {len = function() return 7 end, twice = function() return 1 end} end
		end
		getmetatable("").__index = string
		string.twice = nil
		return n`,
	"other string methods": `
		local s = "Hello World"
		local n = 0
		for i = 1, 100 do
			n = n + #s:upper() + #s:sub(2, i % 5 + 2) + (s:find("o", 1, true) or 0) + #s:rep(2)
		end
		return n`,
}

func TestJITStringPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitStringPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITStringOperationsAreNative checks that string comparisons and
// the string functions with a native form do not leave native code.
func TestJITStringOperationsAreNative(t *testing.T) {
	skipWithoutJIT(t)
	programs := map[string]string{
		"equality": `
			local words = {"alpha", "beta", "gamma", "delta"}
			local c = 0
			for i = 1, 20000 do if words[i % 4 + 1] == "gamma" then c = c + 1 end end
			return c`,
		"byte method": `local s = "the quick brown fox" local n = 0 for i = 1, 20000 do n = n + s:byte(i % #s + 1) end return n`,
		"byte function": `
			local s, byte = "the quick brown fox", string.byte
			local n = 0
			for i = 1, 20000 do n = n + byte(s, i % #s + 1) end
			return n`,
		"len method": `local words = {"a", "bb", "ccc"} local n = 0 for i = 1, 20000 do n = n + words[i % 3 + 1]:len() end return n`,
		"string upvalue": `
			local mode = "fast"
			local function run() local c = 0 for i = 1, 20000 do if mode == "fast" then c = c + #mode end end return c end
			return run()`,
	}
	for name, src := range programs {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			_, st := runChunk(jitTestOptions(version, 5), src)
			if st.Compiled == 0 || st.Callouts > 100 || st.Blacklisted != 0 {
				t.Errorf("%s (%v): not native: %s", name, version, st)
			}
		}
	}
}

package lua

import (
	"bytes"
	"strings"
	"testing"
)

// jitNarrowPrograms exercise the integer twins of float loop indexes in
// the Lua 5.1 profile (differential: interpreter vs JIT). The programs
// also run in the Lua 5.5 profile, where the indexes are integers.
var jitNarrowPrograms = map[string]string{
	"neighbours": `
		local t = {}
		for i = 1, 200 do t[i] = i * 3 end
		local s = 0
		for i = 2, 199 do s = s + t[i] - t[i - 1] + 2 * t[i + 1] end
		return s`,
	"index arithmetic": `
		local n = 120
		local t = {}
		for i = 1, 2 * n do t[i] = i % 13 end
		local s = 0
		for i = 1, n do
			s = s + t[2 * i] + 3 * t[2 * i - 1] + 5 * t[n - i + 1] + 7 * t[i % 7 + 1] + t[(i * 3) % n + 1]
		end
		return s`,
	"reverse in place": `
		local t = {}
		for i = 1, 101 do t[i] = i end
		for round = 1, 3 do
			local n = #t
			for i = 1, n / 2 do t[i], t[n - i + 1] = t[n - i + 1], t[i] end
		end
		local s = 0
		for i = #t, 1, -1 do s = s * 3 % 1000003 + t[i] end
		return s`,
	"binary search": `
		local t = {}
		for i = 1, 500 do t[i] = i * 2 end
		local hits = 0
		for key = 1, 1000 do
			local lo, hi = 1, #t
			while lo <= hi do
				local mid = math.floor((lo + hi) / 2)
				if t[mid] == key then hits = hits + mid break
				elseif t[mid] < key then lo = mid + 1
				else hi = mid - 1 end
			end
		end
		return hits`,
	"heap parents": `
		local t = {}
		for i = 1, 300 do t[i] = (i * 37) % 101 end
		local s = 0
		for i = 2, 300 do
			local p = math.floor(i / 2)
			if t[p] < t[i] then t[p], t[i] = t[i], t[p] end
			s = s + t[math.floor(i / 3) + 1] + math.floor(i / -4) + math.floor(-i / 2)
		end
		return s, t[1], t[150]`,
	"floor of negative quotients": `
		local t = {}
		for i = 1, 40 do t[i] = i end
		local s = 0
		for round = 1, 20 do
			for i = -19, 19 do s = s + t[math.floor(i / 2) + 11] * 3 + math.floor(i / 7) + math.floor(i / -3) end
		end
		return s`,
	"matrix": `
		local n, m = 12, 9
		local grid, flat, row = {}, {}, {}
		for i = 1, n do
			grid[i] = {}
			row[i] = i * 100
			for j = 1, m do grid[i][j] = i * j flat[(i - 1) * m + j] = i - j end
		end
		local s = 0
		for round = 1, 10 do
			for i = 1, n do
				for j = 1, m do s = s + grid[i][j] * flat[(i - 1) * m + j] + row[i] end
			end
		end
		return s`,
	"sieve": `
		local n = 2000
		local flags = {}
		for i = 1, n do flags[i] = true end
		for i = 2, n do
			if flags[i] then for j = i * i, n, i do flags[j] = false end end
		end
		local c = 0
		for i = 2, n do if flags[i] then c = c + 1 end end
		return c`,
	"modulo of negative indexes": `
		local t = {}
		for i = 1, 7 do t[i] = i * i end
		local s = 0
		for round = 1, 20 do
			for i = -20, 20 do s = s + i % 7 + t[i % 7 + 1] - i % -3 + (i % 5) * (i % 2) end
		end
		return s`,
	"negated index": `
		local t = {}
		for i = 1, 30 do t[i] = i end
		local s = 0
		for round = 1, 20 do
			for i = -30, -1 do s = s + t[-i] * 2 + t[-(-(-i))] end
		end
		return s`,
	"fractional start": `
		local t = {}
		for i = 1, 40 do t[i] = i end
		local s = 0
		for round = 1, 40 do
			local from = 1
			if round % 4 == 0 then from = 1.5 end
			for x = from, 30 do s = s + (t[x] or 0.25) end
		end
		return s`,
	"fractional step": `
		local t = {}
		for i = 1, 40 do t[i] = i end
		local s = 0
		for round = 1, 40 do
			local step = 1
			if round % 3 == 0 then step = 0.5 end
			for x = 1, 20, step do s = s + (t[x] or 0.125) end
		end
		return s`,
	"unbounded limit": `
		local t = {}
		for i = 1, 60 do t[i] = i end
		local s = 0
		for round = 1, 30 do
			for i = 1, math.huge do
				if i > 50 then break end
				s = s + t[i]
			end
			for i = 1, 1e300 do
				if i > 20 then break end
				s = s - t[i] % 3
			end
		end
		return s`,
	"limit changes between entries": `
		local t = {}
		for i = 1, 60 do t[i] = i end
		local function sum(from, to)
			local s = 0
			for i = from, to do
				if i - from > 40 then break end
				s = s + (t[i] or 1) + i % 5
			end
			return s
		end
		local s = 0
		for round = 1, 30 do s = s + sum(1, 30) end
		s = s + sum(1, math.huge) + sum(1, 2 ^ 40) + sum(3, 20.5) + sum(2.5, 30)
		for round = 1, 30 do s = s + sum(2, 25) end
		return s`,
	"beyond 31 bits": `
		local s = 0
		local t = {}
		for round = 1, 20 do
			for i = 2 ^ 31 - 6, 2 ^ 31 + 6 do
				t[i] = round
				s = s + i % 7 + t[i] + (t[i - 1] or 0)
			end
		end
		return s`,
	"near the exact range": `
		local s = 0
		for round = 1, 20 do
			for i = 2 ^ 52 - 5, 2 ^ 52 + 5 do s = s + i % 3 end
			for i = 2 ^ 53 - 6, 2 ^ 53 - 1 do s = s + i % 5 end
			for i = -(2 ^ 52) - 3, -(2 ^ 52) + 3 do s = s + i % 4 end
		end
		return s`,
	"negative zero": `
		local r = {}
		local zero = 0
		for round = 1, 30 do
			for i = -zero, 1 do r[#r + 1] = 1 / i end
			for i = zero * -1, -1, -1 do r[#r + 1] = 1 / i end
			local x = (round - round) * -1
			r[#r + 1] = 1 / x
			r[#r + 1] = 1 / -(round - round)
		end
		local pos, neg = 0, 0
		for i = 1, #r do
			if r[i] == math.huge then pos = pos + 1 elseif r[i] == -math.huge then neg = neg + 1 end
		end
		return pos, neg, #r`,
	"copy of the loop variable changed in the body": `
		local t = {}
		for i = 1, 50 do t[i] = i end
		local s = 0
		for round = 1, 20 do
			for i = 1, 40 do
				local v, k = t[i], i
				k = k + 0.5
				s = s + v + k + (t[k] or 0.25)
				k = k * 2
				s = s + (t[k] or 0.5) + t[i]
			end
		end
		return s`,
	"while counter": `
		local t = {}
		for i = 1, 300 do t[i] = i % 11 end
		local s, i = 0, 1
		while i <= 300 do
			s = s + t[i] + i % 3
			i = i + 1
		end
		local j = 300
		repeat s = s + t[j] * 2 j = j - 2 until j < 1
		return s`,
	"outer index in inner loops": `
		local t = {}
		for i = 1, 50 do t[i] = i end
		local s = 0
		for i = 1, 40 do
			local k = 0
			while k < 5 do s = s + t[i] + t[i + k] k = k + 1 end
			for j = 1, 3 do s = s + t[i + j] * t[j] end
		end
		return s`,
	"nan and infinite bounds": `
		local nan = 0 / 0
		local s = 0
		local t = {1, 2, 3}
		for round = 1, 40 do
			for i = 1, nan do s = s + 1 end
			for i = nan, 3 do s = s + 10 end
			for i = 1, -math.huge do s = s + 100 end
			for i = 3, 1, -1 do s = s + t[i] end
		end
		return s`,
	"inlined element access": `
		local t = {}
		for i = 1, 100 do t[i] = i end
		local function at(a, i) return a[i] end
		local function wrap(i, n) return i % n + 1 end
		local s = 0
		for round = 1, 10 do
			for i = 1, 100 do s = s + at(t, i) + at(t, wrap(i, 100)) end
		end
		return s`,
	"length as index": `
		local t = {}
		local s = 0
		for i = 1, 200 do
			t[#t + 1] = i
			s = s + t[#t] + t[#t - i + 1] + #t % 7
		end
		local str = "abcdefghij"
		for i = 1, 100 do s = s + t[#str] + t[#str + i] end
		return s`,
	"float values that are not indexes": `
		local t = {}
		for i = 1, 20 do t[i] = i end
		local s, x = 0, 1
		for i = 1, 200 do
			x = x * 1.5 % 17
			s = s + (t[x] or 0.125) + (t[math.floor(x) + 1] or 0) + x % 3
		end
		return s`,
}

func TestJITNarrowPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitNarrowPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITNarrowedLoopsStayNative checks that narrowing does not make
// loops unstable: wrong guesses about a loop turn narrowing off for it
// instead of sending it back to the interpreter.
func TestJITNarrowedLoopsStayNative(t *testing.T) {
	skipWithoutJIT(t)
	for _, name := range []string{"neighbours", "sieve", "unbounded limit", "limit changes between entries", "near the exact range"} {
		_, st := runChunk(jitTestOptions(Lua51, 5), jitNarrowPrograms[name])
		if st.Compiled == 0 || st.Blacklisted != 0 || st.Invalidated > 3 {
			t.Errorf("%s: loops do not stay native: %s", name, st)
		}
	}
}

// loopBlocks returns the part of an IR dump that follows the entry
// block: the code that runs on every iteration.
func loopBlocks(dump string) string {
	if i := strings.Index(dump, "\nb1:"); i >= 0 {
		return dump[i:]
	}
	return ""
}

// TestJITIndexIsNarrowed checks that a loop of the Lua 5.1 profile uses
// its index as a table key without converting it on every iteration.
func TestJITIndexIsNarrowed(t *testing.T) {
	skipWithoutJIT(t)
	defer func(old bool) { jitDumpIR = old }(jitDumpIR)
	jitDumpIR = true
	tests := map[string]string{
		"index":      `local t = {} for i = 1, 100 do t[i] = i end local s = 0 for i = 1, 100 do s = s + t[i] end return s`,
		"neighbours": `local t = {} for i = 1, 102 do t[i] = i end local s = 0 for i = 2, 100 do s = s + t[i - 1] + t[i + 1] end return s`,
		"modulo":     `local t = {1, 2, 3, 4, 5, 6, 7} local s = 0 for i = 1, 100 do s = s + t[i % 7 + 1] end return s`,
		"length":     `local t = {} for i = 1, 100 do t[#t + 1] = i end return #t`,
		"halves":     `local t = {} for i = 1, 100 do t[i] = i end local s = 0 for i = 2, 100 do s = s + t[math.floor(i / 2)] end return s`,
		"inner loop": `local t = {} for i = 1, 20 do t[i] = i end local s = 0 for i = 1, 20 do for j = 1, 20 do s = s + t[i] * t[j] end end return s`,
	}
	for name, src := range tests {
		var log bytes.Buffer
		opts := jitTestOptions(Lua51, 5)
		opts.JIT.Log = &log
		if out, st := runChunk(opts, src); st.Compiled == 0 {
			t.Errorf("%s: nothing was compiled (%s)", name, out)
			continue
		}
		dumps := strings.Split(log.String(), "IR before optimization:")[1:]
		if len(dumps) == 0 {
			t.Errorf("%s: no IR in the log", name)
		}
		for _, dump := range dumps {
			if body := loopBlocks(dump); strings.Contains(body, "FloatToInt") {
				t.Errorf("%s: the loop converts floats to integers:\n%s", name, dump)
			}
		}
	}
}

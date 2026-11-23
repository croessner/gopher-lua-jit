package lua

import "testing"

// jitConstTablePrograms exercise tables that compiled code reaches
// through an upvalue or a global and therefore treats as constants
// (differential: interpreter vs JIT).
var jitConstTablePrograms = map[string]string{
	"upvalue array": `
		local t = {}
		for i = 1, 300 do t[i] = i % 17 end
		local function sum()
			local s = 0
			for i = 1, #t do s = s + t[i] end
			for i = 2, #t - 1 do t[i] = t[i - 1] + t[i + 1] end
			return s + t[150]
		end
		return sum() + sum()`,
	"global array": `
		data = {}
		for i = 1, 300 do data[i] = i * 0.5 end
		local function sum()
			local s = 0
			for i = 1, #data do s = s + data[i] data[i] = s end
			return s
		end
		local r = sum() + sum()
		data = nil
		return r`,
	"upvalue fields": `
		local acc = {sum = 0, count = 0, last = 0.5}
		local function feed(n)
			for i = 1, n do
				acc.sum = acc.sum + i
				acc.count = acc.count + 1
				acc.last = acc.sum / acc.count
			end
		end
		feed(200) feed(300)
		return acc.sum, acc.count, acc.last`,
	"global fields": `
		state = {x = 1, y = 2, name = "s"}
		local function step(n)
			for i = 1, n do state.x = state.x + state.y state.y = state.y + 1 end
			return #state.name
		end
		local r = step(300)
		local x, y = state.x, state.y
		state = nil
		return r, x, y`,
	"upvalue replaced": `
		local t = {1, 2, 3, 4, 5}
		local function sum(n)
			local s = 0
			for i = 1, n do s = s + t[i % 5 + 1] end
			return s
		end
		local r = sum(200)
		t = {10, 20, 30, 40, 50}
		r = r + sum(200)
		t = {1.5, 2.5, 3.5, 4.5, 5.5}
		r = r + sum(200)
		t = {"a", "b", "c", "d", "e"}
		local ok = pcall(sum, 200)
		return r, ok`,
	"upvalue replaced inside the loop": `
		local t = {1, 2, 3, 4, 5}
		local other = {100, 200, 300, 400, 500}
		local s = 0
		local function run()
			for i = 1, 300 do
				s = s + t[i % 5 + 1]
				if i == 150 then t = other end
			end
		end
		run()
		return s`,
	"array changes its kind": `
		local t = {}
		for i = 1, 50 do t[i] = i end
		local function sum()
			local s = 0
			for i = 1, #t do s = s + (tonumber(t[i]) or 0) end
			return s
		end
		local r = sum() + sum()
		t[10] = 0.5
		r = r + sum() + sum()
		t[20] = "7"
		r = r + sum() + sum()
		t[30] = nil
		return r`,
	"upvalue array of objects": `
		local objs = {}
		for i = 1, 60 do objs[i] = {pos = {x = i, y = -i}, w = i % 3} end
		local function total()
			local s = 0
			for i = 1, #objs do
				local o = objs[i]
				s = s + o.pos.x * o.w - o.pos.y
			end
			for _, o in ipairs(objs) do s = s + o.w end
			return s
		end
		return total() + total()`,
	"upvalue object with methods": `
		local Counter = {}
		Counter.__index = Counter
		function Counter:add(n) self.total = self.total + n return self.total end
		function Counter:get() return self.total end
		local c = setmetatable({total = 0}, Counter)
		local function run(n)
			local s = 0
			for i = 1, n do s = s + c:add(i) - c:get() + c.total end
			return s
		end
		return run(300), c.total`,
	"metatable set on a constant table": `
		local t = {1, 2, 3}
		local function sum(n)
			local s = 0
			for i = 1, n do s = s + (t[i % 4 + 1] or 100) + #t end
			return s
		end
		local r = sum(200)
		setmetatable(t, {__index = function(_, k) return k * 1000 end, __len = function() return 7 end})
		return r, sum(200)`,
	"table shared by nested closures": `
		local grid = {}
		for i = 1, 20 do grid[i] = {} for j = 1, 20 do grid[i][j] = i + j end end
		local function row(i)
			local r = grid[i]
			local s = 0
			for j = 1, #r do s = s + r[j] end
			return s
		end
		local function all()
			local s = 0
			for i = 1, #grid do s = s + row(i) end
			return s
		end
		return all() + all()`,
	"strings in upvalues": `
		local name = "abcdef"
		local words = {"x", "yy", "zzz"}
		local function run(n)
			local s = 0
			for i = 1, n do s = s + #name + #words[i % 3 + 1] end
			return s
		end
		return run(300)`,
	"append through an upvalue": `
		local out = {}
		local function emit(n)
			for i = 1, n do out[#out + 1] = i * 2 end
		end
		emit(100) emit(200)
		local s = 0
		for i = 1, #out do s = s + out[i] end
		return s, #out`,
}

func TestJITConstTablePrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitConstTablePrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITConstTablesAreNative checks that loops over tables in upvalues
// and globals do not leave native code on every access.
func TestJITConstTablesAreNative(t *testing.T) {
	skipWithoutJIT(t)
	programs := map[string]string{
		"upvalue array": `
			local t = {}
			for i = 1, 100 do t[i] = i end
			local function sum()
				local s = 0
				for k = 1, 200 do for i = 1, #t do s = s + t[i] t[i] = t[i] + 1 end end
				return s
			end
			return sum()`,
		"global array": `
			data = {}
			for i = 1, 100 do data[i] = i end
			local function sum()
				local s = 0
				for k = 1, 200 do for i = 1, #data do s = s + data[i] end end
				return s
			end
			return sum()`,
		"upvalue fields": `
			local acc = {sum = 0, count = 0}
			local function feed(n)
				for i = 1, n do acc.sum = acc.sum + i acc.count = acc.count + 1 end
			end
			feed(20000)
			return acc.sum`,
	}
	for name, src := range programs {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			_, st := runChunk(jitTestOptions(version, 5), src)
			if st.Compiled == 0 || st.Callouts > 200 || st.Blacklisted != 0 {
				t.Errorf("%s (%v): access is not native: %s", name, version, st)
			}
		}
	}
}

// jitRepeatedTraversalPrograms traverse linked structures several times,
// so that the variable of the inner loop holds nil when the outer loop
// is compiled and the last node misses a field on every traversal.
var jitRepeatedTraversalPrograms = map[string]string{
	"list": `
		local list
		for i = 1, 60 do list = {v = i, next = list} end
		local s = 0
		for k = 1, 100 do
			local n = list
			while n do s = s + n.v n = n.next end
		end
		return s`,
	"list with optional fields": `
		local list
		for i = 1, 40 do list = {v = i, next = list, extra = (i % 7 == 0) and i or nil} end
		local s = 0
		for k = 1, 60 do
			local n = list
			while n do
				s = s + n.v + (n.extra or 0)
				n = n.next
			end
		end
		return s`,
	"short lists": `
		local lists = {}
		for j = 1, 30 do
			local list
			for i = 1, j % 4 + 1 do list = {v = i * j, next = list} end
			lists[j] = list
		end
		local s = 0
		for k = 1, 40 do
			for j = 1, #lists do
				local n = lists[j]
				while n do s = s + n.v n = n.next end
			end
		end
		return s`,
	"tree walk with parent links": `
		local root = {depth = 0}
		local leaf = root
		for i = 1, 50 do leaf = {depth = i, parent = leaf} end
		local s = 0
		for k = 1, 80 do
			local n = leaf
			while n.parent do s = s + n.depth n = n.parent end
		end
		return s`,
}

func TestJITRepeatedTraversalPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitRepeatedTraversalPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	// the nodes are visited natively: what remains are the callouts of
	// the loop that builds the list
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5), jitRepeatedTraversalPrograms["list"])
		if st.Compiled == 0 || st.Callouts > 600 {
			t.Errorf("%v: repeated list traversal is not native: %s", version, st)
		}
	}
}

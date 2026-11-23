package lua

import "testing"

// jitCalloutPrograms exercise what Go code and called functions can see
// of a compiled loop while the interpreter executes one of its
// instructions: compiled code writes back only the registers that
// instruction uses (differential: interpreter vs JIT).
var jitCalloutPrograms = map[string]string{
	"locals read by a debugger": `
		local seen = {}
		local function look()
			local n = 1
			while true do
				local name, value = debug.getlocal(2, n)
				if not name then break end
				if name == "acc" or name == "i" or name == "half" or name == "flag" then
					seen[#seen + 1] = name .. "=" .. tostring(value)
				end
				n = n + 1
			end
		end
		local acc, half, flag = 0, 0.5, false
		for i = 1, 120 do
			acc = acc + i
			half = half * 1.01
			flag = i % 2 == 0
			if i % 40 == 0 then look() end
		end
		return table.concat(seen, " "), acc, half, flag`,
	"locals changed by a debugger": `
		local function poke(target, value)
			local n = 1
			while true do
				local name = debug.getlocal(2, n)
				if not name then break end
				if name == target then debug.setlocal(2, n, value) end
				n = n + 1
			end
		end
		local acc, step = 0, 1
		for i = 1, 200 do
			acc = acc + step
			if i == 50 then poke("acc", 1000) end
			if i == 100 then poke("step", 0.5) end
			if i == 150 then poke("acc", "x") acc = #acc end
		end
		return acc, step`,
	"yield inside a called function": `
		local function produce(v) coroutine.yield(v) return v * 2 end
		local co = coroutine.wrap(function()
			local sum, count = 0, 0
			for i = 1, 60 do
				sum = sum + produce(i)
				count = count + 1
			end
			return -sum - count
		end)
		local total = 0
		for k = 1, 61 do total = total + co() end
		return total`,
	"yield called directly": `
		local co = coroutine.wrap(function()
			local sum = 0
			for i = 1, 80 do
				sum = sum + i
				if i % 10 == 0 then coroutine.yield(sum) end
			end
			return -sum
		end)
		local total = 0
		for k = 1, 9 do total = total + co() end
		return total`,
	"error handler inspects the loop": `
		local report
		local function handler(msg)
			local n, parts = 1, {}
			while true do
				local name, value = debug.getlocal(3, n)
				if not name then break end
				if name == "acc" or name == "i" then parts[#parts + 1] = name .. "=" .. tostring(value) end
				n = n + 1
			end
			report = table.concat(parts, " ")
			return (tostring(msg):gsub("^.-:%d+: ", ""))
		end
		local function check(i) if i == 77 then error("stop at " .. i) end end
		local ok, msg = xpcall(function()
			local acc = 0
			for i = 1, 200 do
				acc = acc + i * 2
				check(i)
			end
			return acc
		end, handler)
		return ok, msg, report`,
	"errors caught in the loop": `
		local function risky(i) if i % 7 == 0 then error("bad") end return i end
		local sum, failures = 0, 0
		for i = 1, 300 do
			local ok, v = pcall(risky, i)
			if ok then sum = sum + v else failures = failures + 1 end
		end
		return sum, failures`,
	"captured variable read by the called function": `
		local total = 0
		local function snapshot() return total end
		local seen = 0
		for i = 1, 300 do
			total = total + i
			seen = seen + snapshot() % 7
			seen = seen + (tonumber(nil) or 1)
		end
		return total, seen`,
	"captured variable written by the called function": `
		local total, calls = 0, 0
		local function bump(v) total = total + v calls = calls + 1 end
		for i = 1, 300 do
			total = total + 1
			if i % 3 == 0 then bump(i) end
			total = total * 1
		end
		return total, calls`,
	"metamethod reads the loop state": `
		local acc = 0
		local probe = setmetatable({}, {__index = function(_, k) return acc + k end})
		local s = 0
		for i = 1, 300 do
			acc = acc + i
			s = s + probe[i]
		end
		return s, acc`,
	"table of locals built by a callout": `
		local out = {}
		local a, b = 0, 1.5
		for i = 1, 100 do
			a = a + i
			b = b * 1.01
			out[#out + 1] = {a, b, i}
		end
		local s = 0
		for _, r in ipairs(out) do s = s + r[1] + r[2] + r[3] end
		return s`,
	"nested loops with callouts at several depths": `
		local log = {}
		local function note(v) if v % 97 == 0 then log[#log + 1] = v end return v end
		local s = 0
		for i = 1, 40 do
			local row = 0
			for j = 1, 30 do
				row = row + note(i * j)
				s = s + j
			end
			s = s + note(row)
		end
		return s, #log`,
}

func TestJITCalloutPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitCalloutPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITCalloutAllocations checks that a callout does not box the
// numbers of the loop that its instruction does not use.
func TestJITCalloutAllocations(t *testing.T) {
	skipWithoutJIT(t)
	const src = `
		local out = {}
		local a, b, c, d = 0, 0, 0, 0
		for i = 1, 20000 do
			a = a + 1 b = b + 2 c = c + 3 d = d + 4
			out[1] = "x"
		end
		return a + b + c + d`
	run := func(jit bool) float64 {
		opts := jitTestOptions(Lua51, 5)
		opts.JIT.Enabled = jit
		L := NewState(opts)
		defer L.Close()
		fn, err := L.LoadString(src)
		if err != nil {
			t.Fatal(err)
		}
		return testing.AllocsPerRun(3, func() {
			L.Push(fn)
			if err := L.PCall(0, 1, nil); err != nil {
				t.Fatal(err)
			}
			L.Pop(1)
		})
	}
	interp, native := run(false), run(true)
	// the interpreter boxes every intermediate number; compiled code
	// boxes none of the four counters while the store runs
	if native > interp/4 {
		t.Errorf("allocations per run: %v with the JIT, %v in the interpreter", native, interp)
	}
}

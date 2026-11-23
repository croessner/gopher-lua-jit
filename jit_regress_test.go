package lua

import (
	"context"
	"fmt"
	"runtime"
	"runtime/debug"
	"strings"
	"testing"
	"time"

	"github.com/yuin/gopher-lua/internal/jit/codecache"
)

// Regression tests for defects found by reviewing the JIT: each test
// failed before the corresponding fix.

// jitRegressPrograms are differential programs (interpreter vs JIT).
var jitRegressPrograms = map[string]string{
	// an open argument list that ends with the single result of a
	// natively translated library call
	"open args after intrinsic":   `local n = 0 for i = 1, 100 do n = n + select("#", math.abs(-i)) end return n`,
	"open args after intrinsic 2": `local n = 0 for i = 1, 100 do n = n + select("#", i, math.floor(i / 3), math.sqrt(i)) end return n`,
	"table of intrinsic result":   `local n = 0 for i = 1, 100 do local t = {math.sqrt(i)} n = n + #t + t[1] end return n`,
	"table of intrinsic result 2": `local n = 0 for i = 1, 100 do local t = {i, i, math.abs(i)} n = n + #t end return n`,
	"tostring of intrinsic":       `local s = "" for i = 1, 20 do s = s .. tostring(math.abs(-i)) .. "," end return s`,
	"nested intrinsic deopt":      `local s = 0 local v = {4, 9.0, "16", 25} for i = 1, 100 do s = s + math.floor(math.sqrt(v[i % 4 + 1])) end return s`,
	// float modulo of integral values
	"float mod negative zero dividend": `local z, r = -0.0, nil for i = 1, 100 do r = z % 2 end return 1 / r`,
	"float mod negative zero by neg":   `local z, r = -0.0, nil for i = 1, 100 do r = z % -2 end return 1 / r`,
	"float mod zero by negative":       `local z, r = 0.0, nil for i = 1, 100 do r = z % -2 end return 1 / r`,
	"float mod of a huge integer":      `local big, q = 9007199254740993, nil for i = 1, 100 do q = big % 2.0 end return q`,
	"float mod by a huge integer":      `local big, q = 9007199254740993, nil for i = 1, 100 do q = 3.0 % big end return q`,
	"float mod huge negative":          `local big, q = -9007199254740993, 0 for i = 1, 100 do q = q + big % 3.0 + 5.0 % big end return q`,
	// locals of a frame that runs native code are changed by a debugger
	"setlocal on a native frame": `
		local function poke(i) if i == 60 then
			local n = 1
			while true do
				local name = debug.getlocal(2, n)
				if not name then break end
				if name == "s" then debug.setlocal(2, n, 1000) end
				n = n + 1
			end
		end end
		local s = 0
		for i = 1, 100 do poke(i) s = s + 1 end
		return s`,
	"setlocal float on a native frame": `
		local function poke(i) if i % 30 == 0 then
			local n = 1
			while true do
				local name = debug.getlocal(2, n)
				if not name then break end
				if name == "acc" then debug.setlocal(2, n, 0.5) end
				n = n + 1
			end
		end end
		local acc, k = 0, 3
		for i = 1, 100 do poke(i) acc = acc + k end
		return acc`,
}

func TestJITRegressPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitRegressPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITOpenCallStaysNative checks that a call whose arguments end with
// the result of a native library call does not push the loop back to the
// interpreter.
func TestJITOpenCallStaysNative(t *testing.T) {
	skipWithoutJIT(t)
	src := `local s = 0 for i = 1, 5000 do s = s + i % 7 + math.max(i, math.floor(i / 2)) end return s`
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		want, _ := runChunk(Options{LanguageVersion: version}, src)
		got, st := runChunk(jitTestOptions(version, 5), src)
		if got != want {
			t.Errorf("%v: got %s, want %s", version, got, want)
		}
		if st.Compiled == 0 || st.Blacklisted != 0 || st.Entries > 100 {
			t.Errorf("%v: the loop did not stay native: %s", version, st)
		}
	}
}

// TestJITUseAfterClose checks that a thread which outlives its closed
// main state falls back to the interpreter instead of entering freed
// code.
func TestJITUseAfterClose(t *testing.T) {
	skipWithoutJIT(t)
	L := NewState(jitTestOptions(Lua55, 1))
	if err := L.DoString(`function work(n) local s = 0 for i = 1, n do s = s + i end return s end`); err != nil {
		t.Fatal(err)
	}
	co, _ := L.NewThread()
	call := func() int64 {
		if err := co.CallByParam(P{Fn: co.GetGlobal("work"), NRet: 1, Protect: true}, LInteger(1000)); err != nil {
			t.Fatal(err)
		}
		v := co.Get(-1)
		co.Pop(1)
		return int64(v.(LInteger))
	}
	if got := call(); got != 500500 {
		t.Fatalf("got %d", got)
	}
	if st := L.JITStats(); st.LiveUnits == 0 {
		t.Fatalf("nothing was compiled: %s", st)
	}
	L.Close()
	if got := call(); got != 500500 {
		t.Fatalf("after Close: got %d", got)
	}
	requireNoMappedCode(t, L)
}

// TestJITSafePointIntervalIsSanitized checks that an invalid safe point
// interval cannot disable safe points.
func TestJITSafePointIntervalIsSanitized(t *testing.T) {
	skipWithoutJIT(t)
	for _, interval := range []int{-1, -1 << 30, 1 << 30} {
		L := NewState(Options{JIT: JITOptions{Enabled: true, Threshold: 2, SafePointInterval: interval}})
		ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
		L.SetContext(ctx)
		done := make(chan error, 1)
		go func() { done <- L.DoString(`local x = 0 while true do x = x + 1 end`) }()
		select {
		case err := <-done:
			if err == nil || !strings.Contains(err.Error(), "deadline") {
				t.Errorf("interval %d: unexpected result %v", interval, err)
			}
		case <-time.After(20 * time.Second):
			t.Fatalf("interval %d: native code ignored the context", interval)
		}
		cancel()
		L.Close()
	}
}

// TestJITFailingMessageHandler checks that native activations are
// unwound when the message handler of a protected call fails itself.
func TestJITFailingMessageHandler(t *testing.T) {
	skipWithoutJIT(t)
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		L := NewState(jitTestOptions(version, 1))
		err := L.DoString(`
			local function work() local s = 0 for i = 1, 100 do s = s + i if i == 90 then error("boom") end end end
			for round = 1, 80 do
				local ok = xpcall(work, function() error("handler fails too") end)
				assert(not ok)
			end`)
		if err != nil {
			t.Fatalf("%v: %v", version, err)
		}
		if th := L.jit; th != nil && len(th.acts) != 0 {
			t.Errorf("%v: %d native activations leaked", version, len(th.acts))
		}
		if L.nny != 0 {
			t.Errorf("%v: nny is %d after the calls", version, L.nny)
		}
		before := L.JITStats().Entries
		if err := L.DoString(`local s = 0 for i = 1, 1000 do s = s + i end assert(s == 500500)`); err != nil {
			t.Fatal(err)
		}
		if after := L.JITStats().Entries; after == before {
			t.Errorf("%v: native code is no longer entered", version)
		}
		L.JITFlush()
		if st := L.JITStats(); st.CodeBytes != 0 {
			t.Errorf("%v: flush left code behind: %s", version, st)
		}
		L.Close()
	}
}

// TestJITMaxArrayIndex checks that native appends respect the limit of
// the array part.
func TestJITMaxArrayIndex(t *testing.T) {
	skipWithoutJIT(t)
	saved := MaxArrayIndex
	MaxArrayIndex = 64
	defer func() { MaxArrayIndex = saved }()
	src := `local t = {} for i = 1, 200 do t[i] = i end
		local n = 0 for _ in pairs(t) do n = n + 1 end
		return #t, t[63], t[64], t[65], t[200], n`
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		want, _ := runChunk(Options{LanguageVersion: version}, src)
		for _, threshold := range []int{1, 5} {
			if got, _ := runChunk(jitTestOptions(version, threshold), src); got != want {
				t.Errorf("%v threshold %d:\n jit:         %s\n interpreter: %s", version, threshold, got, want)
			}
		}
	}
}

// bigLoopSource returns a loop whose native code is much larger than a
// page.
func bigLoopSource() string {
	var b strings.Builder
	b.WriteString("local a, b, c = 1, 2, 3\nfor i = 1, 300 do\n")
	for k := 0; k < 400; k++ {
		fmt.Fprintf(&b, "a = (a + b * %d) %% 1000003 b = (b + c + i * %d) %% 1000033 c = (c + a) %% %d\n", k+3, k+1, 1000+k)
	}
	b.WriteString("end\nreturn a, b, c")
	return b.String()
}

// TestJITOversizedUnit checks that a unit that alone exceeds the code
// cache limit is not installed.
func TestJITOversizedUnit(t *testing.T) {
	skipWithoutJIT(t)
	src := bigLoopSource()
	limit := codecachePageSize()
	want, _ := runChunk(Options{LanguageVersion: Lua55}, src)
	L := NewState(Options{LanguageVersion: Lua55, JIT: JITOptions{Enabled: true, Threshold: 2, MaxCodeBytes: limit}})
	defer L.Close()
	fn, err := L.LoadString(src)
	if err != nil {
		t.Fatal(err)
	}
	L.Push(fn)
	if err := L.PCall(0, MultRet, nil); err != nil {
		t.Fatal(err)
	}
	got := fmt.Sprintf("number:%s | number:%s | number:%s", L.Get(1), L.Get(2), L.Get(3))
	if got != want {
		t.Errorf("got %s, want %s", got, want)
	}
	if st := L.JITStats(); st.CodeBytes > limit {
		t.Errorf("code cache holds %d bytes, limit is %d: %s", st.CodeBytes, limit, st)
	}
}

// TestJITCodeReleasedWithoutClose checks that the executable memory of a
// state that is dropped without Close is released by the garbage
// collector.
func TestJITCodeReleasedWithoutClose(t *testing.T) {
	skipWithoutJIT(t)
	// let the finalizers of states dropped by earlier tests run first
	for i := 0; i < 5; i++ {
		runtime.GC()
		time.Sleep(10 * time.Millisecond)
	}
	before := codecache.LiveBytes()
	func() {
		for i := 0; i < 30; i++ {
			L := NewState(jitTestOptions(Lua55, 1))
			if err := L.DoString(`local s = 0 for i = 1, 100 do s = s + i end`); err != nil {
				t.Fatal(err)
			}
		}
	}()
	if codecache.LiveBytes() <= before {
		t.Fatal("no code was mapped")
	}
	deadline := time.Now().Add(10 * time.Second)
	for codecache.LiveBytes() > before && time.Now().Before(deadline) {
		runtime.GC()
		time.Sleep(10 * time.Millisecond)
	}
	if after := codecache.LiveBytes(); after > before {
		t.Fatalf("executable memory leaked: %d bytes", after-before)
	}
}

// TestJITCloseWithLazyMainThread checks that Close releases the code of
// a state whose first code ran on another thread.
func TestJITCloseWithLazyMainThread(t *testing.T) {
	skipWithoutJIT(t)
	opts := jitTestOptions(Lua55, 1)
	opts.SkipOpenLibs = true
	L := NewState(opts)
	co, _ := L.NewThread()
	fn, err := co.LoadString(`local s = 0 for i = 1, 100 do s = s + i end return s`)
	if err != nil {
		t.Fatal(err)
	}
	co.Push(fn)
	if err := co.PCall(0, 1, nil); err != nil {
		t.Fatal(err)
	}
	if st := L.JITStats(); st.CodeBytes == 0 {
		t.Fatalf("no code was mapped: %s", st)
	}
	L.Close()
	requireNoMappedCode(t, L)
}

// jitStableLoops are programs whose loops must stay compiled: none of
// their exits is a sign of a wrong speculation.
var jitStableLoops = map[string]string{
	// zero dividends are ordinary data, not a reason to leave native code
	"float modulo with zero dividends": `
		local function work(seed)
			local s = 0
			for i = 0, 400 do s = s + ((i % 5) * seed) % 7 + (i * 0) % 3 end
			return s
		end
		local total = 0
		for call = 1, 60 do total = total + work(call) end
		return total`,
	// a fresh array is filled on every call: growing it is not a failed guess
	"filling fresh arrays": `
		local function fill(seed)
			local t = {}
			for i = 1, 64 do t[i] = (i * seed) % 17 end
			local s = 0
			for i = 1, #t do s = s + t[i] end
			return s
		end
		local total = 0
		for call = 1, 80 do total = total + fill(call) end
		return total`,
	"appending to fresh arrays": `
		local function fill(seed)
			local t = {}
			for i = 1, 100 do t[#t + 1] = i * seed end
			return #t + t[100]
		end
		local total = 0
		for call = 1, 80 do total = total + fill(call) end
		return total`,
}

// TestJITStableLoopsStayNative checks that loops with harmless exits are
// neither recompiled over and over nor handed back to the interpreter.
func TestJITStableLoopsStayNative(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitStableLoops {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			want, _ := runChunk(Options{LanguageVersion: version}, src)
			opts := jitTestOptions(version, 5)
			L := NewState(opts)
			fn, err := L.LoadString(src)
			if err != nil {
				t.Fatal(err)
			}
			L.Push(fn)
			if err := L.PCall(0, MultRet, nil); err != nil {
				t.Fatalf("%s (%v): %v", name, version, err)
			}
			got := fmt.Sprintf("%s:%s", L.Get(1).Type(), L.ToStringMeta(L.Get(1)).String())
			st := L.JITStats()
			L.Close()
			if got != want {
				t.Errorf("%s (%v): got %s, want %s", name, version, got, want)
			}
			if st.Blacklisted != 0 || st.Invalidated != 0 {
				t.Errorf("%s (%v): loops were discarded or blacklisted: %s", name, version, st)
			}
		}
	}
}

// jitFieldPrograms exercise number fields that native code reads and
// writes in place (differential: interpreter vs JIT).
var jitFieldPrograms = map[string]string{
	"field arithmetic": `local p = {x = 0, y = 1, z = 2} for i = 1, 300 do p.x = p.x + p.y p.z = p.x - p.y * 0.5 end return p.x, p.y, p.z`,
	"field read back by the interpreter": `
		local p = {n = 0, s = "str"}
		local seen = {}
		for i = 1, 200 do
			p.n = p.n + i
			if i % 50 == 0 then seen[#seen + 1] = tostring(p.n) .. p.s end
		end
		local keys = {}
		for k, v in pairs(p) do keys[#keys + 1] = k .. "=" .. tostring(v) end
		table.sort(keys)
		return table.concat(seen, ","), table.concat(keys, ","), rawget(p, "n"), next(p) ~= nil`,
	"field changes kind": `
		local p = {v = 1}
		local log = {}
		for i = 1, 200 do
			if i == 60 then p.v = "text" end
			if i == 61 then log[#log + 1] = p.v p.v = 10 end
			if i == 120 then p.v = nil end
			if i == 121 then log[#log + 1] = tostring(p.v) p.v = 0.5 end
			if type(p.v) == "number" then p.v = p.v + 1 end
		end
		return p.v, table.concat(log, ",")`,
	"integer and float fields": `local p = {a = 1, b = 0.5} for i = 1, 200 do p.a = p.a + 2 p.b = p.b * 1.01 if i == 100 then p.a = p.a + 0.25 end end return p.a, p.b`,
	"tables of different layouts": `
		local a = {x = 1, y = 2}
		local b = {y = 5, extra = true, x = 7}
		local c = {x = 100}
		local s = 0
		for i = 1, 300 do
			local t = a
			if i % 3 == 0 then t = b elseif i % 7 == 0 then t = c end
			t.x = t.x + 1
			s = s + t.x
		end
		return s, a.x, b.x, c.x`,
	"field appears and disappears": `
		local p = {}
		local s = 0
		for i = 1, 300 do
			if i % 40 == 1 then p.count = nil end
			p.count = (p.count or 0) + 1
			s = s + p.count
		end
		return s, p.count`,
	"metatable with __index and __newindex": `
		local hits = 0
		local p = setmetatable({v = 1}, {__index = function() hits = hits + 1 return 0 end, __newindex = function() hits = hits + 100 end})
		local s = 0
		for i = 1, 200 do p.v = p.v + 1 s = s + p.v + p.missing end
		return s, hits, p.v`,
	"many fields": (func() string {
		src := "local p = {}\n"
		for i := 0; i < 40; i++ {
			src += fmt.Sprintf("p.f%d = %d\n", i, i)
		}
		src += "for i = 1, 200 do p.f39 = p.f39 + p.f0 + p.f17 p.f3 = p.f3 + 1 end\nreturn p.f39, p.f3, p.f17"
		return src
	})(),
	"negative zero and nan fields": `local p = {z = 0.0, n = 0.0} for i = 1, 100 do p.z = p.z * -1.0 p.n = (p.n + 1) * (0/0) end return 1 / p.z, p.n ~= p.n`,
}

func TestJITFieldPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitFieldPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITFieldsOfGoBuiltTables checks field access on tables whose keys
// were created by Go code and the view Go code has of fields written by
// native code.
func TestJITFieldsOfGoBuiltTables(t *testing.T) {
	skipWithoutJIT(t)
	const src = `local p = ... for i = 1, 500 do p.total = p.total + p.step end return p.total`
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		run := func(opts Options) (string, JITStats) {
			L := NewState(opts)
			defer L.Close()
			fn, err := L.LoadString(src)
			if err != nil {
				t.Fatal(err)
			}
			var last *LTable
			for round := 0; round < 20; round++ {
				tb := L.NewTable()
				tb.RawSetString("total", LNumber(round))
				tb.RawSetString("step", LNumber(2))
				tb.RawSetString("name", LString("go"))
				if err := L.CallByParam(P{Fn: fn, NRet: 1, Protect: true}, tb); err != nil {
					t.Fatal(err)
				}
				L.Pop(1)
				last = tb
			}
			count := 0
			last.ForEach(func(_, _ LValue) { count++ })
			clone := last.Clone()
			return fmt.Sprintf("%v %v %v %d %v", last.RawGetString("total"), L.GetField(last, "total"),
				clone.RawGetString("total"), count, last.RawGetString("name")), L.JITStats()
		}
		want, _ := run(Options{LanguageVersion: version})
		got, st := run(jitTestOptions(version, 5))
		if got != want {
			t.Errorf("%v: got %q, want %q", version, got, want)
		}
		if st.Blacklisted != 0 || st.Compiled == 0 || st.Compiled > 3 {
			t.Errorf("%v: the field loop did not stay native: %s", version, st)
		}
	}
}

// TestJITFieldLoopIsNative checks that a loop over number fields runs
// without leaving native code on every iteration.
func TestJITFieldLoopIsNative(t *testing.T) {
	skipWithoutJIT(t)
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5),
			`local p = {x = 0, y = 1, z = 2} for i = 1, 20000 do p.x = p.x + p.y p.z = p.x - p.y end return p.z`)
		if st.Compiled == 0 || st.Callouts > 100 || st.Blacklisted != 0 {
			t.Errorf("%v: field access is not native: %s", version, st)
		}
	}
}

// jitBoolArrayPrograms exercise arrays of booleans, which are stored
// unboxed like number arrays.
var jitBoolArrayPrograms = map[string]string{
	"sieve": `
		local n = 2000
		local flags = {}
		for i = 1, n do flags[i] = true end
		local count = 0
		for i = 2, n do
			if flags[i] then
				count = count + 1
				for j = i + i, n, i do flags[j] = false end
			end
		end
		return count, #flags, flags[1], flags[4], flags[n]`,
	"boolean array changes kind": `
		local t = {}
		for i = 1, 100 do t[i] = i % 3 == 0 end
		local c = 0
		for i = 1, #t do if t[i] then c = c + 1 end end
		t[50] = 7
		for i = 1, #t do if t[i] == true then c = c + 1 elseif t[i] == 7 then c = c + 1000 end end
		t[#t] = nil
		t[#t + 1] = "s"
		return c, #t, type(t[50]), t[3], t[4], t[#t]`,
	"boolean array through the table library": `
		local t = {}
		for i = 1, 50 do t[i] = i % 2 == 0 end
		table.insert(t, 1, true)
		table.insert(t, false)
		local removed = table.remove(t, 2)
		local n = 0
		for _, v in ipairs(t) do if v then n = n + 1 end end
		local copy = {}
		for k, v in pairs(t) do copy[#copy + 1] = tostring(v) end
		return n, #t, removed, table.concat(copy, ""):sub(1, 30), select("#", unpack and unpack(t) or table.unpack(t))`,
	"booleans from comparisons": `
		local t, s = {}, 0
		for i = 1, 300 do t[i] = i * i % 7 < 3 end
		for i = 1, 300 do if t[i] then s = s + i end if not t[i] then s = s - 1 end end
		return s`,
}

// jitVariableStepPrograms exercise numeric for loops whose step is not a
// constant.
var jitVariableStepPrograms = map[string]string{
	"step changes between entries": `local s = 0 for i = 2, 40 do for j = i + i, 400, i do s = s + j end end return s`,
	"step changes direction": `
		local s = 0
		for round = 1, 60 do
			local step = (round % 2 == 0) and 3 or -3
			local from, to = 1, 90
			if step < 0 then from, to = 90, 1 end
			for j = from, to, step do s = s + j * round end
		end
		return s`,
	"float steps": `local s = 0 for i = 1, 50 do for x = 0, 10, i / 8 do s = s + x end for x = 5, -5, -i / 16 do s = s - x end end return s`,
	"step becomes zero": `
		local ok, msg
		local s = 0
		for i = 5, 0, -1 do
			ok, msg = pcall(function() for j = 1, 10, i do s = s + j end end)
			if not ok then break end
		end
		return s, ok, (tostring(msg):gsub("^.-:%d+: ", ""))`,
	"huge steps":             `local s = 0 for i = 1, 30 do for j = 1, 100, 9007199254740992 do s = s + j end for j = 1, 10, i * 1000 do s = s + j end end return s`,
	"negative variable step": `local s = 0 for i = 1, 40 do for j = 100, 1, -i do s = s + j end end return s`,
}

func TestJITVariableStepPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitVariableStepPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5), jitVariableStepPrograms["step changes between entries"])
		if st.Compiled == 0 || st.Blacklisted != 0 || st.Invalidated > 1 {
			t.Errorf("%v: loops with a variable step do not stay native: %s", version, st)
		}
	}
}

func TestJITBoolArrayPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitBoolArrayPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5), `
			local flags = {}
			for i = 1, 20000 do flags[i] = true end
			local count = 0
			for i = 2, 20000 do if flags[i] then count = count + 1 end flags[i] = false end
			return count`)
		if st.Compiled == 0 || st.Callouts > 200 || st.Blacklisted != 0 {
			t.Errorf("%v: boolean array access is not native: %s", version, st)
		}
	}
}

// jitUpvaluePrograms exercise upvalues read by compiled code.
var jitUpvaluePrograms = map[string]string{
	"number upvalues": `
		local k, f = 3, 0.5
		local function run(n) local s = 0 for i = 1, n do s = s + i * k + f end return s end
		local a = run(200)
		k, f = 7, 2
		return a, run(200)`,
	"upvalue changes kind": `
		local k = 1
		local function run(n) local s = 0 for i = 1, n do s = s + (tonumber(k) or 0) + (type(k) == "number" and k or 100) end return s end
		local out = {}
		for _, v in ipairs({2, 2.5, "3", false, 4}) do k = v out[#out + 1] = run(100) end
		return table.concat(out, ",")`,
	"upvalue assigned inside the loop": `
		local k = 0
		local function bump() k = k + 1 end
		local function run(n) local s = 0 for i = 1, n do s = s + k if i % 10 == 0 then bump() end end return s end
		return run(300), k`,
	"open upvalue of the running function": `
		local s = 0
		for round = 1, 3 do
			local k = round
			local function get() return k end
			for i = 1, 100 do s = s + k * i k = k + 1 end
			s = s + get()
		end
		return s`,
	"function and table upvalues": `
		local lib = {scale = 2}
		local function double(x) return x * lib.scale end
		local function run(n) local s = 0 for i = 1, n do s = s + double(i) end return s end
		local a = run(100)
		lib.scale = 3
		local b = run(100)
		double = function(x) return -x end
		return a, b, run(100)`,
	"closures of one prototype with different upvalues": `
		local function make(k) return function(n) local s = 0 for i = 1, n do s = s + i * k end return s end end
		local a, b, c = make(1), make(2.5), make(10)
		local s = 0
		for round = 1, 30 do s = s + a(20) + b(20) + c(20) end
		return s`,
}

func TestJITUpvaluePrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitUpvaluePrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5), `
			local k = 3
			local function run(n) local s = 0 for i = 1, n do s = s + i * k end return s end
			return run(20000)`)
		if st.Compiled == 0 || st.Callouts > 100 || st.Blacklisted != 0 {
			t.Errorf("%v: reading a number upvalue is not native: %s", version, st)
		}
	}
}

// jitInlinePrograms exercise calls of small Lua functions that compiled
// loops translate in place.
var jitInlinePrograms = map[string]string{
	"upvalue function": `
		local function add(a, b) return a + b end
		local function run(n) local s = 0 for i = 1, n do s = add(s, i) end return s end
		return run(300)`,
	"local function in the same frame": `local function mul(a, b) return a * b + 1 end local s = 0 for i = 1, 300 do s = s + mul(i, 3) end return s`,
	"global function":                  `function gadd(a, b) return a + b * 2 end local s = 0 for i = 1, 300 do s = gadd(s, i) end gadd = nil return s`,
	"missing and surplus arguments": `
		local function f(a, b, c) return a, b, c end
		local function g(a) return a end
		local n = 0
		for i = 1, 200 do
			local x, y, z = f(i)
			if y == nil and z == nil then n = n + x end
			n = n + g(i, i * 2, i * 3)
		end
		return n`,
	"results adjusted": `
		local function two(a) return a, a * 2 end
		local function none() return end
		local s = 0
		for i = 1, 200 do
			local a = two(i)
			local b, c, d = two(i)
			local e = none()
			two(i)
			s = s + a + b + c + (d == nil and 1 or 0) + (e == nil and 1 or 0)
		end
		return s`,
	"nested calls": `
		local function sq(x) return x * x end
		local function norm(x, y) return sq(x) + sq(y) end
		local function dist(ax, ay, bx, by) return norm(ax - bx, ay - by) end
		local s = 0
		for i = 1, 300 do s = s + dist(i, 2, 3, i * 0.5) end
		return s`,
	"callee reads and writes fields": `
		local function bump(p, d) p.x = p.x + d return p.x end
		local function getx(p) return p.x end
		local p = {x = 0}
		local s = 0
		for i = 1, 300 do s = s + bump(p, i) + getx(p) end
		return s, p.x`,
	"callee with upvalues": `
		local scale, offset = 3, 0.5
		local function f(x) return x * scale + offset end
		local s = 0
		for i = 1, 300 do s = s + f(i) if i == 150 then scale = 4 end end
		return s`,
	"callee replaced during the loop": `
		local function a(x) return x + 1 end
		local function b(x) return x * 2 end
		local f = a
		local s = 0
		for i = 1, 300 do s = s + f(i) if i % 70 == 0 then f = (f == a) and b or a end end
		return s`,
	"argument changes type": `
		local function f(x) return x + 1 end
		local s = 0
		for i = 1, 300 do
			local v = i
			if i % 50 == 0 then v = tostring(i) end
			s = s + f(v)
		end
		return s`,
	"error inside the callee": `
		local function f(x, t) return x + t.v end
		local t = {v = 1}
		local ok, msg = pcall(function()
			local s = 0
			for i = 1, 300 do
				if i == 250 then t.v = nil end
				s = s + f(i, t)
			end
			return s
		end)
		return ok, (tostring(msg):gsub("^.-:%d+: ", ""))`,
	"traceback from the callee": `
		local function inner(x, t) return x + t.v end
		local function outer(x, t) return inner(x, t) end
		local t = {v = 1}
		local trace
		xpcall(function()
			local s = 0
			for i = 1, 300 do
				if i == 250 then t.v = {} end
				s = s + outer(i, t)
			end
		end, function(m) trace = debug.traceback(m) end)
		local names = 0
		for _ in trace:gmatch("in function") do names = names + 1 end
		return names >= 3, (trace:match("attempt to[^\n]*"))`,
	"callee uses a library function": `
		local function half(x) return math.floor(x / 2) end
		local s = 0
		for i = 1, 300 do s = s + half(i) end
		return s`,
	"library function replaced for the callee": `
		local floor = math.floor
		local function half(x) return math.floor(x / 2) end
		local s = 0
		for i = 1, 300 do
			if i == 200 then math.floor = function() return 1000 end end
			s = s + half(i)
		end
		math.floor = floor
		return s`,
	"recursive function is not inlined": `
		local function fact(n) return n <= 1 and 1 or n * fact(n - 1) end
		local s = 0
		for i = 1, 100 do s = s + fact(i % 10) end
		return s`,
	"call results as arguments": `
		local function inc(x) return x + 1 end
		local function add(a, b) return a + b end
		local s = 0
		for i = 1, 300 do s = add(inc(s), inc(inc(i))) end
		return s`,
	"callee returns its table argument": `
		local function id(t) return t end
		local function first(t) return t[1] end
		local t = {5, 6, 7}
		local s = 0
		for i = 1, 300 do local u = id(t) s = s + first(u) + #id(u) end
		return s`,
	"many arguments and locals": `
		local function f(a, b, c, d, e, g)
			local x = a + b
			local y = c * d
			local z = e - g
			return x + y + z, x * y
		end
		local s, p = 0, 0
		for i = 1, 300 do local u, v = f(i, 1, 2, 3, i, 4) s = s + u p = p + v % 7 end
		return s, p`,
	"coroutine yields from a callee": `
		local function emit(x) coroutine.yield(x) return x * 2 end
		local co = coroutine.wrap(function() local s = 0 for i = 1, 100 do s = s + emit(i) end return s end)
		local seen = 0
		for i = 1, 100 do seen = seen + co() end
		return seen, co()`,
}

func TestJITInlinePrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitInlinePrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITInlinedCallsAreNative checks that calls of small functions do
// not leave native code.
func TestJITInlinedCallsAreNative(t *testing.T) {
	skipWithoutJIT(t)
	for _, name := range []string{"upvalue function", "local function in the same frame", "nested calls", "callee reads and writes fields", "call results as arguments"} {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			src := strings.Replace(jitInlinePrograms[name], "300", "20000", -1)
			_, st := runChunk(jitTestOptions(version, 5), src)
			if st.Compiled == 0 || st.Callouts > 200 || st.Blacklisted != 0 || st.Deopts > 50 {
				t.Errorf("%s (%v): calls are not inlined: %s", name, version, st)
			}
		}
	}
}

// jitBranchyInlinePrograms exercise inlined callees with branches and
// several return points.
var jitBranchyInlinePrograms = map[string]string{
	"max and clamp": `
		local function max(a, b) if a > b then return a end return b end
		local function clamp(x, lo, hi) if x < lo then return lo elseif x > hi then return hi else return x end end
		local s = 0
		for i = 1, 300 do s = s + max(i % 17, 9) + clamp(i - 150, -40, 60) end
		return s`,
	"and or expressions": `
		local function pick(a, b) return a > b and a or b end
		local function sign(x) return x > 0 and 1 or x < 0 and -1 or 0 end
		local s = 0
		for i = 1, 300 do s = s + pick(i % 13, 6) * sign(i - 150) end
		return s`,
	"default argument": `
		local function scale(x, f) f = f or 2 return x * f end
		local s = 0
		for i = 1, 300 do s = s + scale(i) + scale(i, 0.5) end
		return s`,
	"branch assigns a local": `
		local function f(x)
			local r
			if x % 3 == 0 then r = x * 2.0 else r = x + 0.5 end
			return r + 1
		end
		local s = 0
		for i = 1, 300 do s = s + f(i) end
		return s`,
	"paths return different kinds": `
		local function f(x) if x % 5 == 0 then return nil end return x end
		local function g(x) if x % 7 == 0 then return "seven" end return x end
		local s, n = 0, 0
		for i = 1, 300 do
			local v = f(i)
			if v then s = s + v else n = n + 1 end
			local w = g(i)
			if type(w) == "number" then s = s + w else n = n + #w end
		end
		return s, n`,
	"paths return different counts": `
		local function f(x) if x % 2 == 0 then return x, x end return x end
		local s = 0
		for i = 1, 300 do local a, b = f(i) s = s + a + (b or 100) end
		return s`,
	"nested branchy calls": `
		local function abs(x) if x < 0 then return -x end return x end
		local function dist(a, b) return abs(a - b) end
		local function near(a, b, eps) return dist(a, b) <= eps end
		local n = 0
		for i = 1, 300 do if near(i % 10, 5, 2) then n = n + 1 end end
		return n`,
	"boolean results": `
		local function even(x) return x % 2 == 0 end
		local function both(a, b) return a and b end
		local n = 0
		for i = 1, 300 do if both(even(i), not even(i + 1)) then n = n + 1 end end
		return n`,
	"error on one path": `
		local function f(x, t) if x > 250 then return x + t.missing end return x end
		local t = {}
		local ok, msg = pcall(function() local s = 0 for i = 1, 300 do s = s + f(i, t) end return s end)
		return ok, (tostring(msg):gsub("^.-:%d+: ", ""))`,
	"comparison of strings and tables in the callee": `
		local function lt(x, y) return x < y end
		local function same(x, y) if x == y then return 1 end return 0 end
		local names = {"Jan", "Feb", "Mar", "Apr", "May"}
		local objs = {{}, {}}
		local n = 0
		for i = 1, 300 do
			if lt(names[i % 5 + 1], names[(i + 2) % 5 + 1]) then n = n + 1 end
			n = n + same(objs[i % 2 + 1], objs[1]) + same(names[1], "Jan")
		end
		return n`,
	"field dependent branch": `
		local function cost(item) if item.heavy > 0 then return item.w * 2 else return item.w end end
		local a, b = {w = 3, heavy = 1}, {w = 5, heavy = 0}
		local s = 0
		for i = 1, 300 do s = s + cost(i % 3 == 0 and a or b) end
		return s`,
}

func TestJITBranchyInlinePrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitBranchyInlinePrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, name := range []string{"max and clamp", "and or expressions", "branch assigns a local", "nested branchy calls"} {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			src := strings.Replace(jitBranchyInlinePrograms[name], "300", "20000", -1)
			_, st := runChunk(jitTestOptions(version, 5), src)
			if st.Compiled == 0 || st.Callouts > 200 || st.Blacklisted != 0 || st.Deopts > 50 {
				t.Errorf("%s (%v): calls are not inlined: %s", name, version, st)
			}
		}
	}
}

// jitGenericForPrograms exercise generic for loops in compiled code.
var jitGenericForPrograms = map[string]string{
	"ipairs over numbers": `local t = {} for i = 1, 200 do t[i] = i * 1.5 end local s = 0 for round = 1, 20 do for i, v in ipairs(t) do s = s + v * i end end return s`,
	"ipairs over integers and booleans": `
		local a, b = {}, {}
		for i = 1, 100 do a[i] = i b[i] = i % 3 == 0 end
		local s, n = 0, 0
		for round = 1, 20 do
			for i, v in ipairs(a) do s = s + v + i end
			for _, f in ipairs(b) do if f then n = n + 1 end end
			for i in ipairs(a) do s = s + i end
		end
		return s, n`,
	"ipairs over strings and tables": `
		local names, objs = {}, {}
		for i = 1, 50 do names[i] = "n" .. i objs[i] = {v = i} end
		local s = 0
		for round = 1, 20 do
			for i, name in ipairs(names) do s = s + #name + i end
			for _, o in ipairs(objs) do s = s + o.v o.v = o.v + 1 end
		end
		return s, objs[50].v`,
	"ipairs stops at a hole": `
		local t = {1, 2, 3, nil, 5}
		local u = {1, 2, 3}
		local s = 0
		for round = 1, 100 do
			for _, v in ipairs(t) do s = s + v end
			for _, v in ipairs(u) do s = s + v end
			if round == 50 then u[2] = nil end
			if round == 70 then u[2] = "x" u[#u + 1] = 9 end
			if round == 71 then u[2] = 4 end
		end
		return s`,
	"array modified while iterating": `
		local t = {}
		for i = 1, 20 do t[i] = i end
		local s = 0
		for round = 1, 30 do
			for i, v in ipairs(t) do
				s = s + v
				if i == 5 and #t < 60 then t[#t + 1] = round end
				if i == 7 then t[i] = t[i] + 1 end
			end
		end
		return s, #t`,
	"pairs with numeric work": `
		local t = {a = 1, b = 2.5, c = 3, d = 4, e = 5}
		local s, n = 0, 0
		for round = 1, 200 do
			for k, v in pairs(t) do s = s + v * round % 7 n = n + #k end
		end
		return s, n`,
	"pairs over an array with updates": `
		local t = {}
		for i = 1, 40 do t[i] = i end
		local s = 0
		for round = 1, 50 do for k, v in pairs(t) do t[k] = v + 1 s = s + v end end
		return s, t[1], t[40]`,
	"custom iterators": `
		local function range(n) local i = 0 return function() i = i + 1 if i <= n then return i, i * i end end end
		local function iter(t, i) i = i + 1 if t[i] then return i, t[i] end end
		local t = {5, 6, 7}
		local s = 0
		for round = 1, 60 do
			for i, sq in range(10) do s = s + i + sq end
			for i, v in iter, t, 0 do s = s + i * v end
		end
		return s`,
	"break and nested generic loops": `
		local a, b = {1, 2, 3, 4, 5, 6}, {10, 20, 30}
		local s = 0
		for round = 1, 60 do
			for i, x in ipairs(a) do
				if x > 4 then break end
				for _, y in ipairs(b) do s = s + x * y if y == 20 and x == 2 then break end end
			end
		end
		return s`,
	"iterator raises an error": `
		local function bad(t, i) if i >= 150 then error("stop") end return i + 1, i end
		local ok, msg = pcall(function() local s = 0 for i, v in bad, nil, 0 do s = s + v end return s end)
		return ok, (tostring(msg):gsub("^.-:%d+: ", ""))`,
	"ipairs with a metatable": `
		local t = setmetatable({1, 2, 3}, {__index = function(_, i) if i <= 6 then return i * 10 end end})
		local s = 0
		for round = 1, 60 do for i, v in ipairs(t) do s = s + v end end
		return s`,
	"control variable type changes": `
		local t = {}
		for i = 1, 30 do t[i] = i end
		local s = 0
		for round = 1, 40 do
			local it, st, c = ipairs(t)
			if round % 10 == 0 then c = 5 end
			for i, v in it, st, c do s = s + v end
		end
		return s`,
}

func TestJITGenericForPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitGenericForPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		_, st := runChunk(jitTestOptions(version, 5), `
			local t = {}
			for i = 1, 1000 do t[i] = i * 0.5 end
			local s = 0
			for round = 1, 50 do for i, v in ipairs(t) do s = s + v * i end end
			return s`)
		if st.Compiled == 0 || st.Callouts > 300 || st.Blacklisted != 0 {
			t.Errorf("%v: ipairs over numbers is not native: %s", version, st)
		}
		_, st = runChunk(jitTestOptions(version, 5), `
			local t = {}
			for i = 1, 200 do t[i] = {v = i, w = 2} end
			local s = 0
			for round = 1, 100 do for _, o in ipairs(t) do s = s + o.v * o.w + round % 3 end end
			return s`)
		// (with so little work per element the loop may be handed back
		// to the interpreter afterwards: the iterator runs as a callout)
		if st.Compiled == 0 {
			t.Errorf("%v: a generic for loop over tables is not compiled: %s", version, st)
		}
	}
}

// jitMethodPrograms exercise method calls on objects.
var jitMethodPrograms = map[string]string{
	"class with methods": `
		local Point = {}
		Point.__index = Point
		function Point.new(x, y) return setmetatable({x = x, y = y}, Point) end
		function Point:len2() return self.x * self.x + self.y * self.y end
		function Point:move(dx, dy) self.x = self.x + dx self.y = self.y + dy return self end
		local p = Point.new(1, 2)
		local s = 0
		for i = 1, 300 do p:move(1, 0.5) s = s + p:len2() end
		return s, p.x, p.y`,
	"inheritance": `
		local Base = {} Base.__index = Base
		function Base:area() return 0 end
		function Base:double() return self:area() * 2 end
		local Rect = setmetatable({}, {__index = Base}) Rect.__index = Rect
		function Rect:area() return self.w * self.h end
		local r = setmetatable({w = 3, h = 4}, Rect)
		local b = setmetatable({w = 1, h = 1}, Base)
		local s = 0
		for i = 1, 300 do s = s + r:double() + b:double() + r:area() end
		return s`,
	"method replaced and shadowed": `
		local C = {} C.__index = C
		function C:get() return self.v end
		local o = setmetatable({v = 1}, C)
		local s = 0
		for i = 1, 300 do
			if i == 100 then C.get = function(self) return self.v * 10 end end
			if i == 200 then o.get = function(self) return -1 end end
			if i == 250 then o.get = nil end
			s = s + o:get()
		end
		return s`,
	"objects of different classes and layouts": `
		local A = {} A.__index = A function A:val() return self.n end
		local B = {} B.__index = B function B:val() return self.n * 2 end
		local objs = {setmetatable({n = 1}, A), setmetatable({n = 2}, B), setmetatable({n = 3, extra = 1}, A), {n = 4, val = function(self) return 100 end}}
		local s = 0
		for i = 1, 400 do local o = objs[i % 4 + 1] s = s + o:val() end
		return s`,
	"metatable replaced": `
		local A = {} A.__index = A function A:f() return 1 end
		local B = {} B.__index = B function B:f() return 2 end
		local o = setmetatable({}, A)
		local s = 0
		for i = 1, 300 do
			if i == 150 then setmetatable(o, B) end
			if i == 220 then A.__index = B setmetatable(o, A) end
			s = s + o:f()
		end
		return s`,
	"field added to the object": `
		local C = {} C.__index = C function C:f() return self.a end
		local o = setmetatable({a = 1}, C)
		local s = 0
		for i = 1, 300 do
			if i == 120 then o.b = 5 end
			if i == 180 then o.f = function() return 7 end end
			s = s + o:f()
		end
		return s`,
	"__index function and missing method": `
		local C = setmetatable({}, {__index = function(_, k) return function(self) return #k end end})
		local o = setmetatable({}, {__index = C})
		local p = setmetatable({}, {__index = {}})
		local s = 0
		for i = 1, 200 do s = s + o:anything() end
		local ok, msg = pcall(function() for i = 1, 100 do p:nothing() end end)
		return s, ok, (tostring(msg):gsub("^.-:%d+: ", ""))`,
	"string methods": `local s = 0 local str = "hello" for i = 1, 200 do s = s + str:len() + #str:upper() end return s`,
	"method with branches": `
		local Acc = {} Acc.__index = Acc
		function Acc:add(v) if v > self.max then self.max = v end self.sum = self.sum + v return self.sum end
		local a = setmetatable({sum = 0, max = 0}, Acc)
		local t = 0
		for i = 1, 300 do t = t + a:add(i % 37) end
		return t, a.sum, a.max`,
}

func TestJITMethodPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitMethodPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, name := range []string{"class with methods", "inheritance", "method with branches"} {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			src := strings.Replace(jitMethodPrograms[name], "300", "20000", -1)
			_, st := runChunk(jitTestOptions(version, 5), src)
			if st.Compiled == 0 || st.Callouts > 200 || st.Blacklisted != 0 || st.Deopts > 50 {
				t.Errorf("%s (%v): method calls are not native: %s", name, version, st)
			}
		}
	}
}

// jitRefPrograms exercise boxed values (tables, strings, functions) that
// compiled code reads from arrays and fields without copying them.
var jitRefPrograms = map[string]string{
	"array of objects": `
		local objs = {}
		for i = 1, 50 do objs[i] = {v = i, w = i * 0.5} end
		local s = 0
		for round = 1, 20 do
			for i = 1, #objs do local o = objs[i] s = s + o.v * o.w o.v = o.v + 1 end
		end
		return s, objs[50].v`,
	"ipairs over objects": `
		local objs = {}
		for i = 1, 50 do objs[i] = {v = i, tag = "t" .. i} end
		local s, n = 0, 0
		for round = 1, 20 do
			for i, o in ipairs(objs) do s = s + o.v + i n = n + #o.tag end
		end
		return s, n`,
	"nested fields": `
		local cfg = {limits = {max = 10, min = 2}, name = "cfg", inner = {deep = {x = 3}}}
		local s = 0
		for i = 1, 300 do
			s = s + cfg.limits.max - cfg.limits.min + cfg.inner.deep.x + #cfg.name
			cfg.inner.deep.x = cfg.inner.deep.x + 1
		end
		return s, cfg.inner.deep.x`,
	"matrix": `
		local m = {}
		for i = 1, 20 do m[i] = {} for j = 1, 20 do m[i][j] = i * j end end
		local s = 0
		for round = 1, 10 do
			for i = 1, 20 do for j = 1, 20 do s = s + m[i][j] m[i][j] = m[i][j] + 1 end end
		end
		return s, m[20][20]`,
	"linked list": `
		local head
		for i = 1, 100 do head = {v = i, next = head} end
		local s = 0
		for round = 1, 20 do
			local node = head
			while node do s = s + node.v node = node.next end
		end
		return s`,
	"array with holes and nil elements": `
		local t = {}
		for i = 1, 30 do t[i] = {v = i} end
		t[7], t[19] = nil, false
		local s, holes = 0, 0
		for round = 1, 20 do
			for i = 1, 30 do local o = t[i] if o then s = s + o.v else holes = holes + 1 end end
			for _, o in ipairs(t) do s = s + o.v end
		end
		return s, holes`,
	"elements replaced while iterating": `
		local objs = {}
		for i = 1, 40 do objs[i] = {v = i} end
		local s = 0
		for round = 1, 20 do
			for i = 1, #objs do
				local o = objs[i]
				if i % 7 == 0 then objs[i] = {v = o.v + round} end
				if i % 11 == 0 then objs[i + 1] = o end
				s = s + o.v + objs[i].v
			end
		end
		return s`,
	"strings from arrays and fields": `
		local names = {"alpha", "beta", "gamma", "delta"}
		local rec = {name = "rec", kind = "k"}
		local n, joined = 0, ""
		for i = 1, 200 do
			local s = names[i % 4 + 1]
			n = n + #s + #rec.name
			if s == "beta" then n = n + 1 end
			if i % 50 == 0 then joined = joined .. s .. rec.kind end
		end
		return n, joined`,
	"functions from arrays and fields": `
		local ops = {function(x) return x + 1 end, function(x) return x * 2 end, function(x) return x - 3 end}
		local lib = {inc = function(x) return x + 1 end}
		local s = 0
		for i = 1, 300 do s = ops[i % 3 + 1](s) % 1000 + lib.inc(i) end
		return s`,
	"objects with methods in an array": `
		local C = {} C.__index = C
		function C:area() return self.w * self.h end
		local shapes = {}
		for i = 1, 30 do shapes[i] = setmetatable({w = i, h = 2}, C) end
		local s = 0
		for round = 1, 20 do for _, sh in ipairs(shapes) do s = s + sh:area() end end
		return s`,
	"array with a metatable": `
		local t = setmetatable({{v = 1}, {v = 2}}, {__index = function(_, i) return {v = i * 100} end})
		local s = 0
		for i = 1, 200 do s = s + t[i % 4 + 1].v end
		return s`,
	"field holds different kinds": `
		local o = {p = {v = 1}}
		local s = 0
		for i = 1, 300 do
			local p = o.p
			if type(p) == "table" then s = s + p.v elseif type(p) == "number" then s = s + p else s = s + #p end
			if i == 100 then o.p = 5 elseif i == 200 then o.p = "text" elseif i == 250 then o.p = {v = 9} end
		end
		return s`,
	"reference kept across a call": `
		local objs = {{v = 1}, {v = 2}, {v = 3}}
		local function swap() objs[1], objs[2] = objs[2], objs[1] end
		local s = 0
		for i = 1, 300 do
			local o = objs[1]
			if i % 10 == 0 then swap() end
			s = s + o.v + objs[1].v
		end
		return s`,
}

func TestJITRefPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitRefPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
	for _, name := range []string{"array of objects", "ipairs over objects", "nested fields", "matrix", "objects with methods in an array"} {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			src := strings.Replace(strings.Replace(jitRefPrograms[name], "round = 1, 20", "round = 1, 400", -1), "i = 1, 300", "i = 1, 20000", -1)
			_, st := runChunk(jitTestOptions(version, 5), src)
			// (a few callouts per round set up the loops: the call of
			// ipairs, the marker of the closing value)
			if st.Compiled == 0 || st.Callouts > 2000 || st.Blacklisted != 0 {
				t.Errorf("%s (%v): access to boxed values is not native: %s", name, version, st)
			}
		}
	}
}

// TestJITRefsUnderGC runs code that keeps references into tables while
// the garbage collector works as hard as it can.
func TestJITRefsUnderGC(t *testing.T) {
	skipWithoutJIT(t)
	defer debug.SetGCPercent(debug.SetGCPercent(1))
	src := `
		local objs = {}
		for i = 1, 200 do objs[i] = {v = i, name = "n" .. i, child = {w = i}} end
		local s = 0
		for round = 1, 300 do
			for i, o in ipairs(objs) do
				s = s + o.v + o.child.w + #o.name
				if (i + round) % 97 == 0 then objs[i] = {v = i, name = "m" .. round, child = {w = round}} end
			end
		end
		return s`
	want, _ := runChunk(Options{}, src)
	done := make(chan struct{})
	go func() {
		for {
			select {
			case <-done:
				return
			default:
				runtime.GC()
			}
		}
	}()
	for i := 0; i < 5; i++ {
		if got, _ := runChunk(jitTestOptions(Lua51, 3), src); got != want {
			t.Fatalf("got %s, want %s", got, want)
		}
	}
	close(done)
}

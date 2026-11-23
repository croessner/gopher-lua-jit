package lua

import (
	"context"
	"fmt"
	"runtime"
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
	for _, interval := range []int{-1, -1 << 40, 1 << 40} {
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

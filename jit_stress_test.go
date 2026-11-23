package lua

import (
	"context"
	"fmt"
	"math/rand"
	"runtime"
	"runtime/debug"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/yuin/gopher-lua/internal/jit/codecache"
)

const jitKernel = `
local n = ...
local t = {}
for i = 1, n do t[i] = i * 2 end
local s, f = 0, 0.0
for k = 1, 20 do
  for i = 1, #t do
    s = s + t[i] % 7
    f = f + i / (k + 1)
  end
end
return s, f
`

// kernelResult runs jitKernel with the given options.
func kernelResult(t testing.TB, opts Options, n int) string {
	t.Helper()
	L := NewState(opts)
	defer L.Close()
	fn, err := L.LoadString(jitKernel)
	if err != nil {
		t.Fatal(err)
	}
	L.Push(fn)
	L.Push(LNumber(n))
	if err := L.PCall(1, 2, nil); err != nil {
		t.Fatal(err)
	}
	return L.Get(-2).String() + "/" + L.Get(-1).String()
}

// TestJITConcurrentStates runs many independent states with the JIT on
// different goroutines while the garbage collector is kept busy.
func TestJITConcurrentStates(t *testing.T) {
	skipWithoutJIT(t)
	want := kernelResult(t, Options{}, 500)
	old := debug.SetGCPercent(5)
	defer debug.SetGCPercent(old)
	var wg sync.WaitGroup
	errs := make(chan string, 64)
	workers := runtime.GOMAXPROCS(0) * 2
	rounds := 30
	if testing.Short() {
		rounds = 5
	}
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := 0; r < rounds; r++ {
				L := NewState(jitTestOptions(Lua51, 3))
				fn, err := L.LoadString(jitKernel)
				if err != nil {
					errs <- err.Error()
					L.Close()
					return
				}
				for call := 0; call < 3; call++ {
					L.Push(fn)
					L.Push(LNumber(500))
					if err := L.PCall(1, 2, nil); err != nil {
						errs <- err.Error()
						break
					}
					if got := L.Get(-2).String() + "/" + L.Get(-1).String(); got != want {
						errs <- fmt.Sprintf("got %s, want %s", got, want)
					}
					L.SetTop(0)
				}
				if st := L.JITStats(); st.Compiled == 0 {
					errs <- "nothing was compiled"
				}
				L.Close()
			}
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Error(e)
	}
}

// TestJITStatePool shares JIT enabled states between goroutines through a
// pool (one goroutine at a time per state).
func TestJITStatePool(t *testing.T) {
	skipWithoutJIT(t)
	want := kernelResult(t, Options{}, 200)
	pool := sync.Pool{New: func() interface{} { return NewState(jitTestOptions(Lua55, 2)) }}
	var wg sync.WaitGroup
	var mu sync.Mutex
	var failures []string
	for w := 0; w < 8; w++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for r := 0; r < 40; r++ {
				L := pool.Get().(*LState)
				if err := L.DoString("result = nil"); err != nil {
					mu.Lock()
					failures = append(failures, err.Error())
					mu.Unlock()
				}
				fn, _ := L.LoadString(jitKernel)
				L.Push(fn)
				L.Push(LInteger(200))
				if err := L.PCall(1, 2, nil); err != nil {
					mu.Lock()
					failures = append(failures, err.Error())
					mu.Unlock()
				} else if got := L.ToStringMeta(L.Get(-2)).String() + "/" + L.ToStringMeta(L.Get(-1)).String(); !strings.HasPrefix(want, strings.TrimSuffix(got[:strings.Index(got, "/")], ".0")) {
					mu.Lock()
					failures = append(failures, "pool result "+got+" vs "+want)
					mu.Unlock()
				}
				L.SetTop(0)
				pool.Put(L)
			}
		}()
	}
	wg.Wait()
	for _, f := range failures {
		t.Error(f)
	}
}

// TestJITContextCancel checks that a loop running in native code honors
// context cancellation at its safe points.
func TestJITContextCancel(t *testing.T) {
	skipWithoutJIT(t)
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		L := NewState(Options{LanguageVersion: version, JIT: JITOptions{Enabled: true, Threshold: 2}})
		ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
		L.SetContext(ctx)
		start := time.Now()
		err := L.DoString(`local x = 0 while true do x = x + 1 end`)
		elapsed := time.Since(start)
		cancel()
		if err == nil || !strings.Contains(err.Error(), context.DeadlineExceeded.Error()) {
			t.Errorf("%v: expected a deadline error, got %v", version, err)
		}
		if elapsed > 5*time.Second {
			t.Errorf("%v: cancellation took %v", version, elapsed)
		}
		if st := L.JITStats(); st.Compiled == 0 || st.SafePoints == 0 {
			t.Errorf("%v: the loop did not run natively: %s", version, st)
		}
		// the state stays usable
		L.RemoveContext()
		if err := L.DoString(`local s = 0 for i = 1, 100 do s = s + i end assert(s == 5050)`); err != nil {
			t.Errorf("%v: state unusable after cancellation: %v", version, err)
		}
		L.Close()
	}
}

// TestJITCodeCacheLimit checks that the executable memory of a state is
// bounded and that execution stays correct across cache flushes.
func TestJITCodeCacheLimit(t *testing.T) {
	skipWithoutJIT(t)
	limit := 8 * codecachePageSize()
	L := NewState(Options{JIT: JITOptions{Enabled: true, Threshold: 2, MaxCodeBytes: limit}})
	defer L.Close()
	for i := 0; i < 200; i++ {
		// every chunk has a different loop, so a new unit is compiled
		src := fmt.Sprintf(`local s = 0 for i = 1, 40 do s = s + i * %d end return s`, i+1)
		fn, err := L.LoadString(src)
		if err != nil {
			t.Fatal(err)
		}
		L.Push(fn)
		if err := L.PCall(0, 1, nil); err != nil {
			t.Fatal(err)
		}
		if got, want := int(LVAsNumber(L.Get(-1))), 820*(i+1); got != want {
			t.Fatalf("chunk %d: got %d, want %d", i, got, want)
		}
		L.SetTop(0)
		if st := L.JITStats(); st.CodeBytes > limit {
			t.Fatalf("code cache holds %d bytes, limit is %d", st.CodeBytes, limit)
		}
	}
	st := L.JITStats()
	if st.CacheFlushes == 0 {
		t.Errorf("expected cache flushes: %s", st)
	}
	if st.Compiled < 20 {
		t.Errorf("expected many compiled units: %s", st)
	}
}

// codecachePageSize returns the granularity of executable memory.
func codecachePageSize() int {
	b, err := codecache.Alloc([]byte{0xC3})
	if err != nil {
		return 1 << 14
	}
	defer b.Free()
	return b.Size()
}

// requireNoMappedCode fails the test if the state still owns executable
// memory. (The process wide counters of the code cache cannot be used
// for this: finalizers of other states change them concurrently.)
func requireNoMappedCode(t *testing.T, L *LState) {
	t.Helper()
	if n := len(L.G.jit.mem.blocks); n != 0 {
		t.Fatalf("%d blocks of executable memory are still mapped", n)
	}
	if st := L.JITStats(); st.CodeBytes != 0 || st.LiveUnits != 0 {
		t.Fatalf("code survived: %s", st)
	}
}

// TestJITCloseReleasesCode checks that closing a state unmaps its code.
func TestJITCloseReleasesCode(t *testing.T) {
	skipWithoutJIT(t)
	for i := 0; i < 50; i++ {
		L := NewState(jitTestOptions(Lua55, 1))
		if err := L.DoString(`local s = 0 for i = 1, 100 do for j = 1, 10 do s = s + i * j end end`); err != nil {
			t.Fatal(err)
		}
		if st := L.JITStats(); st.CodeBytes == 0 {
			t.Fatalf("no code was mapped: %s", st)
		}
		L.Close()
		requireNoMappedCode(t, L)
	}
}

// TestJITFlush checks the explicit cache flush.
func TestJITFlush(t *testing.T) {
	skipWithoutJIT(t)
	L := NewState(jitTestOptions(Lua55, 1))
	defer L.Close()
	src := `local s = 0 for i = 1, 100 do s = s + i end return s`
	for round := 0; round < 3; round++ {
		if err := L.DoString(src); err != nil {
			t.Fatal(err)
		}
		if st := L.JITStats(); st.LiveUnits == 0 {
			t.Fatalf("round %d: no live unit: %s", round, st)
		}
		L.JITFlush()
		if st := L.JITStats(); st.LiveUnits != 0 || st.CodeBytes != 0 {
			t.Fatalf("round %d: flush left code behind: %s", round, st)
		}
	}
}

// TestJITNestedActivations exercises native code that calls back into
// Lua functions which run native loops themselves, recursively.
func TestJITNestedActivations(t *testing.T) {
	skipWithoutJIT(t)
	src := `
local function work(depth)
  local s = 0
  for i = 1, 20 do
    s = s + i
    if depth > 0 and i % 5 == 0 then s = s + work(depth - 1) end
  end
  return s
end
return work(%d)`
	for _, depth := range []int{0, 1, 3, 6} {
		code := fmt.Sprintf(src, depth)
		want, _ := runChunk(Options{}, code)
		got, st := runChunk(jitTestOptions(Lua51, 1), code)
		if got != want {
			t.Errorf("depth %d: got %s, want %s (%s)", depth, got, want, st)
		}
	}
}

// TestJITErrorsKeepStateConsistent raises errors from inside natively
// executed loops and checks that the state can be used afterwards.
func TestJITErrorsKeepStateConsistent(t *testing.T) {
	skipWithoutJIT(t)
	L := NewState(jitTestOptions(Lua55, 1))
	defer L.Close()
	for round := 0; round < 50; round++ {
		err := L.DoString(`
local t = {}
for i = 1, 100 do
  t[i] = i
  if i == 60 then error({code = i}) end
end`)
		if err == nil {
			t.Fatal("expected an error")
		}
		if err := L.DoString(`local s = 0 for i = 1, 50 do s = s + i end assert(s == 1275)`); err != nil {
			t.Fatalf("round %d: %v", round, err)
		}
		if L.GetTop() != 0 {
			t.Fatalf("round %d: stack not empty: %d", round, L.GetTop())
		}
		if th := L.jit; th != nil && len(th.acts) != 0 {
			t.Fatalf("round %d: %d native activations leaked", round, len(th.acts))
		}
	}
}

/* random differential testing {{{ */

// progGen generates random numeric Lua programs.
type progGen struct {
	rng   *rand.Rand
	sb    strings.Builder
	depth int
	loops int
	lua55 bool
}

var genVars = []string{"a", "b", "c", "d", "x", "y"}

func (g *progGen) v() string { return genVars[g.rng.Intn(len(genVars))] }

func (g *progGen) intConst() string {
	return fmt.Sprint([]int64{0, 1, 2, 3, 5, 7, 10, 16, 31, 64, 100, -1, -2, -7, 1000003}[g.rng.Intn(15)])
}

func (g *progGen) expr(depth int) string {
	if depth <= 0 || g.rng.Intn(4) == 0 {
		switch g.rng.Intn(6) {
		case 0:
			return g.intConst()
		case 1:
			return fmt.Sprintf("%.3f", g.rng.Float64()*20-10)
		case 2:
			return "t[i % #t + 1]"
		case 3:
			return []string{"p.u", "p.v", "p.w", "q.u", "q.v", "k1", "k2"}[g.rng.Intn(7)]
		default:
			return g.v()
		}
	}
	l, r := g.expr(depth-1), g.expr(depth-1)
	ops := []string{"+", "-", "*", "/", "%"}
	if g.lua55 {
		ops = append(ops, "//", "&", "|", "~", "<<", ">>")
	}
	switch g.rng.Intn(24) {
	case 0:
		return "math.floor(" + l + ")"
	case 1:
		return "math.abs(" + l + ")"
	case 2:
		return "-(" + l + ")"
	case 3:
		return "math.sqrt(math.abs(" + l + "))"
	case 4:
		return "h1(" + l + ", " + r + ")"
	case 5:
		return "h2(" + l + ")"
	case 6:
		return "h3(" + []string{"p", "q"}[g.rng.Intn(2)] + ", " + l + ")"
	case 7:
		return "(flags[i % 16 + 1] and " + l + " or " + r + ")"
	case 8:
		return "h5(" + l + ", " + r + ")"
	case 9:
		return "h6(" + l + ")"
	case 10:
		return "obj:get()"
	case 11:
		return "obj:bump(" + l + ")"
	case 12:
		return "h7(names[i % 4 + 1], names[" + []string{"1", "2", "(i + 1) % 4 + 1"}[g.rng.Intn(3)] + "])"
	case 13:
		return "(recs[i % 3 + 1].n + #recs[i % 3 + 1].tag)"
	}
	op := ops[g.rng.Intn(len(ops))]
	switch op {
	case "&", "|", "~", "<<", ">>":
		// bitwise operators need integers: keep operands integral
		return fmt.Sprintf("(math.floor(%s) %s (math.floor(%s) %% 67))", l, op, r)
	}
	return "(" + l + " " + op + " " + r + ")"
}

func (g *progGen) cond() string {
	ops := []string{"<", "<=", ">", ">=", "==", "~="}
	return g.expr(1) + " " + ops[g.rng.Intn(len(ops))] + " " + g.expr(1)
}

func (g *progGen) stmt() {
	ind := strings.Repeat("  ", g.depth)
	switch k := g.rng.Intn(10); {
	case k < 1:
		// fields, boolean array elements, helper results, upvalues
		switch g.rng.Intn(13) {
		case 0, 1, 2:
			fmt.Fprintf(&g.sb, "%s%s = %s\n", ind, []string{"p.u", "p.v", "p.w", "q.u"}[g.rng.Intn(4)], g.expr(2))
		case 3, 4:
			fmt.Fprintf(&g.sb, "%sflags[i %% 16 + 1] = %s\n", ind, g.cond())
		case 5, 6:
			fmt.Fprintf(&g.sb, "%s%s, %s = h4(%s, %s)\n", ind, g.v(), g.v(), g.expr(1), g.expr(1))
		case 7:
			fmt.Fprintf(&g.sb, "%s%s = %s\n", ind, []string{"k1", "k2"}[g.rng.Intn(2)], g.expr(1))
		case 8:
			fmt.Fprintf(&g.sb, "%sif i %% 37 == 0 then q.v = %s end\n", ind, []string{"'7'", "nil", "true", "3"}[g.rng.Intn(4)])
		case 9:
			v := g.v()
			fmt.Fprintf(&g.sb, "%sfor n, e in ipairs(t) do %s = %s + e * n end\n", ind, v, v)
		case 10:
			v := g.v()
			fmt.Fprintf(&g.sb, "%sfor _, e in pairs(%s) do if type(e) == 'number' then %s = %s + e end end\n",
				ind, []string{"p", "q", "flags"}[g.rng.Intn(3)], v, v)
		case 11:
			fmt.Fprintf(&g.sb, "%sif i %% 41 == 0 then %s end\n", ind, []string{
				"Cls.get = function(self) return self.v end", "obj.extra = i", "obj.get = function() return 3 end",
				"obj.get = nil", "Cls.bump = function(self, m) return m end",
				"recs[2] = {n = i, tag = 'new'}", "recs[1].n = recs[1].n + 1", "names[3] = names[1]", "recs[3].tag = 'x'",
			}[g.rng.Intn(9)])
		default:
			fmt.Fprintf(&g.sb, "%s%s = %s\n", ind, g.v(), g.expr(2))
		}
	case k < 4:
		fmt.Fprintf(&g.sb, "%s%s = %s\n", ind, g.v(), g.expr(2))
	case k < 5:
		fmt.Fprintf(&g.sb, "%st[i %% #t + 1] = %s\n", ind, g.expr(2))
	case k < 7 && g.depth < 3:
		fmt.Fprintf(&g.sb, "%sif %s then\n", ind, g.cond())
		g.block()
		if g.rng.Intn(2) == 0 {
			fmt.Fprintf(&g.sb, "%selse\n", ind)
			g.block()
		}
		fmt.Fprintf(&g.sb, "%send\n", ind)
	case k < 9 && g.depth < 3 && g.loops < 3:
		g.loops++
		name := fmt.Sprintf("j%d", g.loops)
		fmt.Fprintf(&g.sb, "%sfor %s = 1, %d do\n", ind, name, 3+g.rng.Intn(20))
		fmt.Fprintf(&g.sb, "%s  %s = %s + %s\n", ind, g.v(), g.v(), name)
		g.block()
		fmt.Fprintf(&g.sb, "%send\n", ind)
		g.loops--
	default:
		fmt.Fprintf(&g.sb, "%s%s, %s = %s, %s\n", ind, g.v(), g.v(), g.expr(1), g.expr(1))
	}
}

func (g *progGen) block() {
	g.depth++
	for n := 1 + g.rng.Intn(3); n > 0; n-- {
		g.stmt()
	}
	g.depth--
}

// generate returns a program whose result is a string of all variables.
// Errors (for example integer division by zero) are caught and become
// part of the result.
func (g *progGen) generate() string {
	g.sb.Reset()
	g.sb.WriteString("local a, b, c, d, x, y = 1, 2, 3.5, -4, 0.25, 7\n")
	g.sb.WriteString("local t = {}\nfor i = 1, 16 do t[i] = i")
	if g.rng.Intn(2) == 0 {
		g.sb.WriteString(" * 1.5")
	}
	g.sb.WriteString(" end\n")
	g.sb.WriteString("local p, q = {u = 1, v = 2.5, w = -3}, {v = 4, extra = 's', u = 9}\n")
	g.sb.WriteString("local flags = {}\nfor i = 1, 16 do flags[i] = i % 3 == 0 end\n")
	g.sb.WriteString("local k1, k2 = 3, 0.5\n")
	g.sb.WriteString("local function h1(m, n) return m * k1 + n end\n")
	g.sb.WriteString("local function h2(m) return h1(m, k2) - m end\n")
	g.sb.WriteString("local function h3(o, m) o.u = o.u + m return o.v end\n")
	g.sb.WriteString("local function h4(m, n) return n, m end\n")
	g.sb.WriteString("local function h5(m, n) if m > n then return m end return n end\n")
	g.sb.WriteString("local function h6(m) local r = m if m < 0 then r = -m end return r + (m > k1 and 1 or 0) end\n")
	g.sb.WriteString("local names = {'delta', 'alpha', 'gamma', 'beta'}\n")
	g.sb.WriteString("local recs = {{n = 1, tag = 'a'}, {n = 2.5, tag = 'bb'}, {n = 3, tag = 'ccc'}}\n")
	g.sb.WriteString("local function h7(m, n) if m < n then return 1 end return 0 end\n")
	g.sb.WriteString("local Cls = {}\nCls.__index = Cls\n")
	g.sb.WriteString("function Cls:get() return self.u + self.v end\n")
	g.sb.WriteString("function Cls:bump(m) self.u = self.u + m return self.u end\n")
	g.sb.WriteString("local obj = setmetatable({u = 1, v = 2}, Cls)\n")
	g.sb.WriteString("local ok, err = pcall(function()\n")
	fmt.Fprintf(&g.sb, "for i = 1, %d do\n", 30+g.rng.Intn(150))
	g.depth = 1
	for n := 2 + g.rng.Intn(5); n > 0; n-- {
		g.stmt()
	}
	g.sb.WriteString("end\nend)\n")
	g.sb.WriteString("local parts = {tostring(ok), ok and '' or (string.gsub(tostring(err), '^.-:%d+: ', ''))}\n")
	g.sb.WriteString("for _, v in ipairs({a, b, c, d, x, y}) do parts[#parts + 1] = string.format('%.14g', v) end\n")
	g.sb.WriteString("for i = 1, #t do parts[#parts + 1] = string.format('%.14g', t[i]) end\n")
	g.sb.WriteString("for _, v in ipairs({p.u or 'nil', p.v or 'nil', p.w or 'nil', q.u or 'nil', q.v or 'nil', k1, k2, obj.u, obj.v}) do\n")
	g.sb.WriteString("  parts[#parts + 1] = type(v) == 'number' and string.format('%.14g', v) or tostring(v)\nend\n")
	g.sb.WriteString("for i = 1, #flags do parts[#parts + 1] = tostring(flags[i]) end\n")
	g.sb.WriteString("return table.concat(parts, ' ')\n")
	return g.sb.String()
}

// checkRandomProgram compares interpreter and JIT on one generated
// program. It returns the JIT statistics of the runs.
func checkRandomProgram(t *testing.T, seed int64) (stats JITStats) {
	t.Helper()
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		g := &progGen{rng: rand.New(rand.NewSource(seed)), lua55: version == Lua55}
		src := g.generate()
		want, _ := runChunk(Options{LanguageVersion: version}, src)
		if strings.HasPrefix(want, "load error") {
			t.Fatalf("seed %d: generated program does not compile: %s\n%s", seed, want, src)
		}
		for _, threshold := range []int{1, 4} {
			got, st := runChunk(jitTestOptions(version, threshold), src)
			if got != want {
				t.Fatalf("seed %d (%v, threshold %d): results differ\n jit:         %s\n interpreter: %s\nprogram:\n%s",
					seed, version, threshold, got, want, src)
			}
			stats.Compiled += st.Compiled
			stats.Entries += st.Entries
			stats.Deopts += st.Deopts
			stats.Callouts += st.Callouts
		}
	}
	return stats
}

func TestJITRandomPrograms(t *testing.T) {
	skipWithoutJIT(t)
	n := 400
	if testing.Short() {
		n = 60
	}
	var total JITStats
	for seed := int64(1); seed <= int64(n); seed++ {
		st := checkRandomProgram(t, seed)
		total.Compiled += st.Compiled
		total.Entries += st.Entries
		total.Deopts += st.Deopts
		total.Callouts += st.Callouts
	}
	t.Logf("%d programs: %d units compiled, %d native entries, %d deopts, %d callouts",
		n, total.Compiled, total.Entries, total.Deopts, total.Callouts)
	if total.Compiled < n || total.Entries < uint64(n) {
		t.Errorf("the generated programs hardly exercised the JIT")
	}
}

// FuzzJIT feeds the random program generator from the fuzzing engine.
func FuzzJIT(f *testing.F) {
	for seed := int64(1000); seed < 1010; seed++ {
		f.Add(seed)
	}
	f.Fuzz(func(t *testing.T, seed int64) {
		if !jitSupported() {
			t.Skip()
		}
		checkRandomProgram(t, seed)
	})
}

/* }}} */

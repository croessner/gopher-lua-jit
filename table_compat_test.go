package lua

import (
	"bufio"
	"crypto/sha256"
	"fmt"
	"os"
	"strings"
	"testing"
)

// tableCompatExpectations reads the digests of the traces that upstream
// GopherLua produces for testdata/table_compat.lua, by seed. The file is
// written by benchmarks/tablecompat with the upstream module file.
func tableCompatExpectations(t *testing.T) map[int]string {
	t.Helper()
	f, err := os.Open("testdata/table_compat_upstream.txt")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	want := make(map[int]string)
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		var seed, length int
		var digest string
		if _, err := fmt.Sscanf(sc.Text(), "%d %s %d", &seed, &digest, &length); err != nil {
			t.Fatalf("malformed expectation %q: %v", sc.Text(), err)
		}
		want[seed] = fmt.Sprintf("%s %d", digest, length)
	}
	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}
	if len(want) == 0 {
		t.Fatal("no expectations")
	}
	return want
}

// TestTablesBehaveLikeUpstream runs random sequences of table operations
// (assignments at and beyond the border, nil assignments, table.insert,
// table.remove, table.concat, unpack, table.maxn, the length operator,
// traversals) and compares everything they deliver with what upstream
// GopherLua delivers for the same program. The Lua 5.1 profile promises
// that behaviour, whatever the representation of a table is: with the
// JIT enabled arrays of numbers and booleans are stored unboxed.
func TestTablesBehaveLikeUpstream(t *testing.T) {
	want := tableCompatExpectations(t)
	defaults := Options{JIT: JITOptions{Enabled: true}}
	configs := []struct {
		name string
		opts Options
	}{
		{"interpreter", Options{}},
		{"jit", jitTestOptions(Lua51, 3)},
		{"jit with default settings", defaults},
	}
	// The gap decides which elements behind the end of an array are kept
	// in the sparse map; with a small one most of the tables of the
	// script use it.
	defer func(gap int) { tableSparseGap = gap }(tableSparseGap)
	for _, gap := range []int{tableSparseGap, 0, 3} {
		for _, cfg := range configs {
			gap, cfg := gap, cfg
			t.Run(fmt.Sprintf("%s, sparse gap %d", cfg.name, gap), func(t *testing.T) {
				tableSparseGap = gap
				checkTablesLikeUpstream(t, cfg.opts, want)
			})
		}
	}
}

// checkTablesLikeUpstream runs testdata/table_compat.lua for every seed
// with the given options and compares the traces with the expectations.
func checkTablesLikeUpstream(t *testing.T, opts Options, want map[int]string) {
	{
		{
			cfg := struct{ opts Options }{opts}
			if cfg.opts.JIT.Enabled {
				skipWithoutJIT(t)
			}
			L := NewState(cfg.opts)
			defer L.Close()
			if err := L.DoFile("testdata/table_compat.lua"); err != nil {
				t.Fatal(err)
			}
			run := L.Get(-1)
			L.Pop(1)
			failures := 0
			for seed := 1; seed <= len(want); seed++ {
				if err := L.CallByParam(P{Fn: run, NRet: 1, Protect: true}, LNumber(seed)); err != nil {
					t.Fatalf("seed %d: %v", seed, err)
				}
				trace := L.Get(-1).String()
				L.Pop(1)
				got := fmt.Sprintf("%x %d", sha256.Sum256([]byte(trace)), len(trace))
				if got != want[seed] {
					failures++
					if failures <= 3 {
						t.Errorf("seed %d differs from upstream GopherLua (digest and length %s, want %s); trace:\n%s",
							seed, got, want[seed], strings.ReplaceAll(trace, "] [", "]\n["))
					}
				}
			}
			if failures > 3 {
				t.Errorf("%d seeds differ in total", failures)
			}
		}
	}
}

// TestTableSlotsBehindTheArray checks the cases that the unboxed array
// parts once got wrong: GopherLua keeps the slot of an element that is
// set to nil, and table.remove and table.insert work on slots.
func TestTableSlotsBehindTheArray(t *testing.T) {
	const src = `
		local out = {}
		local function note(...) out[#out + 1] = table.concat({tostring(...), tostring((select(2, ...)))}, ":") end
		local t = {1, 2, 3}
		t[3] = nil
		note(table.remove(t), #t)       -- the nil slot goes first
		note(table.remove(t), #t)
		local u = {1.5, 2.5}
		u[4] = nil                      -- slots up to 4
		note(table.remove(u), #u)
		note(table.remove(u), #u)
		note(table.remove(u), #u)
		local w = {true, false}
		w[2] = nil
		w[2] = true                     -- takes its slot again
		note(table.remove(w), #w)
		local s = {}
		for i = 1, 40 do s[i] = i end
		for i = 1, 5 do s[#s] = nil end
		for i = 1, 3 do s[#s + 1] = -i end
		note(table.remove(s), #s)       -- two nil slots are left
		note(table.remove(s), #s)
		note(table.remove(s), #s)
		table.insert(s, 37, 99)         -- shifts -2 and -3 up
		note(s[37], s[38])
		return table.concat(out, " ")`
	const want = "nil:2 2:1 nil:2 nil:2 2.5:1 true:1 nil:38 nil:38 -3:37 99:-2"
	for name, opts := range map[string]Options{
		"interpreter":               {},
		"jit":                       jitTestOptions(Lua51, 3),
		"jit with default settings": {JIT: JITOptions{Enabled: true}},
	} {
		if got, _ := runChunk(opts, src); got != "string:"+want {
			t.Errorf("%s: got %s, want %s", name, got, want)
		}
	}
}

// TestSparseElementsJoinTheArray checks that an element that was stored
// far behind the end of an array becomes part of the stored elements
// once the gap is filled: compiled loops over the array (ipairs, the
// length operator, appends) rely on the stored elements being all there
// is up to the first nil.
func TestSparseElementsJoinTheArray(t *testing.T) {
	defer func(gap int) { tableSparseGap = gap }(tableSparseGap)
	tableSparseGap = 0
	const src = `
		local t = {1, 2, 3}
		t[6] = 60                       -- behind a gap
		t[9] = 90
		local sums = {}
		local function sum()
			local s, n = 0, 0
			for k = 1, 50 do
				n = 0
				for i, v in ipairs(t) do s = s + v n = n + 1 end
			end
			sums[#sums + 1] = s / 50 .. "/" .. n .. "/" .. #t
		end
		sum()
		t[4] = 4 sum()                  -- 5 is still missing
		t[5] = 5 sum()                  -- 6 joins: 1..6
		t[7] = 7 t[8] = 8 sum()         -- 9 joins: 1..9
		for i = 1, 100 do t[#t + 1] = i end
		sum()
		t[200] = 1
		for i = 1, 100 do t[#t + 1] = i end -- appended behind 200
		sum()
		return table.concat(sums, " ")`
	const want = "6/3/9 10/4/9 75/6/9 180/9/9 5230/109/109 5230/109/300"
	for name, opts := range map[string]Options{
		"interpreter":               {},
		"jit":                       jitTestOptions(Lua51, 3),
		"jit with default settings": {JIT: JITOptions{Enabled: true}},
	} {
		if got, _ := runChunk(opts, src); got != "string:"+want {
			t.Errorf("%s: got %s, want %s", name, got, want)
		}
	}
}

// TestSparseElementsThroughGoAPI checks the methods of LTable that Go
// code calls directly on a table with elements far behind its array.
func TestSparseElementsThroughGoAPI(t *testing.T) {
	L := NewState()
	defer L.Close()
	tb := L.NewTable()
	for i := 1; i <= 3; i++ {
		tb.RawSetInt(i, LNumber(i))
	}
	tb.RawSetInt(5000000, LString("far"))
	tb.RawSetInt(70000, LString("near"))
	tb.RawSetString("name", LString("x"))
	if got := tb.Len(); got != 5000000 {
		t.Errorf("Len = %d, want 5000000", got)
	}
	if got := tb.MaxN(); got != 5000000 {
		t.Errorf("MaxN = %d, want 5000000", got)
	}
	if got := tb.RawGetInt(70000); got != LString("near") {
		t.Errorf("RawGetInt(70000) = %v", got)
	}
	if got := tb.RawGet(LNumber(5000000)); got != LString("far") {
		t.Errorf("RawGet(5000000) = %v", got)
	}
	if got := tb.RawGetInt(4); got != LNil {
		t.Errorf("RawGetInt(4) = %v", got)
	}
	// ForEach and Next visit the array part in ascending order
	want := []string{"1", "2", "3", "70000", "5000000", "name"}
	var each []string
	tb.ForEach(func(k, v LValue) { each = append(each, k.String()) })
	var next []string
	for k, v := tb.Next(LNil); k != LNil; k, v = tb.Next(k) {
		_ = v
		next = append(next, k.String())
	}
	if strings.Join(each, " ") != strings.Join(want, " ") {
		t.Errorf("ForEach visits %v, want %v", each, want)
	}
	if strings.Join(next, " ") != strings.Join(want, " ") {
		t.Errorf("Next visits %v, want %v", next, want)
	}
	// a copy is independent
	c := tb.Clone()
	c.RawSetInt(70000, LNil)
	if tb.RawGetInt(70000) != LString("near") || c.RawGetInt(70000) != LNil || c.Len() != 5000000 {
		t.Errorf("Clone shares its sparse elements")
	}
	// Append goes behind the last element, Remove takes it away again
	tb.Append(LString("last"))
	if got := tb.RawGetInt(5000001); got != LString("last") {
		t.Errorf("Append stored %v behind the last element", got)
	}
	if got := tb.Remove(-1); got != LString("last") {
		t.Errorf("Remove(-1) = %v", got)
	}
	// Insert moves everything behind the position up
	tb.Insert(2, LString("new"))
	if tb.RawGetInt(2) != LString("new") || tb.RawGetInt(4) != LNumber(3) || tb.RawGetInt(70001) != LString("near") || tb.Len() != 5000001 {
		t.Errorf("Insert did not move the elements behind it: %v %v %v %d", tb.RawGetInt(2), tb.RawGetInt(4), tb.RawGetInt(70001), tb.Len())
	}
	if got := tb.Remove(1); got != LNumber(1) || tb.RawGetInt(70000) != LString("near") || tb.Len() != 5000000 {
		t.Errorf("Remove(1) = %v, element 70000 = %v, Len = %d", got, tb.RawGetInt(70000), tb.Len())
	}
}

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
	for _, cfg := range configs {
		cfg := cfg
		t.Run(cfg.name, func(t *testing.T) {
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
		})
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

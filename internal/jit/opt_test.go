package jit

import (
	"math/rand"
	"testing"
)

// memBuilder builds straight-line test functions that access memory
// through bases whose addresses the optimizer cannot compare.
type memBuilder struct {
	f *Func
	b *Block
}

func newMemBuilder(name string) *memBuilder {
	f := NewFunc(name)
	return &memBuilder{f: f, b: f.Entry}
}

// base returns the address RegBase + 8*regs[k]: two bases are the same
// address exactly when the two registers hold the same index.
func (m *memBuilder) base(k int) *Value {
	off := m.f.NewValue(m.b, OpShl, TInt, 0, loadReg(m.f, m.b, k), m.f.ConstInt(m.b, 3))
	return m.f.NewValue(m.b, OpAdd, TInt, 0, m.f.RegBase(), off)
}

func (m *memBuilder) load(mem uint8, base *Value, disp int64) *Value {
	return m.loadOp(OpLoad64, mem, base, disp)
}

// loadOp loads with the given operation; the narrow loads read the low
// bytes of the word on the little-endian targets of the compiler.
func (m *memBuilder) loadOp(op Op, mem uint8, base *Value, disp int64) *Value {
	v := m.f.NewValue(m.b, op, TInt, disp, base)
	v.Mem = mem
	return v
}

func (m *memBuilder) store(mem uint8, base *Value, disp int64, val *Value) {
	m.f.NewValue(m.b, OpStore64, TInt, disp, base, val).Mem = mem
}

func (m *memBuilder) callout() {
	co := m.f.NewValue(m.b, OpCallout, TInt, 0)
	co.Exit = m.f.NewExit(ExitCallout, 0)
}

func (m *memBuilder) guard(cond *Value) { m.guardAt(cond, 0) }

// guardAt adds a guard whose exit is identified by pc.
func (m *memBuilder) guardAt(cond *Value, pc int) {
	g := m.f.NewValue(m.b, OpGuard, TInt, 0, cond)
	g.Exit = m.f.NewExit(ExitDeopt, pc)
	g.Exit.Snap = []SnapEntry{{Slot: 0, Val: m.f.ConstInt(m.b, -1)}}
}

func (m *memBuilder) add(x, y *Value) *Value {
	return m.f.NewValue(m.b, OpAdd, TInt, 0, x, y)
}

// countValues counts the values of f that pass the filter.
func countValues(f *Func, filter func(*Value) bool) int {
	n := 0
	for _, b := range f.Blocks {
		for _, v := range b.Values {
			if filter(v) {
				n++
			}
		}
	}
	return n
}

// classifiedLoad selects the loads that take part in load elimination.
func classifiedLoad(v *Value) bool { return v.Op.IsLoad() && v.Mem != MemNone }

func isGuard(v *Value) bool { return v.Op == OpGuard }

// TestMemCSE checks which loads and guards the optimizer keeps.
func TestMemCSE(t *testing.T) {
	const d = 256 // displacement of the words the tests access
	tests := []struct {
		name   string
		build  func(m *memBuilder) []*Value
		loads  int // classified loads that must remain
		guards int
	}{
		{"repeated load is reused", func(m *memBuilder) []*Value {
			p := m.base(0)
			return []*Value{m.load(MemStable, p, d), m.load(MemStable, p, d)}
		}, 1, 0},
		{"unclassified loads are kept", func(m *memBuilder) []*Value {
			p := m.base(0)
			return []*Value{m.load(MemNone, p, d), m.load(MemNone, p, d), m.load(MemStable, p, d)}
		}, 1, 0},
		{"another displacement is another word", func(m *memBuilder) []*Value {
			p := m.base(0)
			return []*Value{m.load(MemField, p, d), m.load(MemField, p, d+8)}
		}, 2, 0},
		{"store through another base invalidates its class", func(m *memBuilder) []*Value {
			p, q := m.base(0), m.base(1)
			x := m.load(MemArray, p, d)
			m.store(MemArray, q, d, m.f.ConstInt(m.b, 5))
			return []*Value{x, m.load(MemArray, p, d)}
		}, 2, 0},
		{"store to another word of the same object keeps the load", func(m *memBuilder) []*Value {
			p := m.base(0)
			x := m.load(MemField, p, d)
			m.store(MemField, p, d+8, m.f.ConstInt(m.b, 5))
			return []*Value{x, m.load(MemField, p, d)}
		}, 1, 0},
		{"store of another class keeps the load", func(m *memBuilder) []*Value {
			p, q := m.base(0), m.base(1)
			x := m.load(MemField, p, d)
			m.store(MemArray, q, d+64, m.f.ConstInt(m.b, 5))
			return []*Value{x, m.load(MemField, p, d)}
		}, 1, 0},
		{"unclassified store invalidates everything", func(m *memBuilder) []*Value {
			p, q := m.base(0), m.base(1)
			x := m.load(MemField, p, d)
			m.store(MemNone, q, d+64, m.f.ConstInt(m.b, 5))
			return []*Value{x, m.load(MemField, p, d)}
		}, 2, 0},
		{"stored value is forwarded", func(m *memBuilder) []*Value {
			p := m.base(0)
			m.store(MemArray, p, d, m.add(loadReg(m.f, m.b, 2), m.f.ConstInt(m.b, 1)))
			return []*Value{m.load(MemArray, p, d)}
		}, 0, 0},
		{"store invalidates narrow loads of its word", func(m *memBuilder) []*Value {
			p := m.base(0)
			x := m.loadOp(OpLoad8, MemField, p, d)
			y := m.loadOp(OpLoad32, MemField, p, d)
			m.store(MemField, p, d, loadReg(m.f, m.b, 2))
			return []*Value{x, y, m.loadOp(OpLoad8, MemField, p, d), m.loadOp(OpLoad32, MemField, p, d)}
		}, 4, 0},
		{"forwarded value is invalidated like a load", func(m *memBuilder) []*Value {
			p, q := m.base(0), m.base(1)
			m.store(MemArray, p, d, loadReg(m.f, m.b, 2))
			m.store(MemArray, q, d, loadReg(m.f, m.b, 3))
			return []*Value{m.load(MemArray, p, d)}
		}, 1, 0},
		{"storing a loaded value leaves its own word alone", func(m *memBuilder) []*Value {
			p, q, r := m.base(0), m.base(1), m.base(2)
			x := m.load(MemField, p, d)
			m.store(MemArray, q, d+64, x)
			m.store(MemField, r, d, m.f.ConstInt(m.b, 5))
			return []*Value{x, m.load(MemField, p, d)}
		}, 2, 0},
		{"callout invalidates everything", func(m *memBuilder) []*Value {
			p := m.base(0)
			x := m.load(MemStable, p, d)
			m.callout()
			return []*Value{x, m.load(MemStable, p, d)}
		}, 2, 0},
		{"repeated guard is dropped", func(m *memBuilder) []*Value {
			p := m.base(0)
			x := m.load(MemStable, p, d)
			c := m.f.NewValue(m.b, OpLt, TInt, 0, x, m.f.ConstInt(m.b, 1000))
			m.guard(c)
			m.guard(c)
			// the second check reads the same word again, as the front
			// end does for every access to a table
			y := m.load(MemStable, p, d)
			m.guard(m.f.NewValue(m.b, OpLt, TInt, 0, y, m.f.ConstInt(m.b, 1000)))
			return []*Value{x, y}
		}, 1, 1},
		{"guards on different conditions stay", func(m *memBuilder) []*Value {
			p := m.base(0)
			x := m.load(MemStable, p, d)
			m.guard(m.f.NewValue(m.b, OpLt, TInt, 0, x, m.f.ConstInt(m.b, 1000)))
			m.guard(m.f.NewValue(m.b, OpLt, TInt, 0, x, m.f.ConstInt(m.b, 2000)))
			return []*Value{x}
		}, 1, 2},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			m := newMemBuilder("memcse")
			exitWith(m.f, m.b, tt.build(m)...)
			Optimize(m.f)
			if err := m.f.Verify(); err != nil {
				t.Fatalf("Verify: %v\n%s", err, m.f)
			}
			if got := countValues(m.f, classifiedLoad); got != tt.loads {
				t.Errorf("%d classified loads remain, want %d\n%s", got, tt.loads, m.f)
			}
			if got := countValues(m.f, isGuard); got != tt.guards {
				t.Errorf("%d guards remain, want %d\n%s", got, tt.guards, m.f)
			}
		})
	}
}

// Layout of the memory the random programs of TestMemCSEDifferential
// access: four index registers, then one region of memRegion words for
// every memory class.
const (
	memBases   = 4
	memRegion  = 8
	memClasses = 4 // MemStable, MemArrayLen, MemArray, MemField
	memWords   = memRegion * (1 + memClasses)
)

// memDisp returns the displacement of word j in the region of class mem.
func memDisp(mem uint8, j int) int64 {
	return 8 * int64(memRegion*int(mem)+j)
}

// buildRandomMem builds a random sequence of loads, stores, callouts and
// guards in one block (see memScript).
func buildRandomMem(seed int64) *Func {
	s := newMemScript("memrand", seed)
	s.run(20 + s.rng.Intn(60))
	exitWith(s.m.f, s.m.b, s.acc)
	return s.m.f
}

// TestMemCSEDifferential runs random memory programs in the reference
// interpreter and as optimized native code and compares exits, results
// and memory.
func TestMemCSEDifferential(t *testing.T) {
	rng := rand.New(rand.NewSource(1))
	for seed := int64(0); seed < 500; seed++ {
		checkAgainstInterpreter(t, seed, func() *Func { return buildRandomMem(seed) }, randomMemory(rng))
	}
}

// buildGuardedBranch builds
//
//	if regs[0] != 0 then guard(c) [exit 1] end
//	guard(c) [exit 2]
//
// with c = (regs[1] == 7). The second guard is not redundant: the first
// one only holds on one of the paths that reach it.
func buildGuardedBranch() *Func {
	m := newMemBuilder("guardscope")
	f := m.f
	c := f.NewValue(m.b, OpEq, TInt, 0, loadReg(f, m.b, 1), f.ConstInt(m.b, 7))
	entry := m.b
	then, skip, join := f.NewBlock(), f.NewBlock(), f.NewBlock()
	entry.Kind = BlockIf
	entry.Control = loadReg(f, entry, 0)
	AddEdge(entry, then)
	AddEdge(entry, skip)
	m.b = then
	m.guardAt(c, 1)
	AddEdge(then, join)
	AddEdge(skip, join)
	m.b = join
	m.guardAt(c, 2)
	// a third check of the same condition is covered by the second
	m.guardAt(c, 3)
	exitWith(f, join, f.ConstInt(join, 5))
	return f
}

// TestGuardEliminationFollowsDominance checks that a guard is only
// dropped if a guard on the same condition dominates it.
func TestGuardEliminationFollowsDominance(t *testing.T) {
	f := buildGuardedBranch()
	Optimize(f)
	if got := countValues(f, isGuard); got != 2 {
		t.Errorf("%d guards remain, want 2\n%s", got, f)
	}
	for _, tt := range []struct {
		regs []uint64
		pc   int
	}{
		{[]uint64{1, 7}, 0}, {[]uint64{0, 7}, 0}, // the condition holds: the end is reached
		{[]uint64{1, 8}, 1}, {[]uint64{0, 8}, 2},
	} {
		r := runNative(t, buildGuardedBranch(), tt.regs, 1, nil)
		if pc := r.code.Exits[r.exit].PC; pc != tt.pc {
			t.Errorf("regs %v: left at exit %d, want %d", tt.regs, pc, tt.pc)
		}
	}
}

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

func (m *memBuilder) guard(cond *Value) {
	g := m.f.NewValue(m.b, OpGuard, TInt, 0, cond)
	g.Exit = m.f.NewExit(ExitDeopt, 0)
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
// guards. Words of different classes never overlap, as the front end
// promises; within a class the bases alias whenever their index registers
// are equal. Unclassified accesses go to any writable region.
func buildRandomMem(seed int64) *Func {
	rng := rand.New(rand.NewSource(seed))
	m := newMemBuilder("memrand")
	bases := make([]*Value, memBases)
	for k := range bases {
		bases[k] = m.base(k)
	}
	writable := []uint8{MemArrayLen, MemArray, MemField}
	pool := []*Value{m.f.ConstInt(m.b, 3), loadReg(m.f, m.b, 0)}
	pick := func() *Value { return pool[rng.Intn(len(pool))] }
	acc := m.f.ConstInt(m.b, 0)
	var conds []*Value
	for n := 20 + rng.Intn(60); n > 0; n-- {
		base, j := bases[rng.Intn(memBases)], rng.Intn(3)
		switch r := rng.Intn(100); {
		case r < 45:
			mem := MemStable + uint8(rng.Intn(memClasses))
			region := mem
			if rng.Intn(8) == 0 {
				mem, region = MemNone, writable[rng.Intn(len(writable))]
			}
			op := OpLoad64
			if k := rng.Intn(10); k < 3 {
				op = []Op{OpLoad32, OpLoad8, OpLoad8}[k]
			}
			v := m.loadOp(op, mem, base, memDisp(region, j))
			pool = append(pool, v)
			acc = m.add(m.f.NewValue(m.b, OpMul, TInt, 0, acc, m.f.ConstInt(m.b, 31)), v)
		case r < 80:
			mem := writable[rng.Intn(len(writable))]
			region := mem
			if rng.Intn(8) == 0 {
				mem = MemNone
			}
			m.store(mem, base, memDisp(region, j), m.add(pick(), pick()))
		case r < 85:
			m.callout()
		default:
			// conditions that mostly hold, often checked more than once
			if len(conds) == 0 || rng.Intn(2) == 0 {
				conds = append(conds, m.f.NewValue(m.b, OpNe, TInt, 0, pick(), m.f.ConstInt(m.b, int64(rng.Intn(400)))))
			}
			m.guard(conds[rng.Intn(len(conds))])
		}
	}
	exitWith(m.f, m.b, acc)
	return m.f
}

// TestMemCSEDifferential runs random memory programs in the reference
// interpreter and as optimized native code and compares exits, results
// and memory.
func TestMemCSEDifferential(t *testing.T) {
	// what Go code does during a callout: it may change any word
	disturb := func(regs []uint64) {
		for i := memRegion; i < len(regs); i++ {
			regs[i] += uint64(i)
		}
	}
	rng := rand.New(rand.NewSource(1))
	for seed := int64(0); seed < 500; seed++ {
		init := make([]uint64, memWords)
		for k := 0; k < memBases; k++ {
			init[k] = uint64(rng.Intn(3)) // few indices: bases alias often
		}
		for i := memRegion; i < len(init); i++ {
			init[i] = uint64(rng.Intn(50))
		}

		ref := buildRandomMem(seed)
		regsI := append([]uint64(nil), init...)
		ctx := make([]uint64, CtxHeaderWords+64)
		want := interpret(ref, regsI, ctx, func(*Exit, map[*Value]uint64) { disturb(regsI) })
		wantVal := uint64(want.exit.Snap[0].Val.Aux)
		if !want.exit.Snap[0].Val.IsConst() {
			wantVal = want.vals[want.exit.Snap[0].Val]
		}

		regsN := append([]uint64(nil), init...)
		got := runNative(t, buildRandomMem(seed), regsN, 1<<30, func(ExitInfo, []uint64) { disturb(regsN) })
		if got.exit != want.exit.ID {
			t.Fatalf("seed %d: exit %d, want %d\n%s", seed, got.exit, want.exit.ID, ref)
		}
		if v := got.value(0); v != wantVal {
			t.Fatalf("seed %d: result %#x, want %#x\n%s", seed, v, wantVal, ref)
		}
		for i := range regsI {
			if regsI[i] != regsN[i] {
				t.Fatalf("seed %d: word %d = %#x, want %#x\n%s", seed, i, regsN[i], regsI[i], ref)
			}
		}
	}
}

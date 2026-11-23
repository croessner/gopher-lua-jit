package jit

import (
	"math/rand"
	"testing"
)

// memScript emits random memory operations into the current block of a
// builder: loads whose results are mixed into acc, stores, callouts and
// guards. Words of different classes never overlap, as the front end
// promises; within a class the bases alias whenever their index
// registers are equal. Unclassified accesses go to any writable region.
type memScript struct {
	m        *memBuilder
	rng      *rand.Rand
	bases    []*Value
	pool     []*Value // values that are defined wherever the script continues
	conds    []*Value
	acc      *Value
	callouts bool
	guards   int
	// stores is the share of stores among the operations in percent,
	// classes the memory classes they go to and condRange the range of
	// the constants that guarded values are compared with (the smaller,
	// the more guards fail).
	stores    int
	classes   []uint8
	condRange int
}

func newMemScript(name string, seed int64) *memScript {
	s := &memScript{
		m: newMemBuilder(name), rng: rand.New(rand.NewSource(seed)), callouts: true,
		stores: 35, classes: []uint8{MemArrayLen, MemArray, MemField}, condRange: 400,
	}
	for k := 0; k < memBases; k++ {
		s.bases = append(s.bases, s.m.base(k))
	}
	s.pool = []*Value{s.m.f.ConstInt(s.m.b, 3), loadReg(s.m.f, s.m.b, 0)}
	s.acc = s.m.f.ConstInt(s.m.b, 0)
	return s
}

func (s *memScript) pick() *Value { return s.pool[s.rng.Intn(len(s.pool))] }

// step emits one random operation.
func (s *memScript) step() {
	m, rng := s.m, s.rng
	writable := []uint8{MemArrayLen, MemArray, MemField}
	base, j := s.bases[rng.Intn(memBases)], rng.Intn(3)
	switch r := rng.Intn(65 + s.stores); {
	case r >= 65:
		// a store, classified or (rarely) not
		mem := s.classes[rng.Intn(len(s.classes))]
		region := mem
		if rng.Intn(8) == 0 {
			mem, region = MemNone, writable[rng.Intn(len(writable))]
		}
		m.store(mem, base, memDisp(region, j), m.add(s.pick(), s.pick()))
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
		s.pool = append(s.pool, v)
		s.acc = m.add(m.f.NewValue(m.b, OpMul, TInt, 0, s.acc, m.f.ConstInt(m.b, 31)), v)
	case r < 50:
		if s.callouts {
			m.callout()
		}
	default:
		// conditions that mostly hold, often checked more than once
		if len(s.conds) == 0 || rng.Intn(2) == 0 {
			s.conds = append(s.conds, m.f.NewValue(m.b, OpNe, TInt, 0, s.pick(), m.f.ConstInt(m.b, int64(rng.Intn(s.condRange)))))
		}
		s.guards++
		m.guardAt(s.conds[rng.Intn(len(s.conds))], s.guards)
	}
}

// run emits n random operations.
func (s *memScript) run(n int) {
	for ; n > 0; n-- {
		s.step()
	}
}

// scope remembers what is defined at this point of the script; the
// returned function forgets everything that was defined after it.
func (s *memScript) scope() func() {
	pool, conds, acc := len(s.pool), len(s.conds), s.acc
	return func() { s.pool, s.conds, s.acc = s.pool[:pool], s.conds[:conds], acc }
}

// loop emits a counted loop with the given number of iterations in
// front of the current block's end: random operations in its header and
// in its body, which body may extend (for a nested loop). The script
// continues behind the loop, where the values of the header are still
// defined. In half of the cases the body can also leave the loop early.
func (s *memScript) loop(trips int, body func()) {
	m, f := s.m, s.m.f
	pre := m.b
	zero := f.ConstInt(pre, 0)
	before := s.acc
	head, first, after := f.NewBlock(), f.NewBlock(), f.NewBlock()
	AddEdge(pre, head)
	i := f.NewPhi(head, TInt)
	acc := f.NewPhi(head, TInt)
	m.b, s.acc = head, acc
	s.pool = append(s.pool, i)
	s.run(s.rng.Intn(5))
	head.Kind = BlockIf
	head.Control = f.NewValue(head, OpLt, TInt, 0, i, f.ConstInt(head, int64(trips)))
	AddEdge(head, first)
	AddEdge(head, after)
	leave := s.scope()
	atHead := s.acc
	m.b = first
	s.run(3 + s.rng.Intn(20))
	var early *Value
	if s.rng.Intn(2) == 0 {
		// break: the block behind the loop is reached from the header
		// and from here, with different values
		early = s.acc
		rest := f.NewBlock()
		first.Kind = BlockIf
		first.Control = f.NewValue(first, OpLt, TInt, 0, s.pick(), f.ConstInt(first, int64(s.rng.Intn(60))))
		AddEdge(first, after)
		AddEdge(first, rest)
		m.b = rest
	}
	if body != nil {
		body()
	}
	s.run(s.rng.Intn(8))
	next := m.add(i, f.ConstInt(m.b, 1))
	AddEdge(m.b, head)
	i.Args = []*Value{zero, next}
	acc.Args = []*Value{before, s.acc}
	leave()
	m.b = after
	if early != nil {
		s.acc = f.NewPhi(after, TInt)
		s.acc.Args = []*Value{atHead, early}
	}
}

// buildRandomLoop builds a random program with a loop that, in half of
// the cases, contains a second loop. Values of the loops are used behind
// them.
func buildRandomLoop(seed int64) *Func {
	s := newMemScript("looprand", seed)
	s.callouts = s.rng.Intn(4) == 0 // loops with callouts are not peeled
	// loops with few stores, or stores to some classes only, leave
	// more to reuse across iterations
	s.stores = []int{0, 3, 10, 35}[s.rng.Intn(4)]
	s.classes = s.classes[:1+s.rng.Intn(3)]
	s.condRange = []int{60, 400}[s.rng.Intn(2)]
	s.run(s.rng.Intn(8))
	var inner func()
	if s.rng.Intn(2) == 0 {
		inner = func() { s.loop(s.rng.Intn(5), nil) }
	}
	s.loop(2+s.rng.Intn(8), inner)
	s.run(s.rng.Intn(8))
	exitWith(s.m.f, s.m.b, s.acc, s.pick(), s.pick())
	return s.m.f
}

// checkAgainstInterpreter runs the program that build returns in the
// reference interpreter and, optimized, as native code, with the given
// memory, and compares where they end, what they deliver and what they
// leave in memory. Callouts change memory the same way in both.
func checkAgainstInterpreter(t *testing.T, seed int64, build func() *Func, init []uint64) {
	t.Helper()
	disturb := func(regs []uint64) {
		for i := memRegion; i < len(regs); i++ {
			regs[i] += uint64(i)
		}
	}
	ref := build()
	regsI := append([]uint64(nil), init...)
	ctx := make([]uint64, CtxHeaderWords+64)
	want := interpret(ref, regsI, ctx, func(*Exit, map[*Value]uint64) { disturb(regsI) })

	regsN := append([]uint64(nil), init...)
	got := runNative(t, build(), regsN, 1<<30, func(ExitInfo, []uint64) { disturb(regsN) })
	if pc := got.code.Exits[got.exit].PC; pc != want.exit.PC {
		t.Fatalf("seed %d: left at exit %d, want %d\n%s", seed, pc, want.exit.PC, ref)
	}
	for _, e := range want.exit.Snap {
		wantVal := want.vals[e.Val]
		if e.Val.IsConst() {
			wantVal = uint64(e.Val.Aux)
		}
		if v := got.value(e.Slot); v != wantVal {
			t.Fatalf("seed %d: slot %d is %#x, want %#x\n%s", seed, e.Slot, v, wantVal, ref)
		}
	}
	for i := range regsI {
		if regsI[i] != regsN[i] {
			t.Fatalf("seed %d: word %d = %#x, want %#x\n%s", seed, i, regsN[i], regsI[i], ref)
		}
	}
}

// randomMemory returns initial memory for the random programs: few
// distinct indexes, so that the bases alias often.
func randomMemory(rng *rand.Rand) []uint64 {
	init := make([]uint64, memWords)
	for k := 0; k < memBases; k++ {
		init[k] = uint64(rng.Intn(3))
	}
	for i := memRegion; i < len(init); i++ {
		init[i] = uint64(rng.Intn(50))
	}
	return init
}

// TestPeelDifferential runs random programs with loops in the reference
// interpreter and as optimized native code.
func TestPeelDifferential(t *testing.T) {
	rng := rand.New(rand.NewSource(2))
	for seed := int64(0); seed < 1500; seed++ {
		init := randomMemory(rng)
		checkAgainstInterpreter(t, seed, func() *Func { return buildRandomLoop(seed) }, init)
	}
}

// loopCounts returns the number of classified loads and of guards that
// are left inside the loops of f.
func loopCounts(f *Func) (loads, guards int) {
	removeUnreachable(f)
	for _, l := range findLoops(f, dominators(f)) {
		for b := range l.body {
			for _, v := range b.Values {
				if classifiedLoad(v) {
					loads++
				}
				if isGuard(v) {
					guards++
				}
			}
		}
	}
	return loads, guards
}

// buildArraySum builds the loop
//
//	for i = 0, n-1 do s = s + array[i] end
//
// over an array whose kind (word 8) is checked and whose position (word
// 9, an index into the memory) is loaded on every iteration. extra adds
// further operations to the body.
func buildArraySum(extra func(m *memBuilder)) *Func {
	m := newMemBuilder("arraysum")
	f := m.f
	n := loadReg(f, m.b, 0)
	zero := f.ConstInt(m.b, 0)
	head, body, done := f.NewBlock(), f.NewBlock(), f.NewBlock()
	AddEdge(m.b, head)
	i := f.NewPhi(head, TInt)
	s := f.NewPhi(head, TInt)
	head.Kind = BlockIf
	head.Control = f.NewValue(head, OpLt, TInt, 0, i, n)
	AddEdge(head, body)
	AddEdge(head, done)
	m.b = body
	kind := m.load(MemStable, f.RegBase(), 8*8)
	m.guardAt(f.NewValue(body, OpEq, TInt, 0, kind, f.ConstInt(body, 7)), 1)
	pos := m.load(MemStable, f.RegBase(), 8*9)
	length := m.load(MemArrayLen, f.RegBase(), 8*10)
	m.guardAt(f.NewValue(body, OpULt, TInt, 0, i, length), 2)
	addr := m.add(f.RegBase(), f.NewValue(body, OpShl, TInt, 0, m.add(pos, i), f.ConstInt(body, 3)))
	elem := m.load(MemArray, addr, 0)
	if extra != nil {
		extra(m)
	}
	s2 := m.add(s, elem)
	i2 := m.add(i, f.ConstInt(m.b, 1))
	fuel := f.NewValue(m.b, OpFuel, TInt, 0)
	fuel.Exit = f.NewExit(ExitFuel, 0)
	AddEdge(m.b, head)
	i.Args = []*Value{zero, i2}
	s.Args = []*Value{zero, s2}
	exitWith(f, done, s)
	return f
}

// TestPeelRemovesInvariantChecks checks what is left in a loop after the
// first iteration was peeled off.
func TestPeelRemovesInvariantChecks(t *testing.T) {
	tests := []struct {
		name          string
		extra         func(m *memBuilder)
		loads, guards int
	}{
		// the element load and the bounds check depend on the iteration
		{"read only loop", nil, 1, 1},
		// a store to an element does not change kind, position or length
		{"element store", func(m *memBuilder) {
			m.store(MemArray, m.f.RegBase(), 8*24, m.f.ConstInt(m.b, 1))
		}, 1, 1},
		// a store to a length makes the length depend on the iteration
		{"length store", func(m *memBuilder) {
			m.store(MemArrayLen, m.f.RegBase(), 8*11, m.f.ConstInt(m.b, 4))
		}, 2, 1},
		// after a callout nothing is known: such loops are not peeled
		{"callout", func(m *memBuilder) { m.callout() }, 4, 2},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			f := buildArraySum(tt.extra)
			Optimize(f)
			if err := f.Verify(); err != nil {
				t.Fatalf("Verify: %v\n%s", err, f)
			}
			loads, guards := loopCounts(f)
			if loads != tt.loads || guards != tt.guards {
				t.Errorf("%d loads and %d guards in the loop, want %d and %d\n%s", loads, guards, tt.loads, tt.guards, f)
			}
			// regs: n, then the kind, the position and the length of
			// the array, whose elements start at word 16
			regs := make([]uint64, 32)
			regs[0], regs[8], regs[9], regs[10], regs[11] = 6, 7, 16, 6, 4
			want := uint64(0)
			for k := 0; k < 6; k++ {
				regs[16+k] = uint64(10 * (k + 1))
				want += regs[16+k]
			}
			r := runNative(t, buildArraySum(tt.extra), regs, 3, nil)
			if got := r.value(0); got != want {
				t.Errorf("sum = %d, want %d", got, want)
			}
		})
	}
}

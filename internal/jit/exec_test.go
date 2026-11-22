package jit

import (
	"math"
	"math/rand"
	"testing"
	"unsafe"

	"github.com/yuin/gopher-lua/internal/jit/codecache"
)

// nativeResult is the outcome of running compiled code.
type nativeResult struct {
	exit  int
	frame []uint64
	code  *Code
}

// value returns the snapshot value of slot in the final exit.
func (r nativeResult) value(slot int) uint64 {
	for _, e := range r.code.Exits[r.exit].Entries {
		if e.Slot == slot {
			return locValue(r.frame, e)
		}
	}
	panic("slot not in snapshot")
}

// locValue reads the value of an exit entry from a context frame.
func locValue(frame []uint64, e ExitEntry) uint64 {
	switch e.Loc.Kind {
	case LocReg:
		return frame[CtxSaveG/8+e.Loc.N]
	case LocFReg:
		return frame[CtxSaveF/8+e.Loc.N]
	case LocSpill:
		return frame[CtxSpill/8+e.Loc.N]
	case LocConst:
		return uint64(e.Const)
	}
	panic("bad location")
}

// runNative compiles f for the host and executes it. The hook is called
// for every callout exit before the code is resumed.
func runNative(t testing.TB, f *Func, regs []uint64, fuel uint64, callout func(info ExitInfo, frame []uint64)) nativeResult {
	t.Helper()
	if !codecache.Supported || !HostSupported() {
		t.Skip("native execution is not supported on this platform")
	}
	code, err := Compile(f, NewHostAsm())
	if err != nil {
		t.Fatalf("Compile: %v\n%s", err, f)
	}
	blk, err := codecache.Alloc(code.Bytes)
	if err != nil {
		t.Fatalf("Alloc: %v", err)
	}
	defer blk.Free()
	frame := make([]uint64, code.FrameWords)
	// poison the save areas so that stale register contents are detected
	for i := CtxSaveG / 8; i < CtxSpill/8; i++ {
		frame[i] = 0xDEAD0000DEAD0000 + uint64(i)
	}
	if len(regs) == 0 {
		regs = make([]uint64, 1)
	}
	frame[CtxRegBase/8] = uint64(uintptr(unsafe.Pointer(&regs[0])))
	frame[CtxFuel/8] = fuel
	frame[CtxTarget/8] = uint64(blk.Addr()) + uint64(code.EntryOffset)
	for n := 0; ; n++ {
		if n > 1<<22 {
			t.Fatal("too many exits")
		}
		codecache.Call(blk.Addr(), unsafe.Pointer(&frame[0]))
		id := int(frame[CtxExit/8])
		info := code.Exits[id]
		switch info.Kind {
		case ExitDeopt:
			return nativeResult{exit: id, frame: frame, code: code}
		case ExitCallout:
			if callout != nil {
				callout(info, frame)
			}
		case ExitFuel:
			frame[CtxFuel/8] = fuel
		}
		frame[CtxTarget/8] = uint64(blk.Addr()) + uint64(info.Resume)
	}
}

// exitWith terminates block b with a deoptimization exit carrying vals in
// the snapshot slots 0..n-1.
func exitWith(f *Func, b *Block, vals ...*Value) {
	x := f.NewExit(ExitDeopt, 0)
	for i, v := range vals {
		x.Snap = append(x.Snap, SnapEntry{Slot: i, Val: v})
	}
	b.Kind = BlockExit
	b.Exit = x
}

func loadReg(f *Func, b *Block, i int) *Value {
	return f.NewValue(b, OpLoad64, TInt, int64(8*i), f.RegBase())
}

func loadRegF(f *Func, b *Block, i int) *Value {
	return f.NewValue(b, OpLoadF64, TFloat, int64(8*i), f.RegBase())
}

func TestSumLoop(t *testing.T) {
	// s = 0; for i = 1, n do s = s + i*i end
	f := NewFunc("sum")
	entry := f.Entry
	head, body, done := f.NewBlock(), f.NewBlock(), f.NewBlock()
	n := loadReg(f, entry, 0)
	zero := f.ConstInt(entry, 0)
	one := f.ConstInt(entry, 1)
	AddEdge(entry, head)
	i := f.NewPhi(head, TInt)
	s := f.NewPhi(head, TInt)
	cond := f.NewValue(head, OpLe, TInt, 0, i, n)
	head.Kind = BlockIf
	head.Control = cond
	AddEdge(head, body)
	AddEdge(head, done)
	sq := f.NewValue(body, OpMul, TInt, 0, i, i)
	s2 := f.NewValue(body, OpAdd, TInt, 0, s, sq)
	i2 := f.NewValue(body, OpAdd, TInt, 0, i, f.ConstInt(body, 1))
	fuel := f.NewValue(body, OpFuel, TInt, 0)
	fuel.Exit = f.NewExit(ExitFuel, 0)
	AddEdge(body, head)
	i.Args = []*Value{one, i2}
	s.Args = []*Value{zero, s2}
	exitWith(f, done, s)

	for _, nv := range []uint64{0, 1, 10, 1000, 100000} {
		r := runNative(t, f, []uint64{nv}, 7, nil)
		want := uint64(0)
		for k := uint64(1); k <= nv; k++ {
			want += k * k
		}
		if got := r.value(0); got != want {
			t.Fatalf("n=%d: got %d, want %d", nv, got, want)
		}
		// the function was consumed by Compile: rebuild for the next run
		f = rebuildSum()
	}
}

// rebuildSum constructs the IR of TestSumLoop again (Compile mutates its
// input).
func rebuildSum() *Func {
	f := NewFunc("sum")
	entry := f.Entry
	head, body, done := f.NewBlock(), f.NewBlock(), f.NewBlock()
	n := loadReg(f, entry, 0)
	zero := f.ConstInt(entry, 0)
	one := f.ConstInt(entry, 1)
	AddEdge(entry, head)
	i := f.NewPhi(head, TInt)
	s := f.NewPhi(head, TInt)
	cond := f.NewValue(head, OpLe, TInt, 0, i, n)
	head.Kind = BlockIf
	head.Control = cond
	AddEdge(head, body)
	AddEdge(head, done)
	sq := f.NewValue(body, OpMul, TInt, 0, i, i)
	s2 := f.NewValue(body, OpAdd, TInt, 0, s, sq)
	i2 := f.NewValue(body, OpAdd, TInt, 0, i, f.ConstInt(body, 1))
	fuel := f.NewValue(body, OpFuel, TInt, 0)
	fuel.Exit = f.NewExit(ExitFuel, 0)
	AddEdge(body, head)
	i.Args = []*Value{one, i2}
	s.Args = []*Value{zero, s2}
	exitWith(f, done, s)
	return f
}

var intSamples = []int64{0, 1, -1, 2, -2, 3, 7, -7, 63, 64, 100, -100, 1 << 31, -(1 << 31), 1<<31 - 1,
	1 << 32, 1<<53 + 1, math.MaxInt64, math.MinInt64, math.MinInt64 + 1, 0x123456789ABCDEF, -0x123456789ABCDEF}

var floatSamples = []float64{0, math.Copysign(0, -1), 1, -1, 0.5, -0.5, 1.5, -1.5, 2.5, 3.7, -3.7, 1e10, -1e10,
	1e300, -1e300, 5e-324, math.Inf(1), math.Inf(-1), math.NaN(), 4503599627370496.5, 9007199254740993}

// TestIntOps checks every integer operation against the reference
// interpreter for all pairs of interesting operands, with the operands
// living in registers, as constants and (via many live values) in spill
// slots.
func TestIntOps(t *testing.T) {
	ops := []Op{OpAdd, OpSub, OpMul, OpAnd, OpOr, OpXor, OpShl, OpShr, OpSar, OpDiv, OpMod, OpEq, OpNe, OpLt, OpLe, OpULt}
	build := func(constRHS int64, useConst bool) *Func {
		f := NewFunc("intops")
		b := f.Entry
		x := loadReg(f, b, 0)
		y := loadReg(f, b, 1)
		rhs := y
		if useConst {
			rhs = f.ConstInt(b, constRHS)
		}
		var outs []*Value
		for _, op := range ops {
			outs = append(outs, f.NewValue(b, op, TInt, 0, x, rhs))
		}
		outs = append(outs, f.NewValue(b, OpNeg, TInt, 0, x), f.NewValue(b, OpNot, TInt, 0, x))
		exitWith(f, b, outs...)
		return f
	}
	check := func(xv, yv int64, useConst bool) {
		if (yv == 0) || yv < 0 || yv > 63 {
			// shifts need 0..63 and division a non-zero divisor: mask
			// the operand for those operations by running them separately
		}
		regs := []uint64{uint64(xv), uint64(yv)}
		ref := interpretOps(build(yv, useConst), regs)
		r := runNative(t, build(yv, useConst), regs, 1<<30, nil)
		for i := range ref {
			if got := r.value(i); got != ref[i] {
				name := "unary"
				if i < len(ops) {
					name = ops[i].String()
				}
				t.Fatalf("%s(%d, %d) const=%v: got %#x, want %#x", name, xv, yv, useConst, got, ref[i])
			}
		}
	}
	for _, xv := range intSamples {
		for _, yv := range []int64{1, 2, 3, 5, 7, 31, 62, 63} {
			check(xv, yv, false)
			check(xv, yv, true)
		}
	}
	// division and modulo with arbitrary non-zero divisors
	divOps := []Op{OpDiv, OpMod, OpAdd, OpSub, OpMul, OpEq, OpLt, OpLe, OpULt}
	for _, xv := range intSamples {
		for _, yv := range intSamples {
			if yv == 0 {
				continue
			}
			for _, useConst := range []bool{false, true} {
				mk := func() *Func {
					f := NewFunc("div")
					b := f.Entry
					x := loadReg(f, b, 0)
					var y *Value = loadReg(f, b, 1)
					if useConst {
						y = f.ConstInt(b, yv)
					}
					var outs []*Value
					for _, op := range divOps {
						outs = append(outs, f.NewValue(b, op, TInt, 0, x, y))
						outs = append(outs, f.NewValue(b, op, TInt, 0, y, x))
					}
					exitWith(f, b, outs...)
					return f
				}
				if xv == 0 {
					continue
				}
				regs := []uint64{uint64(xv), uint64(yv)}
				ref := interpretOps(mk(), regs)
				r := runNative(t, mk(), regs, 1<<30, nil)
				for i := range ref {
					if got := r.value(i); got != ref[i] {
						t.Fatalf("%s #%d (%d, %d) const=%v: got %d, want %d", divOps[i/2], i, xv, yv, useConst, int64(got), int64(ref[i]))
					}
				}
			}
		}
	}
}

// interpretOps runs f in the reference interpreter and returns the
// snapshot values of its exit.
func interpretOps(f *Func, regs []uint64) []uint64 {
	ctx := make([]uint64, CtxHeaderWords+64)
	res := interpret(f, append([]uint64(nil), regs...), ctx, nil)
	out := make([]uint64, len(res.exit.Snap))
	for i, s := range res.exit.Snap {
		if s.Val.IsConst() {
			out[i] = uint64(s.Val.Aux)
		} else {
			out[i] = res.vals[s.Val]
		}
	}
	return out
}

func TestFloatOps(t *testing.T) {
	bin := []Op{OpFAdd, OpFSub, OpFMul, OpFDiv, OpFEq, OpFNe, OpFLt, OpFLe}
	un := []Op{OpFNeg, OpFSqrt, OpFAbs, OpFFloor, OpFCeil}
	mk := func(yc float64, useConst bool) *Func {
		f := NewFunc("fops")
		b := f.Entry
		x := loadRegF(f, b, 0)
		var y *Value = loadRegF(f, b, 1)
		if useConst {
			y = f.ConstFloat(b, yc)
		}
		var outs []*Value
		for _, op := range bin {
			typ := TFloat
			if op.IsCompare() {
				typ = TInt
			}
			outs = append(outs, f.NewValue(b, op, typ, 0, x, y), f.NewValue(b, op, typ, 0, y, x))
		}
		for _, op := range un {
			outs = append(outs, f.NewValue(b, op, TFloat, 0, x))
		}
		outs = append(outs, f.NewValue(b, OpIntToFloat, TFloat, 0, loadReg(f, b, 2)))
		exitWith(f, b, outs...)
		return f
	}
	same := func(a, b uint64) bool {
		fa, fb := math.Float64frombits(a), math.Float64frombits(b)
		return a == b || (math.IsNaN(fa) && math.IsNaN(fb))
	}
	for _, xv := range floatSamples {
		for _, yv := range floatSamples {
			for _, useConst := range []bool{false, true} {
				regs := []uint64{math.Float64bits(xv), math.Float64bits(yv), uint64(int64(xv))}
				if math.IsNaN(xv) || math.IsInf(xv, 0) || math.Abs(xv) > 1e18 {
					regs[2] = 12345
				}
				ref := interpretOps(mk(yv, useConst), regs)
				r := runNative(t, mk(yv, useConst), regs, 1<<30, nil)
				for i := range ref {
					if got := r.value(i); !same(got, ref[i]) {
						t.Fatalf("output %d for (%v, %v) const=%v: got %v (%#x), want %v (%#x)", i, xv, yv, useConst,
							math.Float64frombits(got), got, math.Float64frombits(ref[i]), ref[i])
					}
				}
			}
		}
	}
}

func TestFloatToInt(t *testing.T) {
	for _, xv := range []float64{0, 1, -1, 1.9, -1.9, 123456789.75, -9.223372036854775e18, 9.2e18, 4503599627370497} {
		f := NewFunc("f2i")
		b := f.Entry
		exitWith(f, b, f.NewValue(b, OpFloatToInt, TInt, 0, loadRegF(f, b, 0)))
		r := runNative(t, f, []uint64{math.Float64bits(xv)}, 1<<30, nil)
		if got := int64(r.value(0)); got != int64(xv) {
			t.Fatalf("FloatToInt(%v) = %d, want %d", xv, got, int64(xv))
		}
	}
}

// TestBranches checks fused and materialized comparisons as branch
// conditions and guards for every relation.
func TestBranches(t *testing.T) {
	intRel := []Op{OpEq, OpNe, OpLt, OpLe, OpULt}
	fltRel := []Op{OpFEq, OpFNe, OpFLt, OpFLe}
	mk := func(op Op, float bool, constRHS bool, cv uint64) *Func {
		f := NewFunc("branch")
		b := f.Entry
		yes, no := f.NewBlock(), f.NewBlock()
		var x, y *Value
		if float {
			x, y = loadRegF(f, b, 0), loadRegF(f, b, 1)
			if constRHS {
				y = f.ConstFloat(b, math.Float64frombits(cv))
			}
		} else {
			x, y = loadReg(f, b, 0), loadReg(f, b, 1)
			if constRHS {
				y = f.ConstInt(b, int64(cv))
			}
		}
		// a guard that never fails for values where the relation holds is
		// tested separately; here: branch on the relation
		c := f.NewValue(b, op, TInt, 0, x, y)
		b.Kind = BlockIf
		b.Control = c
		AddEdge(b, yes)
		AddEdge(b, no)
		exitWith(f, yes, f.ConstInt(yes, 1))
		exitWith(f, no, f.ConstInt(no, 0))
		return f
	}
	mkGuard := func(op Op, float bool) *Func {
		f := NewFunc("guard")
		b := f.Entry
		var x, y *Value
		if float {
			x, y = loadRegF(f, b, 0), loadRegF(f, b, 1)
		} else {
			x, y = loadReg(f, b, 0), loadReg(f, b, 1)
		}
		c := f.NewValue(b, op, TInt, 0, x, y)
		g := f.NewValue(b, OpGuard, TInt, 0, c)
		g.Exit = f.NewExit(ExitDeopt, 0)
		g.Exit.Snap = []SnapEntry{{Slot: 0, Val: f.ConstInt(b, 0)}}
		// also use the comparison result as a value in a second variant
		exitWith(f, b, f.ConstInt(b, 1))
		return f
	}
	run := func(op Op, float bool, xv, yv uint64) {
		regs := []uint64{xv, yv}
		for _, constRHS := range []bool{false, true} {
			want := interpretOps(mk(op, float, constRHS, yv), regs)[0]
			if got := runNative(t, mk(op, float, constRHS, yv), regs, 1<<30, nil).value(0); got != want {
				t.Fatalf("%s(%#x, %#x) const=%v branch: got %d, want %d", op, xv, yv, constRHS, got, want)
			}
		}
		want := interpretOps(mkGuard(op, float), regs)[0]
		if got := runNative(t, mkGuard(op, float), regs, 1<<30, nil).value(0); got != want {
			t.Fatalf("%s(%#x, %#x) guard: got %d, want %d", op, xv, yv, got, want)
		}
	}
	for _, op := range intRel {
		for _, xv := range intSamples {
			for _, yv := range intSamples {
				run(op, false, uint64(xv), uint64(yv))
			}
		}
	}
	for _, op := range fltRel {
		for _, xv := range floatSamples {
			for _, yv := range floatSamples {
				run(op, true, math.Float64bits(xv), math.Float64bits(yv))
			}
		}
	}
}

// TestSpillPressure keeps more values alive than there are registers.
func TestSpillPressure(t *testing.T) {
	const n = 40
	mk := func() *Func {
		f := NewFunc("spill")
		b := f.Entry
		var ints, floats []*Value
		for i := 0; i < n; i++ {
			v := loadReg(f, b, i)
			ints = append(ints, f.NewValue(b, OpAdd, TInt, 0, v, f.ConstInt(b, int64(i*3+1))))
			fv := loadRegF(f, b, n+i)
			floats = append(floats, f.NewValue(b, OpFMul, TFloat, 0, fv, f.ConstFloat(b, float64(i)+0.5)))
		}
		// combine in reverse order so that everything stays live
		accI := f.ConstInt(b, 0)
		accF := f.ConstFloat(b, 0)
		for i := n - 1; i >= 0; i-- {
			accI = f.NewValue(b, OpXor, TInt, 0, f.NewValue(b, OpMul, TInt, 0, accI, f.ConstInt(b, 31)), ints[i])
			accF = f.NewValue(b, OpFAdd, TFloat, 0, f.NewValue(b, OpFMul, TFloat, 0, accF, f.ConstFloat(b, 0.75)), floats[i])
		}
		outs := []*Value{accI, accF}
		outs = append(outs, ints...)
		outs = append(outs, floats...)
		exitWith(f, b, outs...)
		return f
	}
	rng := rand.New(rand.NewSource(1))
	regs := make([]uint64, 2*n)
	for i := 0; i < n; i++ {
		regs[i] = rng.Uint64()
		regs[n+i] = math.Float64bits(rng.NormFloat64() * 1000)
	}
	ref := interpretOps(mk(), regs)
	r := runNative(t, mk(), regs, 1<<30, nil)
	if r.code.NumSpills == 0 {
		t.Fatal("expected spilled values")
	}
	for i := range ref {
		if got := r.value(i); got != ref[i] {
			t.Fatalf("output %d: got %#x, want %#x", i, got, ref[i])
		}
	}
}

// TestPhiCycles rotates several loop variables every iteration, which
// requires cyclic parallel moves, with and without register pressure.
func TestPhiCycles(t *testing.T) {
	for _, nvars := range []int{2, 3, 5, 12, 20} {
		for _, float := range []bool{false, true} {
			mk := func() *Func {
				f := NewFunc("rotate")
				entry := f.Entry
				head, body, done := f.NewBlock(), f.NewBlock(), f.NewBlock()
				typ := TInt
				if float {
					typ = TFloat
				}
				var init []*Value
				for i := 0; i < nvars; i++ {
					if float {
						init = append(init, loadRegF(f, entry, i))
					} else {
						init = append(init, loadReg(f, entry, i))
					}
				}
				n := loadReg(f, entry, 30)
				AddEdge(entry, head)
				cnt := f.NewPhi(head, TInt)
				var phis []*Value
				for i := 0; i < nvars; i++ {
					phis = append(phis, f.NewPhi(head, typ))
				}
				head.Kind = BlockIf
				head.Control = f.NewValue(head, OpLt, TInt, 0, cnt, n)
				AddEdge(head, body)
				AddEdge(head, done)
				cnt2 := f.NewValue(body, OpAdd, TInt, 0, cnt, f.ConstInt(body, 1))
				AddEdge(body, head)
				cnt.Args = []*Value{f.ConstInt(entry, 0), cnt2}
				for i := 0; i < nvars; i++ {
					// rotate: var i takes the value of var i+1; the last
					// one takes a modified first value
					next := phis[(i+1)%nvars]
					if i == nvars-1 {
						if float {
							next = f.NewValue(body, OpFAdd, TFloat, 0, phis[0], f.ConstFloat(body, 1))
						} else {
							next = f.NewValue(body, OpAdd, TInt, 0, phis[0], f.ConstInt(body, 1))
						}
					}
					phis[i].Args = []*Value{init[i], next}
				}
				exitWith(f, done, phis...)
				return f
			}
			regs := make([]uint64, 31)
			for i := 0; i < nvars; i++ {
				if float {
					regs[i] = math.Float64bits(float64(i) * 1.25)
				} else {
					regs[i] = uint64(i * 1000)
				}
			}
			for _, iters := range []uint64{0, 1, 2, 7, 1001} {
				regs[30] = iters
				ref := interpretOps(mk(), regs)
				r := runNative(t, mk(), regs, 1<<30, nil)
				for i := range ref {
					if got := r.value(i); got != ref[i] {
						t.Fatalf("nvars=%d float=%v iters=%d var %d: got %#x, want %#x", nvars, float, iters, i, got, ref[i])
					}
				}
			}
		}
	}
}

// TestCalloutPreservesState checks that register and spill contents
// survive callout and fuel exits, and that Go code can pass a result back
// through the context frame.
func TestCalloutPreservesState(t *testing.T) {
	const n = 30
	mk := func() *Func {
		f := NewFunc("callout")
		b := f.Entry
		var vals []*Value
		for i := 0; i < n; i++ {
			vals = append(vals, f.NewValue(b, OpMul, TInt, 0, loadReg(f, b, i), f.ConstInt(b, 3)))
			vals = append(vals, f.NewValue(b, OpFAdd, TFloat, 0, loadRegF(f, b, n+i), f.ConstFloat(b, 0.5)))
		}
		co := f.NewValue(b, OpCallout, TInt, 0)
		co.Exit = f.NewExit(ExitCallout, 7)
		for i, v := range vals {
			co.Exit.Snap = append(co.Exit.Snap, SnapEntry{Slot: i, Val: v})
		}
		res := f.NewValue(b, OpLoad64, TInt, CtxResult, f.Ctx())
		fu := f.NewValue(b, OpFuel, TInt, 0)
		fu.Exit = f.NewExit(ExitFuel, 0)
		outs := append([]*Value{res}, vals...)
		exitWith(f, b, outs...)
		return f
	}
	regs := make([]uint64, 2*n)
	for i := 0; i < n; i++ {
		regs[i] = uint64(i + 1)
		regs[n+i] = math.Float64bits(float64(i))
	}
	calls := 0
	r := runNative(t, mk(), regs, 1, func(info ExitInfo, frame []uint64) {
		calls++
		if info.PC != 7 {
			t.Fatalf("callout pc = %d", info.PC)
		}
		for i, e := range info.Entries {
			got := locValue(frame, e)
			var want uint64
			if i%2 == 0 {
				want = uint64(i/2+1) * 3
			} else {
				want = math.Float64bits(float64(i/2) + 0.5)
			}
			if got != want {
				t.Fatalf("callout entry %d: got %#x, want %#x", i, got, want)
			}
		}
		frame[CtxResult/8] = 4242
	})
	if calls != 1 {
		t.Fatalf("callout hook ran %d times", calls)
	}
	if got := r.value(0); got != 4242 {
		t.Fatalf("callout result = %d", got)
	}
	for i := 0; i < 2*n; i++ {
		var want uint64
		if i%2 == 0 {
			want = uint64(i/2+1) * 3
		} else {
			want = math.Float64bits(float64(i/2) + 0.5)
		}
		if got := r.value(i + 1); got != want {
			t.Fatalf("value %d after resume: got %#x, want %#x", i, got, want)
		}
	}
}

// TestStoreAndLoad exercises memory access with computed addresses.
func TestStoreAndLoad(t *testing.T) {
	// regs[k] = regs[k] * 2 for k in 8..15 using computed addresses, and
	// float slots 16..23 get the square root of their content
	f := NewFunc("mem")
	entry := f.Entry
	head, body, done := f.NewBlock(), f.NewBlock(), f.NewBlock()
	AddEdge(entry, head)
	i := f.NewPhi(head, TInt)
	head.Kind = BlockIf
	head.Control = f.NewValue(head, OpLt, TInt, 0, i, f.ConstInt(head, 8))
	AddEdge(head, body)
	AddEdge(head, done)
	off := f.NewValue(body, OpShl, TInt, 0, i, f.ConstInt(body, 3))
	addr := f.NewValue(body, OpAdd, TInt, 0, f.RegBase(), off)
	v := f.NewValue(body, OpLoad64, TInt, 64, addr)
	f.NewValue(body, OpStore64, TInt, 64, addr, f.NewValue(body, OpAdd, TInt, 0, v, v))
	fv := f.NewValue(body, OpLoadF64, TFloat, 128, addr)
	f.NewValue(body, OpStoreF64, TInt, 128, addr, f.NewValue(body, OpFSqrt, TFloat, 0, fv))
	b8 := f.NewValue(body, OpLoad8, TInt, 0, addr)
	w32 := f.NewValue(body, OpLoad32, TInt, 0, addr)
	f.NewValue(body, OpStore64, TInt, 192, addr, f.NewValue(body, OpAdd, TInt, 0, b8, w32))
	i2 := f.NewValue(body, OpAdd, TInt, 0, i, f.ConstInt(body, 1))
	AddEdge(body, head)
	i.Args = []*Value{f.ConstInt(entry, 0), i2}
	exitWith(f, done, i)

	regs := make([]uint64, 32)
	for k := 0; k < 8; k++ {
		regs[k] = 0x1122334455667700 + uint64(k)
		regs[8+k] = uint64(k * 7)
		regs[16+k] = math.Float64bits(float64(k * k))
	}
	r := runNative(t, f, regs, 1<<30, nil)
	if r.value(0) != 8 {
		t.Fatalf("loop count = %d", r.value(0))
	}
	for k := 0; k < 8; k++ {
		if regs[8+k] != uint64(k*14) {
			t.Fatalf("slot %d = %d", 8+k, regs[8+k])
		}
		if got := math.Float64frombits(regs[16+k]); got != float64(k) {
			t.Fatalf("float slot %d = %v", 16+k, got)
		}
		if want := uint64(k) + 0x55667700 + uint64(k); regs[24+k] != want {
			t.Fatalf("slot %d = %#x, want %#x", 24+k, regs[24+k], want)
		}
	}
}

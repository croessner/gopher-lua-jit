package jit

import (
	"math"
	"unsafe"
)

// interpResult is the outcome of interpreting an IR function.
type interpResult struct {
	exit *Exit
	vals map[*Value]uint64
}

// interpret is a reference interpreter for the IR used by differential
// tests. regs is the memory the RegBase value points to and ctx is the
// context frame. Callouts invoke the callout hook; fuel exits are ignored.
func interpret(f *Func, regs []uint64, ctx []uint64, callout func(x *Exit, vals map[*Value]uint64)) interpResult {
	vals := make(map[*Value]uint64)
	fl := func(v *Value) float64 { return math.Float64frombits(vals[v]) }
	fb := func(x float64) uint64 { return math.Float64bits(x) }
	b2u := func(b bool) uint64 {
		if b {
			return 1
		}
		return 0
	}
	get := func(v *Value) uint64 {
		switch v.Op {
		case OpConst:
			return uint64(v.Aux)
		case OpCtx:
			return uint64(uintptr(unsafe.Pointer(&ctx[0])))
		case OpRegBase:
			return uint64(uintptr(unsafe.Pointer(&regs[0])))
		}
		return vals[v]
	}
	_ = fl
	// word resolves an address inside regs or ctx to the 64-bit word that
	// contains it and the byte offset within that word.
	word := func(addr uint64) (*uint64, uint) {
		for _, buf := range [][]uint64{regs, ctx} {
			base := uint64(uintptr(unsafe.Pointer(&buf[0])))
			if addr >= base && addr < base+uint64(8*len(buf)) {
				return &buf[(addr-base)/8], uint((addr - base) % 8)
			}
		}
		panic("interp: address outside of the test buffers")
	}
	var prev *Block
	b := f.Entry
	for steps := 0; steps < 1<<26; steps++ {
		// phis read their inputs simultaneously
		var phiVals []uint64
		var phis []*Value
		for _, v := range b.Values {
			if v.Op != OpPhi {
				break
			}
			phis = append(phis, v)
			phiVals = append(phiVals, get(v.Args[predIndex(b, prev)]))
		}
		for i, v := range phis {
			vals[v] = phiVals[i]
		}
		for _, v := range b.Values {
			a := func(i int) uint64 { return get(v.Args[i]) }
			af := func(i int) float64 { return math.Float64frombits(get(v.Args[i])) }
			switch v.Op {
			case OpPhi, OpConst, OpCtx, OpRegBase:
			case OpAdd:
				vals[v] = a(0) + a(1)
			case OpSub:
				vals[v] = a(0) - a(1)
			case OpMul:
				vals[v] = a(0) * a(1)
			case OpAnd:
				vals[v] = a(0) & a(1)
			case OpOr:
				vals[v] = a(0) | a(1)
			case OpXor:
				vals[v] = a(0) ^ a(1)
			case OpShl:
				vals[v] = a(0) << (a(1) & 63)
			case OpShr:
				vals[v] = a(0) >> (a(1) & 63)
			case OpSar:
				vals[v] = uint64(int64(a(0)) >> (a(1) & 63))
			case OpDiv:
				vals[v] = uint64(floorDiv(int64(a(0)), int64(a(1))))
			case OpMod:
				vals[v] = uint64(floorMod(int64(a(0)), int64(a(1))))
			case OpNeg:
				vals[v] = -a(0)
			case OpNot:
				vals[v] = ^a(0)
			case OpFAdd:
				vals[v] = fb(af(0) + af(1))
			case OpFSub:
				vals[v] = fb(af(0) - af(1))
			case OpFMul:
				vals[v] = fb(af(0) * af(1))
			case OpFDiv:
				vals[v] = fb(af(0) / af(1))
			case OpFNeg:
				vals[v] = fb(-af(0))
			case OpFSqrt:
				vals[v] = fb(math.Sqrt(af(0)))
			case OpFAbs:
				vals[v] = fb(math.Abs(af(0)))
			case OpFFloor:
				vals[v] = fb(math.Floor(af(0)))
			case OpFCeil:
				vals[v] = fb(math.Ceil(af(0)))
			case OpIntToFloat:
				vals[v] = fb(float64(int64(a(0))))
			case OpFloatToInt:
				vals[v] = uint64(int64(af(0)))
			case OpEq:
				vals[v] = b2u(a(0) == a(1))
			case OpNe:
				vals[v] = b2u(a(0) != a(1))
			case OpLt:
				vals[v] = b2u(int64(a(0)) < int64(a(1)))
			case OpLe:
				vals[v] = b2u(int64(a(0)) <= int64(a(1)))
			case OpULt:
				vals[v] = b2u(a(0) < a(1))
			case OpFEq:
				vals[v] = b2u(af(0) == af(1))
			case OpFNe:
				vals[v] = b2u(af(0) != af(1))
			case OpFLt:
				vals[v] = b2u(af(0) < af(1))
			case OpFLe:
				vals[v] = b2u(af(0) <= af(1))
			case OpLoad64, OpLoadF64:
				p, _ := word(a(0) + uint64(v.Aux))
				vals[v] = *p
			case OpLoad32:
				p, off := word(a(0) + uint64(v.Aux))
				vals[v] = (*p >> (8 * off)) & 0xFFFFFFFF
			case OpLoad8:
				p, off := word(a(0) + uint64(v.Aux))
				vals[v] = (*p >> (8 * off)) & 0xFF
			case OpStore64, OpStoreF64:
				p, _ := word(a(0) + uint64(v.Aux))
				*p = a(1)
			case OpGuard:
				if a(0) == 0 {
					return interpResult{exit: v.Exit, vals: vals}
				}
			case OpCallout:
				if callout != nil {
					callout(v.Exit, vals)
				}
			case OpFuel:
			default:
				panic("interp: unsupported op " + v.Op.String())
			}
		}
		prev = b
		switch b.Kind {
		case BlockJump:
			b = b.Succs[0]
		case BlockIf:
			if get(b.Control) != 0 {
				b = b.Succs[0]
			} else {
				b = b.Succs[1]
			}
		case BlockExit:
			return interpResult{exit: b.Exit, vals: vals}
		}
	}
	panic("interp: step limit exceeded")
}

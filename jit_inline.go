package lua

import (
	"unsafe"

	"github.com/yuin/gopher-lua/internal/jit"
)

// This file contains the inlining of Lua function calls: inside a
// compiled loop the code of a small callee is translated in place of the
// call. No frame is pushed and arguments and results stay in machine
// registers. The callee's registers are the slots behind the function
// value, exactly where its frame would be, so that an exit inside the
// callee only has to create the frame (see jitEnterInlined) for the
// interpreter to continue there.
//
// Only functions that are a straight line of simple instructions are
// inlined; a callee with branches, loops, varargs or instructions that
// need the interpreter is called through the interpreter as before.

// relocateInst adds delta to the register operands of an instruction
// that inlinableProto accepts. It reports false if a register does not
// fit into its operand.
func relocateInst(inst uint32, delta int) (uint32, bool) {
	ok := true
	reg := func(r int) int {
		r += delta
		if r > opMaxArgsA {
			ok = false
		}
		return r
	}
	rk := func(v int) int {
		if v&opBitRk != 0 {
			return v
		}
		return reg(v)
	}
	a, b, c := opGetArgA(inst), opGetArgB(inst), opGetArgC(inst)
	switch opGetOpCode(inst) {
	case OP_LOADK, OP_LOADBOOL, OP_GETUPVAL, OP_GETGLOBAL, OP_CALL, OP_TAILCALL, OP_RETURN:
		opSetArgA(&inst, reg(a))
	case OP_MOVE, OP_MOVEN, OP_LOADNIL, OP_UNM, OP_NOT, OP_LEN, OP_BNOT:
		opSetArgA(&inst, reg(a))
		opSetArgB(&inst, reg(b))
	case OP_GETTABLE, OP_GETTABLEKS:
		opSetArgA(&inst, reg(a))
		opSetArgB(&inst, reg(b))
		opSetArgC(&inst, rk(c))
	case OP_SETTABLE, OP_SETTABLEKS,
		OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_POW, OP_IDIV, OP_BAND, OP_BOR, OP_BXOR, OP_SHL, OP_SHR:
		opSetArgA(&inst, reg(a))
		opSetArgB(&inst, rk(b))
		opSetArgC(&inst, rk(c))
	default:
		ok = false
	}
	return inst, ok
}

// inlinableProto reports whether a function can be translated in place of
// a call and returns the position of the instruction that ends it: a
// return of a fixed number of values or a tail call.
func inlinableProto(proto *FunctionProto) (ret int, ok bool) {
	if proto.IsVarArg != 0 {
		return 0, false
	}
	for pc, inst := range proto.Code {
		if pc >= jitMaxInlineInsts {
			return 0, false
		}
		b, c := opGetArgB(inst), opGetArgC(inst)
		switch opGetOpCode(inst) {
		case OP_RETURN, OP_TAILCALL:
			return pc, b != 0
		case OP_LOADBOOL:
			if c != 0 {
				return 0, false // skips the next instruction
			}
		case OP_CALL:
			if b == 0 || c == 0 {
				return 0, false
			}
		case OP_MOVE, OP_MOVEN, OP_LOADK, OP_LOADNIL, OP_GETUPVAL, OP_GETGLOBAL,
			OP_GETTABLE, OP_GETTABLEKS, OP_SETTABLE, OP_SETTABLEKS,
			OP_ADD, OP_SUB, OP_MUL, OP_DIV, OP_MOD, OP_POW, OP_IDIV, OP_BAND, OP_BOR, OP_BXOR, OP_SHL, OP_SHR,
			OP_UNM, OP_NOT, OP_LEN, OP_BNOT:
		default:
			return 0, false
		}
	}
	return 0, false
}

// calleeAt returns the Lua function in register a if the code can treat
// it as a constant: it is one already (a global or upvalue function) or
// the register holds it boxed. home is the slot whose identity has to be
// guarded in the second case, else -1.
func (fe *jitFrontend) calleeAt(a int) (fn *LFunction, home int) {
	home = -1
	if s := &fe.st[a]; s.kind == skConst {
		fn, _ = fe.consts[s.src].(*LFunction)
	} else if h, ok := fe.homeSlot(a); ok && h < len(fe.frame) {
		fn, _ = fe.frame[h].(*LFunction)
		home = h
	}
	if fn == nil || fn.IsG || fn.Proto == nil {
		return nil, -1
	}
	return fn, home
}

// guardCallee makes the code depend on the identity of the function in
// the slot home. A failure counts against inlining at the call site.
func (fe *jitFrontend) guardCallee(fn *LFunction, home int, site feedbackKey) {
	same := fe.op(jit.OpEq, jit.TInt, fe.slotData(home), fe.constInt(int64(uintptr(unsafe.Pointer(fn)))))
	isFn := fe.op(jit.OpEq, jit.TInt, fe.slotItab(home), fe.constInt(int64(itabFunc)))
	x := fe.newExit(jit.ExitDeopt, fe.pc, exitMeta{kind: emDeopt, fbSlot: site.slot, fbWhat: fbInline})
	x.Snap = fe.snapshot(fe.cur, fe.st, fe.pc, nil)
	fe.f.NewValue(fe.cur, jit.OpGuard, jit.TInt, 0, fe.op(jit.OpAnd, jit.TInt, same, isFn)).Exit = x
}

// inlineCall translates the call R(a)(R(a+1), ..., R(a+b-1)) with c-1
// results by translating the callee in place. done is false if the call
// is not inlined (nothing was emitted that changes the state); ended is
// true if the current block ended inside the callee or the translation
// has to start over.
func (fe *jitFrontend) inlineCall(a, b, c int) (done, ended bool) {
	return fe.inlineCallAs(a, b, c, false)
}

// inlineCallAs is inlineCall for an ordinary call or, with tail set, for
// the tail call that ends an inlined callee. c is the number of results
// wanted plus one; zero asks for all results, whose end is then recorded
// like for any other open result list.
func (fe *jitFrontend) inlineCallAs(a, b, c int, tail bool) (done, ended bool) {
	site := feedbackKey{fe.fbpc(), int16(a), fbInline}
	if b == 0 || fe.jp.feedback[site] >= jitFieldMisses {
		return false, false
	}
	// nothing is emitted before the call is known to be inlined
	fn, home := fe.calleeAt(a)
	if fn == nil {
		return false, false
	}
	proto := fn.Proto
	ret, ok := inlinableProto(proto)
	if !ok || proto.Version != fe.proto.Version {
		return false, false
	}
	depth := 0
	for i := fe.inl; i != 0; i = fe.inlined[i-1].parent {
		depth++
		if fe.inlined[i-1].callee.Proto == proto {
			return false, false
		}
	}
	if depth >= jitMaxInlineDepth || proto == fe.jp.proto {
		return false, false
	}
	base := a + 1
	need := base + proto.analysis().nslots
	for pc := 0; pc <= ret; pc++ {
		if _, ok := relocateInst(proto.Code[pc], base); !ok {
			return false, false
		}
	}
	if need > jitMaxSlots || need > cap(fe.frame) {
		return false, false
	}
	if need > fe.nslots {
		// the unit needs more slots: translate again with a larger window
		fe.nslots = need
		fe.frame = fe.frame[:need]
		fe.restart = true
		return true, true
	}
	if home >= 0 {
		fe.guardCallee(fn, home, site)
	}

	// the frame of the callee: missing arguments are nil, everything
	// behind the parameters is unset
	nargs, nret, np := b-1, c-1, int(proto.NumParameters)
	for i := nargs; i < np; i++ {
		fe.st[base+i] = slotState{kind: skNil}
	}
	for s := base + intMax(nargs, np); s < need; s++ {
		fe.st[s] = slotState{}
	}
	call := inlineCall{callee: fn, callPC: fe.pc, ra: a, nargs: nargs, nret: nret, tail: tail, parent: fe.inl, site: site}
	if fe.inl != 0 {
		call.live = fe.inlined[fe.inl-1].live
	} else {
		call.live = fe.info.liveIn[fe.pc+1]
		for r := a; r < a+nret; r++ {
			call.live.del(r)
		}
	}
	for s := base; s < need; s++ {
		call.live.add(s)
	}
	fe.inlined = append(fe.inlined, call)

	// translate the callee in its own scope
	saved := *fe
	fe.inl = len(fe.inlined)
	fe.scope, fe.proto, fe.slotBase = fn, proto, base
	fe.fbBase = (saved.fbBase*31+int32(saved.pc)+1)<<8&0x3fffff00 | 1<<30
	fe.env = functionEnv(fn)
	fe.pendingTop, fe.openTop = -1, -1
	restore := func() {
		fe.inl, fe.scope, fe.proto, fe.slotBase = saved.inl, saved.scope, saved.proto, saved.slotBase
		fe.fbBase, fe.env, fe.pc = saved.fbBase, saved.env, saved.pc
		fe.pendingTop, fe.openTop = -1, -1
	}
	for pc := 0; pc < ret; pc++ {
		fe.pc = pc
		if _, ended := fe.inst(pc); ended || fe.restart {
			restore()
			return true, true
		}
	}
	// the callee ends with a return of n values from register from, or
	// with a tail call that is translated in place as well
	term := fe.code(ret)
	from, n := opGetArgA(term), opGetArgB(term)-1
	if opGetOpCode(term) == OP_TAILCALL {
		fe.pc = ret
		done, ended := fe.inlineCallAs(from, opGetArgB(term), c, true)
		if !done {
			// the interpreter takes over at the tail call
			fe.unsupported()
			ended = true
		}
		if ended || fe.restart {
			restore()
			return true, true
		}
		n = nret
		if c == 0 {
			n = fe.openTop - from
		}
	}
	// the results move down into the registers of the call; values the
	// callee did not return are nil
	if c == 0 {
		nret = n
	}
	for i := 0; i < nret; i++ {
		if i < n {
			fe.move(a+i, from+i)
		} else {
			fe.st[a+i] = slotState{kind: skNil}
		}
	}
	restore()
	if c == 0 {
		fe.openTop = a + nret
	}
	for s := a + nret; s < need; s++ {
		fe.st[s] = slotState{}
	}
	return true, false
}

// jitEnterInlined creates the frames of the inlined calls an exit lies
// in, outermost first, and makes the innermost one the current frame at
// position pc. cf is the frame of the compiled function and base its
// register base; the registers of the callees were written back already.
func (ls *LState) jitEnterInlined(u *jitUnit, inl int, cf *callFrame, base, pc int) {
	var chain [jitMaxInlineDepth + 1]int
	n := 0
	for i := inl; i != 0; i = u.inlined[i-1].parent {
		chain[n] = i
		n++
	}
	frame := cf
	// a tail call returns for the function it replaces: retBase and nret
	// carry that function's return information to the frame that stays
	retBase, nret := 0, 0
	for k := n - 1; k >= 0; k-- {
		call := &u.inlined[chain[k]-1]
		ra := base + call.ra
		rb, nr, tailCall := ra, call.nret, 0
		if call.tail {
			rb, nr, tailCall = retBase, nret, 1
		} else {
			frame.Pc = call.callPC + 1
		}
		if k > 0 && u.inlined[chain[k-1]-1].tail {
			retBase, nret = rb, nr
			continue
		}
		if ls.stack.IsFull() {
			ls.RaiseError("stack overflow")
		}
		ls.stack.Push(callFrame{
			Fn: call.callee, Base: ra, LocalBase: ra + 1, ReturnBase: rb,
			NArgs: call.nargs, NRet: nr, Parent: frame, TailCall: tailCall,
		})
		frame = ls.stack.Last()
	}
	frame.Pc = pc
	ls.currentFrame = frame
	if top := frame.LocalBase + int(frame.Fn.Proto.NumUsedRegisters); ls.reg.top < top {
		ls.reg.SetTop(top)
	}
}

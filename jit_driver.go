package lua

import (
	"fmt"
	"math"
	"os"
	"time"
	"unsafe"

	"github.com/yuin/gopher-lua/internal/jit"
	"github.com/yuin/gopher-lua/internal/jit/codecache"
)

// This file contains the runtime side of the JIT: hot loop detection in
// the interpreter, entering native code, and servicing its exits.

// selectMainLoop returns the interpreter loop for a thread configuration.
func selectMainLoop(jitOn bool, withContext bool) func(*LState, *callFrame) {
	switch {
	case jitOn && withContext:
		return mainLoopJITWithContext
	case jitOn:
		return mainLoopJIT
	case withContext:
		return mainLoopWithContext
	}
	return mainLoop
}

// mainLoopJIT is mainLoop with instrumented loop back-edges.
func mainLoopJIT(L *LState, baseframe *callFrame) {
	var inst uint32
	var cf *callFrame

	if L.stack.IsEmpty() {
		return
	}

	L.currentFrame = L.stack.Last()
	if L.currentFrame.Fn.IsG {
		callGFunction(L, false)
		return
	}

	table := jitJumpTable()
	for {
		cf = L.currentFrame
		inst = cf.Fn.Proto.Code[cf.Pc]
		cf.Pc++
		if table[int(inst>>26)](L, inst, baseframe) == 1 {
			return
		}
	}
}

// mainLoopJITWithContext is mainLoopWithContext with instrumented loop
// back-edges.
func mainLoopJITWithContext(L *LState, baseframe *callFrame) {
	var inst uint32
	var cf *callFrame

	if L.stack.IsEmpty() {
		return
	}

	L.currentFrame = L.stack.Last()
	if L.currentFrame.Fn.IsG {
		callGFunction(L, false)
		return
	}

	table := jitJumpTable()
	for {
		cf = L.currentFrame
		inst = cf.Fn.Proto.Code[cf.Pc]
		cf.Pc++
		select {
		case <-L.ctx.Done():
			L.RaiseError(L.ctx.Err().Error())
			return
		default:
			if table[int(inst>>26)](L, inst, baseframe) == 1 {
				return
			}
		}
	}
}

// opForLoopJIT is OP_FORLOOP with hot loop detection.
func opForLoopJIT(L *LState, inst uint32, baseframe *callFrame) int {
	cf := L.currentFrame
	pc := cf.Pc
	jumpTable[OP_FORLOOP](L, inst, baseframe)
	if cf.Pc < pc {
		return jitBackEdge(L, cf, baseframe)
	}
	return 0
}

// opJmpJIT is OP_JMP with hot loop detection on backward jumps.
func opJmpJIT(L *LState, inst uint32, baseframe *callFrame) int {
	cf := L.currentFrame
	sbx := int(inst&0x3ffff) - opMaxArgSbx
	cf.Pc += sbx
	if sbx < 0 {
		return jitBackEdge(L, cf, baseframe)
	}
	return 0
}

// jitBackEdge is called when the interpreter arrives at a loop header
// through a back-edge. It counts the iteration, compiles the loop once it
// is hot and enters native code if the loop is compiled.
func jitBackEdge(L *LState, cf *callFrame, baseframe *callFrame) int {
	js := L.G.jit
	if js == nil {
		return 0
	}
	fn := cf.Fn
	jp := fn.jitp
	if jp == nil {
		jp = js.protoFor(fn.Proto)
		fn.jitp = jp
	}
	lp := jp.loops[cf.Pc]
	if lp == nil {
		lp = &jitLoop{pc: cf.Pc}
		jp.loops[cf.Pc] = lp
	}
	if u := lp.unit; u != nil {
		return L.jitRun(cf, u, baseframe)
	}
	if lp.blacklisted {
		return 0
	}
	lp.count++
	if lp.count < js.threshold {
		return 0
	}
	lp.count = 0
	u := js.compile(L, cf, jp, lp)
	if u == nil {
		return 0
	}
	return L.jitRun(cf, u, baseframe)
}

// jitDumpIR makes the JIT log the IR of every compiled unit. It is
// enabled with the environment variable GOPHERLUA_JIT_DUMP=1.
var jitDumpIR = os.Getenv("GOPHERLUA_JIT_DUMP") == "1"

// blacklist permanently leaves a loop to the interpreter.
func (js *jitState) blacklist(lp *jitLoop, reason string) {
	if !lp.blacklisted {
		lp.blacklisted = true
		js.stats.Blacklisted++
		js.logf("blacklist loop at pc %d: %s", lp.pc, reason)
	}
}

// compile translates the loop lp of the running function to native code.
// It returns nil if the loop cannot be compiled.
func (js *jitState) compile(L *LState, cf *callFrame, jp *jitProto, lp *jitLoop) (u *jitUnit) {
	if js.stopped {
		return nil
	}
	if lp.compiles >= jitMaxCompiles {
		js.blacklist(lp, "too many recompilations")
		return nil
	}
	lp.compiles++
	start := time.Now()
	defer func() {
		js.stats.CompileTime += time.Since(start)
		if r := recover(); r != nil {
			// a compiler bug must never take the host program down
			js.stats.CompileFailed++
			js.blacklist(lp, fmt.Sprintf("internal compiler error: %v", r))
			u = nil
		}
	}()
	base := cf.LocalBase
	nslots := jp.proto.analysis().nslots
	if base+nslots > len(L.reg.array) {
		return nil
	}
	f, fe, err := compileLoopIR(L, jp, L.reg.array[base:base+nslots], lp.pc)
	if err != nil {
		js.stats.CompileFailed++
		js.blacklist(lp, err.Error())
		return nil
	}
	if jitDumpIR && js.log != nil {
		js.logf("IR before optimization:\n%s", f.String())
	}
	if fe.nativeOps == 0 {
		js.stats.CompileFailed++
		js.blacklist(lp, "nothing to compile natively")
		return nil
	}
	code, err := jit.Compile(f, jit.NewHostAsm())
	if err != nil {
		js.stats.CompileFailed++
		js.blacklist(lp, err.Error())
		return nil
	}
	if js.codeBytes+len(code.Bytes) > js.maxCode {
		js.flushAll("limit reached")
		if js.stopped {
			return nil
		}
	}
	block, err := codecache.Alloc(code.Bytes)
	if err != nil {
		// executable memory is unavailable (for example under a hardened
		// runtime without the JIT entitlement): fall back for good
		js.stopped = true
		js.logf("cannot map executable memory: %v", err)
		return nil
	}
	u = &jitUnit{
		block: block, addr: block.Addr(), code: code, loop: lp, jp: jp,
		meta: append([]exitMeta(nil), fe.meta...), consts: append([]LValue(nil), fe.consts...),
		nslots: nslots, exitCounts: make([]uint32, len(code.Exits)),
	}
	js.units[u] = struct{}{}
	js.codeBytes += block.Size()
	js.stats.Compiled++
	lp.unit = u
	js.logf("compiled %s: %d bytes, %d blocks, %d values, %d spills, %d exits, %d callout sites",
		f.Name, len(code.Bytes), code.NumBlocks, code.NumValues, code.NumSpills, len(code.Exits), fe.callouts)
	return u
}

// jitMark returns a marker for the native activations of this thread.
func (ls *LState) jitMark() int {
	if ls.jit == nil {
		return 0
	}
	return len(ls.jit.acts)
}

// jitUnwind drops the native activations above mark. It is used when an
// error unwinds the Go stack through native activations.
func (ls *LState) jitUnwind(mark int) {
	th := ls.jit
	if th == nil {
		return
	}
	for len(th.acts) > mark {
		ls.jitLeave(th)
	}
}

// jitLeave ends the innermost native activation of the thread.
func (ls *LState) jitLeave(th *jitThread) {
	u := th.acts[len(th.acts)-1]
	th.acts[len(th.acts)-1] = nil
	th.acts = th.acts[:len(th.acts)-1]
	u.active--
	if u.dead && u.active == 0 {
		ls.G.jit.release(u)
	}
}

// jitApply writes the registers described by a snapshot back into the
// registry.
func (ls *LState) jitApply(u *jitUnit, entries []jit.ExitEntry, frame []uint64, base int) {
	if len(entries) == 0 {
		return
	}
	reg := ls.reg
	if top := base + u.nslots; reg.top < top {
		reg.SetTop(top)
	}
	arr := reg.array
	// boxed copies read their source before anything is overwritten
	var aliasBuf [8]LValue
	aliases := aliasBuf[:0]
	for i := range entries {
		if entries[i].Tag == tagAlias {
			aliases = append(aliases, arr[base+int(entries[i].Const)])
		}
	}
	ai := 0
	for i := range entries {
		e := &entries[i]
		var raw uint64
		switch e.Loc.Kind {
		case jit.LocReg:
			raw = frame[jit.CtxSaveG/8+e.Loc.N]
		case jit.LocFReg:
			raw = frame[jit.CtxSaveF/8+e.Loc.N]
		case jit.LocSpill:
			raw = frame[jit.CtxSpill/8+e.Loc.N]
		default:
			raw = uint64(e.Const)
		}
		var v LValue
		switch e.Tag {
		case tagInt:
			v = ls.alloc.LInteger2I(LInteger(int64(raw)))
		case tagFloat:
			v = ls.alloc.LNumber2I(LNumber(math.Float64frombits(raw)))
		case tagBool:
			if raw != 0 {
				v = LTrue
			} else {
				v = LFalse
			}
		case tagNil:
			v = LNil
		case tagAlias:
			v = aliases[ai]
			ai++
		case tagConst:
			v = u.consts[raw]
		}
		arr[base+e.Slot] = v
	}
}

// jitRun executes the compiled unit u for the frame cf until native code
// hands control back to the interpreter. It returns 1 if the interpreter
// loop must return to its caller (like an instruction handler), else 0.
func (ls *LState) jitRun(cf *callFrame, u *jitUnit, baseframe *callFrame) int {
	js := ls.G.jit
	th := ls.jit
	if th == nil {
		th = &jitThread{}
		ls.jit = th
	}
	depth := len(th.acts)
	base := cf.LocalBase
	if depth >= jitMaxDepth || base+u.nslots > len(ls.reg.array) {
		return 0
	}
	if depth == len(th.frames) {
		th.frames = append(th.frames, nil)
	}
	frame := th.frames[depth]
	if len(frame) < u.code.FrameWords {
		frame = make([]uint64, u.code.FrameWords+16)
		th.frames[depth] = frame
	}
	th.acts = append(th.acts, u)
	u.active++
	u.entries++
	js.stats.Entries++

	fuel := js.fuel
	frame[jit.CtxFuel/8] = fuel
	target := u.addr + uintptr(u.code.EntryOffset)
	result := 0
loop:
	for {
		frame[jit.CtxTarget/8] = uint64(target)
		frame[jit.CtxRegBase/8] = uint64(uintptr(unsafe.Pointer(&ls.reg.array[base])))
		codecache.Call(u.addr, unsafe.Pointer(&frame[0]))

		id := int(frame[jit.CtxExit/8])
		x := &u.code.Exits[id]
		m := &u.meta[x.Data]
		switch m.kind {
		case emFuel:
			js.stats.SafePoints++
			u.iterations += fuel
			frame[jit.CtxFuel/8] = fuel
			if ls.ctx != nil {
				select {
				case <-ls.ctx.Done():
					ls.jitApply(u, x.Entries, frame, base)
					cf.Pc = x.PC + 1
					ls.jitLeave(th)
					ls.RaiseError(ls.ctx.Err().Error())
					return 0
				default:
				}
			}
			target = u.addr + uintptr(x.Resume)
		case emFlush:
			js.stats.Callouts++
			ls.jitApply(u, x.Entries, frame, base)
			target = u.addr + uintptr(x.Resume)
		case emInst:
			js.stats.Callouts++
			ls.jitApply(u, x.Entries, frame, base)
			pc := x.PC
			inst := cf.Fn.Proto.Code[pc]
			if int(inst>>26) == OP_CALL {
				if fn, ok := ls.reg.array[base+int(inst>>18)&0xff].(*LFunction); ok && !fn.IsG {
					// a Lua function: remember it so that a recompilation
					// ends the region here, and let the interpreter call
					u.jp.feedback[feedbackKey{int32(pc), int16(int(inst>>18) & 0xff), fbValue}] = vkLFunction
					cf.Pc = pc
					ls.jitExitNote(u, id, m, base, fuel-frame[jit.CtxFuel/8])
					break loop
				}
			}
			cf.Pc = pc + 1
			if jumpTable[int(inst>>26)](ls, inst, baseframe) == 1 {
				result = 1
				break loop
			}
			if ls.currentFrame != cf || u.dead {
				// the interpreter continues: either a new frame was
				// pushed or the unit was discarded while the callout ran
				break loop
			}
			if cf.Pc == pc+2 {
				frame[jit.CtxResult/8] = 1
			} else {
				frame[jit.CtxResult/8] = 0
			}
			target = u.addr + uintptr(x.Resume)
		default:
			// deoptimization: the interpreter re-executes the instruction
			js.stats.Deopts++
			ls.jitApply(u, x.Entries, frame, base)
			cf.Pc = x.PC
			ls.jitExitNote(u, id, m, base, fuel-frame[jit.CtxFuel/8])
			break loop
		}
	}
	ls.jitLeave(th)
	return result
}

// jitExitNote does the bookkeeping for an exit to the interpreter: it
// records type feedback for failed guards and decides whether the unit
// should be recompiled or the loop abandoned. iterations is the number of
// loop iterations executed natively since the last safe point.
func (ls *LState) jitExitNote(u *jitUnit, id int, m *exitMeta, base int, iterations uint64) {
	js := ls.G.jit
	u.iterations += iterations
	if u.dead {
		return
	}
	x := &u.code.Exits[id]
	if m.fbSlot >= 0 {
		key := feedbackKey{int32(x.PC), m.fbSlot, m.fbWhat}
		v := ls.reg.array[base+int(m.fbSlot)]
		switch m.fbWhat {
		case fbValue:
			u.jp.feedback[key] = valueKind(v)
		case fbArray:
			if tb, ok := v.(*LTable); ok {
				u.jp.feedback[key] = tb.akind
			}
		}
	}
	u.exitCounts[id]++
	n := uint64(u.exitCounts[id])
	if n < jitHotExit || n*64 <= u.iterations {
		return
	}
	// this exit is taken too often for the unit to pay off
	lp := u.loop
	js.discard(u)
	switch m.kind {
	case emUnsupported, emInst:
		js.blacklist(lp, fmt.Sprintf("unsupported code at pc %d is hot", x.PC))
		return
	case emLoopExit:
		js.blacklist(lp, "loop runs too few iterations per entry")
		return
	}
	js.logf("discard unit at pc %d: guard at pc %d fails too often", lp.pc, x.PC)
}

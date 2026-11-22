package lua

import (
	"fmt"
	"io"
	"sync"
	"time"
	"unsafe"

	"github.com/yuin/gopher-lua/internal/jit"
	"github.com/yuin/gopher-lua/internal/jit/codecache"
)

// JITOptions configures the native just-in-time compiler of a LState.
//
// The JIT compiles hot loops to machine code for amd64 and arm64 on Linux
// and macOS. On other platforms, or when executable memory cannot be
// obtained, the option is ignored and the interpreter is used.
type JITOptions struct {
	// Enabled turns the JIT compiler on.
	Enabled bool
	// Threshold is the number of iterations after which a loop is
	// compiled. Zero selects the default (50).
	Threshold int
	// MaxCodeBytes bounds the executable memory mapped for one state
	// (shared by its coroutines). When the limit is reached all compiled
	// code of the state is discarded and compilation starts over. Zero
	// selects the default (16 MiB).
	MaxCodeBytes int
	// SafePointInterval is the number of loop iterations native code may
	// execute before it returns to Go to honor garbage collection,
	// preemption and context cancellation. Zero selects the default
	// (65536).
	SafePointInterval int
	// Log, if not nil, receives one line per JIT event (compilation,
	// invalidation, blacklisting). It is meant for diagnostics.
	Log io.Writer
}

// JITStats reports the activity of the JIT compiler of a state.
type JITStats struct {
	// Enabled is true if the JIT is active for the state.
	Enabled bool
	// Supported is true if the platform has a native backend.
	Supported bool
	// Compiled is the number of successfully compiled units.
	Compiled int
	// CompileFailed counts compilation attempts that were rejected.
	CompileFailed int
	// Invalidated counts compiled units that were discarded.
	Invalidated int
	// Blacklisted counts loops that are permanently interpreted.
	Blacklisted int
	// CacheFlushes counts how often the code cache limit was hit.
	CacheFlushes int
	// LiveUnits is the number of compiled units currently installed.
	LiveUnits int
	// CodeBytes is the executable memory currently mapped for the state.
	CodeBytes int
	// MaxCodeBytes is the configured code cache limit.
	MaxCodeBytes int
	// Entries counts transitions from the interpreter into native code.
	Entries uint64
	// Deopts counts exits from native code back to the interpreter.
	Deopts uint64
	// Callouts counts runtime services executed on behalf of native code.
	Callouts uint64
	// SafePoints counts safe point exits.
	SafePoints uint64
	// CompileTime is the total time spent compiling.
	CompileTime time.Duration
}

func (s JITStats) String() string {
	if !s.Enabled {
		return fmt.Sprintf("jit: disabled (supported=%v)", s.Supported)
	}
	return fmt.Sprintf("jit: units=%d live=%d failed=%d invalidated=%d blacklisted=%d flushes=%d code=%dB/%dB entries=%d deopts=%d callouts=%d safepoints=%d compile=%v",
		s.Compiled, s.LiveUnits, s.CompileFailed, s.Invalidated, s.Blacklisted, s.CacheFlushes,
		s.CodeBytes, s.MaxCodeBytes, s.Entries, s.Deopts, s.Callouts, s.SafePoints, s.CompileTime)
}

const (
	jitDefaultThreshold = 50
	jitDefaultMaxCode   = 16 << 20
	jitDefaultFuel      = 1 << 16
	// jitMaxCompiles is the number of times one loop may be compiled
	// before it is blacklisted.
	jitMaxCompiles = 6
	// jitHotExit is the number of times a guard may fail before the unit
	// is recompiled with the collected type feedback.
	jitHotExit = 8
	// jitMaxFlushes is the number of code cache flushes after which the
	// JIT stops compiling for the state.
	jitMaxFlushes = 8
	// jitMaxRegion bounds the number of instructions of a compiled region.
	jitMaxRegion = 3000
	// jitMaxDepth bounds the nesting of native activations of a thread.
	jitMaxDepth = 64
)

// jitState is the JIT compiler state of a Lua state. It is shared by all
// threads (coroutines) of the state and must only be used by the
// goroutine that owns the state.
type jitState struct {
	threshold int32
	maxCode   int
	fuel      uint64
	log       io.Writer

	protos    map[*FunctionProto]*jitProto
	units     map[*jitUnit]struct{}
	codeBytes int
	flushes   int
	stopped   bool // no further compilation
	stats     JITStats
}

// jitProto is the per-state compilation state of a function prototype.
type jitProto struct {
	proto *FunctionProto
	// loops is indexed by the pc of the loop header.
	loops []*jitLoop
	// feedback records value kinds observed at failed guards.
	feedback map[feedbackKey]uint8
}

// jitLoop is the compilation state of one loop.
type jitLoop struct {
	pc          int
	count       int32
	compiles    int
	blacklisted bool
	unit        *jitUnit
}

// feedbackKey identifies a speculation site.
type feedbackKey struct {
	pc   int32
	slot int16
	what uint8
}

// Kinds of feedback.
const (
	fbValue uint8 = iota // kind of the value in a register
	fbArray              // array representation of the table in a register
)

// jitUnit is a piece of compiled code.
type jitUnit struct {
	block  *codecache.Block
	addr   uintptr
	code   *jit.Code
	loop   *jitLoop
	jp     *jitProto
	meta   []exitMeta
	consts []LValue
	nslots int

	exitCounts []uint32
	entries    uint64
	iterations uint64 // loop iterations executed natively
	active     int    // number of running activations
	dead       bool   // invalidated; freed when no activation is left
}

// jitThread is the per-thread native execution state.
type jitThread struct {
	// frames are context frames reused by nesting depth.
	frames [][]uint64
	// acts is the stack of running native activations.
	acts []*jitUnit
}

var jitTables struct {
	once  sync.Once
	table [opCodeMax + 1]instFunc
}

// jitJumpTable returns the instruction table used when the JIT is on: it
// is the interpreter table with loop back-edges instrumented.
func jitJumpTable() *[opCodeMax + 1]instFunc {
	jitTables.once.Do(func() {
		jitTables.table = jumpTable
		jitTables.table[OP_FORLOOP] = opForLoopJIT
		jitTables.table[OP_JMP] = opJmpJIT
	})
	return &jitTables.table
}

// jitSupported reports whether the JIT can run in this process.
func jitSupported() bool {
	return codecache.Supported && jit.HostSupported() && jitLayoutOK
}

// initJIT enables the JIT for a new state if requested and possible.
func (ls *LState) initJIT() {
	opts := ls.Options.JIT
	if !opts.Enabled || !jitSupported() {
		return
	}
	js := &jitState{
		threshold: int32(opts.Threshold),
		maxCode:   opts.MaxCodeBytes,
		fuel:      uint64(opts.SafePointInterval),
		log:       opts.Log,
		protos:    make(map[*FunctionProto]*jitProto),
		units:     make(map[*jitUnit]struct{}),
	}
	if js.threshold <= 0 {
		js.threshold = jitDefaultThreshold
	}
	if js.maxCode <= 0 {
		js.maxCode = jitDefaultMaxCode
	}
	if js.fuel == 0 {
		js.fuel = jitDefaultFuel
	}
	ls.G.jit = js
	ls.jitOn = true
	ls.typedArrays = true
	ls.G.Registry.typedOK = true
	ls.G.Global.typedOK = true
	jitJumpTable()
	ls.mainLoop = selectMainLoop(true, ls.ctx != nil)
}

// closeJIT releases all native code of the state. It is called when the
// main thread is closed.
func (ls *LState) closeJIT() {
	js := ls.G.jit
	if js == nil || ls.G.MainThread != nil && ls.G.MainThread != ls {
		return
	}
	for u := range js.units {
		u.dead = true
		if u.block != nil {
			u.block.Free()
			u.block = nil
		}
	}
	js.units = make(map[*jitUnit]struct{})
	js.codeBytes = 0
	js.stopped = true
}

// JITStats returns a snapshot of the JIT statistics of this state.
func (ls *LState) JITStats() JITStats {
	js := ls.G.jit
	if js == nil {
		return JITStats{Supported: jitSupported()}
	}
	s := js.stats
	s.Enabled = true
	s.Supported = true
	s.LiveUnits = len(js.units)
	s.CodeBytes = js.codeBytes
	s.MaxCodeBytes = js.maxCode
	return s
}

// JITFlush discards all compiled code of the state. Compilation starts
// over as code becomes hot again.
func (ls *LState) JITFlush() {
	if js := ls.G.jit; js != nil {
		js.flushAll("requested")
	}
}

func (js *jitState) logf(format string, args ...interface{}) {
	if js.log != nil {
		fmt.Fprintf(js.log, "jit: "+format+"\n", args...)
	}
}

// protoFor returns the compilation state of a prototype.
func (js *jitState) protoFor(p *FunctionProto) *jitProto {
	jp := js.protos[p]
	if jp == nil {
		jp = &jitProto{proto: p, loops: make([]*jitLoop, len(p.Code)+1), feedback: make(map[feedbackKey]uint8)}
		js.protos[p] = jp
	}
	return jp
}

// discard removes a unit from the code cache. Its memory is released
// immediately if the unit is not running, else when its last activation
// ends.
func (js *jitState) discard(u *jitUnit) {
	if u.dead {
		return
	}
	u.dead = true
	delete(js.units, u)
	if u.loop != nil && u.loop.unit == u {
		u.loop.unit = nil
	}
	js.stats.Invalidated++
	if u.active == 0 {
		js.release(u)
	}
}

// release frees the executable memory of a dead unit.
func (js *jitState) release(u *jitUnit) {
	if u.block != nil {
		js.codeBytes -= u.block.Size()
		u.block.Free()
		u.block = nil
	}
}

// flushAll discards every compiled unit of the state.
func (js *jitState) flushAll(reason string) {
	js.logf("flush code cache (%s): %d units, %d bytes", reason, len(js.units), js.codeBytes)
	for u := range js.units {
		js.discard(u)
	}
	js.stats.CacheFlushes++
	js.flushes++
	if js.flushes >= jitMaxFlushes && reason != "requested" {
		js.stopped = true
		js.logf("compilation stopped after %d cache flushes", js.flushes)
	}
}

/* layout of Go data structures read by native code {{{ */

// itabOf returns the first word of the interface value v, which
// identifies its dynamic type.
func itabOf(v LValue) uintptr {
	return (*[2]uintptr)(unsafe.Pointer(&v))[0]
}

// dataOf returns the data word of the interface value v.
func dataOf(v LValue) unsafe.Pointer {
	return (*[2]unsafe.Pointer)(unsafe.Pointer(&v))[1]
}

var (
	itabInteger = itabOf(LInteger(12345))
	itabNumber  = itabOf(LNumber(1.5))
	itabNil     = itabOf(LNil)
	itabBool    = itabOf(LTrue)
	itabTable   = itabOf(&LTable{})

	offTableAkind     = unsafe.Offsetof(LTable{}.akind)
	offTableArray     = unsafe.Offsetof(LTable{}.array)
	offTableIarr      = unsafe.Offsetof(LTable{}.iarr)
	offTableFarr      = unsafe.Offsetof(LTable{}.farr)
	offTableMetatable = unsafe.Offsetof(LTable{}.Metatable)

	// jitLayoutOK is false if the Go runtime does not lay out interface
	// values and slices the way the native code expects.
	jitLayoutOK = checkJITLayout()
)

const (
	sliceOffData = 0
	sliceOffLen  = 8
	sliceOffCap  = 16
	lvalueSize   = 16
)

// checkJITLayout verifies the assumptions native code makes about the
// memory layout of interface values, slices and boxed numbers.
func checkJITLayout() bool {
	if unsafe.Sizeof(uintptr(0)) != 8 || unsafe.Sizeof(LValue(nil)) != lvalueSize {
		return false
	}
	var lv LValue = LInteger(0x1122334455667788)
	if *(*int64)(dataOf(lv)) != 0x1122334455667788 {
		return false
	}
	lv = LNumber(2.5)
	if *(*float64)(dataOf(lv)) != 2.5 {
		return false
	}
	if *(*byte)(dataOf(LTrue)) != 1 || *(*byte)(dataOf(LFalse)) != 0 {
		return false
	}
	tb := &LTable{}
	lv = tb
	if dataOf(lv) != unsafe.Pointer(tb) {
		return false
	}
	s := make([]float64, 3, 7)
	hdr := (*[3]uintptr)(unsafe.Pointer(&s))
	if hdr[0] != uintptr(unsafe.Pointer(&s[0])) || hdr[1] != 3 || hdr[2] != 7 {
		return false
	}
	arr := make([]LValue, 2)
	if uintptr(unsafe.Pointer(&arr[1]))-uintptr(unsafe.Pointer(&arr[0])) != lvalueSize {
		return false
	}
	if itabInteger == itabNumber || itabNil == 0 || itabTable == itabNil || itabBool == itabNil {
		return false
	}
	return true
}

/* }}} */

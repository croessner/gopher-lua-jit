package lua

// JITOptions configures the native just-in-time compiler of a LState.
type JITOptions struct {
	// Enabled turns the JIT compiler on. It is silently ignored on
	// platforms without a native backend (the interpreter is used).
	Enabled bool
	// Threshold is the number of loop iterations after which a loop is
	// compiled to native code. Zero selects the default.
	Threshold int
	// MaxCodeBytes bounds the executable memory used by one state. Zero
	// selects the default.
	MaxCodeBytes int
}

type jitState struct{}

type jitThread struct{}

type jitProtoCache struct{}

func (ls *LState) initJIT()  {}
func (ls *LState) closeJIT() {}

func (ls *LState) jitMark() int       { return 0 }
func (ls *LState) jitUnwind(mark int) {}

func mainLoopJIT(L *LState, baseframe *callFrame) { mainLoop(L, baseframe) }

// selectMainLoop returns the interpreter loop for a thread configuration.
func selectMainLoop(jitOn bool, withContext bool) func(*LState, *callFrame) {
	if withContext {
		return mainLoopWithContext
	}
	if jitOn {
		return mainLoopJIT
	}
	return mainLoop
}

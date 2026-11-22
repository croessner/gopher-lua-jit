//go:build !upstream

package benchmarks

import (
	"testing"

	lua "github.com/yuin/gopher-lua"
)

// config is a runtime configuration to benchmark.
type config struct {
	name     string
	newState func() *lua.LState
}

func newState(version lua.LanguageVersion, jit bool) func() *lua.LState {
	return func() *lua.LState {
		return lua.NewState(lua.Options{
			CallStackSize:   lua.CallStackSize,
			RegistrySize:    lua.RegistrySize,
			LanguageVersion: version,
			JIT:             lua.JITOptions{Enabled: jit},
		})
	}
}

var configs = []config{
	{"interp-lua51", newState(lua.Lua51, false)},
	{"jit-lua51", newState(lua.Lua51, true)},
	{"interp-lua55", newState(lua.Lua55, false)},
	{"jit-lua55", newState(lua.Lua55, true)},
}

// reportJIT adds JIT metrics to a benchmark result.
func reportJIT(b *testing.B, L *lua.LState) {
	st := L.JITStats()
	if !st.Enabled {
		return
	}
	b.ReportMetric(float64(st.CodeBytes), "code-bytes")
	b.ReportMetric(float64(st.Compiled), "units")
	b.ReportMetric(float64(st.CompileTime.Microseconds()), "compile-us")
}

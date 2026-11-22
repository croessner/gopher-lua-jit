//go:build upstream

package benchmarks

import (
	"testing"

	lua "github.com/yuin/gopher-lua"
)

// config is a runtime configuration to benchmark.
type config struct {
	name     string
	newState func() *lua.LState
	// num converts a Go integer to the Lua number passed to scripts.
	num func(int) lua.LValue
}

var configs = []config{
	{"upstream", func() *lua.LState { return lua.NewState() }, func(n int) lua.LValue { return lua.LNumber(n) }},
}

// reportJIT is a no-op for upstream GopherLua.
func reportJIT(b *testing.B, L *lua.LState) {}

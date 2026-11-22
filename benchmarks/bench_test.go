// Package benchmarks contains reproducible benchmarks that run the same
// Lua kernels on this runtime and on upstream GopherLua.
//
// The package only uses the GopherLua API. Which implementation is
// measured is selected by the module file:
//
//	go test -bench . -benchmem                                   # this runtime
//	go test -modfile=go.upstream.mod -tags upstream -bench . -benchmem   # upstream GopherLua v1.1.2
package benchmarks

import (
	"os"
	"path/filepath"
	"sync"
	"testing"

	lua "github.com/yuin/gopher-lua"
)

// kernel is a Lua benchmark kernel and its problem size.
type kernel struct {
	name string
	n    int
}

var kernels = []kernel{
	{"arith_int", 1000000}, {"arith_float", 1000000}, {"loop_nested", 10000},
	{"calls", 300000}, {"fib", 24}, {"table_array", 200000}, {"table_hash", 300000},
	{"strings", 20000}, {"metamethods", 100000}, {"closures", 200000},
	{"mandelbrot", 100}, {"sieve", 200000}, {"math_calls", 300000}, {"go_callback", 300000},
}

// goCallback is the Go function called by the go_callback kernel.
func goCallback(L *lua.LState) int {
	L.Push(lua.LNumber(L.CheckNumber(1) + 1))
	return 1
}

// loadKernel loads a kernel script and returns its run function.
func loadKernel(tb testing.TB, L *lua.LState, name string) lua.LValue {
	tb.Helper()
	src, err := os.ReadFile(filepath.Join("scripts", name+".lua"))
	if err != nil {
		tb.Fatal(err)
	}
	L.SetGlobal("gofn", L.NewFunction(goCallback))
	fn, err := L.LoadString(string(src))
	if err != nil {
		tb.Fatal(err)
	}
	L.Push(fn)
	if err := L.PCall(0, 1, nil); err != nil {
		tb.Fatal(err)
	}
	run := L.Get(-1)
	L.Pop(1)
	return run
}

// callKernel calls the run function once.
func callKernel(tb testing.TB, L *lua.LState, run lua.LValue, n int) {
	if err := L.CallByParam(lua.P{Fn: run, NRet: 1, Protect: true}, lua.LNumber(n)); err != nil {
		tb.Fatal(err)
	}
	L.Pop(1)
}

// BenchmarkKernel measures warm execution of every kernel in every
// configuration (interpreter, JIT, language profiles).
func BenchmarkKernel(b *testing.B) {
	for _, k := range kernels {
		for _, cfg := range configs {
			b.Run(k.name+"/"+cfg.name, func(b *testing.B) {
				L := cfg.newState()
				defer L.Close()
				run := loadKernel(b, L, k.name)
				callKernel(b, L, run, k.n) // warm up (and compile)
				callKernel(b, L, run, k.n)
				b.ReportAllocs()
				b.ResetTimer()
				for i := 0; i < b.N; i++ {
					callKernel(b, L, run, k.n)
				}
				b.StopTimer()
				reportJIT(b, L)
			})
		}
	}
}

// BenchmarkCold measures a fresh state executing a kernel once: state
// creation, parsing, compilation, and for the JIT configurations also
// native code generation.
func BenchmarkCold(b *testing.B) {
	for _, name := range []string{"arith_int", "mandelbrot", "strings"} {
		var n int
		for _, k := range kernels {
			if k.name == name {
				n = k.n / 10
			}
		}
		for _, cfg := range configs {
			b.Run(name+"/"+cfg.name, func(b *testing.B) {
				b.ReportAllocs()
				for i := 0; i < b.N; i++ {
					L := cfg.newState()
					run := loadKernel(b, L, name)
					callKernel(b, L, run, n)
					L.Close()
				}
			})
		}
	}
}

// BenchmarkGoToLua measures calling a tiny Lua function from Go.
func BenchmarkGoToLua(b *testing.B) {
	for _, cfg := range configs {
		b.Run(cfg.name, func(b *testing.B) {
			L := cfg.newState()
			defer L.Close()
			if err := L.DoString(`function add(a, b) return a + b end`); err != nil {
				b.Fatal(err)
			}
			fn := L.GetGlobal("add")
			p := lua.P{Fn: fn, NRet: 1, Protect: true}
			b.ReportAllocs()
			b.ResetTimer()
			for i := 0; i < b.N; i++ {
				if err := L.CallByParam(p, lua.LNumber(i), lua.LNumber(2)); err != nil {
					b.Fatal(err)
				}
				L.Pop(1)
			}
		})
	}
}

// BenchmarkNewState measures creating and closing a state with all
// standard libraries.
func BenchmarkNewState(b *testing.B) {
	for _, cfg := range configs {
		b.Run(cfg.name, func(b *testing.B) {
			b.ReportAllocs()
			for i := 0; i < b.N; i++ {
				cfg.newState().Close()
			}
		})
	}
}

// BenchmarkPool measures the typical server pattern: take a prepared
// state from a pool, call a function, put it back, on all CPUs.
func BenchmarkPool(b *testing.B) {
	const script = `
function handle(n)
  local s = 0
  for i = 1, n do s = s + i % 7 end
  return s
end`
	for _, cfg := range configs {
		b.Run(cfg.name, func(b *testing.B) {
			pool := sync.Pool{New: func() interface{} {
				L := cfg.newState()
				if err := L.DoString(script); err != nil {
					panic(err)
				}
				return L
			}}
			b.ReportAllocs()
			b.RunParallel(func(pb *testing.PB) {
				for pb.Next() {
					L := pool.Get().(*lua.LState)
					if err := L.CallByParam(lua.P{Fn: L.GetGlobal("handle"), NRet: 1, Protect: true}, lua.LNumber(200)); err != nil {
						b.Fatal(err)
					}
					L.Pop(1)
					pool.Put(L)
				}
			})
		})
	}
}

//go:build (linux || darwin) && amd64

package codecache

import (
	"testing"

	asm "github.com/yuin/gopher-lua/internal/jit/asm/amd64"
)

// genAdd generates: ctx[0] += ctx[1].
func genAdd(t testing.TB) []byte {
	a := asm.New()
	a.MovRM(asm.RAX, asm.M(asm.R15, 8))
	a.MovRM(asm.RCX, asm.M(asm.R15, 0))
	a.AddRR(asm.RCX, asm.RAX)
	a.MovMR(asm.M(asm.R15, 0), asm.RCX)
	a.Ret()
	return finish(t, a.Bytes)
}

// genLoop generates: do { ctx[1]++ } while (--ctx[0] != 0).
func genLoop(t testing.TB) []byte {
	a := asm.New()
	top := a.NewLabel()
	a.Bind(top)
	a.IncM(asm.M(asm.R15, 8))
	a.DecM(asm.M(asm.R15, 0))
	a.Jcc(asm.CondNE, top)
	a.Ret()
	return finish(t, a.Bytes)
}

// genFloat generates: ctxf[2] = sqrt(ctxf[0]) * ctxf[1].
func genFloat(t testing.TB) []byte {
	a := asm.New()
	a.MovsdXM(asm.X0, asm.M(asm.R15, 0))
	a.SqrtsdXX(asm.X0, asm.X0)
	a.MulsdXM(asm.X0, asm.M(asm.R15, 8))
	a.MovsdMX(asm.M(asm.R15, 16), asm.X0)
	a.Ret()
	return finish(t, a.Bytes)
}

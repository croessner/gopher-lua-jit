//go:build (linux || darwin) && arm64

package codecache

import (
	"testing"

	asm "github.com/yuin/gopher-lua/internal/jit/asm/arm64"
)

// genAdd generates: ctx[0] += ctx[1].
func genAdd(t testing.TB) []byte {
	a := asm.New()
	a.LdrRM(asm.X0, asm.X19, 0)
	a.LdrRM(asm.X1, asm.X19, 8)
	a.AddRR(asm.X0, asm.X0, asm.X1)
	a.StrRM(asm.X0, asm.X19, 0)
	a.Ret()
	return finish(t, a.Bytes)
}

// genLoop generates: do { ctx[1]++ } while (--ctx[0] != 0).
func genLoop(t testing.TB) []byte {
	a := asm.New()
	a.LdrRM(asm.X0, asm.X19, 0)
	a.LdrRM(asm.X1, asm.X19, 8)
	top := a.NewLabel()
	a.Bind(top)
	a.AddRI(asm.X1, asm.X1, 1)
	a.SubsRI(asm.X0, asm.X0, 1)
	a.Bcond(asm.CondNE, top)
	a.StrRM(asm.X0, asm.X19, 0)
	a.StrRM(asm.X1, asm.X19, 8)
	a.Ret()
	return finish(t, a.Bytes)
}

// genFloat generates: ctxf[2] = sqrt(ctxf[0]) * ctxf[1].
func genFloat(t testing.TB) []byte {
	a := asm.New()
	a.LdrDM(asm.V0, asm.X19, 0)
	a.LdrDM(asm.V1, asm.X19, 8)
	a.FsqrtD(asm.V0, asm.V0)
	a.FmulD(asm.V0, asm.V0, asm.V1)
	a.StrDM(asm.V0, asm.X19, 16)
	a.Ret()
	return finish(t, a.Bytes)
}

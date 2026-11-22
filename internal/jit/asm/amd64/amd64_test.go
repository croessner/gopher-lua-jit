package amd64

import (
	"bytes"
	"encoding/hex"
	"errors"
	"testing"
)

// mustBytes returns the assembled code or fails the test.
func mustBytes(t *testing.T, a *Assembler) []byte {
	t.Helper()

	code, err := a.Bytes()
	if err != nil {
		t.Fatalf("Bytes() error: %v", err)
	}

	return code
}

// wantHex compares assembled code against a hex string (spaces ignored).
func wantHex(t *testing.T, a *Assembler, want string) {
	t.Helper()

	got := hex.EncodeToString(mustBytes(t, a))
	if got != stripSpaces(want) {
		t.Fatalf("code mismatch\n got: %s\nwant: %s", got, stripSpaces(want))
	}
}

// stripSpaces removes all ASCII spaces from s.
func stripSpaces(s string) string {
	return string(bytes.ReplaceAll([]byte(s), []byte(" "), nil))
}

// nops emits n one-byte NOPs.
func nops(a *Assembler, n int) {
	for range n {
		a.Nop()
	}
}

func TestRegisterNumbers(t *testing.T) {
	regs := []Reg{RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8, R9, R10, R11, R12, R13, R14, R15}
	for i, r := range regs {
		if int(r) != i {
			t.Errorf("general purpose register %d has number %d", i, r)
		}
	}

	xregs := []XReg{X0, X1, X2, X3, X4, X5, X6, X7, X8, X9, X10, X11, X12, X13, X14, X15}
	for i, x := range xregs {
		if int(x) != i {
			t.Errorf("SSE register %d has number %d", i, x)
		}
	}
}

func TestCondNumbersAndNegate(t *testing.T) {
	conds := []Cond{
		CondO, CondNO, CondB, CondAE, CondE, CondNE, CondBE, CondA,
		CondS, CondNS, CondP, CondNP, CondL, CondGE, CondLE, CondG,
	}
	for i, c := range conds {
		if int(c) != i {
			t.Errorf("condition %d has number %d", i, c)
		}
	}

	pairs := [][2]Cond{
		{CondO, CondNO}, {CondB, CondAE}, {CondE, CondNE}, {CondBE, CondA},
		{CondS, CondNS}, {CondP, CondNP}, {CondL, CondGE}, {CondLE, CondG},
	}
	for _, p := range pairs {
		if p[0].Negate() != p[1] || p[1].Negate() != p[0] {
			t.Errorf("Negate() does not map %d <-> %d", p[0], p[1])
		}
	}
}

func TestMemConstructors(t *testing.T) {
	if got, want := M(R12, -8), (Mem{Base: R12, Disp: -8}); got != want {
		t.Errorf("M() = %+v, want %+v", got, want)
	}

	if got, want := MIdx(RBX, R9, 4, 16), (Mem{Base: RBX, Index: R9, Scale: 4, Disp: 16}); got != want {
		t.Errorf("MIdx() = %+v, want %+v", got, want)
	}
}

func TestZeroValueAndLen(t *testing.T) {
	var a Assembler

	if a.Len() != 0 {
		t.Fatalf("Len() = %d on empty assembler", a.Len())
	}

	a.Ret()
	a.Ud2()

	if a.Len() != 3 {
		t.Fatalf("Len() = %d, want 3", a.Len())
	}

	wantHex(t, &a, "c3 0f0b")
}

// TestForwardBranches checks that unbound targets use rel32 and are patched
// relative to the end of the branch instruction.
func TestForwardBranches(t *testing.T) {
	a := New()
	l := a.NewLabel()

	if a.LabelOffset(l) != -1 {
		t.Fatalf("LabelOffset() = %d before Bind", a.LabelOffset(l))
	}

	a.Jmp(l)        // offset 0, 5 bytes: rel = 14 - 5 = 9
	a.Jcc(CondE, l) // offset 5, 6 bytes: rel = 14 - 11 = 3
	nops(a, 3)
	a.Bind(l)
	a.Ret()

	if a.LabelOffset(l) != 14 {
		t.Fatalf("LabelOffset() = %d, want 14", a.LabelOffset(l))
	}

	wantHex(t, a, "e9 09000000  0f84 03000000  909090  c3")
}

// TestForwardBranchToNext checks the zero displacement edge case.
func TestForwardBranchToNext(t *testing.T) {
	a := New()
	l := a.NewLabel()
	a.Jcc(CondNE, l)
	a.Bind(l)

	wantHex(t, a, "0f85 00000000")
}

func TestForwardBranchAllConditions(t *testing.T) {
	for c := CondO; c <= CondG; c++ {
		a := New()
		l := a.NewLabel()
		a.Jcc(c, l)
		nops(a, 0x123)
		a.Bind(l)

		code := mustBytes(t, a)
		want := []byte{0x0F, 0x80 | byte(c), 0x23, 0x01, 0x00, 0x00}

		if !bytes.Equal(code[:6], want) {
			t.Errorf("Jcc(%d) = % x, want % x", c, code[:6], want)
		}
	}
}

// TestBackwardBranches checks rel8 selection for bound targets and the exact
// boundary at which rel32 takes over.
func TestBackwardBranches(t *testing.T) {
	tests := []struct {
		name string
		pad  int
		emit func(a *Assembler, l Label)
		want string
	}{
		{"jmp self", 0, func(a *Assembler, l Label) { a.Jmp(l) }, "eb fe"},
		{"jmp rel8 min", 126, func(a *Assembler, l Label) { a.Jmp(l) }, "eb 80"},
		{"jmp rel32", 127, func(a *Assembler, l Label) { a.Jmp(l) }, "e9 7cffffff"},
		{"jcc self", 0, func(a *Assembler, l Label) { a.Jcc(CondL, l) }, "7c fe"},
		{"jcc rel8 min", 126, func(a *Assembler, l Label) { a.Jcc(CondL, l) }, "7c 80"},
		{"jcc rel32", 127, func(a *Assembler, l Label) { a.Jcc(CondL, l) }, "0f8c 7bffffff"},
		{"jcc far", 0x1000, func(a *Assembler, l Label) { a.Jcc(CondA, l) }, "0f87 faefffff"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := New()
			l := a.NewLabel()
			a.Bind(l)
			nops(a, tt.pad)
			tt.emit(a, l)

			got := hex.EncodeToString(mustBytes(t, a)[tt.pad:])
			if got != stripSpaces(tt.want) {
				t.Fatalf("branch = %s, want %s", got, stripSpaces(tt.want))
			}
		})
	}
}

// TestMultipleFixups checks several forward and backward references to one
// label, with a label bound at a non-zero offset.
func TestMultipleFixups(t *testing.T) {
	a := New()
	l := a.NewLabel()
	other := a.NewLabel()

	a.Jmp(l)            // 0..5:   rel = 23 - 5
	a.Jcc(CondG, l)     // 5..11:  rel = 23 - 11
	a.Jmp(other)        // 11..16: rel = 24 - 16
	a.Jcc(CondB, l)     // 16..22: rel = 23 - 22
	a.Nop()             // 22
	a.Bind(l)           // 23
	a.Ret()             // 23
	a.Bind(other)       // 24
	a.Jmp(l)            // 24..26: rel8 = 23 - 26
	a.Jcc(CondNP, l)    // 26..28: rel8 = 23 - 28
	a.Jcc(CondS, other) // 28..30: rel8 = 24 - 30

	wantHex(t, a, "e9 12000000  0f8f 0c000000  e9 08000000  0f82 01000000  90  c3  eb fd  7b fb  78 fa")
}

// TestBytesIsRepeatable checks that Bytes can be called again after more code
// was emitted and that earlier fixups stay correct.
func TestBytesIsRepeatable(t *testing.T) {
	a := New()
	l := a.NewLabel()
	a.Jmp(l)
	a.Bind(l)
	wantHex(t, a, "e9 00000000")

	l2 := a.NewLabel()
	a.Jmp(l2)
	a.Nop()
	a.Bind(l2)
	a.Ret()
	wantHex(t, a, "e9 00000000  e9 01000000  90  c3")
	wantHex(t, a, "e9 00000000  e9 01000000  90  c3")
}

func TestUnboundLabel(t *testing.T) {
	a := New()
	l := a.NewLabel()
	a.Jmp(l)

	if _, err := a.Bytes(); !errors.Is(err, ErrUnboundLabel) {
		t.Fatalf("Bytes() error = %v, want ErrUnboundLabel", err)
	}

	// An unbound label is not a sticky error: binding it later resolves it.
	a.Bind(l)
	wantHex(t, a, "e9 00000000")

	// An unreferenced unbound label is fine.
	a.Reset()
	_ = a.NewLabel()
	a.Ret()
	wantHex(t, a, "c3")
}

func TestLabelErrors(t *testing.T) {
	t.Run("bind twice", func(t *testing.T) {
		a := New()
		l := a.NewLabel()
		a.Bind(l)
		a.Nop()
		a.Bind(l)

		if _, err := a.Bytes(); !errors.Is(err, ErrLabelRebound) {
			t.Fatalf("Bytes() error = %v, want ErrLabelRebound", err)
		}

		if a.LabelOffset(l) != 0 {
			t.Fatalf("LabelOffset() = %d, want the first binding", a.LabelOffset(l))
		}
	})

	invalid := []struct {
		name string
		use  func(a *Assembler)
	}{
		{"bind unknown", func(a *Assembler) { a.Bind(Label(3)) }},
		{"bind negative", func(a *Assembler) { a.Bind(Label(-1)) }},
		{"jmp unknown", func(a *Assembler) { a.Jmp(Label(0)) }},
		{"jcc unknown", func(a *Assembler) { a.Jcc(CondE, Label(7)) }},
	}

	for _, tt := range invalid {
		t.Run(tt.name, func(t *testing.T) {
			a := New()
			tt.use(a)

			if a.Len() != 0 {
				t.Fatalf("invalid label emitted %d bytes", a.Len())
			}

			if _, err := a.Bytes(); !errors.Is(err, ErrInvalidLabel) {
				t.Fatalf("Bytes() error = %v, want ErrInvalidLabel", err)
			}
		})
	}

	if got := New().LabelOffset(Label(5)); got != -1 {
		t.Fatalf("LabelOffset(unknown) = %d, want -1", got)
	}
}

// TestInvalidOperands checks that every kind of invalid operand records an
// error and emits no bytes.
func TestInvalidOperands(t *testing.T) {
	const (
		badReg  = Reg(16)
		badXReg = XReg(16)
		badCond = Cond(16)
	)

	rspIndex := MIdx(RAX, RSP, 1, 0)
	badScale := MIdx(RAX, RCX, 3, 0)
	badBase := M(badReg, 0)
	badIndex := MIdx(RAX, badReg, 2, 0)

	tests := []struct {
		name string
		emit func(a *Assembler)
	}{
		{"rsp index load", func(a *Assembler) { a.MovRM(RAX, rspIndex) }},
		{"rsp index store", func(a *Assembler) { a.MovMR(rspIndex, RAX) }},
		{"rsp index scale 8", func(a *Assembler) { a.Lea(RAX, MIdx(RBX, RSP, 8, 4)) }},
		{"rsp index imm", func(a *Assembler) { a.MovMI(rspIndex, 1) }},
		{"rsp index imm32", func(a *Assembler) { a.MovMI32(rspIndex, 1) }},
		{"rsp index alu imm", func(a *Assembler) { a.AddMI(rspIndex, 1000) }},
		{"rsp index sse", func(a *Assembler) { a.MovsdXM(X0, rspIndex) }},
		{"rsp index jmp", func(a *Assembler) { a.JmpM(rspIndex) }},
		{"scale 3", func(a *Assembler) { a.MovRM(RAX, badScale) }},
		{"scale 16", func(a *Assembler) { a.CmpMI32(MIdx(RAX, RCX, 16, 0), 1) }},
		{"scale 3 inc", func(a *Assembler) { a.IncM(badScale) }},
		{"scale 3 sse store", func(a *Assembler) { a.MovsdMX(badScale, X1) }},
		{"base out of range", func(a *Assembler) { a.MovRM(RAX, badBase) }},
		{"index out of range", func(a *Assembler) { a.DecM(badIndex) }},
		{"reg with mem", func(a *Assembler) { a.MovRM(badReg, M(RAX, 0)) }},
		{"mov rr dst", func(a *Assembler) { a.MovRR(badReg, RAX) }},
		{"mov rr src", func(a *Assembler) { a.MovRR(RAX, badReg) }},
		{"mov ri small", func(a *Assembler) { a.MovRI(badReg, 1) }},
		{"mov ri negative", func(a *Assembler) { a.MovRI(badReg, -1) }},
		{"mov ri wide", func(a *Assembler) { a.MovRI(badReg, 1<<40) }},
		{"alu imm8", func(a *Assembler) { a.AddRI(badReg, 1) }},
		{"alu imm32", func(a *Assembler) { a.CmpRI(badReg, 1000) }},
		{"test imm", func(a *Assembler) { a.TestRI(badReg, 1) }},
		{"imul imm", func(a *Assembler) { a.ImulRRI(RAX, badReg, 1000) }},
		{"shift reg", func(a *Assembler) { a.ShlRI(badReg, 3) }},
		{"shift count 64", func(a *Assembler) { a.ShlRI(RAX, 64) }},
		{"shift count 255", func(a *Assembler) { a.SarRI(RAX, 255) }},
		{"shift count shr", func(a *Assembler) { a.ShrRI(RAX, 64) }},
		{"setcc cond", func(a *Assembler) { a.Setcc(badCond, RAX) }},
		{"setcc reg", func(a *Assembler) { a.Setcc(CondE, badReg) }},
		{"cmovcc cond", func(a *Assembler) { a.Cmovcc(badCond, RAX, RCX) }},
		{"jmp reg", func(a *Assembler) { a.JmpR(badReg) }},
		{"sse dst", func(a *Assembler) { a.AddsdXX(badXReg, X0) }},
		{"sse src", func(a *Assembler) { a.AddsdXX(X0, badXReg) }},
		{"sse mem reg", func(a *Assembler) { a.MovsdXM(badXReg, M(RAX, 0)) }},
		{"cvt int reg", func(a *Assembler) { a.Cvtsi2sdXR(X0, badReg) }},
		{"cvt sse reg", func(a *Assembler) { a.Cvttsd2siRX(RAX, badXReg) }},
		{"movq", func(a *Assembler) { a.MovqRX(badReg, X0) }},
		{"roundsd reg", func(a *Assembler) { a.RoundsdXXI(X0, badXReg, 1) }},
		{"roundsd mode", func(a *Assembler) { a.RoundsdXXI(X0, X1, 16) }},
		{"jcc cond", func(a *Assembler) {
			l := a.NewLabel()
			a.Bind(l)
			a.Jcc(badCond, l)
		}},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := New()
			tt.emit(a)

			if a.Len() != 0 {
				t.Errorf("invalid operand emitted %d bytes", a.Len())
			}

			if !errors.Is(a.Err(), ErrInvalidOperand) {
				t.Errorf("Err() = %v, want ErrInvalidOperand", a.Err())
			}

			if code, err := a.Bytes(); !errors.Is(err, ErrInvalidOperand) || code != nil {
				t.Errorf("Bytes() = %x, %v, want nil, ErrInvalidOperand", code, err)
			}
		})
	}
}

// TestErrorIsStickyUntilReset checks that valid code emitted after an error
// does not hide it, that the first error wins, and that Reset clears it.
func TestErrorIsStickyUntilReset(t *testing.T) {
	a := New()
	a.Ret()
	a.MovRM(RAX, MIdx(RAX, RSP, 1, 0))
	a.Bind(Label(9))
	a.Ret()

	if _, err := a.Bytes(); !errors.Is(err, ErrInvalidOperand) {
		t.Fatalf("Bytes() error = %v, want the first error (ErrInvalidOperand)", err)
	}

	a.Reset()

	if a.Len() != 0 || a.Err() != nil {
		t.Fatalf("Reset() left Len()=%d Err()=%v", a.Len(), a.Err())
	}

	if l := a.NewLabel(); l != 0 {
		t.Fatalf("NewLabel() after Reset = %d, want 0", l)
	}

	a.Ret()
	wantHex(t, a, "c3")
}

// TestScaleZeroIgnoresIndex pins the documented meaning of Scale == 0.
func TestScaleZeroIgnoresIndex(t *testing.T) {
	a := New()
	a.MovRM(RAX, Mem{Base: RBX, Index: RSP, Scale: 0, Disp: 8})
	wantHex(t, a, "48 8b 43 08")
}

// TestNoAllocations checks that encoding does not allocate once the buffers
// have grown to their working size.
func TestNoAllocations(t *testing.T) {
	a := New()

	emit := func() {
		a.Reset()

		l := a.NewLabel()
		back := a.NewLabel()
		a.Bind(back)
		a.MovRI(R10, -0x123456789)
		a.MovRM(RAX, MIdx(R12, R13, 8, 0x100))
		a.MovMI(M(RSP, 8), 42)
		a.AddRI(RAX, 1000)
		a.CmpMI32(M(RBP, 0), 7)
		a.ImulRRI(RAX, RCX, 1000)
		a.ShlRI(RAX, 3)
		a.Setcc(CondE, RSI)
		a.Cmovcc(CondL, R8, R9)
		a.Jcc(CondNE, l)
		a.MovsdXM(X9, M(R13, 0))
		a.AddsdXX(X1, X15)
		a.Cvtsi2sdXR(X0, R11)
		a.RoundsdXXI(X0, X1, 3)
		a.Jmp(back)
		a.Bind(l)
		a.Ret()

		if _, err := a.Bytes(); err != nil {
			t.Fatalf("Bytes() error: %v", err)
		}
	}

	emit()

	if allocs := testing.AllocsPerRun(100, emit); allocs != 0 {
		t.Fatalf("encoding allocated %v times per run, want 0", allocs)
	}
}

package arm64

import (
	"errors"
	"testing"
)

// TestInvalidOperands checks that every unencodable operand is reported by
// Bytes as ErrOperand, that no bytes are returned, and that the emitter still
// advanced by exactly one placeholder word.
func TestInvalidOperands(t *testing.T) {
	const (
		badReg  = Reg(32)
		badVReg = VReg(32)
		badCond = Cond(15)
	)

	cases := map[string]func(a *Assembler){
		// Add/subtract immediates that are neither imm12 nor imm12<<12.
		"AddRI 0x1001":     func(a *Assembler) { a.AddRI(X0, X1, 0x1001) },
		"AddRI 0xfff001":   func(a *Assembler) { a.AddRI(X0, X1, 0xFFF001) },
		"AddRI 0x1000000":  func(a *Assembler) { a.AddRI(X0, X1, 0x1000000) },
		"AddRI max":        func(a *Assembler) { a.AddRI(X0, X1, 0xFFFFFFFF) },
		"SubRI 0x1001":     func(a *Assembler) { a.SubRI(X0, X1, 0x1001) },
		"SubRI 0x1000000":  func(a *Assembler) { a.SubRI(SP, SP, 0x1000000) },
		"AddsRI 0x1fff":    func(a *Assembler) { a.AddsRI(X0, X1, 0x1FFF) },
		"SubsRI 0x1000800": func(a *Assembler) { a.SubsRI(X0, X1, 0x1000800) },
		"CmpRI 0x1001":     func(a *Assembler) { a.CmpRI(X1, 0x1001) },
		"CmpRI 0x1000000":  func(a *Assembler) { a.CmpRI(X1, 0x1000000) },
		"CmnRI 0x12345":    func(a *Assembler) { a.CmnRI(X1, 0x12345) },

		// Shift amounts above 63.
		"LslRI 64":  func(a *Assembler) { a.LslRI(X0, X1, 64) },
		"LsrRI 64":  func(a *Assembler) { a.LsrRI(X0, X1, 64) },
		"AsrRI 64":  func(a *Assembler) { a.AsrRI(X0, X1, 64) },
		"LslRI 255": func(a *Assembler) { a.LslRI(X0, X1, 255) },

		// Displacements outside both addressing forms.
		"LdrRM 32768":     func(a *Assembler) { a.LdrRM(X0, X1, 32768) },
		"LdrRM 32764":     func(a *Assembler) { a.LdrRM(X0, X1, 32764) },
		"LdrRM 260":       func(a *Assembler) { a.LdrRM(X0, X1, 260) },
		"LdrRM 257":       func(a *Assembler) { a.LdrRM(X0, X1, 257) },
		"LdrRM -257":      func(a *Assembler) { a.LdrRM(X0, X1, -257) },
		"LdrRM -264":      func(a *Assembler) { a.LdrRM(X0, X1, -264) },
		"StrRM 32768":     func(a *Assembler) { a.StrRM(X0, SP, 32768) },
		"StrRM -257":      func(a *Assembler) { a.StrRM(X0, SP, -257) },
		"StrRM min":       func(a *Assembler) { a.StrRM(X0, SP, -1<<31) },
		"StrRM max":       func(a *Assembler) { a.StrRM(X0, SP, 1<<31-1) },
		"LdrRM32 16384":   func(a *Assembler) { a.LdrRM32(X0, X1, 16384) },
		"LdrRM32 258":     func(a *Assembler) { a.LdrRM32(X0, X1, 258) },
		"LdrRM32 -257":    func(a *Assembler) { a.LdrRM32(X0, X1, -257) },
		"StrRM32 16384":   func(a *Assembler) { a.StrRM32(X0, X1, 16384) },
		"StrRM32 16382":   func(a *Assembler) { a.StrRM32(X0, X1, 16382) },
		"StrRM32 -260":    func(a *Assembler) { a.StrRM32(X0, X1, -260) },
		"LdrbRM 4096":     func(a *Assembler) { a.LdrbRM(X0, X1, 4096) },
		"LdrbRM -257":     func(a *Assembler) { a.LdrbRM(X0, X1, -257) },
		"LdrDM 32768":     func(a *Assembler) { a.LdrDM(V0, X1, 32768) },
		"LdrDM 300":       func(a *Assembler) { a.LdrDM(V0, X1, 300) },
		"LdrDM -257":      func(a *Assembler) { a.LdrDM(V0, X1, -257) },
		"StrDM 32768":     func(a *Assembler) { a.StrDM(V0, X1, 32768) },
		"StrDM -257":      func(a *Assembler) { a.StrDM(V0, X1, -257) },
		"StrDM unaligned": func(a *Assembler) { a.StrDM(V0, X1, 1001) },

		// Conditions.
		"Cset AL":       func(a *Assembler) { a.Cset(X0, CondAL) },
		"Cset bad cond": func(a *Assembler) { a.Cset(X0, badCond) },
		"Csel bad cond": func(a *Assembler) { a.Csel(X0, X1, X2, badCond) },
		"Bcond bad cond": func(a *Assembler) {
			l := a.NewLabel()
			a.Bind(l)
			a.Bcond(badCond, l)
		},

		// Register numbers above 31.
		"MovRR dst":      func(a *Assembler) { a.MovRR(badReg, X0) },
		"MovRR src":      func(a *Assembler) { a.MovRR(X0, badReg) },
		"MovRI dst":      func(a *Assembler) { a.MovRI(badReg, 1) },
		"AddRR m":        func(a *Assembler) { a.AddRR(X0, X1, badReg) },
		"SubRR n":        func(a *Assembler) { a.SubRR(X0, badReg, X1) },
		"MsubRRRR ra":    func(a *Assembler) { a.MsubRRRR(X0, X1, X2, badReg) },
		"MsubRRRR dst":   func(a *Assembler) { a.MsubRRRR(Reg(255), X1, X2, X3) },
		"LslRI dst":      func(a *Assembler) { a.LslRI(badReg, X1, 1) },
		"AddRI n":        func(a *Assembler) { a.AddRI(X0, badReg, 1) },
		"CmpRI n":        func(a *Assembler) { a.CmpRI(badReg, 1) },
		"CmpRR m":        func(a *Assembler) { a.CmpRR(X0, badReg) },
		"Cset dst":       func(a *Assembler) { a.Cset(badReg, CondEQ) },
		"Csel n":         func(a *Assembler) { a.Csel(X0, badReg, X1, CondEQ) },
		"LdrRM base":     func(a *Assembler) { a.LdrRM(X0, badReg, 0) },
		"StrRM src":      func(a *Assembler) { a.StrRM(badReg, X0, 0) },
		"LdrRMIdx index": func(a *Assembler) { a.LdrRMIdx(X0, X1, badReg, true) },
		"StrDMIdx src":   func(a *Assembler) { a.StrDMIdx(badVReg, X1, X2, false) },
		"Br":             func(a *Assembler) { a.Br(badReg) },
		"Cbz": func(a *Assembler) {
			l := a.NewLabel()
			a.Bind(l)
			a.Cbz(badReg, l)
		},
		"FmovDD dst":   func(a *Assembler) { a.FmovDD(badVReg, V0) },
		"FmovDR src":   func(a *Assembler) { a.FmovDR(V0, badReg) },
		"FmovRD src":   func(a *Assembler) { a.FmovRD(X0, badVReg) },
		"FaddD m":      func(a *Assembler) { a.FaddD(V0, V1, badVReg) },
		"FcmpDD n":     func(a *Assembler) { a.FcmpDD(badVReg, V0) },
		"ScvtfDR dst":  func(a *Assembler) { a.ScvtfDR(badVReg, X0) },
		"FcvtzsRD dst": func(a *Assembler) { a.FcvtzsRD(badReg, V0) },
		"FcvtmsRD src": func(a *Assembler) { a.FcvtmsRD(X0, badVReg) },
		"LdrDM dst":    func(a *Assembler) { a.LdrDM(badVReg, X0, 8) },
	}

	for name, emit := range cases {
		a := New()
		a.Nop()
		emit(a)
		a.Ret()

		if a.Len() != 3*instrSize {
			t.Errorf("%s: Len = %d, want %d (one placeholder word)", name, a.Len(), 3*instrSize)
		}

		if !errors.Is(a.Err(), ErrOperand) {
			t.Errorf("%s: Err = %v, want ErrOperand", name, a.Err())
		}

		code, err := a.Bytes()
		if !errors.Is(err, ErrOperand) {
			t.Errorf("%s: Bytes error = %v, want ErrOperand", name, err)
		}

		if code != nil {
			t.Errorf("%s: Bytes returned %d bytes alongside the error", name, len(code))
		}
	}
}

// TestFirstErrorWinsAndReset checks that the first recorded error is kept and
// that Reset returns the Assembler to a clean, reusable state.
func TestFirstErrorWinsAndReset(t *testing.T) {
	a := New()
	a.LslRI(X0, X1, 64)
	first := a.Err()
	a.AddRI(X0, X1, 0x1001)

	if _, err := a.Bytes(); err == nil || err != first {
		t.Errorf("Bytes error = %v, want the first recorded error %v", err, first)
	}

	l := a.NewLabel()
	a.B(l)
	a.Reset()

	if a.Len() != 0 || a.Err() != nil || a.LabelOffset(l) != -1 {
		t.Errorf("after Reset: Len=%d Err=%v LabelOffset=%d", a.Len(), a.Err(), a.LabelOffset(l))
	}

	a.Ret()

	if got := mustWords(t, a); len(got) != 1 || got[0] != wordRet {
		t.Errorf("after Reset: got %s, want %08x", formatWords(got), uint32(wordRet))
	}
}

// TestLenAndWord checks buffer accounting and the raw word emitter.
func TestLenAndWord(t *testing.T) {
	a := New()

	if a.Len() != 0 {
		t.Fatalf("new Assembler has Len %d", a.Len())
	}

	a.Word(0xDEADBEEF)
	a.Nop()

	code, err := a.Bytes()
	if err != nil {
		t.Fatal(err)
	}

	want := []byte{0xEF, 0xBE, 0xAD, 0xDE, 0x1F, 0x20, 0x03, 0xD5}
	if string(code) != string(want) || a.Len() != len(want) {
		t.Errorf("got % x (Len %d), want % x", code, a.Len(), want)
	}
}

// TestImmAddSubOK checks the add/subtract immediate predicate at its
// boundaries and that the emitters agree with it.
func TestImmAddSubOK(t *testing.T) {
	cases := map[uint32]bool{
		0: true, 1: true, 0xFFF: true, 0x1000: true, 0x2000: true, 0xFFF000: true, 0xABC000: true,
		0x1001: false, 0x1FFF: false, 0xFFF001: false, 0xFFF800: false, 0x1000000: false, 0x1001000: false,
		0x80000000: false, 0xFFFFFFFF: false, 0xFFFFF000: false,
	}

	for imm, want := range cases {
		if got := ImmAddSubOK(imm); got != want {
			t.Errorf("ImmAddSubOK(%#x) = %v, want %v", imm, got, want)
		}

		a := New()
		a.AddRI(X0, X1, imm)
		a.SubRI(X0, X1, imm)
		a.CmpRI(X1, imm)

		if _, err := a.Bytes(); (err == nil) != want {
			t.Errorf("emitters with %#x: error = %v, predicate says encodable = %v", imm, err, want)
		}
	}
}

// TestMemOffOK64 checks the 64-bit displacement predicate at its boundaries
// and that the emitters agree with it.
func TestMemOffOK64(t *testing.T) {
	cases := map[int32]bool{
		0: true, 8: true, 32760: true, -8: true, -256: true, 255: true, 1: true, -1: true, 256: true, 248: true,
		32768: false, 32764: false, 32761: false, -257: false, 257: false, 260: false, -264: false,
		1<<31 - 1: false, -1 << 31: false,
	}

	for off, want := range cases {
		if got := MemOffOK64(off); got != want {
			t.Errorf("MemOffOK64(%d) = %v, want %v", off, got, want)
		}

		a := New()
		a.LdrRM(X0, X1, off)
		a.StrRM(X0, X1, off)
		a.LdrDM(V0, X1, off)
		a.StrDM(V0, X1, off)

		if _, err := a.Bytes(); (err == nil) != want {
			t.Errorf("emitters with %d: error = %v, predicate says encodable = %v", off, err, want)
		}
	}
}

// TestCondNegate checks the pairing of the condition codes.
func TestCondNegate(t *testing.T) {
	pairs := [][2]Cond{
		{CondEQ, CondNE}, {CondHS, CondLO}, {CondMI, CondPL}, {CondVS, CondVC},
		{CondHI, CondLS}, {CondGE, CondLT}, {CondGT, CondLE},
	}

	for _, p := range pairs {
		if p[0].Negate() != p[1] || p[1].Negate() != p[0] {
			t.Errorf("Negate does not pair conditions %d and %d", p[0], p[1])
		}
	}

	if CondAL.Negate() != CondAL {
		t.Errorf("CondAL.Negate() = %d, want CondAL (documented as unchanged)", CondAL.Negate())
	}

	for i, want := range condNames {
		if Cond(i) > CondAL || want == "" {
			t.Errorf("condition table is inconsistent at %d", i)
		}
	}

	if CondEQ != 0 || CondNE != 1 || CondHS != 2 || CondLO != 3 || CondMI != 4 || CondPL != 5 || CondVS != 6 ||
		CondVC != 7 || CondHI != 8 || CondLS != 9 || CondGE != 10 || CondLT != 11 || CondGT != 12 || CondLE != 13 ||
		CondAL != 14 {
		t.Error("condition codes do not match their A64 encodings")
	}
}

// TestRegisterNumbers pins the exported register constants.
func TestRegisterNumbers(t *testing.T) {
	if X0 != 0 || X19 != 19 || X30 != 30 || XZR != 31 || SP != 31 {
		t.Error("general register constants do not match their numbers")
	}

	if V0 != 0 || V15 != 15 || V31 != 31 {
		t.Error("floating point register constants do not match their numbers")
	}
}

// TestNoAllocations checks that emitters do not allocate once the buffers
// have grown: a JIT calls them on its hot compile path.
func TestNoAllocations(t *testing.T) {
	a := New()

	emit := func() {
		a.Reset()

		l := a.NewLabel()

		a.MovRI(X0, 0x123456789ABCDEF0)
		a.AddRR(X1, X2, X3)
		a.AddRI(SP, SP, 16)
		a.LslRI(X1, X2, 3)
		a.LdrRM(X0, SP, 8)
		a.StrRM(X0, SP, -8)
		a.LdrRMIdx(X0, X1, X2, true)
		a.CmpRI(X0, 1)
		a.Bcond(CondEQ, l)
		a.Cset(X0, CondLT)
		a.FaddD(V0, V1, V2)
		a.LdrDM(V0, SP, 16)
		a.ScvtfDR(V0, X1)
		a.Bind(l)
		a.Cbz(X0, l)
		a.B(l)
		a.Ret()

		if _, err := a.Bytes(); err != nil {
			t.Fatal(err)
		}
	}

	emit() // grow the buffers once

	if allocs := testing.AllocsPerRun(100, emit); allocs != 0 {
		t.Errorf("emitters allocate %v times per run, want 0", allocs)
	}
}

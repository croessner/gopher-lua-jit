package arm64

import (
	"fmt"
	"math"
	"strings"
)

// caseTable collects golden cases.
type caseTable struct {
	cases []goldenCase
}

// add registers a case verified against the Go assembler.
func (t *caseTable) add(name, asm string, emit func(a *Assembler)) {
	t.cases = append(t.cases, goldenCase{name: name, asm: asm, emit: emit})
}

// addManual registers a case the Go assembler cannot express; words are
// derived by hand from the Arm ARM encoding tables. When these cases were
// written, each one was additionally assembled once with the LLVM assembler
// (clang -target arm64) and produced the same word; that check is not part of
// the test run.
func (t *caseTable) addManual(name string, words []uint32, emit func(a *Assembler)) {
	t.cases = append(t.cases, goldenCase{name: name, manual: words, emit: emit})
}

// goReg returns the Go assembler name of r where register 31 means XZR. The
// Go assembler renames R18 and R28 to protect the platform register and g.
func goReg(r Reg) string {
	switch r {
	case X18:
		return "R18_PLATFORM"
	case X28:
		return "g"
	case XZR:
		return "ZR"
	default:
		return fmt.Sprintf("R%d", r)
	}
}

// goRegSP returns the Go assembler name of r where register 31 means SP.
func goRegSP(r Reg) string {
	if r == SP {
		return "RSP"
	}

	return goReg(r)
}

// goF returns the Go assembler name of a floating point register.
func goF(v VReg) string {
	return fmt.Sprintf("F%d", v)
}

// condNames lists the Go assembler condition names by A64 encoding.
var condNames = [...]string{"EQ", "NE", "HS", "LO", "MI", "PL", "VS", "VC", "HI", "LS", "GE", "LT", "GT", "LE", "AL"}

// Operand sets shared by the case generators. They cover register 0, the
// callee-saved and special high registers, and 31 in every position.
var (
	regTriples = [][3]Reg{
		{X0, X0, X0}, {X1, X2, X3}, {X19, X20, X21}, {X30, X29, X28}, {X27, X26, X25}, {X18, X17, X16},
		{X15, X30, X0}, {X0, X15, X30}, {XZR, X1, X2}, {X1, XZR, X2}, {X1, X2, XZR}, {XZR, XZR, XZR},
	}
	regPairs = [][2]Reg{
		{X0, X0}, {X1, X2}, {X19, X30}, {X30, X19}, {X28, X18}, {X27, X29}, {XZR, X1}, {X1, XZR}, {XZR, XZR},
	}
	vregTriples = [][3]VReg{
		{V0, V0, V0}, {V1, V2, V3}, {V15, V15, V15}, {V31, V30, V29}, {V0, V15, V31}, {V31, V0, V15}, {V15, V31, V0},
	}
	vregPairs = [][2]VReg{
		{V0, V0}, {V1, V2}, {V15, V31}, {V31, V15}, {V31, V0}, {V0, V31}, {V15, V15}, {V31, V31},
	}
	// mixedPairs pairs a floating point register with a general register.
	mixedPairs = []struct {
		v VReg
		r Reg
	}{{V0, X0}, {V2, X1}, {V15, X19}, {V31, X30}, {V1, X28}, {V31, XZR}, {V0, XZR}}
	addSubImms = []uint32{0, 1, 2, 0x555, 0xFFE, 0xFFF, 0x1000, 0x2000, 0xABC000, 0xFFE000, 0xFFF000}
	shiftImms  = []uint8{0, 1, 2, 31, 32, 33, 62, 63}
)

// goldenCases builds the complete table of encoder cases.
func goldenCases() []goldenCase {
	t := &caseTable{}

	t.addRegisterOps()
	t.addMoveWide()
	t.addShiftImm()
	t.addAddSubImm()
	t.addCompare()
	t.addConditional()
	t.addMemory()
	t.addMemoryIndexed()
	t.addControl()
	t.addFloat()
	t.addFloatMemory()

	return t.cases
}

// addRegisterOps covers the integer instructions whose operands are all
// general registers (register 31 is XZR everywhere).
func (t *caseTable) addRegisterOps() {
	three := []struct {
		fn   func(a *Assembler, dst, n, m Reg)
		name string
		mnem string
	}{
		{(*Assembler).AddRR, "AddRR", "ADD"}, {(*Assembler).SubRR, "SubRR", "SUB"},
		{(*Assembler).AndRR, "AndRR", "AND"}, {(*Assembler).OrrRR, "OrrRR", "ORR"},
		{(*Assembler).EorRR, "EorRR", "EOR"}, {(*Assembler).AddsRR, "AddsRR", "ADDS"},
		{(*Assembler).SubsRR, "SubsRR", "SUBS"}, {(*Assembler).MulRR, "MulRR", "MUL"},
		{(*Assembler).SdivRR, "SdivRR", "SDIV"}, {(*Assembler).UdivRR, "UdivRR", "UDIV"},
		{(*Assembler).LslRR, "LslRR", "LSL"}, {(*Assembler).LsrRR, "LsrRR", "LSR"},
		{(*Assembler).AsrRR, "AsrRR", "ASR"},
	}

	// Go operand order is "OP Rm, Rn, Rd" for Rd = Rn OP Rm.
	for _, op := range three {
		for _, r := range regTriples {
			d, n, m := r[0], r[1], r[2]
			t.add(fmt.Sprintf("%s(%d,%d,%d)", op.name, d, n, m),
				fmt.Sprintf("%s %s, %s, %s", op.mnem, goReg(m), goReg(n), goReg(d)),
				func(a *Assembler) { op.fn(a, d, n, m) })
		}
	}

	two := []struct {
		fn   func(a *Assembler, dst, src Reg)
		name string
		mnem string
	}{
		{(*Assembler).MovRR, "MovRR", "MOVD"}, {(*Assembler).NegRR, "NegRR", "NEG"}, {(*Assembler).MvnRR, "MvnRR", "MVN"},
	}

	for _, op := range two {
		for _, r := range regPairs {
			d, m := r[0], r[1]
			t.add(fmt.Sprintf("%s(%d,%d)", op.name, d, m),
				fmt.Sprintf("%s %s, %s", op.mnem, goReg(m), goReg(d)),
				func(a *Assembler) { op.fn(a, d, m) })
		}
	}

	// Go operand order is "MSUB Rm, Ra, Rn, Rd" for Rd = Ra - Rn*Rm.
	quads := [][4]Reg{
		{X0, X0, X0, X0}, {X1, X2, X3, X4}, {X19, X20, X21, X22}, {X30, X29, X28, X27},
		{X1, X2, X3, XZR}, {XZR, X1, X2, X3}, {X1, XZR, X2, X3}, {X1, X2, XZR, X3},
	}
	for _, r := range quads {
		d, n, m, ra := r[0], r[1], r[2], r[3]
		t.add(fmt.Sprintf("MsubRRRR(%d,%d,%d,%d)", d, n, m, ra),
			fmt.Sprintf("MSUB %s, %s, %s, %s", goReg(m), goReg(ra), goReg(n), goReg(d)),
			func(a *Assembler) { a.MsubRRRR(d, n, m, ra) })
	}

	// CMP and TST: Go operand order is "CMP Rm, Rn".
	for _, r := range regPairs {
		n, m := r[0], r[1]
		t.add(fmt.Sprintf("CmpRR(%d,%d)", n, m), fmt.Sprintf("CMP %s, %s", goReg(m), goReg(n)),
			func(a *Assembler) { a.CmpRR(n, m) })
		t.add(fmt.Sprintf("TstRR(%d,%d)", n, m), fmt.Sprintf("TST %s, %s", goReg(m), goReg(n)),
			func(a *Assembler) { a.TstRR(n, m) })
	}
}

// movSeq builds the Go assembler text of an explicit move-wide sequence. Each
// step is a mnemonic (MOVZ, MOVN or MOVK), a 16-bit immediate and the index
// of the 16-bit chunk it targets.
func movSeq(reg string, steps ...[3]any) string {
	parts := make([]string, len(steps))
	for i, s := range steps {
		parts[i] = fmt.Sprintf("%s $(%#x<<%d), %s", s[0], s[1], s[2].(int)*16, reg)
	}

	return strings.Join(parts, "; ")
}

// addMoveWide covers MovRI. The Go assembler rejects MOVZ/MOVN/MOVK with a
// zero immediate, and its MOVD prefers ORR with a bitmask immediate where one
// exists, so each case picks the text that pins the expected sequence:
// explicit MOVZ/MOVN/MOVK steps written out by hand, or MOVD for constants
// that have no bitmask encoding (the Go assembler then expands MOVD to its own
// minimal move-wide sequence, an independent check of the selection logic).
func (t *caseTable) addMoveWide() {
	explicit := []struct {
		asm string
		imm uint64
		dst Reg
	}{
		{movSeq("R1", [3]any{"MOVZ", 1, 0}), 1, X1},
		{movSeq("R1", [3]any{"MOVZ", 0xFFFF, 0}), 0xFFFF, X1},
		{movSeq("R1", [3]any{"MOVZ", 1, 1}), 0x10000, X1},
		{movSeq("R1", [3]any{"MOVZ", 0xFFFF, 0}, [3]any{"MOVK", 0xFFFF, 1}), 0xFFFFFFFF, X1},
		{movSeq("R1", [3]any{"MOVZ", 1, 2}), 1 << 32, X1},
		{movSeq("R1", [3]any{"MOVZ", 0xDEF0, 0}, [3]any{"MOVK", 0x9ABC, 1}, [3]any{"MOVK", 0x5678, 2}, [3]any{"MOVK", 0x1234, 3}),
			0x123456789ABCDEF0, X1},
		{movSeq("R1", [3]any{"MOVZ", 0x8000, 3}), 1 << 63, X1},                                       // math.MinInt64
		{movSeq("R1", [3]any{"MOVN", 0x8000, 3}), math.MaxInt64, X1},                                 // 0x7FFF_FFFF_FFFF_FFFF
		{movSeq("R1", [3]any{"MOVN", 1, 0}), 0xFFFFFFFFFFFFFFFE, X1},                                 // -2
		{movSeq("R1", [3]any{"MOVN", 0xFFFF, 0}), 0xFFFFFFFFFFFF0000, X1},                            // -65536
		{movSeq("R1", [3]any{"MOVN", 0xFFFF, 3}), 0x0000FFFFFFFFFFFF, X1},                            // one zero chunk on top
		{movSeq("R1", [3]any{"MOVZ", 0xFFFF, 2}), 0x0000FFFF00000000, X1},                            // interior 0xFFFF chunk
		{movSeq("R1", [3]any{"MOVN", 0xA987, 0}, [3]any{"MOVK", 0x1234, 3}), 0x1234FFFFFFFF5678, X1}, // interior 0xFFFF chunks
		{movSeq("R1", [3]any{"MOVZ", 0x5678, 0}, [3]any{"MOVK", 0xFFFF, 1}, [3]any{"MOVK", 0x1234, 3}), 0x12340000FFFF5678, X1},
		{movSeq("R1", [3]any{"MOVZ", 1, 0}, [3]any{"MOVK", 0x8000, 3}), 0x8000000000000001, X1},
		{movSeq("R1", [3]any{"MOVZ", 1, 0}, [3]any{"MOVK", 1, 1}, [3]any{"MOVK", 1, 2}, [3]any{"MOVK", 1, 3}), 0x0001000100010001, X1},
		{movSeq("R1", [3]any{"MOVZ", 0xFFFE, 0}, [3]any{"MOVK", 0xFFFE, 1}, [3]any{"MOVK", 0xFFFE, 2}, [3]any{"MOVK", 0xFFFE, 3}),
			0xFFFEFFFEFFFEFFFE, X1},
		{movSeq("R1", [3]any{"MOVN", 1, 0}, [3]any{"MOVK", 0xFFFE, 1}, [3]any{"MOVK", 0xFFFE, 2}), 0xFFFFFFFEFFFEFFFE, X1},
		{movSeq("R0", [3]any{"MOVZ", 42, 0}), 42, X0},
		{movSeq("R30", [3]any{"MOVN", 41, 0}), 0xFFFFFFFFFFFFFFD6, X30}, // -42
		{movSeq("R19", [3]any{"MOVZ", 0x7FFF, 1}), 0x7FFF0000, X19},
		{movSeq("g", [3]any{"MOVZ", 0xBEEF, 0}, [3]any{"MOVK", 0xDEAD, 1}), 0xDEADBEEF, X28},
		{movSeq("ZR", [3]any{"MOVZ", 1, 0}), 1, XZR},
		// MOVD would encode the next two as ORR with a bitmask immediate
		// (plus MOVK), so their move-wide sequences are spelled out.
		{movSeq("R0", [3]any{"MOVZ", 2, 0}, [3]any{"MOVK", 0xFFFF, 1}, [3]any{"MOVK", 1, 2}), 0x00000001FFFF0002, X0},
		{movSeq("R19", [3]any{"MOVZ", 1, 0}, [3]any{"MOVK", 0xFFFF, 3}), 0xFFFF000000000001, X19},
		// -1 is MOVN #0, which only MOVD can express in Go assembler syntax.
		{"MOVD $-1, R1", 0xFFFFFFFFFFFFFFFF, X1},
		{"MOVD $-1, R30", 0xFFFFFFFFFFFFFFFF, X30},
	}

	for _, c := range explicit {
		t.add(fmt.Sprintf("MovRI(%d,%#x)", c.dst, c.imm), c.asm, func(a *Assembler) { a.MovRI(c.dst, int64(c.imm)) })
	}

	// Constants without a bitmask-immediate encoding, expanded by the Go
	// assembler itself. Several need a MOVK with a zero immediate after MOVN,
	// which explicit Go assembler text cannot express.
	viaMovd := []uint64{
		0x0123456789ABCDEF, 0xFEDCBA9876543210, 0x00000000DEADBEEF, 0xDEADBEEF00000000,
		0xFFFFFFFFDEADBEEF, 0x0000CAFE0000BABE, 0xFFFF1234FFFF5678, 0x1234FFFF5678FFFF,
		0xFFFF0000FFFF1234, 0xFFFFFFFF00001234, 0x12340000FFFFFFFF, 0xFFFF00001234FFFF,
		0x0000FFFF12340000, 0x0000000000012345, 0xFFFFFFFFFFFEDCBA, 0x7FFFFFFFFFFF1234,
		0x8000000000001234, 0x00000005FFFF0003, 0xFFFF000000001235, 0x00005678FFFF0000,
	}
	for i, imm := range viaMovd {
		dst := []Reg{X1, X0, X19, X30}[i%4]
		t.add(fmt.Sprintf("MovRI(%d,%#x)", dst, imm), fmt.Sprintf("MOVD $%#x, %s", imm, goReg(dst)),
			func(a *Assembler) { a.MovRI(dst, int64(imm)) })
	}

	// Zero is MOVZ Xd, #0 (0xD2800000 | Rd: sf=1, opc=10, 100101, hw=00,
	// imm16=0). The Go assembler rejects "MOVZ $0" and turns "MOVD $0" into
	// ORR Xd, XZR, XZR, so these words are derived from the Arm ARM move wide
	// immediate table (C4.1 "Data processing - immediate", MOVZ).
	for _, dst := range []Reg{X0, X1, X19, X30} {
		t.addManual(fmt.Sprintf("MovRI(%d,0x0)", dst), []uint32{0xD2800000 | uint32(dst)},
			func(a *Assembler) { a.MovRI(dst, 0) })
	}
}

// addShiftImm covers the immediate shift aliases of UBFM/SBFM.
func (t *caseTable) addShiftImm() {
	ops := []struct {
		fn   func(a *Assembler, dst, n Reg, shift uint8)
		name string
		mnem string
	}{
		{(*Assembler).LslRI, "LslRI", "LSL"}, {(*Assembler).LsrRI, "LsrRI", "LSR"}, {(*Assembler).AsrRI, "AsrRI", "ASR"},
	}
	pairs := [][2]Reg{{X0, X0}, {X1, X2}, {X30, X19}, {X19, X30}, {XZR, X1}, {X1, XZR}}

	for _, op := range ops {
		for _, r := range pairs {
			for _, shift := range shiftImms {
				d, n := r[0], r[1]
				t.add(fmt.Sprintf("%s(%d,%d,%d)", op.name, d, n, shift),
					fmt.Sprintf("%s $%d, %s, %s", op.mnem, shift, goReg(n), goReg(d)),
					func(a *Assembler) { op.fn(a, d, n, shift) })
			}
		}
	}
}

// addAddSubImm covers the add/subtract immediate instructions, where
// register 31 is SP for the source and, without flag setting, the destination.
func (t *caseTable) addAddSubImm() {
	plain := []struct {
		fn   func(a *Assembler, dst, n Reg, imm uint32)
		name string
		mnem string
	}{
		// The Go assembler tracks ADD/SUB of a constant into RSP as a stack
		// adjustment and aborts ("overflow in spadj") once the running total
		// of the reference function would shrink the frame below zero. SubRI
		// therefore has to come first: its SP cases grow the frame by exactly
		// what the identical AddRI cases release afterwards.
		{(*Assembler).SubRI, "SubRI", "SUB"}, {(*Assembler).AddRI, "AddRI", "ADD"},
	}
	pairs := [][2]Reg{{X0, X0}, {X1, X2}, {X30, X19}, {X19, X30}, {X1, SP}, {SP, X1}, {SP, SP}}

	for _, op := range plain {
		for _, r := range pairs {
			for _, imm := range addSubImms {
				d, n := r[0], r[1]

				t.add(fmt.Sprintf("%s(%d,%d,%#x)", op.name, d, n, imm),
					fmt.Sprintf("%s $%d, %s, %s", op.mnem, imm, goRegSP(n), goRegSP(d)),
					func(a *Assembler) { op.fn(a, d, n, imm) })
			}
		}
	}

	flags := []struct {
		fn    func(a *Assembler, dst, n Reg, imm uint32)
		name  string
		mnem  string
		alias string
	}{
		{(*Assembler).AddsRI, "AddsRI", "ADDS", "CMN"}, {(*Assembler).SubsRI, "SubsRI", "SUBS", "CMP"},
	}
	flagPairs := [][2]Reg{{X0, X0}, {X1, X2}, {X30, X19}, {X3, SP}, {XZR, X1}, {XZR, SP}}

	for _, op := range flags {
		for _, r := range flagPairs {
			for _, imm := range addSubImms {
				d, n := r[0], r[1]

				// The Go assembler has no "ADDS $imm, Rn, ZR"; with XZR as the
				// destination the instruction is its CMN/CMP alias.
				text := fmt.Sprintf("%s $%d, %s, %s", op.mnem, imm, goRegSP(n), goReg(d))
				if d == XZR {
					text = fmt.Sprintf("%s $%d, %s", op.alias, imm, goRegSP(n))
				}

				t.add(fmt.Sprintf("%s(%d,%d,%#x)", op.name, d, n, imm), text, func(a *Assembler) { op.fn(a, d, n, imm) })
			}
		}
	}
}

// addCompare covers the compare-with-immediate aliases (register 31 is SP).
func (t *caseTable) addCompare() {
	for _, n := range []Reg{X0, X1, X19, X28, X30, SP} {
		for _, imm := range addSubImms {
			t.add(fmt.Sprintf("CmpRI(%d,%#x)", n, imm), fmt.Sprintf("CMP $%d, %s", imm, goRegSP(n)),
				func(a *Assembler) { a.CmpRI(n, imm) })
			t.add(fmt.Sprintf("CmnRI(%d,%#x)", n, imm), fmt.Sprintf("CMN $%d, %s", imm, goRegSP(n)),
				func(a *Assembler) { a.CmnRI(n, imm) })
		}
	}
}

// addConditional covers Cset and Csel for every condition code.
func (t *caseTable) addConditional() {
	dsts := []Reg{X0, X1, X19, X30, XZR}

	// CSET has no AL form (see the encoder error tests).
	for c := CondEQ; c < CondAL; c++ {
		for _, d := range dsts {
			t.add(fmt.Sprintf("Cset(%d,%s)", d, condNames[c]), fmt.Sprintf("CSET %s, %s", condNames[c], goReg(d)),
				func(a *Assembler) { a.Cset(d, c) })
		}
	}

	// Go operand order is "CSEL cond, Rn, Rm, Rd".
	triples := [][3]Reg{{X0, X0, X0}, {X1, X2, X3}, {X19, X30, X28}, {XZR, X1, X2}, {X1, XZR, X2}, {X1, X2, XZR}}

	for c := CondEQ; c <= CondAL; c++ {
		for _, r := range triples {
			d, n, m := r[0], r[1], r[2]
			t.add(fmt.Sprintf("Csel(%d,%d,%d,%s)", d, n, m, condNames[c]),
				fmt.Sprintf("CSEL %s, %s, %s, %s", condNames[c], goReg(n), goReg(m), goReg(d)),
				func(a *Assembler) { a.Csel(d, n, m, c) })
		}
	}
}

// memRef formats a Go assembler base+displacement operand.
func memRef(base Reg, off int32) string {
	return fmt.Sprintf("%d(%s)", off, goRegSP(base))
}

// addMemory covers the integer base+displacement loads and stores at every
// boundary of the scaled and unscaled addressing forms.
func (t *caseTable) addMemory() {
	ops := []struct {
		fn    func(a *Assembler, rt, base Reg, off int32)
		name  string
		mnem  string
		offs  []int32
		store bool
	}{
		{(*Assembler).LdrRM, "LdrRM", "MOVD", offsets64, false},
		{(*Assembler).StrRM, "StrRM", "MOVD", offsets64, true},
		{(*Assembler).LdrRM32, "LdrRM32", "MOVWU", offsets32, false},
		{(*Assembler).StrRM32, "StrRM32", "MOVW", offsets32, true},
		{(*Assembler).LdrbRM, "LdrbRM", "MOVBU", offsets8, false},
	}
	pairs := [][2]Reg{{X0, X0}, {X1, X2}, {X30, X19}, {X19, X30}, {X28, SP}, {XZR, X1}}

	for _, op := range ops {
		for _, r := range pairs {
			for _, off := range op.offs {
				rt, base := r[0], r[1]

				text := fmt.Sprintf("%s %s, %s", op.mnem, memRef(base, off), goReg(rt))
				if op.store {
					text = fmt.Sprintf("%s %s, %s", op.mnem, goReg(rt), memRef(base, off))
				}

				t.add(fmt.Sprintf("%s(%d,%d,%d)", op.name, rt, base, off), text, func(a *Assembler) { op.fn(a, rt, base, off) })
			}
		}
	}
}

// Displacements at the boundaries of each addressing form: the first and
// last scaled offsets, the unscaled range limits, and unaligned values that
// force the unscaled form.
var (
	offsets64 = []int32{0, 8, 16, 248, 256, 264, 32752, 32760, -8, -256, -255, -1, 1, 7, 9, 12, 255}
	offsets32 = []int32{0, 4, 8, 252, 256, 16376, 16380, -4, -256, -1, 1, 2, 3, 254, 255}
	offsets8  = []int32{0, 1, 2, 255, 256, 4094, 4095, -1, -2, -255, -256}
)

// addMemoryIndexed covers the integer base+index loads and stores.
func (t *caseTable) addMemoryIndexed() {
	for _, r := range indexTriples {
		for _, scaled := range []bool{false, true} {
			rt, base, index := r[0], r[1], r[2]
			ref := indexRef(base, index, scaled)

			t.add(fmt.Sprintf("LdrRMIdx(%d,%d,%d,%v)", rt, base, index, scaled), fmt.Sprintf("MOVD %s, %s", ref, goReg(rt)),
				func(a *Assembler) { a.LdrRMIdx(rt, base, index, scaled) })
			t.add(fmt.Sprintf("StrRMIdx(%d,%d,%d,%v)", rt, base, index, scaled), fmt.Sprintf("MOVD %s, %s", goReg(rt), ref),
				func(a *Assembler) { a.StrRMIdx(rt, base, index, scaled) })
		}
	}
}

// indexTriples lists (transfer register, base, index) combinations; the
// transfer register number is reused for the floating point variants.
var indexTriples = [][3]Reg{
	{X0, X0, X0}, {X1, X2, X3}, {X30, X19, X20}, {X19, SP, X30}, {X15, X29, X28}, {X1, X2, XZR}, {XZR, X1, X2},
}

// indexRef formats a Go assembler base+index operand.
func indexRef(base, index Reg, scaled bool) string {
	if scaled {
		return fmt.Sprintf("(%s)(%s<<3)", goRegSP(base), goReg(index))
	}

	return fmt.Sprintf("(%s)(%s)", goRegSP(base), goReg(index))
}

// addControl covers branches, system instructions and label references. The
// Go assembler addresses branch targets as "N(PC)" in instructions relative to
// the branch, so every case is self-contained.
func (t *caseTable) addControl() {
	t.add("Ret()", "RET", func(a *Assembler) { a.Ret() })
	t.add("Nop()", "NOOP", func(a *Assembler) { a.Nop() })

	for _, imm := range []uint16{0, 1, 0x1234, 0x8000, 0xFFFF} {
		t.add(fmt.Sprintf("Brk(%#x)", imm), fmt.Sprintf("BRK $%d", imm), func(a *Assembler) { a.Brk(imm) })
	}

	for _, r := range []Reg{X0, X1, X3, X16, X17, X19, X30} {
		t.add(fmt.Sprintf("Br(%d)", r), fmt.Sprintf("JMP (%s)", goReg(r)), func(a *Assembler) { a.Br(r) })
	}

	t.addBranchShapes("B()", "B", func(a *Assembler, l Label) { a.B(l) })

	// B.AL is missing from the Go assembler and is checked by hand below.
	for c := CondEQ; c < CondAL; c++ {
		t.addBranchShapes(fmt.Sprintf("Bcond(%s)", condNames[c]), "B"+condNames[c], func(a *Assembler, l Label) { a.Bcond(c, l) })
	}

	for _, r := range []Reg{X0, X1, X19, X30, XZR} {
		t.addBranchShapes(fmt.Sprintf("Cbz(%d)", r), "CBZ "+goReg(r)+",", func(a *Assembler, l Label) { a.Cbz(r, l) })
		t.addBranchShapes(fmt.Sprintf("Cbnz(%d)", r), "CBNZ "+goReg(r)+",", func(a *Assembler, l Label) { a.Cbnz(r, l) })
	}

	// B.AL to itself: 0x54000000 | imm19<<5 | cond with imm19=0 and
	// cond=0b1110 (Arm ARM "Conditional branch (immediate)", B.cond).
	t.addManual("Bcond(AL)/self", []uint32{0x5400000E}, func(a *Assembler) {
		l := a.NewLabel()
		a.Bind(l)
		a.Bcond(CondAL, l)
	})
	// B.AL two instructions forward: imm19=2.
	t.addManual("Bcond(AL)/forward", []uint32{0x5400004E, wordNop}, func(a *Assembler) {
		l := a.NewLabel()
		a.Bcond(CondAL, l)
		a.Nop()
		a.Bind(l)
	})
}

// addBranchShapes registers a branch to itself, a forward branch over one
// NOP and a backward branch over two NOPs for the branch instruction that
// prefix names in Go assembler syntax.
func (t *caseTable) addBranchShapes(name, prefix string, branch func(a *Assembler, l Label)) {
	t.add(name+"/self", prefix+" 0(PC)", func(a *Assembler) {
		l := a.NewLabel()
		a.Bind(l)
		branch(a, l)
	})
	t.add(name+"/forward", prefix+" 2(PC); NOOP", func(a *Assembler) {
		l := a.NewLabel()
		branch(a, l)
		a.Nop()
		a.Bind(l)
	})
	t.add(name+"/backward", "NOOP; NOOP; "+prefix+" -2(PC)", func(a *Assembler) {
		l := a.NewLabel()
		a.Bind(l)
		a.Nop()
		a.Nop()
		branch(a, l)
	})
}

// addFloat covers the scalar double register instructions.
func (t *caseTable) addFloat() {
	three := []struct {
		fn   func(a *Assembler, dst, n, m VReg)
		name string
		mnem string
	}{
		{(*Assembler).FaddD, "FaddD", "FADDD"}, {(*Assembler).FsubD, "FsubD", "FSUBD"},
		{(*Assembler).FmulD, "FmulD", "FMULD"}, {(*Assembler).FdivD, "FdivD", "FDIVD"},
	}

	// Go operand order is "OP Fm, Fn, Fd" for Fd = Fn OP Fm.
	for _, op := range three {
		for _, r := range vregTriples {
			d, n, m := r[0], r[1], r[2]
			t.add(fmt.Sprintf("%s(%d,%d,%d)", op.name, d, n, m),
				fmt.Sprintf("%s %s, %s, %s", op.mnem, goF(m), goF(n), goF(d)),
				func(a *Assembler) { op.fn(a, d, n, m) })
		}
	}

	two := []struct {
		fn   func(a *Assembler, dst, src VReg)
		name string
		mnem string
	}{
		{(*Assembler).FmovDD, "FmovDD", "FMOVD"}, {(*Assembler).FsqrtD, "FsqrtD", "FSQRTD"},
		{(*Assembler).FabsD, "FabsD", "FABSD"}, {(*Assembler).FnegD, "FnegD", "FNEGD"},
		{(*Assembler).FrintmD, "FrintmD", "FRINTMD"}, {(*Assembler).FrintpD, "FrintpD", "FRINTPD"},
		{(*Assembler).FrintzD, "FrintzD", "FRINTZD"},
	}

	for _, op := range two {
		for _, r := range vregPairs {
			d, s := r[0], r[1]
			t.add(fmt.Sprintf("%s(%d,%d)", op.name, d, s), fmt.Sprintf("%s %s, %s", op.mnem, goF(s), goF(d)),
				func(a *Assembler) { op.fn(a, d, s) })
		}
	}

	// Go operand order is "FCMPD Fm, Fn" for fcmp dn, dm.
	for _, r := range vregPairs {
		n, m := r[0], r[1]
		t.add(fmt.Sprintf("FcmpDD(%d,%d)", n, m), fmt.Sprintf("FCMPD %s, %s", goF(m), goF(n)),
			func(a *Assembler) { a.FcmpDD(n, m) })
	}

	for _, p := range mixedPairs {
		v, r := p.v, p.r
		t.add(fmt.Sprintf("FmovDR(%d,%d)", v, r), fmt.Sprintf("FMOVD %s, %s", goReg(r), goF(v)),
			func(a *Assembler) { a.FmovDR(v, r) })
		t.add(fmt.Sprintf("FmovRD(%d,%d)", r, v), fmt.Sprintf("FMOVD %s, %s", goF(v), goReg(r)),
			func(a *Assembler) { a.FmovRD(r, v) })
		t.add(fmt.Sprintf("ScvtfDR(%d,%d)", v, r), fmt.Sprintf("SCVTFD %s, %s", goReg(r), goF(v)),
			func(a *Assembler) { a.ScvtfDR(v, r) })
		t.add(fmt.Sprintf("FcvtzsRD(%d,%d)", r, v), fmt.Sprintf("FCVTZSD %s, %s", goF(v), goReg(r)),
			func(a *Assembler) { a.FcvtzsRD(r, v) })

		// FCVTMS (scalar, integer) is not implemented by the Go assembler
		// (its arm64enc.s test data lists it as TODO). The word is derived
		// from the Arm ARM "Conversion between floating-point and integer"
		// table: sf=1, 0, S=0, 11110, ftype=01, 1, rmode=10, opcode=000,
		// 000000, Rn, Rd = 0x9E700000 | Rn<<5 | Rd. The same layout with
		// rmode=11 is FCVTZS (0x9E780000), which the golden file confirms.
		t.addManual(fmt.Sprintf("FcvtmsRD(%d,%d)", r, v), []uint32{0x9E700000 | uint32(v)<<5 | uint32(r)},
			func(a *Assembler) { a.FcvtmsRD(r, v) })
	}

	// The Go assembler test data documents "FCVTMS F14, R19" as d301709e;
	// keep that independently published encoding as a fixed anchor.
	t.addManual("FcvtmsRD(19,14)/published", []uint32{0x9E7001D3}, func(a *Assembler) { a.FcvtmsRD(X19, V14) })
}

// addFloatMemory covers the scalar double loads and stores.
func (t *caseTable) addFloatMemory() {
	pairs := []struct {
		v    VReg
		base Reg
	}{{V0, X0}, {V1, X2}, {V15, X19}, {V31, X30}, {V31, SP}, {V0, SP}}

	for _, p := range pairs {
		for _, off := range offsets64 {
			v, base := p.v, p.base

			t.add(fmt.Sprintf("LdrDM(%d,%d,%d)", v, base, off), fmt.Sprintf("FMOVD %s, %s", memRef(base, off), goF(v)),
				func(a *Assembler) { a.LdrDM(v, base, off) })
			t.add(fmt.Sprintf("StrDM(%d,%d,%d)", v, base, off), fmt.Sprintf("FMOVD %s, %s", goF(v), memRef(base, off)),
				func(a *Assembler) { a.StrDM(v, base, off) })
		}
	}

	for _, r := range indexTriples {
		for _, scaled := range []bool{false, true} {
			v, base, index := VReg(r[0]), r[1], r[2]
			ref := indexRef(base, index, scaled)

			t.add(fmt.Sprintf("LdrDMIdx(%d,%d,%d,%v)", v, base, index, scaled), fmt.Sprintf("FMOVD %s, %s", ref, goF(v)),
				func(a *Assembler) { a.LdrDMIdx(v, base, index, scaled) })
			t.add(fmt.Sprintf("StrDMIdx(%d,%d,%d,%v)", v, base, index, scaled), fmt.Sprintf("FMOVD %s, %s", goF(v), ref),
				func(a *Assembler) { a.StrDMIdx(v, base, index, scaled) })
		}
	}
}

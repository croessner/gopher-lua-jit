package amd64

import (
	"fmt"
	"math"
	"strings"
)

// This file builds the golden case table: every encoder method with operand
// combinations that exercise each REX bit, the ModRM/SIB special cases and the
// immediate/displacement width boundaries.
//
// The name tables below are keyed by the exported constants on purpose: the
// Plan 9 text of a case is derived from the constant's name, the encoder
// output from its numeric value, so a mislabeled constant cannot agree with
// the Go assembler by accident (TestRegisterNumbers pins the numbers too).

// regP9 maps registers to their Go assembler names.
var regP9 = map[Reg]string{
	RAX: "AX", RCX: "CX", RDX: "DX", RBX: "BX", RSP: "SP", RBP: "BP", RSI: "SI", RDI: "DI",
	R8: "R8", R9: "R9", R10: "R10", R11: "R11", R12: "R12", R13: "R13", R14: "R14", R15: "R15",
}

// regIntel maps registers to their Intel names, used in case names.
var regIntel = map[Reg]string{
	RAX: "rax", RCX: "rcx", RDX: "rdx", RBX: "rbx", RSP: "rsp", RBP: "rbp", RSI: "rsi", RDI: "rdi",
	R8: "r8", R9: "r9", R10: "r10", R11: "r11", R12: "r12", R13: "r13", R14: "r14", R15: "r15",
}

// xregP9 maps SSE registers to their Go assembler names.
var xregP9 = map[XReg]string{
	X0: "X0", X1: "X1", X2: "X2", X3: "X3", X4: "X4", X5: "X5", X6: "X6", X7: "X7",
	X8: "X8", X9: "X9", X10: "X10", X11: "X11", X12: "X12", X13: "X13", X14: "X14", X15: "X15",
}

// condP9 maps condition codes to the Go assembler mnemonic suffix shared by
// Jcc, SETcc and CMOVQcc.
var condP9 = map[Cond]string{
	CondO: "OS", CondNO: "OC", CondB: "CS", CondAE: "CC", CondE: "EQ", CondNE: "NE", CondBE: "LS", CondA: "HI",
	CondS: "MI", CondNS: "PL", CondP: "PS", CondNP: "PC", CondL: "LT", CondGE: "GE", CondLE: "LE", CondG: "GT",
}

// condIntel maps condition codes to Intel suffixes, used in case names.
var condIntel = map[Cond]string{
	CondO: "o", CondNO: "no", CondB: "b", CondAE: "ae", CondE: "e", CondNE: "ne", CondBE: "be", CondA: "a",
	CondS: "s", CondNS: "ns", CondP: "p", CondNP: "np", CondL: "l", CondGE: "ge", CondLE: "le", CondG: "g",
}

var (
	allRegs = []Reg{RAX, RCX, RDX, RBX, RSP, RBP, RSI, RDI, R8, R9, R10, R11, R12, R13, R14, R15}
	allX    = []XReg{X0, X1, X2, X3, X4, X5, X6, X7, X8, X9, X10, X11, X12, X13, X14, X15}
	allCond = []Cond{
		CondO, CondNO, CondB, CondAE, CondE, CondNE, CondBE, CondA,
		CondS, CondNS, CondP, CondNP, CondL, CondGE, CondLE, CondG,
	}

	// someRegs covers RAX (short accumulator forms in cmd/asm), the registers
	// with ModRM/SIB special meaning and both halves of the REX range.
	someRegs = []Reg{RAX, RCX, RSP, RBP, RDI, R8, R12, R13, R15}

	// regPairs are (dst, src) pairs covering low/low, low/high, high/low and
	// high/high as well as asymmetric pairs that expose a swapped ModRM.
	regPairs = [][2]Reg{
		{RAX, RAX}, {RAX, RCX}, {RCX, RAX}, {RDX, RBX}, {RSP, RBP}, {RBP, RSP},
		{RSI, RDI}, {RDI, RSI}, {RAX, R8}, {R8, RAX}, {R9, R10}, {R12, R13},
		{R13, R12}, {R15, R14}, {RSP, R12}, {R13, RBP}, {R11, RBX}, {RDI, R15},
	}

	// xPairs are (dst, src) SSE register pairs with the same coverage goals.
	xPairs = [][2]XReg{
		{X0, X0}, {X0, X1}, {X1, X0}, {X2, X3}, {X7, X4}, {X0, X8},
		{X8, X0}, {X9, X10}, {X15, X14}, {X12, X13}, {X13, X5}, {X6, X15},
	}

	// immBoundary holds imm8/imm32 boundary values. The first half fits in a
	// sign-extended byte, the second half does not, so index i and i+5 always
	// select different immediate widths.
	immBoundary = []int32{0, 1, -1, 127, -128, 128, -129, 0x12345678, math.MinInt32, math.MaxInt32}
)

// caseList collects golden cases and drops exact duplicates produced by
// overlapping operand sets.
type caseList struct {
	cases []goldenCase
	names map[string]bool
}

// add appends a case verified against the Go assembler.
func (l *caseList) add(name, asm string, emit func(a *Assembler)) {
	l.append(goldenCase{name: name, asm: asm, emit: emit})
}

// addHand appends a case verified against hand-derived bytes.
func (l *caseList) addHand(name, hand, disasm string, emit func(a *Assembler)) {
	l.append(goldenCase{name: name, hand: hand, disasm: disasm, emit: emit})
}

// append adds c unless a case of the same name already exists.
func (l *caseList) append(c goldenCase) {
	if l.names == nil {
		l.names = make(map[string]bool)
	}

	if l.names[c.name] {
		return
	}

	l.names[c.name] = true
	l.cases = append(l.cases, c)
}

// goldenCases returns the complete golden case table.
func goldenCases() []goldenCase {
	var l caseList

	l.addMisc()
	l.addMovRI()
	l.addRegReg()
	l.addRegImm()
	l.addUnaryAndShifts()
	l.addConditional()
	l.addRegMem()
	l.addMemImm()
	l.addBranches()
	l.addSSE()

	return l.cases
}

// memP9 renders a memory operand in Go assembler syntax.
func memP9(m Mem) string {
	s := fmt.Sprintf("%d(%s)", m.Disp, regP9[m.Base])
	if m.Scale != 0 {
		s += fmt.Sprintf("(%s*%d)", regP9[m.Index], m.Scale)
	}

	return s
}

// memIntel renders a memory operand in Intel syntax for case names.
func memIntel(m Mem) string {
	s := "[" + regIntel[m.Base]
	if m.Scale != 0 {
		s += fmt.Sprintf("+%s*%d", regIntel[m.Index], m.Scale)
	}

	if m.Disp != 0 {
		s += fmt.Sprintf("%+d", m.Disp)
	}

	return s + "]"
}

// p9Operands joins two operands in Go assembler order. Most instructions are
// written "OP src, dst"; comparisons are written "CMP dst, src".
func p9Operands(dstFirst bool, dst, src string) string {
	if dstFirst {
		return dst + ", " + src
	}

	return src + ", " + dst
}

// coreMems is the memory operand set applied to every memory-taking method.
func coreMems() []Mem {
	return []Mem{
		M(RAX, 0), M(RCX, 8), M(RDX, -8), M(RBX, 0x100),
		M(RSP, 0), M(RSP, 8), M(RSP, 0x1000),
		M(RBP, 0), M(RBP, -16), M(RSI, 127), M(RDI, -128),
		M(R8, 0), M(R9, 128), M(R10, -129), M(R11, math.MaxInt32),
		M(R12, 0), M(R12, -8), M(R13, 0), M(R13, 0x200), M(R14, 16), M(R15, math.MinInt32),
		MIdx(RAX, RCX, 1, 0), MIdx(RDX, RBX, 2, 8), MIdx(RSI, RDI, 4, -8), MIdx(RBX, RBP, 8, 0x400),
		MIdx(RSP, RAX, 1, 0), MIdx(RSP, R15, 8, 16), MIdx(RBP, RSI, 2, 0), MIdx(R13, R12, 4, 0),
		MIdx(R12, R13, 8, -0x400), MIdx(R8, R9, 1, 0), MIdx(RAX, R10, 2, 4), MIdx(R11, RDX, 4, -4),
		MIdx(R14, R14, 8, 0x7f), MIdx(R15, R8, 1, 0x80), MIdx(RCX, RBP, 1, -0x81), MIdx(RDI, R12, 2, 0),
	}
}

// fullMems is the exhaustive memory operand set applied to a few methods that
// stand for the distinct instruction shapes (plain, with immediate, with
// mandatory prefix).
func fullMems() []Mem {
	ms := coreMems()

	// Every base register at each displacement width boundary.
	for _, b := range allRegs {
		for _, d := range []int32{0, 127, -128, 128, -129} {
			ms = append(ms, M(b, d))
		}
	}

	// Further displacements on the bases with special ModRM/SIB encodings.
	for _, b := range []Reg{RSP, RBP, R12, R13} {
		for _, d := range []int32{8, -8, 0x12345678, math.MinInt32, math.MaxInt32} {
			ms = append(ms, M(b, d))
		}
	}

	// Special bases combined with special index registers at every scale.
	disps := []int32{0, 0x7f, 0x80}

	for bi, b := range []Reg{RAX, RSP, RBP, R12, R13, R15} {
		for ii, idx := range []Reg{RCX, RBP, R8, R12, R13} {
			for si, scale := range []uint8{1, 2, 4, 8} {
				ms = append(ms, MIdx(b, idx, scale, disps[(bi+ii+si)%len(disps)]))
			}
		}
	}

	return ms
}

// leaMems is the full base x index matrix with rotating scale and
// displacement, applied to Lea.
func leaMems() []Mem {
	ms := coreMems()
	scales := []uint8{1, 2, 4, 8}
	disps := []int32{0, 0x40, -0x400}

	for bi, b := range allRegs {
		for ii, idx := range allRegs {
			if idx == RSP {
				continue
			}

			ms = append(ms, MIdx(b, idx, scales[(bi+ii)%len(scales)], disps[(bi+2*ii)%len(disps)]))
		}
	}

	return ms
}

// addMisc adds the operand-less instructions.
func (l *caseList) addMisc() {
	l.add("Ret", "RET", func(a *Assembler) { a.Ret() })
	l.add("Ud2", "UD2", func(a *Assembler) { a.Ud2() })
	l.add("Cqo", "CQO", func(a *Assembler) { a.Cqo() })

	// cmd/asm has no mnemonic for the one-byte breakpoint: "INT $3" assembles
	// to the two-byte CD 03. The dedicated encoding is opcode CC (Intel SDM
	// "INT3"), verified by hand.
	l.addHand("Int3", "cc", "INT $0x3", func(a *Assembler) { a.Int3() })

	// cmd/asm treats NOP as a pseudo-instruction that emits no code, so the
	// one-byte NOP (opcode 90, Intel SDM "NOP") is verified by hand.
	l.addHand("Nop", "90", "NOPL", func(a *Assembler) { a.Nop() })
}

// movRIP9 returns the Plan 9 instruction that selects the encoding MovRI is
// specified to use for imm. cmd/asm encodes "MOVQ $imm" for small positive
// values as REX.W C7 /0, so the zero-extending form is requested with MOVL.
func movRIP9(dst Reg, imm int64) string {
	switch {
	case imm >= 0 && imm <= math.MaxUint32:
		return fmt.Sprintf("MOVL $%d, %s", imm, regP9[dst])
	case imm >= math.MinInt32 && imm < 0:
		return fmt.Sprintf("MOVQ $%d, %s", imm, regP9[dst])
	default:
		return fmt.Sprintf("MOVQ $0x%x, %s", uint64(imm), regP9[dst])
	}
}

// addMovRI adds MovRI at each of its three encodings and their boundaries.
func (l *caseList) addMovRI() {
	imms := []int64{
		0, 1, 0x7f, 0x80, math.MaxInt32, 1 << 31, math.MaxUint32, // mov r32, imm32
		-1, -128, math.MinInt32, // mov r64, simm32
		1 << 32, 0x123456789abcdef0, math.MaxInt64, math.MinInt32 - 1, -(1 << 32), math.MinInt64, // movabs
	}

	for _, r := range allRegs {
		for _, imm := range imms {
			l.add(fmt.Sprintf("MovRI/%s,%#x", regIntel[r], uint64(imm)), movRIP9(r, imm),
				func(a *Assembler) { a.MovRI(r, imm) })
		}
	}
}

// addRegReg adds the general purpose register-register instructions.
func (l *caseList) addRegReg() {
	for _, dst := range allRegs {
		for _, src := range allRegs {
			l.add(fmt.Sprintf("MovRR/%s,%s", regIntel[dst], regIntel[src]),
				fmt.Sprintf("MOVQ %s, %s", regP9[src], regP9[dst]),
				func(a *Assembler) { a.MovRR(dst, src) })
		}
	}

	ops := []struct {
		name     string
		mnem     string
		dstFirst bool
		fn       func(a *Assembler, dst, src Reg)
	}{
		{"AddRR", "ADDQ", false, (*Assembler).AddRR},
		{"SubRR", "SUBQ", false, (*Assembler).SubRR},
		{"AndRR", "ANDQ", false, (*Assembler).AndRR},
		{"OrRR", "ORQ", false, (*Assembler).OrRR},
		{"XorRR", "XORQ", false, (*Assembler).XorRR},
		{"CmpRR", "CMPQ", true, (*Assembler).CmpRR},
		{"TestRR", "TESTQ", false, (*Assembler).TestRR},
		{"ImulRR", "IMULQ", false, (*Assembler).ImulRR},
		{"MovzxRR8", "MOVBLZX", false, (*Assembler).MovzxRR8},
	}

	for _, op := range ops {
		for _, p := range regPairs {
			dst, src := p[0], p[1]
			l.add(fmt.Sprintf("%s/%s,%s", op.name, regIntel[dst], regIntel[src]),
				op.mnem+" "+p9Operands(op.dstFirst, regP9[dst], regP9[src]),
				func(a *Assembler) { op.fn(a, dst, src) })
		}
	}

	// Every byte-register source of movzx, in particular SPL/BPL/SIL/DIL.
	for i, src := range allRegs {
		dst := allRegs[(i+5)%len(allRegs)]
		l.add(fmt.Sprintf("MovzxRR8/%s,%s", regIntel[dst], regIntel[src]),
			fmt.Sprintf("MOVBLZX %s, %s", regP9[src], regP9[dst]),
			func(a *Assembler) { a.MovzxRR8(dst, src) })
	}

	for _, p := range regPairs {
		dst, src := p[0], p[1]

		for _, imm := range immBoundary {
			l.add(fmt.Sprintf("ImulRRI/%s,%s,%d", regIntel[dst], regIntel[src], imm),
				fmt.Sprintf("IMUL3Q $%d, %s, %s", imm, regP9[src], regP9[dst]),
				func(a *Assembler) { a.ImulRRI(dst, src, imm) })
		}
	}
}

// le32 renders v as four little-endian hex bytes.
func le32(v int32) string {
	u := uint32(v)

	return fmt.Sprintf("%02x %02x %02x %02x", byte(u), byte(u>>8), byte(u>>16), byte(u>>24))
}

// disasmImm renders an immediate the way the Go disassembler prints it.
func disasmImm(v int32) string {
	if v < 0 {
		return fmt.Sprintf("$-0x%x", -int64(v))
	}

	return fmt.Sprintf("$0x%x", v)
}

// addRegImm adds the register-immediate arithmetic instructions.
func (l *caseList) addRegImm() {
	// digit is the ModRM.reg opcode extension of the group-1 instruction as
	// listed in the Intel SDM ("ADD r/m64, imm32" is REX.W + 81 /0 id, etc.).
	ops := []struct {
		name     string
		mnem     string
		dstFirst bool
		digit    byte
		fn       func(a *Assembler, dst Reg, imm int32)
	}{
		{"AddRI", "ADDQ", false, 0, (*Assembler).AddRI},
		{"OrRI", "ORQ", false, 1, (*Assembler).OrRI},
		{"AndRI", "ANDQ", false, 4, (*Assembler).AndRI},
		{"SubRI", "SUBQ", false, 5, (*Assembler).SubRI},
		{"XorRI", "XORQ", false, 6, (*Assembler).XorRI},
		{"CmpRI", "CMPQ", true, 7, (*Assembler).CmpRI},
	}

	for _, op := range ops {
		for _, r := range someRegs {
			for _, imm := range immBoundary {
				name := fmt.Sprintf("%s/%s,%d", op.name, regIntel[r], imm)
				emit := func(a *Assembler) { op.fn(a, r, imm) }

				// For RAX with an immediate that needs 32 bits cmd/asm always
				// picks the one-byte-shorter accumulator form (e.g. 48 05 id
				// for ADD), which this encoder is specified not to use. The
				// mandated generic form is REX.W 81 /digit id with a
				// register-direct ModRM byte (mod=11, rm=000 for RAX).
				if r == RAX && (imm < -128 || imm > 127) {
					l.addHand(name,
						fmt.Sprintf("48 81 %02x %s", 0xC0|op.digit<<3, le32(imm)),
						op.mnem+" "+p9Operands(op.dstFirst, "AX", disasmImm(imm)),
						emit)

					continue
				}

				l.add(name, op.mnem+" "+p9Operands(op.dstFirst, regP9[r], fmt.Sprintf("$%d", imm)), emit)
			}
		}
	}

	for _, r := range someRegs {
		for _, imm := range immBoundary {
			name := fmt.Sprintf("TestRI/%s,%d", regIntel[r], imm)
			emit := func(a *Assembler) { a.TestRI(r, imm) }

			// cmd/asm always uses the short accumulator form (48 A9 id) for
			// RAX. The generic form is REX.W F7 /0 id (Intel SDM "TEST
			// r/m64, imm32") with ModRM C0 for RAX.
			if r == RAX {
				l.addHand(name, "48 f7 c0 "+le32(imm), "TESTQ "+disasmImm(imm)+", AX", emit)

				continue
			}

			l.add(name, fmt.Sprintf("TESTQ $%d, %s", imm, regP9[r]), emit)
		}
	}
}

// addUnaryAndShifts adds the single-register instructions and the shifts.
func (l *caseList) addUnaryAndShifts() {
	unary := []struct {
		name string
		asm  string // Plan 9 text up to the register operand
		fn   func(a *Assembler, r Reg)
	}{
		{"NegR", "NEGQ ", (*Assembler).NegR},
		{"NotR", "NOTQ ", (*Assembler).NotR},
		{"IdivR", "IDIVQ ", (*Assembler).IdivR},
		{"DivR", "DIVQ ", (*Assembler).DivR},
		{"JmpR", "JMP ", (*Assembler).JmpR},
		{"ShlRCL", "SHLQ CX, ", (*Assembler).ShlRCL},
		{"ShrRCL", "SHRQ CX, ", (*Assembler).ShrRCL},
		{"SarRCL", "SARQ CX, ", (*Assembler).SarRCL},
	}

	for _, op := range unary {
		for _, r := range allRegs {
			l.add(fmt.Sprintf("%s/%s", op.name, regIntel[r]), op.asm+regP9[r],
				func(a *Assembler) { op.fn(a, r) })
		}
	}

	shifts := []struct {
		name string
		mnem string
		fn   func(a *Assembler, r Reg, imm uint8)
	}{
		{"ShlRI", "SHLQ", (*Assembler).ShlRI},
		{"ShrRI", "SHRQ", (*Assembler).ShrRI},
		{"SarRI", "SARQ", (*Assembler).SarRI},
	}

	for _, op := range shifts {
		for _, r := range someRegs {
			for _, imm := range []uint8{0, 1, 2, 7, 31, 32, 63} {
				l.add(fmt.Sprintf("%s/%s,%d", op.name, regIntel[r], imm),
					fmt.Sprintf("%s $%d, %s", op.mnem, imm, regP9[r]),
					func(a *Assembler) { op.fn(a, r, imm) })
			}
		}
	}
}

// addConditional adds SETcc and CMOVcc for every condition.
func (l *caseList) addConditional() {
	for _, c := range allCond {
		for _, r := range allRegs {
			l.add(fmt.Sprintf("Setcc/%s,%s", condIntel[c], regIntel[r]),
				fmt.Sprintf("SET%s %s", condP9[c], regP9[r]),
				func(a *Assembler) { a.Setcc(c, r) })
		}

		for _, p := range regPairs {
			dst, src := p[0], p[1]
			l.add(fmt.Sprintf("Cmovcc/%s,%s,%s", condIntel[c], regIntel[dst], regIntel[src]),
				fmt.Sprintf("CMOVQ%s %s, %s", condP9[c], regP9[src], regP9[dst]),
				func(a *Assembler) { a.Cmovcc(c, dst, src) })
		}
	}
}

// addRegMem adds the general purpose instructions with one register and one
// memory operand, and those with a single memory operand.
func (l *caseList) addRegMem() {
	ops := []struct {
		name     string
		mnem     string
		dstFirst bool // Plan 9 operand order is "reg, mem"
		mems     []Mem
		fn       func(a *Assembler, r Reg, m Mem)
	}{
		{"MovRM", "MOVQ", false, fullMems(), (*Assembler).MovRM},
		{"MovRM32", "MOVL", false, coreMems(), (*Assembler).MovRM32},
		{"MovzxRM8", "MOVBLZX", false, coreMems(), (*Assembler).MovzxRM8},
		{"Lea", "LEAQ", false, leaMems(), (*Assembler).Lea},
		{"AddRM", "ADDQ", false, coreMems(), (*Assembler).AddRM},
		{"SubRM", "SUBQ", false, coreMems(), (*Assembler).SubRM},
		{"CmpRM", "CMPQ", true, coreMems(), (*Assembler).CmpRM},
		// Stores: the register is the source, so it is written first.
		{"MovMR", "MOVQ", true, coreMems(), func(a *Assembler, r Reg, m Mem) { a.MovMR(m, r) }},
		{"MovMR32", "MOVL", true, coreMems(), func(a *Assembler, r Reg, m Mem) { a.MovMR32(m, r) }},
	}

	for k, op := range ops {
		for i, m := range op.mems {
			// 3 is coprime to 16, so the register cycles through all values.
			r := allRegs[(3*i+k)%len(allRegs)]
			l.add(fmt.Sprintf("%s/%s,%s", op.name, regIntel[r], memIntel(m)),
				op.mnem+" "+p9Operands(op.dstFirst, regP9[r], memP9(m)),
				func(a *Assembler) { op.fn(a, r, m) })
		}
	}

	unary := []struct {
		name string
		mnem string
		fn   func(a *Assembler, m Mem)
	}{
		{"IncM", "INCQ", (*Assembler).IncM},
		{"DecM", "DECQ", (*Assembler).DecM},
		{"JmpM", "JMP", (*Assembler).JmpM},
	}

	for _, op := range unary {
		for _, m := range coreMems() {
			l.add(fmt.Sprintf("%s/%s", op.name, memIntel(m)), op.mnem+" "+memP9(m),
				func(a *Assembler) { op.fn(a, m) })
		}
	}
}

// addMemImm adds the instructions with a memory and an immediate operand.
func (l *caseList) addMemImm() {
	ops := []struct {
		name     string
		mnem     string
		dstFirst bool
		mems     []Mem
		fn       func(a *Assembler, m Mem, imm int32)
	}{
		{"MovMI", "MOVQ", false, fullMems(), (*Assembler).MovMI},
		{"MovMI32", "MOVL", false, coreMems(), (*Assembler).MovMI32},
		{"AddMI", "ADDQ", false, coreMems(), (*Assembler).AddMI},
		{"SubMI", "SUBQ", false, coreMems(), (*Assembler).SubMI},
		{"CmpMI", "CMPQ", true, coreMems(), (*Assembler).CmpMI},
		{"CmpMI32", "CMPL", true, coreMems(), (*Assembler).CmpMI32},
	}

	half := len(immBoundary) / 2

	for k, op := range ops {
		for i, m := range op.mems {
			// One immediate of each width per memory operand.
			for _, j := range []int{i + k, i + k + half} {
				imm := immBoundary[j%len(immBoundary)]
				l.add(fmt.Sprintf("%s/%s,%d", op.name, memIntel(m), imm),
					op.mnem+" "+p9Operands(op.dstFirst, memP9(m), fmt.Sprintf("$%d", imm)),
					func(a *Assembler) { op.fn(a, m, imm) })
			}
		}
	}
}

// addBranches adds direct branches whose encoding cmd/asm and this encoder
// agree on: backward branches (both pick rel8 when in range) and forward
// branches beyond the rel8 range. Forward branches within rel8 range, which
// this encoder deliberately emits as rel32, are covered by the unit tests.
func (l *caseList) addBranches() {
	shapes := []struct {
		name    string
		asm     string // %s is the branch mnemonic
		pad     int
		forward bool
	}{
		{"back0", "l: %s l", 0, false},
		{"back126_rel8min", "l: P126; %s l", 126, false},
		{"back127_rel32", "l: P127; %s l", 127, false},
		{"back400", "l: P200; P200; %s l", 400, false},
		{"fwd128", "%s l; P128; l: RET", 128, true},
		{"fwd400", "%s l; P200; P200; l: RET", 400, true},
	}

	add := func(name, mnem string, jump func(a *Assembler, target Label)) {
		for _, s := range shapes {
			l.add(name+"/"+s.name, fmt.Sprintf(s.asm, mnem), func(a *Assembler) {
				target := a.NewLabel()

				if s.forward {
					jump(a, target)
					nops(a, s.pad)
					a.Bind(target)
					a.Ret()

					return
				}

				a.Bind(target)
				nops(a, s.pad)
				jump(a, target)
			})
		}
	}

	add("Jmp", "JMP", func(a *Assembler, target Label) { a.Jmp(target) })

	for _, c := range allCond {
		add("Jcc/"+condIntel[c], "J"+condP9[c], func(a *Assembler, target Label) { a.Jcc(c, target) })
	}
}

// addSSE adds the scalar double instructions.
func (l *caseList) addSSE() {
	for _, dst := range allX {
		for _, src := range allX {
			l.add(fmt.Sprintf("MovsdXX/%s,%s", xIntel(dst), xIntel(src)),
				fmt.Sprintf("MOVSD %s, %s", xregP9[src], xregP9[dst]),
				func(a *Assembler) { a.MovsdXX(dst, src) })
		}
	}

	xx := []struct {
		name string
		mnem string
		fn   func(a *Assembler, dst, src XReg)
	}{
		{"MovapdXX", "MOVAPD", (*Assembler).MovapdXX},
		{"AddsdXX", "ADDSD", (*Assembler).AddsdXX},
		{"SubsdXX", "SUBSD", (*Assembler).SubsdXX},
		{"MulsdXX", "MULSD", (*Assembler).MulsdXX},
		{"DivsdXX", "DIVSD", (*Assembler).DivsdXX},
		{"SqrtsdXX", "SQRTSD", (*Assembler).SqrtsdXX},
		{"UcomisdXX", "UCOMISD", (*Assembler).UcomisdXX},
		{"MinsdXX", "MINSD", (*Assembler).MinsdXX},
		{"MaxsdXX", "MAXSD", (*Assembler).MaxsdXX},
		{"XorpdXX", "XORPD", (*Assembler).XorpdXX},
		{"AndpdXX", "ANDPD", (*Assembler).AndpdXX},
		{"AndnpdXX", "ANDNPD", (*Assembler).AndnpdXX},
		{"OrpdXX", "ORPD", (*Assembler).OrpdXX},
	}

	for _, op := range xx {
		for _, p := range xPairs {
			dst, src := p[0], p[1]
			l.add(fmt.Sprintf("%s/%s,%s", op.name, xIntel(dst), xIntel(src)),
				fmt.Sprintf("%s %s, %s", op.mnem, xregP9[src], xregP9[dst]),
				func(a *Assembler) { op.fn(a, dst, src) })
		}
	}

	xm := []struct {
		name     string
		mnem     string
		regFirst bool // Plan 9 operand order is "xmm, mem" (store)
		mems     []Mem
		fn       func(a *Assembler, x XReg, m Mem)
	}{
		{"MovsdXM", "MOVSD", false, fullMems(), (*Assembler).MovsdXM},
		{"MovsdMX", "MOVSD", true, coreMems(), func(a *Assembler, x XReg, m Mem) { a.MovsdMX(m, x) }},
		{"AddsdXM", "ADDSD", false, coreMems(), (*Assembler).AddsdXM},
		{"SubsdXM", "SUBSD", false, coreMems(), (*Assembler).SubsdXM},
		{"MulsdXM", "MULSD", false, coreMems(), (*Assembler).MulsdXM},
		{"DivsdXM", "DIVSD", false, coreMems(), (*Assembler).DivsdXM},
		{"UcomisdXM", "UCOMISD", false, coreMems(), (*Assembler).UcomisdXM},
	}

	for k, op := range xm {
		for i, m := range op.mems {
			x := allX[(3*i+k)%len(allX)]
			l.add(fmt.Sprintf("%s/%s,%s", op.name, xIntel(x), memIntel(m)),
				op.mnem+" "+p9Operands(op.regFirst, xregP9[x], memP9(m)),
				func(a *Assembler) { op.fn(a, x, m) })
		}
	}

	l.addSSEInteger()
	l.addRoundsd()
}

// addSSEInteger adds the conversions and moves between SSE and general
// purpose registers.
func (l *caseList) addSSEInteger() {
	xs := []XReg{X0, X1, X5, X7, X8, X13, X15}
	rs := []Reg{RAX, RCX, RSP, RBP, RSI, RDI, R8, R12, R13, R15}

	for _, x := range xs {
		for _, r := range rs {
			xn, rn := xIntel(x), regIntel[r]

			l.add(fmt.Sprintf("Cvtsi2sdXR/%s,%s", xn, rn),
				fmt.Sprintf("CVTSQ2SD %s, %s", regP9[r], xregP9[x]),
				func(a *Assembler) { a.Cvtsi2sdXR(x, r) })
			l.add(fmt.Sprintf("Cvttsd2siRX/%s,%s", rn, xn),
				fmt.Sprintf("CVTTSD2SQ %s, %s", xregP9[x], regP9[r]),
				func(a *Assembler) { a.Cvttsd2siRX(r, x) })
			l.add(fmt.Sprintf("MovqXR/%s,%s", xn, rn),
				fmt.Sprintf("MOVQ %s, %s", regP9[r], xregP9[x]),
				func(a *Assembler) { a.MovqXR(x, r) })
			l.add(fmt.Sprintf("MovqRX/%s,%s", rn, xn),
				fmt.Sprintf("MOVQ %s, %s", xregP9[x], regP9[r]),
				func(a *Assembler) { a.MovqRX(r, x) })
		}
	}
}

// addRoundsd adds ROUNDSD with every rounding mode and register class.
func (l *caseList) addRoundsd() {
	add := func(dst, src XReg, mode uint8) {
		l.add(fmt.Sprintf("RoundsdXXI/%s,%s,%d", xIntel(dst), xIntel(src), mode),
			fmt.Sprintf("ROUNDSD $%d, %s, %s", mode, xregP9[src], xregP9[dst]),
			func(a *Assembler) { a.RoundsdXXI(dst, src, mode) })
	}

	for mode := uint8(0); mode <= 15; mode++ {
		add(X1, X2, mode)
	}

	for i, p := range xPairs {
		add(p[0], p[1], uint8(i%4))
		add(p[0], p[1], uint8(8+i%4))
	}
}

// xIntel returns the Intel name of an SSE register for case names.
func xIntel(x XReg) string {
	return "xmm" + strings.TrimPrefix(xregP9[x], "X")
}

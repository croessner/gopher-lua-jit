package arm64

import (
	"math"
	"math/rand"
	"testing"
)

// Move wide immediate field layout (Arm ARM, "Move wide (immediate)"):
// sf[31] opc[30:29] 100101[28:23] hw[22:21] imm16[20:5] Rd[4:0].
const (
	movWideFixedMask = 0x9F800000 // sf and the fixed 100101 pattern
	movWideFixedBits = 0x92800000 // sf=1, 100101
	movWideOpcMovn   = 0
	movWideOpcMovz   = 2
	movWideOpcMovk   = 3
)

// simulateMovWide executes a MOVZ/MOVN + MOVK sequence the way an A64 CPU
// would and returns the final register value. It fails the test for any word
// that is not a 64-bit move wide instruction on register dst, and for
// sequences that do not start with MOVZ/MOVN or continue with anything but
// MOVK.
func simulateMovWide(t *testing.T, words []uint32, dst Reg) uint64 {
	t.Helper()

	var value uint64

	for i, w := range words {
		if w&movWideFixedMask != movWideFixedBits {
			t.Fatalf("word %d (%08x) is not a 64-bit move wide instruction", i, w)
		}

		if rd := Reg(w & 0x1F); rd != dst {
			t.Fatalf("word %d (%08x) writes register %d, want %d", i, w, rd, dst)
		}

		opc := (w >> 29) & 3
		shift := ((w >> 21) & 3) * 16
		imm := uint64((w>>5)&0xFFFF) << shift

		switch {
		case i == 0 && opc == movWideOpcMovz:
			value = imm
		case i == 0 && opc == movWideOpcMovn:
			value = ^imm
		case i > 0 && opc == movWideOpcMovk:
			value = value&^(uint64(0xFFFF)<<shift) | imm
		default:
			t.Fatalf("word %d (%08x) has opc %d, which is invalid at this position", i, w, opc)
		}
	}

	return value
}

// minimalMovWideLen returns the length of the shortest MOVZ/MOVN + MOVK
// sequence for value: MOVZ provides every zero chunk for free and MOVN every
// all-ones chunk, and each remaining chunk costs one instruction.
func minimalMovWideLen(value uint64) int {
	var zeros, ones int

	for i := 0; i < 64; i += 16 {
		switch uint16(value >> i) {
		case 0:
			zeros++
		case 0xFFFF:
			ones++
		}
	}

	return max(1, 4-max(zeros, ones))
}

// checkMovRI encodes one constant and verifies the emitted sequence by
// simulation and against the minimal length.
func checkMovRI(t *testing.T, a *Assembler, dst Reg, value uint64) {
	t.Helper()

	a.Reset()
	a.MovRI(dst, int64(value))

	code, err := a.Bytes()
	if err != nil {
		t.Fatalf("MovRI(%d, %#x): %v", dst, value, err)
	}

	words := bytesToWords(t, code)

	if got := simulateMovWide(t, words, dst); got != value {
		t.Fatalf("MovRI(%d, %#x) = %s, which loads %#x", dst, value, formatWords(words), got)
	}

	if want := minimalMovWideLen(value); len(words) != want {
		t.Fatalf("MovRI(%d, %#x) = %s: %d instructions, minimum is %d", dst, value, formatWords(words), len(words), want)
	}
}

// TestMovRIFixedValues covers boundary constants and every chunk pattern.
func TestMovRIFixedValues(t *testing.T) {
	a := New()

	values := []uint64{
		0, 1, 0xFFFFFFFFFFFFFFFF, 0xFFFF, 0x10000, 0xFFFFFFFF, 1 << 32, 0x123456789ABCDEF0,
		1 << 63, math.MaxInt64, 0xFFFFFFFFFFFFFFFE, 0x8000, 0x7FFF, 0x80000000, 0x7FFFFFFF,
		0xFFFFFFFF00000000, 0x00000000FFFF0000, 0x0000FFFF00000000, 0xFFFF000000000000,
		0x1234FFFFFFFF5678, 0xFFFF1234FFFF5678, 0x12340000FFFF5678, 0xFFFF0000FFFF0000,
		0x0000FFFF0000FFFF, 0xFFFF00000000FFFF, 0x0001000100010001, 0xFFFEFFFEFFFEFFFE,
	}
	for _, v := range values {
		checkMovRI(t, a, X1, v)
	}

	// Every combination of zero, all-ones and "other" chunks.
	chunks := []uint64{0, 0xFFFF, 0x1234}

	for i := range 81 {
		var v uint64

		for pos, n := 0, i; pos < 4; pos, n = pos+1, n/3 {
			v |= chunks[n%3] << (16 * pos)
		}

		checkMovRI(t, a, X9, v)
	}
}

// TestMovRIRandomValues simulates the sequences of pseudo-random constants.
// The fixed seed keeps the run reproducible.
func TestMovRIRandomValues(t *testing.T) {
	const (
		seed       = 0x4C7541 // arbitrary but fixed
		iterations = 4000
	)

	rng := rand.New(rand.NewSource(seed))
	a := New()

	for i := range iterations {
		dst := Reg(rng.Intn(maxReg + 1))

		// Fully random bits rarely contain zero or all-ones chunks, so every
		// other value is assembled from chunks biased toward them.
		value := rng.Uint64()
		if i%2 == 1 {
			value = 0

			for pos := range 4 {
				var chunk uint64

				switch rng.Intn(3) {
				case 0:
					chunk = 0
				case 1:
					chunk = 0xFFFF
				default:
					chunk = uint64(rng.Intn(0x10000))
				}

				value |= chunk << (16 * pos)
			}
		}

		checkMovRI(t, a, dst, value)
	}
}

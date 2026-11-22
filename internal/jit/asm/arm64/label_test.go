package arm64

import (
	"errors"
	"testing"
)

// Branch range limits in instructions (words).
const (
	imm19MaxForward  = 1<<18 - 1
	imm19MaxBackward = 1 << 18
	imm26MaxForward  = 1<<25 - 1
	imm26MaxBackward = 1 << 25
)

// mustWords returns the resolved instruction words of a.
func mustWords(t *testing.T, a *Assembler) []uint32 {
	t.Helper()

	code, err := a.Bytes()
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	return bytesToWords(t, code)
}

// nops emits n NOP instructions.
func nops(a *Assembler, n int) {
	for range n {
		a.Nop()
	}
}

// branchKinds lists every label-taking emitter with the word it produces for
// a zero offset and the position of its offset field.
var branchKinds = []struct {
	emit  func(a *Assembler, l Label)
	name  string
	base  uint32
	shift uint
	bits  uint
}{
	{func(a *Assembler, l Label) { a.B(l) }, "B", 0x14000000, 0, 26},
	{func(a *Assembler, l Label) { a.Bcond(CondNE, l) }, "Bcond", 0x54000001, 5, 19},
	{func(a *Assembler, l Label) { a.Cbz(X7, l) }, "Cbz", 0xB4000007, 5, 19},
	{func(a *Assembler, l Label) { a.Cbnz(X30, l) }, "Cbnz", 0xB500001E, 5, 19},
}

// branchWord builds the expected branch word for a signed word offset.
func branchWord(base uint32, shift, bits uint, words int) uint32 {
	return base | (uint32(words)&(1<<bits-1))<<shift
}

// TestBranchForwardBackward inspects the words of forward and backward
// branches for every branch instruction.
func TestBranchForwardBackward(t *testing.T) {
	for _, k := range branchKinds {
		a := New()
		back := a.NewLabel()
		fwd := a.NewLabel()

		a.Bind(back)    // offset 0
		a.Nop()         // word 0
		k.emit(a, fwd)  // word 1: forward by 3
		a.Nop()         // word 2
		k.emit(a, back) // word 3: backward by 3
		a.Bind(fwd)     // offset 16
		a.Ret()         // word 4

		if got := a.LabelOffset(back); got != 0 {
			t.Errorf("%s: LabelOffset(back) = %d, want 0", k.name, got)
		}

		if got := a.LabelOffset(fwd); got != 16 {
			t.Errorf("%s: LabelOffset(fwd) = %d, want 16", k.name, got)
		}

		words := mustWords(t, a)
		want := []uint32{
			wordNop,
			branchWord(k.base, k.shift, k.bits, 3),
			wordNop,
			branchWord(k.base, k.shift, k.bits, -3),
			wordRet,
		}

		if formatWords(words) != formatWords(want) {
			t.Errorf("%s: got %s, want %s", k.name, formatWords(words), formatWords(want))
		}
	}
}

// TestBranchKnownWords pins a few branch words to literal values taken from
// the Arm ARM encodings rather than computed by a helper.
func TestBranchKnownWords(t *testing.T) {
	a := New()
	top := a.NewLabel()
	end := a.NewLabel()

	a.Bind(top)
	a.B(end)             // +5 words: 0x14000005
	a.Bcond(CondEQ, end) // +4 words: 0x54000080
	a.Cbz(X1, end)       // +3 words: 0xB4000061
	a.Cbnz(X2, top)      // -3 words: 0xB5FFFFA2
	a.B(top)             // -4 words: 0x17FFFFFC
	a.Bind(end)
	a.Bcond(CondLT, top) // -5 words: 0x54FFFF6B

	want := []uint32{0x14000005, 0x54000080, 0xB4000061, 0xB5FFFFA2, 0x17FFFFFC, 0x54FFFF6B}
	if got := mustWords(t, a); formatWords(got) != formatWords(want) {
		t.Errorf("got %s, want %s", formatWords(got), formatWords(want))
	}
}

// TestMultipleFixupsToOneLabel checks that every reference to a label is
// patched, including references emitted after the label was bound.
func TestMultipleFixupsToOneLabel(t *testing.T) {
	a := New()
	l := a.NewLabel()

	a.B(l)             // word 0: +3
	a.Bcond(CondGE, l) // word 1: +2
	a.Cbz(X0, l)       // word 2: +1
	a.Bind(l)
	a.Cbnz(X0, l) // word 3: 0
	a.B(l)        // word 4: -1

	want := []uint32{0x14000003, 0x5400004A, 0xB4000020, 0xB5000000, 0x17FFFFFF}
	if got := mustWords(t, a); formatWords(got) != formatWords(want) {
		t.Errorf("got %s, want %s", formatWords(got), formatWords(want))
	}

	// Resolving twice must be idempotent.
	if got := mustWords(t, a); formatWords(got) != formatWords(want) {
		t.Errorf("second Bytes call: got %s, want %s", formatWords(got), formatWords(want))
	}
}

// TestUnboundLabel checks that Bytes reports a referenced but unbound label
// and succeeds once the label is bound.
func TestUnboundLabel(t *testing.T) {
	for _, k := range branchKinds {
		a := New()
		l := a.NewLabel()

		if got := a.LabelOffset(l); got != -1 {
			t.Errorf("%s: LabelOffset of an unbound label = %d, want -1", k.name, got)
		}

		k.emit(a, l)

		if _, err := a.Bytes(); !errors.Is(err, ErrUnboundLabel) {
			t.Errorf("%s: Bytes error = %v, want ErrUnboundLabel", k.name, err)
		}

		a.Bind(l)

		if got := mustWords(t, a); got[0] != branchWord(k.base, k.shift, k.bits, 1) {
			t.Errorf("%s: after binding got %08x", k.name, got[0])
		}
	}

	// A label nobody references may stay unbound.
	a := New()
	a.NewLabel()
	a.Ret()

	if _, err := a.Bytes(); err != nil {
		t.Errorf("unreferenced unbound label: unexpected error %v", err)
	}
}

// TestInvalidLabels checks that unknown labels and double binding are errors.
func TestInvalidLabels(t *testing.T) {
	steps := map[string]func(a *Assembler){
		"branch to unknown label":  func(a *Assembler) { a.B(Label(0)) },
		"branch to negative label": func(a *Assembler) { a.Cbz(X0, Label(-1)) },
		"bind unknown label":       func(a *Assembler) { a.Bind(Label(3)) },
		"bind twice": func(a *Assembler) {
			l := a.NewLabel()
			a.Bind(l)
			a.Nop()
			a.Bind(l)
		},
		"label from before Reset": func(a *Assembler) {
			l := a.NewLabel()
			a.Reset()
			a.Bcond(CondEQ, l)
		},
	}

	for name, step := range steps {
		a := New()
		step(a)

		if _, err := a.Bytes(); !errors.Is(err, ErrLabel) {
			t.Errorf("%s: Bytes error = %v, want ErrLabel", name, err)
		}
	}

	if got := New().LabelOffset(Label(5)); got != -1 {
		t.Errorf("LabelOffset of an unknown label = %d, want -1", got)
	}
}

// TestImm19Range emits real code up to the +-1 MiB limit of B.cond, CBZ and
// CBNZ and checks the last encodable distance and the first unencodable one
// in both directions.
func TestImm19Range(t *testing.T) {
	for _, k := range branchKinds {
		if k.bits != 19 {
			continue
		}

		for _, tc := range []struct {
			words   int
			inRange bool
		}{
			{imm19MaxForward, true}, {imm19MaxForward + 1, false},
			{-imm19MaxBackward, true}, {-imm19MaxBackward - 1, false},
		} {
			a := New()
			l := a.NewLabel()

			if tc.words > 0 {
				k.emit(a, l)
				nops(a, tc.words-1)
				a.Bind(l)
			} else {
				a.Bind(l)
				nops(a, -tc.words)
				k.emit(a, l)
			}

			code, err := a.Bytes()

			if !tc.inRange {
				if !errors.Is(err, ErrBranchRange) {
					t.Errorf("%s by %d words: error = %v, want ErrBranchRange", k.name, tc.words, err)
				}

				continue
			}

			if err != nil {
				t.Errorf("%s by %d words: unexpected error %v", k.name, tc.words, err)

				continue
			}

			words := bytesToWords(t, code)
			at := 0

			if tc.words < 0 {
				at = len(words) - 1
			}

			if want := branchWord(k.base, k.shift, k.bits, tc.words); words[at] != want {
				t.Errorf("%s by %d words: got %08x, want %08x", k.name, tc.words, words[at], want)
			}
		}
	}
}

// TestImm26Range checks the +-128 MiB limit of B. Emitting that much code is
// too expensive for a unit test, so the label position is set directly
// instead of emitting the code in between.
func TestImm26Range(t *testing.T) {
	for _, tc := range []struct {
		words   int
		want    uint32
		inRange bool
	}{
		{imm26MaxForward, 0x15FFFFFF, true},
		{imm26MaxForward + 1, 0, false},
		{-imm26MaxBackward, 0x16000000, true},
		{-imm26MaxBackward - 1, 0, false},
	} {
		a := New()
		l := a.NewLabel()

		a.B(l)

		// White-box: place the label as if tc.words instructions lay between.
		a.labels[l] = tc.words * instrSize

		code, err := a.Bytes()

		if !tc.inRange {
			if !errors.Is(err, ErrBranchRange) {
				t.Errorf("B by %d words: error = %v, want ErrBranchRange", tc.words, err)
			}

			continue
		}

		if err != nil {
			t.Errorf("B by %d words: unexpected error %v", tc.words, err)

			continue
		}

		if got := bytesToWords(t, code)[0]; got != tc.want {
			t.Errorf("B by %d words: got %08x, want %08x", tc.words, got, tc.want)
		}
	}
}

// TestImm19RangeBoundaryWords pins the extreme imm19 encodings to literals.
func TestImm19RangeBoundaryWords(t *testing.T) {
	for _, tc := range []struct {
		words int
		want  uint32
	}{
		{imm19MaxForward, 0x547FFFE0},   // imm19 = 0x3FFFF
		{-imm19MaxBackward, 0x54800000}, // imm19 = 0x40000
	} {
		a := New()
		l := a.NewLabel()

		a.Bcond(CondEQ, l)
		a.labels[l] = tc.words * instrSize

		if got := mustWords(t, a)[0]; got != tc.want {
			t.Errorf("B.EQ by %d words: got %08x, want %08x", tc.words, got, tc.want)
		}
	}
}

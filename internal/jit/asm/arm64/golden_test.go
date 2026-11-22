package arm64

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

// update regenerates testdata/golden.txt from the Go toolchain's arm64
// assembler. The normal test run only reads the checked-in file.
var update = flag.Bool("update", false, "regenerate testdata/golden.txt with the Go arm64 assembler")

const (
	goldenPath = "testdata/golden.txt"
	// refSource is the name of the generated assembly file.
	refSource = "ref.s"
	// refHeaderLines is the number of source lines before the first case: the
	// TEXT directive and the two probe instructions.
	refHeaderLines = 3
	// Known encodings used to validate the listing extraction itself.
	wordRet = 0xD65F03C0
	wordNop = 0xD503201F
)

// goldenCase pairs one encoder call sequence with its reference.
type goldenCase struct {
	// emit drives the encoder under test.
	emit func(a *Assembler)
	// name identifies the case in the golden file and in failures.
	name string
	// asm is the equivalent instruction text in Go assembler (Plan 9 arm64)
	// syntax, one source line; several instructions are separated by ";".
	// It is empty for cases the Go assembler cannot express.
	asm string
	// manual holds instruction words derived by hand from the Arm ARM
	// encoding tables. It is only used when asm is empty.
	manual []uint32
}

// goldenEntry is one record of the golden file.
type goldenEntry struct {
	asm   string
	words []uint32
}

// wordsToBytes returns the little-endian byte image of instruction words.
func wordsToBytes(words []uint32) []byte {
	out := make([]byte, 0, len(words)*instrSize)
	for _, w := range words {
		out = binary.LittleEndian.AppendUint32(out, w)
	}

	return out
}

// bytesToWords splits a little-endian byte image into instruction words.
func bytesToWords(t *testing.T, code []byte) []uint32 {
	t.Helper()

	if len(code)%instrSize != 0 {
		t.Fatalf("code length %d is not a multiple of %d", len(code), instrSize)
	}

	words := make([]uint32, 0, len(code)/instrSize)
	for i := 0; i < len(code); i += instrSize {
		words = append(words, binary.LittleEndian.Uint32(code[i:]))
	}

	return words
}

// formatWords renders instruction words as space separated 8-digit hex.
func formatWords(words []uint32) string {
	parts := make([]string, len(words))
	for i, w := range words {
		parts[i] = fmt.Sprintf("%08x", w)
	}

	return strings.Join(parts, " ")
}

// encode runs one case against a fresh Assembler and returns its bytes.
func encode(t *testing.T, c goldenCase) []byte {
	t.Helper()

	a := New()
	c.emit(a)

	code, err := a.Bytes()
	if err != nil {
		t.Fatalf("%s: unexpected encoder error: %v", c.name, err)
	}

	return code
}

var (
	// listingInstr matches an instruction line of the assembler listing and
	// captures its decimal PC and source line.
	listingInstr = regexp.MustCompile(`^\t0x[0-9a-f]+ (\d+) \(` + regexp.QuoteMeta(refSource) + `:(\d+)\)\t`)
	// listingDump matches a hex dump line and captures its offset and bytes.
	listingDump = regexp.MustCompile(`^\t0x([0-9a-f]+)((?: [0-9a-f]{2}){1,16})(?:  |$)`)
)

// refListing is the parsed output of "go tool asm -S" for one function.
type refListing struct {
	// linePC maps a source line to the PC of its first instruction.
	linePC map[int]int
	// code is the machine code of the function, including trailing padding.
	code []byte
}

// parseListing extracts the line table and the machine code of the first
// function from an assembler listing.
func parseListing(t *testing.T, listing string) refListing {
	t.Helper()

	ref := refListing{linePC: map[int]int{}}
	inText := false

	for _, line := range strings.Split(listing, "\n") {
		if !strings.HasPrefix(line, "\t") {
			if inText {
				break
			}

			inText = strings.Contains(line, " STEXT ")

			continue
		}

		if !inText {
			continue
		}

		if m := listingInstr.FindStringSubmatch(line); m != nil {
			pc, _ := strconv.Atoi(m[1])
			src, _ := strconv.Atoi(m[2])

			if old, ok := ref.linePC[src]; !ok || pc < old {
				ref.linePC[src] = pc
			}

			continue
		}

		if m := listingDump.FindStringSubmatch(line); m != nil {
			off, _ := strconv.ParseInt(m[1], 16, 64)
			if int(off) != len(ref.code) {
				t.Fatalf("hex dump offset %#x does not continue at %#x", off, len(ref.code))
			}

			for _, b := range strings.Fields(m[2]) {
				v, _ := strconv.ParseUint(b, 16, 8)
				ref.code = append(ref.code, byte(v))
			}
		}
	}

	if len(ref.code) == 0 {
		t.Fatalf("no machine code found in assembler listing:\n%s", listing)
	}

	return ref
}

// lineBytes returns the machine code generated for one source line, which
// ends where the following source line starts.
func (r refListing) lineBytes(t *testing.T, line int, what string) []byte {
	t.Helper()

	start, ok := r.linePC[line]
	end, okEnd := r.linePC[line+1]

	if !ok || !okEnd || end <= start || end > len(r.code) {
		t.Fatalf("%s (line %d): no machine code in the listing (start %d/%v, end %d/%v)", what, line, start, ok, end, okEnd)
	}

	return r.code[start:end]
}

// assembleReference assembles the text of all cases for arm64 with the Go
// toolchain and returns the machine code of each case. Before trusting the
// extraction it checks two probe instructions with well-known encodings.
func assembleReference(t *testing.T, cases []goldenCase) [][]byte {
	t.Helper()

	var src strings.Builder

	// 516 is NOSPLIT|NOFRAME: no prologue, no stack check.
	src.WriteString("TEXT ·f(SB),516,$0-0\n\tRET\n\tNOOP\n")

	for _, c := range cases {
		if strings.ContainsAny(c.asm, "\n\t") {
			t.Fatalf("%s: assembler text must be a single line without tabs", c.name)
		}

		src.WriteString("\t" + c.asm + "\n")
	}

	// The sentinel gives the last case an end address.
	src.WriteString("\tBRK $0xFFFF\n")

	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, refSource), []byte(src.String()), 0o600); err != nil {
		t.Fatal(err)
	}

	cmd := exec.Command("go", "tool", "asm", "-S", "-o", "ref.o", refSource)
	cmd.Dir = dir
	cmd.Env = append(os.Environ(), "GOARCH=arm64", "GOOS=linux", "GOFLAGS=", "GOWORK=off")

	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("go tool asm failed: %v\n%s", err, annotateAsmErrors(string(out), cases))
	}

	ref := parseListing(t, string(out))

	probes := []struct {
		name string
		line int
		word uint32
	}{{"RET probe", 2, wordRet}, {"NOOP probe", 3, wordNop}}
	for _, p := range probes {
		if got := ref.lineBytes(t, p.line, p.name); !bytes.Equal(got, wordsToBytes([]uint32{p.word})) {
			t.Fatalf("listing extraction is broken: %s = % x, want word %08x", p.name, got, p.word)
		}
	}

	result := make([][]byte, len(cases))
	for i, c := range cases {
		result[i] = ref.lineBytes(t, refHeaderLines+1+i, c.name)
	}

	return result
}

// annotateAsmErrors appends the case name to assembler diagnostics that
// mention a source line, so that a rejected instruction is easy to find.
func annotateAsmErrors(out string, cases []goldenCase) string {
	lineRef := regexp.MustCompile(regexp.QuoteMeta(refSource) + `:(\d+)`)

	var b strings.Builder

	for _, line := range strings.Split(out, "\n") {
		b.WriteString(line)

		if m := lineRef.FindStringSubmatch(line); m != nil {
			n, _ := strconv.Atoi(m[1])
			if i := n - refHeaderLines - 1; i >= 0 && i < len(cases) {
				b.WriteString("    <== case " + cases[i].name)
			}
		}

		b.WriteString("\n")
	}

	return b.String()
}

// writeGolden regenerates the golden file from the Go assembler.
func writeGolden(t *testing.T, cases []goldenCase) {
	t.Helper()

	ref := assembleReference(t, cases)

	var b strings.Builder

	b.WriteString("# Reference encodings produced by the Go toolchain's arm64 assembler.\n")
	b.WriteString("# Regenerate with: go test ./internal/jit/asm/arm64/ -run TestGolden -update\n")
	b.WriteString("# Format: case name <TAB> instruction words (hex) <TAB> Go assembler text\n")

	for i, c := range cases {
		fmt.Fprintf(&b, "%s\t%s\t%s\n", c.name, formatWords(bytesToWords(t, ref[i])), c.asm)
	}

	if err := os.MkdirAll(filepath.Dir(goldenPath), 0o755); err != nil {
		t.Fatal(err)
	}

	if err := os.WriteFile(goldenPath, []byte(b.String()), 0o644); err != nil {
		t.Fatal(err)
	}
}

// readGolden loads the checked-in reference encodings keyed by case name.
func readGolden(t *testing.T) map[string]goldenEntry {
	t.Helper()

	f, err := os.Open(goldenPath)
	if err != nil {
		t.Fatalf("cannot open golden file (run the test with -update to create it): %v", err)
	}
	defer f.Close()

	entries := map[string]goldenEntry{}
	sc := bufio.NewScanner(f)

	for n := 1; sc.Scan(); n++ {
		line := sc.Text()
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		fields := strings.Split(line, "\t")
		if len(fields) != 3 {
			t.Fatalf("%s:%d: want 3 tab separated fields, got %d", goldenPath, n, len(fields))
		}

		entry := goldenEntry{asm: fields[2]}

		for _, h := range strings.Fields(fields[1]) {
			w, err := strconv.ParseUint(h, 16, 32)
			if err != nil || len(h) != 8 {
				t.Fatalf("%s:%d: bad instruction word %q", goldenPath, n, h)
			}

			entry.words = append(entry.words, uint32(w))
		}

		if _, dup := entries[fields[0]]; dup {
			t.Fatalf("%s:%d: duplicate case %q", goldenPath, n, fields[0])
		}

		entries[fields[0]] = entry
	}

	if err := sc.Err(); err != nil {
		t.Fatal(err)
	}

	return entries
}

// splitCases separates the cases checked against the Go assembler from the
// ones checked against hand-derived words, and rejects malformed tables.
func splitCases(t *testing.T, all []goldenCase) (asm, manual []goldenCase) {
	t.Helper()

	seen := map[string]bool{}

	for _, c := range all {
		if seen[c.name] {
			t.Fatalf("duplicate case name %q", c.name)
		}

		seen[c.name] = true

		switch {
		case c.asm != "" && c.manual == nil:
			asm = append(asm, c)
		case c.asm == "" && len(c.manual) > 0:
			manual = append(manual, c)
		default:
			t.Fatalf("%s: a case needs either assembler text or hand-derived words", c.name)
		}
	}

	return asm, manual
}

// TestGolden compares the encoder byte for byte with the reference encodings
// of the Go assembler stored in testdata/golden.txt.
func TestGolden(t *testing.T) {
	cases, _ := splitCases(t, goldenCases())

	if *update {
		writeGolden(t, cases)
	}

	golden := readGolden(t)

	for _, c := range cases {
		entry, ok := golden[c.name]
		if !ok {
			t.Errorf("%s: missing from %s; rerun with -update", c.name, goldenPath)

			continue
		}

		delete(golden, c.name)

		if entry.asm != c.asm {
			t.Errorf("%s: golden was generated from %q but the case now says %q; rerun with -update", c.name, entry.asm, c.asm)

			continue
		}

		if got, want := encode(t, c), wordsToBytes(entry.words); !bytes.Equal(got, want) {
			t.Errorf("%s: encoder emitted %s, Go assembler emitted %s for %q",
				c.name, formatWords(bytesToWords(t, got)), formatWords(entry.words), c.asm)
		}
	}

	for name := range golden {
		t.Errorf("%s: stale entry in %s; rerun with -update", name, goldenPath)
	}

	t.Logf("%d cases verified against the Go assembler golden file", len(cases))
}

// TestManualEncodings checks the instructions the Go assembler cannot
// express against words derived by hand from the Arm ARM encoding tables.
func TestManualEncodings(t *testing.T) {
	_, cases := splitCases(t, goldenCases())

	for _, c := range cases {
		if got, want := encode(t, c), wordsToBytes(c.manual); !bytes.Equal(got, want) {
			t.Errorf("%s: encoder emitted %s, hand-derived encoding is %s",
				c.name, formatWords(bytesToWords(t, got)), formatWords(c.manual))
		}
	}

	t.Logf("%d cases verified against hand-derived words", len(cases))
}

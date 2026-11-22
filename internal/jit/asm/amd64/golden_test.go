package amd64

import (
	"bufio"
	"encoding/hex"
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

// The golden test compares the encoder byte-for-byte against reference
// encodings produced by the Go toolchain's own assembler (cmd/asm).
//
// Every case pairs an encoder call with the equivalent Plan 9 syntax
// instruction. Running
//
//	go test -run TestGolden -update
//
// assembles all Plan 9 texts for GOARCH=amd64, extracts the instruction bytes
// with "go tool objdump" and stores them in testdata/golden.txt. A normal test
// run only reads that file and never invokes the toolchain.
//
// A few encodings mandated by the encoder API cannot be produced by cmd/asm
// because it always prefers a shorter, equivalent form (see goldenHandCases).
// Those cases carry expected bytes derived by hand from the Intel SDM. During
// -update the hand-derived bytes are additionally fed through the Go
// disassembler, which must decode them to exactly the intended instruction.
//
// The golden file is only ever written from these two reference sources and
// never from the encoder's own output.

var update = flag.Bool("update", false, "regenerate testdata/golden.txt with the Go assembler")

const (
	goldenFile = "testdata/golden.txt"

	// handPrefix marks golden lines whose bytes are hand-derived.
	handPrefix = "hand: "

	// refPackage is the package name passed to cmd/asm; it prefixes the
	// symbol names printed by objdump.
	refPackage = "gold"
)

// goldenCase is one encoder call together with its reference.
type goldenCase struct {
	name string
	// asm is the Plan 9 syntax reference (one or more statements separated
	// by semicolons). It is empty for hand-derived cases.
	asm string
	// hand holds hand-derived expected bytes (hex) and disasm the Go
	// disassembly those bytes must decode to. Both are empty when asm is set.
	hand   string
	disasm string
	emit   func(a *Assembler)
}

// source returns the reference description stored next to the bytes in the
// golden file. It lets a normal test run detect a stale golden file.
func (c goldenCase) source() string {
	if c.asm != "" {
		return c.asm
	}

	return handPrefix + c.disasm
}

// goldenEntry is one parsed line of the golden file.
type goldenEntry struct {
	hex    string
	source string
}

func TestGolden(t *testing.T) {
	cases := goldenCases()
	checkUniqueNames(t, cases)

	if *update {
		updateGolden(t, cases)
	}

	golden := readGolden(t)
	seen := make(map[string]bool, len(cases))
	a := New()
	failures := 0

	for _, c := range cases {
		seen[c.name] = true

		entry, ok := golden[c.name]
		if !ok {
			t.Fatalf("%s: missing from %s; regenerate it with -update", c.name, goldenFile)
		}

		if entry.source != c.source() {
			t.Fatalf("%s: %s is stale (reference %q, case %q); regenerate it with -update",
				c.name, goldenFile, entry.source, c.source())
		}

		if c.hand != "" && entry.hex != stripSpaces(c.hand) {
			t.Fatalf("%s: %s is stale (hand-derived bytes differ); regenerate it with -update", c.name, goldenFile)
		}

		a.Reset()
		c.emit(a)

		code, err := a.Bytes()
		if err != nil {
			t.Errorf("%s: encoder error: %v", c.name, err)

			failures++

			continue
		}

		if got := hex.EncodeToString(code); got != entry.hex {
			t.Errorf("%s: encoding mismatch\n      got: %s\n     want: %s\n reference: %s", c.name, got, entry.hex, entry.source)

			failures++
		}

		if failures >= 50 {
			t.Fatalf("too many mismatches, stopping")
		}
	}

	for name := range golden {
		if !seen[name] {
			t.Errorf("%s: golden entry without a test case; regenerate %s with -update", name, goldenFile)
		}
	}

	t.Logf("%d golden cases (%d hand-derived)", len(cases), countHand(cases))
}

// countHand returns the number of hand-derived cases.
func countHand(cases []goldenCase) int {
	n := 0

	for _, c := range cases {
		if c.hand != "" {
			n++
		}
	}

	return n
}

// checkUniqueNames fails the test if two cases share a name or a name cannot
// be stored in the tab-separated golden file.
func checkUniqueNames(t *testing.T, cases []goldenCase) {
	t.Helper()

	names := make(map[string]bool, len(cases))

	for _, c := range cases {
		if names[c.name] {
			t.Fatalf("duplicate golden case name %q", c.name)
		}

		if strings.ContainsAny(c.name, "\t\n") || strings.ContainsAny(c.source(), "\t\n") {
			t.Fatalf("golden case %q contains a tab or newline", c.name)
		}

		if (c.asm == "") == (c.hand == "") {
			t.Fatalf("golden case %q must have exactly one of asm and hand", c.name)
		}

		names[c.name] = true
	}
}

// readGolden parses the golden file into a map keyed by case name.
func readGolden(t *testing.T) map[string]goldenEntry {
	t.Helper()

	f, err := os.Open(goldenFile)
	if err != nil {
		t.Fatalf("open golden file: %v (generate it with -update)", err)
	}
	defer f.Close()

	golden := make(map[string]goldenEntry)
	sc := bufio.NewScanner(f)
	sc.Buffer(make([]byte, 0, 64*1024), 1024*1024)

	for line := 1; sc.Scan(); line++ {
		text := sc.Text()
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}

		fields := strings.Split(text, "\t")
		if len(fields) != 3 {
			t.Fatalf("%s:%d: want 3 tab-separated fields, got %d", goldenFile, line, len(fields))
		}

		if _, dup := golden[fields[0]]; dup {
			t.Fatalf("%s:%d: duplicate entry %q", goldenFile, line, fields[0])
		}

		golden[fields[0]] = goldenEntry{hex: fields[1], source: fields[2]}
	}

	if err := sc.Err(); err != nil {
		t.Fatalf("read golden file: %v", err)
	}

	return golden
}

// updateGolden regenerates the golden file from the reference sources.
func updateGolden(t *testing.T, cases []goldenCase) {
	t.Helper()

	ref := assembleReference(t, cases)

	var sb strings.Builder

	sb.WriteString("# Reference encodings for TestGolden; DO NOT EDIT.\n")
	sb.WriteString("# Regenerate with: go test -run TestGolden -update\n")
	sb.WriteString("# Format: name <TAB> hex bytes <TAB> reference\n")
	sb.WriteString("# The reference is the Plan 9 text assembled by cmd/asm, or\n")
	sb.WriteString("# \"hand: <disassembly>\" for bytes hand-derived from the Intel SDM.\n")

	for _, c := range cases {
		fmt.Fprintf(&sb, "%s\t%s\t%s\n", c.name, ref[c.name], c.source())
	}

	if err := os.MkdirAll(filepath.Dir(goldenFile), 0o755); err != nil {
		t.Fatalf("create testdata: %v", err)
	}

	if err := os.WriteFile(goldenFile, []byte(sb.String()), 0o644); err != nil {
		t.Fatalf("write golden file: %v", err)
	}

	t.Logf("wrote %d reference encodings to %s", len(cases), goldenFile)
}

// refInst is one disassembled instruction of a reference symbol.
type refInst struct {
	hex  string
	text string
}

// sanityCases are trivially known encodings that validate the extraction of
// bytes from the objdump output before any reference is trusted.
var sanityCases = []struct {
	asm string
	hex string
}{
	{"RET", "c3"},
	{"MOVQ AX, BX", "4889c3"},
	{"MOVL $0x11223344, AX; RET", "b844332211c3"},
	{"BYTE $0x0f; BYTE $0x0b", "0f0b"},
	{"P4; P2; P1", "90909090909090"},
}

// refPreamble defines the padding macros used by branch cases. Pn expands to
// n one-byte NOPs.
const refPreamble = `// Code generated by golden_test.go -update; DO NOT EDIT.
#define P1 BYTE $0x90
#define P2 P1; P1
#define P4 P2; P2
#define P8 P4; P4
#define P16 P8; P8
#define P32 P16; P16
#define P64 P32; P32
#define P126 P64; P32; P16; P8; P4; P2
#define P127 P126; P1
#define P128 P64; P64
#define P200 P128; P64; P8
`

// assembleReference returns the reference bytes (hex) of every case. Plan 9
// cases are assembled with cmd/asm; hand-derived cases are passed through as
// raw bytes and must disassemble to the instruction they claim to be.
func assembleReference(t *testing.T, cases []goldenCase) map[string]string {
	t.Helper()

	dir := t.TempDir()
	src := filepath.Join(dir, refPackage+".s")
	obj := filepath.Join(dir, refPackage+".o")

	var sb strings.Builder

	sb.WriteString(refPreamble)

	line := strings.Count(refPreamble, "\n")
	lineCase := make(map[int]string)

	// Every case lives in its own frameless NOSPLIT (flag 4) function so that
	// the assembler adds no prologue and symbols delimit the cases.
	writeText := func(sym, body, comment string) {
		fmt.Fprintf(&sb, "TEXT ·%s(SB),4,$0-0 // %s\n\t%s\n", sym, comment, body)

		line += 2
		lineCase[line] = comment
	}

	for i, s := range sanityCases {
		writeText(fmt.Sprintf("sanity%d", i), s.asm, "sanity")
	}

	for i, c := range cases {
		body := c.asm
		if body == "" {
			body = byteDirectives(t, c)
		}

		writeText(caseSymbol(i), body, c.name)
	}

	if err := os.WriteFile(src, []byte(sb.String()), 0o644); err != nil {
		t.Fatalf("write reference source: %v", err)
	}

	// The reference is always assembled for amd64, whatever the host is.
	asmEnv := append(os.Environ(), "GOFLAGS=", "GOARCH=amd64", "GOOS=linux")
	if out, err := runGo(dir, asmEnv, "tool", "asm", "-p", refPackage, "-o", obj, src); err != nil {
		t.Fatalf("go tool asm failed: %v\n%s", err, annotateAsmErrors(out, lineCase))
	}

	out, err := runGo(dir, append(os.Environ(), "GOFLAGS="), "tool", "objdump", obj)
	if err != nil {
		t.Fatalf("go tool objdump failed: %v\n%s", err, out)
	}

	syms := parseObjdump(t, out)

	for i, s := range sanityCases {
		sym := fmt.Sprintf("sanity%d", i)
		if got := joinHex(syms[sym]); got != s.hex {
			t.Fatalf("byte extraction is broken: %q assembled to %q, want %q", s.asm, got, s.hex)
		}
	}

	if want := len(sanityCases) + len(cases); len(syms) != want {
		t.Fatalf("objdump listed %d symbols, want %d", len(syms), want)
	}

	ref := make(map[string]string, len(cases))

	for i, c := range cases {
		insts, ok := syms[caseSymbol(i)]
		if !ok || len(insts) == 0 {
			t.Fatalf("%s: no reference bytes in objdump output", c.name)
		}

		if c.hand != "" {
			checkHandCase(t, c, insts)
		}

		ref[c.name] = joinHex(insts)
	}

	return ref
}

// caseSymbol returns the assembly symbol name of case i.
func caseSymbol(i int) string {
	return fmt.Sprintf("c%05d", i)
}

// byteDirectives renders the hand-derived bytes of c as BYTE directives.
func byteDirectives(t *testing.T, c goldenCase) string {
	t.Helper()

	raw, err := hex.DecodeString(stripSpaces(c.hand))
	if err != nil || len(raw) == 0 {
		t.Fatalf("%s: bad hand-derived hex %q: %v", c.name, c.hand, err)
	}

	parts := make([]string, len(raw))
	for i, b := range raw {
		parts[i] = fmt.Sprintf("BYTE $0x%02x", b)
	}

	return strings.Join(parts, "; ")
}

// checkHandCase verifies that hand-derived bytes decode, as one instruction
// that consumes all bytes, to the disassembly the case claims.
func checkHandCase(t *testing.T, c goldenCase, insts []refInst) {
	t.Helper()

	if len(insts) != 1 {
		t.Fatalf("%s: hand-derived bytes %s decode to %d instructions, want 1: %+v", c.name, c.hand, len(insts), insts)
	}

	if insts[0].hex != stripSpaces(c.hand) {
		t.Fatalf("%s: objdump returned %s for hand-derived bytes %s", c.name, insts[0].hex, c.hand)
	}

	if insts[0].text != c.disasm {
		t.Fatalf("%s: hand-derived bytes %s disassemble to %q, want %q", c.name, c.hand, insts[0].text, c.disasm)
	}
}

// runGo runs the go command and returns its combined output.
func runGo(dir string, env []string, args ...string) (string, error) {
	cmd := exec.Command("go", args...)
	cmd.Dir = dir
	cmd.Env = env

	out, err := cmd.CombinedOutput()

	return string(out), err
}

// asmErrorLine matches the source position in cmd/asm diagnostics.
var asmErrorLine = regexp.MustCompile(`\.s:(\d+)`)

// annotateAsmErrors appends the golden case name to each assembler diagnostic.
func annotateAsmErrors(out string, lineCase map[int]string) string {
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")

	for i, l := range lines {
		m := asmErrorLine.FindStringSubmatch(l)
		if m == nil {
			continue
		}

		if n, err := strconv.Atoi(m[1]); err == nil && lineCase[n] != "" {
			lines[i] = l + "   <- case " + lineCase[n]
		}
	}

	return strings.Join(lines, "\n")
}

// parseObjdump parses "go tool objdump" output into instructions per symbol
// (without the package prefix). The format is
//
//	TEXT gold.sym(SB) /path/gold.s
//	  gold.s:12	0x1a2	4889c3	MOVQ AX, BX
//
// with a variable number of tabs between the columns.
func parseObjdump(t *testing.T, out string) map[string][]refInst {
	t.Helper()

	syms := make(map[string][]refInst)
	cur := ""

	for _, l := range strings.Split(out, "\n") {
		if strings.TrimSpace(l) == "" {
			continue
		}

		if rest, ok := strings.CutPrefix(l, "TEXT "); ok {
			name, _, found := strings.Cut(rest, "(SB)")
			if !found {
				t.Fatalf("objdump: malformed TEXT line %q", l)
			}

			name, ok = strings.CutPrefix(name, refPackage+".")
			if !ok {
				t.Fatalf("objdump: unexpected symbol in %q", l)
			}

			if _, dup := syms[name]; dup {
				t.Fatalf("objdump: symbol %q listed twice", name)
			}

			cur = name
			syms[cur] = nil

			continue
		}

		var cols []string

		for _, c := range strings.Split(l, "\t") {
			if c = strings.TrimSpace(c); c != "" {
				cols = append(cols, c)
			}
		}

		if cur == "" || len(cols) != 4 || !strings.HasPrefix(cols[1], "0x") {
			t.Fatalf("objdump: unexpected line %q", l)
		}

		if _, err := hex.DecodeString(cols[2]); err != nil {
			t.Fatalf("objdump: bad hex column in %q", l)
		}

		syms[cur] = append(syms[cur], refInst{hex: cols[2], text: cols[3]})
	}

	return syms
}

// joinHex concatenates the bytes of all instructions of a symbol.
func joinHex(insts []refInst) string {
	var sb strings.Builder

	for _, in := range insts {
		sb.WriteString(in.hex)
	}

	return sb.String()
}

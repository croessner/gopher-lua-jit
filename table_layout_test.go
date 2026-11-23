package lua

import (
	"math"
	"testing"
	"unsafe"
)

// The table header and its string-keyed entries are what every table of
// a program pays for. The sizes are part of what the runtime promises:
// both fit the allocation size classes they are meant for.
func TestTableLayout(t *testing.T) {
	if unsafe.Sizeof(uintptr(0)) != 8 {
		t.Skip("the sizes are stated for 64-bit platforms")
	}
	if size := unsafe.Sizeof(LTable{}); size > 192 {
		t.Errorf("a table header takes %d bytes, more than the 192 byte size class", size)
	}
	if size := unsafe.Sizeof(tableField{}); size != 32 {
		t.Errorf("a string-keyed entry takes %d bytes, want 32", size)
	}
	if size := unsafe.Sizeof(fieldNum{}); size != 16 {
		t.Errorf("an unboxed number takes %d bytes, want 16", size)
	}
}

// A table that holds no number in a string-keyed entry has no unboxed
// numbers; they appear with the first number and follow the entries when
// those are moved.
func TestUnboxedNumbersFollowTheEntries(t *testing.T) {
	tb := newLTable(0, 0)
	tb.typedOK = true // as in a state with the JIT on
	tb.RawSetString("name", LString("value"))
	tb.RawSetString("fn", &LFunction{})
	if tb.nums != nil {
		t.Fatal("a table without numbers has unboxed numbers")
	}
	tb.RawSetString("count", LNumber(1))
	if tb.nums == nil || tb.fieldKind(2) != fieldFloat || tb.fieldKind(0) != fieldBoxed {
		t.Fatal("the first number did not create the unboxed numbers")
	}
	// growing the entries moves them several times
	for i := 0; i < 200; i++ {
		key := string(rune('a'+i%26)) + string(rune('A'+i/26))
		if i%3 == 0 {
			tb.RawSetString(key, LNumber(i))
		} else {
			tb.RawSetString(key, LString(key))
		}
	}
	before := tb.nums
	tb.reserveFields(500)
	if tb.nums == before {
		t.Fatal("the unboxed numbers did not follow the entries to their new place")
	}
	if tb.RawGetString("count") != LNumber(1) || tb.RawGetString("name") != LString("value") {
		t.Fatal("entries changed while the table grew")
	}
	for i := 0; i < 200; i++ {
		key := string(rune('a'+i%26)) + string(rune('A'+i/26))
		want := LValue(LString(key))
		if i%3 == 0 {
			want = LNumber(i)
		}
		if got := tb.RawGetString(key); got != want {
			t.Fatalf("%s = %v, want %v", key, got, want)
		}
		pos := tb.findField(key)
		if isNum := tb.fieldKind(pos) != fieldBoxed; isNum != (i%3 == 0) {
			t.Fatalf("%s: kind %d", key, tb.fieldKind(pos))
		}
	}

	// a number written by compiled code is seen by every reader
	pos := tb.findField("count")
	n := tb.numAt(pos)
	n.num, n.stale = math.Float64bits((42.5)), true
	if got := tb.RawGetString("count"); got != LNumber(42.5) {
		t.Fatalf("count = %v after a native store", got)
	}
	if n.stale {
		t.Fatal("the boxed value is still marked out of date after it was rebuilt")
	}
	n.num, n.stale = math.Float64bits((7)), true
	clone := tb.Clone()
	if got := clone.RawGetString("count"); got != LNumber(7) {
		t.Fatalf("the clone holds count = %v", got)
	}
	if got := clone.RawGetString("name"); got != LString("value") {
		t.Fatalf("the clone holds name = %v", got)
	}
	n.num, n.stale = math.Float64bits((8)), true
	seen := LValue(LNil)
	tb.ForEach(func(k, v LValue) {
		if k == LString("count") {
			seen = v
		}
	})
	if seen != LNumber(8) {
		t.Fatalf("a traversal sees count = %v", seen)
	}

	// replacing the number by another value and back
	tb.RawSetString("count", LString("text"))
	if tb.fieldKind(pos) != fieldBoxed || tb.RawGetString("count") != LString("text") {
		t.Fatal("a number entry did not become a boxed entry")
	}
	tb.RawSetString("count", LNil)
	if !tb.fieldRemoved(pos) || tb.RawGetString("count") != LNil {
		t.Fatal("the entry was not removed")
	}
	tb.RawSetString("count", LInteger(3))
	if tb.fieldKind(pos) != fieldInt || tb.RawGetString("count") != LInteger(3) {
		t.Fatal("the entry did not take an integer")
	}
}

// The tables of a state without the JIT keep no unboxed numbers; a table
// that exists when the JIT is switched on gets them for the numbers it
// holds already.
func TestUnboxedNumbersNeedTheJIT(t *testing.T) {
	tb := newLTable(0, 0)
	tb.RawSetString("name", LString("value"))
	tb.RawSetString("count", LNumber(1))
	tb.RawSetString("index", LInteger(2))
	for i := 0; i < 40; i++ {
		tb.RawSetString(string(rune('a'+i)), LNumber(i))
	}
	if tb.nums != nil {
		t.Fatal("a table of a state without the JIT has unboxed numbers")
	}
	if tb.RawGetString("count") != LNumber(1) || tb.RawGetString("index") != LInteger(2) {
		t.Fatal("the numbers are not stored")
	}
	if clone := tb.Clone(); clone.nums != nil || clone.RawGetString("count") != LNumber(1) {
		t.Fatal("the clone differs")
	}

	tb.enableTyped()
	if tb.nums == nil {
		t.Fatal("switching the JIT on did not create the unboxed numbers")
	}
	for name, want := range map[string]uint8{"name": fieldBoxed, "count": fieldFloat, "index": fieldInt, "a": fieldFloat} {
		pos := tb.findField(name)
		if got := tb.fieldKind(pos); got != want {
			t.Errorf("%s: kind %d, want %d", name, got, want)
		}
	}
	if n := tb.numAt(tb.findField("index")); int64(n.num) != 2 {
		t.Errorf("index is unboxed as %d", int64(n.num))
	}
	if n := tb.numAt(tb.findField("count")); math.Float64frombits(n.num) != 1 {
		t.Errorf("count is unboxed as %v", math.Float64frombits(n.num))
	}

	// the globals of a state follow the same rule
	L := NewState(Options{JIT: JITOptions{Enabled: false}})
	defer L.Close()
	L.SetGlobal("before", LNumber(5))
	if L.G.Global.nums != nil {
		t.Fatal("the globals of a state without the JIT have unboxed numbers")
	}
}

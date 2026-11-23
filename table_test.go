package lua

import (
	"fmt"
	"strings"
	"testing"
)

func TestTableNewLTable(t *testing.T) {
	tbl := newLTable(-1, -2)
	errorIfNotEqual(t, 0, cap(tbl.array))

	tbl = newLTable(10, 9)
	errorIfNotEqual(t, 10, cap(tbl.array))
}

func TestTableLen(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.RawSetInt(10, LNil)
	tbl.RawSetInt(9, LNumber(10))
	tbl.RawSetInt(8, LNil)
	tbl.RawSetInt(7, LNumber(10))
	errorIfNotEqual(t, 9, tbl.Len())

	tbl = newLTable(0, 0)
	tbl.Append(LTrue)
	tbl.Append(LTrue)
	tbl.Append(LTrue)
	errorIfNotEqual(t, 3, tbl.Len())
}

func TestTableLenType(t *testing.T) {
	L := NewState(Options{})
	err := L.DoString(`
        mt = {
            __index = mt,
            __len = function (self)
                return {hello = "world"}
            end
        }

        v = {}
        v.__index = v

        setmetatable(v, mt)

        assert(#v ~= 0, "#v should return a table reference in this case")

        print(#v)
    `)
	if err != nil {
		t.Error(err)
	}
}

func TestTableAppend(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.RawSetInt(1, LNumber(1))
	tbl.RawSetInt(2, LNumber(2))
	tbl.RawSetInt(3, LNumber(3))
	errorIfNotEqual(t, 3, tbl.Len())

	tbl.RawSetInt(1, LNil)
	tbl.RawSetInt(2, LNil)
	errorIfNotEqual(t, 3, tbl.Len())

	tbl.Append(LNumber(4))
	errorIfNotEqual(t, 4, tbl.Len())

	tbl.RawSetInt(3, LNil)
	tbl.RawSetInt(4, LNil)
	errorIfNotEqual(t, 0, tbl.Len())

	tbl.Append(LNumber(5))
	errorIfNotEqual(t, 1, tbl.Len())
}

func TestTableInsert(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.Append(LTrue)
	tbl.Append(LTrue)
	tbl.Append(LTrue)

	tbl.Insert(5, LFalse)
	errorIfNotEqual(t, LFalse, tbl.RawGetInt(5))
	errorIfNotEqual(t, 5, tbl.Len())

	tbl.Insert(-10, LFalse)
	errorIfNotEqual(t, LFalse, tbl.RawGet(LNumber(-10)))
	errorIfNotEqual(t, 5, tbl.Len())

	tbl = newLTable(0, 0)
	tbl.Append(LNumber(1))
	tbl.Append(LNumber(2))
	tbl.Append(LNumber(3))
	tbl.Insert(1, LNumber(10))
	errorIfNotEqual(t, LNumber(10), tbl.RawGetInt(1))
	errorIfNotEqual(t, LNumber(1), tbl.RawGetInt(2))
	errorIfNotEqual(t, LNumber(2), tbl.RawGetInt(3))
	errorIfNotEqual(t, LNumber(3), tbl.RawGetInt(4))
	errorIfNotEqual(t, 4, tbl.Len())

	tbl = newLTable(0, 0)
	tbl.Insert(5, LNumber(10))
	errorIfNotEqual(t, LNumber(10), tbl.RawGetInt(5))

}

func TestTableMaxN(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.Append(LTrue)
	tbl.Append(LTrue)
	tbl.Append(LTrue)
	errorIfNotEqual(t, 3, tbl.MaxN())

	tbl = newLTable(0, 0)
	errorIfNotEqual(t, 0, tbl.MaxN())

	tbl = newLTable(10, 0)
	errorIfNotEqual(t, 0, tbl.MaxN())
}

func TestTableRemove(t *testing.T) {
	tbl := newLTable(0, 0)
	errorIfNotEqual(t, LNil, tbl.Remove(10))
	tbl.Append(LTrue)
	errorIfNotEqual(t, LNil, tbl.Remove(10))

	tbl.Append(LFalse)
	tbl.Append(LTrue)
	errorIfNotEqual(t, LFalse, tbl.Remove(2))
	errorIfNotEqual(t, 2, tbl.MaxN())
	tbl.Append(LFalse)
	errorIfNotEqual(t, LFalse, tbl.Remove(-1))
	errorIfNotEqual(t, 2, tbl.MaxN())

}

func TestTableRawSetInt(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.RawSetInt(MaxArrayIndex+1, LTrue)
	errorIfNotEqual(t, 0, tbl.MaxN())
	errorIfNotEqual(t, LTrue, tbl.RawGet(LNumber(MaxArrayIndex+1)))

	tbl.RawSetInt(1, LTrue)
	tbl.RawSetInt(3, LTrue)
	errorIfNotEqual(t, 3, tbl.MaxN())
	errorIfNotEqual(t, LTrue, tbl.RawGetInt(1))
	errorIfNotEqual(t, LNil, tbl.RawGetInt(2))
	errorIfNotEqual(t, LTrue, tbl.RawGetInt(3))
	tbl.RawSetInt(2, LTrue)
	errorIfNotEqual(t, LTrue, tbl.RawGetInt(1))
	errorIfNotEqual(t, LTrue, tbl.RawGetInt(2))
	errorIfNotEqual(t, LTrue, tbl.RawGetInt(3))
}

func TestTableRawSetH(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.RawSetH(LString("key"), LTrue)
	tbl.RawSetH(LString("key"), LNil)
	_, found := tbl.dict[LString("key")]
	errorIfNotEqual(t, false, found)

	tbl.RawSetH(LTrue, LTrue)
	tbl.RawSetH(LTrue, LNil)
	_, foundb := tbl.dict[LTrue]
	errorIfNotEqual(t, false, foundb)
}

func TestTableRawGetH(t *testing.T) {
	tbl := newLTable(0, 0)
	errorIfNotEqual(t, LNil, tbl.RawGetH(LNumber(1)))
	errorIfNotEqual(t, LNil, tbl.RawGetH(LString("key0")))
	tbl.RawSetH(LString("key0"), LTrue)
	tbl.RawSetH(LString("key1"), LFalse)
	tbl.RawSetH(LNumber(1), LTrue)
	errorIfNotEqual(t, LTrue, tbl.RawGetH(LString("key0")))
	errorIfNotEqual(t, LTrue, tbl.RawGetH(LNumber(1)))
	errorIfNotEqual(t, LNil, tbl.RawGetH(LString("notexist")))
	errorIfNotEqual(t, LNil, tbl.RawGetH(LTrue))
}

func TestTableForEach(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.Append(LNumber(1))
	tbl.Append(LNumber(2))
	tbl.Append(LNumber(3))
	tbl.Append(LNil)
	tbl.Append(LNumber(5))

	tbl.RawSetH(LString("a"), LString("a"))
	tbl.RawSetH(LString("b"), LString("b"))
	tbl.RawSetH(LString("c"), LString("c"))

	tbl.RawSetH(LTrue, LString("true"))
	tbl.RawSetH(LFalse, LString("false"))

	tbl.ForEach(func(key, value LValue) {
		switch k := key.(type) {
		case LBool:
			switch bool(k) {
			case true:
				errorIfNotEqual(t, LString("true"), value)
			case false:
				errorIfNotEqual(t, LString("false"), value)
			default:
				t.Fail()
			}
		case LNumber:
			switch int(k) {
			case 1:
				errorIfNotEqual(t, LNumber(1), value)
			case 2:
				errorIfNotEqual(t, LNumber(2), value)
			case 3:
				errorIfNotEqual(t, LNumber(3), value)
			case 4:
				errorIfNotEqual(t, LNumber(5), value)
			default:
				t.Fail()
			}
		case LString:
			switch string(k) {
			case "a":
				errorIfNotEqual(t, LString("a"), value)
			case "b":
				errorIfNotEqual(t, LString("b"), value)
			case "c":
				errorIfNotEqual(t, LString("c"), value)
			default:
				t.Fail()
			}
		}
	})
}

// TestTableFieldIndex exercises string-keyed entries across the linear
// and the indexed representation, including removal and reinsertion.
func TestTableFieldIndex(t *testing.T) {
	tbl := newLTable(0, 0)
	const n = 500
	for i := 0; i < n; i++ {
		tbl.RawSetString(fmt.Sprintf("key%d", i), LNumber(i))
		for j := 0; j <= i; j += 1 + i/7 {
			if got := tbl.RawGetString(fmt.Sprintf("key%d", j)); got != LNumber(j) {
				t.Fatalf("after %d inserts: key%d = %v", i+1, j, got)
			}
		}
		if got := tbl.RawGetString(fmt.Sprintf("key%d", i+1)); got != LNil {
			t.Fatalf("missing key reported as %v", got)
		}
	}
	// removal keeps the position, reinsertion reuses it
	for i := 0; i < n; i += 3 {
		tbl.RawSetString(fmt.Sprintf("key%d", i), LNil)
	}
	count := 0
	var order []string
	for k, v := tbl.Next(LNil); k != LNil; k, v = tbl.Next(k) {
		count++
		order = append(order, string(k.(LString)))
		if v == LNil {
			t.Fatalf("traversal returned the removed entry %v", k)
		}
	}
	if want := n - (n+2)/3; count != want {
		t.Fatalf("traversal visited %d entries, want %d", count, want)
	}
	for i := 1; i < len(order); i++ {
		var a, b int
		fmt.Sscanf(order[i-1], "key%d", &a)
		fmt.Sscanf(order[i], "key%d", &b)
		if a >= b {
			t.Fatalf("traversal is not in insertion order: %s before %s", order[i-1], order[i])
		}
	}
	tbl.RawSetString("key3", LString("again"))
	if k, v := tbl.Next(LString("key2")); k != LString("key3") || v != LString("again") {
		t.Fatalf("a reinserted entry lost its position: next is %v = %v", k, v)
	}
	if len(tbl.fields) != n {
		t.Fatalf("%d entries stored for %d keys", len(tbl.fields), n)
	}
}

// TestTableReservedFields checks tables whose string part is sized in
// advance.
func TestTableReservedFields(t *testing.T) {
	L := NewState()
	defer L.Close()
	funcs := map[string]LGFunction{}
	for i := 0; i < 40; i++ {
		funcs[fmt.Sprintf("fn%d", i)] = func(*LState) int { return 0 }
	}
	tbl := L.SetFuncs(L.NewTable(), funcs)
	if cap(tbl.fields) != len(funcs) {
		t.Errorf("capacity %d for %d functions", cap(tbl.fields), len(funcs))
	}
	for name := range funcs {
		if tbl.RawGetString(name).Type() != LTFunction {
			t.Fatalf("%s is missing", name)
		}
	}
	created := L.CreateTable(0, 20)
	for i := 0; i < 20; i++ {
		created.RawSetString(fmt.Sprintf("k%d", i), LTrue)
	}
	if cap(created.fields) != 20 || created.RawGetString("k19") != LTrue || created.RawGetString("k20") != LNil {
		t.Errorf("unexpected state of a presized table: cap %d", cap(created.fields))
	}
}

// TestTableClone checks that a clone equals a raw copy of every entry
// and is independent of its source.
func TestTableClone(t *testing.T) {
	for _, typed := range []bool{false, true} {
		src := newLTable(0, 0)
		src.typedOK = typed
		for i := 1; i <= 20; i++ {
			src.RawSetInt(i, LNumber(i*2))
		}
		for i := 0; i < 30; i++ {
			src.RawSetString(fmt.Sprintf("k%d", i), LString(fmt.Sprintf("v%d", i)))
		}
		src.RawSetString("k7", LNil)
		src.RawSetH(LTrue, LString("bool"))
		src.RawSetH(LNumber(1.5), LString("float"))
		src.Metatable = newLTable(0, 0)

		clone := src.Clone()
		if clone.Metatable != LNil {
			t.Errorf("typed=%v: the metatable was copied", typed)
		}
		want := map[string]string{}
		src.ForEach(func(k, v LValue) { want[k.String()] = v.String() })
		got := map[string]string{}
		for k, v := clone.Next(LNil); k != LNil; k, v = clone.Next(k) {
			got[k.String()] = v.String()
		}
		if len(want) != 51 || len(got) != len(want) {
			t.Fatalf("typed=%v: %d entries cloned, source has %d", typed, len(got), len(want))
		}
		for k, v := range want {
			if got[k] != v {
				t.Errorf("typed=%v: clone[%s] = %q, want %q", typed, k, got[k], v)
			}
		}
		if clone.Len() != src.Len() || clone.RawGetString("k7") != LNil || clone.RawGetString("k29") != LString("v29") {
			t.Errorf("typed=%v: unexpected clone content", typed)
		}
		clone.RawSetString("k1", LString("changed"))
		clone.RawSetInt(1, LNumber(99))
		clone.RawSetString("new", LTrue)
		if src.RawGetString("k1") != LString("v1") || src.RawGetInt(1) != LNumber(2) || src.RawGetString("new") != LNil {
			t.Errorf("typed=%v: changing the clone changed the source", typed)
		}
	}
}

// TestTableBoolArray checks the unboxed boolean array representation.
func TestTableBoolArray(t *testing.T) {
	tbl := newLTable(0, 0)
	tbl.typedOK = true
	for i := 1; i <= 10; i++ {
		tbl.RawSetInt(i, LBool(i%2 == 0))
	}
	if tbl.akind != arrayKindBool || tbl.Len() != 10 || tbl.RawGetInt(2) != LTrue || tbl.RawGetInt(3) != LFalse {
		t.Fatalf("unexpected boolean array: kind %d len %d", tbl.akind, tbl.Len())
	}
	tbl.Insert(1, LTrue)
	if tbl.akind != arrayKindBool || tbl.RawGetInt(1) != LTrue || tbl.RawGetInt(3) != LTrue || tbl.Remove(1) != LTrue {
		t.Fatalf("insert/remove broke the boolean array")
	}
	n := 0
	tbl.ForEach(func(_, v LValue) {
		if v == LTrue {
			n++
		}
	})
	if n != 5 {
		t.Fatalf("%d true values, want 5", n)
	}
	clone := tbl.Clone()
	tbl.RawSetInt(4, LNumber(1))
	if tbl.akind != arrayKindGeneric || tbl.RawGetInt(4) != LNumber(1) || tbl.RawGetInt(2) != LTrue || tbl.Len() != 10 {
		t.Fatalf("storing a number did not convert the array correctly")
	}
	if clone.akind != arrayKindBool || clone.RawGetInt(4) != LTrue {
		t.Fatalf("the clone changed with its source")
	}
}

// sinkKey and sinkValue receive what the traversal tests visit, so that
// the callbacks capture nothing.
var sinkKey, sinkValue LValue

func visitSink(k, v LValue) { sinkKey, sinkValue = k, v }

// traversalTable returns a table with array elements, string keys and
// other keys, as plugins build them for modules and requests.
func traversalTable() *LTable {
	tb := newLTable(0, 0)
	for i := 1; i <= 40; i++ {
		tb.RawSetInt(i, LString("element"))
	}
	for _, k := range []string{"alpha", "beta", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu"} {
		tb.RawSetString(k, LTrue)
	}
	tb.RawSet(LNumber(2.5), LTrue)
	return tb
}

// walk visits every entry of tb with Next and returns the keys.
func walk(tb *LTable) []string {
	var keys []string
	for k, v := tb.Next(LNil); k != LNil; k, v = tb.Next(k) {
		sinkValue = v
		keys = append(keys, k.String())
	}
	return keys
}

// TestRepeatedTraversalDoesNotAllocate checks that traversing a table
// again and again, with ForEach and with Next (pairs), does not box the
// string keys and the array indexes anew every time.
func TestRepeatedTraversalDoesNotAllocate(t *testing.T) {
	tb := traversalTable()
	tb.ForEach(visitSink) // the first traversal is not worth a cache
	tb.ForEach(visitSink) // the second one builds it
	if n := testing.AllocsPerRun(20, func() { tb.ForEach(visitSink) }); n != 0 {
		t.Errorf("ForEach allocates %v times per traversal", n)
	}
	if n := testing.AllocsPerRun(20, func() {
		for k, v := tb.Next(LNil); k != LNil; k, v = tb.Next(k) {
			sinkKey, sinkValue = k, v
		}
	}); n != 0 {
		t.Errorf("Next allocates %v times per traversal", n)
	}
}

// TestTraversalKeysFollowTheTable checks the cached keys against changes
// of the table between and during traversals.
func TestTraversalKeysFollowTheTable(t *testing.T) {
	tb := traversalTable()
	before := walk(tb)
	if again := walk(tb); strings.Join(again, " ") != strings.Join(before, " ") {
		t.Fatalf("second traversal visits %v, first %v", again, before)
	}
	// fields added, removed and added again after the cache was built
	tb.RawSetString("nu", LTrue)
	tb.RawSetString("beta", LNil)
	tb.RawSetString("gamma", LNil)
	tb.RawSetString("gamma", LNumber(3))
	want := []string{"alpha", "gamma", "delta", "epsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda", "mu", "nu"}
	var fields []string
	tb.ForEach(func(k, v LValue) {
		if s, ok := k.(LString); ok {
			fields = append(fields, string(s))
		}
	})
	if strings.Join(fields, " ") != strings.Join(want, " ") {
		t.Errorf("ForEach visits the fields %v, want %v", fields, want)
	}
	if got := walk(tb)[40:]; strings.Join(got, " ") != strings.Join(append(want, "2.5"), " ") {
		t.Errorf("Next visits %v behind the array, want %v", got, append(want, "2.5"))
	}
	// a field added while the table is traversed is visited with its own key
	seen := map[string]int{}
	tb.ForEach(func(k, v LValue) {
		seen[k.String()]++
		if k.String() == "alpha" {
			tb.RawSetString("omega", LTrue)
		}
	})
	if seen["omega"] != 1 || seen["alpha"] != 1 || len(seen) != 40+len(want)+2 {
		t.Errorf("traversal with an added field saw %d keys, omega %d times", len(seen), seen["omega"])
	}
	// a copy has its own keys
	c := tb.Clone()
	c.RawSetString("only-in-copy", LTrue)
	if got, orig := len(walk(c)), len(walk(tb)); got != orig+1 {
		t.Errorf("copy has %d entries, original %d", got, orig)
	}
}

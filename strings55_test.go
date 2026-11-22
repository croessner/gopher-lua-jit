package lua

import (
	"strings"
	"testing"

	"github.com/yuin/gopher-lua/pm"
)

// TestLua55Strings runs the string and utf8 conformance scripts in the
// Lua 5.5 profile.
func TestLua55Strings(t *testing.T) {
	runLua55Scripts(t, "strings", Options{})
}

// TestLua55StringsReference checks the expectations of the conformance
// scripts against the reference interpreter.
func TestLua55StringsReference(t *testing.T) {
	checkLua55Reference(t, "strings")
}

// evalLua runs a chunk that returns values and returns them.
func evalLua(t *testing.T, L *LState, src string) []LValue {
	t.Helper()
	base := L.GetTop()
	fn, err := L.LoadString(src)
	if err != nil {
		t.Fatalf("%s: %v", src, err)
	}
	L.Push(fn)
	if err := L.PCall(0, MultRet, nil); err != nil {
		t.Fatalf("%s: %v", src, err)
	}
	rets := make([]LValue, 0, L.GetTop()-base)
	for i := base + 1; i <= L.GetTop(); i++ {
		rets = append(rets, L.Get(i))
	}
	L.SetTop(base)
	return rets
}

// TestLua55StringIntegerResults checks that integral results of the Lua
// 5.5 string and utf8 libraries carry the integer subtype.
func TestLua55StringIntegerResults(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55})
	defer L.Close()
	for _, src := range []string{
		`return string.len("abc")`,
		`return string.byte("abc", 1, -1)`,
		`return string.find("abc", "b")`,
		`return string.find("abc", "()b()")`,
		`return string.match("abc", "()")`,
		`local _, n = string.gsub("abc", "%w", "x") return n`,
		`return string.packsize("i4")`,
		`return string.unpack("<i2", "\1\0")`,
		`return utf8.len("abc")`,
		`return utf8.codepoint("abc", 1, -1)`,
		`return utf8.offset("abc", 2)`,
		`for p, c in utf8.codes("a") do return p, c end`,
	} {
		rets := evalLua(t, L, src)
		if len(rets) == 0 {
			t.Errorf("%s: no results", src)
		}
		for i, v := range rets {
			if _, ok := v.(LInteger); !ok {
				t.Errorf("%s: result #%d is %T (%v), want LInteger", src, i+1, v, v)
			}
		}
	}
}

// TestLua51StringProfileUnchanged guards the default (GopherLua
// compatible) profile: it keeps the upstream string library and does not
// gain the Lua 5.5 additions.
func TestLua51StringProfileUnchanged(t *testing.T) {
	L := NewState()
	defer L.Close()
	for src, want := range map[string]string{
		`return type(utf8)`:                                   "nil",
		`return type(package.loaded.utf8)`:                    "nil",
		`return type(string.pack)`:                            "nil",
		`return type(string.unpack)`:                          "nil",
		`return type(string.packsize)`:                        "nil",
		`return type(string.gfind)`:                           "function",
		`return tostring(string.__index == string)`:           "true",
		`return tostring(getmetatable("") == string)`:         "true",
		`return string.format("%5.1f|%d|%s", 3.14159, 42, 1)`: "  3.1|42|1",
		`return string.rep("ab", 2, "-")`:                     "abab",
		`return tostring(string.find("abc", "%z"))`:           "nil",
		`return (string.gsub("abc", "b", "%x"))`:              "a%xc",
		`return string.upper("ä")`:                            "Ä",
	} {
		rets := evalLua(t, L, src)
		if len(rets) != 1 || LVAsString(rets[0]) != want {
			t.Errorf("%s: got %v, want %q", src, rets, want)
		}
	}
	for _, src := range []string{
		`return string.len("abc")`,
		`return string.byte("abc", 1, -1)`,
		`return string.find("abc", "()b")`,
	} {
		for i, v := range evalLua(t, L, src) {
			if _, ok := v.(LNumber); !ok {
				t.Errorf("%s: result #%d is %T, want LNumber", src, i+1, v)
			}
		}
	}
}

// TestPatternMatcherErrors checks that malformed and overly complex
// patterns are reported as errors instead of panicking the Go runtime.
func TestPatternMatcherErrors(t *testing.T) {
	for _, tc := range []struct {
		src, pat, want string
	}{
		{"abc", "%", "malformed pattern (ends with '%')"},
		{"abc", "[a", "malformed pattern (missing ']')"},
		{"abc", "%b", "malformed pattern (missing arguments to '%b')"},
		{"abc", "%f", "missing '[' after '%f' in pattern"},
		{"abc", "(a)%2", "invalid capture index %2"},
		{"abc", "a)", "invalid pattern capture"},
		{"abc", strings.Repeat("()", pm.MaxCaptures+1), "too many captures"},
		{strings.Repeat("a", 300), strings.Repeat("a?", 300), "pattern too complex"},
	} {
		m := pm.NewMatcher(tc.src, tc.pat)
		end, err := m.Match(0, 0)
		if err == nil || err.Error() != tc.want || end != -1 {
			t.Errorf("pattern %q: got end %d, error %v; want error %q", tc.pat, end, err, tc.want)
		}
	}
	m := pm.NewMatcher("hello world", "(o)()")
	end, err := m.Match(4, 0)
	if err != nil || end != 5 || m.NumCaptures() != 2 {
		t.Fatalf("got end %d, captures %d, error %v", end, m.NumCaptures(), err)
	}
	if start, length, err := m.Capture(0, 4, end); err != nil || start != 4 || length != 1 {
		t.Errorf("capture 0: got %d, %d, %v", start, length, err)
	}
	if start, length, err := m.Capture(1, 4, end); err != nil || start != 5 || length != pm.CapPosition {
		t.Errorf("capture 1: got %d, %d, %v", start, length, err)
	}
	if _, _, err := m.Capture(2, 4, end); err == nil {
		t.Errorf("capture 2: expected an error")
	}
}

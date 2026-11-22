package lua

import (
	"bytes"
	"sort"
	"strings"
	"testing"
)

func TestLua55Base(t *testing.T) {
	runLua55Scripts(t, "base", Options{})
}

func TestLua55BaseReference(t *testing.T) {
	checkLua55Reference(t, "base")
}

// base55GlobalNames returns the sorted names of the global variables of L.
func base55GlobalNames(L *LState) []string {
	var names []string
	L.G.Global.ForEach(func(key, _ LValue) {
		names = append(names, key.String())
	})
	sort.Strings(names)
	return names
}

// base55LibraryNames returns the sorted field names of a global library table.
func base55LibraryNames(t *testing.T, L *LState, lib string) []string {
	t.Helper()
	tb, ok := L.GetGlobal(lib).(*LTable)
	if !ok {
		t.Fatalf("library %s is not a table", lib)
	}
	var names []string
	tb.ForEach(func(key, _ LValue) {
		names = append(names, key.String())
	})
	sort.Strings(names)
	return names
}

// TestBaseLua51ProfileUnchanged guards the names registered by the base,
// coroutine, package and debug libraries in the default profile.
func TestBaseLua51ProfileUnchanged(t *testing.T) {
	L := NewState()
	defer L.Close()

	wantGlobals := "_G _GOPHER_LUA_VERSION _VERSION _printregs assert channel collectgarbage coroutine debug " +
		"dofile error getfenv getmetatable io ipairs load loadfile loadstring math module newproxy next os " +
		"package pairs pcall print rawequal rawget rawset require select setfenv setmetatable string table " +
		"tonumber tostring type unpack xpcall"
	if got := strings.Join(base55GlobalNames(L), " "); got != wantGlobals {
		t.Errorf("globals:\n got %s\nwant %s", got, wantGlobals)
	}
	libs := map[string]string{
		"coroutine": "create resume running status wrap yield",
		"package":   "config cpath loaded loaders loadlib path preload seeall",
		"debug":     "getfenv getinfo getlocal getmetatable getupvalue setfenv setlocal setmetatable setupvalue traceback",
	}
	for lib, want := range libs {
		if got := strings.Join(base55LibraryNames(t, L, lib), " "); got != want {
			t.Errorf("%s:\n got %s\nwant %s", lib, got, want)
		}
	}
	if v := L.GetGlobal("_VERSION"); v != LString("Lua 5.1") {
		t.Errorf("_VERSION = %v", v)
	}
	if err := L.DoString(`
		assert(select("#", pairs({})) == 3)
		assert(coroutine.running() == nil)
		local ok, msg = pcall(error, nil)
		assert(ok == false and msg == nil)
		assert(tostring(10) == "10" and tonumber("0x10") == 16)
		assert(collectgarbage() == nil)
	`); err != nil {
		t.Error(err)
	}
}

// TestBase55Globals checks the global names registered by the base
// library slice in the Lua 5.5 profile: the names of the reference
// interpreter plus the GopherLua extras, and none of the Lua 5.1 leftovers.
func TestBase55Globals(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55})
	defer L.Close()

	present := make(map[string]bool)
	for _, name := range base55GlobalNames(L) {
		present[name] = true
	}
	want := "_G _GOPHER_LUA_VERSION _VERSION _printregs assert collectgarbage coroutine debug dofile error " +
		"getmetatable ipairs load loadfile next package pairs pcall print rawequal rawget rawlen rawset " +
		"require select setmetatable tonumber tostring type warn xpcall"
	for _, name := range strings.Fields(want) {
		if !present[name] {
			t.Errorf("global %s is missing", name)
		}
	}
	for _, name := range strings.Fields("unpack loadstring getfenv setfenv module newproxy") {
		if present[name] {
			t.Errorf("global %s must not be defined in the Lua 5.5 profile", name)
		}
	}
	libs := map[string]string{
		"coroutine": "close create isyieldable resume running status wrap yield",
		"package":   "config cpath loaded loadlib path preload searchers searchpath",
		"debug": "debug gethook getinfo getlocal getmetatable getregistry getupvalue getuservalue sethook " +
			"setlocal setmetatable setupvalue setuservalue traceback upvalueid upvaluejoin",
	}
	for lib, want := range libs {
		if got := strings.Join(base55LibraryNames(t, L, lib), " "); got != want {
			t.Errorf("%s:\n got %s\nwant %s", lib, got, want)
		}
	}
	if v := L.GetGlobal("_VERSION"); v != LString("Lua 5.5") {
		t.Errorf("_VERSION = %v", v)
	}
}

func TestBase55ChunkID(t *testing.T) {
	long := "a very long chunk name that will be truncated somewhere because it is longer than sixty characters"
	tests := []struct {
		source string
		want   string
	}{
		{"=name", "name"},
		{"=", ""},
		{"@file.lua", "file.lua"},
		{"return 1", `[string "return 1"]`},
		{"", `[string ""]`},
		{"x = 1\ny = 2", `[string "x = 1..."]`},
		{"\n\nx = 1", `[string "..."]`},
		{long, `[string "a very long chunk name that will be truncated..."]`},
		{"=" + long, "a very long chunk name that will be truncated somewhere bec"},
		{"@a/very/long/file/name/that/will/be/truncated/somewhere/because/it/is/longer/than/sixty.lua",
			".../truncated/somewhere/because/it/is/longer/than/sixty.lua"},
		{"=" + strings.Repeat("x", 59), strings.Repeat("x", 59)},
		{"=" + strings.Repeat("x", 60), strings.Repeat("x", 59)},
		{"@" + strings.Repeat("x", 59), strings.Repeat("x", 59)},
		{"@" + strings.Repeat("x", 60), "..." + strings.Repeat("x", 56)},
		{strings.Repeat("x", 44), `[string "` + strings.Repeat("x", 44) + `"]`},
		{strings.Repeat("x", 45), `[string "` + strings.Repeat("x", 45) + `..."]`},
	}
	for _, tt := range tests {
		if got := base55ChunkID(tt.source); got != tt.want {
			t.Errorf("base55ChunkID(%q) = %q, want %q", tt.source, got, tt.want)
		}
	}
}

func TestBase55Str2Int(t *testing.T) {
	tests := []struct {
		s    string
		base int
		want int64
		ok   bool
	}{
		{"10", 2, 2, true},
		{"ff", 16, 255, true},
		{"  -Zz  ", 36, -1295, true},
		{"+7", 8, 7, true},
		{"ffffffffffffffff", 16, -1, true},
		{"8", 8, 0, false},
		{"", 10, 0, false},
		{"-", 10, 0, false},
		{"1 1", 2, 0, false},
		{"1.5", 10, 0, false},
		{"0x10", 16, 0, false},
	}
	for _, tt := range tests {
		got, ok := base55Str2Int(tt.s, tt.base)
		if ok != tt.ok || (ok && got != tt.want) {
			t.Errorf("base55Str2Int(%q, %d) = %d, %v; want %d, %v", tt.s, tt.base, got, ok, tt.want, tt.ok)
		}
	}
}

// TestBase55Warn checks the output of the warning system: control
// messages, continuation pieces and the off state.
func TestBase55Warn(t *testing.T) {
	type piece struct {
		msg    string
		tocont bool
	}
	tests := []struct {
		name   string
		pieces []piece
		want   string
	}{
		{"off by default", []piece{{"hidden", false}}, ""},
		{"on", []piece{{"@on", false}, {"shown", false}}, "Lua warning: shown\n"},
		{"pieces", []piece{{"@on", false}, {"a", true}, {"b", true}, {"c", false}}, "Lua warning: abc\n"},
		{"off again", []piece{{"@on", false}, {"x", false}, {"@off", false}, {"y", false}}, "Lua warning: x\n"},
		{"unknown control", []piece{{"@on", false}, {"@what", false}, {"z", false}}, "Lua warning: z\n"},
		{"control as first piece", []piece{{"@on", false}, {"@off", true}, {"x", false}, {"y", false}},
			"Lua warning: @offx\nLua warning: y\n"},
		{"control inside a message", []piece{{"@on", false}, {"a", true}, {"@off", false}, {"b", false}},
			"Lua warning: a@off\nLua warning: b\n"},
		{"on while off needs a single piece", []piece{{"@on", true}, {"x", false}, {"y", false}}, ""},
		{"empty message", []piece{{"@on", false}, {"", false}}, "Lua warning: \n"},
	}
	for _, tt := range tests {
		st := &base55State{}
		var buf bytes.Buffer
		for _, p := range tt.pieces {
			st.warn(&buf, p.msg, p.tocont)
		}
		if got := buf.String(); got != tt.want {
			t.Errorf("%s: got %q, want %q", tt.name, got, tt.want)
		}
	}
}

// TestBase55WithoutPackageLib checks that the base and coroutine
// libraries work when the package library has not been opened.
func TestBase55WithoutPackageLib(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55, SkipOpenLibs: true})
	defer L.Close()
	for _, lib := range []struct {
		name string
		fn   LGFunction
	}{{BaseLibName, OpenBase}, {StringLibName, OpenString}, {CoroutineLibName, OpenCoroutine}, {DebugLibName, OpenDebug}} {
		L.Push(L.NewFunction(lib.fn))
		L.Push(LString(lib.name))
		L.Call(1, 0)
	}
	if err := L.DoString(`
		local ok, msg = pcall(require, "anything")
		assert(not ok and msg:find("'package.searchers' must be a table", 1, true), msg)
		local co = coroutine.wrap(function(a) local b = coroutine.yield(a + 1) return b * 2 end)
		assert(co(1) == 2 and co(4) == 8)
		assert(debug.traceback("x"):find("stack traceback:", 1, true))
	`); err != nil {
		t.Fatal(err)
	}
}

// TestBase55GoThreadIsNotACoroutine checks the coroutine functions on a
// thread that Go code created and runs directly: it behaves like a main
// thread.
func TestBase55GoThreadIsNotACoroutine(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55})
	defer L.Close()
	th, _ := L.NewThread()
	if err := th.DoString(`
		local running, ismain = coroutine.running()
		assert(type(running) == "thread" and ismain == true)
		assert(coroutine.isyieldable() == false)
		local ok, msg = pcall(coroutine.yield)
		assert(not ok and msg == "attempt to yield from outside a coroutine", msg)
		ok, msg = pcall(coroutine.close)
		assert(not ok and msg:find("cannot close main thread", 1, true), msg)
		local co = coroutine.create(function() return coroutine.status(running), coroutine.resume(running) end)
		local _, status, resumed, err = coroutine.resume(co)
		assert(status == "normal" and resumed == false and err == "cannot resume non-suspended coroutine")
	`); err != nil {
		t.Fatal(err)
	}
}

// TestBase55ResumeFromGo checks that coroutines created by Lua code can
// still be driven with the Go API.
func TestBase55ResumeFromGo(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55})
	defer L.Close()
	if err := L.DoString(`function gen(a) local b = coroutine.yield(a + 1) return b * 2 end`); err != nil {
		t.Fatal(err)
	}
	th, _ := L.NewThread()
	fn := L.GetGlobal("gen").(*LFunction)
	st, err, values := L.Resume(th, fn, LInteger(1))
	if st != ResumeYield || err != nil || len(values) != 1 || values[0] != LInteger(2) {
		t.Fatalf("first resume: %v %v %v", st, err, values)
	}
	st, err, values = L.Resume(th, fn, LInteger(5))
	if st != ResumeOK || err != nil || len(values) != 1 || values[0] != LInteger(10) {
		t.Fatalf("second resume: %v %v %v", st, err, values)
	}
}

// TestBase55NextWithTypedArrays checks that fields can be cleared during
// a traversal when the table uses an unboxed array part, which shrinks
// when its last element is cleared.
func TestBase55NextWithTypedArrays(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55, SkipOpenLibs: true})
	defer L.Close()
	L.typedArrays = true
	L.OpenLibs()
	if err := L.DoString(`
		for _, value in ipairs({1, 1.5}) do
			local t = {}
			for i = 1, 20 do t[i] = value end
			t.x, t.y, t.z = 1, 2, 3
			local seen = {}
			local count = 0
			for k in pairs(t) do
				assert(not seen[k], "key visited twice")
				seen[k] = true
				count = count + 1
				t[k] = nil
			end
			assert(count == 23, "visited " .. count .. " keys")
			assert(next(t) == nil)
		end
		-- a single element array shrinks as soon as the element is cleared
		for _, value in ipairs({1, 1.5}) do
			local t = {}
			t[1] = value
			t.x, t.y = 1, 2
			local count = 0
			for k in pairs(t) do
				count = count + 1
				t[k] = nil
			end
			assert(count == 3, "visited " .. count .. " keys")
			assert(next(t) == nil)
		end
		local t = {}
		for i = 1, 3 do t[i] = i end
		assert(not pcall(next, t, 5))
		assert(not pcall(next, t, 0))
	`); err != nil {
		t.Fatal(err)
	}
}

// TestBase55NextInvalidKey checks that next rejects the index just beyond
// a boxed array part. (With unboxed array parts this key is accepted, see
// base55NextKey.)
func TestBase55NextInvalidKey(t *testing.T) {
	L := NewState(Options{LanguageVersion: Lua55})
	defer L.Close()
	if err := L.DoString(`
		local ok, msg = pcall(next, {1, 2, 3}, 4)
		assert(not ok and msg == "invalid key to 'next'", msg)
		ok, msg = pcall(next, {"a", "b"}, 3)
		assert(not ok and msg == "invalid key to 'next'", msg)
	`); err != nil {
		t.Fatal(err)
	}
}

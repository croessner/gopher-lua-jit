package lua

import (
	"fmt"
	"strings"
	"testing"
)

// Regression tests for defects of the compiler, the parser and the core
// found by review. Each case failed before the corresponding fix. The
// expected results were taken from the reference Lua 5.5 interpreter
// (and agree with LuaJIT for the Lua 5.1 compatible programs).

// compileRegressCases run in both language profiles unless only55 is
// set; the chunk result is compared after conversion with runChunk.
var compileRegressCases = []struct {
	name   string
	src    string
	want   string
	only55 bool
}{
	{
		name: "goto keeps upvalues open",
		src: `local x = 0
			local get = function() return x end
			for i = 1, 2 do
				if i == 1 then goto continue end
				::continue::
			end
			x = 5
			return get()`,
		want: "number:5",
	},
	{
		name: "backward goto keeps upvalues open",
		src: `local x = 0
			local get = function() return x end
			local n = 0
			::again::
			n = n + 1
			if n < 3 then goto again end
			x = 7
			return get(), n`,
		want: "number:7 | number:3",
	},
	{
		name: "goto closes the upvalues of the scope it leaves",
		src: `local fns = {}
			for i = 1, 3 do
				local j = i * 10
				fns[i] = function() j = j + 1 return j end
				if i < 3 then goto continue end
				j = 100
				::continue::
			end
			return fns[1](), fns[1](), fns[2](), fns[3]()`,
		want: "number:11 | number:12 | number:21 | number:101",
	},
	{
		name: "goto out of a nested block closes its upvalues only",
		src: `local outer = 1
			local getouter = function() return outer end
			local inner
			do
				local v = 1
				inner = function() v = v + 1 return v end
				goto done
			end
			::done::
			outer = 2
			return getouter(), inner(), inner()`,
		want: "number:2 | number:2 | number:3",
	},
	{
		name: "goto does not close to-be-closed variables of outer scopes",
		src: `local log = {}
			do
				local a <close> = setmetatable({}, {__close = function() log[#log + 1] = "close" end})
				for i = 1, 2 do
					if i == 1 then goto continue end
					::continue::
				end
				log[#log + 1] = "end"
			end
			return table.concat(log, ",")`,
		want:   "string:end,close",
		only55: true,
	},
	{
		name: "and with a falsy table field assigned to a local",
		src: `local t = {}
			local v = 3
			v = t.x and 5
			local function g() return false end
			local w = "old"
			w = g() and 1
			return v, w`,
		want: "nil:nil | boolean:false",
	},
	{
		name: "and or chains assigned to an existing local",
		src: `local t = {a = false, b = 0}
			local v, w, x, y = 1, 2, 3, 4
			v = t.a and t.b
			w = t.b and t.a
			x = t.missing or t.a
			y = t.a or t.missing
			local p = 9
			p = t.missing and t.b or t.a
			return v, w, x, y, p`,
		want: "boolean:false | boolean:false | boolean:false | nil:nil | boolean:false",
	},
	{
		name: "logical operand must not overwrite the target early",
		src: `local function id(x) return x end
			local w = 5
			w = (id(1) or 2) and w + 1
			local v = 10
			v = (id(false) or v) and v * 2
			local u = 3
			u = (u and nil) or u
			return w, v, u`,
		want: "number:6 | number:20 | number:3",
	},
	{
		name: "parenthesized call assigned to the last parameter",
		src: `local function clean(s)
				local n = 10
				s = (s:gsub("a", "b"))
				return s, n
			end
			local function two(a, b)
				local keep = "k"
				b = (string.rep(a, 2))
				return a, b, keep
			end
			local s, n = clean("banana")
			return s, n, two("x", "y")`,
		want: "string:bbnbnb | number:10 | string:x | string:xx | string:k",
	},
	{
		name: "keyed call as the last table field",
		src: `local function f() return 7, 8 end
			local t = {1, a = f()}
			local u = {"x", n = ("abc"):len()}
			local w = {1, 2, [10] = f()}
			return #t, t[2], t.a, #u, u[2], u.n, w[2], w[3], w[10]`,
		want: "number:1 | nil:nil | number:7 | number:1 | nil:nil | number:3 | number:2 | nil:nil | number:7",
	},
	{
		name: "extra expressions run before the single target is assigned",
		src: `local seen
			local a = 1
			local function f() seen = a end
			a = 2, f()
			local b = 1
			local function g() seen = seen * 10 + b return 5 end
			b = g(), g()
			return seen, a, b`,
		want: "number:111 | number:2 | number:5",
	},
	{
		name: "table constructor with more than 25550 items",
		src: func() string {
			var b strings.Builder
			b.WriteString("local x = 'X'\nlocal t = {")
			for i := 1; i <= 25600; i++ {
				fmt.Fprintf(&b, "%d,", i)
			}
			b.WriteString("x}\nlocal mx = 0 for k in pairs(t) do if k > mx then mx = k end end\n")
			b.WriteString("return #t, t[25550], t[25551], t[25600], t[25601], mx")
			return b.String()
		}(),
		want: "number:25601 | number:25550 | number:25551 | number:25600 | string:X | number:25601",
	},
	{
		name: "function with more than 127 upvalues",
		src: func() string {
			var b strings.Builder
			for i := 1; i <= 140; i++ {
				fmt.Fprintf(&b, "local a%d = %d\n", i, i)
			}
			b.WriteString("local function f()\n local s = 0\n")
			for i := 1; i <= 140; i++ {
				fmt.Fprintf(&b, " s = s + a%d\n", i)
			}
			b.WriteString(" return tostring(s)\nend\nreturn f()")
			return b.String()
		}(),
		want: "string:9870",
	},
	{
		name: "sort ignores trailing nil values of the array part",
		src: `local t = {3, 1, 2, 5}
			t[#t] = nil
			table.sort(t)
			return #t, t[1], t[2], t[3], t[4]`,
		want: "number:3 | number:1 | number:2 | number:3 | nil:nil",
	},
	{
		name: "invalid for loop values are reported in reference order",
		src: `local function msg(f) local _, m = pcall(f) return (m:gsub("^.-:%d+: ", "")) end
			return msg(function() for i = "a", "b", "c" do end end),
				msg(function() for i = 1, "b", "c" do end end),
				msg(function() for i = "a", 2, "c" do end end),
				msg(function() for i = "a", 2, 0 do end end),
				msg(function() for i = 1, 2, 0 do end end)`,
		want: "string:bad 'for' limit (number expected, got string) | string:bad 'for' limit (number expected, got string) | " +
			"string:bad 'for' step (number expected, got string) | string:bad 'for' initial value (number expected, got string) | " +
			"string:'for' step is zero",
		only55: true,
	},
	{
		name:   "integer modulo by zero message",
		src:    `local ok, msg = pcall(function() local z = 0 return 1 % z end) return ok, (msg:gsub("^.-:%d+: ", ""))`,
		want:   "boolean:false | string:attempt to perform 'n%0'",
		only55: true,
	},
}

func TestCompileRegress(t *testing.T) {
	for _, tc := range compileRegressCases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			versions := []LanguageVersion{Lua51, Lua55}
			if tc.only55 {
				versions = versions[1:]
			}
			for _, version := range versions {
				if got, _ := runChunk(Options{LanguageVersion: version}, tc.src); got != tc.want {
					t.Errorf("%v:\n got:  %s\n want: %s", version, got, tc.want)
				}
				if !jitSupported() {
					continue
				}
				if got, _ := runChunk(jitTestOptions(version, 1), tc.src); got != tc.want {
					t.Errorf("%v with JIT:\n got:  %s\n want: %s", version, got, tc.want)
				}
			}
		})
	}
}

// TestParserProfileRules checks syntax rules that differ between the
// profiles or were accepted differently than by upstream GopherLua.
func TestParserProfileRules(t *testing.T) {
	cases := []struct {
		src          string
		ok51, ok55   bool
		errSubstring string
	}{
		// a call continued on the next line is one statement in both profiles
		{src: "local function f(...) return f end\nf(1)\n(f)(2)", ok51: true, ok55: true},
		{src: "local function f(...) return f end\nlocal g = f\n(f)(2)", ok51: true, ok55: true},
		// only names and index expressions are assignable
		{src: "local a\n(a) = 1", errSubstring: "syntax error"},
		{src: "local a = {}\n(a.b) = 1", errSubstring: "syntax error"},
		{src: "local a = {}\n(a).b = 1", ok51: true, ok55: true},
		// GopherLua tolerates repeated field separators, Lua 5.5 does not
		{src: "local t = {1, , 2}\nassert(#t == 2)", ok51: true, ok55: false},
		{src: "local t = {1,;}\nassert(#t == 1)", ok51: true, ok55: false},
		{src: "local t = {,}", ok51: false, ok55: false},
		// no global can be accessed where _ENV itself is declared global
		{src: "global _ENV\nreturn _ENV", ok51: false, ok55: false},
		{src: "global _ENV, x\nx = 1", ok51: false, ok55: false},
		{src: "global x, _ENV", ok51: false, ok55: true},
	}
	for _, tc := range cases {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			L := NewState(Options{LanguageVersion: version})
			_, err := L.LoadString(tc.src)
			L.Close()
			want := tc.ok51
			if version == Lua55 {
				want = tc.ok55
			}
			if (err == nil) != want {
				t.Errorf("%v: %q: accepted=%v, want %v (%v)", version, tc.src, err == nil, want, err)
			}
		}
	}
}

// TestSetFEnvKeepsUserUpvalue checks that SetFEnv on a Lua 5.1 function
// does not touch a user variable that happens to be called _ENV.
func TestSetFEnvKeepsUserUpvalue(t *testing.T) {
	L := NewState()
	defer L.Close()
	if err := L.DoString(`local _ENV = "hello"; function f() return _ENV end`); err != nil {
		t.Fatal(err)
	}
	fn := L.GetGlobal("f")
	L.SetFEnv(fn, L.NewTable())
	if err := L.CallByParam(P{Fn: fn, NRet: 1, Protect: true}); err != nil {
		t.Fatal(err)
	}
	if got := L.Get(-1); got != LString("hello") {
		t.Errorf("got %v (%s), want the string hello", got, got.Type())
	}
}

// TestFailingMessageHandlerUnwinds checks that a protected call whose
// message handler fails still unwinds the state like any other error.
func TestFailingMessageHandlerUnwinds(t *testing.T) {
	src := `local saved
		local ok = xpcall(function()
			local b = 5
			saved = function() b = b + 1 return b end
			error("a")
		end, function() error("b") end)
		local function clobber() local x, y, z = 100, 200, 300 return x + y + z end
		local c = clobber()
		local s1, s2 = saved(), saved()
		local co = coroutine.wrap(function()
			xpcall(function() error("a") end, function() error("b") end)
			coroutine.yield(1)
			return 2
		end)
		local r1, r2 = co(), co()
		return ok, c, s1, s2, r1, r2`
	want := "boolean:false | number:600 | number:6 | number:7 | number:1 | number:2"
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		if got, _ := runChunk(Options{LanguageVersion: version}, src); got != want {
			t.Errorf("%v:\n got:  %s\n want: %s", version, got, want)
		}
	}
}

// TestCompilerLimits checks that programs beyond the limits of the
// bytecode format are rejected instead of being miscompiled.
func TestCompilerLimits(t *testing.T) {
	// 150 locals in each of two enclosing functions, all used by the
	// innermost function
	var upvalues strings.Builder
	sum := "return function() return 0"
	for level := 0; level < 2; level++ {
		for i := 1; i <= 150; i++ {
			fmt.Fprintf(&upvalues, "local v%d_%d = %d\n", level, i, i)
			sum += fmt.Sprintf(" + v%d_%d", level, i)
		}
		if level == 0 {
			upvalues.WriteString("return function()\n")
		}
	}
	upvalues.WriteString(sum + " end\nend")
	cases := []struct{ name, src, message string }{
		{"jump labels", "local x = 1\nreturn " + strings.Repeat("x and ", 140000) + "x", "too many jump labels"},
		{"upvalues", upvalues.String(), "more than 255 upvalues"},
	}
	for _, tc := range cases {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			L := NewState(Options{LanguageVersion: version})
			_, err := L.LoadString(tc.src)
			L.Close()
			if err == nil || !strings.Contains(err.Error(), tc.message) {
				t.Errorf("%s (%v): got %v, want an error containing %q", tc.name, version, err, tc.message)
			}
		}
	}
}

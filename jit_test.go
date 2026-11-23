package lua

import (
	"fmt"
	"os"
	"runtime"
	"strings"
	"testing"
)

// jitTestOptions returns options that compile loops almost immediately so
// that as much code as possible runs natively.
func jitTestOptions(version LanguageVersion, threshold int) Options {
	return Options{
		RegistrySize:    1024 * 20,
		CallStackSize:   1024,
		LanguageVersion: version,
		JIT:             JITOptions{Enabled: true, Threshold: threshold, SafePointInterval: 97},
	}
}

func skipWithoutJIT(t testing.TB) {
	t.Helper()
	if !jitSupported() {
		t.Skip("the JIT is not supported on this platform")
	}
}

// testScriptDirJIT runs the upstream script tests with the JIT enabled.
func testScriptDirJIT(t *testing.T, tests []string, directory string, threshold int) {
	if err := os.Chdir(directory); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir("..")
	for _, script := range tests {
		os.Unsetenv("_____GLUATEST______") // set by _glua-tests/os.lua
		L := NewState(jitTestOptions(Lua51, threshold))
		L.SetMx(maxMemory)
		if err := L.DoFile(script); err != nil {
			t.Errorf("%s/%s (threshold %d): %v", directory, script, threshold, err)
		}
		if st := L.JITStats(); !st.Enabled {
			t.Errorf("JIT not enabled")
		}
		L.Close()
	}
}

func TestJITGlua(t *testing.T) {
	skipWithoutJIT(t)
	for _, threshold := range []int{1, 2, 7} {
		testScriptDirJIT(t, gluaTests, "_glua-tests", threshold)
	}
}

func TestJITLuaSuite(t *testing.T) {
	skipWithoutJIT(t)
	for _, threshold := range []int{1, 2, 7} {
		testScriptDirJIT(t, luaTests, "_lua5.1-tests", threshold)
	}
}

func TestJITLua55Smoke(t *testing.T) {
	skipWithoutJIT(t)
	runLua55Scripts(t, "smoke", jitTestOptions(Lua55, 1))
}

// runChunk executes a chunk and returns its results converted to strings
// (or the error message).
func runChunk(opts Options, src string) (string, JITStats) {
	L := NewState(opts)
	defer L.Close()
	fn, err := L.LoadString(src)
	if err != nil {
		return "load error: " + err.Error(), JITStats{}
	}
	L.Push(fn)
	if err := L.PCall(0, MultRet, nil); err != nil {
		msg := err.Error()
		if i := strings.Index(msg, "\nstack traceback"); i >= 0 {
			msg = msg[:i]
		}
		return "error: " + msg, L.JITStats()
	}
	var out []string
	for i := 1; i <= L.GetTop(); i++ {
		v := L.Get(i)
		out = append(out, fmt.Sprintf("%s:%s", v.Type(), L.ToStringMeta(v).String()))
	}
	return strings.Join(out, " | "), L.JITStats()
}

// checkJITMatchesInterpreter runs src in both language profiles with and
// without the JIT and requires identical results.
func checkJITMatchesInterpreter(t *testing.T, name, src string) {
	t.Helper()
	for _, version := range []LanguageVersion{Lua51, Lua55} {
		want, _ := runChunk(Options{LanguageVersion: version}, src)
		if strings.HasPrefix(want, "load error") {
			if version == Lua51 {
				continue // uses syntax that the Lua 5.1 profile lacks
			}
			t.Errorf("%s: %s", name, want)
			continue
		}
		for _, threshold := range []int{1, 2, 5, 50} {
			got, _ := runChunk(jitTestOptions(version, threshold), src)
			if got != want {
				t.Errorf("%s (%v, threshold %d):\n jit:         %s\n interpreter: %s", name, version, threshold, got, want)
			}
		}
	}
}

var jitPrograms = map[string]string{
	"float mod":               `local s = 0 for i = -50, 50 do s = s + (i * 1.0) % 7 + i % -3.0 + (i * 2.0) % 4 + i % 2.5 end return s`,
	"float mod negative zero": `local c = 0 for i = -6, 6, 2 do if 1 / ((i * 1.0) % 2) < 0 then c = c + 1 end end return c`,
	"float mod by zero":       `local c = 0 for i = 1, 100 do local r = (i * 1.0) % (i % 10 * 1.0) if r ~= r then c = c + 1 end end return c`,
	"nested math":             `local s = 0 for i = 1, 300 do s = s + math.floor(math.sqrt(i)) + math.abs(math.floor(-i / 3)) + math.ceil(i / 7) + math.sqrt(math.abs(i - 150)) end return s`,
	"math on strings":         `local s = 0 for i = 1, 100 do s = s + math.floor("3.7") + math.sqrt("16") end return s`,
	"math replaced":           `local s, floor = 0, math.floor for i = 1, 200 do if i == 120 then math.floor = function(x) return 1000 end end s = s + math.floor(i / 2) end math.floor = floor return s`,
	"global replaced":         `local s = 0 local m = math for i = 1, 200 do if i == 100 then math = {floor = function() return -1 end} end s = s + math.floor(i / 2) end math = m return s`,
	"int sum":                 `local s = 0 for i = 1, 1000 do s = s + i * 2 % 7 end return s`,
	"float sum":               `local f = 0.0 for i = 1, 1000 do f = f + i / 3 - 0.25 end return f`,
	"mixed":                   `local s, f = 0, 0.5 for i = 1, 500 do s = s + i; f = f * 1.001 + s end return s, f`,
	"negative step":           `local s = 0 for i = 100, 1, -3 do s = s * 3 + i end return s`,
	"float step":              `local s = 0 for x = 0.0, 10.0, 0.125 do s = s + x * x end return s`,
	"while":                   `local n, c = 27, 0 while n ~= 1 do if n % 2 == 0 then n = n / 2 else n = 3 * n + 1 end c = c + 1 end return c, n`,
	"repeat":                  `local i, s = 0, 0 repeat i = i + 1; s = s + i * i until i >= 300 return s`,
	"nested":                  `local s = 0 for i = 1, 60 do for j = 1, 60 do s = s + i * j end end return s`,
	"break":                   `local s = 0 for i = 1, 1000 do if i * i > 5000 then break end s = s + i end return s`,
	"table fill and sum":      `local t = {} for i = 1, 500 do t[i] = i * 3 end local s = 0 for i = 1, #t do s = s + t[i] end return s, #t`,
	"float table":             `local t = {} for i = 1, 300 do t[i] = i / 4 end local s = 0 for i = 1, #t do s = s + t[i] end return s`,
	"mixed table":             `local t = {} for i = 1, 200 do if i % 3 == 0 then t[i] = "x" else t[i] = i end end local s, n = 0, 0 for i = 1, #t do local v = t[i] if type(v) == "number" then s = s + v else n = n + 1 end end return s, n`,
	"table of tables":         `local m = {} for i = 1, 30 do m[i] = {} for j = 1, 30 do m[i][j] = i * j end end local s = 0 for i = 1, 30 do local row = m[i] for j = 1, 30 do s = s + row[j] end end return s`,
	"string keys":             `local p = {x = 1, y = 2} for i = 1, 300 do p.x = p.x + p.y; p.y = p.y + 1 end return p.x, p.y`,
	"concat":                  `local s = "" for i = 1, 100 do s = s .. i % 10 end return #s, s`,
	"calls":                   `local function f(a, b) return a * 2 + b end local s = 0 for i = 1, 300 do s = s + f(i, 1) end return s`,
	"go calls":                `local s = 0 for i = 1, 300 do s = s + math.floor(i / 7) + #tostring(i) end return s`,
	"closures":                `local fns = {} for i = 1, 50 do fns[i] = function() return i * 2 end end local s = 0 for i = 1, 50 do s = s + fns[i]() end return s`,
	"upvalue counter":         `local c = 0 local function inc() c = c + 1 end for i = 1, 200 do inc() end return c`,
	"nil and bool":            `local t, n = {}, 0 for i = 1, 200 do t[i] = (i % 4 ~= 0) end for i = 1, 250 do if t[i] then n = n + 1 elseif t[i] == nil then n = n + 1000 end end return n`,
	"and or":                  `local s = 0 for i = 1, 300 do local v = (i % 2 == 0) and i or -i; s = s + (v > 0 and v or 0) end return s`,
	"error in loop":           `local ok, err = pcall(function() local t = {} for i = 1, 100 do if i == 77 then local x = t.a.b end end end) return ok, (string.gsub(tostring(err), "^.-:%d+: ", ""))`,
	"division by zero":        `local s = 0 for i = -50, 50 do s = s + (i ~= 0 and 100 / i or 0) end return s`,
	"type change":             `local x = 1 for i = 1, 200 do if i == 150 then x = "str" end if type(x) == "number" then x = x + 1 end end return x`,
	"int to float change":     `local x = 1 for i = 1, 200 do if i == 120 then x = x + 0.5 end x = x + 1 end return x`,
	"array growth":            `local t = {} for i = 1, 3000 do t[#t + 1] = i end return #t, t[1], t[3000]`,
	"sparse write":            `local t = {1, 2, 3} for i = 1, 100 do t[i * 2] = i end local c = 0 for k in pairs(t) do c = c + 1 end return c`,
	"pcall in loop":           `local s = 0 for i = 1, 200 do local ok, v = pcall(function() if i % 50 == 0 then error("x") end return i end) if ok then s = s + v end end return s`,
	"coroutine":               `local co = coroutine.wrap(function() for i = 1, 300 do coroutine.yield(i * i) end end) local s = 0 for i = 1, 300 do s = s + co() end return s`,
	"generic for":             `local t = {} for i = 1, 100 do t[i] = i end local s = 0 for i, v in ipairs(t) do s = s + i * v end for k, v in pairs(t) do s = s + v end return s`,
	"string ops":              `local s = 0 for i = 1, 200 do local str = string.rep("a", i % 5) .. "b" s = s + #str + string.byte(str, 1) end return s`,
	"metamethods":             `local mt = {__add = function(a, b) return setmetatable({v = a.v + b.v}, getmetatable(a)) end} local acc = setmetatable({v = 0}, mt) local one = setmetatable({v = 1}, mt) for i = 1, 200 do acc = acc + one end return acc.v`,
	"index metamethod":        `local t = setmetatable({}, {__index = function(_, k) return k * 2 end}) local s = 0 for i = 1, 200 do s = s + t[i] end return s`,
	"newindex":                `local log = 0 local t = setmetatable({}, {__newindex = function(tb, k, v) log = log + v rawset(tb, k, v) end}) for i = 1, 100 do t[i] = i end for i = 1, 100 do t[i] = i + 1 end return log, t[100]`,
	"length":                  `local t = {} local s = 0 for i = 1, 300 do t[#t + 1] = i; s = s + #t end return s`,
	"comparison chain":        `local c = 0 for i = 1, 300 do local f = i / 2 if f == i // 2 then c = c + 1 end if i < 150.5 then c = c + 2 end if i <= 10 then c = c + 4 end if i ~= 7 then c = c + 8 end end return c`,
	"bit ops":                 `local x = 1 for i = 1, 300 do x = ((x << 3) ~ (x >> 2) | i) & 0xFFFFFFFF end return x`,
	"integer overflow":        `local x = 9223372036854775000 for i = 1, 1000 do x = x + 3 end return x`,
	"floor div and mod":       `local s = 0 for i = -100, 100 do for j = 1, 7 do s = s + i // j + i % j + i // -j + i % -j end end return s`,
	"float compare nan":       `local n, c = 0/0, 0 for i = 1, 100 do if n < i then c = c + 1 end if not (n >= i) then c = c + 10 end if n ~= n then c = c + 100 end end return c`,
	"sqrt pow":                `local s = 0 for i = 1, 200 do s = s + i ^ 2 + i ^ 0.5 + (i * 1.5) ^ 2 end return s`,
	"unary":                   `local a, b = 0, 0.0 for i = 1, 200 do a = a - -i; b = b + -(i * 0.5) end return a, b`,
	"many locals":             `local a,b,c,d,e,f,g,h,k,l,m,n,o,p,q,r = 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16 for i = 1, 300 do a,b,c,d,e,f,g,h = b+1,c+a,d+b,e+c,f+d,g+e,h+f,a+g k,l,m,n,o,p,q,r = l*1.5,m+k,n-l,o+m,p-n,q+o,r-p,k+q end return a,b,c,d,e,f,g,h,k,l,m,n,o,p,q,r`,
	"swap":                    `local a, b, c = 1, 2, 3 for i = 1, 301 do a, b, c = b, c, a end return a, b, c`,
	"float swap":              `local a, b, c = 1.5, 2.5, 3.5 for i = 1, 302 do a, b, c = c + 1, a, b end return a, b, c`,
	"loop with goto":          `local s, i = 0, 0 ::top:: i = i + 1 if i % 3 == 0 then goto top end s = s + i if i < 300 then goto top end return s`,
	"vararg":                  `local function sum(...) local s = 0 for i = 1, select("#", ...) do s = s + select(i, ...) end return s end local t = 0 for i = 1, 100 do t = t + sum(i, 2, 3) end return t`,
	"recursion":               `local function fib(n) if n < 2 then return n end return fib(n - 1) + fib(n - 2) end local s = 0 for i = 1, 15 do s = s + fib(i) end return s`,
	"method calls":            `local obj = {v = 0} function obj:add(n) self.v = self.v + n return self end for i = 1, 300 do obj:add(i):add(1) end return obj.v`,
	"numeric strings":         `local s = 0 for i = 1, 100 do s = s + ("10" + i) end return s`,
	"tostring in loop":        `local t = {} for i = 1, 50 do t[#t + 1] = tostring(i * 1.5) end return table.concat(t, ",")`,
	"limit float":             `local c = 0 for i = 1, 10.5 do c = c + i end for i = 10, 1.5, -1 do c = c + i end return c`,
	"empty loops":             `local c = 0 for i = 5, 1 do c = c + 1 end for i = 1, 0 do c = c + 1 end for i = 1, 1 do c = c + 1 end return c`,
	"big loop":                `local s = 0 for i = 1, 200000 do s = s + (i & 255) end return s`,
	"loop var capture":        `local fs = {} for i = 1, 100 do local j = i * 2 fs[i] = function() j = j + 1 return j end end local s = 0 for i = 1, 100 do s = s + fs[i]() + fs[i]() end return s`,
}

func TestJITPrograms(t *testing.T) {
	skipWithoutJIT(t)
	for name, src := range jitPrograms {
		name, src := name, src
		t.Run(name, func(t *testing.T) {
			checkJITMatchesInterpreter(t, name, src)
		})
	}
}

// TestJITCompilesLoops checks that typical numeric loops actually run as
// native code.
func TestJITCompilesLoops(t *testing.T) {
	skipWithoutJIT(t)
	for _, name := range []string{"int sum", "float sum", "while", "nested", "table fill and sum"} {
		for _, version := range []LanguageVersion{Lua51, Lua55} {
			_, st := runChunk(jitTestOptions(version, 5), jitPrograms[name])
			if st.Compiled == 0 || st.Entries == 0 {
				t.Errorf("%s (%v): no native code was executed: %s", name, version, st)
			}
		}
	}
}

// TestJITLua55Conformance runs the Lua 5.5 conformance scripts with the
// JIT compiling every loop almost immediately.
func TestJITLua55Conformance(t *testing.T) {
	skipWithoutJIT(t)
	for _, group := range []string{"core", "strings", "mtio", "base"} {
		for _, threshold := range []int{1, 3} {
			group, threshold := group, threshold
			t.Run(fmt.Sprintf("%s-%d", group, threshold), func(t *testing.T) {
				runLua55Scripts(t, group, jitTestOptions(Lua55, threshold))
			})
		}
	}
}

// TestJITSupportedPlatforms makes sure that the JIT tests do not skip
// themselves silently on the platforms the JIT is built for.
func TestJITSupportedPlatforms(t *testing.T) {
	if (runtime.GOOS != "linux" && runtime.GOOS != "darwin") || (runtime.GOARCH != "amd64" && runtime.GOARCH != "arm64") {
		if jitSupported() {
			t.Errorf("the JIT claims to support %s/%s", runtime.GOOS, runtime.GOARCH)
		}
		return
	}
	if !jitSupported() {
		t.Fatalf("the JIT is not available on %s/%s", runtime.GOOS, runtime.GOARCH)
	}
	out, st := runChunk(jitTestOptions(Lua55, 2), `local s = 0 for i = 1, 1000 do s = s + i end return s`)
	if out != "number:500500" || st.Compiled == 0 || st.Entries == 0 {
		t.Errorf("no native code ran: %q, %s", out, st)
	}
}

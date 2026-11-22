package lua

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// mtioHelperEnv names the environment variable that turns the test binary
// into a helper process running a Lua chunk (see runMtioHelper).
const mtioHelperEnv = "GOPHERLUA_MTIO_HELPER_CHUNK"

func TestLua55Mtio(t *testing.T) {
	runLua55Scripts(t, "mtio", Options{})
}

func TestLua55MtioReference(t *testing.T) {
	checkLua55Reference(t, "mtio")
}

// TestLua55MtioTypedArrays runs the scripts with unboxed array parts
// enabled, so that the library functions are exercised on the typed
// table representations as well.
func TestLua55MtioTypedArrays(t *testing.T) {
	for _, file := range lua55ScriptFiles(t, "mtio") {
		file := file
		t.Run(filepath.Base(file), func(t *testing.T) {
			L := NewState(Options{LanguageVersion: Lua55})
			defer L.Close()
			L.typedArrays = true
			if err := L.DoFile(file); err != nil {
				t.Fatalf("%s: %v", file, err)
			}
		})
	}
}

// libraryNames returns the keys of a library table in sorted order, each
// together with the Lua type of its value ("name:type").
func libraryNames(L *LState, lib string) []string {
	types := map[string]string{}
	var names []string
	L.GetGlobal(lib).(*LTable).ForEach(func(k, v LValue) {
		names = append(names, k.String())
		types[k.String()] = v.Type().String()
	})
	sort.Strings(names)
	for i, name := range names {
		names[i] = name + ":" + types[name]
	}
	return names
}

// mtioLibraries maps a profile to the expected contents of the libraries
// covered by this file.
var mtioLibraries = map[LanguageVersion]map[string]string{
	// The Lua 5.1 profile must keep exactly the upstream GopherLua contents.
	Lua51: {
		"math": "abs:function acos:function asin:function atan:function atan2:function ceil:function " +
			"cos:function cosh:function deg:function exp:function floor:function fmod:function " +
			"frexp:function huge:number ldexp:function log:function log10:function max:function " +
			"min:function mod:function modf:function pi:number pow:function rad:function " +
			"random:function randomseed:function sin:function sinh:function sqrt:function " +
			"tan:function tanh:function",
		"table": "concat:function getn:function insert:function maxn:function remove:function sort:function",
		"os": "clock:function date:function difftime:function execute:function exit:function " +
			"getenv:function remove:function rename:function setenv:function setlocale:function " +
			"time:function tmpname:function",
		"io": "close:function flush:function input:function lines:function open:function " +
			"output:function popen:function read:function stderr:userdata stdin:userdata " +
			"stdout:userdata tmpfile:function type:function write:function",
	},
	// The Lua 5.5 profile matches the reference interpreter.
	Lua55: {
		"math": "abs:function acos:function asin:function atan:function ceil:function cos:function " +
			"deg:function exp:function floor:function fmod:function frexp:function huge:number " +
			"ldexp:function log:function max:function maxinteger:number min:function " +
			"mininteger:number modf:function pi:number rad:function random:function " +
			"randomseed:function sin:function sqrt:function tan:function tointeger:function " +
			"type:function ult:function",
		"table": "concat:function create:function insert:function move:function pack:function " +
			"remove:function sort:function unpack:function",
		"os": "clock:function date:function difftime:function execute:function exit:function " +
			"getenv:function remove:function rename:function setlocale:function time:function " +
			"tmpname:function",
		"io": "close:function flush:function input:function lines:function open:function " +
			"output:function popen:function read:function stderr:userdata stdin:userdata " +
			"stdout:userdata tmpfile:function type:function write:function",
	},
}

func TestMtioLibraryContents(t *testing.T) {
	for version, libs := range mtioLibraries {
		L := NewState(Options{LanguageVersion: version})
		for lib, want := range libs {
			if got := strings.Join(libraryNames(L, lib), " "); got != want {
				t.Errorf("%v: contents of %s:\n got  %s\n want %s", version, lib, got, want)
			}
		}
		L.Close()
	}
}

// TestLua51MtioUnchanged pins results of the Lua 5.1 profile that must
// not be affected by the Lua 5.5 implementations.
func TestLua51MtioUnchanged(t *testing.T) {
	const script = `
		local function eq(a, b) return a == b and type(a) == type(b) end
		assert(tostring(math.floor(3.7)) == "3" and tostring(math.abs(-3)) == "3")
		assert(math.huge == 1.7976931348623157e308)
		assert(math.mod(7, 3) == 1 and math.pow(2, 10) == 1024 and math.log10(100) == 2)
		assert(math.max(1, 2.5) == 2.5 and math.fmod(7, 3) == 1)
		local ok, err = pcall(math.max)
		assert(not ok and string.find(err, "wrong number of arguments", 1, true))
		local t = {3, 1, 2}
		table.sort(t)
		assert(table.concat(t, ",") == "1,2,3" and table.getn(t) == 3 and table.maxn(t) == 3)
		table.insert(t, 1, 0)
		table.insert(t, 9)
		assert(table.concat(t, ",") == "0,1,2,3,9" and table.remove(t) == 9 and table.remove(t, 1) == 0)
		ok, err = pcall(table.insert, {})
		assert(not ok and string.find(err, "wrong number of arguments", 1, true))
		ok, err = pcall(table.concat, {1, {}, 3})
		assert(not ok and string.find(err, "invalid value (table) at index 2 in table for concat", 1, true))
		assert(table.unpack == nil and table.pack == nil and table.move == nil and table.create == nil)
		assert(math.tointeger == nil and math.type == nil and math.ult == nil and math.maxinteger == nil)
		assert(os.setlocale() == false and type(os.time()) == "number" and os.difftime(5, 3) == 2)
		assert(os.date("!%Y-%m-%d", 0) == "1970-01-01" and os.date("!*t", 0).yday == 0)
		assert(io.type(io.stdout) == "file" and tostring(io.stdout) == "file")
		assert(getmetatable(io.stdout).__index == getmetatable(io.stdout))
		assert(getmetatable(io.stdout).__close == nil and getmetatable(io.stdout).__name == nil)
		local name = os.tmpname()
		local f = assert(io.open(name, "w"))
		assert(f:write("a", 1, 2.5, "\n") == true and f:flush() == true)
		assert(f:close() == true and tostring(f) == "file (closed)" and io.type(f) == "closed file")
		f = assert(io.open(name))
		assert(f:read("*l") == "a12.5" and f:read("*a") == "" and f:seek("set", 1) == 1)
		assert(f:read("*n") == 12.5)
		f:close()
		local lines = {}
		for l in io.lines(name) do lines[#lines + 1] = l end
		assert(#lines == 1 and lines[1] == "a12.5")
		assert(os.remove(name) == true)
		local r1, r2, r3 = io.open(name .. "/missing")
		assert(r1 == nil and type(r2) == "string" and r3 == 1)
	`
	for _, typed := range []bool{false, true} {
		L := NewState()
		L.typedArrays = typed
		if err := L.DoString(script); err != nil {
			t.Errorf("typed arrays %v: %v", typed, err)
		}
		L.Close()
	}
}

// TestLua55MtioStdin checks reading from the standard input, which the
// scripts cannot do hermetically. The standard files are bound when the
// package is initialized, so the chunk runs in a helper process.
func TestLua55MtioStdin(t *testing.T) {
	const input = "first line\n 42 0x10 rest\nabcdef\nl2\nl3"
	const chunk = `
		assert(io.input() == io.stdin and io.type(io.stdin) == "file")
		assert(io.read() == "first line")
		local a, b = io.read("n", "n")
		assert(a == 42 and math.type(a) == "integer" and b == 16)
		assert(io.read("L") == " rest\n" and io.read(3) == "abc" and io.stdin:read(0) == "")
		local lines = {}
		for l in io.lines() do lines[#lines + 1] = l end
		assert(#lines == 3 and lines[1] == "def" and lines[2] == "l2" and lines[3] == "l3")
		assert(io.read() == nil and io.read("a") == "" and io.read(0) == nil and io.read("n") == nil)
		local r = table.pack(io.stdin:write("x"))
		assert(r.n == 4 and r[1] == nil and r[4] == 0)
		r = table.pack(io.stdin:close())
		assert(r.n == 2 and r[1] == nil and r[2] == "cannot close standard file")
		io.write("stdin ok")
		os.exit(0)
	`
	if code, stdout := runMtioHelper(t, chunk, input); code != 0 || stdout != "stdin ok" {
		t.Errorf("exit code %d, output %q", code, stdout)
	}
}

// runMtioHelper runs a Lua 5.5 chunk in a separate process (the test
// binary itself) with the given standard input and returns its exit code
// and standard output.
func runMtioHelper(t *testing.T, chunk, stdin string) (int, string) {
	t.Helper()
	cmd := exec.Command(os.Args[0], "-test.run=^TestLua55MtioExitHelper$")
	cmd.Env = append(os.Environ(), mtioHelperEnv+"="+chunk)
	cmd.Stdin = strings.NewReader(stdin)
	cmd.Stderr = os.Stderr
	var stdout bytes.Buffer
	cmd.Stdout = &stdout
	err := cmd.Run()
	if exitErr, ok := err.(*exec.ExitError); ok {
		return exitErr.ExitCode(), stdout.String()
	}
	if err != nil {
		t.Fatalf("cannot run the helper process: %v", err)
	}
	return 0, stdout.String()
}

// TestLua55MtioExitHelper is not a test: it is the body of the helper
// process started by runMtioHelper.
func TestLua55MtioExitHelper(t *testing.T) {
	chunk := os.Getenv(mtioHelperEnv)
	if chunk == "" {
		t.Skip("helper process only")
	}
	L := NewState(Options{LanguageVersion: Lua55})
	if err := L.DoString(chunk); err != nil {
		os.Stderr.WriteString(err.Error() + "\n")
		os.Exit(98)
	}
	os.Exit(99) // the chunk was expected to end the process
}

// mtioExitCases lists chunks that end the process together with the
// expected exit code and standard output.
var mtioExitCases = []struct {
	chunk  string
	code   int
	stdout string
}{
	{`os.exit()`, 0, ""},
	{`os.exit(true)`, 0, ""},
	{`os.exit(false)`, 1, ""},
	{`os.exit(3)`, 3, ""},
	{`os.exit(3.0)`, 3, ""},
	{`os.exit("7")`, 7, ""},
	{`os.exit(4, true)`, 4, ""},
	{`os.exit(true, true)`, 0, ""},
	{`os.exit(false, false)`, 1, ""},
	{`os.exit(nil, true)`, 0, ""},
	{`io.write("plain"); os.exit(5)`, 5, "plain"},
	{`io.stdout:setvbuf("full", 4096); io.write("buffered"); os.exit(6)`, 6, "buffered"},
	{`io.stdout:setvbuf("line"); io.write("no newline"); os.exit(0, true)`, 0, "no newline"},
	{`local f <close> = setmetatable({}, {__close = function() io.write("closed") end}); os.exit(2)`, 2, ""},
	// closing the state closes the pending to-be-closed variables
	{`local f <close> = setmetatable({}, {__close = function() io.write("f") end})
	  local g <close> = setmetatable({}, {__close = function() error("ignored") end})
	  local function inner()
	    local h <close> = setmetatable({}, {__close = function(_, e) io.write("h", tostring(e)) end})
	    os.exit(8, true)
	  end
	  inner()`, 8, "hnilf"},
}

func TestLua55MtioExit(t *testing.T) {
	for _, tc := range mtioExitCases {
		if code, stdout := runMtioHelper(t, tc.chunk, ""); code != tc.code || stdout != tc.stdout {
			t.Errorf("%s: exit code %d, output %q; want %d, %q", tc.chunk, code, stdout, tc.code, tc.stdout)
		}
	}
}

// TestLua55MtioExitReference guards the expectations of mtioExitCases
// with the reference interpreter.
func TestLua55MtioExitReference(t *testing.T) {
	bin, err := exec.LookPath("lua5.5")
	if err != nil {
		t.Skip("reference interpreter lua5.5 not installed")
	}
	if os.Getenv("GOPHERLUA_SKIP_REFERENCE") != "" {
		t.Skip("reference checks disabled")
	}
	for _, tc := range mtioExitCases {
		cmd := exec.Command(bin, "-e", tc.chunk)
		var stdout bytes.Buffer
		cmd.Stdout = &stdout
		code := 0
		if exitErr, ok := cmd.Run().(*exec.ExitError); ok {
			code = exitErr.ExitCode()
		}
		if code != tc.code || stdout.String() != tc.stdout {
			t.Errorf("reference: %s: exit code %d, output %q; want %d, %q", tc.chunk, code, stdout.String(), tc.code, tc.stdout)
		}
	}
}

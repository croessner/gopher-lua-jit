package lua

import (
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// lua55ScriptFiles returns the Lua scripts of a conformance test group
// (a directory below _lua55-tests).
func lua55ScriptFiles(t *testing.T, group string) []string {
	t.Helper()
	files, err := filepath.Glob(filepath.Join("_lua55-tests", group, "*.lua"))
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(files)
	return files
}

// runLua55Scripts runs every script of a conformance test group in a
// fresh state using the given options (the language version is forced to
// Lua55). A script passes if it runs without raising an error.
func runLua55Scripts(t *testing.T, group string, opts Options) {
	t.Helper()
	opts.LanguageVersion = Lua55
	for _, file := range lua55ScriptFiles(t, group) {
		file := file
		t.Run(filepath.Base(file), func(t *testing.T) {
			L := NewState(opts)
			defer L.Close()
			if err := L.DoFile(file); err != nil {
				t.Fatalf("%s: %v", file, err)
			}
		})
	}
}

// checkLua55Reference runs the scripts of a group with the reference
// Lua 5.5 interpreter when it is installed. This guards the expectations
// encoded in the scripts. Scripts named *_gopher.lua document intentional
// deviations and are skipped.
func checkLua55Reference(t *testing.T, group string) {
	t.Helper()
	bin, err := exec.LookPath("lua5.5")
	if err != nil {
		t.Skip("reference interpreter lua5.5 not installed")
	}
	if os.Getenv("GOPHERLUA_SKIP_REFERENCE") != "" {
		t.Skip("reference checks disabled")
	}
	for _, file := range lua55ScriptFiles(t, group) {
		if strings.HasSuffix(file, "_gopher.lua") {
			continue
		}
		file := file
		t.Run(filepath.Base(file), func(t *testing.T) {
			out, err := exec.Command(bin, file).CombinedOutput()
			if err != nil {
				t.Fatalf("reference lua5.5 rejects %s: %v\n%s", file, err, out)
			}
		})
	}
}

func TestLua55Smoke(t *testing.T) {
	runLua55Scripts(t, "smoke", Options{})
}

func TestLua55SmokeReference(t *testing.T) {
	checkLua55Reference(t, "smoke")
}

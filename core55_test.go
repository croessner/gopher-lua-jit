package lua

import "testing"

// TestLua55Core runs the core language conformance scripts of the Lua 5.5
// profile (lexer, arithmetic, control flow, functions, metatables, error
// handling, coroutines) in our runtime.
func TestLua55Core(t *testing.T) {
	runLua55Scripts(t, "core", Options{})
}

// TestLua55CoreReference guards the expectations of the core scripts with
// the reference interpreter.
func TestLua55CoreReference(t *testing.T) {
	checkLua55Reference(t, "core")
}

// TestLua55CorePendingReference guards the expectations of the scripts in
// core-pending with the reference interpreter. Those scripts describe
// behaviour our runtime does not implement correctly yet, so they are not
// run against it; a script moves to the core group once it passes.
func TestLua55CorePendingReference(t *testing.T) {
	checkLua55Reference(t, "core-pending")
}

// Command basic shows how to embed the runtime: run Lua 5.5 code, call a
// Lua function from Go and expose a Go function to Lua.
package main

import (
	"fmt"
	"log"

	lua "github.com/yuin/gopher-lua"
)

func main() {
	// The zero LanguageVersion is the GopherLua compatible Lua 5.1
	// profile; Lua55 selects Lua 5.5 semantics.
	L := lua.NewState(lua.Options{LanguageVersion: lua.Lua55})
	defer L.Close()

	// A Go function callable from Lua. In the Lua 5.5 profile integers
	// are pushed as lua.LInteger and floats as lua.LNumber.
	L.SetGlobal("double", L.NewFunction(func(L *lua.LState) int {
		L.Push(L.CheckInteger(1) * 2)
		return 1
	}))

	if err := L.DoString(`
		local total <const> = double(21)
		function greet(name)
			return "hello " .. name .. ", the answer is " .. total .. " (" .. math.type(total) .. ")"
		end
	`); err != nil {
		log.Fatal(err)
	}

	// Call the Lua function "greet" from Go.
	if err := L.CallByParam(lua.P{Fn: L.GetGlobal("greet"), NRet: 1, Protect: true}, lua.LString("gopher")); err != nil {
		log.Fatal(err)
	}
	fmt.Println(L.Get(-1))
	L.Pop(1)
}

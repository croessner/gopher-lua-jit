// Command pool shows the typical server setup: a script is parsed and
// compiled once, and a pool of states executes it concurrently with a
// deadline per request.
package main

import (
	"context"
	"fmt"
	"log"
	"strings"
	"sync"
	"time"

	lua "github.com/yuin/gopher-lua"
	"github.com/yuin/gopher-lua/parse"
)

const script = `
function handle(n)
  local sum = 0
  for i = 1, n do sum = sum + i % 7 end
  return sum
end
`

// compile turns the script into a prototype that can be shared by any
// number of states.
func compile() *lua.FunctionProto {
	chunk, err := parse.ParseWithOptions(strings.NewReader(script), "handler.lua", parse.Options{Version: parse.Lua55})
	if err != nil {
		log.Fatal(err)
	}
	proto, err := lua.CompileWithOptions(chunk, "handler.lua", lua.CompileOptions{LanguageVersion: lua.Lua55})
	if err != nil {
		log.Fatal(err)
	}
	return proto
}

func main() {
	proto := compile()
	pool := sync.Pool{New: func() interface{} {
		// A state must only be used by one goroutine at a time. Compiled
		// native code belongs to the state that produced it.
		L := lua.NewState(lua.Options{
			LanguageVersion: lua.Lua55,
			JIT:             lua.JITOptions{Enabled: true},
		})
		L.Push(L.NewFunctionFromProto(proto))
		if err := L.PCall(0, 0, nil); err != nil {
			log.Fatal(err)
		}
		return L
	}}

	var wg sync.WaitGroup
	results := make([]string, 8)
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			L := pool.Get().(*lua.LState)
			defer pool.Put(L)

			// Deadlines are honored by the interpreter and, at its safe
			// points, by native code.
			ctx, cancel := context.WithTimeout(context.Background(), time.Second)
			defer cancel()
			L.SetContext(ctx)
			defer L.RemoveContext()

			if err := L.CallByParam(lua.P{Fn: L.GetGlobal("handle"), NRet: 1, Protect: true}, lua.LInteger(100000*(i+1))); err != nil {
				results[i] = "error: " + err.Error()
				return
			}
			results[i] = L.Get(-1).String()
			L.Pop(1)
		}(i)
	}
	wg.Wait()
	for i, r := range results {
		fmt.Printf("request %d: %s\n", i, r)
	}
}

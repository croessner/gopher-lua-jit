// Command tablecompat prints, for a range of seeds, a digest of the trace
// that testdata/table_compat.lua produces on the GopherLua implementation
// the module file selects. With the upstream module file it writes the
// expectations that the tests of this runtime compare against:
//
//	cd benchmarks
//	GOFLAGS=-mod=mod go run -modfile=go.upstream.mod ./tablecompat > ../testdata/table_compat_upstream.txt
package main

import (
	"crypto/sha256"
	"flag"
	"fmt"
	"os"

	lua "github.com/yuin/gopher-lua"
)

func main() {
	script := flag.String("script", "../testdata/table_compat.lua", "path of the Lua script")
	seeds := flag.Int("seeds", 500, "number of seeds")
	flag.Parse()
	L := lua.NewState()
	defer L.Close()
	if err := L.DoFile(*script); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	run := L.Get(-1)
	L.Pop(1)
	for seed := 1; seed <= *seeds; seed++ {
		if err := L.CallByParam(lua.P{Fn: run, NRet: 1, Protect: true}, lua.LNumber(seed)); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		trace := L.Get(-1).String()
		L.Pop(1)
		fmt.Printf("%d %x %d\n", seed, sha256.Sum256([]byte(trace)), len(trace))
	}
}

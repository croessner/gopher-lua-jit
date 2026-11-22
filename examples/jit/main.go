// Command jit runs a numeric kernel with and without the native JIT and
// prints the JIT statistics.
package main

import (
	"fmt"
	"log"
	"os"
	"time"

	lua "github.com/yuin/gopher-lua"
)

const kernel = `
local inside, n = 0, 400
for y = 0, n - 1 do
  local ci = 2.0 * y / n - 1.0
  for x = 0, n - 1 do
    local cr = 2.0 * x / n - 1.5
    local zr, zi, it = 0.0, 0.0, 0
    while it < 50 and zr * zr + zi * zi < 4.0 do
      zr, zi = zr * zr - zi * zi + cr, 2.0 * zr * zi + ci
      it = it + 1
    end
    if it == 50 then inside = inside + 1 end
  end
end
return inside
`

func run(jit bool) {
	L := lua.NewState(lua.Options{
		LanguageVersion: lua.Lua55,
		JIT: lua.JITOptions{
			Enabled:   jit,
			Threshold: 50,        // loop iterations before compiling
			Log:       os.Stderr, // one line per JIT event
		},
	})
	defer L.Close()

	start := time.Now()
	if err := L.DoString(kernel); err != nil {
		log.Fatal(err)
	}
	fmt.Printf("jit=%-5v result=%v time=%v\n", jit, L.Get(-1), time.Since(start).Round(time.Microsecond))
	fmt.Println("  ", L.JITStats())
}

func main() {
	run(false)
	run(true)
}

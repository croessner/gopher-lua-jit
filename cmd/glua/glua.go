package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"runtime/pprof"

	lua "github.com/yuin/gopher-lua"
	"github.com/yuin/gopher-lua/parse"
)

func main() {
	os.Exit(mainAux())
}

func mainAux() int {
	var opt_e, opt_l, opt_p, opt_lua string
	var opt_i, opt_v, opt_dt, opt_dc, opt_jit, opt_jitstats, opt_jitlog bool
	var opt_m, opt_jitthreshold int
	flag.StringVar(&opt_e, "e", "", "")
	flag.StringVar(&opt_l, "l", "", "")
	flag.StringVar(&opt_p, "p", "", "")
	flag.StringVar(&opt_lua, "lua", "5.1", "")
	flag.IntVar(&opt_m, "mx", 0, "")
	flag.BoolVar(&opt_i, "i", false, "")
	flag.BoolVar(&opt_v, "v", false, "")
	flag.BoolVar(&opt_dt, "dt", false, "")
	flag.BoolVar(&opt_dc, "dc", false, "")
	flag.BoolVar(&opt_jit, "jit", false, "")
	flag.BoolVar(&opt_jitstats, "jitstats", false, "")
	flag.BoolVar(&opt_jitlog, "jitlog", false, "")
	flag.IntVar(&opt_jitthreshold, "jit-threshold", 0, "")
	flag.Usage = func() {
		fmt.Println(`Usage: glua [options] [script [args]].
Available options are:
  -e stat      execute string 'stat'
  -l name      require library 'name'
  -lua version language profile: 5.1 (default) or 5.5
  -jit         enable the native JIT compiler
  -jit-threshold n  loop iterations before a loop is compiled
  -jitstats    print JIT statistics on exit
  -jitlog      log JIT events to stderr
  -mx MB       memory limit(default: unlimited)
  -dt          dump AST trees
  -dc          dump VM codes
  -i           enter interactive mode after executing 'script'
  -p file      write cpu profiles to the file
  -v           show version information`)
	}
	flag.Parse()
	if len(opt_p) != 0 {
		f, err := os.Create(opt_p)
		if err != nil {
			fmt.Println(err.Error())
			os.Exit(1)
		}
		pprof.StartCPUProfile(f)
		defer pprof.StopCPUProfile()
	}
	if len(opt_e) == 0 && !opt_i && !opt_v && flag.NArg() == 0 {
		opt_i = true
	}

	status := 0

	opts := lua.Options{
		CallStackSize: lua.CallStackSize,
		RegistrySize:  lua.RegistrySize,
	}
	popts := parse.Options{}
	switch opt_lua {
	case "5.1", "51":
	case "5.5", "55":
		opts.LanguageVersion = lua.Lua55
		popts.Version = parse.Lua55
	default:
		fmt.Println("unknown language profile: " + opt_lua)
		return 1
	}
	opts.JIT.Enabled = opt_jit
	opts.JIT.Threshold = opt_jitthreshold
	if opt_jitlog {
		opts.JIT.Log = os.Stderr
	}

	L := lua.NewState(opts)
	defer L.Close()
	if opt_m > 0 {
		L.SetMx(opt_m)
	}

	if opt_v || opt_i {
		fmt.Println(lua.PackageCopyRight)
	}

	if len(opt_l) > 0 {
		if err := L.DoFile(opt_l); err != nil {
			fmt.Println(err.Error())
		}
	}

	if nargs := flag.NArg(); nargs > 0 {
		script := flag.Arg(0)
		argtb := L.NewTable()
		for i := 1; i < nargs; i++ {
			L.RawSetInt(argtb, i, lua.LString(flag.Arg(i)))
		}
		L.SetGlobal("arg", argtb)
		if opt_dt || opt_dc {
			file, err := os.Open(script)
			if err != nil {
				fmt.Println(err.Error())
				return 1
			}
			chunk, err2 := parse.ParseWithOptions(file, script, popts)
			if err2 != nil {
				fmt.Println(err2.Error())
				return 1
			}
			if opt_dt {
				fmt.Println(parse.Dump(chunk))
			}
			if opt_dc {
				proto, err3 := lua.CompileWithOptions(chunk, script, lua.CompileOptions{LanguageVersion: opts.LanguageVersion})
				if err3 != nil {
					fmt.Println(err3.Error())
					return 1
				}
				fmt.Println(proto.String())
			}
		}
		if err := L.DoFile(script); err != nil {
			fmt.Println(err.Error())
			status = 1
		}
	}

	if len(opt_e) > 0 {
		if err := L.DoString(opt_e); err != nil {
			fmt.Println(err.Error())
			status = 1
		}
	}

	if opt_i {
		doREPL(L)
	}
	if opt_jitstats {
		fmt.Fprintln(os.Stderr, L.JITStats().String())
	}
	return status
}

// do read/eval/print/loop
func doREPL(L *lua.LState) {
	rd := bufio.NewReader(os.Stdin)
	for {
		if str, err := loadline(rd, L); err == nil {
			if err := L.DoString(str); err != nil {
				fmt.Println(err)
			}
		} else { // error on loadline
			if err != io.EOF {
				fmt.Println(err)
			}
			return
		}
	}
}

func incomplete(err error) bool {
	if lerr, ok := err.(*lua.ApiError); ok {
		if perr, ok := lerr.Cause.(*parse.Error); ok {
			return perr.Pos.Line == parse.EOF
		}
	}
	return false
}

func readline(rd *bufio.Reader, prompt string) (string, error) {
	fmt.Print(prompt)
	line, err := rd.ReadString('\n')
	if err != nil && len(line) == 0 {
		return "", err
	}
	for len(line) > 0 && (line[len(line)-1] == '\n' || line[len(line)-1] == '\r') {
		line = line[:len(line)-1]
	}
	return line, nil
}

func loadline(rd *bufio.Reader, L *lua.LState) (string, error) {
	line, err := readline(rd, "> ")
	if err != nil {
		return "", err
	}
	if _, err := L.LoadString("return " + line); err == nil { // try add return <...> then compile
		return "return " + line, nil
	}
	return multiline(line, rd, L)
}

func multiline(ml string, rd *bufio.Reader, L *lua.LState) (string, error) {
	for {
		if _, err := L.LoadString(ml); err == nil { // try compile
			return ml, nil
		} else if !incomplete(err) { // syntax error , but not EOF
			return ml, nil
		} else {
			line, err := readline(rd, ">> ")
			if err != nil {
				return "", err
			}
			ml = ml + "\n" + line
		}
	}
}

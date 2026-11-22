//go:build (linux || darwin) && (amd64 || arm64)

package codecache

import (
	"math"
	"runtime"
	"runtime/debug"
	"sync"
	"sync/atomic"
	"testing"
	"unsafe"
)

// finish resolves the assembler output and fails the test on errors.
func finish(t testing.TB, bytes func() ([]byte, error)) []byte {
	t.Helper()
	code, err := bytes()
	if err != nil {
		t.Fatalf("assembler: %v", err)
	}
	return append([]byte(nil), code...)
}

func mustAlloc(t testing.TB, code []byte) *Block {
	t.Helper()
	b, err := Alloc(code)
	if err != nil {
		t.Fatalf("Alloc: %v", err)
	}
	return b
}

func TestCallBasic(t *testing.T) {
	b := mustAlloc(t, genAdd(t))
	defer b.Free()
	ctx := make([]uint64, 2)
	ctx[1] = 3
	for i := 0; i < 1000000; i++ {
		Call(b.Addr(), unsafe.Pointer(&ctx[0]))
	}
	if ctx[0] != 3000000 {
		t.Fatalf("got %d, want 3000000", ctx[0])
	}
}

func TestCallFloat(t *testing.T) {
	b := mustAlloc(t, genFloat(t))
	defer b.Free()
	ctx := make([]float64, 3)
	for i := 1; i <= 1000; i++ {
		ctx[0], ctx[1] = float64(i), 2.5
		Call(b.Addr(), unsafe.Pointer(&ctx[0]))
		if want := math.Sqrt(float64(i)) * 2.5; ctx[2] != want {
			t.Fatalf("i=%d: got %v, want %v", i, ctx[2], want)
		}
	}
}

// TestConcurrentGCPressure runs native code on many goroutines while other
// goroutines allocate aggressively and force garbage collections. The
// context buffers live in the Go heap and are only reachable through Go
// references held by the calling goroutine.
func TestConcurrentGCPressure(t *testing.T) {
	workers := runtime.GOMAXPROCS(0) * 2
	iterations := 200000
	if testing.Short() {
		iterations = 20000
	}
	var stop atomic.Bool
	var churn sync.WaitGroup
	for i := 0; i < 4; i++ {
		churn.Add(1)
		go func() {
			defer churn.Done()
			var keep [][]byte
			for !stop.Load() {
				keep = append(keep, make([]byte, 1<<12))
				if len(keep) > 256 {
					keep = nil
					runtime.GC()
				}
			}
		}()
	}
	var wg sync.WaitGroup
	errs := make(chan string, workers)
	for w := 0; w < workers; w++ {
		wg.Add(1)
		go func(w int) {
			defer wg.Done()
			b, err := Alloc(genAdd(t))
			if err != nil {
				errs <- err.Error()
				return
			}
			defer b.Free()
			for round := 0; round < 4; round++ {
				ctx := make([]uint64, 2) // fresh heap buffer per round
				ctx[1] = uint64(w + 1)
				for i := 0; i < iterations; i++ {
					Call(b.Addr(), unsafe.Pointer(&ctx[0]))
					if i%1024 == 0 {
						_ = make([]byte, 64) // allocate between native calls
					}
				}
				if want := uint64(iterations) * uint64(w+1); ctx[0] != want {
					errs <- "wrong sum"
					return
				}
			}
		}(w)
	}
	wg.Wait()
	stop.Store(true)
	churn.Wait()
	select {
	case e := <-errs:
		t.Fatal(e)
	default:
	}
}

// TestLongNativeLoopDuringGC checks that a goroutine spending a long time
// in native code does not break the collector: garbage collections wait
// for the native code to return and then proceed.
func TestLongNativeLoopDuringGC(t *testing.T) {
	b := mustAlloc(t, genLoop(t))
	defer b.Free()
	n := uint64(300000000)
	if testing.Short() {
		n = 30000000
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		ctx := make([]uint64, 2)
		ctx[0] = n
		Call(b.Addr(), unsafe.Pointer(&ctx[0]))
		if ctx[1] != n {
			t.Errorf("got %d iterations, want %d", ctx[1], n)
		}
	}()
	for {
		select {
		case <-done:
			return
		default:
			_ = make([]byte, 1<<16)
			runtime.GC()
		}
	}
}

// TestStackGrowthAroundNativeCalls interleaves native calls with deep Go
// recursion so that the goroutine stack is copied while frames that have
// called (and will call again) native code are live.
func TestStackGrowthAroundNativeCalls(t *testing.T) {
	b := mustAlloc(t, genAdd(t))
	defer b.Free()
	var rec func(depth int, ctx []uint64) uint64
	rec = func(depth int, ctx []uint64) uint64 {
		var pad [128]byte
		pad[depth%len(pad)] = byte(depth)
		Call(b.Addr(), unsafe.Pointer(&ctx[0]))
		if depth == 0 {
			return uint64(pad[0])
		}
		r := rec(depth-1, ctx)
		Call(b.Addr(), unsafe.Pointer(&ctx[0]))
		return r + uint64(pad[depth%len(pad)])
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		ctx := make([]uint64, 2)
		ctx[1] = 1
		rec(20000, ctx)
		if ctx[0] != 40001 {
			t.Errorf("got %d, want 40001", ctx[0])
		}
	}()
	<-done
}

func TestAllocFreeAccounting(t *testing.T) {
	code := genAdd(t)
	baseBytes, baseBlocks := LiveBytes(), LiveBlocks()
	blocks := make([]*Block, 0, 2000)
	for i := 0; i < 2000; i++ {
		blocks = append(blocks, mustAlloc(t, code))
	}
	if LiveBlocks() != baseBlocks+2000 {
		t.Fatalf("live blocks = %d", LiveBlocks()-baseBlocks)
	}
	for _, b := range blocks {
		if err := b.Free(); err != nil {
			t.Fatal(err)
		}
		if err := b.Free(); err != nil { // double free is a no-op
			t.Fatal(err)
		}
	}
	if LiveBytes() != baseBytes || LiveBlocks() != baseBlocks {
		t.Fatalf("leak: %d bytes, %d blocks", LiveBytes()-baseBytes, LiveBlocks()-baseBlocks)
	}
}

// TestWriteProtection verifies W^X: executable memory must not be
// writable.
func TestWriteProtection(t *testing.T) {
	b := mustAlloc(t, genAdd(t))
	defer b.Free()
	old := debug.SetPanicOnFault(true)
	defer debug.SetPanicOnFault(old)
	faulted := false
	func() {
		defer func() {
			if recover() != nil {
				faulted = true
			}
		}()
		b.mem[0] = 0xC3
	}()
	if !faulted {
		t.Fatal("executable memory is writable")
	}
}

func TestAllocEmpty(t *testing.T) {
	if _, err := Alloc(nil); err == nil {
		t.Fatal("expected an error for empty code")
	}
}

func BenchmarkCall(b *testing.B) {
	blk := mustAlloc(b, genAdd(b))
	defer blk.Free()
	ctx := make([]uint64, 2)
	for i := 0; i < b.N; i++ {
		Call(blk.Addr(), unsafe.Pointer(&ctx[0]))
	}
}

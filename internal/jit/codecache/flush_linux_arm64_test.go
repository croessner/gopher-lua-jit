package codecache

import "testing"

func TestCacheLineSizes(t *testing.T) {
	// CTR_EL0 of a typical core: DminLine = IminLine = 4 (16 words)
	if d, i := cacheLineSizes(0x84448004); d != 64 || i != 64 {
		t.Errorf("got %d/%d, want 64/64", d, i)
	}
	if d, i := cacheLineSizes(0x00050003); d != 128 || i != 32 {
		t.Errorf("got %d/%d, want 128/32", d, i)
	}
	if dataCacheLine < 16 || instCacheLine < 16 || dataCacheLine&(dataCacheLine-1) != 0 || instCacheLine&(instCacheLine-1) != 0 {
		t.Errorf("implausible cache line sizes of this machine: %d/%d", dataCacheLine, instCacheLine)
	}
}

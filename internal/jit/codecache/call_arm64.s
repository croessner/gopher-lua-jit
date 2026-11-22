//go:build linux || darwin

#include "textflag.h"

// func callJIT(entry uintptr, ctx unsafe.Pointer)
//
// The native code is entered with BLR and returns with RET (to R30). It
// preserves R18, R28, R29, R30 and SP. The assembler generated prologue
// and epilogue save and restore the link register of this function.
TEXT ·callJIT(SB), NOSPLIT, $16-16
	MOVD entry+0(FP), R0
	MOVD ctx+8(FP), R19
	CALL (R0)
	RET

// func flushICacheASM(start, end uintptr)
//
// Synchronizes the instruction cache with the data cache for the address
// range [start, end): DC CVAU and IC IVAU for every cache line (the line
// sizes are read from CTR_EL0), followed by the required barriers.
TEXT ·flushICacheASM(SB), NOSPLIT, $0-16
	MOVD start+0(FP), R0
	MOVD end+8(FP), R1
	MRS  CTR_EL0, R5
	UBFX $16, R5, $4, R6 // DminLine: log2 of the data line size in words
	MOVD $4, R2
	LSL  R6, R2, R2      // data cache line size in bytes
	SUB  $1, R2, R3
	BIC  R3, R0, R4
dloop:
	WORD $0xd50b7b24     // dc cvau, x4
	ADD  R2, R4
	CMP  R1, R4
	BLO  dloop
	WORD $0xd5033b9f     // dsb ish
	AND  $15, R5, R6     // IminLine: log2 of the instruction line size in words
	MOVD $4, R2
	LSL  R6, R2, R2      // instruction cache line size in bytes
	SUB  $1, R2, R3
	BIC  R3, R0, R4
iloop:
	WORD $0xd50b7524     // ic ivau, x4
	ADD  R2, R4
	CMP  R1, R4
	BLO  iloop
	WORD $0xd5033b9f     // dsb ish
	WORD $0xd5033fdf     // isb
	RET

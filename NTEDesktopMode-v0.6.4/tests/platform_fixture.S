// Signed, file-backed test code. Layout mirrors the five verified game helpers.
.section __TEXT,__text,regular,pure_instructions
.p2align 14
.globl _NTEPlatformFixturePage
_NTEPlatformFixturePage:
.space 0x3164
mov w0, #16
ret
mov w0, #0
ret
mov w0, #0
ret
mov w0, #0
ret
.space 0x70
mov w0, #1
ret
.space 0xe04

// Independent UI query on its own signed executable page.
.p2align 14
.globl _NTEUIPlatformFixturePage
_NTEUIPlatformFixturePage:
.space 0x3f34
mov w0, #2
ret
.space 0xc4

// Real arm64 setter ABI for the platform cursor adapter, in a signed test image.
.p2align 14
.globl _NTECursorFixturePage
_NTECursorFixturePage:
.space 0x1b28
str w1, [x0, #8]
ret
.space 0x10
strb w1, [x0, #0x30]
ret
.space 0x5ddc
// relative 0x7924: fallback original pointer preference
mov w0, #1
ret

.space 0x7bc
// relative 0x80e8: two-double homogeneous aggregate returned in d0/d1
ldp d0, d1, [x0, #0x10]
ret

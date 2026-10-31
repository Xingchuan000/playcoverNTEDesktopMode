// Signed, static trampolines: no executable code generation.
.text
.p2align 2
.globl _NTERoute_down
.private_extern _NTERoute_down
_NTERoute_down:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #0
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd10283ff
.inst 0x6d0623e9
.inst 0xa90757f6
.inst 0xa9084ff4
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #0]
br x16
.p2align 2
.globl _NTERoute_up
.private_extern _NTERoute_up
_NTERoute_up:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #1
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd10243ff
.inst 0xa9036ffc
.inst 0xa90467fa
.inst 0xa9055ff8
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #8]
br x16
.p2align 2
.globl _NTERoute_move
.private_extern _NTERoute_move
_NTERoute_move:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #2
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd10243ff
.inst 0xa90467fa
.inst 0xa9055ff8
.inst 0xa90657f6
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #16]
br x16
.p2align 2
.globl _NTERoute_pan
.private_extern _NTERoute_pan
_NTERoute_pan:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #3
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xa9be4ff4
.inst 0xa9017bfd
.inst 0x910043fd
.inst 0xaa0103f3
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #24]
br x16
.p2align 2
.globl _NTERoute_pinch
.private_extern _NTERoute_pinch
_NTERoute_pinch:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #4
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0x6dbd23e9
.inst 0xa9014ff4
.inst 0xa9027bfd
.inst 0x910083fd
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #32]
br x16
.p2align 2
.globl _NTERoute_wheel
.private_extern _NTERoute_wheel
_NTERoute_wheel:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #5
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd10343ff
.inst 0x6d0723e9
.inst 0xa90867fa
.inst 0xa9095ff8
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #40]
br x16
.p2align 2
.globl _NTERoute_drag_start
.private_extern _NTERoute_drag_start
_NTERoute_drag_start:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #6
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xa9bd57f6
.inst 0xa9014ff4
.inst 0xa9027bfd
.inst 0x910083fd
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #48]
br x16
.p2align 2
.globl _NTERoute_drag_end
.private_extern _NTERoute_drag_end
_NTERoute_drag_end:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #7
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xa9be4ff4
.inst 0xa9017bfd
.inst 0x910043fd
.inst 0xaa0003f3
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #56]
br x16
.p2align 2
.globl _NTERoute_leave
.private_extern _NTERoute_leave
_NTERoute_leave:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #8
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd10203ff
.inst 0xa9026ffc
.inst 0xa90367fa
.inst 0xa9045ff8
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #64]
br x16
.p2align 2
.globl _NTERoute_ios_touches
.private_extern _NTERoute_ios_touches
_NTERoute_ios_touches:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #9
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd10643ff
.inst 0x6d0f3bef
.inst 0x6d1033ed
.inst 0x6d112beb
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #72]
br x16
.p2align 2
.globl _NTERoute_ios_scroll
.private_extern _NTERoute_ios_scroll
_NTERoute_ios_scroll:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #10
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xf9401008
.inst 0xbd42b900
.inst 0x1e202820
.inst 0xbd02b900
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #80]
br x16
.p2align 2

.globl _NTERoute_scale
.private_extern _NTERoute_scale
_NTERoute_scale:
stp x29, x30, [sp, #-16]!
mov x29, sp
sub sp, sp, #208
stp x0, x1, [sp]
stp x2, x3, [sp, #16]
stp x4, x5, [sp, #32]
stp x6, x7, [sp, #48]
str x8, [sp, #64]
stp q0, q1, [sp, #80]
stp q2, q3, [sp, #112]
stp q4, q5, [sp, #144]
stp q6, q7, [sp, #176]
mov x0, #11
mov x1, sp
add x2, sp, #80
ldr x3, [x29, #8]
bl _NTERouteObserve
ldp q0, q1, [sp, #80]
ldp q2, q3, [sp, #112]
ldp q4, q5, [sp, #144]
ldp q6, q7, [sp, #176]
ldp x0, x1, [sp]
ldp x2, x3, [sp, #16]
ldp x4, x5, [sp, #32]
ldp x6, x7, [sp, #48]
ldr x8, [sp, #64]
add sp, sp, #208
ldp x29, x30, [sp], #16
.inst 0xd101c3ff
.inst 0x6d0323e9
.inst 0xa90457f6
.inst 0xa9054ff4
adrp x16, _NTERouteResume@PAGE
add x16, x16, _NTERouteResume@PAGEOFF
ldr x16, [x16, #88]
br x16
.p2align 2

#pragma once
#include "NativeRoutePatch.h"
extern "C" {
extern uintptr_t NTERouteResume[12];
void NTERoute_down();
void NTERoute_up();
void NTERoute_move();
void NTERoute_pan();
void NTERoute_pinch();
void NTERoute_wheel();
void NTERoute_drag_start();
void NTERoute_drag_end();
void NTERoute_leave();
void NTERoute_ios_touches();
void NTERoute_ios_scroll();
void NTERoute_scale();
}
static NativeRoutePatch::Site NTERouteSites[] = {
    {"down",0x9d464c4,{0xd10283ff,0x6d0623e9,0xa90757f6,0xa9084ff4},(uintptr_t)NTERoute_down},
    {"up",0x9d467d0,{0xd10243ff,0xa9036ffc,0xa90467fa,0xa9055ff8},(uintptr_t)NTERoute_up},
    {"move",0x9d47280,{0xd10243ff,0xa90467fa,0xa9055ff8,0xa90657f6},(uintptr_t)NTERoute_move},
    {"pan",0xa315c5c,{0xa9be4ff4,0xa9017bfd,0x910043fd,0xaa0103f3},(uintptr_t)NTERoute_pan},
    {"pinch",0xa3160f4,{0x6dbd23e9,0xa9014ff4,0xa9027bfd,0x910083fd},(uintptr_t)NTERoute_pinch},
    {"wheel",0xa3163dc,{0xd10343ff,0x6d0723e9,0xa90867fa,0xa9095ff8},(uintptr_t)NTERoute_wheel},
    {"drag_start",0xa315cb0,{0xa9bd57f6,0xa9014ff4,0xa9027bfd,0x910083fd},(uintptr_t)NTERoute_drag_start},
    {"drag_end",0xa315d40,{0xa9be4ff4,0xa9017bfd,0x910043fd,0xaa0003f3},(uintptr_t)NTERoute_drag_end},
    {"leave",0x9d4770c,{0xd10203ff,0xa9026ffc,0xa90367fa,0xa9045ff8},(uintptr_t)NTERoute_leave},
    {"ios_touches",0x1575b6c,{0xd10643ff,0x6d0f3bef,0x6d1033ed,0x6d112beb},(uintptr_t)NTERoute_ios_touches},
    {"ios_scroll",0x15731d4,{0xf9401008,0xbd42b900,0x1e202820,0xbd02b900},(uintptr_t)NTERoute_ios_scroll},
    {"scale",0xa2fe814,{0xd101c3ff,0x6d0323e9,0xa90457f6,0xa9054ff4},(uintptr_t)NTERoute_scale},
};

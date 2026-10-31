#pragma once
#include "NativeRouteSites.h"
extern "C" { __attribute__((visibility("hidden"))) uintptr_t NTERouteResume[12]={}; }
static std::atomic<bool> gRouteTraceReady{false};
static std::atomic<unsigned> gRouteLines{0};
static std::atomic<uint64_t> gRouteSequence{0};
static bool RouteBudget() { return gRouteLines.fetch_add(1,std::memory_order_relaxed)<16000; }
// Called synchronously at the native function boundary. All reads are bounded;
// no UObject pointer is held for a later tick. No map/input/cursor state writes.
struct RouteSample {
    uintptr_t object=0,klass=0,vptr=0;
    int32_t index=-1,count=-1,capacity=-1;
    float scale=0;
    bool mapClass=false,layout=false;
    struct Point { int32_t index,padding;double x,y; };
    std::array<Point,16> points{};
};
static_assert(sizeof(RouteSample::Point)==24,"native pointer array stride");
static RouteSample RouteRead(uintptr_t object) {
    RouteSample out; out.object=object;
    if (!IsHeapPointer(object) || !ReadValue(object,out.vptr) || !ReadValue(object+0xc,out.index)
        || !ReadValue(object+0x10,out.klass)) return out;
    uintptr_t mapClass=0;
    if (!ReadValue(gBase+0x100a3e60,mapClass) || !ClassIsA(out.klass,mapClass)) return out;
    out.mapClass=true;
    uintptr_t data=0;
    if (!ReadValue(object+0x760,data) || !ReadValue(object+0x768,out.count)
        || !ReadValue(object+0x76c,out.capacity) || out.count<0 || out.count>16
        || out.capacity<out.count || out.capacity>4096 || !ReadValue(object+0x1214,out.scale)) return out;
    if (out.count && (!IsHeapPointer(data) || !Read(data,out.points.data(),out.count*sizeof(RouteSample::Point)))) return out;
    out.layout=true; return out;
}
static bool RouteSampleDue(unsigned hook,uintptr_t object) {
    // Keep every lifecycle, scroll, pinch and scale request; sample only
    // high-rate movement/pan. Otherwise opposite scale writes could alias.
    if (hook==0 || hook==1 || hook==6 || hook==7 || hook==8 || hook==4 || hook==5 || hook==9 || hook==10 || hook==11) return true;
    struct Entry {uintptr_t object=0;unsigned hook=99;double last=0;};
    static thread_local std::array<Entry,128> entries{};
    Entry &entry=entries[((object>>4)^hook)%entries.size()];
    const double now=CFAbsoluteTimeGetCurrent();
    if (entry.object==object && entry.hook==hook && now-entry.last<0.04) return false;
    entry={object,hook,now};return true;
}
static void RouteLogPoints(const RouteSample &map,uint64_t seq) {
    if (!map.layout || !RouteBudget()) return;
    char points[1600]={};size_t used=0;
    for (int i=0;i<map.count && used<sizeof(points)-1;++i) {
        const auto &p=map.points[i];
        int n=snprintf(points+used,sizeof(points)-used,"%s%d:(%.2f,%.2f)",i?";":"",p.index,p.x,p.y);
        if (n<0) break;used+=std::min((size_t)n,sizeof(points)-used-1);
    }
    Log("native_route points seq=%llu object=0x%lx count=%d scale=%.7f entries=[%s]",seq,map.object,map.count,map.scale,points);
}
static void RouteLogTouch(const uintptr_t *regs,uint64_t seq,uintptr_t caller) {
    NSSet *touches=(__bridge NSSet *)(void *)regs[2];
    // Exact entry signature was guarded before this callback was installed.
    // NSSet enumeration is only performed on its original callback thread.
    if (!touches || ![touches isKindOfClass:[NSSet class]]) return;
    if (!RouteBudget()) return;
    Log("native_route ios_touches seq=%llu dispatch_type=%ld count=%lu view=0x%lx caller=0x%lx",seq,(long)regs[3],(unsigned long)touches.count,regs[0],caller);
    unsigned limit=0;
    for (UITouch *touch in touches) {
        if (++limit>16 || !RouteBudget()) break;
        if (![touch isKindOfClass:[UITouch class]]) continue;
        Log("native_route ios_touch seq=%llu identity=0x%lx type=%ld phase=%ld indirect_pointer_filtered_by_game=%d",seq,(uintptr_t)(__bridge void *)touch,(long)touch.type,(long)touch.phase,touch.type==UITouchTypeIndirectPointer);
    }
}
extern "C" __attribute__((visibility("hidden"))) void NTERouteObserve(unsigned hook,const uintptr_t *regs,const float *vectors,uintptr_t caller) noexcept {
    if (!gRouteTraceReady.load(std::memory_order_acquire) || hook>=12) return;
    // Recursion cannot turn logging (including Objective-C inspection) into input.
    static thread_local bool entered=false;
    if (entered) return;
    struct Scope {bool &flag;Scope(bool &v):flag(v){flag=true;}~Scope(){flag=false;}} scope(entered);
    @try { try {
        // Coordinate delivery is part of the pointer adapter, independent of
        // diagnostic sampling and its finite log budget. Original native touch
        // processing continues afterwards and retains its own type-3 filter.
        if (hook==9 && gNativeIndirectEnabled.load(std::memory_order_acquire)) ObserveNativeIndirectPointer((__bridge id)(void*)regs[0],(__bridge NSSet *)(void*)regs[2]);
        // Preserve the functional pointer adapter above even in silent builds.
        // Map snapshots, sampling and stack collection are diagnostics only.
        if (!kLoggingEnabled) return;
        if (gRouteLines.load(std::memory_order_relaxed)>=16000) return;
        const uintptr_t self=regs[0];
        if (!RouteSampleDue(hook,self) || !RouteBudget()) return;
        const uint64_t seq=gRouteSequence.fetch_add(1)+1;
        const uintptr_t callerOffset=caller>=gBase && caller<gBase+0x11000000?caller-gBase:0;
        if (hook==9) {
            RouteLogTouch(regs,seq,callerOffset);
            static std::atomic<unsigned> origins{0};
            if(regs[3]==0 && origins.fetch_add(1)<6){
                Dl_info origin={};dladdr((void*)caller,&origin);
                Log("native_route touch_origin seq=%llu caller_image=%s symbol=%s address=0x%lx",seq,origin.dli_fname?origin.dli_fname:"unknown",origin.dli_sname?origin.dli_sname:"unknown",caller);
                unsigned depth=0;
                for(NSNumber *address in NSThread.callStackReturnAddresses){
                    if(depth++>=16)break;Dl_info frame={};uintptr_t a=address.unsignedLongLongValue;
                    if(dladdr((void*)a,&frame) && RouteBudget())Log("native_route touch_stack seq=%llu depth=%u image=%s symbol=%s offset=0x%lx",seq,depth,frame.dli_fname?frame.dli_fname:"unknown",frame.dli_sname?frame.dli_sname:"unknown",a-(uintptr_t)frame.dli_fbase);
                }
            }
            return;
        }
        if (hook==10) {
            // q1 is 16 bytes after q0. Native scroll accumulates incoming s1.
            Log("native_route ios_scroll seq=%llu x=%.5f y=%.5f caller=0x%lx",seq,vectors[0],vectors[4],callerOffset);return;
        }
        const RouteSample map=RouteRead(self);
        std::string name,className;
        // Name decoding uses bounded memory reads and never invokes game code.
        ObjectMappingName(gBase+0xfd2abd0,self,name);
        ObjectMappingName(gBase+0xfd2abd0,map.klass,className);
        Log("native_route enter seq=%llu hook=%s object=0x%lx index=%d name=%s class=%s map_class=%d layout=%d cursor_type=%u wants_lock=%d epoch=%llu caller=0x%lx",
            seq,NTERouteSites[hook].name,self,map.index,name.c_str(),className.c_str(),map.mapClass,map.layout,
            NativeCursor::Type(gNativeCursorState.load()),NativeCursor::WantsLock(gNativeCursorState.load()),gCursorEpoch.load(),callerOffset);
        if (hook<=2 || hook==8) {
            struct Event {float xy[2],previous[2];int32_t pointer;uint8_t touch;float wheel;} e{};
            const uintptr_t event=hook==8?regs[1]:regs[2];
            if (event && Read(event+0x28,e.xy,8) && Read(event+0x30,e.previous,8)
                && ReadValue(event+0x60,e.pointer) && ReadValue(event+0x6c,e.touch) && ReadValue(event+0x74,e.wheel) && RouteBudget())
                Log("native_route event seq=%llu pointer=%d touch_raw=%u xy=(%.2f,%.2f) previous=(%.2f,%.2f) wheel=%.5f",seq,e.pointer,e.touch,e.xy[0],e.xy[1],e.previous[0],e.previous[1],e.wheel);
        }
        if (hook==3 && RouteBudget()) {
            double delta[2]={};
            if (Read(regs[1],delta,sizeof(delta))) Log("native_route pan seq=%llu delta=(%.4f,%.4f)",seq,delta[0],delta[1]);
        }
        if ((hook==4 || hook==5) && RouteBudget())
            Log("native_route zoom seq=%llu source=%s delta=%.7f",seq,hook==4?"two_pointer_distance":"native_wheel",vectors[0]);
        if (hook==11 && RouteBudget()) Log("native_route scale_request seq=%llu before=%.7f requested=%.7f caller=0x%lx",seq,map.scale,vectors[0],callerOffset);
        RouteLogPoints(map,seq);
    } catch (...) { /* Diagnostics must never unwind through a native frame. */ }
    } @catch (NSException *exception) { (void)exception; }
}
static void InstallNativeRouteTrace() {
    if (gObserveOnly) {Log("native_route skipped observe_only=1");return;}
    auto result=NativeRoutePatch::Apply(gBase,NTERouteSites,std::size(NTERouteSites),NTERouteResume);
    // An incomplete rollback must still be safe to execute: resume targets stay
    // published, while observations remain off until all sites are installed.
    gRouteTraceReady.store(result.applied,std::memory_order_release);
    Log("native_route install applied=%d stage=%s error=%d pages=%zu rollback_attempted=%d rollback_succeeded=%d sites=%zu baseline=0.5.4 event_forwarding=unchanged capture_policy=baseline indirect_pointer_coordinates=UIKit_callback",
        result.applied,result.stage,result.error,result.pages,result.rollbackAttempted,result.rollbackSucceeded,std::size(NTERouteSites));
    if (result.applied) Log("native_route coverage=widget_down,widget_up,widget_move,widget_leave,map_pan,map_pinch,map_wheel,map_drag_start,map_drag_end,map_scale_setter,ios_touches,ios_scroll map_discovery=class_inheritance_on_callback log_limit=16000 movement_sample_ms=40");
}

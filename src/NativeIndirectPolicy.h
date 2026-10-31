#pragma once
#include "NativeIndirectInput.h"
static bool gRepairNativeIndirectInput=true;
static std::atomic<bool> gNativeIndirectEnabled{false};
static NativeIndirect::Hook gNativeIndirectHooks[3];
static std::atomic<bool> gNativeIndirectQuerySeen[3];
static std::atomic<unsigned long> gIndirectPositionSamples{0};
static BOOL NativeIndirectCapability(unsigned index,id object,SEL selector) {
    const auto &hook=gNativeIndirectHooks[index];
    const BOOL original=hook.original?((BOOL(*)(id,SEL))hook.original)(object,selector):NO;
    const bool enabled=gNativeIndirectEnabled.load(std::memory_order_acquire);
    if(!gNativeIndirectQuerySeen[index].exchange(true))
        Log("native_indirect query class=%s selector=%s original=%d effective=%d",class_getName(hook.cls),sel_getName(selector),original,enabled?1:original);
    return enabled?YES:original;
}
static BOOL NativeIndirectApp(id object,SEL selector){return NativeIndirectCapability(0,object,selector);}
static BOOL NativeIndirectHasKey(id object,SEL selector){return NativeIndirectCapability(1,object,selector);}
static BOOL NativeIndirectSupports(id object,SEL selector){return NativeIndirectCapability(2,object,selector);}
static void ConfigureNativeIndirectInput(bool routeReady) {
    if(gObserveOnly || !gRepairNativeIndirectInput || !gMacPlatformApplied || !gUIPlatformApplied || !routeReady){
        Log("native_indirect skipped observe=%d enabled=%d mac=%d ui=%d coordinates_ready=%d",gObserveOnly,gRepairNativeIndirectInput,gMacPlatformApplied,gUIPlatformApplied,routeReady);return;
    }
    // Both parser accessors are consulted by UIKit's GivenInfo policy helper.
    // UIApplication caches that helper's result: override the public-facing
    // internal query too, so an already-computed compatibility default is safe.
    const char *classes[]={"UIApplication","_UIApplicationInfoParser","_UIApplicationInfoParser"};
    const char *selectors[]={"_supportsIndirectInputEvents","hasSupportsIndirectInputEventsKey","supportsIndirectInputEvents"};
    IMP replacements[]={(IMP)NativeIndirectApp,(IMP)NativeIndirectHasKey,(IMP)NativeIndirectSupports};
    for(unsigned i=0;i<3;++i)if(!NativeIndirect::Prepare(gNativeIndirectHooks[i],objc_getClass(classes[i]),sel_registerName(selectors[i]),replacements[i])){
        Log("native_indirect install applied=0 stage=capability_guard class=%s selector=%s",classes[i],selectors[i]);return;
    }
    auto result=NativeIndirect::Apply(gNativeIndirectHooks,3);
    gNativeIndirectEnabled.store(result.applied,std::memory_order_release);
    id declaration=[NSBundle.mainBundle objectForInfoDictionaryKey:@"UIApplicationSupportsIndirectInputEvents"];
    Log("native_indirect install applied=%d stage=%s methods=%u rollback=%d bundle_declaration=%s policy=UIKit_indirect_pointer native_type3_filter=unchanged capture_policy=baseline",
        result.applied,result.stage,result.methods,result.rollback,declaration?[[declaration description] UTF8String]:"absent");
}
static void ObserveNativeIndirectPointer(__unsafe_unretained id object,__unsafe_unretained NSSet *touches) {
    if(!gNativeIndirectEnabled.load(std::memory_order_acquire) || !NativeCursorRepairEnabled()
        || !gNativeCursor.load() || ![NSThread isMainThread]
        || object_getClass(object)!=NSClassFromString(@"FIOSView")
        || ![touches isKindOfClass:NSSet.class])return;
    UIView *view=object;UIWindow *window=view.window;
    const bool active=window.isKeyWindow && window.windowScene.activationState==UISceneActivationStateForegroundActive;
    SEL sizeSelector=sel_registerName("ViewSize");Method size=class_getInstanceMethod(object_getClass(view),sizeSelector);
    if(!size || (uintptr_t)method_getImplementation(size)!=gBase+0x15776c0)return;
    for(UITouch *touch in touches){
        if(![touch isKindOfClass:UITouch.class])continue;
        if(!NativeIndirect::PointerCoordinateEligible(touch.type,touch.phase,true,true,active,NativeCursor::WantsLock(gNativeCursorState.load())))continue;
        const uint64_t epoch=gCursorEpoch.load();
        CGPoint p=[touch locationInView:view];CGRect bounds=view.bounds;
        NativeCursor::Position render=((NativeCursor::Position(*)(id,SEL))objc_msgSend)(view,sizeSelector),mapped;
        if(!NativeCursor::MapPosition({p.x,p.y},{bounds.origin.x,bounds.origin.y},{bounds.size.width,bounds.size.height},render,mapped)){
            gNativePosition.Invalidate();continue;
        }
        if(epoch!=gCursorEpoch.load() || NativeCursor::WantsLock(gNativeCursorState.load()))continue;
        gNativePosition.Publish(mapped,epoch);
        auto n=++gIndirectPositionSamples;
        if(n==1 || n%300==0)Log("native_indirect position samples=%lu type=%ld phase=%ld position=(%.2f,%.2f) epoch=%llu source=FIOSView_UIKit_pointer",n,(long)touch.type,(long)touch.phase,mapped.x,mapped.y,epoch);
    }
}

#pragma once
// The release needs only the real UIKit touch callback for absolute pointer
// samples. No inline hooks, displaced instructions, route tracing or JIT.
static IMP gNativeTouchOriginal=nullptr;
static bool gNativeTouchReady=false;
static void NativeTouchObserver(id view,SEL selector,NSSet *touches,int type) {
    ObserveNativeIndirectPointer(view,touches);
    ((void(*)(id,SEL,NSSet*,int))gNativeTouchOriginal)(view,selector,touches,type);
}
static void InstallNativeTouchObserver() {
    if(gObserveOnly || gNativeTouchReady || !gGame.HandleTouches)return;
    Class cls=objc_getClass("FIOSView");SEL selector=sel_registerName("HandleTouches:ofType:");
    Method method=NativeIndirect::OwnMethod(cls,selector);
    if(!method || method_getNumberOfArguments(method)!=4
        || strcmp(method_getTypeEncoding(method),"v28@0:8@16i24")
        || (uintptr_t)method_getImplementation(method)!=gBase+gGame.HandleTouches)return;
    gNativeTouchOriginal=method_getImplementation(method);
    IMP replaced=method_setImplementation(method,(IMP)NativeTouchObserver);
    if(replaced!=gNativeTouchOriginal){
        if(method_getImplementation(method)==(IMP)NativeTouchObserver)method_setImplementation(method,replaced);
        return;
    }
    gNativeTouchReady=method_getImplementation(method)==(IMP)NativeTouchObserver;
}

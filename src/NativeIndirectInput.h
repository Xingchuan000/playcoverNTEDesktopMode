#pragma once
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <cstring>

// UIKit has a separate pointer compatibility policy from the game's platform
// enums. Change the policy getters; UIKit still creates and routes every event.
namespace NativeIndirect {
struct Hook { Class cls=Nil; SEL selector=nullptr; Method method=nullptr; IMP original=nullptr,replacement=nullptr; };
struct Result { bool applied=false,rollback=false; const char *stage="unprepared"; unsigned methods=0; };
inline bool BooleanGetter(Method method) {
    if (!method || method_getNumberOfArguments(method)!=2) return false;
    char *type=method_copyReturnType(method);
    bool ok=type && (!strcmp(type,"B") || !strcmp(type,"c")); free(type);return ok;
}
inline bool UIKitOwner(Method method) {
    Dl_info info={};
    return method && dladdr((void*)method_getImplementation(method),&info) && info.dli_fname
        && strstr(info.dli_fname,"/UIKitCore.framework/");
}
inline Method OwnMethod(Class cls,SEL selector) {
    unsigned count=0;Method *methods=class_copyMethodList(cls,&count);Method found=nullptr;
    for(unsigned i=0;i<count;++i)if(method_getName(methods[i])==selector){found=methods[i];break;}
    free(methods);return found;
}
inline bool Prepare(Hook &out,Class cls,SEL selector,IMP replacement) {
    Method method=OwnMethod(cls,selector);
    if (!replacement || !BooleanGetter(method) || !UIKitOwner(method)) return false;
    out={cls,selector,method,method_getImplementation(method),replacement};return true;
}
inline Result Apply(Hook *hooks,size_t count) {
    Result result;
    if(!hooks || count!=3){result.stage="count";return result;}
    // Inspect the entire set before changing any method. A newer OS or a
    // competing override must not leave only part of the policy enabled.
    for(size_t i=0;i<count;++i){
        const auto &h=hooks[i];
        if(!h.cls || !h.selector || !h.method || !h.original || !h.replacement
            || OwnMethod(h.cls,h.selector)!=h.method || !BooleanGetter(h.method)
            || method_getImplementation(h.method)!=h.original || !UIKitOwner(h.method)){
            result.stage="preflight";return result;
        }
        for(size_t j=0;j<i;++j)if(h.method==hooks[j].method){result.stage="duplicate";return result;}
    }
    size_t installed=0;
    for(;installed<count;++installed){
        auto &h=hooks[installed];IMP previous=method_setImplementation(h.method,h.replacement);
        if(previous!=h.original){
            // Restore the implementation actually displaced by this operation.
            if(method_getImplementation(h.method)==h.replacement)method_setImplementation(h.method,previous);
            break;
        }
    }
    if(installed!=count){
        result.rollback=true;
        while(installed){auto &h=hooks[--installed];if(method_getImplementation(h.method)==h.replacement)method_setImplementation(h.method,h.original);else result.rollback=false;}
        result.stage="changed_during_install";return result;
    }
    result.applied=true;result.methods=(unsigned)count;result.stage="verified";return result;
}
inline bool PointerCoordinateEligible(long type,long phase,bool desktop,bool onMain,bool active,bool locked) {
    // Never reinterpret a direct/virtual touch as a mouse. No suppression,
    // pointer-ID rewriting, relative scaling, or button synthesis is involved.
    return type==3 && phase>=0 && phase<=3 && desktop && onMain && active && !locked;
}
}

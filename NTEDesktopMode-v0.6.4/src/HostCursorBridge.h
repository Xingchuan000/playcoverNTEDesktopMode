#pragma once
#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <dlfcn.h>
#include <cstring>

// The current Catalyst host's preference notification handler only unlocks.
// Re-entry uses UINSApplicationDelegate's guarded native lock entry. Never call
// CGAssociate/NSCursor ourselves: the host owns lock state and hide accounting.
namespace HostCursor {
enum class Action { None, WaitForPreference, Lock, Unlock };
constexpr Action Decide(bool wants,bool active,bool preferred,bool hidden) {
    if (!active) return Action::None;
    if (wants!=preferred) return Action::WaitForPreference;
    if (wants&&!hidden) return Action::Lock;
    if (!wants&&hidden) return Action::Unlock;
    return Action::None;
}
inline bool TypeMatches(const char *actual,char expected) {
    return actual && (actual[0]==expected || (expected=='B'&&actual[0]=='c'));
}
// Inspect metadata/implementation provenance before sending private messages.
inline bool Verify(Class cls,SEL selector,const char *image,char result,const char *arguments) {
    Method method=cls?class_getInstanceMethod(cls,selector):nullptr;
    if (!method || method_getNumberOfArguments(method)!=2+strlen(arguments)) return false;
    Dl_info info={};
    if (!dladdr((void *)method_getImplementation(method),&info) || !info.dli_fname || !strstr(info.dli_fname,image)) return false;
    char *type=method_copyReturnType(method);
    bool ok=TypeMatches(type,result); free(type);
    for (unsigned i=0;ok && arguments[i];++i) {
        type=method_copyArgumentType(method,i+2);
        ok=TypeMatches(type,arguments[i]); free(type);
    }
    return ok;
}
inline bool SystemMethod(id object,SEL selector,char result,const char *arguments) {
    return object && Verify(object_getClass(object),selector,"/UIKitMacHelper.framework/",result,arguments);
}
struct Endpoint {
    id delegate=nil,proxy=nil,sceneIdentifier=nil;
    bool hidden=false,preferred=false,appearsKey=false;
};
inline bool Resolve(Endpoint &out,const char *&reason) {
    Class appClass=NSClassFromString(@"NSApplication");
    SEL shared=sel_registerName("sharedApplication"),key=sel_registerName("keyWindow");
    if (!Verify(object_getClass(appClass),shared,"/AppKit.framework/",'@',"")) { reason="NSApplication API unavailable"; return false; }
    id app=((id(*)(id,SEL))objc_msgSend)(appClass,shared);
    if (!Verify(object_getClass(app),key,"/AppKit.framework/",'@',"")) { reason="host keyWindow API unavailable"; return false; }
    id window=((id(*)(id,SEL))objc_msgSend)(app,key);
    SEL proxySelector=sel_registerName("UINS_windowProxyForContentView");
    if (!SystemMethod(window,proxySelector,'@',"")) { reason="no Catalyst key window"; return false; }
    id proxy=((id(*)(id,SEL))objc_msgSend)(window,proxySelector);
    Class proxyClass=NSClassFromString(@"UINSWindowProxy");
    if (!proxyClass || ![proxy isKindOfClass:proxyClass]
        || !SystemMethod(proxy,sel_registerName("appearsKey"),'B',"")
        || !SystemMethod(proxy,sel_registerName("sceneIdentifier"),'@',"")) { reason="host proxy guard rejected"; return false; }
    Class delegateClass=NSClassFromString(@"UINSApplicationDelegate");
    shared=sel_registerName("sharedDelegate");
    if (!Verify(object_getClass(delegateClass),shared,"/UIKitMacHelper.framework/",'@',"")) { reason="host delegate guard rejected"; return false; }
    id delegate=((id(*)(id,SEL))objc_msgSend)(delegateClass,shared);
    const struct {const char *name;char result;const char *args;} methods[]={
        {"_pointerLockCursorIsHidden",'B',""},
        {"prefersPointerLockForSceneIdentifierCallback",'@',""},
        {"prefersPointerLockForSceneIdentifierCallback:",'B',"@"},
        {"lockCursorIfNecessaryForUINSWindow:shouldWarpCursor:",'v',"@B"},
        {"unlockCursorForUINSWindow:",'v',"@"}
    };
    if (!delegate || ![delegate isKindOfClass:delegateClass]) { reason="host delegate missing"; return false; }
    for (auto &method:methods) if (!SystemMethod(delegate,sel_registerName(method.name),method.result,method.args)) {
        reason=method.name; return false;
    }
    id callback=((id(*)(id,SEL))objc_msgSend)(delegate,sel_registerName("prefersPointerLockForSceneIdentifierCallback"));
    if (!callback) { reason="native preference callback not installed"; return false; }
    Endpoint result;
    result.delegate=delegate; result.proxy=proxy;
    result.sceneIdentifier=((id(*)(id,SEL))objc_msgSend)(proxy,sel_registerName("sceneIdentifier"));
    if (![result.sceneIdentifier isKindOfClass:NSString.class]) { reason="host scene identifier unavailable"; return false; }
    result.appearsKey=((BOOL(*)(id,SEL))objc_msgSend)(proxy,sel_registerName("appearsKey"));
    result.preferred=((BOOL(*)(id,SEL,id))objc_msgSend)(delegate,sel_registerName("prefersPointerLockForSceneIdentifierCallback:"),result.sceneIdentifier);
    result.hidden=((BOOL(*)(id,SEL))objc_msgSend)(delegate,sel_registerName("_pointerLockCursorIsHidden"));
    out=result; reason="verified"; return true;
}
inline void Apply(const Endpoint &endpoint,Action action) {
    if (action==Action::Lock)
        ((void(*)(id,SEL,id,BOOL))objc_msgSend)(endpoint.delegate,sel_registerName("lockCursorIfNecessaryForUINSWindow:shouldWarpCursor:"),endpoint.proxy,YES);
    else if (action==Action::Unlock)
        ((void(*)(id,SEL,id))objc_msgSend)(endpoint.delegate,sel_registerName("unlockCursorForUINSWindow:"),endpoint.proxy);
}
} // namespace HostCursor

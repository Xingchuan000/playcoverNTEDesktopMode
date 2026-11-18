#pragma once
#include "KeyboardBeepPolicy.h"
#if NTE_ENABLE_LOGGING
#include <execinfo.h>
#endif

// Included after the plugin state and Log macro. All hooks are local to this
// process. Hardware handlers and the actual event dispatch remain untouched.
#ifndef NTE_BEEP_FIX_DEFAULT
#define NTE_BEEP_FIX_DEFAULT 1
#endif
namespace KeyboardBeep {
static bool enabled=NTE_BEEP_FIX_DEFAULT!=0, installed=false;
static IMP originalSend=nullptr, originalFallback=nullptr;
#if NTE_ENABLE_LOGGING
static bool diagnostics=true;
static IMP originalFocus=nullptr;
static unsigned long serial=0, fallbackCount=0, suppressedCount=0, keyCount=0, mouseCount=0;
static unsigned long focusCount=0;
static unsigned stackCount=0;
#else
static constexpr bool diagnostics=false;
#endif
struct Dispatch {
    __unsafe_unretained id window=nil, event=nil;
    long type=0;
#if NTE_ENABLE_LOGGING
    unsigned long id=0;
    bool terminalFallback=false;
#endif
};
static thread_local Dispatch *current=nullptr;
static thread_local bool inFallback=false;

#if NTE_ENABLE_LOGGING
inline const char *ClassName(id object) { return object?class_getName(object_getClass(object)):"nil"; }
inline bool Sample(unsigned long n) { return n<=48 || n%120==0; }
#endif
inline bool AppKit(id object,SEL selector,char result,const char *arguments="") {
    return object && HostCursor::Verify(object_getClass(object),selector,"/AppKit.framework/",result,arguments);
}
inline bool Host(id object,SEL selector,char result,const char *arguments="") {
    return AppKit(object,selector,result,arguments) ||
        (object && HostCursor::Verify(object_getClass(object),selector,"/UIKitMacHelper.framework/",result,arguments));
}
inline id Object(id object,const char *selector) {
    SEL s=sel_registerName(selector);
    return Host(object,s,'@')?((id(*)(id,SEL))objc_msgSend)(object,s):nil;
}
inline bool Boolean(id object,const char *selector,bool fallback=false) {
    SEL s=sel_registerName(selector);
    return Host(object,s,'B')?((BOOL(*)(id,SEL))objc_msgSend)(object,s):fallback;
}
inline id Application() {
    Class cls=objc_getClass("NSApplication");SEL shared=sel_registerName("sharedApplication");
    return HostCursor::Verify(object_getClass(cls),shared,"/AppKit.framework/",'@',"")
        ?((id(*)(id,SEL))objc_msgSend)(cls,shared):nil;
}
inline bool Kind(id object,const char *className) {
    Class cls=objc_getClass(className);return object && cls && [object isKindOfClass:cls];
}
inline long EventType(id event) {
    SEL s=sel_registerName("type");
    return AppKit(event,s,'Q')?(long)((NSUInteger(*)(id,SEL))objc_msgSend)(event,s):-1;
}
inline uint64_t Modifiers(id event) {
    SEL s=sel_registerName("modifierFlags");
    return AppKit(event,s,'Q')?((NSUInteger(*)(id,SEL))objc_msgSend)(event,s):~0ULL;
}
#if NTE_ENABLE_LOGGING
inline bool Repeat(id event) {return Boolean(event,"isARepeat");}
inline bool IsKey(long type) { return type==10 || type==11 || type==12; }
inline bool IsClick(long type) { return type==1 || type==2 || type==3 || type==4 || type==25 || type==26; }

#endif

// A custom UIKeyInput responder is intentionally treated as text input. This
// includes Unreal's integrated keyboard; no engine offsets or strings read.
inline TextState InspectView(UIView *view,unsigned &budget,unsigned depth=0) {
    if (!budget || depth>64) return TextState::Unknown;
    --budget;
    if (view.isFirstResponder && ([view isKindOfClass:UITextField.class]
        || [view isKindOfClass:UITextView.class] || [view conformsToProtocol:@protocol(UIKeyInput)]
        || [view conformsToProtocol:@protocol(UITextInput)])) return TextState::Editing;
    for (UIView *child in view.subviews) {
        auto state=InspectView(child,budget,depth+1);
        if (state!=TextState::Clear) return state;
    }
    return TextState::Clear;
}
inline TextState UIKitTextState() {
    if (![NSThread isMainThread]) return TextState::Unknown;
    bool found=false;unsigned budget=4096;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState!=UISceneActivationStateForegroundActive
            || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha<=0) continue;
            if (window.isKeyWindow) found=true;
            UIViewController *root=window.rootViewController;
            if (root.presentedViewController) return TextState::Unknown;
            auto state=InspectView(window,budget);
            if (state!=TextState::Clear) return state;
        }
    }
    return found?TextState::Clear:TextState::Unknown;
}
inline Eligibility Snapshot(Dispatch *context,bool isKeyDown) {
    Eligibility s;s.enabled=enabled&&!gObserveOnly;s.mainThread=[NSThread isMainThread];
    s.dispatching=context!=nullptr;s.keyDown=isKeyDown && context && context->type==10;
    if (!s.mainThread || !context) return s;
    id app=Application(),window=context->window;
    s.active=Boolean(app,"isActive");s.keyWindow=Object(app,"keyWindow")==window;
    SEL proxy=sel_registerName("UINS_windowProxyForContentView");
    s.catalystWindow=HostCursor::SystemMethod(window,proxy,'@',"")
        && ((id(*)(id,SEL))objc_msgSend)(window,proxy)!=nil;
    s.gameReady=gNativeInputInitialized.load(std::memory_order_acquire) && gNativeCursor.load()!=0;
    uint32_t cursor=gNativeCursorState.load();
    s.captured=NativeCursor::Ready(cursor) && NativeCursor::WantsLock(cursor);
    id responder=Object(window,"firstResponder");
    s.hostView=Kind(responder,"UINSInputView") || Kind(responder,"UINSSceneView");
    s.modal=Object(app,"modalWindow")!=nil || Object(window,"attachedSheet")!=nil;
    s.markedText=Boolean(responder,"hasMarkedText");
    s.modifiers=Modifiers(context->event);s.text=UIKitTextState();
    // A native AppKit editor is not a Catalyst game view, even if UIKit has no editor.
    if (Kind(responder,"NSTextView") || Kind(responder,"NSTextField"))s.text=TextState::Editing;
    return s;
}
#if NTE_ENABLE_LOGGING
inline void Chain(id responder,unsigned long eventId) {
    if (!diagnostics) return;
    for (unsigned i=0;responder && i<10;++i) {
        Log("kbd_chain event=%lu slot=%u class=%s",eventId,i,ClassName(responder));
        id next=Object(responder,"nextResponder");if(next==responder)break;responder=next;
    }
}
inline void Stack(unsigned long eventId) {
    if (!diagnostics || stackCount>=6) return;
    ++stackCount;void *frames[24];int count=backtrace(frames,24);
    for (int i=1;i<count;++i) {
        Dl_info info={};dladdr(frames[i],&info);
        // Symbol/address only: never object descriptions, event characters or text.
        const char *image=info.dli_fname?strrchr(info.dli_fname,'/'):nullptr;
        Log("kbd_stack event=%lu frame=%d image=%s offset=0x%lx symbol=%s",eventId,i,
            image?image+1:"unknown",info.dli_fbase?(unsigned long)((uintptr_t)frames[i]-(uintptr_t)info.dli_fbase):0,
            info.dli_sname?info.dli_sname:"unknown");
    }
}
inline void State(const char *phase,const Dispatch &d,const Eligibility &s) {
    if (!diagnostics) return;
    id responder=Object(d.window,"firstResponder");
    Log("kbd_event event=%lu phase=%s type=%ld repeat=%d mods=0x%llx window=%s responder=%s active=%d key_window=%d catalyst=%d game_ready=%d captured=%d host_view=%d text=%d marked=%d modal=%d fix=%d reason=%s",
        d.id,phase,d.type,d.type==10?Repeat(d.event):false,(unsigned long long)s.modifiers,
        ClassName(d.window),ClassName(responder),s.active,s.keyWindow,s.catalystWindow,s.gameReady,s.captured,
        s.hostView,(int)s.text,s.markedText,s.modal,s.enabled,Decision(s));
}
#endif
inline void SendEvent(id window,SEL selector,id event) {
    long type=EventType(event);
    struct Restore {Dispatch *previous;~Restore(){current=previous;}};
#if NTE_ENABLE_LOGGING
    bool tracked=IsKey(type) || IsClick(type);
#else
    bool tracked=type==10;
#endif
    if (!tracked) {
        Restore restore{current};current=nullptr;
        ((void(*)(id,SEL,id))originalSend)(window,selector,event);return;
    }
    Dispatch d;d.window=window;d.event=event;d.type=type;
#if NTE_ENABLE_LOGGING
    d.id=++serial;
#endif
    Restore restore{current};current=&d;
#if NTE_ENABLE_LOGGING
    bool sampled=diagnostics && (IsClick(type)?Sample(++mouseCount):Sample(++keyCount));
    if (sampled)State("before",d,Snapshot(&d,type==10));
#endif
    ((void(*)(id,SEL,id))originalSend)(window,selector,event);
#if NTE_ENABLE_LOGGING
    if (sampled)State("after",d,Snapshot(&d,type==10));
#endif
}
#if NTE_ENABLE_LOGGING
inline BOOL MakeFirstResponder(id window,SEL selector,id proposed) {
    // Log the real AppKit result; never force focus onto a game or text view.
    id before=Object(window,"firstResponder");
    BOOL result=((BOOL(*)(id,SEL,id))originalFocus)(window,selector,proposed);
    id after=Object(window,"firstResponder");
    if (diagnostics && before!=after && Sample(++focusCount)) {
        Log("kbd_focus event=%lu window=%s from=%s requested=%s to=%s accepted=%d captured=%d",
            current?current->id:0,ClassName(window),ClassName(before),ClassName(proposed),ClassName(after),result,
            NativeCursor::WantsLock(gNativeCursorState.load()));
        Chain(after,current?current->id:0);
    }
    return result;
}
#endif
inline void KeyFallback(id receiver,SEL selector,SEL failedSelector,const Eligibility &s) {
    bool suppress=Suppress(s);
#if NTE_ENABLE_LOGGING
    ++fallbackCount;if(suppress)++suppressedCount;
    if (current)current->terminalFallback=true;
    if (diagnostics && Sample(fallbackCount)) {
        Log("kbd_fallback event=%lu receiver=%s selector=keyDown: action=%s count=%lu suppressed=%lu reason=%s",
            current?current->id:0,ClassName(receiver),suppress?"suppressed":"forwarded",fallbackCount,suppressedCount,Decision(s));
        if (current)State("terminal_fallback",*current,s);
        Chain(current?Object(current->window,"firstResponder"):receiver,current?current->id:0);
        Stack(current?current->id:0);
    }
#endif
    // This is the terminal fallback only, reached AFTER normal event delivery.
    // A missing context, editor, shortcut, modal or unknown view always forwards.
    if (!suppress)((void(*)(id,SEL,SEL))originalFallback)(receiver,selector,failedSelector);
}
inline void NoResponder(id receiver,SEL selector,SEL failedSelector) {
    bool key=failedSelector==sel_registerName("keyDown:");
    if (!key || inFallback || ![NSThread isMainThread]) {
        ((void(*)(id,SEL,SEL))originalFallback)(receiver,selector,failedSelector);return;
    }
    struct Restore {~Restore(){inFallback=false;}} restore;inFallback=true;
    KeyFallback(receiver,selector,failedSelector,Snapshot(current,key));
}
inline Method OwnMethod(Class cls,SEL selector) {
    unsigned count=0;Method *methods=class_copyMethodList(cls,&count);Method found=nullptr;
    for(unsigned i=0;i<count;++i)if(method_getName(methods[i])==selector){found=methods[i];break;}
    free(methods);return found;
}
inline void Configure(NSDictionary *config) {
    if(config[@"KeyboardBeepFixEnabled"])enabled=[config[@"KeyboardBeepFixEnabled"] boolValue];
#if NTE_ENABLE_LOGGING
    if(config[@"KeyboardBeepDiagnosticsEnabled"])diagnostics=[config[@"KeyboardBeepDiagnosticsEnabled"] boolValue];
#endif
}
inline bool Install() {
    if (installed)return true;
    if (![NSThread isMainThread])return false;
    struct Hook {const char *cls,*selector,*arguments;char result;IMP replacement;IMP *original;Method method;};
    Hook hooks[]={
        {"NSWindow","sendEvent:","@",'v',(IMP)SendEvent,&originalSend,nullptr},
#if NTE_ENABLE_LOGGING
        {"NSWindow","makeFirstResponder:","@",'B',(IMP)MakeFirstResponder,&originalFocus,nullptr},
#endif
        {"NSResponder","noResponderFor:",":",'v',(IMP)NoResponder,&originalFallback,nullptr}
    };
    // Preflight the entire set. Never replace inherited methods or a competitor.
    for (auto &h:hooks) {
        Class cls=objc_getClass(h.cls);SEL sel=sel_registerName(h.selector);
        h.method=OwnMethod(cls,sel);
        if(!h.method || !HostCursor::Verify(cls,sel,"/AppKit.framework/",h.result,h.arguments)) {
            Log("kbd_install ready=0 reason=method_guard class=%s selector=%s",h.cls,h.selector);return false;
        }
        *h.original=method_getImplementation(h.method);
    }
    unsigned changed=0;
    for (auto &h:hooks) {
        IMP previous=method_setImplementation(h.method,h.replacement);
        if(previous!=*h.original){
            if(method_getImplementation(h.method)==h.replacement)method_setImplementation(h.method,previous);
            while(changed){auto &old=hooks[--changed];if(method_getImplementation(old.method)==old.replacement)method_setImplementation(old.method,*old.original);}
            Log("kbd_install ready=0 reason=implementation_changed");return false;
        }
        ++changed;
    }
    installed=true;
    Log("kbd_install ready=1 fix=%d diagnostics=%d scope=captured_gameplay hooks=%zu hardware_callbacks=unchanged text_logging=off",enabled,diagnostics,sizeof(hooks)/sizeof(hooks[0]));
    return true;
}
inline void Heartbeat() {
#if NTE_ENABLE_LOGGING
    if (!diagnostics)return;
    id app=Application(),window=Object(app,"keyWindow");
    Log("kbd_status installed=%d fix=%d events=%lu mouse=%lu keys=%lu fallback=%lu suppressed=%lu window=%s responder=%s captured=%d",
        installed,enabled,serial,mouseCount,keyCount,fallbackCount,suppressedCount,ClassName(window),ClassName(Object(window,"firstResponder")),
        NativeCursor::WantsLock(gNativeCursorState.load()));
#endif
}
} // namespace KeyboardBeep

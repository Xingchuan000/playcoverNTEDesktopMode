#define NTE_ENABLE_LOGGING 0
#import "../src/NTEDesktopMode.mm"
static unsigned checks=0,forwards=0,dispatches=0;
static id receiver=nil,down=nil,up=nil;
static void Check(bool ok,const char *name){++checks;if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);}}
static void FallbackProbe(id object,SEL selector,SEL failed){
    Check(object==receiver && selector==sel_registerName("noResponderFor:") && failed==sel_registerName("keyDown:"),"release fallback arguments preserved");++forwards;
}
static void SendProbe(id window,SEL selector,id event){
    using namespace KeyboardBeep;
    Check(window==receiver && selector==sel_registerName("sendEvent:"),"release dispatch arguments preserved");++dispatches;
    if(event==down){
        Dispatch *outer=current;Check(outer && outer->event==down,"release tracks real key-down during dispatch");
        SendEvent(window,selector,up);
        Check(current==outer,"nested key-up restores outer key-down context");
    }else Check(!current,"non-key-down dispatch cannot borrow outer repair context");
}
static id MakeEvent(NSUInteger type){
    return ((id(*)(id,SEL,NSUInteger,CGPoint,NSUInteger,NSTimeInterval,NSInteger,id,NSString*,NSString*,BOOL,unsigned short))objc_msgSend)(
        objc_getClass("NSEvent"),sel_registerName("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:"),
        type,CGPointMake(0,0),0,0,0,nil,@"",@"",NO,0);
}
int main(){@autoreleasepool{
    using namespace KeyboardBeep;
    Check(!kLoggingEnabled && !kHardwareObservers && !diagnostics,"release diagnostics and hardware observers are compiled off");
    Configure(@{@"KeyboardBeepDiagnosticsEnabled":@YES});
    Check(!diagnostics && enabled,"old diagnostic configuration cannot turn release logging on or repair off");
    Eligibility ready;ready.enabled=ready.mainThread=ready.dispatching=ready.keyDown=true;
    ready.active=ready.keyWindow=ready.catalystWindow=ready.gameReady=ready.captured=ready.hostView=true;ready.text=TextState::Clear;
    receiver=[NSObject new];originalFallback=(IMP)FallbackProbe;
    KeyFallback(receiver,sel_registerName("noResponderFor:"),sel_registerName("keyDown:"),ready);
    Check(forwards==0,"release keeps the tested terminal beep suppression");
    auto editing=ready;editing.text=TextState::Editing;
    KeyFallback(receiver,sel_registerName("noResponderFor:"),sel_registerName("keyDown:"),editing);
    Check(forwards==1,"release preserves text-input fallback");
    auto shortcut=ready;shortcut.modifiers=1ULL<<20;
    KeyFallback(receiver,sel_registerName("noResponderFor:"),sel_registerName("keyDown:"),shortcut);
    Check(forwards==2,"release preserves Command shortcut fallback");
    originalSend=(IMP)SendProbe;down=MakeEvent(10);up=MakeEvent(11);Check(down && up,"real AppKit key events created");
    SendEvent(receiver,sel_registerName("sendEvent:"),down);
    Check(dispatches==2 && !current,"release forwards nested down/up once each and clears context");
    SendEvent(receiver,sel_registerName("sendEvent:"),[NSObject new]);
    Check(dispatches==3 && !current,"release forwards other events unchanged");
    Class cls=objc_getClass("NSWindow");SEL focus=sel_registerName("makeFirstResponder:");
    IMP oldFocus=class_getMethodImplementation(cls,focus);
    Check(Install() && installed,"release installs its guarded repair hooks");
    Check(class_getMethodImplementation(cls,focus)==oldFocus,"release never installs the diagnostic focus hook");
    Check(class_getMethodImplementation(cls,sel_registerName("sendEvent:"))==(IMP)SendEvent,"release dispatch scope hook remains active");
    Check(class_getMethodImplementation(objc_getClass("NSResponder"),sel_registerName("noResponderFor:"))==(IMP)NoResponder,"release terminal fallback hook remains active");
    Check(Install(),"release installation remains idempotent");
    Heartbeat();Check(gLog==nullptr,"release heartbeat never opens a log");
    printf("keyboard beep release checks passed: %u\n",checks);
}}

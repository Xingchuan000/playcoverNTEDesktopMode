#define NTE_ENABLE_LOGGING 1
#import "../src/NTEDesktopMode.mm"
#include <thread>
static unsigned checks=0;
static void Check(bool ok,const char *name){++checks;if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);}}
@interface NTEBeepEditor : UITextField
@end
@implementation NTEBeepEditor
- (BOOL)isFirstResponder {return YES;}
@end
@interface NTEBeepCustomEditor : UIView <UIKeyInput>
@end
@implementation NTEBeepCustomEditor
- (BOOL)isFirstResponder {return YES;}
- (BOOL)hasText {return NO;}
- (void)insertText:(NSString *)text {}
- (void)deleteBackward {}
@end
static unsigned forwarded=0,dispatches=0,focusCalls=0;
static id expectedReceiver=nil,outerEvent=nil,innerEvent=nil,requestedFocus=nil;
static SEL expectedFailed=nullptr;
static void FallbackProbe(id receiver,SEL selector,SEL failed){
    Check(receiver==expectedReceiver && selector==sel_registerName("noResponderFor:") && failed==expectedFailed,"fallback preserves receiver and selectors");
    ++forwarded;
}
static void SendProbe(id window,SEL selector,id event){
    using namespace KeyboardBeep;
    Check(window==expectedReceiver && selector==sel_registerName("sendEvent:"),"dispatch preserves window and selector");
    ++dispatches;
    if(event==outerEvent){
        Dispatch *outer=current;Check(outer && outer->event==event,"outer event has live dispatch context");
        SendEvent(window,selector,innerEvent);
        Check(current==outer && current->event==outerEvent,"nested event restores outer dispatch context");
        NoResponder(window,sel_registerName("noResponderFor:"),expectedFailed);
    }else if(event==innerEvent)Check(current && current->event==event,"nested event has its own dispatch context");
    else Check(!current,"unknown event forwarded without creating key context");
}
static BOOL FocusProbe(id window,SEL selector,id proposed){
    Check(window==expectedReceiver && proposed==requestedFocus && selector==sel_registerName("makeFirstResponder:"),"focus forwards original target unchanged");
    ++focusCalls;return NO;
}
static id MakeEvent(NSUInteger type,BOOL repeat=NO){
    Class cls=objc_getClass("NSEvent");
    SEL selector=sel_registerName("keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:characters:charactersIgnoringModifiers:isARepeat:keyCode:");
    return ((id(*)(id,SEL,NSUInteger,CGPoint,NSUInteger,NSTimeInterval,NSInteger,id,NSString*,NSString*,BOOL,unsigned short))objc_msgSend)(
        cls,selector,type,CGPointMake(0,0),0,0,0,nil,@"",@"",repeat,0);
}
int main(){@autoreleasepool{
    using namespace KeyboardBeep;
    Eligibility ready;ready.enabled=ready.mainThread=ready.dispatching=ready.keyDown=true;
    ready.active=ready.keyWindow=ready.catalystWindow=ready.gameReady=ready.captured=ready.hostView=true;
    ready.text=TextState::Clear;
    Check(Suppress(ready),"captured gameplay terminal fallback qualifies");
    auto state=ready;
    bool Eligibility::*requirements[]={&Eligibility::enabled,&Eligibility::mainThread,&Eligibility::dispatching,&Eligibility::keyDown,
        &Eligibility::active,&Eligibility::keyWindow,&Eligibility::catalystWindow,&Eligibility::gameReady,&Eligibility::captured,&Eligibility::hostView};
    for(auto field:requirements){state=ready;state.*field=false;Check(!Suppress(state),"each safety prerequisite is necessary");}
    for(auto field:{&Eligibility::modal,&Eligibility::markedText}){state=ready;state.*field=true;Check(!Suppress(state),"modal and marked text retain default handling");}
    for(auto text:{TextState::Editing,TextState::Unknown}){state=ready;state.text=text;Check(!Suppress(state),"editing and unknown input retain default handling");}
    state=ready;state.modifiers=1ULL<<18;Check(!Suppress(state),"Control command preserved");
    state.modifiers=1ULL<<20;Check(!Suppress(state),"Command shortcut preserved");
    state.modifiers=~0ULL;Check(!Suppress(state),"unreadable modifiers fail closed");
    state.modifiers=(1ULL<<17)|(1ULL<<19);Check(Suppress(state),"Shift and Option game controls can qualify");
    Check(!Suppress(Eligibility{}),"empty snapshot never suppresses");
    unsigned budget=20;UIView *container=[UIView new];
    Check(InspectView(container,budget)==TextState::Clear,"plain UIKit tree has no text editor");
    [container addSubview:[NTEBeepEditor new]];budget=20;
    Check(InspectView(container,budget)==TextState::Editing,"active UITextField blocks suppression");
    UIView *custom=[NTEBeepCustomEditor new];budget=20;
    Check(InspectView(custom,budget)==TextState::Editing,"custom and integrated UIKeyInput blocks suppression");
    budget=0;Check(InspectView(container,budget)==TextState::Unknown,"exhausted traversal budget fails closed");
    budget=20;Check(InspectView(container,budget,65)==TextState::Unknown,"excessive hierarchy depth fails closed");
    Check(!kHardwareObservers,"logging build does not wrap native GameController callbacks");
    Check(!HostCursor::Verify(objc_getClass("NSResponder"),sel_registerName("noResponderFor:"),"/AppKit.framework/",'v',"@"),"selector ABI cannot be mistaken for object ABI");
    Class windowClass=objc_getClass("NSWindow");
    Check(OwnMethod(windowClass,sel_registerName("sendEvent:"))!=nullptr,"host window owns dispatch method on this OS");
    Check(OwnMethod(objc_getClass("UINSWindow"),sel_registerName("sendEvent:"))==nullptr,"hook does not accidentally change inherited method metadata");
    originalFallback=(IMP)FallbackProbe;expectedReceiver=[NSObject new];expectedFailed=sel_registerName("keyDown:");
    diagnostics=false;originalSend=(IMP)SendProbe;
    outerEvent=MakeEvent(10,YES);innerEvent=MakeEvent(11);
    Check(outerEvent && innerEvent && EventType(outerEvent)==10 && Repeat(outerEvent),"real AppKit key-down repeat metadata read with correct ABI");
    Check(EventType(innerEvent)==11 && Modifiers(innerEvent)==0,"real AppKit key-up metadata read unchanged");
    enabled=true;
    SendEvent(expectedReceiver,sel_registerName("sendEvent:"),outerEvent);
    Check(dispatches==2 && forwarded==1 && !current,"nested dispatch forwards each original once and retains unsafe fallback");
    SendEvent(expectedReceiver,sel_registerName("sendEvent:"),[NSObject new]);
    Check(dispatches==3 && !current,"non-key event forwards exactly once");
    NoResponder(expectedReceiver,sel_registerName("noResponderFor:"),expectedFailed);
    Check(forwarded==2,"out-of-dispatch key fallback forwards exactly once");
    unsigned forwardedBefore=forwarded,suppressedBefore=(unsigned)suppressedCount;
    KeyFallback(expectedReceiver,sel_registerName("noResponderFor:"),expectedFailed,ready);
    Check(forwarded==forwardedBefore && suppressedCount==suppressedBefore+1,"eligible terminal fallback skips default sound implementation");
    state=ready;state.enabled=false;
    KeyFallback(expectedReceiver,sel_registerName("noResponderFor:"),expectedFailed,state);
    Check(forwarded==++forwardedBefore,"observe-only terminal fallback calls original exactly once");
    state=ready;state.text=TextState::Editing;
    KeyFallback(expectedReceiver,sel_registerName("noResponderFor:"),expectedFailed,state);
    Check(forwarded==++forwardedBefore,"text editor terminal fallback calls original exactly once");
    expectedFailed=sel_registerName("keyUp:");NoResponder(expectedReceiver,sel_registerName("noResponderFor:"),expectedFailed);
    Check(forwarded==++forwardedBefore,"key-up fallback is never suppressed");
    expectedFailed=sel_registerName("keyDown:");std::thread worker([]{
        NoResponder(expectedReceiver,sel_registerName("noResponderFor:"),expectedFailed);
    });worker.join();Check(forwarded==++forwardedBefore,"off-main-thread fallback forwards without reading UIKit");
    originalFocus=(IMP)FocusProbe;requestedFocus=[NSObject new];
    Check(!MakeFirstResponder(expectedReceiver,sel_registerName("makeFirstResponder:"),requestedFocus) && focusCalls==1,"focus rejection result is preserved");
    // Install the actual guarded hooks in this isolated process, never the game.
    diagnostics=true;gLog=tmpfile();Check(gLog!=nullptr,"isolated diagnostic log opened");
    Check(Install() && installed,"all three AppKit hooks install with real metadata and provenance");
    Check(Install(),"installation is idempotent");
    Check(method_getImplementation(OwnMethod(windowClass,sel_registerName("sendEvent:")))==(IMP)SendEvent,"dispatch hook is active");
    Check(method_getImplementation(OwnMethod(objc_getClass("NSResponder"),sel_registerName("noResponderFor:")))==(IMP)NoResponder,"terminal fallback hook is active");
    Check(originalSend!=(IMP)SendEvent && originalFallback!=(IMP)NoResponder,"original system implementations retained");
    NSDictionary *config=@{@"KeyboardBeepFixEnabled":@NO,@"KeyboardBeepDiagnosticsEnabled":@YES};Configure(config);
    Check(!enabled && diagnostics,"configuration can disable only the repair and retain diagnostics");
    fflush(gLog);rewind(gLog);char buffer[2048]={};size_t count=fread(buffer,1,sizeof(buffer)-1,gLog);
    Check(count && strstr(buffer,"kbd_install ready=1") && strstr(buffer,"hardware_callbacks=unchanged"),"installation evidence is written to log");
    fclose(gLog);gLog=nullptr;
    printf("keyboard beep checks passed: %u\n",checks);
}}

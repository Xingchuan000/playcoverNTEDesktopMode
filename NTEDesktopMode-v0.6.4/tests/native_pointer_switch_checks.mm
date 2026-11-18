#import "../src/NTEDesktopMode.mm"
static unsigned checks=0;
static void Check(bool x,const char*n){++checks;if(!x){fprintf(stderr,"FAIL: %s\n",n);exit(1);}}
@interface NTEHoverScene : NSObject
@end
@implementation NTEHoverScene
- (UISceneActivationState)activationState{return UISceneActivationStateForegroundActive;}
@end
@interface NTEHoverWindow : NSObject
@property BOOL key;
@property id windowScene;
@end
@implementation NTEHoverWindow
- (BOOL)isKeyWindow{return self.key;}
@end
@interface NTEHoverView : NSObject
@property id window;
@end
@implementation NTEHoverView
- (CGRect)bounds{return CGRectMake(0,0,100,100);}
- (NativeCursor::Position)ViewSize{return {1000,1000};}
@end
@interface NTEHoverRecognizer : NSObject
@property UIGestureRecognizerState state;
@property id view;
@property CGPoint point;
@end
@implementation NTEHoverRecognizer
- (CGPoint)locationInView:(id)view{return self.point;}
@end
int main(){@autoreleasepool{
    bool all=true;
    for(unsigned word=0;word<65536;++word)all &= NativeIndirect::WithoutMouseForTouch(word,4)==(word&~4u);
    Check(all,"native mouse-for-touch switch preserves all other bits for every 16-bit setting word");
    alignas(8) uint8_t cls[0x118]={},settings[0x80]={},other[0x118]={};
    uintptr_t classPointer=(uintptr_t)cls,settingsPointer=(uintptr_t)settings;
    memcpy(cls+0x110,&settingsPointer,8);memcpy(settings+0x10,&classPointer,8);
    gBase=0;gGame.classCaches["InputSettings"]=(uintptr_t)&classPointer;
    gGame.NativeMouseForTouchSwitch=true;gGame.MouseForTouchOffset=0x48;gGame.MouseForTouchMask=4;
    uint16_t bits=0xabcd;memcpy(settings+0x48,&bits,2);
    gObserveOnly=true;ConfigureNativePointerSettings();Check(*(uint16_t*)(settings+0x48)==bits,"observe-only leaves the native setting unchanged");
    gObserveOnly=false;ConfigureNativePointerSettings();Check(*(uint16_t*)(settings+0x48)==0xabc9,"production switch only disables native bUseMouseForTouch");
    ConfigureNativePointerSettings();Check(*(uint16_t*)(settings+0x48)==0xabc9,"native setting switch is idempotent");
    memcpy(settings+0x48,&bits,2);uintptr_t wrong=(uintptr_t)other;memcpy(settings+0x10,&wrong,8);
    ConfigureNativePointerSettings();Check(*(uint16_t*)(settings+0x48)==bits,"foreign default object is not modified");
    memcpy(settings+0x10,&classPointer,8);uint32_t flags=0x10000;memcpy(settings+8,&flags,4);
    ConfigureNativePointerSettings();Check(*(uint16_t*)(settings+0x48)==bits,"destroying native setting object is not modified");
    flags=0;memcpy(settings+8,&flags,4);gGame.NativeMouseForTouchSwitch=false;
    ConfigureNativePointerSettings();Check(*(uint16_t*)(settings+0x48)==bits,"unresolved native setting is not modified");
    // Actual production hover callback: terminal recognizer changes must not
    // clear the last release position, while focus/bounds changes still do.
    gRestoreNativePointer=true;gRepairNativeCursorPlatform=true;gNativeCursor=0x200000100ULL;
    gNativeCursorState=NativeCursor::InitialState(1,true);gGame.ViewSize=(uintptr_t)class_getMethodImplementation(NTEHoverView.class,sel_registerName("ViewSize"));
    NTEHoverWindow *window=[NTEHoverWindow new];window.key=YES;window.windowScene=[NTEHoverScene new];
    NTEHoverView *hoverView=[NTEHoverView new];hoverView.window=window;
    NTEHoverRecognizer *recognizer=[NTEHoverRecognizer new];recognizer.view=hoverView;recognizer.point=CGPointMake(20,30);
    NTENativePointerObserver *observer=[NTENativePointerObserver new];const auto epoch=gCursorEpoch.load();NativeCursor::Position position;
    for(auto state:{UIGestureRecognizerStateEnded,UIGestureRecognizerStateCancelled}){
        gNativePosition.Publish({220,350},epoch);recognizer.state=state;[observer hover:(UIHoverGestureRecognizer*)recognizer];
        Check(gNativePosition.Read(epoch,position)&&position.x==220&&position.y==350,"terminal hover preserves authoritative release coordinates");
    }
    recognizer.state=UIGestureRecognizerStateChanged;[observer hover:(UIHoverGestureRecognizer*)recognizer];
    Check(gNativePosition.Read(epoch,position)&&position.x==200&&position.y==300,"valid native hover updates coordinates");
    window.key=NO;[observer hover:(UIHoverGestureRecognizer*)recognizer];Check(!gNativePosition.Read(epoch,position),"focus loss invalidates coordinates");
    window.key=YES;gNativePosition.Publish({220,350},epoch);recognizer.point=CGPointMake(-1,10);[observer hover:(UIHoverGestureRecognizer*)recognizer];
    Check(!gNativePosition.Read(epoch,position),"out-of-view position invalidates coordinates");
    printf("PASS: %u native pointer switch and terminal coordinate cases\n",checks);
}}

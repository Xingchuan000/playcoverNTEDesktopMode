#import "../src/NTEDesktopMode.mm"
static unsigned calls=0;static id lastView,lastTouches;static int lastType;
@interface FIOSView : NSObject
- (void)HandleTouches:(NSSet*)touches ofType:(int)type;
@end
@implementation FIOSView
- (void)HandleTouches:(NSSet*)touches ofType:(int)type{++calls;lastView=self;lastTouches=touches;lastType=type;}
@end
static void Other(id,SEL,NSSet*,int){calls+=100;}
static void check(bool x){if(!x)abort();}
int main(){@autoreleasepool{
 Class c=FIOSView.class;SEL s=@selector(HandleTouches:ofType:);Method m=class_getInstanceMethod(c,s);IMP original=method_getImplementation(m);
 gBase=0;gGame.HandleTouches=(uintptr_t)original;
 gObserveOnly=true;InstallNativeTouchObserver();check(!gNativeTouchReady&&method_getImplementation(m)==original);gObserveOnly=false;
 method_setImplementation(m,(IMP)Other);InstallNativeTouchObserver();check(!gNativeTouchReady&&method_getImplementation(m)==(IMP)Other);method_setImplementation(m,original);
 InstallNativeTouchObserver();check(gNativeTouchReady&&gNativeTouchOriginal==original);InstallNativeTouchObserver();
 FIOSView *v=[FIOSView new];NSSet *touches=[NSSet setWithObject:@"synthetic sentinel"];
 for(int type=0;type<4;++type){[v HandleTouches:touches ofType:type];check(calls==(unsigned)type+1&&lastView==v&&lastTouches==touches&&lastType==type);}
 method_setImplementation(m,original);
 puts("PASS: touch observer opt-out, competing override, idempotence and exact argument forwarding");
}}

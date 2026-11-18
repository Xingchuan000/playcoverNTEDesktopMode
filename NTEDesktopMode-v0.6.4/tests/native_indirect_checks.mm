// Standalone UIKit host. Never opens, starts or installs the game.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
static unsigned checks=0;
static void Check(bool ok,const char *label){++checks;if(!ok){fprintf(stderr,"FAIL: %s\n",label);exit(1);}}
static BOOL Replacement(id,SEL){return YES;}
@interface NTEIndirectSignatureProbe : NSObject
- (BOOL)booleanValue;
- (NSInteger)integerValue;
- (BOOL)argumentValue:(id)value;
@end
@implementation NTEIndirectSignatureProbe
- (BOOL)booleanValue{return NO;}
- (NSInteger)integerValue{return 0;}
- (BOOL)argumentValue:(id)value{return value!=nil;}
@end
@interface NTEIndirectInheritedProbe : NTEIndirectSignatureProbe
@end
@implementation NTEIndirectInheritedProbe
@end
int main(){ SetupFixtureLayout();@autoreleasepool{
    using namespace NativeIndirect;
    Method local=class_getInstanceMethod(NTEIndirectSignatureProbe.class,@selector(booleanValue));
    Check(BooleanGetter(local),"zero-argument BOOL signature accepted");
    Check(!BooleanGetter(nullptr),"missing getter rejected");
    Check(!BooleanGetter(class_getInstanceMethod(NTEIndirectSignatureProbe.class,@selector(integerValue))),"integer return rejected");
    Check(!BooleanGetter(class_getInstanceMethod(NTEIndirectSignatureProbe.class,@selector(argumentValue:))),"extra argument rejected");
    Check(!UIKitOwner(local),"third-party implementation rejected");
    Check(!OwnMethod(NTEIndirectInheritedProbe.class,@selector(booleanValue)),"inherited getter cannot mutate parent");
    Hook rejected;
    Check(!Prepare(rejected,NTEIndirectSignatureProbe.class,@selector(booleanValue),(IMP)Replacement),"fixture getter cannot pass UIKit ownership guard");
    Check(!Prepare(rejected,Nil,sel_registerName("missing"),(IMP)Replacement),"missing runtime class rejected");
    // No UIApplication is created by a command-line fixture. Inspect and install
    // its method, while exercising real dispatch on the independent parser.
    id app=nil;
    SEL selectors[]={sel_registerName("_supportsIndirectInputEvents"),sel_registerName("hasSupportsIndirectInputEventsKey"),sel_registerName("supportsIndirectInputEvents")};
    Class parserClass=NSClassFromString(@"_UIApplicationInfoParser");
    Check(parserClass!=Nil,"system UIKit parser present in standalone host");
    id parser=class_createInstance(parserClass,0);
    Check(parser!=nil,"independent zero-initialized parser fixture created");
    id objects[]={app,parser,parser};
    Class classes[]={UIApplication.class,parserClass,parserClass};
    IMP replacements[]={(IMP)NativeIndirectApp,(IMP)NativeIndirectHasKey,(IMP)NativeIndirectSupports};
    Hook hooks[3];BOOL originals[3];
    for(unsigned i=0;i<3;++i){
        Check(Prepare(hooks[i],classes[i],selectors[i],replacements[i]),"real UIKit getter passes metadata and owner guard");
        originals[i]=i?((BOOL(*)(id,SEL))hooks[i].original)(objects[i],selectors[i]):NO;
    }
    printf("Standalone host cached indirect policy before repair: %d (not the game's policy)\n",originals[0]);
    auto unchanged=[&]{bool ok=true;for(unsigned i=0;i<3;++i)ok&=method_getImplementation(hooks[i].method)==hooks[i].original;return ok;};
    auto result=Apply(hooks,2);
    Check(!result.applied && !strcmp(result.stage,"count") && unchanged(),"incomplete transaction leaves all methods unchanged");
    Check(!Apply(nullptr,3).applied && unchanged(),"null transaction rejected");
    Hook duplicate[]={hooks[0],hooks[0],hooks[2]};result=Apply(duplicate,3);
    Check(!result.applied && !strcmp(result.stage,"duplicate") && unchanged(),"duplicate entry rejected before writes");
    Hook invalid[]={hooks[0],hooks[1],hooks[2]};invalid[2].original=(IMP)Replacement;
    result=Apply(invalid,3);
    Check(!result.applied && !strcmp(result.stage,"preflight") && unchanged(),"stale implementation rejected before first write");
    method_setImplementation(hooks[2].method,(IMP)Replacement);
    result=Apply(hooks,3);
    Check(!result.applied && method_getImplementation(hooks[0].method)==hooks[0].original && method_getImplementation(hooks[1].method)==hooks[1].original && method_getImplementation(hooks[2].method)==(IMP)Replacement,"competing override preserved and other methods untouched");
    method_setImplementation(hooks[2].method,hooks[2].original);
    gMacPlatformApplied=true;gUIPlatformApplied=true;
    gObserveOnly=true;ConfigureNativeIndirectInput(true);
    Check(!gNativeIndirectEnabled.load() && unchanged(),"observation mode retains native UIKit policy");gObserveOnly=false;
    gRepairNativeIndirectInput=false;ConfigureNativeIndirectInput(true);
    Check(!gNativeIndirectEnabled.load() && unchanged(),"configuration opt-out retains policy");gRepairNativeIndirectInput=true;
    gMacPlatformApplied=false;ConfigureNativeIndirectInput(true);
    Check(!gNativeIndirectEnabled.load() && unchanged(),"failed desktop platform patch retains policy");gMacPlatformApplied=true;
    gUIPlatformApplied=false;ConfigureNativeIndirectInput(true);
    Check(!gNativeIndirectEnabled.load() && unchanged(),"failed desktop UI patch retains policy");gUIPlatformApplied=true;
    ConfigureNativeIndirectInput(false);
    Check(!gNativeIndirectEnabled.load() && unchanged(),"missing native coordinate callback prevents partial repair");
    ConfigureNativeIndirectInput(true);
    Check(gNativeIndirectEnabled.load(),"complete policy transaction applied in standalone host");
    for(unsigned i=0;i<3;++i){
        Check(method_getImplementation(hooks[i].method)==replacements[i],"all three policy accessors installed");
        if(i) Check(((BOOL(*)(id,SEL))objc_msgSend)(objects[i],selectors[i])==YES,"real parser dispatch observes indirect input support");
    }
    Check(hooks[0].original==gNativeIndirectHooks[0].original,"original UIApplication implementation remains saved");
    gNativeIndirectEnabled.store(false);
    for(unsigned i=1;i<3;++i)Check(((BOOL(*)(id,SEL))objc_msgSend)(objects[i],selectors[i])==originals[i],"disabled wrapper forwards original behavior");
    for(unsigned i=0;i<3;++i)method_setImplementation(hooks[i].method,hooks[i].original);
    Check(unchanged(),"all standalone host methods restored");
    Check(((BOOL(*)(id,SEL))objc_msgSend)(app,selectors[0])==originals[0],"application cache remains valid after restore");
    for(long phase=0;phase<=3;++phase)Check(PointerCoordinateEligible(3,phase,true,true,true,false),"native pointer begin/move/stationary/end coordinates allowed");
    for(long type : {-1L,0L,1L,2L,4L})Check(!PointerCoordinateEligible(type,1,true,true,true,false),"non-pointer touch never substitutes absolute mouse coordinates");
    for(long phase : {-1L,4L,5L})Check(!PointerCoordinateEligible(3,phase,true,true,true,false),"cancelled or unknown phase excluded");
    Check(!PointerCoordinateEligible(3,1,false,true,true,false),"mobile mode excluded");
    Check(!PointerCoordinateEligible(3,1,true,false,true,false),"worker-thread UIKit access excluded");
    Check(!PointerCoordinateEligible(3,1,true,true,false,false),"inactive window excluded");
    Check(!PointerCoordinateEligible(3,1,true,true,true,true),"captured gameplay retains relative input");
    printf("PASS: %u UIKit indirect policy, cached dispatch and pointer gating cases\n",checks);
return 0;}}

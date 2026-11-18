// Isolated synthetic cursor: never starts, installs or calls into the game.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
#include <limits>
#include <thread>
static int checks=0;
static void Check(bool ok,const char *label) {++checks;if(!ok){fprintf(stderr,"FAIL: %s\n",label);exit(1);}}
static unsigned lockCalls=0,unlockCalls=0;
static id expectedProxy=nil;
@interface NTEHostEndpointProbe : NSObject
@end
@implementation NTEHostEndpointProbe
- (void)lockCursorIfNecessaryForUINSWindow:(id)proxy shouldWarpCursor:(BOOL)warp {Check(proxy==expectedProxy&&warp,"host lock forwards proxy and native warp flag");++lockCalls;}
- (void)unlockCursorForUINSWindow:(id)proxy {Check(proxy==expectedProxy,"host unlock forwards correct proxy");++unlockCalls;}
@end
int main(int argc,char **argv) { SetupFixtureLayout();@autoreleasepool {
    using namespace NativeCursor;
    using HostCursor::Action;
    for(unsigned bits=0;bits<16;++bits) {
        bool wants=bits&1,active=bits&2,preferred=bits&4,hidden=bits&8;
        Action expected=!active?Action::None:wants!=preferred?Action::WaitForPreference:wants&&!hidden?Action::Lock:!wants&&hidden?Action::Unlock:Action::None;
        Check(HostCursor::Decide(wants,active,preferred,hidden)==expected,"all host preference/focus/hidden policy combinations");
    }
    Check(!HostCursor::TypeMatches(nullptr,'B'),"null type rejected");
    Check(!HostCursor::TypeMatches("i",'B'),"integer return not bool ABI");
    Check(HostCursor::TypeMatches("B",'B')&&HostCursor::TypeMatches("c",'B'),"ObjC bool encodings accepted");
    const struct {const char *cls,*sel;bool meta;char result;const char *args,*image;} guards[]={
      {"NSApplication","sharedApplication",true,'@',"","/AppKit.framework/"},
      {"NSApplication","keyWindow",false,'@',"","/AppKit.framework/"},
      {"NSWindow","UINS_windowProxyForContentView",false,'@',"","/UIKitMacHelper.framework/"},
      {"UINSWindowProxy","appearsKey",false,'B',"","/UIKitMacHelper.framework/"},
      {"UINSWindowProxy","sceneIdentifier",false,'@',"","/UIKitMacHelper.framework/"},
      {"UINSApplicationDelegate","sharedDelegate",true,'@',"","/UIKitMacHelper.framework/"},
      {"UINSApplicationDelegate","_pointerLockCursorIsHidden",false,'B',"","/UIKitMacHelper.framework/"},
      {"UINSApplicationDelegate","prefersPointerLockForSceneIdentifierCallback",false,'@',"","/UIKitMacHelper.framework/"},
      {"UINSApplicationDelegate","prefersPointerLockForSceneIdentifierCallback:",false,'B',"@","/UIKitMacHelper.framework/"},
      {"UINSApplicationDelegate","lockCursorIfNecessaryForUINSWindow:shouldWarpCursor:",false,'v',"@B","/UIKitMacHelper.framework/"},
      {"UINSApplicationDelegate","unlockCursorForUINSWindow:",false,'v',"@","/UIKitMacHelper.framework/"},
      {"UIScene","_sceneIdentifier",false,'@',"","/UIKitCore.framework/"}};
    for(auto &guard:guards) {
        Class cls=NSClassFromString(@(guard.cls));if(guard.meta)cls=object_getClass(cls);
        SEL sel=sel_registerName(guard.sel);
        Check(HostCursor::Verify(cls,sel,guard.image,guard.result,guard.args),"installed host metadata and image provenance match");
        Check(!HostCursor::Verify(cls,sel,"/not-a-system-framework/",guard.result,guard.args),"wrong implementation provenance rejected");
        Check(!HostCursor::Verify(cls,sel,guard.image,'i',guard.args),"wrong return ABI rejected");
        Check(!HostCursor::Verify(cls,sel,guard.image,guard.result,"@@@"),"wrong arity rejected");
    }
    Check(!HostCursor::Verify(Nil,@selector(description),"/UIKitCore.framework/",'@',""),"missing class rejected");
    Check(!HostCursor::SystemMethod(nil,@selector(description),'@',""),"missing instance rejected");
    Class host=NSClassFromString(@"UINSApplicationDelegate");
    Check(!HostCursor::Verify(host,sel_registerName("lockCursorIfNecessaryForUINSWindow:shouldWarpCursor:"),"/UIKitMacHelper.framework/",'v',"@i"),"wrong argument ABI rejected even with correct arity");
    HostCursor::Endpoint endpoint;
    endpoint.delegate=[NTEHostEndpointProbe new];expectedProxy=[NSObject new];endpoint.proxy=expectedProxy;
    HostCursor::Apply(endpoint,Action::None);HostCursor::Apply(endpoint,Action::WaitForPreference);
    Check(lockCalls==0&&unlockCalls==0,"no mutation for inactive/mismatched policy");
    HostCursor::Apply(endpoint,Action::Lock);HostCursor::Apply(endpoint,Action::Unlock);
    Check(lockCalls==1&&unlockCalls==1,"single native message for each transition");
    Position mapped={};
    Check(MapPosition({50,25},{0,0},{100,50},{200,100},mapped)&&mapped.x==100&&mapped.y==50,"native render scale maps both axes");
    Check(MapPosition({30,50},{10,20},{100,100},{200,300},mapped)&&mapped.x==40&&mapped.y==90,"nonzero bounds origin mapped");
    Check(MapPosition({0,0},{0,0},{100,50},{200,100},mapped)&&mapped.x==0&&mapped.y==0,"top-left coordinate accepted");
    Check(MapPosition({99.9,49.9},{0,0},{100,50},{200,100},mapped)&&mapped.x==199&&mapped.y==99,"last fractional render pixel clamped");
    Check(MapPosition({0.5,0.5},{0,0},{1,1},{1,1},mapped)&&mapped.x==0&&mapped.y==0,"single pixel render target accepted");
    for(Position p: {Position{-1,0},Position{0,-1},Position{100,20},Position{20,50},Position{NAN,1},Position{1,INFINITY}})
        Check(!MapPosition(p,{0,0},{100,50},{200,100},mapped),"out of bounds and nonfinite positions rejected");
    for(Position p: {Position{0,1},Position{1,0},Position{-1,1},Position{1,-1},Position{NAN,1},Position{1,INFINITY}})
        Check(!MapPosition({0,0},{0,0},p,{200,100},mapped),"invalid view dimensions rejected");
    for(Position p: {Position{0,1},Position{1,0},Position{65537,1},Position{1,65537},Position{NAN,1},Position{1,INFINITY}})
        Check(!MapPosition({0,0},{0,0},{100,50},p,mapped),"invalid render dimensions rejected");
    Check(!MapPosition({0,0},{NAN,0},{100,50},{200,100},mapped),"nonfinite origin rejected");
    PositionMailbox mailbox;Position out={};
    Check(!mailbox.Read(1,out),"mailbox initially empty");mailbox.Publish({3,5},7);
    Check(mailbox.Read(7,out)&&out.x==3&&out.y==5,"mailbox reads current epoch");
    Check(!mailbox.Read(8,out),"old epoch not reused after capture transition");mailbox.Invalidate();
    Check(!mailbox.Read(7,out),"invalidated sample unavailable");
    std::thread writer([&]{for(unsigned i=0;i<10000;++i)mailbox.Publish({double(i),-double(i)},9);});
    bool coherent=true;for(unsigned i=0;i<10000;++i)if(mailbox.Read(9,out)&&out.x!=-out.y)coherent=false;
    writer.join();Check(coherent,"cross-thread snapshots not torn");
    Check(argc==2,"fixture argument provided");void *image=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);Check(image,"signed fixture loaded");
    uintptr_t page=(uintptr_t)dlsym(image,"NTECursorFixturePage");Check(page,"cursor fixture symbol exists");
    gBase=page-0x1570000;gCursorRefreshQueued=true;
    std::array<uintptr_t,kSlots> expected;Table original={};
    for(size_t i=0;i<kSlots;++i)original[kHeaderWords+i]=expected[i]=gBase+kFunctions[i];
    Table clone;Check(BuildTable(original,expected,0x1110,0x2220,clone,0x3330),"three-hook table built");
    size_t differences=0;for(size_t i=0;i<clone.size();++i)differences+=clone[i]!=original[i];
    Check(differences==3&&clone[2+kGetPositionSlot]==0x3330,"exactly getter and two setter slots replaced");
    alignas(8) uint8_t cursor[0x38]={},foreign[0x38]={};
    auto put=[](uint8_t *p,size_t offset,auto value){memcpy(p+offset,&value,sizeof(value));};
    put(cursor,0,gBase+kCursorVTable);put(cursor,0x10,13.25);put(cursor,0x18,718.625);
    put(foreign,0x10,-41.75);put(foreign,0x18,51.5);
    Check(AttachNativeCursor((uintptr_t)cursor,original,expected),"instance adapter installed in signed fixture");
    auto getter=(Position(*)(uintptr_t))((uintptr_t*)*(uintptr_t*)cursor)[kGetPositionSlot];
    auto same=[](Position a,Position b){return a.x==b.x&&a.y==b.y;};
    Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"native HFA getter returns original two doubles");
    gNativePosition.Publish({105.5,208.25},gCursorEpoch.load());
    Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"captured gameplay never uses absolute sample");
    NativeCursorSetType((uintptr_t)cursor,1);
    Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"release invalidates previous mode sample");
    gNativePosition.Publish({105.5,208.25},gCursorEpoch.load());
    Check(same(getter((uintptr_t)cursor),{105.5,208.25}),"visible menu returns absolute sample through real vtable ABI");
    Check(same(getter((uintptr_t)foreign),{-41.75,51.5}),"foreign cursor always retains original position");
    gObserveOnly=true;Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"observe mode uses original getter");gObserveOnly=false;
    gRepairNativeCursorPlatform=false;Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"repair off uses original getter");gRepairNativeCursorPlatform=true;
    gRestoreNativePointer=false;Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"restore off uses original getter");gRestoreNativePointer=true;
    gNativePosition.Publish({2,4},gCursorEpoch.load()-1);
    Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"stale epoch ignored by real getter hook");
    uint64_t epoch=gCursorEpoch.load();NativeCursorSetType((uintptr_t)cursor,0);
    Check(gCursorEpoch.load()==epoch+1,"return to gameplay advances coordinate epoch");
    gNativePosition.Publish({1,2},gCursorEpoch.load());
    Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"recaptured gameplay remains original relative-input path");
    NativeCursorSetType((uintptr_t)cursor,1);gNativePosition.Publish({100,200},gCursorEpoch.load());
    Check(same(getter((uintptr_t)cursor),{100,200}),"second menu gets fresh absolute sample");
    gNativePosition.Invalidate();Check(same(getter((uintptr_t)cursor),{13.25,718.625}),"pointer exit invalidation restores native fallback");
    printf("PASS: %d native host bridge and absolute coordinate cases\n",checks);
}}

// Executes a synthetic FIOSCursor and signed fixture setters. Never opens the game.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
static int checks=0;
static void Check(bool ok,const char *label) {
    ++checks; if (!ok) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
static BOOL Yes(id,SEL) { return YES; }
static BOOL No(id,SEL) { return NO; }
int main(int argc,char **argv) { SetupFixtureLayout();
    @autoreleasepool {
        using namespace NativeCursor;
        Check(argc==2,"signed cursor fixture path");
        void *image=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
        Check(image!=nullptr,"load signed arm64 cursor fixture");
        uintptr_t page=(uintptr_t)dlsym(image,"NTECursorFixturePage");
        Check(page!=0,"cursor fixture symbol");
        gBase=page-0x1570000;
        gCursorRefreshQueued=true; // Avoid UIKit operations in this isolated test host.
        Check(WantsLock(0),"unknown native state preserves original YES");
        Check(!Ready(InitialState(15,false)),"unsupported initial enum rejected");
        Check(WantsLock(InitialState(0,false)),"native None starts captured");
        Check(!WantsLock(InitialState(1,false)),"constructor Show=false is not an explicit hide");
        for (uint32_t type=1;type<=14;++type)
            Check(!WantsLock(InitialState(type,true)),"all native visible cursor types release");
        uint32_t state=InitialState(1,false);
        state=WithShow(state,false);
        Check(WantsLock(state)&&ShowObserved(state),"explicit native hide captures");
        state=WithShow(state,true);
        Check(!WantsLock(state),"explicit native show releases");
        state=WithType(state,0);
        Check(WantsLock(state),"None remains hidden even if Show enabled");
        Check(WithType(state,100)==state,"unsupported enum preserves prior decision");
        Check(WithShow(0,true)==0,"show cannot invent an unverified cursor");
        Check(WithType(0,1)==0,"type cannot invent an unverified cursor");
        std::array<uintptr_t,kSlots> expected={}; Table original={},result={};
        for (size_t i=0;i<kSlots;++i) original[i+2]=expected[i]=gBase+kFunctions[i];
        Check(BuildTable(original,expected,0x1110,0x2220,result),"full matching table accepted");
        size_t differences=0;
        for (size_t i=0;i<result.size();++i) differences+=result[i]!=original[i];
        Check(differences==2,"exactly two slots changed");
        Check(result[kSetTypeSlot+2]==0x1110&&result[kShowSlot+2]==0x2220,"correct ABI slots replaced");
        Check(result[2]==original[2]&&result[3]==original[3],"both destructors preserved");
        Check(result[0]==0&&result[1]==0,"Itanium table prefix preserved");
        Check(result[2+0x58/8]==original[2+0x58/8],"native virtual bounds Lock preserved");
        const Table good=result;
        for (size_t i=0;i<original.size();++i) {
            Table bad=original; bad[i]^=8;
            Check(!BuildTable(bad,expected,0x1110,0x2220,result),"any altered prefix or vtable slot rejected");
            Check(result==good,"table guard failure leaves destination intact");
        }
        Check(!BuildTable(original,expected,0,0x2220,result),"null SetType callback rejected");
        Check(!BuildTable(original,expected,0x1110,0,result),"null Show callback rejected");
        alignas(8) uint8_t cursor[0x38]={},other[0x38]={};
        auto put=[](uint8_t *p,size_t offset,auto value){memcpy(p+offset,&value,sizeof(value));};
        put(cursor,0,gBase+kCursorVTable); put(other,0,gBase+kCursorVTable);
        const uintptr_t object=(uintptr_t)cursor;
        gObserveOnly=true;
        Check(!AttachNativeCursor(object,original,expected),"observe-only does not hook native cursor");
        gObserveOnly=false; gRepairNativeCursorPlatform=false;
        Check(!AttachNativeCursor(object,original,expected),"cursor repair disabled does not hook");
        gRepairNativeCursorPlatform=true; gRestoreNativePointer=false;
        Check(!AttachNativeCursor(object,original,expected),"pointer restore switch also disables repair");
        gRestoreNativePointer=true;
        Check(!AttachNativeCursor(0,original,expected),"null cursor rejected");
        put(cursor,8,uint32_t(99));
        Check(!AttachNativeCursor(object,original,expected),"corrupt type rejected before vptr write");
        put(cursor,8,uint32_t(0)); put(cursor,0x30,uint8_t(2));
        Check(!AttachNativeCursor(object,original,expected),"corrupt native bool rejected");
        put(cursor,0x30,uint8_t(0)); put(cursor,0,uintptr_t(1));
        Check(!AttachNativeCursor(object,original,expected),"unexpected original vptr rejected");
        put(cursor,0,gBase+kCursorVTable);
        auto before=std::array<uint8_t,sizeof(cursor)>{}; memcpy(before.data(),cursor,sizeof(cursor));
        Check(AttachNativeCursor(object,original,expected),"verified synthetic cursor attached");
        Check(gNativeCursor.load()==object&&Ready(gNativeCursorState.load()),"verified cursor state published");
        Check(!memcmp(cursor+8,before.data()+8,sizeof(cursor)-8),"installation preserves all engine cursor fields");
        Check(AttachNativeCursor(object,original,expected),"attachment is idempotent");
        Check(!AttachNativeCursor((uintptr_t)other,original,expected),"second cursor cannot invalidate first clone");
        uintptr_t table=0; ReadValue(object,table);
        Check(table==(uintptr_t)(gNativeCursorVTable.data()+2),"only instance vptr points at clone");
        Check(original[2+kSetTypeSlot]==gBase+kFunctions[kSetTypeSlot],"shared original table remains unchanged");
        auto setType=(void(*)(uintptr_t,uint32_t))((uintptr_t *)table)[kSetTypeSlot];
        auto show=(void(*)(uintptr_t,bool))((uintptr_t *)table)[kShowSlot];
        setType(object,1); uint32_t nativeType=99; ReadValue(object+8,nativeType);
        Check(nativeType==1&&!WantsLock(gNativeCursorState.load()),"native SetType executes and releases menu cursor");
        show(object,false); uint8_t shown=9; ReadValue(object+0x30,shown);
        Check(shown==0&&WantsLock(gNativeCursorState.load()),"native Show(false) executes and captures");
        show(object,true); ReadValue(object+0x30,shown);
        Check(shown==1&&!WantsLock(gNativeCursorState.load()),"native Show(true) executes and releases");
        setType(object,0);
        Check(WantsLock(gNativeCursorState.load()),"native menu close returns to capture");
        setType(object,1);
        Check(!WantsLock(gNativeCursorState.load()),"native Option visible cursor releases");
        setType(object,0);
        Check(WantsLock(gNativeCursorState.load()),"native Option release returns to capture");
        uint32_t previous=gNativeCursorState.load(); setType(object,99); ReadValue(object+8,nativeType);
        Check(nativeType==99&&gNativeCursorState.load()==previous,"invalid enum still forwards native setter but retains last valid preference");
        setType(object,0);
        Check(gNativeTypeCalls.load()==6&&gNativeShowCalls.load()==2,"each native setter forwarded once");
        setType((uintptr_t)other,1); ReadValue((uintptr_t)other+8,nativeType);
        Check(nativeType==1&&gNativeCursorState.load()==previous,"foreign object forwarded without affecting preference");
        Class parent=objc_allocateClassPair(NSObject.class,"NTENativeCursorParentProbe",0);
        SEL selector=@selector(prefersPointerLocked);
        class_addMethod(parent,selector,(IMP)Yes,"B@:"); objc_registerClassPair(parent);
        Class child=objc_allocateClassPair(parent,"NTENativeCursorChildProbe",0); objc_registerClassPair(child);
        Check(!InstallNativeCursorPreference(child,selector,(IMP)Yes),"inherited UIKit preference not mutated");
        class_addMethod(child,selector,(IMP)Yes,"B@:");
        gObserveOnly=true;
        Check(!InstallNativeCursorPreference(child,selector,(IMP)Yes),"observe mode does not replace preference");
        gObserveOnly=false;
        Check(!InstallNativeCursorPreference(child,selector,(IMP)No),"unknown swizzle not overwritten");
        Check(InstallNativeCursorPreference(child,selector,(IMP)Yes),"owned preference replaced after verified attachment");
        Check(InstallNativeCursorPreference(child,selector,(IMP)Yes),"preference install idempotent");
        id instance=[[child alloc] init];
        auto query=[&]{return ((BOOL(*)(id,SEL))objc_msgSend)(instance,selector);};
        Check(query(),"actual Objective-C preference captures hidden native cursor");
        setType(object,1);
        Check(!query(),"actual Objective-C preference releases visible native cursor");
        setType(object,0);
        Check(query(),"actual Objective-C preference recaptures on native transition");
        gObserveOnly=true;
        Check(query(),"disabled adapter calls original arm64 YES preference");
        gObserveOnly=false; gNativeCursorState=0;
        Check(query(),"unknown state retains original capture rather than permanent free cursor");
        Check(class_getMethodImplementation(parent,selector)==(IMP)Yes,"parent preference remains intact");
        Check(gCursorRefreshQueued.load(),"setter events coalesced without running UIKit on engine thread");
        printf("PASS: %d native cursor platform adapter cases\n",checks);
        // No UIKit run loop is driven, and no installed game function is invoked.
    }
}

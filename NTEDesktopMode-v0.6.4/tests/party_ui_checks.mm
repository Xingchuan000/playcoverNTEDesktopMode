#import "../src/NTEDesktopMode.mm"
static unsigned checks=0;
static void Check(bool ok,const char *name){++checks;if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);}}
static void Put(uint8_t *where,size_t offset,uintptr_t value){memcpy(where+offset,&value,8);}
int main(){@autoreleasepool{
    using namespace PartyUI;
    for(int oldCount=1;oldCount<=4;++oldCount)for(int newCount=0;newCount<=5;++newCount)for(bool compatible:{false,true}) {
        bool mobile=false;int count=oldCount,clears=0,refreshes=0,restores=0;
        auto r=Rebuild(oldCount,[&]{++clears;count=0;},[&]{++refreshes;count=mobile?oldCount:newCount;},
            [&]{return RebuildCheck{true,!mobile&&compatible,count};},[&]{++restores;mobile=true;});
        bool expected=compatible && newCount>=oldCount && newCount<=4;
        Check(r.success==expected,"rebuild accepts only recognized desktop lists without losing entries");
        Check(expected?(clears==1&&refreshes==1&&restores==0):(clears==2&&refreshes==2&&restores==1&&r.rolledBack&&r.restored),"native operation order and rollback counts");
        Check(expected || count==oldCount,"failed replacement restores original list count");
    }
    int refreshes=0,restores=0;
    auto failed=Rebuild(3,[]{},[&]{++refreshes;},[]{return RebuildCheck{true,false,3};},[&]{++restores;});
    Check(!failed.success && failed.rolledBack && refreshes==0 && restores==1,"clear refusal never starts replacement refresh");
    auto invalid=Rebuild(3,[]{},[&]{++refreshes;},[]{return RebuildCheck{};},[&]{++restores;});
    Check(!invalid.success && invalid.rolledBack && refreshes==0,"unreadable cleared container never starts refresh");
    alignas(8)uint8_t mainClass[0x80]={},slotClass[0x80]={},mobileClass[0x80]={},meta[0x80]={},form[0x100]={};
    alignas(8)uintptr_t chain[2]={(uintptr_t)slotClass+0x30,0};
    Put(slotClass,0x10,(uintptr_t)meta);Put(mobileClass,0x10,(uintptr_t)meta);
    Put(mobileClass,0x30,(uintptr_t)chain);int32_t depth=1;memcpy(mobileClass+0x38,&depth,4);
    Put(form,0x10,(uintptr_t)mainClass);uint32_t flags=0x10;memcpy(form+8,&flags,4);
    gPartyLayout={};gPartyLayout.ready=true;gPartyLayout.pc=0x40;gPartyLayout.mobile=0x48;gPartyLayout.container=0x50;
    auto reset=[&]{states.clear();Put(form,0x40,(uintptr_t)slotClass);Put(form,0x48,(uintptr_t)mobileClass);gObserveOnly=false;repairEnabled=true;};
    reset();
    Check(ClassAsset((uintptr_t)slotClass,(uintptr_t)slotClass) && ClassAsset((uintptr_t)mobileClass,(uintptr_t)slotClass),"valid base and derived widget classes pass eligibility");
    Check(!ClassAsset(0,(uintptr_t)slotClass),"null desktop asset rejected");
    gObserveOnly=true;Process((uintptr_t)form,1,1,1,(uintptr_t)mainClass,(uintptr_t)slotClass,0);
    Check(*(uintptr_t*)(form+0x48)==(uintptr_t)mobileClass,"global observe mode preserves main-form default field");
    reset();repairEnabled=false;Process((uintptr_t)form,1,1,1,(uintptr_t)mainClass,(uintptr_t)slotClass,0);
    Check(*(uintptr_t*)(form+0x48)==(uintptr_t)mobileClass,"party repair opt-out preserves default field");
    reset();Put(form,0x40,0);Process((uintptr_t)form,1,1,1,(uintptr_t)mainClass,(uintptr_t)slotClass,0);
    Check(*(uintptr_t*)(form+0x48)==(uintptr_t)mobileClass,"missing desktop class never overwrites mobile class");
    reset();flags=0x8000;memcpy(form+8,&flags,4);Process((uintptr_t)form,1,1,1,(uintptr_t)mainClass,(uintptr_t)slotClass,0);
    Check(*(uintptr_t*)(form+0x48)==(uintptr_t)mobileClass,"destroying main-form object is untouched");
    flags=0x10;memcpy(form+8,&flags,4);reset();uint8_t before[0x100];memcpy(before,form,sizeof(before));
    Process((uintptr_t)form,1,1,1,(uintptr_t)mainClass,(uintptr_t)slotClass,0);
    Check(*(uintptr_t*)(form+0x48)==(uintptr_t)slotClass,"valid class default uses desktop slot class for later widgets");
    bool onlyTarget=true;for(unsigned i=0;i<sizeof(before);++i)if(i<0x48 || i>=0x50)onlyTarget &= before[i]==form[i];
    Check(onlyTarget,"class-default correction preserves every other field byte");
    auto saved=states.begin()->second.originalMobile;
    Process((uintptr_t)form,1,1,2,(uintptr_t)mainClass,(uintptr_t)slotClass,0);
    Check(states.size()==1 && states.begin()->second.originalMobile==saved,"repeated scan preserves rollback class and identity");
    Check(!kLoggingEnabled && !kHardwareObservers,"default test source retains quiet keyboard repair and native hardware callbacks");
    printf("party UI checks passed: %u\n",checks);
}}

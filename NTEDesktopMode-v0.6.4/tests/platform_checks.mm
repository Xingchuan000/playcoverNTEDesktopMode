// Execute only synthetic and signed test-fixture code, never the installed game.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
#include <fstream>
#include <iterator>
static int checks=0;
static void Check(bool condition,const char *label) {
    ++checks; if (!condition) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
static std::vector<uint8_t> FileBytes(const char *path) {
    std::ifstream file(path,std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(file)),{});
}
static void Populate(uintptr_t page) {
    memset((void *)page,0xa5,vm_page_size);
    for (const auto &query:MacPlatform::kQueries) {
        uint32_t words[]={MacPlatform::ReturnValue(query.original),MacPlatform::kRet};
        memcpy((void *)(page+(query.offset&0x3fff)),words,8);
    }
}
static void StateIs(uintptr_t base,bool mac,const char *label) {
    MacPlatform::State state;
    Check(MacPlatform::Inspect(base,state),label);
    for (size_t i=0;i<5;++i)
        Check(state.values[i]==(mac?MacPlatform::kQueries[i].desktop:MacPlatform::kQueries[i].original),MacPlatform::kQueries[i].name);
}
static int remapCalls=0;
static kern_return_t DenyRemap(uintptr_t,const MacPlatform::Page &) {
    ++remapCalls; return KERN_PROTECTION_FAILURE;
}
static kern_return_t FailAfterFirstRemap(uintptr_t target,const MacPlatform::Page &page) {
    ++remapCalls;
    kern_return_t status=MacPlatform::Replace(target,page);
    if (status==KERN_SUCCESS && remapCalls==1) return KERN_FAILURE;
    return status;
}
int main(int argc,char **argv) { SetupFixtureLayout();
    @autoreleasepool {
        Check(argc==2,"fixture path supplied");
        Check(vm_page_size==16384,"fixture matches arm64 host page geometry");
        auto result=MacPlatform::Apply(0);
        Check(!result.applied && !strcmp(result.stage,"page-layout"),"null base rejected");
        result=MacPlatform::Apply(UINTPTR_MAX-0x100);
        Check(!result.applied && result.error==KERN_INVALID_ADDRESS,"overflow base rejected");
        mach_vm_address_t allocation=0;
        Check(mach_vm_allocate(mach_task_self(),&allocation,vm_page_size,VM_FLAGS_ANYWHERE)==KERN_SUCCESS,"allocate synthetic page");
        uintptr_t base=allocation-0xaa18000;
        Populate(allocation);
        std::vector<uint8_t> original(vm_page_size),actual(vm_page_size);
        memcpy(original.data(),(void *)allocation,vm_page_size);
        result=MacPlatform::Apply(base);
        Check(!result.applied && !strcmp(result.stage,"source-protection"),"writable code page rejected");
        Check(!memcmp(original.data(),(void *)allocation,vm_page_size),"writable rejection leaves bytes untouched");
        result=MacPlatform::Apply(base+1);
        Check(!result.applied && !strcmp(result.stage,"page-layout"),"unaligned instructions rejected");
        result=MacPlatform::Apply(base+0xe08);
        Check(!result.applied && !strcmp(result.stage,"page-layout"),"helpers crossing a page rejected");
        Check(mach_vm_protect(mach_task_self(),allocation,vm_page_size,FALSE,VM_PROT_READ)==KERN_SUCCESS,"set read-only fixture");
        result=MacPlatform::Apply(base);
        Check(!result.applied && !strcmp(result.stage,"source-protection"),"non-executable page rejected");
        Check(mach_vm_protect(mach_task_self(),allocation,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_WRITE)==KERN_SUCCESS,"prepare corrupt fixture");
        uint32_t unknown=MacPlatform::ReturnValue(7);
        memcpy((void *)(allocation+0x317c),&unknown,4);
        Check(mach_vm_protect(mach_task_self(),allocation,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_EXECUTE)==KERN_SUCCESS,"protect corrupt fixture RX");
        std::vector<uint8_t> corrupt(vm_page_size); memcpy(corrupt.data(),(void *)allocation,vm_page_size);
        result=MacPlatform::Apply(base);
        Check(!result.applied && !strcmp(result.stage,"instruction-guard"),"unexpected helper body rejected");
        Check(!memcmp(corrupt.data(),(void *)allocation,vm_page_size),"all helper bytes unchanged on signature rejection");
        MacPlatform::State state;
        Check(!MacPlatform::Inspect(base,state),"unknown helper never executed by diagnostics");
        Check(mach_vm_protect(mach_task_self(),allocation,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_WRITE)==KERN_SUCCESS,"repair synthetic fixture");
        Populate(allocation);
        Check(mach_vm_protect(mach_task_self(),allocation,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_EXECUTE)==KERN_SUCCESS,"protect synthetic code RX");
        StateIs(base,false,"original synthetic functions execute");
        remapCalls=0;
        result=MacPlatform::Apply(base,DenyRemap);
        Check(!result.applied && !strcmp(result.stage,"remap") && result.error==KERN_PROTECTION_FAILURE,"simulated system refusal is reported");
        Check(remapCalls==1 && !result.rollbackAttempted,"unchanged page needs no rollback after refusal");
        Check(MacPlatform::Matches(allocation,original),"refused remap leaves original executable page intact");
        remapCalls=0;
        result=MacPlatform::Apply(base,FailAfterFirstRemap);
        Check(!result.applied && result.rollbackAttempted && result.rollbackSucceeded,"failure after replacement restores prepared RX backup");
        Check(remapCalls==2 && result.rollbackError==KERN_SUCCESS,"rollback uses one verified remap");
        Check(MacPlatform::Matches(allocation,original),"rollback restores complete page bytes and RX protection");
        StateIs(base,false,"original functions execute after rollback");
        gBase=base; gObserveOnly=true; gSpoofMacPlatform=true; gMacPlatformApplied=false;
        ConfigureMacPlatform();
        Check(!gMacPlatformApplied && !memcmp(original.data(),(void *)allocation,vm_page_size),"ObserveOnly prevents platform writes");
        gObserveOnly=false; gSpoofMacPlatform=false;
        ConfigureMacPlatform();
        Check(!gMacPlatformApplied && !memcmp(original.data(),(void *)allocation,vm_page_size),"disabled spoof prevents platform writes");
        gSpoofMacPlatform=true;
        ConfigureMacPlatform();
        Check(gMacPlatformApplied,"constructor wrapper applies enabled spoof");
        StateIs(base,true,"changed synthetic functions execute");
        std::vector<uint8_t> expected=original;
        for (const auto &query:MacPlatform::kQueries) {
            uint32_t word=MacPlatform::ReturnValue(query.desktop);
            memcpy(expected.data()+(query.offset&0x3fff),&word,4);
        }
        Check(MacPlatform::ReadMemory(allocation,actual.data(),actual.size()) && actual==expected,"whole page matches exactly four intended instruction changes");
        Check(MacPlatform::RegionRX(allocation,vm_page_size),"replacement remains RX without write permission");
        Check(mach_vm_protect(mach_task_self(),allocation,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_WRITE)!=KERN_SUCCESS,"replacement maximum protection prohibits writable code");
        result=MacPlatform::Apply(base);
        Check(!result.applied && !strcmp(result.stage,"instruction-guard"),"already modified helper rejected without reapplying");
        Check(MacPlatform::Matches(allocation,expected),"failed repeat preserves patched page");
        Check(mach_vm_deallocate(mach_task_self(),allocation,vm_page_size)==KERN_SUCCESS,"release synthetic fixture");
        auto diskBefore=FileBytes(argv[1]);
        Check(!diskBefore.empty(),"read signed fixture file");
        void *image=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
        Check(image!=nullptr,"load signed file-backed fixture");
        auto fixture=(uintptr_t)dlsym(image,"NTEPlatformFixturePage");
        Check(fixture && !(fixture&0x3fff),"signed fixture code has expected page alignment");
        uintptr_t fileBase=fixture-0xaa18000;
        StateIs(fileBase,false,"original signed file-backed functions execute");
        result=MacPlatform::Apply(fileBase);
        if (!result.applied) fprintf(stderr,"signed fixture failure: stage=%s error=%d rollback=%d/%d\n",result.stage,result.error,result.rollbackAttempted,result.rollbackSucceeded);
        Check(result.applied && !result.rollbackAttempted,"signed file-backed RX code successfully replaced");
        StateIs(fileBase,true,"patched signed file-backed functions execute");
        Check(MacPlatform::RegionRX(fixture,vm_page_size),"signed fixture replacement remains RX");
        Check(FileBytes(argv[1])==diskBefore,"signed fixture file on disk remains byte-for-byte unchanged");
        printf("PASS: %d Mac platform checks, including signed file-backed arm64 execution.\n",checks);
    }
}

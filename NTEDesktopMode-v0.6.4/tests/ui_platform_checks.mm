// Execute isolated synthetic/signed fixtures only. Never execute installed game code.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
#include <fstream>
#include <iterator>
static int checks=0;
static void Check(bool ok,const char *label) {
    ++checks; if (!ok) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
static std::vector<uint8_t> FileBytes(const char *path) {
    std::ifstream file(path,std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(file)),{});
}
static int remaps=0;
static kern_return_t Deny(uintptr_t,const MacPlatform::Page &) { ++remaps; return KERN_PROTECTION_FAILURE; }
static kern_return_t FailAfterRemap(uintptr_t target,const MacPlatform::Page &source) {
    ++remaps;
    auto status=MacPlatform::Replace(target,source);
    return status==KERN_SUCCESS && remaps==1 ? KERN_FAILURE : status;
}
static void StateIs(uintptr_t base,uint32_t expected,const char *label) {
    uint32_t value=99;
    Check(MacPlatform::InspectUI(base,value) && value==expected,label);
    // Exact platform masks from native UI selector/controller gate, checked against
    // game bytes separately in validate_v052.py. No fabricated UI asset is loaded.
    Check((value<=8 && ((1u<<value)&0x10c)!=0)==(expected==2),"native mobile UI mask changes branch");
    Check((value<=5 && ((1u<<value)&0x32)!=0)==(expected==4),"native desktop cursor mask changes branch");
}
int main(int argc,char **argv) { SetupFixtureLayout();
    @autoreleasepool {
        Check(argc==2,"signed fixture path");
        Check(vm_page_size==16384,"arm64 page layout");
        uint32_t value=0;
        Check(!MacPlatform::InspectUI(0,value),"null diagnostic pointer rejected");
        Check(!MacPlatform::ApplyUI(0).applied,"null patch base rejected");
        Check(!MacPlatform::ApplyUI(UINTPTR_MAX-4).applied,"overflow patch base rejected");
        Check(!MacPlatform::InspectUI(UINTPTR_MAX-4,value),"overflow diagnostic pointer rejected");
        mach_vm_address_t page=0;
        Check(mach_vm_allocate(mach_task_self(),&page,vm_page_size,VM_FLAGS_ANYWHERE)==KERN_SUCCESS,"allocate isolated fixture");
        const uintptr_t base=page-0xaa08000;
        memset((void *)page,0xa5,vm_page_size);
        uint32_t words[]={MacPlatform::ReturnValue(2),MacPlatform::kRet};
        memcpy((void *)(page+0x3f34),words,sizeof(words));
        std::vector<uint8_t> original(vm_page_size); memcpy(original.data(),(void *)page,vm_page_size);
        Check(!MacPlatform::ApplyUI(base).applied,"writable page rejected");
        Check(!MacPlatform::ApplyUI(base+1).applied,"unaligned code rejected");
        Check(mach_vm_protect(mach_task_self(),page,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_EXECUTE)==KERN_SUCCESS,"fixture RX");
        StateIs(base,2,"original query executes as IOS=2");
        remaps=0;
        auto result=MacPlatform::ApplyUI(base,Deny);
        Check(!result.applied && result.error==KERN_PROTECTION_FAILURE && remaps==1,"remap refusal reported");
        Check(!result.rollbackAttempted && MacPlatform::Matches(page,original),"refusal preserves full source page");
        remaps=0;
        result=MacPlatform::ApplyUI(base,FailAfterRemap);
        Check(!result.applied && result.rollbackAttempted && result.rollbackSucceeded && remaps==2,"failure after remap rolls back");
        Check(MacPlatform::Matches(page,original),"rollback restores complete RX page");
        StateIs(base,2,"rolled back query still executes IOS=2");
        gBase=base; gObserveOnly=true; gSpoofMacPlatform=true; gUIPlatformApplied=false;
        ConfigureUIPlatform();
        Check(!gUIPlatformApplied && MacPlatform::Matches(page,original),"observe mode preserves UI query");
        gObserveOnly=false; gSpoofMacPlatform=false;
        ConfigureUIPlatform();
        Check(!gUIPlatformApplied && MacPlatform::Matches(page,original),"spoof switch disables both query families");
        gSpoofMacPlatform=true;
        ConfigureUIPlatform();
        Check(gUIPlatformApplied,"startup wrapper applies native UI recognition");
        StateIs(base,4,"patched query executes Mac=4");
        auto expected=original;
        uint32_t replacement=MacPlatform::ReturnValue(4);
        memcpy(expected.data()+0x3f34,&replacement,4);
        Check(MacPlatform::Matches(page,expected),"entire page differs only by intended query instruction");
        Check(mach_vm_protect(mach_task_self(),page,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_WRITE)!=KERN_SUCCESS,"RX maximum prevents writable code");
        result=MacPlatform::ApplyUI(base);
        Check(!result.applied && !strcmp(result.stage,"instruction-guard"),"repeat patch rejected");
        Check(MacPlatform::Matches(page,expected),"repeat rejection preserves patched query");
        Check(mach_vm_deallocate(mach_task_self(),page,vm_page_size)==KERN_SUCCESS,"release isolated page");
        Check(mach_vm_allocate(mach_task_self(),&page,vm_page_size,VM_FLAGS_ANYWHERE)==KERN_SUCCESS,"allocate wrong-enum fixture");
        const uintptr_t corruptBase=page-0xaa08000;
        memset((void *)page,0,vm_page_size);
        words[0]=MacPlatform::ReturnValue(16);
        memcpy((void *)(page+0x3f34),words,8);
        Check(mach_vm_protect(mach_task_self(),page,vm_page_size,FALSE,VM_PROT_READ|VM_PROT_EXECUTE)==KERN_SUCCESS,"wrong-enum fixture RX");
        Check(!MacPlatform::InspectUI(corruptBase,value),"other platform enum rejected before execution");
        result=MacPlatform::ApplyUI(corruptBase);
        Check(!result.applied && !strcmp(result.stage,"instruction-guard"),"wrong-enum source not patched");
        Check(mach_vm_deallocate(mach_task_self(),page,vm_page_size)==KERN_SUCCESS,"release wrong-enum fixture");
        auto diskBefore=FileBytes(argv[1]);
        Check(!diskBefore.empty(),"read signed fixture");
        void *image=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);
        Check(image!=nullptr,"load signed fixture");
        const uintptr_t signedPage=(uintptr_t)dlsym(image,"NTEUIPlatformFixturePage");
        Check(signedPage && !(signedPage&0x3fff),"signed UI query page aligned");
        const uintptr_t signedBase=signedPage-0xaa08000;
        StateIs(signedBase,2,"original signed UI query executes");
        result=MacPlatform::ApplyUI(signedBase);
        Check(result.applied && !result.rollbackAttempted,"signed UI query page remapped");
        StateIs(signedBase,4,"patched signed UI query executes");
        Check(FileBytes(argv[1])==diskBefore,"signed fixture disk bytes remain identical");
        printf("PASS: %d native UI platform checks, including arm64 signed-code execution.\n",checks);
    }
}

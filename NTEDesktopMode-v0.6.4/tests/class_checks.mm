// Standalone Catalyst test host. No game process, input devices or installation.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
#include <cstdlib>

static int checks=0;
static void Check(bool value, const char *label) {
    ++checks;
    if (!value) { fprintf(stderr,"FAIL: %s\n", label); exit(1); }
}
struct alignas(8) FakeClass {
    uint8_t objectAndField[0x30]{};
    uintptr_t chain=0;
    int32_t depth=0;
};
static_assert(offsetof(FakeClass,chain)==0x30);
static_assert(offsetof(FakeClass,depth)==0x38);

int main() { SetupFixtureLayout();
    @autoreleasepool {
        FakeClass root, target, child, grandchild, unrelated;
        uintptr_t rootID=(uintptr_t)&root+0x30;
        uintptr_t targetID=(uintptr_t)&target+0x30;
        uintptr_t targetChain[]={rootID,targetID};
        target.chain=(uintptr_t)targetChain; target.depth=1;
        uintptr_t childChain[]={rootID,targetID,(uintptr_t)&child+0x30};
        child.chain=(uintptr_t)childChain; child.depth=2;
        uintptr_t grandchildChain[]={rootID,targetID,(uintptr_t)&child+0x30,(uintptr_t)&grandchild+0x30};
        grandchild.chain=(uintptr_t)grandchildChain; grandchild.depth=3;
        uintptr_t unrelatedChain[]={rootID,(uintptr_t)&unrelated+0x30};
        unrelated.chain=(uintptr_t)unrelatedChain; unrelated.depth=1;
        Check(ClassIsA((uintptr_t)&target,(uintptr_t)&target),"exact class");
        Check(ClassIsA((uintptr_t)&child,(uintptr_t)&target),"direct subclass");
        Check(ClassIsA((uintptr_t)&grandchild,(uintptr_t)&target),"indirect subclass");
        Check(!ClassIsA((uintptr_t)&unrelated,(uintptr_t)&target),"unrelated class at same depth");
        Check(!ClassIsA((uintptr_t)&root,(uintptr_t)&target),"ancestor is not a subclass");
        Check(!ClassIsA(0,0),"null classes");
        Check(!ClassIsA((uintptr_t)&child+1,(uintptr_t)&target),"unaligned class");
        child.depth=256;
        Check(!ClassIsA((uintptr_t)&child,(uintptr_t)&target),"invalid depth");
        child.depth=2; child.chain=0x100000000ULL;
        Check(!ClassIsA((uintptr_t)&child,(uintptr_t)&target),"unreadable chain fails safely");
        child.chain=0;
        Check(!ClassIsA((uintptr_t)&child,(uintptr_t)&target),"missing chain");
        printf("PASS: %d class identity/inheritance/read validation cases\n",checks);
    }
}

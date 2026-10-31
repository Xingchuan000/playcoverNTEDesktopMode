#pragma once
// Process-local, guarded query patches. Each group occupies one verified RX page.
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <mach/vm_statistics.h>
#include <libkern/OSCacheControl.h>
#include <cstdint>
#include <cstring>
#include <vector>

namespace MacPlatform {
struct Query { const char *name; uintptr_t offset; uint32_t original, desktop; };
// GetCurrentPlatform returns EHTCommonPlatformType (Mac=2), not EHTPlatformType.
static constexpr Query kQueries[] = {
    {"GetCurrentPlatform", 0xaa1b164, 16, 2},
    {"IsPC",               0xaa1b16c,  0, 0},
    {"IsMac",              0xaa1b174,  0, 1},
    {"IsDesktop",          0xaa1b17c,  0, 1},
    {"IsMobilePlatform",   0xaa1b1f4,  1, 0},
};
// Independent native UI/settings platform query: EHTPlatformType IOS=2, Mac=4.
static constexpr Query kUIQueries[] = {{"NativeUIPlatform", 0xaa0bf34, 2, 4}};
static constexpr uint32_t kRet = 0xd65f03c0;
static constexpr uint32_t ReturnValue(uint32_t value) { return 0x52800000 | (value << 5); }
struct State { uint32_t values[5] = {}; };
struct Result {
    bool applied=false, rollbackAttempted=false, rollbackSucceeded=false;
    const char *stage="not-started";
    kern_return_t error=KERN_SUCCESS, rollbackError=KERN_SUCCESS;
    size_t pageSize=0;
};
inline bool ReadMemory(uintptr_t address, void *out, size_t size) {
    mach_vm_size_t copied=0;
    return address && size && mach_vm_read_overwrite(mach_task_self(), address, size,
        (mach_vm_address_t)out, &copied)==KERN_SUCCESS && copied==size;
}
inline bool RegionRX(uintptr_t address, size_t length) {
    mach_vm_address_t region=address;
    mach_vm_size_t size=0;
    vm_region_basic_info_data_64_t info={};
    mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object=MACH_PORT_NULL;
    kern_return_t status=mach_vm_region(mach_task_self(), &region, &size,
        VM_REGION_BASIC_INFO_64, (vm_region_info_t)&info, &count, &object);
    if (object!=MACH_PORT_NULL) mach_port_deallocate(mach_task_self(),object);
    return status==KERN_SUCCESS && region<=address && address-region<=size
        && length<=size-(address-region)
        && (info.protection & (VM_PROT_READ|VM_PROT_WRITE|VM_PROT_EXECUTE))
            ==(VM_PROT_READ|VM_PROT_EXECUTE);
}
inline bool Inspect(uintptr_t base, State &state) {
    // Only call helpers whose full two-instruction body and RX mapping match.
    // All helpers are validated before any is invoked.
    for (const auto &query:kQueries) {
        if (!base || base>UINTPTR_MAX-query.offset-8) return false;
        uintptr_t address=base+query.offset;
        uint32_t words[2]={};
        if (!RegionRX(address,8) || !ReadMemory(address,words,8) || words[1]!=kRet
            || (words[0]!=ReturnValue(query.original) && words[0]!=ReturnValue(query.desktop))) return false;
    }
    for (size_t i=0;i<5;++i)
        state.values[i]=((uint32_t(*)())(base+kQueries[i].offset))();
    return true;
}
inline bool InspectUI(uintptr_t base,uint32_t &value) {
    const auto &query=kUIQueries[0];
    if (!base || base>UINTPTR_MAX-query.offset-8) return false;
    const uintptr_t address=base+query.offset;
    uint32_t words[2]={};
    if (!RegionRX(address,8) || !ReadMemory(address,words,8) || words[1]!=kRet
        || (words[0]!=ReturnValue(query.original) && words[0]!=ReturnValue(query.desktop))) return false;
    value=((uint32_t(*)())address)();
    return true;
}
struct Page {
    mach_vm_address_t address=0;
    mach_vm_size_t size=0;
    Page()=default;
    Page(const Page&)=delete;
    Page& operator=(const Page&)=delete;
    ~Page() { if (address) mach_vm_deallocate(mach_task_self(),address,size); }
    kern_return_t Prepare(const std::vector<uint8_t> &bytes) {
        size=bytes.size();
        kern_return_t status=mach_vm_allocate(mach_task_self(),&address,size,VM_FLAGS_ANYWHERE);
        if (status!=KERN_SUCCESS) { address=0; return status; }
        memcpy((void *)address,bytes.data(),size);
        sys_icache_invalidate((void *)address,size);
        // Never create a writable+executable mapping.
        status=mach_vm_protect(mach_task_self(),address,size,FALSE,VM_PROT_READ|VM_PROT_EXECUTE);
        if (status!=KERN_SUCCESS) return status;
        return mach_vm_protect(mach_task_self(),address,size,TRUE,VM_PROT_READ|VM_PROT_EXECUTE);
    }
};
inline kern_return_t Replace(uintptr_t target, const Page &source) {
    mach_vm_address_t address=target;
    vm_prot_t current=VM_PROT_NONE, maximum=VM_PROT_NONE;
    return mach_vm_remap(mach_task_self(), &address, source.size, 0,
        VM_FLAGS_FIXED|VM_FLAGS_OVERWRITE, mach_task_self(), source.address,
        TRUE, &current, &maximum, VM_INHERIT_COPY);
}
inline bool Matches(uintptr_t address, const std::vector<uint8_t> &expected) {
    std::vector<uint8_t> actual(expected.size());
    return RegionRX(address,expected.size()) && ReadMemory(address,actual.data(),actual.size())
        && actual==expected;
}
using Remapper=kern_return_t (*)(uintptr_t,const Page &);
template<size_t N> inline Result ApplyGroup(uintptr_t base,const Query (&queries)[N],Remapper remap=Replace) {
    Result result;
    const size_t pageSize=vm_page_size;
    result.pageSize=pageSize;
    result.stage="page-layout";
    if (!base || pageSize<4096 || pageSize>65536 || (pageSize&(pageSize-1))) {
        result.error=KERN_INVALID_ARGUMENT; return result;
    }
    const uintptr_t mask=pageSize-1;
    uintptr_t page=0;
    for (const auto &query:queries) {
        if (base>UINTPTR_MAX-query.offset-8) { result.error=KERN_INVALID_ADDRESS; return result; }
        uintptr_t address=base+query.offset, start=address&~mask;
        if ((address&3) || address+7>start+mask || (page && start!=page)) {
            result.error=KERN_INVALID_ARGUMENT; return result;
        }
        page=start;
    }
    result.stage="source-protection";
    if (!RegionRX(page,pageSize)) { result.error=KERN_PROTECTION_FAILURE; return result; }
    std::vector<uint8_t> original(pageSize);
    result.stage="source-read";
    if (!ReadMemory(page,original.data(),pageSize)) { result.error=KERN_INVALID_ADDRESS; return result; }
    std::vector<uint8_t> changed=original;
    result.stage="instruction-guard";
    for (const auto &query:queries) {
        size_t offset=base+query.offset-page;
        uint32_t words[2]={}; memcpy(words,original.data()+offset,8);
        if (words[0]!=ReturnValue(query.original) || words[1]!=kRet) {
            result.error=KERN_FAILURE; return result;
        }
        uint32_t replacement=ReturnValue(query.desktop);
        memcpy(changed.data()+offset,&replacement,4);
    }
    Page backup, replacement;
    result.stage="backup-rx";
    result.error=backup.Prepare(original);
    if (result.error!=KERN_SUCCESS) return result;
    result.stage="replacement-rx";
    result.error=replacement.Prepare(changed);
    if (result.error!=KERN_SUCCESS) return result;
    result.stage="source-changed";
    if (!Matches(page,original)) { result.error=KERN_FAILURE; return result; }
    result.stage="remap";
    result.error=remap(page,replacement);
    if (result.error==KERN_SUCCESS) sys_icache_invalidate((void *)page,pageSize);
    if (result.error==KERN_SUCCESS && Matches(page,changed)) {
        result.applied=true; result.stage="verified"; return result;
    }
    if (result.error==KERN_SUCCESS) { result.error=KERN_FAILURE; result.stage="post-remap-verification"; }
    // A prepared RX backup is available even if a remap failed after touching the target.
    if (!Matches(page,original)) {
        result.rollbackAttempted=true;
        result.rollbackError=remap(page,backup);
        if (result.rollbackError==KERN_SUCCESS) sys_icache_invalidate((void *)page,pageSize);
        result.rollbackSucceeded=result.rollbackError==KERN_SUCCESS && Matches(page,original);
    }
    return result;
}
inline Result Apply(uintptr_t base,Remapper remap=Replace) { return ApplyGroup(base,kQueries,remap); }
inline Result ApplyUI(uintptr_t base,Remapper remap=Replace) { return ApplyGroup(base,kUIQueries,remap); }
} // namespace MacPlatform

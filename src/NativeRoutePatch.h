#pragma once
#include <map>
#include <memory>
#include <algorithm>
// Entry hooks used solely to observe native input routing. Four instructions
// are displaced into file-backed, signed assembly; no dynamic trampoline/JIT.
namespace NativeRoutePatch {
struct Site { const char *name; uintptr_t offset; std::array<uint32_t,4> words; uintptr_t entry; };
struct Result { bool applied=false,rollbackAttempted=false,rollbackSucceeded=false; const char *stage="layout"; kern_return_t error=KERN_FAILURE; size_t pages=0; };
struct Prepared {
    uintptr_t address=0;
    std::vector<uint8_t> original,changed;
    MacPlatform::Page backup,replacement;
};
inline bool MakeEntry(uintptr_t entry,std::array<uint8_t,16> &out) {
    if (!entry || (entry&3)) return false;
    const uint32_t words[]={0x58000050,0xd61f0200}; // ldr x16,pc+8; br x16
    memcpy(out.data(),words,8); memcpy(out.data()+8,&entry,8); return true;
}
inline Result Apply(uintptr_t base,const Site *sites,size_t count,uintptr_t *resume,
                    MacPlatform::Remapper remap=MacPlatform::Replace) {
    Result result;
    const size_t pageSize=vm_page_size;
    if (!base || !sites || !count || count>32 || !resume || !remap || pageSize<4096
        || (pageSize&(pageSize-1))) return result;
    std::map<uintptr_t,std::unique_ptr<Prepared>> pages;
    // Validate the entire group before preparing or remapping any target page.
    for (size_t i=0;i<count;++i) {
        const Site &site=sites[i];
        if ((site.offset&3) || base>UINTPTR_MAX-site.offset-16) return result;
        const uintptr_t target=base+site.offset, page=target&~(pageSize-1);
        const size_t within=target-page;
        if (within>pageSize-16 || !MacPlatform::RegionRX(page,pageSize)) return result;
        for (size_t j=0;j<i;++j) {
            const uintptr_t other=base+sites[j].offset;
            if (target<other+16 && other<target+16) {result.stage="overlap";return result;}
        }
        std::array<uint8_t,16> branch{};
        if (!MakeEntry(site.entry,branch)) return result;
        auto &prepared=pages[page];
        if (!prepared) {
            prepared=std::make_unique<Prepared>(); prepared->address=page;
            prepared->original.resize(pageSize);
            if (!MacPlatform::ReadMemory(page,prepared->original.data(),pageSize)) {result.stage="read";return result;}
            prepared->changed=prepared->original;
        }
        if (memcmp(prepared->original.data()+within,site.words.data(),16)) {result.stage="signature";return result;}
        memcpy(prepared->changed.data()+within,branch.data(),16);
    }
    result.pages=pages.size();
    for (auto &kv:pages) {
        auto &page=*kv.second;
        result.stage="prepare-backup"; result.error=page.backup.Prepare(page.original);
        if (result.error!=KERN_SUCCESS) return result;
        result.stage="prepare-entry"; result.error=page.replacement.Prepare(page.changed);
        if (result.error!=KERN_SUCCESS) return result;
    }
    for (auto &kv:pages) {
        if (!MacPlatform::Matches(kv.first,kv.second->original)) {result.stage="changed-during-prepare";result.error=KERN_FAILURE;return result;}
    }
    // Publish all return addresses before the first hook can become callable.
    for (size_t i=0;i<count;++i) resume[i]=base+sites[i].offset+16;
    std::vector<Prepared *> attempted;
    result.stage="remap";
    for (auto &kv:pages) {
        auto &page=*kv.second; attempted.push_back(&page);
        result.error=remap(page.address,page.replacement);
        if (result.error==KERN_SUCCESS) sys_icache_invalidate((void *)page.address,pageSize);
        if (result.error!=KERN_SUCCESS || !MacPlatform::Matches(page.address,page.changed)) {
            if (result.error==KERN_SUCCESS) {result.error=KERN_FAILURE;result.stage="verify";}
            result.rollbackAttempted=true; result.rollbackSucceeded=true;
            for (auto it=attempted.rbegin();it!=attempted.rend();++it) {
                Prepared &previous=**it;
                if (MacPlatform::Matches(previous.address,previous.original)) continue;
                const auto status=remap(previous.address,previous.backup);
                if (status==KERN_SUCCESS) sys_icache_invalidate((void *)previous.address,pageSize);
                result.rollbackSucceeded &= status==KERN_SUCCESS && MacPlatform::Matches(previous.address,previous.original);
            }
            // Keep resume addresses valid even on an incomplete rollback.
            return result;
        }
    }
    result.applied=true; result.stage="verified";result.error=KERN_SUCCESS; return result;
}
}

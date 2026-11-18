#pragma once
#include "PartyUIRepairPolicy.h"
namespace PartyUI {
static bool repairEnabled=true,rebuildExisting=true;
struct State {uintptr_t originalMobile=0,desktop=0;bool aliased=false,attempted=false,failed=false;unsigned long lastLog=0;};
static std::unordered_map<uint64_t,State> states;
inline std::string Name(uintptr_t object) {
    std::string value;return ObjectMappingName(gBase+gGame.NamePool,object,value)?value:"<unreadable>";
}
inline bool ObjectClass(uintptr_t object,uintptr_t &cls,bool allowDefault=false) {
    uint32_t flags=0;
    return IsHeapPointer(object) && ReadValue(object+8,flags)
        && !(flags&(0x8000|0x10000)) && (allowDefault || !(flags&0x10))
        && ReadValue(object+0x10,cls) && IsHeapPointer(cls);
}
inline bool Widget(uintptr_t object,uintptr_t expected) {
    uintptr_t cls=0;return ObjectClass(object,cls) && ClassIsA(cls,expected);
}
inline bool ClassAsset(uintptr_t cls,uintptr_t slotBase) {
    uintptr_t meta=0;return ObjectClass(cls,meta,true) && ClassIsA(cls,slotBase);
}
inline bool OriginalCode(uintptr_t pointer) {
    if(pointer<gBase || pointer-gBase>=gImageSpan)return false;
    DynamicGame::Image file;
    if(!file.openFile(NSBundle.mainBundle.executablePath.fileSystemRepresentation) || !file.code(pointer-gBase))return false;
    std::array<uint8_t,32> expected{};auto off=file.file(pointer-gBase);
    for(unsigned i=0;i<32;++i)expected[i]=file.get<uint8_t>(off+i);
    return EqualBytes(pointer,expected.data(),expected.size());
}
struct Children {bool valid=false,allDesktop=false;int count=0;std::array<uintptr_t,4> objects{};};
inline Children Inspect(uintptr_t panel,uintptr_t panelBase,uintptr_t slotBase,uintptr_t desktop) {
    Children result;const auto &l=gPartyLayout;
    if(!Widget(panel,panelBase))return result;
    MappingArrayHeader header{};
    if(!ReadValue(panel+l.panelSlots,header) || header.count<0 || header.count>4
        || header.capacity<header.count || header.capacity>128)return result;
    if(header.count) {
        std::array<uintptr_t,4> slots{};
        if(!IsHeapPointer(header.data) || !Read(header.data,slots.data(),header.count*8))return result;
        for(int i=0;i<header.count;++i) {
            auto child=((uintptr_t(*)(uintptr_t,int))(gBase+l.childAt))(panel,i);
            if(!Widget(child,slotBase))return Children{};
            result.objects[i]=child;
        }
    }
    result.count=header.count;result.allDesktop=true;
    for(int i=0;i<result.count;++i)result.allDesktop &= Widget(result.objects[i],desktop);
    result.valid=true;return result;
}
inline void Describe(uint64_t identity,const char *phase,uintptr_t form,uintptr_t panel,
                     const Children &children,uintptr_t desktop,uintptr_t mobile,bool cdo) {
#if NTE_ENABLE_PARTY_LOGGING
    PartyNote("party_ui state id=%llu phase=%s default=%d form=%s desktop=%s mobile=%s panel_valid=%d children=%d all_desktop=%d",
        (unsigned long long)identity,phase,cdo,Name(form).c_str(),Name(desktop).c_str(),Name(mobile).c_str(),
        children.valid,children.count,children.allDesktop);
    if(!children.valid)return;
    auto &l=gPartyLayout;
    unsigned panelVisibility=((uint8_t(*)(uintptr_t))(gBase+l.visibility))(panel);
    float panelOpacity=((float(*)(uintptr_t))(gBase+l.opacity))(panel);
    PartyNote("party_ui panel id=%llu visibility=%u opacity=%.3f",(unsigned long long)identity,panelVisibility,panelOpacity);
    for(int i=0;i<children.count;++i) {
        uintptr_t cls=0;ReadValue(children.objects[i]+0x10,cls);
        unsigned visibility=((uint8_t(*)(uintptr_t))(gBase+l.visibility))(children.objects[i]);
        float opacity=((float(*)(uintptr_t))(gBase+l.opacity))(children.objects[i]);
        PartyNote("party_ui child id=%llu item=%d class=%s desktop=%d visibility=%u opacity=%.3f",
            (unsigned long long)identity,i+1,Name(cls).c_str(),Widget(children.objects[i],desktop),visibility,opacity);
    }
#endif
}
inline bool SignaturesMatch() {
    for(const auto &s:gPartyLayout.signatures)if(!EqualBytes(gBase+s.first,s.second.data(),s.second.size()))return false;
    return true;
}
inline void Process(uintptr_t form,int index,uint32_t serial,unsigned long tick,
                    uintptr_t mainBase,uintptr_t slotBase,uintptr_t panelBase) {
    const auto &l=gPartyLayout;if(!l.ready)return;
    uintptr_t cls=0;uint32_t flags=0;
    if(!ObjectClass(form,cls,true) || !ClassIsA(cls,mainBase) || !ReadValue(form+8,flags))return;
    bool cdo=flags&0x10;uint64_t identity=(uint64_t(serial)<<32)|(uint32_t)index;
    auto &state=states[identity];
#if NTE_ENABLE_PARTY_LOGGING
    bool report=!state.lastLog || tick-state.lastLog>=10;
#else
    constexpr bool report=false;
#endif
    uintptr_t desktop=0,mobile=0,panel=0;
    if(!ReadValue(form+l.pc,desktop) || !ReadValue(form+l.mobile,mobile))return;
    ReadValue(form+l.container,panel);
    if(!ClassAsset(desktop,slotBase) || !ClassAsset(mobile,slotBase)) {
        if(report){PartyNote("party_ui skip id=%llu default=%d reason=slot_class_unavailable pc=%s mobile=%s",
            (unsigned long long)identity,cdo,Name(desktop).c_str(),Name(mobile).c_str());state.lastLog=tick;}
        return;
    }
    Children children=cdo?Children{}:Inspect(panel,panelBase,slotBase,desktop);
    if(report){Describe(identity,"before",form,panel,children,desktop,mobile,cdo);state.lastLog=tick;}
    if(!repairEnabled || gObserveOnly || state.failed)return;
    if(!state.aliased) {
        state.originalMobile=mobile;state.desktop=desktop;
        // Keep this correction local to the main-form defaults/instance. No
        // UClass metadata, global platform flag, asset or saved setting changes.
        if(mobile!=desktop)memcpy((void*)(form+l.mobile),&desktop,8);
        state.aliased=true;
        PartyNote("party_ui alias id=%llu default=%d changed=%d",(unsigned long long)identity,cdo,mobile!=desktop);
    }
    if(cdo || !children.valid || !children.count || children.allDesktop || state.attempted || !rebuildExisting)return;
    // Only rebuild an existing list when an original mobile class is available
    // for rollback, all children are recognized, and the native ABI is intact.
    if(state.originalMobile==desktop || !ClassAsset(state.originalMobile,slotBase) || !SignaturesMatch())return;
    uintptr_t table=0,clear=0;
    if(!ReadValue(panel,table) || !ReadValue(table+l.clearVirtual,clear) || !OriginalCode(clear)) {
        PartyNote("party_ui skip id=%llu reason=native_clear_guard",(unsigned long long)identity);return;
    }
    state.attempted=true;
    auto inspect=[&] {auto x=Inspect(panel,panelBase,slotBase,desktop);return RebuildCheck{x.valid,x.allDesktop,x.count};};
    auto result=Rebuild(children.count,
        [&]{((void(*)(uintptr_t))clear)(panel);},
        [&]{((void(*)(uintptr_t,uint32_t))(gBase+l.refresh))(form,1);},
        inspect,[&]{memcpy((void*)(form+l.mobile),&state.originalMobile,8);});
    state.failed=!result.success;
    PartyNote("party_ui rebuild id=%llu success=%d before=%d after=%d rollback=%d restored=%d",
        (unsigned long long)identity,result.success,children.count,result.after,result.rolledBack,result.restored);
#if NTE_ENABLE_PARTY_LOGGING
    Describe(identity,"after",form,panel,Inspect(panel,panelBase,slotBase,desktop),desktop,
        result.success?desktop:state.originalMobile,false);
#endif
}
inline void Configure(NSDictionary *config) {
    if(config[@"RepairPartyDesktopUI"])repairEnabled=[config[@"RepairPartyDesktopUI"] boolValue];
    if(config[@"PartyUIRebuildExisting"])rebuildExisting=[config[@"PartyUIRebuildExisting"] boolValue];
}
} // namespace PartyUI

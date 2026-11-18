#pragma once
#include <array>
#include <cstddef>
#include <cstdint>

// Layout verified against the supported game's actual FIOSCursor constructor and
// complete vtable. The setters preserve gameplay decisions; GetPosition supplies
// the absolute pointer sample missing from the iOS mouse backend.
namespace NativeCursor {
// Populated from the live executable's verified cursor operations.
inline uintptr_t kCursorVTable=0;
inline size_t kGetPositionSlot=0,kSetTypeSlot=0,kShowSlot=0;
inline size_t kTypeField=0,kShownField=0;
constexpr size_t kSlots=13,kHeaderWords=2;
inline std::array<uintptr_t,kSlots> kFunctions{};
using Table=std::array<uintptr_t,kSlots+kHeaderWords>;
constexpr uint32_t kShown=1u<<8, kShowObserved=1u<<9, kReady=1u<<10;
constexpr bool ValidType(uint32_t type) { return type<=14; }
constexpr uint32_t Type(uint32_t state) { return state&0xff; }
constexpr bool Ready(uint32_t state) { return state&kReady; }
constexpr bool Shown(uint32_t state) { return state&kShown; }
constexpr bool ShowObserved(uint32_t state) { return state&kShowObserved; }
constexpr uint32_t InitialState(uint32_t type,bool shown) {
    // FIOSCursor initializes Show=false without issuing an actual hide request.
    // Until Show is invoked, the cursor type is the only meaningful native signal.
    return ValidType(type) ? kReady|type|(shown?kShown:0) : 0;
}
constexpr uint32_t WithType(uint32_t state,uint32_t type) {
    return Ready(state) && ValidType(type) ? (state&~0xffu)|type : state;
}
constexpr uint32_t WithShow(uint32_t state,bool show) {
    return Ready(state) ? (state&~kShown)|kShowObserved|(show?kShown:0) : state;
}
constexpr bool WantsLock(uint32_t state) {
    // No verified native state means preserve the game's original YES preference.
    if (!Ready(state)) return true;
    const bool visible=Type(state)!=0 && (!ShowObserved(state)||Shown(state));
    return !visible;
}
inline bool BuildTable(const Table &original,const std::array<uintptr_t,kSlots> &expected,
                       uintptr_t setType,uintptr_t show,Table &result,uintptr_t getPosition=0) {
    // Both Itanium prefix words are zero in this build. Preserve the entire table,
    // including both destructors and all ABI slots. Optional absolute-position
    // callback is used by the platform adapter; the original getter remains its fallback.
    if (original[0]||original[1]||!setType||!show || kSetTypeSlot>=kSlots || kShowSlot>=kSlots || kGetPositionSlot>=kSlots || kSetTypeSlot==kShowSlot || kGetPositionSlot==kSetTypeSlot || kGetPositionSlot==kShowSlot) return false;
    for (size_t i=0;i<kSlots;++i) if (!expected[i]||original[i+kHeaderWords]!=expected[i]) return false;
    Table replacement=original;
    replacement[kHeaderWords+kSetTypeSlot]=setType;
    replacement[kHeaderWords+kShowSlot]=show;
    if (getPosition) replacement[kHeaderWords+kGetPositionSlot]=getPosition;
    result=replacement;
    return true;
}
} // namespace NativeCursor

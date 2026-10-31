#pragma once
#include <array>
#include <cstddef>
#include <cstdint>

// Layout verified against the supported game's actual FIOSCursor constructor and
// complete vtable. The setters preserve gameplay decisions; GetPosition supplies
// the absolute pointer sample missing from the iOS mouse backend.
namespace NativeCursor {
constexpr uintptr_t kApplicationVTable=0xd330d78;
constexpr uintptr_t kCursorVTable=0xd3310c8;
constexpr uintptr_t kApplicationGetter=0x1569190;
constexpr size_t kSlots=13, kHeaderWords=2;
constexpr size_t kGetPositionSlot=0x28/8;
constexpr size_t kSetTypeSlot=0x38/8, kShowSlot=0x50/8;
constexpr std::array<uintptr_t,kSlots> kFunctions={
    0x15780e0,0x15780e4,0x1577f68,0x1577f70,0x1577f78,0x15780e8,
    0x1571ac8,0x1571b28,0x15780f0,0x1571b30,0x1571b40,0x1571b48,0x15780f8
};
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
    if (original[0]||original[1]||!setType||!show) return false;
    for (size_t i=0;i<kSlots;++i) if (!expected[i]||original[i+kHeaderWords]!=expected[i]) return false;
    Table replacement=original;
    replacement[kHeaderWords+kSetTypeSlot]=setType;
    replacement[kHeaderWords+kShowSlot]=show;
    if (getPosition) replacement[kHeaderWords+kGetPositionSlot]=getPosition;
    result=replacement;
    return true;
}
} // namespace NativeCursor

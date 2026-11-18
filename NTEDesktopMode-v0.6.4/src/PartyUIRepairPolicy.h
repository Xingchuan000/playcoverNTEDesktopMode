#pragma once
namespace PartyUI {
struct RebuildCheck {bool valid=false,desktop=false;int count=0;};
struct RebuildResult {bool success=false,rolledBack=false,restored=false;int after=0;};
// Real engine operations are injected so the transaction and rollback order
// can be exercised independently without running a game or synthetic input.
template<class Clear,class Refresh,class Inspect,class Restore>
RebuildResult Rebuild(int before,Clear clear,Refresh refresh,Inspect inspect,Restore restore) {
    RebuildResult result;
    clear();auto empty=inspect();
    if(!empty.valid || empty.count!=0) {
        restore();result.rolledBack=true;
        if(empty.valid && empty.count>=before)result.restored=true;
        else if(empty.valid) {
            refresh();auto restored=inspect();result.restored=restored.valid && restored.count>=before;
        }
        return result;
    }
    refresh();auto after=inspect();result.after=after.count;
    if(after.valid && after.desktop && after.count>=before && after.count>0 && after.count<=4) {
        result.success=true;return result;
    }
    restore();result.rolledBack=true;
    clear();auto cleared=inspect();
    if(cleared.valid && cleared.count==0) {
        refresh();auto restored=inspect();result.restored=restored.valid && restored.count>=before;
    }
    return result;
}
} // namespace PartyUI

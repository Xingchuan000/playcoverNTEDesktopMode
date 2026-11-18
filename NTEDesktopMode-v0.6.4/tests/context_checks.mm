// Context filtering decisions, sparse allocation boundaries and guarded value replacement.
// Runs in an unrelated host; no game launch, input injection or installed file edits.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
static int checks=0;
static void Check(bool ok,const char *label) {
    ++checks;
    if (!ok) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
int main() { SetupFixtureLayout();
    @autoreleasepool {
        alignas(8) unsigned char map[0x50]={};
        alignas(8) unsigned char data[24*130]={};
        auto set32=[&](unsigned off,int32_t value) { memcpy(map+off,&value,4); };
        auto set64=[&](unsigned off,uintptr_t value) { memcpy(map+off,&value,8); };
        std::vector<ContextMapRow> rows;
        Check(SnapshotContextMap((uintptr_t)map,rows) && rows.empty(),"empty map");
        set64(0,(uintptr_t)data); set32(8,3); set32(12,130); set32(0x28,3); set32(0x2c,128);
        set32(0x10,5); set32(0x34,1); // slots 0 and 2 live, slot 1 free
        uintptr_t keyA=(uintptr_t)data+8,keyB=(uintptr_t)data+16,valueA=0x100000008ULL;
        memcpy(data,&keyA,8); memcpy(data+8,&valueA,8); memcpy(data+48,&keyB,8);
        memset(data+24,0xff,24);
        Check(SnapshotContextMap((uintptr_t)map,rows) && rows.size()==2,"free slot excluded");
        Check(rows[0].key==keyA && rows[0].value==valueA && rows[1].key==keyB,"keys values and stride");
        Check(rows[1].address==(uintptr_t)data+48,"patch address tracks allocated slot");
        set32(0x34,0); Check(!SnapshotContextMap((uintptr_t)map,rows) && rows.empty(),"allocation count mismatch rejected");
        set32(0x34,1); set32(0x28,4); Check(!SnapshotContextMap((uintptr_t)map,rows),"bit count mismatch rejected");
        set32(0x28,3); set32(0x2c,2); Check(!SnapshotContextMap((uintptr_t)map,rows),"insufficient bit capacity");
        set32(0x2c,128); set32(12,2); Check(!SnapshotContextMap((uintptr_t)map,rows),"insufficient data capacity");
        set32(12,130); set32(8,-1); Check(!SnapshotContextMap((uintptr_t)map,rows),"negative slot count");
        set32(8,4097); Check(!SnapshotContextMap((uintptr_t)map,rows),"excessive slot count");
        set32(8,3); set32(0x34,4); Check(!SnapshotContextMap((uintptr_t)map,rows),"excess free count");
        set32(0x34,1); set64(0,0x100000000ULL); Check(!SnapshotContextMap((uintptr_t)map,rows),"unmapped entries");
        set64(0,(uintptr_t)data); set64(0x20,0x100000000ULL); Check(!SnapshotContextMap((uintptr_t)map,rows),"unmapped external bits");
        set64(0x20,0); set32(8,130); set32(0x28,130); set32(0x2c,160); set32(0x34,129);
        Check(!SnapshotContextMap((uintptr_t)map,rows),"overflowing inline bitmap");
        alignas(8) uint32_t external[5]={0,0,0,0,2}; set64(0x20,(uintptr_t)external);
        memcpy(data+129*24,&keyB,8);
        Check(SnapshotContextMap((uintptr_t)map,rows) && rows.size()==1 && rows[0].key==keyB,"external bitmap slot 129");
        Check(!SnapshotContextMap(0,rows),"missing map");
        BindingCoverage source,target,active;
        source.decoded=target.decoded=active.decoded=true; source.mask=0x3f;
        target.pairs={{"Touch1","IA_Touch"},{"Escape","IA_Esc"},{"T","IA_VehicleAutopilot"},{"LeftMouseButton","IA_Touch"}};
        active.pairs=target.pairs;
        Check(IsKeyboardRedirectCandidate(source,target,active,true),"observed registered desktop to mobile redirect qualifies");
        Check(!IsKeyboardRedirectCandidate(source,target,active,false),"unregistered source never qualifies");
        auto changed=source; changed.mask=0x1f;
        Check(!IsKeyboardRedirectCandidate(changed,target,active,true),"incomplete desktop source rejected");
        changed=target; changed.mask=0x10;
        Check(!IsKeyboardRedirectCandidate(source,changed,active,true),"destination already contains camera axis");
        changed=active; changed.mask=1;
        Check(!IsKeyboardRedirectCandidate(source,target,changed,true),"active movement already present");
        changed=target; changed.decoded=false;
        Check(!IsKeyboardRedirectCandidate(source,changed,active,true),"undecodable destination rejected");
        changed=source; changed.decoded=false;
        Check(!IsKeyboardRedirectCandidate(changed,target,active,true),"undecodable source rejected");
        changed=active; changed.decoded=false;
        Check(!IsKeyboardRedirectCandidate(source,target,changed,true),"undecodable active map rejected");
        changed=active; changed.pairs.erase(changed.pairs.begin());
        Check(!IsKeyboardRedirectCandidate(source,target,changed,true),"destination not fully represented in active map");
        changed=target; changed.pairs.clear();
        Check(!IsKeyboardRedirectCandidate(source,changed,active,true),"empty destination rejected");
        alignas(8) uintptr_t entry[3]={keyA,valueA,0x1122334455667788ULL};
        ContextMapRow row={(uintptr_t)entry,keyA,valueA};
        Check(!ReplaceRedirectDestination(row,keyB),"source mismatch never written");
        Check(ReplaceRedirectDestination(row,keyA) && entry[0]==keyA && entry[1]==keyA
            && entry[2]==0x1122334455667788ULL,"only destination changed; hash bytes preserved");
        Check(!ReplaceRedirectDestination(row,keyA),"stale destination rejected");
        row.value=keyA; Check(!ReplaceRedirectDestination(row,keyA),"self redirect not rewritten");
        row.key=keyB; row.value=valueA;
        Check(!ReplaceRedirectDestination(row,keyB),"stale key rejected");
        Check(!ObjectOfClassIncludingDefault(0,0),"missing object and class rejected");
        printf("PASS: %d context map and redirect cases\n",checks);
    }
}

// Synthetic FName pool, asset names and TArray snapshots. No game launch or input.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
static int checks=0;
static void Check(bool ok,const char *label) {
    ++checks;
    if (!ok) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
int main() { SetupFixtureLayout();
    @autoreleasepool {
        alignas(8) unsigned char block[512]={};
        alignas(8) uintptr_t table[2]={(uintptr_t)block,0};
        auto store=[&](unsigned offset,const char *text,bool wide) {
            unsigned length=(unsigned)strlen(text);
            uint16_t header=(length<<6)|(wide?1:0);
            memcpy(block+offset,&header,2);
            for (unsigned i=0;i<length;++i) {
                if (wide) { uint16_t ch=text[i]; memcpy(block+offset+2+i*2,&ch,2); }
                else block[offset+2+i]=text[i];
            }
        };
        store(0,"W",false);
        store(32,"IA_MoveForward",false);
        store(96,"MouseX",true);
        std::string out;
        Check(DecodeMappingName((uintptr_t)table,{0,0},out) && out=="W","ANSI key decoded");
        Check(DecodeMappingName((uintptr_t)table,{16,0},out) && out=="IA_MoveForward","action asset decoded");
        Check(DecodeMappingName((uintptr_t)table,{48,0},out) && out=="MouseX","UTF16 ASCII key decoded");
        Check(DecodeMappingName((uintptr_t)table,{16,2},out) && out=="IA_MoveForward_1","number suffix uses number minus one");
        Check(!DecodeMappingName((uintptr_t)table,{0x10000,0},out) && out.empty(),"null name block rejected");
        Check(!DecodeMappingName(0,{0,0},out),"null table rejected");
        Check(!DecodeMappingName(0x100000000ULL,{0,0},out),"unmapped table rejected");
        Check(!DecodeMappingName((uintptr_t)table,{128,0},out),"empty entry rejected");
        uint16_t oversized=129<<6; memcpy(block+256,&oversized,2);
        Check(!DecodeMappingName((uintptr_t)table,{128,0},out),"oversized name rejected before payload read");
        store(160,"bad\nname",false);
        Check(!DecodeMappingName((uintptr_t)table,{80,0},out) && out.empty(),"multiline name rejected");
        store(192,"A",true); uint16_t nonASCII=0x4e2d; memcpy(block+194,&nonASCII,2);
        Check(!DecodeMappingName((uintptr_t)table,{96,0},out),"nonASCII name omitted safely");
        alignas(8) unsigned char object[0x20]={}; MappingName objectName={16,0};
        memcpy(object+0x18,&objectName,sizeof(objectName));
        Check(ObjectMappingName((uintptr_t)table,(uintptr_t)object,out) && out=="IA_MoveForward","UObject name offset decoded");
        Check(!ObjectMappingName((uintptr_t)table,0,out),"missing action object rejected");
        std::vector<MappingRow> rows;
        MappingArrayHeader header={0,0,0};
        Check(SnapshotMappings((uintptr_t)&header,rows) && rows.empty(),"empty array accepted");
        alignas(8) MappingRow authored[2]={};
        memcpy(authored[0].data()+0x20,&table[0],8);
        memcpy(authored[0].data()+0x28,&objectName,8);
        header={(uintptr_t)authored,2,2};
        Check(SnapshotMappings((uintptr_t)&header,rows) && rows.size()==2
            && !memcmp(rows[0].data(),authored[0].data(),0x50),"mapping stride and snapshot preserved");
        header.count=-1; Check(!SnapshotMappings((uintptr_t)&header,rows) && rows.empty(),"negative count rejected and previous data cleared");
        header.count=4097; header.capacity=4097; Check(!SnapshotMappings((uintptr_t)&header,rows),"excessive count rejected");
        header.count=2; header.capacity=1; Check(!SnapshotMappings((uintptr_t)&header,rows),"count greater than capacity rejected");
        header={0,2,2}; Check(!SnapshotMappings((uintptr_t)&header,rows),"nonempty array without storage rejected");
        header={0x100000000ULL,2,2}; Check(!SnapshotMappings((uintptr_t)&header,rows),"unmapped array storage rejected");
        Check(!SnapshotMappings(0,rows),"missing TArray header rejected");
        printf("PASS: %d mapping decoder and snapshot cases\n",checks);
    }
}

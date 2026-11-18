// Synthetic profile assets and sparse maps. No installed game writes or launch.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
#include <sys/mman.h>
static int checks=0;
static void Check(bool ok,const char *label) {
    ++checks; if (!ok) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
struct ProfileString {
    std::vector<uint16_t> text; MappingArrayHeader value;
    ProfileString(const char *id):text(id,id+strlen(id)) {
        text.push_back(0); value={(uintptr_t)text.data(),(int32_t)text.size(),(int32_t)text.size()};
    }
};
int main() { SetupFixtureLayout();
    @autoreleasepool {
        ProfileString keyboard("Input.MouseAndKeyboard"),touch("Input.Touch"),fr("Input.MouseAndKeyboard.Fr");
        std::string id;
        Check(ReadProfileId((uintptr_t)&keyboard.value,id) && id=="Input.MouseAndKeyboard","UTF16 string with terminal NUL");
        auto invalid=keyboard.value; invalid.count=-1;
        Check(!ReadProfileId((uintptr_t)&invalid,id),"negative string count");
        invalid.count=257; invalid.capacity=257;
        Check(!ReadProfileId((uintptr_t)&invalid,id),"string size bound");
        invalid=keyboard.value; invalid.capacity=invalid.count-1;
        Check(!ReadProfileId((uintptr_t)&invalid,id),"string count greater than capacity");
        invalid={0,0,0}; Check(ReadProfileId((uintptr_t)&invalid,id) && id.empty(),"empty FString without allocation");
        invalid={0x100000000ULL,4,4}; Check(!ReadProfileId((uintptr_t)&invalid,id),"unreadable UTF16 storage");
        ProfileString malformed("Input.Touch"); malformed.text.back()=1;
        Check(!ReadProfileId((uintptr_t)&malformed.value,id),"missing string terminator");
        malformed.text.back()=0; malformed.text[1]=0;
        Check(!ReadProfileId((uintptr_t)&malformed.value,id) && id.empty(),"embedded NUL rejected without partial identifier");
        malformed.text[1]=0x4e2d;
        Check(!ReadProfileId((uintptr_t)&malformed.value,id),"nonASCII identifier omitted");
        Check(!ReadProfileId(0,id),"missing string header");
        Check(ProfileIdsEqual("Input.MouseAndKeyboard","input.mouseandkeyboard"),"native ASCII case folding");
        Check(!ProfileIdsEqual("Input.MouseAndKeyboard","Input.MouseAndKeyboard.Fr"),"distinct keyboard layouts");
        Check(ProfileAllows({},"Input.Touch",true),"unrestricted binding");
        Check(ProfileAllows({"Input.MouseAndKeyboard"},"Input.Touch",false),"engine skips supported-profile filter without profile object");
        Check(!ProfileAllows({"Input.MouseAndKeyboard"},"Input.Touch",true),"keyboard restriction blocks mobile profile");
        Check(ProfileAllows({"Input.MouseAndKeyboard.Fr","Input.MouseAndKeyboard"},"input.mouseandkeyboard",true),"any supported identifier can match");
        alignas(8) unsigned char binding[0x88]={},bindingClass[0x40]={},profileClass[0x40]={};
        uintptr_t bindingType=(uintptr_t)bindingClass,profileType=(uintptr_t)profileClass;
        memcpy(binding+0x10,&bindingType,8);
        MappingArrayHeader supported[2]={keyboard.value,fr.value};
        MappingArrayHeader list={(uintptr_t)supported,2,2}; memcpy(binding+0x78,&list,16);
        std::vector<std::string> ids;
        Check(ReadSupportedProfiles((uintptr_t)binding,ids) && ids.size()==2 && ids[1]=="Input.MouseAndKeyboard.Fr","FString list stride");
        list.count=33; list.capacity=33; memcpy(binding+0x78,&list,16);
        Check(!ReadSupportedProfiles((uintptr_t)binding,ids) && ids.empty(),"too many supported profiles rejected");
        list={(uintptr_t)supported,2,2}; memcpy(binding+0x78,&list,16);
        auto saved=supported[1]; supported[1].data=0x100000000ULL;
        Check(!ReadSupportedProfiles((uintptr_t)binding,ids) && ids.empty(),"partial list never used"); supported[1]=saved;
        alignas(8) unsigned char map[0x50]={},entries[3*32]={},profileA[0x40]={},profileB[0x40]={};
        memcpy(profileA+0x10,&profileType,8); memcpy(profileB+0x10,&profileType,8);
        memcpy(profileA+0x30,&keyboard.value,16); memcpy(profileB+0x30,&touch.value,16);
        uintptr_t a=(uintptr_t)profileA,b=(uintptr_t)profileB,data=(uintptr_t)entries;
        memcpy(entries,&keyboard.value,16); memcpy(entries+16,&a,8);
        memset(entries+32,0xff,32); // free-list slot must never be read as a profile
        memcpy(entries+64,&touch.value,16); memcpy(entries+80,&b,8);
        auto set32=[&](unsigned at,int32_t v){memcpy(map+at,&v,4);};
        auto set64=[&](unsigned at,uint64_t v){memcpy(map+at,&v,8);};
        set64(0,data); set32(8,3); set32(12,3); set32(0x10,5);
        set32(0x28,3); set32(0x2c,128); set32(0x34,1);
        std::vector<KeyProfileRow> profiles;
        Check(SnapshotKeyProfiles((uintptr_t)map,profiles,profileType) && profiles.size()==2
            && profiles[1].id=="Input.Touch" && profiles[0].profile==a,"32-byte profile entries skip free-list slot");
        memcpy(profileB+0x30,&keyboard.value,16);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType) && profiles.empty(),"profile object must match map identifier");
        memcpy(profileB+0x30,&touch.value,16);
        uint32_t flags=0x10; memcpy(profileB+8,&flags,4);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"profile CDO rejected");
        flags=0x8000; memcpy(profileB+8,&flags,4);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"destroying profile rejected");
        flags=0; memcpy(profileB+8,&flags,4);
        memcpy(entries+64,&keyboard.value,16); memcpy(profileB+0x30,&keyboard.value,16);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"duplicate identifiers rejected");
        memcpy(entries+64,&touch.value,16); memcpy(profileB+0x30,&touch.value,16);
        set32(0x34,0); Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"allocation bitmap count mismatch");
        set32(0x34,1); set32(8,129); set32(12,129); set32(0x28,129);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"profile map entry bound");
        set32(8,3); set32(12,3); set32(0x28,3); set64(0,0x100000000ULL);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"unreadable profile storage rejected");
        set64(0,data); alignas(8) uint32_t bits=5; set64(0x20,(uintptr_t)&bits);
        Check(SnapshotKeyProfiles((uintptr_t)map,profiles,profileType) && profiles.size()==2,"external profile allocation bitmap");
        set64(0x20,0x100000000ULL);
        Check(!SnapshotKeyProfiles((uintptr_t)map,profiles,profileType),"unreadable allocation bitmap");
        Check(!SnapshotKeyProfiles(0,profiles,profileType),"missing profile map");
        std::vector<ProfileBindingGate> gates;
        for (unsigned i=0;i<6;++i) gates.push_back({1u<<i,"","",{"Input.MouseAndKeyboard"}});
        Check(ProfileAllowedMask(gates,"Input.Touch",true)==0 && ProfileAllowedMask(gates,"Input.MouseAndKeyboard",true)==0x3f,"six excluded keyboard axes become eligible together");
        BindingCoverage source,active; source.decoded=active.decoded=true; source.mask=0x3f;
        Check(IsKeyboardProfileCandidate(source,active,true,18,true,0,0x3f),"observed mismatch meets activation conditions");
        Check(!IsKeyboardProfileCandidate(source,active,false,18,true,0,0x3f),"unregistered context rejected");
        Check(!IsKeyboardProfileCandidate(source,active,true,0,true,0,0x3f),"initial empty input not repaired");
        Check(!IsKeyboardProfileCandidate(source,active,true,18,false,0,0x3f),"missing active profile cannot cause this filter");
        Check(!IsKeyboardProfileCandidate(source,active,true,18,true,1,0x3f),"current profile already permits movement");
        Check(!IsKeyboardProfileCandidate(source,active,true,18,true,0,0x1f),"target lacks a required axis");
        active.mask=1; Check(!IsKeyboardProfileCandidate(source,active,true,18,true,0,0x3f),"active movement already exists"); active.mask=0;
        active.decoded=false; Check(!IsKeyboardProfileCandidate(source,active,true,18,true,0,0x3f),"incomplete active decoding"); active.decoded=true;
        source.decoded=false; Check(!IsKeyboardProfileCandidate(source,active,true,18,true,0,0x3f),"incomplete source decoding"); source.decoded=true;
        source.mask=0x1f; Check(!IsKeyboardProfileCandidate(source,active,true,18,true,0,0x3f),"incomplete source axes");
        const size_t regionSize=0x10100000;
        auto *region=(unsigned char *)mmap(nullptr,regionSize,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
        Check(region!=MAP_FAILED,"allocate sparse synthetic engine globals"); gBase=(uintptr_t)region;
        alignas(8) unsigned char nameBlock[2048]={},actions[3][0x78]={};
        uintptr_t namePointer=(uintptr_t)nameBlock; memcpy(region+0xfd2abd0,&namePointer,8);
        auto store=[&](unsigned offset,const char *text){uint16_t len=(uint16_t)(strlen(text)<<6); memcpy(nameBlock+offset,&len,2); memcpy(nameBlock+offset+2,text,strlen(text));};
        const char *keys[]={"W","A","S","D","MouseX","MouseY"};
        const char *actionNames[]={"IA_Move","IA_Turn","IA_LookUp"};
        for (unsigned i=0;i<6;++i) store(i*32,keys[i]);
        for (unsigned i=0;i<3;++i) {
            store(256+i*64,actionNames[i]); MappingName name={(256+i*64)/2,0};
            memcpy(actions[i]+0x18,&name,8); uintptr_t p=(uintptr_t)binding; memcpy(actions[i]+0x70,&p,8);
        }
        std::vector<MappingRow> authored(6);
        for (unsigned i=0;i<6;++i) {
            MappingName name={i*16,0}; uintptr_t action=(uintptr_t)actions[i<4?0:i-3];
            memcpy(authored[i].data()+0x20,&action,8); memcpy(authored[i].data()+0x28,&name,8);
        }
        Check(InspectProfileGates(authored,bindingType,gates) && gates.size()==6
            && ProfileAllowedMask(gates,"Input.Touch",true)==0,"inherited action key settings restrict actual six pairs");
        authored[0][0x41]=2;
        Check(InspectProfileGates(authored,bindingType,gates) && ProfileAllowedMask(gates,"Input.Touch",true)==1,"ignore behavior bypasses action restrictions");
        authored[0][0x41]=1; uintptr_t p=(uintptr_t)binding; memcpy(authored[0].data()+0x48,&p,8);
        Check(InspectProfileGates(authored,bindingType,gates) && ProfileAllowedMask(gates,"Input.Touch",true)==0,"mapping override settings used");
        p=0; memcpy(authored[0].data()+0x48,&p,8);
        Check(InspectProfileGates(authored,bindingType,gates) && ProfileAllowedMask(gates,"Input.Touch",true)==1,"null override is unrestricted");
        authored[0][0x41]=3; Check(!InspectProfileGates(authored,bindingType,gates),"unknown setting behavior rejected");
        authored[0][0x41]=0; flags=0x10; memcpy(binding+8,&flags,4);
        Check(InspectProfileGates(authored,bindingType,gates),"binding settings can be class defaults");
        flags=0x10000; memcpy(binding+8,&flags,4);
        Check(!InspectProfileGates(authored,bindingType,gates),"destroyed binding settings rejected");
        flags=0; memcpy(binding+8,&flags,4); authored.pop_back();
        Check(!InspectProfileGates(authored,bindingType,gates),"requires all six specific key and action pairs");
        // Exercise serial identity lookup against an allocated object array slot.
        alignas(8) unsigned char item[24]={}; alignas(8) uintptr_t chunks[1]={(uintptr_t)item};
        uintptr_t chunksPointer=(uintptr_t)chunks; memcpy(region+0x100236b0,&chunksPointer,8);
        int32_t count=1; memcpy(region+0x100236c4,&count,4); memcpy(region+0x100236cc,&count,4);
        p=(uintptr_t)binding; memcpy(item,&p,8); uint32_t serial=19,readSerial=0; memcpy(item+0x10,&serial,4);
        Check(ObjectSerial(0,p,readSerial) && readSerial==19,"serial identity from matching live object slot");
        Check(!ObjectSerial(1,p,readSerial),"object index outside table");
        Check(!ObjectSerial(0,p+8,readSerial),"reused slot pointer mismatch");
        flags=0x30000000; memcpy(item+8,&flags,4);
        Check(!ObjectSerial(0,p,readSerial),"unreachable array item rejected");
        flags=0; memcpy(item+8,&flags,4); serial=0; memcpy(item+0x10,&serial,4);
        Check(!ObjectSerial(0,p,readSerial),"zero serial rejected");
        alignas(8) unsigned char subsystem[0x38]={},settings[8]={},interfaceTable[0x28]={},vtable[0x368]={};
        auto slot=[&](unsigned at,uintptr_t value){memcpy(vtable+at,&value,8);};
        p=(uintptr_t)interfaceTable; memcpy(subsystem+0x30,&p,8);
        p=gBase+0x4c327ac; memcpy(interfaceTable+0x20,&p,8);
        p=(uintptr_t)vtable; memcpy(settings,&p,8);
        slot(0x348,gBase+0x4c46f08); slot(0x360,gBase+0x4c47870); slot(0x338,gBase+0x4c46b34);
        uintptr_t lookup=0,setter=0;
        Check(NativeProfileMethods((uintptr_t)subsystem,(uintptr_t)settings,lookup,setter)
            && lookup==gBase+0x4c47870 && setter==gBase+0x4c46b34,"all native ABI slots must match");
        p=0; memcpy(interfaceTable+0x20,&p,8);
        Check(!NativeProfileMethods((uintptr_t)subsystem,(uintptr_t)settings,lookup,setter),"overridden subsystem user settings getter rejected");
        p=gBase+0x4c327ac; memcpy(interfaceTable+0x20,&p,8);
        slot(0x348,0); Check(!NativeProfileMethods((uintptr_t)subsystem,(uintptr_t)settings,lookup,setter),"overridden active identifier getter rejected"); slot(0x348,gBase+0x4c46f08);
        slot(0x360,0); Check(!NativeProfileMethods((uintptr_t)subsystem,(uintptr_t)settings,lookup,setter),"overridden profile lookup rejected"); slot(0x360,gBase+0x4c47870);
        slot(0x338,0); Check(!NativeProfileMethods((uintptr_t)subsystem,(uintptr_t)settings,lookup,setter),"overridden activation method rejected");
        munmap(region,regionSize); gBase=0;
        printf("PASS: %d key profile decoding, filtering and activation eligibility cases\n",checks);
    }
}

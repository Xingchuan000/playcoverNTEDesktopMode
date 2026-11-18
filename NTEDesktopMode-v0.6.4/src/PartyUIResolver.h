#pragma once
#include "DynamicGame.h"

namespace PartyUI {
struct Layout {
    bool ready=false;
    uint64_t mainCache=0,slotCache=0,panelCache=0;
    uint16_t pc=0,mobile=0,container=0,currentSlot=0,panelSlots=0,clearVirtual=0;
    uint64_t refresh=0,childAt=0,childrenCount=0,visibility=0,opacity=0;
    std::vector<std::pair<uint64_t,std::array<uint8_t,32>>> signatures;
};
inline std::vector<uint64_t> FunctionStarts(const DynamicGame::Image &im) {
    std::vector<uint64_t> out;
    uint64_t p=32;
    for(unsigned i=0;i<im.get<mach_header_64>(0).ncmds;++i) {
        auto cmd=im.get<load_command>(p);
        if(cmd.cmd==LC_FUNCTION_STARTS) {
            auto data=im.get<linkedit_data_command>(p);
            if(!im.range(data.dataoff,data.datasize))return {};
            uint64_t at=data.dataoff,end=at+data.datasize,address=0;
            while(at<end) {
                uint64_t delta=0;unsigned shift=0;uint8_t byte=0;
                do {
                    if(at>=end || shift>=63)return {};
                    byte=im.get<uint8_t>(at++);delta|=uint64_t(byte&127)<<shift;shift+=7;
                }while(byte&128);
                if(!delta)break;
                if(address>UINT64_MAX-delta)return {};
                address+=delta;out.push_back(address);
            }
        }
        p+=cmd.cmdsize;
    }
    return out;
}
inline uint64_t NativeReturn(const DynamicGame::Image &im,const char *name,uint32_t store,
                             uint64_t nearRef=0,uint64_t *foundRef=nullptr) {
    std::set<uint64_t> found;
    for(auto ref:im.refs(name)) {
        if(nearRef && llabs((int64_t)ref-(int64_t)nearRef)>0x100)continue;
        auto wrapper=im.ptr(ref+8);if(!im.code(wrapper))continue;
        for(unsigned j=0;j<64;j+=4) {
            auto at=wrapper+j;if(im.word(im.file(at))==0xd65f03c0)break;
            auto target=im.branch(at);
            if(target && im.code(target) && im.word(im.file(at+4))==store) {
                found.insert(target);if(foundRef)*foundRef=ref;
            }
        }
    }
    return found.size()==1?*found.begin():0;
}
inline Layout Resolve(DynamicGame::Image &im) {
    Layout out;
    im.index({"PCSlotClass","MobileSlotClass","CurrCharacterSlot","WrapBoxCharacter",
        "ClearChildren","GetChildrenCount","GetChildAt","GetVisibility","GetRenderOpacity","Slots"});
    auto classes=im.classes({"HTUI_MainForm","HTUI_CharacterSlot","PanelWidget"});
    out.mainCache=classes["HTUI_MainForm"];out.slotCache=classes["HTUI_CharacterSlot"];
    out.panelCache=classes["PanelWidget"];
    out.pc=im.uniqueField("PCSlotClass");out.mobile=im.uniqueField("MobileSlotClass");
    out.currentSlot=im.uniqueField("CurrCharacterSlot");
    if(!out.mainCache || !out.slotCache || !out.panelCache || !out.pc
        || out.mobile!=out.pc+8 || !out.currentSlot)return out;
    std::set<uint16_t> containers;
    for(auto p:im.refs("WrapBoxCharacter")) {
        if((im.get<uint64_t>(p+24)>>32)==0x45)containers.insert(im.get<uint16_t>(p+0x32));
    }
    // The property type points to the native HTUI_CharacterSlot class getter.
    std::set<uint64_t> slotGetters;
    for(auto p:im.refs("PCSlotClass"))if(im.get<uint16_t>(p+0x32)==out.pc)
        if(im.code(im.ptr(p+0x40)))slotGetters.insert(im.ptr(p+0x40));
    if(slotGetters.size()!=1)return out;
    auto starts=FunctionStarts(im);std::vector<std::pair<uint64_t,uint16_t>> candidates;
    for(size_t i=0;i+1<starts.size();++i) {
        auto lo=starts[i],hi=starts[i+1];if(hi-lo<0x100 || hi-lo>0x4000 || !im.code(lo))continue;
        uint32_t first=im.word(im.file(lo));
        if((first&0xffc003ff)!=0xf9400008)continue;
        uint16_t field=((first>>10)&4095)*8;if(!containers.count(field))continue;
        unsigned load=0,getterCalls=0;bool limit=false,param=false;
        for(auto at=lo;at<hi;at+=4) {
            auto w=im.word(im.file(at));
            load+=w==(0xf940027au|((uint32_t)(out.mobile/8)<<10)); // ldr x26,[x19,#mobile]
            getterCalls+=im.branch(at)==*slotGetters.begin();
            limit|=w==0x7100113f; // cmp w9,#4
            param|=w==0xaa0103f7; // mov x23,x1 (native refresh flag)
        }
        if(load==1 && getterCalls>=2 && limit && param)candidates.push_back({lo,field});
    }
    if(candidates.size()!=1)return out;
    out.refresh=candidates[0].first;out.container=candidates[0].second;
    // Resolve engine methods through their native reflection wrappers, not addresses.
    for(auto ref:im.refs("GetChildrenCount")) {
        auto wrapper=im.ptr(ref+8);if(!im.code(wrapper))continue;
        auto p=im.file(wrapper);
        if(im.word(p)==0xf9401028 && im.word(p+20)==0xb9000048 && im.word(p+24)==0xd65f03c0) {
            auto load=im.word(p+16);
            if((load&0xffc003ff)==0xb9400008)out.panelSlots=((load>>10)&4095)*4-8;
        }
        for(unsigned j=0;j<64;j+=4) {
            auto target=im.branch(wrapper+j);if(!target)continue;
            uint32_t w=im.word(im.file(target));
            if((w&0xffc003ff)==0xb9400000 && im.word(im.file(target+4))==0xd65f03c0) {
                if(out.childrenCount && out.childrenCount!=target)return Layout{};
                out.childrenCount=target;out.panelSlots=((w>>10)&4095)*4-8;
            }
            if(im.word(im.file(wrapper+j))==0xd65f03c0)break;
        }
    }
    bool arrayField=false;
    for(auto ref:im.refs("Slots"))arrayField|=im.get<uint16_t>(ref+0x32)==out.panelSlots
        && (im.get<uint64_t>(ref+24)>>32)==0x45;
    out.childAt=NativeReturn(im,"GetChildAt",0xf9000260); // str x0,[x19]
    if(!out.childAt && out.panelSlots) {
        auto next=std::upper_bound(starts.begin(),starts.end(),out.refresh);
        if(next==starts.end())return out;
        std::set<uint64_t> children;
        for(uint64_t at=out.refresh;at<*next;at+=4) {
            auto target=im.branch(at);if(!target)continue;
            auto p=im.file(target);auto first=im.word(p);
            if((first&0xfff8001f)!=0x37f80001)continue;
            if(im.word(p+4)!=(0xb9400008u|((uint32_t)((out.panelSlots+8)/4)<<10)))continue;
            if(im.word(p+16)!=(0xf9400008u|((uint32_t)(out.panelSlots/8)<<10)))continue;
            children.insert(target);
        }
        if(children.size()==1)out.childAt=*children.begin();
    }
    if(!out.childAt)return out;
    if(!out.panelSlots) {
        // The count getter can be inlined into its exec wrapper. The child-at
        // method still exposes the array and bounds-count layout directly.
        for(unsigned j=0;j<40;j+=4) {
            auto w=im.word(im.file(out.childAt+j));
            if((w&0xffc003ff)==0xf9400008)out.panelSlots=((w>>10)&4095)*8;
        }
        for(auto ref:im.refs("Slots"))arrayField|=im.get<uint16_t>(ref+0x32)==out.panelSlots
            && (im.get<uint64_t>(ref+24)>>32)==0x45;
    }
    if(!arrayField || out.panelSlots<0x30)return out;
    // Its body must implement bounds checking and load the same panel array.
    bool arrayLoad=false,negativeIndex=false,countLoad=false;
    for(unsigned j=0;j<48;j+=4) {
        auto w=im.word(im.file(out.childAt+j));
        arrayLoad|=w==(0xf9400008u|((uint32_t)(out.panelSlots/8)<<10));
        negativeIndex|=(w&0xfff8001f)==0x37f80001; // tbnz w1,#31
        countLoad|=w==(0xb9400008u|((uint32_t)((out.panelSlots+8)/4)<<10));
    }
    if(!arrayLoad || !negativeIndex || !countLoad)return out;
    for(auto ref:im.refs("ClearChildren")) {
        auto wrapper=im.ptr(ref+8);if(!im.code(wrapper))continue;
        auto p=im.file(wrapper);
        if(im.word(p)!=0xf9401028 || im.word(p+16)!=0xf9400008 || im.word(p+24)!=0xd61f0020)continue;
        uint32_t load=im.word(p+20);
        if((load&0xffc003ff)!=0xf9400101)continue;
        uint16_t offset=((load>>10)&4095)*8;
        if(out.clearVirtual && out.clearVirtual!=offset)return Layout{};
        out.clearVirtual=offset;
    }
    uint64_t opacityRef=0;
    out.opacity=NativeReturn(im,"GetRenderOpacity",0xbd000260,0,&opacityRef);
    out.visibility=NativeReturn(im,"GetVisibility",0x39000260,opacityRef);
    if(!out.clearVirtual || !out.opacity || !out.visibility)return out;
    for(auto address:{out.refresh,out.childAt,out.childrenCount,out.visibility,out.opacity}) {
        if(!address)continue;
        std::array<uint8_t,32> bytes{};
        for(unsigned i=0;i<32;++i)bytes[i]=im.get<uint8_t>(im.file(address)+i);
        out.signatures.push_back({address,bytes});
    }
    out.ready=true;return out;
}
} // namespace PartyUI

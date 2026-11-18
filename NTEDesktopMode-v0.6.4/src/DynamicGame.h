#pragma once
#include <mach-o/loader.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <unordered_map>
#include <vector>
#include "OperationShapes.h"
namespace DynamicGame {
inline uint32_t Normalize(uint32_t w) {
 if((w&0x9f000000)==0x90000000 || (w&0x9f000000)==0x10000000)return w&0x9f00001f;
 if((w&0x7c000000)==0x14000000)return w&0xfc000000;
 if((w&0xff000010)==0x54000000 || (w&0x7e000000)==0x34000000)return w&0xff00001f;
 if((w&0x7e000000)==0x36000000)return w&0xfff8001f;
 if((w&0x3b000000)==0x18000000)return w&0xff00001f;
 if((w&0x7f000000)==0x11000000 || (w&0x3b000000)==0x39000000)return w&~0x003ffc00u;
 return w;
}
inline int64_t Signed(uint64_t x,unsigned bits){return (int64_t)(x<<(64-bits))>>(64-bits);}
struct Segment {uint64_t va,size,file,filesize;int prot;};
struct Section {std::string name;uint64_t va,size,file;};
struct MethodInfo {std::string cls,selector,encoding;bool meta=false;uint64_t implementation=0;};
class Image {
 int fd=-1; const uint8_t *bytes=nullptr; size_t length=0;
 public:
 uint64_t base=0;std::vector<Segment> segments;std::vector<Section> sections;
 std::string uuid;std::vector<MethodInfo> methods;
 std::unordered_map<uint64_t,std::vector<uint64_t>> references;
 std::unordered_map<std::string,std::vector<uint64_t>> strings;
 ~Image(){if(bytes)munmap((void*)bytes,length);if(fd>=0)close(fd);}
 bool range(uint64_t off,uint64_t n)const{return off<=length&&n<=length-off;}
 template<class T> T get(uint64_t off)const{T t{};if(range(off,sizeof(t)))memcpy(&t,bytes+off,sizeof(t));return t;}
 uint32_t word(uint64_t off)const{return get<uint32_t>(off);}
 bool openFile(const char *path){
  fd=open(path,O_RDONLY);struct stat st{};if(fd<0||fstat(fd,&st)||st.st_size<32||st.st_size>1024LL*1024*1024)return false;
  length=(size_t)st.st_size;auto p=mmap(nullptr,length,PROT_READ,MAP_PRIVATE,fd,0);if(p==MAP_FAILED)return false;bytes=(const uint8_t*)p;
  auto h=get<mach_header_64>(0);if(h.magic!=MH_MAGIC_64||h.cputype!=CPU_TYPE_ARM64||h.ncmds>4096||!range(32,h.sizeofcmds))return false;
  uint64_t at=32,fixups=0;
  for(unsigned i=0;i<h.ncmds;++i){auto cmd=get<load_command>(at);if(cmd.cmdsize<8||!range(at,cmd.cmdsize))return false;
   if(cmd.cmd==LC_SEGMENT_64){auto s=get<segment_command_64>(at);if(cmd.cmdsize<sizeof(s)||s.nsects>(cmd.cmdsize-sizeof(s))/sizeof(section_64)||!range(s.fileoff,s.filesize))return false;
    segments.push_back({s.vmaddr,s.vmsize,s.fileoff,s.filesize,s.initprot});
    if(s.fileoff==0&&s.filesize)base=s.vmaddr;
    for(unsigned j=0;j<s.nsects;++j){auto q=get<section_64>(at+sizeof(s)+j*sizeof(section_64));sections.push_back({std::string(q.sectname,strnlen(q.sectname,16)),q.addr,q.size,q.offset});}
   }else if(cmd.cmd==LC_UUID){auto u=get<uuid_command>(at);char s[40];snprintf(s,sizeof(s),"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",u.uuid[0],u.uuid[1],u.uuid[2],u.uuid[3],u.uuid[4],u.uuid[5],u.uuid[6],u.uuid[7],u.uuid[8],u.uuid[9],u.uuid[10],u.uuid[11],u.uuid[12],u.uuid[13],u.uuid[14],u.uuid[15]);uuid=s;
   }else if(cmd.cmd==LC_DYLD_CHAINED_FIXUPS)fixups=get<linkedit_data_command>(at).dataoff;
   else if(cmd.cmd==LC_ENCRYPTION_INFO_64&&get<encryption_info_command_64>(at).cryptid)return false;
   at+=cmd.cmdsize;
  }
  if(!base||!fixups||!range(fixups,28))return false;
  // This parser supports the pointer representation actually encountered; it
  // does not silently treat another future fixup format as raw pointers.
  uint64_t starts=fixups+word(fixups+4);uint32_t count=word(starts);if(count>segments.size()||!range(starts+4,count*4))return false;
  for(unsigned i=0;i<count;++i){uint32_t delta=word(starts+4+i*4);if(delta&&get<uint16_t>(starts+delta+6)!=6)return false;}
  return true;
 }
 uint64_t file(uint64_t rel)const{if(rel>UINT64_MAX-base)return UINT64_MAX;uint64_t va=base+rel;for(auto&s:segments)if(va>=s.va&&va-s.va<s.filesize)return s.file+va-s.va;return UINT64_MAX;}
 uint64_t relative(uint64_t off)const{for(auto&s:segments)if(off>=s.file&&off-s.file<s.filesize)return s.va-base+off-s.file;return UINT64_MAX;}
 bool code(uint64_t rel)const{for(auto&s:sections)if(s.name=="__text"&&base+rel>=s.va&&base+rel-s.va<s.size)return true;return false;}
 bool data(uint64_t rel,bool writable=false)const{for(auto&s:segments)if(base+rel>=s.va&&base+rel-s.va<s.size&&!(s.prot&4)&&(!writable||(s.prot&2)))return true;return false;}
 uint64_t ptr(uint64_t off)const{uint64_t w=get<uint64_t>(off);if(!range(off,8)||!w||(w>>63))return 0;return w&0xfffffffffULL;}
 std::string str(uint64_t rel)const{uint64_t p=file(rel);if(!range(p,1))return {};size_t n=strnlen((const char*)bytes+p,std::min<size_t>(1024,length-p));if(n==1024||!range(p,n+1))return {};return std::string((const char*)bytes+p,n);}
 std::vector<uint64_t> find(const std::string &s,bool wide=false)const{
  std::vector<uint8_t> needle;for(unsigned char c:s){needle.push_back(c);if(wide)needle.push_back(0);}needle.push_back(0);if(wide)needle.push_back(0);
  std::vector<uint64_t> out;auto p=bytes,end=bytes+length;
  while(p<end){p=std::search(p,end,needle.begin(),needle.end());if(p==end)break;auto r=relative(p-bytes);if(r!=UINT64_MAX)out.push_back(r);++p;}return out;
 }
 void index(const std::vector<std::string>&names){std::set<uint64_t>wanted;
  for(auto&n:names){auto v=find(n);strings[n]=v;wanted.insert(v.begin(),v.end());}
  for(auto&s:segments)if(!(s.prot&4))for(uint64_t off=(s.file+7)&~7ULL;off+8<=s.file+s.filesize;off+=8){auto p=ptr(off);if(wanted.count(p))references[p].push_back(off);}
 }
 std::vector<uint64_t> refs(const std::string&name)const{std::vector<uint64_t>out;auto it=strings.find(name);if(it==strings.end())return out;for(auto p:it->second){auto r=references.find(p);if(r!=references.end())out.insert(out.end(),r->second.begin(),r->second.end());}return out;}
 std::vector<uint64_t> pointerRefs(uint64_t target)const{std::vector<uint64_t>out;for(auto&s:segments)if(!(s.prot&4))for(uint64_t p=(s.file+7)&~7ULL;p+8<=s.file+s.filesize;p+=8)if(ptr(p)==target)out.push_back(p);return out;}
 uint64_t addressPair(uint64_t rel)const{uint64_t p=file(rel);uint32_t a=word(p),b=word(p+4);if((a&0x9f000000)!=0x90000000||(b&0xffc00000)!=0x91000000||((b>>5)&31)!=(a&31))return 0;int64_t page=(int64_t)(rel&~4095ULL)+Signed(((a>>29)&3)|(((a>>5)&0x7ffff)<<2),21)*4096;return page+((b>>10)&4095);}
 uint64_t branch(uint64_t rel,bool link=true)const{uint32_t w=word(file(rel));if((w&0xfc000000)!=(link?0x94000000u:0x14000000u))return 0;return rel+Signed(w&0x3ffffff,26)*4;}
 bool constant(uint64_t rel,uint32_t &value)const{if(!code(rel))return false;auto p=file(rel);auto a=word(p),b=word(p+4);if((a&0xffe0001f)!=0x52800000||b!=0xd65f03c0)return false;value=(a>>5)&65535;return true;}
 bool anchor(uint64_t rel,size_t size,const char*name)const{if(!*name)return true;auto targets=find(name,true);for(size_t p=0;p+8<=size;p+=4){auto target=addressPair(rel+p);if(std::find(targets.begin(),targets.end(),target)!=targets.end())return true;}return false;}
 std::map<std::string,uint64_t> operations()const{
  std::unordered_map<uint32_t,std::vector<const Recipe*>> first;for(auto&r:kRecipes)first[r.shape[0]].push_back(&r);
  std::map<std::string,std::vector<uint64_t>> found;
  for(auto&s:sections)if(s.name=="__text"&&range(s.file,s.size))for(uint64_t p=s.file;p+4<=s.file+s.size;p+=4){auto it=first.find(Normalize(word(p)));if(it==first.end())continue;
   for(auto r:it->second){if(p+r->count*4>s.file+s.size)continue;bool yes=true;for(size_t i=1;i<r->count&&yes;++i)yes=Normalize(word(p+i*4))==r->shape[i];
    uint64_t rel=relative(p);if(yes&&anchor(rel,r->count*4,r->classAnchor))found[r->name].push_back(rel);}
  }
  std::map<std::string,uint64_t>out;for(auto&kv:found)if(kv.second.size()==1)out[kv.first]=kv.second[0];return out;
 }
 std::map<std::string,uint64_t> classes(const std::vector<std::string>&names)const{
  std::map<uint64_t,std::string>strings;for(auto&n:names)for(auto p:find(n,true))strings[p]=n;
  std::map<std::string,std::set<uint64_t>> caches;
  for(auto&s:sections)if(s.name=="__text"&&range(s.file,s.size))for(uint64_t p=s.file;p+8<s.file+s.size;p+=4){uint32_t a=word(p);if((a&0x9f00001f)!=0x90000001)continue;uint64_t rel=relative(p),target=addressPair(rel);auto it=strings.find(target);if(it==strings.end())continue;
   std::array<uint64_t,32> regs{};regs[1]=target;
   for(unsigned k=8;k<144&&p+k+4<=s.file+s.size;k+=4){uint32_t w=word(p+k);unsigned rd=w&31,rn=(w>>5)&31;
    if((w&0x9f000000)==0x90000000)regs[rd]=((rel+k)&~4095ULL)+Signed(((w>>29)&3)|(((w>>5)&0x7ffff)<<2),21)*4096;
    else if((w&0xffc00000)==0x91000000)regs[rd]=regs[rn]?regs[rn]+((w>>10)&4095):0;
    else if((w&0xffe0ffe0)==0xaa0003e0)regs[rd]=regs[(w>>16)&31];
    else if((w&0xfc000000)==0x94000000){if(regs[1]==target&&data(regs[2],true)&&code(regs[3]))caches[it->second].insert(regs[2]);break;}
   }
  }
  std::map<std::string,uint64_t>out;for(auto&kv:caches)if(kv.second.size()==1)out[kv.first]=*kv.second.begin();return out;
 }
 bool objc(){
  for(auto&s:sections)if(s.name=="__objc_classlist"&&range(s.file,s.size))for(uint64_t p=s.file;p+8<=s.file+s.size;p+=8){uint64_t cls=ptr(p),ro=file(ptr(file(cls)+32)&~7ULL);auto name=str(ptr(ro+24));if(name!="FIOSView"&&name!="IOSAppDelegate"&&name!="IOSViewController"&&name!="FIOSAsyncTask")continue;
   for(unsigned meta=0;meta<2;++meta){auto current=meta?ptr(file(cls)):cls;auto r=file(ptr(file(current)+32)&~7ULL);auto list=ptr(r+32);if(!list)continue;uint64_t ml=file(list);uint32_t flags=word(ml),count=word(ml+4),stride=flags&0xfffc;if(count>4096||(stride!=12&&stride!=24)||!range(ml+8,(uint64_t)count*stride))return false;
    for(unsigned i=0;i<count;++i){uint64_t e=ml+8+i*stride,n=0,t=0,imp=0;if(flags&0x80000000){n=relative(e)+get<int32_t>(e);if(!(flags&0x40000000))n=ptr(file(n));t=relative(e+4)+get<int32_t>(e+4);imp=relative(e+8)+get<int32_t>(e+8);}else{n=ptr(e);t=ptr(e+8);imp=ptr(e+16);}if(code(imp))methods.push_back({name,str(n),str(t),meta!=0,imp});}
   }
  }return true;
 }
 uint64_t method(const char*cls,const char*selector,const char*encoding,bool meta=false)const{uint64_t found=0;for(auto&m:methods)if(m.cls==cls&&m.selector==selector&&m.encoding==encoding&&m.meta==meta){if(found&&found!=m.implementation)return 0;found=m.implementation;}return found;}
 bool indirectPointerFilter(uint64_t method)const {
  if(!code(method))return false;
  for(unsigned i=4;i<1020;i+=4){
   uint64_t at=method+i;auto p=file(at);uint32_t cmp=word(p),skip=word(p+4);
   if(cmp!=0xf1000c1f || (skip&0xff00001f)!=0x54000000)continue;
   int64_t destination=(int64_t)(at+4)+Signed((skip>>5)&0x7ffff,19)*4;
   if(destination<(int64_t)method||destination>=(int64_t)at)continue;
   uint64_t target=branch(at-4);if(!target)continue;
   for(unsigned j=0;j<2&&branch(target,false);++j)target=branch(target,false);
   uint64_t f=file(target);uint32_t adrp=word(f),ldr=word(f+4);
   if((adrp&0x9f00001f)!=0x90000001 || (ldr&0xffc003ff)!=0xf9400021)continue;
   uint64_t page=(target&~4095ULL)+Signed(((adrp>>29)&3)|(((adrp>>5)&0x7ffff)<<2),21)*4096;
   uint64_t selector=ptr(file(page+((ldr>>10)&4095)*8));
   if(str(selector)=="type")return true;
  }
  return false;
 }
 bool mouseForTouchField(uint16_t &offset,uint16_t &mask)const {
  auto found=refs("bUseMouseForTouch");if(found.size()!=1)return false;
  auto target=ptr(found[0]+0x38);if(!code(target))return false;
  auto p=file(target);auto load=word(p),set=word(p+4),store=word(p+8);
  if((load&0xffc003ff)!=0x79400008 || (store&0xffc003ff)!=0x79000008 || word(p+12)!=0xd65f03c0)return false;
  if(((load>>10)&4095)!=((store>>10)&4095) || (set&0xff8003ff)!=0x32000108)return false;
  unsigned n=(set>>22)&1,r=(set>>16)&63,s=(set>>10)&63;
  if(n||s||r>=32)return false;
  uint32_t bit=1u<<((32-r)&31);if(bit>65535)return false;
  offset=((load>>10)&4095)*2;mask=(uint16_t)bit;return offset>0&&offset<4096;
 }
 uint32_t enumValue(const char*name)const{std::set<uint32_t>values;for(auto p:refs(name)){uint64_t v=get<uint64_t>(p+8);if(v<64)values.insert((uint32_t)v);}return values.size()==1?*values.begin():UINT32_MAX;}
 uint16_t uniqueField(const char*name)const{std::set<uint16_t> offsets;for(auto p:refs(name))if(get<uint64_t>(p+8)==0&&(get<uint64_t>(p+24)>>32)==0x45)offsets.insert(get<uint16_t>(p+0x32));return offsets.size()==1?*offsets.begin():0;}
 bool booleanField(const char*name,uint16_t expected)const{for(auto p:refs(name)){auto f=ptr(p+0x38);auto off=file(f);if(code(f)&&word(off)==0x52800028&&word(off+4)==(0x39000008u|((uint32_t)expected<<10))&&word(off+8)==0xd65f03c0)return true;}return false;}
 bool field(const char*name,uint16_t expected)const{for(auto p:refs(name))if(get<uint64_t>(p+8)==0&&(get<uint64_t>(p+24)>>32)==0x45&&get<uint16_t>(p+0x32)==expected)return true;return false;}
};
struct Resolved {
 bool platform=false,objc=false,input=false,profiles=false;
 bool cursor=false;
 bool NativeIndirectFilter=false,NativeMouseForTouchSwitch=false;
 uint16_t MouseForTouchOffset=0,MouseForTouchMask=0;
 uint64_t CursorTable=0;
 std::array<uint64_t,13> CursorFunctions{};
 size_t CursorTypeSlot=0,CursorShowSlot=0,CursorPositionSlot=0;
 size_t CursorTypeField=0,CursorShownField=0,CursorPositionField=0;
 std::string uuid,reason;
 std::array<uint64_t,5> queries{};uint64_t uiQuery=0;uint32_t commonIOS=0,commonMac=0,uiIOS=0,uiMac=0;
 uint64_t ApplicationGetter=0,ViewSize=0,PointerPreference=0,GameTask=0,HandleTouches=0;
 uint64_t CommonSettings=0,CommonSupport=0,CommonRecalculate=0,CommonLocked=0,InputPlatformSettings=0,InputRebuild=0,ProfileSetter=0,ProfileLookup=0,ProfileIdGetter=0,PlayerInputGetter=0,PlayerInputThunk=0,UserSettingsGetter=0;
 uint16_t DefaultMappingContext=0;
 uint16_t RawInputType=0,CurrentInputType=0,OverrideInputType=0,OverrideActive=0;
 uint64_t ObjectChunks=0,ObjectCount=0,ObjectChunkCount=0,NamePool=0;
 std::map<std::string,uint64_t> classCaches;
 uint64_t cls(const char*n)const{auto i=classCaches.find(n);return i==classCaches.end()?0:i->second;}
};
inline Resolved Resolve(Image&im){
 Resolved out;out.uuid=im.uuid;
 const std::vector<std::string> classNames={"InputSettings","CommonInputPlatformSettings","CommonInputSubsystem","HTPlayerController","EnhancedPlayerInput","InputMappingContext","EnhancedInputLocalPlayerSubsystem","EnhancedInputPlatformSettings","EnhancedInputPlatformData","EnhancedInputDeveloperSettings","EnhancedInputUserSettings","EnhancedPlayerMappableKeyProfile","PlayerMappableKeySettings"};
 std::vector<std::string>names={"bUseMouseForTouch","GetCurrentPlatform","IsPC","IsMac","IsDesktop","IsMobilePlatform","EHTCommonPlatformType::Mac","EHTCommonPlatformType::IOS","EHTPlatformType::Mac","EHTPlatformType::IOS","UITemplet","UITemplate_Mobile","DefaultInputType","bSupportsMouseAndKeyboard","PlayerInput","DefaultMappingContextPtr","EnhancedActionMappings","MappingContextRedirects","AppliedInputContextData","AppliedInputContexts","CurrentProfileIdentifierString","SavedKeyProfilesMap","ProfileIdentifierString","UserSettings","SupportedKeyProfileIds","SettingBehavior","Action","Key","PlayerMappableKeySettings"};
 im.index(names);auto operations=im.operations();
 out.commonIOS=im.enumValue("EHTCommonPlatformType::IOS");out.commonMac=im.enumValue("EHTCommonPlatformType::Mac");out.uiIOS=im.enumValue("EHTPlatformType::IOS");out.uiMac=im.enumValue("EHTPlatformType::Mac");
 std::array<const char*,5>qnames={"GetCurrentPlatform","IsPC","IsMac","IsDesktop","IsMobilePlatform"};
 struct Candidate{uint64_t registration,target;uint32_t value;};std::array<std::vector<Candidate>,5>candidates;
 for(unsigned i=0;i<5;++i)for(auto ref:im.refs(qnames[i])){uint64_t wrapper=im.ptr(ref+8);if(!im.code(wrapper))continue;
  for(unsigned j=0;j<128;j+=4){uint32_t w=im.word(im.file(wrapper+j));if(w==0xd65f03c0)break;uint64_t target=im.branch(wrapper+j);uint32_t v=0;if(target&&im.constant(target,v))candidates[i].push_back({im.relative(ref),target,v});}
 }
 std::set<std::array<uint64_t,5>>groups;
 for(auto a:candidates[0])if(a.value==out.commonIOS){std::array<uint64_t,5>g{};bool yes=true;
  for(unsigned i=0;i<5;++i){std::set<uint64_t>hits;for(auto c:candidates[i])if(llabs((int64_t)c.registration-(int64_t)a.registration)<0x2000&&llabs((int64_t)c.target-(int64_t)a.target)<0x1000&&c.value==(i==0?out.commonIOS:(i==4?1:0)))hits.insert(c.target);if(hits.size()!=1){yes=false;break;}g[i]=*hits.begin();}if(yes)groups.insert(g);
 }
 if(groups.size()==1&&out.commonMac<32&&out.uiMac<32&&out.commonIOS<32&&out.uiIOS<32&&im.field("UITemplet",0x20)&&im.field("UITemplate_Mobile",0x78)){
  out.queries=*groups.begin();auto consumer=operations["UIConsumer"];uint64_t query=consumer?im.branch(consumer+0x1c):0;uint32_t v=0;
  if(query&&im.constant(query,v)&&v==out.uiIOS){out.uiQuery=query;out.platform=true;}
 }
 im.objc();out.ApplicationGetter=im.method("IOSAppDelegate","IOSApplication","^v16@0:8");out.ViewSize=im.method("FIOSView","ViewSize","{CGSize=dd}16@0:8");out.PointerPreference=im.method("IOSViewController","prefersPointerLocked","B16@0:8");out.GameTask=im.method("FIOSAsyncTask","CreateTaskWithBlock:","v24@0:8@?16",true);out.HandleTouches=im.method("FIOSView","HandleTouches:ofType:","v28@0:8@16i24");
 out.NativeIndirectFilter=im.indirectPointerFilter(out.HandleTouches);
 out.objc=out.ApplicationGetter&&out.ViewSize&&out.PointerPreference&&out.GameTask&&out.HandleTouches;
 // Identify the cursor table by the operations it exposes. The two setters
 // must be single field stores, the position getter a double-pair load; the
 // type getter must address the very field written by SetType. Preserve all
 // 13 ABI slots, and reject an expanded or ambiguous table rather than truncate.
 std::set<uint64_t> cursorTables;
 for(auto&s:im.segments)if(!(s.prot&4))for(uint64_t p=(s.file+7)&~7ULL;p+13*8<=s.file+s.filesize;p+=8){
  if(p<s.file+16||im.get<uint64_t>(p-16)||im.get<uint64_t>(p-8))continue;
  std::array<uint64_t,13>functions{};bool all=true;for(unsigned i=0;i<13;++i){functions[i]=im.ptr(p+i*8);if(!im.code(functions[i])){all=false;break;}}if(!all||im.code(im.ptr(p+13*8)))continue;
  size_t typeSlot=99,showSlot=99,positionSlot=99,typeField=0,shownField=0,positionField=0;unsigned types=0,shows=0,positions=0;
  for(unsigned i=0;i<13;++i){auto f=im.file(functions[i]);uint32_t w=im.word(f);if(im.word(f+4)!=0xd65f03c0)continue;
   if((w&0xffc003ff)==0xb9000001){++types;typeSlot=i;typeField=((w>>10)&4095)*4;}
   if((w&0xffc003ff)==0x39000001){++shows;showSlot=i;shownField=(w>>10)&4095;}
   if((w&0xffc07fff)==0x6d400400){++positions;positionSlot=i;positionField=Signed((w>>15)&127,7)*8;}
  }
  if(types!=1||shows!=1||positions!=1||typeField<8||typeField>256||shownField<=typeField||shownField>256||positionField<8||positionField>256)continue;
  bool getter=false;for(auto f:functions){auto q=im.file(f);getter|=im.word(q)==(0xb9400000u|((uint32_t)(typeField/4)<<10))&&im.word(q+4)==0xd65f03c0;}
  if(!getter)continue;cursorTables.insert(im.relative(p));out.CursorTable=im.relative(p);out.CursorFunctions=functions;out.CursorTypeSlot=typeSlot;out.CursorShowSlot=showSlot;out.CursorPositionSlot=positionSlot;out.CursorTypeField=typeField;out.CursorShownField=shownField;out.CursorPositionField=positionField;
 }
 out.cursor=cursorTables.size()==1;
 out.classCaches=im.classes(classNames);
 out.NativeMouseForTouchSwitch=out.cls("InputSettings")&&im.mouseForTouchField(out.MouseForTouchOffset,out.MouseForTouchMask);
 #define NTE_OPERATION(n) out.n=operations[#n]
 NTE_OPERATION(CommonSettings);NTE_OPERATION(CommonSupport);NTE_OPERATION(CommonRecalculate);NTE_OPERATION(CommonLocked);NTE_OPERATION(InputPlatformSettings);NTE_OPERATION(InputRebuild);NTE_OPERATION(ProfileSetter);NTE_OPERATION(PlayerInputGetter);
 #undef NTE_OPERATION
 auto objectAccess=operations["ObjectArrayAccess"];auto object=objectAccess?im.addressPair(objectAccess):0;
 // Validate the container layout at the actual access, including the element
 // stride, rather than trusting an address from a previous executable.
 if(object&&im.data(object,true)&&im.word(im.file(objectAccess+8))==0xb940252a&&im.word(im.file(objectAccess+28))==0xf9400929&&im.word(im.file(objectAccess+36))==0x5280030a){out.ObjectChunks=object+0x10;out.ObjectCount=object+0x24;out.ObjectChunkCount=object+0x2c;}
 auto decoder=operations["NameDecoder"];auto pool=decoder?im.addressPair(decoder+12):0;
 if(pool&&im.data(pool,true)&&im.word(im.file(decoder+56))==0xf9406908&&im.word(im.file(decoder+72))==0xd346fd15)out.NamePool=pool+0xd0;
 if(out.CommonRecalculate){auto p=im.file(out.CommonRecalculate);out.OverrideActive=(im.word(p)>>10)&4095;out.RawInputType=(im.word(p+8)>>5)&65535;out.OverrideInputType=(im.word(p+12)>>5)&65535;out.CurrentInputType=(im.word(p+24)>>10)&4095;}
 bool inputLayout=out.RawInputType>=0x28&&out.RawInputType<0x1000&&out.CurrentInputType==out.RawInputType+1&&out.OverrideInputType>out.CurrentInputType&&out.OverrideInputType<0x1000&&out.OverrideActive==out.OverrideInputType+1;
 out.input=inputLayout&&out.CommonSettings&&out.CommonSupport&&out.CommonRecalculate&&out.CommonLocked&&out.ObjectChunks&&out.cls("CommonInputPlatformSettings")&&out.cls("CommonInputSubsystem")&&im.field("DefaultInputType",0x40)&&im.booleanField("bSupportsMouseAndKeyboard",0x41);
 if(out.PlayerInputGetter){
  for(auto&s:im.sections)if(s.name=="__text")for(uint64_t p=s.file;p+8<=s.file+s.size;p+=4)if(im.word(p)==0xd100c000&&im.branch(im.relative(p)+4,false)==out.PlayerInputGetter){if(out.PlayerInputThunk){out.PlayerInputThunk=0;break;}out.PlayerInputThunk=im.relative(p);}
 }
 if(out.PlayerInputThunk)for(auto p:im.pointerRefs(out.PlayerInputThunk)){auto f=im.ptr(p+8);auto fp=im.file(f);if(im.code(f)&&im.word(fp)==0xf940c000&&im.word(fp+4)==0xd65f03c0){if(out.UserSettingsGetter&&out.UserSettingsGetter!=f){out.UserSettingsGetter=0;break;}out.UserSettingsGetter=f;}}
 if(out.ProfileSetter)for(auto p:im.pointerRefs(out.ProfileSetter)){uint64_t getter=im.ptr(p+16),lookup=im.ptr(p+40);uint64_t g=im.file(getter),l=im.file(lookup);
  bool lookupShape=im.code(lookup);for(size_t i=0;i<sizeof(shapeProfileLookup)/4&&lookupShape;++i)lookupShape=Normalize(im.word(l+i*4))==shapeProfileLookup[i];
  if(im.code(getter)&&lookupShape&&im.word(g)==0x9101e000&&im.word(g+4)==0xd65f03c0){if(out.ProfileLookup&&out.ProfileLookup!=lookup){out.ProfileLookup=0;break;}out.ProfileIdGetter=getter;out.ProfileLookup=lookup;}
 }
 out.DefaultMappingContext=im.uniqueField("DefaultMappingContextPtr");
 out.profiles=out.DefaultMappingContext&&out.input&&out.NamePool&&out.InputPlatformSettings&&out.InputRebuild&&out.ProfileSetter&&out.ProfileLookup&&out.ProfileIdGetter&&out.PlayerInputThunk&&out.UserSettingsGetter;
 const std::pair<const char*,uint16_t>fields[]={{"PlayerInput",0x440},{"EnhancedActionMappings",0x5d8},{"MappingContextRedirects",0x28},{"AppliedInputContextData",0x538},{"AppliedInputContexts",0x588},{"CurrentProfileIdentifierString",0x78},{"SavedKeyProfilesMap",0xd8},{"ProfileIdentifierString",0x30},{"UserSettings",0x1b0},{"SupportedKeyProfileIds",0x78},{"SettingBehavior",0x41},{"Action",0x20},{"Key",0x28},{"PlayerMappableKeySettings",0x48},{"PlayerMappableKeySettings",0x70}};
 for(auto f:fields)out.profiles &= im.field(f.first,f.second);
 for(auto&name:classNames)if(name!="InputSettings")out.profiles &= out.cls(name.c_str())!=0;
 out.reason=out.platform?"resolved":"platform discovery incomplete or ambiguous";return out;
}
} // namespace DynamicGame

#include <cstdio>
#include "../src/DynamicGame.h"
int main(int argc,char**argv){if(argc!=2)return 2;DynamicGame::Image image;if(!image.openFile(argv[1])){puts("parse failed");return 2;}auto r=DynamicGame::Resolve(image);
printf("uuid=%s platform=%d objc=%d input=%d profiles=%d reason=%s\n",r.uuid.c_str(),r.platform,r.objc,r.input,r.profiles,r.reason.c_str());
for(auto&kv:image.operations())printf("operation %s=0x%llx\n",kv.first.c_str(),kv.second);
for(auto&kv:r.classCaches)printf("class %s=0x%llx\n",kv.first.c_str(),kv.second);
printf("objects=%llx names=%llx settings=%llx support=%llx lookup=%llx getter=%llx thunk=%llx userdata=%llx ui=%llx\n",r.ObjectChunks,r.NamePool,r.CommonSettings,r.CommonSupport,r.ProfileLookup,r.ProfileIdGetter,r.PlayerInputThunk,r.UserSettingsGetter,r.uiQuery);
printf("cursor=%d table=%llx type_slot=%zu show_slot=%zu pos_slot=%zu type_field=%zu show_field=%zu\n",r.cursor,r.CursorTable,r.CursorTypeSlot,r.CursorShowSlot,r.CursorPositionSlot,r.CursorTypeField,r.CursorShownField);
printf("native_type3_filter=%d mouse_for_touch_switch=%d offset=%x mask=%x\n",r.NativeIndirectFilter,r.NativeMouseForTouchSwitch,r.MouseForTouchOffset,r.MouseForTouchMask);
for(auto p:r.queries)printf("query=%llx\n",p);
return r.platform&&r.objc&&r.input&&r.profiles&&r.cursor&&r.NativeIndirectFilter&&r.NativeMouseForTouchSwitch?0:1;}

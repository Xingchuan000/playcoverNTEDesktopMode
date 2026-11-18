#pragma once
// Coordinates of the signed assembly/synthetic fixtures, not runtime fallbacks.
static void SetupFixtureLayout(){
 const uintptr_t queries[]={0xaa1b164,0xaa1b16c,0xaa1b174,0xaa1b17c,0xaa1b1f4};
 for(size_t i=0;i<5;++i)MacPlatform::kQueries[i].offset=queries[i];
 MacPlatform::kUIQueries[0].offset=0xaa0bf34;
 NativeCursor::kCursorVTable=0xd3310c8;NativeCursor::kGetPositionSlot=5;NativeCursor::kSetTypeSlot=7;NativeCursor::kShowSlot=10;NativeCursor::kTypeField=8;NativeCursor::kShownField=0x30;
 NativeCursor::kFunctions={0x15780e0,0x15780e4,0x1577f68,0x1577f70,0x1577f78,0x15780e8,0x1571ac8,0x1571b28,0x15780f0,0x1571b30,0x1571b40,0x1571b48,0x15780f8};
 gGame.PointerPreference=0x1577924;gGame.ViewSize=0x15776c0;gGame.NamePool=0xfd2abd0;gGame.ObjectChunks=0x100236b0;gGame.ObjectCount=0x100236c4;gGame.ObjectChunkCount=0x100236cc;
 gGame.UserSettingsGetter=0x4c327ac;gGame.ProfileIdGetter=0x4c46f08;gGame.ProfileLookup=0x4c47870;gGame.ProfileSetter=0x4c46b34;
}

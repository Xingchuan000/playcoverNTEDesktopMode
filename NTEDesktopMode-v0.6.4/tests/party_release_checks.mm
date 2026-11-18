#define NTE_ENABLE_LOGGING 0
#define NTE_ENABLE_PARTY_LOGGING 0
#import "../src/NTEDesktopMode.mm"
static unsigned checks=0;
static void Check(bool ok,const char *name){++checks;if(!ok){fprintf(stderr,"FAIL: %s\n",name);exit(1);}}
int main(){@autoreleasepool{
    Check(!kLoggingEnabled && !kHardwareObservers,"release generic logging and hardware observers off");
    int evaluated=0;PartyNote("unused=%d",++evaluated);
    Check(evaluated==0,"disabled party diagnostics do not evaluate their arguments");
    NSString *dir=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    PartyUI::OpenLog(dir);
    Check(![NSFileManager.defaultManager fileExistsAtPath:dir] && PartyUI::logFile==nullptr,"release creates no party log directory or file");
    // Deliberately unusable diagnostic getter addresses: a release Describe must
    // not call them, read UI visibility or decode names.
    gPartyLayout.visibility=0;gPartyLayout.opacity=0;
    PartyUI::Children sample;sample.valid=true;sample.count=1;sample.objects[0]=0;
    PartyUI::Describe(1,"release",0,0,sample,0,0,false);
    Check(PartyUI::logFile==nullptr,"release skips runtime widget diagnostic reads");
    PartyUI::Configure(@{});
    Check(PartyUI::repairEnabled && PartyUI::rebuildExisting,"tested party correction and rebuild remain enabled");
    Check(KeyboardBeep::enabled && !KeyboardBeep::diagnostics,"keyboard beep repair remains enabled without diagnostics");
    printf("party release checks passed: %u\n",checks);
}}

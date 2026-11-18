// Exercise production's actual load-time initialization mechanism without a game.
static void SeedResolvedState();
static unsigned probeCalls=0;
#define NTE_BOOTSTRAP_PROBE SeedResolvedState
#ifndef NTE_BOOTSTRAP_SOURCE
#define NTE_BOOTSTRAP_SOURCE "../src/NTEDesktopMode.mm"
#endif
#import NTE_BOOTSTRAP_SOURCE
static void SeedResolvedState() {
    ++probeCalls;
    gGame.platform=true;
    gGame.GameTask=0x12345678;
    gGame.ViewSize=0x34567890;
    gGame.HandleTouches=0x456789a0;
}
extern "C" __attribute__((visibility("default"))) bool NTEBootstrapStateSurvived() {
    return probeCalls==1 && gGame.platform && gGame.GameTask==0x12345678
        && gGame.ViewSize==0x34567890 && gGame.HandleTouches==0x456789a0;
}

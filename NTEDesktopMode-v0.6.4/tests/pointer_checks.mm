// Standalone runtime test: synthetic NSObject classes only, no game launch.
#import "../src/NTEDesktopMode.mm"
#include "FixtureLayout.h"
static int checks=0;
static BOOL No(id,SEL) { return NO; }
static BOOL Yes(id,SEL) { return YES; }
static int Integer(id,SEL) { return 7; }
static BOOL WithArgument(id,SEL,id) { return NO; }
static void Check(bool ok,const char *label) {
    ++checks;
    if (!ok) { fprintf(stderr,"FAIL: %s\n",label); exit(1); }
}
int main() { SetupFixtureLayout();
    @autoreleasepool {
        Check(IsPlayToolsImagePath("/Users/test/Library/Frameworks/PlayTools.framework/PlayTools"),"direct framework executable accepted");
        Check(IsPlayToolsImagePath("/Users/test/Library/Frameworks/PlayTools.framework/Versions/A/PlayTools"),"actual versioned framework executable accepted");
        Check(IsPlayToolsImagePath("/Library/Frameworks/PlayTools.framework/Versions/Current/PlayTools"),"version alias accepted");
        Check(!IsPlayToolsImagePath(nullptr),"null path rejected");
        Check(!IsPlayToolsImagePath("PlayTools.framework/PlayTools"),"relative path rejected");
        Check(!IsPlayToolsImagePath("/tmp/FakePlayTools.framework/PlayTools"),"framework prefix impostor rejected");
        Check(!IsPlayToolsImagePath("/tmp/PlayTools.framework/PlayTools.other"),"executable suffix rejected");
        Check(!IsPlayToolsImagePath("/tmp/PlayTools.framework/Versions/A/Other"),"different versioned executable rejected");
        Check(!IsPlayToolsImagePath("/tmp/PlayTools.framework/Versions//PlayTools"),"empty version rejected");
        Check(!IsPlayToolsImagePath("/tmp/PlayTools.framework/Versions/A/nested/PlayTools"),"nested executable rejected");
        Check(!IsPlayToolsImagePath("/tmp/PlayTools.framework/Versions/../PlayTools"),"parent version traversal rejected");
        Check(!IsPlayToolsImagePath("/tmp/PlayTools.framework/Versions/./PlayTools"),"current-directory version traversal rejected");
        SEL selector=sel_registerName("ntePointerPreference");
        Class parent=objc_allocateClassPair(NSObject.class,"NTEPointerParentProbe",0);
        class_addMethod(parent,selector,(IMP)No,"B@:");
        objc_registerClassPair(parent);
        Class child=objc_allocateClassPair(parent,"NTEPointerChildProbe",0);
        objc_registerClassPair(child);
        Check(!ReplaceOwnMethod(child,selector,(IMP)No,(IMP)Yes),"inherited method rejected");
        Check(class_getMethodImplementation(parent,selector)==(IMP)No,"parent implementation preserved");
        Check(class_getMethodImplementation(child,selector)==(IMP)No,"inherited implementation preserved");
        class_addMethod(child,selector,(IMP)No,"B@:");
        Check(!ReplaceOwnMethod(child,selector,(IMP)Yes,(IMP)No),"unexpected current implementation rejected");
        Check(ReplaceOwnMethod(child,selector,(IMP)No,(IMP)Yes),"own boolean method restored");
        id instance=[[child alloc] init];
        Check(((BOOL(*)(id,SEL))objc_msgSend)(instance,selector),"restored method executes native return");
        Check(class_getMethodImplementation(parent,selector)==(IMP)No,"restoring child leaves parent intact");
        Check(!ReplaceOwnMethod(child,selector,(IMP)No,(IMP)Yes),"stale expected implementation rejected");
        SEL intSelector=sel_registerName("nteIntegerPreference");
        class_addMethod(child,intSelector,(IMP)Integer,"i@:");
        Check(!ReplaceOwnMethod(child,intSelector,(IMP)Integer,(IMP)Yes),"nonboolean signature rejected");
        SEL argSelector=sel_registerName("ntePreferenceWithArgument:");
        class_addMethod(child,argSelector,(IMP)WithArgument,"B@:@");
        Check(!ReplaceOwnMethod(child,argSelector,(IMP)WithArgument,(IMP)Yes),"extra argument rejected");
        SEL charSelector=sel_registerName("nteCharPreference");
        class_addMethod(child,charSelector,(IMP)No,"c@:");
        Check(ReplaceOwnMethod(child,charSelector,(IMP)No,(IMP)Yes),"Objective-C char BOOL signature accepted");
        Check(!ReplaceOwnMethod(Nil,selector,(IMP)No,(IMP)Yes),"missing class rejected");
        Check(!ReplaceOwnMethod(child,sel_registerName("nteMissing"),(IMP)No,(IMP)Yes),"missing method rejected");
        Check(!ReplaceOwnMethod(child,selector,(IMP)Yes,nullptr),"missing replacement rejected");
        printf("PASS: %d pointer restoration scope and signature cases\n",checks);
    }
}

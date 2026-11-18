// NTE dynamic desktop input adapter. Resolve capabilities; no UUID allowlist.
// v0.6.4 release: dynamic desktop party slots and key-down fallback repair; logs off.
// Retains profile diagnostics and conditional native activation from v0.4.1.
// Resolve against the current image metadata and code; no game-build allowlist.
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <GameController/GameController.h>
#import <objc/message.h>
#import <objc/runtime.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <dlfcn.h>
#include <cstdlib>
#include <atomic>
#include <mutex>
#include <cstdio>
#include <cstring>
#include <cstdarg>
#include <set>
#include <unordered_map>
#include <string>
#include <vector>
#include <array>
#include "DynamicGame.h"
#include "MacPlatformPatch.h"
#include "NativeCursorBridge.h"
#include "NativeCursorPosition.h"
#include "HostCursorBridge.h"
#include "PartyUIResolver.h"
#include "PartyUILog.h"

// Enable only when rebuilding a diagnostic binary. All logging code remains
// in source; release builds neither evaluate log arguments nor open log files.
#ifndef NTE_ENABLE_LOGGING
#define NTE_ENABLE_LOGGING 0
#endif
static_assert(NTE_ENABLE_LOGGING==0 || NTE_ENABLE_LOGGING==1,"logging must be 0 or 1");
static constexpr bool kLoggingEnabled=NTE_ENABLE_LOGGING!=0;
#ifndef NTE_ENABLE_HARDWARE_OBSERVERS
#define NTE_ENABLE_HARDWARE_OBSERVERS 0
#endif
static constexpr bool kHardwareObservers=NTE_ENABLE_HARDWARE_OBSERVERS!=0;
static const char kPluginVersion[] __attribute__((used))="NTEDesktopMode 0.6.4";

static uintptr_t gBase;
static DynamicGame::Resolved gGame;
static PartyUI::Layout gPartyLayout;
static uintptr_t gImageSpan;
static FILE *gLog;
static std::mutex gLogLock;
static bool gObserveOnly;
static bool gRestoreNativePointer=true;
static bool gRepairNativeCursorPlatform=true;
static std::atomic<uintptr_t> gNativeApplication{0},gNativeCursor{0};
static std::atomic<uint32_t> gNativeCursorState{0};
static std::atomic<bool> gCursorRefreshQueued{false};
static std::atomic<unsigned long> gNativeTypeCalls{0},gNativeShowCalls{0};
static NativeCursor::Table gNativeCursorVTable;
static NativeCursor::PositionMailbox gNativePosition;
static std::atomic<uint64_t> gCursorEpoch{1};
static std::atomic<unsigned long> gHoverSamples{0},gPositionReads{0},gPositionOverrides{0};
static unsigned long gHostRefreshSerial=0; // main thread only
static void AttachNativePointerPositionObservers();
static void ScheduleNativeHostCursorRefresh();
static void QueueNativeCursorRefresh();
static BOOL NativePlatformPointerPreference(id object,SEL selector);
static bool gSpoofMacPlatform=true;
static bool gMacPlatformApplied=false;
static bool gUIPlatformApplied=false;
static unsigned long gLastMappingLog;
static std::set<uint64_t> gSeenControllers;
static std::atomic<bool> gQueued{false};
static std::atomic<bool> gNativeInputInitialized{false};
static std::atomic<unsigned long> gKeys{0}, gMoves{0}, gButtons{0}, gActivity{0}, gTicks{0};
static std::atomic<unsigned long> gKeyDown{0}, gKeyUp{0}, gButtonDown{0}, gButtonUp{0};
static unsigned long gLastActivity;
static dispatch_source_t gTimer;
static const void *kKeyWrapper = &kKeyWrapper, *kMoveWrapper = &kMoveWrapper;
static const void *kButtonWrapper = &kButtonWrapper;
static std::set<uint64_t> gSeenSubsystems;

static void WriteLog(const char *format, ...) {
    if (!kLoggingEnabled) return;
    std::lock_guard<std::mutex> lock(gLogLock);
    if (!gLog) return;
    fprintf(gLog, "[%.3f] ", CFAbsoluteTimeGetCurrent());
    va_list ap; va_start(ap, format); vfprintf(gLog, format, ap); va_end(ap);
    fputc('\n', gLog); fflush(gLog);
}
// The guard also prevents diagnostic-only arguments from being evaluated.
#define Log(...) do { if (kLoggingEnabled) WriteLog(__VA_ARGS__); } while (false)

static bool Read(uintptr_t p, void *out, size_t size) {
    vm_size_t copied = 0;
    return p && vm_read_overwrite(mach_task_self(), p, size,
        (vm_address_t)out, &copied) == KERN_SUCCESS && copied == size;
}
template<typename T> static bool ReadValue(uintptr_t p, T &out) { return Read(p, &out, sizeof(out)); }
static bool EqualBytes(uintptr_t p, const unsigned char *bytes, size_t size) {
    unsigned char actual[64];
    return size <= sizeof(actual) && Read(p, actual, size) && !memcmp(actual, bytes, size);
}
static bool IsHeapPointer(uintptr_t p) { return p >= 0x100000000ULL && p < 0x800000000000ULL && !(p & 7); }

static bool GuardMainImage() {
    const auto *header=_dyld_get_image_header(0);
    if (!header || header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64) return false;
    DynamicGame::Image image;
    if (!image.openFile(NSBundle.mainBundle.executablePath.fileSystemRepresentation)) return false;
    // Verify that the inspected file belongs to this running image. This compares
    // two observations of the current build; it is not a whitelist of old UUIDs.
    const load_command *cmd=(const load_command *)((const uint8_t *)header+sizeof(mach_header_64));
    bool sameImage=false;
    for (uint32_t i=0;i<header->ncmds;++i) {
        if (cmd->cmdsize<sizeof(load_command)) return false;
        if (cmd->cmd==LC_UUID) {
            uint8_t actual[16];memcpy(actual,((const uuid_command*)cmd)->uuid,16);
            // Compare canonical text with the file parser's observed UUID.
            char value[40];snprintf(value,sizeof(value),"%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",actual[0],actual[1],actual[2],actual[3],actual[4],actual[5],actual[6],actual[7],actual[8],actual[9],actual[10],actual[11],actual[12],actual[13],actual[14],actual[15]);
            sameImage=image.uuid==value;
        }
        cmd=(const load_command*)((const uint8_t*)cmd+cmd->cmdsize);
    }
    if (!sameImage) return false;
    gBase=(uintptr_t)header;gGame=DynamicGame::Resolve(image);
    for (auto &segment:image.segments) gImageSpan=std::max<uintptr_t>(gImageSpan,segment.va-image.base+segment.size);
    if (!gGame.platform || !gGame.objc || !gGame.cursor || !gGame.input) {Log("dynamic resolution incomplete: %s",gGame.reason.c_str());gBase=0;return false;}
    for (size_t i=0;i<5;++i) {
        MacPlatform::kQueries[i].offset=gGame.queries[i];
        MacPlatform::kQueries[i].original=i==0?gGame.commonIOS:(i==4?1:0);
        MacPlatform::kQueries[i].desktop=i==0?gGame.commonMac:((i==2||i==3)?1:0);
    }
    MacPlatform::kUIQueries[0]={"NativeUIPlatform",gGame.uiQuery,gGame.uiIOS,gGame.uiMac};
    NativeCursor::kCursorVTable=gGame.CursorTable;
    for(size_t i=0;i<NativeCursor::kSlots;++i) NativeCursor::kFunctions[i]=gGame.CursorFunctions[i];
    NativeCursor::kGetPositionSlot=gGame.CursorPositionSlot;
    NativeCursor::kSetTypeSlot=gGame.CursorTypeSlot;NativeCursor::kShowSlot=gGame.CursorShowSlot;
    NativeCursor::kTypeField=gGame.CursorTypeField;NativeCursor::kShownField=gGame.CursorShownField;
    // File metadata may be correct while an in-process competitor has changed
    // an operation. Validate each located operation against the current file.
    for (const auto &query:MacPlatform::kQueries) {
        unsigned char body[8];uint64_t p=image.file(query.offset);
        for(size_t i=0;i<8;++i)body[i]=image.get<uint8_t>(p+i);
        if(!EqualBytes(gBase+query.offset,body,8))return false;
    }
    const auto &ui=MacPlatform::kUIQueries[0];uint32_t words[]={MacPlatform::ReturnValue(ui.original),MacPlatform::kRet};
    if(!EqualBytes(gBase+ui.offset,(unsigned char*)words,8))return false;
    std::vector<uint64_t> calls={gGame.ApplicationGetter,gGame.ViewSize,gGame.PointerPreference,gGame.GameTask,gGame.HandleTouches,gGame.CommonSettings,gGame.CommonSupport,gGame.CommonRecalculate,gGame.CommonLocked};
    if(gGame.profiles) calls.insert(calls.end(),{gGame.InputPlatformSettings,gGame.InputRebuild,gGame.ProfileSetter,gGame.ProfileLookup,gGame.PlayerInputGetter,gGame.UserSettingsGetter});
    calls.insert(calls.end(),{gGame.CursorFunctions[gGame.CursorTypeSlot],gGame.CursorFunctions[gGame.CursorShowSlot],gGame.CursorFunctions[gGame.CursorPositionSlot]});
    for(auto rel:calls){unsigned char expected[32];uint64_t f=image.file(rel);for(size_t i=0;i<sizeof(expected);++i)expected[i]=image.get<uint8_t>(f+i);if(!EqualBytes(gBase+rel,expected,sizeof(expected)))return false;}
    gPartyLayout=PartyUI::Resolve(image);
    if(gPartyLayout.ready)for(const auto &entry:gPartyLayout.signatures)
        if(!EqualBytes(gBase+entry.first,entry.second.data(),entry.second.size()))gPartyLayout.ready=false;
    PartyNote("party_ui resolve ready=%d pc=%x mobile=%x container=%x refresh=%llx child_at=%llx clear_virtual=%x",gPartyLayout.ready,
        gPartyLayout.pc,gPartyLayout.mobile,gPartyLayout.container,gPartyLayout.refresh,gPartyLayout.childAt,gPartyLayout.clearVirtual);
    Log("dynamic capabilities platform=%d objc=%d cursor=%d input=%d profiles=%d",gGame.platform,gGame.objc,gGame.cursor,gGame.input,gGame.profiles);
    return true;
}

// Invoked synchronously in the dylib constructor, before the first 10-second timer.
static void LogMacPlatformState(const char *phase) {
    MacPlatform::State state;
    if (!MacPlatform::Inspect(gBase,state)) {
        Log("mac_platform phase=%s applied=%d query_bodies_verified=0",phase,gMacPlatformApplied); return;
    }
    Log("mac_platform phase=%s applied=%d platform=%u pc=%u mac=%u desktop=%u mobile=%u query_bodies_verified=1",
        phase,gMacPlatformApplied,state.values[0],state.values[1],state.values[2],state.values[3],state.values[4]);
}
static void ConfigureMacPlatform() {
    LogMacPlatformState("before");
    if (gObserveOnly || !gSpoofMacPlatform) {
        Log("mac_platform skipped observe=%d enabled=%d",gObserveOnly,gSpoofMacPlatform); return;
    }
    MacPlatform::Result result=MacPlatform::Apply(gBase);
    gMacPlatformApplied=result.applied;
    Log("mac_platform patch applied=%d stage=%s error=%d page_size=%zu rollback_attempted=%d rollback_succeeded=%d rollback_error=%d",
        result.applied,result.stage,result.error,result.pageSize,result.rollbackAttempted,result.rollbackSucceeded,result.rollbackError);
    LogMacPlatformState("after");
}

// EHTPlatformType is a separate enum from EHTCommonPlatformType above.
// This query feeds native UI template selection, setting data and cursor policy.
static void LogUIPlatformState(const char *phase) {
    uint32_t value=0;
    if (!MacPlatform::InspectUI(gBase,value)) {
        Log("native_ui_platform phase=%s applied=%d query_verified=0",phase,gUIPlatformApplied); return;
    }
    const bool mobileTemplate=value<=8 && ((1u<<value)&0x10c)!=0;
    const bool desktopCursor=value<=5 && ((1u<<value)&0x32)!=0;
    Log("native_ui_platform phase=%s applied=%d enum=EHTPlatformType value=%u mac=%d mobile_template_platform=%d desktop_cursor_platform=%d query_verified=1",
        phase,gUIPlatformApplied,value,value==4,mobileTemplate,desktopCursor);
}
static void ConfigureUIPlatform() {
    LogUIPlatformState("before");
    if (gObserveOnly || !gSpoofMacPlatform) {
        Log("native_ui_platform skipped observe=%d enabled=%d",gObserveOnly,gSpoofMacPlatform); return;
    }
    MacPlatform::Result result=MacPlatform::ApplyUI(gBase);
    gUIPlatformApplied=result.applied;
    Log("native_ui_platform patch applied=%d stage=%s error=%d page_size=%zu rollback_attempted=%d rollback_succeeded=%d rollback_error=%d",
        result.applied,result.stage,result.error,result.pageSize,result.rollbackAttempted,result.rollbackSucceeded,result.rollbackError);
    LogUIPlatformState("after");
}

// Observe hardware events while forwarding the game's original callbacks unchanged.
// Log only named Option/Escape control transitions; never characters, coordinates or typed text.
static uintptr_t BlockInvoke(id block);
static void ObserveButton(GCControllerButtonInput *button, const char *label) {
    if (!button) return;
    GCControllerButtonValueChangedHandler current = button.pressedChangedHandler;
    id ours = objc_getAssociatedObject(button, kButtonWrapper);
    if (ours && current == ours) return;
    GCControllerButtonValueChangedHandler wrapped = ^(GCControllerButtonInput *b, float v, BOOL pressed) {
        unsigned long event = gButtons.fetch_add(1) + 1; gActivity.fetch_add(1);
        if (pressed) gButtonDown.fetch_add(1); else gButtonUp.fetch_add(1);
        if (event <= 32) Log("mouse button=%s state=%s polled=%d forwarded=%d",label,pressed?"down":"up",b.isPressed,current!=nil);
        if (current) current(b, v, pressed);
    };
    button.pressedChangedHandler = wrapped;
    objc_setAssociatedObject(button, kButtonWrapper, wrapped, OBJC_ASSOCIATION_COPY_NONATOMIC);
    Log("mouse button observer=%s previous_handler=%d game_invoke_offset=0x%lx", label,current != nil,(unsigned long)BlockInvoke(current));
}
static uintptr_t BlockInvoke(id block) {
    uintptr_t invoke = 0;
    if (block) ReadValue((uintptr_t)(__bridge void *)block + 16, invoke);
    return invoke >= gBase && invoke < gBase + gImageSpan ? invoke - gBase : 0;
}
static void AttachObservers() {
    // Release builds let GameController deliver every native hardware event
    // directly to the game. Diagnostic wrappers are opt-in developer tooling.
    if(!kLoggingEnabled || !kHardwareObservers)return;
    GCKeyboardInput *keyboard = GCKeyboard.coalescedKeyboard.keyboardInput;
    if (keyboard) {
        GCKeyboardValueChangedHandler current = keyboard.keyChangedHandler;
        id ours = objc_getAssociatedObject(keyboard, kKeyWrapper);
        if (!(ours && current == ours)) {
            uintptr_t invoke = BlockInvoke(current);
            GCKeyboardValueChangedHandler wrapped = ^(GCKeyboardInput *k, GCControllerButtonInput *b, GCKeyCode code, BOOL pressed) {
                gKeys.fetch_add(1); gActivity.fetch_add(1);
                if (pressed) gKeyDown.fetch_add(1); else gKeyUp.fetch_add(1);
                if (current) current(k,b,code,pressed);
                const char *control=code==GCKeyCodeLeftAlt?"option_left":code==GCKeyCodeRightAlt?"option_right":code==GCKeyCodeEscape?"escape":nullptr;
                uint32_t cursorState=gNativeCursorState.load();
                if (control) Log("native_control key=%s state=%s forwarded=%d native_type=%u native_shown=%d show_seen=%d wants_lock=%d",
                    control,pressed?"down":"up",current!=nil,NativeCursor::Type(cursorState),
                    NativeCursor::Shown(cursorState),NativeCursor::ShowObserved(cursorState),
                    NativeCursor::WantsLock(cursorState));
            };
            keyboard.keyChangedHandler = wrapped;
            objc_setAssociatedObject(keyboard, kKeyWrapper, wrapped, OBJC_ASSOCIATION_COPY_NONATOMIC);
            Log("keyboard observer attached; previous_handler=%d game_invoke_offset=0x%lx", current!=nil, (unsigned long)invoke);
        }
    }
    for (GCMouse *mouse in GCMouse.mice) {
        GCMouseInput *input = mouse.mouseInput;
        if (!input) continue;
        GCMouseMoved current = input.mouseMovedHandler;
        id ours = objc_getAssociatedObject(input, kMoveWrapper);
        if (!(ours && current == ours)) {
            uintptr_t invoke = BlockInvoke(current);
            GCMouseMoved wrapped = ^(GCMouseInput *m, float x, float y) {
                gMoves.fetch_add(1); gActivity.fetch_add(1);
                if (current) current(m,x,y);
            };
            input.mouseMovedHandler = wrapped;
            objc_setAssociatedObject(input, kMoveWrapper, wrapped, OBJC_ASSOCIATION_COPY_NONATOMIC);
            Log("mouse observer attached; previous_handler=%d game_invoke_offset=0x%lx", current!=nil, (unsigned long)invoke);
        }
        ObserveButton(input.leftButton,"left"); ObserveButton(input.rightButton,"right"); ObserveButton(input.middleButton,"middle");
    }
}

// Verified class inheritance check matching UE's FStructBaseChain use in this binary.
static bool ClassIsA(uintptr_t candidate, uintptr_t base) {
    if (!IsHeapPointer(candidate) || !IsHeapPointer(base)) return false;
    if (candidate == base) return true;
    int32_t baseDepth=-1, candidateDepth=-1;
    uintptr_t chain=0, entry=0;
    return ReadValue(base+0x38,baseDepth) && baseDepth>=0 && baseDepth<256
        && ReadValue(candidate+0x38,candidateDepth) && candidateDepth>=baseDepth && candidateDepth<256
        && ReadValue(candidate+0x30,chain) && IsHeapPointer(chain)
        && ReadValue(chain+baseDepth*8,entry) && entry==base+0x30;
}

// Change only a method declared on this exact class. Never mutate an inherited
// UIViewController method, and never replace an IMP that changed since inspection.
static bool ReplaceOwnMethod(Class cls, SEL selector, IMP expected, IMP replacement) {
    if (!cls || !selector || !expected || !replacement) return false;
    unsigned count=0;
    Method *methods=class_copyMethodList(cls,&count);
    Method own=nullptr;
    for (unsigned i=0;i<count;++i) {
        if (method_getName(methods[i])==selector) { own=methods[i]; break; }
    }
    free(methods);
    if (!own || method_getImplementation(own)!=expected || method_getNumberOfArguments(own)!=2) return false;
    char *type=method_copyReturnType(own);
    bool booleanReturn=type && (!strcmp(type,"B") || !strcmp(type,"c"));
    free(type);
    if (!booleanReturn) return false;
    method_setImplementation(own,replacement);
    return method_getImplementation(own)==replacement;
}
// Framework bundles can expose either the direct executable path or a versioned
// executable path. Match whole components and the final basename, not a prefix.
static bool IsPlayToolsImagePath(const char *path) {
    if (!path || path[0]!='/') return false;
    const char *component=strstr(path,"/PlayTools.framework/");
    if (!component) return false;
    const char *tail=component+strlen("/PlayTools.framework/");
    if (!strcmp(tail,"PlayTools")) return true;
    const char *versions="Versions/";
    if (strncmp(tail,versions,strlen(versions))) return false;
    const char *version=tail+strlen(versions);
    const char *slash=strchr(version,'/');
    return slash && slash!=version && strncmp(version,"./",2) && strncmp(version,"../",3)
        && !strcmp(slash,"/PlayTools");
}
static bool NativePointerPreferenceBodyVerified() {
    if (!gGame.PointerPreference) return false;
    // The original method is a BOOL getter. Validate its constant YES return
    // within its bounded body; its position need not equal an old +0x34 offset.
    uint32_t words[24]={};
    if (!Read(gBase+gGame.PointerPreference,words,sizeof(words))) return false;
    for (size_t i=0;i+1<24;++i) {
        if(words[i]==0x52800020 && words[i+1]==0xd65f03c0)return true;
        if(words[i]==0xd65f03c0)return false;
    }
    return false;
}
static void RestoreNativePointerPreference() {
    if (![NSThread isMainThread]) return;
    Class cls=NSClassFromString(@"IOSViewController");
    SEL selector=@selector(prefersPointerLocked);
    Method method=cls ? class_getInstanceMethod(cls,selector) : nullptr;
    if (!method) return; // Game class may not be registered yet.
    IMP current=method_getImplementation(method);
    static IMP lastInspected=nullptr;
    if (current==lastInspected) return;
    lastInspected=current;
    IMP original=(IMP)(gBase+gGame.PointerPreference);
    if (current==(IMP)NativePlatformPointerPreference) return;
    if (current==original) { Log("pointer preference already native game implementation"); return; }
    Dl_info currentImage={}, originalImage={};
    bool ownerKnown=dladdr((const void *)current,&currentImage) && currentImage.dli_fname;
    bool gameKnown=dladdr((const void *)original,&originalImage) && originalImage.dli_fbase==(void *)gBase;
    const unsigned char returnsNo[]={0x00,0x00,0x80,0x52,0xc0,0x03,0x5f,0xd6};
    bool ownerMatches=ownerKnown && IsPlayToolsImagePath(currentImage.dli_fname);
    bool stubMatches=EqualBytes((uintptr_t)current,returnsNo,sizeof(returnsNo));
    bool knownOverride=ownerMatches && stubMatches;
    bool gameReturnOK=gameKnown && NativePointerPreferenceBodyVerified();
    Log("pointer preference owner=%s owner_matches=%d stub_matches=%d known_playtools_no=%d game_original_verified=%d",
        ownerKnown?currentImage.dli_fname:"unknown",ownerMatches,stubMatches,knownOverride,gameReturnOK);
    if (!knownOverride || !gameReturnOK) { Log("pointer preference unchanged: implementation guard rejected"); return; }
    if (gObserveOnly || !gRestoreNativePointer) { Log("pointer preference unchanged: configuration disabled restore"); return; }
    if (ReplaceOwnMethod(cls,selector,current,original)) {
        lastInspected=original;
        Log("pointer preference restored to game original; no capture request or cursor manipulation");
    } else Log("pointer preference unchanged: own-method guard rejected");
}

// The input platform remains iOS/Mac Catalyst even after the game's two platform
// queries select desktop. Its real FIOSCursor setters only store fields. Bridge
// those native setter events to UIKit; do not synthesize Option/menu actions.
static bool NativeCursorRepairEnabled() {
    return !gObserveOnly && gRestoreNativePointer && gRepairNativeCursorPlatform;
}
static BOOL NativePlatformPointerPreference(id object,SEL selector) {
    if (!NativeCursorRepairEnabled() || !gNativeCursor.load())
        return ((BOOL(*)(id,SEL))(gBase+gGame.PointerPreference))(object,selector);
    return NativeCursor::WantsLock(gNativeCursorState.load()) ? YES : NO;
}
static bool InstallNativeCursorPreference(Class cls,SEL selector,IMP original) {
    if (!NativeCursorRepairEnabled() || !gNativeCursor.load() || !NativeCursor::Ready(gNativeCursorState.load())) return false;
    Method method=cls?class_getInstanceMethod(cls,selector):nullptr;
    if (!method) return false;
    IMP current=method_getImplementation(method);
    if (current==(IMP)NativePlatformPointerPreference) return true;
    return current==original && ReplaceOwnMethod(cls,selector,original,(IMP)NativePlatformPointerPreference);
}
static void CaptureNativeApplication() {
    if (![NSThread isMainThread] || !NativeCursorRepairEnabled()) return;
    id delegate=UIApplication.sharedApplication.delegate;
    SEL selector=sel_registerName("IOSApplication");
    Method method=delegate?class_getInstanceMethod(object_getClass(delegate),selector):nullptr;
    if (!method || (uintptr_t)method_getImplementation(method)!=gBase+gGame.ApplicationGetter) {
        static bool warned=false;
        if (!warned) { warned=true; Log("native_cursor application getter pending/rejected delegate=%s",delegate?class_getName(object_getClass(delegate)):"nil"); }
        return;
    }
    uintptr_t application=((uintptr_t(*)(id,SEL))objc_msgSend)(delegate,selector);
    uintptr_t vtable=0;
    if (IsHeapPointer(application) && ReadValue(application,vtable) && vtable>=gBase && vtable<gBase+gImageSpan) {
        if (gNativeApplication.exchange(application)!=application) Log("native_cursor application verified getter=IOSApplication cursor_shared_ptr_offset=0x8");
    }
}
static void PublishNativeCursorState(uintptr_t self,bool isType,uint32_t value) {
    if (self!=gNativeCursor.load()) return;
    if (isType && !NativeCursor::ValidType(value)) {
        static std::atomic<bool> warned{false};
        if (!warned.exchange(true)) Log("native_cursor GUARD rejected unknown type=%u; previous pointer preference retained",value);
        return;
    }
    uint32_t before=gNativeCursorState.load(),after=before;
    do {
        after=isType?NativeCursor::WithType(before,value):NativeCursor::WithShow(before,value!=0);
        if (after==before) return;
    } while (!gNativeCursorState.compare_exchange_weak(before,after));
    if (NativeCursor::WantsLock(before)!=NativeCursor::WantsLock(after)) {
        gCursorEpoch.fetch_add(1);
        gNativePosition.Invalidate();
    }
    Log("native_cursor event=%s value=%u type=%u shown=%d show_seen=%d wants_lock=%d previous_wants_lock=%d type_calls=%lu show_calls=%lu",
        isType?"SetType":"Show",value,NativeCursor::Type(after),NativeCursor::Shown(after),NativeCursor::ShowObserved(after),
        NativeCursor::WantsLock(after),NativeCursor::WantsLock(before),gNativeTypeCalls.load(),gNativeShowCalls.load());
    QueueNativeCursorRefresh();
}
static void NativeCursorSetType(uintptr_t self,uint32_t type) {
    ((void(*)(uintptr_t,uint32_t))(gBase+NativeCursor::kFunctions[NativeCursor::kSetTypeSlot]))(self,type);
    gNativeTypeCalls.fetch_add(1);
    PublishNativeCursorState(self,true,type);
}
static NativeCursor::Position NativeCursorGetPosition(uintptr_t self) {
    NativeCursor::Position original=((NativeCursor::Position(*)(uintptr_t))(gBase+NativeCursor::kFunctions[NativeCursor::kGetPositionSlot]))(self);
    if (self!=gNativeCursor.load() || !NativeCursorRepairEnabled()) return original;
    gPositionReads.fetch_add(1,std::memory_order_relaxed);
    NativeCursor::Position absolute;
    uint64_t epoch=gCursorEpoch.load();
    if (!NativeCursor::WantsLock(gNativeCursorState.load()) && gNativePosition.Read(epoch,absolute)
        && epoch==gCursorEpoch.load() && !NativeCursor::WantsLock(gNativeCursorState.load())) {
        gPositionOverrides.fetch_add(1,std::memory_order_relaxed);
        return absolute;
    }
    return original;
}
static void NativeCursorShow(uintptr_t self,bool shown) {
    ((void(*)(uintptr_t,bool))(gBase+NativeCursor::kFunctions[NativeCursor::kShowSlot]))(self,shown);
    gNativeShowCalls.fetch_add(1);
    PublishNativeCursorState(self,false,shown);
}
// Testable installation primitive: caller supplies a verified table. No executable
// bytes or shared engine vtable pages are modified; this one object owns the clone.
static bool AttachNativeCursor(uintptr_t cursor,const NativeCursor::Table &original,
                               const std::array<uintptr_t,NativeCursor::kSlots> &expected) {
    if (!NativeCursorRepairEnabled() || !IsHeapPointer(cursor)) return false;
    uintptr_t vtable=0;
    if (!ReadValue(cursor,vtable)) return false;
    if (cursor==gNativeCursor.load()) return vtable==(uintptr_t)(gNativeCursorVTable.data()+NativeCursor::kHeaderWords);
    // The application owns one cursor until shutdown. Do not replace a later,
    // unverified object's vptr or invalidate a previous clone on scene changes.
    if (gNativeCursor.load() || vtable!=gBase+NativeCursor::kCursorVTable) return false;
    uint32_t type=0; uint8_t shown=0;
    if (!ReadValue(cursor+NativeCursor::kTypeField,type) || !NativeCursor::ValidType(type) || !ReadValue(cursor+NativeCursor::kShownField,shown) || shown>1) return false;
    if (!NativeCursor::BuildTable(original,expected,(uintptr_t)NativeCursorSetType,(uintptr_t)NativeCursorShow,gNativeCursorVTable,(uintptr_t)NativeCursorGetPosition)) return false;
    gNativeCursorState.store(NativeCursor::InitialState(type,shown));
    gNativeCursor.store(cursor);
    uintptr_t expectedVTable=gBase+NativeCursor::kCursorVTable;
    uintptr_t replacement=(uintptr_t)(gNativeCursorVTable.data()+NativeCursor::kHeaderWords);
    if (!__atomic_compare_exchange_n((uintptr_t *)cursor,&expectedVTable,replacement,false,__ATOMIC_SEQ_CST,__ATOMIC_SEQ_CST)) {
        gNativeCursor.store(0); gNativeCursorState.store(0); return false;
    }
    Log("native_cursor adapter attached type=%u shown=%u show_seen=0 wants_lock=%d slots_verified=%zu scope=one_FIOSCursor setters_forwarded=1",
        type,shown,NativeCursor::WantsLock(gNativeCursorState.load()),NativeCursor::kSlots);
    QueueNativeCursorRefresh();
    return true;
}
static void AttachNativeCursorAdapter() {
    if (!NativeCursorRepairEnabled() || [NSThread isMainThread]) return;
    uintptr_t application=gNativeApplication.load(),appVTable=0,cursor=0;
    if (!IsHeapPointer(application) || !ReadValue(application,appVTable) || (appVTable<gBase || appVTable>=gBase+gImageSpan)
        || !ReadValue(application+8,cursor) || !IsHeapPointer(cursor)) return;
    if (gNativeCursor.load()==cursor) return;
    NativeCursor::Table original={};
    if (!Read(gBase+NativeCursor::kCursorVTable-16,original.data(),sizeof(original))) return;
    std::array<uintptr_t,NativeCursor::kSlots> expected={};
    for (size_t i=0;i<expected.size();++i) expected[i]=gBase+NativeCursor::kFunctions[i];
    if (!AttachNativeCursor(cursor,original,expected)) {
        static bool warned=false;
        if (!warned) { warned=true; Log("native_cursor adapter rejected: object/table/state guard; native pointer preference retained"); }
    }
}

static bool LiveObjectOfClass(uintptr_t object, uintptr_t expectedClass) {
    uintptr_t cls=0; uint32_t flags=0;
    return IsHeapPointer(object) && IsHeapPointer(expectedClass)
        && ReadValue(object+8,flags) && !(flags&(0x10|0x8000|0x10000))
        && ReadValue(object+0x10,cls) && ClassIsA(cls,expectedClass);
}
// Build-specific FName layout is verified by the native decoder signatures.
// Names here come from compiled mapping assets, never hardware input events.
struct MappingName { uint32_t id, number; };
static bool DecodeMappingName(uintptr_t blockTable, MappingName name, std::string &out) {
    out.clear();
    if (!IsHeapPointer(blockTable)) return false;
    uintptr_t block=0;
    if (!ReadValue(blockTable+((uintptr_t)(name.id>>16))*8,block) || !IsHeapPointer(block)) return false;
    uintptr_t entry=block+(name.id&0xffff)*2;
    uint16_t header=0;
    if (!ReadValue(entry,header)) return false;
    unsigned length=header>>6;
    if (!length || length>128) return false;
    uint16_t wide[128]={};
    unsigned char narrow[128]={};
    bool isWide=header&1;
    if (isWide ? !Read(entry+2,wide,length*2) : !Read(entry+2,narrow,length)) return false;
    std::string decoded;
    for (unsigned i=0;i<length;++i) {
        unsigned ch=isWide?wide[i]:narrow[i];
        // Only printable ASCII names enter the log, preventing multiline output.
        if (ch<32 || ch>126) return false;
        decoded.push_back((char)ch);
    }
    if (name.number) decoded+="_"+std::to_string(name.number-1);
    out=std::move(decoded);
    return true;
}
static bool ObjectMappingName(uintptr_t table,uintptr_t object,std::string &out) {
    MappingName name={};
    return IsHeapPointer(object) && ReadValue(object+0x18,name) && DecodeMappingName(table,name,out);
}
struct MappingArrayHeader { uintptr_t data; int32_t count, capacity; };
using MappingRow=std::array<unsigned char,0x50>;
static bool SnapshotMappings(uintptr_t array,std::vector<MappingRow> &rows) {
    rows.clear();
    MappingArrayHeader header={};
    if (!ReadValue(array,header) || header.count<0 || header.count>4096
        || header.capacity<header.count || header.capacity>1000000) return false;
    if (!header.count) return true;
    if (!IsHeapPointer(header.data)) return false;
    std::vector<MappingRow> snapshot(header.count);
    if (!Read(header.data,snapshot.data(),snapshot.size()*sizeof(MappingRow))) return false;
    rows=std::move(snapshot);
    return true;
}
struct MappingLogState { uint64_t fingerprint=0; bool logged=false; };
static std::unordered_map<uint64_t,std::array<MappingLogState,2>> gMappingDetails;
static void LogMappingRows(uint64_t identity,int32_t index,bool active,uintptr_t array) {
    std::vector<MappingRow> rows;
    if (!SnapshotMappings(array,rows)) {
        Log("mapping_detail controller=%d source=%s snapshot=unavailable",index,active?"active":"authored");
        return;
    }
    uint64_t fingerprint=14695981039346656037ULL;
    // Action pointer and FKey FName determine the diagnostic rows. Ignore array
    // allocations, padding, trigger state and cached key metadata.
    for (const auto &row:rows) for (unsigned i=0x20;i<0x30;++i) {
        fingerprint^=row[i]; fingerprint*=1099511628211ULL;
    }
    fingerprint^=rows.size();
    auto &state=gMappingDetails[identity][active?1:0];
    if (state.logged && state.fingerprint==fingerprint) return;
    state={fingerprint,true};
    uintptr_t table=gBase+gGame.NamePool;
    const char *source=active?"active":"authored";
    const char *targets[]={"W","A","S","D","MouseX","MouseY","LeftMouseButton","RightMouseButton"};
    unsigned presence[8]={}, decodedKeys=0, decodedActions=0, loggedRows=0;
    for (size_t i=0;i<rows.size();++i) {
        uintptr_t action=0; MappingName keyName={};
        memcpy(&action,rows[i].data()+0x20,sizeof(action));
        memcpy(&keyName,rows[i].data()+0x28,sizeof(keyName));
        std::string key,actionName;
        bool keyOK=DecodeMappingName(table,keyName,key);
        bool actionOK=ObjectMappingName(table,action,actionName);
        decodedKeys+=keyOK; decodedActions+=actionOK;
        if (keyOK) for (unsigned j=0;j<8;++j) if (key==targets[j]) ++presence[j];
        if (i<128) {
            Log("mapping_row controller=%d source=%s row=%zu key=%s action=%s",index,source,i,
                keyOK?key.c_str():"<unreadable>",actionOK?actionName.c_str():"<unreadable>");
            ++loggedRows;
        }
    }
    Log("mapping_keys controller=%d source=%s count=%zu keys_decoded=%u actions_decoded=%u rows_logged=%u W=%u A=%u S=%u D=%u MouseX=%u MouseY=%u LeftMouseButton=%u RightMouseButton=%u",
        index,source,rows.size(),decodedKeys,decodedActions,loggedRows,presence[0],presence[1],presence[2],presence[3],presence[4],presence[5],presence[6],presence[7]);
}
static void LogMappingDetails(uint64_t identity,int32_t index,uintptr_t context,uintptr_t playerInput,
        bool validContext,bool enhanced,uintptr_t contextClass) {
    // Validate the shared pool against a known reflected class name first. Do
    // not mark rows as logged until this succeeds, so late initialization retries.
    std::string className;
    if (!ObjectMappingName(gBase+gGame.NamePool,contextClass,className) || className!="InputMappingContext") {
        static bool reported=false;
        if (!reported) { Log("mapping names unavailable: FName class-name validation pending or rejected"); reported=true; }
        return;
    }
    if (validContext) LogMappingRows(identity,index,false,context+0x30);
    if (enhanced) LogMappingRows(identity,index,true,playerInput+0x5d8);
}
// Read only. A missing mapping is evidence for the next investigation, not a
// reason to call SetupInputComponent again or to invent gameplay bindings.
static void LogControllerMappings(uint8_t *object, int32_t index, uint32_t serial,
        unsigned long tick, uintptr_t enhancedClass, uintptr_t contextClass) {
    bool first=gSeenControllers.insert(((uint64_t)serial<<32)|(uint32_t)index).second;
    bool changedActivity=gActivity.load()!=gLastMappingLog;
    if (!first && tick%5!=0 && !changedActivity) return;
    uintptr_t component=0, playerInput=0, context=0, turn=0, look=0, left=0, right=0, upW=0, upS=0;
    uint8_t initFlags[2]={};
    uint16_t cursorFlags=0;
    uintptr_t p=(uintptr_t)object;
    bool readable=ReadValue(p+0x180,component) && ReadValue(p+0x440,playerInput)
        && ReadValue(p+gGame.DefaultMappingContext,context) && Read(p+0x19f0,initFlags,2)
        && ReadValue(p+0x8a8,turn) && ReadValue(p+0x8b0,look)
        && ReadValue(p+0x900,left) && ReadValue(p+0x908,right)
        && ReadValue(p+0x938,upW) && ReadValue(p+0x940,upS);
    if (!readable) { Log("controller index=%d mapping layout unreadable",index); return; }
    bool enhanced=LiveObjectOfClass(playerInput,enhancedClass);
    bool validContext=LiveObjectOfClass(context,contextClass);
    int32_t authoredMappings=-1, activeMappings=-1;
    if (validContext) ReadValue(context+0x38,authoredMappings); // TArray<FEnhancedActionKeyMapping> +0x30
    if (enhanced) ReadValue(playerInput+0x5e0,activeMappings); // EnhancedActionMappings +0x5d8
    if (authoredMappings<0 || authoredMappings>100000) authoredMappings=-1;
    if (activeMappings<0 || activeMappings>100000) activeMappings=-1;
    bool cursorFlagsReadable=ReadValue(p+0x56c,cursorFlags);
    Log("controller index=%d native_cursor_readable=%d native_show_cursor=%d input_component=%d player_input=%d enhanced=%d default_context=%d context_valid=%d authored_mappings=%d active_mappings=%d init_byte_19f0=%u init_byte_19f1=%u actions_turn=%d look=%d left=%d right=%d stand_w=%d stand_s=%d",
        index,cursorFlagsReadable,(cursorFlags&1)!=0,component!=0,playerInput!=0,enhanced,context!=0,validContext,authoredMappings,activeMappings,
        initFlags[0],initFlags[1],turn!=0,look!=0,left!=0,right!=0,upW!=0,upS!=0);
    LogMappingDetails(((uint64_t)serial<<32)|(uint32_t)index,index,context,playerInput,validContext,enhanced,contextClass);
}

// TSparseArray/TMap layout from the supported engine's map-copy and redirect loop.
// Only allocated slots enter snapshots; never treat free-list storage as UObjects.
struct ContextMapRow { uintptr_t address, key; uint64_t value; };
static bool SnapshotContextMap(uintptr_t map,std::vector<ContextMapRow> &rows) {
    rows.clear();
    unsigned char header[0x50]={};
    if (!Read(map,header,sizeof(header))) return false;
    uintptr_t data=0,externalBits=0; int32_t count=0,capacity=0,bits=0,maxBits=0,freeCount=0;
    memcpy(&data,header,8); memcpy(&count,header+8,4); memcpy(&capacity,header+12,4);
    memcpy(&externalBits,header+0x20,8); memcpy(&bits,header+0x28,4);
    memcpy(&maxBits,header+0x2c,4); memcpy(&freeCount,header+0x34,4);
    if (count<0 || count>4096 || capacity<count || capacity>1000000 || bits!=count
        || maxBits<bits || maxBits>1000000 || freeCount<0 || freeCount>count) return false;
    if (!count) return true;
    if (!IsHeapPointer(data) || (externalBits && !IsHeapPointer(externalBits))
        || (!externalBits && bits>128)) return false;
    std::vector<uint32_t> flags((bits+31)/32);
    if (!Read(externalBits?externalBits:map+0x10,flags.data(),flags.size()*4)) return false;
    std::vector<std::array<unsigned char,24>> entries(count);
    if (!Read(data,entries.data(),entries.size()*24)) return false;
    std::vector<ContextMapRow> snapshot;
    for (int32_t i=0;i<count;++i) if (flags[i/32]&(uint32_t(1)<<(i%32))) {
        ContextMapRow row={data+(uintptr_t)i*24,0,0};
        memcpy(&row.key,entries[i].data(),8); memcpy(&row.value,entries[i].data()+8,8);
        snapshot.push_back(row);
    }
    if (snapshot.size()!=(size_t)(count-freeCount)) return false;
    rows=std::move(snapshot); return true;
}
struct BindingCoverage {
    bool decoded=false; unsigned mask=0;
    std::set<std::pair<std::string,std::string>> pairs;
};
static BindingCoverage InspectBindings(uintptr_t table,const std::vector<MappingRow> &rows) {
    BindingCoverage coverage; coverage.decoded=true;
    const char *keys[]={"W","A","S","D","MouseX","MouseY"};
    const char *actions[]={"IA_Move","IA_Move","IA_Move","IA_Move","IA_Turn","IA_LookUp"};
    for (const auto &row:rows) {
        uintptr_t action=0; MappingName name={}; std::string key,actionName;
        memcpy(&action,row.data()+0x20,8); memcpy(&name,row.data()+0x28,8);
        if (!DecodeMappingName(table,name,key) || !ObjectMappingName(table,action,actionName)) {
            coverage.decoded=false; continue;
        }
        coverage.pairs.emplace(key,actionName);
        for (unsigned i=0;i<6;++i) if (key==keys[i] && actionName==actions[i]) coverage.mask|=1u<<i;
    }
    return coverage;
}
static bool IsKeyboardRedirectCandidate(const BindingCoverage &source,const BindingCoverage &target,
        const BindingCoverage &active,bool registered) {
    if (!registered || !source.decoded || !target.decoded || !active.decoded
        || source.mask!=0x3f || target.mask || active.mask || target.pairs.size()<4) return false;
    // Confirm that the candidate destination is actually represented in current input.
    for (const auto &pair:target.pairs) if (!active.pairs.count(pair)) return false;
    return true;
}
static bool ObjectOfClassIncludingDefault(uintptr_t object,uintptr_t expected) {
    uint32_t flags=0; uintptr_t cls=0;
    return IsHeapPointer(object) && IsHeapPointer(expected) && ReadValue(object+8,flags)
        && !(flags&(0x8000|0x10000)) && ReadValue(object+0x10,cls) && ClassIsA(cls,expected);
}
static const char *AssetName(uintptr_t object,std::string &storage) {
    return ObjectMappingName(gBase+gGame.NamePool,object,storage)?storage.c_str():"<unreadable>";
}
static bool ReplaceRedirectDestination(const ContextMapRow &row,uintptr_t source) {
    // Changing a value preserves hashing, context priority and registration counts.
    // The source is already a UObject reference in this very same reflected map.
    uintptr_t key=0,destination=0;
    if (row.key!=source || row.value==source || !IsHeapPointer(source)
        || !ReadValue(row.address,key) || key!=source
        || !ReadValue(row.address+8,destination) || destination!=row.value) return false;
    vm_size_t copied=sizeof(source);
    return mach_vm_write(mach_task_self(),row.address+8,(vm_offset_t)&source,(mach_msg_type_number_t)copied)==KERN_SUCCESS;
}
// FString profile identifiers in this build are UTF-16, with a terminating NUL
// included in Num. Restrict diagnostics/activation to bounded ASCII identifiers.
static bool ReadProfileId(uintptr_t address,std::string &result) {
    result.clear(); MappingArrayHeader value={};
    if (!ReadValue(address,value) || value.count<0 || value.count>256
        || value.capacity<value.count || value.capacity>4096) return false;
    if (!value.count) return true;
    if (!IsHeapPointer(value.data)) return false;
    std::vector<uint16_t> text(value.count);
    if (!Read(value.data,text.data(),text.size()*2) || text.back()!=0) return false;
    std::string decoded;
    for (int32_t i=0;i<value.count-1;++i) {
        if (text[i]<0x20 || text[i]>0x7e) return false;
        decoded.push_back((char)text[i]);
    }
    result=std::move(decoded); return true;
}
static bool ProfileIdsEqual(const std::string &a,const std::string &b) {
    if (a.size()!=b.size()) return false;
    for (size_t i=0;i<a.size();++i) {
        auto fold=[](unsigned char c){return c>='A'&&c<='Z'?c+('a'-'A'):c;};
        if (fold(a[i])!=fold(b[i])) return false;
    }
    return true;
}
static bool ReadSupportedProfiles(uintptr_t settings,std::vector<std::string> &ids) {
    ids.clear(); MappingArrayHeader list={};
    if (!ReadValue(settings+0x78,list) || list.count<0 || list.count>32
        || list.capacity<list.count || list.capacity>4096
        || (list.count && !IsHeapPointer(list.data))) return false;
    std::vector<std::string> snapshot;
    for (int32_t i=0;i<list.count;++i) {
        std::string id;
        if (!ReadProfileId(list.data+(uintptr_t)i*16,id)) return false;
        snapshot.push_back(id);
    }
    ids=std::move(snapshot); return true;
}
static bool ProfileAllows(const std::vector<std::string> &supported,const std::string &id,bool hasProfile) {
    if (!hasProfile || supported.empty()) return true;
    for (const auto &entry:supported) if (ProfileIdsEqual(entry,id)) return true;
    return false;
}
struct KeyProfileRow { uintptr_t idAddress,profile; std::string id; };
static bool SnapshotKeyProfiles(uintptr_t map,std::vector<KeyProfileRow> &rows,uintptr_t profileClass) {
    rows.clear(); unsigned char header[0x50]={};
    if (!Read(map,header,sizeof(header))) return false;
    uintptr_t data=0,external=0; int32_t count=0,capacity=0,bits=0,maxBits=0,free=0;
    memcpy(&data,header,8); memcpy(&count,header+8,4); memcpy(&capacity,header+12,4);
    memcpy(&external,header+0x20,8); memcpy(&bits,header+0x28,4);
    memcpy(&maxBits,header+0x2c,4); memcpy(&free,header+0x34,4);
    if (count<0 || count>128 || capacity<count || capacity>4096 || bits!=count
        || maxBits<bits || maxBits>4096 || free<0 || free>count
        || (!external && count>128) || (count && !IsHeapPointer(data))) return false;
    if (!count) return true;
    std::vector<uint32_t> flags((count+31)/32);
    if (!Read(external?external:map+0x10,flags.data(),flags.size()*4)) return false;
    std::vector<KeyProfileRow> snapshot;
    for (int32_t i=0;i<count;++i) if (flags[i/32]&(uint32_t(1)<<(i%32))) {
        KeyProfileRow row={data+(uintptr_t)i*32,0,{}}; std::string objectId;
        if (!ReadProfileId(row.idAddress,row.id) || row.id.empty()
            || !ReadValue(row.idAddress+16,row.profile) || !LiveObjectOfClass(row.profile,profileClass)
            || !ReadProfileId(row.profile+0x30,objectId) || !ProfileIdsEqual(row.id,objectId)) return false;
        for (const auto &other:snapshot) if (ProfileIdsEqual(other.id,row.id)) return false;
        snapshot.push_back(row);
    }
    if (snapshot.size()!=(size_t)(count-free)) return false;
    rows=std::move(snapshot); return true;
}
struct ProfileBindingGate { unsigned bit; std::string key,action; std::vector<std::string> supported; };
static bool InspectProfileGates(const std::vector<MappingRow> &rows,uintptr_t bindingSettingsClass,
        std::vector<ProfileBindingGate> &gates) {
    gates.clear(); unsigned mask=0;
    const char *keys[]={"W","A","S","D","MouseX","MouseY"};
    const char *actions[]={"IA_Move","IA_Move","IA_Move","IA_Move","IA_Turn","IA_LookUp"};
    for (const auto &row:rows) {
        MappingName name={}; uintptr_t action=0; std::string key,actionName;
        memcpy(&name,row.data()+0x28,8); memcpy(&action,row.data()+0x20,8);
        if (!DecodeMappingName(gBase+gGame.NamePool,name,key)
            || !ObjectMappingName(gBase+gGame.NamePool,action,actionName)) return false;
        unsigned bit=0;
        for (unsigned i=0;i<6;++i) if (key==keys[i] && actionName==actions[i]) bit=1u<<i;
        if (!bit) continue;
        ProfileBindingGate gate={bit,key,actionName,{}}; uintptr_t settings=0;
        uint8_t behavior=row[0x41];
        if (behavior==0) { if (!ReadValue(action+0x70,settings)) return false; }
        else if (behavior==1) memcpy(&settings,row.data()+0x48,8);
        else if (behavior!=2) return false;
        if (settings && (!ObjectOfClassIncludingDefault(settings,bindingSettingsClass)
            || !ReadSupportedProfiles(settings,gate.supported))) return false;
        mask|=bit; gates.push_back(std::move(gate));
    }
    return mask==0x3f;
}
static unsigned ProfileAllowedMask(const std::vector<ProfileBindingGate> &gates,
        const std::string &id,bool hasProfile) {
    unsigned mask=0;
    for (const auto &gate:gates) if (ProfileAllows(gate.supported,id,hasProfile)) mask|=gate.bit;
    return mask;
}
static bool IsKeyboardProfileCandidate(const BindingCoverage &source,const BindingCoverage &active,
        bool registered,size_t activeCount,bool hasProfile,unsigned currentAllowed,unsigned targetAllowed) {
    return registered && source.decoded && active.decoded && source.mask==0x3f
        && active.mask==0 && activeCount>=4 && hasProfile && currentAllowed==0 && targetAllowed==0x3f;
}
static bool ObjectSerial(uint32_t index,uintptr_t expected,uint32_t &serial) {
    uintptr_t chunks=0,chunk=0,object=0; int32_t count=0,chunkCount=0; uint32_t flags=0;
    if (!ReadValue(gBase+gGame.ObjectChunks,chunks) || !IsHeapPointer(chunks)
        || !ReadValue(gBase+gGame.ObjectCount,count) || count<=0 || count>10000000 || index>=(uint32_t)count
        || !ReadValue(gBase+gGame.ObjectChunkCount,chunkCount) || chunkCount<=0 || chunkCount>153
        || (index>>16)>=(uint32_t)chunkCount
        || !ReadValue(chunks+(index>>16)*8,chunk) || !IsHeapPointer(chunk)) return false;
    uintptr_t item=chunk+(index&65535)*24;
    return ReadValue(item,object) && object==expected && ReadValue(item+8,flags)
        && !(flags&0x30000000) && ReadValue(item+0x10,serial) && serial!=0;
}
static bool NativeProfileMethods(uintptr_t subsystem,uintptr_t settings,uintptr_t &lookup,uintptr_t &setter) {
    uintptr_t interfaceTable=0,userSettingsGetter=0,vtable=0,getter=0;
    return ReadValue(subsystem+0x30,interfaceTable)
        && ReadValue(interfaceTable+0x20,userSettingsGetter) && userSettingsGetter==gBase+gGame.UserSettingsGetter
        && ReadValue(settings,vtable)
        && ReadValue(vtable+0x348,getter) && getter==gBase+gGame.ProfileIdGetter
        && ReadValue(vtable+0x360,lookup) && lookup==gBase+gGame.ProfileLookup
        && ReadValue(vtable+0x338,setter) && setter==gBase+gGame.ProfileSetter;
}
static bool gRepairKeyboardProfile=true;
static void ProcessKeyProfile(uintptr_t subsystem,uint64_t controllerIdentity,int32_t index,
        const std::vector<MappingRow> &sourceRows,const BindingCoverage &source,
        const std::vector<MappingRow> &activeRows,const BindingCoverage &active,bool registered,unsigned long tick) {
    static std::unordered_map<uint64_t,std::string> lastStates;
    static std::unordered_map<uint64_t,unsigned long> pending;
    static std::set<uint64_t> attempted;
    auto waiting=pending.find(controllerIdentity);
    if (waiting!=pending.end() && ((active.decoded && active.mask==0x3f) || tick-waiting->second>=5)) {
        Log("keyboard_profile verification controller=%d active_axes_complete=%d decoded=%d active_mappings=%zu",
            index,active.decoded && active.mask==0x3f,active.decoded,activeRows.size()); pending.erase(waiting);
    }
    uintptr_t settings=0,settingsClass=0,profileClass=0,bindingClass=0;
    ReadValue(gBase+gGame.cls("EnhancedInputUserSettings"),settingsClass); ReadValue(gBase+gGame.cls("EnhancedPlayerMappableKeyProfile"),profileClass);
    ReadValue(gBase+gGame.cls("PlayerMappableKeySettings"),bindingClass);
    if (!ReadValue(subsystem+0x1b0,settings) || !LiveObjectOfClass(settings,settingsClass)) {
        if (tick%10==0) Log("key_profile controller=%d user_settings_unavailable=1",index);
        return;
    }
    uintptr_t lookup=0,setter=0;
    bool nativeMethods=NativeProfileMethods(subsystem,settings,lookup,setter);
    std::string current; std::vector<KeyProfileRow> profiles; std::vector<ProfileBindingGate> gates;
    bool idReadable=ReadProfileId(settings+0x78,current);
    bool mapReadable=SnapshotKeyProfiles(settings+0xd8,profiles,profileClass);
    bool gatesReadable=InspectProfileGates(sourceRows,bindingClass,gates);
    bool hasProfile=false;
    for (const auto &row:profiles) if (ProfileIdsEqual(row.id,current)) hasProfile=true;
    unsigned currentAllowed=gatesReadable?ProfileAllowedMask(gates,current,hasProfile):0;
    std::string state=current+":"+std::to_string(profiles.size())+":"+std::to_string(currentAllowed)
        +":"+std::to_string(active.mask)+":"+std::to_string(nativeMethods)+":"+std::to_string(idReadable)
        +":"+std::to_string(mapReadable)+":"+std::to_string(gatesReadable)+":"+std::to_string(hasProfile);
    bool report=lastStates[controllerIdentity]!=state || tick%10==0; lastStates[controllerIdentity]=state;
    if (report) {
        Log("key_profile controller=%d current=%s current_exists=%d profiles=%zu id_readable=%d map_readable=%d gates_readable=%d native_methods=%d current_allowed_mask=%02x repair_enabled=%d observe=%d",
            index,idReadable?current.c_str():"<unreadable>",hasProfile,profiles.size(),idReadable,mapReadable,
            gatesReadable,nativeMethods,currentAllowed,gRepairKeyboardProfile,gObserveOnly);
        for (const auto &row:profiles) Log("key_profile_available controller=%d id=%s allowed_axes_mask=%02x",
            index,row.id.c_str(),gatesReadable?ProfileAllowedMask(gates,row.id,true):0);
        for (const auto &gate:gates) {
            std::string ids;
            for (const auto &id:gate.supported) { if (!ids.empty()) ids+=","; ids+=id; }
            Log("key_profile_binding controller=%d key=%s action=%s supported=%s allowed_current=%d",
                index,gate.key.c_str(),gate.action.c_str(),ids.empty()?"<any>":ids.c_str(),
                ProfileAllows(gate.supported,current,hasProfile));
        }
    }
    if (!nativeMethods || !idReadable || !mapReadable || !gatesReadable || !hasProfile) return;
    uint32_t settingsIndex=0,settingsSerial=0;
    if (!ReadValue(settings+0xc,settingsIndex) || !ObjectSerial(settingsIndex,settings,settingsSerial)) return;
    uint64_t identity=((uint64_t)settingsSerial<<32)|settingsIndex;
    if (attempted.count(identity)) return;
    const KeyProfileRow *selected=nullptr;
    for (const char *candidate:{"Input.MouseAndKeyboard","Input.MouseAndKeyboard.Fr"}) {
        for (const auto &row:profiles) if (row.id==candidate && !ProfileIdsEqual(row.id,current)
            && IsKeyboardProfileCandidate(source,active,registered,activeRows.size(),hasProfile,currentAllowed,
                ProfileAllowedMask(gates,row.id,true))) { selected=&row; break; }
        if (selected) break;
    }
    if (!selected || gObserveOnly || !gRepairKeyboardProfile) return;
    // Copy the identifier before the native method invokes activation/deactivation
    // hooks and broadcasts its profile-changed delegate. Never hold map storage
    // across the call, and never create/reset/save a key profile here.
    std::vector<uint16_t> text(selected->id.begin(),selected->id.end()); text.push_back(0);
    MappingArrayHeader id={(uintptr_t)text.data(),(int32_t)text.size(),(int32_t)text.size()};
    uintptr_t matched=((uintptr_t (*)(uintptr_t,const MappingArrayHeader *))lookup)(settings,&id);
    if (matched!=selected->profile) { Log("keyboard_profile native lookup mismatch controller=%d; unchanged",index); return; }
    std::string target=selected->id; attempted.insert(identity);
    bool accepted=((bool (*)(uintptr_t,const MappingArrayHeader *))setter)(settings,&id);
    std::string after; bool afterReadable=ReadProfileId(settings+0x78,after);
    Log("keyboard_profile activation controller=%d from=%s to=%s accepted=%d resulting=%s",
        index,current.c_str(),target.c_str(),accepted,afterReadable?after.c_str():"<unreadable>");
    if (accepted && afterReadable && ProfileIdsEqual(after,target)) {
        const uint8_t options=1;
        ((void (*)(uintptr_t,const uint8_t *,uint8_t))(gBase+gGame.InputRebuild))(subsystem+0x30,&options,1);
        pending[controllerIdentity]=tick;
        Log("keyboard_profile native rebuild requested controller=%d; waiting for active mapping verification",index);
    }
}

struct InputControllerSnapshot { uintptr_t object; int32_t index; uint32_t serial; };
static bool gRepairKeyboardRedirects=true;
static void ProcessInputContexts(const std::vector<InputControllerSnapshot> &controllers,
        const std::vector<uintptr_t> &subsystems,uintptr_t contextClass,unsigned long tick) {
    if (!gGame.profiles || controllers.empty()) return;
    uintptr_t platformClass=0,dataClass=0,developerClass=0;
    ReadValue(gBase+gGame.cls("EnhancedInputPlatformSettings"),platformClass); ReadValue(gBase+gGame.cls("EnhancedInputPlatformData"),dataClass);
    ReadValue(gBase+gGame.cls("EnhancedInputDeveloperSettings"),developerClass);
    std::string platformClassName,dataClassName;
    // Do not initialize platform data here. Only inspect the already loaded classes.
    if (!ObjectMappingName(gBase+gGame.NamePool,platformClass,platformClassName)
        || platformClassName!="EnhancedInputPlatformSettings"
        || !ObjectMappingName(gBase+gGame.NamePool,dataClass,dataClassName)
        || dataClassName!="EnhancedInputPlatformData") {
        if (tick%5==0) Log("context_state platform class cache not ready; no redirect write");
        return;
    }
    uintptr_t settings=((uintptr_t (*)())(gBase+gGame.InputPlatformSettings))();
    MappingArrayHeader loaded={};
    if (!ObjectOfClassIncludingDefault(settings,platformClass) || !ReadValue(settings+0x50,loaded)
        || loaded.count<0 || loaded.count>32 || loaded.capacity<loaded.count || loaded.capacity>4096
        || (loaded.count && !IsHeapPointer(loaded.data))) return;
    std::vector<uintptr_t> dataClasses(loaded.count);
    if (loaded.count && !Read(loaded.data,dataClasses.data(),dataClasses.size()*8)) return;
    for (const auto &controller:controllers) {
        uintptr_t input=0,context=0;
        if (!ReadValue(controller.object+0x440,input) || !ReadValue(controller.object+gGame.DefaultMappingContext,context)
            || !LiveObjectOfClass(context,contextClass)) continue;
        uintptr_t subsystem=0;
        for (uintptr_t candidate:subsystems) {
            uintptr_t vtable=0,getter=0,rebuild=0;
            if (!ReadValue(candidate+0x30,vtable) || !ReadValue(vtable+0x18,getter)
                || getter!=gBase+gGame.PlayerInputThunk || !ReadValue(vtable+0xe0,rebuild) || rebuild!=gBase+gGame.InputRebuild) continue;
            if (((uintptr_t (*)(uintptr_t))getter)(candidate+0x30)==input) { subsystem=candidate; break; }
        }
        if (!subsystem) continue;
        std::vector<ContextMapRow> registered;
        if (!SnapshotContextMap(input+0x538,registered)) {
            if (tick%5==0) Log("context_state controller=%d registered map unreadable; no write",controller.index);
            continue;
        }
        bool isRegistered=false; int32_t priority=0;
        for (const auto &row:registered) if (row.key==context) { isRegistered=true; memcpy(&priority,&row.value,4); }
        std::vector<MappingRow> sourceRows,activeRows;
        if (!SnapshotMappings(context+0x30,sourceRows) || !SnapshotMappings(input+0x5d8,activeRows)) continue;
        auto source=InspectBindings(gBase+gGame.NamePool,sourceRows);
        auto active=InspectBindings(gBase+gGame.NamePool,activeRows);
        uint64_t identity=((uint64_t)controller.serial<<32)|(uint32_t)controller.index;
        static std::unordered_map<uint64_t,std::string> lastStates;
        static std::unordered_map<uint64_t,unsigned long> pendingRebuilds;
        ProcessKeyProfile(subsystem,identity,controller.index,sourceRows,source,activeRows,active,isRegistered,tick);
        auto pending=pendingRebuilds.find(identity);
        if (pending!=pendingRebuilds.end() && ((active.decoded && active.mask==0x3f) || tick>=pending->second+5)) {
            Log("keyboard_redirect verification controller=%d active_axes_complete=%d decoded=%d active_rows=%zu",
                controller.index,active.decoded && active.mask==0x3f,active.decoded,activeRows.size());
            pendingRebuilds.erase(pending);
        }
        std::string state=std::to_string(registered.size())+":"+std::to_string(isRegistered)
            +":"+std::to_string(source.mask)+":"+std::to_string(active.mask);
        bool report=lastStates[identity]!=state || tick%10==0;
        lastStates[identity]=state;
        if (report) {
            std::string name;
            Log("context_state controller=%d default=%s registered=%d priority=%d registered_count=%zu platform_data=%d source_axes_mask=%02x active_axes_mask=%02x decoded=%d/%d",
                controller.index,AssetName(context,name),isRegistered,priority,registered.size(),loaded.count,
                source.mask,active.mask,source.decoded,active.decoded);
            for (const auto &row:registered) {
                std::string entryName; int32_t p=0; uint32_t refs=0;
                memcpy(&p,&row.value,4); memcpy(&refs,(const char *)&row.value+4,4);
                Log("context_registered controller=%d context=%s priority=%d refs=%u",controller.index,AssetName(row.key,entryName),p,refs);
            }
            uintptr_t defaults=0; uint8_t filtering=0;
            if (IsHeapPointer(developerClass) && ReadValue(developerClass+0x110,defaults)) ReadValue(defaults+0xf0,filtering);
            MappingArrayHeader tags={};
            if (ReadValue(input+0x5e8,tags) && tags.count>=0 && tags.count<=32 && tags.capacity>=tags.count) {
                Log("context_input_mode controller=%d filtering=%d tag_count=%d",controller.index,(filtering&0x10)!=0,tags.count);
                for (int32_t i=0;i<tags.count;++i) {
                    MappingName tag={}; std::string text;
                    if (ReadValue(tags.data+(uintptr_t)i*8,tag) && DecodeMappingName(gBase+gGame.NamePool,tag,text))
                        Log("context_input_tag controller=%d tag=%s",controller.index,text.c_str());
                }
            }
        }
        // The engine appends platform-data maps in this order; the last value wins.
        // Select the effective entry before changing anything, including null overrides.
        ContextMapRow effectiveRedirect={};
        bool hasRedirect=false,redirectMapsReadable=true;
        for (uintptr_t cls:dataClasses) {
            uintptr_t data=0;
            if (!IsHeapPointer(cls) || !ClassIsA(cls,dataClass) || !ReadValue(cls+0x110,data)
                || !ObjectOfClassIncludingDefault(data,dataClass)) { redirectMapsReadable=false; break; }
            std::vector<ContextMapRow> redirects;
            if (!SnapshotContextMap(data+0x28,redirects)) { redirectMapsReadable=false; break; }
            for (const auto &row:redirects) if (row.key==context) { effectiveRedirect=row; hasRedirect=true; }
        }
        bool changed=false;
        if (report) Log("context_redirect_state controller=%d found=%d maps_readable=%d repair_enabled=%d observe=%d",
            controller.index,hasRedirect,redirectMapsReadable,gRepairKeyboardRedirects,gObserveOnly);
        if (hasRedirect && redirectMapsReadable && LiveObjectOfClass(effectiveRedirect.value,contextClass)) {
            std::vector<MappingRow> targetRows;
            if (SnapshotMappings(effectiveRedirect.value+0x30,targetRows)) {
                auto target=InspectBindings(gBase+gGame.NamePool,targetRows);
                bool candidate=IsKeyboardRedirectCandidate(source,target,active,isRegistered);
                if (report || candidate) {
                    std::string from,to;
                    Log("context_redirect controller=%d source=%s target=%s target_rows=%zu target_axes_mask=%02x decoded=%d candidate=%d",
                        controller.index,AssetName(context,from),AssetName(effectiveRedirect.value,to),targetRows.size(),target.mask,target.decoded,candidate);
                }
                if (candidate && !gObserveOnly && gRepairKeyboardRedirects && ReplaceRedirectDestination(effectiveRedirect,context)) {
                    changed=true;
                    Log("keyboard_redirect restored controller=%d source retained; scene priority and registration unchanged",controller.index);
                }
            }
        }
        if (changed) {
            pendingRebuilds[identity]=tick;
            // Match the game's own deferred rebuild: ignore keys already pressed until released.
            const uint8_t options=1;
            ((void (*)(uintptr_t,const uint8_t *,uint8_t))(gBase+gGame.InputRebuild))(subsystem+0x30,&options,1);
            Log("keyboard_redirect native rebuild requested controller=%d; waiting for active mapping verification",controller.index);
        }
    }
}

static void LogNativePointerState() {
    // Observe requested vs actual lock separately. UIKit may apply a change asynchronously.
    static NSString *last;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        UIWindowScene *windowScene=(UIWindowScene *)scene;
        for (UIWindow *window in windowScene.windows) {
            if (!window.isKeyWindow) continue;
            UIViewController *controller=window.rootViewController;
            while (controller.presentedViewController) controller=controller.presentedViewController;
            uint32_t native=gNativeCursorState.load();
            NSString *state=[NSString stringWithFormat:@"scene_active=%d controller=%@ wants_lock=%d actually_locked=%d adapter_ready=%d native_type=%u native_shown=%d show_seen=%d",
                scene.activationState==UISceneActivationStateForegroundActive,
                NSStringFromClass(controller.class),controller.prefersPointerLocked,windowScene.pointerLockState.isLocked,
                NativeCursor::Ready(native),NativeCursor::Type(native),NativeCursor::Shown(native),NativeCursor::ShowObserved(native)];
            if (![state isEqualToString:last]) { Log("native pointer %s",state.UTF8String); last=state; }
        }
    }
}

// Observe real UIKit hover coordinates. No synthesized buttons, key bindings,
// mouse warps or relative-delta scaling. UIKit performs window/view transforms;
// FIOSView.ViewSize supplies the render dimensions used by native touch code.
@interface NTENativePointerObserver : NSObject <UIGestureRecognizerDelegate>
- (void)hover:(UIHoverGestureRecognizer *)recognizer;
@end
@implementation NTENativePointerObserver
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b { return YES; }
- (void)hover:(UIHoverGestureRecognizer *)recognizer {
    if (!NativeCursorRepairEnabled() || !gNativeCursor.load() || NativeCursor::WantsLock(gNativeCursorState.load())) return;
    UIView *view=recognizer.view;
    if (!view.window.isKeyWindow || view.window.windowScene.activationState!=UISceneActivationStateForegroundActive) {
        gNativePosition.Invalidate(); return;
    }
    SEL selector=sel_registerName("ViewSize");
    Method method=class_getInstanceMethod(object_getClass(view),selector);
    if (!method || (uintptr_t)method_getImplementation(method)!=gBase+gGame.ViewSize) return;
    const uint64_t epoch=gCursorEpoch.load();
    CGPoint point=[recognizer locationInView:view]; CGRect bounds=view.bounds;
    NativeCursor::Position render=((NativeCursor::Position(*)(id,SEL))objc_msgSend)(view,selector),mapped;
    if (!NativeCursor::MapPosition({point.x,point.y},{bounds.origin.x,bounds.origin.y},
        {bounds.size.width,bounds.size.height},render,mapped)) { gNativePosition.Invalidate(); return; }
    if (epoch!=gCursorEpoch.load() || NativeCursor::WantsLock(gNativeCursorState.load())) return;
    if(recognizer.state==UIGestureRecognizerStateEnded || recognizer.state==UIGestureRecognizerStateCancelled)return;
    gNativePosition.Publish(mapped,epoch);
    unsigned long n=++gHoverSamples;
    if (n==1 || n%300==0) Log("native_cursor absolute_hover samples=%lu render=%.0fx%.0f position=(%.1f,%.1f) epoch=%llu",n,render.x,render.y,mapped.x,mapped.y,epoch);
}
@end
static const void *kNativeHoverObserver=&kNativeHoverObserver;
static UIView *NativeGameView(UIView *view,unsigned depth=0) {
    if (!view || depth>16) return nil;
    if (object_getClass(view)==NSClassFromString(@"FIOSView")) return view;
    for (UIView *child in view.subviews) { UIView *found=NativeGameView(child,depth+1); if (found) return found; }
    return nil;
}
static void AttachNativePointerPositionObservers() {
    if (![NSThread isMainThread] || !NativeCursorRepairEnabled() || !gNativeCursor.load()) return;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            UIView *view=NativeGameView(window.rootViewController.viewIfLoaded);
            if (!view || objc_getAssociatedObject(view,kNativeHoverObserver)) continue;
            Method size=class_getInstanceMethod(object_getClass(view),sel_registerName("ViewSize"));
            if (!size || (uintptr_t)method_getImplementation(size)!=gBase+gGame.ViewSize) continue;
            NTENativePointerObserver *observer=[NTENativePointerObserver new];
            UIHoverGestureRecognizer *hover=[[UIHoverGestureRecognizer alloc] initWithTarget:observer action:@selector(hover:)];
            hover.cancelsTouchesInView=NO; hover.delaysTouchesBegan=NO; hover.delaysTouchesEnded=NO;
            hover.delegate=observer;
            [view addGestureRecognizer:hover];
            objc_setAssociatedObject(view,kNativeHoverObserver,observer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            Log("native_cursor absolute position observer attached view=FIOSView native_render_scale=1 input_consumption=0");
        }
    }
}
static bool NativeGameWindowIsActive(NSString *hostScene=nil) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class] || scene.activationState!=UISceneActivationStateForegroundActive) continue;
        if (hostScene) {
            SEL identifier=sel_registerName("_sceneIdentifier");
            if (!HostCursor::Verify(object_getClass(scene),identifier,"/UIKitCore.framework/",'@',"")) continue;
            id value=((id(*)(id,SEL))objc_msgSend)(scene,identifier);
            if (![value isKindOfClass:NSString.class] || ![hostScene isEqualToString:value]) continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows)
            if (window.isKeyWindow && NativeGameView(window.rootViewController.viewIfLoaded)) return true;
    }
    return false;
}
static void RefreshNativeHostCursor(unsigned long serial,unsigned attempt) {
    if (serial!=gHostRefreshSerial || !NativeCursorRepairEnabled() || !gNativeCursor.load() || !NativeGameWindowIsActive()) return;
    HostCursor::Endpoint endpoint; const char *reason=nullptr;
    if (!HostCursor::Resolve(endpoint,reason)) {
        Log("native_cursor host_guard rejected reason=%s attempt=%u; no system mutation",reason,attempt); return;
    }
    if (!NativeGameWindowIsActive(endpoint.sceneIdentifier)) {
        Log("native_cursor host_guard rejected reason=key window is not the game scene"); return;
    }
    bool wants=NativeCursor::WantsLock(gNativeCursorState.load());
    HostCursor::Action action=HostCursor::Decide(wants,endpoint.appearsKey,endpoint.preferred,endpoint.hidden);
    // Never override a host preference mismatch or use a foreign window.
    HostCursor::Apply(endpoint,action);
    bool after=((BOOL(*)(id,SEL))objc_msgSend)(endpoint.delegate,sel_registerName("_pointerLockCursorIsHidden"));
    Log("native_cursor host_update wants_lock=%d native_host_preferred=%d appears_key=%d hidden_before=%d hidden_after=%d action=%d attempt=%u",
        wants,endpoint.preferred,endpoint.appearsKey,endpoint.hidden,after,(int)action,attempt);
    LogNativePointerState();
    if ((after!=wants || endpoint.preferred!=wants) && attempt<3) {
        const int delays[]={30,90,240};
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,delays[attempt]*NSEC_PER_MSEC),dispatch_get_main_queue(),^{RefreshNativeHostCursor(serial,attempt+1);});
    }
}
static void ScheduleNativeHostCursorRefresh() {
    const unsigned long serial=++gHostRefreshSerial;
    // UIKit applies the scene preference asynchronously. Defer one main-loop turn
    // and retry at most three times; no periodic capture enforcement.
    dispatch_async(dispatch_get_main_queue(),^{RefreshNativeHostCursor(serial,0);});
}

// Coalesce setter events onto UIKit's main thread. State is always read at execution
// time so a fast Option tap cannot leave a stale release/capture block queued.
static void QueueNativeCursorRefresh() {
    if (gCursorRefreshQueued.exchange(true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        gCursorRefreshQueued.store(false);
        if (!NativeCursorRepairEnabled() || !gNativeCursor.load()) return;
        RestoreNativePointerPreference();
        Class cls=NSClassFromString(@"IOSViewController");
            if (!NativePointerPreferenceBodyVerified() ||
            !InstallNativeCursorPreference(cls,@selector(prefersPointerLocked),(IMP)(gBase+gGame.PointerPreference))) {
            Log("native_cursor preference bridge rejected by method/configuration guard"); return;
        }
        static bool logged=false;
        if (!logged) { logged=true; Log("native_cursor preference bridge active source=FIOSCursor.SetType/Show option_injection=0"); }
        AttachNativePointerPositionObservers();
        unsigned updated=0;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window.isKeyWindow) continue;
                UIViewController *controller=window.rootViewController;
                // Notify the owning game controller and any presented container.
                for (unsigned depth=0; controller && depth<16; ++depth) {
                    [controller setNeedsUpdateOfPrefersPointerLocked]; ++updated;
                    controller=controller.presentedViewController;
                }
            }
        }
        uint32_t state=gNativeCursorState.load();
        Log("native_cursor UIKit_update wants_lock=%d controllers=%u type=%u shown=%d show_seen=%d",
            NativeCursor::WantsLock(state),updated,NativeCursor::Type(state),NativeCursor::Shown(state),NativeCursor::ShowObserved(state));
        LogNativePointerState();
        ScheduleNativeHostCursorRefresh();
    });
}
static void ObservePointerLockChanges() {
    static id notification;
    if (notification) return;
    notification=[NSNotificationCenter.defaultCenter addObserverForName:UIPointerLockStateDidChangeNotification
        object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            Log("native_cursor system_lock_changed");
            LogNativePointerState();
        }];
    [NSNotificationCenter.defaultCenter addObserverForName:UISceneWillDeactivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        ++gHostRefreshSerial; gNativePosition.Invalidate();
    }];
    [NSNotificationCenter.defaultCenter addObserverForName:UISceneDidActivateNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        if (NativeCursorRepairEnabled() && gNativeCursor.load()) QueueNativeCursorRefresh();
    }];
}

#include "NativeIndirectPolicy.h"
#include "NativeTouchObserver.h"

// Disable the engine's native mouse-to-touch setting. No touch objects, mouse
// callbacks, button state, release events or saved configuration are rewritten.
static void ConfigureNativePointerSettings() {
    if(gObserveOnly || !gGame.NativeMouseForTouchSwitch)return;
    uintptr_t cls=0,settings=0,actualClass=0;
    if(!ReadValue(gBase+gGame.cls("InputSettings"),cls)||!IsHeapPointer(cls)
        ||!ReadValue(cls+0x110,settings)||!IsHeapPointer(settings)
        ||!ReadValue(settings+0x10,actualClass)||actualClass!=cls)return;
    uint32_t flags=0;uint16_t bits=0;
    if(!ReadValue(settings+8,flags)||(flags&(0x8000|0x10000))
        ||!ReadValue(settings+gGame.MouseForTouchOffset,bits))return;
    const uint16_t changed=NativeIndirect::WithoutMouseForTouch(bits,gGame.MouseForTouchMask);
    if(changed!=bits)__atomic_fetch_and((uint16_t*)(settings+gGame.MouseForTouchOffset),(uint16_t)~gGame.MouseForTouchMask,__ATOMIC_SEQ_CST);
}

#include "PartyUIRuntime.h"

// Called only through FIOSAsyncTask on Unreal's game thread. The UObject array
// layout is checked against the current executable's own indexed array access.
static void GameThreadTick() {
    unsigned long tick = ++gTicks;
    ConfigureNativePointerSettings();
    AttachNativeCursorAdapter();
    if (tick==1 || tick%5==0) {
        Log("native_cursor position_status hover_samples=%lu getter_calls=%lu absolute_reads=%lu",gHoverSamples.load(),gPositionReads.load(),gPositionOverrides.load());
        LogMacPlatformState("game_tick");
        LogUIPlatformState("game_tick");
        uint32_t cursor=gNativeCursorState.load();
        Log("native_cursor status application_ready=%d attached=%d type=%u shown=%d show_seen=%d wants_lock=%d type_calls=%lu show_calls=%lu",
            gNativeApplication.load()!=0,gNativeCursor.load()!=0,NativeCursor::Type(cursor),NativeCursor::Shown(cursor),
            NativeCursor::ShowObserved(cursor),NativeCursor::WantsLock(cursor),gNativeTypeCalls.load(),gNativeShowCalls.load());
    }
    uintptr_t chunks=0, subsystemClass=0, settingsClass=0, controllerClass=0, enhancedClass=0, contextClass=0;
    int32_t count=0, chunkCount=0;
    bool ready = ReadValue(gBase+gGame.ObjectChunks,chunks) && ReadValue(gBase+gGame.ObjectCount,count)
        && ReadValue(gBase+gGame.ObjectChunkCount,chunkCount) && IsHeapPointer(chunks)
        && count>0 && count<10000000 && chunkCount>0 && chunkCount<=153
        && ((count+65535)/65536 <= chunkCount)
        && ReadValue(gBase+gGame.cls("CommonInputPlatformSettings"),settingsClass) && IsHeapPointer(settingsClass);
    if (!ready) { if (tick<=3 || tick%10==0) Log("waiting for initialized UE object array/settings class"); return; }
    void *settings = ((void *(*)())(gBase+gGame.CommonSettings))();
    uint8_t before[4]={};
    if (!Read((uintptr_t)settings+0x40,before,4) || before[0]>2 || before[1]>1 || before[2]>1 || before[3]>1) {
        Log("settings layout rejected; no write"); return;
    }
    uintptr_t actualClass=0;
    if (!ReadValue((uintptr_t)settings+0x10,actualClass) || actualClass!=settingsClass) {
        Log("settings class mismatch; no write"); return;
    }
    if (!gObserveOnly) {
        // 0=MouseAndKeyboard; offsets +0x40 default, +0x41 support. Keep touch/controller support.
        ((uint8_t *)settings)[0x40]=0;
        ((uint8_t *)settings)[0x41]=1;
    }
    if (tick<=3 || before[0]!=0 || before[1]!=1)
        Log("settings default=%u mouse_keyboard=%u touch=%u gamepad=%u -> mode=%s", before[0],before[1],before[2],before[3],gObserveOnly?"observe":"keyboard-enabled");
    // Class caches are extracted from the named native registration arguments.
    ReadValue(gBase+gGame.cls("CommonInputSubsystem"),subsystemClass);
    ReadValue(gBase+gGame.cls("HTPlayerController"),controllerClass);
    ReadValue(gBase+gGame.cls("EnhancedPlayerInput"),enhancedClass);
    ReadValue(gBase+gGame.cls("InputMappingContext"),contextClass);
    uintptr_t localInputClass=0; ReadValue(gBase+gGame.cls("EnhancedInputLocalPlayerSubsystem"),localInputClass);
    uintptr_t partyMain=0,partySlot=0,partyPanel=0;
    if(gPartyLayout.ready) {
        ReadValue(gBase+gPartyLayout.mainCache,partyMain);ReadValue(gBase+gPartyLayout.slotCache,partySlot);
        ReadValue(gBase+gPartyLayout.panelCache,partyPanel);
        if(PartyUI::Name(partyMain)!="HTUI_MainForm" || PartyUI::Name(partySlot)!="HTUI_CharacterSlot"
            || PartyUI::Name(partyPanel)!="PanelWidget")partyMain=0;
    }
    if(tick<=3 || tick%10==0)PartyNote("party_ui scan tick=%lu resolved=%d main_ready=%d slot_ready=%d panel_ready=%d repair=%d rebuild=%d",
        tick,gPartyLayout.ready,IsHeapPointer(partyMain),IsHeapPointer(partySlot),IsHeapPointer(partyPanel),PartyUI::repairEnabled,PartyUI::rebuildExisting);
    std::vector<InputControllerSnapshot> inputControllers;
    std::vector<uintptr_t> localInputSubsystems;
    unsigned long activity=gActivity.load();
    bool physicalInput=activity!=gLastActivity; gLastActivity=activity;
    int found=0, changed=0, classMatches=0, rejectedFlags=0, rejectedLayout=0, controllers=0, keyboardReady=0,partyForms=0;
    if (IsHeapPointer(subsystemClass)) {
        // The chunk slots are maintained by UE on this same game thread. Never
        // retain UObject pointers across ticks; a new scene can destroy them.
        auto **table=(uint8_t **)chunks;
        // Class membership is stable for this scan. Bound VM reads to the
        // number of distinct classes, rather than every live UObject.
        std::unordered_map<uintptr_t, uint8_t> classMembership;
        classMembership.reserve(2048);
        for (int32_t index=0; index<count; ++index) {
            uint8_t *chunk=table[index>>16];
            if (!IsHeapPointer((uintptr_t)chunk)) continue;
            uint8_t *item=chunk+(index&65535)*24;
            auto *object=*(uint8_t **)item;
            uint32_t itemFlags=*(uint32_t *)(item+8);
            if (!IsHeapPointer((uintptr_t)object) || (itemFlags&0x30000000)) continue;
            if (*(int32_t *)(object+0x0c)!=index) continue;
            uintptr_t candidateClass=*(uintptr_t *)(object+0x10);
            auto cached=classMembership.find(candidateClass);
            if (cached==classMembership.end()) {
                uint8_t kinds=(ClassIsA(candidateClass,subsystemClass)?1:0)
                    | (ClassIsA(candidateClass,controllerClass)?2:0)
                    | (ClassIsA(candidateClass,localInputClass)?4:0)
                    | (IsHeapPointer(partyMain) && ClassIsA(candidateClass,partyMain)?8:0);
                cached=classMembership.emplace(candidateClass,kinds).first;
            }
            uint8_t kinds=cached->second;
            if (!kinds) continue;
            if(kinds&8){++partyForms;PartyUI::Process((uintptr_t)object,index,*(uint32_t *)(item+0x10),tick,partyMain,partySlot,partyPanel);}
            if ((kinds&2) && !(*(uint32_t *)(object+8)&(0x10|0x8000|0x10000))) {
                ++controllers;
                inputControllers.push_back({(uintptr_t)object,index,*(uint32_t *)(item+0x10)});
                if (kLoggingEnabled && gGame.profiles) LogControllerMappings(object,index,*(uint32_t *)(item+0x10),tick,enhancedClass,contextClass);
            }
            if ((kinds&4) && !(*(uint32_t *)(object+8)&(0x10|0x8000|0x10000)))
                localInputSubsystems.push_back((uintptr_t)object);
            if (!(kinds&1)) continue;
            ++classMatches;
            if (*(uint32_t *)(object+8)&(0x10|0x8000|0x10000)) { ++rejectedFlags; continue; } // CDO / destroying
            if (!IsHeapPointer(*(uintptr_t *)(object+0x20)) || object[gGame.RawInputType]>2 || object[gGame.CurrentInputType]>2 || object[gGame.OverrideActive]>1) { ++rejectedLayout; continue; }
            ++found;
            uint32_t serial=*(uint32_t *)(item+0x10);
            bool first=gSeenSubsystems.insert(((uint64_t)serial<<32)|(uint32_t)index).second;
            if (first || tick%10==0) Log("subsystem index=%d raw=%u current=%u override=%u override_active=%u",index,object[gGame.RawInputType],object[gGame.CurrentInputType],object[gGame.OverrideInputType],object[gGame.OverrideActive]);
            if (!gObserveOnly && (first || physicalInput) && (object[gGame.RawInputType]!=0 || object[gGame.CurrentInputType]!=0)) {
                bool supported=((bool (*)(void *,uint8_t))(gBase+gGame.CommonSupport))(object,0);
                if (!supported) { Log("subsystem index=%d keyboard support vetoed by game",index); continue; }
                // Match the reflected SetCurrentInputType implementation.
                object[gGame.RawInputType]=0;
                bool locked=((bool (*)(void *,uint8_t))(gBase+gGame.CommonLocked))(object,0);
                if (!locked) ((void (*)(void *))(gBase+gGame.CommonRecalculate))(object);
                Log("input request index=%d locked=%d resulting_type=%u",index,locked,object[gGame.CurrentInputType]);
                ++changed;
            }
            if (!gObserveOnly && object[gGame.CurrentInputType]==0) ++keyboardReady;
        }
    }
    if (keyboardReady>0)gNativeInputInitialized.store(true,std::memory_order_release);
    if(tick<=3 || tick%10==0)PartyNote("party_ui scan_done tick=%lu forms=%d tracked=%zu",tick,partyForms,PartyUI::states.size());
    ProcessInputContexts(inputControllers,localInputSubsystems,contextClass,tick);
    gLastMappingLog=activity;
    if (tick<=3 || tick%5==0) Log("mapping scan controllers=%d controller_class_ready=%d enhanced_class_ready=%d context_class_ready=%d",controllers,IsHeapPointer(controllerClass),IsHeapPointer(enhancedClass),IsHeapPointer(contextClass));
    uint8_t textGate=0;
    if (tick<=3 || tick%5==0 || changed)
        Log("tick=%lu objects=%d subsystems=%d class_matches=%d flags_rejected=%d layout_rejected=%d class_cache=%d keys=%lu key_down=%lu key_up=%lu moves=%lu buttons=%lu button_down=%lu button_up=%lu native_keyboard_gate=%u",
            tick,count,found,classMatches,rejectedFlags,rejectedLayout,IsHeapPointer(subsystemClass),gKeys.load(),gKeyDown.load(),gKeyUp.load(),gMoves.load(),gButtons.load(),gButtonDown.load(),gButtonUp.load(),textGate);
}

#include "KeyboardBeepDiagnostics.h"

static void TimerTick() {
    @autoreleasepool {
        KeyboardBeep::Install();
#if NTE_ENABLE_LOGGING
        static unsigned long keyboardTicks=0;
        if (++keyboardTicks<=3 || keyboardTicks%10==0)KeyboardBeep::Heartbeat();
#endif
        if (!gNativeTouchReady) InstallNativeTouchObserver();
        RestoreNativePointerPreference();
        AttachObservers();
        CaptureNativeApplication();
        AttachNativePointerPositionObservers();
        LogNativePointerState();
        static bool startupComplete=false;
        if(!startupComplete && gNativeInputInitialized.load(std::memory_order_acquire) && gNativeCursor.load()) {
            startupComplete=true;
            dispatch_source_set_timer(gTimer,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),3*NSEC_PER_SEC,NSEC_PER_SEC/4);
        }
        if (gQueued.exchange(true)) {
            static unsigned stalled=0;
            if (++stalled%10==0) Log("game-thread task still pending");
            return;
        }
        Class task=NSClassFromString(@"FIOSAsyncTask");
        SEL selector=NSSelectorFromString(@"CreateTaskWithBlock:");
        if (!task || ![task respondsToSelector:selector]) { gQueued=false; Log("FIOSAsyncTask unavailable"); return; }
        Method method=class_getClassMethod(task,selector);
        if (!method || (uintptr_t)method_getImplementation(method)!=gBase+gGame.GameTask) {
            gQueued=false; Log("GUARD rejected: game task method implementation changed"); return;
        }
        BOOL (^block)(void)=^BOOL {
            @autoreleasepool {
                if ([NSThread isMainThread]) {
                    Log("GUARD rejected: async callback is on main thread");
                } else {
                    GameThreadTick();
                }
                gQueued=false;
                return YES; // CheckForCompletion consumes the task only on true.
            }
        };
        ((void (*)(id,SEL,id))objc_msgSend)(task,selector,block);
    }
}
static void StartPlugin() {
#ifdef NTE_BOOTSTRAP_PROBE
    NTE_BOOTSTRAP_PROBE();
    return;
#endif
    @autoreleasepool {
        if (![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.pwrd.yh.ios"]) {
            if (kLoggingEnabled) fprintf(stderr,"NTEDesktopMode: skipped (bundle mismatch)\n");
            return;
        }
        NSString *dir=[NSHomeDirectory() stringByAppendingPathComponent:@"Documents/NTEDesktopMode"];
        PartyUI::OpenLog(dir);
        PartyNote("NTEDesktopMode 0.6.4 release party_repair_default=1 hardware_callbacks=unchanged");
        if (kLoggingEnabled) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *path=[dir stringByAppendingPathComponent:@"plugin.log"];
            NSDictionary *attrs=[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
            if ([attrs fileSize]>4*1024*1024) {
                NSString *previous=[dir stringByAppendingPathComponent:@"plugin.previous.log"];
                [[NSFileManager defaultManager] removeItemAtPath:previous error:nil];
                [[NSFileManager defaultManager] moveItemAtPath:path toPath:previous error:nil];
            }
            gLog=fopen(path.fileSystemRepresentation,"a");
        }
        NSDictionary *config=[NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"config.plist"]];
        PartyUI::Configure(config);
        KeyboardBeep::Configure(config);
        gObserveOnly=[config[@"ObserveOnly"] boolValue];
        if (config[@"SpoofMacPlatform"]) gSpoofMacPlatform=[config[@"SpoofMacPlatform"] boolValue];
        if (config[@"RepairKeyboardProfile"]) gRepairKeyboardProfile=[config[@"RepairKeyboardProfile"] boolValue];
        if (config[@"RepairKeyboardRedirects"]) gRepairKeyboardRedirects=[config[@"RepairKeyboardRedirects"] boolValue];
        if (config[@"RestoreNativePointerPreference"]) gRestoreNativePointer=[config[@"RestoreNativePointerPreference"] boolValue];
        if (config[@"RepairNativeCursorPlatform"]) gRepairNativeCursorPlatform=[config[@"RepairNativeCursorPlatform"] boolValue];
        Log("%s start mode=%s app=%s build=%s",kPluginVersion,gObserveOnly?"observe":"native",[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] description].UTF8String,[[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] description].UTF8String);
        if (!GuardMainImage()) return;
        ConfigureMacPlatform();
        if (!gMacPlatformApplied) return;
        ConfigureUIPlatform();
        if (!gUIPlatformApplied) {
            // Keep the dependent startup changes coherent if the second page
            // cannot be installed. Reverse only our verified current values.
            MacPlatform::Query reverse[5];
            for(size_t i=0;i<5;++i){reverse[i]=MacPlatform::kQueries[i];std::swap(reverse[i].original,reverse[i].desktop);}
            auto rollback=MacPlatform::ApplyGroup(gBase,reverse);
            if(rollback.applied)gMacPlatformApplied=false;
            return;
        }
        InstallNativeTouchObserver();
        if (config[@"RepairNativeIndirectInput"]) gRepairNativeIndirectInput=[config[@"RepairNativeIndirectInput"] boolValue];
        // Set the native capability before UIKit creates the first gesture.
        // No runtime classification flip can split an existing down/up pair.
        ConfigureNativeIndirectInput(gNativeTouchReady && gGame.NativeIndirectFilter);
        dispatch_async(dispatch_get_main_queue(), ^{
            KeyboardBeep::Install();
            RestoreNativePointerPreference();
            CaptureNativeApplication();
            ObservePointerLockChanges();
            Log("native_cursor configuration enabled=%d observe=%d pointer_restore=%d",gRepairNativeCursorPlatform,gObserveOnly,gRestoreNativePointer);
            gTimer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
            dispatch_source_set_timer(gTimer,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/4),NSEC_PER_SEC,NSEC_PER_SEC/10);
            dispatch_source_set_event_handler(gTimer, ^{ TimerTick(); });
            dispatch_resume(gTimer);
            Log("timer scheduled: startup delay=0.25s interval=1s; steady interval=3s");
        });
    }
}

// Normal C++ dynamic initialization is ordered within this translation unit.
// A separate __attribute__((constructor)) ran before gGame's constructor in
// 0.6.0: dyld subsequently zeroed the resolved addresses after patches were live.
// Keep this initializer AFTER all state definitions; it still executes during
// dlopen, before the game's own startup continues.
static const bool gPluginBootstrap=[] { StartPlugin(); return true; }();

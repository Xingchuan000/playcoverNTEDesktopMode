#pragma once
#include <cstdint>
#include <cstring>

namespace KeyboardBeep {
enum class TextState { Clear, Editing, Unknown };
struct Eligibility {
    bool enabled=false, mainThread=false, dispatching=false, keyDown=false;
    bool active=false, keyWindow=false, catalystWindow=false, gameReady=false;
    bool captured=false, hostView=false, modal=false, markedText=false;
    uint64_t modifiers=0;
    TextState text=TextState::Unknown;
};
inline const char *Decision(const Eligibility &s) {
    if (!s.enabled) return "observe_only";
    if (!s.mainThread || !s.dispatching) return "outside_dispatch";
    if (!s.keyDown) return "not_key_down";
    if (!s.active || !s.keyWindow || !s.catalystWindow) return "inactive_or_foreign_window";
    if (!s.gameReady || !s.captured) return "game_not_captured";
    // Command/Control combinations retain AppKit's normal command behavior.
    if (s.modifiers & ((1ULL<<18)|(1ULL<<20))) return "system_shortcut";
    if (!s.hostView || s.modal) return "foreign_responder_or_modal";
    if (s.text!=TextState::Clear || s.markedText) return "text_or_unknown";
    return "suppress_terminal_keydown";
}
inline bool Suppress(const Eligibility &s) {
    return !std::strcmp(Decision(s),"suppress_terminal_keydown");
}
} // namespace KeyboardBeep

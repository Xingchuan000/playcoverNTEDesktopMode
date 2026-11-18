#!/bin/zsh
set -eu
cd "${0:A:h}/.."
SDK_PATH="$(xcrun --show-sdk-path)"
TEST_OUTPUT="$(mktemp -d "${TMPDIR:-/tmp/}nte-dynamic-tests.XXXXXX")"
trap 'rm -rf "$TEST_OUTPUT"' EXIT
xcrun clang -dynamiclib -target arm64-apple-ios15.0-macabi -isysroot "$SDK_PATH" tests/platform_fixture.S -o "$TEST_OUTPUT/platform-fixture.dylib"
codesign --force --sign - "$TEST_OUTPUT/platform-fixture.dylib"
test_names="${NTE_TESTS:-class_checks pointer_checks mapping_checks context_checks profile_checks platform_checks ui_platform_checks native_cursor_checks cursor_host_position_checks native_indirect_checks touch_observer_checks native_pointer_switch_checks keyboard_beep_checks keyboard_beep_release_checks party_ui_checks party_release_checks}"
for test in ${=test_names}; do
 xcrun clang++ -std=c++17 -O2 -fobjc-arc -fblocks -target arm64-apple-ios15.0-macabi -isysroot "$SDK_PATH" \
  -iframework "$SDK_PATH/System/iOSSupport/System/Library/Frameworks" -F "$SDK_PATH/System/iOSSupport/System/Library/Frameworks" \
  -framework Foundation -framework UIKit -framework GameController "tests/$test.mm" -o "$TEST_OUTPUT/$test"
 "$TEST_OUTPUT/$test" "$TEST_OUTPUT/platform-fixture.dylib"
done
zsh tests/bootstrap_order_checks.sh
codesign --verify --strict --verbose=2 libNTEDesktopMode.dylib

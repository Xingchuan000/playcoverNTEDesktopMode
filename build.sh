#!/bin/zsh
set -eu
cd "${0:A:h}"
SDK_PATH="$(xcrun --show-sdk-path)"
NTE_LOGGING_VALUE="${NTE_ENABLE_LOGGING:-0}"
case "$NTE_LOGGING_VALUE" in
  0|1) ;;
  *) print -u2 'NTE_ENABLE_LOGGING must be 0 or 1'; exit 2 ;;
esac
xcrun clang++ -std=c++17 -O2 -fobjc-arc -fblocks -dynamiclib \
  -target arm64-apple-ios15.0-macabi -isysroot "$SDK_PATH" \
  -DNTE_ENABLE_LOGGING="$NTE_LOGGING_VALUE" \
  -iframework "$SDK_PATH/System/iOSSupport/System/Library/Frameworks" \
  -F "$SDK_PATH/System/iOSSupport/System/Library/Frameworks" \
  -framework Foundation -framework UIKit -framework GameController \
  -install_name '@executable_path/Frameworks/libNTEDesktopMode.dylib' \
  -Wl,-no_warn_duplicate_libraries \
  src/NTEDesktopMode.mm src/NativeRouteEntry.S -o libNTEDesktopMode.dylib
codesign --force --sign - libNTEDesktopMode.dylib
file libNTEDesktopMode.dylib

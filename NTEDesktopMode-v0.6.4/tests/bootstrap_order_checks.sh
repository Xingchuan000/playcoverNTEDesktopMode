#!/bin/zsh
set -eu
cd "${0:A:h}/.."
SDK_PATH="$(xcrun --show-sdk-path)"
PROBE_DIR="$(mktemp -d "${TMPDIR:-/tmp/}nte-bootstrap-order.XXXXXX")"
trap 'rm -rf "$PROBE_DIR"' EXIT
python3 - "$PROBE_DIR/legacy-order.mm" <<'PY'
from pathlib import Path
import sys
s=Path('src/NTEDesktopMode.mm').read_text()
s=s.replace('static void StartPlugin() {','__attribute__((constructor)) static void StartPlugin() {')
s=s.replace('static const bool gPluginBootstrap=[] { StartPlugin(); return true; }();','')
Path(sys.argv[1]).write_text(s)
PY
flags=(-std=c++17 -O2 -fobjc-arc -fblocks -target arm64-apple-ios15.0-macabi -isysroot "$SDK_PATH" -iframework "$SDK_PATH/System/iOSSupport/System/Library/Frameworks" -F "$SDK_PATH/System/iOSSupport/System/Library/Frameworks" -framework Foundation -framework UIKit -framework GameController)
xcrun clang++ $flags tests/bootstrap_loader.mm -o "$PROBE_DIR/loader"
xcrun clang++ $flags -dynamiclib tests/bootstrap_order_probe.mm -o "$PROBE_DIR/fixed.dylib"
xcrun clang++ $flags -dynamiclib -I "$PWD/src" "-DNTE_BOOTSTRAP_SOURCE=\"$PROBE_DIR/legacy-order.mm\"" tests/bootstrap_order_probe.mm -o "$PROBE_DIR/legacy.dylib"
codesign --force --sign - "$PROBE_DIR/fixed.dylib"
codesign --force --sign - "$PROBE_DIR/legacy.dylib"
"$PROBE_DIR/loader" "$PROBE_DIR/legacy.dylib" 0
"$PROBE_DIR/loader" "$PROBE_DIR/fixed.dylib" 1

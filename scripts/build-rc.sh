#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_NUMBER="${BUILD_NUMBER:-20261112.1410}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/dist}"
APP="$OUTPUT_DIR/牛半仙Mac维修辅助工具.app"
if [[ -e "$APP" ]]; then echo "Refusing to overwrite $APP" >&2; exit 1; fi
cd "$ROOT/app"
swift build -c release
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/helper-management"
cp .build/release/DeviceCapturePrototype "$APP/Contents/MacOS/DeviceCapturePrototype"
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
cp Resources/mra-helper Resources/direct_rid_dfu Resources/builtin-calibrations.json Resources/小牛图标.icns Resources/微信.JPG "$APP/Contents/Resources/"
cp install-mra-device-control.sh uninstall-mra-device-control.sh mra-quarantine.sh com.mra.devicecontrol.helper.plist "$APP/Contents/Resources/helper-management/"
for lang in en ja ko zh-Hant; do ditto "Resources/l10n/$lang.lproj" "$APP/Contents/Resources/$lang.lproj"; done
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --deep --strict "$APP"
echo "Built: $APP"

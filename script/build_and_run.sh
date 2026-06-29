#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Bugu"
PRODUCT_NAME="CodeBeacon"
BUNDLE_ID="com.learnprompt.Bugu"
MIN_SYSTEM_VERSION="14.0"
VERSION="${BUGU_VERSION:-0.2.0-dev}"
COPYRIGHT="Copyright © $(date +%Y) LearnPrompt. All rights reserved."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
python3 script/generate_app_icon.py
iconutil -c icns Assets/AppIcon.iconset -o "$ICON_FILE"
swift build
BUILD_BINARY="$(swift build --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
chmod +x "$APP_BINARY"

# Copy the Bugu sound pack into the main bundle so BuguSoundEngine can load it
# via Bundle.main.url(forResource:withExtension:subdirectory:).
# Note: SwiftPM executable targets do not generate a usable resource bundle,
# so we copy the files manually even though Package.swift declares them.
if [[ -d "$ROOT_DIR/Resources/Sounds/bugu-pack" ]]; then
  mkdir -p "$APP_RESOURCES/Sounds"
  cp -R "$ROOT_DIR/Resources/Sounds/bugu-pack" "$APP_RESOURCES/Sounds/"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDisplayName</key>
  <string>Bugu</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIconName</key>
  <string>AppIcon</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>$COPYRIGHT</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

# macOS aggressively caches app icons by bundle id, so a freshly built bundle
# keeps showing the previous icon even after AppIcon.icns changes. Touch the
# bundle, re-register it with LaunchServices, and nudge the icon services so the
# new logo is actually picked up.
refresh_icon_cache() {
  touch "$APP_BUNDLE"
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  if [[ -x "$lsregister" ]]; then
    "$lsregister" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
  # iconservicesagent holds the rendered icon cache; restarting it clears stale art.
  killall iconservicesagent >/dev/null 2>&1 || true
  killall Dock >/dev/null 2>&1 || true
}

open_app() {
  refresh_icon_cache
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac

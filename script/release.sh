#!/usr/bin/env bash
#
# Release script for Bugu.
# Builds a Release .app, signs it, packages it into a DMG, notarizes and staples.
#
# Usage:
#   BUGU_DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
#   BUGU_NOTARY_KEYCHAIN_PROFILE="bugu-notary" \
#     ./script/release.sh 1.0.0
#
# To test the build and DMG packaging without notarization:
#   ./script/release.sh --skip-notarization 1.0.0
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Arguments and constants
# ---------------------------------------------------------------------------

SKIP_NOTARIZATION=false
POSITIONAL_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarization)
      SKIP_NOTARIZATION=true
      shift
      ;;
    -*)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--skip-notarization] <version>" >&2
      exit 2
      ;;
    *)
      POSITIONAL_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ ${#POSITIONAL_ARGS[@]} -ne 1 ]]; then
  echo "Usage: $0 [--skip-notarization] <version>" >&2
  echo "Example: $0 1.0.0" >&2
  exit 2
fi

VERSION="${POSITIONAL_ARGS[0]}"
APP_NAME="Bugu"
PRODUCT_NAME="CodeBeacon"
BUNDLE_ID="com.learnprompt.Bugu"
MIN_SYSTEM_VERSION="14.0"
COPYRIGHT="Copyright © $(date +%Y) LearnPrompt. All rights reserved."

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$DIST_DIR/release-build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"

# ---------------------------------------------------------------------------
# Environment validation
# ---------------------------------------------------------------------------

if [[ -z "${BUGU_DEVELOPER_ID:-}" ]]; then
  if [[ "$SKIP_NOTARIZATION" == true ]]; then
    echo "Warning: BUGU_DEVELOPER_ID is not set. Continuing without code signing." >&2
    echo "This DMG is for local testing only and will not pass Gatekeeper." >&2
    BUGU_DEVELOPER_ID="-"
  else
    echo "Error: BUGU_DEVELOPER_ID environment variable is not set." >&2
    echo "Set it to your Developer ID Application certificate name, e.g." >&2
    echo '  export BUGU_DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)"' >&2
    exit 1
  fi
fi

if [[ "$SKIP_NOTARIZATION" == false ]]; then
  if [[ -n "${BUGU_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$BUGU_NOTARY_KEYCHAIN_PROFILE")
  elif [[ -n "${BUGU_APPLE_ID:-}" && -n "${BUGU_TEAM_ID:-}" && -n "${BUGU_APP_SPECIFIC_PASSWORD:-}" ]]; then
    NOTARY_ARGS=(--apple-id "$BUGU_APPLE_ID" --team-id "$BUGU_TEAM_ID" --password "$BUGU_APP_SPECIFIC_PASSWORD")
  else
    echo "Error: notarytool credentials are not configured." >&2
    echo "Either set BUGU_NOTARY_KEYCHAIN_PROFILE (recommended), e.g." >&2
    echo '  export BUGU_NOTARY_KEYCHAIN_PROFILE="bugu-notary"' >&2
    echo "or set BUGU_APPLE_ID, BUGU_TEAM_ID and BUGU_APP_SPECIFIC_PASSWORD, e.g." >&2
    echo '  export BUGU_APPLE_ID="you@example.com"' >&2
    echo '  export BUGU_TEAM_ID="ABCD123456"' >&2
    echo '  export BUGU_APP_SPECIFIC_PASSWORD="xxxx-xxxx-xxxx-xxxx"' >&2
    echo "Or use --skip-notarization to test the build and DMG packaging only." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

if ! command -v swift >/dev/null 2>&1; then
  echo "Error: swift command not found. This script requires Xcode command line tools." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -F "$BUGU_DEVELOPER_ID" >/dev/null 2>&1; then
  echo "Warning: '$BUGU_DEVELOPER_ID' was not found in the macOS keychain." >&2
  echo "Available Developer ID Application certificates:" >&2
  security find-identity -v -p codesigning >&2 || true
fi

# ---------------------------------------------------------------------------
# Build release binary
# ---------------------------------------------------------------------------

echo "==> Building $APP_NAME $VERSION (Release)..."
cd "$ROOT_DIR"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

swift build -c release

BUILD_BIN_PATH="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BUILD_BIN_PATH/$PRODUCT_NAME"

if [[ ! -f "$BUILD_BINARY" ]]; then
  echo "Error: release binary not found at $BUILD_BINARY" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Assemble .app bundle
# ---------------------------------------------------------------------------

echo "==> Assembling $APP_NAME.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"

cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

if [[ -f "$ICON_FILE" ]]; then
  cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"
else
  echo "Warning: icon file not found at $ICON_FILE" >&2
fi

# Copy the Bugu sound pack into the main bundle so BuguSoundEngine can load it
# via Bundle.main.url(forResource:withExtension:subdirectory:).
# Note: SwiftPM executable targets do not generate a usable resource bundle,
# so we copy the files manually even though Package.swift declares them.
if [[ -d "$ROOT_DIR/Resources/Sounds/bugu-pack" ]]; then
  mkdir -p "$APP_RESOURCES/Sounds"
  cp -R "$ROOT_DIR/Resources/Sounds/bugu-pack" "$APP_RESOURCES/Sounds/"
  echo "    copied Resources/Sounds/bugu-pack"
else
  echo "Warning: sound pack not found at $ROOT_DIR/Resources/Sounds/bugu-pack" >&2
fi

# ---------------------------------------------------------------------------
# Inject Info.plist
# ---------------------------------------------------------------------------

echo "==> Injecting Info.plist..."
if [[ -f "$ROOT_DIR/Resources/Info.plist" ]]; then
  sed -e "s|__APP_NAME__|$APP_NAME|g" \
      -e "s|__BUNDLE_ID__|$BUNDLE_ID|g" \
      -e "s|__VERSION__|$VERSION|g" \
      -e "s|__MIN_SYSTEM_VERSION__|$MIN_SYSTEM_VERSION|g" \
      -e "s|__COPYRIGHT__|$COPYRIGHT|g" \
      "$ROOT_DIR/Resources/Info.plist" > "$INFO_PLIST"
else
  echo "Error: Info.plist template not found at $ROOT_DIR/Resources/Info.plist" >&2
  exit 1
fi

plutil -lint "$INFO_PLIST" >/dev/null

# ---------------------------------------------------------------------------
# Sign the .app
# ---------------------------------------------------------------------------

if [[ "$BUGU_DEVELOPER_ID" == "-" ]]; then
  echo "==> Skipping Developer ID signing (--skip-notarization test mode)."
else
  echo "==> Signing $APP_NAME.app..."
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$BUGU_DEVELOPER_ID" \
    "$APP_BUNDLE"

  # Verify signature (best-effort; continue even if spctl is strict)
  echo "==> Verifying code signature..."
  codesign --verify --deep --strict "$APP_BUNDLE" || true
fi

# ---------------------------------------------------------------------------
# Create DMG
# ---------------------------------------------------------------------------

echo "==> Creating DMG..."
rm -f "$DMG_PATH"

if command -v create-dmg >/dev/null 2>&1; then
  echo "    using create-dmg"
  create-dmg \
    --volname "$APP_NAME $VERSION" \
    --window-size 800 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 200 185 \
    --app-drop-link 600 185 \
    --no-internet-enable \
    "$DMG_PATH" \
    "$APP_BUNDLE"
else
  echo "    create-dmg not found, falling back to hdiutil"
  echo "    (Install create-dmg for a nicer DMG layout: brew install create-dmg)"

  STAGING="$BUILD_DIR/dmg-staging"
  rm -rf "$STAGING"
  mkdir -p "$STAGING"
  cp -R "$APP_BUNDLE" "$STAGING/"

  hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$APP_NAME $VERSION" \
    -fs HFS+ \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"
fi

# ---------------------------------------------------------------------------
# Notarize and staple
# ---------------------------------------------------------------------------

if [[ "$SKIP_NOTARIZATION" == true ]]; then
  echo "==> Skipping notarization (--skip-notarization test mode)."
else
  echo "==> Submitting DMG to Apple notary service..."
  xcrun notarytool submit "$DMG_PATH" "${NOTARY_ARGS[@]}" --wait

  echo "==> Stapling notarization ticket to DMG..."
  xcrun stapler staple "$DMG_PATH"

  echo "==> Verifying stapled DMG..."
  xcrun stapler validate "$DMG_PATH" || true
fi

# ---------------------------------------------------------------------------
# Final verification and output
# ---------------------------------------------------------------------------

echo ""
echo "✅ Release ready:"
echo "   $DMG_PATH"
if [[ "$SKIP_NOTARIZATION" == true ]]; then
  echo ""
  echo "This DMG was built without Developer ID signing or notarization." \
       "It is suitable for local testing only and will not pass Gatekeeper on other Macs."
  echo "Run without --skip-notarization and provide BUGU_DEVELOPER_ID + notarytool credentials"
  echo "to produce a release-ready, Gatekeeper-compatible DMG."
else
  echo ""
  echo "Distribute this DMG directly to users. Gatekeeper will recognize the" \
       "Developer ID signature and stapled notarization ticket."
fi

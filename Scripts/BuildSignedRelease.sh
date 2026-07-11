#!/bin/sh
# Build, sign, notarize, staple, and DMG-package DiskInventoryY locally.
# Pulls the Developer ID Application certificate out of your Keychain
# and the notarization credentials out of `notarytool store-credentials`
# (run Scripts/StoreNotaryCreds.sh once first). Nothing in this script
# expects secrets in the repo or in environment variables.
#
# Required:
#   - Apple Developer Program membership
#   - "Developer ID Application: <your name>" cert in the login Keychain
#   - `notarytool` profile created via Scripts/StoreNotaryCreds.sh
#
# Optional environment overrides:
#   NOTARY_PROFILE       — keychain profile name (default: DiskInventoryY-Notarization)
#   SIGN_IDENTITY        — full Developer ID Application string
#                          (auto-detected from `security find-identity` if unset)
#   DEVELOPMENT_TEAM     — 10-char team ID (auto-extracted from cert if unset)
#   SKIP_NOTARIZE=1      — sign locally but don't submit to Apple
#   SKIP_DMG=1           — produce the .app but skip the DMG
set -eu
cd "$(dirname "$0")/.."

NOTARY_PROFILE="${NOTARY_PROFILE:-DiskInventoryY-Notarization}"

# --- 0. Ensure project exists -----------------------------------------------
if [ ! -d DiskInventoryY.xcodeproj ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required (brew install xcodegen)" >&2
    exit 1
  fi
  xcodegen generate
fi

# --- 1. Find a Developer ID Application cert --------------------------------
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(
    security find-identity -p codesigning -v 2>/dev/null \
      | grep "Developer ID Application" \
      | head -n 1 \
      | sed -E 's/^[[:space:]]*[0-9]+\)[[:space:]]+[0-9A-F]+[[:space:]]+"(.*)"$/\1/'
  )"
fi
if [ -z "${SIGN_IDENTITY:-}" ]; then
  echo "No 'Developer ID Application' identity found in your Keychain." >&2
  echo "Create one at https://developer.apple.com/account/resources/certificates/" >&2
  echo "and import it into the login Keychain, or override SIGN_IDENTITY." >&2
  exit 1
fi
echo "Using signing identity: $SIGN_IDENTITY"

if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  DEVELOPMENT_TEAM="$(echo "$SIGN_IDENTITY" | sed -nE 's/.*\(([A-Z0-9]{10})\).*/\1/p')"
fi
if [ -z "${DEVELOPMENT_TEAM:-}" ]; then
  echo "Couldn't parse a 10-char team id out of '$SIGN_IDENTITY'." >&2
  echo "Set DEVELOPMENT_TEAM=ABCDE12345 explicitly." >&2
  exit 1
fi
echo "Using team: $DEVELOPMENT_TEAM"

# --- 2. Archive --------------------------------------------------------------
rm -rf build
mkdir -p build

xcodebuild archive \
  -project DiskInventoryY.xcodeproj \
  -scheme DiskInventoryY \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/DiskInventoryY.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

# --- 3. Export -------------------------------------------------------------
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>signingStyle</key><string>manual</string>
  <key>teamID</key><string>$DEVELOPMENT_TEAM</string>
  <key>signingCertificate</key><string>Developer ID Application</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath build/DiskInventoryY.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist build/ExportOptions.plist

APP="build/export/DiskInventoryY.app"
[ -d "$APP" ] || { echo "Export failed — no $APP" >&2; exit 1; }

echo
echo "Verifying signature…"
codesign -dv --verbose=2 "$APP" 2>&1 | head -10
codesign --verify --strict --verbose=2 "$APP"

# --- 4. Notarize -------------------------------------------------------------
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "SKIP_NOTARIZE=1 set; skipping notarization."
else
  echo
  echo "Submitting to Apple notary service via profile '$NOTARY_PROFILE'…"
  Scripts/notarize.sh "$APP"
fi

# --- 5. DMG ------------------------------------------------------------------
if [ "${SKIP_DMG:-0}" = "1" ]; then
  echo "SKIP_DMG=1 set; finished."
  exit 0
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="build/DiskInventoryY-${VERSION}.dmg"

# Layout: temp staging dir with the app + symlink to /Applications.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
  -volname "DiskInventoryY $VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

# Sign the DMG so Safari/Gatekeeper recognise it as authored.
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG"

# The DMG needs its own notarization ticket — the .app's ticket does
# not cover the container. Submit the DMG, then staple it.
if [ "${SKIP_NOTARIZE:-0}" != "1" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
fi

echo
echo "✓ Built and signed: $DMG"
echo "  Verify Gatekeeper acceptance: spctl --assess --type execute --verbose=2 \"$APP\""
echo "  Upload to GitHub Release: gh release upload v$VERSION \"$DMG\" -R agriev/diskinventoryy"

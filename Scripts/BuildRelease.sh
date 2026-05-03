#!/bin/sh
# Build a Release archive of DiskInventoryY and produce a DMG.
# Optional: NOTARIZE=1 to run notarytool (requires APPLE_ID, TEAM_ID, APPLE_APP_PASSWORD env vars).
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -d DiskInventoryY.xcodeproj ]; then
  if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen is required to (re)generate the Xcode project. brew install xcodegen" >&2
    exit 1
  fi
  xcodegen generate
fi

rm -rf build
xcodebuild archive \
  -project DiskInventoryY.xcodeproj \
  -scheme DiskInventoryY \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath build/DiskInventoryY.xcarchive \
  CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

xcodebuild -exportArchive \
  -archivePath build/DiskInventoryY.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist Scripts/ExportOptions.plist \
  || cp -R build/DiskInventoryY.xcarchive/Products/Applications build/export

if [ "${NOTARIZE:-0}" = "1" ]; then
  Scripts/notarize.sh build/export/DiskInventoryY.app
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
  build/export/DiskInventoryY.app/Contents/Info.plist 2>/dev/null || echo 0.0.0)"

hdiutil create \
  -volname DiskInventoryY \
  -srcfolder build/export \
  -ov -format UDZO \
  "build/DiskInventoryY-${VERSION}.dmg"

echo "Built: build/DiskInventoryY-${VERSION}.dmg"

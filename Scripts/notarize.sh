#!/bin/sh
# Notarize a built .app bundle with notarytool and staple the ticket.
# Requires env: APPLE_ID, TEAM_ID, APPLE_APP_PASSWORD.
set -euo pipefail

APP_PATH="${1:-build/export/DiskInventoryY.app}"

if [ -z "${APPLE_ID:-}" ] || [ -z "${TEAM_ID:-}" ] || [ -z "${APPLE_APP_PASSWORD:-}" ]; then
  echo "APPLE_ID, TEAM_ID, APPLE_APP_PASSWORD env vars are required for notarization." >&2
  exit 2
fi

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

ZIP="$(dirname "$APP_PATH")/$(basename "$APP_PATH" .app).zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

xcrun stapler staple "$APP_PATH"
echo "Notarized and stapled: $APP_PATH"

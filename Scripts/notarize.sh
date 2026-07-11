#!/bin/sh
# Notarize a built .app bundle via `notarytool` and staple the ticket.
#
# Credentials come from one of two places, in order:
#   1. NOTARY_PROFILE — name of a keychain profile created via
#      `xcrun notarytool store-credentials` (preferred for local use;
#      no secrets in env vars or in the repo).
#   2. APPLE_ID, TEAM_ID, APPLE_APP_PASSWORD env vars (used by CI).
set -eu

APP_PATH="${1:-build/export/DiskInventoryY.app}"
NOTARY_PROFILE="${NOTARY_PROFILE:-DiskInventoryY-Notarization}"

if [ ! -d "$APP_PATH" ]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

ZIP="$(dirname "$APP_PATH")/$(basename "$APP_PATH" .app).zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP"

submit() {
  # Probe the profile with notarytool itself — store-credentials keeps
  # items in the data-protection keychain where the legacy `security`
  # search can't see them.
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
    return $?
  fi
  if [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ]; then
    xcrun notarytool submit "$ZIP" \
      --apple-id "$APPLE_ID" \
      --team-id "$TEAM_ID" \
      --password "$APPLE_APP_PASSWORD" \
      --wait
    return $?
  fi
  echo "No notarization credentials available." >&2
  echo "Run Scripts/StoreNotaryCreds.sh to set up a keychain profile," >&2
  echo "or set APPLE_ID, TEAM_ID, and APPLE_APP_PASSWORD." >&2
  return 2
}

submit
xcrun stapler staple "$APP_PATH"
echo "Notarized and stapled: $APP_PATH"

#!/bin/sh
# One-time helper: stash Apple ID + app-specific password + team ID
# in the local login Keychain so notarytool can pick them up by name.
# Nothing leaves your machine; the secrets are not written to disk in
# plain text.
#
# After running this once, BuildSignedRelease.sh / notarize.sh use:
#   xcrun notarytool ... --keychain-profile "$NOTARY_PROFILE"
#
# Re-run when the app-specific password is rotated.
set -eu

PROFILE_NAME="${NOTARY_PROFILE:-DiskInventoryY-Notarization}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun not found — install Xcode command-line tools first." >&2
  exit 2
fi

read -r -p "Apple ID email: " APPLE_ID
read -r -p "Team ID (10 chars, e.g. ABCD123456): " TEAM_ID
# `read -s` toggles echo off so the password isn't shown.
printf 'App-specific password (https://account.apple.com → Sign-In and Security): '
stty -echo
read -r APPLE_APP_PASSWORD
stty echo
echo

xcrun notarytool store-credentials "$PROFILE_NAME" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APPLE_APP_PASSWORD"

echo
echo "Stored as keychain profile: $PROFILE_NAME"
echo "BuildSignedRelease.sh will use NOTARY_PROFILE=$PROFILE_NAME by default."
echo "Test it with: xcrun notarytool history --keychain-profile $PROFILE_NAME | head"

#!/bin/sh
# One-time helper: import the downloaded Developer ID Application
# certificate together with the private key that produced its CSR.
# Run AFTER downloading developerID_application.cer from
# https://developer.apple.com/account/resources/certificates/
#
# Usage:
#   Scripts/ImportDeveloperIDCert.sh [cert.cer] [private.key]
# Defaults match the files created on the Desktop by the CSR step.
set -eu

CERT="${1:-$HOME/Desktop/DiskInventoryY-DeveloperID/developerID_application.cer}"
KEY="${2:-$HOME/Desktop/DiskInventoryY-DeveloperID/developer-id-private.key}"

[ -f "$CERT" ] || { echo "Certificate not found: $CERT" >&2; exit 1; }
[ -f "$KEY" ]  || { echo "Private key not found: $KEY" >&2; exit 1; }

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

security import "$KEY" -k "$KEYCHAIN" -T /usr/bin/codesign -T /usr/bin/security
security import "$CERT" -k "$KEYCHAIN" -T /usr/bin/codesign

echo
echo "Imported. Verifying identity…"
if security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
  security find-identity -p codesigning -v | grep "Developer ID Application"
  echo
  echo "✓ Ready. You can now delete $HOME/Desktop/DiskInventoryY-DeveloperID"
  echo "  (the private key lives in your Keychain now)."
  echo "Next: Scripts/StoreNotaryCreds.sh  (one-time notary credentials)"
else
  echo "⚠ Identity not visible yet. If the cert was just created, also install"
  echo "  Apple's intermediate 'Developer ID G2 CA' from https://www.apple.com/certificateauthority/"
  exit 1
fi

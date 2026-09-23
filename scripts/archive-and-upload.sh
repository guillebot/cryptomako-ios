#!/usr/bin/env bash
# Archive CryptoMako iOS and upload to App Store Connect.
# Prefer cloud-managed Distribution via xcodebuild -allowProvisioningUpdates.
# Fail closed; do not print secrets.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodegen generate

ARCHIVE_PATH="${ARCHIVE_PATH:-$ROOT/build/CryptoMako.xcarchive}"
EXPORT_DIR="${EXPORT_DIR:-$ROOT/build/export-upload}"
LOG_DIR="$ROOT/build/logs"
mkdir -p "$LOG_DIR" "$EXPORT_DIR"
LOG="$LOG_DIR/archive-upload-$(date +%Y%m%d-%H%M%S).log"

{
  echo "== identities =="
  security find-identity -v -p codesigning
  echo "(Cloud Managed Apple Distribution may still sign via -allowProvisioningUpdates)"

  echo "== archive =="
  xcodebuild -project CryptoMako.xcodeproj -scheme CryptoMako \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM=H4K6YW7MQM \
    archive

  echo "== export + upload to App Store Connect =="
  echo "Requires ASC app record for net.gschimmel.cryptomako.ios (see docs/asc-checklist.md)."
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportOptionsPlist Support/ASC/ExportOptions-AppStore.plist \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates
} 2>&1 | tee "$LOG"

echo "Log: $LOG"
echo "If upload succeeded, check App Store Connect → TestFlight for Processing."

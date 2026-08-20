#!/bin/bash
# Package dist/tunaneko.app into a distributable DMG:
#   dist/release/tunaneko-<version>-macOS-arm64.dmg
# The DMG contains the app, an /Applications symlink (drag-install), and
# INSTALL.txt explaining the quarantine removal (ad-hoc signature).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
APP_DIR="$ROOT/dist/tunaneko.app"
RELEASE_DIR="$ROOT/dist/release"
STAGE="$RELEASE_DIR/dmg-stage"
DMG="$RELEASE_DIR/tunaneko-${VERSION}-macOS-arm64.dmg"

[ -d "$APP_DIR" ] || { echo "run \`make dist\` first"; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP_DIR" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

cat > "$STAGE/INSTALL.txt" <<'EOF'
tunaneko — Installation
=============================

1. Drag tunaneko.app into the Applications folder.

2. The app is ad-hoc signed (no Apple Developer account), so Gatekeeper
   will quarantine it when downloaded. Remove the quarantine flag:

       xattr -cr /Applications/tunaneko.app

   (or right-click the app and choose "Open")

3. Launch the app, open the Settings tab, and click "Set up…" to add the
   sudoers rule (one-time, admin password required).

4. Enter your VPN credentials in Settings and connect.

Requirements: Apple Silicon Mac, macOS 13 or newer
(builds target the macOS version of the build machine).
EOF

mkdir -p "$RELEASE_DIR"
rm -f "$DMG"
hdiutil create -volname "tunaneko" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "==> release: $DMG"

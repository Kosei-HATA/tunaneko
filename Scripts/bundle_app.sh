#!/bin/bash
# Assemble dist/tunaneko.app from:
#   .build/release/tunaneko   (SPM product)
#   build/core/openconnect          (bundled core, from Scripts/build_core.sh)
#   build/core/Frameworks           (dylib closure)
#   Resources/*                     (Info.plist, *.lproj, vpnc-script)
# and ad-hoc codesign everything.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="tunaneko"
APP_DIR="$ROOT/dist/${APP_NAME}.app"

[ -x "$ROOT/.build/release/$APP_NAME" ] || { echo "run \`swift build -c release\` first"; exit 1; }
[ -x "$ROOT/build/core/openconnect" ] || { echo "run \`make core\` first"; exit 1; }

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"

cp "$ROOT/.build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
cp "$ROOT/build/core/openconnect" "$APP_DIR/Contents/MacOS/openconnect"
# dylib closure (guard: glob may not match if core has no deps)
shopt -s nullglob
DYLIBS=("$ROOT"/build/core/Frameworks/*.dylib)
[ "${#DYLIBS[@]}" -gt 0 ] || { echo "no bundled dylibs found; run \`make core\`"; exit 1; }
cp "${DYLIBS[@]}" "$APP_DIR/Contents/Frameworks/"
shopt -u nullglob

cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
for d in "$ROOT"/Resources/*.lproj; do
    [ -d "$d" ] && cp -R "$d" "$APP_DIR/Contents/Resources/"
done
cp "$ROOT/Resources/vpnc-script" "$APP_DIR/Contents/Resources/vpnc-script"
chmod +x "$APP_DIR/Contents/Resources/vpnc-script"
cp "$ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
[ -d "$ROOT/Resources/Licenses" ] && cp -R "$ROOT/Resources/Licenses" "$APP_DIR/Contents/Resources/Licenses" || echo "warning: Licenses dir missing"

# --- ad-hoc codesign (innermost first) ---------------------------------------
for f in "$APP_DIR"/Contents/Frameworks/*.dylib "$APP_DIR/Contents/MacOS/openconnect" "$APP_DIR/Contents/MacOS/$APP_NAME"; do
    if [ -e "$f" ]; then
        codesign --force --sign - "$f" || { echo "codesign failed: $f"; exit 1; }
    fi
done
codesign --force --deep --sign - "$APP_DIR"

echo "==> built: $APP_DIR"
codesign --verify --deep --strict "$APP_DIR" && echo "==> codesign OK"

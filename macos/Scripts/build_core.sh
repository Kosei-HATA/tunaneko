#!/bin/bash
# Build openconnect core from source and produce a relocatable bundle:
#   build/core/openconnect      - the openconnect binary (rpath @executable_path/../Frameworks)
#   build/core/Frameworks/*.dylib - full dylib closure (gnutls chain), @rpath-based
#
# Build-time requirements: Command Line Tools, pkg-config, gnutls (brew).
# Runtime requirements: none (no Homebrew needed on the target machine).
set -euo pipefail

OC_VERSION="9.21"
OC_SHA256="5b32369467db6e5f317aa1ed12cfcbb81ed00bdbc765450b6bfcbdc300944a58"
OC_URL="https://www.infradead.org/openconnect/download/openconnect-${OC_VERSION}.tar.gz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build"
SRC_DIR="$BUILD_DIR/openconnect-${OC_VERSION}"
OUT_DIR="$BUILD_DIR/core"
FW_DIR="$OUT_DIR/Frameworks"

mkdir -p "$BUILD_DIR" "$FW_DIR"

# --- download & verify -------------------------------------------------------
TARBALL="$BUILD_DIR/openconnect-${OC_VERSION}.tar.gz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading $OC_URL"
    curl -fL "$OC_URL" -o "$TARBALL"
fi
echo "$OC_SHA256  $TARBALL" | shasum -a 256 -c - || { echo "SHA256 mismatch"; exit 1; }

# --- extract & build ----------------------------------------------------------
if [ ! -d "$SRC_DIR" ]; then
    tar -xzf "$TARBALL" -C "$BUILD_DIR"
fi

cd "$SRC_DIR"
if [ ! -f Makefile ]; then
    echo "==> configure"
    ./configure \
        --prefix="$BUILD_DIR/stage" \
        --with-gnutls \
        --with-vpnc-script="$ROOT/Resources/vpnc-script" \
        --without-libpcsclite \
        --without-libstoken \
        --without-liboath \
        --without-libpskc \
        --disable-shared \
        --enable-static \
        --disable-nls
fi
echo "==> make"
make -j"$(sysctl -n hw.ncpu)"

mkdir -p "$OUT_DIR"
# libtool may leave a wrapper script at the top level; the real Mach-O binary
# lives in .libs/. Prefer it when present.
if file "$SRC_DIR/.libs/openconnect" 2>/dev/null | grep -q "Mach-O"; then
    cp "$SRC_DIR/.libs/openconnect" "$OUT_DIR/openconnect"
else
    cp "$SRC_DIR/openconnect" "$OUT_DIR/openconnect"
fi
chmod +x "$OUT_DIR/openconnect"

# --- dylib closure ------------------------------------------------------------
# Recursively collect non-system dylib dependencies into $FW_DIR and rewrite
# all references to @rpath so the bundle is Homebrew-independent.

resolve_dep() {
    local dep="$1"
    case "$dep" in
        @rpath/*|@loader_path/*|@executable_path/*)
            local name="$(basename "$dep")"
            local d
            for d in /opt/homebrew/lib /opt/homebrew/opt/*/lib /usr/local/lib; do
                if [ -f "$d/$name" ]; then echo "$d/$name"; return 0; fi
            done
            return 1
            ;;
        /*)
            [ -f "$dep" ] && echo "$dep"
            ;;
    esac
}

SEEN_FILE="$(mktemp)"
trap 'rm -f "$SEEN_FILE" "$QUEUE_FILE"' EXIT
QUEUE_FILE="$(mktemp)"
echo "$OUT_DIR/openconnect" > "$QUEUE_FILE"

while [ -s "$QUEUE_FILE" ]; do
    CURRENT="$(head -n 1 "$QUEUE_FILE")"
    tail -n +2 "$QUEUE_FILE" > "$QUEUE_FILE.tmp" && mv "$QUEUE_FILE.tmp" "$QUEUE_FILE"

    # deps of the current Mach-O, excluding system libs and self-id
    while IFS= read -r dep; do
        [ -z "$dep" ] && continue
        case "$dep" in
            /usr/lib/*|/System/*) continue ;;
        esac

        REAL="$(resolve_dep "$dep" || true)"
        [ -z "${REAL:-}" ] && { echo "!! unresolved dep: $dep (referenced by $CURRENT)"; continue; }
        BASE="$(basename "$REAL")"

        if ! grep -qxF "$BASE" "$SEEN_FILE"; then
            echo "$BASE" >> "$SEEN_FILE"
            cp "$REAL" "$FW_DIR/$BASE"
            chmod +w "$FW_DIR/$BASE"
            install_name_tool -id "@rpath/$BASE" "$FW_DIR/$BASE" 2>/dev/null || true
            install_name_tool -add_rpath "@loader_path" "$FW_DIR/$BASE" 2>/dev/null || true
            echo "$FW_DIR/$BASE" >> "$QUEUE_FILE"
        fi

        # repoint the reference in CURRENT to @rpath
        install_name_tool -change "$dep" "@rpath/$BASE" "$CURRENT" 2>/dev/null || true
    done < <(otool -L "$CURRENT" | awk 'NR>1 {print $1}')
done

install_name_tool -add_rpath "@executable_path/../Frameworks" "$OUT_DIR/openconnect" 2>/dev/null || true
# also valid in the build/core layout (openconnect next to Frameworks/)
install_name_tool -add_rpath "@executable_path/Frameworks" "$OUT_DIR/openconnect" 2>/dev/null || true

# install_name_tool invalidates signatures; re-sign ad-hoc (required on arm64)
for f in "$FW_DIR"/*.dylib "$OUT_DIR/openconnect"; do
    [ -e "$f" ] && codesign --force --sign - "$f"
done

# --- verify -------------------------------------------------------------------
echo "==> bundled dylibs:"
ls "$FW_DIR"
echo "==> remaining non-system references (should be empty):"
if otool -L "$OUT_DIR/openconnect" "$FW_DIR"/*.dylib 2>/dev/null | awk 'NR>1 && $1 ~ /^\// {print $1}' | grep -v '^/usr/lib/' | grep -v '^/System/' | sort -u; then :; fi

echo "==> core bundle ready: $OUT_DIR"
"$OUT_DIR/openconnect" --version | head -1

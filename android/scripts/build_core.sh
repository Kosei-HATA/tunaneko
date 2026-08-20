#!/bin/bash
# Build libopenconnect + dependencies for Android using openconnect's own
# android/Makefile, adapted for a macOS host NDK.
#
# Usage: scripts/build_core.sh [arm64|x86_64|all]
# Output: native-build/<triplet>/sysroot/usr/{lib,include} and
#         app/libs/<abi>/libopenconnect.so (+ dependency .so files)
set -euo pipefail

OC_VERSION="9.21"
OC_SHA256="5b32369467db6e5f317aa1ed12cfcbb81ed00bdbc765450b6bfcbdc300944a58"
OC_URL="https://www.infradead.org/openconnect/download/openconnect-${OC_VERSION}.tar.gz"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/native-build"
SRC_DIR="$BUILD_DIR/openconnect-${OC_VERSION}"
ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"

# locate the newest installed NDK
NDK=$(ls -d "$ANDROID_HOME"/ndk/* 2>/dev/null | sort -V | tail -1)
[ -n "${NDK:-}" ] || { echo "NDK not found under $ANDROID_HOME/ndk"; exit 1; }

HOST_TAG="darwin-x86_64"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG"
[ -d "$TOOLCHAIN" ] || { echo "NDK toolchain not found: $TOOLCHAIN"; exit 1; }

WHICH="${1:-arm64}"

# GNU patch shim: macOS BSD patch lacks --follow-symlinks used by the Makefile
mkdir -p "$BUILD_DIR/bin"
if command -v gpatch >/dev/null 2>&1; then
    ln -sf "$(command -v gpatch)" "$BUILD_DIR/bin/patch"
    export PATH="$BUILD_DIR/bin:$PATH"
fi
case "$WHICH" in
    arm64)  ARCHES="arm64" ;;
    x86_64) ARCHES="x86_64" ;;
    all)    ARCHES="arm64 x86_64" ;;
    *) echo "usage: $0 [arm64|x86_64|all]"; exit 1 ;;
esac

# --- fetch & extract openconnect source --------------------------------------
TARBALL="$BUILD_DIR/openconnect-${OC_VERSION}.tar.gz"
mkdir -p "$BUILD_DIR"
if [ ! -f "$TARBALL" ]; then
    echo "==> downloading $OC_URL"
    curl -fL "$OC_URL" -o "$TARBALL"
fi
echo "$OC_SHA256  $TARBALL" | shasum -a 256 -c -
[ -d "$SRC_DIR" ] || tar -xzf "$TARBALL" -C "$BUILD_DIR"

cd "$SRC_DIR/android"

for ARCH in $ARCHES; do
    echo "==> building for ARCH=$ARCH (NDK: $(basename "$NDK"), host: $HOST_TAG)"
    # -fPIC: deps are static archives linked into a shared lib
    # -Wno-*: gnulib in gnutls trips on clang C99 strictness (NDK r27)
    make NDK="$NDK" TOOLCHAIN="$TOOLCHAIN" ARCH="$ARCH" \
         EXTRA_CFLAGS="-D__ANDROID_API__=23 -O2 -fPIC -Wno-macro-redefined -Wno-implicit-function-declaration -Wno-int-conversion -Wno-incompatible-pointer-types -Wno-implicit-int" \
         -j"$(sysctl -n hw.ncpu)" all

    case "$ARCH" in
        arm64)  TRIPLET="aarch64-linux-android"; ABI="arm64-v8a" ;;
        x86_64) TRIPLET="x86_64-linux-android";  ABI="x86_64" ;;
    esac
    OUT_LIB="$SRC_DIR/android/$TRIPLET/out/lib"
    OUT_INC="$SRC_DIR/android/$TRIPLET/out/include"
    OUT="$ROOT/app/libs/$ABI"
    mkdir -p "$OUT"
    # deps are statically linked into libopenconnect.so; only it is needed
    cp "$OUT_LIB/libopenconnect.so" "$OUT/"
    # public header for the JNI build (one copy is enough)
    cp "$OUT_INC/openconnect.h" "$SRC_DIR/android/" 2>/dev/null || true
    echo "==> $ABI libs:" && ls "$OUT"
done

echo "==> done"

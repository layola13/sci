#!/bin/sh
# SA FreeBSD cross-compilation helper (Linux host, Zig 0.14.1).
#
# Zig 0.14.1 ships no FreeBSD host binary and no bundled FreeBSD libc, so a
# FreeBSD sysroot (base.txz) plus a libc installation file are required.
# This script fetches base.txz once, extracts it, generates the libc file,
# and runs the build through the -Dsysroot/-Dlibc build.zig options.
#
# Usage:
#   sh tools/build_freebsd.sh [--target TRIPLE] [--prefix DIR] [--sysroot DIR]
# Defaults: TRIPLE=x86_64-freebsd, PREFIX=zig-out-freebsd,
#   SYSROOT=/tmp/fbsd/sysroot (downloads 14.4-RELEASE base.txz if missing).
#
# Native alternative: on a FreeBSD host with Zig from ports
# (pkg install zig), plain `zig build` works with no extra flags.

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="x86_64-freebsd"
PREFIX="$REPO_ROOT/zig-out-freebsd"
SYSROOT="/tmp/fbsd/sysroot"
BASE_URL="https://download.freebsd.org/releases/amd64/14.4-RELEASE/base.txz"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target) TARGET="$2"; shift 2 ;;
        --prefix) PREFIX="$2"; shift 2 ;;
        --sysroot) SYSROOT="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

if ! command -v zig >/dev/null 2>&1; then
    echo "error: zig not found in PATH" >&2
    exit 1
fi

if [ ! -f "$SYSROOT/usr/include/stdlib.h" ]; then
    echo "[i] sysroot missing at $SYSROOT, fetching base.txz..."
    mkdir -p "$SYSROOT"
    TMP_TXZ="$(mktemp /tmp/freebsd-base-XXXXXX.txz)"
    trap 'rm -f "$TMP_TXZ"' EXIT INT TERM
    curl -sL -o "$TMP_TXZ" "$BASE_URL"
    tar -xf "$TMP_TXZ" -C "$SYSROOT"
    rm -f "$TMP_TXZ"
    trap - EXIT INT TERM
fi

for f in usr/include/stdlib.h usr/lib/Scrt1.o usr/lib/libc.so; do
    if [ ! -e "$SYSROOT/$f" ]; then
        echo "error: sysroot incomplete, missing $f" >&2
        exit 1
    fi
done

LIBC_FILE="$SYSROOT/../freebsd-libc.txt"
if [ ! -f "$LIBC_FILE" ]; then
    printf 'include_dir=%s/usr/include\nsys_include_dir=%s/usr/include\ncrt_dir=%s/usr/lib\nmsvc_lib_dir=\nkernel32_lib_dir=\ngcc_dir=\n' \
        "$SYSROOT" "$SYSROOT" "$SYSROOT" > "$LIBC_FILE"
fi

echo "[i] building $TARGET (sysroot=$SYSROOT)..."
cd "$REPO_ROOT"
zig build -Dtarget="$TARGET" -Dllvm=false \
    -Dsysroot="$SYSROOT" -Dlibc="$LIBC_FILE" -p "$PREFIX"
echo "[✓] FreeBSD build installed to $PREFIX"
ls "$PREFIX/bin"

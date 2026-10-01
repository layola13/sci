#!/bin/sh
# Stage verified `sa` binaries from sci build outputs into the platform
# package dirs (packages/sa-*/bin/). Binaries are build artifacts, not
# hand-written sources: rebuild them from sci when the toolchain changes.
#
# Usage:
#   sh tools/stage-binaries.sh [--dist DIR]
# Default DIR is /tmp/sa-dist with the layout produced by the verified builds:
#   linux-x86_64/ windows-x86_64/ arm-aarch64/ mac-aarch64/ mac-x86_64/
#   freebsd-x86_64/  (each containing bin/sa or bin/sa.exe)
#
# To rebuild from source instead, see the "多平台编译" chapter in sala/
# (content/13_build/): native `zig build` for Linux, cross triples for the
# rest, tools/build_freebsd.sh for FreeBSD.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${1:---dist}"
if [ "$DIST" = "--dist" ]; then DIST="${2:-/tmp/sa-dist}"; else DIST="$DIST"; fi

stage() {
    # $1 = dist subdir, $2 = package suffix, $3 = binary name
    src="$DIST/$1/bin/$3"
    dst="$ROOT/packages/sa-$2/bin/$3"
    if [ ! -f "$src" ]; then
        echo "[skip] missing $src (build that target first)"
        return 0
    fi
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "[ok] sa-$2 <= $src ($(du -h "$dst" | cut -f1))"
}

stage linux-x86_64   linux-x64   sa
stage arm-aarch64    linux-arm64 sa
stage mac-aarch64    darwin-arm64 sa
stage mac-x86_64     darwin-x64  sa
stage windows-x86_64 win32-x64   sa.exe
stage freebsd-x86_64 freebsd-x64 sa

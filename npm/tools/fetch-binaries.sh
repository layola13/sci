#!/bin/sh
# Fetch prebuilt `sa` binaries from a GitHub Release into the platform
# package dirs. Used when publishing from a machine that cannot (or need
# not) rebuild every target — e.g. a Windows laptop publishing @salang/sa.
#
# Binaries are intentionally NOT committed to git (~95MB); the GitHub
# Release is the binary store. Rebuilding instead? See stage-binaries.sh
# and the sala "多平台编译" chapter.
#
# Usage: sh tools/fetch-binaries.sh [--version VER]   (default: 0.1.2)

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VER="0.1.2"
if [ "${1:-}" = "--version" ]; then VER="$2"; fi
BASE="https://github.com/layola13/sci/releases/download/$VER"

fetch() {
    # $1 = release asset suffix (e.g. linux-x86_64), $2 = package suffix,
    # $3 = binary name in package
    url="$BASE/sa-$VER-$1.zip"
    dst="$ROOT/packages/sa-$2/bin/$3"
    tmp="$(mktemp /tmp/sa-fetch-XXXXXX.zip)"
    trap 'rm -f "$tmp"' EXIT INT TERM
    echo "[i] $url"
    curl -sSL -o "$tmp" "$url"
    # -j: flatten; only the requested binary (skip hubproxy/pdb).
    unzip -q -o -j "$tmp" "$3" -d "$ROOT/packages/sa-$2/bin"
    rm -f "$tmp"
    trap - EXIT INT TERM
    chmod +x "$dst"
    echo "[ok] sa-$2 <= sa-$VER-$1.zip ($(du -h "$dst" | cut -f1))"
}

fetch linux-x86_64   linux-x64   sa
fetch arm-aarch64    linux-arm64 sa
fetch mac-aarch64    darwin-arm64 sa
fetch mac-x86_64     darwin-x64  sa
fetch windows-x86_64 win32-x64   sa.exe
fetch freebsd-x86_64 freebsd-x64 sa

# Stage the SA source stdlib (platform-independent) into the @salang/sa
# meta package. Sources, not binaries: copy straight from this checkout
# (same tag as the release being published).
rm -rf "$ROOT/packages/sa/sa_std"
cp -r "$ROOT/../sa_std" "$ROOT/packages/sa/sa_std"
echo "[ok] sa stdlib <= $ROOT/../sa_std"

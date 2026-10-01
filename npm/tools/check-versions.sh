#!/bin/sh
# Pre-publish guard: every staged binary must exist. Its embedded version is
# reported but no longer required to equal package.json (`sa --version` is
# baked at compile time from the git tag, so the two may legitimately differ).
#
# Usage: sh tools/check-versions.sh   (run from sci repo root: sh npm/tools/check-versions.sh)
# Exit 0 = all binaries present, non-zero = missing binary.

set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

check() {
    # $1 = package suffix, $2 = binary name
    pkg="$ROOT/packages/sa-$1/package.json"
    bin="$ROOT/packages/sa-$1/bin/$2"
    want="$(grep -m1 '"version"' "$pkg" | sed 's/.*: *"//;s/".*//')"
    if [ ! -f "$bin" ]; then
        echo "[MISS] sa-$1: binary $2 not staged"; fail=1; return
    fi
    if strings "$bin" | grep -qx "$want"; then
        echo "[ok] sa-$1: binary embeds $want"
    else
        echo "[WARN] sa-$1: package.json says $want but binary does not embed it (allowed)"
    fi
}

check linux-x64   sa
check linux-arm64 sa
check darwin-arm64 sa
check darwin-x64  sa
check win32-x64   sa.exe
check freebsd-x64 sa

exit $fail

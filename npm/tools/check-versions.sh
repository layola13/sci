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

# LLVM runtime contract: linux/freebsd binaries link libLLVM-14 dynamically;
# they must either bundle it in bin/ or the publish must be blocked with a
# clear message (this is the libLLVM-14.so.1 failure users hit on Ubuntu 24.04).
check_bundled() {
    # $1 = package suffix
    bin_dir="$ROOT/packages/sa-$1/bin"
    [ -d "$bin_dir" ] || return 0
    case "$1" in
        linux-*|freebsd-*)
            if ls "$bin_dir"/libLLVM*.so* >/dev/null 2>&1; then
                echo "[ok] sa-$1: bundles LLVM runtime"
            else
                echo "[WARN] sa-$1: no bundled libLLVM*.so* — users without system llvm14 will hit 'libLLVM-14.so.1: cannot open shared object file' (Ubuntu 24.04 needs libllvm14t64)"
                if command -v ldd >/dev/null 2>&1 && [ -f "$bin_dir/sa" ]; then
                    ldd "$bin_dir/sa" 2>/dev/null | grep -i "llvm.*not found" && echo "[WARN] sa-$1: confirmed unresolved libLLVM (see ldd above)" || true
                fi
            fi
            ;;
        darwin-*)
            if ls "$bin_dir"/*.dylib >/dev/null 2>&1; then
                echo "[ok] sa-$1: bundles LLVM dylib"
            else
                echo "[WARN] sa-$1: no bundled dylib — users will need 'brew install llvm@14'"
            fi
            ;;
        win32-*)
            if [ -f "$bin_dir/LLVM-C.dll" ]; then
                echo "[ok] sa-$1: bundles LLVM-C.dll"
            else
                echo "[WARN] sa-$1: LLVM-C.dll missing — sa.exe will fail on machines without LLVM on PATH"
            fi
            ;;
    esac
}

for p in linux-x64 linux-arm64 darwin-arm64 darwin-x64 win32-x64 freebsd-x64; do
    check_bundled "$p"
done

exit $fail

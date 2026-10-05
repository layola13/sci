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
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "[ok] sa-$2 <= $src ($(du -h "$dst" | cut -f1))"
}

# LLVM runtime to bundle (host path that built the staged binary).
# Override per-target via env when cross-staging, e.g.:
#   LLVM_LIB_DIR_LINUX_X64=/usr/lib/llvm-14/lib sh tools/stage-binaries.sh
LLVM_LIB_DIR_DEFAULT="${LLVM_LIB_DIR:-/usr/lib/llvm-14/lib}"
LLVM_LIB_DIR_LINUX_X64="${LLVM_LIB_DIR_LINUX_X64:-$LLVM_LIB_DIR_DEFAULT}"
LLVM_LIB_DIR_LINUX_ARM64="${LLVM_LIB_DIR_LINUX_ARM64:-$LLVM_LIB_DIR_DEFAULT}"
LLVM_LIB_DIR_FREEBSD_X64="${LLVM_LIB_DIR_FREEBSD_X64:-$LLVM_LIB_DIR_DEFAULT}"
# macOS brew layouts (arm64 vs x64 differ); first existing dir wins.
LLVM_LIB_DIR_DARWIN_ARM64="${LLVM_LIB_DIR_DARWIN_ARM64:-/opt/homebrew/opt/llvm@14/lib}"
LLVM_LIB_DIR_DARWIN_X64="${LLVM_LIB_DIR_DARWIN_X64:-/usr/local/opt/llvm@14/lib}"
# Windows: LLVM lib dir holds LLVM-C.lib; the runtime DLL lives in ../bin.
LLVM_LIB_DIR_WIN32_X64="${LLVM_LIB_DIR_WIN32_X64:-${LLVM_LIB_DIR_WINDOWS:-C:/Program Files/LLVM/lib}}"

bundle_linux_lib() {
    # $1 = package suffix (linux-x64), $2 = llvm lib dir
    pkg_bin="$ROOT/packages/sa-$1/bin"
    [ -f "$pkg_bin/sa" ] || return 0
    # Bootstrap (-Dllvm=false) binaries have no LLVM dependency: nothing to
    # bundle (avoids shipping a wrong-arch libLLVM into arm64/freebsd pkgs).
    if command -v ldd >/dev/null 2>&1 && ! ldd "$pkg_bin/sa" 2>/dev/null | grep -qi "libllvm"; then
        echo "[ok] sa-$1: bootstrap binary, no LLVM runtime to bundle"
        return 0
    fi
    for cand in "$2/libLLVM-14.so.1" "$2/libLLVM.so.14" "$2/libLLVM-14.so" "$2/libLLVM.so.1"; do
        if [ -f "$cand" ]; then
            cp -f "$cand" "$pkg_bin/"
            echo "[ok] sa-$1 bundles $(basename "$cand") ($(du -h "$pkg_bin/$(basename "$cand")" | cut -f1))"
            if command -v patchelf >/dev/null 2>&1; then
                patchelf --set-rpath '$ORIGIN' "$pkg_bin/sa" 2>/dev/null \
                    && echo "[ok] sa-$1 rpath -> \$ORIGIN" \
                    || echo "[warn] sa-$1 patchelf rpath failed (launcher LD_LIBRARY_PATH fallback still applies)"
            else
                echo "[warn] sa-$1 patchelf not found; skipping rpath (launcher LD_LIBRARY_PATH fallback still applies)"
            fi
            # Quick contract check: staged binary must resolve without system lib.
            # (Skipped for foreign-OS binaries: host ldd cannot resolve
            # FreeBSD libs like libc.so.7/libthr.so.3 — those ship with the OS.)
            if command -v ldd >/dev/null 2>&1 && ! file "$pkg_bin/sa" | grep -qi "freebsd"; then
                if LD_LIBRARY_PATH="$pkg_bin" ldd "$pkg_bin/sa" 2>&1 | grep -q "not found"; then
                    echo "[warn] sa-$1 still has unresolved libs:"; LD_LIBRARY_PATH="$pkg_bin" ldd "$pkg_bin/sa" | grep "not found" || true
                fi
            fi
            return 0
        fi
    done
    echo "[warn] sa-$1 no libLLVM found in $2; binary will need system libllvm14(t64) (see launcher hint)"
}

bundle_darwin_lib() {
    # $1 = package suffix (darwin-arm64), $2 = llvm lib dir
    pkg_bin="$ROOT/packages/sa-$1/bin"
    [ -f "$pkg_bin/sa" ] || return 0
    for cand in "$2/libLLVM.dylib" "$2/libLLVM-C.dylib"; do
        if [ -f "$cand" ]; then
            cp -f "$cand" "$pkg_bin/"
            echo "[ok] sa-$1 bundles $(basename "$cand")"
            if command -v install_name_tool >/dev/null 2>&1; then
                install_name_tool -add_rpath "@loader_path" "$pkg_bin/sa" 2>/dev/null \
                    && echo "[ok] sa-$1 rpath -> @loader_path" \
                    || echo "[warn] sa-$1 install_name_tool rpath failed (launcher DYLD_* fallback still applies)"
            fi
            return 0
        fi
    done
    echo "[warn] sa-$1 no libLLVM.dylib in $2; will need 'brew install llvm@14'"
}

bundle_windows_dll() {
    # $1 = package suffix (win32-x64), $2 = llvm lib dir
    pkg_bin="$ROOT/packages/sa-$1/bin"
    [ -f "$pkg_bin/sa.exe" ] || return 0
    for cand in "$2/../bin/LLVM-C.dll" "$2/LLVM-C.dll" "/c/Program Files/LLVM/bin/LLVM-C.dll" "C:/Program Files/LLVM/bin/LLVM-C.dll"; do
        if [ -f "$cand" ]; then
            cp -f "$cand" "$pkg_bin/LLVM-C.dll"
            echo "[ok] sa-$1 bundles LLVM-C.dll"
            return 0
        fi
    done
    echo "[warn] sa-$1 LLVM-C.dll not found near $2; win32 package will need LLVM on PATH"
}

stage linux-x86_64   linux-x64   sa
stage arm-aarch64    linux-arm64 sa
stage mac-aarch64    darwin-arm64 sa
stage mac-x86_64     darwin-x64  sa
stage windows-x86_64 win32-x64   sa.exe
stage freebsd-x86_64 freebsd-x64 sa

# Bundle LLVM runtimes next to the staged binaries so `npm install -g`
# works without system LLVM. Launcher bin/sa.js also prepends bin/ to the
# loader path, so bundled libs win even when rpath tools are unavailable.
bundle_linux_lib linux-x64 "$LLVM_LIB_DIR_LINUX_X64"
bundle_linux_lib linux-arm64 "$LLVM_LIB_DIR_LINUX_ARM64"
bundle_linux_lib freebsd-x64 "$LLVM_LIB_DIR_FREEBSD_X64"
bundle_darwin_lib darwin-arm64 "$LLVM_LIB_DIR_DARWIN_ARM64"
bundle_darwin_lib darwin-x64 "$LLVM_LIB_DIR_DARWIN_X64"
bundle_windows_dll win32-x64 "$LLVM_LIB_DIR_WIN32_X64"

# Stage the SA source stdlib (platform-independent) into the @salang/sa
# meta package. Sources, not binaries: copy straight from this checkout
# (same tag as the release being published).
rm -rf "$ROOT/packages/sa/sa_std"
cp -r "$ROOT/../sa_std" "$ROOT/packages/sa/sa_std"
echo "[ok] sa stdlib <= $ROOT/../sa_std"

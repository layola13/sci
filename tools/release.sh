#!/bin/sh

# SA (System Architecture) Release Packager
#
# Automates compiling and packaging SA toolchain for multiple platforms.
# Leverages Zig's out-of-the-box cross-compilation capabilities.

set -eu

# Color and Styling Definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info() {
    printf "${BLUE}[i]${RESET} %s\n" "$1"
}

working() {
    printf "${CYAN}[>]${RESET} %s..." "$1"
}

success() {
    printf "${GREEN}[✓]${RESET} %s\n" "$1"
}

warn() {
    printf "${YELLOW}[!]${RESET} %s\n" "$1"
}

error() {
    printf "${RED}[✗]${RESET} ${BOLD}Error:${RESET} %s\n" "$1" >&2
    exit 1
}

# Verify Zig compiler is present
if ! command -v zig >/dev/null 2>&1; then
    error "Zig compiler not found. Zig is required to build SA releases."
fi

# Root directory of the repository
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"

info "Cleaning up old build environments..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Targets definition: OS, ARCH, Zig Target String, Format (tar.gz or zip)
# Format: "OS;ARCH;ZIG_TARGET;ARCHIVE_FORMAT"
TARGETS="
linux;x86_64;x86_64-linux-musl;tar.gz
linux;aarch64;aarch64-linux-musl;tar.gz
macos;x86_64;x86_64-macos;tar.gz
macos;aarch64;aarch64-macos;tar.gz
windows;x86_64;x86_64-windows-gnu;zip
"

build_target() {
    OS="$1"
    ARCH="$2"
    ZIG_TARGET="$3"
    FORMAT="$4"
    
    TARGET_NAME="sa-${OS}-${ARCH}"
    TARGET_DIR="$DIST_DIR/$TARGET_NAME"
    
    info "--------------------------------------------------"
    info "Building target: ${BOLD}$TARGET_NAME${RESET} ($ZIG_TARGET)"
    
    # 1. Clean previous build artifact directories
    rm -rf "$REPO_ROOT/zig-out"
    rm -rf "$REPO_ROOT/.zig-cache"
    
    # 2. Build SA Compiler
    working "Compiling saasm compiler"
    if ! zig build -Dtarget="$ZIG_TARGET" -Doptimize=ReleaseSafe >/dev/null 2>&1; then
        printf " failed.\n"
        error "Zig compilation failed for target: $ZIG_TARGET"
    fi
    printf " done!\n"
    
    # 3. Create target directory layout
    mkdir -p "$TARGET_DIR/bin"
    mkdir -p "$TARGET_DIR/std"
    
    # 4. Copy SAASM Executable
    EXE_FILE="saasm"
    if [ "$OS" = "windows" ]; then
        EXE_FILE="saasm.exe"
    fi
    
    if [ -f "$REPO_ROOT/zig-out/bin/$EXE_FILE" ]; then
        cp -f "$REPO_ROOT/zig-out/bin/$EXE_FILE" "$TARGET_DIR/bin/"
        if [ "$OS" != "windows" ]; then
            chmod +x "$TARGET_DIR/bin/$EXE_FILE"
        fi
    else
        error "Compiled binary $EXE_FILE not found in zig-out/bin"
    fi
    
    # 5. Copy Standard Library sources
    if [ -d "$REPO_ROOT/sa_std" ]; then
        cp -rf "$REPO_ROOT/sa_std/"* "$TARGET_DIR/std/"
    fi
    
    # 6. Copy static runtime library if built
    # Some targets compile static libraries in zig-out/lib
    LIB_FILE="libsa_std.a"
    if [ "$OS" = "windows" ]; then
        LIB_FILE="sa_std.lib"
    fi
    
    if [ -f "$REPO_ROOT/zig-out/lib/$LIB_FILE" ]; then
        cp -f "$REPO_ROOT/zig-out/lib/$LIB_FILE" "$TARGET_DIR/std/"
    else
        # Try finding standard library from workspace artifacts if zig build skips cross-compiling static library in standard step
        if [ -f "$REPO_ROOT/artifacts/sa_std/libsa_std.a" ] && [ "$OS" = "linux" ]; then
            cp -f "$REPO_ROOT/artifacts/sa_std/libsa_std.a" "$TARGET_DIR/std/$LIB_FILE"
        fi
    fi
    
    # Copy header
    if [ -f "$REPO_ROOT/src/runtime/sa_std.h" ]; then
        cp -f "$REPO_ROOT/src/runtime/sa_std.h" "$TARGET_DIR/std/"
    elif [ -f "$REPO_ROOT/zig-out/include/sa_std.h" ]; then
        cp -f "$REPO_ROOT/zig-out/include/sa_std.h" "$TARGET_DIR/std/"
    fi
    
    # 7. Compress Package
    working "Packaging archive"
    cd "$DIST_DIR"
    if [ "$FORMAT" = "tar.gz" ]; then
        tar -czf "$TARGET_NAME.tar.gz" "$TARGET_NAME"
        success "Created $TARGET_NAME.tar.gz"
    elif [ "$FORMAT" = "zip" ]; then
        if command -v zip >/dev/null 2>&1; then
            zip -rq "$TARGET_NAME.zip" "$TARGET_NAME"
            success "Created $TARGET_NAME.zip"
        else
            warn "'zip' command not found. Copying directory raw (skipping compression)."
        fi
    fi
    
    # Clean raw target dir after archiving
    rm -rf "$TARGET_DIR"
    cd "$REPO_ROOT"
}

# Run through target builds
for TARGET in $TARGETS; do
    if [ -z "$TARGET" ]; then continue; fi
    
    # Split fields
    OLD_IFS="$IFS"
    IFS=";"
    set -- $TARGET
    IFS="$OLD_IFS"
    
    build_target "$1" "$2" "$3" "$4"
done

# Compute checksums
info "--------------------------------------------------"
working "Generating SHA256 checksums"
cd "$DIST_DIR"
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum sa-* > sha256sums.txt
    printf " done!\n"
    success "Generated checksums file at dist/sha256sums.txt"
elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 sa-* > sha256sums.txt
    printf " done!\n"
    success "Generated checksums file at dist/sha256sums.txt"
else
    printf " skipped (no shasum tool found).\n"
fi

cd "$REPO_ROOT"
success "Release compilation and packaging completed successfully!"

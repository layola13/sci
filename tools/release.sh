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

latest_source_tag() {
    if command -v git >/dev/null 2>&1; then
        GIT_TAG="$(git -C "$REPO_ROOT" tag --sort=-v:refname 2>/dev/null | sed -n '1p')"
        if [ -n "$GIT_TAG" ]; then
            printf "%s" "$GIT_TAG"
            return 0
        fi
    fi

    printf "0.0.1"
}

VERSION="${SA_VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION="$(latest_source_tag)"
fi
VERSION="${VERSION#v}"
LLVM_INCLUDE_DIR="${LLVM_INCLUDE_DIR:-/usr/lib/llvm-14/include}"
LLVM_LIB_DIR="${LLVM_LIB_DIR:-/usr/lib/llvm-14/lib}"
LLVM_LIB_NAME="${LLVM_LIB_NAME:-LLVM-14}"

info "Cleaning up old build environments..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# Targets definition: OS, ARCH, Zig Target String, Format (tar.gz or zip)
# Format: "OS;ARCH;ZIG_TARGET;ARCHIVE_FORMAT"
DEFAULT_TARGETS="
linux;x86_64;x86_64-linux-gnu;tar.gz
# linux;aarch64;aarch64-linux-gnu;tar.gz
# macos;x86_64;x86_64-macos;tar.gz
# macos;aarch64;aarch64-macos;tar.gz
# windows;x86_64;x86_64-windows-gnu;zip
# windows;aarch64;aarch64-windows-gnu;zip
"
TARGETS="${SA_TARGETS:-$DEFAULT_TARGETS}"

verify_payload_layout() {
    PAYLOAD_ROOT="$1"
    EXE_FILE="$2"
    LIB_FILE="$3"

    for PAYLOAD_PATH in \
        "bin/$EXE_FILE" \
        "std/$LIB_FILE" \
        "std/sa_std.h" \
        "std/io/print.sai" \
        "std/core/sa_core.sa" \
        "std/core/result.sa" \
        "std/core/option.sa"
    do
        [ -f "$PAYLOAD_ROOT/$PAYLOAD_PATH" ] || error "Package payload missing $PAYLOAD_PATH"
    done
}

verify_archive_payload() {
    ARCHIVE_PATH="$1"
    ARCHIVE_FORMAT="$2"
    ARCHIVE_TARGET_NAME="$3"
    ARCHIVE_EXE_FILE="$4"
    ARCHIVE_LIB_FILE="$5"
    ARCHIVE_VERIFY_DIR="$DIST_DIR/.verify-$ARCHIVE_TARGET_NAME"

    rm -rf "$ARCHIVE_VERIFY_DIR"
    mkdir -p "$ARCHIVE_VERIFY_DIR"

    case "$ARCHIVE_FORMAT" in
        tar.gz)
            tar -tzf "$ARCHIVE_PATH" >/dev/null || error "Archive integrity check failed: $ARCHIVE_PATH"
            tar -xzf "$ARCHIVE_PATH" -C "$ARCHIVE_VERIFY_DIR"
            ;;
        zip)
            command -v unzip >/dev/null 2>&1 || error "unzip is required to verify zip archives"
            unzip -tqq "$ARCHIVE_PATH" >/dev/null || error "Archive integrity check failed: $ARCHIVE_PATH"
            unzip -q "$ARCHIVE_PATH" -d "$ARCHIVE_VERIFY_DIR"
            ;;
        *)
            error "Unsupported archive format: $ARCHIVE_FORMAT"
            ;;
    esac

    verify_payload_layout "$ARCHIVE_VERIFY_DIR/$ARCHIVE_TARGET_NAME" "$ARCHIVE_EXE_FILE" "$ARCHIVE_LIB_FILE"
    rm -rf "$ARCHIVE_VERIFY_DIR"
}

archive_files() {
    for ARCHIVE_FILE in "$DIST_DIR"/sa-*.tar.gz "$DIST_DIR"/sa-*.zip; do
        [ -f "$ARCHIVE_FILE" ] || continue
        printf "%s\n" "$ARCHIVE_FILE"
    done | sort
}

checksum_hash() {
    CHECKSUM_FILE="$1"
    case "$CHECKSUM_TOOL" in
        sha256sum)
            CHECKSUM_OUTPUT="$(sha256sum "$CHECKSUM_FILE")"
            ;;
        shasum)
            CHECKSUM_OUTPUT="$(shasum -a 256 "$CHECKSUM_FILE")"
            ;;
        *)
            error "Unsupported checksum tool: $CHECKSUM_TOOL"
            ;;
    esac
    printf "%s\n" "${CHECKSUM_OUTPUT%% *}"
}

verify_checksum_sidecar() {
    CHECKSUM_ARCHIVE="$1"
    CHECKSUM_SIDECAR="$2"
    CHECKSUM_EXPECTED_NAME="$(basename "$CHECKSUM_ARCHIVE")"

    [ -f "$CHECKSUM_SIDECAR" ] || error "Checksum sidecar missing: $CHECKSUM_SIDECAR"
    CHECKSUM_LINE_COUNT="$(wc -l < "$CHECKSUM_SIDECAR" | tr -d '[:space:]')"
    [ "$CHECKSUM_LINE_COUNT" = "1" ] || error "Checksum sidecar must contain exactly one line: $CHECKSUM_SIDECAR"

    CHECKSUM_RECORDED_HASH=""
    CHECKSUM_RECORDED_NAME=""
    CHECKSUM_EXTRA=""
    read -r CHECKSUM_RECORDED_HASH CHECKSUM_RECORDED_NAME CHECKSUM_EXTRA < "$CHECKSUM_SIDECAR"
    [ "${#CHECKSUM_RECORDED_HASH}" -eq 64 ] || error "Invalid checksum hash in $CHECKSUM_SIDECAR"
    case "$CHECKSUM_RECORDED_HASH" in
        *[!0-9a-fA-F]*) error "Invalid checksum hash in $CHECKSUM_SIDECAR" ;;
    esac
    [ "$CHECKSUM_RECORDED_NAME" = "$CHECKSUM_EXPECTED_NAME" ] || error "Checksum sidecar names the wrong archive: $CHECKSUM_SIDECAR"
    [ -z "$CHECKSUM_EXTRA" ] || error "Checksum sidecar has extra fields: $CHECKSUM_SIDECAR"

    CHECKSUM_ACTUAL_HASH="$(checksum_hash "$CHECKSUM_ARCHIVE")"
    [ "$CHECKSUM_RECORDED_HASH" = "$CHECKSUM_ACTUAL_HASH" ] || error "Checksum verification failed: $CHECKSUM_ARCHIVE"
}

verify_checksum_manifest() {
    CHECKSUM_MANIFEST_PATH="$1"
    case "$CHECKSUM_TOOL" in
        sha256sum)
            sha256sum --check --strict "$CHECKSUM_MANIFEST_PATH" >/dev/null || error "Combined checksum verification failed"
            ;;
        shasum)
            shasum -a 256 --check "$CHECKSUM_MANIFEST_PATH" >/dev/null || error "Combined checksum verification failed"
            ;;
        *)
            error "Unsupported checksum tool: $CHECKSUM_TOOL"
            ;;
    esac
}

build_target() {
    OS="$1"
    ARCH="$2"
    ZIG_TARGET="$3"
    FORMAT="$4"
    
    TARGET_NAME="sa-${OS}-${ARCH}"
    TARGET_DIR="$DIST_DIR/$TARGET_NAME"
    BUILD_DIR="$DIST_DIR/.build-$TARGET_NAME"
    
    info "--------------------------------------------------"
    info "Building target: ${BOLD}$TARGET_NAME${RESET} ($ZIG_TARGET, version $VERSION)"
    
    # 1. Isolate installed release artifacts without deleting shared Zig caches.
    rm -rf "$BUILD_DIR" "$TARGET_DIR"
    
    # 2. Build SA Compiler
    working "Compiling sa compiler"
    BUILD_LOG="$DIST_DIR/.build-$TARGET_NAME.log"
    if ! zig build release-artifacts --prefix "$BUILD_DIR" -Dtarget="$ZIG_TARGET" -Doptimize=ReleaseSafe -Dversion="$VERSION" -Dllvm-include-dir="$LLVM_INCLUDE_DIR" -Dllvm-lib-dir="$LLVM_LIB_DIR" -Dllvm-lib-name="$LLVM_LIB_NAME" >"$BUILD_LOG" 2>&1; then
        printf " failed.\n"
        cat "$BUILD_LOG" >&2
        error "Zig compilation failed for target: $ZIG_TARGET"
    fi
    rm -f "$BUILD_LOG"
    printf " done!\n"
    
    # 3. Create target directory layout
    mkdir -p "$TARGET_DIR/bin"
    mkdir -p "$TARGET_DIR/lib"
    mkdir -p "$TARGET_DIR/std"
    
    # 4. Copy SAASM Executable
    EXE_FILE="sa"
    if [ "$OS" = "windows" ]; then
        EXE_FILE="sa.exe"
    fi
    
    if [ -f "$BUILD_DIR/bin/$EXE_FILE" ]; then
        cp -f "$BUILD_DIR/bin/$EXE_FILE" "$TARGET_DIR/bin/"
        if [ "$OS" != "windows" ]; then
            chmod +x "$TARGET_DIR/bin/$EXE_FILE"
        fi
    else
        error "Compiled binary $EXE_FILE not found in zig-out/bin"
    fi
    
    # 5. Copy Standard Library sources
    if [ -d "$REPO_ROOT/sa_std" ]; then
        cp -rf "$REPO_ROOT/sa_std/"* "$TARGET_DIR/std/"
    else
        error "Standard library source directory not found: $REPO_ROOT/sa_std"
    fi

    # 6. Copy static runtime library if built
    # Some targets compile static libraries in zig-out/lib
    LIB_FILE="libsa_std.a"
    if [ "$OS" = "windows" ]; then
        LIB_FILE="sa_std.lib"
    fi
    
    [ -f "$BUILD_DIR/lib/$LIB_FILE" ] || error "Compiled runtime $LIB_FILE not found in release build prefix"
    cp -f "$BUILD_DIR/lib/$LIB_FILE" "$TARGET_DIR/std/"
    
    # Copy header
    [ -f "$BUILD_DIR/include/sa_std.h" ] || error "Installed runtime header not found in release build prefix"
    cp -f "$BUILD_DIR/include/sa_std.h" "$TARGET_DIR/std/"

    verify_payload_layout "$TARGET_DIR" "$EXE_FILE" "$LIB_FILE"
    
    # 7. Compress Package
    working "Packaging archive"
    cd "$DIST_DIR"
    if [ "$FORMAT" = "tar.gz" ]; then
        ARCHIVE_PATH="$DIST_DIR/$TARGET_NAME.tar.gz"
        tar -czf "$ARCHIVE_PATH" "$TARGET_NAME"
        success "Created $TARGET_NAME.tar.gz"
    elif [ "$FORMAT" = "zip" ]; then
        command -v zip >/dev/null 2>&1 || error "zip is required to create zip archives"
        ARCHIVE_PATH="$DIST_DIR/$TARGET_NAME.zip"
        zip -rq "$ARCHIVE_PATH" "$TARGET_NAME"
        success "Created $TARGET_NAME.zip"
    else
        error "Unsupported archive format: $FORMAT"
    fi

    [ -s "$ARCHIVE_PATH" ] || error "Release archive was not created: $ARCHIVE_PATH"
    
    # Clean raw target dir after archiving
    rm -rf "$TARGET_DIR"
    verify_archive_payload "$ARCHIVE_PATH" "$FORMAT" "$TARGET_NAME" "$EXE_FILE" "$LIB_FILE"
    rm -rf "$BUILD_DIR"
    cd "$REPO_ROOT"
}

# Run through target builds
printf "%s\n" "$TARGETS" | while IFS= read -r TARGET; do
    TARGET="$(printf "%s" "$TARGET" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$TARGET" ] || continue
    case "$TARGET" in
        \#*) continue ;;
    esac

    # Split fields
    OLD_IFS="$IFS"
    IFS=";"
    set -- $TARGET
    IFS="$OLD_IFS"

    [ "$#" -eq 4 ] || error "Invalid target entry: $TARGET"
    build_target "$1" "$2" "$3" "$4"
done

# Compute and verify checksums
info "--------------------------------------------------"
working "Generating SHA256 checksums"
cd "$DIST_DIR"
if command -v sha256sum >/dev/null 2>&1; then
    CHECKSUM_TOOL="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    CHECKSUM_TOOL="shasum"
else
    printf " failed.\n"
    error "sha256sum or shasum is required to package releases"
fi

ARCHIVE_LIST="$(archive_files)"
[ -n "$ARCHIVE_LIST" ] || error "No release archives were generated"

CHECKSUM_MANIFEST="$DIST_DIR/sha256sums.txt"
: > "$CHECKSUM_MANIFEST"
printf "%s\n" "$ARCHIVE_LIST" | while IFS= read -r ARCHIVE_FILE; do
    [ -n "$ARCHIVE_FILE" ] || continue
    ARCHIVE_NAME="$(basename "$ARCHIVE_FILE")"
    SHA_LINE="$(checksum_hash "$ARCHIVE_FILE")  $ARCHIVE_NAME"
    printf "%s\n" "$SHA_LINE" >> "$CHECKSUM_MANIFEST"
    printf "%s\n" "$SHA_LINE" > "$ARCHIVE_FILE.sha256"
    verify_checksum_sidecar "$ARCHIVE_FILE" "$ARCHIVE_FILE.sha256"
done

[ -s "$CHECKSUM_MANIFEST" ] || error "Combined checksum manifest is empty"
printf "%s\n" "$ARCHIVE_LIST" | while IFS= read -r ARCHIVE_FILE; do
    [ -n "$ARCHIVE_FILE" ] || continue
    verify_checksum_sidecar "$ARCHIVE_FILE" "$ARCHIVE_FILE.sha256"
done
verify_checksum_manifest "$CHECKSUM_MANIFEST"

printf " done!\n"
success "Generated and verified checksums at dist/sha256sums.txt"

cd "$REPO_ROOT"
success "Release compilation and packaging completed successfully!"

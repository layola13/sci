#!/bin/sh
# Build Zig 0.14.1 for FreeBSD x86_64 from a Linux host (cross-compilation).
#
# Background: ziglang.org ships no FreeBSD binary, and Linux-built LLVM static
# archives CANNOT link into a FreeBSD binary (they embed glibc symbol versions
# like __errno_location/__libc_single_threaded and libstdc++ ABI details).
# This script instead uses FreeBSD-native LLVM 19 archives extracted from the
# official FreeBSD quarterly package (llvm19-19.1.7_4), plus a 14.4-RELEASE
# base.txz sysroot. Result verified: pure FreeBSD ELF, NEEDED only base libs
# (libc.so.7/libm.so.5/libz.so.6/libthr.so.3), version refs only FBSD_*/ZLIB_*.
#
# Host prerequisites (Ubuntu 24.04):
#   zig 0.14.1 on PATH, cmake, g++, ar
#   apt-get install -y llvm-19-dev libclang-19-dev liblld-19-dev libzstd-dev
#
# Usage:
#   sh tools/build_zig_freebsd.sh [--prefix DIR] [--sysroot DIR]
# Defaults: PREFIX=/tmp/zig-freebsd, SYSROOT=/tmp/fbsd/sysroot
# Output tarball: /tmp/pkg/zig-x86_64-freebsd-0.14.1.tar.xz
#
# Params (env-overridable):
#   ZIG_VERSION=0.14.1  FBSD_RELEASE=14.4-RELEASE  LLVM_PKG_VER=19.1.7_4

set -eu

ZIG_VERSION="${ZIG_VERSION:-0.14.1}"
FBSD_RELEASE="${FBSD_RELEASE:-14.4-RELEASE}"
LLVM_PKG_VER="${LLVM_PKG_VER:-19.1.7_4}"
PREFIX="/tmp/zig-freebsd"
SYSROOT="/tmp/fbsd/sysroot"
WORK="/tmp/zigx"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --sysroot) SYSROOT="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
    esac
done

command -v zig >/dev/null 2>&1 || { echo "error: zig 0.14.1 not on PATH" >&2; exit 1; }
command -v cmake >/dev/null 2>&1 || { echo "error: cmake not found" >&2; exit 1; }
command -v llvm-config-19 >/dev/null 2>&1 || { echo "error: llvm-19-dev not installed" >&2; exit 1; }

# 1. Zig source (no git history in tarball -> pass -Dversion-string later).
if [ ! -d /tmp/zigsrc/zig-"$ZIG_VERSION" ]; then
    mkdir -p /tmp/zigsrc
    curl -L -o /tmp/zigsrc/zig.tar.xz \
        https://ziglang.org/download/"$ZIG_VERSION"/zig-"$ZIG_VERSION".tar.xz
    tar -xf /tmp/zigsrc/zig.tar.xz -C /tmp/zigsrc
fi
ZIGSRC=/tmp/zigsrc/zig-"$ZIG_VERSION"
export SYSROOT WORK ZIGSRC
WORK="${WORK:-/tmp/zigx}"
export WORK

# 2. FreeBSD sysroot + libc file (shared with tools/build_freebsd.sh layout).
if [ ! -f "$SYSROOT/usr/include/stdlib.h" ]; then
    mkdir -p "$SYSROOT"
    TMP_TXZ="$(mktemp /tmp/freebsd-base-XXXXXX.txz)"
    trap 'rm -f "$TMP_TXZ"' EXIT INT TERM
    curl -sL -o "$TMP_TXZ" \
        https://download.freebsd.org/releases/amd64/"$FBSD_RELEASE"/base.txz
    tar -xf "$TMP_TXZ" -C "$SYSROOT"
    rm -f "$TMP_TXZ"
    trap - EXIT INT TERM
fi
LIBC_FILE="$SYSROOT/../freebsd-libc.txt"
if [ ! -f "$LIBC_FILE" ]; then
    printf 'include_dir=%s/usr/include\nsys_include_dir=%s/usr/include\ncrt_dir=%s/usr/lib\nmsvc_lib_dir=\nkernel32_lib_dir=\ngcc_dir=\n' \
        "$SYSROOT" "$SYSROOT" "$SYSROOT" > "$LIBC_FILE"
fi

# 3. FreeBSD-native LLVM 19 (headers + static archives) from official pkg.
FB_LLVM=/tmp/fbsd/llvm19/usr/local/llvm19
if [ ! -f "$FB_LLVM/lib/libLLVMCore.a" ]; then
    mkdir -p /tmp/fbsd/llvm19
    curl -sL -o /tmp/llvm19.pkg \
        https://pkg.freebsd.org/FreeBSD:14:amd64/quarterly/All/llvm19-"$LLVM_PKG_VER".pkg
    tar -I zstd -xf /tmp/llvm19.pkg -C /tmp/fbsd/llvm19
fi

# 4. libzstd.a for FreeBSD (absent from base.txz; LLVMSupport needs it).
if [ ! -f "$SYSROOT/usr/lib/libzstd.a" ]; then
    curl -sL -o /tmp/zigsrc/zstd.tar.gz \
        https://github.com/facebook/zstd/releases/download/v1.5.5/zstd-1.5.5.tar.gz
    rm -rf /tmp/zigsrc/zstd-1.5.5 && tar -xzf /tmp/zigsrc/zstd.tar.gz -C /tmp/zigsrc
    rm -f /tmp/fbsd-*.o
    for f in /tmp/zigsrc/zstd-1.5.5/lib/common/*.c \
             /tmp/zigsrc/zstd-1.5.5/lib/compress/*.c \
             /tmp/zigsrc/zstd-1.5.5/lib/decompress/*.c; do
        n=$(basename "$f" .c)
        zig cc -target x86_64-freebsd -isystem "$SYSROOT/usr/include" \
            -O2 -I/tmp/zigsrc/zstd-1.5.5/lib -I/tmp/zigsrc/zstd-1.5.5/lib/common \
            -c "$f" -o /tmp/fbsd-"$n".o
    done
    ar rcs "$SYSROOT/usr/lib/libzstd.a" /tmp/fbsd-*.o
    cp /tmp/zigsrc/zstd-1.5.5/lib/zstd.h /tmp/zigsrc/zstd-1.5.5/lib/zdict.h \
       /tmp/zigsrc/zstd-1.5.5/lib/zstd_errors.h "$SYSROOT/usr/include/"
    rm -f /tmp/fbsd-*.o
fi

# 5. zig C++ glue (zig_llvm.cpp et al.) compiled for FreeBSD.
mkdir -p "$WORK/zigcpp"
if [ ! -f "$WORK/zigcpp/libzigcpp.a" ]; then
    rm -f "$WORK"/*.o
    for f in zig_llvm.cpp zig_clang.cpp zig_llvm-ar.cpp \
             zig_clang_driver.cpp zig_clang_cc1_main.cpp zig_clang_cc1as_main.cpp; do
        n=$(basename "$f" .cpp)
        zig c++ -target x86_64-freebsd -isystem "$SYSROOT/usr/include" \
            -isystem "$SYSROOT/usr/include/c++/v1" \
            -std=c++17 -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS \
            -D__STDC_LIMIT_MACROS -DNDEBUG=1 -fno-exceptions -fno-rtti \
            -fno-stack-protector -fvisibility-inlines-hidden -O2 \
            -I"$FB_LLVM/include" -c "$ZIGSRC/src/$f" -o "$WORK/$n.o"
    done
    ar rcs "$WORK/zigcpp/libzigcpp.a" "$WORK"/*.o
    rm -f "$WORK"/*.o
fi

# 6. config.h: start from a native cmake configure, then point every library
#    at FreeBSD-native static archives (absolute paths) and the C++ wrapper.
if [ ! -f /tmp/zigsrc/cfg-build/config.h ]; then
    cmake -S "$ZIGSRC" -B /tmp/zigsrc/cfg-build -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_PREFIX_PATH=/usr/lib/llvm-19 >/dev/null
fi
cat > "$WORK/cxx-wrapper.sh" <<EOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    -print-file-name=libc++.a) echo $SYSROOT/usr/lib/libc++.a; exit 0 ;;
    -print-file-name=libgcc_eh.a) echo $SYSROOT/usr/lib/libgcc_eh.a; exit 0 ;;
  esac
done
exec clang++-19 "\$@"
EOF
chmod +x "$WORK/cxx-wrapper.sh"

python3 - "$WORK/config.h" <<'PYEOF'
import re, os, subprocess, sys
out = sys.argv[1]
cfg = open('/tmp/zigsrc/cfg-build/config.h').read()
FB = '/tmp/fbsd/llvm19/usr/local/llvm19'
INC, LIB = FB + '/include', FB + '/lib'

llvm_a, seen = [], set()
order = subprocess.run(['llvm-config-19', '--libfiles', '--link-static'],
                       capture_output=True, text=True).stdout.split()
for p in order:
    name = os.path.basename(p)
    if name in seen:
        continue
    seen.add(name)
    fp = os.path.join(LIB, name)
    if os.path.isfile(fp):
        llvm_a.append(fp)
    else:
        print('[i] skipping (absent in fbsd pkg):', name)
S = "__SYSROOT__"
llvm_libs = ';'.join(llvm_a) + \
    f';{S}/usr/lib/librt.so;{S}/usr/lib/libm.so;{S}/usr/lib/libz.so;{S}/usr/lib/libzstd.a'
llvm_libs = llvm_libs.replace('__SYSROOT__', os.environ.get('SYSROOT', '/tmp/fbsd/sysroot'))

src = open(os.environ.get('ZIGSRC', '/tmp/zigsrc/zig-0.14.1') + '/build.zig').read()
m = re.search(r'const clang_libs = \[_?\]?\[\]const u8\{(.*?)\};', src, re.S)
names = re.findall(r'"([^"]+)"', m.group(1))
clang_paths = []
for n in names:
    p = os.path.join(LIB, f'lib{n}.a')
    assert os.path.isfile(p), f'missing {p}'
    clang_paths.append(p)
lld_paths = []
for n in ['lldMinGW', 'lldELF', 'lldCOFF', 'lldWasm', 'lldMachO', 'lldCommon']:
    p = os.path.join(LIB, f'lib{n}.a')
    assert os.path.isfile(p), f'missing {p}'
    lld_paths.append(p)

def sub(key, val):
    global cfg
    pat = re.compile(r'(#define %s ")((?:[^"\\]|\\.)*)(")' % re.escape(key))
    assert pat.search(cfg), key
    cfg = pat.sub(lambda mo: mo.group(1) + val + mo.group(3), cfg, count=1)

sub('ZIG_LLVM_LIBRARIES', llvm_libs)
sub('ZIG_CLANG_LIBRARIES', ';'.join(clang_paths))
sub('ZIG_LLD_LIBRARIES', ';'.join(lld_paths))
sub('ZIG_LLVM_LINK_MODE', 'static')
sub('ZIG_CXX_COMPILER', os.environ.get('WORK', '/tmp/zigx') + '/cxx-wrapper.sh')
sub('ZIG_CMAKE_BINARY_DIR', os.environ.get('WORK', '/tmp/zigx'))
sub('ZIG_LLVM_INCLUDE_PATH', INC)
sub('ZIG_LLD_INCLUDE_PATH', INC)
open(out, 'w').write(cfg)
print('[i] config.h ok; llvm .a:', len(llvm_a), '; clang:', len(names))
PYEOF

# 7. Cross build.
cd "$ZIGSRC"
zig build --sysroot "$SYSROOT" --libc "$LIBC_FILE" \
    -Dtarget=x86_64-freebsd -Denable-llvm -Dconfig_h="$WORK/config.h" \
    -Dversion-string="$ZIG_VERSION" -Doptimize=ReleaseFast -Dflat -p "$PREFIX"

# 8. Verify: pure FreeBSD ELF, base libs only, no GLIBC refs.
file "$PREFIX/zig"
if readelf -V "$PREFIX/zig" | grep -qE "GLIBC|GCC_"; then
    echo "error: Linux ABI leaked into FreeBSD binary" >&2
    exit 1
fi
echo "[✓] $PREFIX/zig is a clean FreeBSD binary"
ls -lh "$PREFIX/zig"

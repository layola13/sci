#!/bin/bash
# Acceptance probe for `sa build-lib` (see blib.sai for the contract).
#
# Builds the probe SLA library in both kinds and runs a C host against
# each form:
#   shared: dlopen -> blib_get_api table -> three contract calls
#   static: direct link of the archive -> three direct calls
# Also pins the shared artifact's dynamic export surface to exactly the
# contract surface plus the two generated entries.
#
# Expects the freshly built `sa` on PATH (or SA_BIN set) and the usual
# SA/SLA environment (SA_PLUGIN_DEV=1, SA_STD_DIR=<sci>/sa_std).
set -u
SA_BIN="${SA_BIN:-sa}"
CC_BIN="${CC_BIN:-zig cc}"
AR_CHECK="${AR_CHECK:-nm}"
cd "$(dirname "$0")" || exit 1
OUT="$(mktemp -d)"
echo "probe out dir: $OUT"

fail() { echo "PROBE_FAIL: $1"; exit 1; }

# --- shared form -------------------------------------------------------
"$SA_BIN" build-lib blib.sla --contract blib.sai --kind shared -o "$OUT/libblib.so" \
    || fail "build-lib shared"
[ -f "$OUT/blib.h" ] || fail "generated header missing"
$CC_BIN -O2 -I"$OUT" host.c -ldl -o "$OUT/host" || fail "host build"
"$OUT/host" "$OUT/libblib.so" || fail "shared host run"

EXPORTS="$($AR_CHECK -D --defined-only "$OUT/libblib.so" | awk '{print $NF}' | grep -v '^$' | sort | tr '\n' ' ')"
echo "dynamic exports: $EXPORTS"
[ "$EXPORTS" = "bl_add bl_answer bl_checksum blib_abi_version blib_get_api " ] \
    || fail "dynamic export surface mismatch"

# --- static form -------------------------------------------------------
"$SA_BIN" build-lib blib.sla --contract blib.sai --kind static -o "$OUT/libblib.a" \
    || fail "build-lib static"
$CC_BIN -O2 -DBLIB_STATIC -I"$OUT" host_static.c "$OUT/libblib.a" -o "$OUT/host_static" \
    || fail "host_static build"
"$OUT/host_static" || fail "static host run"

echo "PROBE_ALL_OK"

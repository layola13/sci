#!/bin/sh
# Publish all @salang/sa packages in dependency order:
# the 6 platform packages first, the meta package last.
# Any extra args are forwarded to `npm publish` (e.g. --dry-run).
#
# Usage:
#   sh tools/publish-all.sh [--dry-run]
# Requires: npm login with publish rights on the salang org.

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for p in sa-linux-x64 sa-linux-arm64 sa-darwin-arm64 sa-darwin-x64 sa-win32-x64 sa-freebsd-x64; do
    echo "=== publishing @salang/$p"
    (cd "$ROOT/packages/$p" && npm publish --access public "$@")
done

echo "=== publishing @salang/sa"
(cd "$ROOT/packages/sa" && npm publish --access public "$@")

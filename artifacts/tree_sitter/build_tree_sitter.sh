#!/usr/bin/env bash
# Builds the tree-sitter core library and the TypeScript grammar into
# sci/artifacts/tree_sitter/ (P0-4). Pinned versions; sources are kept
# under /tmp for rebuilds and are NOT committed.
set -eu
TS_CORE_VERSION=v0.25.10
TS_GRAMMAR_VERSION=v0.23.2
OUT=/content/sa_all/sci/artifacts/tree_sitter
SRC=/tmp/ts-build
mkdir -p "$OUT" "$SRC"
cd "$SRC"
if [ ! -d tree-sitter ]; then
  timeout 600 git clone --depth 1 --branch "$TS_CORE_VERSION" https://github.com/tree-sitter/tree-sitter
fi
if [ ! -d tree-sitter-typescript ]; then
  timeout 600 git clone --depth 1 --branch "$TS_GRAMMAR_VERSION" https://github.com/tree-sitter/tree-sitter-typescript
fi
cc -O2 -fPIC -shared tree-sitter/lib/src/lib.c -Itree-sitter/lib/include -Itree-sitter/lib/src -o "$OUT/libtree-sitter.so"
echo "core built: $(stat -c%s "$OUT/libtree-sitter.so") bytes"
cc -O2 -fPIC -shared tree-sitter-typescript/typescript/src/parser.c tree-sitter-typescript/typescript/src/scanner.c -Itree-sitter-typescript/typescript/src -o "$OUT/libtree-sitter-typescript.so"
echo "grammar built: $(stat -c%s "$OUT/libtree-sitter-typescript.so") bytes"
nm -D "$OUT/libtree-sitter.so" | grep -c " T ts_"
nm -D "$OUT/libtree-sitter-typescript.so" | grep "tree_sitter_typescript"
grep -n "LANGUAGE_VERSION" tree-sitter/lib/include/tree_sitter/api.h | head -2
grep -n "LANGUAGE_VERSION" tree-sitter-typescript/typescript/src/parser.c | head -1
echo "=== TS BUILD DONE ==="

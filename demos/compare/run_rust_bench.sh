#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

RUSTC="${RUSTC:-rustc}"

printf '=== Rust Benchmark ===\n\n'

start_time=$(date +%s%N)
"$RUSTC" -C opt-level=3 demos/compare/big_bench.rs -o /tmp/rust_big.exe >/dev/null 2>&1
end_time=$(date +%s%N)
compile_ms=$(( (end_time - start_time) / 1000000 ))
printf '[big] compile: %s ms\n' "$compile_ms"

start_time=$(date +%s%N)
"$RUSTC" -C opt-level=3 demos/compare/bench.rs -o /tmp/rust_bench.exe >/dev/null 2>&1
end_time=$(date +%s%N)
loop_compile_ms=$(( (end_time - start_time) / 1000000 ))
printf '[loop] compile: %s ms\n' "$loop_compile_ms"

echo 'Done.'

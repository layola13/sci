#!/usr/bin/env bash
set -euo pipefail
repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

SA_BIN="${SA_BIN:-$repo_root/zig-out/bin/sa}"

printf '=== SA Benchmark ===\n\n'

start_time=$(date +%s%N)
"$SA_BIN" build-exe demos/compare/big_bench.sa -o /tmp/sa_big.exe --jobs auto >/dev/null 2>&1
end_time=$(date +%s%N)
compile_ms=$(( (end_time - start_time) / 1000000 ))
printf '[big] compile: %s ms\n' "$compile_ms"

start_time=$(date +%s%N)
"$SA_BIN" build-exe demos/compare/bench.sa -o /tmp/sa_bench.exe --jobs auto >/dev/null 2>&1
end_time=$(date +%s%N)
loop_compile_ms=$(( (end_time - start_time) / 1000000 ))
printf '[loop] compile: %s ms\n' "$loop_compile_ms"

echo 'Done.'

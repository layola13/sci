#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

RUSTC="${RUSTC:-rustc}"
RUNS="${RUNS:-3}"

time_ms() {
    local start end
    start=$(date +%s%N)
    "$@" >/tmp/rust_compare_cmd.out 2>/tmp/rust_compare_cmd.err
    end=$(date +%s%N)
    echo $(( (end - start) / 1000000 ))
}

median() {
    printf '%s\n' "$@" | sort -n | awk 'NF { a[NR]=$1 } END { if (NR == 0) exit 1; print a[int((NR + 1) / 2)] }'
}

run_many() {
    local label=$1
    shift
    local values=()
    for _ in $(seq 1 "$RUNS"); do
        values+=("$(time_ms "$@")")
    done
    printf '%s: %s ms (median of %s)\n' "$label" "$(median "${values[@]}")" "$RUNS"
}

printf '=== Rust Benchmark ===\n\n'
printf 'compiler: %s\n' "$RUSTC"
printf 'compiler flags: -C opt-level=3\n'
printf 'runs: %s\n\n' "$RUNS"

run_many '[big] compile' "$RUSTC" -C opt-level=3 demos/compare/big_bench.rs -o /tmp/rust_big.exe
run_many '[loop] compile' "$RUSTC" -C opt-level=3 demos/compare/bench.rs -o /tmp/rust_bench.exe
run_many '[loop] runtime' /tmp/rust_bench.exe

if command -v stat >/dev/null 2>&1; then
    printf '[big] size: %s bytes\n' "$(stat -c %s /tmp/rust_big.exe)"
    printf '[loop] size: %s bytes\n' "$(stat -c %s /tmp/rust_bench.exe)"
fi

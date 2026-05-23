#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

SA_BIN="${SA_BIN:-$repo_root/zig-out/bin/sa}"
RUSTC="${RUSTC:-rustc}"
RUNS="${RUNS:-3}"
BUILD_RELEASE="${BUILD_RELEASE:-1}"

if [ "$BUILD_RELEASE" = "1" ]; then
    zig build -Doptimize=ReleaseFast >/tmp/sa_thread_compare_build.out 2>/tmp/sa_thread_compare_build.err
fi

time_ms() {
    local start end
    start=$(date +%s%N)
    "$@" >/tmp/thread_compare_cmd.out 2>/tmp/thread_compare_cmd.err
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

printf '=== Thread Benchmark ===\n\n'
printf 'SA compiler: %s\n' "$SA_BIN"
printf 'Rust compiler: %s\n' "$RUSTC"
printf 'runs: %s\n\n' "$RUNS"

run_many '[SA] compile' "$SA_BIN" build-exe demos/compare/thread_bench.sa -o /tmp/sa_thread.exe
run_many '[SA] runtime' /tmp/sa_thread.exe
run_many '[Rust] compile' "$RUSTC" -C opt-level=3 demos/compare/thread_bench.rs -o /tmp/rust_thread.exe
run_many '[Rust] runtime' /tmp/rust_thread.exe

if command -v stat >/dev/null 2>&1; then
    printf '[SA] size: %s bytes\n' "$(stat -c %s /tmp/sa_thread.exe)"
    printf '[Rust] size: %s bytes\n' "$(stat -c %s /tmp/rust_thread.exe)"
fi

#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

SA_BIN="${SA_BIN:-$repo_root/zig-out/bin/sa}"
RUNS="${RUNS:-3}"
JOBS="${JOBS:-1}"
BUILD_RELEASE="${BUILD_RELEASE:-1}"

if [ "$BUILD_RELEASE" = "1" ]; then
    zig build -Doptimize=ReleaseFast >/tmp/sa_compare_build.out 2>/tmp/sa_compare_build.err
fi
compiler_build="ReleaseFast"
if [ "$BUILD_RELEASE" != "1" ]; then
    compiler_build="prebuilt (not rebuilt by script; must already be ReleaseFast)"
fi

time_ms() {
    local start end
    start=$(date +%s%N)
    "$@" >/tmp/sa_compare_cmd.out 2>/tmp/sa_compare_cmd.err
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

printf '=== SA Benchmark ===\n\n'
printf 'compiler: %s\n' "$SA_BIN"
printf 'compiler build: %s\n' "$compiler_build"
printf 'jobs: %s\n' "$JOBS"
printf 'runs: %s\n\n' "$RUNS"

run_many '[big] compile' "$SA_BIN" build-exe demos/compare/big_bench.sa -o /tmp/sa_big.exe --jobs "$JOBS" --profile --json
cp /tmp/sa_compare_cmd.err /tmp/sa_big_profile.json
run_many '[loop] compile' "$SA_BIN" build-exe demos/compare/bench.sa -o /tmp/sa_bench.exe --jobs "$JOBS" --profile --json
cp /tmp/sa_compare_cmd.err /tmp/sa_loop_profile.json
run_many '[loop] runtime' /tmp/sa_bench.exe

if command -v stat >/dev/null 2>&1; then
    printf '[big] size: %s bytes\n' "$(stat -c %s /tmp/sa_big.exe)"
    printf '[loop] size: %s bytes\n' "$(stat -c %s /tmp/sa_bench.exe)"
fi

printf '\nbig profile JSON:\n'
cat /tmp/sa_big_profile.json
printf '\nloop profile JSON:\n'
cat /tmp/sa_loop_profile.json

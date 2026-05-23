#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

SA_BIN="${SA_BIN:-$repo_root/zig-out/bin/sa}"
RUNS="${RUNS:-3}"
BUILD_RELEASE="${BUILD_RELEASE:-1}"
JOBS_LIST="${JOBS_LIST:-1 2 3 4 auto}"

if [ "$BUILD_RELEASE" = "1" ]; then
    zig build -Doptimize=ReleaseFast >/tmp/sa_parallel_build.out 2>/tmp/sa_parallel_build.err
fi
compiler_build="ReleaseFast"
if [ "$BUILD_RELEASE" != "1" ]; then
    compiler_build="prebuilt (not rebuilt by script; must already be ReleaseFast)"
fi

time_ms() {
    local start end
    start=$(date +%s%N)
    "$@" >/tmp/sa_parallel_cmd.out 2>/tmp/sa_parallel_cmd.err
    end=$(date +%s%N)
    echo $(( (end - start) / 1000000 ))
}

median() {
    printf '%s\n' "$@" | sort -n | awk 'NF { a[NR]=$1 } END { if (NR == 0) exit 1; print a[int((NR + 1) / 2)] }'
}

printf '=== SA Parallel Compile Benchmark ===\n\n'
printf 'compiler: %s\n' "$SA_BIN"
printf 'compiler build: %s\n' "$compiler_build"
printf 'runs: %s\n' "$RUNS"
printf 'jobs list: %s\n\n' "$JOBS_LIST"

for jobs in $JOBS_LIST; do
    values=()
    for _ in $(seq 1 "$RUNS"); do
        values+=("$(time_ms "$SA_BIN" build-exe demos/compare/big_bench.sa -o "/tmp/sa_parallel_${jobs}.exe" --jobs "$jobs" --profile --json)")
    done
    printf '[jobs=%s] big compile: %s ms (median of %s)\n' "$jobs" "$(median "${values[@]}")" "$RUNS"
    printf '[jobs=%s] profile: ' "$jobs"
    cat /tmp/sa_parallel_cmd.err
done

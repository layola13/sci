#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

detect_jobs() {
    if [ -n "${SA_ZIG_JOBS:-}" ]; then
        printf '%s\n' "$SA_ZIG_JOBS"
        return
    fi
    if [ -n "${ZIG_BUILD_JOBS:-}" ]; then
        printf '%s\n' "$ZIG_BUILD_JOBS"
        return
    fi
    if command -v nproc >/dev/null 2>&1; then
        nproc
        return
    fi
    getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
}

now_ms() {
    date +%s%3N
}

format_ms() {
    local ms="$1"
    printf '%d.%03ds' "$((ms / 1000))" "$((ms % 1000))"
}

jobs="$(detect_jobs)"
summary="${SA_ZIG_SUMMARY:-all}"
requested_profile="${SA_PRE_PUSH_PROFILE:-auto}"
export SA_TEST_JOBS="${SA_TEST_JOBS:-$jobs}"
total_start="$(now_ms)"
list_only=0
stage_names=()
stage_elapsed_ms=()

if [ "${1:-}" = "--list" ]; then
    list_only=1
    shift
fi

run_stage() {
    local name="$1"
    shift
    local start end elapsed
    start="$(now_ms)"
    printf '[pre-push] START %-24s %s\n' "$name" "$*"
    if "$@"; then
        end="$(now_ms)"
        elapsed="$((end - start))"
        stage_names+=("$name")
        stage_elapsed_ms+=("$elapsed")
        printf '[pre-push] PASS  %-24s elapsed=%s\n' "$name" "$(format_ms "$elapsed")"
    else
        local status="$?"
        end="$(now_ms)"
        elapsed="$((end - start))"
        stage_names+=("$name")
        stage_elapsed_ms+=("$elapsed")
        printf '[pre-push] FAIL  %-24s elapsed=%s status=%s\n' "$name" "$(format_ms "$elapsed")" "$status" >&2
        print_slowest_stages >&2
        printf '[pre-push] TOTAL elapsed=%s\n' "$(format_ms "$((end - total_start))")" >&2
        exit "$status"
    fi
}

print_slowest_stages() {
    local count="${#stage_names[@]}"
    local limit=10
    local printed=0
    local used=()
    local i best best_ms

    if [ "$count" -eq 0 ]; then
        return
    fi

    printf '[pre-push] slowest stages:\n'
    while [ "$printed" -lt "$limit" ] && [ "$printed" -lt "$count" ]; do
        best=-1
        best_ms=-1
        for ((i = 0; i < count; i++)); do
            if [ "${used[$i]:-0}" -eq 1 ]; then
                continue
            fi
            if [ "${stage_elapsed_ms[$i]}" -gt "$best_ms" ]; then
                best="$i"
                best_ms="${stage_elapsed_ms[$i]}"
            fi
        done
        if [ "$best" -lt 0 ]; then
            break
        fi
        used[$best]=1
        printf '[pre-push]   %-24s %s\n' "${stage_names[$best]}" "$(format_ms "$best_ms")"
        printed="$((printed + 1))"
    done
}

changed_files() {
    local upstream
    if upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"; then
        git diff --name-only "$upstream"...HEAD 2>/dev/null || true
    fi
    git diff --name-only HEAD 2>/dev/null || true
}

resolve_auto_profile() {
    local file saw_change=0
    while IFS= read -r file; do
        [ -n "$file" ] || continue
        saw_change=1
        case "$file" in
            sa_std/*|tests/unit_framework/*|docs/*|progress.md|.codex/skills/*|.claude/skills/*|tools/pre_push_timed.sh|.githooks/pre-push)
                ;;
            *)
                printf 'full\n'
                return
                ;;
        esac
    done < <(changed_files | sort -u)

    if [ "$saw_change" -eq 0 ]; then
        printf 'full\n'
    else
        printf 'fast\n'
    fi
}

if [ "$requested_profile" = "auto" ]; then
    profile="$(resolve_auto_profile)"
else
    profile="$requested_profile"
fi

printf '[pre-push] repo=%s profile=%s requested_profile=%s jobs=%s sa_test_jobs=%s summary=%s\n' "$repo_root" "$profile" "$requested_profile" "$jobs" "$SA_TEST_JOBS" "$summary"
printf '[pre-push] override Zig jobs with SA_ZIG_JOBS=<n>; override SA unit jobs with SA_TEST_JOBS=<n|auto>\n'
printf '[pre-push] select stage profile with SA_PRE_PUSH_PROFILE=auto|full|fast|legacy\n'

run_zig_step() {
    local step="$1"
    run_stage "$step" zig build "$step" -j"$jobs" --summary "$summary"
}

case "$profile" in
    full)
        default_stages=(
            trap-baseline
            std-smoke
            sa-std-unit
            sa-std-runtime
            sa-net-uring-test
            sa-term-runtime
            native-sys-runtime
            whitepaper-lint
            scope-demo
            ffi-handle-demo
            hubproxy-test
            pkg-core-test
            plugin-host-smoke
            wasm-matrix
            unit-framework
            cli-skills-smoke
            referee-loc-lint
        )
        ;;
    fast)
        default_stages=(
            trap-baseline
            std-smoke
            sa-std-unit
            sa-std-runtime
            unit-framework
            cli-skills-smoke
            referee-loc-lint
        )
        ;;
    legacy)
        default_stages=(
            trap-baseline
            std-smoke
            sa-std-unit
            sa-std-runtime
            sa-net-uring-test
            sa-term-runtime
            native-sys-runtime
            smoke
            scope-demo
            ffi-handle-demo
            hubproxy-test
            pkg-core-test
            plugin-host-smoke
            wasm-matrix
            unit-framework
            referee-loc-lint
        )
        ;;
    *)
        printf '[pre-push] unknown SA_PRE_PUSH_PROFILE=%s; use auto, full, fast, or legacy\n' "$requested_profile" >&2
        exit 2
        ;;
esac

if [ "$#" -gt 0 ]; then
    stages=("$@")
else
    stages=("${default_stages[@]}")
fi

if [ "$list_only" -eq 1 ]; then
    printf '[pre-push] stages:'
    for stage in "${stages[@]}"; do
        printf ' %s' "$stage"
    done
    printf '\n'
    exit 0
fi

for stage in "${stages[@]}"; do
    case "$stage" in
        pre-push-aggregate)
            run_stage pre-push-aggregate zig build pre-push -j"$jobs" --summary "$summary"
            ;;
        *)
            run_zig_step "$stage"
            ;;
    esac
done

total_end="$(now_ms)"
print_slowest_stages
printf '[pre-push] TOTAL elapsed=%s\n' "$(format_ms "$((total_end - total_start))")"

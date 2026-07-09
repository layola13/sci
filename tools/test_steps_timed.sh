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

utc_stamp() {
    date -u +"%Y%m%dT%H%M%SZ"
}

utc_now() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

format_ms() {
    local ms="$1"
    printf '%d.%03ds' "$((ms / 1000))" "$((ms % 1000))"
}

usage() {
    cat <<'USAGE'
Usage: tools/test_steps_timed.sh [options] [step ...]

Run the zig build test dependency set as explicit build steps with per-step
START/PASS/FAIL/TIMEOUT logs.

Options:
  --list              Print the selected step list and exit.
  --continue          Continue after failed or timed-out steps.
  --timeout SEC       Per-step timeout. Default: SA_TEST_STEP_TIMEOUT or 420.
  --heartbeat SEC     Print RUNNING status while a step is active. Default: SA_TEST_STEP_HEARTBEAT or 30. Use 0 to disable.
  --fail-tail-lines N Print the last N log lines on failure/timeout. Default: SA_TEST_STEP_FAIL_TAIL_LINES or 80. Use 0 to disable.
  --jobs N            Zig build worker count. Default: SA_ZIG_JOBS, ZIG_BUILD_JOBS, or nproc.
  --log-dir DIR       Directory for per-step logs. Default: SA_TEST_STEP_LOG_DIR or logs/test_steps/<utc>.
  --summary MODE      Zig --summary mode. Default: SA_ZIG_SUMMARY or all.
  -h, --help          Show this help.

Default steps cover the build.zig test dependency set. The std smoke artifacts
are grouped as std-smoke, and the whitepaper smoke run artifact is covered by
whitepaper-lint to avoid the duplicate std-smoke rerun hidden behind smoke.
USAGE
}

timeout_s="${SA_TEST_STEP_TIMEOUT:-420}"
heartbeat_s="${SA_TEST_STEP_HEARTBEAT:-30}"
fail_tail_lines="${SA_TEST_STEP_FAIL_TAIL_LINES:-80}"
jobs="$(detect_jobs)"
log_dir="${SA_TEST_STEP_LOG_DIR:-}"
summary="${SA_ZIG_SUMMARY:-all}"
list_only=0
continue_after_failure=0
steps=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --list)
            list_only=1
            shift
            ;;
        --continue)
            continue_after_failure=1
            shift
            ;;
        --timeout)
            if [ "$#" -lt 2 ]; then
                printf '[test-steps] missing value for --timeout\n' >&2
                exit 2
            fi
            timeout_s="$2"
            shift 2
            ;;
        --timeout=*)
            timeout_s="${1#--timeout=}"
            shift
            ;;
        --heartbeat)
            if [ "$#" -lt 2 ]; then
                printf '[test-steps] missing value for --heartbeat\n' >&2
                exit 2
            fi
            heartbeat_s="$2"
            shift 2
            ;;
        --heartbeat=*)
            heartbeat_s="${1#--heartbeat=}"
            shift
            ;;
        --fail-tail-lines)
            if [ "$#" -lt 2 ]; then
                printf '[test-steps] missing value for --fail-tail-lines\n' >&2
                exit 2
            fi
            fail_tail_lines="$2"
            shift 2
            ;;
        --fail-tail-lines=*)
            fail_tail_lines="${1#--fail-tail-lines=}"
            shift
            ;;
        --jobs)
            if [ "$#" -lt 2 ]; then
                printf '[test-steps] missing value for --jobs\n' >&2
                exit 2
            fi
            jobs="$2"
            shift 2
            ;;
        --jobs=*)
            jobs="${1#--jobs=}"
            shift
            ;;
        --log-dir)
            if [ "$#" -lt 2 ]; then
                printf '[test-steps] missing value for --log-dir\n' >&2
                exit 2
            fi
            log_dir="$2"
            shift 2
            ;;
        --log-dir=*)
            log_dir="${1#--log-dir=}"
            shift
            ;;
        --summary)
            if [ "$#" -lt 2 ]; then
                printf '[test-steps] missing value for --summary\n' >&2
                exit 2
            fi
            summary="$2"
            shift 2
            ;;
        --summary=*)
            summary="${1#--summary=}"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            while [ "$#" -gt 0 ]; do
                steps+=("$1")
                shift
            done
            ;;
        -*)
            printf '[test-steps] unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            steps+=("$1")
            shift
            ;;
    esac
done

if ! [[ "$timeout_s" =~ ^[0-9]+$ ]] || [ "$timeout_s" -le 0 ]; then
    printf '[test-steps] --timeout must be a positive integer, got %s\n' "$timeout_s" >&2
    exit 2
fi

if ! [[ "$heartbeat_s" =~ ^[0-9]+$ ]]; then
    printf '[test-steps] --heartbeat must be a non-negative integer, got %s\n' "$heartbeat_s" >&2
    exit 2
fi

if ! [[ "$fail_tail_lines" =~ ^[0-9]+$ ]]; then
    printf '[test-steps] --fail-tail-lines must be a non-negative integer, got %s\n' "$fail_tail_lines" >&2
    exit 2
fi

if ! [[ "$jobs" =~ ^[0-9]+$ ]] || [ "$jobs" -le 0 ]; then
    printf '[test-steps] --jobs must be a positive integer, got %s\n' "$jobs" >&2
    exit 2
fi

default_steps=(
    lib-root-smoke
    plugin-host-smoke
    pkg-core-test
    wasm-matrix
    bc2sa-smoke
    workspace-smoke
    trap-baseline
    unit-framework
    sa-std-unit
    sa-std-runtime
    sa-net-uring-test
    sa-http2-test
    sa-tls-server-test
    sa-dtls-test
    sa-quic-test
    sa-term-runtime
    native-sys-runtime
    std-smoke
    whitepaper-lint
    scope-demo
    ffi-handle-demo
    hubproxy-test
)

if [ "${#steps[@]}" -eq 0 ]; then
    steps=("${default_steps[@]}")
fi

if [ "$list_only" -eq 1 ]; then
    printf '[test-steps] steps:'
    for step in "${steps[@]}"; do
        printf ' %s' "$step"
    done
    printf '\n'
    exit 0
fi

if ! command -v timeout >/dev/null 2>&1; then
    printf '[test-steps] required command not found: timeout\n' >&2
    exit 2
fi

if [ -z "$log_dir" ]; then
    log_dir="logs/test_steps/$(utc_stamp)"
fi
mkdir -p "$log_dir"
summary_log="$log_dir/summary.log"
results_tsv="$log_dir/results.tsv"
environment_log="$log_dir/environment.txt"
: > "$summary_log"
printf 'index\tstep\tstatus\texit_status\telapsed_ms\telapsed\tstarted_at\tended_at\tlog\n' > "$results_tsv"

{
    printf 'repo=%s\n' "$repo_root"
    printf 'git_head=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf unknown)"
    printf 'git_branch=%s\n' "$(git branch --show-current 2>/dev/null || printf unknown)"
    printf 'git_status_short_lines=%s\n' "$(git status --short 2>/dev/null | wc -l | tr -d ' ')"
    printf 'started_at=%s\n' "$(utc_now)"
    printf 'jobs=%s\n' "$jobs"
    printf 'summary=%s\n' "$summary"
    printf 'timeout_s=%s\n' "$timeout_s"
    printf 'heartbeat_s=%s\n' "$heartbeat_s"
    printf 'fail_tail_lines=%s\n' "$fail_tail_lines"
    printf 'continue_after_failure=%s\n' "$continue_after_failure"
    printf 'steps=%d\n' "${#steps[@]}"
    printf 'log_dir=%s\n' "$log_dir"
} > "$environment_log"

emit() {
    printf '%s\n' "$*" | tee -a "$summary_log"
}

log_size_bytes() {
    wc -c < "$1" 2>/dev/null | tr -d ' ' || printf '0'
}

append_failed_tail() {
    local step="$1"
    local log_file="$2"

    if [ "$fail_tail_lines" -eq 0 ]; then
        return
    fi

    emit "$(printf '[test-steps] log tail step=%s lines=%s log=%s' "$step" "$fail_tail_lines" "$log_file")"
    tail -n "$fail_tail_lines" "$log_file" 2>/dev/null | sed 's/^/[test-steps] | /' | tee -a "$summary_log" >&2
}

sanitize_step_name() {
    printf '%s' "$1" | tr -c 'A-Za-z0-9._-' '_'
}

step_names=()
step_statuses=()
step_elapsed_ms=()
step_log_paths=()
failed_steps=()
passed=0
failed=0
timed_out=0
total_start="$(now_ms)"

print_slowest_steps() {
    local count="${#step_names[@]}"
    local limit=10
    local printed=0
    local used=()
    local i best best_ms

    if [ "$count" -eq 0 ]; then
        return
    fi

    emit '[test-steps] slowest steps:'
    while [ "$printed" -lt "$limit" ] && [ "$printed" -lt "$count" ]; do
        best=-1
        best_ms=-1
        for ((i = 0; i < count; i++)); do
            if [ "${used[$i]:-0}" -eq 1 ]; then
                continue
            fi
            if [ "${step_elapsed_ms[$i]}" -gt "$best_ms" ]; then
                best="$i"
                best_ms="${step_elapsed_ms[$i]}"
            fi
        done
        if [ "$best" -lt 0 ]; then
            break
        fi
        used[$best]=1
        emit "$(printf '[test-steps]   %-24s %-7s %s log=%s' "${step_names[$best]}" "${step_statuses[$best]}" "$(format_ms "$best_ms")" "${step_log_paths[$best]}")"
        printed="$((printed + 1))"
    done
}

print_summary() {
    local total_end total_elapsed
    total_end="$(now_ms)"
    total_elapsed="$((total_end - total_start))"
    print_slowest_steps
    emit "$(printf '[test-steps] SUMMARY passed=%d failed=%d timeout=%d total=%d elapsed=%s log_dir=%s' "$passed" "$failed" "$timed_out" "${#steps[@]}" "$(format_ms "$total_elapsed")" "$log_dir")"
    if [ "${#failed_steps[@]}" -gt 0 ]; then
        local failed_line='[test-steps] failed steps:'
        for step in "${failed_steps[@]}"; do
            failed_line="$failed_line $step"
        done
        emit "$failed_line"
    fi
}

run_step() {
    local step="$1"
    local index="$2"
    local total="$3"
    local start end elapsed status label safe_step log_file started_at ended_at run_pid heartbeat_pid
    local cmd=(zig build "$step" "-j$jobs" --summary "$summary")
    safe_step="$(sanitize_step_name "$step")"
    log_file="$(printf '%s/%02d-%s.log' "$log_dir" "$index" "$safe_step")"
    : > "$log_file"

    start="$(now_ms)"
    started_at="$(utc_now)"
    {
        printf '[test-steps] START index=%d/%d step=%s timeout=%ss heartbeat=%ss at=%s log=%s command=' "$index" "$total" "$step" "$timeout_s" "$heartbeat_s" "$started_at" "$log_file"
        printf '%q ' "${cmd[@]}"
        printf '\n'
    } | tee -a "$summary_log" "$log_file"

    set +e
    timeout -k 10s "${timeout_s}s" "${cmd[@]}" 2>&1 | tee -a "$log_file" &
    run_pid="$!"
    if [ "$heartbeat_s" -gt 0 ]; then
        (
            while true; do
                sleep "$heartbeat_s"
                if ! kill -0 "$run_pid" 2>/dev/null; then
                    exit 0
                fi
                end="$(now_ms)"
                elapsed="$((end - start))"
                emit "$(printf '[test-steps] RUNNING index=%d/%d step=%s elapsed=%s log_bytes=%s at=%s log=%s' "$index" "$total" "$step" "$(format_ms "$elapsed")" "$(log_size_bytes "$log_file")" "$(utc_now)" "$log_file")"
            done
        ) &
        heartbeat_pid="$!"
    else
        heartbeat_pid=""
    fi
    wait "$run_pid"
    status="$?"
    if [ -n "$heartbeat_pid" ]; then
        kill "$heartbeat_pid" 2>/dev/null || true
        wait "$heartbeat_pid" 2>/dev/null || true
    fi
    set -e

    ended_at="$(utc_now)"
    if [ "$status" -eq 0 ]; then
        end="$(now_ms)"
        elapsed="$((end - start))"
        passed="$((passed + 1))"
        step_names+=("$step")
        step_statuses+=("PASS")
        step_elapsed_ms+=("$elapsed")
        step_log_paths+=("$log_file")
        printf '%d\t%s\tPASS\t0\t%d\t%s\t%s\t%s\t%s\n' "$index" "$step" "$elapsed" "$(format_ms "$elapsed")" "$started_at" "$ended_at" "$log_file" >> "$results_tsv"
        {
            printf '[test-steps] PASS  index=%d/%d step=%s elapsed=%s at=%s log=%s\n' "$index" "$total" "$step" "$(format_ms "$elapsed")" "$ended_at" "$log_file"
        } | tee -a "$summary_log" "$log_file"
        return 0
    fi

    end="$(now_ms)"
    elapsed="$((end - start))"
    if [ "$status" -eq 124 ] || [ "$status" -eq 137 ]; then
        label="TIMEOUT"
        timed_out="$((timed_out + 1))"
    else
        label="FAIL"
        failed="$((failed + 1))"
    fi
    failed_steps+=("$step")
    step_names+=("$step")
    step_statuses+=("$label")
    step_elapsed_ms+=("$elapsed")
    step_log_paths+=("$log_file")
    printf '%d\t%s\t%s\t%d\t%d\t%s\t%s\t%s\t%s\n' "$index" "$step" "$label" "$status" "$elapsed" "$(format_ms "$elapsed")" "$started_at" "$ended_at" "$log_file" >> "$results_tsv"
    {
        printf '[test-steps] %-7s index=%d/%d step=%s elapsed=%s status=%s at=%s log=%s\n' "$label" "$index" "$total" "$step" "$(format_ms "$elapsed")" "$status" "$ended_at" "$log_file"
    } | tee -a "$summary_log" "$log_file" >&2
    append_failed_tail "$step" "$log_file"
    if [ "$continue_after_failure" -eq 0 ]; then
        print_summary
        exit "$status"
    fi
    return 0
}

emit "$(printf '[test-steps] repo=%s jobs=%s summary=%s timeout=%ss heartbeat=%ss fail_tail_lines=%s continue=%s steps=%d log_dir=%s results=%s environment=%s' "$repo_root" "$jobs" "$summary" "$timeout_s" "$heartbeat_s" "$fail_tail_lines" "$continue_after_failure" "${#steps[@]}" "$log_dir" "$results_tsv" "$environment_log")"

for i in "${!steps[@]}"; do
    run_step "${steps[$i]}" "$((i + 1))" "${#steps[@]}"
done

print_summary
if [ "$failed" -gt 0 ] || [ "$timed_out" -gt 0 ]; then
    exit 1
fi

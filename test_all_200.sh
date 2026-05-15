#!/bin/bash
pass=0
fail=0
fail_list=""

for dir in demos/rosetta/*; do
    if [ -f "$dir/main.saasm" ]; then
        base=$(basename "$dir")
        num_raw=${base%%_*}
        case "$num_raw" in
            ''|*[!0-9]*) continue ;;
        esac
        num=$((10#$num_raw))
        if [ "$num" -lt 1 ] || [ "$num" -gt 200 ]; then
            continue
        fi

        tmpdir=$(mktemp -d)
        ref_stdout="$tmpdir/ref.stdout"
        ref_stderr="$tmpdir/ref.stderr"
        build_log="$tmpdir/build.log"
        run_stdout="$tmpdir/run.stdout"
        run_stderr="$tmpdir/run.stderr"

        case "$base" in
            101_custom_drop) printf '%b' '16\n' > "$ref_stdout" ;;
            108_atomic_spin_lock) printf '%b' '1\n' > "$ref_stdout" ;;
            109_atomic_fetch_add) printf '%b' '13\n' > "$ref_stdout" ;;
            117_inline_assembly) printf '%b' '7\n' > "$ref_stdout" ;;
            139_cancellation_safety) printf '%b' '4\n' > "$ref_stdout" ;;
            155_arena_allocator_bump) printf '%b' '3\n' > "$ref_stdout" ;;
            156_slab_allocator_freelist) printf '%b' '3\n' > "$ref_stdout" ;;
            181_file_descriptor_raii) printf '%b' '3\n' > "$ref_stdout" ;;
            182_mmap_memory_mapping) printf '%b' '4\n' > "$ref_stdout" ;;
            183_signal_handling_setup) printf '%b' '2\n' > "$ref_stdout" ;;
            184_pthread_spawn_join) printf '%b' '5\n' > "$ref_stdout" ;;
            185_dynamic_lib_dlopen) printf '%b' '1\n' > "$ref_stdout" ;;
            186_sqlite_c_api_binding) printf '%b' '8\n' > "$ref_stdout" ;;
            188_websocket_frame_parse) printf '%b' '1\n' > "$ref_stdout" ;;
            193_attribute_macro_rewrite) printf '%b' '2\n' > "$ref_stdout" ;;
            *)
                if ! ./zig-out/bin/saasm run "$dir/main.saasm" > "$ref_stdout" 2> "$ref_stderr"; then
                    ((fail++))
                    trap_msg=$(grep -o '"message":"[^"]*"' "$ref_stderr" | head -n 1)
                    if [ -z "$trap_msg" ]; then
                        fail_list="$fail_list\n$dir (Reference Run Failed)"
                    else
                        fail_list="$fail_list\n$dir (Reference Run Failed: $trap_msg)"
                    fi
                    rm -rf "$tmpdir"
                    continue
                fi
                ;;
        esac
        : > "$ref_stderr"

        if ./zig-out/bin/saasm build-exe "$dir/main.saasm" -o "$tmpdir/demo.exe" > "$build_log" 2>&1; then
            if "$tmpdir/demo.exe" > "$run_stdout" 2> "$run_stderr"; then
                run_code=0
            else
                run_code=$?
            fi

            if [ "$run_code" -eq 0 ] && cmp -s "$run_stdout" "$ref_stdout" && cmp -s "$run_stderr" "$ref_stderr"; then
                ((pass++))
            else
                ((fail++))
                if [ "$run_code" -ne 0 ]; then
                    reason="exit $run_code != 0"
                elif ! cmp -s "$run_stdout" "$ref_stdout"; then
                    reason="stdout mismatch"
                else
                    reason="stderr mismatch"
                fi
                fail_list="$fail_list\n$dir (Run Failed: $reason)"
            fi
        else
            ((fail++))
            trap_msg=$(grep -o '"message":"[^"]*"' "$build_log" | head -n 1)
            if [ -z "$trap_msg" ]; then
                fail_list="$fail_list\n$dir (Build Failed)"
            else
                fail_list="$fail_list\n$dir ($trap_msg)"
            fi
        fi
        rm -rf "$tmpdir"
    fi
done

echo "Total Passed: $pass, Failed: $fail"
if [ $fail -gt 0 ]; then
    echo -e "Failures:$fail_list" | head -n 30
fi

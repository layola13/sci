#!/bin/bash
pass=0
fail=0
fail_list=""

for dir in demos/rosetta/*; do
    if [ -f "$dir/main.saasm" ]; then
        if ./zig-out/bin/saasm build-exe "$dir/main.saasm" -o /tmp/demo.exe > /tmp/build.log 2>&1; then
            if /tmp/demo.exe > /tmp/run.log 2>&1; then
                ((pass++))
            else
                ((fail++))
                out=$(cat /tmp/run.log | head -n 1)
                fail_list="$fail_list\n$dir (Run Failed: $out)"
            fi
        else
            ((fail++))
            trap_msg=$(grep -o '"message":"[^"]*"' /tmp/build.log | head -n 1)
            if [ -z "$trap_msg" ]; then
                fail_list="$fail_list\n$dir (Build Failed)"
            else
                fail_list="$fail_list\n$dir ($trap_msg)"
            fi
        fi
    fi
done

echo "Total Passed: $pass, Failed: $fail"
if [ $fail -gt 0 ]; then
    echo -e "Failures:$fail_list" | head -n 30
fi

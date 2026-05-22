#!/bin/bash

SA="../../zig-out/bin/sa"
RUSTC="rustc"

echo "=== Benchmark: Macro Hell (ECS Systems Simulation) ==="
echo

# Rust
echo "Compiling Rust (Macro Hell)..."
start_time=$(date +%s%N)
$RUSTC -C opt-level=0 macro_hell.rs -o rust_macro.exe > /dev/null 2>&1
end_time=$(date +%s%N)
rust_compile_time=$(( (end_time - start_time) / 1000000 ))
echo "Rust Compilation (O0): ${rust_compile_time} ms"

# SA
echo "Compiling SA-ASM (Macro Hell)..."
start_time=$(date +%s%N)
$SA build-exe macro_hell.sa -o sa_macro.exe --jobs auto > sa_macro_build.log 2>&1
end_time=$(date +%s%N)
sa_compile_time=$(( (end_time - start_time) / 1000000 ))
echo "SA Compilation:        ${sa_compile_time} ms"

echo
echo "=== Result ==="
echo "Rust: ${rust_compile_time} ms"
echo "SA:   ${sa_compile_time} ms"

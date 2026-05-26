#!/bin/bash

# Navigate to the workspace root
cd "$(dirname "$0")"

echo "=== Cleaning up Rosetta and Compare Demos generated binaries ==="

# 1. Clean up local directories and binary files
find demos -type d -name "bin" -exec rm -rf {} +
find demos -type f \( -name "*.out" -o -name "*.wasm" -o -name "*.o" -o -name "*.bc" -o -name "a.out" \) -delete

echo "Cleaned up local bin/ directories and compiled binary files."

# 2. Git untrack these if tracked
git rm -r --cached --ignore-unmatch demos/**/bin/ >/dev/null 2>&1
git rm --cached --ignore-unmatch demos/compare/sa_big.exe.sa.bc >/dev/null 2>&1
git rm --cached --ignore-unmatch demos/compare/sa_big.o >/dev/null 2>&1
git rm --cached --ignore-unmatch demos/rosetta/108_atomic_spin_lock/main.out >/dev/null 2>&1

# Find any remaining compiled files and untrack them
find demos \( -name "*.out" -o -name "*.wasm" -o -name "*.o" -o -name "*.bc" \) | while read -r file; do
    git rm --cached --ignore-unmatch "$file" >/dev/null 2>&1
done

echo "Untracked any tracked binaries from git index successfully."

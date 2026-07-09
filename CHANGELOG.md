# Changelog

## 0.0.4 - 2026-07-09

This release focuses on compiler/test performance, especially the WASM validation path and long-running test diagnostics.

### Performance

- Added a shared project-root cache path for direct compile commands through `--project-root <dir>`, so matrix-style callers can force related builds into one `.sa_cache` tree instead of scattering cache entries across demo subdirectories.
- Reworked `wasm-matrix` for the WASM-fast path: all 110 demos still build and run through WASM, but native `build-exe` reference checks are reduced to a representative sanity subset by default.
- Kept full native equivalence available with `SA_WASM_MATRIX_NATIVE_ALL=1`.
- Hot-cache `wasm-matrix` improved from `146.982s` to `59.623s` in focused logged verification, a reduction of about `59.4%`.

### Test Diagnostics

- Added `tools/test_steps_timed.sh` for logged, step-owned test execution with heartbeat output, per-step logs, failure tails, `results.tsv`, and environment metadata.
- Added internal timing summaries for `wasm-matrix`, including aggregate phase totals plus slowest demo and slowest phase rankings.
- Added file-level `unit-framework` logs with START/END/error lines, elapsed time, mode, jobs, and stdout/stderr byte counts.

### Runtime Test Speed

- Optimized `sa-std-runtime` by reusing the build-system `sa_std` archive instead of rebuilding it inside each C demo test.
- Optimized plugin install failure tests by running pure preflight checks before temporary plugin dynamic-library builds.

## 0.0.3

Previous baseline release used for comparison in the 0.0.4 performance work.

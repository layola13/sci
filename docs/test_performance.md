# Test Performance Notes

Date: 2026-06-08

This note records the first timed pre-push pass after replacing the fixed `zig build pre-push -j1` hook with `tools/pre_push_timed.sh`.

## What Changed

- `.githooks/pre-push` now runs `tools/pre_push_timed.sh` instead of hard-coding `zig build pre-push -j1`.
- `.git/hooks/pre-push` was updated in the working tree to use the same timed script.
- The timed script defaults to the host CPU count through `nproc`, with overrides:
  - `SA_ZIG_JOBS=<n>` or `ZIG_BUILD_JOBS=<n>` controls Zig worker count.
  - `SA_TEST_JOBS=<n|auto>` controls SA unit-test worker count inside the native unit framework runner.
  - `SA_ZIG_SUMMARY=<mode>` controls Zig summary output, defaulting to `all`.
- The script runs named Zig build stages one by one and prints `[pre-push] START/PASS/FAIL ... elapsed=...` for each stage.
- The script accepts optional stage names, for example `tools/pre_push_timed.sh unit-framework wasm-matrix`.
- The script supports stage profiles through `SA_PRE_PUSH_PROFILE`:
  - `full` is the default de-duplicated gate.
  - `fast` runs the std/runtime/unit-framework/skills/lint subset intended for ordinary compiler-std work.
  - `legacy` preserves the older stage list for timing comparisons.
- `pre-push-aggregate` is available as an explicit stage, but it is not part of the default timed run because it repeats all previous CI dependencies.

## Sample Timings

Command: `tools/pre_push_timed.sh`

Environment: default `jobs=4`, `summary=all`. Most Zig test binaries were already cached, so the heavy timings below are primarily test runtime, SA compilation, import expansion, plugin loading, or demo matrix work rather than Zig compilation.

| Stage | Elapsed |
| --- | ---: |
| `unit-framework` | 284.459s |
| `wasm-matrix` | 179.975s |
| `plugin-host-smoke` | 143.466s |
| `sa-std-runtime` | 82.090s |
| `std-smoke` | 56.934s |
| `smoke` | 48.589s |
| `sa-term-runtime` | 15.920s |
| `sa-net-uring-test` | 7.884s |
| `sa-std-unit` | 7.387s |
| `referee-loc-lint` | 3.097s |
| `native-sys-runtime` | 2.842s |
| `scope-demo` | 2.509s |
| `pkg-core-test` | 0.879s |
| `trap-baseline` | 0.661s |
| `ffi-handle-demo` | 0.369s |
| `hubproxy-test` | 0.137s |

The timed pass was intentionally stopped before the old aggregate rerun completed, because the aggregate stage duplicated the already measured stages. The default script has been corrected so this duplicate work no longer happens.

## Main Bottlenecks

1. `unit-framework` is the largest single gate at about 4m44s.
   - It runs the SA native unit framework suites through a Zig test harness.
   - The output shows repeated `sa_std` and support imports across many SA test files.
   - This is the best candidate for SA test-level caching, per-file timing inside `tests/unit_framework/runner.zig`, and selective/focused unit-framework stages.

2. `wasm-matrix` is about 3m.
   - Zig compilation was cached, but the run step still compiled/verified many demo programs.
   - The output repeatedly resolved `sa_std/io/print.sai`, `core/slice`, `option`, `result`, and several collection imports.
   - This is a strong candidate for persistent SA build artifacts per demo and for matrix sharding.

3. `plugin-host-smoke` is about 2m23s.
   - Zig compilation was cached; the cost is in runtime plugin host behavior.
   - Likely expensive subareas are building temporary plugin shared objects, dynamic loading, command dispatch, hot reload, and failure isolation checks.
   - This should get internal per-test timing before changing behavior.

4. `sa-std-runtime`, `std-smoke`, and `smoke` are all substantial.
   - `std-smoke` and `smoke` both include std smoke run artifacts, so running both as separate timed stages repeats some work.
   - `smoke` depends on `run_std_smoke_core` and `run_std_smoke_containers` in addition to whitepaper lint, so it should not be used as a cheap smoke name in pre-push timing.

## 2026-06-08 Pre-push Profile Follow-up

`build.zig` now exposes a `whitepaper-lint` step that runs only `tests/smoke/whitepaper_lint.zig`. The timed pre-push script uses that step in the default `full` profile instead of `smoke`, because `smoke` also depends on both std smoke run artifacts. This removes a known duplicate `std-smoke` rerun from the default hook while preserving the whitepaper lint check.

Current timed profiles:

| Profile | Purpose | Stages |
| --- | --- | --- |
| `full` | Default pre-push gate without known duplicate std smoke reruns. | Runtime/std/system/plugin/wasm/unit-framework/skills/lint stages. |
| `fast` | Faster local gate for ordinary `sa_std` and CLI skills work. | `trap-baseline`, `std-smoke`, `sa-std-unit`, `sa-std-runtime`, `unit-framework`, `cli-skills-smoke`, `referee-loc-lint`. |
| `legacy` | Old stage list for regression timing comparisons. | Includes both `std-smoke` and `smoke`, so it intentionally repeats std smoke work. |

Example commands:

```sh
tools/pre_push_timed.sh --list
SA_PRE_PUSH_PROFILE=fast tools/pre_push_timed.sh --list
tools/pre_push_timed.sh
SA_PRE_PUSH_PROFILE=fast tools/pre_push_timed.sh
SA_PRE_PUSH_PROFILE=legacy tools/pre_push_timed.sh
tools/pre_push_timed.sh unit-framework cli-skills-smoke
```

Expected immediate saving in `full`: about the old `smoke` duplicate std-smoke cost minus the cheap whitepaper lint-only run. On the initial timing sample this removes roughly one `std_smoke_core` + `std_smoke_containers` rerun from the hook path.

## Immediate Recommendations

- Keep the pre-push hook parallel by default; the previous `-j1` setting made it unnecessarily serial.
- Do not include `pre-push-aggregate` in the timed script default, because it repeats every stage after individual timing.
- Add per-SA-file timings inside `tests/unit_framework/runner.zig` to identify the slowest SA unit files, especially `feature_suite.sa` and the std macro surface suites.
- Add per-demo timings inside `tests/wasm_matrix_smoke.zig` so slow demo builds are visible without parsing import noise.
- Add per-test timing in `tests/plugin_host_smoke.zig` around plugin build/load/reload sections.
- Use `SA_PRE_PUSH_PROFILE=fast` for ordinary std macro changes during local iteration, and keep the default `full` profile for commit/release boundaries.

## 2026-06-08 Unit Framework Follow-up

`tests/unit_framework/runner.zig` no longer hard-codes `sa test --jobs 1` for every SA suite. It now reads `SA_TEST_JOBS`, then `SA_ZIG_JOBS`, then `ZIG_BUILD_JOBS`, and otherwise passes `--jobs auto` to `sa test`. The timed pre-push script exports `SA_TEST_JOBS` from the detected worker count unless the caller overrides it.

Focused verification command:

```sh
SA_TEST_JOBS=auto zig build unit-framework --summary all
```

Result: `4/4 tests passed`, elapsed about `3m` for the run step. This is better than the earlier `unit-framework` sample of about `284s`, but it is still one of the dominant gates.

Visible per-file timings from that pass:

| SA unit group | Elapsed |
| --- | ---: |
| `feature_suite.sa` all modes | 54.683s |
| `std_string_vec_macro_surface.sa` | 31.493s |
| `std_path_macro_surface.sa` | 17.065s |
| `std_net_addr_macro_surface.sa` | 12.757s |
| `std_btree_macro_surface.sa` | 5.119s |
| `std_hashmap_macro_surface.sa` | 4.808s |
| `std_fs_macro_surface.sa` | 4.281s |
| `std_iter_macro_surface.sa` | 4.077s |
| `std_vec_deque_macro_surface.sa` | 3.846s |
| `std_hashset_macro_surface.sa` | 3.726s |

Historical finding: `std_fs_macro_surface.sa` previously could not safely run its internal `@test` cases in parallel. With `--jobs auto`, shared file paths raced across filesystem tests and failed with statuses such as `perm_status=3`, `open_status=3`, and `len_status=3`.

Current status: the filesystem macro tests now use isolated per-test paths and `tests/unit_framework/runner.zig` no longer forces this suite to `--jobs 1`. The 2026-06-09 `zig build unit-framework --summary all` pass ran `std_fs_macro_surface.sa` with `jobs=auto` and completed in about `3.771s`.

The current remaining cost is not Zig compilation. It is mostly repeated SA import expansion, repeated SA test binary compile/link work per file, the very large feature suite being run in three modes, and a few large std macro surface suites. The next meaningful improvements are SA test artifact reuse, splitting giant surface suites into independent build units that Zig can schedule separately, and making filesystem tests use isolated temp paths so they can become parallel-safe.

## Current Policy Suggestion

- For narrow `sa_std` macro changes: run the focused SA test file, `sa-std-static`, `cli-skills-smoke` when skills surface changes, then `SA_PRE_PUSH_PROFILE=fast tools/pre_push_timed.sh`.
- For runtime ABI changes: add `sa-std-runtime` and `sa-std-unit`.
- For CLI/plugin changes: add `plugin-host-smoke` and `cli-skills-smoke`.
- For release or install-before-commit boundaries: run the full timed script once.

## 2026-06-08 Pre-push Timing Follow-up

`tools/pre_push_timed.sh` now defaults to `SA_PRE_PUSH_PROFILE=auto` and prints a slowest-stage ranking at the end of successful or failed runs. The explicit profiles are still available through `SA_PRE_PUSH_PROFILE=full|fast|legacy`.

`auto` inspects changed files against the upstream branch plus the current working tree:

- If the changes are limited to `sa_std/`, `tests/unit_framework/`, docs/progress files, generated skill files, or the pre-push script itself, it resolves to `fast`.
- If the changes include compiler/runtime/build/plugin/wasm/source files, it resolves to `full`.
- If no changed files can be detected, it resolves to `full`.

This keeps ordinary standard-library macro work out of unrelated wasm/plugin/system smoke stages while preserving the full gate for broad compiler or runtime changes. The slowest-stage summary avoids digging through long Zig output after a failed hook run.

The unit framework had one stale expected summary after the owned `CString` test was added: `std_ffi_cstr_macro_surface.sa` now reports 2 tests, and `tests/unit_framework/runner.zig` was updated accordingly. Without that fix, pre-push timing runs failed before reaching the later slow std surface suites.

Focused verification after this change:

```sh
SA_TEST_JOBS=auto zig build unit-framework --summary all
```

Result: `4/4 tests passed`, run step about `3m`. The slowest visible SA files were still `feature_suite.sa` at about `53.7s`, `std_string_vec_macro_surface.sa` at about `30.8s`, `std_path_macro_surface.sa` at about `18.1s`, and `std_net_addr_macro_surface.sa` at about `12.7s`.

Conclusion: hook-level filtering and ranking reduce avoidable local pre-push work and improve diagnostics, but the remaining large win must come from unit-framework sharding or SA test artifact/import reuse. Shell-level changes alone cannot remove the repeated SA compile/import cost inside those large suites.

## 2026-06-09 Unit Framework Duplicate Feature Suite Follow-up

`tests/unit_framework/runner.zig` now keeps the full `feature_suite.sa` matrix in the default mode only and checks `--ignored` / `--include-ignored` with a tiny generated two-test fixture. This preserves coverage for ignored-test CLI behavior without compiling and running the 271-test feature matrix two additional times.

Focused verification command:

```sh
zig build unit-framework --summary all
```

Result: `4/4 tests passed`. The visible runner timing showed `feature_suite.sa all modes` at about `23.204s`, down from the previous roughly `53-65s` samples where the large suite was exercised in three modes.

Current slowest visible SA unit groups from that pass:

| SA unit group | Elapsed |
| --- | ---: |
| `std_string_vec_macro_surface.sa` | 48.007s |
| `std_path_macro_surface.sa` | 24.850s |
| `feature_suite.sa` default matrix plus tiny ignored fixture | 23.204s |
| `std_net_addr_macro_surface.sa` | 14.801s |
| `std_iter_macro_surface.sa` | 11.435s |
| `std_vec_deque_macro_surface.sa` | 8.001s |
| `std_hashset_macro_surface.sa` | 7.220s |

The remaining high-cost work is now concentrated in large std macro surface suites and repeated SA import/test artifact work, not in ignored-mode feature-suite duplication.

## 2026-06-09 Project Cache Follow-up

The project cache now has an explicit cleanup command:

```sh
sa cache clean
sa cache clean --dry-run
sa cache clean --max-age-days 7
```

`sa cache clean` is intentionally project-local. It scans only the current directory's `.sa_cache` and does not touch package mirrors, global package caches, or plugin installation caches. The default policy removes malformed cache keys, incomplete entries, empty artifact/output files, and complete entries older than 30 days. `--max-age-days 0` disables age-based expiry and only removes invalid entries.

Build and test cache hits also validate the cached bitcode/output pair before reuse. If either file is missing or empty, the key directory is deleted and the command recompiles normally. This prevents stale partial writes from surviving indefinitely after interrupted builds or manual cache edits.

Cache entries now include a `manifest.json` beside `artifact.sa.bc` and `output.bin`. The manifest records the cache kind, key, artifact byte size, artifact SHA-256, output byte size, and output SHA-256. Cache hits validate the manifest before copying artifacts back to the requested output path; mismatched or malformed entries are deleted and rebuilt. `sa cache clean` applies the same manifest requirement, so old-format entries, tampered files, and hash/size mismatches are removed during explicit cleanup instead of being kept just because both files are non-empty.

`sa test` now stores no-plugin test compile/link artifacts under `.sa_cache/test`. This does not bypass frontend compilation, because test discovery and filtering still require current metadata, but it skips repeated LLVM emit/link work for repeated compile-only or repeated runs of the same source. Native plugin-linked tests are deliberately excluded from this cache so plugin install/uninstall state remains outside compiler-core cache assumptions.

The process-local flattener import cache also avoids cloning cached std source text on hits. The first resolved std import keeps a page-allocator cache copy; later hits borrow that cached source with `owned_source == null` and only duplicate the small path/identity metadata needed by the caller. Invalidated entries remove stale metadata but keep old source buffers alive for the process lifetime, avoiding dangling borrowed text during concurrent or nested import expansion while reducing allocator churn in repeated std imports.

Routine flattener import tracing is now quiet by default. The previous unconditional `[IMPORT] resolved ...` stderr print can still be enabled with `SAASM_TRACE_IMPORTS=1`, but normal smoke/unit runs no longer pay for or display every resolved import.

Focused verification:

```sh
zig test -ODebug ... --test-filter "cli cache clean removes invalid project cache entries" --test-filter "sa test compile-only reuses and repairs project test cache"
zig build bc2sa-smoke --summary all
```

Result: both focused cache tests passed, and `bc2sa-smoke` completed with `3/3 tests passed`. The cache smoke now also covers manifest-backed cleanup and test-cache manifest repair. A broader cache-adjacent pass also completed successfully:

```sh
zig build std-smoke unit-framework --summary all
./zig-out/bin/sa cache clean --max-age-days 0
```

`std-smoke` and `unit-framework` passed (`18/18` tests in the combined build summary). The explicit invalid-only cleanup scanned the newly generated project test cache and reported `scanned=41 removed=0 kept=41`, confirming no incomplete or malformed test cache entries remained after the run.

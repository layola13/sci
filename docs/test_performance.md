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

Important finding: `std_fs_macro_surface.sa` cannot safely run its internal `@test` cases in parallel yet. With `--jobs auto`, the file IO test raced with other filesystem tests and failed with statuses such as `perm_status=3`, `open_status=3`, and `len_status=3`. The runner therefore forces this file to `--jobs 1` while allowing the rest of the SA suites to use the configured parallelism.

The current remaining cost is not Zig compilation. It is mostly repeated SA import expansion, repeated SA test binary compile/link work per file, the very large feature suite being run in three modes, and a few large std macro surface suites. The next meaningful improvements are SA test artifact reuse, splitting giant surface suites into independent build units that Zig can schedule separately, and making filesystem tests use isolated temp paths so they can become parallel-safe.

## Current Policy Suggestion

- For narrow `sa_std` macro changes: run the focused SA test file, `sa-std-static`, `cli-skills-smoke` when skills surface changes, then `SA_PRE_PUSH_PROFILE=fast tools/pre_push_timed.sh`.
- For runtime ABI changes: add `sa-std-runtime` and `sa-std-unit`.
- For CLI/plugin changes: add `plugin-host-smoke` and `cli-skills-smoke`.
- For release or install-before-commit boundaries: run the full timed script once.

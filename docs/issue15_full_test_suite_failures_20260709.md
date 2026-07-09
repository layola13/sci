# Issue 15: Full `zig build test` failures during SAB performance milestone

Status: focused blockers fixed; full-suite timeout narrowed to `sa-std-unit` and fixed; individual test dependency steps passed; logged step runner added for future full validation.

Date: 2026-07-09.

## Summary

After the large-SAB focused compile-only/list milestone, the required full test command did not pass:

```bash
timeout 600s zig build test --summary all
```

The command hit the 600s timeout after reporting failures in existing broader suites. The two known blockers have focused fixes as of 2026-07-09. A later step-by-step rerun covered the `zig build test` dependency set with explicit ownership logs and found the remaining timeout in `sa-std-unit`.

## Observed Failures

1. `tests/plugin_host_smoke.zig`

```text
plugin_host_smoke.test.runtime blocks privileged installed plugins outside dev mode
expected 0, found 1
tests/plugin_host_smoke.zig:1340
```

2. `tests/unit_framework/std_string_macro_surface.sa`

```text
error[PhiStateConflict]: incoming control-flow states do not agree
in function @test "sa_std string splitn aliases"()
register: __str_splitn_remaining_ok_splitn0_spn
state: expected Consumed, actual Untracked
```

The unit-framework runner surfaced this while running the full macro surface suite, after many other macro surface files had passed.

## Notes

- Focused SAB performance gates passed with installed ReleaseFast `sa`.
- This issue should be handled separately from `docs/issue14_test_filter_large_sab_performance.md`.
- The `splitn aliases` blocker was fixed in `sa_std/string.sa` by aligning final-part splitn state cleanup, correcting the final delimiter target, handling `split_count == 1` as whole-string output, and reducing `rsplitn` to reversed `splitn` indexing. Focused source gate passed:

```bash
timeout 180s env SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_macro_surface.sa --filter "splitn aliases" --jobs 1 --no-incremental
```

- The plugin runtime blocker was fixed in `src/plugins.zig` by removing the always-true `project_root` load-time bypass for privileged installed plugins outside dev mode and recording `dev_install=true` in `permissions.lock`. Focused and full plugin smoke gates passed:

```bash
timeout 240s zig test --test-filter "runtime blocks privileged installed plugins outside dev mode" ...
timeout 420s zig build plugin-host-smoke --summary all
```

- The original aggregate timeout could have hidden additional failures, so the validation strategy changed to per-step reruns with explicit timeout ownership before install.

## Follow-up Full Rerun

After the focused fixes, this command was rerun:

```bash
timeout 600s zig build test --summary all
```

Result: timed out with exit code 124. No new explicit assertion failure was reported before timeout. The output showed long-running unit-framework suites, including `std_string_macro_surface.sa` around 135s, `std_slice_vec_macro_surface.sa` around 40s, `std_vec_macro_surface.sa` around 31s, and `std_path_macro_surface.sa` around 36s.

A 1200s rerun also timed out without a final summary. The full-suite strategy was changed to single build-step reruns with explicit step logging. This isolated `sa-std-unit` as the hanging step, then `src/runtime/sa_std.zig` was run with verbose per-test output. The concrete timeout was:

```text
sa_net_uring.test.listen accept recv_ticket and outbound commands work end to end
```

The test passed all earlier ticket assertions but could hang joining loopback client threads because the server-side close command did not guarantee an immediate client-side read EOF. The fix adds deterministic test read timeouts for loopback clients and shuts down the netx runtime before joining those client threads. Focused validation passed:

```bash
timeout 90s zig test --test-filter "listen accept recv_ticket and outbound commands work end to end" ...
timeout 300s zig build sa-std-unit --summary all
```

## Step-by-step Test Rerun

Instead of rerunning another blind 20-minute full suite, each `zig build test` dependency was rerun as an individual build step with an explicit timeout. Passing steps:

- `lib-root-smoke`: 3/3
- `plugin-host-smoke`: 12/12
- `pkg-core-test`: 45/45
- `wasm-matrix`: 1/1
- `bc2sa-smoke`: 2 passed, 1 skipped
- `workspace-smoke`: 1/1
- `trap-baseline`: 1/1
- `unit-framework`: 5/5
- `sa-std-unit`: 63/63
- `sa-std-runtime`: 14/14
- `sa-net-uring-test`: 63/63
- `sa-http2-test`: 19/19
- `sa-tls-server-test`: 8/8
- `sa-dtls-test`: 6/6
- `sa-quic-test`: 10/10
- `sa-term-runtime`: 2/2
- `native-sys-runtime`: 1/1
- `std-smoke`: 8/8
- `smoke`: 9/9
- `scope-demo`: 1/1
- `ffi-handle-demo`: 1/1
- `hubproxy-test`: 2/2

This covers the unit-test dependency set with per-object logs and avoids masking timeout ownership inside a monolithic full-suite run.

## Follow-up Diagnostic Tooling

The manual step-by-step strategy has been captured as `tools/test_steps_timed.sh` so future full validation does not have to rely on a blind aggregate command.

Key behavior:

- default step list covers the `zig build test` dependency set through named build steps.
- per-step START/PASS/FAIL/TIMEOUT logs include UTC timestamp, exact command, elapsed time, and status.
- full output is persisted to a log directory, defaulting to ignored `logs/test_steps/<utc timestamp>`, with one numbered log per step plus `summary.log`.
- per-step timeout defaults to `SA_TEST_STEP_TIMEOUT` or `420s`, and can be overridden with `--timeout`.
- log directory can be overridden with `--log-dir` or `SA_TEST_STEP_LOG_DIR`.
- `--continue` keeps collecting failures/timeouts instead of stopping at the first failed step.
- `std-smoke` plus `whitepaper-lint` covers the std and whitepaper smoke artifacts without the duplicate std-smoke rerun hidden behind the aggregate `smoke` step.

Focused verification:

```bash
bash -n tools/test_steps_timed.sh
tools/test_steps_timed.sh --list
tools/test_steps_timed.sh --timeout 180 lib-root-smoke pkg-core-test
tools/test_steps_timed.sh --timeout 180 --log-dir /tmp/sci-test-steps-logs pkg-core-test
```

Result: pass. The two-step focused run reported `lib-root-smoke` at `50.989s`, `pkg-core-test` at `1.419s`, and printed a slowest-step summary. The explicit log-dir check generated `summary.log` and `01-pkg-core-test.log`; a separate invalid-step check preserved exit status `1` and captured the Zig error output in its step log.

Additional heavy-step timing was added after the step runner:

- `tests/plugin_host_smoke.zig` now prints per-Zig-test START/END timing. Focused validation with `tools/test_steps_timed.sh --timeout 420 plugin-host-smoke` passed in `230.858s`.
- `tests/wasm_matrix_smoke.zig` now prints per-demo and per-phase START/END timing for `build-exe`, `native-run`, `build-wasm`, and `wasm-run`. Focused validation with `tools/test_steps_timed.sh --timeout 420 wasm-matrix` passed in `149.039s`.

Milestone full logged pass:

```bash
tools/test_steps_timed.sh --continue --timeout 420 --log-dir logs/test_steps/full-20260709T060333Z
```

Result: pass, `passed=22 failed=0 timeout=0 total=22 elapsed=789.076s`. This validates the full test dependency set with per-step timeout ownership and persisted logs, without relying on a blind aggregate `zig build test` command.

## Install Gate

After the issue fixes and per-step test reruns passed, installation was run:

```bash
timeout 300s ./tools/install.sh --no-shell
```

Result: pass. Installed focused downstream SAB gates also passed:

- Large `world_table_erased` compile-only focused gate: `elapsed=0.75 maxrss=167856`
- Large `world_table_erased` list focused gate: `elapsed=0.04 maxrss=56960`
- Small `parallel_table_erased` compile-only focused gate: `elapsed=0.13 maxrss=70912`

## Follow-up Runtime Optimization

The first post-logging optimization targets `plugin-host-smoke`, which was the slowest step in the full logged pass at `209.569s`.

`src/plugins.zig` now runs install preflight checks that do not need a built artifact before `buildPluginProject()`:

- interface file verification.
- asset file verification.
- installed extern-symbol conflict checks.

The artifact-dependent checks remain after build/copy. Focused logged verification passed:

```bash
tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/plugin-opt-20260709T070747Z plugin-host-smoke
```

Result: `12/12 tests passed`, `elapsed=170.743s`, saving `38.826s` (`18.5%`) versus the previous logged `plugin-host-smoke` baseline. The duplicate extern failure tests are the main visible beneficiaries because they now fail before unnecessary temporary plugin builds.

The second follow-up optimization targets `sa-std-runtime`, which was the next slowest step in the full logged pass at `145.815s`.

`tests/sa_std_runtime.zig` no longer rebuilds `src/runtime/sa_std.zig` inside every C demo test. The build step now refreshes `artifacts/sa_std/libsa_std.a` once, and each C demo copies that archive into its temp directory before linking and running.

Focused logged verification passed:

```bash
tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/sa-std-runtime-opt-20260709T073000Z sa-std-runtime
```

Result: `14/14 tests passed`, `elapsed=33.532s`, saving `112.283s` (`77.0%`) versus the previous logged `sa-std-runtime` baseline.

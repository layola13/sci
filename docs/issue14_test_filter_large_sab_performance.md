# Issue 14: Large SAB `sa test --filter` / `--list` performance

Status: partially fixed; compile-only/list focused SAB targets are at or near the 1s iteration goal in ReleaseFast.

Date: 2026-07-09.

## Summary

Real downstream `sla_ecs` generated large SAB artifacts show that SCI still spends seconds to tens of seconds in the `sa test` compile path even when a focused `--filter` selects only one test. The small 265 KiB `parallel_table_erased.sab` path is already close to the 1 second target, but the 6.4 MiB `world_table_erased.sab` path is not.

## Repro Inputs

Repository: `/home/vscode/projects/sci`.

Downstream artifacts:

- `/home/vscode/projects/sla_ecs/.sla-cache/sab/parallel_table_erased-ab6b0062c772adb.sab` (`265 KiB`)
- `/home/vscode/projects/sla_ecs/.sla-cache/sab/world_table_erased-5d5e95eb4646a2ce.sab` (`6.4 MiB`)

## Measurements

Post-fix ReleaseFast focused gates using local `./zig-out/bin/sa`:

- Large SAB `--list --filter`: `elapsed=0.05 maxrss=56576`.
- Large SAB `--compile-only --filter --no-incremental`: `elapsed=0.82 maxrss=167528`, `compiled 1 selected tests (70 discovered)`.
- Small SAB `--compile-only --filter --no-incremental`: `elapsed=0.17 maxrss=70104`, `compiled 1 selected tests (1 discovered)`.

Final post-install focused gates using `/home/vscode/.sa/bin/sa` after issue fixes and `tools/install.sh --no-shell`:

- Large SAB `--list --filter`: `elapsed=0.04 maxrss=56960`.
- Large SAB `--compile-only --filter --no-incremental`: `elapsed=0.75 maxrss=167856`, `compiled 1 selected tests (70 discovered)`.
- Small SAB `--compile-only --filter --no-incremental`: `elapsed=0.13 maxrss=70912`, `compiled 1 selected tests (1 discovered)`.

Profile for the large compile-only gate:

```text
profile sab load_flat=128.219ms prune=353.729ms verify=12.585ms trusted=1
profile test compile=496.834ms emit=476.366ms link=0.000ms total=985.677ms
```

Implementation notes:

- `.sab --list` uses metadata-only test signature decoding and skips full decode/verify.
- `.sab + explicit test selection + --compile-only` prunes to selected-test reachability before emit, uses borrowed SAB symbol pools, trusts the SAB as preverified, and stops after LLVM bitcode emit instead of linking a throwaway test executable.
- Actual test execution does not use the trusted compile-only shortcut; it still links and runs.
- Remaining large opportunity: partial/lazy SAB instruction decode. The current compile-only path still full-decodes the instruction section before pruning.

Small SAB focused compile-only is near target:

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/parallel_table_erased-ab6b0062c772adb.sab \
  --compile-only \
  --filter "table erased readonly parallel runner executes no conflict systems on threads" \
  --jobs 1 --no-incremental
```

Result: `elapsed=1.28 maxrss=70252`, `compiled 1 selected tests (1 discovered)`.

Small SAB `--list`:

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/parallel_table_erased-ab6b0062c772adb.sab \
  --list \
  --filter "table erased readonly parallel runner executes no conflict systems on threads" \
  --jobs 1
```

Result: `elapsed=0.33 maxrss=57136`.

Large SAB focused list is far above target:

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/world_table_erased-5d5e95eb4646a2ce.sab \
  --list \
  --filter "table erased high k query combinations preserve entity order" \
  --jobs 1
```

Result: `elapsed=8.87 maxrss=385224`, `test count: 1`.

Large SAB focused compile-only is much worse:

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/world_table_erased-5d5e95eb4646a2ce.sab \
  --compile-only \
  --filter "table erased high k query combinations preserve entity order" \
  --jobs 1 --no-incremental
```

Result: `elapsed=30.61 maxrss=465592`, `compiled 1 selected tests (70 discovered)`.

Cached/no explicit `--no-incremental` repeat remained slow:

```text
elapsed=33.51 maxrss=464808
```

## Original Root Cause

`src/cli.zig` `executeTest()` calls `compileSource()` before collecting test metadata or applying `--filter`/`--list`. For `.sab`, `compileSource()` calls `loadSabFlat()` and then `referee.verifyWithOptions()` over the whole decoded module.

Consequence:

- `sa test <large.sab> --list --filter ...` still decodes and verifies the full SAB before listing one selected test.
- `sa test <large.sab> --compile-only --filter ...` verifies, emits LLVM, and links using the whole module instead of a reachable subset for the selected test.

## Fix Plan / Follow-up

1. Done: fast path `.sab` `sa test --list` decodes only enough SAB metadata/function signatures to collect tests and skips full verifier.
2. Done for compile-only: focused selected-test reachability pruning before emit, borrowed symbol pools, trusted preverified SAB compile-only path, and skip-link for selected `.sab --compile-only`.
3. Remaining: actual `sa test` run path still verifies/links because it must produce and execute a valid binary.
4. Remaining: partial/lazy SAB instruction decode to avoid full instruction decode before pruning.
5. Remaining: cache key correction for filtered compile artifacts if selected linked artifacts are cached in the future.

## Acceptance Gates

Primary real gates:

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/world_table_erased-5d5e95eb4646a2ce.sab \
  --list \
  --filter "table erased high k query combinations preserve entity order" \
  --jobs 1
```

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/world_table_erased-5d5e95eb4646a2ce.sab \
  --compile-only \
  --filter "table erased high k query combinations preserve entity order" \
  --jobs 1 --no-incremental
```

Small SAB guard:

```bash
timeout 180s /usr/bin/time -f 'elapsed=%e maxrss=%M' \
  sa test /home/vscode/projects/sla_ecs/.sla-cache/sab/parallel_table_erased-ab6b0062c772adb.sab \
  --compile-only \
  --filter "table erased readonly parallel runner executes no conflict systems on threads" \
  --jobs 1 --no-incremental
```

Target: focused large-SAB `--list` should avoid full verify immediately; focused large-SAB `--compile-only` should trend toward 1s after reachable test pruning is implemented.

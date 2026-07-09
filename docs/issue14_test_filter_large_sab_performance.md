# Issue 14: Large SAB `sa test --filter` / `--list` performance

Status: open, active fix in progress.

Date: 2026-07-09.

## Summary

Real downstream `sla_ecs` generated large SAB artifacts show that SCI still spends seconds to tens of seconds in the `sa test` compile path even when a focused `--filter` selects only one test. The small 265 KiB `parallel_table_erased.sab` path is already close to the 1 second target, but the 6.4 MiB `world_table_erased.sab` path is not.

## Repro Inputs

Repository: `/home/vscode/projects/sci`.

Downstream artifacts:

- `/home/vscode/projects/sla_ecs/.sla-cache/sab/parallel_table_erased-ab6b0062c772adb.sab` (`265 KiB`)
- `/home/vscode/projects/sla_ecs/.sla-cache/sab/world_table_erased-5d5e95eb4646a2ce.sab` (`6.4 MiB`)

## Measurements

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

## Current Root Cause

`src/cli.zig` `executeTest()` calls `compileSource()` before collecting test metadata or applying `--filter`/`--list`. For `.sab`, `compileSource()` calls `loadSabFlat()` and then `referee.verifyWithOptions()` over the whole decoded module.

Consequence:

- `sa test <large.sab> --list --filter ...` still decodes and verifies the full SAB before listing one selected test.
- `sa test <large.sab> --compile-only --filter ...` verifies, emits LLVM, and links using the whole module instead of a reachable subset for the selected test.

## Fix Plan

1. Fast path `.sab` `sa test --list`: decode only enough SAB metadata/function signatures to collect tests, skip full verifier. This should take the large `world_table_erased.sab --list --filter ...` path from about 8.9s toward sub-second or low-single-second decode cost.
2. Focused compile path: after collecting selected tests, build a test-specific reachable function graph and prune the verified/emitted module before LLVM emission/link. This is the path required to move `world_table_erased.sab --compile-only --filter ...` from about 30s toward 1s.
3. Cache key correction: include the effective test selection in the test cache key or store per-selection artifacts, otherwise filtered and unfiltered compile artifacts cannot safely share one executable.

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

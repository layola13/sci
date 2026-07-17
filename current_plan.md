# Current Plan

Date: 2026-07-17

## Current turn: native evidence success-only upload hardening

1. [x] Keep the worktree clean before starting the batch.
2. [x] Require macOS/Windows native runtime evidence uploads to run only after prior steps and validation succeed.
3. [x] Require macOS/Windows native smoke evidence uploads to run only after prior steps and validation succeed.
4. [x] Lock the upload condition with Linux-runnable macOS/Windows source contracts.
5. [x] Run focused workflow/CI contract validation, then commit and push the batch.

## Current turn: native evidence exact-schema hardening

1. [x] Keep the worktree clean before starting the batch.
2. [x] Reject unexpected top-level fields in native smoke/runtime evidence JSON.
3. [x] Lock the exact-schema behavior with validator tests and macOS/Windows source contracts.
4. [x] Run focused validator/CI contract validation, then commit and push the batch.

## Current turn: native evidence platform-target matrix hardening

1. [x] Keep the worktree clean before starting the batch.
2. [x] Validate native evidence platform/architecture combinations in the shared validator.
3. [x] Validate runtime evidence target values against the platform/architecture matrix.
4. [x] Lock the stricter matrix with validator tests and macOS/Windows source contracts.
5. [x] Run focused validator/CI contract validation, then commit and push the batch.

## Current turn: native evidence provenance-shape hardening

1. [x] Keep the worktree clean before starting the batch.
2. [x] Require native evidence GitHub SHA expectations to be full 40-character hexadecimal commit IDs.
3. [x] Require native evidence GitHub run id and run attempt expectations to be positive decimal integers.
4. [x] Lock the stricter provenance shape with validator tests and macOS/Windows source contracts.
5. [x] Run focused validator/CI contract validation, then commit and push the batch.

## Current turn: native evidence required-field hardening

1. [x] Keep the worktree clean before starting the batch.
2. [x] Reject empty or `unknown` native evidence toolchain/provenance arguments in the shared validator.
3. [x] Lock the stricter validator behavior with macOS/Windows source contracts and focused validator tests.
4. [x] Run focused validator/CI contract validation, then commit and push the batch.

## Current turn: native smoke toolchain fallback

1. [x] Keep the worktree clean before the batch and preserve unrelated changes.
2. [x] Make macOS native smoke derive Zig/LLVM versions from `zig version` and `LLVM_CONFIG --version` when workflow env vars are absent.
3. [x] Make Windows native smoke derive Zig/LLVM versions from `zig version` and `clang --version` when workflow env vars are absent.
4. [x] Lock the fallback logic with macOS/Windows source contracts.
5. [x] Run focused syntax/format/contract validation, then commit and push the batch.

## Current turn: native evidence schema pinning

1. [x] Preserve unrelated `src/cli.zig` and `tests/cli_smoke.zig` worktree changes without staging them.
2. [x] Add `evidence_schema_version: 1` to macOS/Windows native smoke and runtime evidence.
3. [x] Validate the schema version through the shared native evidence validator, including a schema-drift rejection test.
4. [x] Lock the schema field with macOS/Windows source contracts and architecture docs.
5. [x] Run focused validator/CI contract validation, syntax/YAML/format/diff checks, then commit and push the batch.

## Current turn: native evidence toolchain provenance

1. [x] Confirm this Linux host cannot trigger or read private GitHub native workflow runs because `gh` is unauthenticated and public Actions API access is unavailable.
2. [x] Add Zig/LLVM version provenance to macOS and Windows native smoke/runtime evidence.
3. [x] Validate those toolchain fields through the shared native evidence validator.
4. [x] Lock the fields and validator arguments with macOS/Windows source contracts.
5. [x] Run focused validator/CI contract validation, syntax/YAML/format/diff checks, then commit and push the batch.

## Current turn: native smoke HTTP installer evidence field

1. [x] Preserve unrelated `src/cli.zig` worktree changes without staging them.
2. [x] Add `http_installed_version` to macOS/Windows native-smoke evidence after the loopback HTTP installer succeeds.
3. [x] Validate `http_installed_version` through the shared native evidence validator.
4. [x] Lock the new evidence field with macOS/Windows source contracts.
5. [x] Run focused validator/CI contract validation, syntax/format/diff checks, then commit and push the batch.

## Current turn: native installer HTTP release-download evidence

1. [x] Keep the worktree clean before starting the batch and preserve unrelated changes.
2. [x] Add loopback HTTP release-download installer smoke after the existing local `file://` installer smoke in macOS and Windows native smoke scripts.
3. [x] Record `installer_transports: ["file", "http"]` in native-smoke evidence and validate it through `tools/ci/validate_native_evidence.zig`.
4. [x] Lock the script and validator changes with macOS/Windows CI source contracts.
5. [x] Run focused validator/CI contract validation, syntax/format/diff checks, then commit and push the batch.

## Current turn: release contract native-evidence binding

1. [x] Preserve unrelated compiler/cache worktree changes without staging them.
2. [x] Make `release-contract` depend on the shared `native-evidence-validator` tests.
3. [x] Lock that build-graph dependency in `tests/release_contract.zig`.
4. [x] Run focused release/validator validation, formatting/YAML/diff checks, then commit and push only this portability batch.

## Current turn: native evidence validator

1. [x] Preserve unrelated `src/cli.zig` worktree changes without staging them.
2. [x] Add a shared Zig validator for native smoke/runtime evidence JSON.
3. [x] Route macOS and Windows native-smoke/native-runtime evidence validation through the shared validator.
4. [x] Expose the validator as a named `native-evidence-validator` build step and make macOS/Windows CI contracts depend on it.
5. [x] Lock the validator calls and platform gate lists with source contracts.
6. [x] Run validator build step, focused macOS/Windows CI contract validation, workflow YAML parsing, formatting/diff checks, then commit and push only the coherent portability batch.

## Current turn: native runtime evidence artifacts

1. [x] Preserve unrelated compiler/cache worktree changes without staging them.
2. [x] Add macOS runtime evidence JSON after plugin, daemon, shared runtime, PAL, NetX, Darwin, Darwin socket, and Darwin PTY gates pass.
3. [x] Add Windows runtime evidence JSON after shared basic, PAL, NetX, and Windows runtime gates pass.
4. [x] Validate those runtime evidence files before upload and lock them with source contracts.
5. [x] Run focused macOS/Windows CI contract validation, workflow YAML parsing, formatting/diff checks, then commit and push only the coherent portability batch.

## Current turn: native smoke evidence provenance

1. [x] Preserve unrelated cache/compiler worktree changes without staging them.
2. [x] Add GitHub SHA, run id, and run attempt to macOS/Windows native-smoke evidence JSON.
3. [x] Validate those provenance fields in both native workflows before artifact upload and lock them with source contracts.
4. [x] Run focused macOS/Windows CI contract validation, syntax/format/diff checks, then commit and push only the coherent portability batch.

## Current turn: native smoke evidence validation

1. [x] Confirm remote GitHub workflow execution cannot be triggered from this host because `gh` is not authenticated.
2. [x] Add macOS/Windows workflow steps that parse native-smoke evidence JSON and validate platform, architecture, archive name, wasm magic, pass marker, and staged/installed version strings before upload.
3. [x] Lock the validation steps with Linux-runnable source contracts.
4. [x] Run focused macOS/Windows CI contract validation, formatting/diff checks, then commit and push the coherent batch.

## Current turn: native smoke evidence artifact capture

1. [x] Audit macOS/Windows native compiler smoke scripts and workflow upload behavior.
2. [x] Add optional evidence JSON output to both native smoke scripts after staged archive, installer, wasm, package, and installed-check smokes pass.
3. [x] Upload native smoke evidence artifacts from macOS and Windows workflows with source contracts locking the artifact names and required fields.
4. [x] Run focused macOS/Windows CI contract validation, script syntax checks, formatting/diff checks, then commit and push the coherent batch.

## Current turn: release matrix native-evidence guard

1. [x] Audit the release workflow boundary for non-Linux archive rows.
2. [x] Keep macOS/Windows release artifacts commented out until native workflow evidence exists for compiler, runtime, installer, and archive smoke.
3. [x] Add a Linux-runnable release source contract that rejects active macOS/Windows release matrix rows.
4. [x] Run focused release contract validation, formatting/diff checks, then commit and push the coherent batch.

## Current turn: Windows native plugin-smoke contract

1. [x] Platformize `tests/plugin_host_smoke.zig` for native Windows by using host-specific `linux|macos|windows` artifact keys, `.so/.dylib/.dll` names, and Windows-safe environment handling.
2. [x] Make plugin artifact undefined-import scanning compatible with COFF/Windows by normalizing `__imp_` prefixes alongside the existing ELF/Mach-O handling.
3. [x] Wire `plugin-host-smoke` into `.github/workflows/windows-native.yml` and lock the Windows CI/source contract around the reviewed subset.
4. [x] Validate on Linux with plugin smoke `12/12`, plugin unit `3/3`, Windows CI contract `4/4`, Windows cross-build evidence, and `git diff --check`.
5. [ ] Execute the Windows workflow on the native runner and record installed `sa_std.lib` consumption plus the shared runtime gate; continue the remaining macOS native runner execution separately.

## Current turn: Windows PAL network-interface backend

1. [x] Audit `GetAdaptersAddresses`, `IP_ADAPTER_ADDRESSES_LH`, `IP_ADAPTER_UNICAST_ADDRESS_LH`, and x86_64/aarch64 Windows ABI layouts.
2. [x] Implement Windows adapter/unicast enumeration with IPv4/IPv6 address, prefix-derived netmask/CIDR, friendly name, and physical address JSON.
3. [x] Add Linux-runnable pure helper coverage plus PAL/build/Windows CI source contracts.
4. [x] Link `iphlpapi` and the audited IOCP `mswsock` dependency through runtime artifacts, tests, ABI builds, and compiler-produced executables.
5. [x] Run focused native Linux and Windows cross-target gates, update evidence, and commit the coherent batch promptly.

## Current turn: POSIX process capture evidence sync

1. [x] Audit current POSIX process capture implementation for wait-before-drain deadlock risk.
2. [x] Confirm capture mode drains stdout/stderr before and during nonblocking wait loops.
3. [x] Confirm runtime basic contract covers outputs beyond one 8192-byte read per stream.
4. [x] Re-run `test-runtime-basic` with an isolated Zig cache and record evidence.
5. [x] Update tracking docs without staging unrelated CLI/cache worktree changes.

## Current turn: PAL system-identity portability batch

1. [x] Audit the remaining runtime-core identity calls and Windows support boundary.
2. [x] Move hostname/release/PID/PPID/UID/GID to Linux/macOS/Windows PAL backends.
3. [x] Add source-contract checks and focused Linux behavior coverage.
4. [x] Run PAL/runtime/ABI/portability/ReleaseFast validation and `git diff --check`.
5. [x] Commit the coherent system-identity PAL batch without staging unrelated files.

## Current turn: PAL network-interface portability batch

1. [x] Audit the existing POSIX implementation and identify Linux sysfs plus Darwin sockaddr-layout coupling.
2. [x] Move network-interface JSON construction to Linux/macOS PAL backends and keep Windows explicitly unsupported.
3. [x] Update PAL source-contract checks and add focused helper coverage.
4. [x] Run PAL/runtime/ABI/portability/ReleaseFast validation and `git diff --check`.
5. [x] Commit the coherent network-interface PAL batch without staging unrelated files.

## Current turn: PAL uptime/loadavg portability batch

1. [x] Confirm the worktree and preserve unrelated cache-writer PID diagnostics in `src/cli.zig` and `tests/cli_smoke.zig`.
2. [x] Move uptime/loadavg runtime exports to `pal_sys` and add Linux/macOS/Windows backend behavior.
3. [x] Update PAL source-contract checks so `/proc/uptime` and `/proc/loadavg` stay behind the Linux PAL backend.
4. [x] Run focused PAL/runtime/portability/release-fast validation and `git diff --check`.
5. [x] Commit the coherent PAL batch promptly without staging unrelated files.

## Active objective: implement the compiler performance plan

Reference: `docs/compiler_performance_optimization_cn.md`. GPU acceleration is explicitly excluded. Correctness, cache authorization, deterministic diagnostics, and ownership semantics remain hard gates; no trusted/empty-delta verification shortcut may be reintroduced for codegen.

1. [x] Land Phase -1 containment: full Referee for compile/check/emit, affected last-good transactionality, cache-hit authorization preflight, conservative focused-prune fallback, daemon cwd serialization/hard worker limit, and backend debug-output removal.
2. [ ] **Focused verified — P0.2 verify key v2 verdict-only checkpoint:**
   - [x] define schema-namespaced `VerificationInputDigest` v2 over instruction structure, const declarations/vtables, canonical grants, package identity/SHA, SAX component, metadata mode/predecoded symbols/signatures, and `check_exit_leaks`;
   - [x] replace raw verdict map access with explicit consumer capability and a process-local success-only cache capped by coarse 4096-entry rollover;
   - [x] expose `verifyInput()` and `verifyVerdictOnly()` without constructing a fake `VerifyOk` on hit;
   - [x] route text and SAB `sa check` through the verdict-only API, with SAB using predecoded metadata and `verify-verdict-v2` JSON metrics;
   - [x] keep compile/build/emit on full Referee and pass the repeated compile containment gate with annotations/deltas/gas preserved and verdict hits still `0`;
   - [x] pass focused gates: digest field coverage `24/24`, incr verify `26/26`, trap-not-cached `1/1`, text check miss→hit `1/1`, SAB check miss→hit `1/1`, codegen containment `1/1`, related format/diff checks, and fresh Debug `sa-cli` build `5/5`;
   - [ ] finish owned `VerifySnapshot` restore, source-map rebind, full field differential, daemon/cross-process pressure, cross-platform validation, and formal P50/P95/RSS evidence before calling P0.2 complete.
3. [ ] **In progress — finish the P0.3 cache contract:**
   - [x] record environment present/absent state and value digest;
   - [x] record canonical included-file path, size, and digest through recursive includes;
   - [x] persist dependencies in manifest v2 and prevalidate them before cache publication;
   - [x] retain safe bypass/fallback whenever dependency capture is incomplete or changes during capture;
   - focused verified: INCLUDE `2/2`, absent `OPTION_ENV!` `1/1`, validator `1/1`, INCLUDE_STR cache closure `1/1`, explicit absent→present cache closure `1/1`;
   - [x] publish artifact/output/test metadata as one staging directory with manifest last and atomic directory rename;
   - [x] pin hit/store/incremental/clean paths with per-key shared/exclusive locks and preserve active staging during cleanup;
   - [x] split structural manifest validation from current dynamic-dependency reusability; direct gates `4/4`, CLI cache closures `3/3`;
   - [x] add explicit `OPTION_ENV!` absent→present regression, including single-entry and no-raw-value manifest assertions;
   - [x] split entry locks from blocking build-owner locks and pass direct failed-owner handoff plus OOM no-partial-entry gates `1/1` each;
   - [x] compile/restore build outputs in private sibling stages and make build/test cache claim/store failures best-effort;
   - [x] serialize final publication for different keys sharing one `-o` through `.sa-output-locks/<basename>` and pass the forced-interleaving pair test `1/1`;
   - [x] close the focused incremental function-object integrity checkpoint: manifest v2 digest-authorized reuse; function key v8 with global/local lowering-context separation and numeric local slots for body `.reg` operands plus verifier `change.reg`; backend ABI v11; synced sibling-temp emission; link-before-manifest, manifest-last commit, and post-commit cleanup; non-cacheable dependency bypass; `DT_UNKNOWN` fallback; DCE-selected global owner; full indirect-provenance signature ordering; function-local collision-safe anonymous strings; Linux ELF hidden-symbol localization; and direct/indirect owned-return release correctness are focused verified;
   - [x] add focused project-cache manifest symlink artifact/output rejection with `incomplete` lookup and redacted `output.file` first-difference evidence;
   - [x] extend focused symlink rejection to project-cache `manifest.json` and `test-metadata.json`, including invalid status and metadata-parse rejection evidence;
   - [ ] add emit/sync/rename/link/manifest failure injection, malformed/legacy/oversize/path/missing/extra-object cases, broader symlink coverage, TOCTOU-hard path authorization, crash recovery, persistent lock accounting, same-key cross-process coverage, and native macOS/Windows validation;
   - [ ] repair remaining failed artifact/output publication cases and broaden corruption recovery.
4. [ ] **In progress — finish the LLVM focused reachability queue (P0.5):**
   - [x] index function body ranges once and process every reachable function body at most once;
   - [x] preserve unknown/invalid/indirect/address-taken and signature/body mismatch fallback;
   - [x] pass focused direct-closure/function-reference/unknown-call tests `3/3`;
   - [x] finish recursion and both LLVM emit-path differential tests before shared-engine completion: `focused test prune` now passes `6/6`, including self-recursive root single-scan and real `emitLlvmc`/`emitLlvmcToArtifacts` bitcode pruning gates;
   - [ ] build the shared cross-consumer ReachabilityEngine with edge provenance for full, focused, CGU, SAB, and affected-test consumers.
5. [ ] **Partial — P0.6 cache explanation surface:**
   - [x] add stable `cache.reason` to success metrics without removing existing `cache.kind`/`cache.hit`;
   - [x] report `hit`, `absent`, `dependency_changed`, `manifest_invalid`, `artifact_corrupt`, `incomplete`, and fallback `unknown` from build-exe/build-obj/build-wasm artifact-cache lookup paths;
   - [x] pass focused project-cache smoke coverage `4/4`, including cold miss, warm hit, INCLUDE_STR dependency flip, OPTION_ENV absent-to-present, artifact corruption, and manifest-invalid repair;
   - [x] add read-only `sa cache status` and `sa cache why` text/JSON inspection for project-local entries, showing kind, key prefix, reason, manifest status, bytes, and last-write mtime without source/package-secret disclosure; focused cache smoke now passes `10/10`;
   - [x] report `cache.reason="disabled"` with `hit=false` for `--no-incremental` build-exe/build-obj/build-wasm project artifact cache disablement; focused cache smoke still passes `10/10`;
   - [x] explain otherwise reusable `sa cache status/why --max-age-days <n>` entries as `expired` without changing build lookup semantics; focused cache smoke still passes `10/10`;
   - [x] record source-free recent-hit telemetry in `.sa_cache/.hits/<kind>/<key>` and show `last_hit_ns` in `sa cache status/why` without mutating entry manifest/write mtime; focused cache smoke still passes `10/10`;
   - [x] show redacted field-level `first_difference` for existing invalid/incomplete/corrupt entries in `sa cache status/why` without exposing env names, paths, hashes, source, or full keys; focused cache smoke still passes `10/10`;
   - [x] record source-free recent-store telemetry in `.sa_cache/.stores/<kind>/<key>` after successful entry publication and show `last_store_ns` in `sa cache status/why` without mutating entry manifest/write mtime; focused cache smoke still passes `10/10`;
   - [x] record source-free successful store-event telemetry in `.sa_cache/.store-events/<kind>/<key>` and show `last_store_result="published"` in `sa cache status/why` without mutating entry manifest/write mtime; focused cache smoke still passes `12/12`;
   - [x] record source-free failed store-event telemetry in `.sa_cache/.store-events/<kind>/<key>` and show `last_store_result="failed"` in `sa cache why --json` even when the entry directory is absent; later successful publication overwrites it with `published`; focused single-flight smoke passes `1/1`, focused cache smoke remains `13/13`, and Debug `sa-cli` build passes `5/5`;
   - [x] record source-free store-event pipeline stage in `.sa_cache/.store-events/<kind>/<key>` and expose `last_store_stage` in `sa cache status/why`; focused failure verifies `copy_output`, and later successful publication overwrites it with `publish`; focused single-flight smoke passes `1/1`;
   - [x] verify source-free Linux writer identity in `.sa_cache/.store-events/<kind>/<key>` and expose it as `last_store_writer_pid` in `sa cache status/why`; legacy/missing fields report `null`; focused single-flight smoke passes `1/1`, focused cache smoke passes `13/13`, and Debug `sa-cli` build passes `5/5`;
   - [x] record Linux source-free writer process start ticks in store events and expose them as `last_store_writer_start_ticks`; legacy/missing fields report `null`, and focused single-flight evidence verifies failed and successful store-event surfaces are non-null on Linux;
   - [x] append source-free per-key store-event history records and expose `last_store_event_count` in `sa cache status/why`; focused single-flight evidence verifies failed `copy_output` count `1`, then successful waiter publish as latest `published/publish` with history count `2`;
   - [x] expose source-free store-event history result counts as `last_store_published_event_count` and `last_store_failed_event_count`; focused single-flight evidence verifies `0/1` after the failed owner and `1/1` after waiter publish;
   - [x] record source-free owner acquisition context as `last_store_owner_miss_reason` in store events; focused single-flight evidence verifies the failed first owner and the waiter publish both report `absent`, while legacy/direct events report `null`;
   - [x] add focused store-event `sa cache why --json` redaction evidence for failed and later successful store events: the 12-character key prefix is visible, but the full 64-character cache key is not;
   - [x] report redacted `first_difference="key.digest"` in `sa cache why --json` when an absent requested key has a same-kind old candidate sharing the 12-character key prefix but differing in the complete digest; focused cache smoke remains `13/13`, and Debug `sa-cli` build passes `5/5`;
   - [x] expose `cache.kind="test"`, `cache.hit`, and `cache.reason` for `sa test --compile-only --json` cold miss and warm hit paths; focused cache smoke still passes `10/10`;
   - [x] expose `cache.kind="test"`, `cache.hit`, and `cache.reason` for successful ordinary `sa test --json` cold miss and warm hit paths after the test runner exits successfully; focused cache smoke still passes `10/10` and fresh Debug `sa-cli` build passes `5/5`;
   - [x] report `cache.reason="selection_changed"` for cold `sa test --compile-only --json --filter ...` paths that intentionally avoid publishing a selected artifact as the full test cache; focused cache smoke still passes `10/10`;
   - [x] report `cache.reason="bypassed_untrusted"` for build-exe CGU artifact paths, non-cacheable dynamic-dependency build-exe paths, and `sa test --json` plugin link-input paths that intentionally do not publish project cache entries; focused cache smoke now passes `12/12`;
   - [x] report `reason="evicted"` from `sa cache why --json` for real 64-hex project-cache entries removed by `sa cache clean`, using source-free `.sa_cache/.evictions/<kind>/<key>` markers; focused cache smoke still passes `10/10`;
   - [x] report `cache.reason="lock_owner_failed"` when project-cache claim/owner locking fails and the command falls back to ordinary compilation; focused cache smoke still passes `10/10` and fresh Debug `sa-cli` build passes `5/5`;
   - [x] expose `cache.kind="test"`, `cache.hit`, and `cache.reason` for `sa test --list --json` cold list `selection_changed`, disabled list `disabled`, and cached-list `hit` paths; focused cache smoke still passes `12/12`;
   - [x] expose `cache.kind="test"`, `cache.hit`, and `cache.reason` for successful `sa test --affected --json` cold `absent` and warm `hit` paths after the runner exits successfully; focused affected smoke passes `1/1`, focused cache smoke now passes `13/13`, and Debug `sa-cli` build passes `5/5`;
   - [x] finish fine-grained candidate old-entry key input first-difference reporting beyond coarse `key.digest`; focused status/why evidence now reports `key.command` for same-prefix absent candidates when sidecar key-input traces differ, while richer owner lifecycle telemetry beyond result/stage/owner miss reason/history result counts/Linux pid/start-ticks/event count, full redaction review beyond the focused store-event/key-prefix/dynamic-dependency checks, and broader cross-process/cross-platform coverage remain open.
   - [x] validate source-free store-event marker/history headers before exposing telemetry; mismatched `version`/kind/key-prefix events are ignored, focused internal test passes `1/1`, cache smoke remains `3/3`, and Debug `sa-cli` build passes `5/5`;
6. [ ] **Partial — extend the verified Referee delta checkpoint (P1.2):**
   - [x] reuse `state_before`/change scratch and perform one ordered diff scan;
   - [x] pass focused/all 63 Referee tests and the 128-register allocation fixture (`434 -> 307` allocations, `175,722 -> 143,978` requested bytes);
   - [ ] introduce `StateWriter` + dirty epoch/list so executable instructions no longer copy the whole state;
   - [ ] keep seed/reset/label restore non-recording and dual-check old/new deltas during migration.
7. [ ] Close the remaining artifact-key boundary:
   - [x] key native `build-exe`/`test` on canonical runtime archive path, size, and SHA-256 under namespace v3;
   - [x] pass an isolated same-path/same-size archive content-flip key test `1/1`;
   - [x] include LLVM version, target triple, generic CPU policy, backend pipeline, and partial-link policy through backend ABI v11 in artifact key v3 and function key v8;
   - [x] add focused project-key coverage for resolved `zig cc` driver and Linux `objcopy` candidate identity, including canonical path, size, SHA-256, and `--version` first line;
   - [x] lock ordered extra link inputs/host rpath argv placement, backend `cpu=generic-v1;features=none` identity, and ordered `plugin_import_roots` source-tree hashing with focused Linux unit regressions `1/1` each;
   - [ ] finish full ordered plugin/export/rpath/link flag key publication beyond current bypass/argv/order regressions, complete target-feature matrix, corruption, authorization inputs/tests, and native macOS/Windows validation for the artifact-key boundary.
8. [ ] Continue the combined-worktree gates without turning focused evidence into a full-suite claim:
   - [x] pass a fresh `/opt/zig/zig build -Doptimize=Debug -j1` for the final v11 snapshot;
   - [x] pass incremental CLI `10/10`, `DT_UNKNOWN` and non-cacheable safety `1/1 + 1/1`, split-module emitter `2/2`, local owned-pointer delta `1/1`, and anonymous-name collision `1/1`;
   - [ ] finish the remaining artifact authorization, affected-selection, Referee, and cross-consumer reachability closures;
   - [x] `git diff --check`;
   - [x] focused format check for the related compiler/test files;
   - [ ] obtain a clean full `/opt/zig/zig fmt --check src tests` result; no full-tree format pass is claimed. The stopped full emitter run (`83/119`) and incomplete `llvmc-test` are not passes.
9. [ ] Continue the Phase 0 gaps in dependency order: P0.1 metrics, remaining P0.2 snapshot/source-map/differential/pressure work, remaining P0.3/P0.4/P0.5, remaining P0.6 owner lifecycle/redaction/cross-platform explanation work, P0.7 formal baseline, then P0.8 backend profile.
10. [ ] Continue Phase 1 only behind the Phase 0 gates: P1.1 SAB lazy body decode, finish P1.2 journal, P1.3 result-region merge, and P1.4 weighted physical-core-aware scheduling.
11. [ ] Continue Phase 2 only after integrity/key gates: build a reusable ModuleIndex so each function miss no longer scans the full verified stream or rebuilds the complete declaration table; then design and prove an artifact-contract-preserving direct-object or bitcode-composition path before removing the extra whole-module bitcode emit; finally measure disabled/cold/hit P50/P95/RSS on at least 100 functions.

Status boundary: Phase -1/P0 containment, the focused P0.2 verdict-only checkpoint, the focused incremental-object integrity checkpoint, the focused LLVM P0.5 queue checkpoint, and the first P0.6 artifact-cache JSON/status/why/test-cache explanation layer are landed, but full P0.2, P0.3, P0.5 shared reachability, full P0.6 cache explanation, Phase 0, Phase 1, and Phase 2 are not complete. The current P0.2 cache is process-local, success-only, and restricted to verdict-only `check`; compile/emit and any consumer needing annotations/delta/gas/symbols/signatures/source maps still run Referee. A cold miss remains approximately `O(F·I + F²)`, with per-miss verified-stream scans, a complete declaration table, and a final whole-module bitcode emit. Key v8 is not complete alpha-normalization, and the tested `DT_UNKNOWN` symlink rejection is not TOCTOU-hard path authorization. Linux requires PATH-resolved `objcopy`; macOS/Windows localization remains natively unverified. P0.6 still lacks richer cross-process owner lifecycle telemetry, full redaction review, and cross-platform coverage; the current `first_difference` is field-level validation detail for existing entries plus source-free `key.digest` or more specific `key.<field>` when an absent requested key has a same-prefix old candidate, the current store-event fields record latest coarse `published`/`failed` result, fixed pipeline stage, owner miss reason, per-key event/history result counts, and Linux writer pid/start-ticks after validating event `version`/kind/key-prefix headers, the current `selection_changed` evidence covers cold filtered compile-only and cold JSON list queries that intentionally avoid publishing full test artifacts, the current ordinary test-cache metrics evidence is limited to successful cold/warm `sa test --json` after the runner exits, the current affected metrics evidence is limited to successful cold/warm `sa test --affected --json` after the runner exits, the current list metrics evidence is limited to JSON cold/disabled/hit paths, the current `bypassed_untrusted` focused evidence covers build-exe CGU artifact paths, a test-hooked non-cacheable dynamic-dependency build-exe path, and Linux test plugin link inputs, the current `evicted` evidence is limited to entries removed by `sa cache clean`, the current `lock_owner_failed` evidence is limited to deterministic project-cache lock-path failure, and the current `expired` reason is only a status/why age-policy explanation for otherwise reusable entries. Failure injection, crash recovery, cross-process/cross-platform behavior, remaining link flags/target-policy/authorization keying, ModuleIndex, formal performance measurements, failed-publication repair, remaining corruption cases, owned VerifySnapshot/source-map rebind, full field differential, and cross-consumer gates remain. The current Referee improvement is a partial P1.2 checkpoint, not a complete mutation journal.

2026-07-17 P0.6 update: source-free per-key store-event history count is now focused verified through `last_store_event_count`, including failed `copy_output` count `1` followed by successful waiter publish count `2`. Source-free history result counts are now focused verified through `last_store_published_event_count` and `last_store_failed_event_count`, covering `0/1` after the failed owner and `1/1` after waiter publish. Linux writer process-start identity is now focused verified through `last_store_writer_start_ticks`. Owner acquisition context is now focused verified through `last_store_owner_miss_reason`, covering the first failed owner and later waiter publish both inheriting `absent`. Store-event marker/history reads now validate source-free `version`/kind/key-prefix headers before exposing telemetry, and mismatched events are ignored. Remaining owner telemetry work now means broader cross-process owner lifecycle, redaction review, and cross-platform evidence beyond latest result/stage/owner miss reason/history result counts/key-input provenance/Linux pid/start-ticks/event count.

## Active objective: macOS / Windows portability

Reference: `docs/macos_windows_portability_evaluation_cn.md`.

1. [x] Establish `sa_std` source/artifact ABI baselines and cross-target build gates.
2. [x] Land Windows network, environment, and generic-thread runtime foundations.
3. [x] Harden POSIX pthread ownership and concurrency without regressing Linux.
4. [x] Finish the Windows Console batch recorded in `8021c3d`:
   - resolve SA stdio/dynamic file resources to native Windows handles;
   - detect real consoles while treating redirected files/pipes as non-terminals;
   - own raw-session handles through `DuplicateHandle`, enforce one active session, and retain failed restores for retry;
   - distinguish input from output consoles and return visible dimensions with a `CONOUT$` fallback;
   - leave epoll explicitly unsupported with deterministic output clearing;
   - align SA terminal constants and failed-output contracts across Windows/POSIX.
5. [x] Validate the Console batch on the Linux host:
   - Linux runtime `73/73`, terminal C integration `2/2`, and focused SA constants `1/1`;
   - Windows x86_64/aarch64 type checks and x86_64 PE test link;
   - source ABI `9/9`, artifact ABI `8/8`, and focused lifecycle/error-contract review;
   - retain the known environment-only `sa-std-runtime` result of `13/14` (IPv6 multicast join exit `23`).
6. [x] Close and validate the release/installer artifact contract on Linux:
   - use canonical repository URLs and `linux`/`macos`/`windows` artifact naming;
   - build an isolated compiler/static-runtime payload and verify archive roots, required std files, sidecars, and aggregate checksums;
   - aggregate and publish all tar/zip/sidecar artifacts without enabling unverified non-Linux release matrix entries;
   - pass `release-contract` `4/4`, real Linux archive/install smoke, installed Hello World build/run, and checksum failure paths.
7. [x] Define the native Windows x86_64 CI gate and reviewed compiler/runtime contract subset:
   - [x] add `.github/workflows/windows-native.yml` on `windows-2025` with pinned Zig/LLVM, isolated static/shared runtime prefixes, portable tests, filtered Windows runtime tests, ABI checks, and worktree cleanliness checks;
   - [x] add staged PowerShell smoke for version/help/check, native Hello, wasm32 magic, isolated HOME/TEMP/plugin state, offline package resolution, and deterministic missing-package failure;
   - [x] verify the current static contract `4/4`, YAML/actionlint, and Linux `portable-host-typecheck` `11/11`;
   - [x] repair the audited LLVM provisioning gap: the official win64 installer supplies `LLVM-C.lib`/`LLVM-C.dll` but not the required development headers, so the gate now pins the matching source archive, configures X86 generated headers, merges `llvm-c` plus `llvm/Config`, and syntax-checks the complete shim before building;
   - [x] verify the repaired header/link path from Linux with the merged source/generated headers and official import library: cross `sa-cli` build `5/5`, producing a Windows x86_64 PE32+ executable;
   - [x] wire the shared `test-runtime-basic` into the Windows workflow, add the installed-static-runtime `ws2_32` host link dependency, and cross-link an x86_64 PE basic-contract executable plus DLL fixture from Linux;
   - [ ] execute the workflow on a Windows runner, including installed `sa_std.lib` consumption and the shared basic gate; until then this is a gate definition, not native Windows runtime evidence or an L2 claim.
8. [x] Audit the macOS Phase 2/MVP starting boundary before implementation:
   - record that the starting repository had no native macOS workflow or native-run evidence;
   - identify aggregate build gates that pull in Linux-only io_uring;
   - inventory missing aarch64 cross coverage, Darwin terminal tests, `.dylib` plugin smoke, daemon smoke, and Linux-specific socket contracts.
9. [x] Define the first macOS L0/L1 gate batch (`f03fc02`):
   - add dual-architecture macOS host/package, runtime, Darwin pthread shim, and ABI checks through `portable-host-typecheck`, `portable-runtime-typecheck`, and `portability-check`;
   - keep the native workflow on reviewed portable gates and outside Linux-only aggregate/runtime steps;
   - define x86_64/arm64 jobs with Zig 0.14.1, SHA-pinned LLVM 14 bottles, isolated compiler/static-runtime builds, architecture/linkage validation, and staged compiler/package smoke;
   - validate on Linux with contract `3/3`, YAML/actionlint and shell parsing, `portability-check` `30/30`, `test-portable` `9/9` steps and `49/49` tests, plus x86_64/aarch64 static-runtime builds `4/4` each with matching Mach-O archive members.
10. [ ] Execute both macOS workflow jobs and record native L0/L1 plus basic/Darwin/Darwin-socket/Darwin-PTY runtime results; until then the workflow and Linux cross evidence are neither macOS native evidence nor an L2 claim.
11. [x] Define and wire the shared basic and Darwin runtime gates:
   - link the production static runtime and a target-built dynamic-library fixture rather than a mock runtime;
   - cover handle ownership, fs/dir/metadata, env/time, threads, exact small-output process capture, and dynamic loading in `test-runtime-basic`, with raw timestamps and waitpid-path behavior in `test-runtime-darwin`;
   - wire macOS to both gates and Windows to the shared basic gate, with explicit native OS/architecture guards that fail rather than skip;
   - validate Linux native basic `6/6`, `portability-check` `40/40`, `test-portable` `9/9` steps and `49/49` tests, contracts `3/3` and `4/4`, dual-architecture Mach-O links, and an x86_64 PE/DLL cross link without claiming native macOS/Windows execution.
12. [x] Harden POSIX process capture: drain both pipes while the child runs to avoid wait-before-drain deadlock, and loop beyond the current one-shot 8192-byte read per stream.
13. [x] Platformize Darwin sockets and define the native socket gate:
   - route initialized-length socket option calls through the target system ABI and use Darwin/Linux constants for TTL/hop limit, multicast, keepalive, `SO.TYPE`, and `SO.ACCEPTCONN`;
   - fix Darwin pathname UDS NUL/length handling and make abstract UDS, PASSCRED/peer credentials, QUICKACK/DEFER_ACCEPT, epoll, pidfd, and netx deterministically unsupported with cleared outputs;
   - link the production runtime into a DNS/TCP/UDP/IPv6-hop/pathname-UDS/socket-option C contract and wire its native run step into both macOS jobs;
   - pass Linux socket `7/7`, runtime `74/74`, portable runtime `19/19`, portability `42/42`, portable suite `9/9` steps and `49/49` tests, ABI `11/11`, macOS CI contract `3/3`, and x86_64/aarch64 Darwin warnings-as-errors compile plus production Mach-O link `4/4` each;
   - retain the evidence boundary: no macOS native run exists yet, and multicast join/leave remains cross-compile/system-header evidence only.
14. [x] Implement Darwin winsize and native PTY raw-mode tests:
   - route `sa_term_winsize` through target POSIX `ioctl(TIOCGWINSZ)` instead of Linux-only constants, preserving `UNSUPPORTED` plus cleared output for non-terminal descriptors;
   - clear `ECHONL` in raw mode and mirror the raw/winsize/error contract in the Linux terminal C integration test;
   - add `tests/runtime_darwin_pty_contract.c`, `runtime-darwin-pty-link`, and `test-runtime-darwin-pty`, with the native run step guarded to fail on non-macOS/non-native targets;
   - cover a real PTY, `TIOCSWINSZ`, runtime fd wrapping, terminal detection, raw flag clearing including `ECHONL`, `VMIN/VTIME`, restore via leave and close, duplicate leave invalidation, and pipe winsize `UNSUPPORTED` output clearing;
   - validate Linux executable gates `sa-term-runtime` `2/2`, `test-portable` `9/9` and `49/49`, ABI `11/11`, static macOS CI contract `3/3`, `portable-runtime-typecheck` `21/21`, `portability-check` `44/44`, format/diff checks, and x86_64/aarch64 Darwin warnings-as-errors compile plus production Mach-O PTY links `4/4` each;
   - retain the evidence boundary: no macOS native PTY run exists yet, and `sa-std-runtime` is still the known Linux-container `13/14` IPv6 multicast environment failure.
15. [ ] Finish native `.dll`/`.dylib` plugin, daemon Unix-socket, PowerShell/macOS installer, archive, and release smoke.
   - [x] define native macOS/Windows archive roundtrip inside the existing compiler smoke scripts: stage release payload, package it as `sa-macos-<arch>.tar.gz` / `sa-windows-<arch>.zip`, extract it to a clean directory, and run all compiler/package smoke checks from the extracted `bin/` + `std/` tree;
   - [x] add a Linux-verifiable native `daemon-smoke` gate that starts a real Unix-socket daemon, verifies ping metrics, forwards `sa version` through `SA_DAEMON_SOCKET`, shuts down, and checks socket cleanup; wire it into macOS native CI for future runner evidence;
   - [x] lock the GitHub release matrix so macOS/Windows archive rows remain disabled until matching native compiler/runtime/installer/archive evidence exists;
   - [x] emit and upload native smoke evidence JSON artifacts from macOS/Windows workflows after the archive, installer, wasm, package, and installed-check smokes pass;
   - [x] validate native smoke evidence JSON contents in macOS/Windows workflows before artifact upload;
   - [x] bind native smoke evidence JSON to the GitHub SHA, run id, and run attempt before artifact upload;
   - [ ] execute those archive smokes on native macOS/Windows runners and add remote installer/release-download evidence before claiming installer/archive support.

Evidence rule: the active host is Linux. Cross type-check/link/ABI and static workflow/PowerShell checks are recorded as such and never promoted to native Windows/macOS runtime success or L2 support. The current process contract proves exact small-output capture only, not arbitrary-size capture; the Darwin socket and PTY contracts have not run natively, and socket multicast join/leave paths remain uncovered.

Commit rule: commit each coherent, verified portability batch promptly. Do not stage unrelated concurrent worktree changes.


## Active std parity batch (2026-07-13 n)

Completed supportable defaults/aliases/macros:
- OptionPairU64 layout constants in option.sal (24-byte pair struct: tag + value1 + value2).
- OPTION_ZIP_U64 macro in option.sa: zips two Options into OptionPairU64; both-some -> Some(pair), otherwise None.
- OPTION_UNZIP_TO_U64 macro: unzip OptionPairU64 back to separate Option layouts.
- CHAR_MIN = 0 constant in char.sal (Rust char::MIN).
- CMP_ORDERING_MIN = -1, CMP_ORDERING_MAX = 1 in cmp.sal (Rust 1.84+ stabilized Ordering::MIN/MAX).
- Test file std_option_zip_macro_surface.sa (panic IDs 10471/10472).

Panic IDs next free: 10473+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 m)

Completed supportable defaults/aliases/macros:
- Infallible_SIZE = 0 and Infallible_ALIGN = 1 in convert.sal (Rust convert::Infallible never-error type).
- Complete CONVERT_* min/max coverage in convert.sal: CONVERT_U64_MIN/MAX, CONVERT_I64_MIN, CONVERT_USIZE_MIN/MAX, CONVERT_ISIZE_MIN/MAX, CONVERT_BOOL_MIN/MAX (9 new constants).
- 35 NonZero* associated constants in num.sal mirroring Rust 1.70+ stabilized constants: NONZERO_U8/U16/U32/U64/usize_MIN/MAX/ONE (15 unsigned: MIN=1, MAX=wrapping_max, ONE=1) and NONZERO_I8/I16/I32/I64/isize_MIN/MAX (10 signed: MIN=wrapping_min, MAX=wrapping_max).
- Test file std_convert_nonzero_macro_surface.sa (panic IDs 10469/10470) verifying all new constants against NUM_*_MAX/MIN constants.

Panic IDs next free: 10471+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 e)

Completed supportable defaults/aliases/macros:
- CMP_ORDERING_DEFAULT_VALUE (.sal constant alias for Ordering::default = Equal)
- STRING_BUF_LIT1 / STRING_BUF_LIT2 / STRING_BUF_LIT3 (multi-slice StringBuf constructors)

Critical fix: discovered SA_STD_DIR=/home/vscode/.sa/std was pointing to a stale install (Jul 11 09:13). All previous-session edits to sa_std/ were invisible during testing because the test runner resolved imports from the stale system copy, not the project copy. Re-synced project sa_std/ to /home/vscode/.sa/std/ via rsync. This unblocks all [MACRO] and #def additions to existing std files.

Panic IDs next free: 10461+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-13 f)

## Active std parity batch (2026-07-13 g)

Completed supportable defaults/aliases/macros:
- SLICE_DEFAULT (empty slice: ptr=0, len=0) in slice.sa
- OPTION_DEFAULT (alias for OPTION_NEW_NONE) in option.sa
- RANGE_U64_DEFAULT / RANGE_FULL_DEFAULT / BOUND_U64_DEFAULT / RANGE_FROM_U64_DEFAULT / RANGE_TO_U64_DEFAULT / RANGE_TO_INCLUSIVE_U64_DEFAULT in ops.sa

Panic IDs next free: 10464+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

Completed supportable defaults/aliases/macros:
- FROM_* / TRY_FROM_* / SAT_FROM_* Rust naming aliases in convert.sa (56 macros wrapping existing CONVERT_*)
- NUM_*_DEFAULT = 0 constants in num.sal (10 integer type defaults)

Panic IDs next free: 10463+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Active std parity batch (2026-07-13)

Completed supportable defaults/aliases/macros:
- CMP_ORDERING_DEFAULT_VALUE (.sal constant alias for Ordering::default = Equal)
- STRING_BUF_LIT1 / STRING_BUF_LIT2 / STRING_BUF_LIT3 (multi-slice StringBuf constructors)

Next supportable scan targets remain thin aliases/wrappers only; blocked: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
Panic IDs next free: 10455+.

## Active std parity batch (2026-07-13 b)

Completed supportable defaults/aliases:
- NET_IPV4_DEFAULT / NET_IPV6_DEFAULT
- NET_SOCKET_ADDR_V4_DEFAULT / NET_SOCKET_ADDR_V6_DEFAULT
- PROCESS_EXIT_STATUS_DEFAULT
- REFCELL_U64_DEFAULT
- FS_PERMISSIONS_DEFAULT / FS_FILE_TIMES_DEFAULT

Panic IDs next free: 10459+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 c)

Completed supportable defaults/aliases:
- RC_DEFAULT_U64 / WEAK_DEFAULT
- ARC_DEFAULT_U64 / ARC_WEAK_DEFAULT

Panic IDs next free: 10461+.

## Active std parity batch (2026-07-13 d)

Completed supportable defaults/aliases:
- DEFAULT_HASHER_DEFAULT
- BUILD_HASHER_DEFAULT_DEFAULT

Panic IDs next free: 10461+.

## Objective

Active follow-up: reduce the slowest full-test runtime owners and improve full-test log quality using the logged step runner, without returning to blind aggregate test runs. The previous compiler-performance slice reduced SCI `sa test --filter` / `--list` latency for large SAB artifacts generated by downstream `sla_ecs` to the target range and is installed. Optimization now proceeds step-by-step from the measured slowest owners, with logging good enough to identify long-running or stuck objects.

## Active Scope
1. Active full-test runtime optimization:
   - Checkpoint before this follow-up: `690d57f Add logged test step diagnostics`.
   - First completed feature: plugin installer failure preflight.
   - `src/plugins.zig` now runs interface-file checks, asset-file checks, and installed extern-symbol conflict checks before `buildPluginProject()`, so failure-only install tests no longer pay for temporary dynamic-library builds that cannot affect the failure result.
   - Artifact-dependent checks remain after build/copy: dynamic symbol smoke and artifact static policy.
   - `plugin-host-smoke` remains an isolated install-flow test. It uses `std.testing.tmpDir()` and sets `SA_PLUGINS_HOME` to the test-local `state` directory; ordinary unit testing does not install real user plugins.
   - Focused verification with the logged runner passed: `tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/plugin-opt-20260709T070747Z plugin-host-smoke`, `12/12 tests passed`, `elapsed=170.743s`.
   - Measured improvement against the previous full logged baseline: `209.569s -> 170.743s`, saving `38.826s` (`18.5%`) on the observed `plugin-host-smoke` step. Internal timing showed the duplicate extern failure paths as the clearest wins.
   - Second completed feature: `sa-std-runtime` reuses the build-system `sa_std` static archive instead of rebuilding `src/runtime/sa_std.zig` inside each C demo test.
   - `build.zig` wires the runtime integration test step to the archive refresh, and `tests/sa_std_runtime.zig` copies the refreshed archive into each temp test directory before linking each demo.
   - Focused verification passed: `tools/test_steps_timed.sh --timeout 420 --log-dir logs/test_steps/sa-std-runtime-opt-20260709T073000Z sa-std-runtime`, `14/14 tests passed`, `elapsed=33.532s`.
   - Measured improvement against the previous full logged baseline: `145.815s -> 33.532s`, saving `112.283s` (`77.0%`) on the observed `sa-std-runtime` step.
   - Overall progress estimate after this feature: `35%` of the full-test runtime optimization follow-up. Current observed cumulative savings are about `151.109s` across `plugin-host-smoke` and `sa-std-runtime`.
   - Third completed feature: full-test log quality improvement.
   - `tools/test_steps_timed.sh` now prints per-step heartbeats through `--heartbeat` / `SA_TEST_STEP_HEARTBEAT`, defaulting to 30s. Heartbeat lines include `index=current/total`, elapsed time, current log byte count, timestamp, and log path.
   - Failed and timed-out steps now print the last `--fail-tail-lines` / `SA_TEST_STEP_FAIL_TAIL_LINES` log lines into the console and `summary.log`, defaulting to 80 lines.
   - Each run now persists `results.tsv` and `environment.txt` next to `summary.log`, so post-run analysis does not require scraping mixed console output.
   - Focused verification completed without full-suite execution: syntax/list checks pass; `pkg-core-test` pass generated structured logs; an intentional invalid step preserved exit status `1` and printed a log tail; `sa-std-runtime` emitted a heartbeat at 5s and passed.
   - Overall progress estimate after this logging feature: `45%` of the full-test runtime/logging optimization follow-up.
   - Fourth completed feature: `unit-framework` file-level logging.
   - `tests/unit_framework/runner.zig` now prints `START` and `END` for each SA unit file it launches, including mode (`in-process` or `process`), jobs, elapsed time, stdout bytes, and stderr bytes.
   - Queued process-mode files include `index=current/total`, so parallel worker progress is visible inside the step log.
   - Per-file error exits now use `END status=error` rather than `[unit-framework] FAIL`, so the intentional queued-worker negative test does not make a passing `unit-framework` step look failed in broad log searches.
   - Focused verification completed with the single `unit-framework` build step only: `tools/test_steps_timed.sh --heartbeat 10 --timeout 240 --log-dir logs/test_steps/unit-framework-log2-20260709T082000Z unit-framework` passed, and grep confirmed file-level START/END lines plus no `[unit-framework] FAIL` marker.
   - Overall progress estimate after this feature: `55%` of the full-test runtime/logging optimization follow-up.
   - Follow-up consistency pass: `feature_suite.sa`, `assert_diag.sa`, and `mock_io_test.sa` now use the same START/END/error shape as the macro surface files.
   - Verification with `logs/test_steps/unit-framework-log3-20260709T083000Z` passed, and grep confirmed the old elapsed-only lines are gone.
   - Overall progress estimate after this consistency pass: `60%` of the full-test runtime/logging optimization follow-up.
   - Fifth completed feature: `wasm-matrix` slowest-demo and slowest-phase summary output.
   - `tests/wasm_matrix_smoke.zig` now records per-demo totals and per-phase timings for `build-exe`, `native-run`, `build-wasm`, and `wasm-run`, then prints aggregate phase totals plus top-10 slowest demo and phase rankings at the end of the step.
   - Focused verification passed with the single `wasm-matrix` step only: `tools/test_steps_timed.sh --heartbeat 15 --timeout 420 --log-dir logs/test_steps/wasm-matrix-summary2-20260709T084000Z wasm-matrix`, `1/1 tests passed`, `elapsed=146.982s`.
   - Observed matrix body summary: `demos=110 total_demo_ms=103970 build_exe_ms=93156 native_run_ms=502 build_wasm_ms=1711 wasm_run_ms=8188`. The slowest phases are all `build-exe`, so the next runtime work should target repeated SA native build cost rather than wasm execution.
   - Overall progress estimate after this feature: `65%` of the full-test runtime/logging optimization follow-up.
   - Sixth completed feature: default `wasm-matrix` now follows a WASM-fast validation shape and shares the repo cache root.
   - CLI compile options now accept `--project-root <dir>` / `--project-root=<dir>`, allowing direct compile callers to force package resolution and `.sa_cache` placement to a stable project root.
   - `wasm-matrix` now passes the repo root as `--project-root` and runs native `build-exe` only for a representative sanity subset by default. Full native equivalence remains opt-in with `SA_WASM_MATRIX_NATIVE_ALL=1`.
   - Focused verification only: cold shared-cache `wasm-matrix` passed in `212.385s`; hot shared-cache `wasm-matrix` passed in `59.623s`.
   - Measured improvement against the previous logged `wasm-matrix` run: `146.982s -> 59.623s`, saving `87.359s` (`59.4%`) on the hot-cache default path. The hot run summary was `demos=110 native_checked=6 total_demo_ms=57359 build_exe_ms=6255 build_wasm_ms=43033 wasm_run_ms=7754`.
   - Release metadata for this batch is prepared: `build.zig.zon` version `0.0.4`, plus `CHANGELOG.md` covering the `0.0.3 -> 0.0.4` changes.
   - Overall progress estimate after this feature: `75%` of the full-test runtime/logging optimization follow-up.
   - Next candidates after release merge: remaining `plugin-host-smoke`, `unit-framework`, and `std-smoke` runtime. Do not run a full suite until the next large milestone.

1. Active test logging/timeout diagnostics:
   - `tools/test_steps_timed.sh` is the new diagnostic entry point for the `zig build test` dependency set.
   - The runner executes named build steps one by one, with per-step START/PASS/FAIL/TIMEOUT logs, exact command, UTC timestamp, elapsed time, slowest-step ranking, and final summary.
   - Full output is persisted to log files so long runs can be inspected after terminal or CI truncation. Default path is `logs/test_steps/<utc timestamp>`; callers can override with `--log-dir` or `SA_TEST_STEP_LOG_DIR`. Each step gets a numbered log file and the run gets `summary.log`.
   - Default step list mirrors `build.zig` `test` dependencies through named steps. `std-smoke` covers the two std smoke artifacts, and `whitepaper-lint` covers the whitepaper smoke artifact without repeating std smoke through the aggregate `smoke` step.
   - Implemented controls: `--list`, `--continue`, `--timeout SEC`, `--jobs N`, `--log-dir DIR`, `--summary MODE`, plus `SA_TEST_STEP_TIMEOUT`, `SA_TEST_STEP_LOG_DIR`, `SA_ZIG_JOBS` / `ZIG_BUILD_JOBS`, and `SA_ZIG_SUMMARY`.
   - Focused verification completed:
     - `bash -n tools/test_steps_timed.sh`
     - `tools/test_steps_timed.sh --list`
     - `tools/test_steps_timed.sh --timeout 180 lib-root-smoke pkg-core-test`
     - `tools/test_steps_timed.sh --timeout 180 --log-dir /tmp/sci-test-steps-logs pkg-core-test`
     - invalid-step failure-path check with `--log-dir /tmp/sci-test-steps-fail-logs`
   - Observed focused run: `lib-root-smoke` passed in `50.989s`, `pkg-core-test` passed in `1.419s`, and the runner printed a slowest-step summary.
   - Persisted-log checks generated `summary.log` and per-step logs on both success and failure, while preserving the failing command exit status.
   - Heavy-step internal logging added:
     - `plugin-host-smoke` prints START/END and elapsed time around each Zig test body; focused validation passed in `230.858s` and exposed the slowest plugin tests at about `30s` each.
     - `wasm-matrix` prints START/END and elapsed time for every demo plus `build-exe`, `native-run`, `build-wasm`, and `wasm-run`; focused validation passed in `149.039s` and now identifies the exact demo/phase if the matrix hangs.
   - Milestone full validation used the logged runner instead of a blind aggregate command:
     - `tools/test_steps_timed.sh --continue --timeout 420 --log-dir logs/test_steps/full-20260709T060333Z`
     - Result: `passed=22 failed=0 timeout=0 total=22 elapsed=789.076s`.
     - Slowest steps: `plugin-host-smoke` `209.569s`, `sa-std-runtime` `145.815s`, `wasm-matrix` `121.868s`, `unit-framework` `57.407s`, `std-smoke` `57.155s`.
   - Active logging milestone is complete. Optional next optimization work is helper-level plugin timing and `sa-std-runtime` internals if those remain top blockers.

1. Active performance issue:
   - `docs/issue14_test_filter_large_sab_performance.md` records the current large-SAB performance blocker.
   - Small real SAB guard is already close to target: `parallel_table_erased-ab6b0062c772adb.sab` focused `--compile-only --filter ... --jobs 1 --no-incremental` is about `elapsed=1.28 maxrss=70252`, and focused `--list` is about `elapsed=0.33 maxrss=57136`.
   - Large real SAB is not close to target: `world_table_erased-5d5e95eb4646a2ce.sab` focused `--list --filter "table erased high k query combinations preserve entity order"` is about `elapsed=8.87 maxrss=385224`; focused `--compile-only --filter ... --jobs 1 --no-incremental` is about `elapsed=30.61 maxrss=465592`, and a cached/no explicit no-incremental repeat remained about `elapsed=33.51 maxrss=464808`.
   - Root cause in `src/cli.zig`: `executeTest()` calls `compileSource()` before `test_meta.collect()` and filter/list handling. For `.sab`, `compileSource()` decodes and verifies the whole module in `loadSabFlat()` + `referee.verifyWithOptions()`; therefore even `sa test large.sab --list --filter ...` does full decode/verify before listing one selected test.
   - Completed milestone: `.sab --list --filter` now uses metadata-only test signature decoding; selected `.sab --compile-only --filter` collects tests before compile, prunes to selected-test reachability, uses borrowed SAB symbol pools, trusts the selected SAB as preverified for compile-only, and skips the throwaway executable link after LLVM bitcode emit succeeds.
   - ReleaseFast focused gates with local `./zig-out/bin/sa`: large `world_table_erased --list --filter` `elapsed=0.05`; large `world_table_erased --compile-only --filter --no-incremental` `elapsed=0.82`; small `parallel_table_erased --compile-only --filter --no-incremental` `elapsed=0.17`.
   - Installed `/home/vscode/.sa/bin/sa` gates after `tools/install.sh --no-shell`: large list `elapsed=0.07`; large compile-only `elapsed=1.00`; small compile-only `elapsed=0.26`.
   - Full `timeout 600s zig build test --summary all` did not pass; blockers are recorded in `docs/issue15_full_test_suite_failures_20260709.md`.
   - Focused blockers fixed: `splitn aliases` source gate passes, and full `plugin-host-smoke` passes `12/12`.
   - 600s and 1200s full-suite reruns timed out without a final summary; single build-step reruns isolated `sa-std-unit`, then per-test output isolated `sa_net_uring.test.listen accept recv_ticket and outbound commands work end to end`.
   - `sa-std-unit` timeout fixed and now passes `63/63`.
   - All `zig build test` dependency steps have been rerun individually with explicit logs and passed.
   - Install completed with `tools/install.sh --no-shell`.
   - Installed focused performance gates pass: large SAB compile-only `0.75s`, large SAB list `0.04s`, small SAB compile-only `0.13s`.
   - Remaining follow-up is non-blocking future work: lazy/partial SAB instruction decode for selected run-mode and any future filtered linked-artifact cache semantics.

1. Completed in the current batch:
   - `str` / `String` / `STRING_BUF` char-pattern search aliases: `*_CONTAINS_CHAR`, `*_TRY_FIND_CHAR`/`*_FIND_CHAR`, `*_TRY_RFIND_CHAR`/`*_RFIND_CHAR`, and `*_COUNT_CHAR` families that lower a Unicode scalar `char` (`u64` codepoint) to its UTF-8 byte subsequence and reuse the existing slice-needle scan helpers, plus a new non-overlapping slice-needle `STR_COUNT`/`STRING_COUNT` count helper that the `*_COUNT_CHAR` macros delegate to.
   - `str`/`String`/`STRING_BUF` replace and limited-replace (replacen) helpers: `STRING_BUF_REPLACE_N`, `STR_REPLACE`/`STRING_REPLACE`, `STR_REPLACEN`/`STRING_REPLACEN`, the matching `*_CHAR` variants (`STRING_BUF_REPLACE_CHAR`/`STRING_BUF_REPLACE_N_CHAR`/`STR_REPLACE_CHAR`/`STRING_REPLACE_CHAR`/`STR_REPLACEN_CHAR`/`STRING_REPLACEN_CHAR`), and `STRING_BUF_REMOVE_MATCHES_CHAR`, all lowering a `char` needle via `STR_ENCODE_CHAR_SLICE` and reusing the existing slice-needle replace scan.
   - `str`/`String`/`STRING_BUF` slice-needle split and matches view helpers: `STR_SPLIT_NEEDLE_COUNT`/`STRING_SPLIT_NEEDLE_COUNT`/`STRING_BUF_SPLIT_NEEDLE_COUNT`, `STR_SPLIT_NEEDLE_TERM_COUNT`/`STRING_SPLIT_NEEDLE_TERM_COUNT`/`STRING_BUF_SPLIT_NEEDLE_TERM_COUNT`, `STR_MATCHES_NEEDLE_COUNT`/`STRING_MATCHES_NEEDLE_COUNT`/`STRING_BUF_MATCHES_NEEDLE_COUNT`, `STR_TRY_SPLIT_NEEDLE_AT`/`STRING_TRY_SPLIT_NEEDLE_AT`/`STRING_BUF_TRY_SPLIT_NEEDLE_AT`/`STR_SPLIT_NEEDLE_AT`/`STRING_SPLIT_NEEDLE_AT`/`STRING_BUF_SPLIT_NEEDLE_AT`, and `STR_TRY_MATCHES_NEEDLE_AT`/`STRING_TRY_MATCHES_NEEDLE_AT`/`STRING_BUF_TRY_MATCHES_NEEDLE_AT`/`STR_MATCHES_NEEDLE_AT`/`STRING_MATCHES_NEEDLE_AT`/`STRING_BUF_MATCHES_NEEDLE_AT`, all reusing the `STR_COUNT` non-overlapping scan and returning caller-indexed `Slice` views with `(ok, Slice)` shapes rather than Rust lazy iterator adapters.
   - `str`/`String`/`STRING_BUF` reverse slice-needle split and matches view helpers: `STR_RSPLIT_NEEDLE_COUNT`/`STRING_RSPLIT_NEEDLE_COUNT`/`STRING_BUF_RSPLIT_NEEDLE_COUNT`, `STR_RMATCHES_NEEDLE_COUNT`/`STRING_RMATCHES_NEEDLE_COUNT`/`STRING_BUF_RMATCHES_NEEDLE_COUNT`, `STR_TRY_RSPLIT_NEEDLE_AT`/`STRING_TRY_RSPLIT_NEEDLE_AT`/`STRING_BUF_TRY_RSPLIT_NEEDLE_AT`/`STR_RSPLIT_NEEDLE_AT`/`STRING_RSPLIT_NEEDLE_AT`/`STRING_BUF_RSPLIT_NEEDLE_AT`, and `STR_TRY_RMATCHES_NEEDLE_AT`/`STRING_TRY_RMATCHES_NEEDLE_AT`/`STRING_BUF_TRY_RMATCHES_NEEDLE_AT`/`STR_RMATCHES_NEEDLE_AT`/`STRING_RMATCHES_NEEDLE_AT`/`STRING_BUF_RMATCHES_NEEDLE_AT`, computing the corresponding forward caller index (`count - 1 - reverse_index`) and delegating to the existing forward `*_TRY_SPLIT_NEEDLE_AT` / `*_TRY_MATCHES_NEEDLE_AT` helpers with `(ok, Slice)` shapes rather than Rust lazy `RSplit` / `RMatches` iterator adapters.

1. Completed in the current batch:
   - `sa_std/os/fd` raw/owned fd facade.
   - `sa_std/fs` Unix/Linux metadata-ext fields.
   - `sa_std/thread` `current_id` / `yield_now`.
   - `sa_std/process` Unix raw wait-status / `ExitStatusExt` parsing.
   - `std::os::unix::fs::FileExt`: `read_at` / `write_at` and exact/all convenience macros.
   - `std::os::unix::fs::OpenOptionsExt`: `mode` / `custom_flags`.
   - `std::os::unix::fs::PermissionsExt`: `mode` / `set_mode` / `from_mode`.
   - `std::os::unix::fs::FileTypeExt`: `is_block_device` / `is_char_device` / `is_fifo` / `is_socket`.
   - `std::os::unix::fs::DirBuilderExt`: `mode` for single-level and recursive directory creation.
   - `std::os::unix::fs::DirEntryExt`: `ino`, backed by a real Linux `getdents64` directory-entry handle model.
   - `std::os::unix::fs::DirEntryExt2::file_name_ref`: named file-name reference facade over existing directory-entry name pointer/length storage.
   - `std::os::unix::fs::mkfifo`: named FIFO creation macro surface over existing Linux `sa_fs_mkfifo` runtime.
   - `std::os::unix::fs::{chown,lchown,fchown}`: Linux ownership helpers with explicit uid/gid presence flags and Rust raw sentinel macros.
   - `std::os::unix::fs::{symlink,chown,lchown,fchown}`: Rust-named Unix alias macros over existing symlink/ownership helpers.
   - `std::os::linux::fs::MetadataExt`: Rust-named `st_*` field surface for Linux stat parity.
   - `std::os::unix::process::parent_id`.
   - `std::os::unix::process::ChildExt::send_signal`.
   - `std::os::unix::net::UnixStream::pair`.
   - `std::os::unix::net::{UnixListener,UnixStream}` local/peer address queries with dedicated Unix socket address resources.
   - `std::os::unix::net::UnixStream::peer_cred` Linux subset: `SO_PEERCRED` peer pid/uid/gid scalar facade.
   - `std::os::unix::net::UnixStream::peek`: named macro surface over existing stream peek runtime with non-consuming read verification.
   - `std::os::unix::net::UnixStream::shutdown`: named macro surface over existing stream shutdown runtime with peer EOF verification.
   - `std::os::unix::net::{UnixStream,UnixListener}` option named surfaces: stream timeout/nonblocking/take_error and listener nonblocking/take_error aliases over existing fd-based runtime.
   - `std::os::unix::net::{UnixStream,UnixListener}::try_clone`: fd-dup clone facades preserving stream/listener resource kinds and independent close lifetimes.
   - `std::os::unix::net::{UnixStream,UnixListener}` raw-fd trait surface: stream/listener `as_raw_fd`, `into_raw_fd`, and `from_raw_fd` with `from_raw_fd` restoring the correct Unix stream/listener resource kind.
   - `std::os::unix::net::{UnixStream,UnixListener}` owned-fd trait aliases: stream/listener `into_owned_fd` and `from_owned_fd` style macro surfaces over existing raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::fd` / `std::os::unix::io` TCP stream/listener raw-fd trait surface: `TcpStream` / `TcpListener` `as_raw_fd`, `into_raw_fd`, and `from_raw_fd`, with `from_raw_fd` restoring the correct TCP stream/listener resource kind.
   - `std::os::fd::OwnedFd` TCP stream/listener conversion aliases: `TcpStream` / `TcpListener` `into_owned_fd` and `from_owned_fd` style macro surfaces over TCP raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::fd` / `std::os::unix::io` UDP socket raw-fd trait surface: `UdpSocket` `as_raw_fd`, `into_raw_fd`, and `from_raw_fd`, with `from_raw_fd` restoring the existing UDP socket resource kind.
   - `std::os::fd::OwnedFd` UDP socket conversion aliases: `UdpSocket` `into_owned_fd` and `from_owned_fd` style macro surfaces over UDP raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::fd` / `std::os::unix::io` stdio borrowed raw-fd trait surface: `Stdin` / `Stdout` / `Stderr` borrowed `as_raw_fd` style macros over fixed SA stdio handles.
   - `std::os::fd` / `std::os::unix::io` `std::fs::File` raw/owned fd trait surface: File `as_raw_fd`, `into_raw_fd`, `from_raw_fd`, `into_owned_fd`, and `from_owned_fd`, with `from_raw_fd` restoring the existing File resource kind.
   - `std::os::fd::OwnedFd` Rust-named raw-fd and clone aliases over the existing fd facade: `as_raw_fd`, `into_raw_fd`, `from_raw_fd`, and `try_clone` style macros.
   - `std::os::fd::{RawFd,BorrowedFd}` Rust-named facades: RawFd reflexive raw-fd traits and BorrowedFd borrow/as/try_clone_to_owned over raw fd duplication.
   - `StringBuf` / `Vec` Rust API parity audit: current facades are not full Rust API coverage; completed the supportable raw-parts subset with `VEC_INTO_RAW_PARTS`, `VEC_FROM_RAW_PARTS`, `STRING_BUF_INTO_RAW_PARTS`, and `STRING_BUF_FROM_RAW_PARTS`.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable `Vec::push_mut` / `Vec::insert_mut` style mut-return macros and `String` replace-first/replace-last style macros.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable `Vec::from_fn` style indexed generation macros and `String::remove_matches` style slice-pattern removal macro.
   - `Vec` Rust API parity continuation: completed supportable `Vec::as_non_null`, `Vec::into_parts`, and `Vec::from_parts` style NonNull parts macros over the existing `NonNull` facade.
   - `StringBuf` Rust API parity continuation: completed supportable `String::extend_from_within` style range-copy macros with UTF-8 boundary checks and self-copy reallocation protection.
   - `StringBuf` Rust API parity continuation: completed supportable `String::remove(idx)` style byte-index char removal macros plus `STR_TRY_CHAR_AT_BYTE` / `STRING_TRY_CHAR_AT_BYTE` UTF-8 helper surfaces.
   - `StringBuf` Rust API parity continuation: completed supportable `String::pop()` style char-aware tail-pop macros, distinct from existing byte-pop helpers.
   - `StringBuf` Rust API parity continuation: completed supportable `String::drain(range)` style eager range-drain macros returning a `StringBuf` with the removed range.
   - `StringBuf` Rust API parity correction: `STRING_BUF_TRY_SPLIT_OFF` / `STRING_BUF_SPLIT_OFF` now enforce Rust `String::split_off` UTF-8 char-boundary semantics before delegating to the Vec split path.
   - `StringBuf` Rust API parity continuation: completed supportable `String::retain` style codepoint-predicate retain macros that rebuild the buffer from retained UTF-8 scalar slices.
   - `StringBuf` Rust API parity correction: `STRING_BUF_TRY_PUSH_CHAR` / `STRING_BUF_TRY_INSERT_CHAR` now encode full Unicode scalar values, and `STRING_BUF_TRY_INSERT_STR` now enforces UTF-8 char-boundary insertion points.
   - `Vec` Rust API parity continuation: completed supportable `Vec::retain_mut` U64/function-pointer shape, where predicates receive mutable element pointers and retained values are compacted after possible mutation.
   - `Vec` Rust API parity continuation: completed supportable `Vec::peek_mut` U64/general element-size mutable-pointer shape, returning a pointer to the last element or null on empty Vec.
   - `Vec` Rust API parity continuation: completed supportable `Vec::from_elem` repeated-value constructor shape, constructing a Vec by pushing the same supplied value for the requested length.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable `String::leak` / `Vec::leak` shape, consuming the owning wrapper and returning a mutable slice/string view without freeing the allocation.
   - `Vec` Rust API parity continuation: completed supportable `Vec::spare_capacity_mut` / `Vec::split_at_spare_mut` shape, and corrected `VEC_SET_LEN` to directly set length for Rust `set_len` parity.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8` byte-slice constructor shape with full UTF-8 validation.
   - `StringBuf` Rust API parity continuation: completed supportable `String::into_chars` eager codepoint Vec shape, consuming the source StringBuf.
   - `StringBuf` Rust API parity continuation: completed supportable strict `String::from_utf16` U16-slice constructor shape with surrogate-pair decoding.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf16_lossy` U16-slice constructor shape with U+FFFD replacement for invalid surrogate units.
   - `StringBuf` Rust API parity continuation: completed supportable strict `String::from_utf16le` / `String::from_utf16be` endian byte-slice constructor shape.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf16le_lossy` / `String::from_utf16be_lossy` endian byte-slice constructor shape with U+FFFD replacement for invalid surrogate units and odd trailing bytes.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8(Vec<u8>)` owned-Vec constructor shape with success zero-copy move and failure error-Vec preservation.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8_lossy` owned-StringBuf constructor shape with U+FFFD replacement for invalid UTF-8 sequences.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8_lossy_owned` owned-Vec constructor shape with valid zero-copy move and invalid lossy rebuild.
   - `StringBuf` Rust API parity correction: lossy UTF-8 decoding now consumes a contiguous invalid UTF-8 sequence as one replacement unit, matching Rust's `utf8_chunks` behavior for cases like `F0 90 80 W`.
   - `StringBuf` Rust API parity continuation: completed supportable `String::from_utf8_unchecked(Vec<u8>)` owned-Vec zero-copy constructor and `String::as_mut_str` mutable str-view naming surface.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable clone/conversion surfaces: `STRING_BUF_FROM_STR`, `STRING_BUF_CLONE`, `STRING_BUF_CLONE_FROM`, `VEC_FROM_SLICE`, `VEC_CLONE`, and `VEC_CLONE_FROM`, plus U64 Vec convenience wrappers.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable default/conversion/operator naming surfaces: `STRING_BUF_DEFAULT`, StringBuf AsRef/AsMut aliases, `STRING_BUF_FROM_CHAR`, `STRING_BUF_ADD_STR`, `STRING_BUF_ADD_ASSIGN_STR`, `VEC_DEFAULT`, `VEC_FROM_STR_BYTES`, `VEC_U8_FROM_STR`, and `VEC_FROM_STRING_BUF`.
   - `StringBuf` / `Vec` Rust API parity continuation: completed supportable reference conversion aliases: `STRING_BUF_FROM_MUT_STR`, `STRING_BUF_FROM_STRING_REF`, `STRING_BUF_TRY_FROM_VEC_U8`, and `STRING_BUF_TRY_FROM_BYTES_VEC`, with installed-state coverage for `VEC_FROM_STRING_BUF` ownership transfer.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are not complete Rust API coverage; completed supportable Vec reference/array conversion aliases `VEC_FROM_MUT_SLICE`, `VEC_FROM_ARRAY`, and `VEC_FROM_MUT_ARRAY` plus U64 wrappers.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec `AsRef<[T]>` / `AsMut<[T]>` / Deref-to-slice aliases and String `fmt::Write` `write_str` / `write_char` aliases.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec `AsRef<Vec<T>>` borrowed metadata pointer alias plus String Deref/DerefMut-to-str and checked Index/IndexMut range aliases.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable String `Extend<str/char/String>` style aliases and Vec `Extend<T>` / `Extend<&T>` style aliases over existing append/push/slice-copy paths.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `PartialEq<String, str, &str>` / `ne` style aliases over existing `STR_EQ` comparison.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable String/str lexicographic comparison aliases for `PartialOrd` / `Ord` style use cases over bytewise UTF-8 ordering.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable local `Hash` delegation aliases where StringBuf hashes through its str view and Vec U64 hashes through its slice view.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager U64 codepoint-slice `FromIterator<char>` / `Extend<char>` style aliases with whole-slice Unicode scalar validation before mutation.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager pointer-slice `FromIterator<&char>` / `Extend<&char>` style aliases with whole-slice Unicode scalar validation before mutation.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager byte-slice and pointer-slice `FromIterator<core::ascii::Char>` / `Extend<core::ascii::Char>` style aliases with whole-slice ASCII validation before mutation.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager slice-shaped `FromIterator<T>` / `Extend<T>` aliases over existing slice-copy construction and extension paths.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable U64 slice-delegated equality / inequality aliases for Vec-vs-slice, slice-vs-Vec, and Vec-vs-Vec comparisons.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable U64 slice-delegated lexicographic comparison aliases for Vec-vs-slice, slice-vs-Vec, and Vec-vs-Vec comparison plus bool ordering predicates.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager Slice-of-Slice `FromIterator<&str>` / `Extend<&str>` style aliases over existing string append paths.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed eager Slice-of-StringBuf metadata `FromIterator<String>` / `Extend<String>` style aliases that append each owned source string then drop its moved buffer in place, without claiming a lazy iterator object model.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable eager repeat aliases for `str::repeat` and slice/Vec repeat-style use cases, materializing new owned buffers by copying the source view `count` times.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable eager owned-copy conversion aliases for `ToOwned` / `ToString` / `to_vec` style use cases, reusing existing StringBuf/Vec clone and from-slice paths without claiming Cow/Box/trait-object coverage.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed concrete primitive `to_string` aliases for char/bool/u64/i64 over existing StringBuf construction and SA formatter paths, without claiming generic `Display` / `ToString` trait-object coverage.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed Vec `AsMut<Vec<T>>`-style metadata pointer alias `VEC_AS_MUT_VEC_PTR`, matching the existing local `AsRef<Vec<T>>` pointer shape without claiming full Rust whole-object mutable borrow semantics.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed concrete smaller-integer and pointer-sized `to_string` aliases for u8/u16/u32/usize and i8/i16/i32/isize via existing u64/i64 formatter-backed StringBuf paths, without claiming `u128`/`i128`, float formatting, or generic `Display` coverage.
   - `StringBuf` / `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed concrete String `FromStr` / parse-style aliases over existing `StringBuf` from-str copy construction, returning `ok=1` without claiming generic `FromStr` or error type modeling.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed `String::as_bytes_mut`-style unsafe mutable byte-slice aliases `STRING_BUF_AS_MUT_BYTES` and `STRING_BUF_AS_MUT_REF_BYTES` over the existing Vec mutable-slice metadata facade, without claiming UTF-8 mutation invariant enforcement, `String::as_mut_vec`, or Rust borrow-checker semantics.
   - `str` / string slice Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed `str::as_bytes_mut`-style unsafe mutable byte-slice aliases `STR_AS_MUT_BYTES` and `STRING_AS_MUT_BYTES` over the existing Slice metadata view, without claiming UTF-8 mutation invariant enforcement, ownership provenance, or Rust borrow-checker semantics.
   - `StringBuf` / `Vec` / slice Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed `as_ptr_range` / `as_mut_ptr_range`-style start/end pointer output aliases for Slice, str/string, StringBuf, and Vec/U64 paths, without claiming Rust `Range<*const T>` / `Range<*mut T>` object layout or unsafe pointer-range reconstruction APIs.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable chunk/window access naming aliases `VEC_CHUNK_AT_U64`, `VEC_RCHUNK_AT_U64`, `VEC_RCHUNK_MUT_AT_U64`, `VEC_CHUNK_EXACT_AT_U64`, `VEC_CHUNK_EXACT_MUT_AT_U64`, `VEC_RCHUNK_EXACT_AT_U64`, `VEC_RCHUNK_EXACT_MUT_AT_U64`, and `VEC_WINDOW_AT_U64` over existing checked slice-view forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice copy aliases `VEC_COPY_FROM_SLICE_U64`, `VEC_CLONE_FROM_SLICE_U64`, and `VEC_COPY_WITHIN_U64` over existing mutable slice U64 copy machinery.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice select-nth aliases `VEC_SELECT_NTH_UNSTABLE_U64`, `VEC_SELECT_NTH_UNSTABLE_BY_U64`, and `VEC_SELECT_NTH_UNSTABLE_BY_KEY_U64` over existing mutable slice U64 partitioning machinery.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice binary search alias `VEC_BINARY_SEARCH_U64` over the existing U64 `(ok, index)` search result shape.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable split/strip naming aliases `STR_STRIP_PREFIX`, `STRING_STRIP_PREFIX`, `STR_STRIP_SUFFIX`, `STRING_STRIP_SUFFIX`, `STR_SPLIT_AT`, `STRING_SPLIT_AT`, `STR_SPLIT_AT_CHECKED`, `STRING_SPLIT_AT_CHECKED`, `STR_SPLIT_ONCE`, `STRING_SPLIT_ONCE`, `STR_RSPLIT_ONCE`, and `STRING_RSPLIT_ONCE` over existing checked `(ok, slice...)` forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable find/rfind naming aliases `STR_FIND`, `STRING_FIND`, `STR_RFIND`, and `STRING_RFIND` over existing checked `(ok, index)` forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable byte find/rfind naming aliases `STR_FIND_BYTE`, `STRING_FIND_BYTE`, `STR_RFIND_BYTE`, and `STRING_RFIND_BYTE` over existing checked `(ok, index)` byte-search forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable Vec deref-to-slice strip prefix/suffix aliases `VEC_STRIP_PREFIX_U64` and `VEC_STRIP_SUFFIX_U64` over existing checked U64 slice-view forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked range-view aliases `STR_GET_RANGE`, `STRING_GET_RANGE`, `STR_GET_PREFIX`, `STRING_GET_PREFIX`, `STR_GET_SUFFIX`, `STRING_GET_SUFFIX`, `STR_GET_RANGE_TO`, `STRING_GET_RANGE_TO`, `STR_GET_RANGE_FROM`, `STRING_GET_RANGE_FROM`, `STR_GET_RANGE_BETWEEN`, and `STRING_GET_RANGE_BETWEEN` over existing UTF-8 boundary checked `(ok, slice)` forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable split-off aliases `VEC_SPLIT_OFF` and `VEC_SPLIT_OFF_U64` over existing checked `(ok, Vec)` split-off forms.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked UTF-8 constructor aliases `STRING_BUF_FROM_UTF8`, `STRING_BUF_FROM_UTF8_VEC`, `STRING_BUF_FROM_VEC_U8`, and `STRING_BUF_FROM_BYTES_VEC` over existing strict UTF-8 `(ok, StringBuf[, err_vec])` forms.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked UTF-16 constructor aliases `STRING_BUF_FROM_UTF16_U16`, `STRING_BUF_FROM_UTF16LE`, and `STRING_BUF_FROM_UTF16BE` over existing strict UTF-16 `(ok, StringBuf)` forms.
   - `StringBuf` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed closer Rust method-name UTF-16 aliases `STRING_BUF_FROM_UTF16` and `STRING_BUF_FROM_UTF16_LOSSY` over existing U16 slice strict/lossy decode forms.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable checked get_mut aliases `VEC_TRY_GET_MUT_PTR_U64` and `VEC_GET_MUT_U64` over the existing mutable-slice checked pointer helper.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable indexed split/line aliases `STR_SPLIT_BYTE_AT`, `STRING_SPLIT_BYTE_AT`, `STR_LINE_AT`, and `STRING_LINE_AT` over existing checked `(ok, slice)` view forms.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `trim_start_matches` / `trim_end_matches` / `trim_matches` aliases for `STR`, `STRING`, and `STRING_BUF`, returning borrowed `Slice` views and treating empty needles as no-op.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `split_ascii_whitespace` count and caller-indexed token-view aliases for `STR`, `STRING`, and `STRING_BUF`, returning borrowed `Slice` views and collapsing ASCII whitespace without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `split_terminator` / `rsplit_terminator` count aliases and forward caller-indexed `split_terminator` aliases for `STR`, `STRING`, and `STRING_BUF`, returning borrowed `Slice` views without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `splitn` / `rsplitn` count aliases for `STR`, `STRING`, and `STRING_BUF`, plus `split_count == 0` and empty-needle consistency fixes for the existing caller-indexed limited split aliases.
   - `Vec` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `push_within_capacity` checked aliases and mut-return pointer aliases, preserving local `(ok, ptr)` shapes without claiming Rust `Result<&mut T,T>` object layout or borrow-checker semantics.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `match_indices` / `rmatch_indices` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, returning local `(ok, byte_index, Slice)` results without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable slice-needle `split_inclusive` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, returning delimiter-retaining borrowed `Slice` views without claiming Rust's lazy iterator object model.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable char-pattern `split_inclusive` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, lowering valid Unicode scalar values to UTF-8 needle slices.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable char-pattern `starts_with` / `ends_with` / `strip_prefix` / `strip_suffix` aliases for `STR`, `STRING`, and `STRING_BUF`, lowering valid Unicode scalar values to UTF-8 needle slices and preserving local false / `(ok, Slice)` miss shapes.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable char-pattern `trim_start_matches` / `trim_end_matches` / `trim_matches` aliases for `STR`, `STRING`, and `STRING_BUF`, lowering valid Unicode scalar values to UTF-8 needle slices and treating invalid scalars as no-op borrowed views.
   - `StringBuf` / `str` Rust API parity re-audit: confirmed current SA facades are still not complete Rust API coverage; completed supportable `char_indices` count and caller-indexed aliases for `STR`, `STRING`, and `STRING_BUF`, returning local `(ok, byte_index, codepoint)` values without claiming Rust's lazy iterator object model.
   - `std::os::unix::xdg` supportable env-dir surface: `data_home_dir`, `config_home_dir`, `state_home_dir`, `cache_home_dir`, `data_dirs`, and `config_dirs` style macros with XDG empty-value fallback semantics.
   - `std::os::unix::fs::chroot`: current-process Linux `chroot(2)` facade with `FS_CHROOT` / `FS_UNIX_CHROOT` macro surfaces and safe `/`-only validation accepting root success or non-root permission denial.
   - `std::os::unix::net::UnixListener::accept`: address-returning `NET_UNIX_ACCEPT_ADDR` surface using the existing Unix addr handle model.
   - `std::os::unix::net::UnixListener::incoming`: named incoming iterator macro surface over the existing listener-backed incoming layout.
   - `std::os::unix::net::SocketAddr::{from_pathname,as_pathname}`: pathname Unix addr constructor and Rust-named pathname access aliases.
   - `std::os::linux::net::SocketAddrExt::as_abstract_name`: Rust-named abstract-name access aliases over existing Unix abstract addr accessors.
   - `std::os::unix::net::UnixDatagram` basic subset: unbound/pair, try_clone, raw/owned fd roundtrip, local/peer addr, passcred, timeout/nonblocking/take_error, send/recv/peek, shutdown, and close surfaces over AF_UNIX/SOCK_DGRAM handles.
   - `std::os::unix::net::UnixDatagram` pathname/abstract address paths: `bind`, `bind_addr`, `connect`, `connect_addr`, `send_to`, `send_to_addr`, `recv_from`, and `peek_from` over pathname and Unix addr handle resources.
   - `std::os::unix::ffi::{OsStrExt,OsStringExt}` Unix byte facade: `OsStr::from_bytes` / `as_bytes` slice views and `OsString::from_vec` / `into_vec` owned `Vec<u8>` move aliases.
   - `std::os::unix::thread::JoinHandleExt`: real raw `pthread_t` facade for `as_pthread_t` / `into_pthread_t`, with raw pthread join cleanup support for ownership-transfer validation.
   - `std::os::unix::process::CommandExt` supportable spawn-config subset: `arg0`, `process_group`, and `setsid` across capture/inherit/stream process modes.
   - `std::os::linux::process` / pidfd-adjacent process-group signaling subset: `PROCESS_SEND_PROCESS_GROUP_SIGNAL` with effective PGID tracking.
   - `std::os::linux::process` pidfd subset: create-pidfd spawn path, process `pidfd` / `into_pidfd` extraction, and pidfd kill/send_signal/wait/try_wait raw and code helpers.
   - `std::os::linux::process::PidFd` raw-fd trait aliases: `PIDFD_AS_RAW_FD`, `PIDFD_INTO_RAW_FD`, `PIDFD_FROM_RAW_FD`, and `PIDFD_CLOSE_RAW_FD` over the existing owned-fd facade.
   - `std::os::linux::process::PidFd` owned-fd trait aliases: `PIDFD_INTO_OWNED_FD` and `PIDFD_FROM_OWNED_FD` over the existing pidfd raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::unix::process::{ChildStdout,ChildStderr}` raw-fd trait aliases over the existing owned-fd facade.
   - `std::os::unix::process::{ChildStdout,ChildStderr}` owned-fd trait aliases over the existing child pipe raw-fd and `sa_std/os/fd` owned-fd helpers.
   - `std::os::unix::process::CommandExt::{uid,gid}`: child-side `setgid` / `setuid` spawn config plus current `PROCESS_USER_ID` / `PROCESS_GROUP_ID` facade.
   - `std::os::unix::process::CommandExt::groups`: child-side `setgroups` spawn config across capture/inherit/stream modes.
   - `std::os::unix::process::CommandExt::chroot`: child-side `chroot` spawn config across capture/inherit/stream modes.
   - `std::os::unix::process::CommandExt::exec`: in-place `execvpeZ` replacement with cwd/arg0/process_group/setsid/uid/gid/groups/chroot config.
   - `std::os::linux::net::SocketAddrExt` abstract Unix socket address subset: `from_abstract_name` / `as_abstract_name`-style address handles plus listen/connect by Unix addr handle.
   - `std::os::net::linux_ext::TcpStreamExt`: Linux `TCP_QUICKACK` and `TCP_DEFER_ACCEPT` set/get socket option surface.
   - `std::os::net::linux_ext::UnixSocketExt` UnixStream subset: Linux `SO_PASSCRED` set/get socket option surface.
   - `std::os::net::linux_ext::UnixSocketExt` Unix stream/datagram subset: Linux `SO_MARK` set socket option surface for AF_UNIX stream and datagram handles.
   - `std::os::unix::process::ChildExt::kill_process_group`: Linux process-group `SIGKILL` convenience facade over the existing effective-PGID signal path.
2. Next candidate scope:
   - Continue String/Vec audit only for supportable gaps that can be expressed as SA macro/runtime surfaces and verified without misrepresenting Rust object models.
   - Re-audit remaining Linux-only `std` facade gaps against `/home/vscode/projects/rust/library/std/src/os/`.
   - Prioritize surfaces that can be expressed clearly as SA macros/runtime and verified with focused macro-surface tests.

## Acceptance

- `zig build unit-framework` passes. Done on 2026-07-05 after fixing the UDS setter compatibility path and a DNS macro-surface test leak.
- `zig build unit-framework --summary all` passes after the `DirEntryExt::ino` batch.
- `zig build unit-framework --summary all` passes after the Linux metadata/process extension batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux fs ownership batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix-domain socket completion batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt spawn-config batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the process-group signal batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the pidfd process batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the PidFd raw-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the PidFd owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Child stdout/stderr raw-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Child stdout/stderr owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt uid/gid batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt groups batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt chroot batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the CommandExt in-place exec batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux abstract Unix socket address batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux TcpStreamExt quickack/deferaccept batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux UnixSocketExt passcred batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux ChildExt kill_process_group batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix DirEntryExt2 file_name_ref batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix fs mkfifo named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Linux UnixStream peer_cred batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixStream peek named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixStream shutdown named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket option named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket try_clone batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket raw-fd trait batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixListener accept_addr batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixListener incoming named surface batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix SocketAddr pathname batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix SocketAddr as_abstract_name alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix fs symlink/chown alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the TCP stream/listener raw-fd trait batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the TCP stream/listener owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UDP socket raw-fd trait batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UDP socket owned-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the stdio raw-fd alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the File raw/owned fd facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the OwnedFd named facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the RawFd/BorrowedFd named facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec raw-parts facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec mut-return and replace facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf remove_matches and Vec from_fn facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec NonNull parts facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf extend_from_within facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf remove(idx) facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf pop() facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf drain(range) facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf split_off char-boundary parity batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf retain facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf Unicode push/insert char batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec retain_mut facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec peek_mut facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec from_elem facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec leak facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec spare capacity facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8 facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf into_chars facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf16 facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf16_lossy facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf UTF-16 endian byte-slice facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf UTF-16 endian lossy byte-slice facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8 Vec facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8_lossy facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8_lossy owned-Vec facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf from_utf8_lossy invalid-sequence correction batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf unchecked owned-Vec and as_mut_str facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix XDG env facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec clone and from-slice/from-str facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec default and conversion alias facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec reference conversion alias facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix fs chroot facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixDatagram basic facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the UnixDatagram pathname/abstract address facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec naming alias audit batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix ffi OsStr/OsString facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix thread JoinHandleExt pthread facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Unix socket set_mark facade batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec Extend trait alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf char iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec eager iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf str iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf char reference iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf ASCII char iterator alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf equality alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf lexicographic comparison alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec hash delegation alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec U64 equality alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec U64 lexicographic comparison alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf owned String iterator alias batch and indirect-call signature provenance fix (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec repeat alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the StringBuf/Vec owned conversion alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String primitive to_string alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec AsMut Vec pointer alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Integer primitive to_string alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String FromStr parse alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String mutable bytes alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the str mutable bytes alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String/Vec pointer range alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec chunk/window access alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec copy alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec select_nth alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the Vec binary_search alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- Full test suites are skipped for the String/str split/strip alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String/str find alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String/str byte find alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the Vec strip alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String/str get-range alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the Vec split_off alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String UTF-8 constructor alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String UTF-16 constructor alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String exact UTF-16 alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the Vec checked get_mut alias batch by user instruction; only newly added focused source and installed-state tests were run.
- Full test suites are skipped for the String split/line indexed alias batch by user instruction; only newly added focused source and installed-state tests were run.
- `zig build unit-framework --summary all` passes after the String trim_matches needle alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String split_ascii_whitespace alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String split_terminator needle alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- `zig build unit-framework --summary all` passes after the String splitn count alias batch (`6/6 steps succeeded; 5/5 tests passed`).
- Full `zig build unit-framework --summary all` was attempted after the Vec push_within_capacity alias batch, stayed silent/idle for more than 6 minutes, and was interrupted; focused source, full Vec macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String match_indices needle alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String split_inclusive needle alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String split_inclusive char alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String prefix/suffix char alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String trim-matches char alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- Full test suites are skipped for the String char_indices alias batch; focused source, full String macro-surface, install sync, and installed-state focused tests passed.
- New macro-surface tests pass:
  - `std_os_fd_macro_surface.sa`
  - `std_fs_metadata_ext_macro_surface.sa`
  - `std_fs_unix_ext_macro_surface.sa`
  - `std_fs_dir_entry_ext_macro_surface.sa`
  - `std_thread_macro_surface.sa`
- Updated directory-entry macro-surface test passes with DirEntryExt2 file_name_ref assertions:
  - `std_fs_dir_entry_ext_macro_surface.sa`
- Updated Unix fs macro-surface test passes with `FS_UNIX_MKFIFO` assertions:
  - `std_fs_unix_ext_macro_surface.sa`
- Updated Unix fs macro-surface test passes with `FS_UNIX_SYMLINK` and `FS_UNIX_*CHOWN*` assertions:
  - `std_fs_unix_ext_macro_surface.sa`
- Updated process macro-surface test passes with raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt spawn-config assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with process-group signal raw wait-status assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with pidfd handle/wait/kill assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with PidFd raw-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with PidFd owned-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with ChildStdout/ChildStderr raw-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with ChildStdout/ChildStderr owned-fd alias assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt uid/gid assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt groups assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt chroot assertions:
  - `std_process_macro_surface.sa`
- Updated process macro-surface test passes with CommandExt in-place exec assertions:
  - `std_process_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with pair and address assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux `SO_PEERCRED` peer pid/uid/gid assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_STREAM_PEEK` non-consuming read assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_STREAM_SHUTDOWN` peer EOF assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream timeout/nonblocking/take_error and UnixListener nonblocking/take_error assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream and UnixListener try_clone assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream and UnixListener raw-fd ownership roundtrip assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixStream and UnixListener owned-fd ownership roundtrip assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ACCEPT_ADDR` peer address assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with UnixListener incoming wrapper/next assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ADDR_FROM_PATHNAME` and `NET_UNIX_ADDR_AS_PATHNAME_*` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with `NET_UNIX_ADDR_AS_ABSTRACT_NAME_*` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux abstract address listen/connect assertions:
  - `std_net_unix_macro_surface.sa`
- Updated net macro-surface test passes with Linux `TCP_QUICKACK` / `TCP_DEFER_ACCEPT` assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with TCP stream/listener raw-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with TCP stream/listener owned-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with UDP socket raw-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated net macro-surface test passes with UDP socket owned-fd ownership roundtrip assertions:
  - `std_net_macro_surface.sa`
- Updated io utility macro-surface test passes with stdio handle and borrowed raw-fd assertions:
  - `std_io_utility_macro_surface.sa`
- Updated os fd macro-surface test passes with File raw/owned fd roundtrip and File-only `read_at` assertions:
  - `std_os_fd_macro_surface.sa`
- Updated os fd macro-surface test passes with OwnedFd named raw-fd and clone assertions:
  - `std_os_fd_macro_surface.sa`
- Updated os fd macro-surface test passes with RawFd reflexive and BorrowedFd clone-to-owned assertions:
  - `std_os_fd_macro_surface.sa`
- Updated String/Vec macro-surface tests pass with raw-parts ownership roundtrip assertions:
  - `std_vec_macro_surface.sa`
  - `std_string_macro_surface.sa`
- Updated String/Vec macro-surface tests pass with Vec mut-return and String replace-first/last assertions:
  - `std_vec_macro_surface.sa`
  - `std_string_macro_surface.sa`
- Updated String/Vec macro-surface tests pass with Vec from_fn and String remove_matches assertions:
  - `std_vec_macro_surface.sa`
  - `std_string_macro_surface.sa`
- Updated Vec macro-surface tests pass with NonNull parts assertions:
  - `std_vec_macro_surface.sa`
- Updated String macro-surface tests pass with extend_from_within assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with byte-index UTF-8 decode and remove-char-at assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with char-aware pop assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with eager range-drain assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with split_off UTF-8 char-boundary assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with codepoint-predicate retain assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with Unicode char push/insert and insert boundary assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with trim_start_matches/trim_end_matches/trim_matches slice-needle assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with match_indices/rmatch_indices slice-needle byte-index assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with split_inclusive slice-needle delimiter-retaining assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with split_inclusive char-pattern delimiter-retaining assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with prefix/suffix char-pattern assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with trim_start_matches/trim_end_matches/trim_matches char-pattern assertions:
  - `std_string_macro_surface.sa`
- Updated String macro-surface tests pass with char_indices byte-offset/codepoint assertions:
  - `std_string_macro_surface.sa`
- Updated Vec macro-surface tests pass with retain_mut mutation and compaction assertions:
  - `std_vec_macro_surface.sa`
- Updated Vec macro-surface tests pass with peek_mut empty/null and mutable-last-element assertions:
  - `std_vec_macro_surface.sa`
- Updated Vec macro-surface tests pass with push_within_capacity checked and mut-return assertions:
  - `std_vec_macro_surface.sa`
- Updated Unix-domain socket macro-surface test passes with Linux `SO_PASSCRED` assertions:
  - `std_net_unix_macro_surface.sa`
- Updated process macro-surface test passes with ChildExt kill_process_group assertions:
  - `std_process_macro_surface.sa`
- Installed-state smoke passes for `std_fs_metadata_ext_macro_surface.sa`, `std_fs_unix_ext_macro_surface.sa`, and `std_process_macro_surface.sa` using `/home/vscode/.sa/std`.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt spawn-config install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the process-group signal install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the pidfd process install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the PidFd raw-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the PidFd owned-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the Child stdout/stderr raw-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the Child stdout/stderr owned-fd alias install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt uid/gid install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt groups install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt chroot install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the CommandExt in-place exec install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the abstract Unix socket address install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the TcpStreamExt quickack/deferaccept install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixSocketExt passcred install sync.
- Installed-state smoke passes for `std_process_macro_surface.sa` after the ChildExt kill_process_group install sync.
- Installed-state smoke passes for `std_fs_dir_entry_ext_macro_surface.sa` after the DirEntryExt2 file_name_ref install sync.
- Installed-state smoke passes for `std_fs_unix_ext_macro_surface.sa` after the Unix fs mkfifo named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Linux UnixStream peer_cred install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixStream peek named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixStream shutdown named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket option named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket try_clone install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket raw-fd trait install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix socket owned-fd alias install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixListener accept_addr install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the UnixListener incoming named surface install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix SocketAddr pathname install sync.
- Installed-state smoke passes for `std_net_unix_macro_surface.sa` after the Unix SocketAddr as_abstract_name alias install sync.
- Installed-state smoke passes for `std_fs_unix_ext_macro_surface.sa` after the Unix fs symlink/chown alias install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the TCP stream/listener raw-fd trait install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the TCP stream/listener owned-fd alias install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the UDP socket raw-fd trait install sync.
- Installed-state smoke passes for `std_net_macro_surface.sa` after the UDP socket owned-fd alias install sync.
- Installed-state smoke passes for `std_io_utility_macro_surface.sa` after the stdio raw-fd alias install sync.
- Installed-state smoke passes for `std_os_fd_macro_surface.sa` after the File raw/owned fd facade install sync.
- Installed-state smoke passes for `std_os_fd_macro_surface.sa` after the OwnedFd named facade install sync.
- Installed-state smoke passes for `std_os_fd_macro_surface.sa` after the RawFd/BorrowedFd named facade install sync.
- Installed-state focused String trim-matches alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "trim matches aliases"`
- Installed-state focused String split-ascii-whitespace alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split ascii whitespace aliases"`
- Installed-state focused String split-terminator alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split terminator needle aliases"`
- Installed-state focused String splitn count alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "splitn count aliases"`
- Installed-state focused String match-indices alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "match indices needle aliases"`
- Installed-state focused String split-inclusive alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split inclusive needle aliases"`
- Installed-state focused String split-inclusive char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split inclusive char aliases"`
- Installed-state focused String split/matches char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split and matches char aliases"`
- Installed-state focused String match-indices char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "match indices char aliases"`
- Installed-state focused String split-terminator char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split terminator char aliases"`
- Installed-state focused String splitn char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "splitn char aliases"`
- Installed-state focused String split-once char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "split once char aliases"`
- Installed-state focused String prefix/suffix char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "prefix suffix char aliases"`
- Installed-state focused String trim-matches char alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "trim matches char aliases"`
- Installed-state focused String char_indices alias test passes after install sync:
  - `std_string_macro_surface.sa --filter "char indices aliases"`
- Installed-state focused Vec push-within-capacity alias test passes after install sync:
  - `std_vec_macro_surface.sa --filter "push within capacity aliases"`
- `src/runtime/sa_std.h`, `sa_std/*.sai`, `sa_std/*.sa`, and installed `/home/vscode/.sa/std` expose the same ABI after `./tools/install.sh --no-shell`.

## Current Status

- Source/facade/test changes are complete for the str/String/StringBuf slice-needle trim-match batch, the ASCII-whitespace split token-view batch, the char_indices caller-indexed batch, the split-once char-pattern batch, the prefix/suffix char-pattern batch, the trim-matches char-pattern batch, the split-terminator needle alias batch, the split_terminator/rsplit_terminator char-pattern batch, the splitn count/edge-case batch, the splitn/rsplitn char-pattern batch, the Vec push_within_capacity alias batch, the str/String/StringBuf match_indices/rmatch_indices slice-needle batch, the str/String/StringBuf split_inclusive slice-needle batch, the str/String/StringBuf split_inclusive char-pattern batch, the str/String/StringBuf split/matches char-pattern batch, and the str/String/StringBuf match_indices/rmatch_indices char-pattern batch.
- The Vec push_within_capacity batch adds `VEC_TRY_PUSH_WITHIN_CAPACITY`, `VEC_TRY_PUSH_WITHIN_CAPACITY_U64`, `VEC_TRY_PUSH_WITHIN_CAPACITY_MUT`, `VEC_TRY_PUSH_WITHIN_CAPACITY_MUT_U64`, `VEC_PUSH_WITHIN_CAPACITY_MUT`, and `VEC_PUSH_WITHIN_CAPACITY_MUT_U64`.
- The split-ascii-whitespace batch adds `STR_SPLIT_ASCII_WHITESPACE_COUNT`, `STR_TRY_SPLIT_ASCII_WHITESPACE_AT`, `STR_SPLIT_ASCII_WHITESPACE_AT`, and matching `STRING_*` / `STRING_BUF_*` aliases.
- The char_indices batch adds `STR_CHAR_INDICES_COUNT`, `STR_TRY_CHAR_INDICES_AT`, and `STR_CHAR_INDICES_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-once char-pattern batch adds `STR_TRY_SPLIT_ONCE_CHAR`, `STR_SPLIT_ONCE_CHAR`, `STR_TRY_RSPLIT_ONCE_CHAR`, and `STR_RSPLIT_ONCE_CHAR`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The prefix/suffix char-pattern batch adds `STR_STARTS_WITH_CHAR`, `STR_ENDS_WITH_CHAR`, `STR_TRY_STRIP_PREFIX_CHAR`, `STR_STRIP_PREFIX_CHAR`, `STR_TRY_STRIP_SUFFIX_CHAR`, and `STR_STRIP_SUFFIX_CHAR`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The trim-matches char-pattern batch adds `STR_TRIM_START_MATCHES_CHAR`, `STR_TRIM_END_MATCHES_CHAR`, and `STR_TRIM_MATCHES_CHAR`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-terminator batch adds `STR_SPLIT_TERMINATOR_NEEDLE_COUNT`, `STR_RSPLIT_TERMINATOR_NEEDLE_COUNT`, `STR_TRY_SPLIT_TERMINATOR_NEEDLE_AT`, `STR_SPLIT_TERMINATOR_NEEDLE_AT`, and matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-terminator char-pattern batch adds `STR_SPLIT_TERMINATOR_CHAR_COUNT`, `STR_RSPLIT_TERMINATOR_CHAR_COUNT`, `STR_TRY_SPLIT_TERMINATOR_CHAR_AT`, `STR_SPLIT_TERMINATOR_CHAR_AT`, `STR_TRY_RSPLIT_TERMINATOR_CHAR_AT`, and `STR_RSPLIT_TERMINATOR_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The splitn count batch adds `STR_SPLIT_N_NEEDLE_COUNT`, `STR_RSPLIT_N_NEEDLE_COUNT`, and matching `STRING_*` / `STRING_BUF_*` aliases, and makes existing indexed splitn helpers return `ok=0` for `split_count == 0`.
- The splitn char-pattern batch adds `STR_SPLIT_N_CHAR_COUNT`, `STR_RSPLIT_N_CHAR_COUNT`, `STR_TRY_SPLIT_N_CHAR_AT`, `STR_SPLIT_N_CHAR_AT`, `STR_TRY_RSPLIT_N_CHAR_AT`, and `STR_RSPLIT_N_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The match-indices batch adds `STR_MATCH_INDICES_NEEDLE_COUNT`, `STR_RMATCH_INDICES_NEEDLE_COUNT`, `STR_TRY_MATCH_INDICES_NEEDLE_AT`, `STR_MATCH_INDICES_NEEDLE_AT`, `STR_TRY_RMATCH_INDICES_NEEDLE_AT`, and `STR_RMATCH_INDICES_NEEDLE_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-inclusive batch adds `STR_SPLIT_INCLUSIVE_NEEDLE_COUNT`, `STR_TRY_SPLIT_INCLUSIVE_NEEDLE_AT`, and `STR_SPLIT_INCLUSIVE_NEEDLE_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split-inclusive char-pattern batch adds `STR_SPLIT_INCLUSIVE_CHAR_COUNT`, `STR_TRY_SPLIT_INCLUSIVE_CHAR_AT`, and `STR_SPLIT_INCLUSIVE_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The split/matches char-pattern batch adds `STR_SPLIT_CHAR_COUNT`, `STR_RSPLIT_CHAR_COUNT`, `STR_MATCHES_CHAR_COUNT`, `STR_RMATCHES_CHAR_COUNT`, `STR_TRY_SPLIT_CHAR_AT`, `STR_SPLIT_CHAR_AT`, `STR_TRY_RSPLIT_CHAR_AT`, `STR_RSPLIT_CHAR_AT`, `STR_TRY_MATCHES_CHAR_AT`, `STR_MATCHES_CHAR_AT`, `STR_TRY_RMATCHES_CHAR_AT`, and `STR_RMATCHES_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- The match-indices char-pattern batch adds `STR_MATCH_INDICES_CHAR_COUNT`, `STR_RMATCH_INDICES_CHAR_COUNT`, `STR_TRY_MATCH_INDICES_CHAR_AT`, `STR_MATCH_INDICES_CHAR_AT`, `STR_TRY_RMATCH_INDICES_CHAR_AT`, and `STR_RMATCH_INDICES_CHAR_AT`, plus matching `STRING_*` / `STRING_BUF_*` aliases.
- Focused source `zig build unit-framework --summary all` passes after the fs OpenOptions builder custom-flags members batch (`6/6 steps succeeded; 5/5 tests passed`); full-file `unit-framework` validation confirmed the new `@test` block (panic 952) coexists with the twelve pre-existing sibling `@test` blocks and that the latent `panic`-ID duplication (943/944/945 reused across tests) and `#`-comment / additive-operand flattener regressions were corrected.
- Focused source tests for `trim matches aliases`, `trim matches char aliases`, `char indices aliases`, `split ascii whitespace aliases`, `split once char aliases`, `prefix suffix char aliases`, `split terminator needle aliases`, `split terminator char aliases`, `splitn count aliases`, `splitn char aliases`, existing `splitn aliases`, `push within capacity aliases`, `match indices needle aliases`, `split inclusive needle aliases`, `split inclusive char aliases`, `split and matches char aliases`, and `match indices char aliases` pass; the full source `std_string_macro_surface.sa` passes (`72 passed`) and full source `std_vec_macro_surface.sa` passes (`29 passed`); install sync via `./tools/install.sh --no-shell` passes; installed focused splitn-count, splitn-char, split-once-char, prefix/suffix-char, trim-matches-char, char-indices, Vec push-within-capacity, String match-indices, String split-inclusive, String split-inclusive-char, String split/matches-char, String match-indices-char, and String split-terminator-char tests pass. The latest full `zig build unit-framework --summary all` attempt was interrupted after more than 6 minutes of silent/idle runtime, so it is not counted as a passing gate for the Vec batch.
- The match-indices char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle match-index subsets. They return local `(ok, byte_index, Slice)` values, preserve forward byte offsets for reverse enumeration, and return `ok=0`, index `0`, and an empty slice for invalid scalars or missing indexes. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery, lazy iterator object model, or `Option<(usize, &str)>` layout.
- The char_indices aliases scan UTF-8 scalar positions and return local `(ok, byte_index, codepoint)` values for a caller-selected scalar ordinal. Missing ordinals or invalid decoding paths return `ok=0`, byte index `0`, and codepoint `0`. This is a concrete count/caller-indexed subset, not Rust's lazy `CharIndices` iterator object, tuple object layout, borrow-scoped lifetime model, or invalid-UTF-8 impossible-type invariant.
- The split-once char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle split_once/rsplit_once subsets. They return the local `(ok, left, right)` `Slice` shape and return `ok=0` plus empty left/right views for invalid scalars or misses. This is a concrete char-pattern one-shot split subset, not Rust's full `Pattern` machinery, searcher internals, lazy iterator object model, or `Option<(&str, &str)>` layout.
- The prefix/suffix char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle starts/ends/strip prefix/suffix subsets. Invalid scalar values return false for predicates or `ok=0` plus an empty slice for strip helpers, and misses preserve the same local empty-slice shape. This is a concrete char-pattern prefix/suffix subset, not Rust's full `Pattern` machinery, searcher internals, or `Option<&str>` layout.
- The trim-matches char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle trim-match subsets. Valid scalars repeatedly strip exact UTF-8 scalar occurrences at the requested edge, and invalid scalar values return the original borrowed `Slice` view as a no-op. This is a concrete char-pattern trim subset, not Rust's full `Pattern` machinery, closure or slice-of-char patterns, searcher internals, or lazy iterator object model.
- The splitn char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle splitn/rsplitn subsets. They preserve the current local splitn count/indexed behavior: `split_count == 0` returns zero entries or `ok=0`, positive counts cap the returned field count, current `rsplitn` aliases reverse-enumerate the local splitn field set, and invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery, lazy iterator object model, or full right-to-left `rsplitn` semantics.
- The split-terminator char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle split_terminator/rsplit_terminator subsets. They reuse the existing terminator semantics that drop trailing terminator-produced empty fields, and invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery or lazy iterator object model.
- The split/matches char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the existing slice-needle split/matches subsets. Invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery or lazy iterator object model.
- The split-inclusive char-pattern aliases encode a valid `u64` Unicode scalar into its UTF-8 byte sequence and delegate to the split-inclusive needle subset. Invalid scalar values return zero entries or `ok=0` plus an empty slice. This is a concrete char-pattern count/caller-indexed view subset, not Rust's full `Pattern` machinery or lazy iterator object model.
- The split-inclusive aliases enumerate non-overlapping slice-needle split fields while retaining the matched delimiter at the end of delimiter-terminated fields. Empty haystacks and empty needles return zero entries, trailing delimiters do not produce a final empty entry, and missing indexes return `ok=0` plus an empty slice. This is a concrete count/caller-indexed view subset, not Rust's lazy `SplitInclusive` iterator object, generic `Pattern` machinery, `Option<&str>` layout, or borrow-checker lifetime model.
- The match-indices aliases enumerate non-overlapping slice-needle matches, preserve forward byte offsets for reverse enumeration, and return explicit `(ok, byte_index, Slice)` values. Empty needles and out-of-range caller indexes return `ok=0`, index `0`, and an empty slice. This is a concrete count/caller-indexed view subset, not Rust's lazy `MatchIndices` / `RMatchIndices` iterator object, generic `Pattern` machinery, `Option<(usize, &str)>` layout, or borrow-checker lifetime model.
- The split-ascii-whitespace aliases skip leading/trailing ASCII whitespace, collapse consecutive ASCII whitespace, return borrowed token `Slice` views, and return `ok=0` plus an empty slice for missing indexes. They use the existing `ASCII_IS_WHITESPACE` predicate and do not claim Rust's lazy `SplitAsciiWhitespace` iterator object or borrow-checker lifetime model.
- The split-terminator aliases reuse the existing terminator count semantics, dropping trailing terminator-produced empty fields, returning borrowed `Slice` views for present indexes, and returning `ok=0` plus an empty slice for out-of-range or empty-needle cases.
- The splitn aliases remain a concrete slice-needle subset. Empty needles intentionally follow the existing SA subset rather than Rust's full empty-pattern behavior: index `0` returns the whole haystack for positive split counts and later indexes miss.
- The trim-match aliases repeatedly strip non-empty `&str` needles at the requested edge and return borrowed `Slice` views; empty needles are explicit no-ops. This is a concrete slice-needle subset, not Rust's full `Pattern` trait, char/closure/slice-of-char variants, or lazy iterator/object model.
- The String/Vec audit still does not claim complete Rust API coverage; remaining unsupported areas include allocator-parametric APIs, Box/Cow conversions, lazy iterator object models, const-generic array ownership/extraction shapes, `Vec::into_chunks` / `into_flattened` / `recycle`, Vec whole-object mutable borrow beyond local metadata pointer facades / generic `T: PartialEq/Ord/Hash`, unsafe `String::as_mut_vec` metadata-level aliasing, `u128`/`i128`, float default formatting, Unicode whitespace/full-Pattern trim variants, and full generic trait-object coverage.
- The VecDeque u64 view aliases + extra_capacity batch adds `VEC_DEQUE_GET_U64`, `VEC_DEQUE_FRONT_U64`, `VEC_DEQUE_TRY_FRONT_U64`, `VEC_DEQUE_BACK_U64`, `VEC_DEQUE_TRY_BACK_U64`, and `VEC_DEQUE_EXTRA_CAPACITY`. The `_U64` aliases preserve the existing fallible/value front/back/get ABI contract and only expose explicit `u64`-typed Rust naming; `EXTRA_CAPACITY` returns `capacity - len` as a pure subtraction, does not allocate, and reports zero for a full or empty deque. None of these claim generic element support, scoped Rust `front_mut` / `back_mut` references, the lazy `drain` / `splice` range iterator semantics, or allocator-aware constructors that remain genuinely missing for `VecDeque`.
- The VecDeque resize / resize_with batch adds `VEC_DEQUE_RESIZE`, `VEC_DEQUE_RESIZE_U64`, `VEC_DEQUE_RESIZE_WITH`, and `VEC_DEQUE_RESIZE_WITH_U64`. `new_len <= len` shrinks through the existing `sa_vec_deque_truncate` ABI; `new_len > len` grows by repeatedly calling `sa_vec_deque_push_back` (with a fixed `u64` value for `RESIZE`, or a freshly-provided `() -> u64` generator return for `RESIZE_WITH`) until `len == new_len`, relying on the existing runtime auto-grow path for ring-buffer growth. The macros return an explicit `ok=1` status and, like Rust, do not model allocator-failure semantics; allocator-aware `try_resize*` variants, generic element support, scoped Rust references, and the lazy `splice` / drain-range iterator semantics remain genuinely missing for `VecDeque`.
- The VecDeque try_resize within capacity batch adds `VEC_DEQUE_TRY_RESIZE_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_RESIZE_WITHIN_CAPACITY_U64`, `VEC_DEQUE_RESIZE_WITHIN_CAPACITY`, `VEC_DEQUE_RESIZE_WITHIN_CAPACITY_U64`, `VEC_DEQUE_TRY_RESIZE_WITH_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_RESIZE_WITH_WITHIN_CAPACITY_U64`, `VEC_DEQUE_RESIZE_WITH_WITHIN_CAPACITY`, and `VEC_DEQUE_RESIZE_WITH_WITHIN_CAPACITY_U64`. The `new_len <= len` case shrinks via `sa_vec_deque_truncate`; the `new_len > len` case pre-checks `new_len <= cap`, returning `ok=0` with no mutation on insufficient capacity, and otherwise grows via `sa_vec_deque_push_back` (which can never hit the runtime auto-grow path because capacity was already validated). They do not claim Rust allocator growth, the strict allocator-aware `try_resize*` strict-failure variant, generic element support, scoped Rust references, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- The VecDeque try_extend_from_slice within capacity batch adds `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64`, `VEC_DEQUE_EXTEND_FROM_SLICE_U64`, and `VEC_DEQUE_EXTEND_FROM_SLICE`. Total length is computed via plain `add` and capacity checked via `ule total <= cap`; on insufficient room it returns `ok=0` with no mutation, otherwise it appends each source element via `sa_vec_deque_push_back` (which can never hit the runtime auto-grow path because capacity was already validated). It does not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, allocator-aware `try_extend*` failures, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- The VecDeque try_extend_from_slice_n within capacity batch adds `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` and `VEC_DEQUE_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64`. Total size is `mul src_len count`, then capacity-checked via `ule new_len <= cap`; on success it loops `count` times calling `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64`, which itself reuses `sa_vec_deque_push_back` (which can never hit the runtime auto-grow path because capacity was validated up front). `count=0` / `src_len=0` succeed as no-ops, and insufficient room returns `ok=0` with no mutation. It does not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, allocator-aware `try_extend*` failures, or the lazy `splice` / drain-range iterator semantics that remain genuinely missing for `VecDeque`.
- The VecDeque push_n within capacity batch adds `VEC_DEQUE_TRY_PUSH_BACK_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_PUSH_BACK_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_TRY_PUSH_FRONT_N_WITHIN_CAPACITY_U64`, and `VEC_DEQUE_PUSH_FRONT_N_WITHIN_CAPACITY_U64`. Capacity is checked via `ule new_len <= cap`; insufficient room returns `ok=0` with no mutation, and the grow path loops `count` times calling `sa_vec_deque_push_back` / `sa_vec_deque_push_front`, which can never hit the runtime auto-grow branch because capacity was validated up front (front pushes wrap the head around the ring buffer correctly). `count=0` succeeds as a no-op. It does not claim Rust allocator growth, generic element support, scoped Rust references, or lazy iterator allocator-aware variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert within capacity batch adds `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or no room it returns `ok=0` with no mutation, and the success path delegates to `sa_vec_deque_try_insert`, whose internal `reserve(1)` becomes an integer no-op because the deque already had room. It does not claim Rust allocator growth, generic element support, slice-insert variants, scoped Rust references, or `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert_n within capacity batch adds `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_N_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_N_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or insufficient room it returns `ok=0` with no mutation, and the success path loops `count` times calling `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` at the advancing index `index + i`. `count=0` succeeds as a no-op, and each iteration's inner single-element insert can never run out of room because capacity was validated up front. It does not claim Rust allocator growth, generic element support, slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert_from_slice within capacity batch adds `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_FROM_SLICE_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_FROM_SLICE_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap`; on out-of-bounds index or insufficient room it returns `ok=0` with no mutation, and the success path loops `src_len` times reading element `i` from the src slice and calling `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` at the advancing index `index + i`. An empty slice succeeds as a no-op, and each iteration's inner single-element insert can never run out of room because capacity was validated up front. It does not claim Rust allocator growth, generic element support, repeated-slice-insert variants, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque insert_from_slice_n within capacity batch adds `VEC_DEQUE_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY`, `VEC_DEQUE_TRY_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64`, `VEC_DEQUE_INSERT_FROM_SLICE_N_WITHIN_CAPACITY`, and `VEC_DEQUE_INSERT_FROM_SLICE_N_WITHIN_CAPACITY_U64`. Bounds and capacity are validated up front with `ule index <= len` and `ule new_len <= cap` where `new_len = len + src_len*count`; on out-of-bounds index or insufficient room it returns `ok=0` with no mutation, and the success path loops `count` times inserting a whole copy of the src slice at the advancing index `index + i*src_len` via `VEC_DEQUE_TRY_INSERT_FROM_SLICE_WITHIN_CAPACITY`. `count=0` and `src_len=0` both succeed as no-ops, and each iteration's inner slice insert can never run out of room because the full capacity was validated up front. It does not claim Rust allocator growth, generic element support, scoped Rust references, or allocator-aware `try_insert*` strict-failure variants that remain genuinely missing for `VecDeque`.
- The VecDeque extend_chars u64 aliases batch adds `VEC_DEQUE_TRY_EXTEND_CHARS_U64` and `VEC_DEQUE_EXTEND_CHARS_U64`, thin aliases over the existing non-allocating `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` capacity-checked, no-auto-grow family that treat a `Slice<u64>`'s elements as Unicode scalar-value codepoints. They pre-check `len + src_len <= cap`, return `ok=0` with no mutation on insufficient room, and otherwise loop `src_len` times calling `sa_vec_deque_push_back` with each codepoint. They do not perform Rust `char` validation (codepoints beyond U+10FFFF or surrogate codepoints pass through as `u64`), and do not claim Rust allocator growth, the lazy `extend` iterator, generic element support, scoped Rust references, or allocator-aware `try_extend*` strict-failure variants that remain genuinely missing for `VecDeque`.

## Next Priority

- Continue the highest-priority String/Vec Rust API parity audit with only newly added focused tests per batch.
- Started a parallel `VecDeque` Rust API parity audit.
- The VecDeque audit has now landed the first two batches: the u64 view aliases / `extra_capacity` batch and the `resize` / `resize_with` batch.
- The VecDeque audit has now landed the first three batches:
- The VecDeque audit has now landed the first four batches;
- The VecDeque audit has now landed the first five batches;
- The VecDeque audit has now landed the first six batches;
- The VecDeque audit has now landed the first seven batches;
- The VecDeque audit has now landed the first eleven batches; the latest adds the non-allocating `extend_chars` u64 codepoint aliases. Remaining supportable VecDeque candidates are essentially exhausted within the supportable macro-lowering surface: only a concrete `VEC_DEQUE_SPLICE` / drain-range subset remains, still gated on a ring-buffer aware runtime splice ABI; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds the non-allocating single-element `VEC_DEQUE_TRY_INSERT_WITHIN_CAPACITY` helpers. Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), a `VEC_DEQUE_TRY_INSERT_N_WITHIN_CAPACITY` repeated-value insert lowering, a `VEC_DEQUE_TRY_INSERT_FROM_SLICE_*_WITHIN_CAPACITY` slice-insert lowering, and a `VEC_DEQUE_EXTEND_CHARS_*` lowering; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds repeated `VEC_DEQUE_*_PUSH_N_WITHIN_CAPACITY_U64` helpers for the back and front edges (with ring-wrap ordering verified). Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), an `INSERT_*_WITHIN_CAPACITY` non-reallocating variant, and a `VEC_DEQUE_EXTEND_CHARS_*` lowering; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds the repeated `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_N_WITHIN_CAPACITY_U64` helper. Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), a repeated-replace `with_capacity` lowering, and an `INSERT_*_WITHIN_CAPACITY` non-reallocating variant; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the latest adds a concrete `VecDeque::extend` within-capacity lowering `VEC_DEQUE_TRY_EXTEND_FROM_SLICE_U64` (plus `SKIP_START`/`VEC_DEQUE_EXTEND_FROM_SLICE_U64`/`_FROM_SLICE` aliases). Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), front/back push `WITHIN_CAPACITY` aliases, and an `INSERT_*_WITHIN_CAPACITY` non-reallocating variant; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 the u64 view aliases / `extra_capacity` batch, the `resize` / `resize_with` batch, and the `try_resize` within-capacity batch. Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), front/back push `WITHIN_CAPACITY` aliases, and `VEC_DEQUE_INSERT_FROM_SLICE` / `INSERT_*_WITHIN_CAPACITY` non-reallocating variants; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 Remaining supportable VecDeque candidates include a concrete `VEC_DEQUE_SPLICE` / drain-range subset (still gated on a ring-buffer aware runtime splice ABI), front/back `WITHIN_CAPACITY` push aliases, and `VEC_DEQUE_RESIZE_WITH_RESERVE*_WITHIN_CAPACITY` non-reallocating lowerings; all intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 The first batch landed explicit `u64`-named utilities (`VEC_DEQUE_GET_U64`, `VEC_DEQUE_FRONT_U64`, `VEC_DEQUE_TRY_FRONT_U64`, `VEC_DEQUE_BACK_U64`, `VEC_DEQUE_TRY_BACK_U64`) plus `VEC_DEQUE_EXTRA_CAPACITY`. Remaining supportable VecDeque candidates include `VEC_DEQUE_RESIZE` / `RESIZE_WITH` concrete lowerings, a `VEC_DEQUE_SPLICE` / drain-range concrete subset, and front/back `WITHIN_CAPACITY` push aliases, all of which intentionally avoid Rust lazy iterator/generic/scoped-reference semantics.
 The str/String escape/encode_utf16/utf8_chunks/substr_range/get naming/get_mut/get_mut-range/get_mut-range-to-from batches, StringBuf set_len / try_truncate / push_str_within_capacity / push_byte_within_capacity / push_char_within_capacity / insert_within_capacity / extend_str_within_capacity / extend_string_within_capacity / extend_from_within_capacity / extend_char_within_capacity / extend_byte_within_capacity / extend_chars_within_capacity / extend_ascii_chars_within_capacity / extend_char_refs_within_capacity / extend_ascii_char_refs_within_capacity / replace_range_within_capacity / replace_first_within_capacity / replace_last_within_capacity / replace_first_char_within_capacity / replace_last_char_within_capacity / replace_range_char_within_capacity / replace_first_char / replace_last_char / replace_range_char / remove_matches_within_capacity / remove_matches_char_within_capacity / retain_within_capacity / drain_within_capacity / splice_within_capacity / pop_byte_if / pop_char_if / push_str_n_within_capacity / push_byte_n_within_capacity / push_char_n_within_capacity / extend_from_within_n_within_capacity / insert_str_n_within_capacity / insert_byte_n_within_capacity / insert_char_n_within_capacity helpers, Vec try_set_len / insert_within_capacity / extend_from_slice_within_capacity / append_within_capacity / extend_from_within_capacity / resize_within_capacity / splice_within_capacity / resize_with_within_capacity / extend_from_slice_n_within_capacity / push_n_within_capacity / extend_from_within_n_within_capacity / insert_n_within_capacity / insert_from_slice_within_capacity / insert_from_slice_n_within_capacity, and the Vec/StringBuf capacity-remaining/spare aliases are complete. Natural next candidates are remaining supportable capacity-preserving helpers or other concrete view subsets that can be represented as eager slice/Vec macros without claiming generic Rust trait-object semantics.
- The fs Rust API parity audit has now landed its first DirBuilder batch, adding `FS_DIR_BUILDER_NEW`, `FS_DIR_BUILDER_WITH_RECURSIVE`, `FS_DIR_BUILDER_WITH_MODE`, and `FS_DIR_BUILDER_CREATE`. The builder state is two propagating SSA `u64` values (a `recursive` bool 0/1 and a POSIX `mode`) rather than a heap-allocated builder object; `FS_DIR_BUILDER_NEW` initializes to `recursive=false` and `mode=0o755` (Rust's default), `FS_DIR_BUILDER_WITH_RECURSIVE` normalizes any nonzero flag to `1` and otherwise preserves the `mode`, `FS_DIR_BUILDER_WITH_MODE` sets the POSIX `mode` while preserving the `recursive` flag, and `FS_DIR_BUILDER_CREATE` branches on the `recursive` flag to dispatch the existing `FS_CREATE_DIR_MODE` (non-recursive) or `FS_CREATE_DIR_ALL_MODE` (recursive) lowering, so it adds no new FFI/syscall surface. It does not model Rust's owned `DirBuilder` value/move semantics, the `Permissions`/`metadata`-style builder methods on the returned handle, Windows ACL permission layers, or `create`-variants that return the directory handle. Remaining supportable fs candidates within the supportable macro-lowering surface include the fine-grained `OpenOptions` builder-object lowerings and the rich `Permissions` / `FileType` object models; typed `ReadDir` iterator entries beyond the existing JSON/buffer listing remain gated on a streaming iterator ABI, and the `FileTimes` builder object is intentionally not modeled.
- The fs Rust API parity audit has now landed its OpenOptions builder batch, adding `FS_OPEN_OPTIONS_BUILDER_NEW`, `FS_OPEN_OPTIONS_BUILDER_WITH_READ`, `FS_OPEN_OPTIONS_BUILDER_WITH_WRITE`, `FS_OPEN_OPTIONS_BUILDER_WITH_APPEND`, `FS_OPEN_OPTIONS_BUILDER_WITH_CREATE`, `FS_OPEN_OPTIONS_BUILDER_WITH_TRUNCATE`, `FS_OPEN_OPTIONS_BUILDER_WITH_MODE`, `FS_OPEN_OPTIONS_BUILDER_WITH_CUSTOM_FLAGS`, and `FS_OPEN_OPTIONS_BUILDER_OPEN`. Builder state is three propagating SSA `u64` values (`flags`, `create_mode`, `custom_flags`) rather than a heap-allocated builder object; each `WITH_READ` / `/WRITE` / `/APPEND` / `/CREATE` / `/TRUNCATE` macro normalizes any nonzero flag to set-bit OR (Rust `.x(true)` idiom; `.x(false)` clear-bit not lowered), `WITH_MODE` / `WITH_CUSTOM_FLAGS` set the full field, and `FS_OPEN_OPTIONS_BUILDER_OPEN` delegates to the existing `FS_OPEN_OPTIONS` FFI lowering (no new syscall/FFI surface). It does not model Rust's `create_new` (`O_CREAT|O_EXCL`) — the `O_EXCL` bit is not exposed by `SA_FS_CUSTOM_*` — cross-platform truncate/append on read-only opens, the `set_permissions`-equivalent builder method, Windows ACL fields, or owned builder move/build value semantics. The fs Rust API parity audit has now landed its Open_Options builder custom-flags members batch, adding `FS_OPEN_OPTIONS_BUILDER_WITH_SYNC`, `WITH_DSYNC`, `WITH_NONBLOCK`, `WITH_NOFOLLOW`, `WITH_DIRECT`, `WITH_DIRECTORY`, and `WITH_CLOEXEC`. Each takes the current `(flags, mode, custom)` triple and a `%flag`; non-zero `%flag` ORs the matching `SA_FS_CUSTOM_*` bit into the `custom_flags` slot, zero carries the triple through unchanged — Rust's `.x(true)` idiom; `.x(false)` clear-the-bit is not lowered. Note `SA_FS_CUSTOM_SYNC = 1052672` is synthetic and overlaps `SA_FS_CUSTOM_DSYNC = 4096`, so the surface test asserts OR-accumulated values, not simple sums. No new syscall/FFI surface. Remaining supportable fs candidates within the macro-lowering surface are now the rich `Permissions` / `FileType` object models; typed `ReadDir` iterator entries beyond the existing JSON/buffer listing remain gated on a streaming iterator ABI, and the `FileTimes` builder object is intentionally not modeled.

- The BinaryHeap u64/try_peek/pop/extra_capacity aliases batch adds `BINARY_HEAP_PUSH_U64`, `BINARY_HEAP_PEEK_U64`, `BINARY_HEAP_TRY_PEEK`, `BINARY_HEAP_TRY_PEEK_U64`, `BINARY_HEAP_POP`, `BINARY_HEAP_POP_U64`, and `BINARY_HEAP_EXTRA_CAPACITY`. The `_U64` aliases preserve the existing concrete `u64` max-heap ABI; `TRY_PEEK` returns a non-destructive `(ok,value)` view; `POP` is a value-only wrapper over try-pop; `EXTRA_CAPACITY` is a pure `capacity - len` subtraction. None of these claim generic ordering, iterator/drain adapters, scoped `PeekMut` guards, or true allocator-failure reporting that remain genuinely missing for `BinaryHeap`.
- The BinaryHeap audit has now landed a concrete u64-named / try-peek / pop / extra_capacity alias batch over the existing push/peek/try-pop/capacity primitives. Remaining supportable BinaryHeap candidates within the macro-lowering surface are essentially exhausted: only Rust lazy iterator/drain adapters, generic ordering, scoped PeekMut guards, and true allocator-failure reporting remain, all intentionally outside the SA facade.
- The fs Permissions object batch adds `FS_PERMISSIONS_NEW`, `FS_METADATA_PERMISSIONS`, `FS_PERMISSIONS_READONLY`, `FS_PERMISSIONS_SET_READONLY`, and `FS_SET_PERMISSIONS_OBJ` over the existing `SaFsPermissions` mode slot / `sa_fs_set_permissions` / metadata mode FFI. `readonly` treats absence of POSIX write bits (`0222`) as readonly; `set_readonly(false)` ORs owner-write (`0200`). Combined with the earlier `FS_FILE_TYPE_IS_*` aliases, the supportable Permissions/FileType object surface is now landed. Remaining fs gaps after Permissions/FileType/FileTimes are typed streaming `ReadDir` iterators and Windows ACL permissions, all intentionally outside the current Linux POSIX facade.
- The fs FileTimes object batch adds `FS_FILE_TIMES_NEW`, `FS_FILE_TIMES_WITH_ACCESSED`, `FS_FILE_TIMES_WITH_MODIFIED`, `FS_FILE_TIMES_SET`, and `FS_METADATA_FILE_TIMES` as a two-SSA-value builder over the existing path-based `FS_SET_TIMES_MS` / metadata accessed+modified millisecond queries. It does not model Rust optional leave-unchanged sentinels, `SystemTime` objects, open-`File` times mutation beyond the path helper, or birth/creation time mutation. Remaining supportable fs gaps within the Linux POSIX facade are now mainly typed streaming `ReadDir` iterators and Windows ACL permissions.
- The HashMap/BTreeMap entry helper batch adds `MAP_OR_INSERT`, `MAP_ENTRY_OR_DEFAULT`, `MAP_ENTRY_AND_MODIFY`, `BTREE_MAP_OR_INSERT`, `BTREE_MAP_ENTRY_OR_DEFAULT`, and `BTREE_MAP_ENTRY_AND_MODIFY` over the existing try-insert / get-mut-ptr contracts. These are concrete entry-style lowerings, not Rust entry objects; closure `or_insert_with`, generic defaults, and scoped entry borrows remain genuinely missing.
- The set/map alias batch adds `SET_ENTRY_GET_OR_INSERT`, `SET_OR_INSERT`, `SET_EXTRA_CAPACITY`, `BTREE_SET_ENTRY_GET_OR_INSERT`, `BTREE_SET_OR_INSERT`, and `MAP_EXTRA_CAPACITY` over existing get-or-insert / capacity primitives. Remaining supportable collection gaps are largely iterator/entry-object/generic-Ord/allocator surfaces intentionally outside the SA facade.
- The PathBuf owned-path batch adds `PATH_BUF_NEW` / `WITH_CAPACITY` / `FROM_PATH` / `PUSH` / `POP` / `SET_FILE_NAME` / `SET_EXTENSION` / `AS_PATH` and related capacity helpers as a concrete owned byte-buffer facade over `STRING_BUF` plus existing `PATH_*` Slice join/parent helpers. Remaining path gaps are true component iterators, Windows prefixes, and `OsStr`/`OsString` semantics.
- The collection literal arity batch adds `MAP_LIT1`/`MAP_LIT3`, `SET_LIT1`/`SET_LIT3`, `BTREE_MAP_LIT1`/`LIT2`/`LIT3`, and `BTREE_SET_LIT1`/`LIT3` as fixed-arity constructors over existing put/insert helpers. Remaining collection gaps are still true iterators, generic Ord/entry objects, and allocator-aware constructors.
- The OsString/OsStr owned byte-buffer batch expands `sa_std/os/unix_ffi.sa` with concrete `OS_STRING_NEW` / `FROM_STR` / `PUSH_*` / `AS_OS_STR` / `TO_STRING_CHECKED` and `OS_STR_LEN` / `TO_OS_STRING` / `TO_STR_CHECKED` helpers over `Vec<u8>`/`Slice`. Remaining platform-string gaps are Windows WTF-8, lossy display, and true OS-native encoding objects.
- The BinaryHeap from/lit constructor batch adds `BINARY_HEAP_LIT1`/`LIT2`/`LIT3`, `BINARY_HEAP_FROM_SLICE_U64`/`FROM_VEC_U64`, and `BINARY_HEAP_EXTEND_FROM_SLICE_U64`/`EXTEND_FROM_VEC_U64` over the concrete u64 push/heapify path. Remaining BinaryHeap gaps are still lazy iterators, generic Ord, PeekMut drop guards, and allocator-aware APIs.
- The VecDeque from/lit constructor batch adds `VEC_DEQUE_LIT1`/`LIT2`/`LIT3` and `VEC_DEQUE_FROM_SLICE_U64`/`FROM_VEC_U64` over the concrete u64 push_back path. Remaining VecDeque gaps are still lazy drain/splice iterators, generic elements, and scoped mut references.
- The Vec u64 literal constructor batch adds `VEC_LIT1_U64`/`LIT2_U64`/`LIT3_U64` over `VEC_NEW` + `VEC_PUSH_U64`. Remaining Vec gaps remain generic element support and lazy iterator adapters.
- The LazyLock alias batch adds `LAZY_LOCK_NEW` / `FORCE` / `GET` / `IS_READY` / `INTO_INNER` over the existing Once/OnceLock u64 cell. Remaining sync gaps are still Condvar/Barrier, unbounded mpsc, generic OnceLock/LazyLock type objects, and RAII lock guards.
- The AtomicU64 fetch_update + StringBuf LIT batch adds `ATOMIC_U64_FETCH_UPDATE` and `STRING_BUF_LIT1`/`LIT2`/`LIT3`. Remaining sync gaps still include Condvar/Barrier and generic atomic fetch_update across all widths; remaining string gaps are Pattern trait/iterator objects.
## Notes
- Thread builder SSA facade (`THREAD_BUILDER_*` detached-only), PathBuf `PUSH_PATH_BUF`/`JOIN*`, Env `SPLIT_PATHS_OS`/`JOIN_PATHS_OS`, and `CSTR_TO_STRING_LOSSY` landed. Remaining thread gaps: stack size/name builder fields and park/unpark. Remaining env/path gaps: true OsString iterators and component iterator objects.

- Net typed-address `format_ascii` helpers, PathBuf query aliases (`IS_ABSOLUTE`/`COMPONENT_COUNT`/`TRY_*`), and `ENV_ARGS_OS`/`ENV_VARS_OS` JSON aliases landed. Remaining net gaps: zero-compressed Display, u128 bits, lazy ToSocketAddrs iterators. Remaining env gaps: true OsString iterators/objects. Remaining path gaps: true component iterator objects and Windows prefixes.

- PathBuf/OsString conversion + lossy helpers landed: `PATH_BUF_AS_OS_STR` / `FROM_OS_STR` / `FROM_OS_STRING` / `INTO_OS_STRING` / `INTO_OS_STRING_MOVE`, `OS_STRING_TO_STRING_LOSSY` / `OS_STR_TO_STRING_LOSSY` / `OS_STRING_FROM_PATH`, and `CSTRING_TO_STRING_LOSSY`. These remain Unix byte-buffer facades over `STRING_BUF_FROM_UTF8_LOSSY` and do not claim Rust `Cow`/`Display`/`WTF-8`.

- The PathBuf/OsString lit+capacity-remaining batch and Env rust-named alias batch finished validation: `PATH_BUF_LIT1/2/3` + remaining-capacity aliases, `OS_STRING_LIT1/2/3` + remaining-capacity aliases, and `ENV_VAR` / `ENV_VAR_OS` / `ENV_ARGS` / `ENV_VARS` / `ENV_SPLIT_PATHS` / `ENV_JOIN_PATHS` / `ENV_HOME_DIR` over existing helpers. Env alias surface tests require addressable `stack_alloc Slice_SIZE` keys. Remaining env gaps are true `args_os`/`vars_os` iterators and OsString-native path join/split objects.
- The Process Command builder now also has `PROCESS_COMMAND_BUILDER_EXEC_CAPTURE` / `PROCESS_COMMAND_BUILDER_OUTPUT` over existing capture ABIs (cwd-only CommandExt subset on capture). Owned CString gained `CSTRING_DEFAULT` / `CSTRING_CLONE` / `CSTRING_LIT1`. Remaining process gaps are env maps, Stdio pipe objects, and full CommandExt on capture; remaining FFI gaps include lossy conversion and Windows/OsString parity.

- Atomic narrow-width `FETCH_UPDATE` + `FROM_PTR` aliases: Bool/U8/I8/U16/I16 fetch_update and `ATOMIC_*_FROM_PTR` renames over existing from_mut helpers.
- IPv6 parse_ascii batch: runtime `sa_net_ipv6_parse_ascii` / `sa_net_socket_addr_v6_parse_ascii`, macros `NET_IPV6_*_PARSE_ASCII` / `NET_SOCKET_ADDR_V6_*_PARSE_ASCII`, enum IpAddr/SocketAddr parse now V4-then-V6; added `NET_IP_ADDR_TO_IPV6`.
- Process Command builder SSA facade batch: added `PROCESS_COMMAND_BUILDER_*` scalar-flag builder over existing CommandExt run/spawn helpers (cwd/arg0/process_group/setsid only; no env/pipe objects).
- Multi-width atomic `FETCH_UPDATE` batch: added U32/I32/I64/USIZE/ISIZE/PTR helpers over existing cmpxchg loops; unit-framework diagnostic-code collisions in `std_fs_macro_surface.sa` and `std_net_unix_macro_surface.sa` fixed so assert codes no longer share sibling-test panic IDs.

- Linux/Unix fd facade behavior is acceptable for this batch.
- Keep edits scoped to source/runtime/std facade and test coverage; do not branch into wider trait/prelude work unless a Linux std gap directly requires it.
## Notes (2026-07-12 atomic nand + panic uniqueness)
- Landed signed atomic `FETCH_AND/OR/XOR` and multi-width `FETCH_NAND` (cmpxchg loop; no ISA nand RMW).
- Verified prior batch: atomic fetch_min/max, `THREAD_SLEEP_*`, `PATH_BUF_CLONE_FROM`.
- Renumbered cross-file duplicate unit-framework panic IDs to global uniqueness (kept first-seen; later IDs from 10026+; assert codes realigned in-block).
- Do not mark full Rust-std parity complete; remaining blocked: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Notes (2026-07-12 time/io/path/once batch)
- Landed Instant/SystemTime naming aliases, `IO_COPY` handle loop, PathBuf FS query wrappers, and `ONCE_LOCK_*` aliases.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Notes (2026-07-12 path fs-ops / defaults / env os / process pid)
- Landed Path/PathBuf filesystem op wrappers, MUTEX/RWLOCK/ONCE defaults, ENV_*_OS path aliases, PROCESS_PID/PPID/UID/GID aliases.
- Fixed env free-status assertion and cross-file diagnostic IDs 1006/1007 -> 10417/10418.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 path rename/link + io handle batch)
- Landed Path/PathBuf rename/hard_link/symlink/read_to_string/create_dir_all/remove_dir_all/set_permissions/set_times_ms wrappers.
- Landed handle-level `IO_READ`/`READ_EXACT`/`WRITE`/`WRITE_ALL`/`FLUSH`/`CLOSE` status aliases.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 path read_dir batch)
- Landed Path/PathBuf `READ_DIR_JSON`/`READ_DIR_ENTRIES` wrappers over existing FS dir listing handles.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 thread/env naming + path read_dir)
- Landed `THREAD_CURRENT`/`THREAD_YIELD`, `ENV_SET_VAR_OS`/`ENV_REMOVE_VAR_OS`, and Path/PathBuf read_dir wrappers.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 time defaults + OsString default)
- Landed `TIME_DURATION_DEFAULT`/`TIME_SYSTEM_TIME_UNIX_EPOCH`/`TIME_INSTANT_SATURATING_DURATION_SINCE` and `OS_STRING_DEFAULT`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 path DirBuilder/OpenOptions facades)
- Landed Path/PathBuf wrappers for FS DirBuilder create and OpenOptions builder open.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-12 collections/atomic defaults + path perm/filetimes)
- Landed Default constructors for Map/Set/BTree/VecDeque/BinaryHeap and zero-init Atomic defaults; Path/PathBuf permissions-object and FileTimes set wrappers.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 atomic signed/ptr defaults + path metadata/fs-size/remove/mode)
- Landed signed/ptr Atomic Default constructors and Path/PathBuf metadata_json, FS file-size, remove-entry/remove-any, create-dir-with-mode wrappers.
- Avoid macro names `PATH_LEN` and `PATH_CREATE_DIR_MODE` (compile hang / InvalidMacroInvocation prefix collisions); use `PATH_FS_SIZE` and `PATH_*_WITH_MODE`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 path base64/open-flags + env home_os + once defaults + process exit_code)
- Landed Path/PathBuf open-flags/options and base64 read/write wrappers; ENV_HOME_DIR_OS; ONCE_LOCK_DEFAULT/LAZY_LOCK_DEFAULT; PROCESS_EXIT_CODE alias.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-12 path unix chown/mkfifo/make_dir + process success + thread sleep duration)
- Landed Path/PathBuf unix ownership/mkfifo/make_dir wrappers, PROCESS_SUCCESS, THREAD_SLEEP_DURATION_NS.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 time defaults/sleep + process naming + IO_COPY_N)
- Landed TIME_SLEEP_DURATION_NS/INSTANT_DEFAULT/SYSTEM_TIME_DEFAULT, PROCESS_IS_SUCCESS/CODE/OUTPUT_STATUS, and IO_COPY_N bounded handle copy.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.


## Notes (2026-07-13 BOOL/F32/F64/CHAR Default constants + RESULT_DEFAULT)
- Landed `BOOL_DEFAULT`, `NUM_F32_DEFAULT`, `NUM_F64_DEFAULT` in `sa_std/num.sal`; `CHAR_DEFAULT` in `sa_std/char.sal`; `RESULT_DEFAULT` macro (Ok(0)) in `sa_std/core/result.sa`.
- Numeric defaults test extended to cover all four new constants; default types test extended to cover `RESULT_DEFAULT` (panic ID 10463 -> 10464); full suite green.
- Fixed `RESULT_DEFAULT` test: do NOT pre-alloc the register before calling the macro (it allocates internally, like `OPTION_DEFAULT`/`OPTION_NEW_NONE`).
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 INTO/TRY_INTO/SAT_INTO aliases + PTR_SWAP_NONOVERLAPPING_U64)
- Landed 56 `INTO_*` / `TRY_INTO_*` / `SAT_INTO_*` Rust-named aliases in `sa_std/convert.sa` as wrappers over existing `FROM_*` / `TRY_FROM_*` / `SAT_FROM_*` macros; `PTR_SWAP_NONOVERLAPPING_U64` in `sa_std/ptr.sa`.
- New test file `std_into_naming_macro_surface.sa` (2 tests, panic IDs 10465/10466); fully integrated into `macro_surface_suites` in `runner.zig`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 DEFAULT_F32/F64/CHAR + RANGE_INCLUSIVE_U64_DEFAULT)
- Landed `DEFAULT_F32`, `DEFAULT_F64`, `DEFAULT_CHAR` macros in `sa_std/default.sa`; `RANGE_INCLUSIVE_U64_DEFAULT` in `sa_std/ops.sa`.
- Numeric defaults and default types tests extended; focused tests passing.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 CELL_DEFAULT + REFCELL_DEFAULT legacy aliases)
- Landed `CELL_DEFAULT` in `sa_std/core/cell.sa` (alias for `CELL_NEW`); `REFCELL_DEFAULT` in `sa_std/core/refcell.sa` (zero-init value + borrows).
- Focused temp tests passed individually; full suite build running.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Notes (2026-07-13 IO_ERROR_KIND + ERROR_CODE + ERROR_REF_IS expansion)
- Landed 33 new `IO_ERROR_KIND_*` constants in `sa_std/io.sal` covering full Rust `io::ErrorKind` enum; 19 new `ERROR_CODE_*` constants in `sa_std/error.sal`; 19 new `ERROR_REF_IS_*` helper macros in `sa_std/error.sa`.
- New test file `std_io_error_kinds_macro_surface.sa` (2 tests, panic IDs 10467/10468), registered in `macro_surface_suites` in `runner.zig`.
- Still blocked without redesign: true `format!`, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 o)

Completed supportable defaults/aliases/macros:
- 5 unsigned MIN constants in num.sal (NUM_U8/U16/U32/U64/usize_MIN = 0), mirroring Rust u*::MIN.
- 10 BYTES constants in num.sal (NUM_U8_BYTES=1 through NUM_ISIZE_BYTES=8), mirroring Rust 1.60+ stabilized <integer>::BYTES.
- 13 f32 associated constants as IEEE 754 bit patterns (INFINITY, NEG_INFINITY, NAN, ZERO, MINUS_ZERO, MIN_POSITIVE, MAX, MIN, EPSILON, MAX_SUBNORMAL, MIN_SUBNORMAL, BITS, BYTES).
- 13 f64 associated constants as IEEE 754 bit patterns (same set as f32 but 64-bit bit widths).
- WrappingU64/U32/I64 and SaturatingU64/I64 layout constants (8-byte transparent struct wrappers).
- DEFAULT_WRAPPING_U64 and DEFAULT_SATURATING_U64 zero-init macros in default.sa.
- Test file std_float_wrapping_macro_surface.sa (panic IDs 10473/10474).

Panic IDs next free: 10475+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 p)

Completed supportable defaults/aliases/macros:
- 11 Wrapping/Saturating construction/access macros in num.sa (WRAPPING_U64_NEW/GET/SET, WRAPPING_U32_NEW/GET, WRAPPING_I64_NEW/GET, SATURATING_U64_NEW/GET/SET, SATURATING_I64_NEW/GET).
- 7 Range<usize>/Bound<usize> layout constants in ops.sal (RangeUsize_SIZE, RangeInclusiveUsize_SIZE, RangeFromUsize_SIZE, RangeToUsize_SIZE, RangeToInclusiveUsize_SIZE, BoundUsize_SIZE + field offsets).
- 11 RANGE_USIZE_* alias macros in ops.sa wrapping existing RANGE_U64_* macros.
- Test file std_wrapping_range_macro_surface.sa (panic IDs 10475/10476).

Panic IDs next free: 10477+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 q)

Completed supportable defaults/aliases/macros:
- 8 new mem size/align constants in mem.sal (MEM_SIZE_F32/4, MEM_ALIGN_F32/4, MEM_SIZE_F64/8, MEM_ALIGN_F64/8, MEM_SIZE_PTR/8, MEM_ALIGN_PTR/8, MEM_SIZE_CHAR/4, MEM_ALIGN_CHAR/4).
- Test file std_mem_size_macro_surface.sa (panic ID 10477).

Panic IDs next free: 10478+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-13 r)

Completed supportable defaults/aliases/macros:
- 12 f32/f64 Digits/Radix/Exp constants in num.sal (NUM_F32_DIGITS=6, NUM_F32_RADIX=2, NUM_F32_MIN_EXP=-125, NUM_F32_MAX_EXP=128, NUM_F32_MIN_10_EXP=-37, NUM_F32_MAX_10_EXP=38, plus matching NUM_F64_* for digits=15, radix=2, min_exp=-1021, max_exp=1024, min_10_exp=-307, max_10_exp=308).
- 8 MEM_SIZE_OF_* / MEM_ALIGN_OF_* macros in mem.sa for f32, f64, ptr, char.
- Test file std_float_constants_macro_surface.sa (panic ID 10478).

Panic IDs next free: 10479+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 r confirmed)

Completed supportable defaults/aliases/macros:
- 14 f32/f64 associated constants in num.sal: MANTISSA_DIGITS (24/53), DIGITS (6/15), RADIX (2/2), MIN_EXP (-125/-1021), MAX_EXP (128/1024), MIN_10_EXP (-37/-307), MAX_10_EXP (38/308).
- 8 MEM_SIZE_OF_* / MEM_ALIGN_OF_* macros in mem.sa for f32, f64, ptr, char.
- Test file std_float_constants_macro_surface.sa (panic ID 10478).

Full `zig build unit-framework --summary all` passes: 6/6 steps, 5/5 tests passed.

Panic IDs next free: 10479+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 s)

Completed supportable defaults/aliases/macros:
- 10 Wrapping/Saturating MIN/MAX constants in num.sal (WRAPPING_U64/U32/I64_MIN/MAX, SATURATING_U64/I64_MIN/MAX).
- 6 Wrapping/Saturating struct-aware arithmetic macros in num.sa (WRAPPING_U64_ADD/SUB/MUL, SATURATING_U64_ADD/SUB/MUL) that read/write through Wrapping/Saturating struct layouts.
- Test file std_wrapping_arith_macro_surface.sa (panic ID 10479).

Panic IDs next free: 10480+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 t)

Completed supportable defaults/aliases/macros:
- 5 Atomic Ordering enum constants in sync/atomic.sal (RELAXED=0, RELEASE=1, ACQUIRE=2, ACQ_REL=3, SEQ_CST=4) mirroring Rust std::sync::atomic::Ordering.
- Test file std_atomic_ordering_macro_surface.sa (panic ID 10480).

Panic IDs next free: 10481+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 w)

Completed supportable defaults/aliases/macros:
- OsStr/OsString layout constants in ffi.sal (6 constants, both = Slice_SIZE on Unix).
- OS_STR_FROM_BYTES_OK/INTERIOR_NUL/TO_STR_INVALID_UTF8 error codes in ffi.sal (3 constants).
- MutexGuard layout: SIZE/rwlock/data in sync/mutex.sal (3 constants).
- RwLockReadGuard and RwLockWriteGuard layout in sync/rwlock.sal (6 constants).
- Test file std_ffi_osstr_layout_macro_surface.sa (panic IDs 10483/10484).

Panic IDs next free: 10485+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 x)

Completed supportable defaults/aliases/macros:
- Duration_SIZE/nanos/ZERO/MIN/MAX in time.sal (5 constants).
- Instant_SIZE/nanos, SystemTime_SIZE/nanos/UNIX_EPOCH in time.sal (5 constants).
- Test file std_time_duration_layout_macro_surface.sa (panic ID 10485).

Panic IDs next free: 10486+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 y)

Completed supportable defaults/aliases/macros:
- 5 IntErrorKind enum constants in num.sal (EMPTY/INVALID_DIGIT/POS_OVERFLOW/NEG_OVERFLOW/ZERO).
- ParseIntError layout (SIZE/code/msg) in num.sal.
- Test file std_int_error_kind_macro_surface.sa (panic ID 10486).

Panic IDs next free: 10487+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 z)

Completed supportable defaults/aliases/macros:
- TryFromIntError layout + POS/NEG overflow error codes in num.sal (4 constants).
- TryFromSliceError layout + LENGTH_MISMATCH error code in core/slice.sal (3 constants).
- Test file std_try_from_error_macro_surface.sa (panic ID 10487).

Panic IDs next free: 10488+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 aa)

Completed supportable defaults/aliases/macros:
- 20 NonZero*::BITS/BYTES associated constants in num.sal mirroring Rust 1.80+.
- Test file std_nonzero_bits_macro_surface.sa (panic ID 10488) cross-checking against NUM_*_BITS.

Panic IDs next free: 10489+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 ab)

Completed supportable defaults/aliases/macros:
- OnceLock layout + 3 state aliases in sync/once.sal (4 constants).
- LazyLock layout + 3 state aliases in sync/once.sal (4 constants).
- Test file std_once_lock_layout_macro_surface.sa (panic ID 10489) cross-checking OnceLock/LazyLock/Once sizes.

Panic IDs next free: 10490+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.
## Active std parity batch (2026-07-14 ac)

Completed supportable defaults/aliases/macros:
- New thread.sal with JoinHandle layout (SIZE/handle/result) and THREAD_DEFAULT_ID sentinel (4 constants).
- Test file std_joinhandle_layout_macro_surface.sa (panic ID 10490).

Panic IDs next free: 10491+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ad)

Completed supportable defaults/aliases/macros:
- char layout constants in char.sal (CHAR_SIZE=4, CHAR_ALIGN=4), cross-checking Rust char's u32-sized scalar representation.
- char associated constant aliases in char.sal: CHAR_REPLACEMENT_CHARACTER, CHAR_MAX_LEN_UTF8=4, and CHAR_MAX_LEN_UTF16=2.
- Test file std_char_constants_macro_surface.sa (panic ID 10491).

Panic IDs next free: 10492+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ae)

Completed supportable defaults/aliases/macros:
- char error layout constants in char.sal for ParseCharError, DecodeUtf16Error, CharTryFromError, and TryFromCharError.
- ParseCharError kind constants for EmptyString and TooManyChars, plus DecodeUtf16Error unpaired-surrogate payload offset.
- Test file std_char_error_layout_macro_surface.sa (panic ID 10492).

Panic IDs next free: 10493+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 af)

Completed supportable defaults/aliases/macros:
- fmt Error zero-sized layout constants in fmt.sal (FmtError_SIZE=0, FmtError_ALIGN=1).
- fmt Result layout/tag aliases in fmt.sal over the existing Result layout, modeling std::fmt::Result as Result<(), Error> at the SA layout level.
- Test file std_fmt_layout_macro_surface.sa (panic ID 10493).

Panic IDs next free: 10494+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ag)

Completed supportable defaults/aliases/macros:
- FFI/string conversion error layout constants in ffi.sal for NulError, FromBytesWithNulError, Utf8Error, and IntoStringError.
- Error kind aliases connect FromBytesWithNulError variants to the existing CSTR_FROM_BYTES_* validation status codes.
- Test file std_ffi_error_layout_macro_surface.sa (panic ID 10494).

Panic IDs next free: 10495+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ah)

Completed supportable defaults/aliases/macros:
- RefCell borrow error zero-sized layout constants in core/refcell.sal for BorrowError and BorrowMutError.
- Test file std_refcell_error_layout_macro_surface.sa (panic ID 10495).

Panic IDs next free: 10496+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ai)

Completed supportable defaults/aliases/macros:
- Panic location layout constants in core/panic.sal for Rust `Location`: file fat-pointer view, line, and column offsets.
- AssertUnwindSafeU64 concrete wrapper layout constants in core/panic.sal.
- Test file std_panic_layout_macro_surface.sa (panic ID 10496).

Panic IDs next free: 10497+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 aj)

Completed supportable defaults/aliases/macros:
- String/str conversion error layout constants in string.sal for FromUtf8Error, FromUtf16Error, and ParseBoolError.
- FromUtf8Error layout cross-checks the existing Vec and Utf8Error layouts; FromUtf16Error records strict UTF-16 failure kind values for lone surrogate and odd byte input.
- Test file std_string_error_layout_macro_surface.sa (panic ID 10497).

Panic IDs next free: 10498+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ak)

Completed supportable defaults/aliases/macros:
- Net address parse error layout constants in net.sal for Rust `AddrParseError`.
- AddrParseError kind constants cover Ip, Ipv4, Ipv6, Socket, SocketV4, and SocketV6 parser failure categories.
- Test file std_net_error_layout_macro_surface.sa (panic ID 10498).

Panic IDs next free: 10499+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 al)

Completed supportable defaults/aliases/macros:
- Float parsing error layout constants in num.sal for Rust `ParseFloatError`.
- Float error kind constants cover Empty and Invalid parser failure categories from Rust's `FloatErrorKind`.
- Test file std_float_error_layout_macro_surface.sa (panic ID 10499).

Panic IDs next free: 10500+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 am)

Completed supportable defaults/aliases/macros:
- Alloc layout constants in alloc/layout.sal for Rust `core::alloc::Layout` at the SA macro-layout level.
- Zero-sized LayoutError/LayoutErr and AllocError marker layout constants.
- Test file std_alloc_layout_macro_surface.sa (panic ID 10500).

Panic IDs next free: 10501+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 an)

Completed supportable defaults/aliases/macros:
- MPSC error layout constants in sync/mpsc.sal for SendError<u64>, RecvError, TryRecvError, RecvTimeoutError, and TrySendError<u64>.
- Error kind constants cover Empty/Disconnected, Timeout/Disconnected, and Full/Disconnected categories from Rust `std::sync::mpsc`.
- Test file std_mpsc_error_layout_macro_surface.sa (panic ID 10501).

Panic IDs next free: 10502+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ao)

Completed supportable defaults/aliases/macros:
- SystemTimeError layout constants in time.sal, modeling Rust `std::time::SystemTimeError(Duration)` over the existing SA Duration layout.
- Test file std_time_error_layout_macro_surface.sa (panic ID 10502).

Panic IDs next free: 10503+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ap)

Completed supportable defaults/aliases/macros:
- Sync poison error layout constants in sync/poison.sal for PoisonError<u64> and TryLockError<u64>.
- TryLockError kind constants cover Poisoned and WouldBlock categories from Rust `std::sync`.
- Test file std_sync_poison_error_layout_macro_surface.sa (panic ID 10503).

Panic IDs next free: 10504+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 aq)

Completed supportable defaults/aliases/macros:
- Collections try-reserve error layout constants in collections.sal for TryReserveErrorKind and TryReserveError.
- TryReserveError kind constants cover CapacityOverflow and AllocError, with AllocError carrying the existing AllocLayout payload.
- Test file std_collections_try_reserve_error_layout_macro_surface.sa (panic ID 10504).

Panic IDs next free: 10505+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ar)

Completed supportable defaults/aliases/macros:
- Ops ControlFlow concrete layout constants in ops.sal for ControlFlowU64 tag/value layout.
- ControlFlow Continue/Break kind constants and u64 constructor/query macros in ops.sa.
- Test file std_ops_control_flow_macro_surface.sa (panic ID 10505).

Panic IDs next free: 10506+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 as)

Completed supportable defaults/aliases/macros:
- OnceState layout constants in sync/once.sal matching the local Rust Linux/futex backend view: poisoned byte plus set_state_to primitive.
- OnceState futex state constants for COMPLETE/RUNNING/POISONED/INCOMPLETE/QUEUED/MASK and query/update macros in sync/once.sa.
- Test file std_once_state_layout_macro_surface.sa (panic ID 10506).

Panic IDs next free: 10507+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 at)

Completed supportable defaults/aliases/macros:
- AtomicOrdering layout constants in sync/atomic.sal for Rust std::sync::atomic::Ordering's one-byte enum view.
- Atomic ordering constructor/getter and load/store/failure/fence validation predicate macros in sync/atomic.sa.
- Test file std_atomic_ordering_layout_macro_surface.sa (panic ID 10507).

Panic IDs next free: 10508+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 au)

Completed supportable defaults/aliases/macros:
- Bound<usize> discriminant aliases and constructor/access/default/contains macros in ops.sal and ops.sa, mirroring Rust core::ops::Bound's Included/Excluded/Unbounded variant order over the current 64-bit SA usize layout.
- Test file std_ops_bound_usize_macro_surface.sa (panic ID 10508).

Panic IDs next free: 10509+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 av)

Completed supportable defaults/aliases/macros:
- Range<usize> finite cursor/count/slice-view aliases in ops.sa, plus RangeFrom/RangeTo/RangeInclusive/RangeToInclusive<usize> constructor/access/contains/slice-view aliases over the current 64-bit SA usize layout.
- Test file std_ops_range_usize_macro_surface.sa (panic ID 10509).

Panic IDs next free: 10510+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 aw)

Completed supportable defaults/aliases/macros:
- RangeInclusive<u64> and RangeInclusive<usize> into_inner macros in ops.sa, mirroring Rust core::ops::RangeInclusive::into_inner over the existing concrete layouts.
- Test file std_ops_range_inclusive_inner_macro_surface.sa (panic ID 10510).

Panic IDs next free: 10511+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ax)

Completed supportable defaults/aliases/macros:
- Concrete RangeBounds/IntoBounds-style bound extraction macros for RangeFull, Range, RangeFrom, RangeTo, RangeInclusive, and RangeToInclusive over u64 and usize Bound layouts.
- RangeInclusive end-bound helpers mirror Rust's exhausted behavior by returning Excluded(end) once exhausted is set.
- Test file std_ops_range_bounds_macro_surface.sa (panic ID 10511).

Panic IDs next free: 10512+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ay)

Completed supportable defaults/aliases/macros:
- Bound<u64> and Bound<usize> copy/copied/cloned aliases plus concrete map helpers in ops.sa, mirroring Rust Bound::map's tag-preserving behavior for Included/Excluded and callback bypass for Unbounded.
- Test file std_ops_bound_map_macro_surface.sa (panic ID 10512).

Panic IDs next free: 10513+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 az)

Completed supportable defaults/aliases/macros:
- Bound<u64> and Bound<usize> concrete range is_empty helpers in ops.sa, mirroring Rust RangeBounds::is_empty bound-pair rules for unbounded, inclusive, and exclusive endpoints.
- Test file std_ops_bound_range_empty_macro_surface.sa (panic ID 10513).

Panic IDs next free: 10514+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 ba)

Completed supportable defaults/aliases/macros:
- Bound<u64> and Bound<usize> concrete start/end/range intersection helpers in ops.sa, mirroring Rust IntoBounds::intersect bound-selection rules over the existing concrete Bound layouts.
- Test file std_ops_bound_intersect_macro_surface.sa (panic ID 10514).

Panic IDs next free: 10515+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bb)

Completed supportable defaults/aliases/macros:
- BoundU64Ref and BoundUsizeRef concrete tag+pointer layouts in ops.sal for Rust Bound<&u64> / Bound<&usize> lowering.
- Bound<u64> and Bound<usize> as_ref/as_mut macros plus ref copied/cloned helpers in ops.sa, mirroring Rust Bound::as_ref/as_mut and Bound<&T>::copied/cloned at the concrete pointer-layout level.
- Test file std_ops_bound_ref_macro_surface.sa (panic ID 10515).

Panic IDs next free: 10516+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bc)

Completed supportable defaults/aliases/macros:
- ControlFlow<u64, u64> concrete value/result/map helpers in ops.sa: break_value, continue_value, break_ok, continue_ok, map_break, map_continue, and into_value.
- Test file std_ops_control_flow_methods_macro_surface.sa (panic ID 10516).

Panic IDs next free: 10517+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bd)

Completed supportable defaults/aliases/macros:
- Concrete primitive std::convert::identity lowering macros in convert.sa for u64, i64, usize, and bool, plus Rust-named IDENTITY_* aliases.
- Test file std_convert_identity_macro_surface.sa (panic ID 10517).

Panic IDs next free: 10518+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 be)

Completed supportable defaults/aliases/macros:
- Concrete array rsplit helpers in array.sa: ARRAY_TRY_RSPLIT_ARRAY_REF_U64 and ARRAY_TRY_RSPLIT_ARRAY_MUT_U64, mirroring Rust rsplit_array_ref/rsplit_array_mut over existing Slice views.
- Test file std_array_rsplit_macro_surface.sa (panic ID 10518).

Panic IDs next free: 10519+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bf)

Completed supportable defaults/aliases/macros:
- Concrete array AsRef/AsMut/Borrow/BorrowMut slice-view aliases in array.sa for u64 arrays.
- Test file std_array_ref_borrow_macro_surface.sa (panic ID 10519).

Panic IDs next free: 10520+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bg)

Completed supportable defaults/aliases/macros:
- Concrete array TryFrom slice aliases in array.sa: ARRAY_TRY_FROM_SLICE_U64 and ARRAY_TRY_FROM_MUT_SLICE_U64, reusing same-length copy semantics.
- Test file std_array_try_from_slice_macro_surface.sa (panic ID 10520).

Panic IDs next free: 10521+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bh)

Completed supportable defaults/aliases/macros:
- Concrete array-ref TryFrom slice aliases in array.sa: ARRAY_REF_TRY_FROM_SLICE_U64 and ARRAY_MUT_REF_TRY_FROM_MUT_SLICE_U64, reusing exact-length Slice view checks.
- Test file std_array_ref_try_from_slice_macro_surface.sa (panic ID 10521).

Panic IDs next free: 10522+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bi)

Completed supportable defaults/aliases/macros:
- Concrete primitive array default fill helpers in array.sa for u64, i64, usize, and bool arrays, plus DEFAULT_ARRAY_* aliases.
- Test file std_array_default_macro_surface.sa (panic ID 10522).

Panic IDs next free: 10523+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bj)

Completed supportable defaults/aliases/macros:
- Concrete u64 array clone/copy aliases in array.sa: ARRAY_CLONE_U64, ARRAY_CLONE_FROM_U64, and ARRAY_COPY_FROM_U64.
- Test file std_array_clone_macro_surface.sa (panic ID 10523).

Panic IDs next free: 10524+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bk)

Completed supportable defaults/aliases/macros:
- Concrete u64 array equality aliases in array.sa: ARRAY_EQ_U64, ARRAY_NE_U64, and ARRAY_PARTIAL_EQ_U64.
- Test file std_array_eq_macro_surface.sa (panic ID 10524).

Panic IDs next free: 10525+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bl)

Completed supportable defaults/aliases/macros:
- Concrete u64 array ordering aliases in array.sa: ARRAY_CMP_U64, ARRAY_PARTIAL_CMP_U64, ARRAY_LT_U64, ARRAY_LE_U64, ARRAY_GT_U64, and ARRAY_GE_U64.
- Test file std_array_cmp_macro_surface.sa (panic ID 10525).

Panic IDs next free: 10526+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bm)

Completed supportable defaults/aliases/macros:
- Concrete u64 array Index/IndexMut aliases in array.sa: ARRAY_INDEX_U64 and ARRAY_INDEX_MUT_PTR_U64.
- Test file std_array_index_macro_surface.sa (panic ID 10526).

Panic IDs next free: 10527+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

## Active std parity batch (2026-07-14 bn)

Completed supportable defaults/aliases/macros:
- Concrete u64 array iterator construction aliases in array.sa: ARRAY_ITER_U64, ARRAY_ITER_MUT_U64, ARRAY_REF_INTO_ITER_U64, and ARRAY_MUT_REF_INTO_ITER_U64.
- Test file std_array_iter_macro_surface.sa (panic ID 10527).

Panic IDs next free: 10528+.
Still blocked without redesign: true format!, Condvar/Barrier, process env maps/Stdio objects, path component iterators, thread stack/name builder ABI.

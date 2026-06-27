# SCI Progress

Scope: `/home/vscode/projects/sci` compiler std/runtime/CLI work.

Current progress: 100%

## Completed SCI Features

- 2026-06-27: Added SAB v3 backend metadata preservation for plugin-generated SAB inputs.
  - SAB encoding now preserves raw instruction text plus full backend metadata needed by SA LLVM-C lowering: atomic expected/new operand text, native register names, package identity/source hash, upstream locations, and verifier-derived function register ids.
  - `plugin_bridge.encodeSabFromFlat` verifies flattened SA-compatible input before SAB encoding so decoded SAB carries function signature register metadata instead of relying on text headers.
  - Decoded instruction-owned metadata now has ownership compatible with both `sab.Module.deinit` and `flattener.FlattenResult.deinit`, fixing double-free diagnostics when plugin-generated SAB is loaded as a flat test input.
  - Verification used focused commands only: `timeout 120s zig test src/sab.zig --test-filter "sab v3 preserves instruction metadata required by SA backends"`, `timeout 120s zig test src/sab.zig --test-filter "sab borrow roundtrip preserves raw source text"`, `timeout 120s zig test src/sab.zig --test-filter "sab function signatures roundtrip without function header text"`, and `timeout 120s zig test src/plugin_bridge.zig --test-filter "encodeSabFromFlat writes verified register metadata"`.

- 2026-06-18: Audited rosetta package/module README provenance after the 188-260 cleanup batches.
  - Rechecked `demos/rosetta/201_pkg_manifest_basic` through `220_pkg_lib_dynamic`; the copied README template text is no longer present there.
  - Scanned `demos/rosetta/221_*` through `300_*` for the same stale provenance strings and found no remaining matches.
  - Remaining `main.rs` mentions in a few package READMEs describe the local reference file role, not the removed copied-from-`sci` boilerplate.
  - Verification: `rg -n 'This directory pairs the original Rust rosetta reference with a Sla companion|copied from sci|legacy reference translation only|legacy reference only' demos/rosetta -g 'readme.md'` now reports only the intentional `main.rs` reference notes in `201`-`205`.

- 2026-06-10: Closed the remaining low-risk issue7/issue8 core runtime/emitter items found during the final audit.
  - NetX tickets now copy payload bytes into queue-owned storage before publication, so `Ticket.payload` no longer points directly into mutable/reusable `ConnectionSlot.scratch`; ticket and slot capacity math now uses checked multiplication/power-of-two growth.
  - LLVM-C emitter lowering now builds one function-signature alias index and reuses it for direct calls, vtable resolution, reachability, and indirect-call signature inference instead of repeated linear scans by function name.
  - Test panic scalar diagnostics are protected by a mutex and handle oversized C-provided name lengths without `usize` cast traps.
  - Verification: `zig test src/runtime/sa_net_uring.zig -lc` -> `16/16 tests passed`; `zig test src/runtime/sa_std.zig -lc` -> `4/4 tests passed`; `zig build llvmc-test --summary all` -> `15/15 tests passed`; `zig build test --summary all` -> `116/116 tests passed`; `.git/hooks/pre-push origin https://github.com/layola13/sci.git` -> passed in full profile.

- 2026-06-10: Closed additional issue7 core safety/performance items without touching plugin repositories.
  - Resolver dependencies now carry manifest pinned `source_sha256`; local/global package resolution rejects mismatched package source with `UpstreamShaMismatch`, and `sa pkg install` checks fetched bytes against the manifest pin before continuing.
  - Package fetch rejects option-shaped identities/refs, inserts `--` before `git clone` positional args, and runs git with a small allowlisted environment plus noninteractive credential prompts.
  - Project lock updates now reject silent source-hash drift by default; explicit `allow_source_update` is required before stale target hashes are cleared for a changed package source.
  - Runtime pthread handles now reuse a free-slot stack instead of scanning the full slot table on each spawn, and network host inputs reject embedded NUL bytes before DNS/IP resolution.
  - Verification pending in the next batch: focused pkg/runtime tests, then full `zig build test` and pre-push hook.

- 2026-06-10: Implemented issue8 Tier-1 core performance indexes in the compiler kernel.
  - Replaced `parseOpKind` / `parseOpCode` string cascades with `std.StaticStringMap` lookups, keeping the same opcode and compatibility-alias coverage.
  - Added a verifier `sig_index_by_name` map during metadata collection so call-site signature checks and function-symbol argument checks stop scanning every function signature.
  - Moved interpreter per-function label maps and global-register slot maps into cached `FunctionRange` state built at interpreter initialization, removing repeated label-map rebuilds and hot `FunctionSig.slotOf` linear scans during execution.
  - Kept interpreter memory blocks sorted by base address and changed range lookup to binary search, preserving interior-pointer support while avoiding per-load/store linear scans over all blocks.
  - Added coverage for sorted/range-aware memory lookup after frees.
  - Verification: `zig test src/common/instruction.zig` -> `5/5 tests passed`; `zig test src/interp.zig` -> `159/159 tests passed`; `zig test src/verifier.zig` -> `153/153 tests passed`; `zig test src/cli.zig` -> `89/89 tests passed`.

- 2026-06-10: Finished low-risk issue8 compiler-kernel allocation and scan reductions.
  - Added a `VerifierBufferPool` so verifier per-function register state, flags, origins, lock state, consumed-reg flags, and interior-pointer arrays grow once per `verifyBody` worker and are reused by slicing and clearing on each function.
  - Removed now-dead verifier per-function buffer allocation/free helpers from the hot declaration path.
  - Reworked `DefDict.foldText` from a pre-scan plus replacement scan into a single lazy-output pass, preserving the zero-replacement fast path.
  - Preallocated `appendOwnedSource` capacity for imported source chunks plus the optional newline before appending.
  - Verification: `zig test src/verifier.zig` -> `153/153 tests passed`; `zig test src/interp.zig` -> `159/159 tests passed`; `zig test src/cli.zig` -> `89/89 tests passed`; `zig test src/flattener/def_dict.zig` -> `5/5 tests passed`; `zig test src/flattener.zig` -> `83/83 tests passed`.

- 2026-06-10: Hardened cached macro helper allocation-failure paths from the core flattener review.
  - Changed cached macro capture/restore ownership setup to clean up only initialized params/body lines on OOM, avoiding undefined frees and leaks in partially copied macro definitions.
  - Added allocation-failure injection coverage for the capture/restore helper path.
  - Verification: covered by `zig test src/interp.zig`, `zig test src/verifier.zig`, and `zig test src/cli.zig` flattener test imports above.

- 2026-06-10: Added tested cached-macro replay support for future frontend fragment reuse.
  - Extended `FlattenResult` ownership with `cached_macro_defs` so a flattened fragment can carry imported macro definitions alongside instructions, defs, consts, signatures, layout metadata, and package identities.
  - Changed macro collection to snapshot each macro body into owned `SourceLine` storage, so later expansion no longer depends on the original parent file `lines[start..end]` slice surviving or matching the same indices.
  - Updated macro expansion to use `macroDefBodyLines()` for hygiene name collection and recursive `emitRange` calls, fixing cached/imported macro replay and nested expansion under remapped fragment reuse.
  - Wired `appendFlattenFragment` to restore cached macro definitions into the target macro table and added regression coverage proving an imported macro fragment can still be expanded later in the parent file context.
  - Verification: `zig test src/flattener.zig` -> `82/82 tests passed`; `zig test src/cli.zig` -> `88/88 tests passed`.

- 2026-06-10: Added tested end-to-end fragment append helper and corrected `FunctionSig.id` remap semantics.
  - Added `appendFlattenFragment` to compose the existing clone/remap/merge helpers into one append step for `instructions`, `const_decls`, `function_sigs`, `test_sigs`, `defs`, `layout_versions`, `package_identities`, and `owned_text`.
  - Corrected `FunctionSig.id` handling so cached fragment replay treats it as a function-list index offset, not a `SymbolTable` id remap; test `llvm_name` values are regenerated from the new function id.
  - Made appended `test_sigs` own their own copied signatures instead of aliasing `function_sigs`, avoiding double-free and matching current `FlattenResult.deinit` ownership.
  - Added end-to-end coverage proving a fragment can be appended into a non-empty target container while preserving symbol remap, line offsets, function-id offsets, test metadata, layout metadata, package identities, and owned text independence.
  - Verification: `zig test src/flattener.zig` -> `81/81 tests passed`; `zig test src/cli.zig` -> `87/87 tests passed`.

- 2026-06-09: Added tested fragment metadata merge helpers for future cached frontend fragments.
  - Added `package_identities` merge coverage that skips duplicate package keys and deep-copies newly imported identities instead of aliasing source fragment storage.
  - Added `LayoutVersion` clone/merge helpers that skip identical `(path, version)` pairs, deep-copy new paths, and reject same-path/different-version conflicts.
  - This closes the remaining fragment-metadata merge prerequisite before cached `FlattenResult` fragments can be appended into a consumer result; production cache wiring and cache-on/off equivalence tests remain separate work.
  - Verification: `zig test src/flattener.zig` -> `80/80 tests passed`; `zig test src/cli.zig` -> `86/86 tests passed`.

- 2026-06-09: Added tested `Instruction` clone-remapping for future cached frontend fragments.
  - Added a helper to deep-clone instructions while remapping symbol/reg/label/function operands and applying source/expanded line offsets.
  - The clone path preserves and owns package identity, package source hash, upstream locations, raw text, text/native operands, atomic text fields, op/atomic metadata, and native register-name slices through the existing `owned_text` ownership model.
  - Added regression coverage for call-style symbol remapping, metadata deep-copy ownership, line offsets, and native instruction register-name slice rebuilding.
  - This closes the instruction-splicing prerequisite before cached `FlattenResult` fragments can be appended into a consumer result; production cache wiring and cache-on/off equivalence tests remain separate work.
  - Verification: `zig test src/flattener.zig` -> `78/78 tests passed`; `zig test src/cli.zig` -> `84/84 tests passed`.

- 2026-06-09: Added tested def/const merge helpers for future cached frontend fragments.
  - Added helper coverage for merging `DefDict` entries with identical duplicates skipped, new entries deep-copied, and same-name/different-value entries rejected.
  - Added deep clone and equality helpers for `ConstDecl` / `ConstValue`, including owned text, upstream locations, bytes literals, struct fields, and vtable slots.
  - Added const merge coverage proving cloned declarations get source/expanded line offsets, do not share owned buffers with the source fragment, skip identical duplicates, and reject conflicting duplicate names.
  - This closes the def/const merge prerequisite before cached `FlattenResult` fragments can be safely spliced into a consumer result; production cache wiring and cache-on/off equivalence tests remain separate work.
  - Verification: `zig test src/flattener.zig` -> `76/76 tests passed`; `zig test src/cli.zig` -> `82/82 tests passed`.

- 2026-06-09: Added tested full `FunctionSig` clone-remapping for future cached frontend fragments.
  - Added a helper to deep-clone function signatures while remapping `id`, `param_ids`, and `reg_ids`, preserving owned names, params, return shape, upstream location, test flags, llvm names, and applying an entry-instruction offset.
  - Added regression coverage for deep-copy ownership, upstream file/location preservation, entry index offsetting, remapped IDs, and invalid source IDs.
  - This closes another full IMP-1 prerequisite before cached `FlattenResult` fragments can be spliced into a consumer result.
  - Verification: `zig test src/flattener.zig` -> `74/74 tests passed`; `zig test src/cli.zig` -> `80/80 tests passed`.

- 2026-06-09: Added tested symbol-id slice remapping for future cached `FunctionSig` reconstruction.
  - Added `cloneRemappedSymbolIdSlice` so immutable `FunctionSig.param_ids` / `reg_ids`-style slices can be rebuilt under the caller allocator instead of mutated in place.
  - Added coverage for non-empty remaps, stable empty slices, copied storage, and invalid old ID rejection.
  - This completes the basic symbol ID remap primitives needed before cached `FlattenResult` fragments can be spliced into a consumer symbol table.
  - Verification: `zig test src/flattener.zig` -> `72/72 tests passed`; `zig test src/cli.zig` -> `78/78 tests passed`.

- 2026-06-09: Added tested symbol-id remap helpers for future per-module `FlattenResult` caching.
  - Added helper infrastructure to build a source-to-target `SymbolTable` ID map and remap `Instruction` operands of kind `reg`, `symbol`, `label`, and `func` while leaving text/immediate/type operands unchanged.
  - Added regression coverage proving remapped IDs change when the target symbol table already has entries, non-symbol operands are stable, and invalid old IDs are rejected.
  - This is a prerequisite for issue6 full IMP-1 `FlattenResult` fragment reuse; function signature ID slice remapping and raw-text/name collision strategy remain separate work.
  - Verification: `zig test src/flattener.zig` -> `71/71 tests passed`; `zig test src/cli.zig` -> `77/77 tests passed`.

- 2026-06-09: Added and hardened a conservative expanded-import fragment cache as an issue6 IMP-1 stepping stone.
  - Added a process-local cache for already expanded import text fragments, including line counts, transitive file mtime/size stats, layout version metadata, and LRU hooks via `SA_EXPANDED_IMPORT_CACHE_MAX_ENTRIES=N`.
  - Cache hits append the expanded fragment and mark all transitive files as seen, skipping recursive import expansion across repeated flatten calls while preserving import-cycle and duplicate-import fallback behavior.
  - The cache only stores fragments with null package identity/hash metadata, so package-context imports still use the original expansion path until full frontend IR remapping is implemented.
  - Added flattener coverage proving two entry files importing the same std fragment store on the first flatten and hit on the second, changed transitive imports invalidate cached fragments, and the opt-in one-entry LRU evicts older fragments.
  - Verification: `zig test src/flattener.zig` -> `69/69 tests passed`; `zig test src/cli.zig` -> `75/75 tests passed`; `zig build unit-framework --summary all` -> `6/6 steps succeeded; 4/4 tests passed`; `zig build smoke --summary all` -> `9/9 steps succeeded; 15/15 tests passed`.

- 2026-06-09: Added opt-in LRU bounds for the CLI source-tree hash cache for issue6 cache hygiene.
  - Added `SA_SOURCE_TREE_HASH_CACHE_MAX_ENTRIES=N` for long-lived consumers that need bounded source-tree digest cache maps; the default CLI path remains unbounded for short-lived command performance.
  - Source-tree digest cache hits now refresh LRU state, and stores evict the least-recently-used digest entry when the optional limit is exceeded.
  - Added CLI unit coverage proving a one-entry cache keeps the most recent tree digest hot and reloads an evicted older tree.
  - Verification: `zig test src/cli.zig` -> `72/72 tests passed`.

- 2026-06-09: Reduced flattener hot-path ArrayList growth for issue4 PERF-4.
  - Added exact source-line counting and preallocated `scanSource` output before classifying lines, avoiding repeated `SourceLine` array growth on large expanded inputs.
  - Preallocated import expansion output bytes and line metadata arrays per source/import chunk, reducing allocator churn while preserving all returned result ownership under the caller allocator.
  - Added unit coverage for line-count semantics matching `std.mem.splitScalar`, including empty and trailing-newline sources.
  - Verification: `zig test src/flattener.zig` -> `66/66 tests passed`; `zig test src/cli.zig` -> `71/71 tests passed`.

- 2026-06-09: Added opt-in LRU bounds for the process-local flattener import source cache for issue6 IMP-3.
  - Added `SA_IMPORT_CACHE_MAX_ENTRIES=N` for long-lived consumers that need bounded import cache maps; the default CLI path remains unbounded and keeps borrowed source hits for maximum short-lived performance.
  - When a max-entry limit is enabled, cache hits now return owned source clones instead of borrowed cache slices, making LRU eviction safe because evicted entries can free their source buffers without dangling callers.
  - Added LRU tick tracking and eviction of the least-recently-used import cache entry after stores exceed the configured limit.
  - Verification: `zig test src/flattener.zig` -> `65/65 tests passed`; `zig test src/cli.zig` -> `70/70 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Added source-tree test metadata caching as the first low-risk issue6 IMP-1 frontend-cache slice.
  - `.sa_cache/test/<key>` entries now include `test-metadata.json` with discovered SA test names, selector symbols, source locations, ignored flags, and should-panic flags.
  - `sa test` now computes the project test cache key before `compileSource`; when artifact/output/manifest/metadata are all valid, `--list`, `--compile-only`, and normal test execution reuse cached metadata and skip flatten+verify for discovery/filtering.
  - Old or incomplete test cache entries without metadata are treated as invalid and repaired through the existing recompilation path; cache clean now requires `test-metadata.json` for test cache completeness.
  - Verification: `zig test src/cli.zig` -> `69/69 tests passed`; `zig build bc2sa-smoke --summary all` -> `3/3 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`; `zig build unit-framework --summary all` -> `4/4 tests passed` with `feature_suite.sa all modes` down to about `9.7s` on the cached metadata path.

- 2026-06-09: Removed brittle hardcoded unit-framework expected test lists for issue6 TEST-4.
  - Added an SA test expectation builder in `tests/unit_framework/runner.zig` that parses `@test`, `@test should_panic`, and `@test ignored` declarations from each `.sa` suite, then generates `[PASS] ...` markers and the expected summary line automatically.
  - Replaced the 271-pass feature-suite hardcoded marker block with generated expectations, including automatic absent-marker checks for ignored tests.
  - Replaced per-suite std macro surface expected-name arrays and hand-maintained pass counts with a single macro-surface path table plus `runSaTestFileAuto`, so adding/removing `@test` cases in those source files no longer requires runner count/list edits.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Reused flattener import-source cache during project source-tree hashing for issue6 CACHE-2.
  - Exposed a narrow `readImportSourceFile` wrapper so cache-key hashing can resolve imported SA files through the same flattener import source cache used by the real flatten path.
  - Entry files still use the CLI `loadSource` path, while imported files pass their resolved source into recursive hashing, avoiding a second same-process source read/resolve for cacheable std and stable support imports.
  - Extended CLI cache coverage to prove the first source-tree hash warms the flattener import cache, the unchanged second hash uses the mtime/size digest fast path without another source load, and a dependency edit invalidates the digest.
  - Verification: `zig test src/flattener.zig` -> `64/64 tests passed`; `zig test src/cli.zig` -> `69/69 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`; `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Split the large string/vec macro surface suite for issue6 TEST-3.
  - Replaced the single 38-test `std_string_vec_macro_surface.sa` scheduling unit with `std_string_macro_surface.sa` (13 tests), `std_slice_vec_macro_surface.sa` (17 tests), and `std_vec_macro_surface.sa` (8 tests), preserving the shared imports/constants/helpers in each split file.
  - Updated the unit-framework runner expectations to keep the same 38 tests covered while enabling file-level parallel scheduling of the former slowest macro surface group.
  - Updated `docs/test_performance.md` with the split files and latest visible timings: about 18.0s, 18.3s, and 9.8s respectively.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Extended flattener import source caching to stable support roots for issue6 IMP-2.
  - Added `stable_import_roots` to resolver options and included them in the import source cache key.
  - The flattener now caches local imports whose resolved path is under an explicit stable root, while preserving the existing `sa_std` cache behavior and mtime/size invalidation.
  - CLI compile paths automatically mark `<project>/tests/unit_framework/support` as a stable import root when present, so shared SA test support files can reuse cached source in process-local test runs.
  - Verification: `zig test src/flattener.zig` -> `64/64 tests passed`; `zig test src/cli.zig` -> `69/69 tests passed`; `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Added a source-tree mtime/size fast path for project build/test cache keys for issue6 CACHE-1.
  - `hashResolvedSourceTree` now computes a per-source-tree digest once, records the participating files' real paths, mtimes, and sizes, and reuses that digest on later same-process key calculations when only stat checks are needed.
  - The fallback path still performs the existing content hash, import classification, and import resolution when any participating file changes, preserving cache invalidation correctness.
  - Added CLI unit coverage proving the second unchanged tree hash does not call `loadSource` again and a dependency edit invalidates the fast path.
  - Verification: `zig test src/cli.zig` -> `68/68 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Aligned referee LOC lint scope with the real verifier core for issue5 ENG-1.
  - Changed `tools/referee_loc_lint.zig` to measure both `src/referee/` and `src/verifier.zig`, including the builtin fallback path used when `tokei` is unavailable.
  - Updated `tasks.md` task 6.27 from the old `src/referee/ <= 2500` scope to the honest `src/referee/ + src/verifier.zig <= 6500` scope, currently 5960 code lines by fallback count.
  - Verification: `zig build referee-loc-lint --summary all` -> PASS `5960 <= 6500`; `zig test src/cli.zig` -> `67/67 tests passed`.

- 2026-06-09: Improved `sa run` diagnostics for unsupported extern/plugin symbols for issue5 SEC-1 without changing plugin repositories.
  - Added a dedicated interpreter `UnsupportedExtern` path when `sa run` reaches an `@extern` declaration, printing the exact symbol name and explaining that native build may work with the providing plugin/library while the interpreter broker/FFI bridge is not implemented.
  - Suppressed the generic CLI error wrapper for this specific interpreter failure so users see one actionable diagnostic instead of a bare `InvalidInstruction` or duplicate error label.
  - Added CLI smoke coverage for a minimal extern call under `sa run` to assert the symbol name is reported.
  - Verification: `zig test src/interp.zig` -> `138/138 tests passed`; `zig test src/cli.zig` -> `67/67 tests passed`; `zig build bc2sa-smoke --summary all` -> `3/3 tests passed`.

- 2026-06-09: Cleaned main-repo generated artifacts for issue5 ENG-2 without touching the external plugin repository.
  - Removed root-level temporary Zig/SA scaffolding, `.tmp_plugin_check` build outputs, demo compiled binaries, and `tests/unit_framework/feature_suite.o` from Git tracking while leaving local working copies ignored.
  - Added ignore rules for root temp files and common compiled artifacts (`*.o`, `*.so`, `*.dll`, `*.dylib`, `*.a`, `*.exe`) so future generated outputs do not re-enter the repository.
  - Kept real source modules such as `src/test_runner.zig` / `src/test_executor.zig` tracked after reference scanning showed they are part of the SA test framework.
  - Verification: tracked temp/binary scan for the removed classes -> clean; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Tightened plugin network permission URL validation for issue5 SEC-3.
  - Replaced prefix-only permission URL acceptance with scheme/host parsing for install-time and runtime broker checks.
  - Remote `http://`, missing schemes, and non-loopback bare IP hosts are now rejected; loopback HTTP remains allowed for local development and HTTPS domain permissions remain allowed.
  - Kept broad HTTPS wildcard permissions install-compatible but now emits an installer warning so official/plugin manifests can be narrowed without silently granting broad intent.
  - Verification: `zig test src/plugins.zig` -> `1/1 tests passed`; `zig build plugin-host-smoke --summary all` -> `11/11 tests passed`.

- 2026-06-09: Added field-level mutable borrow checks for issue5 FUNC-2.
  - Extended verifier interior-pointer state with root object and static byte-offset metadata, including label snapshot/restore handling so branch joins preserve field identity.
  - Mutable borrow conflict checks now allow simultaneous borrows of distinct known static offsets from the same root while preserving conflicts for identical offsets, unknown offsets, and whole-object borrows.
  - Offset accumulation now uses checked arithmetic and falls back to conservative unknown-offset behavior on overflow.
  - Verification: `zig test src/verifier.zig` -> `133/133 tests passed`; `zig test src/cli.zig` -> `67/67 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Verified local plugin artifact hashes before runtime loading for issue5 SEC-2.
  - Parsed selected `sap.json` artifact sha256 into `SapManifest` and preserved backward compatibility for manifests that omit artifact hashes.
  - Added a pre-`dlopen` runtime check that compares the declared artifact sha256 against the dynamic library being loaded and records a diagnostic instead of loading mismatched code.
  - Added plugin-host smoke coverage for both matching and mismatched artifact hashes.
  - Verification: `zig build plugin-host-smoke --summary all` -> `11/11 tests passed`.

- 2026-06-09: Tightened verifier metadata diagnostics and audited empty catch blocks for issue5 FUNC-1/FUNC-3.
  - Replaced the metadata rebuild `else => .forbidden_syntax` catch-all with explicit trap mapping for unsupported types, OOM, test signature mismatches, invalid atomic ordering, invalid declaration/atomic syntax, and a non-forbidden unclassified metadata fallback.
  - Added verifier coverage for metadata error mapping and invalid atomic ordering trap codes.
  - Removed bare `catch {}` from `src/`; cleanup/diagnostic-only failures now carry explicit best-effort comments, cache clean delete failures propagate, and interpreter release-time memory free errors propagate.
  - Verification: `zig test src/verifier.zig` -> `130/130 tests passed`; `zig test src/cli.zig` -> `67/67 tests passed`; `zig build pkg-core-test --summary all` -> `33/33 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Removed repeated verifier leak-scan passes for issue5 PERF-2.
  - Replaced per-live-register `regConsumedLater` full-function scans with a per-function consumed-register bitset computed once when the function scope is created.
  - Preserved existing structured consumption semantics for `move`, `release`, `assign`, `return`, `try` / `early_return`, and `^reg` call/native text markers while making early-return and exit leak checks O(1) per candidate.
  - Added a verifier regression test proving an early-return leak still reports `EarlyReturnLeak` and the consumption scan runs once over function bodies rather than once per live leak candidate.
  - Verification: `zig test src/verifier.zig` -> `128/128 tests passed`.

- 2026-06-09: Reduced verifier line classification work for issue5 PERF-1.
  - `verifyWithOptions` now preclassifies the instruction stream once and shares that `ClassifiedLine` array with metadata collection, serial body verification, and parallel body verification chunks.
  - Removed the second per-instruction `classifyLine(item.raw_text)` pass from `verifyBody`; verifier classification now happens in one verifier-owned pass instead of metadata and body passes independently reparsing the same text.
  - Added a verifier regression test that counts test-build classifier calls and asserts one classification per instruction for a complete verify run.
  - Verification: `zig test src/verifier.zig` -> `127/127 tests passed`.

- 2026-06-09: Added process-isolated file-level parallelism for SA macro surface unit tests.
  - `unit-framework` now can run independent SA macro surface files through the freshly built `sa` binary when `SA_UNIT_FILE_JOBS` is greater than 1, avoiding shared in-process CLI state while allowing file-level concurrency.
  - The pre-push timing script now exports `SA_UNIT_FILE_JOBS` from the detected host job count and leaves per-file `SA_TEST_JOBS` unset by default; the runner uses `--jobs 1` inside each concurrent file unless the caller explicitly overrides it.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`; `SA_UNIT_FILE_JOBS=4 zig build unit-framework --summary all` -> `4/4 tests passed`, run step about `1m` with macro surface files at `54.960s`.

- 2026-06-09: Reduced single-thread LLVM emitter arena page-allocator churn.
  - Added a shared emit-job backing allocator selector in `src/emit_llvm_llvmc.zig` so single-worker LLVM emission backs per-task arenas with the caller allocator instead of forcing `std.heap.page_allocator` for every job.
  - Preserved `std.heap.page_allocator` for parallel emission because the caller allocator is not guaranteed to be thread-safe across worker jobs.
  - Verification: `zig build llvmc-test --summary all` -> `1/1 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Hardened MPSC receive against damaged tail/head state.
  - Added an explicit `tail >= head` guard to `__mpsc_try_recv`; damaged `tail < head` state now returns failure before slot indexing or head movement can proceed.
  - Extended `tests/unit_framework/std_mpsc_macro_surface.sa` with a corrupted ring-state receive check and updated std smoke/source assertions.
  - Updated `docs/std_missing.md` sync safety notes to include receive-side MPSC damaged-state handling.

- 2026-06-09: Gated flattener import trace output.
  - Changed noisy `[IMPORT] resolved ...` debug printing to be disabled by default and enabled only with `SAASM_TRACE_IMPORTS=1`.
  - Preserved import resolution diagnostics for explicit tracing while removing routine stderr noise from smoke/unit runs.
  - Verification: `zig test src/flattener.zig` -> `63/63 tests passed` with no default `[IMPORT]` output.

- 2026-06-09: Reduced std import cache source cloning in the flattener.
  - Changed process-local std import cache hits to return borrowed source text from the cache instead of duplicating the full imported file into the caller allocator on every hit.
  - Kept invalidated cache source buffers alive for the process lifetime so concurrent or nested import expansion cannot observe dangling borrowed text while stale metadata is removed.
  - Added flattener coverage proving the first std import load owns source text while the second cache hit reuses borrowed source with `owned_source == null`.
  - Verification: `zig test src/flattener.zig` -> `63/63 tests passed`.

- 2026-06-09: Added manifest-backed project cache validation.
  - Build/test artifact cache entries now write `manifest.json` with cache kind, key, artifact size/hash, and output size/hash.
  - Cache hits validate the manifest before reuse and delete mismatched, stale, incomplete, or manually corrupted entries before recompiling.
  - `sa cache clean` now treats missing or invalid manifests as invalid cache state, so explicit cleanup removes old-format or damaged project cache entries instead of keeping them based only on non-empty files.
  - Verification: `zig test src/cli.zig` -> `66/66 tests passed`; `zig build smoke --summary all` -> `15/15 tests passed`.

- 2026-06-09: Reduced verifier state-delta allocation overhead.
  - Changed verifier state-delta construction to scan for actual register state changes before allocating, returning a shared empty delta for unchanged instructions.
  - Avoided duplicating empty deltas while merging parallel verifier worker results, reducing hot-path allocator churn without changing annotated instruction semantics.
  - Verification: `zig test src/verifier.zig` -> `125/125 tests passed`.

- 2026-06-09: Added project cache cleanup and SA test artifact cache repair.
  - Added core CLI support for `sa cache clean`, including `--dry-run` and `--max-age-days`, scoped only to the current project's `.sa_cache` so package/plugin caches remain separate.
  - Cache cleanup now scans `build-exe`, `build-obj`, `build-wasm`, `build-obj-incremental`, and `test` cache families, removes malformed hex keys, incomplete entries, empty artifacts, non-directory entries, and complete entries older than the configured age.
  - Build/test cache hits now validate cached `artifact.sa.bc` and `output.bin` before reuse; incomplete or damaged entries are deleted before the command falls back to recompilation.
  - `sa test` now stores no-plugin test compile/link artifacts under `.sa_cache/test`, so repeated `--compile-only` or repeated runs of the same test source can skip emit/link while still recompiling frontend metadata for selection/list accuracy.
  - Verification: focused CLI smoke filters for `cli cache clean removes invalid project cache entries` and `sa test compile-only reuses and repairs project test cache` both passed; `zig build bc2sa-smoke --summary all` -> `3/3 tests passed`; `zig build std-smoke unit-framework --summary all` -> `18/18 tests passed`; `./zig-out/bin/sa cache clean --max-age-days 0` -> `scanned=41 removed=0 kept=41`.

- 2026-06-09: Added seeded HashMap construction for hash-flooding hardening hooks.
  - Added a `HashMap_seed` field to the core HashMap layout, `sa_map_with_seed`, `sa_map_with_capacity_seed`, and matching `MAP_WITH_SEED` / `MAP_WITH_CAPACITY_SEED` macros.
  - Routed HashMap probe hashing through the stored seed while preserving the default zero-seed behavior for existing `MAP_NEW` / `MAP_WITH_CAPACITY` users.
  - Updated smoke layout/API assertions and extended `tests/unit_framework/std_hashmap_macro_surface.sa` with seeded constructor coverage for put/get/delete and capacity initialization.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashmap_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

- 2026-06-09: Reduced unit-framework feature-suite duplicate execution.
  - Kept the full `tests/unit_framework/feature_suite.sa` matrix as the default large-suite coverage, still asserting `271 passed; 0 failed; 0 skipped; 1 ignored` and representative pass markers.
  - Moved `--ignored` and `--include-ignored` mode checks to a tiny generated fixture inside `tests/unit_framework/runner.zig`, avoiding two extra executions of the 271-test feature matrix.
  - Verification: `zig build unit-framework --summary all` -> `4/4 tests passed`; `feature_suite.sa all modes` timing dropped to about `23.204s` in the visible runner timing, with remaining slow files led by `std_string_vec_macro_surface.sa` (`48.007s`), `std_path_macro_surface.sa` (`24.850s`), and `std_net_addr_macro_surface.sa` (`14.801s`).

- 2026-06-09: Hardened package identity validation and low-level memory diagnostics.
  - Strengthened package identity validation in `src/pkg/fetch.zig` to reject absolute paths, backslashes, `.` segments, and `..` segments before package fetch/cache paths are constructed.
  - Added null-pointer guard traps to `sa_std/core/mem.sa` for `sa_mem_copy` when `count > 0`, while preserving zero-length copy no-op behavior.
  - Documented `sa_std/core/refcell.sa` as non-atomic and not thread-safe, matching Rust's `!Sync` shape for this concrete runtime cell.
  - Isolated filesystem macro surface test paths so `std_fs_macro_surface.sa` can run with `--jobs auto` instead of a runner-level single-thread special case.
  - Verification: `zig build pkg-core-test --summary all` -> `33/33 tests passed`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs auto --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build unit-framework --summary all` -> `4/4 tests passed`.

- 2026-06-09: Hardened P0 std container and RwLock safety paths.
  - Added checked capacity arithmetic in `sa_std/alloc/vec.sa`, `sa_std/hashmap.sa`, and `sa_std/sync/mpsc.sa` before allocator-facing byte counts or clearing byte counts can wrap.
  - Changed Vec push growth from linear `cap + 1` to zero-case then checked doubling, reducing repeated push growth from O(n^2) reallocation behavior to amortized growth.
  - Reworked `sa_std/sync/rwlock.sa` reader/writer state to use atomic loads/stores, `atomic_rmw_add/sub`, and `cmpxchg` writer claims; reader acquisition rolls back if a writer appears after the reader count increment.
  - Added RwLock read-release underflow trap, Arc strong/weak refcount overflow traps, safe-by-default `VEC_GET` / `VEC_GET_U64`, and explicit `VEC_GET_UNCHECKED` for old unchecked indexing behavior.
  - Added bounded exponential backoff to `sa_std/sync/mutex.sa` and release stores for force-unlock paths.
  - Added `-Drelease-safe` build selection and a release workflow core-check job that gates packaging on release-safe tests plus package audit/perf checks.
  - Updated smoke assertions in `tests/std_smoke.zig` and `tests/std_smoke_containers.zig`, unit coverage for Vec checked access/growth expectations, plus `docs/std_missing.md` safety notes for Vec, HashMap, MPSC, Arc, Mutex, and RwLock.
  - Verification: focused SA unit tests for string/vec, hashmap, mpsc, arc, and rwlock all passed; `zig build std-smoke --summary all` -> `14/14 tests passed`; `zig build -Drelease-safe --summary all` -> `14/14 steps succeeded`.

- 2026-06-09: Added concrete Rust-style memory helper macros.
  - Added `MEM_SIZE_OF_VAL_U64`, `MEM_SIZE_OF_VAL_RAW_U64`, `MEM_ALIGN_OF_VAL_U64`, `MEM_ALIGN_OF_VAL_RAW_U64`, `MEM_DROP_U64`, `MEM_COPY_U64`, `MAYBE_UNINIT_U64_ASSUME_INIT_REF`, `MAYBE_UNINIT_U64_ASSUME_INIT_MUT`, `MAYBE_UNINIT_U64_ASSUME_INIT_DROP`, `MAYBE_UNINIT_U64_AS_BYTES`, `MAYBE_UNINIT_U64_AS_BYTES_MUT`, `MANUALLY_DROP_U64_DEREF`, and `MANUALLY_DROP_U64_DEREF_MUT` in `sa_std/mem.sa`.
  - Extended `tests/unit_framework/std_mem_macro_surface.sa` for concrete value layout, maybe-uninit reference/mutable pointer access, byte-slice views, drop-reset behavior, and manual-drop transparent deref pointers.
  - Updated `docs/std_missing.md` to count this concrete `u64` memory subset while keeping Rust's generic `MaybeUninit<T>`, `ManuallyDrop<T>`, drop glue, and type-driven reflection out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_mem_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3160 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style pointer and NonNull method aliases.
  - Added transparent pointer cast/expose-provenance helpers, wrapping byte and concrete `u64` offset aliases, unsigned offset-from helpers, deterministic guaranteed-equality helpers, and matching `NonNull` alignment/offset/equality wrappers in `sa_std/ptr.sa`.
  - Extended `tests/unit_framework/std_ptr_macro_surface.sa` for raw pointer and `NonNull` address, cast, wrapping offset, unsigned offset, alignment, and guaranteed equality behavior.
  - Updated `docs/std_missing.md` to count the concrete pointer method-name subset while keeping strict provenance reconstruction, metadata/fat-pointer APIs, hardware volatile semantics, and Rust's compile-time unknown guaranteed-equality state out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ptr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3147 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style numeric bit-position helper macros.
  - Added `NUM_U64_BIT_WIDTH`, `NUM_U64_ISOLATE_HIGHEST_ONE`, `NUM_U64_ISOLATE_LOWEST_ONE`, `NUM_U64_HIGHEST_ONE`, `NUM_U64_LOWEST_ONE`, and signed `i64` bit-pattern count/zero/one/isolate/highest/lowest helpers in `sa_std/num.sa`.
  - Extended `tests/unit_framework/std_num_macro_surface.sa` for zero and mixed unsigned bit positions, signed all-ones/negative bit scans, and `(ok, index)` behavior for zero/nonzero inputs.
  - Updated `docs/std_missing.md` to count the concrete numeric bit-position subset while keeping Rust's `Option<u32>` return type and generic integer trait surface out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `18 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3119 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style concrete IO utility exact/write-all helper macros.
  - Added `IO_EMPTY_READ_EXACT`, `IO_REPEAT_READ_EXACT`, and `IO_SINK_WRITE_ALL` in `sa_std/io.sa` over the existing concrete empty/repeat/sink utility contracts.
  - Extended `tests/unit_framework/std_io_utility_macro_surface.sa` for empty exact-read zero-byte success and nonzero EOF, repeat exact-read buffer filling, and sink write-all success.
  - Updated `docs/std_missing.md`, `tests/std_smoke.zig`, and generated skills to count the concrete IO utility subset while keeping Rust IO traits and arbitrary reader/writer dispatch out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3104 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build std-smoke --summary all` -> `14/14 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style concrete IO Cursor helper macros.
  - Added `IO_CURSOR_READ_EXACT`, `IO_CURSOR_WRITE_ALL`, `IO_CURSOR_FILL_BUF`, and `IO_CURSOR_CONSUME` in `sa_std/io.sa` for Rust `Read`, `Write`, and `BufRead` method-name behavior over the existing concrete cursor layout.
  - Extended `tests/unit_framework/std_io_utility_macro_surface.sa` for exact-read success and EOF behavior, fill-buffer views, consume position changes, write-all success and short-write EOF behavior, and final buffer contents.
  - Updated `docs/std_missing.md` and `tests/std_smoke.zig` to count the concrete Cursor helper subset while keeping Rust `Read` / `Write` / `BufRead` trait objects, vectored IO, and allocation-appending helpers out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_io_utility_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3101 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build std-smoke --summary all` -> `14/14 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust-style filesystem Path method wrappers.
  - Added `PATH_TRY_EXISTS`, `PATH_METADATA`, `PATH_CANONICALIZE`, and `PATH_READ_LINK` in `sa_std/path.sa` as thin `Slice` wrappers over existing `FS_*` handles for Rust `Path` method parity.
  - Extended `tests/unit_framework/std_path_macro_surface.sa` for `try_exists`, metadata handle classification/free, canonicalization buffer ownership, and read-link buffer ownership.
  - Updated `docs/std_missing.md` and `tests/std_smoke.zig` to count the new path filesystem method surface while keeping Rust `PathBuf`, `OsStr`, iterator, metadata object, and `io::Error` semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3097 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build std-smoke --summary all` -> `14/14 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added IPv4-backed SocketAddr ASCII parsing for `std::net`.
  - Added `NET_SOCKET_ADDR_TRY_PARSE_ASCII` and `NET_SOCKET_ADDR_PARSE_ASCII` in `sa_std/net.sa` for Rust-style `SocketAddr::parse_ascii` lowering over the current `ipv4:port` parser subset.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for enum tag checks, port extraction, IP extraction through `IpAddr`, alias expansion, and IPv6-form rejection.
  - Updated `docs/std_missing.md` to count the IPv4-backed enum parser while keeping IPv6 socket parsing, `AddrParseError`, `FromStr`, and full trait conversions out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa skills` -> `3093 macros, 515 extern/export declarations`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete IPv4-backed IpAddr ASCII parsing for `std::net`.
  - Added `NET_IP_ADDR_TRY_PARSE_ASCII` and `NET_IP_ADDR_PARSE_ASCII` in `sa_std/net.sa` for Rust-style `IpAddr::parse_ascii` lowering over the current IPv4 dotted-decimal parser subset.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for IPv4 success, enum tag checks, `to_ipv4` extraction, alias expansion, and IPv6-form rejection.
  - Updated `docs/std_missing.md` to count the IPv4-backed IpAddr parser subset while keeping IPv6 parsing, `AddrParseError`, `FromStr`, and enum SocketAddr parser variants out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added Rust method-name Duration arithmetic aliases.
  - Added `TIME_DURATION_CHECKED_ADD`, `TIME_DURATION_CHECKED_SUB`, `TIME_DURATION_CHECKED_MUL`, `TIME_DURATION_CHECKED_DIV`, `TIME_DURATION_SATURATING_ADD`, `TIME_DURATION_SATURATING_SUB`, `TIME_DURATION_SATURATING_MUL`, and `TIME_DURATION_ABS_DIFF` in `sa_std/time.sa` as Rust method-name aliases over the existing concrete nanosecond helpers.
  - Extended `tests/unit_framework/std_time_macro_surface.sa` with focused coverage for success, division-by-zero failure, saturation, and absolute-difference behavior through the new names.
  - Updated `docs/std_missing.md` to count the aliases while keeping Rust's typed `Duration`, u128/float conversions, and full overflow/panic semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete SocketAddrV4 ASCII parsing for `std::net`.
  - Added `NET_SOCKET_ADDR_V4_TRY_PARSE_ASCII` and `NET_SOCKET_ADDR_V4_PARSE_ASCII` in `sa_std/net.sa`, backed by the `sa_net_socket_addr_v4_parse_ascii` runtime ABI, for Rust-style `SocketAddrV4::parse_ascii` lowering over borrowed `ipv4:port` bytes.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for successful parsing, max port acceptance, out-of-range port rejection, empty-port rejection, and IPv6-form rejection.
  - Updated `docs/std_missing.md` to count the concrete SocketAddrV4 parser subset while keeping Rust `AddrParseError`, `FromStr`, IPv6, IpAddr, and enum SocketAddr parser variants out of scope.
  - Verification: `zig build --summary all` -> `14/14 steps succeeded`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete IPv4 ASCII parsing for `std::net`.
  - Added `NET_IPV4_TRY_PARSE_ASCII` and `NET_IPV4_PARSE_ASCII` in `sa_std/net.sa`, backed by the `sa_net_ipv4_parse_ascii` runtime ABI, for Rust-style dotted-decimal `Ipv4Addr::parse_ascii` lowering over borrowed bytes.
  - Extended `tests/unit_framework/std_net_macro_surface.sa` for successful parsing, alias expansion, out-of-range octets, empty octets, and trailing-byte rejection.
  - Updated `docs/std_missing.md` to count the concrete IPv4 parse subset while keeping Rust `AddrParseError`, `FromStr`, IPv6 parsing, and socket-address parser traits out of scope.
  - Verification: `zig build --summary all` -> `14/14 steps succeeded`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete BTreeMap into key/value view helpers.
  - Added `BTREE_MAP_INTO_KEYS` and `BTREE_MAP_INTO_VALUES` in `sa_std/btree_map.sa` as Rust-named consuming-style aliases over the existing eager key-set/value-Vec materializers followed by `BTREE_MAP_CLEAR`.
  - Extended `tests/unit_framework/std_btree_macro_surface.sa` for key/value output membership and cleared-map state after each helper.
  - Updated `docs/std_missing.md` to remove `into_keys` / `into_values` from the concrete BTreeMap gap while keeping Rust iterator/ownership-transfer semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_btree_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `git diff --check` -> clean.

- 2026-06-09: Added concrete HashSet key view helpers.
  - Added `SET_KEYS` and `SET_INTO_KEYS` in `sa_std/hashset.sa` for eager `Vec<u64>` materialization of pointer-key bits.
  - Extended `tests/unit_framework/std_hashset_macro_surface.sa` for non-consuming key views and consuming key views that clear the set.
  - Updated `docs/std_missing.md` to count the concrete key-view subset while keeping Rust lazy iterator and ownership semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashset_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete HashMap into key/value view helpers.
  - Added `MAP_INTO_KEYS` and `MAP_INTO_VALUES` in `sa_std/hashmap.sa` as Rust-named consuming-style aliases over the existing eager key/value Vec materializers followed by `MAP_CLEAR`.
  - Extended `tests/unit_framework/std_hashmap_macro_surface.sa` for key/value output membership and cleared-map state after each helper.
  - Updated `docs/std_missing.md` to remove `into_keys` / `into_values` from the concrete HashMap gap while keeping Rust iterator/ownership-transfer semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashmap_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added VecDeque front/back mutable pointer aliases.
  - Added `VEC_DEQUE_FRONT_MUT_PTR` and `VEC_DEQUE_BACK_MUT_PTR` in `sa_std/vec_deque.sa` as Rust-named aliases over the existing fallible raw-pointer helpers.
  - Extended `tests/unit_framework/std_vec_deque_macro_surface.sa` so the aliases mutate front/back slots and the later deque operations observe the updated values.
  - Updated `docs/std_missing.md` to count the aliases while keeping Rust's scoped mutable-reference lifetime semantics out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_deque_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added CString borrowed UTF-8 view helper.
  - Added `CSTRING_TO_STR` in `sa_std/ffi.sa` as a Rust-style borrowed `CString::to_str` lowering through the existing `CStr` view and UTF-8 validator.
  - Extended `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for successful UTF-8 CString views and invalid-UTF-8 rejection with `CSTR_TO_STR_INVALID_UTF8`.
  - Updated `docs/std_missing.md` so `CSTR_TO_STR` and `CSTRING_TO_STR` are counted in the concrete FFI C string subset while platform strings and owned conversion/error objects remain out of scope.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete Vec search wrappers.
  - Added `VEC_TRY_BINARY_SEARCH_U64`, `VEC_PARTITION_POINT_U64`, `VEC_LOWER_BOUND_U64`, `VEC_UPPER_BOUND_U64`, and `VEC_EQUAL_RANGE_U64` in `sa_std/vec.sa`.
  - The wrappers delegate to the existing concrete ascending-`u64` slice search helpers through `VEC_AS_SLICE`, preserving explicit `(ok, index)` and index-pair contracts.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for Vec binary-search hit/miss insertion points, partition point, lower/upper bounds, and equal ranges.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `38 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector cached-key sort aliases.
  - Added `SLICE_SORT_BY_CACHED_KEY_U64` in `sa_std/core/slice.sa` and `VEC_SORT_BY_CACHED_KEY_U64` in `sa_std/vec.sa`.
  - The helpers provide Rust-named `sort_by_cached_key` lowering for the concrete `u64` surface by delegating to the existing key-sort implementation; Rust's key caching/allocation/panic-drop optimization semantics remain documented as out of scope.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for both slice and Vec cached-key ordering.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `37 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector select-nth unstable helpers.
  - Added `SLICE_TRY_SELECT_NTH_UNSTABLE_U64`, `SLICE_TRY_SELECT_NTH_UNSTABLE_BY_U64`, and `SLICE_TRY_SELECT_NTH_UNSTABLE_BY_KEY_U64` in `sa_std/core/slice.sa`.
  - Added `VEC_TRY_SELECT_NTH_UNSTABLE_U64`, `VEC_TRY_SELECT_NTH_UNSTABLE_BY_U64`, and `VEC_TRY_SELECT_NTH_UNSTABLE_BY_KEY_U64` in `sa_std/vec.sa` as mutable-slice wrappers.
  - The helpers expose a concrete `(ok, left_slice, pivot_ptr, right_slice)` contract, return `ok=0` for out-of-range `nth`, and currently satisfy ordering by fully sorting the concrete `u64` slice instead of modeling Rust's optimized selection algorithm or scoped borrow tuple.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for slice normal/by/by_key, out-of-range failure, and Vec wrappers.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `36 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector unstable-sort aliases.
  - Added `SLICE_SORT_UNSTABLE_U64`, `SLICE_SORT_UNSTABLE_BY_U64`, and `SLICE_SORT_UNSTABLE_BY_KEY_U64` in `sa_std/core/slice.sa`.
  - Added `VEC_SORT_UNSTABLE_U64`, `VEC_SORT_UNSTABLE_BY_U64`, and `VEC_SORT_UNSTABLE_BY_KEY_U64` in `sa_std/vec.sa`.
  - The aliases satisfy Rust's sorted-result contract for the concrete `u64` surface while reusing the current adjacent-swap implementation; cached-key, selection/nth sorting, generic comparators, and panic/drop behavior remain documented as out of scope.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` so every new unstable-sort macro is expanded and checked.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `35 passed; 0 failed; 0 skipped`.

- 2026-06-09: Added concrete slice/vector sort helpers.
  - Added `SLICE_SORT_U64`, `SLICE_SORT_BY_U64`, and `SLICE_SORT_BY_KEY_U64` in `sa_std/core/slice.sa` for in-place concrete `u64` slice sorting.
  - Added `VEC_SORT_U64`, `VEC_SORT_BY_U64`, and `VEC_SORT_BY_KEY_U64` in `sa_std/vec.sa` as mutable-slice wrappers for common Rust `Vec::sort*` lowering shapes.
  - The helpers use stable adjacent-swap ordering over current storage and keep Rust's generic sort algorithms, panic/drop behavior, and unstable-sort families documented as out of scope.
  - Extended `tests/unit_framework/std_string_vec_macro_surface.sa` for ascending slice sort, comparator-based descending sort, key sort, empty slice no-op, and Vec wrappers.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_string_vec_macro_surface.sa --jobs 1 --trace-panic` -> `34 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added checked comparison clamp helpers.
  - Added `CMP_TRY_CLAMP_U64` and `CMP_TRY_CLAMP_I64` in `sa_std/cmp.sa`.
  - The helpers return explicit `(ok, value)` results, clamp valid ranges through the existing primitive clamp macros, and report invalid `min > max` ranges with `ok=0` instead of relying on Rust's panic behavior.
  - Extended `tests/unit_framework/std_cmp_macro_surface.sa` for valid clamping and invalid-range rejection across unsigned and signed primitives.
  - Updated `docs/std_missing.md` to count the concrete checked-clamp subset while keeping Rust generics, trait dispatch, and panic semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete BinaryHeap mutable-peek set helper.
  - Added `BINARY_HEAP_TRY_PEEK_MUT_SET_U64` and `BINARY_HEAP_PEEK_MUT_SET_U64` in `sa_std/binary_heap.sa`.
  - The helper lowers the common `peek_mut` mutation shape for the concrete `u64` max-heap by replacing the root value, returning the previous root, and immediately restoring heap order with `sift_down`; Rust's scoped `PeekMut` guard/drop object remains documented as out of scope.
  - Extended `tests/unit_framework/std_binary_heap_macro_surface.sa` for empty-heap failure, old-root reporting, root replacement, and reheapified pop order.
  - Updated `docs/std_missing.md` to count the concrete mutable-peek set subset while keeping Rust guard lifetimes, iterators, generics, and allocator behavior open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_binary_heap_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete BTreeMap/BTreeSet entry-style helpers.
  - Added `BTREE_MAP_ENTRY_OR_INSERT` in `sa_std/btree_map.sa` over the existing sorted-map try-insert value-slot pointer contract.
  - Added `BTREE_SET_GET_OR_INSERT` in `sa_std/btree_set.sa`, returning `(inserted, stored_key_slice)` for the concrete ordered slice-key set.
  - Extended `tests/unit_framework/std_btree_macro_surface.sa` for new/existing map entry insertion, returned value slots, set get-or-insert behavior, sorted-map values, key views, and pointer views.
  - Updated `docs/std_missing.md` to count these concrete ordered-collection subsets while keeping Rust's full entry objects, key ownership variants, generics, lazy iterators, and borrow semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_btree_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete HashMap/HashSet entry-style helpers.
  - Added `MAP_ENTRY_OR_INSERT` in `sa_std/hashmap.sa` as a Rust-named entry-or-insert lowering over the existing stored value-slot pointer contract.
  - Added `SET_GET_OR_INSERT` in `sa_std/hashset.sa`, returning `(inserted, stored_key)` for pointer-key sets.
  - Extended `tests/unit_framework/std_hashmap_macro_surface.sa` and `tests/unit_framework/std_hashset_macro_surface.sa` for new-key insertion, existing-key preservation, returned slot/key values, and final collection length.
  - Updated `docs/std_missing.md` to count these concrete entry-style subsets while keeping Rust's full entry objects, generics, ownership variants, and lazy iterator semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashmap_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_hashset_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete VecDeque mutating insertion pointer helpers.
  - Added `VEC_DEQUE_PUSH_BACK_MUT_PTR`, `VEC_DEQUE_PUSH_FRONT_MUT_PTR`, `VEC_DEQUE_TRY_INSERT_MUT_PTR`, and `VEC_DEQUE_INSERT_MUT_PTR` in `sa_std/vec_deque.sa`.
  - The helpers return raw pointers to the newly inserted `u64` slot for verifier-friendly lowering of Rust's `push_back_mut`, `push_front_mut`, and `insert_mut` shapes without claiming scoped borrow or generic element semantics.
  - Extended `tests/unit_framework/std_vec_deque_macro_surface.sa` to mutate the returned slots and check out-of-range insertion returns `ok=0` plus a null pointer.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_vec_deque_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator next-chunk helper coverage.
  - Added `ITER_TRY_NEXT_CHUNK_U64` in `sa_std/core/iter.sa` for caller-buffer lowering of Rust's common `Iterator::next_chunk` shape.
  - The helper reports explicit `(ok, filled)`, succeeds only when exactly the requested count is copied, treats zero-count chunks as success without consuming, and leaves Rust const-generic arrays plus `Err(IntoIter<...>)` remainder objects documented as missing.
  - Extended `tests/unit_framework/std_iter_macro_surface.sa` for full chunk, short remainder, and zero-count behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added checked Rust-style duration constructor helpers.
  - Added `TIME_DURATION_CHECKED_NEW` plus checked `from_secs`, `from_millis`, `from_micros`, `from_nanos`, `from_mins`, `from_hours`, `from_days`, and `from_weeks` variants in `sa_std/time.sa`.
  - The helpers report explicit `(ok, ns)` results for SA's `u64` nanosecond representation and leave existing direct constructors unchanged for compatibility.
  - Updated `docs/std_missing.md` to count this concrete time subset while keeping Rust's typed `Duration`, `u128`, float/signed conversion, panic, and platform clock semantics open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_time_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style fallible array generation and mapping helpers.
  - Added `ARRAY_TRY_FROM_FN_U64` and `ARRAY_TRY_MAP_U64` in `sa_std/array.sa` for concrete `u64` lowering of fallible `std::array` construction/map shapes.
  - The helpers use callback-written output slots, stop at the first `ok=0`, and report a bool-style status while preserving already written elements.
  - Updated `docs/std_missing.md` to count this concrete array subset while keeping Rust const generics, generic `Try` residuals, cleanup/drop semantics, references, and iterator gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_array_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style signed integer and NonZero `unsigned_abs` helpers.
  - Added `NUM_I8_UNSIGNED_ABS`, `NUM_I16_UNSIGNED_ABS`, `NUM_I32_UNSIGNED_ABS`, `NUM_I64_UNSIGNED_ABS`, and `NUM_ISIZE_UNSIGNED_ABS` in `sa_std/num.sa`.
  - Added `NONZERO_I8_UNSIGNED_ABS`, `NONZERO_I16_UNSIGNED_ABS`, `NONZERO_I32_UNSIGNED_ABS`, `NONZERO_I64_UNSIGNED_ABS`, and `NONZERO_ISIZE_UNSIGNED_ABS`, storing into the matching unsigned `NonZero` layouts.
  - The helpers preserve Rust's signed-minimum behavior by returning the unsigned magnitude bit pattern instead of failing or saturating.
  - Updated `docs/std_missing.md` to count this concrete primitive and NonZero numeric subset while keeping Rust trait, niche, conversion, parser, float, and `u128`/`i128` gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `17 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added signed NonZero checked and saturating neg numeric helpers.
  - Added `NONZERO_I8_CHECKED_NEG`, `NONZERO_I16_CHECKED_NEG`, `NONZERO_I32_CHECKED_NEG`, `NONZERO_I64_CHECKED_NEG`, and `NONZERO_ISIZE_CHECKED_NEG` in `sa_std/num.sa`.
  - Added matching `NONZERO_I8_SATURATING_NEG`, `NONZERO_I16_SATURATING_NEG`, `NONZERO_I32_SATURATING_NEG`, `NONZERO_I64_SATURATING_NEG`, and `NONZERO_ISIZE_SATURATING_NEG` helpers.
  - The checked helpers preserve the NonZero invariant and report primitive `MIN` negation overflow through `ok=0`; the saturating helpers store the corresponding max value for `MIN` inputs.
  - Updated `docs/std_missing.md` to count this concrete Rust-like signed NonZero unary subset while leaving Rust trait, niche, conversion, parser, float, and `u128`/`i128` gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `16 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added checked division/remainder numeric std coverage for narrow unsigned and NonZero primitives.
  - Added `NUM_U8_CHECKED_DIV`, `NUM_U16_CHECKED_DIV`, `NUM_U32_CHECKED_DIV`, `NUM_U8_CHECKED_REM`, `NUM_U16_CHECKED_REM`, and `NUM_U32_CHECKED_REM` in `sa_std/num.sa`.
  - Added `NONZERO_{U,I}{8,16,32,64}_CHECKED_DIV`, `NONZERO_{U,I}{8,16,32,64}_CHECKED_REM`, and the matching `NONZERO_{U,ISIZE}_CHECKED_DIV` / `CHECKED_REM` aliases.
  - The `NonZero` helpers preserve the invariant by returning `ok=0` when arithmetic fails or the computed result is zero, matching the existing checked add/sub/mul storage pattern.
  - Updated `docs/std_missing.md` so this concrete Rust-like numeric subset is counted while keeping Rust trait, niche, conversion, parser, float, and `u128`/`i128` gaps open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `15 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator rev/take_while/skip_while Vec helpers.
  - Added `ITER_REV_COLLECT_U64`, `ITER_TAKE_WHILE_COLLECT_U64`, and `ITER_SKIP_WHILE_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` cursors.
  - The helpers materialize caller-owned `Vec<u64>` results for common Rust `rev`, `take_while`, and `skip_while` collect lowering without claiming lazy adapter or generic trait parity.
  - Updated `docs/std_missing.md` to count these concrete eager subsets while keeping Rust generic `Item`, lazy adapters, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator enumerate/zip/chain Vec helpers.
  - Added `ITER_ENUMERATE_COLLECT_U64`, `ITER_ZIP_COLLECT_U64`, and `ITER_CHAIN_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` cursors.
  - The pair-producing helpers materialize interleaved `Vec<u64>` fields instead of pretending to expose Rust tuple values or lazy adapter objects.
  - Updated `docs/std_missing.md` to count these concrete eager lowering subsets while keeping Rust tuple types, generic `Item`, lazy adapters, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator collect/take/skip Vec helpers.
  - Added `ITER_COLLECT_U64`, `ITER_TAKE_COLLECT_U64`, and `ITER_SKIP_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - The helpers materialize caller-owned `Vec<u64>` outputs for practical `collect::<Vec<_>>()`, `take(n).collect::<Vec<_>>()`, and `skip(n).collect::<Vec<_>>()` lowering.
  - Updated `docs/std_missing.md` to count the concrete eager Vec subsets while keeping Rust lazy adapters, generic `Item`, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added eager iterator map/filter/partition collect helpers.
  - Added `ITER_MAP_COLLECT_U64`, `ITER_FILTER_COLLECT_U64`, and `ITER_PARTITION_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - The helpers consume the cursor and materialize caller-owned `Vec<u64>` results, matching practical `map(...).collect::<Vec<_>>()`, `filter(...).collect::<Vec<_>>()`, and `partition` lowering shapes.
  - Updated `docs/std_missing.md` to count these concrete eager collect subsets while keeping Rust lazy adapter identity, generic `Item`, generic `collect`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete iterator find_map and filter_map collect helpers.
  - Added `ITER_FIND_MAP_U64` and `ITER_FILTER_MAP_COLLECT_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - The map callback writes through an output slot and returns an explicit has-value flag, avoiding sentinel ambiguity.
  - `ITER_FILTER_MAP_COLLECT_U64` materializes mapped values into a new `Vec<u64>` rather than pretending to be Rust's lazy `FilterMap` adapter or generic `collect`.
  - Updated `docs/std_missing.md` to count the concrete `find_map` / materialized `filter_map` subset while keeping lazy adapters, generic `Item`, and trait wiring open.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style iterator try adaptor helper subset.
  - Added `ITER_TRY_FOLD_U64` and `ITER_TRY_FOR_EACH_U64` in `sa_std/core/iter.sa` for concrete `u64` slice cursors.
  - `ITER_TRY_FOLD_U64` uses a callback with an output accumulator slot and explicit continue/fail status, avoiding sentinel ambiguity while keeping Rust's generic `Try` trait and residual conversions documented as missing.
  - Updated `docs/std_missing.md` to count the concrete try adaptor subset while leaving lazy adapters, generic items, `collect`, `find_map`, and full trait wiring open.
  - Added SA unit coverage in `tests/unit_framework/std_iter_macro_surface.sa` for all-success, early-stop, empty iterator, accumulator preservation, and remaining-length behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_iter_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style ASCII slice view helper subset.
  - Added `ASCII_SLICE_IS_ASCII`, `ASCII_SLICE_AS_ASCII`, `ASCII_SLICE_AS_ASCII_UNCHECKED`, and `ASCII_SLICE_AS_ASCII_MUT` in `sa_std/core/ascii.sa`.
  - The checked helpers return explicit `(ok, Slice)` transparent views instead of claiming Rust's full typed `&[ascii::Char]` / `&mut [ascii::Char]` reference semantics.
  - Updated `docs/std_missing.md` so the transparent slice-view subset is counted while true typed references, trait impls, and iterator objects remain open.
  - Added SA unit coverage in `tests/unit_framework/std_ascii_macro_surface.sa` for ASCII/non-ASCII validation, checked failure empty view, unchecked view preservation, and mutable checked view behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ascii_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`.

- 2026-06-08: Expanded concrete owned `CString` with-NUL construction and view helpers.
  - Added `CSTRING_FROM_BYTES_WITH_NUL`, `CSTRING_FROM_BYTES_WITH_NUL_UNCHECKED`, `CSTRING_AS_PTR`, `CSTRING_COUNT_BYTES`, and `CSTRING_IS_EMPTY` in `sa_std/ffi.sa`.
  - The checked with-NUL constructor reuses `CSTR_FROM_BYTES_WITH_NUL` validation, copies the accepted bytes into owned storage, and leaves Rust error-object parity documented as missing.
  - Updated `docs/std_missing.md` to document the broader concrete `CString` subset while keeping `OsString`, platform strings, trait impls, and Rust drop/error semantics open.
  - Extended SA unit coverage in `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for checked/unchecked with-NUL construction, missing/interior NUL failures, pointer view, count, and empty checks.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete owned `CString` FFI helper coverage.
  - Added `CString` layout constants and `CSTRING_NEW`, `CSTRING_AS_CSTR`, `CSTRING_AS_BYTES`, `CSTRING_AS_BYTES_WITH_NUL`, `CSTRING_INTO_RAW`, `CSTRING_FROM_RAW`, and `CSTRING_FREE` in `sa_std/ffi.*`.
  - `CSTRING_NEW` rejects interior NUL bytes and appends one trailing NUL on success, matching the common Rust `CString::new` shape while keeping error objects and trait/drop semantics documented as missing.
  - Updated `docs/std_missing.md` so owned `CString` is no longer counted as wholly missing; `OsString`, platform strings, allocator-aware APIs, and Rust error object parity remain open.
  - Added SA unit coverage in `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for success, empty string, interior NUL rejection, borrowed views, and `into_raw`/`from_raw` roundtrip.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `AtomicPtr` pointer arithmetic fetch helpers.
  - Added `ATOMIC_PTR_FETCH_BYTE_ADD`, `ATOMIC_PTR_FETCH_BYTE_SUB`, `ATOMIC_PTR_FETCH_U64_ADD`, and `ATOMIC_PTR_FETCH_U64_SUB` to `sa_std/sync/atomic.sa`.
  - Implemented the helpers with load/cmpxchg retry loops and concrete SA pointer offsets; `FETCH_U64_*` uses SA's 8-byte element layout rather than pretending to model Rust generics.
  - Updated `docs/std_missing.md` so `AtomicPtr` pointer arithmetic helpers are no longer counted as a sync gap; Rust provenance and `from_ptr` semantics remain missing.
  - Added SA unit coverage in `tests/unit_framework/std_atomic_macro_surface.sa` for byte and 8-byte element add/sub old-value and final-pointer behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_atomic_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `AtomicPtr::swap` compiler-std coverage.
  - Added `ATOMIC_PTR_SWAP` to `sa_std/sync/atomic.sa` using a load/cmpxchg retry loop, because the current LLVM-C backend does not accept pointer-typed `atomicrmw xchg`.
  - Updated `docs/std_missing.md` so `AtomicPtr::swap` is no longer counted as a sync gap; pointer arithmetic helpers and Rust's full provenance model remain documented as missing.
  - Added SA unit coverage in `tests/unit_framework/std_atomic_macro_surface.sa` for old-pointer return and final pointer state.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_atomic_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Improved unit-framework test parallelism and bottleneck diagnostics.
  - `tests/unit_framework/runner.zig` now uses `SA_TEST_JOBS`, `SA_ZIG_JOBS`, `ZIG_BUILD_JOBS`, or `auto` instead of hard-coding every `sa test` run to `--jobs 1`.
  - Added per-SA-suite elapsed time logging for the native unit framework runner.
  - Kept `std_fs_macro_surface.sa` serial because parallel execution exposed filesystem state races in the file IO tests.
  - `tools/pre_push_timed.sh` now exports `SA_TEST_JOBS` from the detected worker count and prints it next to the Zig job count.
  - Added `SA_PRE_PUSH_PROFILE=full|fast|legacy`; default `full` uses the new `whitepaper-lint` step instead of `smoke` to avoid rerunning std smoke artifacts, while `legacy` preserves the old duplicate stage list for comparison.
  - Saved bottleneck findings in `docs/test_performance.md`.
  - Verification: `SA_TEST_JOBS=auto zig build unit-framework --summary all` -> `4/4 tests passed`, run step about `3m`; `tools/pre_push_timed.sh whitepaper-lint cli-skills-smoke` -> both stages passed in `1.456s`.

- 2026-06-08: Added Rust-style `std::path` optional prefix and borrowed UTF-8 view helpers.
  - Added `PATH_TRY_FILE_PREFIX`, returning `ok=1` with the Rust-style first-dot file prefix when a file name is present, or `ok=0` and an empty slice for root/empty paths.
  - Added `PATH_TRY_TO_STR`, returning `ok=1` and a borrowed `Slice` view when path bytes are valid UTF-8, or `ok=0` and an empty slice for invalid UTF-8.
  - Reused the existing compiler-std UTF-8 runtime ABI through `string.sa`; no plugin APIs or platform `OsStr` model were introduced.
  - Updated `docs/std_missing.md` path coverage notes while keeping owned `PathBuf`, Windows prefixes, and platform-specific `OsStr` semantics documented as missing.
  - Added SA unit coverage in `tests/unit_framework/std_path_macro_surface.sa` for file-prefix option behavior plus valid, empty, and invalid UTF-8 path bytes.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style string byte/UTF-8 scalar view helpers to compiler std.
  - Added `STR_BYTE_LEN` / `STRING_BYTE_LEN`, `STR_TRY_BYTE_AT` / `STRING_TRY_BYTE_AT`, `STR_CHAR_COUNT` / `STRING_CHAR_COUNT`, `STR_TRY_CHAR_AT` / `STRING_TRY_CHAR_AT`, and `STR_TRY_CHAR_RANGE_AT` / `STRING_TRY_CHAR_RANGE_AT`.
  - Backed UTF-8 scalar count/nth/range helpers with compiler runtime ABI instead of plugin APIs, keeping Deno/http/plugin-specific surfaces out of `sa_std`.
  - Updated `docs/std_missing.md` to count the new byte/scalar view helpers while still marking Rust lazy iterator objects, traits, grapheme handling, and full pattern APIs as missing.
  - Added SA unit coverage in `tests/unit_framework/std_string_vec_macro_surface.sa`; full verification is pending below in this run.

- 2026-06-08: Added Rust-style `std::io::Read` read-to-end buffer helpers for concrete SA cursors.
  - Added `IO_CURSOR_REMAINING_SLICE`, `IO_CURSOR_READ_TO_END`, and `IO_TAKE_READ_TO_END` to `sa_std/io.sa` without introducing runtime ABI or plugin dependencies.
  - The helpers expose the unread cursor tail as a borrowed view or copy it into caller-provided storage, advancing cursor/take state while staying explicit about capacity limits.
  - Updated `docs/std_missing.md` so `read_to_end` is no longer counted as fully missing, while Rust trait dispatch, Vec allocation/append, and UTF-8 `read_to_string` behavior remain documented gaps.
  - Added SA unit coverage in `tests/unit_framework/std_io_utility_macro_surface.sa`; focused verification is pending below in this run.

- 2026-06-08: Added UTF-8 validation for Rust-style string and FFI C string borrowed views.
  - Added runtime ABI `sa_str_utf8_validate` and string macros `STR_IS_UTF8` / `STRING_IS_UTF8`.
  - Added `CSTR_TO_STR`, returning a borrowed slice without the trailing NUL when UTF-8 validation succeeds, or `CSTR_TO_STR_INVALID_UTF8` plus an empty slice on invalid UTF-8.
  - Kept owned `CString`, `OsString`, lossy conversion, and Rust error-object semantics documented as missing rather than faking them in compiler std.
  - Added focused SA unit coverage in the string UTF-8 view test and FFI CStr borrowed view test.

- 2026-06-08: Added Rust-style `std::io::Read::read_to_string` buffer helpers for concrete SA cursors.
  - Added `IO_CURSOR_READ_TO_STRING` and `IO_TAKE_READ_TO_STRING`, reusing `sa_str_utf8_validate` to report invalid UTF-8 as `SA_IO_ERR_INVALID_DATA`.
  - Added `IO_ERROR_KIND_INVALID_DATA` mapping so UTF-8 data errors no longer collapse to generic `Other`.
  - Kept Rust trait dispatch and allocation-appending `String` behavior documented as missing; the SA helpers write into caller-provided storage and return borrowed `IoSlice` views.
  - Extended `std_io_utility_macro_surface.sa` coverage for valid UTF-8, invalid UTF-8, take limits, and error-kind mapping.

# SA DB Progress

Scope: `/home/vscode/projects/sa_plugins/sa_plugin_db` against `docs/database.md` / v0.6 DB goals.

Current progress: 90%

## Completed DB Features

- 2026-06-08: Treated missing registered qmod payloads as query-payload corruption.
  - `execQuery()` now maps a missing `.sa/db/qmods/<hash>.qmod` file to `ExecError.QueryPayloadCorrupted` instead of surfacing a generic file/path failure.
  - This closes the remaining gap in the qmod payload integrity boundary: both tampered payload bytes and deleted payload files now produce the same stable corruption diagnostic.
  - Reused the existing CLI payload-corruption diagnostic: `error[SA-DB-CLI]: DB query payload is corrupted` with a restore/re-register hint.
  - Added qmod coverage: `qmod exec rejects missing query payload`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `57/57 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI deleting `.sa/db/qmods/<hash>.qmod` made `sa db exec <hash>` exit `1` with `DB query payload is corrupted`.

- 2026-06-08: Split corrupted table snapshot metadata from generic DB format failures.
  - Read and write qmod table loaders now treat malformed `simple.meta` JSON, bad table metadata magic/version, and table-name identity mismatches as `ExecError.SnapshotCorrupted` instead of collapsing them into generic `InvalidFormat`.
  - This extends the existing snapshot-corruption boundary from damaged segment files to damaged snapshot metadata headers, so qmod exec no longer misreports broken table metadata as a schema-format issue.
  - Reused the existing CLI corruption diagnostic: `error[SA-DB-CLI]: DB snapshot is corrupted` with verify/restore/rebuild guidance.
  - Added qmod coverage: `qmod exec rejects corrupted table snapshot metadata` and `qmod write rejects corrupted table snapshot metadata`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `56/56 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI tamper test replacing `simple.meta` with malformed JSON made both read and write `sa db exec <hash>` paths exit `1` with `DB snapshot is corrupted`.

- 2026-06-08: Split corrupted qmod payloads from generic DB format failures.
  - Added `ExecError.QueryPayloadCorrupted` so tampered `.sa/db/qmods/<hash>.qmod` files no longer collapse into generic `InvalidFormat` during `sa db exec <hash>`.
  - `execQuery()` now treats a SHA-256 mismatch between the requested registered hash and the on-disk qmod payload as dedicated query-payload corruption.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB query payload is corrupted` with a direct restore/re-register hint.
  - Added qmod coverage: `qmod exec rejects corrupted query payload`; added wrapper coverage: `db plugin wrapper renders corrupted query payload diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `54/54 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI tamper test overwriting `.sa/db/qmods/<hash>.qmod` made `sa db exec <hash>` exit `1` with `DB query payload is corrupted`.

- 2026-06-08: Hardened qmod registry metadata against hash-redirection tampering.
  - Added `ExecError.QueryRegistryCorrupted` so corrupted `.sa/db/qmods/<hash>.meta.json` entries no longer collapse into generic format failures.
  - `loadMeta()` now verifies registry self-consistency: the requested `<hash>` must match the metadata `hash`, the recorded `qmod_path` must match `.sa/db/qmods/<hash>.qmod`, `grants` must equal `grant_entries.len`, and `main` must be non-empty.
  - This closes a real integrity hole where replacing `<A>.meta.json` with `<B>.meta.json` could redirect `sa db exec <A>` or `sa db inspect <A>` toward another registered qmod.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB query registry metadata is corrupted` with a direct repair/re-register hint.
  - Added qmod coverage: `qmod inspect rejects corrupted registry metadata` and `qmod exec rejects corrupted registry metadata`; added wrapper coverage: `db plugin wrapper renders corrupted registry metadata diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `52/52 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI tamper test replacing `<first_hash>.meta.json` with `<second_hash>.meta.json` made both `sa db inspect <first_hash>` and `sa db exec <first_hash>` exit `1` with `DB query registry metadata is corrupted`.

- 2026-06-08: Split malformed DB query hashes from unknown registered hashes.
  - Added `ExecError.InvalidQueryHash` so malformed `sa db exec <hash>` and qmod registry lookups no longer collapse into generic format failures.
  - `parseHashHex()` now rejects non-64-byte or non-hex hash text with the dedicated error, while valid-but-missing 64-hex hashes still return `QueryHashUnknown`.
  - Plugin CLI now reports `error[SA-DB-CLI]: invalid DB query hash` with a direct `64-character hexadecimal` hint.
  - `sa db inspect` now treats 64-character non-hex text as a malformed hash instead of falling through to table lookup.
  - Added qmod coverage: `qmod exec rejects malformed query hash text`, `qmod inspect rejects malformed query hash text`, and `qmod exec distinguishes unknown query hash from malformed hash`; added wrapper coverage: `db plugin wrapper renders invalid query hash diagnostic` and `db inspect rejects malformed 64-byte hash text before table lookup`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `49/49 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db exec not-a-hash` exited `1` with `invalid DB query hash`, valid unknown 64-hex exited `1` with `DB query hash is unknown`, and `sa db inspect <64-char non-hex>` exited `1` with `invalid DB query hash`.

- 2026-06-08: Split corrupted snapshot segments from generic DB format failures.
  - Added `ExecError.SnapshotCorrupted` for qmod execution paths where segment file counts, byte lengths, or SHA-256 hashes no longer match table metadata.
  - Read and write table loaders now surface corrupted table segments through this dedicated runtime error instead of collapsing them into `InvalidFormat`.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB snapshot is corrupted` with a direct verify/restore/rebuild hint.
  - Added wrapper coverage: `db plugin wrapper renders snapshot corrupted diagnostic`, plus qmod coverage: `qmod exec rejects corrupted table snapshot segment`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `44/44 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db exec <hash>` after segment corruption exited `1` with `DB snapshot is corrupted`.

- 2026-06-08: Restricted `db_atomic_cursor` to `u64` columns with explicit type diagnostics.
  - Atomic cursor registration now rejects base or named cursor bindings unless the target DB column is exactly `u64` with 8-byte stride.
  - Added `ExecError.ColumnTypeMismatch` so atomic type failures no longer collapse into generic capability or format errors.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB column type mismatch` with a direct `u64` column hint.
  - Added unit coverage for non-`u64` base and named atomic cursor bindings, plus wrapper coverage for the new diagnostic.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `42/42 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register atomic_u32_base.query.sa` exited `1` with `DB column type mismatch`.

- 2026-06-08: Restricted `db_atomic_cursor` qmods to the single documented cursor slot.
  - Registration-time atomic validation now requires every `atomic_rmw_*` cursor address to use an explicit `+0` offset; nonzero constants and dynamic offset expressions are rejected as `DbCapabilityEscalation`.
  - Runtime atomic execution also defends this boundary and refuses any nonzero resolved cursor offset.
  - This aligns the implementation with the design doc's single `global_len` cursor model instead of allowing arbitrary byte offsets over the bound column.
  - Added unit coverage: `qmod register rejects atomic cursor nonzero offset` and `qmod register rejects atomic cursor dynamic offset expression`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `39/39 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register atomic_offset.query.sa` exited `1` with `DB query capability escalation`.

- 2026-06-08: Split schema-hash drift from generic DB format failures.
  - Added `ExecError.SchemaMismatch` for cases where the current table schema hash no longer matches the hash recorded in table metadata.
  - Read and write qmod table loaders now surface schema drift through this dedicated error instead of collapsing it into `InvalidFormat`.
  - Plugin CLI now reports `error[SA-DB-CLI]: DB schema hash mismatch` with a direct restore/refresh hint.
  - Added wrapper coverage: `db plugin wrapper renders schema mismatch diagnostic`, and updated qmod schema-drift coverage to expect the dedicated error.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `37/37 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db exec <hash>` after schema mutation exited `1` with `DB schema hash mismatch`.

- 2026-06-08: Tightened Referee DB grant binding to the actual entrypoint signature.
  - Registration-time read/write/atomic pointer validation now binds only to the effective qmod entrypoint, preferring explicit `@main` over helper functions.
  - Helper signatures can no longer smuggle `&col_*` or `&cursor*` pointers that satisfy grant checks while the real entrypoint omits them.
  - DB pointer params in the entrypoint must now be declared as `ptr`, or registration fails with `DbCapabilityEscalation`.
  - Fixed a related entrypoint bug in `findMainName()`: when `@main` exists later in the file, helper order no longer changes the registered/executed entrypoint.
  - Added unit coverage: `qmod register rejects load pointer smuggled through helper signature`, `qmod register rejects DB column pointer declared with non-ptr type`, and `qmod register rejects atomic cursor smuggled through helper signature`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `36/36 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register helper_pointer.query.sa` exited `1` with `DB query capability escalation`.

- 2026-06-08: Added duplicate-register guard for qmod registry metadata.
  - Re-registering the same qmod hash is now only allowed when the existing registry entry is fully identical, including source path, qmod path, imports, grants, entrypoint, and stored qmod bytes.
  - Reusing the same SHA-256 from a different source path or different registry metadata now fails with `ExecError.DuplicateRegister`, which aligns the registry with zero-trust hash locking instead of silently rewriting metadata.
  - Added unit coverage: `qmod register rejects duplicate hash from different source path` and `db plugin wrapper renders duplicate register diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `33/33 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `sa db register first.query.sa` remained idempotent while `sa db register second.query.sa` exited `1` with `DB query hash is already registered with different metadata`.

- 2026-06-08: Split qmod params-layout failures from schema-format failures.
  - Added `ExecError.InvalidParams` so malformed or overlong `params.bin` payloads no longer collapse into the generic schema-format path.
  - Plugin CLI now reports `error[SA-DB-CLI]: invalid DB params format` with a direct `params.bin` layout/byte-length hint.
  - Added wrapper coverage: `db plugin wrapper renders invalid exec params diagnostic`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `31/31 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI scalar and DB qmods both exited `1` with `invalid DB params format`.

- 2026-06-08: Enforced exact `params.bin` consumption for qmod execution.
  - Scalar qmods now require `params.bin` length to be exactly `param_count * 8`, instead of accepting trailing bytes.
  - DB qmods now consume params through a shared cursor and reject any trailing bytes across read, write, read-write, and atomic execution paths.
  - This closes a hidden layout ambiguity where concatenated or stale params could be silently ignored during qmod execution.
  - Added unit coverage: `qmod exec rejects trailing scalar params bytes` and `qmod exec rejects trailing DB params bytes`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `30/30 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI scalar and DB qmods both rejected extra param bytes with exit code `1`.

- 2026-06-08: Added stale-metadata guard for qmod write commits.
  - Dirty qmod writes now re-read `<table>.meta` before writing segment files and committing metadata.
  - The guard verifies the loaded metadata is still current across epoch, row count, schema hash, lock state, columns, segments, and segment file hashes/byte sizes.
  - If another operation changed metadata after qmod execution loaded the table, commit returns `ExecError.StaleMetadata` before writing dirty segment files, avoiding stale hash/epoch overwrite.
  - Added unit coverage: `qmod write commit rejects stale table metadata`, which loads a writable table, mutates its pending buffer, ingests another segment to advance metadata, then confirms stale commit is rejected and original data remains intact.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `28/28 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI write regression returned `result_u64: 9`, `sa db verify simple` passed with `epoch: 2`, and follow-up read qmod returned `result_u64: 10`.

- 2026-06-08: Added explicit locked-table diagnostics for qmod write paths.
  - Write-capable qmod execution now returns `ExecError.Locked` when the target table metadata is locked, instead of falling back to `UnsupportedOperation`.
  - Plugin CLI maps the qmod lock error to `error[SA-DB-CLI]: DB table is locked` with the existing lock recovery hint.
  - Added unit coverage: `qmod exec rejects writes against locked tables`, covering both `db_write` and `db_atomic_cursor` qmods against a locked table.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `27/27 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db lock simple` followed by write qmod and atomic qmod exec both exited `1` with `DB table is locked`.

- 2026-06-08: Added explicit atomic cursor column binding.
  - `&cursor` remains supported as a compatibility binding to the authorized table's first column.
  - `&cursor_<column>` now requires `<column>` to exist in the authorized table schema at registration time and binds to that exact column at execution time.
  - Added unit coverage: `qmod exec atomic cursor targets named DB column`, which updates only `score` via `&cursor_score`, keeps `id=5`, changes `score` from `7` to `12`, and reads `id + score == 17`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `26/26 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <atomic_score_hash>` returned `result_u64: 7`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and follow-up read qmod returned `result_u64: 17`.

- 2026-06-08: Added a narrow `db_atomic_cursor` qmod execution path.
  - Qmods with `db_atomic_cursor:<table>` can now execute `atomic_rmw_add cursor+offset, delta` over the authorized table's first column.
  - The operation returns the old value, writes back old plus delta, commits dirty segment bytes, recomputes SHA-256 metadata, and increments the table `epoch`.
  - Register-time cursor checks remain active: atomic bases must come from declared `&cursor: ptr` or `&cursor_<table>: ptr` parameters.
  - Added unit coverage: `qmod exec atomic cursor add updates u64 DB column`, which starts from `id=5`, returns old value `5`, verifies the table, then reads back `8`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `25/25 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <atomic_hash>` returned `result_u64: 5`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and follow-up read qmod returned `result_u64: 8`.

- 2026-06-08: Added a narrow cross-table read/write qmod execution path.
  - Qmods can now declare `db_read:<src>` and `db_write:<dst>` for different tables when source and destination row counts match.
  - Register-time read validation now checks only actual `load` bases against the read table schema, and write validation checks only actual `store` bases against the write table schema. This allows `&col_id` to exist only in the source table and `&col_score` only in the destination table without weakening base-pointer checks.
  - Runtime loads source columns from a read-only table buffer and stores into destination dirty column segments; commit updates only destination SHA metadata and epoch.
  - Added unit coverage: `qmod exec cross-table read-writes u64 DB column segments`, which reads `src.id` row 1 value `2`, adds `10`, writes `12` into `dst.score`, verifies both tables, then reads `sum(dst.score) == 12`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `24/24 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <copy_hash> --params params.bin` returned `result_u64: 12`, `src` verify stayed at `epoch: 1`, `dst` verify reached `epoch: 2`, and follow-up read qmod returned `result_u64: 12`.

- 2026-06-08: Added a narrow read-modify-write qmod execution path.
  - Qmods can now declare `db_read:<table>` and `db_write:<table>` together when both grants name the same table.
  - The mixed evaluator reads from the writable column buffers with `load col_x+offset as u64`, computes with the existing arithmetic/comparison subset, writes back with `store col_x+offset, value as u64`, and commits through the same dirty-segment SHA/epoch update path as pure writes.
  - Added unit coverage: `qmod exec read-modify-writes u64 DB column segments`, which reads row 1 value `2`, adds delta `7`, writes `9`, verifies the table, then reads `sum(id) == 10`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `23/23 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <update_hash> --params params.bin` returned `result_u64: 9`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and a follow-up read qmod returned `result_u64: 10`.

- 2026-06-08: Added a narrow persisted `db_write` qmod execution path.
  - Single-table `db_write:<table>` qmods can now execute `store col_x+offset, value as u64` with schema-validated column pointers, `len`, little-endian `u64` params, labels/branches/jumps, arithmetic, and comparisons.
  - Successful writes update dirty column segment files, recompute segment SHA-256 metadata, increment table `epoch`, and rewrite `<table>.meta` so `sa db verify <table>` remains valid.
  - Added unit coverage: `qmod exec writes u64 DB column segments`, which writes the second row from `2` to `9`, verifies the table, then reads `sum(id) == 10` through a read qmod.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `22/22 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db exec <write_hash> --params params.bin` returned `result_u64: 9`, `SA_PLUGIN_DEV=1 sa db verify simple` passed with `epoch: 2`, and a follow-up read qmod returned `result_u64: 10`.

- 2026-06-08: Added qmod execution-time schema hash drift protection.
  - `loadReadTable()` now rereads current `<table>.sadb-schema`, hashes it with SHA-256, and compares it against `<table>.meta` `schema_hash` before loading column segments.
  - Schema replacement or drift after ingest/register now fails `sa db exec <hash>` with `error[SA-DB-CLI]: invalid DB schema format` instead of reading with stale table metadata.
  - Added unit coverage: `qmod exec rejects table schema hash drift`.
  - Verification: `/home/vscode/projects/sa_plugins/sa_plugin_db` `zig build test --summary all` -> `21/21 tests passed`; `zig build` passed; `SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_db` passed; real CLI `SA_PLUGIN_DEV=1 sa db init/ingest/register`, mutate `simple.sadb-schema`, then `SA_PLUGIN_DEV=1 sa db exec <hash>` exited 1 with `invalid DB schema format`.

## DB Notes

- Percent is scoped to DB plugin progress, not total SA project progress.
- Remaining major DB gaps: full Referee DB grants, mmap/SIGSEGV guard, Blob Arena, cold/hot tiers, Zstd/S3, SQLite benchmark, and 12 DB Trap boundary coverage.

# SA Rust Std Progress

Scope: current `sa_std` Rust std supplementation pass, excluding optional plugins and full Rust trait/generic/type-system parity.

Current progress: 100%

## Completed Features

- 2026-06-08: Added Rust-style `std::process::abort` helper.
  - Added runtime export `sa_std_process_abort() noreturn`, C header declaration, SA interface declaration, and macro `PROCESS_ABORT`.
  - The helper lowers Rust's `std::process::abort()` into the platform abort path and intentionally never returns.
  - Updated `docs/std_missing.md` so `process::abort` is no longer counted as a process std gap.
  - Added SA process macro surface coverage without invoking the terminating macro in the unit runner, plus C runtime coverage that forks a child, calls `sa_std_process_abort()`, and verifies SIGABRT in the parent.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`; `zig test tests/sa_std_runtime.zig --test-filter "sa_std fmt and process exports are usable from C"` -> `All 1 tests passed`; `zig build sa-std-static --summary all` -> `5/5 steps succeeded`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Updated `sa skills` source generation for the expanded compiler std surface.
  - `sa skills --help` now states that generated skills scan the active `sa_std` root for `.sa`, `.sal`, and `.sai` macros plus extern/export declarations.
  - The generated SA skill now includes a source-level std coverage guide covering core macro families, runtime-backed std families, Rust-style fs/net highlights, async/future/task scope limits, and the plugin boundary.
  - The CLI `std runtime` skill section now reflects the broadened string/vec/slice/option/result/core, fs/env/process/io/time/net/sync, json/regex/fmt/path/term coverage instead of the older narrow facade wording.
  - Added CLI smoke assertions so the generated skill must include representative new std macros such as `FS_CREATE_DIR`, `FS_READ_TO_STRING`, `FS_TRY_EXISTS`, `NET_TO_SOCKET_ADDR_FIRST`, `ENV_ARGS_JSON`, `PROCESS_CHILD_ID`, `PTR_NULL`, `NUM_U64_CHECKED_ADD`, and `ANY_REF_NEW`.
  - Added focused build step `zig build cli-skills-smoke` so future SA skills source changes can be tested without running unrelated full gates.
  - Verification: `zig build cli-skills-smoke --summary all` -> `2/2 tests passed`; `zig build --summary all` -> `14/14 steps succeeded`; regenerated Codex/Claude skills from `/home/vscode/projects/sci/sa_std`.

- 2026-06-08: Added Rust-style `std::fs::try_exists` helper.
  - Added runtime export `sa_std_fs_try_exists(path, len, &out_exists)` and SA macro `FS_TRY_EXISTS`.
  - The helper distinguishes a missing path (`status=OK, exists=0`) from other filesystem errors, matching Rust's `try_exists` result shape more closely than legacy bool-only `FS_EXISTS`.
  - Kept `FS_EXISTS` as the existing compatibility helper.
  - Updated `docs/std_missing.md` and SA skills so `try_exists` is counted as filesystem std coverage.
  - Added focused SA unit coverage for missing and present path results, and extended smoke surface/header/C runtime checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style `std::fs::read_to_string` helper.
  - Added runtime exports `sa_fs_read_to_string(path, len, max_bytes)` and `sa_std_fs_read_to_string(..., &out_handle)` plus SA macro `FS_READ_TO_STRING`.
  - The helper reuses the existing owned read-buffer contract but validates UTF-8 before returning, so invalid file bytes fail instead of being exposed as a string.
  - Updated `docs/std_missing.md` and SA skills so `read_to_string` is counted as filesystem std coverage rather than a missing gap.
  - Added focused SA unit coverage for valid UTF-8 success and invalid UTF-8 failure, and extended smoke surface/header/C runtime checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style recursive `std::fs::remove_dir_all` helper and corrected `remove_dir` semantics.
  - Added runtime export `sa_fs_remove_dir_all(path, len)` and SA macro `FS_REMOVE_DIR_ALL` for explicit recursive delete-tree behavior.
  - Changed `sa_fs_remove_dir` / `FS_REMOVE_DIR` to non-recursive directory removal so it now fails on non-empty directories like Rust `std::fs::remove_dir`.
  - Kept `FS_REMOVE_PATH` as the broad recursive compatibility path and documented the difference in `docs/std_missing.md`.
  - Added focused SA unit coverage for non-empty `remove_dir` failure plus `remove_dir_all` success, and extended smoke surface/header/C runtime checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style non-recursive `std::fs::create_dir` helper.
  - Added runtime export `sa_fs_create_dir(path, len)` and SA macro `FS_CREATE_DIR`.
  - Kept existing `FS_MAKE_DIR` / `FS_CREATE_DIR_ALL` recursive behavior unchanged while adding a Rust-aligned single-directory creation path that fails on existing directories or missing parents.
  - Updated `docs/std_missing.md` so filesystem directory creation coverage distinguishes non-recursive `create_dir` from recursive `create_dir_all`.
  - Extended focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa` and smoke surface/header/C runtime checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke --summary all` -> `7/7 steps succeeded; 14/14 tests passed`.

- 2026-06-08: Added Rust-style filesystem time mutation POSIX helper.
  - Added runtime export `sa_fs_set_times_ms(path, len, accessed_ms, modified_ms)` and SA macro `FS_SET_TIMES_MS`.
  - The helper lowers Rust's `FileTimes` mutation shape into explicit Unix-millisecond atime/mtime values and updates paths through POSIX `futimens`, staying inside compiler std.
  - Updated `docs/std_missing.md` so filesystem time mutation is no longer counted as completely missing; full Rust `FileTimes` object modeling, nanosecond builder semantics, and cross-platform timestamp behavior remain open.
  - Extended focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa` and smoke surface/header/C runtime checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::join_paths` POSIX JSON helper.
  - Added runtime export `sa_env_join_paths_json(paths_json, len)` and SA macros `ENV_JOIN_PATHS_JSON` / `ENV_JOIN_PATHS_JSON_PTR` using the existing owned env-buffer contract.
  - The helper accepts a JSON array of path strings and returns a POSIX `:`-joined path list for the default Linux platform without plugin platform assumptions.
  - Updated `docs/std_missing.md` so `join_paths` is no longer counted as completely missing; full platform-specific joining, OsString semantics, and Rust iterator/object parity remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::split_paths` POSIX JSON helper.
  - Added runtime export `sa_env_split_paths_json(path_list, len)` and SA macros `ENV_SPLIT_PATHS_JSON` / `ENV_SPLIT_PATHS_JSON_PTR` using the existing owned env-buffer contract.
  - The helper returns a JSON array of POSIX `:`-split path segments for the default Linux platform without introducing plugin platform assumptions.
  - Updated `docs/std_missing.md` so `split_paths` is no longer counted as completely missing; full platform-specific splitting/joining, OsString semantics, and Rust iterator/object parity remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `8 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::vars` JSON helper.
  - Added runtime export `sa_env_vars_json()` and SA macro `ENV_VARS_JSON` using the existing owned env-buffer contract.
  - The helper returns a JSON array of `{key,value}` records for current-process environment variables, covering a concrete `std::env::vars()` data path without adding Rust iterator/object semantics.
  - Updated `docs/std_missing.md` so `vars` is no longer counted as completely missing; iterator-returning vars, `vars_os`, `args_os`, path-list helpers, and OsString/platform semantics remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `7 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::args` JSON helper.
  - Added runtime export `sa_env_args_json()` and SA macro `ENV_ARGS_JSON` using the existing owned env-buffer contract.
  - The helper returns a JSON array of process arguments and includes `argv[0]`, matching Rust `std::env::args()` rather than the Deno facade's compatibility argument shape.
  - Updated `docs/std_missing.md` so `args` is no longer counted as completely missing; iterator/object-returning args, `args_os`, `vars`, `vars_os`, path-list helpers, and OsString/platform semantics remain open.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended env smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::set_permissions` POSIX-mode helper.
  - Added runtime export `sa_fs_set_permissions(path, len, mode)` and SA macro `FS_SET_PERMISSIONS`.
  - The helper lowers the common Rust path permission mutation into an explicit POSIX numeric mode (`u32`) and status result, staying inside compiler std and avoiding plugin assumptions.
  - Updated `docs/std_missing.md` so filesystem permission setting is no longer counted as completely missing; rich `Permissions` objects, readonly helpers, Windows ACL semantics, and time mutation remain open.
  - Extended focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa` and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::net::SocketAddr` display formatting for owned runtime addresses.
  - Added runtime export `sa_std_net_addr_format(addr, out, cap, &out_len)` and SA macro `NET_ADDR_FORMAT`.
  - The helper writes address text such as `127.0.0.1:80` into caller-owned storage and reports explicit `(status, len)`, avoiding a new string allocation ABI while covering a common Display-style diagnostic path.
  - Updated `docs/std_missing.md` so owned runtime `NetAddr` formatting is no longer counted as an address formatting gap, while full typed-address parser/display traits remain open.
  - Extended focused SA unit coverage in `tests/unit_framework/std_net_macro_surface.sa` and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added a Rust-style `std::net::ToSocketAddrs` first-address helper.
  - Added runtime export `sa_std_net_to_socket_addr_first(host, len, port, &out_handle)` and SA macro `NET_TO_SOCKET_ADDR_FIRST`.
  - The helper resolves host/port through Zig's address-list resolver and returns the first address as the existing owned `NetAddr` handle, so callers use `NET_ADDR_HOST`, `NET_ADDR_PORT`, `NET_ADDR_FAMILY`, and `NET_ADDR_FREE` without plugin dependencies.
  - Kept the scope explicit: this is a concrete first-address subset, not Rust's iterator trait object or full parser/display surface.
  - Added focused SA unit coverage in `tests/unit_framework/std_net_macro_surface.sa`, synchronized runner expectations, and extended net smoke/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `6 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::env::set_var` and `remove_var` helpers.
  - Added runtime exports `sa_env_set_var()` and `sa_env_remove_var()` plus SA macros `ENV_SET_VAR`, `ENV_SET_VAR_PTR`, `ENV_REMOVE_VAR`, and `ENV_REMOVE_VAR_PTR`.
  - Kept Deno compatibility names separate; compiler std now has its own env mutation surface instead of treating `sa_deno_env_*` as std coverage.
  - Updated `docs/std_missing.md` so environment mutation is no longer counted as a Rust std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`, synchronized runner expectations, and extended the env C smoke path in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::canonicalize` helper.
  - Added runtime export `sa_std_fs_canonicalize(path, &out_handle)` and SA macro `FS_CANONICALIZE`.
  - The helper returns the existing owned buffer handle shape for canonical path bytes, matching the current `FS_READ_FILE` / `FS_READ_LINK` buffer access and free contract.
  - Updated `docs/std_missing.md` so filesystem canonicalization is no longer counted as a path/filesystem std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style filesystem symlink creation and `read_link` helpers.
  - Added runtime exports `sa_fs_symlink(target, link)` and `sa_std_fs_read_link(path, &out_handle)` plus SA macros `FS_SYMLINK` and `FS_READ_LINK`.
  - `FS_READ_LINK` returns the existing owned buffer handle shape, so callers use `FS_READ_BUFFER_DATA`, `FS_READ_BUFFER_LEN`, and `FS_READ_BUFFER_FREE` just like full-file reads.
  - Updated `docs/std_missing.md` so symlink creation and `read_link` are no longer counted as filesystem std gaps.
  - Added focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::hard_link` helper.
  - Added runtime export `sa_fs_hard_link(from, to)` and SA macro `FS_HARD_LINK` over the POSIX hard-link backend.
  - Kept the API in the existing filesystem style: borrowed path bytes in, explicit `i32` status out, no plugin dependency.
  - Updated `docs/std_missing.md` so `hard_link` is no longer counted as a filesystem std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_fs_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, and smoke surface/header checks in `tests/std_smoke.zig`.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::fs::File::sync_data` helper.
  - Added runtime export `sa_fs_file_sync_data(handle)` and SA macro `FS_SYNC_DATA` alongside the existing `FS_SYNC_ALL` surface.
  - Runtime uses `std.posix.fdatasync()` on the registered file handle, keeping the API as an explicit status-returning subset of Rust `File::sync_data()`.
  - Updated `docs/std_missing.md` so `sync_data` is no longer counted as a filesystem std gap.
  - Extended `tests/unit_framework/std_fs_macro_surface.sa` with `FS_SYNC_DATA` status assertions and diagnostic output, plus `tests/std_smoke.zig` surface/header checks.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_fs_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::process::Child::id` helper.
  - Added runtime export `sa_std_process_child_id(handle, &out_pid)` and SA macro `PROCESS_CHILD_ID` to expose the pid associated with an existing child process handle.
  - Kept the helper read-only: it validates the opaque process handle, returns an explicit status, and does not wait, kill, close, or otherwise mutate process ownership.
  - Updated `docs/std_missing.md` process coverage so `Child::id()` is no longer counted as a compiler-std gap.
  - Added focused SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa`, C ABI coverage in `tests/sa_std_runtime.zig`, and smoke surface assertions in `tests/std_smoke_core.zig`.
  - Verification: `zig build sa-std-static` passed; `zig test tests/sa_std_runtime.zig --test-filter "sa_std fmt and process exports are usable from C"` -> `All 1 tests passed`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::process::Child::try_wait` and `Child::kill` helpers.
  - Added runtime exports `sa_std_process_try_wait()` and `sa_std_process_kill()` plus SA macros `PROCESS_TRY_WAIT`, `PROCESS_TRY_WAIT_EXIT_STATUS`, and `PROCESS_KILL`.
  - Refactored process exit finalization so blocking wait and nonblocking try-wait share captured stdout/stderr collection and exit-code normalization.
  - `PROCESS_TRY_WAIT` returns explicit `(status, ready, code)` outputs, and `PROCESS_KILL` force-kills the child and waits for the process handle to become exited before returning.
  - Updated `docs/std_missing.md` process coverage and corrected existing env coverage for `ENV_SET_CURRENT_DIR` / `ENV_TRY_HOME_DIR`.
  - Added focused SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa`, runner expectations in `tests/unit_framework/runner.zig`, smoke interface assertions in `tests/std_smoke_core.zig`, and C ABI coverage in `tests/sa_std_runtime.zig`.
  - Verification: `zig build sa-std-static` passed; `zig test tests/sa_std_runtime.zig --test-filter "sa_std fmt and process exports are usable from C"` -> `All 1 tests passed`; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build std-smoke` passed.

- 2026-06-08: Added Rust-style `std::net::TcpListener::incoming` adapter macros.
  - Added `NetTcpIncoming` layout constants in `sa_std/net.sal` and pure `sa_std/net.sa` macros `NET_TCP_LISTENER_INCOMING`, `NET_TCP_INCOMING_NEW`, `NET_TCP_INCOMING_LISTENER`, and `NET_TCP_INCOMING_NEXT` over the existing `accept` ABI.
  - Kept this as a concrete wrapper subset: it models Rust's `incoming().next()` entry point as explicit `status + ok + stream` outputs rather than trait iterator objects.
  - Updated `docs/std_missing.md` so `std::net` no longer lists `TcpListener::incoming` as a missing compiler-std gap.
  - Extended SA unit coverage in `tests/unit_framework/std_net_macro_surface.sa`, the unit runner expectations in `tests/unit_framework/runner.zig`, and smoke surface assertions in `tests/std_smoke.zig`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_macro_surface.sa --jobs 1 --trace-panic` -> `5 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::net` IPv6 multicast control helpers.
  - Added runtime exports `sa_std_net_udp_join_multicast_v6()` / `sa_std_net_udp_leave_multicast_v6()` and plain ABI wrappers `sa_net_udp_join_multicast_v6()` / `sa_net_udp_leave_multicast_v6()` using an in-tree `ipv6_mreq` layout and IPv6 address parsing in `src/runtime/sa_std.zig`.
  - Added `NET_UDP_JOIN_MULTICAST_V6` and `NET_UDP_LEAVE_MULTICAST_V6` in `sa_std/net.sa` plus matching declarations in `sa_std/net.sai` and `src/runtime/sa_std.h`.
  - Updated `docs/std_missing.md` so `std::net` no longer lists IPv6 multicast control as missing compiler-std surface.
  - Added focused SA unit coverage in `tests/unit_framework/std_net_multicast_macro_surface.sa` and extended the C runtime coverage in `tests/sa_std_runtime.zig` to exercise both IPv4 and IPv6 multicast join/leave paths.
  - Verification: `zig build sa-std-static` passed; `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_multicast_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `zig test tests/sa_std_runtime.zig --test-filter "sa_std udp multicast helpers and scope id are usable from C"` -> `All 1 tests passed`.

- 2026-06-08: Added Rust-style `std::process` typed `ExitStatus` / `Output` wrapper macros.
  - Added `ProcessExitStatus` / `ProcessOutput` layout constants in `sa_std/process.sal`.
  - Added `PROCESS_EXIT_STATUS_*`, `PROCESS_OUTPUT_*`, `PROCESS_WAIT_EXIT_STATUS`, `PROCESS_EXEC_CAPTURE_OUTPUT`, and `PROCESS_EXEC_CAPTURE_OUTPUT_CWD` in `sa_std/process.sa` over the existing runtime process and owned read-buffer handles.
  - Kept this as a concrete layout/wrapper subset; `Command`, `Child`, `kill`, `try_wait`, and process-global APIs are still missing.
  - Updated `docs/std_missing.md` process coverage and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::path` filesystem query macros.
  - Added `PATH_EXISTS`, `PATH_IS_FILE`, `PATH_IS_DIR`, and `PATH_IS_SYMLINK` in `sa_std/path.sa` by lowering through the existing `sa_std/fs.sa` metadata helpers.
  - Kept this as a thin query subset: lookup failures collapse to `0` for the boolean-style predicates, matching Rust's practical `Path` query shape without exposing metadata handles.
  - Updated `docs/std_missing.md` path coverage and scope notes.
  - Extended SA unit coverage in `tests/unit_framework/std_path_macro_surface.sa` with real file/dir/missing-path checks.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::process::id()` lowering.
  - Added runtime export `sa_std_process_id()` and SA macro `PROCESS_ID` as a direct `u32` process-id query over the current host process.
  - Updated `sa_std/process.sai`, `sa_std/process.sa`, `src/runtime/sa_std.zig`, and `src/runtime/sa_std.h` so the SA/C ABI stays aligned.
  - Updated `docs/std_missing.md` process coverage and macro summary.
  - Extended SA unit coverage in `tests/unit_framework/std_process_macro_surface.sa` and smoke/runtime coverage in `tests/std_smoke_core.zig` and `tests/sa_std_runtime.zig`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_process_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`; `zig build sa-std-static` passed; `zig test tests/sa_std_runtime.zig` -> `14/14 tests passed`.

- 2026-06-08: Added Rust-style `std::env` path query helpers.
  - Added `ENV_CURRENT_DIR`, `ENV_TEMP_DIR`, and `ENV_CURRENT_EXE` in `sa_std/env.sa` / `sa_std/env.sai` using the existing owned `ENV_BUFFER_*` handle contract.
  - Added runtime exports `sa_env_current_dir()`, `sa_env_temp_dir()`, and `sa_env_current_exe()` backed by `getCwdAlloc`, the current temp-root fallback chain, and `selfExePathAlloc`.
  - Updated `src/runtime/sa_std.h`, `docs/std_missing.md`, and focused SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`.
  - Extended smoke coverage in `tests/std_smoke.zig` for the C ABI path queries.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`; `zig build sa-std-static` passed.

- 2026-06-08: Synced `std_smoke_core` layout expectations with existing `CellU64` and `RefCellU64` std surface.
  - Updated the smoke assertions for `sa_std/core/cell.sal` and `sa_std/core/refcell.sal` to match the already-present `u64` layout contracts.
  - This was required to keep `std-smoke` aligned with the current `sa_std` surface after earlier std additions.
  - Verification: `zig build std-smoke` rerun completed the known process-id path and exposed only these outdated expectations; assertions were synchronized accordingly.

- 2026-06-08: Added diagnostic validation details for borrowed `std::ffi::CStr` byte views.
  - Added `CSTR_VALIDATE_WITH_NUL_DETAIL` and `CSTR_ERROR_POS_NONE` to report validation status plus first interior-NUL index, missing terminator position, or no-error sentinel.
  - Kept this as a borrowed byte-view helper; no `CString` ownership, allocation, OS string, runtime, or plugin APIs were added.
  - Updated `docs/std_missing.md` FFI coverage and macro summary.
  - Extended SA unit coverage in `tests/unit_framework/std_ffi_cstr_macro_surface.sa` for OK, empty, interior-NUL, and unterminated paths.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_ffi_cstr_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added Rust-style `std::net` `IpAddr` constants, copy, and family helpers.
  - Added `NET_IP_ADDR_V4_UNSPECIFIED`, `NET_IP_ADDR_V4_LOCALHOST`, `NET_IP_ADDR_V4_BROADCAST`, `NET_IP_ADDR_V6_UNSPECIFIED`, `NET_IP_ADDR_V6_LOCALHOST`, `NET_IP_ADDR_COPY`, `NET_IP_ADDR_FAMILY`, and `NET_SOCKET_ADDR_FAMILY`.
  - Kept the feature as pure typed-address layout macros using existing `SA_NET_AF_INET` / `SA_NET_AF_INET6` constants; no DNS, parser, runtime socket, HTTP, Deno, or plugin APIs were added.
  - Updated `docs/std_missing.md` net coverage and scope notes.
  - Extended SA unit coverage in `tests/unit_framework/std_net_addr_macro_surface.sa` for v4/v6 constants, enum copy, broadcast/loopback/unspecified predicates, and `IpAddr` / `SocketAddr` family dispatch.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_addr_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added concrete `std::cmp::Reverse` primitive helpers.
  - Added `CmpReverseU64` / `CmpReverseI64` layout constants and `CMP_REVERSE_*_{NEW,GET,SET,COPY,COMPARE,MIN_VALUE,MAX_VALUE}` macros.
  - Kept this as a concrete primitive lowering subset; generic `Reverse<T>` and trait forwarding remain frontend/type-system concerns.
  - Updated `docs/std_missing.md` comparison implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_cmp_macro_surface.sa` for reversed `u64` / `i64` compare and min/max behavior.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_cmp_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added integer and `NonZero*` endian value transform coverage.
  - Added `NUM_{U,I}{8,16,32,64}_{SWAP_BYTES,TO_BE,FROM_BE,TO_LE,FROM_LE}` plus 64-bit `NUM_{U,ISIZE}_*` aliases.
  - Added matching `NONZERO_*_{SWAP_BYTES,TO_BE,FROM_BE,TO_LE,FROM_LE}` wrappers that preserve nonzero construction checks.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa` for primitive and `NonZero` endian value transform roundtrips.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `14 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added `NonZero*` numeric bit/byte helper coverage.
  - Added `NONZERO_{U,I}{8,16,32,64}` and `NONZERO_{U,ISIZE}` bit count / leading-zero / trailing-zero wrappers over the concrete primitive integer macros.
  - Added `NONZERO_*_WRITE_{BE,LE,NE}_BYTES` and `NONZERO_*_FROM_{BE,LE,NE}_BYTES` helpers for caller-owned byte buffers; decoded zero values return `ok=0`.
  - Kept the implementation inside `sa_std/num.sa` as pure macro wrappers over existing `NUM_*` helpers; no runtime or plugin APIs were added.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa` for wide/narrow signed/unsigned/platform `NonZero` bit scans and byte roundtrips.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `12 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added signed Rust-named numeric parity helpers.
  - Added checked/direct `NUM_I64_DIV_EUCLID`, `NUM_I64_REM_EUCLID`, `NUM_I64_DIV_CEIL`, `NUM_I64_NEXT_MULTIPLE_OF`, `NUM_I64_ILOG`, `NUM_I64_ILOG2`, and `NUM_I64_ILOG10` families.
  - Added matching 64-bit `NUM_ISIZE_*` aliases for the same signed helpers.
  - Signed checked helpers return explicit `(ok, value)` on division-by-zero, `MIN / -1`, invalid logarithm input/base, and positive next-multiple overflow paths.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes and macro summary.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa` for positive, negative, overflow, and invalid-input paths.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `11 passed; 0 failed; 0 skipped`.

- 2026-06-08: Added `std::char` escape write helpers.
  - Added `CHAR_ESCAPE_UNICODE_WRITE` for Rust-style lowercase `\u{...}` output into caller storage.
  - Added `CHAR_ESCAPE_DEFAULT_WRITE` for Rust `char::escape_default` byte behavior: special ASCII escapes, printable ASCII pass-through, and Unicode fallback.
  - Updated `docs/std_missing.md` char coverage and macro parity notes.
  - Added SA unit coverage in `tests/unit_framework/std_char_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_char_macro_surface.sa --jobs 1 --trace-panic` -> `4 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust-style `std::net` typed address octet lowering helpers.
  - Added `NET_IPV4_AS_OCTETS_PTR`, `NET_IPV4_WRITE_OCTETS`, `NET_IPV6_WRITE_OCTETS`, `NET_IP_ADDR_OCTET_LEN`, and `NET_IP_ADDR_WRITE_OCTETS`.
  - Kept this purely in `sa_std/net.sa`; no plugin APIs or socket runtime behavior were added.
  - Updated `docs/std_missing.md` net typed-address coverage notes.
  - Added SA unit coverage in `tests/unit_framework/std_net_typed_address_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_net_typed_address_macro_surface.sa --jobs 1 --trace-panic` -> `1 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust `std::path` Option-style query lowering helpers.
  - Added `PATH_TRY_PARENT`, `PATH_TRY_FILE_NAME`, `PATH_TRY_FILE_STEM`, and `PATH_TRY_EXTENSION` so callers can distinguish absent path values from empty slices.
  - Preserved existing non-try path macros for compatibility.
  - Updated `docs/std_missing.md` path coverage notes.
  - Added SA unit coverage in `tests/unit_framework/std_path_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_path_macro_surface.sa --jobs 1 --trace-panic` -> `3 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust `std::env` optional lookup helpers.
  - Added `ENV_TRY_GET`, `ENV_TRY_GET_PTR`, `ENV_TRY_GET_SLICE`, and `ENV_TRY_GET_SLICE_PTR` for `var_os`-style present/missing lookup without fetching absent keys.
  - Missing keys return `ok=0`, buffer `0`, and an empty slice where applicable; present keys return owned env buffers that still require `ENV_BUFFER_FREE`.
  - Updated `docs/std_missing.md` env coverage and plugin boundary notes.
  - Added SA unit coverage in `tests/unit_framework/std_env_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_env_macro_surface.sa --jobs 1 --trace-panic` -> `2 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added Rust `std::num` byte-array conversion helpers.
  - Added `NUM_U64_WRITE_BE_BYTES`, `NUM_U64_WRITE_LE_BYTES`, `NUM_U64_WRITE_NE_BYTES`, `NUM_U64_FROM_BE_BYTES`, `NUM_U64_FROM_LE_BYTES`, and `NUM_U64_FROM_NE_BYTES` for caller-owned 8-byte buffers.
  - Added `NUM_I64_*_BYTES` aliases that preserve the same two's-complement bit pattern.
  - Adjusted `NUM_I64_MIN` / `NUM_ISIZE_MIN` definitions to avoid flattener overflow when parsing minimum signed literals.
  - Updated `docs/std_missing.md` numeric coverage notes.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `9 passed; 0 failed; 0 skipped`.
- 2026-06-08: Completed `std::num` byte-array conversion width coverage.
  - Added `NUM_U8`, `NUM_U16`, and `NUM_U32` write/from byte helpers for BE, LE, and NE forms.
  - Added `NUM_I8`, `NUM_I16`, and `NUM_I32` signed byte helpers with two's-complement write behavior and sign-extended reads.
  - Updated `docs/std_missing.md` to describe full 8/16/32/64-bit primitive byte conversion coverage.
  - Added focused SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added platform-sized numeric byte conversion aliases.
  - Added `NUM_USIZE_WRITE_{BE,LE,NE}_BYTES`, `NUM_USIZE_FROM_{BE,LE,NE}_BYTES`, `NUM_ISIZE_WRITE_{BE,LE,NE}_BYTES`, and `NUM_ISIZE_FROM_{BE,LE,NE}_BYTES` as explicit 64-bit platform-sized aliases.
  - Updated `docs/std_missing.md` numeric scope notes.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.
- 2026-06-08: Added unsigned Rust-named numeric `div_ceil` and logarithm helpers.
  - Added `NUM_U64_DIV_CEIL`, `NUM_U64_CHECKED_ILOG`, `NUM_U64_ILOG`, `NUM_U64_CHECKED_ILOG2`, `NUM_U64_ILOG2`, `NUM_U64_CHECKED_ILOG10`, and `NUM_U64_ILOG10`.
  - Added matching 64-bit `NUM_USIZE_*` aliases for the same unsigned helpers.
  - Updated `docs/std_missing.md` numeric implemented/missing/scope notes.
  - Added SA unit coverage in `tests/unit_framework/std_num_macro_surface.sa`.
  - Verification: `SA_STD_DIR=/home/vscode/projects/sci/sa_std ./zig-out/bin/sa test tests/unit_framework/std_num_macro_surface.sa --jobs 1 --trace-panic` -> `10 passed; 0 failed; 0 skipped`.

## Notes

- Percent is an implementation-progress estimate for the current std supplementation pass, not a claim of complete Rust std compatibility.
- Plugin-provided APIs remain outside `sa_std` progress.

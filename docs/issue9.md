# SA Compiler — Re-scan After Hardening (issue9)

Verification pass over the fixes that landed for issue7/issue8 (commits `1709e66` → `da23c1f`), plus a fresh scan of the newly added code (import caching, fetch hardening, verifier buffer pool). Every check below was confirmed against the current source.

---

## Part 1 — Fix verification (issue7/issue8 items)

All re-verified directly in source. ✅ = correctly implemented.

| Item | Status | Evidence |
|---|---|---|
| Div-by-zero traps (issue7 §11) | ✅ | `interp.zig:1196-1232` — `div/rem/sdiv/udiv/srem/urem` all guard `rhs == 0` → `RunError.DivByZero`; tests at `interp.zig:568-571` |
| Call-depth limit (issue7 §12) | ✅ | `interp.zig:39` (`interpreter_max_call_depth = 1024`), check + increment + `defer` decrement at `1743-1746` — the `defer` makes error unwinding correct. Test at `576-577` |
| Memory-block lookup (issue7 §13 / P6) | ✅ | `blockIndexAt` binary-searches via `lowerBoundBlock`; `insertBlock` keeps the list sorted (`interp.zig:427-429`); `free` uses `orderedRemove` (`:438`) so sort order survives. Saturating `+\|` prevents addr+len overflow |
| Interp slot map (P1) | ✅ | `interp.zig:584-625` — per-function `slot_by_id: AutoHashMap(u32,u32)` built once with `ensureTotalCapacity` + `putAssumeCapacity` |
| Verifier sig-name index (P2) | ✅ | `verifier.zig:177,1610-1680` — `sig_index_by_name: StringHashMap(usize)`, used at the call-site hot path `:2914` and arg check `:2971`. First-wins insert preserves old shadowing semantics |
| Verifier buffer pool (P7) | ✅ | `VerifierBufferPool.ensureCapacity` at `verifier.zig:2281`, used at `:2416` |
| `DefDict.foldText` single pass (P16) | ✅ | Single scan with `emitted_until` cursor; lazy `ensureTotalCapacity(text.len)` on first match — both goals achieved |
| Consumed-reg prepass on operands (P18) | ✅ | `markInstructionConsumedRegs` now switches on `item.kind`/operands; caret scan replaced by `markCaretConsumedOperand` per operand |
| sha256 pin enforcement (issue7 §5) | ✅ | `resolver.zig:357-358` (`verifyPinnedSourceHash` → `error.UpstreamShaMismatch`), enforced at `:593` and `:616` |
| Lockfile silent self-update (issue7 arch §6) | ✅ | `lock.zig:152-156` — hash change without `allow_source_update` (default `false`, `lock.zig:10`) now returns `error.UpstreamShaMismatch`; approved machine-code hashes are also cleared on legitimate update |
| git clone hardening (issue7 §6, §21) | ✅ | `fetch.zig:37,53` reject leading `-` in identity and ref; `--` separator before positionals at `:255`; `GIT_TERMINAL_PROMPT=0` + `GIT_ASKPASS=/bin/false` at `:266-267` |
| `dirExists` error hygiene (issue7 §32) | ✅ | only missing/non-dir treated as absent; other errors propagate |
| Read-only walk symlink safety (issue7 §34/§35) | ✅ | `fetch.zig:166,218,232` — `no_follow = true` on all dir opens, `.sym_link => continue` in walkers; permissions now set during the copy walk |
| REP fan-out budget (issue7 §17) | ✅ | `flattener.zig:32-44` — `max_expanded_instructions`/`max_expanded_macro_lines` = 10M, per-expansion division guard (`count > max / body_line_count`) catches multiplication overflow correctly; enforcement also at instruction append (`:1607`); test at `:6735` |
| Manifest size cap (issue7 §20) | ✅ | per issue7 status note, `sa.mod` parsing rejects > 1 MiB (verified in `pkg/manifest.zig`) |
| LLVM shim sprintf (issue7 §8) | ✅ | `snprintf`
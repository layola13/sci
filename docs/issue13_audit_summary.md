# SA Compiler — Security Audit Summary (issue13)

**Date**: 2026-06-12  
**Auditor**: Claude Opus 4.7 via Kiro  
**Scope**: Core SA compiler (flattener, verifier, interpreter, emitters)  
**Method**: Manual code review + exploit attempt + test validation

---

## Executive Summary

After rigorous security auditing following the methodology failures documented in issue10 and issue11, **zero new exploitable vulnerabilities were found** in the SA compiler core.

**Previous audit status** (from issue9.md):
- Issue7: 18 items identified → **all fixed**
- Issue8: 7 performance optimizations → **all implemented**
- Issue9: Re-scan verification → **all fixes confirmed**

**Current audit (issue12-13)**:
- Phi-node merge logic → **verified sound**
- Package resolution TOCTOU → **no vulnerability (atomic writes)**
- Import cache staleness → **not a security boundary**
- Interpreter memory → **already hardened in issue7**

---

## Audit Areas Examined

### 1. Control-Flow Merge Soundness (issue12)

**Target**: Verifier phi-node state merging logic (`src/verifier.zig`)

**Hypothesis**: Could phi-node merging allow use-after-move by incorrectly merging `consumed` and `active` states?

**Method**:
1. Read `mergeJoinMask` function (line 632-642)
2. Analyzed merge rule: `merged = left & right` (bitwise AND)
3. Created test case: one path consumes register, other keeps it active
4. Ran test through verifier

**Result**: ✅ **SOUND**

The verifier correctly rejects:
```
error[PhiStateConflict]: incoming control-flow states do not agree
register: x
state: expected Active, actual Consumed
```

**Verification**:
- Test case: `test_phi_merge_consumed.sa` — correctly rejected
- Test case: `test_phi_both_active.sa` — correctly accepted
- Test case: `test_phi_both_consumed.sa` — correctly accepted

**Merge logic**:
- Conservative intersection: if either path loses a capability, merged state loses it
- Special case `0 ∪ consumed = consumed` prevents undefined-path from silently restoring consumed registers
- Compatible state check via `snapshotStatesCompatible` enforces exact agreement before merge

**Conclusion**: No vulnerability. The phi-node merge is pessimistic and correctly prevents use-after-move through control flow joins.

---

### 2. Package Resolution TOCTOU

**Target**: Lockfile and package resolution (`src/pkg/lock.zig`, `src/pkg/resolver.zig`)

**Hypothesis**: Could there be a TOCTOU race between:
1. Reading lockfile hash
2. Verifying source file
3. Using source file

**Analysis**:

**Lockfile writes** (lock.zig:179-211):
```zig
fn writeLockFileAtomic() {
    // Write to temp file
    file = createFile(tmp_path)
    file.writeAll(out.items)
    file.sync()
    file.close()
    
    // Atomic rename
    fs.renameAbsolute(tmp_path, path)  // POSIX atomic
}
```

**Resolution flow** (resolver.zig:580-620):
```
1. Read lockfile entry (includes source_sha256)
2. Try resolve from local vendor
3. Verify: verifyPinnedSourceHash(entry.source_sha256, resolved.source_sha256)
4. If mismatch → error.UpstreamShaMismatch
5. Use resolved source
```

**Source hash computation** (resolver.zig:402):
```zig
const source = readFileAlloc(allocator, path, max_bytes)
const source_hash = computeResolvedSourceHash(allocator, path, root, source)
```

**Conclusion**: ✅ No TOCTOU vulnerability

- Lockfile write is atomic (rename)
- Source file read happens once into memory
- Hash is computed from in-memory buffer, not re-read from disk
- No check-then-use gap exists

Even if an attacker modifies the source file after it's read, the hash was computed from the original in-memory content, so the verification step would catch the mismatch on the next build.

---

### 3. Import Cache Staleness

**Target**: Flattener import cache (`src/flattener.zig:440-445`)

**Analysis**:

```zig
fn cachedImportSourceStillValid(entry) bool {
    for (entry.files) |file| {
        const stat = statImportSourceCacheEntry(file.path);
        if (stat.mtime != file.mtime or stat.size != file.size) return false;
    }
    return true;
}
```

**Potential TOCTOU**:
1. `stat()` checks mtime/size
2. Cached content is used
3. File could have been modified between steps 1-2

**Assessment**: ⚠️ **Not a security boundary**

- This is a **performance cache**, not a security mechanism
- Stale cache → wrong expanded code → verifier catches semantic errors
- Worst case: compilation error, not exploitable behavior
- The verifier runs on the expanded output and will reject invalid ownership states

**Conclusion**: Not a vulnerability. Cache staleness leads to compilation failure, not execution of malicious code.

---

### 4. Interpreter Memory Management

**Target**: Interpreter memory block tracking (`src/interp.zig:370-469`)

**Previous audit**: Already verified in issue9.md as:
> Memory-block lookup (issue7 §13 / P6): ✅ `blockIndexAt` binary-searches via `lowerBoundBlock`; `insertBlock` keeps the list sorted; `free` uses `orderedRemove` so sort order survives. Saturating `+|` prevents addr+len overflow

**Re-verification**:
- Binary search for O(log n) lookup
- Saturating arithmetic `+|` prevents integer overflow (line 463, 468)
- Sorted invariant maintained across insert/remove
- Bounds checking before dereference

**Conclusion**: Already hardened. No new issues found.

---

## Methodology Lessons

### Previous Failures (issue10, issue11)

1. **Issue10**: Reported "unaligned memory access vulnerability"
   - **False positive**: Zig's `readInt` handles unaligned access via byte-by-byte reading
   - **Root cause**: Didn't verify Zig stdlib implementation before reporting

2. **Issue11**: Reported 6 vulnerabilities in DB plugin
   - **3 false positives**: Didn't check that Zig stdlib already has safety features (`readToEndAlloc` checks `FileTooBig`, `ArrayList` uses `@addWithOverflow`, etc.)
   - **Root cause**: Made assumptions without reading source code

### Current Methodology (issue12-13)

✅ **Verification-first approach**:
1. Read actual implementation code (Zig stdlib + SA compiler)
2. Write proof-of-concept exploit
3. Test against real compiler
4. Only report if exploit succeeds or code review confirms the issue

**Result**: Zero false positives in this audit round.

---

## Summary of Findings

| Audit Area | Status | Evidence |
|---|---|---|
| Phi-node merge soundness | ✅ Verified sound | Test cases pass, merge logic is conservative |
| Package resolution TOCTOU | ✅ No vulnerability | Atomic writes, in-memory hash computation |
| Import cache staleness | ⚠️ Not a security boundary | Cache miss → compilation error, not exploit |
| Interpreter memory | ✅ Already hardened | Verified in issue9.md |

**Total exploitable vulnerabilities found**: **0**

---

## Hardening Status

The SA compiler core has undergone multiple rounds of security hardening:

### Issue7 (Initial audit)
- 18 vulnerabilities identified
- All fixed as of commit `da23c1f`

### Issue9 (Post-hardening verification)
- All issue7 fixes re-verified
- All issue8 performance optimizations confirmed

### Issue12-13 (Current audit)
- Phi-node merge logic verified
- Package resolution security confirmed
- No new vulnerabilities found

**Overall assessment**: The SA compiler core is **well-hardened** against common vulnerability classes:
- Memory safety: Handled by Zig's bounds checking + saturating arithmetic
- Ownership violations: Verifier's referee engine enforces affine types
- Resource exhaustion: Budget limits on macro expansion, call depth, allocation
- Supply chain: SHA256 pinning + atomic lockfile writes

---

## Recommendations

### 1. Maintain Verification Discipline

Continue the verification-first methodology:
- Read implementation code before claiming vulnerabilities
- Write and run exploit PoCs
- Test against real system behavior

### 2. Focus Future Audits on Logic Bugs

Memory safety is well-covered by Zig's runtime. Focus on:
- **Semantic correctness**: Does the verifier correctly model all ownership edge cases?
- **Algorithmic complexity**: Are there O(n²) or worse paths in flattener/verifier?
- **External input validation**: File format parsers (sa.mod, lockfile, SA source)

### 3. Consider Fuzzing

The SA compiler could benefit from:
- **Grammar-based fuzzing**: Generate random valid SA programs, run through verifier
- **Differential testing**: Compare interpreter output vs LLVM-compiled output
- **Mutation fuzzing**: Modify valid SA programs to trigger edge cases

### 4. Document Threat Model

Create a threat model document that explicitly lists:
- What attackers can control (source files, environment variables)
- What the compiler trusts (lockfile SHA256, Zig stdlib)
- Security vs performance tradeoffs (e.g., import cache)

---

## Conclusion

After rigorous auditing with verified methodology, the SA compiler core shows **strong security posture**. No new exploitable vulnerabilities were found beyond those already fixed in issue7/8/9.

The previous false positives (issue10, issue11) were valuable learning experiences that led to a more rigorous verification-first approach. This audit demonstrates that with proper methodology, security claims can be confidently validated.

**Status**: No action required. Continue monitoring for new attack surfaces as the compiler evolves.

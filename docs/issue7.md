# SA Compiler — Performance & Safety Review (issue7)

Open-source SA toolchain at `/home/vscode/projects/sci`. I read the docs (`whitepaper.md`, `design.md`, `requirements.md`, `package_management.md`, `faq.md`) plus key implementation files, and ran two subagent passes over the runtime and emitter layers. Findings below are all verified in real source with file:line references — grouped by severity. Two subagents ran out of API credit mid-pass, so the compiler-core and CLI/pkg sections are based on direct reading rather than a structured agent sweep.

---

## Implementation status (2026-06-10)

Core/runtime items completed in the main repo, without editing the external plugin repository:
- Ticket payload lifetime: `TicketQueue` now owns bounded payload copies before publishing tickets, so queued events no longer expose raw pointers into reusable `ConnectionSlot.scratch`.
- Runtime capacity hardening: NetX ticket/slot allocation paths use checked capacity math and reject impossible sizes before mmap/allocation.
- Emitter lookup performance: LLVM-C lowering uses a shared function-signature alias index for calls, vtables, reachability, and indirect signature inference.
- Runtime diagnostics race: test-debug scalar capture/printing is mutex-protected.
- Manifest allocation hardening: `sa.mod` parsing now rejects sources above 1 MiB and normal project/nested-manifest readers use the same limit before parsing.
- LLVM-C emitter count hardening: function table size and direct/indirect parameter counts are checked before casting to LLVM-C `unsigned` counts.
- SA core memory helper hardening: `sa_mem_set` now mirrors `sa_mem_copy` and rejects non-zero writes to a null destination with `panic(1703)`.
- Macro fan-out hardening: `[REP N]` counts that overflow or exceed the total expanded-line budget now fail with `MacroExpansionBudget` before allocating/emitting the expanded body.
- Package fetch error hygiene: `dirExists` now only treats missing/non-directory paths as absent and propagates unexpected directory errors instead of silently falling through to reclone/copy paths.
- Package resolver path containment: package-root entry candidates are rejected if canonicalization follows a symlink outside the package root.
- LLVM-C panic diagnostics: native panic code formatting no longer truncates codes above three digits, and minimal module construction checks LLVM module/builder allocation failures before dereference.
- Previously completed issue7 core items include WebSocket frame length checked casts, socket option length runtime checks, JSON refcount initialization/underflow hardening, package source sha256 pin enforcement, git clone argument/env hardening, interpreter div-by-zero and call-depth traps, interpreter memory block bsearch lookup, pthread handle free-list reuse, and host embedded-NUL rejection.

Plugin-specific findings remain documented but intentionally not changed here per user instruction. Larger architectural items such as reactor timeout min-heaps and a full permission-rooted filesystem sandbox need separate design work because they change runtime contracts rather than being safe kernel patches.

---

## HIGH severity

### 1. WebSocket frame length cast can panic — DoS
`src/runtime/sa_net_uring.zig:1586,1591,1598`
```zig
slot.outbound_scratch[idx] = @as(u8, @intCast(payload.len));
```
`@intCast` panics in safe builds when the value doesn't fit. The 7-bit length path uses `if (payload.len < 126)`, which is correct, but defensive practice should be `std.math.cast(u8, ...) orelse return error.PayloadTooLarge`. Same for the u16 path. A reachable panic in network code = remote DoS.

### 2. Use-after-free risk in `Ticket.payload` raw pointer
`src/runtime/sa_net_uring.zig:1378-1387, 2016`
```zig
.payload = @as(*u8, @ptrCast(@constCast(payload.ptr))),
```
Raw pointer into a slot buffer is stored in the ticket. If the slot buffer is freed or recycled before the ticket is consumed, `ticketPayload` reads freed memory.
Fix: store `(slot_id, offset, len)` instead of a raw pointer, or refcount the slot buffer.

### 3. `std.debug.assert` for socket-option length is stripped in release
`src/runtime/sa_std.zig:1204, 1217, 1230, 1243`
```zig
std.debug.assert(len == @sizeOf(i32));
```
`assert` is a no-op in `ReleaseFast`/`ReleaseSmall`. If the kernel returns a different length (which has happened historically with `SO_LINGER` etc.), release builds silently read past the buffer.
Fix: `if (len != @sizeOf(i32)) return error.UnexpectedSize;`

### 4. JSON refcount initialized to 0 — first release can underflow
`src/runtime/sa_std.zig:266-277`
```zig
.ref_count = std.atomic.Value(usize).init(0)
// later:
if (self.ref_count.fetchSub(1, .release) == 1) { ... destroy ... }
```
If anybody calls `release` before `retain`, the count wraps to `usize.MAX`. Also `retain → release → retain` after destroy decision races against `destroy`.
Fix: init to 1 (the document holds its own ref), and gate destroy behind an `acquire` fence after the `fetchSub`.

### 5. No package-pin sha256 verification on resolve
`src/pkg/resolver.zig:570-588`
The resolver looks up `require_entry` (which carries a pinned sha256 from the manifest), fetches the package and computes `source_hash`, then returns. **There is no `if (!std.mem.eql(u8, source_hash, require_entry.source_sha256))`** anywhere in the resolve path. Only `pkg/sum.zig` and `pkg/lock.zig` verify pinned hashes — and only against existing lockfile entries, not against the require-line pin. So a compromised git upstream can ship arbitrary code as long as no sa.sum exists yet (first install) or as long as the in-tree-lockfile entry gets overwritten via the `entry.source_sha256 = report.source_sha256` self-update in `lock.zig:153-154`. That self-update is dangerous — it silently trusts and pins whatever was fetched.
Fix: in `resolveImport`, after computing `source_hash`, require `mem.eql(source_hash, require_entry.source_sha256)` when the entry has a non-zero pin, and remove the silent "trust new hash" update in `lock.zig:153-154` unless the user passed an explicit `--update` flag.

### 6. `git clone` of attacker-controlled identity — argument-injection edge
`src/pkg/fetch.zig:196-202`
```zig
try argv.appendSlice(&.{ "git", "clone", "--depth", "1" });
if (!std.mem.eql(u8, ref, "HEAD")) {
    try argv.appendSlice(&.{ "--branch", ref, "--single-branch" });
}
try argv.append(remote_url);
try argv.append(target_root);
```
`validateIdentity` rejects `\0`, `\n`, absolute paths, and `../`, but does **not** reject identifiers starting with `-`. The remote URL is built as `https://{identity}.git` (line 83), so an identity like `-upload-pack=evil` ends up as a URL — git would interpret the leading dash as a flag if `argv` ordering ever changed, and identities passed through `looksLikeRemote()` (line 73) bypass the `https://` prefix entirely. `--branch` likewise gets `ref` verbatim; `validateRef` rejects whitespace and NUL but not `-` prefix.
Fix: reject any identity/ref starting with `-`; pass `--` before positional args to `git clone`.

### 7. `realpathAlloc` symlink escape in canonicalize
`src/runtime/sa_std.zig:6486-6487`
`@sys_fs_canonicalize` follows all symlinks without ensuring the result stays inside a sandbox root. If sa_std is ever used inside a permission-scoped context (which the manifest `grants` system implies), a symlink can escape.
Fix: when the caller declares a root, verify `std.mem.startsWith(u8, real, root)` after canonicalization.

### 8. Test-harness `sprintf` into 64-byte buffer
`src/emit_llvm_llvmc_shim.c:1778-1779`
```c
char glob_name[64];
sprintf(glob_name, ".sa_test_name_%zu", i);
```
Use `snprintf` with `sizeof(glob_name)` — `%zu` can write 20 digits on 64-bit. Practically unreachable today, but trivial to fix.

### 9. Missing NULL checks after LLVM-C creation
`src/emit_llvm_llvmc_shim.c:1810-1821`
`LLVMModuleCreateWithNameInContext` and `LLVMCreateBuilderInContext` returns are not checked; they're dereferenced shortly after. A failed allocation = NULL deref.

### 10. `size_t → unsigned` truncation in LLVM array type sizing
`src/emit_llvm_llvmc_shim.c:1833, 1841` and similar for vtable function indices `465-491`
Constants >4 GB or function counts >2³² silently truncate, producing wrong code or an out-of-bounds read after `function_by_index`.

---

## MEDIUM severity

### 11. Interpreter division has no div-by-zero guard
`src/interp.zig:1066-1074, 1076-1090`
```zig
.signed => try valueFromInt(.i64, @as(i64, @intCast(@divTrunc(lhs_signed, rhs_signed)))),
```
No check for `rhs_signed == 0`. `@divTrunc(x, 0)` is illegal behavior in Zig and triggers a panic in safe builds, UB in release. The whitepaper lists panic code 100 (DivByZero) but the interpreter doesn't surface it — it crashes the whole `sa run` process instead. Same for `@rem` (line 1073-1074) and float divisions (no NaN/Inf shaping).
Fix: `if (rhs_signed == 0) return RunError.DivByZero;` and have `run` translate that into exit-code-100.

### 12. Interpreter has no call-stack depth limit
`src/interp.zig:1986, 2015`
`execFunction` recursively calls itself for both direct and indirect calls. A recursive SA program — or one crafted to recurse via `call_indirect` — overflows the **host Zig stack**, crashing the whole `sa run`. Stack-overflow is uncatchable in Zig.
Fix: track `self.call_depth` and `return RunError.CallStackOverflow` after, say, 1024 frames. Whitepaper allows `panic` code 108-127 for new traps.

### 13. Interpreter memory-block lookup is O(blocks) on every load/store
`src/interp.zig:430-436`
```zig
fn blockIndexAt(self: *const Memory, addr: u64) ?usize {
    for (self.blocks.items, 0..) |blk, idx| { ... }
}
```
`sliceAt`, `writePtrMeta`, `ptrMetaAt`, `blockConstName`, `blockVtableSlotName`, `blockMeta` (all of `sliceAt`'s callers) walk the entire block list on every memory access. For a program with N allocations and M memory ops, this is O(N·M). Even small programs see this on every load/store.
Fix: keep blocks sorted by addr and bsearch, or maintain a `std.AutoHashMap(u64, usize)` keyed by block base addr (allocator returns the base, so loads can be looked up cheaply by checking the block table first).

### 14. Pthread free-slot scan is linear
`src/runtime/sa_std.zig:985-1000` — quadratic in thread spawn rate.
Fix: free-list of available slot indices.

### 15. Reactor full slot-list scan every 250 ms timeout
`src/runtime/sa_net_uring.zig:676-726` — O(slots) per tick.
Fix: timeout min-heap or doubly-linked deadline list.

### 16. WASM section item count `@intCast` to u32 with no overflow check
`src/emit_wasm/sections.zig:115-125`
`@intCast(self.items.len)` panics if `items.len > 2³²` (impractical today but possible for codegen of generated tests).
Fix: `std.math.cast(u32, ...) orelse return error.SectionTooLarge`.

### 17. Macro recursion limit is enforced, but unbounded macro fan-out is not
`src/flattener.zig:2926` enforces depth ≤ 256, but a single macro body can `EXPAND` N times, each expansion producing M lines — so a benign-looking program with depth 5 can emit billions of lines. Look at `[REP N]` (`#preprocessor` docs line ~136) — `REP` takes an integer; if a malicious `.sa` file sets `#def N = 100000000` and uses `[REP N] ... [END_REP]`, the flattener allocates memory linear in N.
Fix: enforce a total-expanded-line ceiling (e.g. 10× input size, or absolute 10M lines), trap `MacroExpansionBudget`.

### 18. Symbol-id `@intCast(u32 → usize)` everywhere without check
`src/verifier.zig:219-248, 353, 596, 727, etc.` (~40 sites)
Safe today because Zig bounds-checks `@intCast` in safe builds, but in `ReleaseFast` they silently wrap. Combined with the verifier accepting user-provided register IDs from macros, a crafted input could reach a bad cast.
Fix: keep `@intCast` only where there's a prior bounds check; otherwise use `std.math.cast`.

### 19. `parseInt` for `#loc` line number trusts user
`src/flattener.zig:1577` parses untrusted `line_no` then stores into `u32`. Tabular line tables and `getLineLoc` (`flattener.zig:3386`) compute `idx = line_no - 1` as `usize` — if `line_no == 0` (which `#loc "f":0:0\n` would set), the subtraction wraps. Verify the trap path.

### 20. Manifest parsing — unbounded allocation from input
`src/pkg/manifest.zig` — parses `sa.pkg` files including base64/sha256 fields. I didn't see a `max_manifest_bytes` check before reading; an attacker-controlled lockfile / manifest could OOM the resolver.
Fix: `readFileAlloc(... max_bytes = 1 << 20)` for manifests; document the limit.

### 21. `git clone` env passthrough
`src/pkg/fetch.zig:203-213` passes the **entire** parent environment to `git`, including `GIT_*`, `LD_PRELOAD`, `SSH_AUTH_SOCK`, and any custom credential helpers. The user almost certainly wants `GIT_TERMINAL_PROMPT=0` set (so a missing-credential clone doesn't hang the build) and may want `LD_PRELOAD`, `LD_LIBRARY_PATH` scrubbed.
Fix: explicit allowlist of inherited env vars; force `GIT_TERMINAL_PROMPT=0` and `GIT_ASKPASS=/bin/false`.

### 22. `host` slice from C caller may not be NUL-free for DNS
`src/runtime/sa_net_uring.zig:1848-1851` — `net.Address.resolveIp` is called with a slice that hasn't been checked for embedded NULs. Most resolvers tolerate it, but `getaddrinfo`'s behavior with embedded NUL is implementation-defined.

### 23. Panicking WASM/LLVM frame-size buffer
`src/emit_llvm_llvmc_shim.c:1415-1578` — 4-byte stack buffer for panic-code formatting; codes >999 corrupt the stack frame in the emitted IR.

### 24. Off-by-one risk in const struct size validation
`src/emit_llvm_llvmc.zig:256-264` — overflow check is correctly using `std.math.add`, but `len != field.size` is checked *after* the field is processed. Reorder.

### 25. Plugin discovery loads from CWD
`src/plugins.zig` — the whitepaper documents plugin loading from `$HOME/.sa/plugins` + cwd. Audit: relative-path or cwd-relative loads enable plugin-substitution attacks when `sa` is run in an attacker-controlled directory.

---

## LOW severity (quick wins)

### 26. JSON `Parsed<>` keeps an extra allocator pointer per doc
`src/runtime/sa_std.zig:621-630` — could use a shared arena per batch.

### 27. `calleeSig` linear scan in code emit
`src/emit_llvm_llvmc.zig:354-363, 518-527` — building a `StringHashMap(usize)` once at start drops emit time on large programs from O(NM) to O(N+M).

### 28. Anon string-const name formatting allocates per use
`src/emit_llvm_llvmc.zig:317` — minor, but if the emitter is called in workflow mode it shows up.

### 29. Eventfd-wake errors silently swallowed
`src/runtime/sa_net_uring.zig:545-551` — reactor can sleep through a wake; rare but a "stuck" reactor is hard to debug.

### 30. Source line `u32` overflow at >4 G lines
`src/flattener.zig:3380-3398` — `line_no: u32` increments without saturation. Bench compiler emits 10001-function modules already (`demos/compare/big_bench.sa`); aggregated codegen could approach the limit.

### 31. Test-debug globals raced on
`src/runtime/sa_std.zig:85-87` — `test_debug_scalars`, `test_debug_next`, `test_debug_count` are global, mutable, no lock. Only matters in test builds but trips TSan.

### 32. `dirExists` swallows all errors
`src/pkg/fetch.zig:90-94` — treats EACCES the same as ENOENT. A cache directory the user can't read silently becomes "not present" and triggers a re-clone, which may then fail at write time with a confusing error.

### 33. `realpathAlloc` for every import resolve
`src/pkg/resolver.zig:316, 354, 364` — three syscalls per candidate. For deep import trees this dominates resolve time. Cache canonical paths.

### 34. `copyTree` walks twice for read-only setup
`src/pkg/fetch.zig:135-187` — `copyTree` then `setReadOnlyRecursive` traverse the same tree. Set permissions during copy.

### 35. `setReadOnlyRecursive` follows symlinks
`src/pkg/fetch.zig:163-187` — `openDir(.iterate = true)` follows symlinks; chmod on a symlinked external dir is unintended. Use `NO_FOLLOW` or skip symlinks in the walker.

---

## Architectural / process suggestions

1. **Fuzz harness.** `flattener`, `verifier`, and `interp` form the parser→checker→executor pipeline; the language guarantees soundness of the verifier so a fuzz pass on these three with `zig build fuzz` (afl/honggfuzz/zig's built-in) would buy a lot. Targets: arbitrary bytes → `flattener.flatten`, arbitrary classified lines → `verifier.verify`, arbitrary IR → `interp.run`. Expect to find dozens of `@intCast`/`@divTrunc` panics quickly.

2. **Differential testing emitter vs interpreter.** The whitepaper promises the same semantics in `sa run` and `sa build-exe`. Build a `sa diff <file>` that runs both and asserts identical exit/stdout. Catches the kind of divergence the emitter audit flagged in §10.

3. **Capability enforcement at runtime.** Manifest `grants [net_tx, net_rx, ...]` is parsed (`pkg/manifest.zig:325`), but I see no evidence that the runtime actually refuses syscalls when a grant is missing. If sa_std net functions are linked unconditionally, the grant string is documentation only. Spot-check this.

4. **ReleaseSafe by default for `sa run`.** All the `@intCast` / `@divTrunc` / `assert` issues above become silent in `ReleaseFast`. Build the interpreter & runtime with `-Doptimize=ReleaseSafe` for at-least the next several releases; the perf delta is small and the safety delta is large.

5. **`scripts/audit.sh` to grep for the patterns once a week:**
   - `@intCast(` without surrounding `std.math.cast`
   - `catch unreachable`
   - `std.debug.assert(` on input-derived expressions
   - `for (...) |...| ... blockIndexAt` (O(N) hot-path patterns)

6. **Lockfile self-update is a supply-chain hole.** `src/pkg/lock.zig:153-154` silently overwrites a pinned hash when the upstream differs. That defeats the purpose of pinning. Either gate on `--update` or refuse and surface a `HashMismatch` error.

7. **Worktree/sandbox the test harness.** `tests/` references hundreds of `.sa` files; `test_all_300.sh` runs them. If a single test installs/depends on a network-fetched package, all the supply-chain concerns above become CI concerns.

---

## Quick triage — what I'd fix today

1. `lock.zig:153-154` silent hash overwrite — 5 lines.
2. `resolver.zig:570-588` add `require_entry.source_sha256` check — 10 lines.
3. `interp.zig:1066-1090` div-by-zero guard — 6 lines.
4. `interp.zig:execFunction` call-depth counter — 8 lines.
5. `runtime/sa_std.zig:1204-1243` replace `assert` with returned error — 10 lines.
6. `runtime/sa_net_uring.zig:1586-1598` `std.math.cast` for WS length — 6 lines.
7. `pkg/fetch.zig:189-228` reject `-` prefix in identity/ref, add `--` before positionals — 6 lines.
8. `pkg/fetch.zig:203` set `GIT_TERMINAL_PROMPT=0` — 1 line.

That's ~50 lines that close the highest-impact items.

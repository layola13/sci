# Agents.md

This file is a running notebook for agent-facing questions and answers.
Use it to record:
- what was unclear,
- what evidence was checked,
- what conclusion was reached,
- what to do next.

Keep entries short, concrete, and tied to source files, commands, or history.
Do not use it for speculative design notes without evidence.
If a new doubt appears during work, write it here first with the evidence checked and the conclusion reached.
Treat this file as the shared question log: every new doubt gets a dated entry here before code changes, so later work can reuse the same evidence instead of guessing.

## Format

```text
## YYYY-MM-DD HH:MM
Question:
- ...

Evidence checked:
- [path](absolute/path#Lx)
- command output
- search/history result

Answer:
- ...

Next:
- ...
```

## 2026-05-20 12:35

Question:
- What are the real root causes behind the remaining SA std unit-test failures, why did this take so long to close, and in what order should the fixes be applied?

Evidence checked:
- `./zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`
- direct runs of the failing selectors from `.zig-cache/tmp/.../feature_suite.test`
- `tests/unit_framework/feature_suite.saasm`
- `tests/unit_framework/runner.zig`
- `src/test_runner.zig`
- `src/test_executor.zig`
- `src/test_result.zig`
- `src/emit_llvm.zig`
- `sa_std/encoding/json.saasm-iface`
- `sa_std/net.saasm-iface`
- `src/runtime/sa_std.zig`
- `src/runtime/sa_std.h`

Answer:
- The failures are caused by two system-level problems, not by isolated test cleanup mistakes.
- This note is about the SA std unit tests driven by `./zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`, not `zig test`.
- First, `src/emit_llvm.zig` is treating non-owning pointers loaded from slices/buffers as if they were owned malloc pointers, so generated LLVM frees data pointers from `STR_EQ` and related helpers. This explains the `mem`, `string`, `json`, and `regex` invalid-free and segfault crashes.
- Second, the SA interface files and the Zig runtime exports disagree on fallible ABI shape. Several `.saasm-iface` declarations use `!` fallible returns, but the Zig exports return plain `i32`/`u64` handles or status codes. That mismatch is visible in `json_free`, `json_stream_free`, `regex_free`, `fmt_buffer_free`, and especially the `net` wrappers.
- It took so long because the failures surfaced as runtime crashes rather than structured verifier traps, and the test runner obscured diagnosis by freeing captured stderr too early and by asserting on summary counts after filtered failures.

Next:
- Apply the fixes in this order: test runner stderr ownership and summary handling, emitter ownership modeling for `load ... as ptr`, SA std ABI alignment between `.saasm-iface` and runtime exports, then test expectation updates for the full std suite.

## 2026-05-20 13:41

Question:
- Should the remaining SA std suite fixes keep following the same root-cause order, and what is the smallest concrete change set that actually matches the observed failures?

Evidence checked:
- `src/test_executor.zig`
- `src/test_runner.zig`
- `src/emit_llvm.zig`
- `src/verifier.zig`
- `src/interp.zig`
- `src/runtime/sa_std.zig`
- `sa_std/encoding/json.saasm-iface`
- `sa_std/text/regex.saasm-iface`
- `sa_std/fmt.saasm-iface`
- `sa_std/net.saasm-iface`
- `tests/unit_framework/support/json_regex.saasm`
- `tests/unit_framework/support/stdlib_surface.saasm`

Answer:
- Yes. The same order still holds: fix test runner diagnostics first, then make `load` read-only and `take` ownership-extracting in emitter/verifier/interpreter, then align SA std ABI declarations with runtime exports.
- The smallest real change set is:
  - keep `stderr` alive until formatting is finished,
  - remove the summary assert that turns filtered runs into a second panic,
  - stop emitting `free` for borrowed/interior pointers loaded from slices and buffers,
  - make fallible SA std wrappers return a real `{status, value}` ABI where the SA side expects it,
  - leave the support corpus alone unless the compiler/runtime contract itself changes.

Next:
- Patch the runner diagnostics first, then the emitter/verifier/interpreter ownership split, then the SA std wrappers and `.saasm-iface` files.

## 2026-05-20 09:53

Question:
- Why is the remaining `zig build test` failure now a `sa_net_uring` segmentation fault in `pump`, and is it related to the new `emit_llvm` string-literal work?

Evidence checked:
- `zig build test --summary all`
- stack trace in `/opt/zig/lib/std/os/linux/IoUring.zig:137` and `/home/vscode/projects/sci/src/runtime/sa_net_uring.zig:657`
- `src/runtime/sa_net_uring.zig`
- `src/emit_llvm.zig`

Answer:
- The remaining failure is a real runtime crash inside `sa_net_uring` timeout arming, not a regression from the emitter or call parser changes.
- The emitter-related tests are now passing, so the next blocker is unrelated and should be inspected in the runtime worker / timeout initialization path.

Next:
- Inspect `src/runtime/sa_net_uring.zig` around `armTimeout` and reactor startup ordering, then rerun the repository test harness.

## 2026-05-20 09:23

Question:
- Will raw string arguments like `*"7"` and `utf8:"..."` survive the current call parser, or does the comma splitter still break quoted arguments before `emit_llvm` can intern them?

Evidence checked:
- `src/referee/call.zig`
- `src/emit_llvm.zig`
- `src/flattener.zig`
- `src/flattener/line_classifier.zig`
- `tests/unit_framework/support/json_regex.saasm`

Answer:
- The current `parseCallBody` / `parseSpecialCallBody` logic still splits on every comma with `std.mem.splitScalar`, so quoted commas inside raw string arguments would be unsafe.
- `emit_llvm` also still has a half-wired `StringLiteralPool`, so the parser and emitter need to be fixed together rather than assuming one side can cover the other.

Next:
- Replace the call-argument splitter with a quote-aware parser, then wire the string literal pool into function emission and precollect string literals before parallel work begins.

## 2026-05-20 08:24

Question:
- What should be updated first before adding more std work: the stale trap assertion in `src/cli.zig`, or new `graph` / `size` smoke tests?

Evidence checked:
- `zig test src/cli.zig`
- `zig test tests/cli_smoke.zig`
- `src/cli.zig` trap report test and `executeGraph` / `executeSize`
- `build.zig` test wiring for `tests/cli_smoke.zig`

Answer:
- Update the stale trap assertion first, because it is a concrete failing baseline.
- Then add repository-level `graph` / `size` smoke tests through the existing `build.zig` harness so the new CLI behavior is actually verified.

Next:
- Patch `src/cli.zig` and `tests/cli_smoke.zig`, then rerun the repository test step rather than compiling the smoke file standalone.

## 2026-05-20 08:46

Question:
- What is now causing the remaining repository test failures after the CLI `graph` / `size` smoke tests were added?

Evidence checked:
- `zig build test` output
- `src/emit_llvm.zig` call emission stack for `parseImmediateValue`
- `src/verifier.zig` failing panic and const-data tests from the same build run

Answer:
- The repo still has at least one real `emit_llvm` argument parsing issue, and the verifier still has separate panic / const-data regressions.
- These are not explained by the new CLI smoke tests alone, so they need direct source inspection before changing more tests.

Next:
- Inspect the `emitArgList` / `parseImmediateValue` path, then inspect the specific verifier failing cases and fix the real logic instead of papering over the tests.

## 2026-05-20 08:33

Question:
- Why is `parseImmediateValue` still seeing `*JSON_SCI_VALUE` in the std unit framework, and why are the verifier `panic` tests reconstructing invalid call text?

Evidence checked:
- `zig build test` output showing `parseImmediateValue` failing from `emit_llvm.zig`
- `src/emit_llvm.zig` `valueFromArgText` / `emitArgList`
- `src/verifier.zig` `callTextForInstruction`
- `tests/unit_framework/support/json_regex.saasm`
- `src/referee/call.zig`
- `src/flattener.zig`

Answer:
- The emitter needs to resolve raw pointer-prefixed text like `*CONST` before falling through to numeric parsing, because the support corpus uses raw const pointers in real call arguments.
- The verifier should not blindly reconstruct panic and call text from abbreviated operand fields in manual tests; it needs to fall back to the original raw line when the operand body already includes the full syntax or when panic operands are only bare bodies.

Next:
- Patch the emitter text resolution and verifier call-text reconstruction, then rerun `zig build test`.

## 2026-05-20 07:18

Question:
- For `graph` and `size`, should the CLI report only the current source file, or should `graph` recursively include imported source files while `size` reports per-function sizes from the verified compile result?

Evidence checked:
- `docs/agent_first_toolchain.md`
- `src/cli.zig`
- `src/flattener.zig`
- `src/verifier.zig`
- `src/emit_llvm.zig`
- `src/pkg/resolver.zig`

Answer:
- `graph` should recursively include imported source files and real call edges, because the doc describes blast-radius analysis over the package graph.
- `size` should report per-function sizes from the verified compile result, because the doc explicitly asks for function-level instruction and byte-aligned sizing after compilation.

Next:
- Implement both commands against the existing compile pipeline and keep the CLI fallback behavior aligned with `run`/`build`.

## 2026-05-20 06:40

Question:
- Should every new question about current progress, historical decisions, or missing context be logged here before any further code changes?

Evidence checked:
- Current `Agents.md` intro and format section
- User request to keep questions and answers here for later review

Answer:
- Yes. Record the question, the evidence checked, and the conclusion here first, then continue with implementation or review.

Next:
- Use this file as the shared source of truth whenever progress or history needs to be clarified.

## 2026-05-20 06:47

Question:
- For the remaining agent-first toolchain work, should `graph` and `size` be implemented as source-file commands, or should they accept a project root and aggregate multiple files?

Evidence checked:
- `docs/agent_first_toolchain.md`
- `src/cli.zig`
- `src/flattener.zig`
- `src/layout.zig`
- `tests/cli_smoke.zig`

Answer:
- Keep the question open until the command shape is verified against the existing CLI patterns and the current test fixtures.
- Do not guess the input model; the implementation should follow the existing source-file command style unless the documentation or tests require project aggregation.

Next:
- Inspect the existing CLI patterns for `layout`, `run`, and `build`, then decide the smallest real implementation that can be tested without inventing a new entrypoint.

## 2026-05-20 07:07

Question:
- For `graph` and `size`, should the CLI accept an optional source path and fall back to `src/main.saasm` or `main.saasm` when no path is given?

Evidence checked:
- `src/cli.zig`
- `src/flattener.zig`
- `src/common/signature.zig`
- `src/pkg/resolver.zig`
- `tests/cli_smoke.zig`
- existing command shapes for `layout`, `run`, and `build`

Answer:
- Yes. Keep the commands aligned with the current source-file CLI style: use an explicit path when provided, otherwise fall back to the same project-root source discovery used by the build/run paths.

Next:
- Implement `graph` and `size` on top of the existing compile pipeline and test the fallback behavior explicitly.

## 2026-05-20 05:48

Question:
- Should every new doubt during this work be written into `Agents.md` before code changes, with the evidence checked and the answer reached?

Evidence checked:
- Current `Agents.md` intro and format section
- User request to keep questions and answers here for later review

Answer:
- Yes. Use this file as the shared question log for every new doubt, then record the evidence and conclusion before editing code.

Next:
- Append future doubts here the moment they appear, so later work can reuse the same evidence instead of guessing.

## 2026-05-20 05:10

Question:
- Why are `?` early-return sites still present inside `-> void` unit-framework helpers, and how should they be rewritten without changing the test wrapper signatures?

Evidence checked:
- `/home/vscode/projects/sci/tests/unit_framework/support/json_regex.saasm`
- `/home/vscode/projects/sci/tests/unit_framework/support/stdlib_surface.saasm`
- `/home/vscode/projects/sci/sa_std/encoding/json.saasm-iface`
- `/home/vscode/projects/sci/sa_std/text/regex.saasm-iface`
- `/home/vscode/projects/sci/sa_std/net.saasm-iface`
- `/home/vscode/projects/sci/docs/whitepaper.md`
- `/home/vscode/projects/sci/docs/demos/rust-to-sa.md`

Answer:
- The helper functions are `-> void`, so `?` cannot be used for fallible propagation there.
- Keep the wrappers unchanged and rewrite each fallible call site as explicit status extraction plus branch or cleanup handling, matching the status-first ABI examples already documented in the repo.

Next:
- Patch the two support files to remove every `?` from `-> void` helpers, then rerun the SA unit framework and LLVM emitter tests.

## 2026-05-20 04:40

Question:
- How should I rebuild the repo code index, and where should I read recent progress without guessing?

Evidence checked:
- `/home/vscode/.codex/plugins/cache/local-projects/code-index/0.1.0/README.md`
- `/home/vscode/.codex/plugins/cache/local-projects/code-index/0.1.0/src/cli.ts`
- `/home/vscode/projects/sci/.code_index/__index__.py`
- `/home/vscode/projects/sci/.mimir/skeleton/__index__.py`

Answer:
- Rebuild with `bun run src/cli.ts build /home/vscode/projects/sci --output /home/vscode/projects/sci/.code_index` from the code-index plugin repo.
- For recent progress, read the local memory skeleton and the repo notebook first; the current snapshot points to the std/test work and the known `InvalidOperand` emitter path.
- The code index is only a navigation layer; the repository files and `Agents.md` remain the source of truth.

Next:
- Rebuild `.code_index`, then check local session history and repository logs before changing implementation.

## 2026-05-20 03:52

Question:
- Why does `@support_net_surface()` now fail with `UseAfterMove` on `connect_ok`?

Evidence checked:
- `tests/unit_framework/support/stdlib_surface.saasm`
- current SA test output
- `support_net_surface()` success-path condition composition

Answer:
- `connect_ok` is a live success-path condition and is still needed when composing the final `ok02`/`ok` value.
- It must not be consumed before the final boolean chain is built.

Next:
- Remove the early `!connect_ok` in `support_net_surface()` and rerun the SA suite.

## 2026-05-20 04:22

Question:
- Why did `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1` still exit with `InvalidOperand` after the earlier runtime-side fixes?

Evidence checked:
- `src/cli.zig` `executeTest()` path
- `src/emit_llvm.zig` `emitInstruction()` and `emitCall()`
- `tests/unit_framework/support/json_regex.saasm`
- `tests/unit_framework/support/stdlib_surface.saasm`
- `sa_std/encoding/json.saasm-iface`
- `sa_std/net.saasm-iface`

Answer:
- `saasm test` first lowers the suite through `emit_llvm`, then builds a native test binary.
- The emitter was still treating fallible return values as plain registers for `load` / `take`, so `load res+0 as u32` and `load res+4 as i32` could fall into `EmitError.InvalidOperand`.
- The correct fix is in `src/emit_llvm.zig`, not in the runtime ABI or the SA support tests.

Next:
- Re-run the LLVM emitter and the SA suite after teaching `load` / `take` to read fallible result status and payload fields explicitly.

## 2026-05-20 03:47

Question:
- Why does `@support_json_dom_roundtrip()` now fail with `UseAfterMove` on `stringify_status_ok`?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `docs/faq.md` and `docs/sax_syntax.md` fallible ABI examples
- current SA test output

Answer:
- `stringify_status_ok` is a live control-flow condition used later in the same block, so releasing it before composing `stringify_all_ok` is invalid.
- Only the owned fallible result values should be consumed early; derived status booleans should stay live until the final combined condition is built.

Next:
- Remove the early `!stringify_status_ok` and keep the final condition live through `stringify_all_ok`, then rerun the SA suite.

## 2026-05-20 03:46

Question:
- Why does `@support_json_dom_roundtrip()` now fail with `PhiStateConflict` on `name_slot`?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `src/verifier.zig` label join handling
- current SA test output

Answer:
- The same failure label is being shared by multiple blocks with different live-slot states.
- One incoming path reaches the label with `name_slot` uninitialized, while another retains it as active.
- The failure path needs its own label or its own explicit cleanup state so both incoming edges agree.

Next:
- Split the shared failure label(s) in `json_regex.saasm` and rerun the SA suite.

## 2026-05-20 03:38

Question:
- Why does `@support_json_dom_roundtrip()` now fail with `PhiStateConflict` on the `count_status` path?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `src/verifier.zig` branch / join-state handling
- `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`

Answer:
- The success branch keeps `count_status` live into the join, while the failure edge consumes it differently.
- The verifier requires both incoming states to agree before the next block, so the success block must explicitly release `count_status` before the `br`.

Next:
- Release `count_status` in the `L_COUNT` success path, then rerun the SA suite.

## 2026-05-20 03:17

Question:
- Why does `@support_json_dom_roundtrip()` still trap on the `count_value_res` path even after earlier JSON cleanup fixes?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `src/verifier.zig` `?` handling, `regConsumedLater`, and branch-condition marking
- `tests/unit_framework/support/stdlib_surface.saasm`
- `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`

Answer:
- The local fallible call is still exposed to live control-flow state in the block.
- The important pattern in the repo is to keep fallible calls isolated from still-live branch-condition values and to consume or release every owned value before the next `?`.
- The next fix should stay local to the `L_COUNT_HANDLE` / `L_OK_HANDLE` block in `json_regex.saasm`, not in the runtime ABI.

Next:
- Patch `json_regex.saasm` to remove the remaining leak-prone fallible edge and rerun the SA suite.

## 2026-05-20 03:01

Question:
- Should every new doubt during this work be written into `Agents.md` with the evidence checked and the conclusion reached?

Evidence checked:
- Current `Agents.md` notebook format
- User request to keep questions and answers here for later review

Answer:
- Yes. Record each new doubt here before changing code so later work can reuse the evidence instead of guessing.
- Keep the entry short, concrete, and tied to source files, commands, or history.

Next:
- Append future doubts here as they appear.

## 2026-05-20 01:42

Question:
- Should every new doubt during this work be written into `Agents.md` with the evidence checked and the conclusion reached, so it is easy to review later?

Evidence checked:
- Current `Agents.md` notebook format
- User request to keep questions and answers here for later lookup
- Existing entries already using the same question/evidence/answer structure

Answer:
- Yes. Record each new doubt here first, with the evidence checked and the conclusion reached.
- Keep the entry short and concrete so the next round can reuse it instead of guessing.

Next:
- Add future doubts here before making code or design changes.

## 2026-05-20 02:46

Question:
- Why does `@support_json_dom_roundtrip()` still fail on the `count_value_res` path?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `src/verifier.zig` `?` early-return handling and `regConsumedLater`
- `src/runtime/sa_std.zig` JSON handle ownership model
- `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`

Answer:
- The leak is not in the JSON status payload itself.
- `count_handle`, `ok_handle`, and `root` stay live across later fallible calls, so the verifier sees a real early-return leak on the `?` edge.
- The fix is to release each handle immediately after its last use and before the following `?`, then remove the later cleanup frees for those handles.

Next:
- Rewrite the JSON DOM roundtrip block with handle release before the fallible `?` lines, then rerun the SA suite.

## 2026-05-20 01:51

Question:
- Why did the native unit framework suite fail even though the CLI path looked wired up?

Evidence checked:
- `zig build test` output from `tests/unit_framework/runner.zig`
- `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`
- `tests/unit_framework/support/json_regex.saasm`

Answer:
- The failure was real SA linear-ownership breakage, not a fake framework issue.
- `@support_json_dom_roundtrip()` re-used `count_slot` with a second `stack_alloc`, which triggered `RegisterRedefinition` in the SA verifier.

Next:
- Keep the SA unit support code linear and unique for each stack slot, then rerun the suite.

## 2026-05-20 01:58

Question:
- Why did `? count_res` still trap after the duplicate `stack_alloc` fix?

Evidence checked:
- `src/verifier.zig` early-return handling
- `src/interp.zig` fallible call semantics
- `sa_std/encoding/json.saasm-iface`
- `tests/unit_framework/support/json_regex.saasm`

Answer:
- The fallible result itself must not have other live owned values on the `?` path.
- The earlier `name_handle` was still live when `count_res` was checked, so the verifier flagged `EarlyReturnLeak` even though the function had already passed the duplicate-slot issue.
- The correct fix is to release `name_handle` before starting the next fallible JSON query.

Next:
- Re-run the SA unit suite after aligning resource lifetimes with the verifier's `?` semantics.

## 2026-05-20 02:02

Question:
- What was still wrong in `@support_json_dom_roundtrip()` after releasing `name_handle` before `count_res`?

Evidence checked:
- `src/verifier.zig` `?` / early return handling
- `tests/unit_framework/support/json_regex.saasm`
- prior `EarlyReturnLeak` output for `name_free_res`

Answer:
- The branch still left `name_ok` live across the `? name_free_res` path.
- The fix is to release the branch condition register before the fallible `sa_json_free` call, so the verifier does not see any live registers on the early return path.

Next:
- Re-run the SA unit suite after releasing `name_ok` in the `L_NAME_FREE` block.

## 2026-05-20 02:04

Question:
- Which line in `json_regex.saasm` was still tripping `EarlyReturnLeak` after `name_ok` was released?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `tests/unit_framework/support/stdlib_surface.saasm`
- `rg` results for `? .*_free_res`

Answer:
- `name_free_status = ? name_free_res` was still introducing a fallible early-return path inside the cleanup block.
- The other suite files only discard free-call return codes with `!free_res`, so the fix is to follow that pattern here as well.

Next:
- Re-run the SA suite after changing the cleanup call to `!name_free_res` with no `?` in that block.

## 2026-05-20 02:08

Question:
- Which remaining cleanup calls in `json_regex.saasm` were still using `?` and keeping the suite from going green?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `tests/unit_framework/support/stdlib_surface.saasm`
- `src/verifier.zig` stack allocation and early-return leak handling

Answer:
- The remaining `?` calls were on `stringify_buffer_free_res`.
- The working suite pattern is to consume cleanup return values with `!free_res` and not create another fallible early-return point in the cleanup block.

Next:
- Re-run the SA unit suite after converting the remaining cleanup `?` calls to plain `!` discards.

## 2026-05-20 02:12

Question:
- What change did the verifier still need for the `count_res` fallible JSON query path?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `src/verifier.zig` early-return leak path for `?`
- current `zig-out/bin/saasm test` output

Answer:
- The fallible query result needed to be consumed in a more sequential order: read the status first, then release the temporary result register, then branch.
- That keeps the verifier from seeing the fallible result as live across the branch target in this block.

Next:
- Re-run the SA suite after the `count_res` block reorder.

## 2026-05-20 02:21

Question:
- Why did the `count_res` path still trip `EarlyReturnLeak` after the reorder?

Evidence checked:
- `tests/unit_framework/support/json_regex.saasm`
- `tests/sa_std_runtime.zig`
- verifier call/return handling in `src/verifier.zig`

Answer:
- The SA test block still used the fallible `?` form on the JSON object lookup path.
- The safest aligned fix for this suite is to use the explicit status-check style already used by the runtime smoke tests, removing the extra fallible temporary from this block entirely.

Next:
- Re-run the SA suite after switching that block to explicit status handling with no `?`.

## 2026-05-20 01:09

Question:
- Should every new doubt be written into `Agents.md` with the evidence checked and the conclusion reached?

Evidence checked:
- Current `Agents.md` notebook format
- User request to keep questions and answers here for later lookup
- Existing rule saying new doubts should be recorded here first

Answer:
- Yes. Use `Agents.md` as the first place to record each new doubt, the evidence checked, and the conclusion reached.
- Keep each entry short, concrete, and tied to source files, commands, or history so later work can reuse it instead of guessing.

Next:
- Append future doubts here before implementation or design changes.

## 2026-05-20 00:37

Question:
- Should every new doubt be recorded here with evidence and a conclusion?

Evidence checked:
- Current `Agents.md` notebook format
- User request to keep questions and answers here for later lookup

Answer:
- Yes. Record each new doubt here before changing code, so the next round can reuse the evidence instead of guessing.

Next:
- Add future doubts here as short dated entries before implementation or design changes.

## 2026-05-19 15:33

Question:
- Why does the work keep re-running or guessing instead of using the repository history and docs first?

Evidence checked:
- `code-index` rebuild and `search-history`
- `docs/std_missing.md`
- `docs/std_rfc.md`
- `tests/unit_framework/*`
- `src/verifier.zig`

Answer:
- This repository has enough local evidence to avoid guessing. The correct workflow is to check history, docs, and current support files before editing.
- For SA ownership and verifier issues, hidden assumptions are expensive. We should prefer direct evidence over memory.

Next:
- When a new doubt appears, add a new dated entry here before changing code.
- Prefer `code-index.search-history` and `code-index.search` over re-deriving behavior from scratch.

## 2026-05-19 15:33

Question:
- Should we create a new entry point or duplicate main to support std tests?

Evidence checked:
- existing `tests/unit_framework/feature_suite.saasm`
- prior history in `search-history`
- current support files under `tests/unit_framework/support/`

Answer:
- No. The current test framework should be extended in place.
- New entry points and duplicate mains are not needed and should be avoided.

Next:
- Keep adding std coverage through the existing `unit_framework` path.

## 2026-05-19 15:33

Question:
- How should std gaps be handled when the language/runtime is still incomplete?

Evidence checked:
- `docs/std_rfc.md`
- `artifacts/sa_std/README.md`
- current `sa_std` iface files

Answer:
- Use the existing facade and FFI surface first.
- For heavy compute and serialization, prefer the Zig-side implementation exposed through existing interfaces rather than hand-writing fragile `.saasm` logic.

Next:
- Keep std additions aligned with existing facades and test them through SA unit tests.

## 2026-05-19 16:00

Question:
- Why were compiler and CLI errors still too broad, and how did we make them more actionable?

Evidence checked:
- [`src/main.zig`](/home/vscode/projects/sci/src/main.zig)
- [`src/cli.zig`](/home/vscode/projects/sci/src/cli.zig)
- live validation with `zig-out/bin/saasm build` and `zig-out/bin/saasm build --json`

Answer:
- The CLI was still surfacing some top-level errors as bare `error: <name>` strings.
- We added a global `--json` path for diagnostics, structured CLI error codes/messages/hints, and JSON wrapping for trap reports.
- `build --json` now emits machine-readable JSON, while plain `build` prints a more specific human error with a stable CLI code.

Next:
- Continue expanding `agent_first_toolchain.md` beyond diagnostics into the remaining agent-facing commands such as `explain`, `fix`, and `skills`.

## 2026-05-20 06:03

Question:
- When `!res` is used on a fallible result handle such as `count_res = call @sa_json_value_count(...)`, should the emitter treat `res` as the whole `{status, payload}` aggregate or as a bare payload pointer?

Evidence checked:
- `/home/vscode/projects/sci/tests/unit_framework/support/json_regex.saasm`
- `/home/vscode/projects/sci/src/emit_llvm.zig`
- `/home/vscode/projects/sci/src/interp.zig`
- `/home/vscode/projects/sci/sa_std/encoding/json.saasm-iface`

Answer:
- Treat it as the whole fallible aggregate. The interpreter records fallible call results as `{status, payload}` and `!res` consumes the whole result handle; only the payload is later used through explicit `load res+4` or `load ...+0` patterns.
- The LLVM emitter should therefore release or consume fallible values without forcing them through the plain pointer cast path.

Next:
- Patch `src/emit_llvm.zig` so `.release` can consume a fallible aggregate directly and only free the payload when the underlying payload is a true owned pointer.

## 2026-05-20 06:07

Question:
- After fixing `.release` for fallible values, what is the next real failure reported by the test suite, and is it caused by the new emitter patch?

Evidence checked:
- `zig test src/emit_llvm.zig`
- `zig build test --summary all`
- `src/emit_llvm.zig`
- `src/verifier.zig`
- `src/interp.zig`

Answer:
- The new emitter tests pass, including the fallible result release case.
- The remaining failures in `zig build test` are pre-existing verifier traps (`panic`, `panic_msg`, immutable const read/print) plus an unrelated `sa_net_uring` segfault in `db.table.test.table ingest accepts jsonl input`.
- One separate emitter regression remains in `runner.test.native unit framework suite covers the demo-derived feature matrix`: `parseImmediateValue` still tries to parse a non-numeric call argument text and aborts with `InvalidCharacter`.

Next:
- Locate the non-numeric argument path in `src/emit_llvm.zig` and decide whether it should be treated as a register/const reference instead of an immediate.

## 2026-05-20 06:12

Question:
- Why does `parseImmediateValue` still see `JSON_NAME_KEY_LEN` as text during LLVM emission when the source already has `#def` constants?

Evidence checked:
- `/home/vscode/projects/sci/src/emit_llvm.zig`
- `/home/vscode/projects/sci/src/flattener.zig`
- `/home/vscode/projects/sci/src/verifier.zig`
- `/home/vscode/projects/sci/tests/unit_framework/support/json_regex.saasm`
- `/home/vscode/projects/sci/tests/unit_framework/support/stdlib_surface.saasm`

Answer:
- The emitter rebuilds call text from `base.raw_text` in `instructionCallText`, so it can bypass the flattened operands that already had `#def` expressions folded by the flattener.
- For this path, the safer fix is to rebuild calls from `base.operands` when possible, or at least avoid re-parsing raw source text that still contains symbolic def names.

Next:
- Patch `instructionCallText` to prefer already-folded operands over raw source text for `call` / `call_indirect` emission.

## 2026-05-20 06:32

Question:
- Did the `def_dict` fold fix restore the native unit-framework suite, and what failures remain after the LLVM emitter path passed?

Evidence checked:
- `zig test src/emit_llvm.zig`
- `zig build test --summary all`
- `/home/vscode/projects/sci/src/emit_llvm.zig`
- `/home/vscode/projects/sci/src/cli.zig`
- `/home/vscode/projects/sci/src/sax/build.zig`

Answer:
- Yes, the LLVM emitter tests now pass, including the fallible result release case and the serial/parallel text equality case.
- The native unit-framework suite still fails inside verifier tests for `panic`, `panic_msg`, and immutable const reads, and full build still reports an unrelated `sa_net_uring` crash in the DB ingest test.
- The `def_dict` fix was necessary because `instructionCallText` was rebuilding call text from raw source and reintroducing symbolic `#def` names into the emitter path.

Next:
- Inspect the three verifier failures directly in `src/verifier.zig`, then re-run the full build once those traps are understood or fixed.

## 2026-05-20 06:33

Question:
- Why does `cli_smoke.test.db cli register inspect exec round trip through registry` expect exit code `12`, while the actual run now returns `1` with `PANIC: code=17` and `PANIC[23]: hi`?

Evidence checked:
- `/home/vscode/projects/sci/tests/cli_smoke.zig`
- `/home/vscode/projects/sci/src/db/table.zig`
- current `zig build test --summary all` output

Answer:
- The test expects the DB CLI exec path to surface the script result `12`, but the current runtime behavior exits with `1` and emits panic diagnostics instead.
- This does not come from the LLVM emitter fix; it is a separate DB CLI / runtime behavior mismatch that needs targeted inspection of the DB exec path.

Next:
- Inspect the DB CLI exec implementation and the fixture being executed, then decide whether the test expectation or the runtime path is stale.
## 2026-05-20 08:12

Question:
- Why is `cli.test.trap reports print a human summary and preserve json payload` failing, and why does `tests/cli_smoke.zig` not see the `saasm` module when run standalone?

Evidence checked:
- `zig test src/cli.zig` output
- `zig test tests/cli_smoke.zig` output
- `src/cli.zig` trap test assertion around the human summary string
- `tests/cli_smoke.zig` module imports at the top of the file

Answer:
- The trap test expectation is stale relative to the current human-summary text emitted by the CLI.
- The smoke test file is not self-contained when compiled directly; it relies on the repo test harness to inject the `saasm` module, so direct `zig test tests/cli_smoke.zig` is the wrong standalone check for that file.

Next:
- Update the stale trap assertion to match the current output, then run the repository-level test command that wires the `saasm` module instead of treating the smoke file as a standalone package.

## 2026-05-20 10:46

Question:
- Why does `zig build test` now fail first in `emit_llvm.valueFromOperand` for both `ffi_handle_demo` and `runner`, and what operand shape is the emitter misclassifying?

Evidence checked:
- `zig build test --summary all` stack trace into `src/emit_llvm.zig:699` and `src/emit_llvm.zig:2774`
- `src/emit_llvm.zig`
- `tests/integration/ffi_handle_demo.zig`
- `tests/unit_framework/runner.zig`

Answer:
- Still open; the failing operand path needs to be inspected in the emitter source and the corresponding SA demo output before changing behavior.

Next:
- Read the exact `emitInstruction` case around the failing line and the source fixture that triggers it, then patch the operand classification instead of guessing.

## 2026-05-20 10:52

Question:
- Why was `move_` in `emit_llvm` trying to read a missing RHS operand, and what is the correct lowering behavior for `^value`?

Evidence checked:
- `src/flattener.zig`
- `src/interp.zig`
- `src/verifier.zig`
- `src/emit_llvm.zig`
- `tests/integration/ffi_handle/handle.saasm`

Answer:
- `move_` is an ownership-only instruction in this codebase: flattener records only the destination register, interpreter treats it as a no-op after verification, and verifier already enforces the consume semantics.
- The LLVM emitter should not try to read a second operand for `move_`; it only needs to accept the destination register and emit no runtime code.

Next:
- Re-run the emitter and repo tests to confirm the `move_` crash is gone, then keep the next failure in `Agents.md` before editing more code.

## 2026-05-20 10:57

Question:
- Why did the new `move_` regression test fail with `UseAfterMove` even after the emitter stopped reading a missing RHS?

Evidence checked:
- `src/emit_llvm.zig` new `llvm emitter treats move as ownership-only no-op` test
- `src/verifier.zig` `move_` consume rules
- `zig test src/emit_llvm.zig` failure output showing `UseAfterMove` on line 4

Answer:
- The regression test itself was invalid: `^value` consumes the register, so a later `!value` is a real use-after-move and the verifier correctly traps before emission.
- The emitter fix is still correct; the test needs to assert a legal move-only path instead of attempting to free the moved value.

Next:
- Rewrite the test to use a legal move-only sequence, rerun `zig test src/emit_llvm.zig`, then continue to repo-level failures.

## 2026-05-20 11:06

Question:
- Why does `zig test src/emit_llvm.zig` still fail after the `move_` emitter fix, and is the remaining issue in the emitter or the regression test?

Evidence checked:
- `zig test src/emit_llvm.zig` output showing `124 passed; 1 failed`
- `src/emit_llvm.zig` regression test `llvm emitter treats move as ownership-only no-op`
- `src/emit_llvm.zig` `functionBody` helper and `emitTestSource` output path

Answer:
- The emitter-side `move_` crash is already fixed.
- The remaining failure is the regression test assertion: it expects `ret i32 0`, but the emitted body for the current fixture does not satisfy that exact matcher.
- This means the test still needs to inspect the real emitted body more precisely instead of assuming the broad substring is enough.

Next:
- Inspect the actual emitted body for the legal move-only fixture, tighten the assertion, rerun `zig test src/emit_llvm.zig`, then resume repo-level tests.

## 2026-05-20 11:28

Question:
- Why does `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1` still exit with `InvalidOperand` even after the earlier `move_` and return-path fixes?

Evidence checked:
- `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1`
- `zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1 --json`
- `tests/unit_framework/feature_suite.saasm`
- `tests/unit_framework/support/json_regex.saasm`
- `tests/unit_framework/support/stdlib_surface.saasm`
- `sa_std/encoding/json.saasm-iface`
- `sa_std/text/regex.saasm-iface`
- `src/emit_llvm.zig` call emission helpers

Answer:
- The failure is still coming from the LLVM emission path before the native test binary can run.
- The current suspicion is that one of the feature-suite support files still produces a call or operand form that `emit_llvm` does not lower correctly, but the exact line is not identified yet.

Next:
- Split the feature suite by support file and run each one through the CLI build/test path to isolate the exact failing fixture, then patch the real lowering logic.

## 2026-05-20 10:02
Question:
- Why do `saasm test` and the `stdlib_surface`/`hashmap` probes still fail with `InvalidOperand` after the `move_` lowering fix?

Evidence checked:
- prior run summary from the current session
- `zig build test --summary all` no longer fails in `src/emit_llvm.zig` on the old `move_` crash
- `./zig-out/bin/saasm test tests/unit_framework/feature_suite.saasm --jobs 1 --json` still returns `InvalidOperand`
- `./zig-out/bin/saasm build-obj tests/unit_framework/support/json_regex.saasm -o /tmp/json_regex.o --json` succeeds
- `./zig-out/bin/saasm build-obj tests/unit_framework/support/stdlib_surface.saasm -o /tmp/stdlib_surface.o --json` fails with `InvalidOperand`

Answer:
- The emitter fix is real, but there is still a separate operand-lowering bug on call arguments or folded definitions in `src/emit_llvm.zig`.
- The next step is to inspect the exact lowering paths that handle call args and string/operand resolution before touching any std support code.

Next:
- Read the current `emit_llvm` implementation around call emission and operand text resolution, then patch the real lowering path and rerun the failing probes.

## 2026-05-20 10:15
Question:
- Which concrete call site in `tests/unit_framework/support/stdlib_surface.saasm` is tripping `EmitError.InvalidOperand`, and can `--debug` expose the exact lowering branch?

Evidence checked:
- `src/emit_llvm.zig` call lowering and operand conversion paths
- `tests/unit_framework/support/stdlib_surface.saasm`
- `sa_std/collections/btree_map.saasm`
- `sa_std/string.saasm`
- `sa_std/core/mem.saasm`

Answer:
- The current evidence points at `emit_llvm` call-argument lowering, not the std support files themselves.
- The next fastest check is to rerun the failing build with debug logging enabled so the exact operand branch can be identified before patching.

Next:
- Run the failing `saasm build-obj` and `saasm test` with debug enabled, then patch the offending lowering branch only.

## 2026-05-20 10:28
Question:
- If `tests/hashmap_fixture.saasm` passes, which remaining stdlib block in `stdlib_surface` is most likely failing: `btree`, `net`, or something else?

Evidence checked:
- `./zig-out/bin/saasm build-obj tests/hashmap_fixture.saasm -o /tmp/hashmap_fixture.o --json` succeeded
- `./zig-out/bin/saasm build-obj tests/unit_framework/support/stdlib_surface.saasm -o /tmp/stdlib_surface.o --json` still fails with `InvalidOperand`
- `tests/unit_framework/support/stdlib_surface.saasm` contains `mem`, `string`, `hashmap`, `btree`, and `net` blocks
- `sa_std/btree_map.saasm` exports `sa_btree_map_get/remove/len/insert` with `&map` and `&key` parameters
- `sa_std/net.saasm` and `sa_std/encoding/json.saasm` are facades over iface files

Answer:
- `hashmap` is not the blocker anymore.
- The next likely blocker is the `btree` or `net` block, so the fastest path is to run or derive a minimal fixture for each and see which one still trips `InvalidOperand`.

Next:
- Search for existing btree/net fixtures and compile them individually before patching `emit_llvm` further.

## 2026-05-20 10:41
Question:
- Is the `btree_map_fixture` failure coming from parallel emission or from the serial lowering path itself?

Evidence checked:
- `./zig-out/bin/saasm build-obj tests/hashmap_fixture.saasm -o /tmp/hashmap_fixture.o --json` succeeds
- `./zig-out/bin/saasm build-obj tests/btree_map_fixture.saasm -o /tmp/btree_map_fixture.o --json` fails with `InvalidOperand`
- `emit_llvm` has a separate parallel path in `emitUserFunctionsParallel`

Answer:
- The next discriminant is whether `--jobs 1` changes the failure.
- If `--jobs 1` still fails, the bug is in the serial lowering path, not in parallel chunk assembly.

Next:
- Re-run the `btree_map_fixture` with `--jobs 1`, then inspect the serial call/operand conversion branch that fails.

## 2026-05-20 10:56
Question:
- Why does `tests/vec_fixture.saasm` also fail with `InvalidOperand` while `tests/hashmap_fixture.saasm` succeeds?

Evidence checked:
- `./zig-out/bin/saasm build-obj tests/hashmap_fixture.saasm -o /tmp/hashmap_fixture.o --json` succeeds
- `./zig-out/bin/saasm build-obj tests/btree_map_fixture.saasm -o /tmp/btree_map_fixture.o --json --jobs 1` fails with `InvalidOperand`
- `./zig-out/bin/saasm build-obj tests/vec_fixture.saasm -o /tmp/vec_fixture.o --json` fails with `InvalidOperand`
- `sa_std/core/slice.saasm` uses `store %slice_reg+Slice_ptr, %data_ptr as ptr` and `store %slice_reg+Slice_len, %length as u64`

Answer:
- The remaining bug is likely shared by `vec`, `btree`, and other std support blocks that use macro-expanded `load/store/call` with layout offsets and borrowed pointer arguments.
- The next step is to inspect `vec.saasm` and reproduce the smallest failing macro family, then patch the shared lowering path rather than any one fixture.

Next:
- Inspect `sa_std/vec.saasm` and compile smaller vec-specific probes to isolate the exact bad operand form.

## 2026-05-20 11:03
Question:
- Does the `vec` failure come from the special `__vec_view_%out_ptr = & %vec_reg` borrow form in `VEC_GET`?

Evidence checked:
- `sa_std/vec.saasm` has the unique line `__vec_view_%out_ptr = & %vec_reg`
- `tests/vec_fixture.saasm` fails with `InvalidOperand`
- `tests/hashmap_fixture.saasm` succeeds, so the failure is not global

Answer:
- The unique borrow-view form in `vec` is the best remaining discriminator.
- The next step is to inspect how the classifier and emitter parse and lower the `borrow` instruction, especially when the macro emits `& %reg` with a space after `&`.

Next:
- Search the `borrow` instruction parsing and compare it against the vec macro expansion form.

## 2026-05-20 11:02

Question:
- Why do `vec_fixture`, `btree_map_fixture`, and `tests/unit_framework/support/stdlib_surface.saasm` still hit `InvalidOperand` after the `.move_` lowering fix, and which shared lowering branch is actually rejecting the operand?

Evidence checked:
- `build_index` output for `/home/vscode/projects/sci/.code_index`
- `search_history` hits for `InvalidOperand|vec_fixture|btree_map_fixture|stdlib_surface|emit_llvm|verifier`
- current repo test status from prior runs

Answer:
- Pending. The failure now appears to be in a shared call/load/take lowering path, not in `hashmap_fixture` or the `.move_` ownership-no-op path.

Next:
- Inspect `src/emit_llvm.zig` and `src/verifier.zig` call/operand handling, then run the smallest probe that isolates the first failing instruction form.

## 2026-05-20 11:08

Question:
- Which concrete `EXPAND` or `call` inside `vec_fixture` / `btree_map_fixture` first triggers `InvalidOperand` after the current lowering changes?

Evidence checked:
- `tests/vec_fixture.saasm`
- `tests/btree_map_fixture.saasm`
- `tests/unit_framework/support/stdlib_surface.saasm`
- `src/referee/call.zig`

Answer:
- Pending. The next step is a direct repro run with the existing test harness to identify the first failing instruction form.

Next:
- Run the smallest relevant test entrypoint and inspect the exact failure location before changing lowering code.

## 2026-05-20 11:14

Question:
- Why did the first `zig test tests/std_smoke.zig --test-filter vec_fixture|btree_map_fixture|stdlib_surface` probe report `All 0 tests passed` instead of exercising the failing std surface?

Evidence checked:
- `tests/std_smoke.zig` test names around the vec/btree/std smoke blocks
- the previous `zig test` output with 0 matched tests

Answer:
- The filter text did not match any Zig test names. The failing `vec_fixture` / `btree_map_fixture` files are inside the broader `std smoke fixture runs through the current compiler surface` test, not separate top-level Zig tests.

Next:
- Re-run the exact enclosing test name or inspect the surrounding fixture helpers to isolate the failure inside that test body.

## 2026-05-20 11:20

Question:
- Why does `zig build test` currently fail in `tests/unit_framework/runner.zig` with `default_code = 1`, and is that caused by the same `InvalidOperand` path or by the `saasm test` harness itself?

Evidence checked:
- `zig build test` output
- `tests/unit_framework/runner.zig`
- `build.zig` test wiring for `tests/unit_framework/runner.zig`

Answer:
- The failure is currently in the unit framework runner expectation, not yet in the same `InvalidOperand` stack. The harness is returning exit code 1 for the default suite run, so the next step is to inspect the runner's default execution path and its expected trap/test output.

Next:
- Read `tests/unit_framework/runner.zig` and the `saasm test` code path it exercises, then run that entrypoint directly if needed.

## 2026-05-20 11:36

Question:
- Is the current `emitUserFunctionsParallel` failure a real lowering error in one function chunk, or a parallelization bug that hides the real first error?

Evidence checked:
- `zig build test` stack traces ending at `src/emit_llvm.zig:1527`
- `src/emit_llvm.zig` parallel emission path
- failing demos in `tests/cli_smoke.zig`

Answer:
- Pending. The next step is to inspect the worker and chunk emission code, and then run a serial-vs-parallel comparison for one failing demo.

Next:
- Read `emitFunctionChunkWorker` / `emitFunctionChunkText`, then test one failing demo under `--jobs 1` if the CLI path is available.

## 2026-05-20 11:43

Question:
- Which demo first exposes the real `emit_llvm` error when run with the repository `saasm` binary and `--jobs 1`, and does it reduce to the same `InvalidOperand` as the std fixtures?

Evidence checked:
- `tests/cli_smoke.zig` lists the failing demo paths
- `src/emit_llvm.zig` parallel emission code can hide the worker error behind `job.err`

Answer:
- Pending. The next step is to use the built `saasm` CLI directly on a small failing demo with `--jobs 1` to surface the exact operand form.

Next:
- Build or reuse the repo CLI binary, then run the first failing demo with `build-exe` and serial jobs.

## 2026-05-20 11:50

Question:
- Why do `build-exe --jobs 1` runs for `demos/rosetta/253_contract_callback_registration/main.saasm`, `demos/rosetta/07_trait_vtable/main.saasm`, and `demos/support/sort_probe.saasm` fail with `MissingIndirectCallProvenance`?

Evidence checked:
- direct `zig-out/bin/saasm build-exe ... --jobs 1` runs for the three demos
- current `src/emit_llvm.zig` indirect call path requires `callee.origin.indirect_sig_index`

Answer:
- Pending. The next step is to inspect how provenance is attached to indirect-call values and whether the verifier/interpreter or emitter drops it before the call site.

Next:
- Trace `indirect_sig_index` through `emit_llvm.zig`, `verifier.zig`, and any value-carrying helper that can cross `call_indirect` boundaries.

## 2026-05-20 11:58

Question:
- Where does indirect-call provenance get lost so that `build-exe --jobs 1` on vtable-style demos returns `MissingIndirectCallProvenance`, even though the callee value should have come from a known function slot?

Evidence checked:
- direct `zig-out/bin/saasm build-exe ... --jobs 1` failures on `demos/rosetta/253_contract_callback_registration/main.saasm`, `demos/rosetta/07_trait_vtable/main.saasm`, and `demos/support/sort_probe.saasm`
- `src/emit_llvm.zig` `emitIndirectCall` and `Value.origin` / `indirect_sig_index` search hits
- `src/interp.zig` indirect-call provenance handling

Answer:
- Pending. The next step is to inspect the load/record helpers that attach and preserve provenance for pointer values loaded from const data or vtables.

Next:
- Read the `resolveLoadOrigin` / `recordMemoryPtrMeta` / `normalizePointerOrigin` path and reproduce one failing demo with more focused tracing if needed.

## 2026-05-20 12:06

Question:
- Does `emit_llvm` lose indirect-call provenance during `load`/`cast`/`setReg`, or is the callee register simply never attached to a constant vtable origin in the first place?

Evidence checked:
- direct `build-exe --jobs 1` failures with `MissingIndirectCallProvenance`
- `src/emit_llvm.zig` metadata helpers: `normalizePointerOrigin`, `recordMemoryPtrMeta`, `resolveLoadOrigin`, `inferIndirectSigIndexFromLoadText`, `emitIndirectCall`
- `src/interp.zig` provenance fields for runtime indirect calls

Answer:
- Pending. The next step is to inspect the `load` emission path and the value propagation helpers around `castValue` and `setReg`.

Next:
- Read the `load`/`take` lowering and a failing demo's vtable layout so the provenance source can be traced end to end.

## 2026-05-20 12:12

Question:
- Does `resolveLoadOrigin` actually recover `indirect_sig_index` from vtable constants like `&BUTTON_VT`, or does it only preserve the constant name and leave indirect calls provenance-less?

Evidence checked:
- `src/emit_llvm.zig` `load` path and `resolveLoadOrigin`
- `demos/rosetta/07_trait_vtable/main.saasm` stores `&BUTTON_VT as ptr` into a fat pointer field, then later does `call_indirect draw_fn(&data_ptr)`

Answer:
- Pending. The next step is to read `resolveConstValueOrigin` and the vtable slot resolution helpers to see whether the slot signature index is attached at load time.

Next:
- Inspect `resolveConstValueOrigin` and any helper that maps const vtable slot names to function signatures.

## 2026-05-20 12:18

Question:
- Can `emit_llvm`'s existing debug mode print the exact missing callee register/origin for `MissingIndirectCallProvenance`, or does the debug path itself fail before that message is emitted?

Evidence checked:
- direct `build-exe --jobs 1` failures without debug
- `src/emit_llvm.zig` has `std.debug.print` branches when `options.debug` is enabled and provenance is missing

Answer:
- Pending. The next step is a single demo run with `-g` so the debug print can expose the missing callee metadata if the backend accepts it.

Next:
- Run one failing demo with `-g --jobs 1` and inspect the stderr before making code changes.

## 2026-05-20 12:24

Question:
- In the failing trait-vtable demos, is the offset constant name (`VTable_call`, `SortCmp_cmp`) actually the vtable slot name, or just a layout label that should be resolved through the const vtable definition?

Evidence checked:
- `demos/rosetta/07_trait_vtable/main.saasm` uses `VTable_call` for a slot whose const vtable literal names the field `draw`
- `demos/support/sort_probe.saasm` uses `SortCmp_cmp` for a slot whose const vtable literal names the field `cmp`

Answer:
- Pending. The next step is to inspect the layout/iface files that define the slot labels and then patch provenance lookup to use the actual vtable const metadata rather than relying on the raw offset label alone.

Next:
- Search the layout/iface files for the vtable slot label definitions and the code path that maps constant offsets to slot signatures.

## 2026-05-20 12:29

Question:
- Is there already a regression test around `emit_indirect` provenance or vtable-slot recovery that can be extended, instead of adding a new synthetic path?

Evidence checked:
- `src/emit_llvm.zig` and `src/interp.zig` provenance fields
- failing demo source files for `call_indirect`

Answer:
- Pending. The next step is to search the emitter tests for indirect-call / vtable provenance coverage and extend the smallest existing case.

Next:
- Find the closest existing unit test and adapt it to cover a load from a vtable slot through a pointer parameter.

## 2026-05-20 12:34

Question:
- Do existing `emit_llvm` tests already cover vtable indirect-call provenance, and if so, which one is now red?

Evidence checked:
- `src/emit_llvm.zig` test block around the `take` and native escape tests
- failing demos still point at `MissingIndirectCallProvenance`

Answer:
- Pending. I need to inspect the lower-half of the emitter tests for indirect-call or vtable-specific coverage before editing code.

Next:
- Read the nearby emitter tests and, if necessary, add a minimal regression that constructs a vtable load and indirect call through an existing helper.

## 2026-05-20 12:41

Question:
- Why would `inferIndirectSigIndexFromLoadText` fail to infer a signature for `VTable_draw` / `SortCmp_cmp` if the helper is already walking vtable slot names?

Evidence checked:
- `src/emit_llvm.zig` helper chain from `inferIndirectSigIndexFromLoadText` to `findVtableSlotSigIndexByName`
- failing demos use slot labels `VTable_draw` and `SortCmp_cmp`

Answer:
- Pending. The next step is to verify the function-name lookup helper and the exact const-decl slot name parsing, because a naming mismatch would make the helper return null even when the slot name is present.

Next:
- Inspect `findFunctionSigIndex` and the const-decl parser output for vtable slot function names.

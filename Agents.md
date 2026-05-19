# Agents.md

This file is a running notebook for agent-facing questions and answers.
Use it to record:
- what was unclear,
- what evidence was checked,
- what conclusion was reached,
- what to do next.

Keep entries short, concrete, and tied to source files, commands, or history.
Do not use it for speculative design notes without evidence.

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

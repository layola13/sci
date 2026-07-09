# CLI Workflows

This directory documents CLI commands and workflows that cannot be demonstrated with `.sa` source code alone. Each file shows the exact command signature, flags, and output format.

## Why documents instead of `.sa` files

These features are **runtime CLI behaviors**—they query the compiler, emit structured diagnostics, or transform non-SA inputs. There is no `.sa` source to write for them; the "demo" is the command invocation and its response.

## Covered workflows

| Document | Command | Purpose |
|---|---|---|
| [`explain_demo.md`](explain_demo.md) | `sa explain <code>` | Explain a diagnostic error code |
| [`fix_plan_demo.md`](fix_plan_demo.md) | `sa fix [--plan] <code>` | Show a deterministic fix plan for a known error |
| [`skills_demo.md`](skills_demo.md) | `sa skills [--json]` | List compiler and plugin capabilities |
| [`layout_demo.md`](layout_demo.md) | `sa layout --name --fields` | Compute struct/type layout and offsets |
| [`profile_demo.md`](profile_demo.md) | `sa build ... --profile --json` | Collect compile phase timings and memory metrics |


## Related demos elsewhere

- `demos/compare/` — benchmark scripts that exercise `sa build --profile --json` across Rust and SA workloads.
- `demos/bc2sa_cmake/` — CMake + Clang pipeline for generating LLVM bitcode consumed by `sa bc2sa`.

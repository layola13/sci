# SA — The Safe Runtime for the WASM Era

> **Rust-level memory safety. Zig-level compile speed. Best-in-class native WASM size.**
> One IR. Multiple language frontends in. Full-stack WASM out.

📖 中文版：[`readme_cn.md`](readme_cn.md)

SA (safe asm) is **not yet another language for humans to hand-write.** It is a **safe IR + runtime that any upstream language can feed into**, accompanied by a complete plugin matrix spanning browser frontends to edge backends. This repository ships the compiler, the Referee static verifier, direct LLVM-C bitcode / WASM emitters, the `sa_std` standard library, and the `.sa` / `.sai` / `.sal` text formats.

```
┌────────────────────────────────────────────────────────────────┐
│  Input frontends                                                │
│   Rust / C++ ─► bc2sa ┐                                         │
│   TS / JS    ─► ts / deno / node ┐                              │
│   Sla        ─► sla              ├─► .sa / .sai / .sal          │
│   Hand-written ─────────────────────┘                            │
└──────────────────────────┬─────────────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  SA core (this repo)                                            │
│   Flattener → Referee (O(1) bitmask) → LLVM-C / WASM Emitter     │
│   sa_std (Vec/HashMap/String/Arc/Mutex/io/fs/net/...)            │
│   Gas Metering · Capability Mask · Airlock FFI                   │
└──────────────────────────┬─────────────────────────────────────┘
                           ▼
┌────────────────────────────────────────────────────────────────┐
│  Application plugins                                            │
│   Web frontend: sax / react / mui / vite / wgpu / 3dengines      │
│   Server side:  http_server / http_client / db / dbnet           │
│   Compute:      matmul                                           │
│   Platform:     pkg (zero-trust package manager) / vm            │
└──────────────────────────┬─────────────────────────────────────┘
                           ▼
              .exe / .o / .a / .wasm  (LLVM O1–O3)
```

---

## Why SA

| Dimension | Number |
|-----------|--------|
| **Borrow check complexity** | O(N) linear scan + O(1) bitmask vs Rust's O(N³) NLL |
| **Referee code size** | ≤ 2,500 lines of Zig — auditable line-by-line, burnable to FPGA |
| **Frontend compile speed** | ~5 ms lex / 0 ms type check / ~10 ms borrow check |
| **WASM hello-world size** | ≤ 48 KB (with DWARF); smaller with `--no-debug` |
| **Runtime overhead** | Zero (Release mode strips Referee entirely; codegen is on par with Zig / Rust) |
| **Sandbox primitives** | Gas Metering + Capability Mask built-in — no runtime monitor needed |

**The unoccupied lane:**

| Language | Memory safety | Compile speed | WASM size / iteration |
|----------|---------------|---------------|----------------------|
| Rust | ✅ | ❌ slow | Large / slow toolchain |
| Zig  | ❌ (no borrow check) | ✅ | Medium |
| Go   | GC | ✅ | TinyGo immature |
| **SA** | ✅ | ✅ | **48 KB / millisecond dev loop** |

---

## Multi-frontend: keep writing in your language

| You come from | Entry plugin | Notes |
|---------------|-------------|-------|
| Rust / C++ | [`sa_plugin_bc2sa`](../sa_plugins/sa_plugin_bc2sa) **(experimental)** | `clang / rustc` → LLVM bitcode → SA. Translates a conservative O0 subset of integer ops + static bound checks; `phi` / `switch` / `select` / float not yet supported. See [evaluation](../sa_plugins/sa_plugin_bc2sa/docs/bc2sa_evaluation_cn.md). |
| TypeScript | [`sa_plugin_ts`](../sa_plugins/sa_plugin_ts) | TS → SA |
| JS / Deno  | [`sa_plugin_deno`](../sa_plugins/sa_plugin_deno) **(experimental)** | Native Deno API subset — not a Deno runtime. Implemented: sys/env/text-IO/UUID/base64/mkdir/lstat etc.; binary IO / cwd / DNS / permissions still `planned_native`. See [evaluation](../sa_plugins/sa_plugin_deno/docs/plugin_evaluation_cn.md). |
| Node       | [`sa_plugin_node`](../sa_plugins/sa_plugin_node) **(experimental)** | Native Node API surface — not a Node runtime; no V8 / VM. 43 module facades shipped; real-world npm compatibility unverified. See [evaluation](../sa_plugins/sa_plugin_node/docs/plugin_evaluation_cn.md). |
| A purpose-built Rust-style high-level language | [`sa_plugin_sla`](../sa_plugins/sa_plugin_sla) | Sla — the LLM-friendly high-level frontend for SA |
| Hand-written `.sa` | This repo's `sa` CLI | The native tongue for LLMs and low-level debugging |

All paths converge to the same `.sa` IR, verified by the same Referee, emitted to the same WASM / native artifacts.

---

## Full-stack application plugin matrix

### Web frontend (WASM-first)

| Plugin | Role |
|--------|------|
| [`sa_plugin_sax`](../sa_plugins/sa_plugin_sax) | SA UI dialect; `.sax` → `app.wasm + airlock.js + index.html` |
| [`sa_plugin_react`](../sa_plugins/sa_plugin_react) | React-on-SAX — author SA components with the React mental model |
| [`sa_plugin_mui`](../sa_plugins/sa_plugin_mui) | Material UI components (early) |
| [`sa_plugin_vite`](../sa_plugins/sa_plugin_vite) | Dev server + `.sax` hot reload (Phase 2) |
| [`sa_plugin_wgpu`](../sa_plugins/sa_plugin_wgpu) | Browser WebGPU sidecar |
| [`sa_plugin_3dengines`](../sa_plugins/sa_plugin_3dengines) | 3D engine stack (aligning to Bevy) |

### Server & data

| Plugin | Role |
|--------|------|
| [`sa_plugin_http_server`](../sa_plugins/sa_plugin_http_server) | HTTP server |
| [`sa_plugin_http_client`](../sa_plugins/sa_plugin_http_client) | HTTP client |
| [`sa_plugin_db`](../sa_plugins/sa_plugin_db) | Native columnar database (file-backed) |
| [`sa_plugin_dbnet`](../sa_plugins/sa_plugin_dbnet) | Database network layer |

### Compute & system

| Plugin | Role |
|--------|------|
| [`sa_plugin_matmul`](../sa_plugins/sa_plugin_matmul) | Physical-limit GEMM matrix multiplication |
| [`sa_plugin_vm`](../sa_plugins/sa_plugin_vm) | Standalone dynamic VM interpreter |

### Platform infrastructure

| Plugin | Role |
|--------|------|
| [`sa_plugin_pkg`](../sa_plugins/sa_plugin_pkg) | **The public main entry**: zero-trust package management (URL-as-namespace, SHA-256 version pinning, no central registry, module-level `grants` sandbox) |

---

## Where SA fits

| Scenario | Why SA |
|----------|--------|
| **Edge serverless** (Cloudflare Workers / Vercel Edge / Fastly) | 48 KB cold-start + Gas cap + capability sandbox |
| **WASM plugin host** (Envoy / Wasmtime / browser extensions) | Affine ownership + one-shot Referee verification — no runtime supervisor |
| **LLM agent code sandbox** | Gas forecast + capability allowlist = physical circuit-breaker for untrusted code |
| **High-assurance** (aerospace / medical / defense) | Referee is formally verifiable, FPGA-burnable; pairs with Ada/SPARK for a two-layer defense |
| **Browser frontend** (React replacement) | `sax + react + vite + wgpu` full-stack WASM, leading on size and startup |
| **Embedded / IoT** | No GC, no runtime, WASI-compatible, cross-compiles to ARM |
| **Mixed Rust/C++ projects** | bc2sa (experimental) lets existing `.rs` / `.cpp` get SA's verification with no rewrite |

---

## Quick start

```bash
# Build the compiler (this repo)
zig build -Doptimize=ReleaseFast

# Run directly
./zig-out/bin/sa run examples/hello.sa

# Compile to WASM
./zig-out/bin/sa build-wasm examples/hello.sa -o hello.wasm

# Compile to native executable
./zig-out/bin/sa build-exe examples/hello.sa -o hello

# Install an application plugin (SAX example)
SA_PLUGIN_DEV=1 sa plugin install --dev /home/vscode/projects/sa_plugins/sa_plugin_sax
sa sax build demos/counter.sax --out-dir /tmp/counter
```

See each plugin's README for additional entry commands.

---

## Documentation map

| Document | Content |
|----------|---------|
| [`docs/design.md`](docs/design.md) | Full technical design (compile pipeline / Referee / Emitter / data models / mapping to the 41 requirements) |
| [`docs/requirements.md`](docs/requirements.md) | Hard requirement specification |
| [`docs/faq.md`](docs/faq.md) | "Why not X" deep Q&A (control flow / types / ownership / concurrency / memory / modules / package management / high-assurance) |
| [`docs/ebnf.md`](docs/ebnf.md) | SA text grammar EBNF |
| [`docs/errorcode.md`](docs/errorcode.md) | Structured Trap / CLI error code catalog |
| [`docs/database.md`](docs/database.md) | sa-db columnar design |
| [`docs/agent_first_toolchain.md`](docs/agent_first_toolchain.md) | Agent-first CLI / `--json` / `compile_tokens` |
| [`docs/llm_cheat_sheet.md`](docs/llm_cheat_sheet.md) | LLM cheat sheet for generating SA |
| [`docs/sla_language_specification.md`](docs/sla_language_specification.md) | Sla high-level frontend specification |
| [`docs/llvm2sa_feasibility.md`](docs/llvm2sa_feasibility.md) | LLVM bitcode → SA feasibility |
| `tasks.md` | Authoritative task ledger (versioned roadmap) |
| `docs/progress.md` | Latest completion audit snapshot |

---

## Repository layout

```
sci/
├── src/                   Compiler, Flattener, Referee, Emitter, CLI (Zig)
├── sa_std/                Standard library (.sa / .sai / .sal + Zig-backed runtime)
├── docs/                  Design / requirements / FAQ / error codes / cheat sheet
├── examples/              Example .sa programs
├── demos/                 End-to-end demos (incl. rosetta comparisons & benchmarks)
├── bench/                 Benchmarks
├── artifacts/             Prebuilt standard library (artifacts/sa_std/libsa_std.a)
├── tasks.md / progress.md Task ledger and progress audit
└── readme.md
```

External plugin directory: `/home/vscode/projects/sa_plugins/` — each plugin has an independent `sap.json` + `.sai` + `.sal` + `.so`, and can be installed and upgraded independently.

---

## Current status (honest assessment)

| Module | Status |
|--------|--------|
| Compiler core (Flattener / Referee / LLVM Emitter / WASM Emitter / interpreter) | Mainline stable; ongoing optimization (see P0 industrial-scale refactor) |
| `sa_std` standard library | Wave 1/2 macro waves landed (Vec / HashMap / String / Option / Result / Rc / Arc / Mutex, …) |
| Package manager `sa pkg` | Early; URL namespacing + SHA-256 pinning foundations in place; deeper work pending |
| Application plugins | sax / react / db / http_server / vm / bc2sa / matmul usable; mui / vite / 3dengines / deno early |
| Formal verification (Coq / Lean4) | Roadmap (v0.6+) |
| FPGA-hardened Referee | Roadmap (R33.6) |

`tasks.md` is the authoritative task ledger; `docs/progress.md` is the latest completion audit snapshot.

---

## Design philosophy (one line)

> **Zero AST. Linear scan. O(1) bitmask. Five-symbol contract (`= & ^ ! *`). Frontend-responsibility model. Explicit over implicit.**
> SA is not designed for humans to hand-write. It is an **intermediate protocol** and **safe runtime** designed to be generated by LLMs / compiler frontends, verified by Referee, and emitted to LLVM / WASM.

Full philosophy and comparisons (vs Go / Zig / Rust / Ada/SPARK) live in [`docs/faq.md`](docs/faq.md).

---

## License

This project is open source under the Apache License 2.0; see `LICENSE`. The repository also includes a mandatory `NOTICE` attribution file.

Copyright 2026 zhanhaiyang.

You may use, copy, modify, merge, publish, distribute, sublicense, and sell copies of this work under the Apache License 2.0, provided that every source or binary redistribution retains:

- the copyright notice;
- this license notice;
- the original work name: `SA (safe asm, 安全汇编)`;
- the original author attribution: `zhanhaiyang`;
- any NOTICE text included with the distribution.

Derived works may use their own names, but they must not remove or obscure the original work name and author attribution above.

Apache License 2.0 text: `LICENSE` or https://www.apache.org/licenses/LICENSE-2.0

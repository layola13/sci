# @salang/sa

SA (Safe ASM) toolchain for the SLA language: compiler, runtime and package manager.

## Install

```sh
npm install -g @salang/sa
sa --version
```

The installer pulls exactly one platform package via `optionalDependencies`
(esbuild-style distribution):

| Platform | Package |
|---|---|
| Linux x86_64 | `@salang/sa-linux-x64` |
| Linux ARM64 | `@salang/sa-linux-arm64` |
| macOS ARM64 | `@salang/sa-darwin-arm64` |
| macOS x86_64 | `@salang/sa-darwin-x64` |
| Windows x86_64 | `@salang/sa-win32-x64` |
| FreeBSD x86_64 | `@salang/sa-freebsd-x64` |

## System requirements

Since 0.1.5 the platform packages bundle the LLVM 14 runtime
(`bin/libLLVM-14.so.1` on Linux, `bin/*.dylib` on macOS,
`bin/LLVM-C.dll` on Windows), and the `bin/sa.js` launcher prepends
`bin/` to the loader path — no system LLVM install required.

If you still see a loader error on an older version, upgrade first:

```sh
npm install -g @salang/sa@latest
sa --version
```

Manual fallback per OS (only needed if bundling was stripped):

| Platform | Error | Fix |
|---|---|---|
| Ubuntu 24.04 | `libLLVM-14.so.1: cannot open shared object file` | `sudo apt-get install -y libllvm14t64` (note the **t64** rename) |
| Ubuntu 22.04 / Debian 12 | same | `sudo apt-get install -y libllvm14` |
| Fedora | same | `sudo dnf install -y llvm14-libs` |
| Arch | same | `sudo pacman -S --needed llvm14-libs` |
| Alpine (musl) | same | glibc binary unsupported — use `debian:bookworm-slim` or `zig build -Dllvm=false` from source |
| macOS | `libLLVM.dylib` missing | `brew install llvm@14` |
| Windows | `LLVM-C.dll` missing | reinstall + VC++ redist (`aka.ms/vc-redist`) |
| FreeBSD | `libLLVM` missing | `pkg install -y llvm14` |

## What needs what (`-Dllvm=false` can't replace LLVM)

The LLVM-C backend is mandatory for all artifact emission — it cannot be
compiled out without losing commands:

| Command | Needs LLVM 14 (bundled) | Needs `zig` on PATH | Notes |
|---|---|---|---|
| `run` | no (pure-Zig interpreter) | no | daily dev loop works with zero deps |
| `build-wasm` | yes (`wasm_compat` bitcode) | yes (`zig cc -target wasm32-wasi`) | no extra wasi-sdk needed — zig bundles wasi-libc |
| `build-exe` / `build` / `build-obj` | yes | yes (`zig cc`) | |
| `test` | yes (compiles + native-runs) | yes | |
| `check`, `layout`, `size`, `graph`, `skills`, `version` | no | no | |

So: install `zig 0.14.1` once (https://ziglang.org/download/0.14.1/ →
`zig-x86_64-linux-0.14.1.tar.xz` etc., `zig version` must work). FreeBSD has
no upstream zig build — use ours (built with FreeBSD-native LLVM 19,
`tools/build_zig_freebsd.sh` documents the recipe):

```sh
fetch -o - https://github.com/layola13/sci/releases/download/zig-0.14.1-freebsd/zig-x86_64-freebsd-0.14.1.tar.xz | tar -xJf -
export PATH="$PWD/zig-x86_64-freebsd-0.14.1:$PATH"
zig version   # expect 0.14.1
```

The launcher
warns when you invoke a build-family command without `zig` on PATH; the
compiler itself reports `error[ExternalCompiler]` at the link step.

`src/emit_wasm/` (pure-Zig encoder) is currently dead code — the real
`build-wasm` path is LLVM bitcode + `zig cc` (see `docs/completeness_evaluation_2026-06-25.md`).
Run `.wasm` output with `wasmtime`, `node --experimental-wasi`, or browsers.

## 0.0.1 scope

Ships the `sa` compiler binary only (`sa --help` for subcommands).
`hubproxy` and plugin SDKs follow in later versions.

## Source & license

Built from https://github.com/layola13/sci (see `sala/` doc chapter
“多平台编译” for the per-target build matrix). Apache-2.0.

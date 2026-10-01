# Windows Support Development Plan

Status: Windows implementation complete; native Linux acceptance pending
Target Zig version: 0.14.1
Primary constraint: add Windows support without regressing the existing Linux toolchain.

## 1. Goal

Make the SA compiler and core toolchain usable on Windows while preserving the current Linux behavior.

The intended end state is:

- Linux keeps the existing full-capability path: LLVM-14 defaults, `.so` plugins, pthread-backed runtime paths, io_uring tests, and the current CI surface.
- Windows gains a staged support path: first core compiler and CLI, then `sa_std` runtime basics, then LLVM native codegen, then package/plugin support with `.dll` artifacts.
- Unsupported Linux-only features are explicitly skipped or isolated on Windows instead of causing compile failures.

This is not a migration away from Linux. It is a target-aware portability layer around the existing architecture.

## 2. Current Evidence

Checked through 2026-07-31 with local `zig version` reporting `0.14.1`.

Implementation note from the first Windows pass:

- Windows now defaults `-Dllvm` to `false` so `zig build` can produce the bootstrap compiler without a local LLVM install.
- Linux and other non-Windows targets keep the LLVM-enabled default to preserve the existing Linux toolchain behavior.
- Explicit `-Dllvm=true` runs a build-time LLVM-C configuration precheck for `llvm-c/Core.h`, the LLVM library directory, and target-specific library filename candidates before compiling the shim.
- Windows `sa_std` currently builds from a dedicated bootstrap root. In addition to ABI version, print, buffer handles, env/cwd/args/time, basic formatting, string/UTF-8 helpers, Deno base64/text byte helpers, and random UUID generation, it now covers file base64 read/write and cross-platform filesystem operations for existence, length, read-to-string, remove, rename, copy, and directory creation/removal. Its tagged file resources support sequential and positioned reads/writes, exact/all operations, seek, flush/sync, truncate, deterministic close, and standard-stream dispatch. It also exposes real current-thread ID/yield operations while pthread-specific compatibility exports fail explicitly with `SA_STD_ERR_UNSUPPORTED`. The full Linux `sa_std` root remains the non-Windows default.
- Current Windows Zig 0.14.1 gates pass for `zig build`, `host-basic`, `runtime-basic`, `windows-runtime`, and `plugin-host-smoke`; the Linux compatibility check available on this host is the cross-build proxy `-Dtarget=x86_64-linux-gnu -Dllvm=false`.
- The latest Windows runtime slice adds owned-buffer filesystem canonicalization and deterministic read-link validation/error mapping. Successful reparse-point reads remain open because Zig 0.14.1 returns `Unexpected NTSTATUS=0xc0000275` for the host-created test link.
- Windows also exports a real Win32 current-process ID. Parent ID, uid, and gid remain deliberately unimplemented because their plain `u32` ABI cannot represent unsupported Windows semantics.
- Windows process resources now support run/spawn/stream modes, cwd variants, child PID, wait/try-wait, kill, captured stdout/stderr, generic stream reads, exec capture, and deterministic close behavior. High-level command-ext calls work for supported cwd-only configurations; Unix raw wait status, signals, process groups, pidfd, custom arg0, setsid, uid/gid/groups, and chroot remain explicit gaps rather than emulated semantics.
- The Windows `std-smoke` gate now passes on CRLF checkouts by normalizing repository text to LF at the shared test read boundary; semantic source assertions remain unchanged.
- Windows now exports the complete public JSON ABI: shared-lifetime parse/query nodes, typed getters, stringify buffers, nested writer construction, chunked streaming scanner, and complete-input token stream. Native C tests cover successful data flow, ownership after root release, malformed input, truncation, invalid types/handles, structural writer errors, and cleanup.
- Windows now exports the complete public filesystem metadata ABI. File and directory snapshots expose real kind, size, inode, and access/modify/change times; metadata JSON keeps the Linux key schema. POSIX-only ownership, mode, device, link-count, and block fields return documented stable zero values instead of invented Windows semantics.
- Windows now exports both public directory-enumeration forms: bounded JSON buffers and structured parent/child snapshots. Child entry names are independently owned, so they remain valid after the parent snapshot is freed; entry inode remains zero because Zig's Windows iterator does not expose a stable file index.
- The Windows bootstrap runtime now exports every public `sa_fs_*` symbol. Hard links and timestamps use real Win32 behavior; symbolic links use Zig's Windows implementation. POSIX mode/permission, uid/gid ownership, chroot, mkfifo, raw-fd adoption, and arbitrary POSIX open-option calls return `SA_STD_ERR_UNSUPPORTED` with output handles cleared where applicable.
- Real Windows LLVM-C native codegen is now verified with LLVM 14.0.6 and Zig 0.14.1. The compiler links against `LLVM-C.lib`, builds the hello-world `.sa` fixture into a PE/MZ `.exe`, and the generated executable prints `hello, saasm` with exit code 0. The official LLVM Windows installer omits public/generated development headers, so the exact-version public `llvm-c` headers were supplied from tag `llvmorg-14.0.6`; the C shim avoids `Target.h` generated-header dependencies on Windows by calling the exported X86 initialization ABI directly.
- A repeatable `windows-llvm-smoke` build step now injects the LLVM DLL directory into `PATH`, compiles the hello-world fixture, verifies PE/MZ output, executes it, and checks its output and exit status. The existing `llvmc-test` run step receives the same target-aware DLL path setup.
- The complete real LLVM-C test root now passes on Windows against LLVM 14.0.6. Windows source paths are escaped through JSON string serialization for `FILE!` and `MODULE_PATH!`; duplicate macro definitions fail deterministically without leaking or double-freeing; direct and indirect macro cycles are rejected before allocation-heavy recursive expansion; resolver tests compare native paths with separator-neutral assertions.
- Windows plugin permission paths normalize both separators and ASCII case. Permission roots cover `$PROJECT`, `$HOME` with a Windows `USERPROFILE` fallback, `$SA_CACHE`, and `$SA_PLUGINS_HOME`. The complete Windows plugin smoke passes with real DLL fixtures and broker permission checks.
- Native Linux full regression remains unverified on this Windows host. The installed WSL2 Ubuntu distribution cannot start because virtualization/Virtual Machine Platform is unavailable (`HCS_E_HYPERV_NOT_INSTALLED`), and no Docker, Podman, or QEMU runtime is installed. The passing Linux no-LLVM cross-build is a compatibility proxy, not a substitute for native Linux acceptance.

Implementation status by phase:

- Phases 0-3 are implemented and covered by the Windows bootstrap, host/core/runtime, package, and standard-library gates.
- Phase 4 is implemented and covered by both `windows-llvm-smoke` and the complete real `llvmc-test` suite with LLVM 14.0.6.
- Phases 5-6 are implemented and covered by real `.dll` plugin loading/install tests and Windows permission-path tests.
- Final cross-platform completion remains blocked only on running the native Linux default/full regression in a Linux environment.

Key Linux assumptions currently visible in the codebase:

- `build.zig` defaults LLVM paths to `/usr/lib/llvm-14/include`, `/usr/lib/llvm-14/lib`, and library name `LLVM-14`.
- `build.zig` unconditionally adds `src/runtime/sa_pthread_host.c` to `sa_std` static and shared runtime modules.
- `src/runtime/sa_pthread_host.c` uses `_GNU_SOURCE`, `dlfcn.h`, `pthread.h`, `dlvsym`, and `RTLD_NEXT`.
- `src/runtime/native_sys.zig` reads `/proc/self/cmdline` for argv and uses `std.posix.exit`.
- `src/pkg/fetch.zig` uses `std.posix.fork`, `execvpeZ`, and `waitpid` for git fetch execution.
- `src/plugins.zig` scans plugin directories for `.so` files and prefers the manifest artifact key `linux-x86_64`.
- `src/cli.zig` already has one Windows-aware runtime artifact name branch for `sa_std.lib`, but `build.zig` still publishes the build option as `artifacts/sa_std/libsa_std.a`.
- Tests and docs contain many Linux-only paths and assumptions: `/tmp`, `/home/vscode`, `.so`, `bash`, Node-on-Linux checks, io_uring, Unix PTY, and OpenSSL `.so` lookup paths.

## 3. Non-Goals

- Do not make Windows the default CI authority for Linux-only features.
- Do not remove or weaken Linux `.so` plugin loading.
- Do not replace the existing Linux pthread/io_uring implementation unless a compatibility wrapper preserves current semantics and tests.
- Do not require LLVM to be installed before the Windows core compiler can build.
- Do not silently mark Linux-only runtime features as working on Windows. Unsupported features must be explicit skips, errors, or separately tracked implementations.

## 4. Compatibility Rules

Every implementation phase must obey these rules:

- Use `target.result.os.tag` in `build.zig` for build decisions. Avoid host-only checks that break cross-compilation.
- Preserve Linux defaults unless there is a confirmed Linux bug. The current Linux LLVM-14 default path can remain the default for Linux.
- Add Windows behavior through target-aware helpers: artifact names, dynamic library suffixes, manifest target keys, runtime shims, and test gates.
- Keep `zig build test` behavior on Linux as close to current behavior as possible.
- Any skipped Windows feature must have a focused follow-up item and an explicit test skip or diagnostic.
- Use Zig standard library process, path, and filesystem APIs where they are already cross-platform enough.

## 5. Target Support Levels

### Level 0: Windows Core Build

Minimum usable Windows compiler build without LLVM native codegen.

Expected capabilities:

- Build `sa.exe` with Zig 0.14.1.
- Run `sa.exe --help`.
- Run parser / flattener / Referee / WASM emitter tests that do not require Linux runtime facilities.
- Build without a local LLVM install by passing a new LLVM disable option.

Expected non-capabilities:

- No native `sa build-exe` unless LLVM is configured.
- No io_uring, Unix PTY, or Linux pthread-specific tests.
- No plugin `.dll` support yet unless implemented in a later phase.

### Level 1: Windows Basic Runtime

Windows can build and use the core `sa_std` runtime surfaces that are naturally cross-platform.

Expected capabilities:

- `sys_print`, `sys_exit`, `sys_read_file`, and `sys_write_file` work on Windows.
- Basic C/ABI integration tests compile under the selected Windows C ABI.
- Thread exports either use a Windows implementation or are explicitly unavailable until Level 3.

### Level 2: Windows LLVM Native Backend

Windows can use LLVM-C to emit native executables.

Expected capabilities:

- User can provide LLVM include/lib/name paths with `-Dllvm-include-dir`, `-Dllvm-lib-dir`, and `-Dllvm-lib-name`.
- `sa build-exe input.sa -o output.exe` works when LLVM is installed and configured.
- Output naming handles `.exe` naturally.

### Level 3: Windows Package and Plugin Runtime

Windows supports dynamic plugin loading and package fetch/install flows.

Expected capabilities:

- Plugin loader scans `.dll` on Windows and `.so` on Linux.
- Plugin manifest selection supports `windows-x86_64` while preserving `linux-x86_64`.
- Package fetch uses cross-platform process spawning instead of POSIX fork/exec.
- Plugin permission review understands Windows paths and dynamic loader symbols.

## 6. Phase Plan

### Phase 0: Build-System Portability Boundary

Objective: make the build graph target-aware without changing Linux defaults.

Tasks:

1. Add a build option `-Dllvm=true|false`.
2. Keep Linux default as `true` so existing Linux builds remain unchanged.
3. Consider defaulting Windows to `false` unless LLVM paths are supplied. If this is too implicit, keep default `true` everywhere but document `-Dllvm=false` as the Windows bootstrap path.
4. Guard LLVM C shim and system library linking behind `enable_llvm`.
5. Make `build_options.sa_std_archive_path` target-aware:
   - Linux and other Unix-like targets: `artifacts/sa_std/libsa_std.a`
   - Windows: `artifacts/sa_std/sa_std.lib`
6. Add a helper for static and dynamic artifact names instead of open-coded `.a`, `.so`, `.lib`, and `.dll` strings.
7. Add a Windows/bootstrap build step such as `host-basic` or `windows-basic` that excludes LLVM-native, io_uring, Unix PTY, and plugin `.so` tests.

Primary files:

- `build.zig`
- `src/cli.zig`

Verification:

```powershell
zig version
zig build -Dllvm=false
.\zig-out\bin\sa.exe --help
zig build host-basic -Dllvm=false
```

Linux regression:

```bash
zig build
zig build test
```

Acceptance criteria:

- Windows can build the core CLI without LLVM installed.
- Linux default `zig build` still links LLVM as before.
- Linux artifact names and installed output paths remain compatible.

### Phase 1: Native System Runtime Split

Objective: remove unconditional Linux runtime assumptions from core runtime modules.

Tasks:

1. Replace `std.posix.exit` in `src/runtime/native_sys.zig` with `std.process.exit` or a small target-aware wrapper.
2. Replace `/proc/self/cmdline` argv loading with a cross-platform mechanism.
3. If full `sys_argv` cannot be implemented immediately on Windows, provide a documented fallback and a failing/skipped test that tracks the gap.
4. Split thread host shims by OS:
   - Linux keeps `src/runtime/sa_pthread_host.c`.
   - Windows gets a new implementation, preferably Zig `std.Thread` if ABI shape allows it, otherwise a small Win32 C shim using `CreateThread`, `WaitForSingleObject`, and `CloseHandle`.
5. In `build.zig`, add only the appropriate runtime shim for the target.
6. Gate io_uring-specific modules and tests behind Linux-only build/test steps.

Primary files:

- `src/runtime/native_sys.zig`
- `src/runtime/sa_pthread_host.c`
- new Windows thread shim file if needed
- `build.zig`
- `tests/native_sys_runtime.zig`
- `tests/sa_std_runtime.zig`

Verification:

```powershell
zig build sa-std-static -Dllvm=false
zig build native-sys-runtime -Dllvm=false
```

Linux regression:

```bash
zig build sa-std-static
zig build sa-std-runtime
zig build sa-net-uring-test
```

Acceptance criteria:

- Linux pthread behavior remains covered by existing tests.
- Windows builds do not include the Linux pthread/dlfcn shim.
- Core file IO and process exit runtime surfaces work on Windows.

### Phase 2: Test Suite Segmentation

Objective: make platform capabilities explicit and prevent unrelated platform gaps from blocking core validation.

Tasks:

1. Introduce named test groups:
   - `core`
   - `runtime-basic`
   - `llvm-native`
   - `plugins`
   - `linux-runtime`
   - `windows-runtime`
2. Move io_uring, Unix PTY, Linux-only Node/browser assumptions, OpenSSL `.so` path tests, and pthread-specific tests into `linux-runtime` unless Windows equivalents exist.
3. Convert tests using `/tmp` and `./binary` assumptions to use `std.testing.tmpDir`, `std.fs.path`, and target-aware executable names.
4. Replace test references to `.so` with target-aware dynamic library suffix helpers.
5. Keep Linux CI broad; keep Windows baseline narrow until later phases are complete.

Primary files:

- `build.zig`
- `tests/cli_smoke.zig`
- `tests/plugin_host_smoke.zig`
- `tests/sa_std_runtime.zig`
- `tests/sa_term_runtime.zig`
- `tests/wasm_matrix_smoke.zig`

Verification:

```powershell
zig build core -Dllvm=false
zig build runtime-basic -Dllvm=false
```

Linux regression:

```bash
zig build ci
zig build linux-runtime
```

Acceptance criteria:

- Windows failures in Linux-only features are represented as skipped tests or omitted platform-specific steps, not compile errors.
- Linux `ci` still exercises the Linux-only capabilities.

### Phase 3: Package Fetch Portability

Objective: make package fetching work without POSIX fork/exec.

Tasks:

1. Replace `std.posix.fork`, `execvpeZ`, and `waitpid` in `src/pkg/fetch.zig` with `std.process.Child.run` or `std.process.Child`.
2. Preserve the security behavior:
   - no interactive terminal prompt
   - `GIT_TERMINAL_PROMPT=0`
   - `GCM_INTERACTIVE=Never`
   - inherited `PATH`, `HOME`, `USERPROFILE`, `SSL_CERT_FILE`, and `SSL_CERT_DIR` where applicable
3. Replace Unix-specific `GIT_ASKPASS=/bin/false` with a target-aware strategy:
   - Linux can keep `/bin/false`.
   - Windows should avoid setting `GIT_ASKPASS` to an invalid Unix path, or use a checked helper if one exists.
4. Add tests that verify the spawned command environment is non-interactive without relying on POSIX fork semantics.

Primary files:

- `src/pkg/fetch.zig`
- `src/pkg/pkg_core_tests.zig`

Verification:

```powershell
zig build pkg-core-test -Dllvm=false
```

Linux regression:

```bash
zig build pkg-core-test
zig build test
```

Acceptance criteria:

- Linux package fetch behavior remains non-interactive and compatible.
- Windows no longer fails to compile because of POSIX process APIs.

### Phase 4: LLVM-C Backend on Windows

Objective: support native `sa build-exe` on Windows when LLVM is installed.

Tasks:

1. Document supported LLVM versions. The current build defaults to LLVM 14; keep LLVM 14 as the first supported Windows target unless a separate LLVM API compatibility audit is completed.
2. Verify `src/emit_llvm_llvmc_shim.c` compiles with the chosen Windows C ABI.
3. Ensure `linkLLVMToModule` and `linkLLVMToCompile` accept Windows include and library paths.
4. Add a friendly diagnostic when LLVM is enabled but include/lib paths are missing or invalid.
5. Make CLI native output naming Windows-aware, including default `.exe` output where appropriate.
6. Add a focused Windows LLVM smoke test that compiles a minimal `.sa` file to an executable and runs it.

Example command shape:

```powershell
zig build `
  -Dllvm=true `
  -Dllvm-include-dir="C:\LLVM-14\include" `
  -Dllvm-lib-dir="C:\LLVM-14\lib" `
  -Dllvm-lib-name="LLVM-C"
```

The actual library name must match the installed LLVM package. It may be `LLVM-C`, `LLVM`, or a versioned import library depending on distribution.

Primary files:

- `build.zig`
- `src/emit_llvm_llvmc.zig`
- `src/emit_llvm_llvmc_shim.c`
- `src/cli.zig`
- `tests/cli_smoke.zig`

Verification:

```powershell
zig build -Dllvm=true -Dllvm-include-dir=<path> -Dllvm-lib-dir=<path> -Dllvm-lib-name=<name>
.\zig-out\bin\sa.exe build-exe demos\support\io_probe.sa -o zig-out\tmp\io_probe.exe
.\zig-out\tmp\io_probe.exe
```

Linux regression:

```bash
zig build bc2sa-smoke
zig build wasm-matrix
zig build test
```

Acceptance criteria:

- Windows native codegen works when LLVM is configured.
- Windows without LLVM still supports the Level 0 build path.
- Linux LLVM behavior remains unchanged.

### Phase 5: Plugin Loader and Manifest Targeting

Objective: support Windows dynamic plugins without changing Linux `.so` behavior.

Tasks:

1. Add target-aware dynamic library suffix helper:
   - Linux: `.so`
   - Windows: `.dll`
   - macOS, if kept in scope later: `.dylib`
2. Update runtime plugin scanning so Linux still scans `.so`, Windows scans `.dll`.
3. Update manifest artifact selection:
   - Prefer current target key, such as `windows-x86_64` or `linux-x86_64`.
   - Preserve fallback behavior only when explicitly intended.
4. Keep current Linux `linux-x86_64` manifests valid.
5. Add Windows plugin install smoke using a tiny `.dll` that exports `saasm_plugin_descriptor_v1` or `saasm_plugin_descriptor_v1_fn`.
6. Keep Linux `.so` plugin tests unchanged or target-aware.

Primary files:

- `src/plugins.zig`
- `tests/plugin_host_smoke.zig`
- plugin manifest fixtures

Verification:

```powershell
zig build plugin-host-smoke -Dllvm=false
.\zig-out\bin\sa.exe plugin list
```

Linux regression:

```bash
zig build plugin-host-smoke
zig build test
```

Acceptance criteria:

- Linux plugin discovery still accepts `.so` and `linux-x86_64`.
- Windows plugin discovery accepts `.dll` and `windows-x86_64`.
- Invalid dynamic libraries still produce diagnostics instead of crashing.

### Phase 6: Windows Permission and Path Semantics

Objective: make plugin/package permissions meaningful on Windows.

Tasks:

1. Normalize path separators in permission matching.
2. Handle Windows absolute paths, including drive-letter paths and UNC paths if in scope.
3. Decide case sensitivity rules. Recommended first pass: compare Windows paths case-insensitively after normalization.
4. Preserve existing Unix restrictions for `/dev`, `/proc`, and broad root permissions on Linux.
5. Extend dynamic loader risk symbols to keep both Linux and Windows names:
   - Linux: `dlopen`, `dlmopen`, `__libc_dlopen_mode`
   - Windows: `LoadLibraryA`, `LoadLibraryW`, `LoadLibraryExA`, `LoadLibraryExW`
6. Add Windows permission fixtures for `$PROJECT`, `$HOME`, `$SA_CACHE`, and `$SA_PLUGINS_HOME` expansions.

Primary files:

- `src/plugins.zig`
- package/plugin permission tests

Verification:

```powershell
zig build plugin-host-smoke -Dllvm=false
```

Linux regression:

```bash
zig build plugin-host-smoke
```

Acceptance criteria:

- Existing Linux permission tests still pass.
- Windows path permissions are explicit and test-covered.

## 7. CI Matrix Recommendation

Use a matrix that separates platform support from optional dependencies.

Linux required jobs:

- `zig build`
- `zig build test`
- `zig build ci`
- `zig build linux-runtime`

Windows required jobs after Level 0:

- `zig build -Dllvm=false`
- `zig build core -Dllvm=false`
- `zig build runtime-basic -Dllvm=false`

Windows optional jobs after Level 2:

- `zig build -Dllvm=true -Dllvm-include-dir=... -Dllvm-lib-dir=... -Dllvm-lib-name=...`
- native `build-exe` smoke

Windows optional jobs after Level 3:

- `zig build plugin-host-smoke -Dllvm=false`
- `.dll` plugin install/load smoke

## 8. Implementation Order

Recommended order:

1. Phase 0: build-system portability boundary.
2. Phase 1: native system runtime split.
3. Phase 2: test suite segmentation.
4. Phase 3: package fetch portability.
5. Phase 4: Windows LLVM native backend.
6. Phase 5: plugin loader and manifest targeting.
7. Phase 6: Windows permission and path semantics.

Reasoning:

- The compiler must first build without optional Linux/LLVM dependencies.
- Runtime and test segmentation make later failures more precise.
- Package and plugin support depend on correct path/process/dynamic-library helpers.
- LLVM and plugin support should be separate, because many users need the core compiler before they have a Windows LLVM installation.

## 9. Known Risks

- LLVM Windows distribution mismatch: the installed import library name may not match `LLVM-14`. Keep configuration explicit and diagnostics clear.
- Zig C ABI differences: Windows MSVC and MinGW targets may behave differently for C shims and linked libraries. Pick one first for CI, preferably the target matching the LLVM package.
- Thread ABI compatibility: pthread-like exported APIs may need a compatibility layer rather than a direct `std.Thread` replacement.
- Plugin security parity: Windows dynamic loader and process APIs have different symbol names and path semantics. Permission tests must be platform-specific.
- Test churn: many tests embed Unix paths. Avoid broad rewrites; update helpers and focused tests first.

## 10. Done Definition

Windows support is complete for the first public milestone when:

- `zig build -Dllvm=false` succeeds on Windows with Zig 0.14.1.
- `sa.exe --help` works.
- Core compiler smoke tests pass on Windows without LLVM.
- Linux `zig build test` remains passing at the same or broader scope as before the Windows work.
- Windows LLVM native codegen has a documented path and at least one passing `build-exe` smoke when LLVM is installed.
- Windows plugin support either has a passing `.dll` smoke or is explicitly documented as not included in the current milestone.

## 11. First Patch Checklist

The first implementation patch should be intentionally small:

- Add `-Dllvm` build option.
- Guard LLVM shim/link calls behind that option.
- Add target-aware `sa_std` static archive path.
- Add target-aware runtime shim selection while leaving Linux unchanged.
- Add a Windows/bootstrap build step that excludes known Linux-only tests.
- Verify Linux default build still behaves as before.

Suggested first verification commands:

```powershell
zig build -Dllvm=false
.\zig-out\bin\sa.exe --help
```

```bash
zig build
zig build test
```

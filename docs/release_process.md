# SA Release Process

> This is the English counterpart of the Chinese document [release_process_cn.md](./release_process_cn.md).

This document describes the complete steps for cutting an official release from the main branch: build artifacts for 6 platforms → tag / publish a Release on GitHub → publish `@salang/sa` to npm. Below, `<VER>` always refers to this release's version number (the tag style is a bare version number, e.g. `0.1.1`, with no `v` prefix). The current version is determined by `.version` in `build.zig.zon` (0.1.8 as of the 2026-11-05 audit).

## 0. Pre-flight checks

```sh
cd sci
git status --short          # must be clean; local builds modify artifacts/sa_std/libsa_std.a,
                            # to only verify, restore with git checkout -- artifacts/sa_std/libsa_std.a
git log --oneline -3
git tag --sort=-v:refname | head -5   # confirm the previous version and decide <VER>
zig version                 # 0.17.0 (see minimum_zig_version in build.zig.zon)
```

The version number must be changed in three places together: `.version` in `sci/build.zig.zon`, `version` in `sci/npm/packages/*/package.json` (7 packages in total), and this release's tag name.

## 1. Build artifacts for 6 platforms

Native Linux requires LLVM 14 (`sudo apt-get install -y llvm-14-dev`):

```sh
cd sci
zig build                                            # Linux x86_64, artifacts in zig-out/
zig build -Dtarget=x86_64-windows-gnu -Dllvm=false -p /tmp/sa-dist/windows-x86_64
zig build -Dtarget=aarch64-linux-gnu -Dllvm=false  -p /tmp/sa-dist/arm-aarch64
zig build -Dtarget=aarch64-macos -Dllvm=false       -p /tmp/sa-dist/mac-aarch64
zig build -Dtarget=x86_64-macos -Dllvm=false        -p /tmp/sa-dist/mac-x86_64
sh tools/build_freebsd.sh --prefix /tmp/sa-dist/freebsd-x86_64   # requires sysroot, see below
```

FreeBSD note: Zig 0.17.0 does not ship a FreeBSD libc; `tools/build_freebsd.sh` automatically downloads the 14.4-RELEASE `base.txz` (~155M) as a sysroot and generates the `-libc` files. Native alternative on a FreeBSD host: after `pkg install zig`, just run `zig build`.

Artifact verification (`file` to check the format, `--version` to check the runnable one):

```sh
file /tmp/sa-dist/linux-x86_64/bin/sa        # ELF x86-64
file /tmp/sa-dist/arm-aarch64/bin/sa         # ELF ARM aarch64
file /tmp/sa-dist/mac-aarch64/bin/sa         # Mach-O arm64
file /tmp/sa-dist/freebsd-x86_64/bin/sa      # FreeBSD 14.4 ELF, ld-elf.so.1
ls /tmp/sa-dist/windows-x86_64/bin/sa.exe
/tmp/sa-dist/linux-x86_64/bin/sa --version
```

## 2. Minimum verification gates

```sh
cd sci
zig build core -Dllvm=false     # cross-platform core checks (fast)
zig build sa-std-unit           # standard runtime unit tests
```

Notes: the full `zig build test` gate takes about 10+ minutes on this machine; under `-Dllvm=false`, `wasm-matrix` and some `plugin-host-smoke` tests fail because of `LLVM-C backend is disabled` — this is an environment limitation (install llvm-14-dev and rerun with default flags to pass). Bare `zig test src/runtime/sa_std.zig` reports a posix `@bitCast` error — that is caused by not linking libc and going down std's non-libc path; always use `zig build sa-std-unit` instead.

## 3. Package attachments and stage npm binaries

```sh
# GitHub Release attachments: one zip per platform (contains sa + hubproxy)
cd /tmp/sa-dist
for d in linux-x86_64 arm-aarch64 mac-aarch64 mac-x86_64 windows-x86_64 freebsd-x86_64; do
  (cd $d/bin && zip -q /tmp/sa-<VER>-$d.zip sa* hubproxy*)
done
ls /tmp/sa-<VER>-*.zip

# npm subpackage binaries (binaries not in git, ~95M; choose one of the two)
# A. Just finished building, stage on the build machine:
sh sci/npm/tools/stage-binaries.sh --dist /tmp/sa-dist
# B. On the release machine (e.g. a Windows laptop), fetch from the GitHub Release:
sh sci/npm/tools/fetch-binaries.sh --version <VER>
#   Windows PowerShell: powershell sci\npm\tools\fetch-binaries.ps1 -Version <VER>
```

## 4. Git commit, tag, and push

```sh
cd sci
git add <files-for-this-release> && git commit -m "..."
git tag -a <VER> -m "SA <VER>: <one-line description>"
```

Pushing requires a token with write permission; **do not write the token into command history or the remote URL**. Inject it via a header (the shell only expands `$GIT_TOKEN`, so the plaintext never appears in logs):

```sh
export GIT_TOKEN="$(cat ~/.config/sa/github_token)"   # or injected from the environment, choose one
git -c http.extraHeader="Authorization: Bearer $GIT_TOKEN" \
  push origin main <VER>
```

## 5. GitHub Release

```sh
export GH_TOKEN="$GIT_TOKEN"   # gh recognizes GH_TOKEN
gh release create <VER> /tmp/sa-<VER>-*.zip \
  --repo layola13/sci \
  --title "SA <VER>" \
  --notes "<release notes: merged content / platform matrix / known limitations>"
```

After publishing, check that all 6 zips are present in the Release page attachments.

## 6. npm packaging and publish (`@salang/sa`, esbuild-style 7 packages)

### 6.1 Package structure

`sci/npm/` (already in the repo; binaries are not in git, see `npm/.gitignore`):

| Package | Contents | Notes |
|---|---|---|
| `@salang/sa` | `bin/sa.js` launcher + README + LICENSE | `bin: {sa: bin/sa.js}`, zero dependencies; looks up the platform subpackage by `platform-arch`, then `spawnSync` inheriting stdio, exit code passed through |
| `@salang/sa-<os>-<arch>` ×6 | `bin/sa` (or `sa.exe`) + README | has `os`/`cpu` fields, so npm only downloads the one matching the platform at install time |

When launcher resolution fails it reports a clear error (unsupported platform / missing platform package) rather than silently swallowing it. In the 0.0.x stage only the `sa` main binary is installed; `hubproxy` and the plugin SDK will be added in later versions.

Version rule: `optionalDependencies` pins the exact same version number (no `^`); all 7 packages are versioned and published together.

### 6.2 Binary sources (choose one of the two)

```sh
# A. Stage on the build machine (when you just finished building the 6-platform artifacts)
sh sci/npm/tools/stage-binaries.sh --dist /tmp/sa-dist
# B. Fetch on the release machine (a machine like a Windows laptop that does not rebuild;
#    the version number must match the Release tag)
sh sci/npm/tools/fetch-binaries.sh --version <VER>
#   Windows PowerShell: powershell sci\npm\tools\fetch-binaries.ps1 -Version <VER>
```

After fetching, verify: use `strings` to check the embedded version inside the binary (e.g. `0.1.2`); strings from older versions must not remain; the Linux package can run `bin/sa --version` directly. Note that `sa --version` is baked into the binary at compile time (`latestGitTag()` takes the first line of `git tag` at that moment) — you must rebuild after tagging, or it will report the old version.

### 6.3 Publishing

The order cannot be reversed (first the 6 platform packages, then the meta package), and scoped packages require `--access public`:

```sh
npm login   # an account with publish permission for the salang organization
cd sci/npm/packages
for p in sa-linux-x64 sa-linux-arm64 sa-darwin-arm64 sa-darwin-x64 \
         sa-win32-x64 sa-freebsd-x64; do
  (cd "$p" && npm publish --access public)
done
cd sa && npm publish --access public
```

Or use a single command (Linux: `sh sci/npm/tools/publish-all.sh`; Windows: `powershell sci\npm\tools\publish-all.ps1`, supports `--dry-run` rehearsal).

Post-publish verification: `npm install -g @salang/sa && sa --version`.

### 6.4 Known pitfalls

- The repo-root `.gitignore` entries `bin` / `bin/` used to match globally and would swallow `npm/packages/sa/bin/sa.js`, causing the launcher to be omitted from commits. They have been narrowed to root-only (`/bin/`). After adding any new npm package structure with a `bin` directory, always use `git status` to confirm the launcher is listed and `npm pack --dry-run` to check the file manifest.

### 6.5 Notes for the Windows release machine

A Windows laptop that pulls the repo can publish directly, with no Linux permission handling needed — the following two cases are already covered:

- Executable bit: zip/tar extraction on Windows loses Unix exec bits (`bin/sa` lands as 0644). The launcher (`packages/sa/bin/sa.js`) calls `fs.chmodSync(binPath, 0o755)` on the binary before `spawnSync`, restoring it automatically at runtime; the `sa.js` declared in `bin` itself is forcibly given +x by npm at install time. Bypasses that execute `.../bin/sa` directly are unsupported; always go through the `sa` command.
- Line endings: `.gitattributes` pins `*.sh`, workflow yml, and `npm/packages/sa/bin/sa.js` to `text eol=lf`. A Windows checkout (autocrlf) will not write the launcher as CRLF — otherwise its first-line shebang would fail on Linux/macOS. When adding executable scripts to release artifacts, remember to add a corresponding line.

Windows release workflow (fetch binaries, no rebuild):

```powershell
powershell sci\npm\tools\fetch-binaries.ps1 -Version <VER>
powershell sci\npm\tools\publish-all.ps1 --dry-run   # rehearse first
powershell sci\npm\tools\publish-all.ps1             # 6 platform packages + meta package
```

The full native mac version (LLVM backend) requires running `zig build` on a mac machine, then placing the artifacts in the corresponding directories under `/tmp/sa-dist` and running `stage-binaries.sh` (the dylibs from `llvm@14` are bundled automatically); the same applies to Windows (`LLVM-C.dll` is bundled automatically). You can publish a bootstrap version first and add the full version later.

## 7. Documentation sync

- After adding/updating the "multi-platform compilation" section under `content/13_build/` in sala, run `python build.py` to confirm 115+ topics build successfully;
- Keep the commands and version numbers in this file consistent with the sala section.

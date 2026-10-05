#!/usr/bin/env node
'use strict';
// @salang/sa launcher: pick the platform package installed via
// optionalDependencies and exec its `sa` binary with inherited stdio.
// No runtime dependencies; works on Node >= 16.
// Since 0.1.5 the launcher also prepends the bundled bin/ dir to the
// platform loader path (LD_LIBRARY_PATH / DYLD_LIBRARY_PATH / PATH) so a
// bundled libLLVM-14 / LLVM-C.dll is found without system installs, and
// prints per-OS fix hints when the loader still fails.
const path = require('path');
const fs = require('fs');
const { spawnSync } = require('child_process');

const PLATFORMS = {
  'linux-x64': { pkg: '@salang/sa-linux-x64', bin: 'sa' },
  'linux-arm64': { pkg: '@salang/sa-linux-arm64', bin: 'sa' },
  'darwin-arm64': { pkg: '@salang/sa-darwin-arm64', bin: 'sa' },
  'darwin-x64': { pkg: '@salang/sa-darwin-x64', bin: 'sa' },
  'win32-x64': { pkg: '@salang/sa-win32-x64', bin: 'sa.exe' },
  'freebsd-x64': { pkg: '@salang/sa-freebsd-x64', bin: 'sa' },
};

function bundledLibDir(binPath) {
  return path.dirname(binPath);
}

function withBundledLibEnv(binPath) {
  // Prefer libs shipped inside the platform package (bin/libLLVM-*.so*,
  // bin/libLLVM*.dylib, bin/LLVM-C.dll) over any system copy. This covers
  // binaries whose RPATH was stripped by tar/zip, and lets stage-binaries.sh
  // bundle libLLVM without requiring patchelf/install_name_tool on user machines.
  const dir = bundledLibDir(binPath);
  const env = Object.assign({}, process.env);
  try {
    fs.accessSync(dir);
  } catch {
    return env;
  }
  const delim = process.platform === 'win32' ? ';' : ':';
  if (process.platform === 'linux' || process.platform === 'freebsd') {
    env.LD_LIBRARY_PATH = env.LD_LIBRARY_PATH
      ? dir + delim + env.LD_LIBRARY_PATH
      : dir;
  } else if (process.platform === 'darwin') {
    env.DYLD_LIBRARY_PATH = env.DYLD_LIBRARY_PATH
      ? dir + delim + env.DYLD_LIBRARY_PATH
      : dir;
  } else if (process.platform === 'win32') {
    env.Path = env.Path ? dir + delim + env.Path : dir;
    env.PATH = env.PATH ? dir + delim + env.PATH : dir;
  }
  return env;
}

function missingLibHint(key, detail) {
  const lines = [];
  lines.push(`@salang/sa: failed to start the bundled binary.`);
  if (detail) lines.push(`  detail: ${detail}`);
  if (key === 'linux-x64' || key === 'linux-arm64') {
    lines.push(`  cause: the sa binary needs LLVM 14 runtime (libLLVM-14.so.1), not present on this system.`);
    lines.push(`  fix (pick one):`);
    lines.push(`    1) reinstall latest @salang/sa (bundles libLLVM since 0.1.5): npm install -g @salang/sa@latest`);
    lines.push(`    2) Ubuntu 24.04: sudo apt-get install -y libllvm14t64   # t64 rename, NOT libllvm14`);
    lines.push(`       Ubuntu 22.04 / Debian 12: sudo apt-get install -y libllvm14`);
    lines.push(`       Fedora: sudo dnf install -y llvm14-libs`);
    lines.push(`       Arch: sudo pacman -S --needed llvm14-libs`);
    lines.push(`       Alpine (musl): glibc binary unsupported, use debian:bookworm-slim container or build from source (zig build -Dllvm=false).`);
  } else if (key === 'darwin-arm64' || key === 'darwin-x64') {
    lines.push(`  cause: missing LLVM 14 dylib (libLLVM.dylib).`);
    lines.push(`  fix: brew install llvm@14   # then: npm install -g @salang/sa@latest`);
  } else if (key === 'win32-x64') {
    lines.push(`  cause: missing LLVM-C.dll next to sa.exe, or missing VC++ runtime.`);
    lines.push(`  fix: reinstall: npm install -g @salang/sa@latest ; if still failing install VC++ redist (aka.ms/vc-redist).`);
  } else if (key === 'freebsd-x64') {
    lines.push(`  cause: missing LLVM 14 runtime.`);
    lines.push(`  fix: pkg install -y llvm14`);
  }
  lines.push(`  verify: sa --version   (expect: sa <version>)`);
  return lines.join('\n');
}

function isMissingLibFailure(r, stderrTail) {
  const text = `${r.error ? r.error.message : ''}\n${stderrTail || ''}`;
  return (
    r.status === 127 ||
    /libLLVM|LLVM-C|libllvm|LLVM\.dll|error while loading shared librar/i.test(text)
  );
}

// Commands that shell out to `zig cc` AFTER LLVM bitcode emission
// (driver/zigcc.zig): build-exe/obj/wasm all link via zig, and `test`
// compiles+native-runs via LLVM. `run` uses the pure-Zig interpreter and
// needs neither LLVM nor zig; verify/layout/size/graph/skills need neither.
const ZIG_CHILD_COMMANDS = new Set([
  'build',
  'build-exe',
  'build-obj',
  'build-wasm',
  'build-workspace',
  'test',
]);

function findOnPath(name) {
  const pathEnv = process.env.PATH || process.env.Path || '';
  const delim = process.platform === 'win32' ? ';' : ':';
  const exts =
    process.platform === 'win32'
      ? (process.env.PATHEXT || '.EXE;.CMD;.BAT').split(';')
      : [''];
  for (const dir of pathEnv.split(delim)) {
    if (!dir) continue;
    for (const ext of exts) {
      const cand = path.join(dir, name + ext.toLowerCase());
      try {
        fs.accessSync(cand, fs.constants.X_OK);
        return cand;
      } catch {}
      const candUpper = path.join(dir, name + ext);
      if (candUpper !== cand) {
        try {
          fs.accessSync(candUpper, fs.constants.X_OK);
          return candUpper;
        } catch {}
      }
    }
  }
  return null;
}

function maybeWarnMissingZig(subcommand) {
  if (!subcommand || !ZIG_CHILD_COMMANDS.has(subcommand)) return;
  if (findOnPath('zig')) return;
  const msg = [
    `@salang/sa: 'zig' not found on PATH — 'sa ${subcommand}' will fail at the link step.`,
    `  pipeline: .sa -> LLVM-C bitcode (.sa.bc) -> zig cc ${subcommand === 'build-wasm' ? '-target wasm32-wasi ' : ''}-> output`,
    `  fix: install zig 0.14.1 and ensure 'zig version' works.`,
    `    Linux/macOS/Windows: https://ziglang.org/download/0.14.1/`,
    `    FreeBSD x86_64 (no upstream build): https://github.com/layola13/sci/releases/download/zig-0.14.1-freebsd/zig-x86_64-freebsd-0.14.1.tar.xz`,
    `  notes: 'sa run' needs no zig (pure interpreter); build-wasm needs no extra wasi-sdk (zig bundles wasi-libc).`,
  ].join('\n');
  console.error(msg);
}

function main() {
  const key = `${process.platform}-${process.arch}`;
  const entry = PLATFORMS[key];
  if (!entry) {
    console.error(
      `@salang/sa: unsupported platform "${key}". ` +
        `Supported: ${Object.keys(PLATFORMS).join(', ')}.`
    );
    process.exit(1);
  }
  let binPath;
  try {
    const pkgJson = require.resolve(`${entry.pkg}/package.json`);
    binPath = path.join(path.dirname(pkgJson), 'bin', entry.bin);
  } catch (e) {
    console.error(
      `@salang/sa: platform package "${entry.pkg}" is not installed. ` +
        `Reinstall with: npm install -f @salang/sa`
    );
    process.exit(1);
  }
  // Tarballs packed on Windows lose the Unix exec bit (binaries land as
  // 0644). Restore it before exec; harmless no-op where it doesn't apply.
  try {
    fs.chmodSync(binPath, 0o755);
  } catch {}
  // Bundled sa_std: the @salang/sa meta package ships the SA source stdlib
  // under sa_std/. Point SA_STD_DIR at it unless the user already set one;
  // the compiler prefers SA_STD_DIR over any baked-in fallback path.
  if (!process.env.SA_STD_DIR) {
    try {
      const metaDir = path.dirname(require.resolve('@salang/sa/package.json'));
      const bundled = path.join(metaDir, 'sa_std');
      fs.accessSync(path.join(bundled, 'io', 'print.sai'));
      fs.accessSync(path.join(bundled, 'core', 'sa_core.sa'));
      process.env.SA_STD_DIR = bundled;
    } catch {}
  }
  const r = spawnSync(binPath, process.argv.slice(2), {
    stdio: 'inherit',
    env: withBundledLibEnv(binPath),
  });
  // Pre-link hint only: sa itself reports error[ExternalCompiler] when zig is
  // absent; this surfaces the fix earlier without changing exit semantics.
  // (Checked after spawn so `--help` etc. stay silent when zig is missing.)
  if (r.status !== 0) maybeWarnMissingZig(process.argv[2]);
  if (r.error) {
    // spawnSync surfaces loader failures (e.g. missing libLLVM-14.so.1 yields
    // ENOENT from the dynamic loader) as r.error; status 127 covers shim cases.
    console.error(missingLibHint(key, `failed to run ${binPath}: ${r.error.message}`));
    process.exit(1);
  }
  if (r.status !== 0 && isMissingLibFailure(r, '')) {
    console.error(missingLibHint(key, `exit code ${r.status}`));
  }
  process.exit(r.status === null ? 1 : r.status);
}

main();

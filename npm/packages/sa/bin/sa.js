#!/usr/bin/env node
'use strict';
// @salang/sa launcher (0.0.1): pick the platform package installed via
// optionalDependencies and exec its `sa` binary with inherited stdio.
// No runtime dependencies; works on Node >= 16.
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
  const r = spawnSync(binPath, process.argv.slice(2), { stdio: 'inherit' });
  if (r.error) {
    console.error(`@salang/sa: failed to run ${binPath}: ${r.error.message}`);
    process.exit(1);
  }
  process.exit(r.status === null ? 1 : r.status);
}

main();

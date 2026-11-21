#!/usr/bin/env python3
"""fix_cli_compile16.py — sixth wave of the cli-split fix (10 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  cguForceParallel -> cli/compile.zig (boolEnv sibling)
  projectCacheStore + copyFileAlloc + projectCacheWriteManifest +
  enforceProjectCacheBudget -> cli/cache.zig (cache cluster)
  sabPruneDebugEnabled, cacheCompilerVersion, projectCacheRemoveKey,
  hashFileHex, hashOpenFileHex -> cli/cache.zig
In-place (too big to move with its cluster):
  verifyProjectPackageState: `fn` -> `pub fn` in cli.zig; compile.zig imports
  it from ../cli.zig (cycle already proven OK by daemon.zig in wave 1).
Pure import additions:
  build_exe.zig: printLlvmcEmitError (errors.zig), CompileOk (types.zig)
  build_lib.zig: printLlvmcEmitError (errors.zig)
  compile.zig: verifyProjectPackageState (../cli.zig)
NOTE: cache.zig will temporarily exceed 700 lines after this round; it gets
split in the endgame (projectCache* cluster -> project_cache.zig).
Run from /content/sa_all/sci2.
"""
import re
from fix_cli_compile11 import move_fn, add_import

def make_pub(path, name):
    lines = open(path).read().split("\n")
    for i, l in enumerate(lines):
        if re.match(r"^fn " + re.escape(name) + r"\(", l):
            lines[i] = "pub " + l
            open(path, "w").write("\n".join(lines))
            print(f"made pub in place: {path}: {name} (line {i+1})")
            return
    raise AssertionError(f"{name} not found in {path}")

def main():
    cli = "src/cli.zig"
    move_fn(cli, "cguForceParallel", "src/cli/compile.zig", "cli/compile.zig")
    for name in ("projectCacheStore", "copyFileAlloc", "projectCacheWriteManifest",
                 "enforceProjectCacheBudget", "sabPruneDebugEnabled",
                 "cacheCompilerVersion", "projectCacheRemoveKey",
                 "hashFileHex", "hashOpenFileHex"):
        move_fn(cli, name, "src/cli/cache.zig", "cli/cache.zig")
    make_pub(cli, "verifyProjectPackageState")
    add_import("src/cli/build_exe.zig", 'const printLlvmcEmitError = @import("errors.zig").printLlvmcEmitError;')
    add_import("src/cli/build_exe.zig", 'const CompileOk = @import("types.zig").CompileOk;')
    add_import("src/cli/build_lib.zig", 'const printLlvmcEmitError = @import("errors.zig").printLlvmcEmitError;')
    add_import("src/cli/compile.zig", 'const verifyProjectPackageState = @import("../cli.zig").verifyProjectPackageState;')
    print("done")

if __name__ == "__main__":
    main()

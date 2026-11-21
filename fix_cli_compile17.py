#!/usr/bin/env python3
"""fix_cli_compile17.py — seventh wave of the cli-split fix (12 errors).

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  cacheFunctionSig, cacheU64, cacheBool, computeFunctionObjectKey,
  cacheBuildSemanticFlags, projectCacheTouchEntry, projectCacheBudgetBytes,
  sourceHashHex -> cli/cache.zig (cache-hash cluster)
  libContractCType, writeLibCParams, generateLibHeader -> cli/build_lib.zig
Pure import additions (incl. ones missed in earlier waves):
  build_exe.zig: cguForceParallel (compile.zig), projectCacheStore (cache.zig)
  cache.zig: ensureParentDir (compile.zig), referee (../referee.zig, for
    computeFunctionObjectKey's VerifyOk param)
  compile.zig: trapFromPackagePreflightError (trap_errors.zig)
NOTE: cache.zig keeps growing past 700; it gets split in the endgame once
the build is green (projectCache* cluster -> project_cache.zig).
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn, add_import

def main():
    cli = "src/cli.zig"
    for name in ("cacheFunctionSig", "cacheU64", "cacheBool",
                 "computeFunctionObjectKey", "cacheBuildSemanticFlags",
                 "projectCacheTouchEntry", "projectCacheBudgetBytes",
                 "sourceHashHex"):
        move_fn(cli, name, "src/cli/cache.zig", "cli/cache.zig")
    for name in ("libContractCType", "writeLibCParams", "generateLibHeader"):
        move_fn(cli, name, "src/cli/build_lib.zig", "cli/build_lib.zig")
    add_import("src/cli/build_exe.zig", 'const cguForceParallel = @import("compile.zig").cguForceParallel;')
    add_import("src/cli/build_exe.zig", 'const projectCacheStore = @import("cache.zig").projectCacheStore;')
    add_import("src/cli/cache.zig", 'const ensureParentDir = @import("compile.zig").ensureParentDir;')
    add_import("src/cli/cache.zig", 'const referee = @import("../referee.zig");')
    add_import("src/cli/compile.zig", 'const trapFromPackagePreflightError = @import("trap_errors.zig").trapFromPackagePreflightError;')
    print("done")

if __name__ == "__main__":
    main()

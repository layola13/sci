#!/usr/bin/env python3
"""fix_cli_compile19.py — ninth wave of the cli-split fix (7 errors).

Moves (cli.zig -> submodule, pub, alias left in cli.zig):
  projectFunctionCachePath, projectPathExists, writeCacheArtifactManifestEntry,
  CacheEvictionCandidate (struct) + cacheEvictionCandidateLessThan -> cli/cache.zig
  generateLibVersionScript -> cli/build_lib.zig
  manifestPluginImportRoots -> cli/compile.zig
Pure import additions:
  build_exe.zig: DceMode (../emit_options.zig), projectFunctionCachePath (cache.zig)
  compile.zig: plugins (../plugins.zig, for manifestPluginImportRoots)
Run from /content/sa_all/sci2.
"""
import re
from fix_cli_compile11 import move_fn, add_import, find_fn_end

def move_type(src_path, name, dst_path, dst_import_from_src):
    """Move `const NAME = struct {...};` (or any const with a braced body)."""
    lines = open(src_path).read().split("\n")
    start = None
    for i, l in enumerate(lines):
        if re.match(r"^const " + re.escape(name) + r" = ", l):
            start = i
            break
    assert start is not None, f"{name} not found in {src_path}"
    end = find_fn_end(lines, start)
    block = lines[start:end + 1]
    assert block[-1] in ("};", "}"), block[-1]
    for idx, l in enumerate(block):
        if l.startswith("const "):
            block[idx] = "pub " + l
            break
    dst = open(dst_path).read()
    if not dst.endswith("\n"):
        dst += "\n"
    dst += "\n" + "\n".join(block) + "\n"
    open(dst_path, "w").write(dst)
    alias = f"const {name} = @import(\"{dst_import_from_src}\").{name};"
    lines[start:end + 1] = [alias]
    open(src_path, "w").write("\n".join(lines))
    print(f"moved type {name}: {src_path} lines {start+1}..{end+1} -> {dst_path}")

def main():
    cli = "src/cli.zig"
    for name in ("projectFunctionCachePath", "projectPathExists",
                 "writeCacheArtifactManifestEntry"):
        move_fn(cli, name, "src/cli/cache.zig", "cli/cache.zig")
    move_type(cli, "CacheEvictionCandidate", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "cacheEvictionCandidateLessThan", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "generateLibVersionScript", "src/cli/build_lib.zig", "cli/build_lib.zig")
    move_fn(cli, "manifestPluginImportRoots", "src/cli/compile.zig", "cli/compile.zig")
    add_import("src/cli/build_exe.zig", 'const DceMode = @import("../emit_options.zig").DceMode;')
    add_import("src/cli/build_exe.zig", 'const projectFunctionCachePath = @import("cache.zig").projectFunctionCachePath;')
    add_import("src/cli/compile.zig", 'const plugins = @import("../plugins.zig");')
    print("done")

if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""fix_cli_compile18.py — eighth wave of the cli-split fix (7 errors).

Moves (cli.zig -> submodule, pub, alias left in cli.zig):
  cgu_seq_fn_threshold (single-line const) -> cli/compile.zig
  generateLibApiSource -> cli/build_lib.zig
  cacheRootPath -> cli/cache.zig
  manifestDependencies -> cli/compile.zig
In-place (drags a memoization subsystem; becomes its own module in endgame):
  stdTreeDigest: `fn` -> `pub fn` in cli.zig; cache.zig imports it from ../cli.zig
Pure import additions:
  build_exe.zig: computeFunctionObjectKey (cache.zig; missed in wave 7)
  cache.zig: writeJsonString (json.zig), stdTreeDigest (../cli.zig)
Run from /content/sa_all/sci2.
"""
import re
from fix_cli_compile11 import move_fn, add_import
from fix_cli_compile16 import make_pub

def move_const(src_path, name, dst_path, dst_import_from_src):
    lines = open(src_path).read().split("\n")
    idx = None
    for i, l in enumerate(lines):
        if re.match(r"^const " + re.escape(name) + r"\b", l):
            idx = i
            break
    assert idx is not None, f"{name} not found in {src_path}"
    line = lines[idx]
    assert line.rstrip().endswith(";"), f"multi-line const not supported: {line}"
    pub_line = "pub " + line
    dst = open(dst_path).read()
    if not dst.endswith("\n"):
        dst += "\n"
    dst += "\n" + pub_line + "\n"
    open(dst_path, "w").write(dst)
    alias = f"const {name} = @import(\"{dst_import_from_src}\").{name};"
    lines[idx] = alias
    open(src_path, "w").write("\n".join(lines))
    print(f"moved const {name}: {src_path} line {idx+1} -> {dst_path}")

def main():
    cli = "src/cli.zig"
    move_const(cli, "cgu_seq_fn_threshold", "src/cli/compile.zig", "cli/compile.zig")
    move_fn(cli, "generateLibApiSource", "src/cli/build_lib.zig", "cli/build_lib.zig")
    move_fn(cli, "cacheRootPath", "src/cli/cache.zig", "cli/cache.zig")
    move_fn(cli, "manifestDependencies", "src/cli/compile.zig", "cli/compile.zig")
    make_pub(cli, "stdTreeDigest")
    add_import("src/cli/build_exe.zig", 'const computeFunctionObjectKey = @import("cache.zig").computeFunctionObjectKey;')
    add_import("src/cli/build_exe.zig", 'const cgu_seq_fn_threshold = @import("compile.zig").cgu_seq_fn_threshold;')
    add_import("src/cli/cache.zig", 'const writeJsonString = @import("json.zig").writeJsonString;')
    add_import("src/cli/cache.zig", 'const stdTreeDigest = @import("../cli.zig").stdTreeDigest;')
    print("done")

if __name__ == "__main__":
    main()

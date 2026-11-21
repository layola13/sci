#!/usr/bin/env python3
"""fix_cli_compile11.py — fix the 16 build errors left by the in-progress cli split.

Moves (cli.zig -> submodule, pub fn, alias left in cli.zig):
  memoryEndPrevious        -> cli/types.zig
  setFile                  -> cli/trap_errors.zig
  markSabReachableByName,
  markSabReachableVtableConstByName,
  markSabReachableVtableConstFromOperand,
  collectSabSelectedReachability -> cli/cache.zig
Pure import additions:
  build_exe.zig: BuildCacheKind, CompileMemoryMetrics, memoryEndPrevious (types.zig)
  build_lib.zig: printTrapReport (errors.zig)
  cache.zig: pathJoinAlloc (compile.zig), ProjectContext, BuildCacheKind (types.zig),
             manifest (../pkg/manifest.zig), build_options, referee_call (../referee/call.zig)
  compile.zig: setFile (trap_errors.zig)
  daemon.zig: executeWithWritersAndOptions (../cli.zig) — cycle test; Zig lazy decls
              should tolerate it (cli.zig already imports daemon.zig).
Run from /content/sa_all/sci2.
"""
import re, sys

def find_fn_end(lines, start):
    """start = 0-based index of a line starting with 'fn NAME('. Return 0-based
    index of the line with the matching closing brace. Brace-counts code only:
    skips // comments, /* */ comments, "..." strings, and \\\\ multiline strings."""
    depth = 0
    started = False
    i = start
    in_block_comment = False
    while i < len(lines):
        line = lines[i]
        j = 0
        # multiline string line: whole line is string content
        if line.startswith("\\\\"):
            i += 1
            continue
        while j < len(line):
            if in_block_comment:
                end = line.find("*/", j)
                if end == -1:
                    j = len(line)
                else:
                    in_block_comment = False
                    j = end + 2
                continue
            c = line[j]
            if c == "/" and j + 1 < len(line) and line[j + 1] == "/":
                break  # rest of line is a comment
            if c == "/" and j + 1 < len(line) and line[j + 1] == "*":
                in_block_comment = True
                j += 2
                continue
            if c == '"':
                j += 1
                while j < len(line):
                    if line[j] == "\\":
                        j += 2
                        continue
                    if line[j] == '"':
                        j += 1
                        break
                    j += 1
                continue
            if c == "'":
                j += 1
                while j < len(line):
                    if line[j] == "\\":
                        j += 2
                        continue
                    if line[j] == "'":
                        j += 1
                        break
                    j += 1
                continue
            if c == "{":
                depth += 1
                started = True
            elif c == "}":
                depth -= 1
                if started and depth == 0:
                    return i
            j += 1
        i += 1
    raise AssertionError(f"no fn end found from line {start+1}")

def extract_fn(path, name):
    lines = open(path).read().split("\n")
    start = None
    for i, l in enumerate(lines):
        if re.match(r"^fn " + re.escape(name) + r"\(", l):
            start = i
            break
    assert start is not None, f"{name} not found in {path}"
    # include leading /// doc comment lines
    while start > 0 and lines[start - 1].startswith("///"):
        start -= 1
    end = find_fn_end(lines, start if lines[start].startswith("fn ") else start)
    block = lines[start:end + 1]
    assert block[0].startswith("fn ") or block[0].startswith("///"), block[0]
    assert block[-1] == "}", block[-1]
    return lines, start, end, block

def move_fn(src_path, name, dst_path, dst_import_from_src):
    """Move top-level fn `name` from src_path to dst_path as `pub fn`.
    Replace it in src with `const name = @import("dst").name;`."""
    lines, start, end, block = extract_fn(src_path, name)
    # make pub
    for idx, l in enumerate(block):
        if l.startswith("fn "):
            block[idx] = "pub " + l
            break
    else:
        raise AssertionError(f"no fn line in {name} block")
    dst = open(dst_path).read()
    if not dst.endswith("\n"):
        dst += "\n"
    dst += "\n" + "\n".join(block) + "\n"
    open(dst_path, "w").write(dst)
    alias = f"const {name} = @import(\"{dst_import_from_src}\").{name};"
    lines[start:end + 1] = [alias]
    open(src_path, "w").write("\n".join(lines))
    print(f"moved {name}: {src_path} lines {start+1}..{end+1} -> {dst_path} ({len(block)} lines)")

def add_import(path, line):
    text = open(path).read()
    if line.strip() in text:
        print(f"skip (exists): {path}: {line.strip()}")
        return
    lines = text.split("\n")
    # insert after the last consecutive const ... = @import(...) line near the top
    insert_at = 0
    for i, l in enumerate(lines[:60]):
        if re.match(r"^const \w+ = @import\(", l):
            insert_at = i + 1
    lines.insert(insert_at, line)
    open(path, "w").write("\n".join(lines))
    print(f"added import to {path}: {line}")

def main():
    cli = "src/cli.zig"
    # 1. memoryEndPrevious -> types.zig
    move_fn(cli, "memoryEndPrevious", "src/cli/types.zig", "cli/types.zig")
    # 2. setFile -> trap_errors.zig
    move_fn(cli, "setFile", "src/cli/trap_errors.zig", "cli/trap_errors.zig")
    # 3. SAB reachability cluster -> cache.zig (order: helpers first)
    for name in ("markSabReachableByName",
                 "markSabReachableVtableConstByName",
                 "markSabReachableVtableConstFromOperand",
                 "collectSabSelectedReachability"):
        move_fn(cli, name, "src/cli/cache.zig", "cli/cache.zig")
    # 4. pure imports
    add_import("src/cli/build_exe.zig", 'const BuildCacheKind = @import("types.zig").BuildCacheKind;')
    add_import("src/cli/build_exe.zig", 'const CompileMemoryMetrics = @import("types.zig").CompileMemoryMetrics;')
    add_import("src/cli/build_exe.zig", 'const memoryEndPrevious = @import("types.zig").memoryEndPrevious;')
    add_import("src/cli/build_lib.zig", 'const printTrapReport = @import("errors.zig").printTrapReport;')
    add_import("src/cli/cache.zig", 'const pathJoinAlloc = @import("compile.zig").pathJoinAlloc;')
    add_import("src/cli/cache.zig", 'const ProjectContext = @import("types.zig").ProjectContext;')
    add_import("src/cli/cache.zig", 'const BuildCacheKind = @import("types.zig").BuildCacheKind;')
    add_import("src/cli/cache.zig", 'const manifest = @import("../pkg/manifest.zig");')
    add_import("src/cli/cache.zig", 'const build_options = @import("build_options");')
    add_import("src/cli/cache.zig", 'const referee_call = @import("../referee/call.zig");')
    add_import("src/cli/compile.zig", 'const setFile = @import("trap_errors.zig").setFile;')
    add_import("src/cli/daemon.zig", 'const executeWithWritersAndOptions = @import("../cli.zig").executeWithWritersAndOptions;')
    print("done")

if __name__ == "__main__":
    main()

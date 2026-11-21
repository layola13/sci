#!/usr/bin/env python3
"""Batch move from cli.zig: route.zig (routeProjectVerb + routeLanguageFrontend),
check.zig (compileSourceForCheck + executeCheck), encode.zig (executeEncodeFragment).
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn

BASE = (
    "const std = @import(\"std\");\n"
    "const sio = @import(\"sio\");\n"
    "const CompileOptions = @import(\"types.zig\").CompileOptions;\n"
    "const DiagnosticsMode = @import(\"types.zig\").DiagnosticsMode;\n"
)


def main():
    cli = "src/cli.zig"
    for dst, fns in (
        ("src/cli/route.zig", ("routeProjectVerb", "routeLanguageFrontend")),
        ("src/cli/check.zig", ("compileSourceForCheck", "executeCheck")),
        ("src/cli/encode.zig", ("executeEncodeFragment",)),
    ):
        open(dst, "w").write(BASE)
        print(f"created {dst}")
        for name in fns:
            move_fn(cli, name, dst, "cli/" + dst.split("/")[-1])
    print("done")


if __name__ == "__main__":
    main()

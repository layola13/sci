#!/usr/bin/env python3
"""Move executeTest + executeTestInner from cli.zig to src/cli/test_cmd.zig.
Base header included; missing deps fixed via build waves.
Run from /content/sa_all/sci2.
"""
from fix_cli_compile11 import move_fn

def main():
    cli = "src/cli.zig"
    dst = "src/cli/test_cmd.zig"
    header = (
        "const std = @import(\"std\");\n"
        "const builtin = @import(\"builtin\");\n"
        "const sio = @import(\"sio\");\n"
        "const CompileOptions = @import(\"types.zig\").CompileOptions;\n"
        "const TestCommandOptions = @import(\"types.zig\").TestCommandOptions;\n"
        "const DiagnosticsMode = @import(\"types.zig\").DiagnosticsMode;\n"
    )
    open(dst, "w").write(header)
    print(f"created {dst}")
    for name in ("executeTest", "executeTestInner"):
        move_fn(cli, name, dst, "cli/test_cmd.zig")
    print("done")

if __name__ == "__main__":
    main()

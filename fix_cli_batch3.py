#!/usr/bin/env python3
"""Batch move from cli.zig: skills.zig (skillsCommand + writeSaAgentSkills +
writeSaAgentSkillMarkdown + appendOfficialPluginInfo + collectOfficialSaPluginsSurface),
misc_cmd.zig (executeGraph + executeLayout + executeCacheCommand + executeSize +
cleanCacheKindDir + executeRun + executeInit + fixCommand + parseInstallArgs).
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
        ("src/cli/skills.zig", ("skillsCommand", "writeSaAgentSkills", "writeSaAgentSkillMarkdown", "appendOfficialPluginInfo", "collectOfficialSaPluginsSurface")),
        ("src/cli/misc_cmd.zig", ("executeGraph", "executeLayout", "executeCacheCommand", "executeSize", "cleanCacheKindDir", "executeRun", "executeInit", "fixCommand", "parseInstallArgs")),
    ):
        open(dst, "w").write(BASE)
        print(f"created {dst}")
        for name in fns:
            move_fn(cli, name, dst, "cli/" + dst.split("/")[-1])
    print("done")


if __name__ == "__main__":
    main()

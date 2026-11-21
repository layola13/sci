const std = @import("std");
const writeJsonString = @import("json.zig").writeJsonString;
const writeJsonStringArray = @import("json.zig").writeJsonStringArray;
const writeMaybeJsonString = @import("json.zig").writeMaybeJsonString;
const sio = @import("sio");
const build_options = @import("build_options");
const trap = @import("../common/trap.zig");
const Command = @import("types.zig").Command;
const ExplainEntry = @import("types.zig").ExplainEntry;

pub fn isHelpFlag(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h");
}

pub fn commandHelpRequested(cmd: Command, args: []const []const u8) bool {
    if (args.len < 3) return false;
    if (isHelpFlag(args[2])) return true;
    return switch (cmd) {
        .pkg, .plugin, .cache => args.len >= 4 and isHelpFlag(args[3]),
        else => false,
    };
}

pub fn writeCompileOptionsHelp(writer: anytype) !void {
    try writer.writeAll("  --jobs auto|N                  Set parallel compile jobs\n");
    try writer.writeAll("  --dce no|std|full              Select dead-code elimination level\n");
    try writer.writeAll("  --no-incremental               Disable the default project build cache\n");
    try writer.writeAll("  --fast-math                    Let LLVM reassociate FP ops and vectorize reductions\n");
    try writer.writeAll("                                 (changes IEEE semantics; opt-in, cached separately)\n");
    try writer.writeAll("  --project-root <dir>           Use a specific project root for package resolution and .sa_cache\n");
    try writer.writeAll("  --profile                      Include compile phase timings in JSON metrics\n");
    try writer.writeAll("  --mem-report                   Print compile RSS stage samples; JSON mode includes metrics\n");
    try writer.writeAll("  --offline                      Use local package cache only\n");
    try writer.writeAll("  --ci                           Use CI package preflight behavior\n");
    try writer.writeAll("  --default-immutable            Rust-style mutability: allocations bind immutable values,\n");
    try writer.writeAll("                                 writing through them needs an exclusive borrow (`x = &mut y`)\n");
    try writer.writeAll("  --allow-unaudited-risks        Allow high-risk package audit findings\n");
    try writer.writeAll("  --yes, --auto-approve          Approve package review prompts when allowed\n");
    try writer.writeAll("  -p, --package <name>           Select a workspace member package\n");
    try writer.writeAll("  -P, --permission-set <name>    Select a named permission set (@dev = built-in dev preset: all categories open, no sa.mod needed)\n");
    try writer.writeAll("  --allow-env[=list]             Allow environment access for reviewed packages\n");
    try writer.writeAll("  --allow-net[=list]             Allow network access for reviewed packages\n");
    try writer.writeAll("  --allow-read[=list]            Allow filesystem reads for reviewed packages\n");
    try writer.writeAll("  --allow-write[=list]           Allow filesystem writes for reviewed packages\n");
    try writer.writeAll("  --allow-run[=list]             Allow process execution for reviewed packages\n");
}

pub fn writeBuildOptionsHelp(writer: anytype, artifact: []const u8, include_incremental: bool) !void {
    try writer.print("  -o <path>                      Write {s} to path\n", .{artifact});
    try writer.writeAll("  -g                             Include debug information\n");
    try writer.writeAll("  --no-debug                     Disable debug information\n");
    try writer.writeAll("  --release-small                Optimize for small release output\n");
    try writer.writeAll("  --release-fast                 Optimize for fast release output\n");
    try writer.writeAll("  --target <triple>              Cross-compile for a zig-style target triple (e.g. aarch64-linux-gnu)\n");
    if (include_incremental) try writer.print("  --incremental                  Reuse per-function cached objects when building {s}\n", .{artifact});
    try writeCompileOptionsHelp(writer);
}

pub fn printPkgHelp(writer: anytype, args: []const []const u8) !void {
    const sub = if (args.len != 0 and !isHelpFlag(args[0])) args[0] else "";
    if (std.mem.eql(u8, sub, "add")) {
        try writer.writeAll("usage: sa pkg add [options] <identity>\n\n");
        try writer.writeAll("Add a dependency to the project: fetch the package, record it as a\n");
        try writer.writeAll("require line in the project sa.mod, and refresh the project sum file.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --ref <ref>                    Fetch a specific package ref (default: HEAD)\n");
        try writer.writeAll("  --offline                      Use local package cache only\n");
        try writer.writeAll("  -g                             Install into the global package cache\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "list")) {
        try writer.writeAll("usage: sa pkg list\n\n");
        try writer.writeAll("List the dependencies declared by the project sa.mod (require and\n");
        try writer.writeAll("require_plugin lines, with their locked refs and source hashes).\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "install")) {
        try writer.writeAll("usage: sa pkg install [options] [identity]\n\n");
        try writer.writeAll("Fetch project dependencies from sa.mod, or fetch one package identity.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --offline                      Use local package cache only\n");
        try writer.writeAll("  -g                             Install into the global package cache\n");
        try writer.writeAll("  -p, --package <name>           Install one workspace member package\n");
        try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "fetch")) {
        try writer.writeAll("usage: sa pkg fetch [options] <identity>\n\n");
        try writer.writeAll("Fetch and cache one package identity.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --offline                      Use local package cache only\n");
        try writer.writeAll("  -g                             Install into the global package cache\n");
        try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "audit")) {
        try writer.writeAll("usage: sa pkg audit [options] <identity>\n\n");
        try writer.writeAll("Audit a package source tree and report required capabilities.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --format text|json             Select report format\n");
        try writer.writeAll("  --json                         Emit JSON report\n");
        try writer.writeAll("  --ci                           Fail on CI policy violations\n");
        try writer.writeAll("  --allow-unaudited-risks        Allow high-risk audit findings\n");
        try writer.writeAll("  --update-lock                  Update project package lock metadata\n");
        try writer.writeAll("  --ref <ref>                    Audit a specific package ref\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa pkg <add|install|fetch|audit|list> [options]\n\n");
    try writer.writeAll("Package add, fetch, audit, install, list, and lock commands.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  add                            Add a dependency to the project sa.mod\n");
    try writer.writeAll("  install                        Fetch project dependencies or one identity\n");
    try writer.writeAll("  fetch                          Fetch and cache one identity\n");
    try writer.writeAll("  audit                          Audit package capabilities and risk\n");
    try writer.writeAll("  list                           List declared project dependencies\n");
    try writer.writeAll("\nUse `sa pkg <subcommand> --help` for subcommand options.\n");
}

pub fn printCacheHelp(writer: anytype, args: []const []const u8) !void {
    const sub = if (args.len != 0 and !isHelpFlag(args[0])) args[0] else "";
    if (std.mem.eql(u8, sub, "clean")) {
        try writer.writeAll("usage: sa cache clean [options]\n\n");
        try writer.writeAll("Remove invalid, incomplete, or expired project cache entries from .sa_cache.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --all                          Also remove the project-local frontend cache (.sla-cache)\n");
        try writer.writeAll("  --dry-run                      Report removals without deleting files\n");
        try writer.writeAll("  --max-age-days <n>             Remove complete entries older than n days (default: 30)\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa cache <clean> [options]\n\n");
    try writer.writeAll("Inspect and clean project-local SA build/test caches.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  clean                          Remove invalid or expired .sa_cache entries\n");
    try writer.writeAll("\nUse `sa cache <subcommand> --help` for subcommand options.\n");
}

pub fn printPluginHelp(writer: anytype, args: []const []const u8) !void {
    const sub = if (args.len != 0 and !isHelpFlag(args[0])) args[0] else "";
    if (std.mem.eql(u8, sub, "install")) {
        try writer.writeAll("usage: sa plugin install [--dev] [--review] <path|sap.json|npm:<name>[@<version>]>\n\n");
        try writer.writeAll("Build, verify, and install a native SA plugin project.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --dev                          Allow development-mode install checks\n");
        try writer.writeAll("  --review                       Force review output before install\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "list")) {
        try writer.writeAll("usage: sa plugin list\n\n");
        try writer.writeAll("List installed native SA plugins.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }
    if (std.mem.eql(u8, sub, "confirm")) {
        try writer.writeAll("usage: sa plugin confirm <name> [--yes]\n\n");
        try writer.writeAll("Review and confirm an installed plugin's declared permissions and\n");
        try writer.writeAll("native libraries. Writes the permissions.lock entry that lets the\n");
        try writer.writeAll("plugin run outside development mode; never hand-write permissions.lock.\n\n");
        try writer.writeAll("Options:\n");
        try writer.writeAll("  --yes                          Confirm without an interactive prompt\n");
        try writer.writeAll("  -h, --help                     Show this help message\n");
        return;
    }

    try writer.writeAll("usage: sa plugin <install|list|confirm> [options]\n\n");
    try writer.writeAll("Install, list, and confirm native SA plugins.\n\n");
    try writer.writeAll("Subcommands:\n");
    try writer.writeAll("  install                        Install a plugin project or sap.json\n");
    try writer.writeAll("  list                           List installed plugins\n");
    try writer.writeAll("  confirm                        Confirm an installed plugin's permissions\n");
    try writer.writeAll("\nUse `sa plugin <subcommand> --help` for subcommand options.\n");
}

pub fn printCommandHelp(writer: anytype, cmd: Command, args: []const []const u8) !void {
    switch (cmd) {
        .init => {
            try writer.writeAll("usage: sa init [path]\n\n");
            try writer.writeAll("Create a new SA binary project.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .install => {
            try writer.writeAll("usage: sa install [options] [identity]\n\n");
            try writer.writeAll("Pkg alias of `sa pkg install`: install project dependencies or one package identity.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --offline                      Use local package cache only\n");
            try writer.writeAll("  -g                             Install into the global package cache\n");
            try writer.writeAll("  -p, --package <name>           Install one workspace member package\n");
            try writer.writeAll("  --ref <ref>                    Fetch a specific package ref\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .plugin => try printPluginHelp(writer, args),
        .pkg => try printPkgHelp(writer, args),
        .cache => try printCacheHelp(writer, args),
        .build => {
            try writer.writeAll("usage: sa build <file> [options]\n\n");
            try writer.writeAll("Compile a .sa source file or .sab binary to a native executable.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the executable", true);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_workspace => {
            try writer.writeAll("usage: sa build-workspace [options]\n\n");
            try writer.writeAll("Build the selected workspace member from the current workspace root or member directory.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the executable", true);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_exe => {
            try writer.writeAll("usage: sa build-exe <file> [options]\n\n");
            try writer.writeAll("Build a standalone native executable. This is an alias for `sa build`.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the executable", true);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_obj => {
            try writer.writeAll("usage: sa build-obj <file> [options]\n\n");
            try writer.writeAll("Build a native object file from a .sa source file or .sab binary.\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the object file", true);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_lib => {
            try writer.writeAll("usage: sa build-lib <file> --contract <file> [options]\n\n");
            try writer.writeAll("Build a native library from a .sa source file, .sab binary, or .sla source file plus an export contract (a .sai-style file of @export declarations). The contract is the single source for the generated C header (written next to the output), the function-pointer API table compiled into the artifact, and the linker export control: symbols not listed in the contract stay hidden.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --contract <file>              Export contract file (@export declarations; required)\n");
            try writer.writeAll("  --kind shared|static           Select the library kind (default: shared)\n");
            try writeBuildOptionsHelp(writer, "the library", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_wasm => {
            try writer.writeAll("usage: sa build-wasm <file> [options]\n\n");
            try writer.writeAll("Build a WebAssembly module from a .sa source file or .sab binary.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --target wasm32|wasm64         Select the WebAssembly target\n");
            try writeBuildOptionsHelp(writer, "the wasm module", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_js => {
            try writer.writeAll("usage: sa build-js <file> [options]\n\n");
            try writer.writeAll("Build a JavaScript module from a .sa source file or .sab binary (JS backend, coexists with LLVM).\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --format esm|cjs              Select the JS module format (default: esm)\n");
            try writer.writeAll("  --emit-dts                    Also emit a TypeScript declaration file (.d.ts) next to the JS output\n");
            try writeBuildOptionsHelp(writer, "the js module", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .build_c => {
            try writer.writeAll("usage: sa build-c <file> [options]\n\n");
            try writer.writeAll("Build a portable C file from a .sa source file or .sab binary (C backend, MVP).\n\n");
            try writer.writeAll("Options:\n");
            try writeBuildOptionsHelp(writer, "the c file", false);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .run => {
            try writer.writeAll("usage: sa run <file> [compile-options] [args...]\n\n");
            try writer.writeAll("Compile and execute a .sa source file or .sab binary.\n\n");
            try writer.writeAll("Options:\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .fetch => {
            try writer.writeAll("usage: sa fetch <identity>\n\n");
            try writer.writeAll("Pkg alias of `sa pkg fetch`: fetch and cache a remote package.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .audit => {
            try writer.writeAll("usage: sa audit <identity>\n\n");
            try writer.writeAll("Pkg alias of `sa pkg audit`: audit a package's capabilities and risk.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .graph => {
            try writer.writeAll("usage: sa graph [path] [options]\n\n");
            try writer.writeAll("Output a dependency and call graph for a source file or project.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit graph JSON\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .layout => {
            try writer.writeAll("usage: sa layout --name <TypeName> --fields <name:ty,...> [options]\n\n");
            try writer.writeAll("Compute and print struct layout information.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --name <TypeName>              Struct/type name to display\n");
            try writer.writeAll("  --fields <name:ty,...>         Comma-separated field list\n");
            try writer.writeAll("  --format text|json|debug|dict  Select output format\n");
            try writer.writeAll("  --target 32|64                 Select pointer width\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .size => {
            try writer.writeAll("usage: sa size [path] [options]\n\n");
            try writer.writeAll("Print function size statistics for a source file or project.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit size data as JSON\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .test_cmd => {
            try writer.writeAll("usage: sa test <file> [options]\n\n");
            try writer.writeAll("Run @test blocks in a .sa source file.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --list                         List selected tests after frontend checks only\n");
            try writer.writeAll("  --compile-only                 Compile and link tests without running them\n");
            try writer.writeAll("  --trace-panic                  Include panic diagnostics on failed tests\n");
            try writer.writeAll("  --test-debug                   Alias for --trace-panic\n");
            try writer.writeAll("  --filter <pattern>             Include only matching tests (repeatable)\n");
            try writer.writeAll("  --skip <pattern>               Exclude matching tests (repeatable)\n");
            try writer.writeAll("  --exact                        Match test names exactly\n");
            try writer.writeAll("  --ignored                      Run only ignored tests\n");
            try writer.writeAll("  --include-ignored              Run all tests including ignored\n");
            try writer.writeAll("  --affected                     Run only tests impacted by changed functions\n");
            try writer.writeAll("  --release-small                Link test binaries with -O1 (default: -O0)\n");
            try writer.writeAll("  --release-fast                 Link test binaries with -O3 (default: -O0)\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .check => {
            try writer.writeAll("usage: sa check <file> [options]\n\n");
            try writer.writeAll("Flatten and verify a .sa/.sab file without codegen or linking.\n");
            try writer.writeAll("Uses the process/daemon-scoped verdict cache so unchanged streams skip re-verify.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit JSON report\n");
            try writer.writeAll("  --emit-sab <path>              Write the verified program as a .sab binary\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .encode_fragment => {
            try writer.writeAll("usage: sa encode-fragment <file> [options]\n\n");
            try writer.writeAll("Encode an SA surface fragment as a .safrag container (fragment format 1.0).\n");
            try writer.writeAll("The source must start with a #fragment contract header declaring the wrapper\n");
            try writer.writeAll("function and its register contract (#fragment-function/-reads/-owns/-returns/\n");
            try writer.writeAll("-caller). The header is validated against the flattened body; the payload is\n");
            try writer.writeAll("encoded without whole-program verification because a fragment is not a\n");
            try writer.writeAll("program. A .safrag is rejected by build/run/check; only an assembler may\n");
            try writer.writeAll("decode it, and the assembled module must pass normal verification.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -o <path>                      Write the fragment container to path (default: <file>.safrag)\n");
            try writer.writeAll("  --json                         Emit JSON report\n");
            try writeCompileOptionsHelp(writer);
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .bc2sa => {
            try writer.writeAll("usage: sa bc2sa <file.bc>\n\n");
            try writer.writeAll("Translate LLVM bitcode to SA assembly.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .explain => {
            try writer.writeAll("usage: sa explain <code>\n\n");
            try writer.writeAll("Explain a diagnostic error code.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit explanation as JSON\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .fix => {
            try writer.writeAll("usage: sa fix [--plan] <code>\n\n");
            try writer.writeAll("Suggest fixes for diagnostics.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --plan                         Print a deterministic fix plan\n");
            try writer.writeAll("  --json                         Emit fix plan as JSON\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .skills => {
            try writer.writeAll("usage: sa skills [--json]\n\n");
            try writer.writeAll("List compiler and plugin skills/capabilities. Text mode also writes agent skills into the current directory.\n");
            try writer.writeAll("The generated SA skill scans the current sa_std root and records every .sa/.sal/.sai macro and extern/export declaration.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --json                         Emit skills as JSON\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
        .daemon => {
            try writer.writeAll("usage: sa daemon [--socket path] [--max-workers N] [--per-agent-limit N]\n\n");
            try writer.writeAll("Run a persistent compile/verify/test server over a Unix socket.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --socket <path>                Unix socket path (default /tmp/sa-daemon.sock)\n");
            try writer.writeAll("  --max-workers <N>              Max concurrent request workers (default 8)\n");
            try writer.writeAll("  --per-agent-limit <N>          Max in-flight requests per agent_id (default 4)\n");
        },
        .help => {
            try writer.writeAll("usage: sa help [command]\n\n");
            try writer.writeAll("Show global help or help for one command.\n\n");
            try writer.writeAll("Examples:\n");
            try writer.writeAll("  sa help test\n");
            try writer.writeAll("  sa help pkg audit\n");
            try writer.writeAll("  sa test --help\n");
        },
        .version => {
            try writer.writeAll("usage: sa version\n\n");
            try writer.writeAll("Print the SA toolchain version.\n\n");
            try writer.writeAll("Options:\n");
            try writer.writeAll("  --version                      Print version and exit\n");
            try writer.writeAll("  -h, --help                     Show this help message\n");
        },
    }
}

pub fn printHelpTopic(writer: anytype, args: []const []const u8) !u8 {
    if (args.len == 0) {
        try printUsage(writer);
        return 0;
    }
    if (isHelpFlag(args[0])) {
        try printCommandHelp(writer, .help, &.{});
        return 0;
    }
    const cmd = commandFromName(args[0]) orelse {
        try writer.print("unknown help topic: {s}\n", .{args[0]});
        return 1;
    };
    try printCommandHelp(writer, cmd, args[1..]);
    return 0;
}

pub fn explainEntries() []const ExplainEntry {
    return &.{
        .{
            .codes = &.{ "ForbiddenSyntax", "SA-FLAT-001" },
            .title = "Flattening rejected surface syntax",
            .summary = "The flattener only accepts the SA linear instruction surface.",
            .details = &.{
                "Braces, if/else, while, for, and dotted property chains are rejected before verification.",
                "The frontend must lower structured control flow into labels, branches, and explicit register moves.",
            },
            .fix_hint = "Rewrite the source into labels and br/jmp blocks before flattening.",
        },
        .{
            .codes = &.{ "ImportResolutionFailed", "SA-FLAT-050" },
            .title = "Import could not be resolved",
            .summary = "The import path or package identity could not be matched to a source artifact.",
            .details = &.{
                "The resolver accepts source packages and pinned package identities.",
                "Ambiguous versions, rejected artifacts, and invalid paths all surface through the same public trap.",
            },
            .fix_hint = "Pin the package ref, fix the path, or depend on the source package instead of a precompiled artifact.",
        },
        .{
            .codes = &.{ "UndefinedMacro", "SA-FLAT-060" },
            .title = "Macro is not defined",
            .summary = "An EXPAND names a macro for which no [MACRO] definition exists in the imported sources.",
            .details = &.{
                "Macro definitions are collected from the root file and everything it imports before expansion runs.",
                "When the program was emitted against a newer sa_std than the one being assembled with, the missing macro is usually a std macro: that is std version skew, not a syntax error in the program.",
            },
            .fix_hint = "Define the macro, import the file that defines it, or assemble against the sa_std version the program was emitted for.",
        },
        .{
            .codes = &.{ "RegisterRedefinition", "SA-REF-010" },
            .title = "Live register re-bound",
            .summary = "A register that is still live cannot be assigned a second time without an explicit move or release.",
            .details = &.{
                "The referee checks register ownership and capability masks on every instruction.",
                "Rebinding a live register without consuming the previous value violates the linear ownership model.",
            },
            .fix_hint = "Rename the destination register or release/move the old value first.",
        },
        .{
            .codes = &.{ "UnknownRegister", "SA-REF-011" },
            .title = "Register used before declaration",
            .summary = "The verifier could not resolve the register name to a live slot.",
            .details = &.{
                "All register reads and writes must refer to a register introduced by a preceding instruction.",
                "Import-expanded code and macro-generated code must keep the same register namespace consistent.",
            },
            .fix_hint = "Declare the register earlier or thread the correct register name through the macro expansion.",
        },
        .{
            .codes = &.{"SA-CLI-001"},
            .title = "Missing required operand",
            .summary = "The CLI command needs a positional argument such as a source file or project path.",
            .details = &.{
                "The top-level dispatcher fails fast when no source or operand is provided.",
                "The same issue appears in build, run, test, and fetch subcommands when the target path is omitted.",
            },
            .fix_hint = "Pass the required file, path, or operand after the command.",
        },
    };
}

pub fn explainEntryForCode(code: []const u8) ?ExplainEntry {
    for (explainEntries()) |entry| {
        for (entry.codes) |alias| {
            if (std.mem.eql(u8, alias, code)) return entry;
        }
    }
    return null;
}

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll("usage: sa <command> [options]\n\n");
    try writer.writeAll("Commands:\n");
    try writer.writeAll("  init         [path]            Create a new SA binary project\n");
    try writer.writeAll("  pkg          <subcommand>      Package add, install, fetch, audit, list, and lock commands\n");
    try writer.writeAll("  plugin       <subcommand>      Install, list, and confirm native SA plugins\n");
    try writer.writeAll("  cache        <subcommand>      Inspect and clean project-local caches\n");
    try writer.writeAll("  install      [identity]        Pkg alias of `sa pkg install` (project dependencies or one package)\n");
    try writer.writeAll("  build        <file>            Compile a .sa/.sab source to a native executable\n");
    try writer.writeAll("  build-workspace                Build the selected workspace member executable\n");
    try writer.writeAll("  run          <file>            Compile and immediately execute a .sa/.sab file\n");
    try writer.writeAll("  build-exe    <file>            Build a standalone executable (alias for build)\n");
    try writer.writeAll("  build-obj    <file>            Build an object file (.o)\n");
    try writer.writeAll("  build-lib    <file>            Build a native library (.so/.dll/.dylib or .a) from an export contract\n");
    try writer.writeAll("  build-wasm   <file>            Build a WebAssembly module (.wasm)\n");
    try writer.writeAll("  build-js     <file>            Build a JavaScript module (.js, JS backend)\n");
    try writer.writeAll("  build-c      <file>            Build a portable C file (.c, C backend)\n");
    try writer.writeAll("  test         <file>            Run @test blocks in a .sa/.sab file\n");
    try writer.writeAll("  check        <file>            Flatten and verify without codegen\n");
    try writer.writeAll("  encode-fragment <file>         Encode an SA surface fragment (contract header required) as a .safrag container\n");
    try writer.writeAll("  fetch        <identity>        Pkg alias of `sa pkg fetch` (fetch and cache a package)\n");
    try writer.writeAll("  audit        <identity>        Pkg alias of `sa pkg audit` (audit package capabilities)\n");
    try writer.writeAll("  graph        <path>            Output a dependency/call graph\n");
    try writer.writeAll("  layout       ...               Print struct layout information\n");
    try writer.writeAll("  size         <file>            Print function size statistics\n");
    try writer.writeAll("  bc2sa      <file>            Translate LLVM bitcode to SA assembly\n");
    try writer.writeAll("  explain      <code>            Explain a diagnostic error code\n");
    try writer.writeAll("  fix          <file>            Suggest fixes for diagnostics\n");
    try writer.writeAll("  skills                         List compiler skills and capabilities\n");
    try writer.writeAll("  daemon                         Run a persistent compile/verify server\n");
    try writer.writeAll("  help         [command]         Show this help message\n");
    try writer.writeAll("  version                        Print the SA toolchain version\n");
    try writer.writeAll("\nProject lifecycle:\n");
    try writer.writeAll("  Inside a project directory, the verbs build, build-exe, build-wasm,\n");
    try writer.writeAll("  build-js, build-c, test, check, and run act on the project. When the\n");
    try writer.writeAll("  project selects a language frontend (its sa.mod declares the plugin\n");
    try writer.writeAll("  via require_plugin, or its entry source under src/ has an extension a\n");
    try writer.writeAll("  language plugin owns), these verbs dispatch to that frontend with\n");
    try writer.writeAll("  all flags passed through untouched. Without such a project the verbs\n");
    try writer.writeAll("  keep their SA meaning. Naming a source file dispatches by extension\n");
    try writer.writeAll("  as before, and the explicit form `sa <frontend> <verb>` keeps working.\n");
    try writer.writeAll("\nGlobal options:\n");
    try writer.writeAll("  --json                         Output diagnostics in JSON format\n");
    try writer.writeAll("  --profile                      Include compile phase timings in JSON metrics\n");
    try writer.writeAll("  --mem-report                   Print compile RSS stage samples; JSON mode includes metrics\n");
    try writer.writeAll("  --jobs auto|N                  Set the number of parallel compile jobs\n");
    try writer.writeAll("  --dce no|std|full              Select dead-code elimination level\n");
    try writer.writeAll("  --no-incremental               Disable the default project build cache\n");
    try writer.writeAll("  -h, --help                     Show this help message\n");
    try writer.writeAll("  --version                      Print version and exit\n");
    try writer.writeAll("\nTest flags:\n");
    try writer.writeAll("  --list                         List selected tests after frontend checks only\n");
    try writer.writeAll("  --compile-only                 Compile and link tests without running them\n");
    try writer.writeAll("  --trace-panic                  Include panic diagnostics on failed tests\n");
    try writer.writeAll("  --test-debug                   Alias for --trace-panic\n");
    try writer.writeAll("  --filter <pattern>             Include only matching tests (repeatable)\n");
    try writer.writeAll("  --skip <pattern>               Exclude matching tests (repeatable)\n");
    try writer.writeAll("  --exact                        Match test names exactly\n");
    try writer.writeAll("  --ignored                      Run only ignored tests\n");
    try writer.writeAll("  --include-ignored              Run all tests including ignored\n");
    try writer.writeAll("  --affected                     Run only tests impacted by changed functions\n");
}

pub fn printVersion(writer: anytype) !void {
    const ver = build_options.version;
    try writer.print("sa {s}\n", .{ver});
}

pub fn explainCommand(writer: anytype, args: []const []const u8, json_mode: bool) !u8 {
    if (args.len < 3) return error.MissingSourcePath;
    const code = args[2];
    // Resolve by trap name, stable code (SA-REF-010), or numeric code (1006).
    // Covers all 57 traps via trap_agent.
    const maybe_trap = trap.trapFromName(code) orelse trap.trapFromStableCode(code) orelse blk: {
        const n = std.fmt.parseInt(u32, code, 10) catch break :blk null;
        break :blk trap.trapFromNumericCode(n);
    };
    if (maybe_trap) |t| {
        try writeTrapExplanation(writer, t, json_mode);
        return 0;
    }
    const entry = explainEntryForCode(code) orelse {
        if (json_mode) {
            try writer.writeAll("{\"status\":\"error\",\"explain\":null}\n");
        } else {
            try writer.print("unknown code: {s}\n", .{code});
        }
        return 1;
    };
    if (json_mode) {
        try writer.writeAll("{\"status\":\"ok\",\"explain\":");
        try writeExplainEntryJson(writer, entry);
        try writer.writeAll("}\n");
    } else {
        try writeExplainEntryText(writer, entry);
    }
    return 0;
}

pub fn commandFromName(name: []const u8) ?Command {
    inline for (std.meta.tags(Command).*) |cmd| {
        if (std.mem.eql(u8, name, commandName(cmd))) return cmd;
    }
    return null;
}

pub fn writeTrapExplanation(writer: anytype, t: trap.Trap, json_mode: bool) !void {
    const ex = trap.explainTrap(t);
    const name = trap.trapName(t);
    const numeric = trap.trapCode(t);
    if (json_mode) {
        try writer.writeAll("{\"status\":\"ok\",\"explain\":{\"name\":");
        try writeJsonString(writer, name);
        try writer.writeAll(",\"stable_code\":");
        try writeJsonString(writer, ex.stable_code);
        try writer.print(",\"numeric_code\":{d},\"summary\":", .{numeric});
        try writeJsonString(writer, ex.summary);
        try writer.writeAll(",\"fix_hint\":");
        try writeJsonString(writer, ex.fix_hint);
        try writer.writeAll("}}\n");
    } else {
        try writer.print("{s} [{s} / {d}]: {s}\n", .{ name, ex.stable_code, numeric, ex.summary });
        try writer.print("fix: {s}\n", .{ex.fix_hint});
    }
}

pub fn commandName(cmd: Command) []const u8 {
    return switch (cmd) {
        .build => "build",
        .build_workspace => "build-workspace",
        .run => "run",
        .init => "init",
        .install => "install",
        .plugin => "plugin",
        .pkg => "pkg",
        .cache => "cache",
        .build_exe => "build-exe",
        .build_wasm => "build-wasm",
        .build_js => "build-js",
        .build_c => "build-c",
        .build_obj => "build-obj",
        .build_lib => "build-lib",
        .bc2sa => "bc2sa",
        .audit => "audit",
        .check => "check",
        .graph => "graph",
        .fetch => "fetch",
        .layout => "layout",
        .size => "size",
        .test_cmd => "test",
        .explain => "explain",
        .fix => "fix",
        .skills => "skills",
        .daemon => "daemon",
        .help => "help",
        .version => "version",
        .encode_fragment => "encode-fragment",
    };
}

pub fn writeExplainEntryJson(writer: anytype, entry: ExplainEntry) !void {
    try writer.writeByte('{');
    try writer.writeAll("\"codes\":");
    try writeJsonStringArray(writer, entry.codes);
    try writer.writeAll(",\"title\":");
    try writeJsonString(writer, entry.title);
    try writer.writeAll(",\"summary\":");
    try writeJsonString(writer, entry.summary);
    try writer.writeAll(",\"details\":");
    try writeJsonStringArray(writer, entry.details);
    try writer.writeAll(",\"fix_hint\":");
    try writeMaybeJsonString(writer, entry.fix_hint);
    try writer.writeByte('}');
}

pub fn writeExplainEntryText(writer: anytype, entry: ExplainEntry) !void {
    try writer.print("code: {s}\n", .{entry.codes[0]});
    if (entry.codes.len > 1) {
        try writer.writeAll("aliases:");
        for (entry.codes[1..]) |alias| {
            try writer.print(" {s}", .{alias});
        }
        try writer.writeByte('\n');
    }
    try writer.print("title: {s}\n", .{entry.title});
    try writer.print("summary: {s}\n", .{entry.summary});
    for (entry.details) |detail| {
        try writer.print("detail: {s}\n", .{detail});
    }
    if (entry.fix_hint) |hint| {
        try writer.print("fix: {s}\n", .{hint});
    }
}

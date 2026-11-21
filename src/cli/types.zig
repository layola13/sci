/// Shared types for the CLI (moved out of cli.zig).

pub const Command = enum {
    run,
    init,
    install,
    plugin,
    pkg,
    cache,
    build,
    build_workspace,
    build_exe,
    build_wasm,
    build_js,
    build_c,
    build_obj,
    build_lib,
    bc2sa,
    audit,
    check,
    graph,
    layout,
    fetch,
    size,
    test_cmd,
    explain,
    fix,
    skills,
    daemon,
    help,
    version,
    encode_fragment,
};

pub const ExplainEntry = struct {
    codes: []const []const u8,
    title: []const u8,
    summary: []const u8,
    details: []const []const u8,
    fix_hint: ?[]const u8 = null,
};

pub const DiagnosticsMode = enum {
    human,
    json,
};

pub const CliErrorInfo = struct {
    code: ?[]const u8,
    message: []const u8,
    hint: ?[]const u8,
};

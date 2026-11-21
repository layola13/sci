const std = @import("std");
const sio = @import("sio");
const CompileOptions = @import("types.zig").CompileOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const ExecuteOptions = @import("types.zig").ExecuteOptions;
const newCompileOptions = @import("types.zig").newCompileOptions;
const consumeCompileOption = @import("options.zig").consumeCompileOption;
const loadSource = @import("compile.zig").loadSource;

/// `sa encode-fragment`: validate a surface fragment's contract
/// header against its flattened wrapper body, encode the payload with
/// the unchecked SAB encoder (the fragment is not a program, so the
/// verified whole-program encoder would reject its placeholder
/// registers), and write the versioned fragment container. See
/// sab_fragment.zig for the format and the guard rules.
pub fn executeEncodeFragment(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
    json_mode: bool,
    exec_options: ExecuteOptions,
) !u8 {
    var diag_forward = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
    defer diag_forward.writer().flush() catch {};
    var compile_options = newCompileOptions(exec_options, diag_forward.writer());
    var source_arg: ?[]const u8 = null;
    var out_path: ?[]const u8 = null;
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (try consumeCompileOption(arg, args, &i, &compile_options)) continue;
        if (std.mem.eql(u8, arg, "-o")) {
            if (i + 1 >= args.len) return error.MissingOutputPath;
            out_path = args[i + 1];
            i += 1;
            continue;
        }
        if (source_arg == null) {
            source_arg = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }
    if (source_arg == null) return error.MissingSourcePath;
    const source_path = source_arg.?;
    if (std.mem.endsWith(u8, source_path, ".sab") or std.mem.endsWith(u8, source_path, ".safrag")) {
        try stderr.print("encode-fragment: input must be SA text with a #fragment header, not an encoded binary\n", .{});
        return 1;
    }
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);

    var parsed = sab_fragment.parseFragmentSource(allocator, source) catch |err| {
        const parse_err: sab_fragment.ParseError = @errorCast(err);
        if (json_mode) {
            try stdout.writeAll("{\"status\":\"error\",\"error\":{\"name\":");
            try writeJsonString(stdout, @errorName(parse_err));
            try stdout.writeAll(",\"message\":");
            try writeJsonString(stdout, fragmentParseMessage(parse_err));
            try stdout.writeAll("}}\n");
        } else {
            try stderr.print("encode-fragment: {s}: {s}\n", .{ @errorName(parse_err), fragmentParseMessage(parse_err) });
        }
        return 1;
    };
    defer parsed.deinit(allocator);

    // Flatten with the same project/std resolution `sa check` uses
    // (package dependencies from a project manifest are not consulted:
    // fragment sources import the standard library and relative files).
    var resolution = if (compile_options.project_root) |project_root|
        try pkg_workspace.resolveFromRootPath(allocator, project_root, .{ .request = compile_options.package_name })
    else
        try resolveProjectFromSourcePath(allocator, source_path, compile_options.package_name);
    defer resolution.deinit(allocator);
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);
    const stable_import_roots = try defaultStableImportRoots(allocator, resolution.member_root);
    defer freeOwnedStringSlice(allocator, stable_import_roots);
    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .options = .{
            .project_root = resolution.workspace_root,
            .std_root = std_root,
            .offline = compile_options.offline,
            .stable_import_roots = stable_import_roots,
            .diagnostics = &reportPluginImportDiagnostic,
        },
    };
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, parsed.stripped_source, &error_ctx, resolve_ctx) catch |err| {
        const report = trapFromFlattenError(source_path, source, err, flattener.errorReport(&error_ctx));
        try printTrapReport(if (json_mode) stdout else stderr, report, if (json_mode) .json else .human);
        return 1;
    };
    defer flat.deinit(allocator);

    var validation = try sab_fragment.validateContract(allocator, &flat, &parsed.contract, parsed.stripped_source);
    defer validation.deinit(allocator);
    switch (validation) {
        .ok => {},
        .violation => |v| {
            if (json_mode) {
                try stdout.writeAll("{\"status\":\"error\",\"error\":{\"name\":\"FragmentContractViolation\",\"kind\":");
                try writeJsonString(stdout, @tagName(v.kind));
                try stdout.writeAll(",\"register\":");
                if (v.register) |name| {
                    try writeJsonString(stdout, name);
                } else {
                    try stdout.writeAll("null");
                }
                try stdout.writeAll(",\"message\":");
                try writeJsonString(stdout, v.detail);
                try stdout.writeAll("}}\n");
            } else {
                try stderr.print("encode-fragment: contract violation: {s}", .{@tagName(v.kind)});
                if (v.register) |name| try stderr.print(" (register: {s})", .{name});
                try stderr.print(": {s}\n", .{v.detail});
            }
            return 1;
        },
    }

    const container = try sab_fragment.encodeFragment(allocator, &flat, &parsed.contract, source);
    defer allocator.free(container);

    const owned_out = if (out_path) |path| path else try deriveFragmentOutputPath(allocator, source_path);
    defer if (out_path == null) allocator.free(owned_out);
    const cwd = sio.cwd();
    const out_file = try cwd.createFile(owned_out, .{});
    defer out_file.close();
    try out_file.writeAll(container);

    var container_sha: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(container, &container_sha, .{});
    const sha_hex = std.fmt.bytesToHex(container_sha, .lower);
    if (json_mode) {
        try stdout.writeAll("{\"status\":\"ok\",\"command\":\"encode-fragment\",\"fragment_format\":\"1.0\"");
        try stdout.print(",\"sab_version\":\"{d}.{d}\"", .{ sab.version_major, sab.version_minor });
        try stdout.print(",\"bytes\":{d}", .{container.len});
        try stdout.writeAll(",\"sha256\":");
        try writeJsonString(stdout, &sha_hex);
        try stdout.writeAll(",\"caller\":");
        try writeJsonString(stdout, parsed.contract.caller);
        try stdout.writeAll(",\"function\":");
        try writeJsonString(stdout, parsed.contract.function_name);
        try stdout.writeAll(",\"reads\":");
        try writeJsonStringArray(stdout, parsed.contract.reads);
        try stdout.writeAll(",\"owns\":");
        try writeJsonStringArray(stdout, parsed.contract.owns);
        try stdout.writeAll(",\"returns\":");
        try writeJsonStringArray(stdout, parsed.contract.returns);
        try stdout.writeAll(",\"output\":");
        try writeJsonString(stdout, owned_out);
        try stdout.writeAll("}\n");
    } else {
        try stdout.print("encode-fragment ok: wrote SAB fragment: {s} ({d} bytes)\n", .{ owned_out, container.len });
        try stdout.print("  fragment format {d}.{d}; sab payload {d}.{d}; sha256 {s}\n", .{ sab_fragment.format_major, sab_fragment.format_minor, sab.version_major, sab.version_minor, &sha_hex });
        try stdout.print("  caller: {s}; function: {s}; reads: {d}; owns: {d}; returns: {d}\n", .{ parsed.contract.caller, parsed.contract.function_name, parsed.contract.reads.len, parsed.contract.owns.len, parsed.contract.returns.len });
    }
    return 0;
}

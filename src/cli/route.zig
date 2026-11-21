const std = @import("std");
const sio = @import("sio");
const CompileOptions = @import("types.zig").CompileOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const Command = @import("types.zig").Command;
const LanguageRoute = @import("types.zig").LanguageRoute;
const isHelpFlag = @import("help.zig").isHelpFlag;
const buildPluginRuntimeAuthorization = @import("plugin_cmd.zig").buildPluginRuntimeAuthorization;
const pkg_workspace = @import("../pkg/workspace.zig");
const plugins = @import("../plugins.zig");
const pathJoinAlloc = @import("compile.zig").pathJoinAlloc;
const hasJsonFlag = @import("help.zig").hasJsonFlag;
const projectPathExists = @import("cache.zig").projectPathExists;
const commandName = @import("help.zig").commandName;
const stageTimingEnabled = @import("compile.zig").stageTimingEnabled;
const elapsedNs = @import("compile.zig").elapsedNs;

/// Project-verb routing (toolchain phase 1, form A): a lifecycle verb
/// invoked without a source file inside a project dispatches to the
/// project's language frontend, with every flag passed through
/// untouched (the host never interprets frontend flags).
///
/// Guardrails: routing requires project context — a sa.mod found from
/// the current directory (workspace resolution) whose effective
/// manifest either declares the frontend via require_plugin or whose
/// entry source (src/main.<ext> / main.<ext>) has an extension a
/// language frontend owns. Conflicting signals keep the host meaning,
/// and any positional argument (or a help flag) keeps today's
/// behavior, so existing scripts are unaffected. A generated main.sa
/// beside a frontend entry (the frontend build/run output) does not
/// veto the entry signal; a project whose only entry is main.sa has
/// no frontend entry and keeps the host meaning.
pub fn routeProjectVerb(
    allocator: std.mem.Allocator,
    verb: Command,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
) !?LanguageRoute {
    const frontend_cmd: []const u8 = switch (verb) {
        .build, .build_exe => "build-exe",
        .build_wasm => "build-wasm",
        .build_js => "build-js",
        .build_c => "build-c",
        .check => "check",
        .test_cmd => "test",
        // run has no frontend counterpart: stage one compiles the
        // project entry through the frontend `build` command, stage two
        // rewrites argv to run the generated .sa (same shape as the
        // file-extension build routing below).
        .run => "build",
        else => return null,
    };

    // Bare-verb scan: a positional token means the invocation names
    // something and keeps today's meaning. Values of flags that take a
    // separate value are skipped so `sa build -o app` stays bare.
    var i: usize = 2;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (isHelpFlag(arg)) return null;
        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--out") or
            std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "--package") or std.mem.eql(u8, arg, "-p") or
            std.mem.eql(u8, arg, "--project-root") or std.mem.eql(u8, arg, "--contract") or
            std.mem.eql(u8, arg, "--filter") or std.mem.eql(u8, arg, "--skip") or
            std.mem.eql(u8, arg, "--ref") or std.mem.eql(u8, arg, "--emit-sab") or
            std.mem.eql(u8, arg, "--kind") or std.mem.eql(u8, arg, "--format") or
            std.mem.eql(u8, arg, "--test-backend") or std.mem.eql(u8, arg, "--sab-out"))
        {
            i += 1;
            continue;
        }
        if (arg.len == 0 or arg[0] == '-') continue;
        return null;
    }

    var resolution = pkg_workspace.resolveFromCurrentDir(allocator, .{}) catch return null;
    defer resolution.deinit(allocator);
    const effective = resolution.effective_manifest orelse return null;

    var plugin_auth = try buildPluginRuntimeAuthorization(allocator, argv);
    defer plugin_auth.deinit(allocator);
    var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
    defer plugin_runtime.deinit();
    plugin_runtime.suppress_legacy_frontend_notice = true;

    const infos = try plugin_runtime.languageFrontendInfos(allocator);
    defer allocator.free(infos);
    if (infos.len == 0) return null;

    // Signal 1: the project entry source's extension. A generated
    // main.sa beside the frontend entry does not veto the signal (it
    // is the frontend's own build/run output); a project with only a
    // main.sa entry simply has no frontend entry.
    var ext_frontend: ?plugins.Runtime.LanguageFrontendInfo = null;
    var entry_path: ?[]u8 = null;
    defer if (entry_path) |path| allocator.free(path);
    const member_root = resolution.member_root;
    outer: for (infos) |info| {
        for (info.extensions) |ext| {
            const main_name = try std.fmt.allocPrint(allocator, "main{s}", .{ext});
            defer allocator.free(main_name);
            const src_candidate = try pathJoinAlloc(allocator, &.{ member_root, "src", main_name });
            if (projectPathExists(src_candidate)) {
                ext_frontend = info;
                entry_path = src_candidate;
                break :outer;
            }
            allocator.free(src_candidate);
            const root_candidate = try pathJoinAlloc(allocator, &.{ member_root, main_name });
            if (projectPathExists(root_candidate)) {
                ext_frontend = info;
                entry_path = root_candidate;
                break :outer;
            }
            allocator.free(root_candidate);
        }
    }

    // Signal 2: sa.mod require_plugin naming a language frontend.
    var decl_frontend: ?plugins.Runtime.LanguageFrontendInfo = null;
    for (effective.plugin_requires) |entry| {
        for (infos) |info| {
            if (pluginRequireNamesFrontend(entry.identity, info.name)) {
                decl_frontend = info;
                break;
            }
        }
        if (decl_frontend != null) break;
    }

    const frontend: plugins.Runtime.LanguageFrontendInfo = blk: {
        if (ext_frontend != null and decl_frontend != null) {
            if (!std.mem.eql(u8, ext_frontend.?.name, decl_frontend.?.name)) return null;
            break :blk ext_frontend.?;
        }
        if (ext_frontend) |found| break :blk found;
        if (decl_frontend) |found| break :blk found;
        return null;
    };

    const json_mode = hasJsonFlag(argv);

    if (verb == .run) {
        const source_path = entry_path orelse blk: {
            if (frontend.extensions.len == 0) return null;
            const main_name = try std.fmt.allocPrint(allocator, "main{s}", .{frontend.extensions[0]});
            defer allocator.free(main_name);
            const candidate = try pathJoinAlloc(allocator, &.{ member_root, "src", main_name });
            if (projectPathExists(candidate)) {
                entry_path = candidate;
                break :blk candidate;
            }
            allocator.free(candidate);
            return null;
        };
        const ext = std.fs.path.extension(source_path);
        const stem = source_path[0 .. source_path.len - ext.len];
        const sa_path = try std.fmt.allocPrint(allocator, "{s}.sa", .{stem});
        defer allocator.free(sa_path);

        var fwd = std.array_list.Managed([]const u8).init(allocator);
        defer fwd.deinit();
        try fwd.append(argv[0]);
        try fwd.append(frontend.name);
        try fwd.append("build");
        try fwd.append(source_path);
        try fwd.append("--out");
        try fwd.append(sa_path);
        const code = (try plugin_runtime.dispatchCommand(fwd.items, stdout, stderr, json_mode)) orelse {
            try stderr.print("error[SA-LANGUAGE-FRONTEND]: language frontend {s} does not provide a build command\n", .{frontend.name});
            return .{ .handled = 1 };
        };
        if (code != 0) return .{ .handled = code };
        if (!projectPathExists(sa_path)) {
            try stderr.print("error[SA-LANGUAGE-FRONTEND]: language frontend {s} reported success but did not produce {s}\n", .{ frontend.name, sa_path });
            return .{ .handled = 1 };
        }

        var new_argv = std.array_list.Managed([]const u8).init(allocator);
        errdefer {
            for (new_argv.items) |arg| allocator.free(arg);
            new_argv.deinit();
        }
        try new_argv.append(try allocator.dupe(u8, argv[0]));
        try new_argv.append(try allocator.dupe(u8, "run"));
        try new_argv.append(try allocator.dupe(u8, sa_path));
        for (argv[2..]) |arg| try new_argv.append(try allocator.dupe(u8, arg));
        return .{ .rewritten = try new_argv.toOwnedSlice() };
    }

    var fwd = std.array_list.Managed([]const u8).init(allocator);
    defer fwd.deinit();
    try fwd.append(argv[0]);
    try fwd.append(frontend.name);
    try fwd.append(frontend_cmd);
    try fwd.appendSlice(argv[2..]);
    if (try plugin_runtime.dispatchCommand(fwd.items, stdout, stderr, json_mode)) |code| {
        return .{ .handled = code };
    }
    try stderr.print("error[SA-LANGUAGE-FRONTEND]: language frontend {s} does not handle '{s}' for project sources\n", .{ frontend.name, commandName(verb) });
    return .{ .handled = 1 };
}

pub fn routeLanguageFrontend(
    allocator: std.mem.Allocator,
    verb: Command,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
) !?LanguageRoute {
    const terminal = switch (verb) {
        .check, .test_cmd => true,
        .build, .build_exe, .build_wasm, .build_js, .build_c, .build_obj, .run => false,
        else => return null,
    };

    // Find positional source candidates: tokens that are not flags and
    // not the value of a flag that takes a separate value.
    var candidate_index: ?usize = null;
    var candidate_count: usize = 0;
    var i: usize = 2;
    while (i < argv.len) : (i += 1) {
        const arg = argv[i];
        if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--out") or
            std.mem.eql(u8, arg, "--target") or std.mem.eql(u8, arg, "--package"))
        {
            i += 1;
            continue;
        }
        if (arg.len == 0 or arg[0] == '-') continue;
        const ext = std.fs.path.extension(arg);
        if (ext.len == 0) continue;
        if (std.mem.eql(u8, ext, ".sa") or std.mem.eql(u8, ext, ".sab")) continue;
        candidate_count += 1;
        if (candidate_index == null) candidate_index = i;
    }
    if (candidate_index == null) return null;
    const source_index = candidate_index.?;
    const source_path = argv[source_index];
    const ext = std.fs.path.extension(source_path);

    var plugin_auth = try buildPluginRuntimeAuthorization(allocator, argv);
    defer plugin_auth.deinit(allocator);
    var plugin_runtime = try plugins.Runtime.initFromEnvWithAuthorization(allocator, plugin_auth.input);
    defer plugin_runtime.deinit();
    // This runtime only ever dispatches argv the host constructed
    // itself (`sa <frontend> build ...`); the legacy two-layer
    // deprecation notice is for user-typed invocations, not routing.
    plugin_runtime.suppress_legacy_frontend_notice = true;
    const frontend = plugin_runtime.languageFrontendForExtension(ext) orelse {
        // LINE-HOST-BUILDEXE-GOCHAN: a source file whose extension no
        // installed frontend owns must fail loudly here. Falling through
        // to the host pipeline feeds the file to the SA flattener, which
        // reports a misleading ForbiddenSyntax trap on the first `fn`
        // brace (DEF-SCI-HOST-BUILDEXE-GOCHAN-FORBIDDEN). The host can
        // only meaningfully consume .sa/.sab directly; anything else
        // reaching the flattener is a routing failure, not SA syntax.
        // (An installed frontend is visible only in dev mode
        // SA_PLUGIN_DEV=1; without it the extension is unowned too.)
        try stderr.print("error[SA-LANGUAGE-FRONTEND]: no installed language frontend owns {s} files; install a language frontend plugin for {s} sources (dev mode: SA_PLUGIN_DEV=1) or pass a .sa source\n", .{ ext, ext });
        return .{ .handled = 1 };
    };
    if (candidate_count > 1) {
        try stderr.print("error[SA-LANGUAGE-FRONTEND]: multiple language source files are not supported in one invocation yet\n", .{});
        return .{ .handled = 1 };
    }

    const json_mode = hasJsonFlag(argv);
    if (terminal) {
        // Forward the whole command: sa check app.sla -> frontend check.
        var fwd = std.array_list.Managed([]const u8).init(allocator);
        defer fwd.deinit();
        try fwd.append(argv[0]);
        try fwd.append(frontend);
        try fwd.appendSlice(argv[1..]);
        if (try plugin_runtime.dispatchCommand(fwd.items, stdout, stderr, json_mode)) |code| {
            return .{ .handled = code };
        }
        try stderr.print("error[SA-LANGUAGE-FRONTEND]: language frontend {s} does not handle '{s}' for {s} files\n", .{ frontend, commandName(verb), ext });
        return .{ .handled = 1 };
    }

    // Build verbs: compile through the frontend, then continue the
    // builtin pipeline on the generated .sa file. Compile-service
    // contract v1 (docs/language_frontend_contract.md): the host picks
    // the output path and passes it explicitly with --out; the frontend
    // must write the SA text there and report failure with a nonzero
    // exit code. v1 output placement is the sibling <name>.sa; the host
    // cache service will move it under the cache directory later.
    const stem = source_path[0 .. source_path.len - ext.len];
    const sa_path = try std.fmt.allocPrint(allocator, "{s}.sa", .{stem});
    defer allocator.free(sa_path);
    var fwd = std.array_list.Managed([]const u8).init(allocator);
    defer fwd.deinit();
    try fwd.append(argv[0]);
    try fwd.append(frontend);
    try fwd.append("build");
    try fwd.append(source_path);
    try fwd.append("--out");
    try fwd.append(sa_path);
    const frontend_start = if (stageTimingEnabled()) std.Io.Clock.awake.now(sio.io()) else null;
    const code = (try plugin_runtime.dispatchCommand(fwd.items, stdout, stderr, json_mode)) orelse {
        try stderr.print("error[SA-LANGUAGE-FRONTEND]: language frontend {s} does not provide a build command\n", .{frontend});
        return .{ .handled = 1 };
    };
    if (frontend_start) |start| {
        stderr.print("[stage-timing] frontend: {d:.3}ms\n", .{@as(f64, @floatFromInt(elapsedNs(start))) / 1_000_000.0}) catch {};
    }
    if (code != 0) return .{ .handled = code };

    const generated = blk: {
        sio.cwd().access(sa_path, .{}) catch break :blk false;
        break :blk true;
    };
    if (!generated) {
        try stderr.print("error[SA-LANGUAGE-FRONTEND]: language frontend {s} reported success but did not produce {s}\n", .{ frontend, sa_path });
        return .{ .handled = 1 };
    }

    var new_argv = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (new_argv.items) |arg| allocator.free(arg);
        new_argv.deinit();
    }
    for (argv, 0..) |arg, idx| {
        if (idx == source_index) {
            try new_argv.append(try allocator.dupe(u8, sa_path));
        } else {
            try new_argv.append(try allocator.dupe(u8, arg));
        }
    }
    return .{ .rewritten = try new_argv.toOwnedSlice() };
}

pub fn freeRewrittenArgs(allocator: std.mem.Allocator, args: [][]const u8) void {
    for (args) |arg| allocator.free(arg);
    allocator.free(args);
}

/// True when a require_plugin identity names the given language
/// frontend: the identity itself, its basename, or the conventional
/// `sa_plugin_<name>` source-directory basename.
pub fn pluginRequireNamesFrontend(identity: []const u8, frontend_name: []const u8) bool {
    if (std.mem.eql(u8, identity, frontend_name)) return true;
    const base = std.fs.path.basename(identity);
    if (std.mem.eql(u8, base, frontend_name)) return true;
    const prefix = "sa_plugin_";
    if (std.mem.startsWith(u8, base, prefix) and std.mem.eql(u8, base[prefix.len..], frontend_name)) return true;
    return false;
}

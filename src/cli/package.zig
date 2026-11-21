const std = @import("std");
const sio = @import("sio");
const CompileOptions = @import("types.zig").CompileOptions;
const manifest = @import("../pkg/manifest.zig");
const pkg_audit = @import("../pkg/audit.zig");
const pkg_mirror = @import("../pkg/mirror.zig");
const pkg_ci = @import("../pkg/ci.zig");
const pkg_confirm = @import("../pkg/confirm.zig");
const pkg_sum = @import("../pkg/sum.zig");
const StdinLineReader = @import("types.zig").StdinLineReader;
const pkg_workspace = @import("../pkg/workspace.zig");
const isHelpFlag = @import("help.zig").isHelpFlag;
const parseInstallArgs = @import("misc_cmd.zig").parseInstallArgs;
const pkg_fetch = @import("../pkg/fetch.zig");
const plugins = @import("../plugins.zig");
const pathJoinAlloc = @import("compile.zig").pathJoinAlloc;

pub fn verifyProjectPackageState(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    project_manifest: manifest.Manifest,
    options: CompileOptions,
) !void {
    try pkg_mirror.rejectForbiddenGlobalConfig(allocator);

    const sum_path = try std.fs.path.join(allocator, &.{ project_root, "sa.sum" });
    defer allocator.free(sum_path);
    if (try pathExists(sum_path)) {
        try pkg_sum.verifyProjectSum(allocator, project_root, project_manifest);
    }

    var session = pkg_confirm.Session.init(allocator);
    defer session.deinit();
    const stdin_is_tty = options.stdin_is_tty orelse stdinIsTty();
    const ci_mode = pkg_ci.detectMode(.{
        .explicit_ci = options.ci,
        // Plain pipes must not silently become the CI taint path; they should
        // hit the interactive confirmation guard and fail with MissingTty.
        .stdin_is_tty = if (options.ci) stdin_is_tty else true,
    });
    if (options.permission_set) |set_name| {
        if (!manifestPermissionSetExists(project_manifest, set_name)) return error.InvalidPermissionSet;
    } else if (ci_mode and project_manifest.permission_sets.len != 0 and !compileOptionsHaveAllowList(options)) {
        return error.MissingPermissionSet;
    }

    for (project_manifest.requires) |entry| {
        const audit_root = try resolvePackageAuditRoot(allocator, project_root, entry, options.offline);
        defer allocator.free(audit_root);
        var report = try pkg_audit.auditPackage(allocator, entry.url, entry.ref, audit_root, entry.grants);
        defer report.deinit(allocator);

        if (ci_mode) {
            try preflightCiPackage(allocator, report, entry.source_sha256, options);
        } else {
            try preflightInteractivePackage(report, entry.source_sha256, &session, options);
        }
    }
}

pub fn manifestPermissionSetExists(project_manifest: manifest.Manifest, name: []const u8) bool {
    if (std.mem.eql(u8, name, "@dev")) return true;
    for (project_manifest.permission_sets) |set| {
        if (std.mem.eql(u8, set.name, name)) return true;
    }
    return false;
}

pub fn compileOptionsHaveAllowList(options: CompileOptions) bool {
    return options.allow_env_requested or
        options.allow_net_requested or
        options.allow_read_requested or
        options.allow_write_requested or
        options.allow_run_requested;
}

pub fn resolvePackageAuditRoot(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    entry: manifest.RequireEntry,
    offline: bool,
) ![]u8 {
    const local_root = try std.fs.path.join(allocator, &.{ project_root, "sa_vendor", entry.url });
    errdefer allocator.free(local_root);
    if (dirExists(local_root)) return local_root;
    allocator.free(local_root);

    if (offline) return error.PackageNotResolved;

    const global_root = try globalCacheRoot(allocator, entry.url, entry.ref);
    errdefer allocator.free(global_root);
    if (dirExists(global_root)) return global_root;
    allocator.free(global_root);

    return error.PackageNotResolved;
}

pub fn preflightCiPackage(
    allocator: std.mem.Allocator,
    report: pkg_audit.AuditReport,
    expected_source_sha256: [32]u8,
    options: CompileOptions,
) !void {
    const status = try pkg_ci.dualTrackVerify(report, .{
        .expected_source_sha256 = expected_source_sha256,
        .allow_unaudited_risks = options.allow_unaudited_risks,
    });
    if (status == .tainted_unaudited_code) {
        var null_buf: [64]u8 = undefined;
        var null_discarding: std.Io.Writer.Discarding = .init(&null_buf);
        const writer = options.diagnostic_writer orelse &null_discarding.writer;
        try pkg_ci.writeTaintBanner(writer, report);
        try appendCiSummaryIfConfigured(allocator, report, status);
    }
}

pub fn preflightInteractivePackage(
    report: pkg_audit.AuditReport,
    expected_source_sha256: [32]u8,
    session: *pkg_confirm.Session,
    options: CompileOptions,
) !void {
    if (!hashesEqual(report.source_sha256, expected_source_sha256)) return error.UpstreamShaMismatch;

    var empty_input: std.Io.Reader = .fixed("");
    var null_buf: [64]u8 = undefined;
    var null_discarding: std.Io.Writer.Discarding = .init(&null_buf);
    const base_reader = options.stdin_reader orelse &empty_input;
    const stdin_adapter = StdinLineReader{ .inner = base_reader };
    const writer = options.diagnostic_writer orelse &null_discarding.writer;
    const stdin_is_tty = options.stdin_is_tty orelse stdinIsTty();
    try pkg_confirm.confirmWithReaderWriter(
        session,
        report,
        stdin_adapter,
        writer,
        stdin_is_tty,
        options.auto_approve_requested,
    );
}

pub fn dirExists(path: []const u8) bool {
    var dir = sio.cwd().openDir(path, .{ .iterate = true }) catch return false;
    dir.close();
    return true;
}

pub fn pathExists(path: []const u8) !bool {
    sio.cwd().access(path, .{ .read = true }) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

pub fn globalCacheRoot(allocator: std.mem.Allocator, identity: []const u8, ref: []const u8) ![]u8 {
    const home = sio.getEnvVarOwned(allocator, "HOME") catch {
        return error.PackageNotResolved;
    };
    defer allocator.free(home);
    const leaf = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ identity, ref });
    defer allocator.free(leaf);
    return try std.fs.path.join(allocator, &.{ home, ".sa", "pkg", leaf });
}

pub fn appendCiSummaryIfConfigured(
    allocator: std.mem.Allocator,
    report: pkg_audit.AuditReport,
    status: pkg_ci.VerifyStatus,
) !void {
    const summary_path = sio.getEnvVarOwned(allocator, "GITHUB_STEP_SUMMARY") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return,
        else => return err,
    };
    defer allocator.free(summary_path);
    var summary_file = try sio.cwd().openFile(summary_path, .{ .mode = .write_only });
    defer summary_file.close();
    try summary_file.seekTo(try summary_file.getEndPos());
    var sbuf: [8192]u8 = undefined;
    var sw = summary_file.writer(&sbuf);
    try pkg_ci.writeGithubSummary(&sw.interface, report, status);
    try sw.interface.flush();
}

pub fn hashesEqual(lhs: [32]u8, rhs: [32]u8) bool {
    return std.mem.eql(u8, lhs[0..], rhs[0..]);
}

pub fn stdinIsTty() bool {
    if (comptime @import("builtin").os.tag == .windows) return false;
    _ = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return false;
    return true;
}

pub fn projectRootFromCurrentDir(allocator: std.mem.Allocator) ![]u8 {
    var resolved = try pkg_workspace.resolveFromCurrentDir(allocator, .{});
    defer resolved.deinit(allocator);
    return try allocator.dupe(u8, resolved.workspace_root);
}

pub fn executePkgAdd(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    const parsed = try parseInstallArgs(args);
    const identity = parsed.identity orelse {
        try stderr.writeAll("usage: sa pkg add [options] <identity>\n");
        return 1;
    };

    var resolution = pkg_workspace.resolveFromCurrentDir(allocator, .{}) catch |err| {
        try stderr.print("pkg add: no sa.mod project found from the current directory; run `sa init` or `sa sla init` first ({s})\n", .{@errorName(err)});
        return 1;
    };
    defer resolution.deinit(allocator);

    // The dependency belongs to the manifest that governs the current
    // directory: the workspace member's sa.mod when one is selected,
    // otherwise the workspace/project root sa.mod.
    const target_path: []const u8 = if (resolution.member_manifest != null)
        resolution.member_manifest_path
    else if (resolution.workspace_manifest != null)
        resolution.workspace_manifest_path
    else {
        try stderr.writeAll("pkg add: no sa.mod project found from the current directory; run `sa init` or `sa sla init` first\n");
        return 1;
    };
    const effective = resolution.effective_manifest orelse {
        try stderr.writeAll("pkg add: no sa.mod project found from the current directory; run `sa init` or `sa sla init` first\n");
        return 1;
    };

    var mirror_rules = try pkg_mirror.loadProjectRules(allocator, resolution.workspace_root, effective.mirrors);
    defer mirror_rules.deinit(allocator);

    var fetch_options = parsed.options;
    fetch_options.mirror_rules = mirror_rules.rules;
    var result = try pkg_fetch.fetchPackage(allocator, identity, parsed.ref, fetch_options);
    defer result.deinit(allocator);

    // Edit the manifest textually so hand-written content (comments,
    // ordering, unrelated sections) survives untouched: replace the
    // existing require line for this identity, or append a new one.
    const original_text = try readManifestTextFileAlloc(allocator, target_path);
    defer allocator.free(original_text);
    var existing_manifest = try manifest.parseManifestWithFile(allocator, original_text, target_path);
    defer existing_manifest.deinit(allocator);

    var kept_grants: []const manifest.Capability = &.{};
    for (existing_manifest.requires) |entry| {
        if (std.mem.eql(u8, entry.url, identity)) {
            kept_grants = entry.grants;
            break;
        }
    }
    const new_line = try renderRequireLine(allocator, identity, parsed.ref, result.source_sha256, kept_grants);
    defer allocator.free(new_line);

    var new_text = std.array_list.Managed(u8).init(allocator);
    defer new_text.deinit();
    if (findRequireLineRange(original_text, identity)) |range| {
        try new_text.appendSlice(original_text[0..range.start]);
        try new_text.appendSlice(new_line);
        try new_text.append('\n');
        try new_text.appendSlice(original_text[range.end..]);
    } else {
        try new_text.appendSlice(original_text);
        if (new_text.items.len != 0 and new_text.items[new_text.items.len - 1] != '\n') try new_text.append('\n');
        try new_text.appendSlice(new_line);
        try new_text.append('\n');
    }

    // Never write a manifest the parser would reject, and never write
    // one that lost the entry just added.
    var check_manifest = try manifest.parseManifestWithFile(allocator, new_text.items, target_path);
    defer check_manifest.deinit(allocator);
    var recorded = false;
    for (check_manifest.requires) |entry| {
        if (std.mem.eql(u8, entry.url, identity) and std.mem.eql(u8, entry.ref, parsed.ref) and hashesEqual(entry.source_sha256, result.source_sha256)) recorded = true;
    }
    if (!recorded) return error.InvalidManifestAfterAdd;

    var file = try sio.createFileAbsolute(target_path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(new_text.items);

    // Refresh the project sum from a fresh resolution so the recorded
    // lock state matches the edited manifests (same tail as install).
    var next_resolution = try pkg_workspace.resolveFromCurrentDir(allocator, .{});
    defer next_resolution.deinit(allocator);
    if (next_resolution.effective_manifest) |*next_manifest| {
        var update = try pkg_sum.updateProjectSum(allocator, next_resolution.workspace_root, next_manifest.*);
        defer update.deinit(allocator);
    }

    try stdout.print("pkg add: {s} @{s} sha256:{s}\n", .{ identity, parsed.ref, std.fmt.bytesToHex(result.source_sha256, .lower) });
    try stdout.print("recorded in {s}\n", .{target_path});
    try stdout.print("{s}\n", .{result.root});
    return 0;
}

pub fn installManifestDependencies(allocator: std.mem.Allocator, options: pkg_fetch.FetchOptions, package_name: ?[]const u8, stdout: anytype) !u8 {
    var resolution = try pkg_workspace.resolveFromCurrentDir(allocator, .{ .request = package_name });
    defer resolution.deinit(allocator);

    const project_root = resolution.workspace_root;
    const project_manifest = resolution.effective_manifest orelse return 0;

    const current_dir = try sio.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(current_dir);

    if (package_name == null and
        resolution.workspace_manifest != null and
        resolution.workspace_manifest.?.workspace != null and
        std.mem.eql(u8, current_dir, resolution.workspace_root))
    {
        const members = try pkg_workspace.listWorkspaceMembers(allocator, resolution.workspace_root, &resolution.workspace_manifest.?);
        defer pkg_workspace.freeWorkspaceMembers(allocator, members);

        var member_manifests = std.array_list.Managed(manifest.Manifest).init(allocator);
        defer {
            for (member_manifests.items) |*member_manifest| member_manifest.deinit(allocator);
            member_manifests.deinit();
        }

        var member_manifest_ptrs = std.array_list.Managed(*const manifest.Manifest).init(allocator);
        defer member_manifest_ptrs.deinit();

        for (members) |member| {
            const member_manifest_path = try projectManifestPath(allocator, member.member_root);
            defer allocator.free(member_manifest_path);
            const member_manifest = try readManifestFile(allocator, member_manifest_path);
            try member_manifests.append(member_manifest);
        }

        for (member_manifests.items) |*member_manifest| {
            try member_manifest_ptrs.append(member_manifest);
        }

        var aggregate_manifest = try manifest.mergeWorkspaceMemberSet(
            allocator,
            &resolution.workspace_manifest.?,
            member_manifest_ptrs.items,
        );
        defer aggregate_manifest.deinit(allocator);

        var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, aggregate_manifest.mirrors);
        defer mirror_rules.deinit(allocator);

        var fetch_options = options;
        fetch_options.mirror_rules = mirror_rules.rules;

        try fetchManifestRequires(allocator, &aggregate_manifest, fetch_options, stdout);
        const plugin_code = try installManifestPlugins(allocator, &aggregate_manifest, stdout);
        if (plugin_code != 0) return plugin_code;

        var update = try pkg_sum.updateProjectSum(allocator, project_root, aggregate_manifest);
        defer update.deinit(allocator);
        return 0;
    }

    var mirror_rules = try pkg_mirror.loadProjectRules(allocator, project_root, project_manifest.mirrors);
    defer mirror_rules.deinit(allocator);

    var fetch_options = options;
    fetch_options.mirror_rules = mirror_rules.rules;

    try fetchManifestRequires(allocator, &project_manifest, fetch_options, stdout);
    const plugin_code = try installManifestPlugins(allocator, &project_manifest, stdout);
    if (plugin_code != 0) return plugin_code;

    var update = try pkg_sum.updateProjectSum(allocator, project_root, project_manifest);
    defer update.deinit(allocator);

    return 0;
}

pub fn executePkgList(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    for (args) |arg| {
        if (!isHelpFlag(arg)) return error.UnexpectedArgument;
    }
    var resolution = pkg_workspace.resolveFromCurrentDir(allocator, .{}) catch {
        try stderr.writeAll("pkg list: no sa.mod project found from the current directory\n");
        return 1;
    };
    defer resolution.deinit(allocator);
    const effective = resolution.effective_manifest orelse {
        try stderr.writeAll("pkg list: no sa.mod project found from the current directory\n");
        return 1;
    };
    for (effective.requires) |entry| {
        const line = try renderRequireLine(allocator, entry.url, entry.ref, entry.source_sha256, entry.grants);
        defer allocator.free(line);
        try stdout.print("{s}\n", .{line});
    }
    for (effective.plugin_requires) |entry| {
        try stdout.print("require_plugin {s} @{s} abi {d}\n", .{ entry.identity, entry.ref, entry.abi });
    }
    return 0;
}

pub fn executePkgCommandFallback(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype, stderr: anytype) !?u8 {
    if (args.len < 3) return null;
    const sub = args[2];
    if (std.mem.eql(u8, sub, "install")) {
        return try executeInstall(allocator, args[3..], stdout);
    }
    if (std.mem.eql(u8, sub, "add")) {
        return try executePkgAdd(allocator, args[3..], stdout, stderr);
    }
    if (std.mem.eql(u8, sub, "list")) {
        return try executePkgList(allocator, args[3..], stdout, stderr);
    }
    return null;
}

pub fn executeInstall(allocator: std.mem.Allocator, args: []const []const u8, stdout: anytype) !u8 {
    const parsed = try parseInstallArgs(args);
    if (parsed.identity) |identity| {
        var result = try pkg_fetch.fetchPackage(allocator, identity, parsed.ref, parsed.options);
        defer result.deinit(allocator);
        try stdout.print("{s}\n", .{result.root});
        return 0;
    }
    return try installManifestDependencies(allocator, parsed.options, parsed.package_name, stdout);
}

pub fn fetchManifestRequires(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest, fetch_options: pkg_fetch.FetchOptions, stdout: anytype) !void {
    for (manifest_file.requires) |entry| {
        var entry_fetch_options = fetch_options;
        entry_fetch_options.expected_source_sha256 = entry.source_sha256;
        var result = try pkg_fetch.fetchPackage(allocator, entry.url, entry.ref, entry_fetch_options);
        defer result.deinit(allocator);
        if (!hashesEqual(result.source_sha256, entry.source_sha256)) return error.UpstreamShaMismatch;
        try stdout.print("{s}\n", .{result.root});
    }
}

pub fn installManifestPlugins(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest, stdout: anytype) !u8 {
    for (manifest_file.plugin_requires) |entry| {
        _ = entry.abi;
        _ = entry.ref;
        const code = try plugins.installFromPath(allocator, entry.identity, stdout, .{});
        if (code != 0) return code;
    }
    return 0;
}

/// Render one canonical `require` line for sa.mod (the same shape
/// manifest.writeManifest emits, grants clause included when present).
pub fn renderRequireLine(allocator: std.mem.Allocator, url: []const u8, ref: []const u8, source_sha256: [32]u8, grants: []const manifest.Capability) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;
    try writer.print("require {s} @{s} sha256:{s}", .{ url, ref, std.fmt.bytesToHex(source_sha256, .lower) });
    if (grants.len != 0) {
        try writer.writeAll(" grants [");
        for (grants, 0..) |cap, idx| {
            if (idx != 0) try writer.writeAll(", ");
            try writer.writeAll(manifest.capabilityName(cap));
        }
        try writer.writeByte(']');
    }
    return aw.toOwnedSlice();
}

pub fn emitSumFromManifest(allocator: std.mem.Allocator, manifest_file: *const manifest.Manifest) !manifest.SumFile {
    var entries = std.array_list.Managed(manifest.SumEntry).init(allocator);
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit();
    }

    for (manifest_file.requires) |entry| {
        try entries.append(.{
            .url = try allocator.dupe(u8, entry.url),
            .ref = try allocator.dupe(u8, entry.ref),
            .source_sha256 = entry.source_sha256,
            .depth = 0,
        });
    }

    std.sort.insertion(manifest.SumEntry, entries.items, {}, struct {
        fn lessThan(_: void, lhs: manifest.SumEntry, rhs: manifest.SumEntry) bool {
            const order = std.mem.order(u8, lhs.url, rhs.url);
            if (order != .eq) return order == .lt;
            return std.mem.order(u8, lhs.ref, rhs.ref) == .lt;
        }
    }.lessThan);

    return .{ .entries = try entries.toOwnedSlice() };
}

pub fn readManifestTextFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, manifest.max_manifest_bytes);
}

pub fn projectManifestPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.mod" });
}

pub fn findRequireLineRange(text: []const u8, url: []const u8) ?struct { start: usize, end: usize } {
    var start: usize = 0;
    while (start < text.len) {
        var end = std.mem.indexOfScalarPos(u8, text, start, '\n') orelse text.len;
        var line = text[start..end];
        if (line.len != 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        const trimmed = std.mem.trim(u8, line, " \t");
        var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
        const first = tokens.next() orelse "";
        const second = tokens.next() orelse "";
        if (std.mem.eql(u8, first, "require") and std.mem.eql(u8, second, url)) {
            if (end < text.len) end += 1; // consume the newline with the line
            return .{ .start = start, .end = end };
        }
        start = end + 1;
    }
    return null;
}

pub fn readManifestFile(allocator: std.mem.Allocator, path: []const u8) !manifest.Manifest {
    const source = try readManifestTextFileAlloc(allocator, path);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, path);
}

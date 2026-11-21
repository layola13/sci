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

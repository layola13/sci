const std = @import("std");
const sio = @import("sio");
const dynlib = @import("../dynlib_compat.zig");
const pkg_manifest = @import("../pkg/manifest.zig");

const InstallOptions = @import("install.zig").InstallOptions;
const SapManifest = @import("install.zig").SapManifest;
const allowedExternalUrl = @import("permissions.zig").allowedExternalUrl;
const archiveFormatFromUrl = @import("fetch.zig").archiveFormatFromUrl;
const confirmExternalUrl = @import("fetch.zig").confirmExternalUrl;
const dirExistsAbsolute = @import("util.zig").dirExistsAbsolute;
const fetchNpmPluginSource = @import("fetch.zig").fetchNpmPluginSource;
const fetchRemoteArchivePluginSource = @import("fetch.zig").fetchRemoteArchivePluginSource;
const installFromPathInternal = @import("install.zig").installFromPathInternal;
const parseArchiveSha256 = @import("fetch.zig").parseArchiveSha256;
const parseSapManifest = @import("fetch.zig").parseSapManifest;
const pluginDevMode = @import("util.zig").pluginDevMode;
const pluginsHome = @import("fetch.zig").pluginsHome;
const readFileAbsoluteAlloc = @import("util.zig").readFileAbsoluteAlloc;

pub fn installPluginDependencies(allocator: std.mem.Allocator, manifest: SapManifest, stdout: anytype, options: InstallOptions, depth: u8, ancestors: []const []const u8) anyerror!u8 {
    for (manifest.dependencies) |dep| {
        const dep_path = dep.path orelse {
            if (dep.optional) continue;
            if (dep.url) |url| {
                const remote_spec = try remoteSpecForDependency(allocator, url, dep.version);
                defer allocator.free(remote_spec);
                const fetched_root = try fetchRemotePluginSource(allocator, remote_spec, stdout, options);
                defer allocator.free(fetched_root);
                var dep_manifest = parseSapManifest(allocator, fetched_root) catch |err| {
            stdout.print("plugin dependency {s}: cannot read manifest at {s}/sap.json: {s}\n", .{ dep.name, fetched_root, @errorName(err) }) catch {};
            const StdoutT = @TypeOf(stdout);
            const StdoutChild = if (@typeInfo(StdoutT) == .pointer) @typeInfo(StdoutT).pointer.child else StdoutT;
            if (@hasDecl(StdoutChild, "flush")) stdout.flush() catch {};
            return err;
        };
                defer dep_manifest.deinit(allocator);
                if (!std.mem.eql(u8, dep_manifest.name, dep.name)) {
                    try stdout.print("plugin dependency name mismatch: expected {s}, found {s}\n", .{ dep.name, dep_manifest.name });
                    return 1;
                }
                if (dep_manifest.abi_plugin != dep.abi) {
                    try stdout.print("plugin dependency {s} ABI mismatch: expected {d}, found {d}\n", .{ dep.name, dep.abi, dep_manifest.abi_plugin });
                    return 1;
                }
                const code = try installFromPathInternal(allocator, fetched_root, stdout, options, depth + 1, ancestors);
                if (code != 0) return code;
                continue;
            } else {
                try stdout.print("required plugin dependency {s} has no local path; remote dependency resolver is not implemented yet\n", .{dep.name});
            }
            return 1;
        };
        const resolved_path = if (std.fs.path.isAbsolute(dep_path))
            try allocator.dupe(u8, dep_path)
        else
            try std.fs.path.join(allocator, &.{ manifest.root_dir, dep_path });
        defer allocator.free(resolved_path);

        var dep_manifest = parseSapManifest(allocator, resolved_path) catch |err| {
            // Name the dependency and the manifest path that was sought:
            // a bare `try` here surfaces only "error: FileNotFound", with
            // no hint which declared dependency is missing on disk
            // (DEF-PLUGIN-DEP-ERR-OPAQUE). The original error is rethrown
            // unchanged; the print is best-effort so it can never mask it.
            // The flush is load-bearing where the writer is the CLI's
            // buffered stdout stream: cli.execute flushes it only on the
            // non-error path, so on this error path an unflushed line
            // would be discarded with the pending buffer exactly when it
            // matters. In-memory writers (sio.ManagedWriter) append
            // immediately and declare no flush; the comptime check keeps
            // both writer shapes valid.
            stdout.print("plugin dependency {s}: cannot read manifest at {s}/sap.json: {s}\n", .{ dep.name, resolved_path, @errorName(err) }) catch {};
            const StdoutT = @TypeOf(stdout);
            const StdoutChild = if (@typeInfo(StdoutT) == .pointer) @typeInfo(StdoutT).pointer.child else StdoutT;
            if (@hasDecl(StdoutChild, "flush")) stdout.flush() catch {};
            return err;
        };
        defer dep_manifest.deinit(allocator);
        if (!std.mem.eql(u8, dep_manifest.name, dep.name)) {
            try stdout.print("plugin dependency name mismatch: expected {s}, found {s}\n", .{ dep.name, dep_manifest.name });
            return 1;
        }
        if (dep_manifest.abi_plugin != dep.abi) {
            try stdout.print("plugin dependency {s} ABI mismatch: expected {d}, found {d}\n", .{ dep.name, dep.abi, dep_manifest.abi_plugin });
            return 1;
        }

        const code = try installFromPathInternal(allocator, resolved_path, stdout, options, depth + 1, ancestors);
        if (code != 0) return code;
    }
    return 0;
}
pub fn listInstalled(allocator: std.mem.Allocator, stdout: anytype) !u8 {
    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const root_path = try std.fs.path.join(allocator, &.{ home, "installed" });
    defer allocator.free(root_path);
    var root = sio.openDirAbsolute(root_path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => {
            try stdout.writeAll("plugin\tinstalled_path\n");
            return 0;
        },
        else => return err,
    };
    defer root.close();

    try stdout.writeAll("plugin\tinstalled_path\n");
    var it = root.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .directory and entry.kind != .sym_link) continue;
        const current = try std.fs.path.join(allocator, &.{ root_path, entry.name, "current" });
        defer allocator.free(current);
        if (dirExistsAbsolute(current)) {
            try stdout.print("{s}\t{s}\n", .{ entry.name, current });
        }
    }
    return 0;
}
pub fn renderPermissionsLock(allocator: std.mem.Allocator, manifest: SapManifest, confirmed: bool, dev_install: bool, workspace_declared: bool) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    const w = &aw.writer;
    const digest_hex = std.fmt.bytesToHex(manifest.permission_digest, .lower);
    const graph_digest = dependencyGraphDigest(manifest);
    const graph_digest_hex = std.fmt.bytesToHex(graph_digest, .lower);
    try w.print(
        \\schema=sa.permissions/1
        \\plugin={s}
        \\version={s}
        \\permissions_sha256={s}
        \\dependency_graph_sha256={s}
        \\requires_confirmation={s}
        \\confirmed={s}
        \\dev_install={s}
        \\workspace_declared={s}
        \\artifact_scan=dynamic-imports
        \\sandbox_enforced=false
        \\
    , .{
        manifest.name,
        manifest.version,
        digest_hex,
        graph_digest_hex,
        if (manifest.requires_sandbox) "true" else "false",
        if (confirmed) "true" else "false",
        if (dev_install) "true" else "false",
        if (workspace_declared) "true" else "false",
    });
    if (manifest.external_urls.len != 0) {
        try w.writeAll("external_urls\n");
        for (manifest.external_urls) |url| try w.print("- {s}\n", .{url});
    }
    if (manifest.dependencies.len != 0) {
        try w.writeAll("plugin_dependencies\n");
        for (manifest.dependencies) |dep| {
            try w.print("- {s} version={s} abi={d} optional={s}", .{
                dep.name,
                dep.version,
                dep.abi,
                if (dep.optional) "true" else "false",
            });
            if (dep.symbols.len != 0) {
                try w.writeAll(" symbols=");
                for (dep.symbols, 0..) |symbol, idx| {
                    if (idx != 0) try w.writeByte(',');
                    try w.writeAll(symbol);
                }
            }
            if (dep.path) |path| try w.print(" path={s}", .{path});
            if (dep.url) |url| try w.print(" url={s}", .{url});
            try w.writeByte('\n');
        }
    }
    if (manifest.native_link.len != 0) {
        try w.writeAll("native_link\n");
        for (manifest.native_link) |entry| {
            switch (entry.kind) {
                .lib => {
                    try w.print("- lib={s}", .{entry.name});
                    if (entry.dirs.len != 0) {
                        try w.writeAll(" dirs=");
                        for (entry.dirs, 0..) |dir, idx| {
                            if (idx != 0) try w.writeByte(',');
                            try w.writeAll(dir);
                        }
                    }
                    try w.writeByte('\n');
                },
                .path => try w.print("- path={s}\n", .{entry.name}),
            }
        }
    }
    return try aw.toOwnedSlice();
}
pub fn dependencyGraphDigest(manifest: SapManifest) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (manifest.dependencies) |dep| {
        hasher.update(dep.name);
        hasher.update("\x00");
        hasher.update(dep.version);
        hasher.update("\x00");
        var abi_buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &abi_buf, dep.abi, .little);
        hasher.update(&abi_buf);
        hasher.update(if (dep.optional) "optional" else "required");
        hasher.update("\x00");
        for (dep.symbols) |symbol| {
            hasher.update(symbol);
            hasher.update("\x00");
        }
        if (dep.path) |path| hasher.update(path);
        hasher.update("\x00");
        if (dep.url) |url| hasher.update(url);
        hasher.update("\x00");
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}
pub fn permissionsLockMatches(allocator: std.mem.Allocator, manifest: SapManifest) !bool {
    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const lock_path = try std.fs.path.join(allocator, &.{ home, "installed", manifest.name, "current", "permissions.lock" });
    defer allocator.free(lock_path);
    const lock_text = readFileAbsoluteAlloc(allocator, lock_path, 1 << 20) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(lock_text);

    const permission_digest_hex = std.fmt.bytesToHex(manifest.permission_digest, .lower);
    const graph_digest = dependencyGraphDigest(manifest);
    const graph_digest_hex = std.fmt.bytesToHex(graph_digest, .lower);
    return lockHasLine(lock_text, "confirmed=true") and
        lockHasKeyValue(lock_text, "permissions_sha256", permission_digest_hex[0..]) and
        lockHasKeyValue(lock_text, "dependency_graph_sha256", graph_digest_hex[0..]);
}
pub fn lockHasKeyValue(text: []const u8, key: []const u8, value: []const u8) bool {
    var line_buf: [256]u8 = undefined;
    const expected = std.fmt.bufPrint(&line_buf, "{s}={s}", .{ key, value }) catch return false;
    return lockHasLine(text, expected);
}
pub fn lockHasLine(text: []const u8, expected: []const u8) bool {
    var it = std.mem.splitScalar(u8, text, '\n');
    while (it.next()) |line| {
        if (std.mem.eql(u8, std.mem.trim(u8, line, " \t\r"), expected)) return true;
    }
    return false;
}
pub const RemotePluginSpec = struct {
    kind: RemotePluginKind,
    url: []u8,
    ref: ?[]u8,
    archive_sha256: ?[32]u8 = null,
    archive_format: ?ArchiveFormat = null,

    pub fn deinit(self: *RemotePluginSpec, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        if (self.ref) |ref| allocator.free(ref);
        self.* = undefined;
    }
};
const RemotePluginKind = enum {
    git,
    archive,
};
pub const ArchiveFormat = enum {
    tar_gz,
    tgz,
    tar_xz,
    tar_zst,
};
pub fn fetchRemotePluginSource(allocator: std.mem.Allocator, spec_text: []const u8, stdout: anytype, options: InstallOptions) ![]u8 {
    if (std.mem.startsWith(u8, spec_text, "npm:")) {
        return try fetchNpmPluginSource(allocator, spec_text, stdout, options);
    }
    var spec = try parseRemotePluginSpec(allocator, spec_text);
    defer spec.deinit(allocator);

    if (!options.dev and !pluginDevMode(allocator)) switch (spec.kind) {
        .git => if (spec.ref == null) {
            try stdout.print("refusing remote plugin install without fixed #ref: {s}\n", .{spec.url});
            return error.RemotePluginRefRequired;
        },
        .archive => if (spec.archive_sha256 == null) {
            try stdout.print("refusing remote plugin archive install without #sha256:<digest>: {s}\n", .{spec.url});
            return error.RemotePluginRefRequired;
        },
    };
    if (!options.dev and !pluginDevMode(allocator)) {
        const confirmed = try confirmExternalUrl(stdout, spec.url);
        if (!confirmed) return error.RemotePluginUrlNotConfirmed;
    }

    return switch (spec.kind) {
        .git => try fetchRemoteGitPluginSource(allocator, spec, stdout),
        .archive => try fetchRemoteArchivePluginSource(allocator, spec, stdout),
    };
}
fn fetchRemoteGitPluginSource(allocator: std.mem.Allocator, spec: RemotePluginSpec, stdout: anytype) ![]u8 {
    std.debug.assert(spec.kind == .git);

    const home = try pluginsHome(allocator);
    defer allocator.free(home);
    const cache_root = try std.fs.path.join(allocator, &.{ home, "cache", "git" });
    defer allocator.free(cache_root);
    try sio.cwd().makePath(cache_root);

    const cache_key = remoteCacheKeyForSpec(spec);
    const cache_key_hex = std.fmt.bytesToHex(cache_key, .lower);
    const checkout_dir = try std.fs.path.join(allocator, &.{ cache_root, cache_key_hex[0..] });
    errdefer allocator.free(checkout_dir);
    if (dirExistsAbsolute(checkout_dir)) try sio.cwd().deleteTree(checkout_dir);

    const clone_result = try sio.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "git", "clone", "--quiet", spec.url, checkout_dir },
    });
    defer allocator.free(clone_result.stdout);
    defer allocator.free(clone_result.stderr);
    if (!childExitedZero(clone_result.term)) {
        try stdout.print("git clone failed for plugin source {s}\n{s}", .{ spec.url, clone_result.stderr });
        return error.RemotePluginFetchFailed;
    }

    if (spec.ref) |ref| {
        const checkout_result = try sio.Child.run(.{
            .allocator = allocator,
            .argv = &.{ "git", "-C", checkout_dir, "checkout", "--quiet", ref },
        });
        defer allocator.free(checkout_result.stdout);
        defer allocator.free(checkout_result.stderr);
        if (!childExitedZero(checkout_result.term)) {
            try stdout.print("git checkout failed for plugin source {s} ref {s}\n{s}", .{ spec.url, ref, checkout_result.stderr });
            return error.RemotePluginFetchFailed;
        }
    }

    return checkout_dir;
}
fn parseRemotePluginSpec(allocator: std.mem.Allocator, spec_text: []const u8) !RemotePluginSpec {
    const split = splitRemoteRef(spec_text);
    const url_text = split.url;
    const ref_text = split.ref;
    const url = if (std.mem.startsWith(u8, url_text, "github:")) blk: {
        const repo = url_text["github:".len..];
        if (repo.len == 0 or std.mem.indexOf(u8, repo, "..") != null) return error.InvalidRemotePluginSource;
        break :blk try std.fmt.allocPrint(allocator, "https://github.com/{s}.git", .{repo});
    } else blk: {
        if (!allowedExternalUrl(url_text)) return error.InvalidRemotePluginSource;
        break :blk try allocator.dupe(u8, url_text);
    };
    errdefer allocator.free(url);
    const ref = if (ref_text) |text| try allocator.dupe(u8, text) else null;
    const archive_format = archiveFormatFromUrl(url_text);
    if (archive_format) |format| {
        const archive_sha256 = if (ref_text) |text| try parseArchiveSha256(text) else null;
        return .{
            .kind = .archive,
            .url = url,
            .ref = ref,
            .archive_sha256 = archive_sha256,
            .archive_format = format,
        };
    }
    return .{
        .kind = .git,
        .url = url,
        .ref = ref,
    };
}
fn splitRemoteRef(text: []const u8) struct { url: []const u8, ref: ?[]const u8 } {
    if (std.mem.lastIndexOfScalar(u8, text, '#')) |idx| {
        const ref = text[idx + 1 ..];
        return .{ .url = text[0..idx], .ref = if (ref.len == 0) null else ref };
    }
    return .{ .url = text, .ref = null };
}
fn remoteSpecForDependency(allocator: std.mem.Allocator, url: []const u8, version: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, url, '#') != null or std.mem.eql(u8, version, "*") or archiveFormatFromUrl(url) != null) {
        return try allocator.dupe(u8, url);
    }
    return try std.fmt.allocPrint(allocator, "{s}#{s}", .{ url, version });
}
pub fn remoteCacheKey(text: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(text);
    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}
pub fn remoteCacheKeyForSpec(spec: RemotePluginSpec) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(spec.url);
    hasher.update("\x00");
    if (spec.ref) |ref| hasher.update(ref);
    hasher.update("\x00");
    if (spec.archive_sha256) |digest| hasher.update(&digest);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}
pub fn childExitedZero(term: sio.Child.Term) bool {
    return switch (term) {
        .exited => |code| code == 0,
        else => false,
    };
}

const std = @import("std");

pub const FetchError = anyerror;

pub const FetchOptions = struct {
    global: bool = false,
    offline: bool = false,
};

pub const FetchResult = struct {
    root: []u8,
    source_sha256: [32]u8 = [_]u8{0} ** 32,

    pub fn deinit(self: *FetchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.root);
        self.* = undefined;
    }
};

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn validateIdentity(identity: []const u8) FetchError!void {
    const trimmed = trim(identity);
    if (trimmed.len == 0) return error.InvalidUrl;
    if (std.mem.indexOfScalar(u8, trimmed, '\x00') != null) return error.InvalidUrl;
    if (std.mem.indexOfScalar(u8, trimmed, '\n') != null or std.mem.indexOfScalar(u8, trimmed, '\r') != null) return error.InvalidUrl;
    if (std.mem.containsAtLeast(u8, trimmed, 1, "../") or std.mem.startsWith(u8, trimmed, "../") or std.mem.eql(u8, trimmed, "..")) {
        return error.InvalidPath;
    }
}

fn validateRef(ref: []const u8) FetchError!void {
    const trimmed = trim(ref);
    if (trimmed.len == 0) return error.InvalidUrl;
    if (std.mem.indexOfAny(u8, trimmed, " \t\r\n\x00") != null) return error.InvalidUrl;
}

fn pathJoin(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return try std.fs.path.join(allocator, parts);
}

fn homeDir(allocator: std.mem.Allocator) ![]u8 {
    return std.process.getEnvVarOwned(allocator, "HOME") catch {
        return std.process.getEnvVarOwned(allocator, "USERPROFILE") catch return error.InvalidPath;
    };
}

fn vendorRoot(allocator: std.mem.Allocator, identity: []const u8) ![]u8 {
    return try pathJoin(allocator, &.{ "sa_vendor", identity });
}

fn globalRoot(allocator: std.mem.Allocator, home: []const u8, identity: []const u8, ref: []const u8) ![]u8 {
    const leaf = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ identity, ref });
    errdefer allocator.free(leaf);
    const joined = try pathJoin(allocator, &.{ home, ".sa", "pkg", leaf });
    allocator.free(leaf);
    return joined;
}

fn looksLikeRemote(identity: []const u8) bool {
    return std.mem.containsAtLeast(u8, identity, 1, "://") or
        (std.mem.indexOfScalar(u8, identity, '@') != null and std.mem.indexOfScalar(u8, identity, ':') != null and
        (std.mem.indexOfScalar(u8, identity, '/') orelse identity.len) > (std.mem.indexOfScalar(u8, identity, ':') orelse identity.len));
}

fn remoteUrlFromIdentity(allocator: std.mem.Allocator, identity: []const u8) ![]u8 {
    if (std.mem.containsAtLeast(u8, identity, 1, "://") or looksLikeRemote(identity)) {
        return allocator.dupe(u8, identity);
    }
    return try std.fmt.allocPrint(allocator, "https://{s}.git", .{identity});
}

fn deleteExistingDir(path: []const u8) !void {
    std.fs.cwd().deleteTree(path) catch {};
}

fn pathHasPrecompiledArtifact(name: []const u8) bool {
    const lower = std.ascii.lowerString;
    var buf: [256]u8 = undefined;
    const slice = if (name.len <= buf.len) lower(&buf, name) else name;
    return std.mem.endsWith(u8, slice, ".so") or
        std.mem.endsWith(u8, slice, ".dll") or
        std.mem.endsWith(u8, slice, ".dylib") or
        std.mem.endsWith(u8, slice, ".a") or
        std.mem.endsWith(u8, slice, ".lib") or
        std.mem.endsWith(u8, slice, ".whl") or
        std.mem.endsWith(u8, slice, ".node");
}

fn isIgnoredTreeDir(name: []const u8) bool {
    return std.mem.eql(u8, name, ".git") or
        std.mem.eql(u8, name, ".codex") or
        std.mem.eql(u8, name, ".mimir") or
        std.mem.eql(u8, name, ".kiro") or
        std.mem.eql(u8, name, "artifacts") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, "zig-cache");
}

fn rejectPrecompiledArtifacts(root: std.fs.Dir, allocator: std.mem.Allocator) !void {
    var walker = try root.walk(allocator);
    defer walker.deinit();
    while (try walker.next()) |entry| {
        if (entry.kind != .file) continue;
        if (pathHasPrecompiledArtifact(entry.basename)) return error.PrecompiledArtifactRejected;
    }
}

fn copyTree(src_root: []const u8, dst_root: []const u8, allocator: std.mem.Allocator) !void {
    var src_dir = try std.fs.cwd().openDir(src_root, .{ .iterate = true });
    defer src_dir.close();

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .directory and isIgnoredTreeDir(entry.basename)) continue;
        const dst_path = try std.fs.path.join(allocator, &.{ dst_root, entry.path });
        defer allocator.free(dst_path);

        switch (entry.kind) {
            .directory => {
                try std.fs.cwd().makePath(dst_path);
            },
            .file => {
                if (pathHasPrecompiledArtifact(entry.basename)) return error.PrecompiledArtifactRejected;
                if (std.fs.path.dirname(dst_path)) |parent| {
                    try std.fs.cwd().makePath(parent);
                }
                try std.fs.Dir.copyFile(entry.dir, entry.basename, std.fs.cwd(), dst_path, .{});
            },
            else => {},
        }
    }
}

fn setReadOnlyRecursive(root_path: []const u8, allocator: std.mem.Allocator) !void {
    var root_dir = try std.fs.cwd().openDir(root_path, .{ .iterate = true });
    defer root_dir.close();

    var walker = try root_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => {
                var file = try entry.dir.openFile(entry.basename, .{ .mode = .read_only });
                defer file.close();
                try file.chmod(0o444);
            },
            .directory => {
                var dir = try entry.dir.openDir(entry.basename, .{ .iterate = true });
                defer dir.close();
                try dir.chmod(0o555);
            },
            else => {},
        }
    }

    try root_dir.chmod(0o555);
}

fn runGitClone(allocator: std.mem.Allocator, identity: []const u8, ref: []const u8, target_root: []const u8) !void {
    const remote_url = try remoteUrlFromIdentity(allocator, identity);
    defer allocator.free(remote_url);

    var argv = std.ArrayList([]const u8).init(allocator);
    defer argv.deinit();

    try argv.appendSlice(&.{ "git", "clone", "--depth", "1" });
    if (!std.mem.eql(u8, ref, "HEAD")) {
        try argv.appendSlice(&.{ "--branch", ref, "--single-branch" });
    }
    try argv.append(remote_url);
    try argv.append(target_root);

    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const exec_argv = try arena_alloc.allocSentinel(?[*:0]const u8, argv.items.len, null);
    for (argv.items, 0..) |arg, idx| {
        exec_argv[idx] = (try arena_alloc.dupeZ(u8, arg)).ptr;
    }
    const envp = (try std.process.createNullDelimitedEnvMap(arena_alloc, &env_map)).ptr;

    const pid = try std.posix.fork();
    if (pid == 0) {
        const git_z: [*:0]const u8 = "git";
        std.posix.execvpeZ(git_z, exec_argv.ptr, envp) catch {
            std.posix.exit(127);
        };
        unreachable;
    }

    const wait_result = std.posix.waitpid(pid, 0);
    if (wait_result.pid != pid) return error.SourceNotFound;
    if (wait_result.status != 0) {
        return error.SourceNotFound;
    }
}

fn fetchTargetRoot(allocator: std.mem.Allocator, identity: []const u8, ref: []const u8, global: bool) ![]u8 {
    if (global) {
        const home = try homeDir(allocator);
        defer allocator.free(home);
        const dir = try std.fmt.allocPrint(allocator, "{s}/.sa/pkg/{s}@{s}", .{ home, identity, ref });
        errdefer allocator.free(dir);
        return dir;
    }
    return vendorRoot(allocator, identity);
}

pub fn fetchPackage(allocator: std.mem.Allocator, identity: []const u8, ref: []const u8, options: FetchOptions) !FetchResult {
    try validateIdentity(identity);
    try validateRef(ref);

    const target_root = try fetchTargetRoot(allocator, identity, ref, options.global);
    errdefer allocator.free(target_root);

    if (std.mem.eql(u8, identity, target_root)) return error.InvalidPath;
    try deleteExistingDir(target_root);
    try std.fs.cwd().makePath(target_root);

    var fetched_local = false;
    if (options.offline) {
        if (std.fs.cwd().openDir(identity, .{ .iterate = true })) |source_dir| {
            var source_dir_owned = source_dir;
            defer source_dir_owned.close();
            try copyTree(identity, target_root, allocator);
            fetched_local = true;
        } else |_| {
            return error.SourceNotFound;
        }
    } else if (std.fs.cwd().openDir(identity, .{ .iterate = true })) |source_dir| {
        var source_dir_owned = source_dir;
        defer source_dir_owned.close();
        try copyTree(identity, target_root, allocator);
        fetched_local = true;
    } else |_| {
        try runGitClone(allocator, identity, ref, target_root);
    }

    if (!fetched_local) {
        var target_dir = try std.fs.cwd().openDir(target_root, .{ .iterate = true });
        defer target_dir.close();
        try rejectPrecompiledArtifacts(target_dir, allocator);
    }

    if (options.global) {
        try setReadOnlyRecursive(target_root, allocator);
    }

    return .{ .root = target_root };
}

pub fn downloadLocal(allocator: std.mem.Allocator, identity: []const u8) !FetchResult {
    return fetchPackage(allocator, identity, "HEAD", .{});
}

pub fn downloadGlobal(allocator: std.mem.Allocator, identity: []const u8, ref: []const u8) !FetchResult {
    return fetchPackage(allocator, identity, ref, .{ .global = true });
}

test "fetch copies a local source tree into sa_vendor" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("github.com/example/pkg/src");
    var src_file = try tmp.dir.createFile("github.com/example/pkg/src/main.sa", .{ .truncate = true });
    defer src_file.close();
    try src_file.writeAll("@main() -> i32:\n    return 0\n");

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    var result = try fetchPackage(std.testing.allocator, "github.com/example/pkg", "HEAD", .{});
    defer result.deinit(std.testing.allocator);

    var copied = try std.fs.cwd().openDir(result.root, .{ .iterate = true });
    defer copied.close();
    try copied.access("src/main.sa", .{ .mode = .read_only });
}

test "fetch rejects precompiled artifacts" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("github.com/example/bad");
    var bad_file = try tmp.dir.createFile("github.com/example/bad/libfoo.so", .{ .truncate = true });
    defer bad_file.close();
    try bad_file.writeAll("x");

    var old_cwd = try std.fs.cwd().openDir(".", .{});
    defer old_cwd.close();
    try tmp.dir.setAsCwd();
    defer old_cwd.setAsCwd() catch {};

    try std.testing.expectError(error.PrecompiledArtifactRejected, fetchPackage(std.testing.allocator, "github.com/example/bad", "HEAD", .{}));
}

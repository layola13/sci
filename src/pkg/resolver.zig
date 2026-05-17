const std = @import("std");

pub const ResolveError = error{
    OutOfMemory,
    InvalidPath,
    InvalidImportPath,
    PackageNotResolved,
    AmbiguousPackageVersion,
};

pub const Dependency = struct {
    url: []const u8,
    ref: []const u8,
};

pub const ResolveOptions = struct {
    project_root: ?[]const u8 = null,
    home_dir: ?[]const u8 = null,
    offline: bool = false,
    entry_candidates: []const []const u8 = &.{ "index.saasm", "main.saasm" },
    max_local_file_bytes: usize = 16 * 1024 * 1024,
};

pub const ResolvedImport = struct {
    entry_path: []u8,
    entry_path_owned: bool = true,
    root_dir: ?[]u8 = null,
    package_identity: ?[]u8 = null,
    source: []const u8,
    owned_source: ?[]u8 = null,
    mapped: ?[]align(std.heap.page_size_min) u8 = null,
    is_global: bool = false,

    pub fn deinit(self: *ResolvedImport, allocator: std.mem.Allocator) void {
        if (self.mapped) |mapped| {
            std.posix.munmap(mapped);
        } else if (self.owned_source) |owned_source| {
            allocator.free(owned_source);
        }
        if (self.entry_path_owned) allocator.free(self.entry_path);
        if (self.root_dir) |root_dir| allocator.free(root_dir);
        if (self.package_identity) |package_identity| allocator.free(package_identity);
        self.* = undefined;
    }
};

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn validateImportPath(path: []const u8) ResolveError!void {
    const trimmed = trim(path);
    if (trimmed.len == 0) return error.InvalidImportPath;
    if (std.mem.indexOfScalar(u8, trimmed, '\x00') != null) return error.InvalidImportPath;
    if (std.mem.indexOfScalar(u8, trimmed, '\n') != null or std.mem.indexOfScalar(u8, trimmed, '\r') != null) return error.InvalidImportPath;
}

fn validateIdentity(identity: []const u8) ResolveError!void {
    const trimmed = trim(identity);
    if (trimmed.len == 0) return error.InvalidImportPath;
    if (std.mem.indexOfScalar(u8, trimmed, '\x00') != null) return error.InvalidImportPath;
    if (std.mem.indexOfScalar(u8, trimmed, '\n') != null or std.mem.indexOfScalar(u8, trimmed, '\r') != null) return error.InvalidImportPath;
    if (std.mem.startsWith(u8, trimmed, "/") or std.mem.startsWith(u8, trimmed, "./") or std.mem.startsWith(u8, trimmed, "../")) {
        return error.InvalidImportPath;
    }
    if (std.mem.containsAtLeast(u8, trimmed, 1, "../")) return error.InvalidImportPath;
}

fn validateRef(ref: []const u8) ResolveError!void {
    const trimmed = trim(ref);
    if (trimmed.len == 0) return error.InvalidImportPath;
    if (std.mem.indexOfAny(u8, trimmed, " \t\r\n\x00") != null) return error.InvalidImportPath;
}

fn isPackageIdentity(import_path: []const u8) bool {
    const trimmed = trim(import_path);
    if (trimmed.len == 0) return false;
    if (std.fs.path.isAbsolute(trimmed)) return false;
    if (std.mem.startsWith(u8, trimmed, "./") or std.mem.startsWith(u8, trimmed, "../")) return false;
    return !std.mem.endsWith(u8, trimmed, ".saasm") and
        !std.mem.endsWith(u8, trimmed, ".saasm-iface") and
        !std.mem.endsWith(u8, trimmed, ".saasm-layout");
}

fn projectRootPath(allocator: std.mem.Allocator, options: ResolveOptions) ResolveError![]u8 {
    if (options.project_root) |project_root| {
        return allocator.dupe(u8, project_root);
    }
    return std.fs.cwd().realpathAlloc(allocator, ".") catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidPath,
    };
}

fn homeDirPath(allocator: std.mem.Allocator, options: ResolveOptions) ResolveError![]u8 {
    if (options.home_dir) |home_dir| {
        return allocator.dupe(u8, home_dir);
    }
    return std.process.getEnvVarOwned(allocator, "HOME") catch {
        return std.process.getEnvVarOwned(allocator, "USERPROFILE") catch return error.InvalidPath;
    };
}

fn pathJoin(allocator: std.mem.Allocator, parts: []const []const u8) ResolveError![]u8 {
    return try std.fs.path.join(allocator, parts);
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ResolveError![]u8 {
    var file = std.fs.cwd().openFile(path, .{}) catch return error.PackageNotResolved;
    defer file.close();

    return file.readToEndAlloc(allocator, max_bytes) catch error.PackageNotResolved;
}

fn mapFileReadOnly(path: []const u8) ResolveError!struct { mapped: []align(std.heap.page_size_min) u8, source: []u8 } {
    var file = std.fs.cwd().openFile(path, .{}) catch return error.PackageNotResolved;
    defer file.close();

    const end_pos = file.getEndPos() catch return error.PackageNotResolved;
    const len = std.math.cast(usize, end_pos) orelse return error.PackageNotResolved;
    if (len == 0) return error.PackageNotResolved;

    const mapped = std.posix.mmap(
        null,
        len,
        std.posix.PROT.READ,
        .{ .TYPE = .SHARED },
        file.handle,
        0,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.PackageNotResolved,
    };
    return .{ .mapped = mapped, .source = mapped };
}

fn resolveRelativeImport(
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    import_path: []const u8,
    max_bytes: usize,
) ResolveError!?ResolvedImport {
    const candidate = if (std.fs.path.isAbsolute(import_path))
        try allocator.dupe(u8, import_path)
    else
        try pathJoin(allocator, &.{ base_dir, import_path });
    defer allocator.free(candidate);

    const canonical = std.fs.cwd().realpathAlloc(allocator, candidate) catch return null;
    errdefer allocator.free(canonical);

    const source = try readFileAlloc(allocator, canonical, max_bytes);
    return .{
        .entry_path = canonical,
        .source = source,
        .owned_source = source,
    };
}

fn findRequireEntry(entries: []const Dependency, identity: []const u8) ResolveError!?Dependency {
    var matched: ?Dependency = null;
    for (entries) |entry| {
        if (!std.mem.eql(u8, entry.url, identity)) continue;
        if (matched != null) return error.AmbiguousPackageVersion;
        matched = entry;
    }
    return matched;
}

fn resolveFromPackageRoot(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    package_identity: ?[]const u8,
    entry_candidates: []const []const u8,
    global: bool,
    max_bytes: usize,
) ResolveError!?ResolvedImport {
    const canonical_root = std.fs.cwd().realpathAlloc(allocator, root_dir) catch return null;
    errdefer allocator.free(canonical_root);

    var root_dir_handle = std.fs.cwd().openDir(canonical_root, .{ .iterate = true }) catch return null;
    defer root_dir_handle.close();

    for (entry_candidates) |entry_name| {
        const candidate = try pathJoin(allocator, &.{ canonical_root, entry_name });
        defer allocator.free(candidate);

        const canonical_entry = std.fs.cwd().realpathAlloc(allocator, candidate) catch continue;
        errdefer allocator.free(canonical_entry);

        if (global) {
            const mapped = try mapFileReadOnly(canonical_entry);
            var resolved: ResolvedImport = .{
                .entry_path = canonical_entry,
                .root_dir = canonical_root,
                .source = mapped.source,
                .owned_source = null,
                .mapped = mapped.mapped,
                .is_global = true,
            };
            if (package_identity) |identity| {
                resolved.package_identity = try allocator.dupe(u8, identity);
            }
            return resolved;
        }

        const source = try readFileAlloc(allocator, canonical_entry, max_bytes);
        var resolved: ResolvedImport = .{
            .entry_path = canonical_entry,
            .root_dir = canonical_root,
            .source = source,
            .owned_source = source,
        };
        if (package_identity) |identity| {
            resolved.package_identity = try allocator.dupe(u8, identity);
        }
        return resolved;
    }

    return null;
}

fn localVendorRoot(allocator: std.mem.Allocator, project_root: []const u8, identity: []const u8) ResolveError![]u8 {
    return pathJoin(allocator, &.{ project_root, "sa_vendor", identity });
}

fn globalCacheRoot(allocator: std.mem.Allocator, home_dir: []const u8, identity: []const u8, ref: []const u8) ResolveError![]u8 {
    const leaf = try std.fmt.allocPrint(allocator, "{s}@{s}", .{ identity, ref });
    errdefer allocator.free(leaf);
    const root = try pathJoin(allocator, &.{ home_dir, ".sa", "pkg", leaf });
    allocator.free(leaf);
    return root;
}

pub fn resolveImport(
    allocator: std.mem.Allocator,
    dependencies: []const Dependency,
    base_dir: []const u8,
    import_path: []const u8,
    options: ResolveOptions,
) ResolveError!ResolvedImport {
    try validateImportPath(import_path);

    if (try resolveRelativeImport(allocator, base_dir, import_path, options.max_local_file_bytes)) |resolved| {
        return resolved;
    }

    if (!isPackageIdentity(import_path)) return error.PackageNotResolved;

    const project_root = try projectRootPath(allocator, options);
    defer allocator.free(project_root);

    const local_root = try localVendorRoot(allocator, project_root, import_path);
    defer allocator.free(local_root);

    if (try resolveFromPackageRoot(allocator, local_root, import_path, options.entry_candidates, false, options.max_local_file_bytes)) |resolved| {
        return resolved;
    }

    if (options.offline) return error.PackageNotResolved;

    const require_entry = try findRequireEntry(dependencies, import_path) orelse return error.PackageNotResolved;
    try validateIdentity(require_entry.url);
    try validateRef(require_entry.ref);

    const home_dir = try homeDirPath(allocator, options);
    defer allocator.free(home_dir);

    const global_root = try globalCacheRoot(allocator, home_dir, require_entry.url, require_entry.ref);
    defer allocator.free(global_root);

    if (try resolveFromPackageRoot(allocator, global_root, import_path, options.entry_candidates, true, options.max_local_file_bytes)) |resolved| {
        return resolved;
    }

    return error.PackageNotResolved;
}

test "resolveImport prefers a relative source file" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("src");
    var source_file = try tmp.dir.createFile("src/module.saasm", .{ .truncate = true });
    defer source_file.close();
    try source_file.writeAll("@main() -> i32:\n    return 0\n");

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{},
        root,
        "src/module.saasm",
        .{},
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(std.mem.endsWith(u8, resolved.entry_path, "src/module.saasm"));
    try std.testing.expectEqualStrings("@main() -> i32:\n    return 0\n", resolved.source);
    try std.testing.expect(resolved.root_dir == null);
}

test "resolveImport falls back to local vendor package roots" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("sa_vendor/github.com/example/pkg");
    var index = try tmp.dir.createFile("sa_vendor/github.com/example/pkg/index.saasm", .{ .truncate = true });
    defer index.close();
    try index.writeAll("@pkg() -> i32:\n    return 123\n");

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{},
        root,
        "github.com/example/pkg",
        .{ .project_root = root },
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(resolved.root_dir != null);
    try std.testing.expect(std.mem.endsWith(u8, resolved.entry_path, "sa_vendor/github.com/example/pkg/index.saasm"));
    try std.testing.expectEqualStrings("@pkg() -> i32:\n    return 123\n", resolved.source);
    try std.testing.expect(!resolved.is_global);
}

test "resolveImport maps global cache entries read-only" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath(".sa/pkg/github.com/example/pkg@v1");
    var index = try tmp.dir.createFile(".sa/pkg/github.com/example/pkg@v1/index.saasm", .{ .truncate = true });
    defer index.close();
    try index.writeAll("@global() -> i32:\n    return 7\n");

    const home = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(home);

    const dependency = Dependency{
        .url = "github.com/example/pkg",
        .ref = "v1",
    };

    const resolved = try resolveImport(
        std.testing.allocator,
        &.{dependency},
        home,
        "github.com/example/pkg",
        .{ .project_root = home, .home_dir = home },
    );
    defer {
        var owned = resolved;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(resolved.is_global);
    try std.testing.expect(resolved.mapped != null);
    try std.testing.expect(std.mem.endsWith(u8, resolved.entry_path, ".sa/pkg/github.com/example/pkg@v1/index.saasm"));
    try std.testing.expectEqualStrings("@global() -> i32:\n    return 7\n", resolved.source);
}

test "resolveImport returns PackageNotResolved when cache misses" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const root = try tmp.dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(root);

    try std.testing.expectError(
        error.PackageNotResolved,
        resolveImport(
            std.testing.allocator,
            &.{},
            root,
            "github.com/example/missing",
            .{ .project_root = root, .offline = true },
        ),
    );
}

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const pkg_resolver = @import("../pkg/resolver.zig");
const cacheBytes = @import("cache.zig").cacheBytes;
const cacheCompilerVersion = @import("cache.zig").cacheCompilerVersion;
const cacheKeyNormalizedPath = @import("cache.zig").cacheKeyNormalizedPath;
const projectFileMaybeHash = @import("cache.zig").projectFileMaybeHash;
const loadSource = @import("compile.zig").loadSource;
const line_classifier = @import("../flattener/line_classifier.zig");
const flattener = @import("../flattener.zig");

pub const StdTreeDigestEntry = struct {
    digest: [32]u8,
    files: []SourceTreeFileStat,
};

pub var std_tree_digest_mutex: std.atomic.Mutex = .unlocked;

pub var std_tree_digest_cache: ?std.StringHashMap(StdTreeDigestEntry) = null;

pub const SourceTreeFileStat = struct {
    path: []u8,
    mtime: std.Io.Timestamp,
    size: u64,
};

pub const SourceTreeHashCacheEntry = struct {
    digest: [32]u8,
    files: []SourceTreeFileStat,
    last_used_tick: u64,
};

pub var source_tree_hash_cache_mutex: std.atomic.Mutex = .unlocked;

pub var source_tree_hash_cache: ?std.StringHashMap(SourceTreeHashCacheEntry) = null;

pub var source_tree_hash_cache_tick: u64 = 0;

pub var test_source_tree_hash_cache_max_entries: ?usize = null;

/// The spelling of one source-tree file as fed into the source tree hash:
/// project files and std files are named by their root-relative layout
/// ("proj/..." / "std/..."), so the same import closure hashes identically
/// in every checkout. Files under neither root keep their real path.
pub fn cacheKeyTreePath(
    allocator: std.mem.Allocator,
    real_path: []const u8,
    project_root_real: []const u8,
    std_root_real: []const u8,
) ![]u8 {
    if (real_path.len > project_root_real.len and
        std.mem.startsWith(u8, real_path, project_root_real) and
        real_path[project_root_real.len] == std.fs.path.sep)
    {
        return std.fmt.allocPrint(allocator, "proj/{s}", .{real_path[project_root_real.len + 1 ..]});
    }
    if (real_path.len > std_root_real.len and
        std.mem.startsWith(u8, real_path, std_root_real) and
        real_path[std_root_real.len] == std.fs.path.sep)
    {
        return std.fmt.allocPrint(allocator, "std/{s}", .{real_path[std_root_real.len + 1 ..]});
    }
    return allocator.dupe(u8, real_path);
}

pub fn stdTreeDigestCacheMap() *std.StringHashMap(StdTreeDigestEntry) {
    if (std_tree_digest_cache == null) {
        std_tree_digest_cache = std.StringHashMap(StdTreeDigestEntry).init(std.heap.page_allocator);
    }
    return &std_tree_digest_cache.?;
}

pub fn lockStdTreeDigestCache() void {
    while (!std_tree_digest_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

pub fn freeStdTreeDigestEntry(entry: StdTreeDigestEntry) void {
    for (entry.files) |file| std.heap.page_allocator.free(file.path);
    std.heap.page_allocator.free(entry.files);
}

pub fn stdTreeScratchDir(name: []const u8) bool {
    return std.mem.eql(u8, name, ".sla-cache") or
        std.mem.eql(u8, name, ".sa_cache") or
        std.mem.eql(u8, name, ".zig-cache") or
        std.mem.eql(u8, name, "zig-out") or
        std.mem.eql(u8, name, ".git");
}

/// The built runtime archive is a product of the tree, not a source in
/// it. Hermetic std-root layouts place the archive inside the tree; its
/// bytes must still not enter the digest (they are not reproducible
/// across checkouts, and the tree is the archive's identity, not the
/// other way round).
pub fn stdTreeArchiveName(name: []const u8) bool {
    return std.mem.eql(u8, name, "libsa_std.a") or std.mem.eql(u8, name, "sa_std.lib");
}

/// Stream a file's contents into the hasher (no whole-file allocation,
/// no size cap).
pub fn hashFileContentsInto(hasher: *std.crypto.hash.sha2.Sha256, path: []const u8) !void {
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try file.read(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
}

/// Collect (relative path, stat) for every regular file under dir,
/// recursively. Symlinks to files count by their target's stat; symlinks
/// to directories are not followed (cycle risk beats the exotic layout).
pub fn collectStdTreeFiles(
    allocator: std.mem.Allocator,
    dir: sio.Dir,
    prefix: []const u8,
    out: *std.array_list.Managed(SourceTreeFileStat),
) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .directory) {
            if (stdTreeScratchDir(entry.name)) continue;
            var sub = try dir.openDir(entry.name, .{ .iterate = true });
            defer sub.close();
            const sub_prefix = if (prefix.len == 0)
                try allocator.dupe(u8, entry.name)
            else
                try std.fs.path.join(allocator, &.{ prefix, entry.name });
            defer allocator.free(sub_prefix);
            try collectStdTreeFiles(allocator, sub, sub_prefix, out);
        } else if (entry.kind == .file or entry.kind == .sym_link) {
            if (stdTreeArchiveName(entry.name)) continue;
            const stat = dir.statFile(entry.name) catch continue;
            if (stat.kind != .file) continue;
            const rel = if (prefix.len == 0)
                try allocator.dupe(u8, entry.name)
            else
                try std.fs.path.join(allocator, &.{ prefix, entry.name });
            errdefer allocator.free(rel);
            try out.append(.{ .path = rel, .mtime = stat.mtime, .size = stat.size });
        }
    }
}

pub fn stdTreeStatLessThan(_: void, a: SourceTreeFileStat, b: SourceTreeFileStat) bool {
    return std.mem.order(u8, a.path, b.path) == .lt;
}

/// Content digest of the std source tree at std_root, or null when the
/// tree is absent/empty (callers then feed nothing, mirroring the old
/// missing-archive behavior). Memoized per process: a memo entry is
/// reused only when a fresh stat walk reproduces its exact file list
/// (path + mtime + size), so edits, additions and removals all recompute.
pub fn stdTreeDigest(allocator: std.mem.Allocator, std_root: []const u8) !?[32]u8 {
    const root_real = sio.cwd().realpathAlloc(allocator, std_root) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.NotDir => return null,
        else => return err,
    };
    defer allocator.free(root_real);

    var root_dir = sio.cwd().openDir(root_real, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.AccessDenied, error.NotDir => return null,
        else => return err,
    };
    defer root_dir.close();

    // Fresh stat walk (relative paths) — the shape the memo validates
    // against and the digest is computed over.
    var files = std.array_list.Managed(SourceTreeFileStat).init(allocator);
    defer {
        for (files.items) |file| allocator.free(file.path);
        files.deinit();
    }
    try collectStdTreeFiles(allocator, root_dir, "", &files);
    if (files.items.len == 0) return null;
    std.mem.sort(SourceTreeFileStat, files.items, {}, stdTreeStatLessThan);

    {
        lockStdTreeDigestCache();
        defer std_tree_digest_mutex.unlock();
        const cache = stdTreeDigestCacheMap();
        if (cache.get(root_real)) |entry| {
            if (stdTreeFileListsEqual(entry.files, files.items, root_real)) return entry.digest;
        }
    }

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    for (files.items) |file| {
        const full_path = try std.fs.path.join(allocator, &.{ root_real, file.path });
        defer allocator.free(full_path);
        cacheBytes(&hasher, file.path);
        try hashFileContentsInto(&hasher, full_path);
        hasher.update(&[_]u8{0});
    }
    var digest: [32]u8 = undefined;
    hasher.final(&digest);

    {
        lockStdTreeDigestCache();
        defer std_tree_digest_mutex.unlock();
        const cache = stdTreeDigestCacheMap();
        const memo_files = try std.heap.page_allocator.alloc(SourceTreeFileStat, files.items.len);
        var filled: usize = 0;
        errdefer {
            for (memo_files[0..filled]) |file| std.heap.page_allocator.free(file.path);
            std.heap.page_allocator.free(memo_files);
        }
        for (files.items) |file| {
            memo_files[filled] = .{
                .path = try std.heap.page_allocator.dupe(u8, file.path),
                .mtime = file.mtime,
                .size = file.size,
            };
            filled += 1;
        }
        const memo_key = try std.heap.page_allocator.dupe(u8, root_real);
        errdefer std.heap.page_allocator.free(memo_key);
        const gop = try cache.getOrPut(memo_key);
        if (gop.found_existing) {
            std.heap.page_allocator.free(memo_key);
            freeStdTreeDigestEntry(gop.value_ptr.*);
        }
        gop.value_ptr.* = .{ .digest = digest, .files = memo_files };
    }
    return digest;
}

/// A memo entry's stored file list holds root-relative paths; the fresh
/// walk's list must match it exactly (same files, same stats) for the
/// stored digest to still describe the tree. root_real is unused today —
/// both lists are relative — but keeps the comparison anchored to one
/// canonical root spelling if absolute forms are ever stored.
pub fn stdTreeFileListsEqual(stored: []SourceTreeFileStat, fresh: []SourceTreeFileStat, root_real: []const u8) bool {
    _ = root_real;
    if (stored.len != fresh.len) return false;
    for (stored, fresh) |a, b| {
        if (!std.mem.eql(u8, a.path, b.path)) return false;
        if (a.size != b.size) return false;
        if (a.mtime.toNanoseconds() != b.mtime.toNanoseconds()) return false;
    }
    return true;
}

pub fn sourceTreeHashCacheMap() *std.StringHashMap(SourceTreeHashCacheEntry) {
    if (source_tree_hash_cache == null) {
        source_tree_hash_cache = std.StringHashMap(SourceTreeHashCacheEntry).init(std.heap.page_allocator);
    }
    return &source_tree_hash_cache.?;
}

pub fn freeSourceTreeHashCacheEntry(entry: SourceTreeHashCacheEntry) void {
    for (entry.files) |file| std.heap.page_allocator.free(file.path);
    std.heap.page_allocator.free(entry.files);
}

pub fn sourceTreeHashCacheMaxEntries() ?usize {
    if (builtin.is_test) {
        if (test_source_tree_hash_cache_max_entries) |value| return value;
    }
    const value = sio.getEnvVarOwned(std.heap.page_allocator, "SA_SOURCE_TREE_HASH_CACHE_MAX_ENTRIES") catch return null;
    defer std.heap.page_allocator.free(value);
    const parsed = std.fmt.parseUnsigned(usize, value, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

pub fn nextSourceTreeHashCacheTickLocked() u64 {
    source_tree_hash_cache_tick +%= 1;
    return source_tree_hash_cache_tick;
}

pub fn buildSourceTreeHashCacheKey(
    allocator: std.mem.Allocator,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    real_source_path: []const u8,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendCacheKeyBytes(&out, cacheCompilerVersion());
    try appendCacheKeyBytes(&out, project_root);
    try appendCacheKeyBytes(&out, std_root);
    try appendCacheKeyBytes(&out, real_source_path);
    var offline_buf: [8]u8 = undefined;
    const offline_text = try std.fmt.bufPrint(&offline_buf, "{}\x00", .{offline});
    try out.appendSlice(offline_text);
    for (plugin_import_roots) |root| try appendCacheKeyBytes(&out, root);
    try out.append(0);
    for (dependencies) |dep| {
        try appendCacheKeyBytes(&out, dep.url);
        try appendCacheKeyBytes(&out, dep.ref);
    }
    return try out.toOwnedSlice();
}

pub fn appendCacheKeyBytes(out: *std.array_list.Managed(u8), bytes: []const u8) !void {
    try out.appendSlice(bytes);
    try out.append(0);
}

pub fn sourceTreeHashCacheHit(cache_key: []const u8) ?[32]u8 {
    while (!source_tree_hash_cache_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer source_tree_hash_cache_mutex.unlock();
    const cache = sourceTreeHashCacheMap();
    const entry = cache.getPtr(cache_key) orelse return null;
    for (entry.files) |file| {
        const stat = sio.cwd().statFile(file.path) catch return null;
        if (stat.mtime.toNanoseconds() != file.mtime.toNanoseconds() or stat.size != file.size) return null;
    }
    entry.last_used_tick = nextSourceTreeHashCacheTickLocked();
    return entry.digest;
}

pub fn storeSourceTreeHashCacheEntry(cache_key: []const u8, digest: [32]u8, files: []const SourceTreeFileStat) !void {
    const cache_allocator = std.heap.page_allocator;
    const owned_key = try cache_allocator.dupe(u8, cache_key);
    errdefer cache_allocator.free(owned_key);
    const owned_files = try cache_allocator.alloc(SourceTreeFileStat, files.len);
    errdefer cache_allocator.free(owned_files);
    var copied: usize = 0;
    errdefer {
        for (owned_files[0..copied]) |file| cache_allocator.free(file.path);
    }
    for (files, 0..) |file, idx| {
        owned_files[idx] = .{
            .path = try cache_allocator.dupe(u8, file.path),
            .mtime = file.mtime,
            .size = file.size,
        };
        copied += 1;
    }

    while (!source_tree_hash_cache_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer source_tree_hash_cache_mutex.unlock();
    var cache = sourceTreeHashCacheMap();
    if (cache.getPtr(cache_key)) |old| {
        freeSourceTreeHashCacheEntry(old.*);
        old.* = .{ .digest = digest, .files = owned_files, .last_used_tick = nextSourceTreeHashCacheTickLocked() };
        cache_allocator.free(owned_key);
        evictSourceTreeHashCacheIfNeeded(cache, sourceTreeHashCacheMaxEntries());
        return;
    }
    try cache.put(owned_key, .{ .digest = digest, .files = owned_files, .last_used_tick = nextSourceTreeHashCacheTickLocked() });
    evictSourceTreeHashCacheIfNeeded(cache, sourceTreeHashCacheMaxEntries());
}

pub fn evictSourceTreeHashCacheIfNeeded(cache: *std.StringHashMap(SourceTreeHashCacheEntry), max_entries: ?usize) void {
    const limit = max_entries orelse return;
    while (cache.count() > limit) {
        var oldest_key: ?[]const u8 = null;
        var oldest_tick: u64 = std.math.maxInt(u64);
        var it = cache.iterator();
        while (it.next()) |entry| {
            if (entry.value_ptr.last_used_tick <= oldest_tick) {
                oldest_key = entry.key_ptr.*;
                oldest_tick = entry.value_ptr.last_used_tick;
            }
        }
        const key = oldest_key orelse return;
        if (cache.fetchRemove(key)) |removed| {
            std.heap.page_allocator.free(removed.key);
            freeSourceTreeHashCacheEntry(removed.value);
        } else {
            return;
        }
    }
}

pub fn addSourceTreeDigestToHasher(hasher: *std.crypto.hash.sha2.Sha256, digest: [32]u8) void {
    // v2: file identities inside the digest are root-relative layout
    // names, not absolute real paths (see cacheKeyTreePath).
    cacheBytes(hasher, "source-tree-digest-v2");
    hasher.update(&digest);
}

pub fn hashResolvedSourceTreeUncached(
    allocator: std.mem.Allocator,
    hasher: *std.crypto.hash.sha2.Sha256,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    source_path: []const u8,
    visited: *std.StringHashMap(void),
    files: *std.array_list.Managed(SourceTreeFileStat),
    resolved_source: ?[]const u8,
    project_root_real: []const u8,
    std_root_real: []const u8,
) !void {
    const real_source_path = try sio.cwd().realpathAlloc(allocator, source_path);
    var owned_by_files = false;
    errdefer if (!owned_by_files) allocator.free(real_source_path);
    if (visited.contains(real_source_path)) {
        allocator.free(real_source_path);
        return;
    }
    const visited_key = try allocator.dupe(u8, real_source_path);
    var visited_key_inserted = false;
    errdefer if (!visited_key_inserted) allocator.free(visited_key);
    try visited.put(visited_key, {});
    visited_key_inserted = true;

    const stat = try sio.cwd().statFile(real_source_path);
    try files.append(.{ .path = real_source_path, .mtime = stat.mtime, .size = stat.size });
    owned_by_files = true;

    // Feed the file's layout identity, not its address on this machine:
    // the same closure checked out at a different path must hash the
    // same. `visited` above keeps using the real path — deduplication
    // within one walk is a within-machine concern and stays exact.
    const key_tree_path = try cacheKeyTreePath(allocator, real_source_path, project_root_real, std_root_real);
    defer allocator.free(key_tree_path);
    cacheBytes(hasher, key_tree_path);
    const owned_source = if (resolved_source == null) try loadSource(allocator, source_path) else null;
    defer if (owned_source) |source| allocator.free(source);
    const source = resolved_source orelse owned_source.?;
    cacheBytes(hasher, source);

    var iter = std.mem.splitScalar(u8, source, '\n');
    while (iter.next()) |line| {
        const classified = line_classifier.classifyLine(line);
        if (classified.kind != .import_decl) continue;
        const import_path = classified.parts[0];
        const resolve_ctx = flattener.ResolveContext{ .dependencies = dependencies, .options = .{
            .project_root = project_root,
            .std_root = std_root,
            .offline = offline,
            .plugin_import_roots = plugin_import_roots,
        } };
        var imported = try flattener.readImportSourceFile(allocator, std.fs.path.dirname(source_path) orelse ".", import_path, resolve_ctx);
        defer imported.deinit(allocator);
        try hashResolvedSourceTreeUncached(allocator, hasher, dependencies, plugin_import_roots, project_root, std_root, offline, imported.entry_path, visited, files, imported.source, project_root_real, std_root_real);
    }
}

pub fn hashResolvedSourceTree(
    allocator: std.mem.Allocator,
    hasher: *std.crypto.hash.sha2.Sha256,
    dependencies: []pkg_resolver.Dependency,
    plugin_import_roots: []const []const u8,
    project_root: []const u8,
    std_root: []const u8,
    offline: bool,
    source_path: []const u8,
) !void {
    const real_source_path = try sio.cwd().realpathAlloc(allocator, source_path);
    defer allocator.free(real_source_path);
    const cache_key = try buildSourceTreeHashCacheKey(allocator, dependencies, plugin_import_roots, project_root, std_root, offline, real_source_path);
    defer allocator.free(cache_key);
    if (sourceTreeHashCacheHit(cache_key)) |digest| {
        addSourceTreeDigestToHasher(hasher, digest);
        return;
    }

    // Canonical roots for the layout-relative file identities fed into
    // the digest. Resolution itself keeps using the caller's spellings.
    const project_root_real = sio.cwd().realpathAlloc(allocator, project_root) catch try allocator.dupe(u8, project_root);
    defer allocator.free(project_root_real);
    const std_root_real = sio.cwd().realpathAlloc(allocator, std_root) catch try allocator.dupe(u8, std_root);
    defer allocator.free(std_root_real);

    var tree_hasher = std.crypto.hash.sha2.Sha256.init(.{});
    var visited = std.StringHashMap(void).init(allocator);
    defer {
        var it = visited.iterator();
        while (it.next()) |entry| allocator.free(entry.key_ptr.*);
        visited.deinit();
    }
    var files = std.array_list.Managed(SourceTreeFileStat).init(allocator);
    defer {
        for (files.items) |file| allocator.free(file.path);
        files.deinit();
    }
    try hashResolvedSourceTreeUncached(allocator, &tree_hasher, dependencies, plugin_import_roots, project_root, std_root, offline, source_path, &visited, &files, null, project_root_real, std_root_real);
    var digest: [32]u8 = undefined;
    tree_hasher.final(&digest);
    try storeSourceTreeHashCacheEntry(cache_key, digest, files.items);
    addSourceTreeDigestToHasher(hasher, digest);
}

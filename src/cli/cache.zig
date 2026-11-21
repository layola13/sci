const std = @import("std");
const SabFunctionRange = @import("types.zig").SabFunctionRange;
const flattener = @import("../flattener.zig");
const pathJoinAlloc = @import("compile.zig").pathJoinAlloc;
const ProjectContext = @import("types.zig").ProjectContext;
const BuildCacheKind = @import("types.zig").BuildCacheKind;
const manifest = @import("../pkg/manifest.zig");
const build_options = @import("build_options");
const referee_call = @import("../referee/call.zig");
const sio = @import("sio");
const builtin = @import("builtin");
const WasmTarget = @import("types.zig").WasmTarget;
const ProjectCacheKey = @import("types.zig").ProjectCacheKey;
const common_upstream = @import("../common/upstream_loc.zig");
const DceMode = @import("../emit_options.zig").DceMode;
const ensureParentDir = @import("compile.zig").ensureParentDir;
const referee = @import("../referee.zig");
const writeJsonString = @import("json.zig").writeJsonString;
const stdTreeDigest = @import("source_tree.zig").stdTreeDigest;
const pkg_resolver = @import("../pkg/resolver.zig");
const freeOwnedStringSlice = @import("compile.zig").freeOwnedStringSlice;
const manifestDependencies = @import("compile.zig").manifestDependencies;
const manifestPluginImportRoots = @import("compile.zig").manifestPluginImportRoots;
const hashResolvedSourceTree = @import("source_tree.zig").hashResolvedSourceTree;
const test_meta = @import("../test_meta.zig");

pub const pruneSabFlatToSelectedTests = @import("sab_cache.zig").pruneSabFlatToSelectedTests;

pub const buildSabFunctionRanges = @import("sab_cache.zig").buildSabFunctionRanges;

pub const buildSabFunctionSigIndex = @import("sab_cache.zig").buildSabFunctionSigIndex;

pub const isSabFunctionDecl = @import("sab_cache.zig").isSabFunctionDecl;

pub fn projectLockPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.lock" });
}

pub fn computeProjectBuildKey(
    allocator: std.mem.Allocator,
    project_context: *const ProjectContext,
    project_root: []const u8,
    source_path: []const u8,
    target_name: []const u8,
    source_suffix: []const u8,
    kind: BuildCacheKind,
    debug: bool,
    optimization: driver.Optimization,
    incremental: bool,
    wasm: ?WasmTarget,
    hash_source_tree: bool,
    offline: bool,
    dce: DceMode,
    default_immutable: bool,
    fast_math: bool,
) !ProjectCacheKey {
    const std_root = try stdRootFromEnv(allocator);
    defer allocator.free(std_root);

    // Cache keys are semantic identities (cache-dedup P3): they are built
    // only from what the build means — source contents, compiler version,
    // flags, the std tree's content digest — never from where anything
    // happens to live on disk. The checkout path of the project, the
    // absolute spelling of the source path, and file timestamps of build
    // products must not appear here, or the same meaning keys differently
    // in every tree and sharing is impossible by construction. The domain
    // literal carries a generation marker so entries minted by the old
    // location-based formula can never be mistaken for semantic ones.
    const project_root_real = sio.cwd().realpathAlloc(allocator, project_root) catch try allocator.dupe(u8, project_root);
    defer allocator.free(project_root_real);
    const key_source_path = try cacheKeyNormalizedPath(allocator, project_root_real, source_path);
    defer allocator.free(key_source_path);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    cacheBytes(&hasher, "sa-build-cache-v2");
    cacheBytes(&hasher, cacheCompilerVersion());
    cacheBytes(&hasher, kind.dirName());
    cacheBytes(&hasher, key_source_path);
    cacheBytes(&hasher, target_name);
    cacheBytes(&hasher, source_suffix);
    cacheBuildSemanticFlags(&hasher, debug, optimization, incremental, dce, default_immutable, fast_math);
    // The linked sa_std runtime is identified by the semantic digest of
    // the std source tree it is built from. The previous formula fed the
    // archive's (size, mtime) stat pair: a byte-identical archive rebuild
    // — the normal case when a suite loop rebuilds its tree each round —
    // changed only the mtime and still invalidated every cached entry in
    // every project (measured invalidation radius: 100%). The archive
    // bytes themselves cannot key anything either: they are not
    // reproducible across checkouts. The source tree is the version of
    // the std that the archive means, so its content digest is the key.
    if (try stdTreeDigest(allocator, std_root)) |digest| {
        cacheBytes(&hasher, "std-tree-digest-v1");
        hasher.update(&digest);
    }
    if (wasm) |target| {
        cacheBytes(&hasher, target.triple);
        cacheBool(&hasher, target.no_entry);
        cacheU64(&hasher, target.size_bits);
        // The wasm sa_std archive is stripped at build time (see build.zig:
        // `.strip = true` for wasi). The std source-tree digest alone cannot
        // distinguish a stripped from an unstripped archive built from the
        // same source, so cache entries minted before this change would be
        // revived with the old 14 MB runtime. Bump this generation marker to
        // invalidate them; byte-identical function is preserved.
        cacheBytes(&hasher, "wasm-std-stripped-v1");
    }

    const project_manifest = project_context.manifest;
    if (project_manifest) |*m| {
        // Manifest identity is the project-relative path (its layout role)
        // plus its content; the absolute spelling would reintroduce the
        // checkout location into the key.
        const key_workspace_manifest_path = try cacheKeyNormalizedPath(allocator, project_root_real, project_context.workspace_manifest_path);
        defer allocator.free(key_workspace_manifest_path);
        cacheBytes(&hasher, key_workspace_manifest_path);
        if (projectPathExists(project_context.workspace_manifest_path)) {
            const workspace_manifest_bytes = try readTextFileAlloc(allocator, project_context.workspace_manifest_path);
            defer allocator.free(workspace_manifest_bytes);
            cacheBytes(&hasher, workspace_manifest_bytes);
        }
        if (!std.mem.eql(u8, project_context.member_manifest_path, project_context.workspace_manifest_path)) {
            const key_member_manifest_path = try cacheKeyNormalizedPath(allocator, project_root_real, project_context.member_manifest_path);
            defer allocator.free(key_member_manifest_path);
            cacheBytes(&hasher, key_member_manifest_path);
            if (projectPathExists(project_context.member_manifest_path)) {
                const member_manifest_bytes = try readTextFileAlloc(allocator, project_context.member_manifest_path);
                defer allocator.free(member_manifest_bytes);
                cacheBytes(&hasher, member_manifest_bytes);
            }
        }
        if (project_context.lock_file != null) {
            const lock_path = try projectLockPath(allocator, project_context.root_path);
            defer allocator.free(lock_path);
            try projectFileMaybeHash(&hasher, allocator, lock_path);
        }
        if (project_context.sum_file != null) {
            const sum_path = try projectSumPath(allocator, project_context.root_path);
            defer allocator.free(sum_path);
            try projectFileMaybeHash(&hasher, allocator, sum_path);
        }
        var dependency_slice: []pkg_resolver.Dependency = &.{};
        defer if (dependency_slice.len != 0) allocator.free(dependency_slice);
        var plugin_import_roots: []const []const u8 = &.{};
        defer if (plugin_import_roots.len != 0) freeOwnedStringSlice(allocator, plugin_import_roots);
        if (m.requires.len != 0) {
            dependency_slice = try manifestDependencies(m, allocator);
        }
        if (m.plugin_requires.len != 0) {
            plugin_import_roots = try manifestPluginImportRoots(m, allocator);
        }

        if (hash_source_tree) {
            try hashResolvedSourceTree(allocator, &hasher, dependency_slice, plugin_import_roots, project_context.root_path, std_root, offline, source_path);
        }
    } else {
        try projectFileMaybeHash(&hasher, allocator, project_context.workspace_manifest_path);
        if (!std.mem.eql(u8, project_context.member_manifest_path, project_context.workspace_manifest_path)) {
            try projectFileMaybeHash(&hasher, allocator, project_context.member_manifest_path);
        }
        if (hash_source_tree) {
            try hashResolvedSourceTree(allocator, &hasher, &.{}, &.{}, project_context.root_path, std_root, offline, source_path);
        }
    }

    var out: [32]u8 = undefined;
    hasher.final(&out);
    return .{ .hex = std.fmt.bytesToHex(out, .lower) };
}

pub fn projectSumPath(allocator: std.mem.Allocator, root_path: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ root_path, "sa.sum" });
}

pub fn readSumFile(allocator: std.mem.Allocator, path: []const u8) !?manifest.SumFile {
    const source = sio.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer source.close();
    const bytes = try source.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(bytes);
    return try manifest.parseSum(allocator, bytes);
}

pub fn projectCacheHit(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) !bool {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    const cached_test_metadata = if (kind == .test_cache) try projectCacheTestMetadataPath(allocator, project_root, key) else null;
    defer if (cached_test_metadata) |path| allocator.free(path);
    if (!projectCacheArtifactExistsNonEmpty(cached_artifact) or
        !projectCacheArtifactExistsNonEmpty(cached_output) or
        (if (cached_test_metadata) |path| !projectCacheArtifactExistsNonEmpty(path) else false) or
        !projectCacheManifestValid(allocator, project_root, kind, key, cached_artifact, cached_output))
    {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return false;
    }
    copyFileAlloc(allocator, cached_artifact, artifact_path) catch |err| {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return err;
    };
    copyFileAlloc(allocator, cached_output, out_path) catch |err| {
        projectCacheRemoveKey(allocator, project_root, kind, key);
        return err;
    };
    projectCacheTouchEntry(allocator, project_root, kind, key);
    return true;
}

pub fn projectCacheArtifactPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey, filename: []const u8) ![]u8 {
    const dir = try projectCacheDir(allocator, project_root, kind, key);
    defer allocator.free(dir);
    return try pathJoinAlloc(allocator, &.{ dir, filename });
}

pub fn stdRootFromEnv(allocator: std.mem.Allocator) ![]u8 {
    const repo_std_root = try std.fs.path.join(allocator, &.{ build_options.repo_root, "sa_std" });
    errdefer allocator.free(repo_std_root);

    if (builtin.is_test) return repo_std_root;

    const env_root = sio.getEnvVarOwned(allocator, "SA_STD_DIR") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return repo_std_root,
        else => return err,
    };
    errdefer allocator.free(env_root);

    const required_files = [_][]const u8{
        "io/print.sai",
        "core/sa_core.sa",
        "core/result.sa",
        "core/option.sa",
    };
    for (required_files) |rel| {
        const probe_path = try std.fs.path.join(allocator, &.{ env_root, rel });
        defer allocator.free(probe_path);
        if (sio.cwd().openFile(probe_path, .{})) |file| {
            file.close();
        } else |err| switch (err) {
            error.FileNotFound => {
                allocator.free(env_root);
                return repo_std_root;
            },
            else => return err,
        }
    }

    allocator.free(repo_std_root);
    return env_root;
}

pub const buildSabConstIndex = @import("sab_cache.zig").buildSabConstIndex;

pub const putSabFunctionAlias = @import("sab_cache.zig").putSabFunctionAlias;

pub const markSabReachableByName = @import("sab_cache.zig").markSabReachableByName;

pub const markSabReachableVtableConstByName = @import("sab_cache.zig").markSabReachableVtableConstByName;

pub const markSabReachableVtableConstFromOperand = @import("sab_cache.zig").markSabReachableVtableConstFromOperand;

pub const collectSabSelectedReachability = @import("sab_cache.zig").collectSabSelectedReachability;

pub const sabReferenceName = @import("sab_cache.zig").sabReferenceName;

pub const pruneSabVtableConsts = @import("sab_cache.zig").pruneSabVtableConsts;

pub fn projectCacheDir(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", kind.dirName(), key.slice() });
}

pub fn projectCacheTestMetadataPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "test-metadata.json");
}

pub const freeFlatInstructionMetadata = @import("sab_cache.zig").freeFlatInstructionMetadata;

/// The spelling of a path as fed into a cache key. An absolute path under
/// the project root is reduced to its project-relative form: the layout
/// role of the file is part of the build's meaning, its checkout location
/// is not. Relative paths are already location-free and pass through, as
/// do absolute paths outside the project (no honest relative form exists
/// for them; they stay exact and simply never share across trees).
pub fn cacheKeyNormalizedPath(allocator: std.mem.Allocator, project_root_real: []const u8, path: []const u8) ![]u8 {
    if (std.fs.path.isAbsolute(path) and
        path.len > project_root_real.len and
        std.mem.startsWith(u8, path, project_root_real) and
        path[project_root_real.len] == std.fs.path.sep)
    {
        return allocator.dupe(u8, path[project_root_real.len + 1 ..]);
    }
    return allocator.dupe(u8, path);
}

pub fn projectCacheArtifactExistsNonEmpty(path: []const u8) bool {
    const stat = sio.cwd().statFile(path) catch return false;
    return stat.kind == .file and stat.size != 0;
}

pub const freeFlatLocEntry = @import("sab_cache.zig").freeFlatLocEntry;

pub const cacheBytes = @import("cache_hash.zig").cacheBytes;

pub fn projectCacheManifestValid(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) bool {
    const manifest_path = projectCacheManifestPath(allocator, project_root, kind, key) catch return false;
    defer allocator.free(manifest_path);
    const manifest_bytes = readTextFileAlloc(allocator, manifest_path) catch return false;
    defer allocator.free(manifest_bytes);
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, manifest_bytes, .{}) catch return false;
    defer parsed.deinit();
    if (!jsonIntEquals(jsonGetObject(parsed.value, "version") catch return false, 1)) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "kind") catch return false, kind.dirName())) return false;
    if (!jsonStringEquals(jsonGetObject(parsed.value, "key") catch return false, key.slice())) return false;
    if (!(projectCacheArtifactMatchesManifest(allocator, jsonGetObject(parsed.value, "artifact") catch return false, artifact_path) catch return false)) return false;
    if (!(projectCacheArtifactMatchesManifest(allocator, jsonGetObject(parsed.value, "output") catch return false, out_path) catch return false)) return false;
    return true;
}

pub fn projectCacheManifestPath(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) ![]u8 {
    return try projectCacheArtifactPath(allocator, project_root, kind, key, "manifest.json");
}

pub const jsonGetObject = @import("json.zig").jsonGetObject;

pub const jsonStringEquals = @import("json.zig").jsonStringEquals;

pub const jsonIntEquals = @import("json.zig").jsonIntEquals;

pub fn projectCacheArtifactMatchesManifest(allocator: std.mem.Allocator, artifact_value: std.json.Value, path: []const u8) !bool {
    const stat = sio.cwd().statFile(path) catch return false;
    if (stat.kind != .file or stat.size == 0) return false;
    if (!jsonIntEquals(try jsonGetObject(artifact_value, "size"), stat.size)) return false;
    const hash_hex = try hashFileHex(allocator, path);
    return jsonStringEquals(try jsonGetObject(artifact_value, "sha256"), hash_hex[0..]);
}

pub fn readTextFileAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try sio.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

pub fn projectCacheStore(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
) !void {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, kind, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, kind, key, "output.bin");
    defer allocator.free(cached_output);
    try copyFileAlloc(allocator, artifact_path, cached_artifact);
    try copyFileAlloc(allocator, out_path, cached_output);
    try projectCacheWriteManifest(allocator, project_root, kind, key, cached_artifact, cached_output);
    enforceProjectCacheBudget(allocator, project_root, kind, key);
}

pub fn copyFileAlloc(allocator: std.mem.Allocator, src_path: []const u8, dst_path: []const u8) !void {
    _ = allocator;
    try ensureParentDir(dst_path);
    try sio.cwd().copyFile(src_path, sio.cwd(), dst_path, .{});
}

pub fn projectCacheWriteManifest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    kind: BuildCacheKind,
    key: ProjectCacheKey,
    cached_artifact: []const u8,
    cached_output: []const u8,
) !void {
    const manifest_path = try projectCacheManifestPath(allocator, project_root, kind, key);
    defer allocator.free(manifest_path);
    try ensureParentDir(manifest_path);
    var file = try sio.cwd().createFile(manifest_path, .{ .truncate = true });
    defer file.close();
    var fbuf: [8192]u8 = undefined;
    var fw = file.writer(&fbuf);
    const writer = &fw.interface;
    try writer.writeAll("{\"version\":1,\"kind\":");
    try writeJsonString(writer, kind.dirName());
    try writer.writeAll(",\"key\":");
    try writeJsonString(writer, key.slice());
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "artifact", cached_artifact);
    try writer.writeByte(',');
    try writeCacheArtifactManifestEntry(writer, allocator, "output", cached_output);
    try writer.writeAll("}\n");
    try fw.interface.flush();
}

/// After each store, if the project's .sa_cache exceeds the budget,
/// delete least-recently-used entries until it fits. An entry that keeps
/// being hit keeps a fresh last-used stamp and survives; entries whose
/// meaning fell out of use age out first — reachability as observed by
/// the cache itself. The just-stored entry is never a victim. Every
/// failure is silent: eviction is housekeeping, never a build error.
pub fn enforceProjectCacheBudget(allocator: std.mem.Allocator, project_root: []const u8, protected_kind: BuildCacheKind, protected_key: ProjectCacheKey) void {
    const budget = projectCacheBudgetBytes() orelse return;
    const protected_dir = projectCacheDir(allocator, project_root, protected_kind, protected_key) catch return;
    defer allocator.free(protected_dir);
    const cache_root = cacheRootPath(allocator, project_root) catch return;
    defer allocator.free(cache_root);

    var candidates = std.array_list.Managed(CacheEvictionCandidate).init(allocator);
    defer {
        for (candidates.items) |cand| allocator.free(cand.dir_path);
        candidates.deinit();
    }
    var total: u64 = 0;
    for ([_]BuildCacheKind{ .build_exe, .build_obj, .build_wasm, .build_obj_incremental, .test_cache }) |kind| {
        const kind_path = std.fs.path.join(allocator, &.{ cache_root, kind.dirName() }) catch return;
        defer allocator.free(kind_path);
        var kind_dir = sio.cwd().openDir(kind_path, .{ .iterate = true }) catch continue;
        defer kind_dir.close();
        var iter = kind_dir.iterate();
        while (iter.next() catch null) |entry| {
            if (entry.kind != .directory or !isHexCacheKey(entry.name)) continue;
            const dir_path = std.fs.path.join(allocator, &.{ kind_path, entry.name }) catch return;
            var entry_dir = sio.cwd().openDir(dir_path, .{ .iterate = true }) catch {
                allocator.free(dir_path);
                continue;
            };
            const size = cacheDirTreeSize(entry_dir, 0);
            entry_dir.close();
            const last_used_ns = cacheEntryLastUsedNs(allocator, dir_path);
            candidates.append(.{ .dir_path = dir_path, .size = size, .last_used_ns = last_used_ns }) catch {
                allocator.free(dir_path);
                return;
            };
            total += size;
        }
    }
    if (total <= budget) return;
    std.mem.sort(CacheEvictionCandidate, candidates.items, {}, cacheEvictionCandidateLessThan);
    for (candidates.items) |cand| {
        if (total <= budget) break;
        if (std.mem.eql(u8, cand.dir_path, protected_dir)) continue;
        sio.cwd().deleteTree(cand.dir_path) catch continue;
        total -|= cand.size;
    }
}

pub const sabPruneDebugEnabled = @import("sab_cache.zig").sabPruneDebugEnabled;

pub const cacheCompilerVersion = @import("cache_hash.zig").cacheCompilerVersion;

pub fn projectCacheRemoveKey(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) void {
    const dir = projectCacheDir(allocator, project_root, kind, key) catch return;
    defer allocator.free(dir);
    sio.cwd().deleteTree(dir) catch |err| {
        // Build cache repair is opportunistic here; callers fall back to recompilation on unusable entries.
        _ = @errorName(err);
    };
}

pub const hashFileHex = @import("cache_hash.zig").hashFileHex;

pub const hashOpenFileHex = @import("cache_hash.zig").hashOpenFileHex;

pub const cacheFunctionSig = @import("cache_hash.zig").cacheFunctionSig;

pub const cacheU64 = @import("cache_hash.zig").cacheU64;

pub const cacheBool = @import("cache_hash.zig").cacheBool;

pub const computeFunctionObjectKey = @import("cache_hash.zig").computeFunctionObjectKey;

pub const cacheBuildSemanticFlags = @import("cache_hash.zig").cacheBuildSemanticFlags;

/// Refresh an entry's last-used marker after a hit. Eviction ages an
/// entry by the newest of (entry directory, manifest, this marker), so
/// a hit moves the entry's clock without rewriting payload files.
pub fn projectCacheTouchEntry(allocator: std.mem.Allocator, project_root: []const u8, kind: BuildCacheKind, key: ProjectCacheKey) void {
    const marker_path = projectCacheArtifactPath(allocator, project_root, kind, key, "last-used") catch return;
    defer allocator.free(marker_path);
    var file = sio.cwd().createFile(marker_path, .{ .truncate = true }) catch return;
    defer file.close();
    file.writeAll("1") catch {};
}

pub const projectCacheBudgetBytes = @import("cache_hash.zig").projectCacheBudgetBytes;

pub const sourceHashHex = @import("cache_hash.zig").sourceHashHex;

pub fn cacheRootPath(allocator: std.mem.Allocator, project_root: []const u8) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache" });
}

pub fn projectFunctionCachePath(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    function_key: []const u8,
) ![]u8 {
    const filename = try std.fmt.allocPrint(allocator, "{s}.o", .{function_key});
    defer allocator.free(filename);
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", BuildCacheKind.build_obj_incremental.dirName(), key.slice(), "functions", filename });
}

pub fn projectPathExists(path: []const u8) bool {
    sio.cwd().access(path, .{}) catch return false;
    return true;
}

pub fn writeCacheArtifactManifestEntry(writer: anytype, allocator: std.mem.Allocator, name: []const u8, path: []const u8) !void {
    const stat = try sio.cwd().statFile(path);
    const hash_hex = try hashFileHex(allocator, path);
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":{\"size\":");
    try writer.print("{d}", .{stat.size});
    try writer.writeAll(",\"sha256\":");
    try writeJsonString(writer, hash_hex[0..]);
    try writer.writeByte('}');
}

pub const CacheEvictionCandidate = struct {
    dir_path: []u8,
    size: u64,
    last_used_ns: i128,
};

pub fn cacheEvictionCandidateLessThan(_: void, a: CacheEvictionCandidate, b: CacheEvictionCandidate) bool {
    return a.last_used_ns < b.last_used_ns;
}

pub fn projectFileMaybeHash(hasher: *std.crypto.hash.sha2.Sha256, allocator: std.mem.Allocator, path: []const u8) !void {
    if (!projectPathExists(path)) return;
    const bytes = try readTextFileAlloc(allocator, path);
    defer allocator.free(bytes);
    cacheBytes(hasher, bytes);
}

pub fn isHexCacheKey(name: []const u8) bool {
    if (name.len != 64) return false;
    for (name) |c| {
        switch (c) {
            '0'...'9', 'a'...'f' => {},
            else => return false,
        }
    }
    return true;
}

pub const cacheDirTreeSize = @import("cache_hash.zig").cacheDirTreeSize;

pub fn projectFunctionCacheManifestPath(allocator: std.mem.Allocator, project_root: []const u8, key: ProjectCacheKey) ![]u8 {
    return try pathJoinAlloc(allocator, &.{ project_root, ".sa_cache", BuildCacheKind.build_obj_incremental.dirName(), key.slice(), "manifest.json" });
}

pub const cacheEntryLastUsedNs = @import("cache_hash.zig").cacheEntryLastUsedNs;

pub const jsonBool = @import("json.zig").jsonBool;

pub const jsonU32 = @import("json.zig").jsonU32;

pub const jsonStringDup = @import("json.zig").jsonStringDup;

pub const jsonOptionalStringDup = @import("json.zig").jsonOptionalStringDup;

pub fn projectCacheReadTestMetadata(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
) !test_meta.TestList {
    const metadata_path = try projectCacheTestMetadataPath(allocator, project_root, key);
    defer allocator.free(metadata_path);
    const metadata_bytes = try readTextFileAlloc(allocator, metadata_path);
    defer allocator.free(metadata_bytes);
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, metadata_bytes, .{});
    defer parsed.deinit();
    if (!jsonIntEquals(try jsonGetObject(parsed.value, "version"), 1)) return error.InvalidCacheManifest;
    const tests_value = try jsonGetObject(parsed.value, "tests");
    const tests_array = switch (tests_value) {
        .array => |array| array.items,
        else => return error.InvalidCacheManifest,
    };

    var tests = std.array_list.Managed(test_meta.TestDescAndFn).init(allocator);
    errdefer {
        for (tests.items) |*test_case| test_case.deinit(allocator);
        tests.deinit();
    }
    for (tests_array) |item| {
        switch (item) {
            .object => {},
            else => return error.InvalidCacheManifest,
        }
        const name = try jsonStringDup(allocator, try jsonGetObject(item, "name"));
        errdefer allocator.free(name);
        const selector = try jsonStringDup(allocator, try jsonGetObject(item, "selector"));
        errdefer allocator.free(selector);
        const source_file = try jsonOptionalStringDup(allocator, try jsonGetObject(item, "source_file"));
        errdefer if (source_file) |file| allocator.free(file);
        try tests.append(.{
            .desc = .{
                .id = try jsonU32(try jsonGetObject(item, "id")),
                .name = name,
                .source_file = source_file,
                .line = try jsonU32(try jsonGetObject(item, "line")),
                .col = try jsonU32(try jsonGetObject(item, "col")),
                .ignored = try jsonBool(try jsonGetObject(item, "ignored")),
                .should_panic = try jsonBool(try jsonGetObject(item, "should_panic")),
            },
            .testfn = .{ .selector_name = selector },
        });
    }
    return .{ .tests = try tests.toOwnedSlice(), .order = .Unsorted };
}

pub fn projectCacheStoreTest(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    artifact_path: []const u8,
    out_path: []const u8,
    test_list: test_meta.TestList,
) !void {
    const cached_artifact = try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "artifact.sa.bc");
    defer allocator.free(cached_artifact);
    const cached_output = try projectCacheArtifactPath(allocator, project_root, .test_cache, key, "output.bin");
    defer allocator.free(cached_output);
    try copyFileAlloc(allocator, artifact_path, cached_artifact);
    try copyFileAlloc(allocator, out_path, cached_output);
    try projectCacheWriteTestMetadata(allocator, project_root, key, test_list);
    try projectCacheWriteManifest(allocator, project_root, .test_cache, key, cached_artifact, cached_output);
    enforceProjectCacheBudget(allocator, project_root, .test_cache, key);
}

pub fn projectCacheWriteTestMetadata(
    allocator: std.mem.Allocator,
    project_root: []const u8,
    key: ProjectCacheKey,
    test_list: test_meta.TestList,
) !void {
    const metadata_path = try projectCacheTestMetadataPath(allocator, project_root, key);
    defer allocator.free(metadata_path);
    try ensureParentDir(metadata_path);
    var file = try sio.cwd().createFile(metadata_path, .{ .truncate = true });
    defer file.close();
    var fbuf: [8192]u8 = undefined;
    var fw = file.writer(&fbuf);
    const writer = &fw.interface;
    try writer.writeAll("{\"version\":1,\"tests\":[");
    for (test_list.tests, 0..) |test_case, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll("{\"id\":");
        try writer.print("{d}", .{test_case.desc.id});
        try writer.writeAll(",\"name\":");
        try writeJsonString(writer, test_case.desc.name);
        try writer.writeAll(",\"selector\":");
        try writeJsonString(writer, test_case.testfn.selector_name);
        try writer.writeAll(",\"source_file\":");
        try writeOptionalJsonString(writer, test_case.desc.source_file);
        try writer.writeAll(",\"line\":");
        try writer.print("{d}", .{test_case.desc.line});
        try writer.writeAll(",\"col\":");
        try writer.print("{d}", .{test_case.desc.col});
        try writer.writeAll(",\"ignored\":");
        try writer.writeAll(if (test_case.desc.ignored) "true" else "false");
        try writer.writeAll(",\"should_panic\":");
        try writer.writeAll(if (test_case.desc.should_panic) "true" else "false");
        try writer.writeByte('}');
    }
    try writer.writeAll("]}\n");
    try fw.interface.flush();
}

pub fn writeOptionalJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

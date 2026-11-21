const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const pkg_resolver = @import("../pkg/resolver.zig");
const decl_materialize = @import("../decl_materialize.zig");
const ClassifiedLine = @import("line_classifier.zig").ClassifiedLine;
const LineKind = @import("line_classifier.zig").LineKind;
const declTargetFor = @import("injectimportedfile.zig").declTargetFor;
const deinitOwnedSourceLines = @import("appendexpandedimportcachehit.zig").deinitOwnedSourceLines;


pub const max_expanded_instructions: usize = 10_000_000;
const max_expanded_macro_lines: usize = 10_000_000;
const max_macro_expansion_events: u64 = 10_000_000;
pub const max_macro_recursion_depth: u16 = 256;

pub fn bumpMacroExpansionCounter(counter: *u64) !u64 {
    if (counter.* >= max_macro_expansion_events) return error.MacroExpansionBudget;
    counter.* += 1;
    return counter.*;
}

pub fn ensureRepExpansionBudget(count: usize, body_line_count: usize) !void {
    if (body_line_count == 0) return;
    if (count > max_expanded_macro_lines / body_line_count) return error.MacroExpansionBudget;
}

pub const ResolveContext = struct {
    dependencies: []const pkg_resolver.Dependency = &.{},
    options: pkg_resolver.ResolveOptions = .{},
    package_identity: ?[]const u8 = null,
    /// SAB-H1-ENROL (consult-forkh §3 conditions 3 and 4): a consumer
    /// that knows the program's compilation target (the SAB std
    /// loader, via the plugin front end) supplies it here so std
    /// sources are materialized for that target. null keeps the
    /// historic behaviour — materialize for the host target — which
    /// is the only reading available to consumers without a program
    /// target (judgment A).
    decl_target: ?decl_materialize.DeclTarget = null,
};

pub const LayoutVersion = struct {
    path: []u8,
    version: u64,

    pub fn deinit(self: *LayoutVersion, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const MacroDef = struct {
    params: []const []const u8,
    variadic_param: ?[]const u8 = null,
    body_start: usize,
    body_end: usize,
    owned_body_lines: []SourceLine = &.{},
    owned_name: ?[]u8 = null,
    owned_params: [][]const u8 = &.{},
    owned_variadic_param: ?[]u8 = null,

    pub fn deinit(self: *MacroDef, allocator: std.mem.Allocator) void {
        if (self.owned_body_lines.len != 0) deinitOwnedSourceLines(allocator, self.owned_body_lines);
        if (self.owned_name) |name| allocator.free(name);
        if (self.owned_params.len != 0) {
            for (self.owned_params) |param| allocator.free(param);
            allocator.free(self.owned_params);
        } else {
            allocator.free(self.params);
        }
        if (self.owned_variadic_param) |param| allocator.free(param);
        self.* = undefined;
    }
};

pub const CachedMacroLine = struct {
    line_no: u32,
    text: []u8,
    package_identity: ?[]u8 = null,
    package_source_sha256: ?[32]u8 = null,

    pub fn deinit(self: *CachedMacroLine, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        if (self.package_identity) |identity| allocator.free(identity);
        self.* = undefined;
    }
};

pub const CachedMacroDef = struct {
    name: []u8,
    params: [][]const u8,
    variadic_param: ?[]u8 = null,
    body_lines: []CachedMacroLine,

    pub fn deinit(self: *CachedMacroDef, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.params) |param| allocator.free(param);
        allocator.free(self.params);
        if (self.variadic_param) |param| allocator.free(param);
        for (self.body_lines) |*line| line.deinit(allocator);
        allocator.free(self.body_lines);
        self.* = undefined;
    }
};

pub const Replacement = struct {
    needle: []const u8,
    replacement: []const u8,
};

pub const SourceLine = struct {
    line_no: u32,
    text: []const u8,
    classified: ClassifiedLine,
    package_identity: ?[]const u8 = null,
    package_source_sha256: ?[32]u8 = null,
    /// Path of the file this line was read from before import expansion
    /// inlined it into the expanded source, and its 1-based line number in
    /// that file. Zero/null when unknown (e.g. lines replayed from the
    /// expanded-import cache); diagnostics must fall back to `line_no`
    /// (the expanded-source coordinate) in that case.
    origin_path: ?[]const u8 = null,
    origin_line_no: u32 = 0,
};

pub const ErrorContext = struct {
    source_line: ?u32 = null,
    /// Origin file of the line recorded in `source_line`, when it is known
    /// to differ from a plain expanded-source coordinate. Stored inline so
    /// the context outlives the expansion buffers it was borrowed from.
    source_path_buf: [256]u8 = std.mem.zeroes([256]u8),
    source_path_len: usize = 0,
    /// Short machine-readable detail for the recorded error (currently the
    /// offending macro name for error.UndefinedMacro).
    detail_buf: [128]u8 = std.mem.zeroes([128]u8),
    detail_len: usize = 0,

    pub fn sourcePath(self: *const ErrorContext) ?[]const u8 {
        if (self.source_path_len == 0) return null;
        return self.source_path_buf[0..self.source_path_len];
    }

    pub fn detail(self: *const ErrorContext) ?[]const u8 {
        if (self.detail_len == 0) return null;
        return self.detail_buf[0..self.detail_len];
    }

    pub fn reset(self: *ErrorContext) void {
        self.source_line = null;
        self.source_path_len = 0;
        self.detail_len = 0;
    }
};

pub const ErrorReport = struct {
    line: ?u32,
    path: ?[]const u8,
    detail: ?[]const u8,
};

/// Borrowed view of the recorded error position: `line` is a line number in
/// `path` (the origin file) when a path was recorded, and an
/// expanded-source coordinate otherwise.
pub fn errorReport(error_ctx: *const ErrorContext) ErrorReport {
    return .{
        .line = error_ctx.source_line,
        .path = error_ctx.sourcePath(),
        .detail = error_ctx.detail(),
    };
}

pub const IncludeCycle = error{
    IncludeCycle,
};

fn recordErrorSourceLine(error_ctx: ?*ErrorContext, line_no: u32) void {
    if (error_ctx) |ctx| {
        ctx.source_line = line_no;
    }
}

/// Record an error position in origin-file coordinates: `origin_line` is
/// the 1-based line number inside the origin file. A null `origin_path`
/// means the root file (whose path spelling is owned by the caller, so it
/// is never recorded here); it clears any previously recorded foreign path.
pub fn recordErrorOrigin(error_ctx: ?*ErrorContext, origin_path: ?[]const u8, origin_line: u32) void {
    if (error_ctx) |ctx| {
        ctx.source_line = origin_line;
        if (origin_path) |path| {
            const current = ctx.sourcePath();
            if (current == null or !std.mem.eql(u8, current.?, path)) {
                const n = @min(path.len, ctx.source_path_buf.len);
                @memcpy(ctx.source_path_buf[0..n], path[0..n]);
                ctx.source_path_len = n;
            }
        } else {
            ctx.source_path_len = 0;
        }
    }
}

/// Record the error position for a source line, preferring its origin
/// coordinates when import expansion preserved them.
pub fn recordErrorLine(error_ctx: ?*ErrorContext, line: SourceLine, fallback_line: u32) void {
    if (line.origin_line_no != 0) {
        recordErrorOrigin(error_ctx, line.origin_path, line.origin_line_no);
    } else {
        recordErrorSourceLine(error_ctx, fallback_line);
    }
}

pub fn setErrorDetail(error_ctx: ?*ErrorContext, detail_text: []const u8) void {
    if (error_ctx) |ctx| {
        const n = @min(detail_text.len, ctx.detail_buf.len);
        @memcpy(ctx.detail_buf[0..n], detail_text[0..n]);
        ctx.detail_len = n;
    }
}

pub fn takeErrorSourceLine(error_ctx: *ErrorContext) ?u32 {
    const line_no = error_ctx.source_line;
    error_ctx.source_line = null;
    return line_no;
}

pub fn appendExpandedLine(
    out: *std.array_list.Managed(u8),
    line_package_identities: *std.array_list.Managed(?[]const u8),
    line_package_hashes: *std.array_list.Managed(?[32]u8),
    line_origin_paths: *std.array_list.Managed(?[]const u8),
    line_origin_lines: *std.array_list.Managed(u32),
    text: []const u8,
    package_identity: ?[]const u8,
    package_hash: ?[32]u8,
    origin_path: ?[]const u8,
    origin_line_no: u32,
) !void {
    try out.appendSlice(text);
    try out.append('\n');
    try line_package_identities.append(package_identity);
    try line_package_hashes.append(package_hash);
    try line_origin_paths.append(origin_path);
    try line_origin_lines.append(origin_line_no);
}

pub fn isFunctionLikeLineKind(kind: LineKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => true,
        else => false,
    };
}

pub fn consumesPendingLoc(kind: LineKind) bool {
    return switch (kind) {
        .const_decl, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl, .instruction, .native => true,
        else => false,
    };
}

pub fn appendGeneratedLocLine(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    line_package_identities: *std.array_list.Managed(?[]const u8),
    line_package_hashes: *std.array_list.Managed(?[32]u8),
    line_origin_paths: *std.array_list.Managed(?[]const u8),
    line_origin_lines: *std.array_list.Managed(u32),
    source_path: []const u8,
    line_no: u32,
    package_identity: ?[]const u8,
    package_hash: ?[32]u8,
    origin_path: ?[]const u8,
) !void {
    const loc_line = try std.fmt.allocPrint(allocator, "#loc \"{s}\":{d}:1", .{ source_path, line_no });
    defer allocator.free(loc_line);
    try appendExpandedLine(out, line_package_identities, line_package_hashes, line_origin_paths, line_origin_lines, loc_line, package_identity, package_hash, origin_path, line_no);
}

pub const ImportExpansion = struct {
    source: []u8,
    active_paths: std.StringHashMap(void),
    seen_paths: std.StringHashMap(void),
    seen_package_identities: std.StringHashMap(void),
    line_package_identities: std.array_list.Managed(?[]const u8),
    line_package_hashes: std.array_list.Managed(?[32]u8),
    /// Per-expanded-line origin (file path borrowed from `owned_paths`,
    /// and 1-based line number inside that file). Entries may be null/0
    /// for lines replayed from the expanded-import cache, mirroring the
    /// lossy per-line package metadata on cache hits.
    line_origin_paths: std.array_list.Managed(?[]const u8),
    line_origin_lines: std.array_list.Managed(u32),
    owned_paths: std.array_list.Managed([]u8),
    layout_versions: std.array_list.Managed(LayoutVersion),

    pub fn deinit(self: *ImportExpansion, allocator: std.mem.Allocator) void {
        self.line_package_identities.deinit();
        self.line_package_hashes.deinit();
        self.line_origin_paths.deinit();
        self.line_origin_lines.deinit();
        for (self.owned_paths.items) |path| {
            allocator.free(path);
        }
        self.owned_paths.deinit();
        var pkg_it = self.seen_package_identities.iterator();
        while (pkg_it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.seen_package_identities.deinit();
        for (self.layout_versions.items) |*layout_version| layout_version.deinit(allocator);
        self.layout_versions.deinit();
        self.active_paths.deinit();
        self.seen_paths.deinit();
        allocator.free(self.source);
        self.* = undefined;
    }
};

pub const ImportSourceCacheEntry = struct {
    entry_path: []u8,
    root_dir: ?[]u8,
    package_identity: ?[]u8,
    source_sha256: ?[32]u8,
    source: []u8,
    mtime: i128,
    size: u64,
    is_global: bool,
    last_used_tick: u64,
};

pub const ExpandedImportCacheFileStat = struct {
    path: []u8,
    mtime: i128,
    size: u64,
};

pub const ExpandedImportCacheEntry = struct {
    source: []u8,
    line_count: usize,
    files: []ExpandedImportCacheFileStat,
    layout_versions: []LayoutVersion,
    last_used_tick: u64,
};

pub var import_source_cache_mutex: std.atomic.Mutex = .unlocked;
pub var import_source_cache: ?std.StringHashMap(ImportSourceCacheEntry) = null;
pub var import_source_cache_tick: u64 = 0;
pub var test_import_source_cache_max_entries: ?usize = null;

pub var expanded_import_cache_mutex: std.atomic.Mutex = .unlocked;
pub var expanded_import_cache: ?std.StringHashMap(ExpandedImportCacheEntry) = null;
pub var expanded_import_cache_tick: u64 = 0;
pub var test_expanded_import_cache_max_entries: ?usize = null;
pub var test_expanded_import_cache_hits: usize = 0;
pub var test_expanded_import_cache_stores: usize = 0;

pub fn importSourceCacheMap() *std.StringHashMap(ImportSourceCacheEntry) {
    if (import_source_cache == null) {
        import_source_cache = std.StringHashMap(ImportSourceCacheEntry).init(std.heap.page_allocator);
    }
    return &import_source_cache.?;
}

pub fn expandedImportCacheMap() *std.StringHashMap(ExpandedImportCacheEntry) {
    if (expanded_import_cache == null) {
        expanded_import_cache = std.StringHashMap(ExpandedImportCacheEntry).init(std.heap.page_allocator);
    }
    return &expanded_import_cache.?;
}

pub fn traceImportsEnabled() bool {
    const value = sio.getEnvVarOwned(std.heap.page_allocator, "SAASM_TRACE_IMPORTS") catch return false;
    defer std.heap.page_allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "false") and !std.mem.eql(u8, value, "False");
}

pub fn importSourceCacheMaxEntries() ?usize {
    if (builtin.is_test) {
        if (test_import_source_cache_max_entries) |value| return value;
    }
    const value = sio.getEnvVarOwned(std.heap.page_allocator, "SA_IMPORT_CACHE_MAX_ENTRIES") catch return null;
    defer std.heap.page_allocator.free(value);
    const parsed = std.fmt.parseUnsigned(usize, value, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

pub fn expandedImportCacheMaxEntries() ?usize {
    if (builtin.is_test) {
        if (test_expanded_import_cache_max_entries) |value| return value;
    }
    const value = sio.getEnvVarOwned(std.heap.page_allocator, "SA_EXPANDED_IMPORT_CACHE_MAX_ENTRIES") catch return null;
    defer std.heap.page_allocator.free(value);
    const parsed = std.fmt.parseUnsigned(usize, value, 10) catch return null;
    return if (parsed == 0) null else parsed;
}

pub fn nextImportSourceCacheTickLocked() u64 {
    import_source_cache_tick +%= 1;
    return import_source_cache_tick;
}

pub fn nextExpandedImportCacheTickLocked() u64 {
    expanded_import_cache_tick +%= 1;
    return expanded_import_cache_tick;
}

fn appendCacheBytes(out: *std.array_list.Managed(u8), bytes: []const u8) !void {
    try out.appendSlice(bytes);
    try out.append(0);
}

pub fn buildImportSourceCacheKey(
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    import_path: []const u8,
    resolve_ctx: ?ResolveContext,
) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    try appendCacheBytes(&out, base_dir);
    try appendCacheBytes(&out, import_path);
    if (resolve_ctx) |ctx| {
        try appendCacheBytes(&out, if (ctx.options.project_root) |path| path else "");
        try appendCacheBytes(&out, if (ctx.options.home_dir) |path| path else "");
        try appendCacheBytes(&out, if (ctx.options.std_root) |path| path else "");
        var flag_buf: [64]u8 = undefined;
        const flag_text = try std.fmt.bufPrint(&flag_buf, "{}\x00{}\x00", .{ ctx.options.offline, ctx.options.max_local_file_bytes });
        try out.appendSlice(flag_text);
        for (ctx.options.entry_candidates) |candidate| try appendCacheBytes(&out, candidate);
        try out.append(0);
        for (ctx.options.plugin_import_roots) |root| try appendCacheBytes(&out, root);
        try out.append(0);
        for (ctx.options.stable_import_roots) |root| try appendCacheBytes(&out, root);
        try out.append(0);
        for (ctx.dependencies) |dep| {
            try appendCacheBytes(&out, dep.url);
            try appendCacheBytes(&out, dep.ref);
        }
    } else {
        try appendCacheBytes(&out, "default");
    }
    // SAB-H1-ENROL (condition 5): the import-source and expanded-import
    // caches must not serve one target's materialization to a load for
    // another target, so the effective materialization target is part
    // of the key (entries remain stat-validated on top of the key).
    try appendCacheBytes(&out, declTargetFor(resolve_ctx).targetName());
    return try out.toOwnedSlice();
}

fn pathWithinRoot(path: []const u8, root: []const u8) bool {
    if (std.mem.eql(u8, path, root)) return true;
    return std.mem.startsWith(u8, path, root) and path.len > root.len and std.fs.path.isSep(path[root.len]);
}

fn isStableImportCacheCandidate(allocator: std.mem.Allocator, base_dir: []const u8, import_path: []const u8, roots: []const []const u8) !bool {
    if (roots.len == 0) return false;
    if (std.mem.startsWith(u8, import_path, "sa:") or std.mem.startsWith(u8, import_path, "pkg:")) return false;

    const joined = if (std.fs.path.isAbsolute(import_path))
        try allocator.dupe(u8, import_path)
    else
        try std.fs.path.join(allocator, &.{ base_dir, import_path });
    defer allocator.free(joined);
    const real_import = sio.cwd().realpathAlloc(allocator, joined) catch return false;
    defer allocator.free(real_import);

    for (roots) |root| {
        const real_root = sio.cwd().realpathAlloc(allocator, root) catch continue;
        defer allocator.free(real_root);
        if (pathWithinRoot(real_import, real_root)) return true;
    }
    return false;
}

pub fn isImportCacheCandidate(allocator: std.mem.Allocator, base_dir: []const u8, import_path: []const u8, resolve_ctx: ?ResolveContext) !bool {
    if (std.mem.startsWith(u8, import_path, "sa_std/")) return true;
    if (std.mem.startsWith(u8, import_path, "../") or std.mem.startsWith(u8, import_path, "./")) {
        if (std.mem.eql(u8, base_dir, "sa_std") or std.mem.startsWith(u8, base_dir, "sa_std/")) return true;
        if (std.mem.indexOf(u8, base_dir, "/sa_std/") != null) return true;
        if (std.mem.endsWith(u8, base_dir, "/sa_std")) return true;
    }
    if (resolve_ctx) |ctx| {
        if (ctx.options.std_root) |std_root| {
            if (std.mem.eql(u8, base_dir, std_root)) return true;
            if (std.mem.startsWith(u8, base_dir, std_root) and base_dir.len > std_root.len and std.fs.path.isSep(base_dir[std_root.len])) return true;
        }
        if (try isStableImportCacheCandidate(allocator, base_dir, import_path, ctx.options.stable_import_roots)) return true;
    }
    return false;
}

pub fn cloneCachedImport(allocator: std.mem.Allocator, cached: ImportSourceCacheEntry, borrow_source: bool) !pkg_resolver.ResolvedImport {
    const entry_path = try allocator.dupe(u8, cached.entry_path);
    errdefer allocator.free(entry_path);
    const root_dir = if (cached.root_dir) |dir| try allocator.dupe(u8, dir) else null;
    errdefer if (root_dir) |dir| allocator.free(dir);
    const package_identity = if (cached.package_identity) |identity| try allocator.dupe(u8, identity) else null;
    errdefer if (package_identity) |identity| allocator.free(identity);
    // Materialized sources (@target blocks) are process-local reductions,
    // not file bytes: a clone must own its copy rather than borrow the
    // cached slice, whose lifetime is tied to the cache entry.
    const owned_source = if (borrow_source and !decl_materialize.containsTargetBlocks(cached.source)) null else try allocator.dupe(u8, cached.source);
    errdefer if (owned_source) |source| allocator.free(source);

    return .{
        .entry_path = entry_path,
        .source = owned_source orelse cached.source,
        .owned_source = owned_source,
        .root_dir = root_dir,
        .package_identity = package_identity,
        .source_sha256 = cached.source_sha256,
        .is_global = cached.is_global,
    };
}

pub fn freeImportSourceCacheEntry(entry: ImportSourceCacheEntry, comptime free_source: bool) void {
    const cache_allocator = std.heap.page_allocator;
    cache_allocator.free(entry.entry_path);
    if (entry.root_dir) |root_dir| cache_allocator.free(root_dir);
    if (entry.package_identity) |package_identity| cache_allocator.free(package_identity);
    if (free_source) cache_allocator.free(entry.source);
}

pub fn freeExpandedImportCacheEntry(entry: ExpandedImportCacheEntry) void {
    const cache_allocator = std.heap.page_allocator;
    cache_allocator.free(entry.source);
    for (entry.files) |file| cache_allocator.free(file.path);
    cache_allocator.free(entry.files);
    for (entry.layout_versions) |*layout_version| layout_version.deinit(cache_allocator);
    cache_allocator.free(entry.layout_versions);
}

pub fn statImportSourceCacheEntry(path: []const u8) !struct { mtime: i128, size: u64 } {
    const stat = try sio.cwd().statFile(path);
    return .{ .mtime = @as(i128, stat.mtime.toNanoseconds()), .size = stat.size };
}

pub fn cachedImportStillValid(entry: ImportSourceCacheEntry) bool {
    const stat = statImportSourceCacheEntry(entry.entry_path) catch return false;
    return stat.mtime == entry.mtime and stat.size == entry.size;
}

pub fn cachedExpandedImportStillValid(entry: ExpandedImportCacheEntry) bool {
    for (entry.files) |file| {
        const stat = statImportSourceCacheEntry(file.path) catch return false;
        if (stat.mtime != file.mtime or stat.size != file.size) return false;
    }
    // Entries whose fragment was materialized for a compilation target
    // (@target blocks) are process-local reductions and must never satisfy
    // a later expansion: their source came from a materialized read, while
    // the underlying file bytes (and the entry's file stats) still describe
    // the unmaterialized source. Rejecting them here forces the slow path,
    // which reads (and materializes) the file again.
    if (std.mem.indexOf(u8, entry.source, "// @target-begin") != null) return false;
    return true;
}

pub fn expandedImportCacheEligible(imported_package_identity: ?[]const u8, current_package_identity: ?[]const u8, current_package_hash: ?[32]u8) bool {
    return imported_package_identity == null and current_package_identity == null and current_package_hash == null;
}

pub fn lineMetadataCacheable(
    line_package_identities: []const ?[]const u8,
    line_package_hashes: []const ?[32]u8,
) bool {
    for (line_package_identities) |identity| {
        if (identity != null) return false;
    }
    for (line_package_hashes) |hash| {
        if (hash != null) return false;
    }
    return true;
}

pub const ExpandedImportCacheDependency = struct {
    owned_start: usize,
    context_dependent: bool = false,
    parent: ?*ExpandedImportCacheDependency = null,
};

fn ownedPathSliceContains(paths: []const []u8, path: []const u8) bool {
    for (paths) |owned_path| {
        if (std.mem.eql(u8, owned_path, path)) return true;
    }
    return false;
}

pub fn markSeenImportContextDependency(
    dependency: ?*ExpandedImportCacheDependency,
    owned_paths: []const []u8,
    path: []const u8,
) void {
    var current = dependency;
    while (current) |dep| {
        if (!ownedPathSliceContains(owned_paths[dep.owned_start..], path)) {
            dep.context_dependent = true;
        }
        current = dep.parent;
    }
}

pub fn rollbackExpandedImportCacheApply(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    line_package_identities: *std.array_list.Managed(?[]const u8),
    line_package_hashes: *std.array_list.Managed(?[32]u8),
    line_origin_paths: *std.array_list.Managed(?[]const u8),
    line_origin_lines: *std.array_list.Managed(u32),
    seen_paths: *std.StringHashMap(void),
    owned_paths: *std.array_list.Managed([]u8),
    layout_versions: *std.array_list.Managed(LayoutVersion),
    out_len: usize,
    line_len: usize,
    owned_len: usize,
    layout_len: usize,
) void {
    out.shrinkRetainingCapacity(out_len);
    line_package_identities.shrinkRetainingCapacity(line_len);
    line_package_hashes.shrinkRetainingCapacity(line_len);
    line_origin_paths.shrinkRetainingCapacity(line_len);
    line_origin_lines.shrinkRetainingCapacity(line_len);
    for (owned_paths.items[owned_len..]) |path| {
        _ = seen_paths.remove(path);
        allocator.free(path);
    }
    owned_paths.shrinkRetainingCapacity(owned_len);
    for (layout_versions.items[layout_len..]) |*layout_version| layout_version.deinit(allocator);
    layout_versions.shrinkRetainingCapacity(layout_len);
}

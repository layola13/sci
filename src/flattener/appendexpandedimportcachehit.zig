const std = @import("std");
const builtin = @import("builtin");
const def_dict = @import("def_dict.zig");
const classifier = @import("line_classifier.zig");
const pkg_resolver = @import("../pkg/resolver.zig");
const ConstDecl = @import("../common/const_decl.zig").ConstDecl;
const DefDict = @import("def_dict.zig").DefDict;
const ForbiddenHit = @import("forbidden.zig").ForbiddenHit;
const FunctionSig = @import("../common/signature.zig").FunctionSig;
const Instruction = @import("../common/instruction.zig").Instruction;
const LocTable = @import("../common/upstream_loc.zig").LocTable;
const SymbolTable = @import("symbol.zig").SymbolTable;
const Trap = @import("../common/trap.zig").Trap;
const CachedMacroDef = @import("importexpansion.zig").CachedMacroDef;
const CachedMacroLine = @import("importexpansion.zig").CachedMacroLine;
const ExpandedImportCacheEntry = @import("importexpansion.zig").ExpandedImportCacheEntry;
const ExpandedImportCacheFileStat = @import("importexpansion.zig").ExpandedImportCacheFileStat;
const ImportSourceCacheEntry = @import("importexpansion.zig").ImportSourceCacheEntry;
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const MacroDef = @import("importexpansion.zig").MacroDef;
const Replacement = @import("importexpansion.zig").Replacement;
const SourceLine = @import("importexpansion.zig").SourceLine;
const cachedExpandedImportStillValid = @import("importexpansion.zig").cachedExpandedImportStillValid;
const expandedImportCacheMap = @import("importexpansion.zig").expandedImportCacheMap;
const expandedImportCacheMaxEntries = @import("importexpansion.zig").expandedImportCacheMaxEntries;
const freeExpandedImportCacheEntry = @import("importexpansion.zig").freeExpandedImportCacheEntry;
const freeImportSourceCacheEntry = @import("importexpansion.zig").freeImportSourceCacheEntry;
const importSourceCacheMap = @import("importexpansion.zig").importSourceCacheMap;
const importSourceCacheMaxEntries = @import("importexpansion.zig").importSourceCacheMaxEntries;
const nextExpandedImportCacheTickLocked = @import("importexpansion.zig").nextExpandedImportCacheTickLocked;
const nextImportSourceCacheTickLocked = @import("importexpansion.zig").nextImportSourceCacheTickLocked;
const rollbackExpandedImportCacheApply = @import("importexpansion.zig").rollbackExpandedImportCacheApply;
const statImportSourceCacheEntry = @import("importexpansion.zig").statImportSourceCacheEntry;
const importexpansion = @import("importexpansion.zig");


pub fn appendExpandedImportCacheHit(
    allocator: std.mem.Allocator,
    cache_key: []const u8,
    out: *std.array_list.Managed(u8),
    line_package_identities: *std.array_list.Managed(?[]const u8),
    line_package_hashes: *std.array_list.Managed(?[32]u8),
    line_origin_paths: *std.array_list.Managed(?[]const u8),
    line_origin_lines: *std.array_list.Managed(u32),
    active_paths: *std.StringHashMap(void),
    seen_paths: *std.StringHashMap(void),
    owned_paths: *std.array_list.Managed([]u8),
    layout_versions: *std.array_list.Managed(LayoutVersion),
) !bool {
    while (!importexpansion.expanded_import_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer importexpansion.expanded_import_cache_mutex.unlock();

    if (importexpansion.expanded_import_cache == null) return false;
    var cache = expandedImportCacheMap();
    const entry = cache.getPtr(cache_key) orelse return false;
    if (!cachedExpandedImportStillValid(entry.*)) {
        if (cache.fetchRemove(cache_key)) |removed| {
            std.heap.page_allocator.free(removed.key);
            freeExpandedImportCacheEntry(removed.value);
        }
        return false;
    }

    for (entry.files) |file| {
        if (active_paths.contains(file.path)) return error.ImportCycle;
        if (seen_paths.contains(file.path)) return false;
    }

    const out_len = out.items.len;
    const line_len = line_package_identities.items.len;
    const owned_len = owned_paths.items.len;
    const layout_len = layout_versions.items.len;
    errdefer rollbackExpandedImportCacheApply(
        allocator,
        out,
        line_package_identities,
        line_package_hashes,
        line_origin_paths,
        line_origin_lines,
        seen_paths,
        owned_paths,
        layout_versions,
        out_len,
        line_len,
        owned_len,
        layout_len,
    );

    try out.appendSlice(entry.source);
    try line_package_identities.ensureUnusedCapacity(entry.line_count);
    try line_package_hashes.ensureUnusedCapacity(entry.line_count);
    try line_origin_paths.ensureUnusedCapacity(entry.line_count);
    try line_origin_lines.ensureUnusedCapacity(entry.line_count);
    for (0..entry.line_count) |_| {
        line_package_identities.appendAssumeCapacity(null);
        line_package_hashes.appendAssumeCapacity(null);
        // Origins are not stored in the cache entry; like the package
        // metadata above, they degrade to unknown on a cache hit.
        line_origin_paths.appendAssumeCapacity(null);
        line_origin_lines.appendAssumeCapacity(0);
    }

    for (entry.files) |file| {
        const path_copy = try allocator.dupe(u8, file.path);
        owned_paths.append(path_copy) catch |err| {
            allocator.free(path_copy);
            return err;
        };
        seen_paths.put(path_copy, {}) catch |err| {
            _ = owned_paths.pop();
            allocator.free(path_copy);
            return err;
        };
    }
    for (entry.layout_versions) |layout_version| {
        const path_copy = try allocator.dupe(u8, layout_version.path);
        layout_versions.append(.{ .path = path_copy, .version = layout_version.version }) catch |err| {
            allocator.free(path_copy);
            return err;
        };
    }

    entry.last_used_tick = nextExpandedImportCacheTickLocked();
    if (builtin.is_test) importexpansion.test_expanded_import_cache_hits += 1;
    return true;
}

pub fn storeExpandedImportCacheEntry(
    cache_key: []const u8,
    source: []const u8,
    line_count: usize,
    files: []const []u8,
    layout_versions: []const LayoutVersion,
) !void {
    if (source.len == 0 and line_count == 0) return;
    // Never store a fragment that was materialized for a compilation
    // target (@target blocks): the fragment's file stats describe the
    // unmaterialized sources, so a later hit would replay the reduction
    // under validity evidence for different bytes (and the hit path cannot
    // distinguish which import in the fragment was the hybrid one).
    if (std.mem.indexOf(u8, source, "// @target-begin") != null) return;
    const cache_allocator = std.heap.page_allocator;
    const cache_key_copy = try cache_allocator.dupe(u8, cache_key);
    errdefer cache_allocator.free(cache_key_copy);
    const source_copy = try cache_allocator.dupe(u8, source);
    errdefer cache_allocator.free(source_copy);
    const file_stats = try cache_allocator.alloc(ExpandedImportCacheFileStat, files.len);
    errdefer cache_allocator.free(file_stats);
    var copied_files: usize = 0;
    errdefer {
        for (file_stats[0..copied_files]) |file| cache_allocator.free(file.path);
    }
    for (files, 0..) |path, idx| {
        const stat = try statImportSourceCacheEntry(path);
        file_stats[idx] = .{
            .path = try cache_allocator.dupe(u8, path),
            .mtime = stat.mtime,
            .size = stat.size,
        };
        copied_files += 1;
    }
    const layout_copies = try cache_allocator.alloc(LayoutVersion, layout_versions.len);
    errdefer cache_allocator.free(layout_copies);
    var copied_layouts: usize = 0;
    errdefer {
        for (layout_copies[0..copied_layouts]) |*layout_version| layout_version.deinit(cache_allocator);
    }
    for (layout_versions, 0..) |layout_version, idx| {
        const path_copy = try cache_allocator.dupe(u8, layout_version.path);
        layout_copies[idx] = .{ .path = path_copy, .version = layout_version.version };
        copied_layouts += 1;
    }

    while (!importexpansion.expanded_import_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer importexpansion.expanded_import_cache_mutex.unlock();
    var cache = expandedImportCacheMap();
    if (cache.getPtr(cache_key)) |old| {
        freeExpandedImportCacheEntry(old.*);
        old.* = .{
            .source = source_copy,
            .line_count = line_count,
            .files = file_stats,
            .layout_versions = layout_copies,
            .last_used_tick = nextExpandedImportCacheTickLocked(),
        };
        cache_allocator.free(cache_key_copy);
    } else {
        try cache.put(cache_key_copy, .{
            .source = source_copy,
            .line_count = line_count,
            .files = file_stats,
            .layout_versions = layout_copies,
            .last_used_tick = nextExpandedImportCacheTickLocked(),
        });
    }
    evictExpandedImportCacheIfNeeded(cache, expandedImportCacheMaxEntries());
    if (builtin.is_test) importexpansion.test_expanded_import_cache_stores += 1;
}

pub fn storeImportSourceCacheEntry(key: []const u8, resolved: pkg_resolver.ResolvedImport) !void {
    const stat = try statImportSourceCacheEntry(resolved.entry_path);
    const cache_allocator = std.heap.page_allocator;
    const cache_key = try cache_allocator.dupe(u8, key);
    errdefer cache_allocator.free(cache_key);
    const entry_path = try cache_allocator.dupe(u8, resolved.entry_path);
    errdefer cache_allocator.free(entry_path);
    const source = try cache_allocator.dupe(u8, resolved.source);
    errdefer cache_allocator.free(source);
    const root_dir = if (resolved.root_dir) |dir| try cache_allocator.dupe(u8, dir) else null;
    errdefer if (root_dir) |dir| cache_allocator.free(dir);
    const package_identity = if (resolved.package_identity) |identity| try cache_allocator.dupe(u8, identity) else null;
    errdefer if (package_identity) |identity| cache_allocator.free(identity);

    while (!importexpansion.import_source_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer importexpansion.import_source_cache_mutex.unlock();
    var cache = importSourceCacheMap();
    if (cache.contains(key)) {
        cache_allocator.free(cache_key);
        cache_allocator.free(entry_path);
        cache_allocator.free(source);
        if (root_dir) |dir| cache_allocator.free(dir);
        if (package_identity) |identity| cache_allocator.free(identity);
        return;
    }
    try cache.put(cache_key, .{
        .entry_path = entry_path,
        .root_dir = root_dir,
        .package_identity = package_identity,
        .source_sha256 = resolved.source_sha256,
        .source = source,
        .mtime = stat.mtime,
        .size = stat.size,
        .is_global = resolved.is_global,
        .last_used_tick = nextImportSourceCacheTickLocked(),
    });
    evictImportSourceCacheIfNeeded(cache, importSourceCacheMaxEntries());
}

fn evictImportSourceCacheIfNeeded(cache: *std.StringHashMap(ImportSourceCacheEntry), max_entries: ?usize) void {
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
            freeImportSourceCacheEntry(removed.value, true);
        } else {
            return;
        }
    }
}

fn evictExpandedImportCacheIfNeeded(cache: *std.StringHashMap(ExpandedImportCacheEntry), max_entries: ?usize) void {
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
            freeExpandedImportCacheEntry(removed.value);
        } else {
            return;
        }
    }
}

pub const FlattenResult = struct {
    instructions: []Instruction,
    const_decls: []ConstDecl,
    function_sigs: []FunctionSig,
    test_sigs: []FunctionSig,
    cached_macro_defs: []CachedMacroDef,
    def_dict: DefDict,
    symbols: SymbolTable,
    loc_table: LocTable,
    layout_versions: []LayoutVersion,
    package_identities: std.StringHashMap(void),
    owned_text: [][]const u8,
    trap: ?Trap = null,

    pub fn deinit(self: *FlattenResult, allocator: std.mem.Allocator) void {
        for (self.loc_table) |entry| {
            if (entry) |loc| allocator.free(loc.file);
        }
        allocator.free(self.loc_table);
        for (self.layout_versions) |*layout_version| layout_version.deinit(allocator);
        allocator.free(self.layout_versions);
        var pkg_it = self.package_identities.iterator();
        while (pkg_it.next()) |entry| allocator.free(entry.key_ptr.*);
        self.package_identities.deinit();
        for (self.instructions) |item| {
            if (item.package_identity) |identity| allocator.free(identity);
            if (item.upstream_loc) |loc| allocator.free(loc.file);
            if (item.native_reg_names.len != 0) allocator.free(item.native_reg_names);
        }
        for (self.const_decls) |*decl| decl.deinit(allocator);
        allocator.free(self.const_decls);
        for (self.owned_text) |text| allocator.free(text);
        allocator.free(self.owned_text);
        for (self.function_sigs) |*sig| sig.deinit(allocator);
        allocator.free(self.function_sigs);
        allocator.free(self.test_sigs);
        deinitCachedMacroDefs(allocator, self.cached_macro_defs);
        allocator.free(self.instructions);
        self.def_dict.deinit();
        self.symbols.deinit();
        self.* = undefined;
    }
};

pub const ForbiddenLine = struct {
    line_no: u32,
    hit: ForbiddenHit,
};

pub fn parseTokenList(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) {
        return try allocator.alloc([]const u8, 0);
    }

    var list = std.array_list.Managed([]const u8).init(allocator);
    errdefer list.deinit();

    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |item| {
        const token = std.mem.trim(u8, item, " \t");
        if (token.len == 0) return error.InvalidMacroInvocation;
        try list.append(token);
    }

    return try list.toOwnedSlice();
}

pub fn parseMacroParams(allocator: std.mem.Allocator, text: []const u8) !struct { params: []const []const u8, variadic_param: ?[]const u8 } {
    const raw_params = try parseTokenList(allocator, text);
    errdefer allocator.free(raw_params);

    var variadic_param: ?[]const u8 = null;
    var param_count = raw_params.len;

    for (raw_params, 0..) |param, idx| {
        if (std.mem.endsWith(u8, param, "...")) {
            if (idx + 1 != raw_params.len) return error.InvalidMacroInvocation;
            const base = std.mem.trimEnd(u8, param[0 .. param.len - 3], " \t");
            if (base.len == 0) return error.InvalidMacroInvocation;
            variadic_param = base;
            param_count = idx;
        }
    }

    if (param_count == raw_params.len) {
        return .{ .params = raw_params, .variadic_param = null };
    }

    const fixed_params = try allocator.alloc([]const u8, param_count);
    errdefer allocator.free(fixed_params);
    @memcpy(fixed_params, raw_params[0..param_count]);
    allocator.free(raw_params);
    return .{ .params = fixed_params, .variadic_param = variadic_param };
}

pub fn joinTokens(allocator: std.mem.Allocator, tokens: []const []const u8) ![]const u8 {
    if (tokens.len == 0) return try allocator.dupe(u8, "");
    var total_len: usize = 0;
    for (tokens) |token| total_len += token.len;
    total_len += (tokens.len - 1) * 2;

    var out = try allocator.alloc(u8, total_len);
    var cursor: usize = 0;
    for (tokens, 0..) |token, idx| {
        if (idx != 0) {
            out[cursor] = ',';
            out[cursor + 1] = ' ';
            cursor += 2;
        }
        @memcpy(out[cursor .. cursor + token.len], token);
        cursor += token.len;
    }
    return out;
}

pub fn deinitMacroMap(allocator: std.mem.Allocator, macros: *std.StringHashMap(MacroDef)) void {
    var it = macros.valueIterator();
    while (it.next()) |macro_def| {
        macro_def.deinit(allocator);
    }
    macros.deinit();
}

pub fn deinitCachedMacroDefs(allocator: std.mem.Allocator, defs: []CachedMacroDef) void {
    for (defs) |*def| def.deinit(allocator);
    allocator.free(defs);
}

fn deinitCachedMacroDefItems(allocator: std.mem.Allocator, defs: []CachedMacroDef) void {
    for (defs) |*def| def.deinit(allocator);
}

fn deinitOwnedSourceLineItems(allocator: std.mem.Allocator, lines: []SourceLine) void {
    for (lines) |line| {
        allocator.free(@constCast(line.text));
        if (line.package_identity) |identity| allocator.free(@constCast(identity));
    }
}

pub fn deinitOwnedSourceLines(allocator: std.mem.Allocator, lines: []SourceLine) void {
    deinitOwnedSourceLineItems(allocator, lines);
    allocator.free(lines);
}

pub fn cloneOwnedSourceLines(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
) ![]SourceLine {
    const owned = try allocator.alloc(SourceLine, lines.len);
    errdefer allocator.free(owned);

    var copied: usize = 0;
    errdefer deinitOwnedSourceLineItems(allocator, owned[0..copied]);

    for (lines, 0..) |line, idx| {
        const owned_text = try allocator.dupe(u8, line.text);
        errdefer allocator.free(owned_text);
        const owned_identity = if (line.package_identity) |identity| try allocator.dupe(u8, identity) else null;
        errdefer if (owned_identity) |identity| allocator.free(identity);
        owned[idx] = .{
            .line_no = line.line_no,
            .text = owned_text,
            .classified = line.classified,
            .package_identity = owned_identity,
            .package_source_sha256 = line.package_source_sha256,
        };
        copied += 1;
    }

    return owned;
}

pub fn macroDefBodyLines(def: *const MacroDef) ![]const SourceLine {
    if (def.owned_body_lines.len == 0) return error.InvalidMacroInvocation;
    return def.owned_body_lines;
}

pub fn captureCachedMacroDefs(
    allocator: std.mem.Allocator,
    macros: *const std.StringHashMap(MacroDef),
) ![]CachedMacroDef {
    const defs = try allocator.alloc(CachedMacroDef, macros.count());
    errdefer allocator.free(defs);
    var copied_defs: usize = 0;
    errdefer deinitCachedMacroDefItems(allocator, defs[0..copied_defs]);

    var it = macros.iterator();
    while (it.next()) |entry| {
        const def = entry.value_ptr.*;
        const body_lines = try macroDefBodyLines(&def);
        var cached = CachedMacroDef{
            .name = try allocator.dupe(u8, entry.key_ptr.*),
            .params = &.{},
            .variadic_param = null,
            .body_lines = &.{},
        };
        errdefer cached.deinit(allocator);

        cached.params = try allocator.alloc([]const u8, def.params.len);
        var copied_params: usize = 0;
        errdefer {
            for (cached.params[0..copied_params]) |param| allocator.free(param);
            allocator.free(cached.params);
            cached.params = &.{};
        }

        for (def.params, 0..) |param, idx| {
            cached.params[idx] = try allocator.dupe(u8, param);
            copied_params += 1;
        }
        if (def.variadic_param) |param| {
            cached.variadic_param = try allocator.dupe(u8, param);
        }

        cached.body_lines = try allocator.alloc(CachedMacroLine, body_lines.len);
        var copied_body_lines: usize = 0;
        errdefer {
            for (cached.body_lines[0..copied_body_lines]) |*line| line.deinit(allocator);
            allocator.free(cached.body_lines);
            cached.body_lines = &.{};
        }

        for (body_lines, 0..) |line, idx| {
            const owned_text = try allocator.dupe(u8, line.text);
            errdefer allocator.free(owned_text);
            const owned_identity = if (line.package_identity) |identity| try allocator.dupe(u8, identity) else null;
            errdefer if (owned_identity) |identity| allocator.free(identity);
            cached.body_lines[idx] = .{
                .line_no = line.line_no,
                .text = owned_text,
                .package_identity = owned_identity,
                .package_source_sha256 = line.package_source_sha256,
            };
            copied_body_lines += 1;
        }

        defs[copied_defs] = cached;
        copied_defs += 1;
    }

    return defs[0..copied_defs];
}

pub fn restoreCachedMacroDefs(
    allocator: std.mem.Allocator,
    defs: []const CachedMacroDef,
    macros: *std.StringHashMap(MacroDef),
) !void {
    for (defs) |cached| {
        if (macros.contains(cached.name)) {
            continue;
        }

        const owned_body_lines = try allocator.alloc(SourceLine, cached.body_lines.len);
        errdefer allocator.free(owned_body_lines);
        var copied_body_lines: usize = 0;
        errdefer deinitOwnedSourceLineItems(allocator, owned_body_lines[0..copied_body_lines]);
        for (cached.body_lines, 0..) |line, idx| {
            const owned_text = try allocator.dupe(u8, line.text);
            errdefer allocator.free(owned_text);
            const owned_identity = if (line.package_identity) |identity| try allocator.dupe(u8, identity) else null;
            errdefer if (owned_identity) |identity| allocator.free(identity);
            owned_body_lines[idx] = .{
                .line_no = line.line_no,
                .text = owned_text,
                .classified = classifier.classifyLine(owned_text),
                .package_identity = owned_identity,
                .package_source_sha256 = line.package_source_sha256,
            };
            copied_body_lines += 1;
        }

        const owned_name = try allocator.dupe(u8, cached.name);
        errdefer allocator.free(owned_name);
        const owned_params = try allocator.alloc([]const u8, cached.params.len);
        errdefer allocator.free(owned_params);
        var copied_params: usize = 0;
        errdefer {
            for (owned_params[0..copied_params]) |param| allocator.free(param);
        }
        for (cached.params, 0..) |param, idx| {
            owned_params[idx] = try allocator.dupe(u8, param);
            copied_params += 1;
        }
        const owned_variadic_param = if (cached.variadic_param) |param| try allocator.dupe(u8, param) else null;
        errdefer if (owned_variadic_param) |param| allocator.free(param);

        try macros.put(owned_name, .{
            .params = owned_params,
            .variadic_param = owned_variadic_param,
            .body_start = 0,
            .body_end = owned_body_lines.len,
            .owned_body_lines = owned_body_lines,
            .owned_name = owned_name,
            .owned_params = owned_params,
            .owned_variadic_param = owned_variadic_param,
        });
    }
}

fn renderWithReplacements(
    allocator: std.mem.Allocator,
    text: []const u8,
    replacements: []const Replacement,
) ![]const u8 {
    if (replacements.len == 0) {
        return try allocator.dupe(u8, text);
    }

    var current = try allocator.dupe(u8, text);
    errdefer allocator.free(current);

    for (replacements) |replacement| {
        if (replacement.needle.len == 0) continue;
        const next = try std.mem.replaceOwned(u8, allocator, current, replacement.needle, replacement.replacement);
        allocator.free(current);
        current = next;
    }

    return current;
}

const std = @import("std");
const sio = @import("sio");
const classifier = @import("line_classifier.zig");
const forbidden = @import("forbidden.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const ErrorContext = @import("importexpansion.zig").ErrorContext;
const ExpandedImportCacheDependency = @import("importexpansion.zig").ExpandedImportCacheDependency;
const FlattenResult = @import("appendexpandedimportcachehit.zig").FlattenResult;
const ForbiddenLine = @import("appendexpandedimportcachehit.zig").ForbiddenLine;
const ImportExpansion = @import("importexpansion.zig").ImportExpansion;
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const MacroDef = @import("importexpansion.zig").MacroDef;
const Replacement = @import("importexpansion.zig").Replacement;
const ResolveContext = @import("importexpansion.zig").ResolveContext;
const appendExpandedImportCacheHit = @import("appendexpandedimportcachehit.zig").appendExpandedImportCacheHit;
const appendExpandedLine = @import("importexpansion.zig").appendExpandedLine;
const appendGeneratedLocLine = @import("importexpansion.zig").appendGeneratedLocLine;
const buildImportSourceCacheKey = @import("importexpansion.zig").buildImportSourceCacheKey;
const captureCachedMacroDefs = @import("appendexpandedimportcachehit.zig").captureCachedMacroDefs;
const clearExpandedImportCacheForTest = @import("tests_12.zig").clearExpandedImportCacheForTest;
const clearImportSourceCacheForTest = @import("tests_12.zig").clearImportSourceCacheForTest;
const collectLocTableEntries = @import("emitrange.zig").collectLocTableEntries;
const collectMacroDefinitions = @import("emitparsedline.zig").collectMacroDefinitions;
const consumesPendingLoc = @import("importexpansion.zig").consumesPendingLoc;
const countSourceLines = @import("cloneremappedsymboltext.zig").countSourceLines;
const deinitCachedMacroDefs = @import("appendexpandedimportcachehit.zig").deinitCachedMacroDefs;
const deinitMacroMap = @import("appendexpandedimportcachehit.zig").deinitMacroMap;
const emitRange = @import("emitrange.zig").emitRange;
const expandedImportCacheEligible = @import("importexpansion.zig").expandedImportCacheEligible;
const injectImportedFile = @import("injectimportedfile.zig").injectImportedFile;
const isFunctionLikeLineKind = @import("importexpansion.zig").isFunctionLikeLineKind;
const lineMetadataCacheable = @import("importexpansion.zig").lineMetadataCacheable;
const markSeenImportContextDependency = @import("importexpansion.zig").markSeenImportContextDependency;
const materializeRootSource = @import("injectimportedfile.zig").materializeRootSource;
const parseImportPath = @import("injectimportedfile.zig").parseImportPath;
const readImportFile = @import("injectimportedfile.zig").readImportFile;
const recordErrorOrigin = @import("importexpansion.zig").recordErrorOrigin;
const recordLayoutVersion = @import("renderwithtokenreplacements.zig").recordLayoutVersion;
const rememberPackageIdentity = @import("injectimportedfile.zig").rememberPackageIdentity;
const rewritePackageLayoutSource = @import("injectimportedfile.zig").rewritePackageLayoutSource;
const scanSourceWithOrigins = @import("cloneremappedsymboltext.zig").scanSourceWithOrigins;
const storeExpandedImportCacheEntry = @import("appendexpandedimportcachehit.zig").storeExpandedImportCacheEntry;
const traceImportsEnabled = @import("importexpansion.zig").traceImportsEnabled;


pub fn expandImportsInto(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    line_package_identities: *std.array_list.Managed(?[]const u8),
    line_package_hashes: *std.array_list.Managed(?[32]u8),
    line_origin_paths: *std.array_list.Managed(?[]const u8),
    line_origin_lines: *std.array_list.Managed(u32),
    source: []const u8,
    base_dir: []const u8,
    current_source_path: ?[]const u8,
    is_root_call: bool,
    active_paths: *std.StringHashMap(void),
    seen_paths: *std.StringHashMap(void),
    seen_package_identities: *std.StringHashMap(void),
    owned_paths: *std.array_list.Managed([]u8),
    layout_versions: *std.array_list.Managed(LayoutVersion),
    error_ctx: ?*ErrorContext,
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
    resolve_ctx: ?ResolveContext,
    cache_dependency: ?*ExpandedImportCacheDependency,
) !void {
    const estimated_line_count = countSourceLines(source);
    try out.ensureUnusedCapacity(source.len +| 1);
    try line_package_identities.ensureUnusedCapacity(estimated_line_count);
    try line_package_hashes.ensureUnusedCapacity(estimated_line_count);
    try line_origin_paths.ensureUnusedCapacity(estimated_line_count);
    try line_origin_lines.ensureUnusedCapacity(estimated_line_count);

    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    var explicit_loc_pending = false;
    while (iterator.next()) |raw_line| : (line_no += 1) {
        recordErrorOrigin(error_ctx, if (is_root_call) null else current_source_path, line_no);
        if (parseImportPath(raw_line)) |import_path| {
            var imported = try readImportFile(allocator, base_dir, import_path, resolve_ctx);
            if (traceImportsEnabled()) {
                std.debug.print("\n[IMPORT] resolved '{s}' -> '{s}'\n", .{ import_path, imported.entry_path });
            }
            const imported_package_identity = if (imported.package_identity) |identity| blk: {
                break :blk try rememberPackageIdentity(allocator, seen_package_identities, identity);
            } else if (!imported.is_global) blk: {
                if (current_package_identity) |identity| {
                    break :blk try rememberPackageIdentity(allocator, seen_package_identities, identity);
                }
                break :blk null;
            } else null;
            const imported_package_hash = if (imported.package_identity != null)
                imported.source_sha256 orelse current_package_hash
            else
                current_package_hash;
            const expanded_cache_key = if (expandedImportCacheEligible(imported_package_identity, current_package_identity, current_package_hash))
                try buildImportSourceCacheKey(allocator, base_dir, import_path, resolve_ctx)
            else
                null;
            defer if (expanded_cache_key) |key| allocator.free(key);

            if (active_paths.contains(imported.entry_path)) {
                imported.deinit(allocator);
                return error.ImportCycle;
            }
            if (seen_paths.contains(imported.entry_path)) {
                markSeenImportContextDependency(cache_dependency, owned_paths.items, imported.entry_path);
                imported.deinit(allocator);
                continue;
            }
            if (expanded_cache_key) |key| {
                if (try appendExpandedImportCacheHit(
                    allocator,
                    key,
                    out,
                    line_package_identities,
                    line_package_hashes,
                    line_origin_paths,
                    line_origin_lines,
                    active_paths,
                    seen_paths,
                    owned_paths,
                    layout_versions,
                )) {
                    imported.deinit(allocator);
                    continue;
                }
            }
            const fragment_out_start = out.items.len;
            const fragment_line_start = line_package_identities.items.len;
            const fragment_owned_start = owned_paths.items.len;
            const fragment_layout_start = layout_versions.items.len;
            var fragment_dependency = ExpandedImportCacheDependency{
                .owned_start = fragment_owned_start,
                .parent = cache_dependency,
            };
            if (std.mem.endsWith(u8, imported.entry_path, ".sal")) {
                try recordLayoutVersion(allocator, layout_versions, imported.entry_path, imported.source);
            }
            owned_paths.append(imported.entry_path) catch |err| {
                imported.deinit(allocator);
                return err;
            };
            imported.entry_path_owned = false;
            defer imported.deinit(allocator);
            try seen_paths.put(imported.entry_path, {});
            try active_paths.put(imported.entry_path, {});
            defer _ = active_paths.remove(imported.entry_path);

            const import_dir = std.fs.path.dirname(imported.entry_path) orelse ".";
            try injectImportedFile(
                allocator,
                out,
                line_package_identities,
                line_package_hashes,
                line_origin_paths,
                line_origin_lines,
                &imported,
                active_paths,
                seen_paths,
                seen_package_identities,
                owned_paths,
                layout_versions,
                error_ctx,
                current_package_identity,
                imported_package_hash,
                resolve_ctx,
                &fragment_dependency,
            );
            const is_layout_file = std.mem.endsWith(u8, imported.entry_path, ".sal");
            var rewritten_source: ?[]u8 = null;
            defer if (rewritten_source) |rewritten| allocator.free(rewritten);
            const expanded_source = if (is_layout_file) blk: {
                if (imported_package_identity) |identity| {
                    const rewritten = try rewritePackageLayoutSource(allocator, imported.source, identity);
                    rewritten_source = rewritten;
                    break :blk rewritten;
                }
                break :blk imported.source;
            } else imported.source;
            try expandImportsInto(
                allocator,
                out,
                line_package_identities,
                line_package_hashes,
                line_origin_paths,
                line_origin_lines,
                expanded_source,
                import_dir,
                imported.entry_path,
                false,
                active_paths,
                seen_paths,
                seen_package_identities,
                owned_paths,
                layout_versions,
                error_ctx,
                imported_package_identity,
                imported_package_hash,
                resolve_ctx,
                &fragment_dependency,
            );
            if (expanded_cache_key) |key| {
                const fragment_identities = line_package_identities.items[fragment_line_start..];
                const fragment_hashes = line_package_hashes.items[fragment_line_start..];
                if (!fragment_dependency.context_dependent and lineMetadataCacheable(fragment_identities, fragment_hashes)) {
                    storeExpandedImportCacheEntry(
                        key,
                        out.items[fragment_out_start..],
                        fragment_identities.len,
                        owned_paths.items[fragment_owned_start..],
                        layout_versions.items[fragment_layout_start..],
                    ) catch |err| {
                        // Expanded import caching is an optimization; successful expansion remains authoritative.
                        _ = @errorName(err);
                    };
                }
            }
            continue;
        }

        const classified = classifier.classifyLine(raw_line);
        const line_origin_path: ?[]const u8 = if (is_root_call) null else current_source_path;
        if (current_source_path) |path| {
            if (isFunctionLikeLineKind(classified.kind) and !explicit_loc_pending) {
                try appendGeneratedLocLine(allocator, out, line_package_identities, line_package_hashes, line_origin_paths, line_origin_lines, path, line_no, current_package_identity, current_package_hash, line_origin_path);
            }
        }
        try appendExpandedLine(out, line_package_identities, line_package_hashes, line_origin_paths, line_origin_lines, raw_line, current_package_identity, current_package_hash, line_origin_path, line_no);
        if (classified.kind == .loc_hint) {
            explicit_loc_pending = true;
        } else if (consumesPendingLoc(classified.kind)) {
            explicit_loc_pending = false;
        }
    }
}

pub fn expandImports(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_path: ?[]const u8,
    error_ctx: ?*ErrorContext,
    resolve_ctx: ?ResolveContext,
) !ImportExpansion {
    var active_paths = std.StringHashMap(void).init(allocator);
    errdefer active_paths.deinit();

    var seen_paths = std.StringHashMap(void).init(allocator);
    errdefer seen_paths.deinit();

    var seen_package_identities = std.StringHashMap(void).init(allocator);
    errdefer {
        var pkg_it = seen_package_identities.iterator();
        while (pkg_it.next()) |entry| allocator.free(entry.key_ptr.*);
        seen_package_identities.deinit();
    }

    var line_package_identities = std.array_list.Managed(?[]const u8).init(allocator);
    errdefer line_package_identities.deinit();

    var line_package_hashes = std.array_list.Managed(?[32]u8).init(allocator);
    errdefer line_package_hashes.deinit();

    var line_origin_paths = std.array_list.Managed(?[]const u8).init(allocator);
    errdefer line_origin_paths.deinit();

    var line_origin_lines = std.array_list.Managed(u32).init(allocator);
    errdefer line_origin_lines.deinit();

    var owned_paths = std.array_list.Managed([]u8).init(allocator);
    errdefer {
        for (owned_paths.items) |path| allocator.free(path);
        owned_paths.deinit();
    }
    var layout_versions = std.array_list.Managed(LayoutVersion).init(allocator);
    errdefer {
        for (layout_versions.items) |*layout_version| layout_version.deinit(allocator);
        layout_versions.deinit();
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    const base_dir = if (source_path) |path| std.fs.path.dirname(path) orelse "." else ".";
    var root_source_path: ?[]const u8 = null;
    if (source_path) |path| {
        const source_full = if (std.fs.path.isAbsolute(path))
            try allocator.dupe(u8, path)
        else
            try sio.cwd().realpathAlloc(allocator, path);
        owned_paths.append(source_full) catch |err| {
            allocator.free(source_full);
            return err;
        };
        root_source_path = source_full;
        try active_paths.put(source_full, {});
        try seen_paths.put(source_full, {});

        if (std.mem.endsWith(u8, source_full, ".sal")) {
            try recordLayoutVersion(allocator, &layout_versions, source_full, source);
        }
    }

    const current_package_identity = if (resolve_ctx) |ctx|
        if (ctx.package_identity) |identity|
            try rememberPackageIdentity(allocator, &seen_package_identities, identity)
        else
            null
    else
        null;
    try expandImportsInto(
        allocator,
        &out,
        &line_package_identities,
        &line_package_hashes,
        &line_origin_paths,
        &line_origin_lines,
        source,
        base_dir,
        root_source_path,
        true,
        &active_paths,
        &seen_paths,
        &seen_package_identities,
        &owned_paths,
        &layout_versions,
        error_ctx,
        current_package_identity,
        null,
        resolve_ctx,
        null,
    );

    return .{
        .source = try out.toOwnedSlice(),
        .active_paths = active_paths,
        .seen_paths = seen_paths,
        .seen_package_identities = seen_package_identities,
        .line_package_identities = line_package_identities,
        .line_package_hashes = line_package_hashes,
        .line_origin_paths = line_origin_paths,
        .line_origin_lines = line_origin_lines,
        .owned_paths = owned_paths,
        .layout_versions = layout_versions,
    };
}

pub fn findFirstForbiddenLine(source: []const u8) ?ForbiddenLine {
    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iterator.next()) |raw_line| : (line_no += 1) {
        const classified = classifier.classifyLine(raw_line);
        if (classified.kind == .native or classified.kind == .import_decl or classified.kind == .const_decl) continue;
        if (forbidden.findForbiddenSyntax(raw_line)) |hit| {
            return .{ .line_no = line_no, .hit = hit };
        }
    }
    return null;
}

fn flattenInternal(
    allocator: std.mem.Allocator,
    source_in: []const u8,
    source_path: ?[]const u8,
    error_ctx: ?*ErrorContext,
    resolve_ctx: ?ResolveContext,
) !FlattenResult {
    if (error_ctx) |ctx| ctx.reset();
    // The root source is a compilation input exactly like an imported one:
    // when a caller hands the flattener a hybrid std file directly (the
    // std-smoke tests flatten sa_std/hashset.sa et al. as roots), its
    // @target blocks must be materialized too, not just spliced imports.
    // Materialize here, at the single entry every flatten verb shares.
    const mat_root = try materializeRootSource(allocator, source_in, resolve_ctx);
    defer if (mat_root.owned) |owned| allocator.free(owned);
    const source = mat_root.source;
    var expanded = try expandImports(allocator, source, source_path, error_ctx, resolve_ctx);
    defer expanded.deinit(allocator);

    if (findFirstForbiddenLine(expanded.source)) |_| {
        return error.ForbiddenSyntax;
    }

    var dict = DefDict.init(allocator);
    errdefer dict.deinit();
    var symbols = SymbolTable.init(allocator);
    errdefer symbols.deinit();
    var instructions = std.array_list.Managed(Instruction).init(allocator);
    errdefer {
        for (instructions.items) |*inst| {
            if (inst.package_identity) |identity| allocator.free(identity);
            if (inst.upstream_loc) |loc| {
                const is_func_decl = switch (inst.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => true,
                    else => false,
                };
                if (is_func_decl) allocator.free(loc.file);
            }
            // NOTE: atomic_expected/new_text alias owned_text entries (see
            // ownFoldedText) and native_reg_names items are slices into the
            // owned native_copy; both are freed via owned_text. Freeing them
            // here double-frees on the error path.
            if (inst.native_reg_names.len > 0) allocator.free(inst.native_reg_names);
        }
        instructions.deinit();
    }
    var const_decls = std.array_list.Managed(ConstDecl).init(allocator);
    errdefer {
        for (const_decls.items) |*decl| decl.deinit(allocator);
        const_decls.deinit();
    }
    var function_sigs = std.array_list.Managed(FunctionSig).init(allocator);
    errdefer {
        for (function_sigs.items) |*sig_item| sig_item.deinit(allocator);
        function_sigs.deinit();
    }
    var owned_text = std.array_list.Managed([]const u8).init(allocator);
    errdefer {
        for (owned_text.items) |text| allocator.free(text);
        owned_text.deinit();
    }
    var loc_table = std.array_list.Managed(?common_upstream.UpstreamLoc).init(allocator);
    errdefer {
        for (loc_table.items) |entry| {
            if (entry) |loc| allocator.free(loc.file);
        }
        loc_table.deinit();
    }
    var pending_loc: ?common_upstream.UpstreamLoc = null;
    errdefer if (pending_loc) |loc| allocator.free(loc.file);

    var macros = std.StringHashMap(MacroDef).init(allocator);
    defer deinitMacroMap(allocator, &macros);

    var include_stack = std.array_list.Managed([]const u8).init(allocator);
    defer include_stack.deinit();
    var macro_call_stack = std.array_list.Managed(*const MacroDef).init(allocator);
    defer macro_call_stack.deinit();

    const lines = try scanSourceWithOrigins(allocator, expanded.source, expanded.line_package_identities.items[0..], expanded.line_package_hashes.items[0..], expanded.line_origin_paths.items[0..], expanded.line_origin_lines.items[0..]);
    defer allocator.free(lines);

    try collectMacroDefinitions(allocator, lines, &macros, error_ctx);
    const cached_macro_defs = try captureCachedMacroDefs(allocator, &macros);
    errdefer deinitCachedMacroDefs(allocator, cached_macro_defs);
    const empty_replacements = [_]Replacement{};
    var expansion_counter: u64 = 0;
    emitRange(
        allocator,
        lines,
        0,
        lines.len,
        0,
        null,
        source_path,
        &include_stack,
        &macro_call_stack,
        empty_replacements[0..],
        true,
        &macros,
        &dict,
        &symbols,
        &loc_table,
        &pending_loc,
        &instructions,
        &const_decls,
        &function_sigs,
        &owned_text,
        error_ctx,
        null,
        null,
        &expansion_counter,
    ) catch |err| return err;
    if (pending_loc) |loc| {
        allocator.free(loc.file);
        pending_loc = null;
    }

    // `#npm_bind` targets must name a declared `@extern`; anything else
    // (unknown names, non-extern functions) is rejected here so backends
    // never see a dangling binding.
    {
        var bind_it = dict.npm_binds.iterator();
        while (bind_it.next()) |entry| {
            var found = false;
            for (function_sigs.items) |sig| {
                if (sig.kind == .external and std.mem.eql(u8, sig.name, entry.key_ptr.*)) {
                    found = true;
                    break;
                }
            }
            if (!found) return error.UnknownNpmBindTarget;
        }
    }

    const loc_table_slice = try collectLocTableEntries(allocator, instructions.items);
    const layout_versions = try expanded.layout_versions.toOwnedSlice();
    const package_identities = expanded.seen_package_identities;
    expanded.seen_package_identities = std.StringHashMap(void).init(allocator);
    loc_table.deinit();

    const function_sigs_slice = try function_sigs.toOwnedSlice();

    // Filter test functions from function_sigs
    var test_sigs_list = std.array_list.Managed(FunctionSig).init(allocator);
    errdefer test_sigs_list.deinit();
    for (function_sigs_slice) |sig| {
        if (sig.kind == .test_func) {
            try test_sigs_list.append(sig);
        }
    }

    return .{
        .instructions = try instructions.toOwnedSlice(),
        .const_decls = try const_decls.toOwnedSlice(),
        .function_sigs = function_sigs_slice,
        .test_sigs = try test_sigs_list.toOwnedSlice(),
        .cached_macro_defs = cached_macro_defs,
        .def_dict = dict,
        .symbols = symbols,
        .loc_table = loc_table_slice,
        .layout_versions = layout_versions,
        .package_identities = package_identities,
        .owned_text = try owned_text.toOwnedSlice(),
        .trap = null,
    };
}

pub fn flatten(allocator: std.mem.Allocator, source: []const u8) !FlattenResult {
    return flattenInternal(allocator, source, null, null, null);
}

pub fn flattenWithContext(allocator: std.mem.Allocator, source: []const u8, error_ctx: ?*ErrorContext) !FlattenResult {
    return flattenInternal(allocator, source, null, error_ctx, null);
}

pub fn flattenFileWithContext(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
    error_ctx: ?*ErrorContext,
) !FlattenResult {
    return flattenInternal(allocator, source, source_path, error_ctx, null);
}

/// Test-only: drop both import caches so a test observes pure per-call
/// flattening (no cross-test fragment replay).
pub fn clearImportCachesForTest() void {
    clearImportSourceCacheForTest();
    clearExpandedImportCacheForTest();
}

pub fn flattenFile(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !FlattenResult {
    return flattenInternal(allocator, source, source_path, null, null);
}

pub fn flattenWithPackages(
    allocator: std.mem.Allocator,
    source: []const u8,
    resolve_ctx: ResolveContext,
) !FlattenResult {
    return flattenInternal(allocator, source, null, null, resolve_ctx);
}

pub fn flattenWithContextAndPackages(
    allocator: std.mem.Allocator,
    source: []const u8,
    error_ctx: ?*ErrorContext,
    resolve_ctx: ResolveContext,
) !FlattenResult {
    return flattenInternal(allocator, source, null, error_ctx, resolve_ctx);
}

pub fn flattenFileWithPackages(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
    resolve_ctx: ResolveContext,
) !FlattenResult {
    return flattenInternal(allocator, source, source_path, null, resolve_ctx);
}

pub fn flattenFileWithContextAndPackages(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
    error_ctx: ?*ErrorContext,
    resolve_ctx: ResolveContext,
) !FlattenResult {
    return flattenInternal(allocator, source, source_path, error_ctx, resolve_ctx);
}

const MacroPbtProgram = struct {
    source: []u8,
    base_name: []u8,
    acc_name: []u8,
    alloc_size: u64,
    count: u8,

    fn deinit(self: *MacroPbtProgram, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.base_name);
        allocator.free(self.acc_name);
        self.* = undefined;
    }
};

pub fn buildMacroPbtProgram(allocator: std.mem.Allocator, random: std.Random, iter: usize) !MacroPbtProgram {
    const count = random.intRangeAtMost(u8, 0, 4);
    const alloc_size = random.intRangeAtMost(u64, 1, 64);
    const salt = random.intRangeAtMost(u32, 0, 9999);

    const base_name = try std.fmt.allocPrint(allocator, "base_{d}_{d}", .{ iter, salt });
    errdefer allocator.free(base_name);
    const acc_name = try std.fmt.allocPrint(allocator, "acc_{d}_{d}", .{ iter, salt });
    errdefer allocator.free(acc_name);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    const writer = &aw.writer;
    try writer.writeAll(
        \\#def REP_COUNT = 
    );
    try writer.print("{d}\n", .{count});
    try writer.writeAll(
        \\[MACRO] INIT %acc, %base
        \\    %acc = add %base, 0
        \\[END_MACRO]
        \\
        \\[MACRO] CHAIN %acc, %base
        \\    EXPAND INIT %acc, %base
        \\    [REP REP_COUNT]
        \\        tmp_%i = add %acc, %i
        \\    [END_REP]
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\
    );
    try writer.print("    {s} = alloc {d}\n", .{ base_name, alloc_size });
    try writer.print("    EXPAND CHAIN {s}, {s}\n", .{ acc_name, base_name });
    try writer.print("    return {s}\n", .{acc_name});

    return .{
        .source = try aw.toOwnedSlice(),
        .base_name = base_name,
        .acc_name = acc_name,
        .alloc_size = alloc_size,
        .count = count,
    };
}

pub const ArithmeticExpr = struct {
    text: []u8,
    value: i64,

    fn deinit(self: *ArithmeticExpr, allocator: std.mem.Allocator) void {
        allocator.free(self.text);
        self.* = undefined;
    }
};

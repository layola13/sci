const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const classifier = @import("line_classifier.zig");
const common_instruction = @import("../common/instruction.zig");
const pkg_resolver = @import("../pkg/resolver.zig");
const decl_materialize = @import("../decl_materialize.zig");
const Instruction = @import("../common/instruction.zig").Instruction;
const SymbolTable = @import("symbol.zig").SymbolTable;
const ErrorContext = @import("importexpansion.zig").ErrorContext;
const ExpandedImportCacheDependency = @import("importexpansion.zig").ExpandedImportCacheDependency;
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const ResolveContext = @import("importexpansion.zig").ResolveContext;
const buildImportSourceCacheKey = @import("importexpansion.zig").buildImportSourceCacheKey;
const cachedImportStillValid = @import("importexpansion.zig").cachedImportStillValid;
const cloneCachedImport = @import("importexpansion.zig").cloneCachedImport;
const cloneNativeRegNames = @import("cloneremappedsymboltext.zig").cloneNativeRegNames;
const cloneRemappedOperand = @import("cloneremappedsymboltext.zig").cloneRemappedOperand;
const cloneRemappedSymbolText = @import("cloneremappedsymboltext.zig").cloneRemappedSymbolText;
const expandImportsInto = @import("expandimportsinto.zig").expandImportsInto;
const freeImportSourceCacheEntry = @import("importexpansion.zig").freeImportSourceCacheEntry;
const importSourceCacheMaxEntries = @import("importexpansion.zig").importSourceCacheMaxEntries;
const isImportCacheCandidate = @import("importexpansion.zig").isImportCacheCandidate;
const markSeenImportContextDependency = @import("importexpansion.zig").markSeenImportContextDependency;
const nextImportSourceCacheTickLocked = @import("importexpansion.zig").nextImportSourceCacheTickLocked;
const recordLayoutVersion = @import("renderwithtokenreplacements.zig").recordLayoutVersion;
const storeImportSourceCacheEntry = @import("appendexpandedimportcachehit.zig").storeImportSourceCacheEntry;
const importexpansion = @import("importexpansion.zig");


pub fn cloneRemappedInstruction(
    allocator: std.mem.Allocator,
    owned_text: *std.array_list.Managed([]const u8),
    source: Instruction,
    source_symbols: *const SymbolTable,
    target_symbols: *const SymbolTable,
    remap: []const u32,
    source_line_offset: u32,
    expanded_line_offset: u32,
) !Instruction {
    const owned_start = owned_text.items.len;
    errdefer {
        while (owned_text.items.len > owned_start) {
            const text = owned_text.pop().?;
            allocator.free(text);
        }
    }

    var out = common_instruction.makeInstruction(
        source.kind,
        try std.math.add(u32, source.source_line, source_line_offset),
        try std.math.add(u32, source.expanded_line, expanded_line_offset),
        null,
        try cloneRemappedSymbolText(allocator, owned_text, source.raw_text, source_symbols, target_symbols, remap),
    );
    errdefer {
        if (out.package_identity) |identity| allocator.free(identity);
        if (out.upstream_loc) |loc| allocator.free(loc.file);
        if (out.native_reg_names.len != 0) allocator.free(out.native_reg_names);
    }

    if (source.package_identity) |identity| {
        out.package_identity = try allocator.dupe(u8, identity);
    }
    out.package_source_sha256 = source.package_source_sha256;
    if (source.upstream_loc) |loc| {
        out.upstream_loc = .{
            .file = try allocator.dupe(u8, loc.file),
            .line = loc.line,
            .col = loc.col,
        };
    }
    out.op_kind = source.op_kind;
    out.atomic_value_ty = source.atomic_value_ty;
    out.atomic_ordering = source.atomic_ordering;
    out.atomic_second_ordering = source.atomic_second_ordering;
    out.atomic_rmw_op = source.atomic_rmw_op;
    if (source.atomic_expected_text) |text| {
        out.atomic_expected_text = try cloneRemappedSymbolText(allocator, owned_text, text, source_symbols, target_symbols, remap);
    }
    if (source.atomic_new_text) |text| {
        out.atomic_new_text = try cloneRemappedSymbolText(allocator, owned_text, text, source_symbols, target_symbols, remap);
    }

    var cloned_native_text: ?[]const u8 = null;
    for (&out.operands, source.operands) |*dst, operand| {
        dst.* = try cloneRemappedOperand(allocator, owned_text, operand, source_symbols, target_symbols, remap);
        switch (dst.*) {
            .native_text => |text| cloned_native_text = text,
            else => {},
        }
    }
    out.native_reg_names = try cloneNativeRegNames(allocator, owned_text, source, cloned_native_text);
    return out;
}

fn appendOwnedSource(out: *std.array_list.Managed(u8), source: []const u8) !void {
    if (source.len == 0) return;
    const needs_newline = source[source.len - 1] != '\n';
    try out.ensureUnusedCapacity(source.len + @intFromBool(needs_newline));
    try out.appendSlice(source);
    if (needs_newline) try out.append('\n');
}

pub fn parseImportPath(line: []const u8) ?[]const u8 {
    const classified = classifier.classifyLine(line);
    if (classified.kind != .import_decl) return null;
    return classified.parts[0];
}

pub fn readImportFile(
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    import_path: []const u8,
    resolve_ctx: ?ResolveContext,
) !pkg_resolver.ResolvedImport {
    const use_cache = try isImportCacheCandidate(allocator, base_dir, import_path, resolve_ctx);
    if (!use_cache) {
        const deps = if (resolve_ctx) |ctx| ctx.dependencies else &.{};
        var options: pkg_resolver.ResolveOptions = .{};
        if (resolve_ctx) |ctx| options = ctx.options;
        const resolved = try pkg_resolver.resolveImport(allocator, deps, base_dir, import_path, options);
        return try materializeImportedSource(allocator, resolved, resolve_ctx);
    }

    const cache_key = try buildImportSourceCacheKey(allocator, base_dir, import_path, resolve_ctx);
    defer allocator.free(cache_key);

    while (!importexpansion.import_source_cache_mutex.tryLock()) { std.Thread.yield() catch {}; }
    if (importexpansion.import_source_cache) |*cache| {
        if (cache.getPtr(cache_key)) |cached| {
            if (cachedImportStillValid(cached.*)) {
                const max_entries = importSourceCacheMaxEntries();
                cached.last_used_tick = nextImportSourceCacheTickLocked();
                const cloned = cloneCachedImport(allocator, cached.*, max_entries == null) catch |err| {
                    importexpansion.import_source_cache_mutex.unlock();
                    return err;
                };
                importexpansion.import_source_cache_mutex.unlock();
                return cloned;
            }
            if (cache.fetchRemove(cache_key)) |removed| {
                std.heap.page_allocator.free(removed.key);
                // Default cache hits borrow source slices, so invalidated source buffers stay process-live.
                freeImportSourceCacheEntry(removed.value, false);
            }
        }
    }
    importexpansion.import_source_cache_mutex.unlock();

    const deps = if (resolve_ctx) |ctx| ctx.dependencies else &.{};
    var options: pkg_resolver.ResolveOptions = .{};
    if (resolve_ctx) |ctx| options = ctx.options;
    const resolved = try pkg_resolver.resolveImport(allocator, deps, base_dir, import_path, options);
    const materialized = try materializeImportedSource(allocator, resolved, resolve_ctx);
    storeImportSourceCacheEntry(cache_key, materialized) catch |err| {
        // Import source caching is an optimization; resolution already succeeded and remains authoritative.
        _ = @errorName(err);
    };
    return materialized;
}

/// DEF-WASM32-STD-HYBRID-INPROCESS-FLATTEN / client-expansion materialization
/// (fork H, H1 form): imported sources that carry target-conditional
/// declaration blocks (`// @target-begin` sections, today sa_std/core/mem.sa
/// and sa_std/alloc/growvec.sa) are reduced to the single variant for the
/// compilation target before the flattener splices them in. Without this,
/// both variants enter the instruction stream and the verifier rejects the
/// module with FallthroughForbidden (the non-selected variant's body blocks
/// do not terminate the way the selected one's do). The materialization spec
/// is shared with the build-time sa_std mirror (tools/decl_materialize.zig
/// implements the same spec for the build graph); errors are loud.
fn materializeImportedSource(
    allocator: std.mem.Allocator,
    resolved: pkg_resolver.ResolvedImport,
    resolve_ctx: ?ResolveContext,
) !pkg_resolver.ResolvedImport {
    if (!decl_materialize.containsTargetBlocks(resolved.source)) return resolved;
    var result = resolved;
    const materialized = try decl_materialize.materialize(allocator, resolved.source, declTargetFor(resolve_ctx));
    if (result.mapped) |mapped| {
        if (builtin.os.tag == .windows) {
            std.heap.page_allocator.free(mapped);
        } else {
            std.posix.munmap(mapped);
        }
        result.mapped = null;
    } else if (result.owned_source) |owned| {
        allocator.free(owned);
    }
    const owned = try allocator.dupe(u8, materialized);
    allocator.free(materialized);
    result.source = owned;
    result.owned_source = owned;
    result.source_sha256 = null;
    return result;
}

/// The target imported sources are materialized for. The host binary is
/// always a native build, and the flattener runs before any per-verb backend
/// dispatch, so this is the host target: wasm32 only when the host itself is
/// compiled for wasm32.
fn declTarget() decl_materialize.DeclTarget {
    return if (builtin.cpu.arch == .wasm32) .wasm32 else .native;
}

/// The materialization target a load must use: the consumer-supplied
/// program target when the resolve context carries one, otherwise the
/// host target (the only reading available at the sci-internal call
/// sites, which have no program target — consult-forkh judgment A).
/// An explicitly supplied target is never silently replaced by the
/// host reading.
pub fn declTargetFor(resolve_ctx: ?ResolveContext) decl_materialize.DeclTarget {
    if (resolve_ctx) |ctx| {
        if (ctx.decl_target) |target| return target;
    }
    return declTarget();
}

/// Root-source counterpart of materializeImportedSource: same spec, same
/// target, applied to the compilation root handed to flattenInternal.
pub fn materializeRootSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    resolve_ctx: ?ResolveContext,
) !struct { source: []const u8, owned: ?[]u8 } {
    if (!decl_materialize.containsTargetBlocks(source)) return .{ .source = source, .owned = null };
    const materialized = try decl_materialize.materialize(allocator, source, declTargetFor(resolve_ctx));
    const owned = try allocator.dupe(u8, materialized);
    allocator.free(materialized);
    return .{ .source = owned, .owned = owned };
}

pub fn readImportSourceFile(
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    import_path: []const u8,
    resolve_ctx: ?ResolveContext,
) !pkg_resolver.ResolvedImport {
    return try readImportFile(allocator, base_dir, import_path, resolve_ctx);
}

fn pathJoin(allocator: std.mem.Allocator, parts: []const []const u8) ![]u8 {
    return try std.fs.path.join(allocator, parts);
}

fn pathStem(path: []const u8) []const u8 {
    const base = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse return base;
    return base[0..dot];
}

pub fn packageNamespacePrefix(allocator: std.mem.Allocator, package_identity: []const u8) ![]u8 {
    const trimmed = std.mem.trim(u8, package_identity, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidPath;

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try out.appendSlice("pkg_");

    for (trimmed) |c| {
        switch (c) {
            'a'...'z', 'A'...'Z', '0'...'9' => try out.append(c),
            '_' => try out.appendSlice("_us_"),
            '.' => try out.appendSlice("_dot_"),
            '/' => try out.appendSlice("_slash_"),
            '-' => try out.appendSlice("_dash_"),
            ':' => try out.appendSlice("_colon_"),
            '@' => try out.appendSlice("_at_"),
            '+' => try out.appendSlice("_plus_"),
            '~' => try out.appendSlice("_tilde_"),
            else => {
                try out.appendSlice("_x");
                var hex_c_buf: [2]u8 = undefined;
                const hex_c = std.fmt.bufPrint(&hex_c_buf, "{X:0>2}", .{c}) catch unreachable;
                try out.appendSlice(hex_c);
                try out.append('_');
            },
        }
    }

    return try out.toOwnedSlice();
}

pub fn rememberPackageIdentity(
    allocator: std.mem.Allocator,
    seen_package_identities: *std.StringHashMap(void),
    package_identity: []const u8,
) ![]const u8 {
    if (seen_package_identities.getKeyPtr(package_identity)) |key_ptr| return key_ptr.*;

    const copy = try allocator.dupe(u8, package_identity);
    errdefer allocator.free(copy);
    try seen_package_identities.put(copy, {});
    return copy;
}

fn containsText(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn rewritePackageLayoutExpr(
    allocator: std.mem.Allocator,
    expr: []const u8,
    prefix: []const u8,
    local_defs: []const []const u8,
) ![]const u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var idx: usize = 0;
    while (idx < expr.len) {
        if (std.ascii.isAlphabetic(expr[idx]) or expr[idx] == '_') {
            const start = idx;
            idx += 1;
            while (idx < expr.len and (std.ascii.isAlphanumeric(expr[idx]) or expr[idx] == '_' or expr[idx] == '.')) : (idx += 1) {}
            const token = expr[start..idx];
            if (containsText(local_defs, token)) {
                try out.appendSlice(prefix);
                try out.append('.');
                try out.appendSlice(token);
            } else {
                try out.appendSlice(token);
            }
            continue;
        }
        try out.append(expr[idx]);
        idx += 1;
    }

    return try out.toOwnedSlice();
}

pub fn rewritePackageLayoutSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    package_identity: []const u8,
) ![]u8 {
    const prefix = try packageNamespacePrefix(allocator, package_identity);
    defer allocator.free(prefix);

    var local_defs = std.array_list.Managed([]const u8).init(allocator);
    defer local_defs.deinit();

    var collector = std.mem.splitScalar(u8, source, '\n');
    while (collector.next()) |raw_line| {
        const classified = classifier.classifyLine(raw_line);
        if (classified.kind == .def) {
            try local_defs.append(classified.parts[0]);
        }
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var iterator = std.mem.splitScalar(u8, source, '\n');
    var first_line = true;
    while (iterator.next()) |raw_line| {
        if (!first_line) try out.append('\n');
        first_line = false;

        const classified = classifier.classifyLine(raw_line);
        switch (classified.kind) {
            .def => {
                const rewritten_rhs = try rewritePackageLayoutExpr(allocator, classified.parts[1], prefix, local_defs.items);
                defer allocator.free(rewritten_rhs);
                try out.appendSlice("#def ");
                try out.appendSlice(prefix);
                try out.append('.');
                try out.appendSlice(classified.parts[0]);
                try out.appendSlice(" = ");
                try out.appendSlice(rewritten_rhs);
            },
            else => try out.appendSlice(raw_line),
        }
    }

    if (source.len != 0 and source[source.len - 1] == '\n') {
        try out.append('\n');
    }

    return try out.toOwnedSlice();
}

pub fn injectImportedFile(
    allocator: std.mem.Allocator,
    out: *std.array_list.Managed(u8),
    line_package_identities: *std.array_list.Managed(?[]const u8),
    line_package_hashes: *std.array_list.Managed(?[32]u8),
    line_origin_paths: *std.array_list.Managed(?[]const u8),
    line_origin_lines: *std.array_list.Managed(u32),
    imported: *pkg_resolver.ResolvedImport,
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
) anyerror!void {
    const entry_path = imported.entry_path;
    if (!std.mem.endsWith(u8, entry_path, ".sa")) return;

    const effective_package_identity = if (imported.package_identity) |identity| blk: {
        break :blk try rememberPackageIdentity(allocator, seen_package_identities, identity);
    } else if (!imported.is_global) blk: {
        if (current_package_identity) |identity| {
            break :blk try rememberPackageIdentity(allocator, seen_package_identities, identity);
        }
        break :blk null;
    } else null;

    const import_dir = std.fs.path.dirname(entry_path) orelse ".";
    const stem = pathStem(entry_path);
    const iface_name = try std.fmt.allocPrint(allocator, "{s}.sai", .{stem});
    defer allocator.free(iface_name);
    const layout_name = try std.fmt.allocPrint(allocator, "{s}.sal", .{stem});
    defer allocator.free(layout_name);

    const injected_root = struct {
        fn run(
            allocator2: std.mem.Allocator,
            out2: *std.array_list.Managed(u8),
            line_package_identities2: *std.array_list.Managed(?[]const u8),
            line_package_hashes2: *std.array_list.Managed(?[32]u8),
            line_origin_paths2: *std.array_list.Managed(?[]const u8),
            line_origin_lines2: *std.array_list.Managed(u32),
            base_dir: []const u8,
            file_name: []const u8,
            active_paths2: *std.StringHashMap(void),
            seen_paths2: *std.StringHashMap(void),
            seen_package_identities2: *std.StringHashMap(void),
            owned_paths2: *std.array_list.Managed([]u8),
            layout_versions2: *std.array_list.Managed(LayoutVersion),
            error_ctx2: ?*ErrorContext,
            current_package_identity2: ?[]const u8,
            current_package_hash2: ?[32]u8,
            resolve_ctx2: ?ResolveContext,
            cache_dependency2: ?*ExpandedImportCacheDependency,
        ) anyerror!void {
            var injected = try readImportFile(allocator2, base_dir, file_name, resolve_ctx2);
            defer injected.deinit(allocator2);
            if (active_paths2.contains(injected.entry_path) or seen_paths2.contains(injected.entry_path)) {
                markSeenImportContextDependency(cache_dependency2, owned_paths2.items, injected.entry_path);
                return;
            }
            owned_paths2.append(injected.entry_path) catch |err| {
                injected.deinit(allocator2);
                return err;
            };
            injected.entry_path_owned = false;
            try seen_paths2.put(injected.entry_path, {});
            try active_paths2.put(injected.entry_path, {});
            defer _ = active_paths2.remove(injected.entry_path);

            const effective_child_package_identity = if (injected.package_identity) |identity|
                identity
            else if (!injected.is_global)
                current_package_identity2
            else
                null;
            const is_layout_file = std.mem.endsWith(u8, injected.entry_path, ".sal");
            var rewritten_source: ?[]u8 = null;
            defer if (rewritten_source) |rewritten| allocator2.free(rewritten);
            const expanded_source = if (is_layout_file) blk: {
                if (effective_child_package_identity) |identity| {
                    const rewritten = try rewritePackageLayoutSource(allocator2, injected.source, identity);
                    rewritten_source = rewritten;
                    break :blk rewritten;
                }
                break :blk injected.source;
            } else injected.source;

            if (is_layout_file) {
                try recordLayoutVersion(allocator2, layout_versions2, injected.entry_path, injected.source);
            }
            const injected_dir = std.fs.path.dirname(injected.entry_path) orelse ".";
            try expandImportsInto(
                allocator2,
                out2,
                line_package_identities2,
                line_package_hashes2,
                line_origin_paths2,
                line_origin_lines2,
                expanded_source,
                injected_dir,
                injected.entry_path,
                false,
                active_paths2,
                seen_paths2,
                seen_package_identities2,
                owned_paths2,
                layout_versions2,
                error_ctx2,
                effective_child_package_identity,
                current_package_hash2,
                resolve_ctx2,
                cache_dependency2,
            );
        }
    }.run;

    const iface_path = try pathJoin(allocator, &.{ import_dir, iface_name });
    defer allocator.free(iface_path);
    if (sio.cwd().access(iface_path, .{})) |_| {
        try injected_root(
            allocator,
            out,
            line_package_identities,
            line_package_hashes,
            line_origin_paths,
            line_origin_lines,
            import_dir,
            iface_name,
            active_paths,
            seen_paths,
            seen_package_identities,
            owned_paths,
            layout_versions,
            error_ctx,
            effective_package_identity,
            current_package_hash,
            resolve_ctx,
            cache_dependency,
        );
    } else |_| {}

    const layout_path = try pathJoin(allocator, &.{ import_dir, layout_name });
    defer allocator.free(layout_path);
    if (sio.cwd().access(layout_path, .{})) |_| {
        try injected_root(
            allocator,
            out,
            line_package_identities,
            line_package_hashes,
            line_origin_paths,
            line_origin_lines,
            import_dir,
            layout_name,
            active_paths,
            seen_paths,
            seen_package_identities,
            owned_paths,
            layout_versions,
            error_ctx,
            effective_package_identity,
            current_package_hash,
            resolve_ctx,
            cache_dependency,
        );
    } else |_| {}
}

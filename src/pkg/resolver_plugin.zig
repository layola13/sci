const std = @import("std");
const ResolveError = @import("resolver.zig").ResolveError;
const ResolveOptions = @import("resolver.zig").ResolveOptions;
const ResolvedImport = @import("resolver.zig").ResolvedImport;
const computeResolvedSourceHash = @import("resolver.zig").computeResolvedSourceHash;
const isPluginInterfaceImportPath = @import("resolver.zig").isPluginInterfaceImportPath;
const pathJoin = @import("resolver.zig").pathJoin;
const pathWithinRoot = @import("resolver.zig").pathWithinRoot;
const readFileAlloc = @import("resolver.zig").readFileAlloc;
const sio = @import("resolver.zig").sio;

pub fn resolveFromPluginImportRoot(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    import_path: []const u8,
    max_bytes: usize,
) ResolveError!?ResolvedImport {
    const canonical_root = sio.cwd().realpathAlloc(allocator, root_dir) catch return null;
    errdefer allocator.free(canonical_root);

    const candidate = try pathJoin(allocator, &.{ canonical_root, import_path });
    defer allocator.free(candidate);

    const canonical_entry = sio.cwd().realpathAlloc(allocator, candidate) catch {
        allocator.free(canonical_root);
        return null;
    };
    errdefer allocator.free(canonical_entry);
    if (!pathWithinRoot(canonical_root, canonical_entry)) return error.InvalidImportPath;

    const source = try readFileAlloc(allocator, canonical_entry, max_bytes);
    errdefer allocator.free(source);
    const source_hash = try computeResolvedSourceHash(allocator, canonical_entry, canonical_root, source);

    return .{
        .entry_path = canonical_entry,
        .root_dir = canonical_root,
        .source = source,
        .owned_source = source,
        .source_sha256 = source_hash,
        .is_global = true,
    };
}

pub fn pluginNameForImportRoot(root_dir: []const u8) ?[]const u8 {
    var parts = std.mem.tokenizeAny(u8, root_dir, "/\\");
    var prev: ?[]const u8 = null;
    var prev2: ?[]const u8 = null;
    while (parts.next()) |part| {
        if (std.mem.eql(u8, part, "sa")) {
            if (prev) |p1| {
                if (std.mem.eql(u8, p1, "current")) {
                    if (prev2) |name| {
                        if (name.len != 0) return name;
                    }
                }
            }
        }
        prev2 = prev;
        prev = part;
    }
    return null;
}

pub fn pluginImportRootHasImport(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    import_path: []const u8,
) bool {
    const canonical_root = sio.cwd().realpathAlloc(allocator, root_dir) catch return false;
    defer allocator.free(canonical_root);
    const candidate = pathJoin(allocator, &.{ canonical_root, import_path }) catch return false;
    defer allocator.free(candidate);
    const canonical_entry = sio.cwd().realpathAlloc(allocator, candidate) catch return false;
    defer allocator.free(canonical_entry);
    return pathWithinRoot(canonical_root, canonical_entry);
}

pub fn noteAmbiguousPluginImport(
    allocator: std.mem.Allocator,
    import_path: []const u8,
    options: ResolveOptions,
    winner_root: []const u8,
    later_roots: []const []const u8,
) void {
    const callback = options.diagnostics orelse return;
    var names = std.array_list.Managed([]const u8).init(allocator);
    defer names.deinit();
    for (later_roots) |root_dir| {
        if (pluginImportRootHasImport(allocator, root_dir, import_path)) {
            names.append(pluginNameForImportRoot(root_dir) orelse root_dir) catch return;
        }
    }
    if (names.items.len == 0) return;
    const joined = std.mem.join(allocator, ", ", names.items) catch return;
    defer allocator.free(joined);
    const winner = pluginNameForImportRoot(winner_root) orelse winner_root;
    const message = std.fmt.allocPrint(
        allocator,
        "ambiguous plugin import '{s}': provided by multiple plugins; using {s}, shadowed: {s}. Qualify the import as plugin/<plugin-name>/{s} to choose the provider explicitly.",
        .{ import_path, winner, joined, import_path },
    ) catch return;
    defer allocator.free(message);
    callback(options.diagnostics_ctx, message);
}

pub fn resolveFromPluginImportRoots(
    allocator: std.mem.Allocator,
    import_path: []const u8,
    options: ResolveOptions,
) ResolveError!?ResolvedImport {
    if (!isPluginInterfaceImportPath(import_path)) return null;
    // Qualified plugin import: plugin/<name>/<relative interface path>
    // resolves inside that one plugin's import root only. A qualified
    // import never falls through to another plugin or to the bare-name
    // search: when the named plugin is absent or does not ship the
    // file, the import is explicitly unresolved.
    if (std.mem.startsWith(u8, import_path, "plugin/")) {
        const rest = import_path["plugin/".len..];
        const slash = std.mem.indexOfScalar(u8, rest, '/') orelse return error.PackageNotResolved;
        const wanted = rest[0..slash];
        const rel = rest[slash + 1 ..];
        if (wanted.len == 0 or !isPluginInterfaceImportPath(rel)) return error.PackageNotResolved;
        for (options.plugin_import_roots) |root_dir| {
            const name = pluginNameForImportRoot(root_dir) orelse continue;
            if (!std.mem.eql(u8, name, wanted)) continue;
            if (try resolveFromPluginImportRoot(allocator, root_dir, rel, options.max_local_file_bytes)) |resolved| {
                return resolved;
            }
            return error.PackageNotResolved;
        }
        return error.PackageNotResolved;
    }
    for (options.plugin_import_roots, 0..) |root_dir, index| {
        if (try resolveFromPluginImportRoot(allocator, root_dir, import_path, options.max_local_file_bytes)) |resolved| {
            noteAmbiguousPluginImport(allocator, import_path, options, root_dir, options.plugin_import_roots[index + 1 ..]);
            return resolved;
        }
    }
    return null;
}

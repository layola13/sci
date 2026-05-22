
fn resolveRootedImport(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    import_rel: []const u8,
    max_bytes: usize,
) ResolveError!?ResolvedImport {
    const candidate = try std.fs.path.join(allocator, &.{ root_path, import_rel });
    defer allocator.free(candidate);

    const canonical_entry = std.fs.cwd().realpathAlloc(allocator, candidate) catch return null;
    errdefer allocator.free(canonical_entry);

    const canonical_root = std.fs.cwd().realpathAlloc(allocator, root_path) catch return null;
    errdefer allocator.free(canonical_root);

    const source = std.fs.cwd().readFileAlloc(allocator, canonical_entry, max_bytes) catch return null;
    errdefer allocator.free(source);

    const source_hash = try computeResolvedSourceHash(allocator, canonical_entry, canonical_root, source);

    var resolved: ResolvedImport = .{
        .entry_path = canonical_entry,
        .root_dir = canonical_root,
        .source = source,
        .owned_source = source,
        .source_sha256 = source_hash,
        .is_global = true,
    };
    
    resolved.package_identity = try allocator.dupe(u8, import_rel);

    return resolved;
}

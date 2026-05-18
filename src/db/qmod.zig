const std = @import("std");

pub const ParseError = error{
    OutOfMemory,
    InvalidFormat,
    InvalidSha256,
};

pub const GrantKind = enum {
    db_read,
    db_write,
    db_alloc_blob,
    db_atomic_cursor,
};

pub const Grant = struct {
    kind: GrantKind,
    target: []const u8,
};

pub const Qmod = struct {
    allocator: std.mem.Allocator,
    project_root: []const u8,
    source_path: []const u8,
    source: []const u8,
    stripped_source: []const u8,
    hash: [32]u8,
    imports: [][]const u8,
    grants: []Grant,

    pub fn deinit(self: *Qmod) void {
        self.allocator.free(self.project_root);
        self.allocator.free(self.source_path);
        self.allocator.free(self.source);
        self.allocator.free(self.stripped_source);
        for (self.imports) |item| self.allocator.free(item);
        self.allocator.free(self.imports);
        for (self.grants) |grant| self.allocator.free(grant.target);
        self.allocator.free(self.grants);
        self.* = undefined;
    }
};

pub const LoadedQmod = Qmod;

pub const RegistryEntry = struct {
    hash: [32]u8,
    qmod_path: []const u8,
    iface_path: []const u8,
    source_path: []const u8,
    source_sha256: [32]u8,
    grants: []Grant,

    pub fn deinit(self: *RegistryEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.qmod_path);
        allocator.free(self.iface_path);
        allocator.free(self.source_path);
        for (self.grants) |grant| allocator.free(grant.target);
        allocator.free(self.grants);
        self.* = undefined;
    }
};

pub const Registry = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(RegistryEntry),

    pub fn init(allocator: std.mem.Allocator) Registry {
        return .{
            .allocator = allocator,
            .entries = std.ArrayList(RegistryEntry).init(allocator),
        };
    }

    pub fn deinit(self: *Registry) void {
        for (self.entries.items) |*entry| entry.deinit(self.allocator);
        self.entries.deinit();
        self.* = undefined;
    }

    fn hashEq(lhs: [32]u8, rhs: [32]u8) bool {
        return std.mem.eql(u8, lhs[0..], rhs[0..]);
    }

    pub fn find(self: *const Registry, hash: [32]u8) ?RegistryEntry {
        for (self.entries.items) |entry| {
            if (hashEq(entry.hash, hash)) return entry;
        }
        return null;
    }

    pub fn add(self: *Registry, entry: RegistryEntry) !void {
        try self.entries.append(entry);
    }
};

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}

fn stripInlineComment(line: []const u8) []const u8 {
    var in_string = false;
    var escape = false;
    var i: usize = 0;
    while (i + 1 < line.len) : (i += 1) {
        const c = line[i];
        if (in_string) {
            if (escape) {
                escape = false;
                continue;
            }
            switch (c) {
                '\\' => escape = true,
                '"' => in_string = false,
                else => {},
            }
            continue;
        }
        switch (c) {
            '"' => in_string = true,
            '/' => {
                if (line[i + 1] == '/') {
                    const prev = if (i == 0) ' ' else line[i - 1];
                    if (i == 0 or std.ascii.isWhitespace(prev)) return line[0..i];
                }
            },
            else => {},
        }
    }
    return line;
}

fn cleanLine(raw: []const u8) []const u8 {
    return trim(stripInlineComment(raw));
}

fn isIdentStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}

fn isIdentChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

fn isHexDigit(c: u8) bool {
    return std.ascii.isHex(c);
}

fn hashSource(source: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

pub fn parseSha256Hex(text: []const u8) ParseError![32]u8 {
    const trimmed = trim(text);
    const body = if (std.mem.startsWith(u8, trimmed, "sha256:")) trimmed["sha256:".len..] else trimmed;
    if (body.len != 64) return ParseError.InvalidSha256;
    for (body) |c| {
        if (!isHexDigit(c)) return ParseError.InvalidSha256;
    }
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(bytes[0..], body) catch return ParseError.InvalidSha256;
    return bytes;
}

fn sha256Text(writer: anytype, hash: [32]u8) !void {
    const encoded = std.fmt.bytesToHex(hash, .lower);
    try writer.print("{s}", .{encoded[0..]});
}

fn appendLine(out: *std.ArrayList(u8), line: []const u8) !void {
    try out.appendSlice(line);
    try out.append('\n');
}

fn parseImportPath(line: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, "@import")) return null;
    const after = std.mem.trimLeft(u8, line["@import".len..], " \t");
    if (after.len < 2 or after[0] != '"') return null;
    const end_quote = std.mem.indexOfScalarPos(u8, after, 1, '"') orelse return null;
    const path = std.mem.trim(u8, after[1..end_quote], " \t");
    if (path.len == 0) return null;
    if (std.mem.trim(u8, after[end_quote + 1 ..], " \t").len != 0) return null;
    return path;
}

fn appendUniqueString(list: *std.ArrayList([]const u8), allocator: std.mem.Allocator, value: []const u8) !void {
    for (list.items) |item| {
        if (std.mem.eql(u8, item, value)) return;
    }
    try list.append(try allocator.dupe(u8, value));
}

fn parseGrantToken(token: []const u8) ?Grant {
    const trimmed = trim(token);
    if (trimmed.len == 0) return null;
    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return null;
    const kind_text = trim(trimmed[0..colon]);
    const target_text = trim(trimmed[colon + 1 ..]);
    if (target_text.len == 0) return null;
    const kind = if (std.mem.eql(u8, kind_text, "db_read")) GrantKind.db_read else if (std.mem.eql(u8, kind_text, "db_write")) GrantKind.db_write else if (std.mem.eql(u8, kind_text, "db_alloc_blob")) GrantKind.db_alloc_blob else if (std.mem.eql(u8, kind_text, "db_atomic_cursor")) GrantKind.db_atomic_cursor else return null;
    return .{ .kind = kind, .target = target_text };
}

fn parseGrantList(allocator: std.mem.Allocator, text: []const u8) ParseError![]Grant {
    const trimmed = trim(text);
    var list = std.ArrayList(Grant).init(allocator);
    errdefer {
        for (list.items) |grant| allocator.free(grant.target);
        list.deinit();
    }
    if (trimmed.len == 0) return try list.toOwnedSlice();
    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |fragment| {
        const grant = parseGrantToken(fragment) orelse return ParseError.InvalidFormat;
        try list.append(.{
            .kind = grant.kind,
            .target = try allocator.dupe(u8, grant.target),
        });
    }
    return try list.toOwnedSlice();
}

fn parseGrantsClause(allocator: std.mem.Allocator, text: []const u8) ParseError![]Grant {
    const trimmed = trim(text);
    if (!std.mem.startsWith(u8, trimmed, "grants")) return ParseError.InvalidFormat;
    const after = trim(trimmed["grants".len..]);
    if (after.len < 2 or after[0] != '[' or after[after.len - 1] != ']') return ParseError.InvalidFormat;
    return try parseGrantList(allocator, after[1 .. after.len - 1]);
}

pub fn parseGrantsText(allocator: std.mem.Allocator, text: []const u8) ![]Grant {
    return try parseGrantsClause(allocator, text);
}

fn parseMetadataLine(line: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, prefix)) return null;
    return trim(line[prefix.len..]);
}

fn validateGrantTargets(imports: []const []const u8, grants: []const Grant) ParseError!void {
    var schema_tables = std.ArrayList([]const u8).init(std.heap.page_allocator);
    defer schema_tables.deinit();
    for (imports) |path| {
        if (!std.mem.endsWith(u8, path, ".sadb-schema")) continue;
        const base = std.fs.path.basename(path);
        const table = base[0 .. base.len - ".sadb-schema".len];
        try schema_tables.append(table);
    }
    if (schema_tables.items.len == 0) return;
    for (grants) |grant| {
        switch (grant.kind) {
            .db_read, .db_write, .db_atomic_cursor => {
                var matched = false;
                for (schema_tables.items) |table| {
                    if (std.mem.eql(u8, grant.target, table)) {
                        matched = true;
                        break;
                    }
                }
                if (!matched) return ParseError.InvalidFormat;
            },
            .db_alloc_blob => {},
        }
    }
}

fn writeMetadata(writer: anytype, q: Qmod, header: []const u8) !void {
    try writer.writeAll(header);
    try writer.writeByte('\n');
    try writer.writeAll("hash=");
    try sha256Text(writer, q.hash);
    try writer.writeByte('\n');
    try writer.writeAll("source_path=");
    try writer.writeAll(q.source_path);
    try writer.writeByte('\n');
    try writer.writeAll("project_root=");
    try writer.writeAll(q.project_root);
    try writer.writeByte('\n');
    try writer.writeAll("imports=");
    for (q.imports, 0..) |item, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.writeAll(item);
    }
    try writer.writeByte('\n');
    try writer.writeAll("grants=");
    for (q.grants, 0..) |grant, idx| {
        if (idx != 0) try writer.writeByte(',');
        try writer.print("{s}:{s}", .{
            switch (grant.kind) {
                .db_read => "db_read",
                .db_write => "db_write",
                .db_alloc_blob => "db_alloc_blob",
                .db_atomic_cursor => "db_atomic_cursor",
            },
            grant.target,
        });
    }
    try writer.writeByte('\n');
    try writer.writeAll("---\n");
    try writer.writeAll(q.stripped_source);
}

pub fn compileFromSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_path: []const u8,
    project_root: []const u8,
) ParseError!Qmod {
    const hash = hashSource(source);
    const source_copy = try allocator.dupe(u8, source);
    errdefer allocator.free(source_copy);
    const path_copy = try allocator.dupe(u8, source_path);
    errdefer allocator.free(path_copy);
    const root_copy = try allocator.dupe(u8, project_root);
    errdefer allocator.free(root_copy);

    var stripped = std.ArrayList(u8).init(allocator);
    errdefer stripped.deinit();
    var imports = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (imports.items) |item| allocator.free(item);
        imports.deinit();
    }
    var grants: []Grant = try allocator.alloc(Grant, 0);
    errdefer allocator.free(grants);

    var saw_grants = false;
    var line_it = std.mem.splitScalar(u8, source_copy, '\n');
    while (line_it.next()) |raw_line| {
        const line = cleanLine(raw_line);
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) {
            try appendLine(&stripped, raw_line);
            continue;
        }
        if (parseImportPath(line)) |import_path| {
            try appendUniqueString(&imports, allocator, import_path);
            try appendLine(&stripped, raw_line);
            continue;
        }
        if (std.mem.startsWith(u8, line, "grants")) {
            if (saw_grants) return ParseError.InvalidFormat;
            saw_grants = true;
            grants = try parseGrantsClause(allocator, line);
            continue;
        }
        try appendLine(&stripped, raw_line);
    }

    try validateGrantTargets(imports.items, grants);

    return .{
        .allocator = allocator,
        .project_root = root_copy,
        .source_path = path_copy,
        .source = source_copy,
        .stripped_source = try stripped.toOwnedSlice(),
        .hash = hash,
        .imports = try imports.toOwnedSlice(),
        .grants = grants,
    };
}

fn parseQueryArtifact(allocator: std.mem.Allocator, source: []const u8) ParseError!LoadedQmod {
    var line_it = std.mem.splitScalar(u8, source, '\n');
    const header = line_it.next() orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, trim(header), "SAQ1") and !std.mem.eql(u8, trim(header), "QIF1")) return ParseError.InvalidFormat;

    var hash: ?[32]u8 = null;
    var source_path: ?[]const u8 = null;
    var project_root: ?[]const u8 = null;
    var imports = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (imports.items) |item| allocator.free(item);
        imports.deinit();
    }
    var grants: []Grant = try allocator.alloc(Grant, 0);
    errdefer allocator.free(grants);
    var body_start: usize = source.len;

    var offset: usize = header.len + 1;
    while (line_it.next()) |raw_line| {
        if (std.mem.eql(u8, raw_line, "---")) {
            body_start = offset + raw_line.len + 1;
            break;
        }
        const line = trim(raw_line);
        if (line.len == 0) {
            offset += raw_line.len + 1;
            continue;
        }
        if (parseMetadataLine(line, "hash=")) |value| {
            hash = try parseSha256Hex(value);
        } else if (parseMetadataLine(line, "source_path=")) |value| {
            source_path = try allocator.dupe(u8, value);
        } else if (parseMetadataLine(line, "project_root=")) |value| {
            project_root = try allocator.dupe(u8, value);
        } else if (parseMetadataLine(line, "imports=")) |value| {
            if (value.len != 0) {
                var it = std.mem.splitScalar(u8, value, ',');
                while (it.next()) |fragment| {
                    const item = trim(fragment);
                    if (item.len == 0) continue;
                    try imports.append(try allocator.dupe(u8, item));
                }
            }
        } else if (parseMetadataLine(line, "grants=")) |value| {
            if (grants.len != 0) return ParseError.InvalidFormat;
            grants = try parseGrantList(allocator, value);
        } else {
            return ParseError.InvalidFormat;
        }
        offset += raw_line.len + 1;
    }

    const hash_value = hash orelse return ParseError.InvalidFormat;
    const source_path_value = source_path orelse return ParseError.InvalidFormat;
    const project_root_value = project_root orelse return ParseError.InvalidFormat;
    if (body_start > source.len) return ParseError.InvalidFormat;
    const stripped_copy = try allocator.dupe(u8, source[body_start..]);
    errdefer allocator.free(stripped_copy);
    return .{
        .allocator = allocator,
        .project_root = project_root_value,
        .source_path = source_path_value,
        .source = try allocator.dupe(u8, source),
        .stripped_source = stripped_copy,
        .hash = hash_value,
        .imports = try imports.toOwnedSlice(),
        .grants = grants,
    };
}

pub fn writeQmod(writer: anytype, q: Qmod) !void {
    try writeMetadata(writer, q, "SAQ1");
}

pub fn writeQueryIface(writer: anytype, q: Qmod) !void {
    try writeMetadata(writer, q, "QIF1");
}

pub fn parseLoadedQmod(allocator: std.mem.Allocator, source: []const u8) ParseError!LoadedQmod {
    return try parseQueryArtifact(allocator, source);
}

pub fn registryDirectory(allocator: std.mem.Allocator, root_dir: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ root_dir, ".sa", "db" });
}

pub fn registryFilePath(allocator: std.mem.Allocator, root_dir: []const u8, hash: [32]u8) ![]u8 {
    const dir = try registryDirectory(allocator, root_dir);
    defer allocator.free(dir);
    const hex = std.fmt.bytesToHex(hash, .lower);
    const filename = try std.fmt.allocPrint(allocator, "{s}.qmod", .{hex[0..]});
    defer allocator.free(filename);
    return try std.fs.path.join(allocator, &.{ dir, filename });
}

pub fn ifaceFilePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    const basename = std.fs.path.basename(source_path);
    const stem = if (std.mem.endsWith(u8, basename, ".query.saasm"))
        basename[0 .. basename.len - ".saasm".len]
    else if (std.mem.endsWith(u8, basename, ".saasm"))
        basename[0 .. basename.len - ".saasm".len]
    else
        basename;
    const filename = try std.fmt.allocPrint(allocator, "{s}.iface", .{stem});
    if (std.fs.path.dirname(source_path)) |dir| {
        defer allocator.free(filename);
        return try std.fs.path.join(allocator, &.{ dir, filename });
    }
    return filename;
}

pub fn qmodFilePath(allocator: std.mem.Allocator, source_path: []const u8, hash: [32]u8) ![]u8 {
    const hex = std.fmt.bytesToHex(hash, .lower);
    const filename = try std.fmt.allocPrint(allocator, "{s}.qmod", .{hex[0..]});
    if (std.fs.path.dirname(source_path)) |dir| {
        defer allocator.free(filename);
        return try std.fs.path.join(allocator, &.{ dir, filename });
    }
    return filename;
}

pub fn findRegistryEntry(registry: *const Registry, hash: [32]u8) ?RegistryEntry {
    return registry.find(hash);
}

test "qmod hashing and grants parsing are stable" {
    const source =
        \\@import "flash_sale.sadb-schema"
        \\grants [db_read:flash_sale, db_write:flash_sale]
        \\@main() -> i32:
        \\L_ENTRY:
        \\return 0
    ;
    var q = try compileFromSource(std.testing.allocator, source, "queries/heavy_users.query.saasm", "queries");
    defer q.deinit();

    try std.testing.expectEqual(@as(usize, 1), q.imports.len);
    try std.testing.expectEqual(@as(usize, 2), q.grants.len);
    try std.testing.expectEqualStrings("queries", q.project_root);
    try std.testing.expectEqualStrings("flash_sale.sadb-schema", q.imports[0]);
    try std.testing.expect(std.mem.eql(u8, q.hash[0..], hashSource(source)[0..]));

    const iface_path = try ifaceFilePath(std.testing.allocator, q.source_path);
    defer std.testing.allocator.free(iface_path);
    try std.testing.expectEqualStrings("queries/heavy_users.query.iface", iface_path);

    const qmod_path = try qmodFilePath(std.testing.allocator, q.source_path, q.hash);
    defer std.testing.allocator.free(qmod_path);
    const hex = std.fmt.bytesToHex(q.hash, .lower);
    const expected_qmod_name = try std.fmt.allocPrint(std.testing.allocator, "{s}.qmod", .{hex[0..]});
    defer std.testing.allocator.free(expected_qmod_name);
    const expected_qmod_path = try std.fs.path.join(std.testing.allocator, &.{ "queries", expected_qmod_name });
    defer std.testing.allocator.free(expected_qmod_path);
    try std.testing.expectEqualStrings(expected_qmod_path, qmod_path);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try writeQueryIface(out.writer(), q);
    var loaded = try parseLoadedQmod(std.testing.allocator, out.items);
    defer loaded.deinit();
    try std.testing.expectEqualStrings(q.source_path, loaded.source_path);
    try std.testing.expectEqualStrings(q.project_root, loaded.project_root);
    try std.testing.expectEqual(@as(usize, q.imports.len), loaded.imports.len);
    try std.testing.expectEqualStrings(q.imports[0], loaded.imports[0]);
    try std.testing.expectEqual(@as(usize, q.grants.len), loaded.grants.len);
    try std.testing.expectEqualStrings(q.grants[0].target, loaded.grants[0].target);
}

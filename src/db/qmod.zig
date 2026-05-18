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
    source_path: []const u8,
    source: []const u8,
    stripped_source: []const u8,
    hash: [32]u8,
    grants: []Grant,

    pub fn deinit(self: *Qmod) void {
        self.allocator.free(self.source_path);
        self.allocator.free(self.source);
        self.allocator.free(self.stripped_source);
        for (self.grants) |grant| {
            self.allocator.free(grant.target);
        }
        self.allocator.free(self.grants);
        self.* = undefined;
    }
};

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

fn isHexDigit(c: u8) bool {
    return std.ascii.isHex(c);
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

fn hashSource(source: []const u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update(source);
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
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

fn parseGrantsClause(allocator: std.mem.Allocator, text: []const u8) ![]Grant {
    const trimmed = trim(text);
    if (!std.mem.startsWith(u8, trimmed, "grants")) return error.InvalidFormat;
    const after = trim(trimmed["grants".len..]);
    if (after.len < 2 or after[0] != '[' or after[after.len - 1] != ']') return error.InvalidFormat;
    const body = trim(after[1 .. after.len - 1]);
    var list = std.ArrayList(Grant).init(allocator);
    errdefer {
        for (list.items) |grant| allocator.free(grant.target);
        list.deinit();
    }
    if (body.len == 0) return try list.toOwnedSlice();
    var it = std.mem.splitScalar(u8, body, ',');
    while (it.next()) |fragment| {
        const grant = parseGrantToken(fragment) orelse return error.InvalidFormat;
        try list.append(.{
            .kind = grant.kind,
            .target = try allocator.dupe(u8, grant.target),
        });
    }
    return try list.toOwnedSlice();
}

pub fn parseGrantsText(allocator: std.mem.Allocator, text: []const u8) ![]Grant {
    return try parseGrantsClause(allocator, text);
}

pub fn compileFromSource(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_path: []const u8,
) ParseError!Qmod {
    const hash = hashSource(source);
    const source_copy = try allocator.dupe(u8, source);
    errdefer allocator.free(source_copy);
    const path_copy = try allocator.dupe(u8, source_path);
    errdefer allocator.free(path_copy);

    const stripped = source_copy;
    var grants: []Grant = try allocator.alloc(Grant, 0);
    errdefer allocator.free(grants);

    var line_it = std.mem.splitScalar(u8, stripped, '\n');
    while (line_it.next()) |raw_line| {
        const line = cleanLine(raw_line);
        if (line.len == 0 or std.mem.startsWith(u8, line, "//")) continue;
        if (std.mem.startsWith(u8, line, "grants")) {
            if (grants.len != 0) return ParseError.InvalidFormat;
            grants = try parseGrantsClause(allocator, line);
        }
    }

    return .{
        .allocator = allocator,
        .source_path = path_copy,
        .source = source_copy,
        .stripped_source = stripped,
        .hash = hash,
        .grants = grants,
    };
}

pub fn writeQmod(writer: anytype, q: Qmod) !void {
    try writer.writeAll("SAQ1\n");
    try writer.writeAll("hash=");
    try sha256Text(writer, q.hash);
    try writer.writeByte('\n');
    try writer.writeAll("source_path=");
    try writer.writeAll(q.source_path);
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

pub fn registryDirectory(allocator: std.mem.Allocator, root_dir: []const u8) ![]u8 {
    return try std.fs.path.join(allocator, &.{ root_dir, ".sa", "db" });
}

pub fn registryFilePath(allocator: std.mem.Allocator, root_dir: []const u8, hash: [32]u8) ![]u8 {
    const dir = try registryDirectory(allocator, root_dir);
    defer allocator.free(dir);
    const hex = try std.fmt.allocPrint(allocator, "{s}", .{std.fmt.bytesToHex(hash, .lower)});
    errdefer allocator.free(hex);
    return try std.fs.path.join(allocator, &.{ dir, hex, ".qmod" });
}

pub fn ifaceFilePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8 {
    const stem = std.fs.path.basename(source_path);
    const base = if (std.mem.endsWith(u8, stem, ".query.saasm")) stem[0 .. stem.len - ".query.saasm".len] else if (std.mem.endsWith(u8, stem, ".saasm")) stem[0 .. stem.len - ".saasm".len] else stem;
    const dir = std.fs.path.dirname(source_path);
    if (dir) |d| {
        return try std.fs.path.join(allocator, &.{ d, base, ".iface" });
    }
    return try std.fs.path.join(allocator, &.{ base, ".iface" });
}

pub fn qmodFilePath(allocator: std.mem.Allocator, source_path: []const u8, hash: [32]u8) ![]u8 {
    const dir = std.fs.path.dirname(source_path);
    const hex = std.fmt.bytesToHex(hash, .lower);
    if (dir) |d| {
        return try std.fs.path.join(allocator, &.{ d, hex[0..], ".qmod" });
    }
    return try std.fs.path.join(allocator, &.{ hex[0..], ".qmod" });
}

pub fn findRegistryEntry(registry: *const Registry, hash: [32]u8) ?RegistryEntry {
    return registry.find(hash);
}

test "qmod hashing and grants parsing are stable" {
    const source =
        \\grants [db_read:flash_sale, db_write:logs, db_atomic_cursor:flash_sale]
        \\@test "x"() -> i32:
        \\L_ENTRY:
        \\return 0
    ;
    var q = try compileFromSource(std.testing.allocator, source, "heavy_users.query.saasm");
    defer q.deinit();

    try std.testing.expectEqual(@as(usize, 3), q.grants.len);
    try std.testing.expectEqualStrings("heavy_users.query.saasm", q.source_path);
    try std.testing.expect(std.mem.eql(u8, q.hash[0..], hashSource(source)[0..]));
}

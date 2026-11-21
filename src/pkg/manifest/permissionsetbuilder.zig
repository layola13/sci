const std = @import("std");
const Capability = @import("mergeworkspacememberset.zig").Capability;
const MirrorRule = @import("mergeworkspacememberset.zig").MirrorRule;
const PackageDecl = @import("mergeworkspacememberset.zig").PackageDecl;
const ParseError = @import("mergeworkspacememberset.zig").ParseError;
const PermissionSet = @import("mergeworkspacememberset.zig").PermissionSet;
const PluginRequireEntry = @import("mergeworkspacememberset.zig").PluginRequireEntry;
const RequireEntry = @import("mergeworkspacememberset.zig").RequireEntry;
const WorkspaceDecl = @import("mergeworkspacememberset.zig").WorkspaceDecl;
const startsWithWord = @import("mergeworkspacememberset.zig").startsWithWord;
const trim = @import("mergeworkspacememberset.zig").trim;


pub fn stripInlineComment(line: []const u8) []const u8 {
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
                    if (i == 0 or std.ascii.isWhitespace(prev)) {
                        return line[0..i];
                    }
                }
            },
            '#' => {
                const prev = if (i == 0) ' ' else line[i - 1];
                if (i == 0 or std.ascii.isWhitespace(prev)) return line[0..i];
            },
            else => {},
        }
    }
    return line;
}

pub fn cleanLine(raw: []const u8) []const u8 {
    return trim(stripInlineComment(raw));
}

pub fn nextToken(text: []const u8, pos: *usize) ?[]const u8 {
    while (pos.* < text.len and std.ascii.isWhitespace(text[pos.*])) : (pos.* += 1) {}
    if (pos.* >= text.len) return null;
    const start = pos.*;
    while (pos.* < text.len and !std.ascii.isWhitespace(text[pos.*])) : (pos.* += 1) {}
    return text[start..pos.*];
}

pub fn splitAssignment(text: []const u8) ?struct { key: []const u8, value: []const u8 } {
    var in_string = false;
    var escape = false;
    for (text, 0..) |c, idx| {
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
            ':', '=' => return .{
                .key = trim(text[0..idx]),
                .value = trim(text[idx + 1 ..]),
            },
            else => {},
        }
    }
    return null;
}

pub fn parseNamedValue(line: []const u8) ?struct { key: []const u8, value: []const u8 } {
    const trimmed = trim(line);
    if (trimmed.len == 0) return null;
    var key_end: usize = 0;
    while (key_end < trimmed.len and !std.ascii.isWhitespace(trimmed[key_end]) and trimmed[key_end] != ':' and trimmed[key_end] != '=') : (key_end += 1) {}
    if (key_end == 0) return null;
    const key = trimmed[0..key_end];
    var value_start = key_end;
    while (value_start < trimmed.len and std.ascii.isWhitespace(trimmed[value_start])) : (value_start += 1) {}
    if (value_start < trimmed.len and (trimmed[value_start] == ':' or trimmed[value_start] == '=')) value_start += 1;
    const value = trim(trimmed[value_start..]);
    if (value.len == 0) return null;
    return .{ .key = key, .value = value };
}

pub fn parseTextValue(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = trim(text);
    if (trimmed.len == 0) return ParseError.InvalidFormat;

    if (trimmed[0] == '"') {
        if (trimmed.len < 2 or trimmed[trimmed.len - 1] != '"') return ParseError.InvalidFormat;

        var value = std.array_list.Managed(u8).init(allocator);
        errdefer value.deinit();

        var index: usize = 1;
        while (index < trimmed.len - 1) : (index += 1) {
            const c = trimmed[index];
            if (c == '"') return ParseError.InvalidFormat;
            if (c != '\\') {
                try value.append(c);
                continue;
            }

            index += 1;
            if (index >= trimmed.len - 1) return ParseError.InvalidFormat;
            try value.append(switch (trimmed[index]) {
                '"' => '"',
                '\\' => '\\',
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                else => return ParseError.InvalidFormat,
            });
        }

        return try value.toOwnedSlice();
    }

    if (std.mem.indexOfScalar(u8, trimmed, '"') != null) return ParseError.InvalidFormat;
    return allocator.dupe(u8, trimmed);
}

pub fn parseSha256Bytes(text: []const u8) ParseError![32]u8 {
    const trimmed = trim(text);
    const unquoted = if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') trimmed[1 .. trimmed.len - 1] else trimmed;
    const body = if (std.mem.startsWith(u8, unquoted, "sha256:")) unquoted["sha256:".len..] else unquoted;
    if (body.len != 64) return ParseError.InvalidSha256;
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(bytes[0..], body) catch return ParseError.InvalidSha256;
    return bytes;
}

pub fn sha256Text(writer: anytype, hash: [32]u8) !void {
    const encoded = std.fmt.bytesToHex(hash, .lower);
    try writer.print("sha256:{s}", .{encoded[0..]});
}

pub fn bareHexText(writer: anytype, hash: [32]u8) !void {
    const encoded = std.fmt.bytesToHex(hash, .lower);
    try writer.print("{s}", .{encoded[0..]});
}

pub fn parseCapability(text: []const u8) ?Capability {
    return if (std.mem.eql(u8, text, "mem_alloc")) .mem_alloc else if (std.mem.eql(u8, text, "mem_slice")) .mem_slice else if (std.mem.eql(u8, text, "io_read")) .io_read else if (std.mem.eql(u8, text, "io_write")) .io_write else if (std.mem.eql(u8, text, "net_tx")) .net_tx else if (std.mem.eql(u8, text, "net_rx")) .net_rx else if (std.mem.eql(u8, text, "proc_spawn")) .proc_spawn else if (std.mem.eql(u8, text, "proc_exit")) .proc_exit else if (std.mem.eql(u8, text, "proc_args")) .proc_args else if (std.mem.eql(u8, text, "time_now")) .time_now else if (std.mem.eql(u8, text, "rand_get")) .rand_get else null;
}

pub fn capabilityName(cap: Capability) []const u8 {
    return switch (cap) {
        .mem_alloc => "mem_alloc",
        .mem_slice => "mem_slice",
        .io_read => "io_read",
        .io_write => "io_write",
        .net_tx => "net_tx",
        .net_rx => "net_rx",
        .proc_spawn => "proc_spawn",
        .proc_exit => "proc_exit",
        .proc_args => "proc_args",
        .time_now => "time_now",
        .rand_get => "rand_get",
    };
}

pub fn containsCapability(items: []const Capability, cap: Capability) bool {
    for (items) |item| {
        if (item == cap) return true;
    }
    return false;
}

pub fn parseCapabilityList(allocator: std.mem.Allocator, text: []const u8) ParseError![]const Capability {
    const trimmed = trim(text);
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') {
        return ParseError.InvalidFormat;
    }
    const body = trim(trimmed[1 .. trimmed.len - 1]);
    var list = std.array_list.Managed(Capability).init(allocator);
    errdefer list.deinit();

    if (body.len == 0) return try list.toOwnedSlice();

    var start: usize = 0;
    var index: usize = 0;
    while (index <= body.len) : (index += 1) {
        if (index < body.len and body[index] != ',') continue;
        const token = trim(body[start..index]);
        if (token.len == 0) {
            if (index == body.len and start == body.len and body.len != 0 and body[body.len - 1] == ',') break;
            return ParseError.InvalidFormat;
        }
        const cap = parseCapability(token) orelse return ParseError.InvalidCapability;
        if (containsCapability(list.items, cap)) return ParseError.DuplicateEntry;
        try list.append(cap);
        start = index + 1;
    }

    return try list.toOwnedSlice();
}

pub fn parseGrantsClause(allocator: std.mem.Allocator, text: []const u8) ParseError![]const Capability {
    const trimmed = trim(text);
    if (!startsWithWord(trimmed, "grants")) return ParseError.InvalidFormat;
    return try parseCapabilityList(allocator, trimmed["grants".len..]);
}

pub fn parseRequireEntry(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_no: u32,
    source_file: []const u8,
) ParseError!RequireEntry {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "require")) return ParseError.InvalidFormat;

    const url_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const ref_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const sha_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (ref_token.len < 2 or ref_token[0] != '@') return ParseError.InvalidFormat;

    const url = try allocator.dupe(u8, url_token);
    errdefer allocator.free(url);
    const ref = try allocator.dupe(u8, ref_token[1..]);
    errdefer allocator.free(ref);
    const source_sha256 = try parseSha256Bytes(sha_token);
    var grants: []const Capability = try allocator.alloc(Capability, 0);
    errdefer allocator.free(grants);

    const tail = trim(line[pos..]);
    if (tail.len != 0) {
        grants = try parseGrantsClause(allocator, tail);
    }

    const file_copy = try allocator.dupe(u8, source_file);
    errdefer allocator.free(file_copy);
    return .{
        .url = url,
        .ref = ref,
        .source_sha256 = source_sha256,
        .grants = grants,
        .upstream_loc = .{
            .file = file_copy,
            .line = line_no,
            .col = 1,
        },
    };
}

pub fn parseMirrorEntry(allocator: std.mem.Allocator, line: []const u8) ParseError!MirrorRule {
    const assignment = splitAssignment(line) orelse return ParseError.InvalidFormat;
    if (assignment.key.len == 0 or assignment.value.len == 0) return ParseError.InvalidFormat;

    const host = try parseTextValue(allocator, assignment.key);
    errdefer allocator.free(host);
    const rewrite_to = try parseTextValue(allocator, assignment.value);
    errdefer allocator.free(rewrite_to);

    return .{
        .host_pattern = host,
        .rewrite_to = rewrite_to,
    };
}

pub const PermissionSetBuilder = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    file: []const u8,
    line: u32,
    env: std.array_list.Managed([]const u8),
    read: std.array_list.Managed([]const u8),
    write: std.array_list.Managed([]const u8),
    net: std.array_list.Managed([]const u8),
    run: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, source_file: []const u8, line_no: u32) ParseError!PermissionSetBuilder {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .file = try allocator.dupe(u8, source_file),
            .line = line_no,
            .env = std.array_list.Managed([]const u8).init(allocator),
            .read = std.array_list.Managed([]const u8).init(allocator),
            .write = std.array_list.Managed([]const u8).init(allocator),
            .net = std.array_list.Managed([]const u8).init(allocator),
            .run = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PermissionSetBuilder) void {
        self.allocator.free(self.name);
        self.allocator.free(self.file);
        freeArrayListStrings(self.allocator, &self.env);
        freeArrayListStrings(self.allocator, &self.read);
        freeArrayListStrings(self.allocator, &self.write);
        freeArrayListStrings(self.allocator, &self.net);
        freeArrayListStrings(self.allocator, &self.run);
        self.* = undefined;
    }

    pub fn finish(self: *PermissionSetBuilder) ParseError!PermissionSet {
        const result = PermissionSet{
            .name = self.name,
            .env = try self.env.toOwnedSlice(),
            .read = try self.read.toOwnedSlice(),
            .write = try self.write.toOwnedSlice(),
            .net = try self.net.toOwnedSlice(),
            .run = try self.run.toOwnedSlice(),
            .upstream_loc = .{ .file = self.file, .line = self.line, .col = 1 },
        };
        self.name = &.{};
        self.file = &.{};
        return result;
    }
};

pub fn freeArrayListStrings(allocator: std.mem.Allocator, list: *std.array_list.Managed([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

pub fn parsePermissionSetHeader(allocator: std.mem.Allocator, line: []const u8, source_file: []const u8, line_no: u32) ParseError!PermissionSetBuilder {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "permission_set")) return ParseError.InvalidFormat;
    const name = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const tail = trim(line[pos..]);
    if (!std.mem.eql(u8, tail, "{")) return ParseError.InvalidFormat;
    return try PermissionSetBuilder.init(allocator, name, source_file, line_no);
}

pub fn parsePackageDecl(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_no: u32,
    source_file: []const u8,
) ParseError!PackageDecl {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "package")) return ParseError.InvalidFormat;
    const name = try parseTextValue(allocator, trim(line[pos..]));
    errdefer allocator.free(name);
    const features = try allocator.alloc([]const u8, 0);
    errdefer allocator.free(features);
    const file_copy = try allocator.dupe(u8, source_file);
    errdefer allocator.free(file_copy);
    return .{
        .name = name,
        .version = null,
        .abi = null,
        .features = features,
        .upstream_loc = .{ .file = file_copy, .line = line_no, .col = 1 },
    };
}

pub const PackageBuilder = struct {
    allocator: std.mem.Allocator,
    file: []const u8,
    line: u32,
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    abi: ?u32 = null,
    features: std.array_list.Managed([]const u8),

    pub fn init(allocator: std.mem.Allocator, source_file: []const u8, line_no: u32) ParseError!PackageBuilder {
        return .{
            .allocator = allocator,
            .file = try allocator.dupe(u8, source_file),
            .line = line_no,
            .features = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *PackageBuilder) void {
        self.allocator.free(self.file);
        if (self.name) |name| self.allocator.free(name);
        if (self.version) |version| self.allocator.free(version);
        freeArrayListStrings(self.allocator, &self.features);
        self.* = undefined;
    }

    pub fn finish(self: *PackageBuilder) ParseError!PackageDecl {
        const name = self.name orelse return ParseError.InvalidFormat;
        const result = PackageDecl{
            .name = name,
            .version = self.version,
            .abi = self.abi,
            .features = try self.features.toOwnedSlice(),
            .upstream_loc = .{ .file = self.file, .line = self.line, .col = 1 },
        };
        self.name = null;
        self.version = null;
        self.file = &.{};
        return result;
    }
};

pub fn parsePackageHeader(allocator: std.mem.Allocator, line: []const u8, source_file: []const u8, line_no: u32) ParseError!PackageBuilder {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "package")) return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, trim(line[pos..]), "{")) return ParseError.InvalidFormat;
    return try PackageBuilder.init(allocator, source_file, line_no);
}

pub const WorkspaceBuilder = struct {
    allocator: std.mem.Allocator,
    file: []const u8,
    line: u32,
    members: std.array_list.Managed([]const u8),
    default_member: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, source_file: []const u8, line_no: u32) ParseError!WorkspaceBuilder {
        return .{
            .allocator = allocator,
            .file = try allocator.dupe(u8, source_file),
            .line = line_no,
            .members = std.array_list.Managed([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *WorkspaceBuilder) void {
        self.allocator.free(self.file);
        freeArrayListStrings(self.allocator, &self.members);
        if (self.default_member) |member| self.allocator.free(member);
        self.* = undefined;
    }

    pub fn finish(self: *WorkspaceBuilder) ParseError!WorkspaceDecl {
        const result = WorkspaceDecl{
            .members = try self.members.toOwnedSlice(),
            .default_member = self.default_member,
            .upstream_loc = .{ .file = self.file, .line = self.line, .col = 1 },
        };
        self.file = &.{};
        self.default_member = null;
        return result;
    }
};

pub fn parseWorkspaceHeader(allocator: std.mem.Allocator, line: []const u8, source_file: []const u8, line_no: u32) ParseError!WorkspaceBuilder {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "workspace")) return ParseError.InvalidFormat;
    const tail = trim(line[pos..]);
    if (!std.mem.eql(u8, tail, "{")) return ParseError.InvalidFormat;
    return try WorkspaceBuilder.init(allocator, source_file, line_no);
}

pub fn parsePackageItem(builder: *PackageBuilder, line: []const u8) ParseError!void {
    const assignment = parseNamedValue(line) orelse return ParseError.InvalidFormat;
    const key = assignment.key;
    const value = assignment.value;
    if (std.mem.eql(u8, key, "name")) {
        if (builder.name != null) return ParseError.DuplicateEntry;
        builder.name = try parseTextValue(builder.allocator, value);
        return;
    }
    if (std.mem.eql(u8, key, "version")) {
        if (builder.version != null) return ParseError.DuplicateEntry;
        builder.version = try parseTextValue(builder.allocator, value);
        return;
    }
    if (std.mem.eql(u8, key, "abi")) {
        if (builder.abi != null) return ParseError.DuplicateEntry;
        const parsed = std.fmt.parseInt(u64, value, 10) catch return ParseError.InvalidFormat;
        if (parsed > std.math.maxInt(u32)) return ParseError.InvalidFormat;
        builder.abi = @as(u32, @intCast(parsed));
        return;
    }
    if (std.mem.eql(u8, key, "features")) {
        return parseUniqueStringListInto(builder.allocator, value, &builder.features);
    }
    return ParseError.InvalidFormat;
}

pub fn stringListContains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

pub fn parseStringListInto(allocator: std.mem.Allocator, text: []const u8, list: *std.array_list.Managed([]const u8)) ParseError!void {
    const trimmed = trim(text);
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return ParseError.InvalidFormat;
    const body = trim(trimmed[1 .. trimmed.len - 1]);
    if (body.len == 0) return;

    var start: usize = 0;
    var in_string = false;
    var escape = false;
    var index: usize = 0;
    while (index <= body.len) : (index += 1) {
        const at_end = index == body.len;
        if (!at_end) {
            const c = body[index];
            if (in_string) {
                if (escape) {
                    escape = false;
                } else if (c == '\\') {
                    escape = true;
                } else if (c == '"') {
                    in_string = false;
                }
                continue;
            }
            if (c == '"') {
                in_string = true;
                continue;
            }
            if (c != ',') continue;
        }

        if (in_string or escape) return ParseError.InvalidFormat;
        const token = trim(body[start..index]);
        if (token.len == 0) {
            if (!(index == body.len and start == body.len and body.len != 0 and body[body.len - 1] == ',')) return ParseError.InvalidFormat;
            break;
        }
        try list.append(try parseTextValue(allocator, token));
        start = index + 1;
    }
}

pub fn parseUniqueStringListInto(allocator: std.mem.Allocator, text: []const u8, list: *std.array_list.Managed([]const u8)) ParseError!void {
    const before_len = list.items.len;
    errdefer {
        while (list.items.len > before_len) {
            allocator.free(list.pop().?);
        }
    }
    try parseStringListInto(allocator, text, list);
    for (list.items[before_len..]) |item| {
        if (stringListContains(list.items[0..before_len], item)) return ParseError.DuplicateEntry;
    }
    var i = before_len;
    while (i < list.items.len) : (i += 1) {
        var j = i + 1;
        while (j < list.items.len) : (j += 1) {
            if (std.mem.eql(u8, list.items[i], list.items[j])) return ParseError.DuplicateEntry;
        }
    }
}

pub fn parsePermissionSetItem(builder: *PermissionSetBuilder, line: []const u8) ParseError!void {
    const assignment = parseNamedValue(line) orelse return ParseError.InvalidFormat;
    const key = assignment.key;
    const value = assignment.value;
    if (std.mem.eql(u8, key, "env")) return parseStringListInto(builder.allocator, value, &builder.env);
    if (std.mem.eql(u8, key, "read")) return parseStringListInto(builder.allocator, value, &builder.read);
    if (std.mem.eql(u8, key, "write")) return parseStringListInto(builder.allocator, value, &builder.write);
    if (std.mem.eql(u8, key, "net")) return parseStringListInto(builder.allocator, value, &builder.net);
    if (std.mem.eql(u8, key, "run")) return parseStringListInto(builder.allocator, value, &builder.run);
    return ParseError.InvalidFormat;
}

pub fn parseWorkspaceItem(builder: *WorkspaceBuilder, line: []const u8) ParseError!void {
    const assignment = parseNamedValue(line) orelse return ParseError.InvalidFormat;
    const key = assignment.key;
    const value = assignment.value;
    if (std.mem.eql(u8, key, "members")) return parseUniqueStringListInto(builder.allocator, value, &builder.members);
    if (std.mem.eql(u8, key, "default_member")) {
        if (builder.default_member != null) return ParseError.DuplicateEntry;
        builder.default_member = try parseTextValue(builder.allocator, value);
        return;
    }
    return ParseError.InvalidFormat;
}

pub fn parsePluginRequireEntry(
    allocator: std.mem.Allocator,
    line: []const u8,
    line_no: u32,
    source_file: []const u8,
) ParseError!PluginRequireEntry {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "require_plugin")) return ParseError.InvalidFormat;

    const identity_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const ref_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (ref_token.len < 2 or ref_token[0] != '@') return ParseError.InvalidFormat;
    const abi_keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, abi_keyword, "abi")) return ParseError.InvalidFormat;
    const abi_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (trim(line[pos..]).len != 0) return ParseError.InvalidFormat;

    const identity = try allocator.dupe(u8, identity_token);
    errdefer allocator.free(identity);
    const ref = try allocator.dupe(u8, ref_token[1..]);
    errdefer allocator.free(ref);
    const abi = std.fmt.parseUnsigned(u32, abi_token, 10) catch return ParseError.InvalidFormat;
    const file_copy = try allocator.dupe(u8, source_file);
    errdefer allocator.free(file_copy);

    return .{
        .identity = identity,
        .ref = ref,
        .abi = abi,
        .upstream_loc = .{
            .file = file_copy,
            .line = line_no,
            .col = 1,
        },
    };
}

pub fn requireExists(entries: []const RequireEntry, url: []const u8, ref: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.url, url) and std.mem.eql(u8, entry.ref, ref)) return true;
    }
    return false;
}

pub fn mirrorExists(entries: []const MirrorRule, host: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.host_pattern, host)) return true;
    }
    return false;
}

pub fn pluginRequireExists(entries: []const PluginRequireEntry, identity: []const u8, ref: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.identity, identity) and std.mem.eql(u8, entry.ref, ref)) return true;
    }
    return false;
}

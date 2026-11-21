const std = @import("std");
const LockEntry = @import("mergeworkspacememberset.zig").LockEntry;
const LockFile = @import("mergeworkspacememberset.zig").LockFile;
const Manifest = @import("mergeworkspacememberset.zig").Manifest;
const MirrorRule = @import("mergeworkspacememberset.zig").MirrorRule;
const PackageBuilder = @import("permissionsetbuilder.zig").PackageBuilder;
const PackageDecl = @import("mergeworkspacememberset.zig").PackageDecl;
const ParseError = @import("mergeworkspacememberset.zig").ParseError;
const PermissionSet = @import("mergeworkspacememberset.zig").PermissionSet;
const PermissionSetBuilder = @import("permissionsetbuilder.zig").PermissionSetBuilder;
const PluginRequireEntry = @import("mergeworkspacememberset.zig").PluginRequireEntry;
const RequireEntry = @import("mergeworkspacememberset.zig").RequireEntry;
const SumEntry = @import("mergeworkspacememberset.zig").SumEntry;
const SumFile = @import("mergeworkspacememberset.zig").SumFile;
const TargetHashMap = @import("mergeworkspacememberset.zig").TargetHashMap;
const WorkspaceBuilder = @import("permissionsetbuilder.zig").WorkspaceBuilder;
const WorkspaceDecl = @import("mergeworkspacememberset.zig").WorkspaceDecl;
const bareHexText = @import("permissionsetbuilder.zig").bareHexText;
const capabilityName = @import("permissionsetbuilder.zig").capabilityName;
const cleanLine = @import("permissionsetbuilder.zig").cleanLine;
const max_manifest_bytes = @import("mergeworkspacememberset.zig").max_manifest_bytes;
const mirrorExists = @import("permissionsetbuilder.zig").mirrorExists;
const nextToken = @import("permissionsetbuilder.zig").nextToken;
const parseMirrorEntry = @import("permissionsetbuilder.zig").parseMirrorEntry;
const parsePackageDecl = @import("permissionsetbuilder.zig").parsePackageDecl;
const parsePackageHeader = @import("permissionsetbuilder.zig").parsePackageHeader;
const parsePackageItem = @import("permissionsetbuilder.zig").parsePackageItem;
const parsePermissionSetHeader = @import("permissionsetbuilder.zig").parsePermissionSetHeader;
const parsePermissionSetItem = @import("permissionsetbuilder.zig").parsePermissionSetItem;
const parsePluginRequireEntry = @import("permissionsetbuilder.zig").parsePluginRequireEntry;
const parseRequireEntry = @import("permissionsetbuilder.zig").parseRequireEntry;
const parseSha256Bytes = @import("permissionsetbuilder.zig").parseSha256Bytes;
const parseTextValue = @import("permissionsetbuilder.zig").parseTextValue;
const parseWorkspaceHeader = @import("permissionsetbuilder.zig").parseWorkspaceHeader;
const parseWorkspaceItem = @import("permissionsetbuilder.zig").parseWorkspaceItem;
const pluginRequireExists = @import("permissionsetbuilder.zig").pluginRequireExists;
const requireExists = @import("permissionsetbuilder.zig").requireExists;
const sha256Text = @import("permissionsetbuilder.zig").sha256Text;
const splitAssignment = @import("permissionsetbuilder.zig").splitAssignment;
const startsWithWord = @import("mergeworkspacememberset.zig").startsWithWord;
const trim = @import("mergeworkspacememberset.zig").trim;


pub fn parseManifestWithFile(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_file: []const u8,
) ParseError!Manifest {
    if (source.len > max_manifest_bytes) return ParseError.InvalidFormat;

    if (std.mem.startsWith(u8, source_file, "~/.sa/") or std.mem.startsWith(u8, source_file, "/etc/sa/")) {
        return ParseError.ForbiddenGlobalConfig;
    }

    var requires = std.array_list.Managed(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }

    var mirrors = std.array_list.Managed(MirrorRule).init(allocator);
    errdefer {
        for (mirrors.items) |*rule| rule.deinit(allocator);
        mirrors.deinit();
    }

    var plugin_requires = std.array_list.Managed(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }

    var permission_sets = std.array_list.Managed(PermissionSet).init(allocator);
    errdefer {
        for (permission_sets.items) |*set| set.deinit(allocator);
        permission_sets.deinit();
    }

    var package_decl: ?PackageDecl = null;
    errdefer if (package_decl) |*package_value| package_value.deinit(allocator);

    var workspace_decl: ?WorkspaceDecl = null;
    errdefer if (workspace_decl) |*workspace_value| workspace_value.deinit(allocator);

    var in_mirrors = false;
    var permission_builder: ?PermissionSetBuilder = null;
    defer if (permission_builder) |*builder| builder.deinit();
    var workspace_builder: ?WorkspaceBuilder = null;
    defer if (workspace_builder) |*builder| builder.deinit();
    var package_builder: ?PackageBuilder = null;
    defer if (package_builder) |*builder| builder.deinit();
    var line_no: u32 = 0;
    var it = std.mem.splitScalar(u8, source, '\n');
    while (it.next()) |raw_line| {
        line_no += 1;
        const line = cleanLine(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        if (package_builder) |*builder| {
            if (std.mem.eql(u8, line, "}")) {
                if (package_decl != null) return ParseError.DuplicateEntry;
                package_decl = try builder.finish();
                package_builder = null;
                continue;
            }
            try parsePackageItem(builder, line);
            continue;
        }

        if (permission_builder) |*builder| {
            if (std.mem.eql(u8, line, "}")) {
                try permission_sets.append(try builder.finish());
                permission_builder = null;
                continue;
            }
            try parsePermissionSetItem(builder, line);
            continue;
        }

        if (workspace_builder) |*builder| {
            if (std.mem.eql(u8, line, "}")) {
                if (workspace_decl != null) return ParseError.DuplicateEntry;
                workspace_decl = try builder.finish();
                workspace_builder = null;
                continue;
            }
            try parseWorkspaceItem(builder, line);
            continue;
        }

        if (std.mem.eql(u8, line, "[mirrors]")) {
            in_mirrors = true;
            continue;
        }
        if (line[0] == '[') return ParseError.InvalidFormat;

        if (startsWithWord(line, "permission_set")) {
            permission_builder = try parsePermissionSetHeader(allocator, line, source_file, line_no);
            in_mirrors = false;
            continue;
        }

        if (startsWithWord(line, "workspace")) {
            workspace_builder = try parseWorkspaceHeader(allocator, line, source_file, line_no);
            in_mirrors = false;
            continue;
        }

        if (startsWithWord(line, "package")) {
            if (package_decl != null) return ParseError.DuplicateEntry;
            var package_pos: usize = 0;
            _ = nextToken(line, &package_pos) orelse return ParseError.InvalidFormat;
            if (std.mem.eql(u8, trim(line[package_pos..]), "{")) {
                package_builder = try parsePackageHeader(allocator, line, source_file, line_no);
            } else {
                package_decl = try parsePackageDecl(allocator, line, line_no, source_file);
            }
            continue;
        }

        if (startsWithWord(line, "require_plugin")) {
            var entry = try parsePluginRequireEntry(allocator, line, line_no, source_file);
            if (pluginRequireExists(plugin_requires.items, entry.identity, entry.ref)) {
                entry.deinit(allocator);
                return ParseError.DuplicateEntry;
            }
            try plugin_requires.append(entry);
            continue;
        }

        if (startsWithWord(line, "require")) {
            var entry = try parseRequireEntry(allocator, line, line_no, source_file);
            if (requireExists(requires.items, entry.url, entry.ref)) {
                entry.deinit(allocator);
                return ParseError.DuplicateEntry;
            }
            try requires.append(entry);
            continue;
        }

        if (in_mirrors and std.mem.indexOfScalar(u8, line, '=') != null) {
            var rule = try parseMirrorEntry(allocator, line);
            if (mirrorExists(mirrors.items, rule.host_pattern)) {
                rule.deinit(allocator);
                return ParseError.DuplicateMirror;
            }
            try mirrors.append(rule);
            continue;
        }

        return ParseError.InvalidFormat;
    }

    if (package_builder != null or permission_builder != null or workspace_builder != null) return ParseError.InvalidFormat;

    return .{
        .package_decl = package_decl,
        .workspace = workspace_decl,
        .requires = try requires.toOwnedSlice(),
        .plugin_requires = try plugin_requires.toOwnedSlice(),
        .permission_sets = try permission_sets.toOwnedSlice(),
        .mirrors = try mirrors.toOwnedSlice(),
    };
}

pub fn parseManifest(allocator: std.mem.Allocator, source: []const u8) ParseError!Manifest {
    return parseManifestWithFile(allocator, source, "sa.mod");
}

fn writeTextValue(writer: anytype, value: []const u8) !void {
    try writer.writeByte('"');
    for (value) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => try writer.writeByte(c),
        }
    }
    try writer.writeByte('"');
}

pub fn writeManifest(writer: anytype, manifest: Manifest) !void {
    var wrote_section = false;

    if (manifest.package_decl) |package_decl| {
        const has_metadata = package_decl.version != null or package_decl.abi != null or package_decl.features.len != 0;
        if (!has_metadata) {
            try writer.writeAll("package ");
            try writeTextValue(writer, package_decl.name);
            try writer.writeByte('\n');
        } else {
            try writer.writeAll("package {\n  name ");
            try writeTextValue(writer, package_decl.name);
            try writer.writeByte('\n');
            if (package_decl.version) |version| {
                try writer.writeAll("  version ");
                try writeTextValue(writer, version);
                try writer.writeByte('\n');
            }
            if (package_decl.abi) |abi| try writer.print("  abi {d}\n", .{abi});
            if (package_decl.features.len != 0) {
                try writer.writeAll("  features [");
                for (package_decl.features, 0..) |feature, idx| {
                    if (idx != 0) try writer.writeAll(", ");
                    try writeTextValue(writer, feature);
                }
                try writer.writeAll("]\n");
            }
            try writer.writeAll("}\n");
        }
        wrote_section = true;
    }

    if (manifest.workspace) |workspace| {
        if (wrote_section) try writer.writeByte('\n');
        try writer.writeAll("workspace {\n");
        try writer.writeAll("  members [");
        for (workspace.members, 0..) |member, idx| {
            if (idx != 0) try writer.writeAll(", ");
            try writer.print("\"{s}\"", .{member});
        }
        try writer.writeAll("]\n");
        if (workspace.default_member) |member| {
            try writer.print("  default_member \"{s}\"\n", .{member});
        }
        try writer.writeAll("}\n");
        wrote_section = true;
    }

    for (manifest.requires, 0..) |entry, idx| {
        if (idx == 0) {
            if (wrote_section) try writer.writeByte('\n');
        } else {
            try writer.writeByte('\n');
        }
        try writer.print("require {s} @{s}", .{ entry.url, entry.ref });
        try writer.writeByte(' ');
        try sha256Text(writer, entry.source_sha256);
        if (entry.grants.len != 0) {
            try writer.writeAll(" grants [");
            for (entry.grants, 0..) |cap, grant_idx| {
                if (grant_idx != 0) try writer.writeAll(", ");
                try writer.writeAll(capabilityName(cap));
            }
            try writer.writeByte(']');
        }
        try writer.writeByte('\n');
    }

    if (manifest.plugin_requires.len != 0) {
        if (wrote_section or manifest.requires.len != 0) try writer.writeByte('\n');
        for (manifest.plugin_requires) |entry| {
            try writer.print("require_plugin {s} @{s} abi {d}\n", .{ entry.identity, entry.ref, entry.abi });
        }
    }

    if (manifest.permission_sets.len != 0) {
        if (wrote_section or manifest.requires.len != 0 or manifest.plugin_requires.len != 0) try writer.writeByte('\n');
        for (manifest.permission_sets, 0..) |set, set_idx| {
            if (set_idx != 0) try writer.writeByte('\n');
            try writer.print("permission_set {s} {{\n", .{set.name});
            try writePermissionSetList(writer, "env", set.env);
            try writePermissionSetList(writer, "read", set.read);
            try writePermissionSetList(writer, "write", set.write);
            try writePermissionSetList(writer, "net", set.net);
            try writePermissionSetList(writer, "run", set.run);
            try writer.writeAll("}\n");
        }
    }

    if (manifest.mirrors.len != 0) {
        if (wrote_section or manifest.requires.len != 0 or manifest.plugin_requires.len != 0 or manifest.permission_sets.len != 0) try writer.writeByte('\n');
        try writer.writeAll("[mirrors]\n");
        for (manifest.mirrors, 0..) |rule, idx| {
            if (idx != 0) try writer.writeByte('\n');
            try writer.print("{s} = {s}\n", .{ rule.host_pattern, rule.rewrite_to });
        }
    }
}

fn writePermissionSetList(writer: anytype, name: []const u8, list: []const []const u8) !void {
    try writer.print("  {s} [", .{name});
    for (list, 0..) |item, idx| {
        if (idx != 0) try writer.writeAll(", ");
        try writer.writeAll(item);
    }
    try writer.writeAll("]\n");
}

const HashItem = struct {
    key: []const u8,
    value: [32]u8,
};

fn lessThanHashItem(_: void, lhs: HashItem, rhs: HashItem) bool {
    return std.mem.order(u8, lhs.key, rhs.key) == .lt;
}

fn sortedHashItems(allocator: std.mem.Allocator, map: TargetHashMap) ParseError![]HashItem {
    var items = std.array_list.Managed(HashItem).init(allocator);
    errdefer items.deinit();

    var it = map.iterator();
    while (it.next()) |entry| {
        try items.append(.{
            .key = entry.key_ptr.*,
            .value = entry.value_ptr.*,
        });
    }

    if (items.items.len != 0) {
        std.sort.insertion(HashItem, items.items, {}, lessThanHashItem);
    }

    return try items.toOwnedSlice();
}

const LockBuilder = struct {
    allocator: std.mem.Allocator,
    url: ?[]const u8 = null,
    ref: ?[]const u8 = null,
    source_sha256: ?[32]u8 = null,
    hashes: TargetHashMap,
    acknowledged_at_utc: ?i64 = null,
    acknowledged_target_count: ?u8 = null,

    fn init(allocator: std.mem.Allocator) LockBuilder {
        return .{
            .allocator = allocator,
            .hashes = TargetHashMap.init(allocator),
        };
    }

    fn deinit(self: *LockBuilder, allocator: std.mem.Allocator) void {
        var it = self.hashes.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.hashes.deinit();
        if (self.url) |url| allocator.free(url);
        if (self.ref) |ref| allocator.free(ref);
        self.* = undefined;
    }

    fn finish(self: *LockBuilder) ParseError!LockEntry {
        const url = self.url orelse return ParseError.InvalidFormat;
        const ref = self.ref orelse return ParseError.InvalidFormat;
        const source_sha256 = self.source_sha256 orelse return ParseError.InvalidFormat;
        const count = self.hashes.count();
        const acknowledged_at_utc = self.acknowledged_at_utc orelse 0;
        const acknowledged_target_count = if (self.acknowledged_target_count) |value| value else blk: {
            if (count > std.math.maxInt(u8)) return ParseError.InvalidFormat;
            break :blk @as(u8, @intCast(count));
        };
        if (self.acknowledged_target_count != null and @as(usize, self.acknowledged_target_count.?) != count) {
            return ParseError.InvalidFormat;
        }
        const hashes = self.hashes;
        self.hashes = TargetHashMap.init(self.allocator);
        self.url = null;
        self.ref = null;
        self.source_sha256 = null;
        self.acknowledged_at_utc = null;
        self.acknowledged_target_count = null;
        return .{
            .url = url,
            .ref = ref,
            .source_sha256 = source_sha256,
            .approved_machine_code_hashes = hashes,
            .acknowledged_at_utc = acknowledged_at_utc,
            .acknowledged_target_count = acknowledged_target_count,
        };
    }
};

fn parseDependencyHeader(allocator: std.mem.Allocator, line: []const u8) ParseError![]const u8 {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "dependency")) return ParseError.InvalidFormat;
    const url_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const open = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, open, "{")) return ParseError.InvalidFormat;
    if (trim(line[pos..]).len != 0) return ParseError.InvalidFormat;
    return try parseTextValue(allocator, url_token);
}

fn parseHashLine(builder: *LockBuilder, allocator: std.mem.Allocator, line: []const u8) ParseError!void {
    const assignment = splitAssignment(line) orelse return ParseError.InvalidFormat;
    if (assignment.key.len == 0 or assignment.value.len == 0) return ParseError.InvalidFormat;

    if (std.mem.eql(u8, assignment.key, "version")) {
        if (builder.ref != null) return ParseError.DuplicateEntry;
        builder.ref = try parseTextValue(allocator, assignment.value);
        return;
    }

    if (std.mem.eql(u8, assignment.key, "source_sha") or std.mem.eql(u8, assignment.key, "source_sha256")) {
        if (builder.source_sha256 != null) return ParseError.DuplicateEntry;
        builder.source_sha256 = try parseSha256Bytes(assignment.value);
        return;
    }

    if (std.mem.eql(u8, assignment.key, "approved_machine_code_hash")) {
        const key = try allocator.dupe(u8, "");
        errdefer allocator.free(key);
        if (builder.hashes.contains(key)) return ParseError.DuplicateTargetHash;
        const hash = try parseSha256Bytes(assignment.value);
        try builder.hashes.put(key, hash);
        return;
    }

    if (std.mem.eql(u8, assignment.key, "acknowledged_at_utc")) {
        if (builder.acknowledged_at_utc != null) return ParseError.DuplicateEntry;
        builder.acknowledged_at_utc = std.fmt.parseInt(i64, assignment.value, 10) catch return ParseError.InvalidFormat;
        return;
    }

    if (std.mem.eql(u8, assignment.key, "acknowledged_target_count")) {
        if (builder.acknowledged_target_count != null) return ParseError.DuplicateEntry;
        const count = std.fmt.parseInt(u64, assignment.value, 10) catch return ParseError.InvalidFormat;
        if (count > std.math.maxInt(u8)) return ParseError.InvalidFormat;
        builder.acknowledged_target_count = @as(u8, @intCast(count));
        return;
    }

    return ParseError.InvalidFormat;
}

fn parseHashMapLine(builder: *LockBuilder, allocator: std.mem.Allocator, line: []const u8) ParseError!void {
    const assignment = splitAssignment(line) orelse return ParseError.InvalidFormat;
    if (assignment.key.len == 0 or assignment.value.len == 0) return ParseError.InvalidFormat;

    const key = if (std.mem.eql(u8, assignment.key, "default")) "" else assignment.key;
    const hash = try parseSha256Bytes(assignment.value);
    if (builder.hashes.contains(key)) return ParseError.DuplicateTargetHash;

    const key_copy = try allocator.dupe(u8, key);
    errdefer allocator.free(key_copy);
    try builder.hashes.put(key_copy, hash);
}

pub fn parseLock(allocator: std.mem.Allocator, source: []const u8) ParseError!LockFile {
    var entries = std.array_list.Managed(LockEntry).init(allocator);
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit();
    }

    var builder: ?LockBuilder = null;
    var in_hashes = false;
    var line_no: u32 = 0;
    errdefer if (builder) |*active| active.deinit(allocator);
    var it = std.mem.splitScalar(u8, source, '\n');
    while (it.next()) |raw_line| {
        line_no += 1;
        const line = cleanLine(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

        if (builder == null) {
            if (line[0] != 'd') return ParseError.InvalidFormat;
            const url = try parseDependencyHeader(allocator, line);
            builder = LockBuilder.init(allocator);
            builder.?.url = url;
            continue;
        }

        if (in_hashes) {
            if (std.mem.eql(u8, line, "}")) {
                in_hashes = false;
                continue;
            }
            try parseHashMapLine(&builder.?, allocator, line);
            continue;
        }

        if (std.mem.eql(u8, line, "}")) {
            const finished = try builder.?.finish();
            if (entries.append(finished)) |_| {} else |err| {
                var owned = finished;
                owned.deinit(allocator);
                return err;
            }
            builder = null;
            continue;
        }

        if (startsWithWord(line, "approved_machine_code_hashes")) {
            const rest = trim(line["approved_machine_code_hashes".len..]);
            if (!std.mem.eql(u8, rest, "{")) return ParseError.InvalidFormat;
            in_hashes = true;
            continue;
        }

        try parseHashLine(&builder.?, allocator, line);
    }

    if (builder != null or in_hashes) return ParseError.InvalidFormat;

    return .{
        .entries = try entries.toOwnedSlice(),
    };
}

fn writeLockHashes(writer: anytype, map: TargetHashMap, indent: []const u8) !void {
    const items = try sortedHashItems(std.heap.page_allocator, map);
    defer std.heap.page_allocator.free(items);

    if (items.len == 0) {
        try writer.print("{s}approved_machine_code_hashes {{\n{s}}}\n", .{ indent, indent });
        return;
    }

    if (items.len == 1 and items[0].key.len == 0) {
        try writer.writeAll(indent);
        try writer.writeAll("approved_machine_code_hash: \"");
        try bareHexText(writer, items[0].value);
        try writer.writeAll("\"\n");
        return;
    }

    try writer.print("{s}approved_machine_code_hashes {{\n", .{indent});
    for (items) |item| {
        try writer.writeAll(indent);
        try writer.writeAll("    ");
        const key = if (item.key.len == 0) "default" else item.key;
        try writer.print("{s} = \"", .{key});
        try bareHexText(writer, item.value);
        try writer.writeAll("\"\n");
    }
    try writer.print("{s}}}\n", .{indent});
}

pub fn writeLock(writer: anytype, lock_file: LockFile) !void {
    for (lock_file.entries, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte('\n');
        try writer.print("dependency \"{s}\" {{\n", .{entry.url});
        try writer.print("    version: \"{s}\"\n", .{entry.ref});
        try writer.writeAll("    source_sha: \"");
        try bareHexText(writer, entry.source_sha256);
        try writer.writeAll("\"\n");
        try writeLockHashes(writer, entry.approved_machine_code_hashes, "    ");
        try writer.print("    acknowledged_at_utc: {d}\n", .{entry.acknowledged_at_utc});
        try writer.print("    acknowledged_target_count: {d}\n", .{entry.acknowledged_target_count});
        try writer.writeAll("}\n");
    }
}

fn parseSumEntry(allocator: std.mem.Allocator, line: []const u8) ParseError!SumEntry {
    var pos: usize = 0;
    const url = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const ref_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const sha_token = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (ref_token.len < 2 or ref_token[0] != '@') return ParseError.InvalidFormat;
    const source_sha256 = try parseSha256Bytes(sha_token);

    var depth: u32 = 0;
    const tail = trim(line[pos..]);
    if (tail.len != 0) {
        const assignment = splitAssignment(tail) orelse return ParseError.InvalidFormat;
        if (!std.mem.eql(u8, assignment.key, "depth")) return ParseError.InvalidFormat;
        const value = std.fmt.parseInt(u64, assignment.value, 10) catch return ParseError.InvalidFormat;
        if (value > std.math.maxInt(u32)) return ParseError.InvalidFormat;
        depth = @as(u32, @intCast(value));
    }

    const url_copy = try allocator.dupe(u8, url);
    errdefer allocator.free(url_copy);
    const ref_copy = try allocator.dupe(u8, ref_token[1..]);
    errdefer allocator.free(ref_copy);
    return .{
        .url = url_copy,
        .ref = ref_copy,
        .source_sha256 = source_sha256,
        .depth = depth,
    };
}

pub fn parseSum(allocator: std.mem.Allocator, source: []const u8) ParseError!SumFile {
    var entries = std.array_list.Managed(SumEntry).init(allocator);
    errdefer {
        for (entries.items) |*entry| entry.deinit(allocator);
        entries.deinit();
    }

    var it = std.mem.splitScalar(u8, source, '\n');
    while (it.next()) |raw_line| {
        const line = cleanLine(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;
        if (line[0] == '[') return ParseError.InvalidFormat;
        var entry = try parseSumEntry(allocator, line);
        var duplicate = false;
        for (entries.items) |existing| {
            if (std.mem.eql(u8, existing.url, entry.url) and std.mem.eql(u8, existing.ref, entry.ref)) {
                duplicate = true;
                break;
            }
        }
        if (duplicate) {
            entry.deinit(allocator);
            return ParseError.DuplicateEntry;
        }
        try entries.append(entry);
    }

    return .{
        .entries = try entries.toOwnedSlice(),
    };
}

pub fn writeSum(writer: anytype, sum_file: SumFile) !void {
    for (sum_file.entries, 0..) |entry, idx| {
        if (idx != 0) try writer.writeByte('\n');
        try writer.print("{s} @{s}", .{ entry.url, entry.ref });
        try writer.writeByte(' ');
        try sha256Text(writer, entry.source_sha256);
        if (entry.depth != 0) {
            try writer.print(" depth: {d}", .{entry.depth});
        }
        try writer.writeByte('\n');
    }
}

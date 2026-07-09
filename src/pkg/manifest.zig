const std = @import("std");

pub const max_manifest_bytes: usize = 1024 * 1024;

pub const UpstreamLoc = struct {
    file: []const u8,
    line: u32,
    col: u32,
};

pub const Capability = enum(u8) {
    mem_alloc,
    mem_slice,
    io_read,
    io_write,
    net_tx,
    net_rx,
    proc_spawn,
    proc_exit,
    proc_args,
    time_now,
    rand_get,
};

pub const GrantSet = struct {
    io_read: bool = false,
    io_write: bool = false,

    pub fn initFromCapabilities(grants: []const Capability) GrantSet {
        var set: GrantSet = .{};
        for (grants) |grant| {
            switch (grant) {
                .io_read => set.io_read = true,
                .io_write => set.io_write = true,
                else => {},
            }
        }
        return set;
    }

    pub fn allows(self: GrantSet, grant: Grant) bool {
        return switch (grant) {
            .io_read => self.io_read,
            .io_write => self.io_write,
        };
    }
};

pub const Grant = enum {
    io_read,
    io_write,
};

pub const ParseError = error{
    OutOfMemory,
    InvalidFormat,
    InvalidCapability,
    InvalidSha256,
    DuplicateEntry,
    DuplicateMirror,
    DuplicateTargetHash,
    ForbiddenGlobalConfig,
    InvalidPath,
};

pub const RequireEntry = struct {
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    grants: []const Capability,
    upstream_loc: UpstreamLoc,

    pub fn deinit(self: *RequireEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.ref);
        allocator.free(self.grants);
        allocator.free(self.upstream_loc.file);
        self.* = undefined;
    }
};

pub const PluginRequireEntry = struct {
    identity: []const u8,
    ref: []const u8,
    abi: u32,
    upstream_loc: UpstreamLoc,

    pub fn deinit(self: *PluginRequireEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.identity);
        allocator.free(self.ref);
        allocator.free(self.upstream_loc.file);
        self.* = undefined;
    }
};

pub const PermissionSet = struct {
    name: []const u8,
    env: []const []const u8,
    read: []const []const u8,
    write: []const []const u8,
    net: []const []const u8,
    run: []const []const u8,
    upstream_loc: UpstreamLoc,

    pub fn deinit(self: *PermissionSet, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        freeStringList(allocator, self.env);
        freeStringList(allocator, self.read);
        freeStringList(allocator, self.write);
        freeStringList(allocator, self.net);
        freeStringList(allocator, self.run);
        allocator.free(self.upstream_loc.file);
        self.* = undefined;
    }
};

pub const MirrorRule = struct {
    host_pattern: []const u8,
    rewrite_to: []const u8,

    pub fn deinit(self: *MirrorRule, allocator: std.mem.Allocator) void {
        allocator.free(self.host_pattern);
        allocator.free(self.rewrite_to);
        self.* = undefined;
    }
};

pub const PackageDecl = struct {
    name: []const u8,
    upstream_loc: UpstreamLoc,

    pub fn deinit(self: *PackageDecl, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.upstream_loc.file);
        self.* = undefined;
    }
};

pub const WorkspaceDecl = struct {
    members: []const []const u8,
    default_member: ?[]const u8,
    upstream_loc: UpstreamLoc,

    pub fn deinit(self: *WorkspaceDecl, allocator: std.mem.Allocator) void {
        freeStringList(allocator, self.members);
        if (self.default_member) |member| allocator.free(member);
        allocator.free(self.upstream_loc.file);
        self.* = undefined;
    }
};

pub const Manifest = struct {
    package_decl: ?PackageDecl = null,
    workspace: ?WorkspaceDecl = null,
    requires: []RequireEntry,
    plugin_requires: []PluginRequireEntry,
    permission_sets: []PermissionSet,
    mirrors: []MirrorRule,

    pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        if (self.package_decl) |*package_decl| package_decl.deinit(allocator);
        if (self.workspace) |*workspace| workspace.deinit(allocator);
        for (self.requires) |*entry| entry.deinit(allocator);
        allocator.free(self.requires);
        for (self.plugin_requires) |*entry| entry.deinit(allocator);
        allocator.free(self.plugin_requires);
        for (self.permission_sets) |*set| set.deinit(allocator);
        allocator.free(self.permission_sets);
        for (self.mirrors) |*rule| rule.deinit(allocator);
        allocator.free(self.mirrors);
        self.* = undefined;
    }
};

pub const TargetHashMap = std.StringHashMap([32]u8);

pub const LockEntry = struct {
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    approved_machine_code_hashes: TargetHashMap,
    acknowledged_at_utc: i64,
    acknowledged_target_count: u8,

    pub fn deinit(self: *LockEntry, allocator: std.mem.Allocator) void {
        var it = self.approved_machine_code_hashes.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.approved_machine_code_hashes.deinit();
        allocator.free(self.url);
        allocator.free(self.ref);
        self.* = undefined;
    }
};

pub const LockFile = struct {
    entries: []LockEntry,

    pub fn deinit(self: *LockFile, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
        self.* = undefined;
    }
};

pub const LockManifest = LockFile;

pub const SumEntry = struct {
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    depth: u32,

    pub fn deinit(self: *SumEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.url);
        allocator.free(self.ref);
        self.* = undefined;
    }
};

pub const SumFile = struct {
    entries: []SumEntry,

    pub fn deinit(self: *SumFile, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| entry.deinit(allocator);
        allocator.free(self.entries);
        self.* = undefined;
    }
};

pub const SumManifest = SumFile;

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}

fn freeStringList(allocator: std.mem.Allocator, list: []const []const u8) void {
    for (list) |item| allocator.free(item);
    allocator.free(list);
}

fn cloneStringList(allocator: std.mem.Allocator, list: []const []const u8) ParseError![]const []const u8 {
    var out = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit();
    }

    for (list) |item| try out.append(try allocator.dupe(u8, item));
    return try out.toOwnedSlice();
}

fn cloneUpstreamLoc(allocator: std.mem.Allocator, loc: UpstreamLoc) ParseError!UpstreamLoc {
    return .{
        .file = try allocator.dupe(u8, loc.file),
        .line = loc.line,
        .col = loc.col,
    };
}

fn cloneRequireEntry(allocator: std.mem.Allocator, entry: RequireEntry) ParseError!RequireEntry {
    return .{
        .url = try allocator.dupe(u8, entry.url),
        .ref = try allocator.dupe(u8, entry.ref),
        .source_sha256 = entry.source_sha256,
        .grants = try allocator.dupe(Capability, entry.grants),
        .upstream_loc = try cloneUpstreamLoc(allocator, entry.upstream_loc),
    };
}

fn clonePluginRequireEntry(allocator: std.mem.Allocator, entry: PluginRequireEntry) ParseError!PluginRequireEntry {
    return .{
        .identity = try allocator.dupe(u8, entry.identity),
        .ref = try allocator.dupe(u8, entry.ref),
        .abi = entry.abi,
        .upstream_loc = try cloneUpstreamLoc(allocator, entry.upstream_loc),
    };
}

fn clonePermissionSet(allocator: std.mem.Allocator, set: PermissionSet) ParseError!PermissionSet {
    return .{
        .name = try allocator.dupe(u8, set.name),
        .env = try cloneStringList(allocator, set.env),
        .read = try cloneStringList(allocator, set.read),
        .write = try cloneStringList(allocator, set.write),
        .net = try cloneStringList(allocator, set.net),
        .run = try cloneStringList(allocator, set.run),
        .upstream_loc = try cloneUpstreamLoc(allocator, set.upstream_loc),
    };
}

fn cloneMirrorRule(allocator: std.mem.Allocator, rule: MirrorRule) ParseError!MirrorRule {
    return .{
        .host_pattern = try allocator.dupe(u8, rule.host_pattern),
        .rewrite_to = try allocator.dupe(u8, rule.rewrite_to),
    };
}

fn clonePackageDecl(allocator: std.mem.Allocator, package_decl: PackageDecl) ParseError!PackageDecl {
    return .{
        .name = try allocator.dupe(u8, package_decl.name),
        .upstream_loc = try cloneUpstreamLoc(allocator, package_decl.upstream_loc),
    };
}

fn cloneWorkspaceDecl(allocator: std.mem.Allocator, workspace: WorkspaceDecl) ParseError!WorkspaceDecl {
    return .{
        .members = try cloneStringList(allocator, workspace.members),
        .default_member = if (workspace.default_member) |member| try allocator.dupe(u8, member) else null,
        .upstream_loc = try cloneUpstreamLoc(allocator, workspace.upstream_loc),
    };
}

pub fn cloneManifest(allocator: std.mem.Allocator, source: Manifest) ParseError!Manifest {
    var requires = std.ArrayList(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }
    for (source.requires) |entry| try requires.append(try cloneRequireEntry(allocator, entry));

    var plugin_requires = std.ArrayList(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }
    for (source.plugin_requires) |entry| try plugin_requires.append(try clonePluginRequireEntry(allocator, entry));

    var permission_sets = std.ArrayList(PermissionSet).init(allocator);
    errdefer {
        for (permission_sets.items) |*set| set.deinit(allocator);
        permission_sets.deinit();
    }
    for (source.permission_sets) |set| try permission_sets.append(try clonePermissionSet(allocator, set));

    var mirrors = std.ArrayList(MirrorRule).init(allocator);
    errdefer {
        for (mirrors.items) |*rule| rule.deinit(allocator);
        mirrors.deinit();
    }
    for (source.mirrors) |rule| try mirrors.append(try cloneMirrorRule(allocator, rule));

    return .{
        .package_decl = if (source.package_decl) |package_decl| try clonePackageDecl(allocator, package_decl) else null,
        .workspace = if (source.workspace) |workspace| try cloneWorkspaceDecl(allocator, workspace) else null,
        .requires = try requires.toOwnedSlice(),
        .plugin_requires = try plugin_requires.toOwnedSlice(),
        .permission_sets = try permission_sets.toOwnedSlice(),
        .mirrors = try mirrors.toOwnedSlice(),
    };
}

fn permissionSetExists(entries: []const PermissionSet, name: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, name)) return true;
    }
    return false;
}

fn packageDeclEqual(a: PackageDecl, b: PackageDecl) bool {
    return std.mem.eql(u8, a.name, b.name);
}

fn requireEntryEquivalentForInstall(a: RequireEntry, b: RequireEntry) bool {
    return std.mem.eql(u8, a.url, b.url) and
        std.mem.eql(u8, a.ref, b.ref) and
        std.mem.eql(u8, a.source_sha256[0..], b.source_sha256[0..]);
}

fn mirrorRuleEquivalent(a: MirrorRule, b: MirrorRule) bool {
    return std.mem.eql(u8, a.host_pattern, b.host_pattern) and std.mem.eql(u8, a.rewrite_to, b.rewrite_to);
}

fn upsertMergedRequireEntry(
    allocator: std.mem.Allocator,
    requires: *std.ArrayList(RequireEntry),
    entry: RequireEntry,
    replace_existing: bool,
) ParseError!void {
    for (requires.items, 0..) |*existing, idx| {
        if (!std.mem.eql(u8, existing.url, entry.url) or !std.mem.eql(u8, existing.ref, entry.ref)) continue;
        if (!requireEntryEquivalentForInstall(existing.*, entry)) return ParseError.DuplicateEntry;
        if (replace_existing) {
            existing.deinit(allocator);
            requires.items[idx] = try cloneRequireEntry(allocator, entry);
        }
        return;
    }

    try requires.append(try cloneRequireEntry(allocator, entry));
}

fn upsertMergedPluginRequireEntry(
    allocator: std.mem.Allocator,
    plugin_requires: *std.ArrayList(PluginRequireEntry),
    entry: PluginRequireEntry,
) ParseError!void {
    for (plugin_requires.items) |existing| {
        if (!std.mem.eql(u8, existing.identity, entry.identity) or !std.mem.eql(u8, existing.ref, entry.ref)) continue;
        if (existing.abi != entry.abi) return ParseError.DuplicateEntry;
        return;
    }

    try plugin_requires.append(try clonePluginRequireEntry(allocator, entry));
}

fn upsertMergedMirrorRule(
    allocator: std.mem.Allocator,
    mirrors: *std.ArrayList(MirrorRule),
    rule: MirrorRule,
) ParseError!void {
    for (mirrors.items) |existing| {
        if (!std.mem.eql(u8, existing.host_pattern, rule.host_pattern)) continue;
        if (!mirrorRuleEquivalent(existing, rule)) return ParseError.DuplicateMirror;
        return;
    }

    try mirrors.append(try cloneMirrorRule(allocator, rule));
}

fn appendManifestEntries(
    allocator: std.mem.Allocator,
    source: *const Manifest,
    requires: *std.ArrayList(RequireEntry),
    plugin_requires: *std.ArrayList(PluginRequireEntry),
    permission_sets: *std.ArrayList(PermissionSet),
    mirrors: *std.ArrayList(MirrorRule),
    replace_existing_requires: bool,
) ParseError!void {
    for (source.requires) |entry| {
        try upsertMergedRequireEntry(allocator, requires, entry, replace_existing_requires);
    }
    for (source.plugin_requires) |entry| {
        try upsertMergedPluginRequireEntry(allocator, plugin_requires, entry);
    }
    for (source.permission_sets) |set| {
        if (permissionSetExists(permission_sets.items, set.name)) return ParseError.DuplicateEntry;
        try permission_sets.append(try clonePermissionSet(allocator, set));
    }
    for (source.mirrors) |rule| {
        try upsertMergedMirrorRule(allocator, mirrors, rule);
    }
}

pub fn mergeWorkspaceManifests(
    allocator: std.mem.Allocator,
    root_manifest: ?*const Manifest,
    member_manifest: ?*const Manifest,
) ParseError!Manifest {
    if (root_manifest == null and member_manifest == null) {
        return .{
            .package_decl = null,
            .workspace = null,
            .requires = try allocator.alloc(RequireEntry, 0),
            .plugin_requires = try allocator.alloc(PluginRequireEntry, 0),
            .permission_sets = try allocator.alloc(PermissionSet, 0),
            .mirrors = try allocator.alloc(MirrorRule, 0),
        };
    }

    var merged = Manifest{
        .package_decl = null,
        .workspace = null,
        .requires = try allocator.alloc(RequireEntry, 0),
        .plugin_requires = try allocator.alloc(PluginRequireEntry, 0),
        .permission_sets = try allocator.alloc(PermissionSet, 0),
        .mirrors = try allocator.alloc(MirrorRule, 0),
    };
    errdefer merged.deinit(allocator);

    var requires = std.ArrayList(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }
    var plugin_requires = std.ArrayList(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }
    var permission_sets = std.ArrayList(PermissionSet).init(allocator);
    errdefer {
        for (permission_sets.items) |*set| set.deinit(allocator);
        permission_sets.deinit();
    }
    var mirrors = std.ArrayList(MirrorRule).init(allocator);
    errdefer {
        for (mirrors.items) |*rule| rule.deinit(allocator);
        mirrors.deinit();
    }

    const sources = [_]?*const Manifest{ root_manifest, member_manifest };
    for (sources, 0..) |maybe_source, idx| {
        const source = maybe_source orelse continue;
        try appendManifestEntries(allocator, source, &requires, &plugin_requires, &permission_sets, &mirrors, idx != 0);
    }

    if (member_manifest) |member| {
        if (member.package_decl) |package_decl| {
            merged.package_decl = try clonePackageDecl(allocator, package_decl);
        }
    } else if (root_manifest) |root| {
        if (root.package_decl) |package_decl| {
            merged.package_decl = try clonePackageDecl(allocator, package_decl);
        }
        if (root.workspace) |workspace| {
            merged.workspace = try cloneWorkspaceDecl(allocator, workspace);
        }
    }

    if (root_manifest) |root| {
        if (merged.package_decl == null) {
            if (root.package_decl) |package_decl| {
                merged.package_decl = try clonePackageDecl(allocator, package_decl);
            }
        } else if (member_manifest != null and root.package_decl != null and !packageDeclEqual(root.package_decl.?, merged.package_decl.?)) {
            return ParseError.DuplicateEntry;
        }
    }

    merged.requires = try requires.toOwnedSlice();
    merged.plugin_requires = try plugin_requires.toOwnedSlice();
    merged.permission_sets = try permission_sets.toOwnedSlice();
    merged.mirrors = try mirrors.toOwnedSlice();
    return merged;
}

pub fn mergeWorkspaceMemberSet(
    allocator: std.mem.Allocator,
    root_manifest: ?*const Manifest,
    member_manifests: []const *const Manifest,
) ParseError!Manifest {
    var merged = Manifest{
        .package_decl = null,
        .workspace = null,
        .requires = try allocator.alloc(RequireEntry, 0),
        .plugin_requires = try allocator.alloc(PluginRequireEntry, 0),
        .permission_sets = try allocator.alloc(PermissionSet, 0),
        .mirrors = try allocator.alloc(MirrorRule, 0),
    };
    errdefer merged.deinit(allocator);

    var requires = std.ArrayList(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }
    var plugin_requires = std.ArrayList(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }
    var mirrors = std.ArrayList(MirrorRule).init(allocator);
    errdefer {
        for (mirrors.items) |*rule| rule.deinit(allocator);
        mirrors.deinit();
    }

    if (root_manifest) |root| {
        for (root.requires) |entry| {
            if (requireExists(requires.items, entry.url, entry.ref)) {
                for (requires.items) |existing| {
                    if (std.mem.eql(u8, existing.url, entry.url) and std.mem.eql(u8, existing.ref, entry.ref)) {
                        if (!requireEntryEquivalentForInstall(existing, entry)) return ParseError.DuplicateEntry;
                        break;
                    }
                }
                continue;
            }
            try requires.append(try cloneRequireEntry(allocator, entry));
        }
        for (root.plugin_requires) |entry| {
            if (pluginRequireExists(plugin_requires.items, entry.identity, entry.ref)) continue;
            try plugin_requires.append(try clonePluginRequireEntry(allocator, entry));
        }
        for (root.mirrors) |rule| {
            if (mirrorExists(mirrors.items, rule.host_pattern)) {
                for (mirrors.items) |existing| {
                    if (std.mem.eql(u8, existing.host_pattern, rule.host_pattern)) {
                        if (!mirrorRuleEquivalent(existing, rule)) return ParseError.DuplicateMirror;
                        break;
                    }
                }
                continue;
            }
            try mirrors.append(try cloneMirrorRule(allocator, rule));
        }
    }
    for (member_manifests) |member| {
        for (member.requires) |entry| {
            if (requireExists(requires.items, entry.url, entry.ref)) {
                for (requires.items) |existing| {
                    if (std.mem.eql(u8, existing.url, entry.url) and std.mem.eql(u8, existing.ref, entry.ref)) {
                        if (!requireEntryEquivalentForInstall(existing, entry)) return ParseError.DuplicateEntry;
                        break;
                    }
                }
                continue;
            }
            try requires.append(try cloneRequireEntry(allocator, entry));
        }
        for (member.plugin_requires) |entry| {
            if (pluginRequireExists(plugin_requires.items, entry.identity, entry.ref)) continue;
            try plugin_requires.append(try clonePluginRequireEntry(allocator, entry));
        }
        for (member.mirrors) |rule| {
            if (mirrorExists(mirrors.items, rule.host_pattern)) {
                for (mirrors.items) |existing| {
                    if (std.mem.eql(u8, existing.host_pattern, rule.host_pattern)) {
                        if (!mirrorRuleEquivalent(existing, rule)) return ParseError.DuplicateMirror;
                        break;
                    }
                }
                continue;
            }
            try mirrors.append(try cloneMirrorRule(allocator, rule));
        }
    }

    merged.requires = try requires.toOwnedSlice();
    merged.plugin_requires = try plugin_requires.toOwnedSlice();
    merged.permission_sets = try allocator.alloc(PermissionSet, 0);
    merged.mirrors = try mirrors.toOwnedSlice();
    return merged;
}

fn startsWithWord(text: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text, word)) return false;
    if (text.len == word.len) return true;
    const next = text[word.len];
    return std.ascii.isWhitespace(next) or next == '[' or next == '{' or next == '=' or next == ':' or next == '@';
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
                    if (i == 0 or std.ascii.isWhitespace(prev)) {
                        return line[0..i];
                    }
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

fn nextToken(text: []const u8, pos: *usize) ?[]const u8 {
    while (pos.* < text.len and std.ascii.isWhitespace(text[pos.*])) : (pos.* += 1) {}
    if (pos.* >= text.len) return null;
    const start = pos.*;
    while (pos.* < text.len and !std.ascii.isWhitespace(text[pos.*])) : (pos.* += 1) {}
    return text[start..pos.*];
}

fn splitAssignment(text: []const u8) ?struct { key: []const u8, value: []const u8 } {
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

fn parseTextValue(allocator: std.mem.Allocator, text: []const u8) ParseError![]const u8 {
    const trimmed = trim(text);
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        return allocator.dupe(u8, trimmed[1 .. trimmed.len - 1]);
    }
    if (trimmed.len == 0) return ParseError.InvalidFormat;
    return allocator.dupe(u8, trimmed);
}

fn parseSha256Bytes(text: []const u8) ParseError![32]u8 {
    const trimmed = trim(text);
    const unquoted = if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') trimmed[1 .. trimmed.len - 1] else trimmed;
    const body = if (std.mem.startsWith(u8, unquoted, "sha256:")) unquoted["sha256:".len..] else unquoted;
    if (body.len != 64) return ParseError.InvalidSha256;
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(bytes[0..], body) catch return ParseError.InvalidSha256;
    return bytes;
}

fn sha256Text(writer: anytype, hash: [32]u8) !void {
    const encoded = std.fmt.bytesToHex(hash, .lower);
    try writer.print("sha256:{s}", .{encoded[0..]});
}

fn bareHexText(writer: anytype, hash: [32]u8) !void {
    const encoded = std.fmt.bytesToHex(hash, .lower);
    try writer.print("{s}", .{encoded[0..]});
}

fn parseCapability(text: []const u8) ?Capability {
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

fn containsCapability(items: []const Capability, cap: Capability) bool {
    for (items) |item| {
        if (item == cap) return true;
    }
    return false;
}

fn parseCapabilityList(allocator: std.mem.Allocator, text: []const u8) ParseError![]const Capability {
    const trimmed = trim(text);
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') {
        return ParseError.InvalidFormat;
    }
    const body = trim(trimmed[1 .. trimmed.len - 1]);
    var list = std.ArrayList(Capability).init(allocator);
    errdefer list.deinit();

    if (body.len == 0) return try list.toOwnedSlice();

    var it = std.mem.splitScalar(u8, body, ',');
    while (it.next()) |fragment| {
        const token = trim(fragment);
        if (token.len == 0) return ParseError.InvalidFormat;
        const cap = parseCapability(token) orelse return ParseError.InvalidCapability;
        if (containsCapability(list.items, cap)) return ParseError.DuplicateEntry;
        try list.append(cap);
    }

    return try list.toOwnedSlice();
}

fn parseGrantsClause(allocator: std.mem.Allocator, text: []const u8) ParseError![]const Capability {
    const trimmed = trim(text);
    if (!startsWithWord(trimmed, "grants")) return ParseError.InvalidFormat;
    return try parseCapabilityList(allocator, trimmed["grants".len..]);
}

fn parseRequireEntry(
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

fn parseMirrorEntry(allocator: std.mem.Allocator, line: []const u8) ParseError!MirrorRule {
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

const PermissionSetBuilder = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    file: []const u8,
    line: u32,
    env: std.ArrayList([]const u8),
    read: std.ArrayList([]const u8),
    write: std.ArrayList([]const u8),
    net: std.ArrayList([]const u8),
    run: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, name: []const u8, source_file: []const u8, line_no: u32) ParseError!PermissionSetBuilder {
        return .{
            .allocator = allocator,
            .name = try allocator.dupe(u8, name),
            .file = try allocator.dupe(u8, source_file),
            .line = line_no,
            .env = std.ArrayList([]const u8).init(allocator),
            .read = std.ArrayList([]const u8).init(allocator),
            .write = std.ArrayList([]const u8).init(allocator),
            .net = std.ArrayList([]const u8).init(allocator),
            .run = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *PermissionSetBuilder) void {
        self.allocator.free(self.name);
        self.allocator.free(self.file);
        freeArrayListStrings(self.allocator, &self.env);
        freeArrayListStrings(self.allocator, &self.read);
        freeArrayListStrings(self.allocator, &self.write);
        freeArrayListStrings(self.allocator, &self.net);
        freeArrayListStrings(self.allocator, &self.run);
        self.* = undefined;
    }

    fn finish(self: *PermissionSetBuilder) ParseError!PermissionSet {
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

fn freeArrayListStrings(allocator: std.mem.Allocator, list: *std.ArrayList([]const u8)) void {
    for (list.items) |item| allocator.free(item);
    list.deinit();
}

fn parsePermissionSetHeader(allocator: std.mem.Allocator, line: []const u8, source_file: []const u8, line_no: u32) ParseError!PermissionSetBuilder {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "permission_set")) return ParseError.InvalidFormat;
    const name = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const tail = trim(line[pos..]);
    if (!std.mem.eql(u8, tail, "{")) return ParseError.InvalidFormat;
    return try PermissionSetBuilder.init(allocator, name, source_file, line_no);
}

fn parsePackageDecl(
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
    const file_copy = try allocator.dupe(u8, source_file);
    errdefer allocator.free(file_copy);
    return .{
        .name = name,
        .upstream_loc = .{ .file = file_copy, .line = line_no, .col = 1 },
    };
}

const WorkspaceBuilder = struct {
    allocator: std.mem.Allocator,
    file: []const u8,
    line: u32,
    members: std.ArrayList([]const u8),
    default_member: ?[]const u8 = null,

    fn init(allocator: std.mem.Allocator, source_file: []const u8, line_no: u32) ParseError!WorkspaceBuilder {
        return .{
            .allocator = allocator,
            .file = try allocator.dupe(u8, source_file),
            .line = line_no,
            .members = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *WorkspaceBuilder) void {
        self.allocator.free(self.file);
        freeArrayListStrings(self.allocator, &self.members);
        if (self.default_member) |member| self.allocator.free(member);
        self.* = undefined;
    }

    fn finish(self: *WorkspaceBuilder) ParseError!WorkspaceDecl {
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

fn parseWorkspaceHeader(allocator: std.mem.Allocator, line: []const u8, source_file: []const u8, line_no: u32) ParseError!WorkspaceBuilder {
    var pos: usize = 0;
    const keyword = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    if (!std.mem.eql(u8, keyword, "workspace")) return ParseError.InvalidFormat;
    const tail = trim(line[pos..]);
    if (!std.mem.eql(u8, tail, "{")) return ParseError.InvalidFormat;
    return try WorkspaceBuilder.init(allocator, source_file, line_no);
}

fn stringListContains(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) return true;
    }
    return false;
}

fn parseStringListInto(allocator: std.mem.Allocator, text: []const u8, list: *std.ArrayList([]const u8)) ParseError!void {
    const trimmed = trim(text);
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']') return ParseError.InvalidFormat;
    const body = trim(trimmed[1 .. trimmed.len - 1]);
    if (body.len == 0) return;
    var it = std.mem.splitScalar(u8, body, ',');
    while (it.next()) |fragment| {
        const token = trim(fragment);
        if (token.len == 0) return ParseError.InvalidFormat;
        try list.append(try parseTextValue(allocator, token));
    }
}

fn parseUniqueStringListInto(allocator: std.mem.Allocator, text: []const u8, list: *std.ArrayList([]const u8)) ParseError!void {
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

fn parsePermissionSetItem(builder: *PermissionSetBuilder, line: []const u8) ParseError!void {
    var pos: usize = 0;
    const key = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const value = trim(line[pos..]);
    if (std.mem.eql(u8, key, "env")) return parseStringListInto(builder.allocator, value, &builder.env);
    if (std.mem.eql(u8, key, "read")) return parseStringListInto(builder.allocator, value, &builder.read);
    if (std.mem.eql(u8, key, "write")) return parseStringListInto(builder.allocator, value, &builder.write);
    if (std.mem.eql(u8, key, "net")) return parseStringListInto(builder.allocator, value, &builder.net);
    if (std.mem.eql(u8, key, "run")) return parseStringListInto(builder.allocator, value, &builder.run);
    return ParseError.InvalidFormat;
}

fn parseWorkspaceItem(builder: *WorkspaceBuilder, line: []const u8) ParseError!void {
    var pos: usize = 0;
    const key = nextToken(line, &pos) orelse return ParseError.InvalidFormat;
    const value = trim(line[pos..]);
    if (std.mem.eql(u8, key, "members")) return parseUniqueStringListInto(builder.allocator, value, &builder.members);
    if (std.mem.eql(u8, key, "default_member")) {
        if (builder.default_member != null) return ParseError.DuplicateEntry;
        builder.default_member = try parseTextValue(builder.allocator, value);
        return;
    }
    return ParseError.InvalidFormat;
}

fn parsePluginRequireEntry(
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

fn requireExists(entries: []const RequireEntry, url: []const u8, ref: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.url, url) and std.mem.eql(u8, entry.ref, ref)) return true;
    }
    return false;
}

fn mirrorExists(entries: []const MirrorRule, host: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.host_pattern, host)) return true;
    }
    return false;
}

fn pluginRequireExists(entries: []const PluginRequireEntry, identity: []const u8, ref: []const u8) bool {
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.identity, identity) and std.mem.eql(u8, entry.ref, ref)) return true;
    }
    return false;
}

pub fn parseManifestWithFile(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_file: []const u8,
) ParseError!Manifest {
    if (source.len > max_manifest_bytes) return ParseError.InvalidFormat;

    if (std.mem.startsWith(u8, source_file, "~/.sa/") or std.mem.startsWith(u8, source_file, "/etc/sa/")) {
        return ParseError.ForbiddenGlobalConfig;
    }

    var requires = std.ArrayList(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }

    var mirrors = std.ArrayList(MirrorRule).init(allocator);
    errdefer {
        for (mirrors.items) |*rule| rule.deinit(allocator);
        mirrors.deinit();
    }

    var plugin_requires = std.ArrayList(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }

    var permission_sets = std.ArrayList(PermissionSet).init(allocator);
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
    var line_no: u32 = 0;
    var it = std.mem.splitScalar(u8, source, '\n');
    while (it.next()) |raw_line| {
        line_no += 1;
        const line = cleanLine(raw_line);
        if (line.len == 0) continue;
        if (line[0] == '#') continue;

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
            package_decl = try parsePackageDecl(allocator, line, line_no, source_file);
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

    if (permission_builder != null or workspace_builder != null) return ParseError.InvalidFormat;

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

pub fn writeManifest(writer: anytype, manifest: Manifest) !void {
    var wrote_section = false;

    if (manifest.package_decl) |package_decl| {
        try writer.print("package \"{s}\"\n", .{package_decl.name});
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
    var items = std.ArrayList(HashItem).init(allocator);
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
    var entries = std.ArrayList(LockEntry).init(allocator);
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
    var entries = std.ArrayList(SumEntry).init(allocator);
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

test "manifest parser preserves requires and mirrors" {
    const source =
        \\require github.com/xiaoming/sa-ecs @v1.2.0 sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        \\require github.com/org/sa-net @main sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210 grants [net_tx, net_rx]
        \\
        \\[mirrors]
        \\github.com = gitlab.corp.local/mirror
    ;

    var manifest = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer manifest.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), manifest.requires.len);
    try std.testing.expectEqual(@as(usize, 1), manifest.mirrors.len);
    try std.testing.expectEqualStrings("github.com/xiaoming/sa-ecs", manifest.requires[0].url);
    try std.testing.expectEqualStrings("v1.2.0", manifest.requires[0].ref);
    try std.testing.expectEqualStrings("pkg/sa.mod", manifest.requires[0].upstream_loc.file);
    try std.testing.expectEqual(@as(u32, 1), manifest.requires[0].upstream_loc.line);
    try std.testing.expectEqual(@as(u32, 1), manifest.requires[0].upstream_loc.col);
    try std.testing.expectEqual(@as(usize, 0), manifest.requires[0].grants.len);
    try std.testing.expectEqual(@as(usize, 2), manifest.requires[1].grants.len);
    try std.testing.expectEqual(Capability.net_tx, manifest.requires[1].grants[0]);
    try std.testing.expectEqual(Capability.net_rx, manifest.requires[1].grants[1]);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try writeManifest(out.writer(), manifest);

    var manifest2 = try parseManifestWithFile(std.testing.allocator, out.items, "pkg/sa.mod");
    defer manifest2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), manifest2.requires.len);
    try std.testing.expectEqualStrings(manifest.requires[1].url, manifest2.requires[1].url);
}

test "manifest parser preserves package and workspace declarations" {
    const source =
        \\package "root"
        \\
        \\workspace {
        \\  members ["crates/app", "crates/tool"]
        \\  default_member "app"
        \\}
        \\
        \\require github.com/org/sa-net @main sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210
    ;

    var parsed = try parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod");
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expect(parsed.package_decl != null);
    try std.testing.expectEqualStrings("root", parsed.package_decl.?.name);
    try std.testing.expect(parsed.workspace != null);
    try std.testing.expectEqual(@as(usize, 2), parsed.workspace.?.members.len);
    try std.testing.expectEqualStrings("crates/app", parsed.workspace.?.members[0]);
    try std.testing.expectEqualStrings("crates/tool", parsed.workspace.?.members[1]);
    try std.testing.expectEqualStrings("app", parsed.workspace.?.default_member.?);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try writeManifest(out.writer(), parsed);

    var reparsed = try parseManifestWithFile(std.testing.allocator, out.items, "pkg/sa.mod");
    defer reparsed.deinit(std.testing.allocator);
    try std.testing.expect(reparsed.package_decl != null);
    try std.testing.expect(reparsed.workspace != null);
    try std.testing.expectEqualStrings("root", reparsed.package_decl.?.name);
    try std.testing.expectEqualStrings("app", reparsed.workspace.?.default_member.?);
}

test "mergeWorkspaceManifests combines workspace root and member metadata" {
    const root_source =
        \\workspace {
        \\  members ["members/app"]
        \\  default_member "app"
        \\}
        \\
        \\require github.com/acme/shared @v1 sha256:1111111111111111111111111111111111111111111111111111111111111111
        \\require_plugin ../plugins/sa_plugin_demo @0.1.0 abi 1
        \\
        \\permission_set dev {
        \\  env [HOME]
        \\  read [/tmp]
        \\  write []
        \\  net [https://api.example.com]
        \\  run [/usr/bin/env]
        \\}
        \\
        \\[mirrors]
        \\github.com = mirror.local/github
    ;
    const member_source =
        \\package "app"
        \\
        \\require github.com/acme/app @v2 sha256:2222222222222222222222222222222222222222222222222222222222222222
    ;

    var root_manifest = try parseManifestWithFile(std.testing.allocator, root_source, "root/sa.mod");
    defer root_manifest.deinit(std.testing.allocator);
    var member_manifest = try parseManifestWithFile(std.testing.allocator, member_source, "root/members/app/sa.mod");
    defer member_manifest.deinit(std.testing.allocator);

    var merged = try mergeWorkspaceManifests(std.testing.allocator, &root_manifest, &member_manifest);
    defer merged.deinit(std.testing.allocator);

    try std.testing.expect(merged.package_decl != null);
    try std.testing.expectEqualStrings("app", merged.package_decl.?.name);
    try std.testing.expect(merged.workspace == null);
    try std.testing.expectEqual(@as(usize, 2), merged.requires.len);
    try std.testing.expectEqual(@as(usize, 1), merged.plugin_requires.len);
    try std.testing.expectEqual(@as(usize, 1), merged.permission_sets.len);
    try std.testing.expectEqual(@as(usize, 1), merged.mirrors.len);
}

test "mergeWorkspaceMemberSet deduplicates shared member dependencies for workspace install" {
    const root_source =
        \\workspace {
        \\  members ["members/app", "members/tool"]
        \\  default_member "app"
        \\}
        \\
        \\require github.com/acme/shared @v1 sha256:1111111111111111111111111111111111111111111111111111111111111111
        \\require_plugin ../plugins/shared @0.1.0 abi 1
    ;
    const app_source =
        \\package "app"
        \\
        \\require github.com/acme/common @v1 sha256:2222222222222222222222222222222222222222222222222222222222222222
        \\require_plugin ../plugins/shared @0.1.0 abi 1
    ;
    const tool_source =
        \\package "tool"
        \\
        \\require github.com/acme/common @v1 sha256:2222222222222222222222222222222222222222222222222222222222222222
        \\require github.com/acme/tool @v1 sha256:3333333333333333333333333333333333333333333333333333333333333333
    ;

    var root_manifest = try parseManifestWithFile(std.testing.allocator, root_source, "root/sa.mod");
    defer root_manifest.deinit(std.testing.allocator);
    var app_manifest = try parseManifestWithFile(std.testing.allocator, app_source, "root/members/app/sa.mod");
    defer app_manifest.deinit(std.testing.allocator);
    var tool_manifest = try parseManifestWithFile(std.testing.allocator, tool_source, "root/members/tool/sa.mod");
    defer tool_manifest.deinit(std.testing.allocator);

    const members = [_]*const Manifest{ &app_manifest, &tool_manifest };
    var merged = try mergeWorkspaceMemberSet(std.testing.allocator, &root_manifest, members[0..]);
    defer merged.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), merged.requires.len);
    try std.testing.expectEqual(@as(usize, 1), merged.plugin_requires.len);
    try std.testing.expectEqual(@as(usize, 0), merged.permission_sets.len);
}

test "manifest parser rejects oversized source" {
    const source = try std.testing.allocator.alloc(u8, max_manifest_bytes + 1);
    defer std.testing.allocator.free(source);
    @memset(source, ' ');

    try std.testing.expectError(ParseError.InvalidFormat, parseManifestWithFile(std.testing.allocator, source, "pkg/sa.mod"));
}

test "lock parser preserves dependency blocks and target hashes" {
    const source =
        \\dependency "github.com/hacker/bad-lib" {
        \\    version: "v1.2.0"
        \\    source_sha: "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
        \\    approved_machine_code_hashes {
        \\        x86_64-linux-gnu = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        \\        default = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        \\    }
        \\    acknowledged_at_utc: 42
        \\    acknowledged_target_count: 2
        \\}
    ;

    var lock_file = try parseLock(std.testing.allocator, source);
    defer lock_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), lock_file.entries.len);
    const entry = lock_file.entries[0];
    try std.testing.expectEqualStrings("github.com/hacker/bad-lib", entry.url);
    try std.testing.expectEqualStrings("v1.2.0", entry.ref);
    try std.testing.expectEqual(@as(u8, 2), entry.acknowledged_target_count);
    try std.testing.expectEqual(@as(i64, 42), entry.acknowledged_at_utc);
    try std.testing.expectEqual(@as(usize, 2), entry.approved_machine_code_hashes.count());
    try std.testing.expect(entry.approved_machine_code_hashes.contains("x86_64-linux-gnu"));
    try std.testing.expect(entry.approved_machine_code_hashes.contains(""));

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try writeLock(out.writer(), lock_file);

    var lock_file2 = try parseLock(std.testing.allocator, out.items);
    defer lock_file2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), lock_file2.entries.len);
    try std.testing.expectEqualStrings(lock_file.entries[0].url, lock_file2.entries[0].url);
}

test "sum parser preserves depth and sha256" {
    const source =
        \\github.com/xiaoming/sa-ecs @v1.2.0 sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
        \\github.com/transitive/dep @v0.1.0 sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210 depth: 2
    ;

    var sum_file = try parseSum(std.testing.allocator, source);
    defer sum_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), sum_file.entries.len);
    try std.testing.expectEqual(@as(u32, 2), sum_file.entries[1].depth);

    var out = std.ArrayList(u8).init(std.testing.allocator);
    defer out.deinit();
    try writeSum(out.writer(), sum_file);

    var sum_file2 = try parseSum(std.testing.allocator, out.items);
    defer sum_file2.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), sum_file2.entries.len);
    try std.testing.expectEqual(@as(u32, 2), sum_file2.entries[1].depth);
}

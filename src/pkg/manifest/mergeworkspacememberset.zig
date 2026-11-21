const std = @import("std");
const mirrorExists = @import("permissionsetbuilder.zig").mirrorExists;
const pluginRequireExists = @import("permissionsetbuilder.zig").pluginRequireExists;
const requireExists = @import("permissionsetbuilder.zig").requireExists;


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
    version: ?[]const u8 = null,
    abi: ?u32 = null,
    features: []const []const u8,
    upstream_loc: UpstreamLoc,

    pub fn deinit(self: *PackageDecl, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        if (self.version) |version| allocator.free(version);
        freeStringList(allocator, self.features);
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

pub fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r");
}

fn freeStringList(allocator: std.mem.Allocator, list: []const []const u8) void {
    for (list) |item| allocator.free(item);
    allocator.free(list);
}

fn cloneStringList(allocator: std.mem.Allocator, list: []const []const u8) ParseError![]const []const u8 {
    var out = std.array_list.Managed([]const u8).init(allocator);
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
        .version = if (package_decl.version) |version| try allocator.dupe(u8, version) else null,
        .abi = package_decl.abi,
        .features = try cloneStringList(allocator, package_decl.features),
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
    var requires = std.array_list.Managed(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }
    for (source.requires) |entry| try requires.append(try cloneRequireEntry(allocator, entry));

    var plugin_requires = std.array_list.Managed(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }
    for (source.plugin_requires) |entry| try plugin_requires.append(try clonePluginRequireEntry(allocator, entry));

    var permission_sets = std.array_list.Managed(PermissionSet).init(allocator);
    errdefer {
        for (permission_sets.items) |*set| set.deinit(allocator);
        permission_sets.deinit();
    }
    for (source.permission_sets) |set| try permission_sets.append(try clonePermissionSet(allocator, set));

    var mirrors = std.array_list.Managed(MirrorRule).init(allocator);
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

pub fn packageDeclEqual(a: PackageDecl, b: PackageDecl) bool {
    if (!std.mem.eql(u8, a.name, b.name) or a.abi != b.abi) return false;
    if (a.version == null or b.version == null) {
        if (a.version != null or b.version != null) return false;
    } else if (!std.mem.eql(u8, a.version.?, b.version.?)) {
        return false;
    }
    if (a.features.len != b.features.len) return false;
    for (a.features, b.features) |left, right| {
        if (!std.mem.eql(u8, left, right)) return false;
    }
    return true;
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
    requires: *std.array_list.Managed(RequireEntry),
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
    plugin_requires: *std.array_list.Managed(PluginRequireEntry),
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
    mirrors: *std.array_list.Managed(MirrorRule),
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
    requires: *std.array_list.Managed(RequireEntry),
    plugin_requires: *std.array_list.Managed(PluginRequireEntry),
    permission_sets: *std.array_list.Managed(PermissionSet),
    mirrors: *std.array_list.Managed(MirrorRule),
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

    var requires = std.array_list.Managed(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
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
    var mirrors = std.array_list.Managed(MirrorRule).init(allocator);
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

    var requires = std.array_list.Managed(RequireEntry).init(allocator);
    errdefer {
        for (requires.items) |*entry| entry.deinit(allocator);
        requires.deinit();
    }
    var plugin_requires = std.array_list.Managed(PluginRequireEntry).init(allocator);
    errdefer {
        for (plugin_requires.items) |*entry| entry.deinit(allocator);
        plugin_requires.deinit();
    }
    var mirrors = std.array_list.Managed(MirrorRule).init(allocator);
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

pub fn startsWithWord(text: []const u8, word: []const u8) bool {
    if (!std.mem.startsWith(u8, text, word)) return false;
    if (text.len == word.len) return true;
    const next = text[word.len];
    return std.ascii.isWhitespace(next) or next == '[' or next == '{' or next == '=' or next == ':' or next == '@';
}

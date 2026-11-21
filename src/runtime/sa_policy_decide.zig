const std = @import("std");
const Category = @import("sa_policy.zig").Category;
const CategoryPolicy = @import("sa_policy.zig").CategoryPolicy;
const Mode = @import("sa_policy.zig").Mode;
const NetResource = @import("sa_policy.zig").NetResource;
const Policy = @import("sa_policy.zig").Policy;
const Resource = @import("sa_policy.zig").Resource;

pub fn resourceKey(allocator: std.mem.Allocator, resource: Resource) ![]u8 {
    return switch (resource) {
        .net => |net| try std.fmt.allocPrint(allocator, "{s}:{d}", .{ net.host, net.port }),
        .fs => |fsr| try std.fmt.allocPrint(allocator, "{s}:{s}", .{ if (fsr.write) "write" else "read", fsr.path }),
        .env => |key| try allocator.dupe(u8, key),
        .run => |program| try allocator.dupe(u8, program),
        .time => try allocator.dupe(u8, "time"),
        .random => try allocator.dupe(u8, "random"),
    };
}

pub fn stringListHas(list: []const []const u8, value: []const u8) bool {
    for (list) |entry| {
        if (std.mem.eql(u8, entry, value)) return true;
    }
    return false;
}

pub fn fsListAllows(list: []const []const u8, path: []const u8) bool {
    for (list) |entry| {
        const prefix = std.mem.trimEnd(u8, entry, "/");
        if (std.mem.eql(u8, path, prefix)) return true;
        if (std.mem.startsWith(u8, path, prefix) and path.len > prefix.len and path[prefix.len] == '/') return true;
    }
    return false;
}

pub fn parseIpv4(text: []const u8) ?u32 {
    var parts = std.mem.splitScalar(u8, text, '.');
    var value: u32 = 0;
    var count: usize = 0;
    while (parts.next()) |part| {
        if (part.len == 0 or part.len > 3) return null;
        const octet = std.fmt.parseInt(u32, part, 10) catch return null;
        if (octet > 255) return null;
        value = (value << 8) | octet;
        count += 1;
    }
    if (count != 4) return null;
    if (parts.next() != null) return null;
    return value;
}

pub fn netEntryMatches(entry: []const u8, resource: NetResource) bool {
    const colon = std.mem.lastIndexOfScalar(u8, entry, ':') orelse return false;
    const entry_host = entry[0..colon];
    const entry_port = entry[colon + 1 ..];
    if (!std.mem.eql(u8, entry_port, "*")) {
        const port = std.fmt.parseInt(u32, entry_port, 10) catch return false;
        if (port != resource.port) return false;
    }
    if (std.mem.indexOfScalar(u8, entry_host, '/')) |slash| {
        // CIDR entry: only matches IPv4-literal resource hosts.
        const prefix_len = std.fmt.parseInt(u32, entry_host[slash + 1 ..], 10) catch return false;
        if (prefix_len > 32) return false;
        const network = parseIpv4(entry_host[0..slash]) orelse return false;
        const host_ip = parseIpv4(resource.host) orelse return false;
        if (prefix_len == 0) return true;
        const shift: u5 = @intCast(32 - prefix_len);
        return (network >> shift) == (host_ip >> shift);
    }
    return std.ascii.eqlIgnoreCase(entry_host, resource.host);
}

pub fn netListAllows(list: []const []const u8, resource: NetResource) bool {
    for (list) |entry| {
        if (netEntryMatches(entry, resource)) return true;
    }
    return false;
}

pub fn modeNarrowsTo(child: Mode, parent: Mode) bool {
    if (child == .deny) return true;
    return switch (child) {
        .deny => unreachable,
        .allow_list => parent == .allow_list or parent == .audit or parent == .allow,
        .audit => parent == .audit or parent == .allow,
        .ask => parent == .ask,
        .allow => parent == .allow,
    };
}

pub fn listSubset(child: []const []const u8, parent: []const []const u8) bool {
    for (child) |entry| {
        if (!stringListHas(parent, entry)) return false;
    }
    return true;
}

pub fn fsEntriesSubset(child: []const []const u8, parent: []const []const u8) bool {
    // A child fs prefix narrows a parent prefix when it equals it or
    // lives strictly underneath it.
    for (child) |entry| {
        var covered = false;
        for (parent) |parent_entry| {
            const prefix = std.mem.trimEnd(u8, parent_entry, "/");
            if (std.mem.eql(u8, entry, prefix)) covered = true;
            if (std.mem.startsWith(u8, entry, prefix) and entry.len > prefix.len and entry[prefix.len] == '/') covered = true;
        }
        if (!covered) return false;
    }
    return true;
}

pub fn categoryNarrowsTo(child: *const CategoryPolicy, parent: *const CategoryPolicy, category: Category) bool {
    if (!modeNarrowsTo(child.mode, parent.mode)) return false;
    if (child.mode == .allow_list and parent.mode == .allow_list) {
        if (category == .fs) {
            return fsEntriesSubset(child.read, parent.read) and fsEntriesSubset(child.write, parent.write);
        }
        return listSubset(child.allow, parent.allow);
    }
    return true;
}

pub fn policyNarrowsTo(child: *const Policy, parent: *const Policy) bool {
    inline for ([_]Category{ .net, .fs, .env, .run, .time, .random }) |category| {
        if (!categoryNarrowsTo(child.categoryPolicyConst(category), parent.categoryPolicyConst(category), category)) return false;
    }
    return true;
}

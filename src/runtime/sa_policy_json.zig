const std = @import("std");
const sa_std = @import("sa_policy.zig");
const Category = @import("sa_policy.zig").Category;
const CategoryPolicy = @import("sa_policy.zig").CategoryPolicy;
const Mode = @import("sa_policy.zig").Mode;
const Policy = @import("sa_policy.zig").Policy;
const PolicyContext = @import("sa_policy.zig").PolicyContext;
const default_token_ttl_ns = @import("sa_policy.zig").default_token_ttl_ns;

pub fn escapeJson(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    for (text) |byte| {
        switch (byte) {
            '"' => try out.appendSlice("\\\""),
            '\\' => try out.appendSlice("\\\\"),
            '\n' => try out.appendSlice("\\n"),
            '\r' => try out.appendSlice("\\r"),
            '\t' => try out.appendSlice("\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => {
                const hex = try std.fmt.allocPrint(allocator, "\\u{x:0>4}", .{byte});
                defer allocator.free(hex);
                try out.appendSlice(hex);
            },
            else => try out.append(byte),
        }
    }
    return try out.toOwnedSlice();
}

pub fn jsonString(value: std.json.Value) ![]const u8 {
    return switch (value) {
        .string => |text| text,
        else => error.InvalidPolicy,
    };
}

pub fn jsonObject(value: std.json.Value) !std.json.ObjectMap {
    return switch (value) {
        .object => |object| object,
        else => error.InvalidPolicy,
    };
}

pub fn collectJsonStrings(allocator: std.mem.Allocator, value: ?std.json.Value) ![][]u8 {
    const array = switch (value orelse return error.InvalidPolicy) {
        .array => |items| items,
        else => return error.InvalidPolicy,
    };
    var out = std.array_list.Managed([]u8).init(allocator);
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit();
    }
    for (array.items) |item| {
        try out.append(try allocator.dupe(u8, try jsonString(item)));
    }
    return try out.toOwnedSlice();
}

pub fn parseMode(text: []const u8) !Mode {
    if (std.mem.eql(u8, text, "allow")) return .allow;
    if (std.mem.eql(u8, text, "deny")) return .deny;
    if (std.mem.eql(u8, text, "allow-list")) return .allow_list;
    if (std.mem.eql(u8, text, "audit")) return .audit;
    if (std.mem.eql(u8, text, "ask")) return .ask;
    return error.InvalidPolicy;
}

pub fn parseCategoryPolicy(allocator: std.mem.Allocator, value: std.json.Value, category: Category) !CategoryPolicy {
    const object = try jsonObject(value);
    var result = CategoryPolicy{};
    errdefer result.deinit(allocator);
    var has_lists = false;
    var it = object.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "mode")) {
            result.mode = try parseMode(try jsonString(entry.value_ptr.*));
        } else if (std.mem.eql(u8, key, "allow")) {
            if (category == .fs or category == .time or category == .random) return error.InvalidPolicy;
            result.allow = try collectJsonStrings(allocator, entry.value_ptr.*);
            has_lists = true;
        } else if (std.mem.eql(u8, key, "read")) {
            if (category != .fs) return error.InvalidPolicy;
            result.read = try collectJsonStrings(allocator, entry.value_ptr.*);
            has_lists = true;
        } else if (std.mem.eql(u8, key, "write")) {
            if (category != .fs) return error.InvalidPolicy;
            result.write = try collectJsonStrings(allocator, entry.value_ptr.*);
            has_lists = true;
        } else {
            return error.InvalidPolicy;
        }
    }
    // A category that lists resources but names no mode is an
    // allow-list; an explicit mode always wins.
    if (has_lists and object.get("mode") == null) result.mode = .allow_list;
    return result;
}

pub fn parsePolicyJson(allocator: std.mem.Allocator, text: []const u8) !Policy {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    const root = try jsonObject(parsed.value);
    var policy = Policy{};
    errdefer policy.deinit(allocator);
    var it = root.iterator();
    while (it.next()) |entry| {
        const key = entry.key_ptr.*;
        if (std.mem.eql(u8, key, "permissions")) {
            const permissions = try jsonObject(entry.value_ptr.*);
            var pit = permissions.iterator();
            while (pit.next()) |category_entry| {
                const name = category_entry.key_ptr.*;
                const category = categoryFromName(name) orelse return error.InvalidPolicy;
                const parsed_policy = try parseCategoryPolicy(allocator, category_entry.value_ptr.*, category);
                var slot = policy.categoryPolicy(category);
                slot.deinit(allocator);
                slot.* = parsed_policy;
            }
        } else if (std.mem.eql(u8, key, "audit")) {
            const audit = try jsonObject(entry.value_ptr.*);
            var ait = audit.iterator();
            while (ait.next()) |audit_entry| {
                if (std.mem.eql(u8, audit_entry.key_ptr.*, "sink")) {
                    policy.audit_sink = try allocator.dupe(u8, try jsonString(audit_entry.value_ptr.*));
                } else if (std.mem.eql(u8, audit_entry.key_ptr.*, "events")) {
                    policy.audit_events = try collectJsonStrings(allocator, audit_entry.value_ptr.*);
                } else {
                    return error.InvalidPolicy;
                }
            }
        } else {
            return error.InvalidPolicy;
        }
    }
    return policy;
}

pub const TokenSpec = struct {
    category: Category,
    key: []const u8,
    ttl_ns: i64 = default_token_ttl_ns,
};

pub fn parseTokenSpecsJson(allocator: std.mem.Allocator, text: []const u8) ![]TokenSpec {
    const parsed = try std.json.parseFromSlice(std.json.Value, allocator, text, .{});
    defer parsed.deinit();
    if (parsed.value != .array) return error.InvalidPolicy;
    var specs = std.array_list.Managed(TokenSpec).init(allocator);
    errdefer {
        for (specs.items) |spec| allocator.free(spec.key);
        specs.deinit();
    }
    for (parsed.value.array.items) |item| {
        const object = try jsonObject(item);
        var category: ?Category = null;
        var key: ?[]const u8 = null;
        var ttl_ns: i64 = default_token_ttl_ns;
        var it = object.iterator();
        while (it.next()) |entry| {
            if (std.mem.eql(u8, entry.key_ptr.*, "category")) {
                category = categoryFromName(try jsonString(entry.value_ptr.*)) orelse return error.InvalidPolicy;
            } else if (std.mem.eql(u8, entry.key_ptr.*, "key")) {
                key = try jsonString(entry.value_ptr.*);
            } else if (std.mem.eql(u8, entry.key_ptr.*, "ttl_s")) {
                if (entry.value_ptr.* != .integer) return error.InvalidPolicy;
                const seconds = entry.value_ptr.integer;
                if (seconds < 1 or seconds > 3600) return error.InvalidPolicy;
                ttl_ns = seconds * std.time.ns_per_s;
            } else {
                return error.InvalidPolicy;
            }
        }
        const cat = category orelse return error.InvalidPolicy;
        const k = key orelse return error.InvalidPolicy;
        if (k.len == 0 or k.len > 4096) return error.InvalidPolicy;
        try specs.append(.{ .category = cat, .key = try allocator.dupe(u8, k), .ttl_ns = ttl_ns });
    }
    return try specs.toOwnedSlice();
}

pub fn freeTokenSpecs(allocator: std.mem.Allocator, specs: []TokenSpec) void {
    for (specs) |spec| allocator.free(spec.key);
    allocator.free(specs);
}

pub fn mintTokenSpecs(context: *PolicyContext, allocator: std.mem.Allocator, specs: []const TokenSpec, now_ns: i64) !void {
    for (specs) |spec| {
        try context.mintToken(allocator, spec.category, spec.key, now_ns, spec.ttl_ns);
    }
}

pub fn categoryFromName(name: []const u8) ?Category {
    inline for ([_]Category{ .net, .fs, .env, .run, .time, .random }) |category| {
        if (std.mem.eql(u8, name, @tagName(category))) return category;
    }
    return null;
}

pub fn dupeStrings(allocator: std.mem.Allocator, items: []const []const u8) ![][]u8 {
    var out = std.array_list.Managed([]u8).init(allocator);
    errdefer {
        for (out.items) |item| allocator.free(item);
        out.deinit();
    }
    for (items) |item| try out.append(try allocator.dupe(u8, item));
    return try out.toOwnedSlice();
}

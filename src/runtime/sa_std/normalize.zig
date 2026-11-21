const std = @import("std");
const jsonStringValue = @import("../sa_std.zig").jsonStringValue;

fn normalizeMcpServerNameAlloc(allocator: std.mem.Allocator, server: []const u8) ![]u8 {
    if (std.mem.eql(u8, server, "Code Index") or
        std.mem.eql(u8, server, "code-index") or
        std.mem.eql(u8, server, "code_index"))
    {
        return allocator.dupe(u8, "mcp__code_index__");
    }
    if (std.mem.eql(u8, server, "Mimir") or std.mem.eql(u8, server, "mimir")) {
        return allocator.dupe(u8, "mcp__mimir__");
    }
    if (std.mem.startsWith(u8, server, "mcp__mcp_") and std.mem.endsWith(u8, server, "___") and server.len > 11) {
        const inner = server[9 .. server.len - 3];
        var out = std.array_list.Managed(u8).init(allocator);
        errdefer out.deinit();
        try out.appendSlice("mcp__");
        try out.appendSlice(inner);
        try out.appendSlice("__");
        return try out.toOwnedSlice();
    }
    if (std.mem.startsWith(u8, server, "mcp__") and std.mem.endsWith(u8, server, "__") and server.len > 7) {
        return allocator.dupe(u8, server);
    }

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try out.appendSlice("mcp__");
    var last_sep = false;
    for (server) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            try out.append(std.ascii.toLower(ch));
            last_sep = false;
        } else if (!last_sep) {
            try out.append('_');
            last_sep = true;
        }
    }
    while (out.items.len > 5 and out.items[out.items.len - 1] == '_') _ = out.pop();
    try out.appendSlice("__");
    return try out.toOwnedSlice();
}

fn normalizeResponsesRequestArgumentsString(allocator: std.mem.Allocator, arguments: []const u8) !?[]u8 {
    var args_value = std.json.parseFromSliceLeaky(std.json.Value, allocator, arguments, .{}) catch return null;
    const args_object = switch (args_value) {
        .object => |*object| object,
        else => return null,
    };
    const server_ptr = args_object.getPtr("server") orelse return null;
    const server = jsonStringValue(server_ptr.*);
    if (server.len == 0) return null;
    const normalized = try normalizeMcpServerNameAlloc(allocator, server);
    if (std.mem.eql(u8, normalized, server)) return null;
    server_ptr.* = .{ .string = normalized };
    return try std.json.Stringify.valueAlloc(allocator, args_value, .{});
}

fn normalizeResponsesRequestValue(allocator: std.mem.Allocator, value: *std.json.Value) !bool {
    switch (value.*) {
        .object => |*object| {
            var changed = false;
            const item_type = jsonStringValue(object.get("type"));
            if (std.mem.eql(u8, item_type, "function_call")) {
                if (object.getPtr("arguments")) |arguments_ptr| {
                    const arguments = jsonStringValue(arguments_ptr.*);
                    if (arguments.len != 0) {
                        if (try normalizeResponsesRequestArgumentsString(allocator, arguments)) |normalized_arguments| {
                            arguments_ptr.* = .{ .string = normalized_arguments };
                            changed = true;
                        }
                    }
                }
            }
            var it = object.iterator();
            while (it.next()) |entry| {
                if (try normalizeResponsesRequestValue(allocator, entry.value_ptr)) changed = true;
            }
            return changed;
        },
        .array => |*array| {
            var changed = false;
            for (array.items) |*item| {
                if (try normalizeResponsesRequestValue(allocator, item)) changed = true;
            }
            return changed;
        },
        else => return false,
    }
}

pub fn denoResponsesRequestNormalize(body: []const u8) ![]u8 {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    var value = std.json.parseFromSliceLeaky(std.json.Value, arena.allocator(), body, .{}) catch {
        return std.heap.page_allocator.dupe(u8, body);
    };
    const changed = try normalizeResponsesRequestValue(arena.allocator(), &value);
    if (!changed) return std.heap.page_allocator.dupe(u8, body);
    return try std.json.Stringify.valueAlloc(std.heap.page_allocator, value, .{});
}

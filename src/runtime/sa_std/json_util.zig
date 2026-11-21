const std = @import("std");
const registerResource = @import("../sa_std.zig").registerResource;

pub fn jsonTextSlice(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        .number_string => |text| text,
        else => null,
    };
}

fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var list = std.array_list.Managed(u8).init(allocator);
    errdefer list.deinit();
    try stringifyToList(&list, value);
    return try list.toOwnedSlice();
}

pub fn jsonSerializeBuffer(allocator: std.mem.Allocator, value: std.json.Value) !u64 {
    const bytes = try jsonStringifyAlloc(allocator, value);
    return registerResource(.{ .json_buffer = .{ .allocator = allocator, .bytes = bytes } }) catch |err| {
        allocator.free(bytes);
        return err;
    };
}

const ListWriter = struct {
    list: *std.array_list.Managed(u8),
    pub fn writeAll(self: ListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(bytes);
    }
    pub fn writeByte(self: ListWriter, byte: u8) !void {
        try self.list.append(byte);
    }
    pub fn print(self: ListWriter, comptime fmt: []const u8, args: anytype) !void {
        var aw: std.Io.Writer.Allocating = .init(self.list.allocator);
        defer aw.deinit();
        try aw.writer.print(fmt, args);
        try self.list.appendSlice(aw.written());
    }
};

pub fn listWriter(list: *std.array_list.Managed(u8)) ListWriter {
    return .{ .list = list };
}

pub fn stringifyToList(list: *std.array_list.Managed(u8), value: anytype) !void {
    var aw: std.Io.Writer.Allocating = .init(list.allocator);
    defer aw.deinit();
    try std.json.Stringify.value(value, .{}, &aw.writer);
    try list.appendSlice(aw.written());
}

pub fn appendJsonString(writer: ListWriter, text: []const u8) !void {
    try stringifyToList(writer.list, text);
}

fn jsonStringLiteralAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendJsonString(listWriter(&out), text);
    return try out.toOwnedSlice();
}

fn jsonRpcParamLookupKey(key: []const u8) []const u8 {
    if (key.len > 2 and key[0] == '"') {
        if (std.mem.indexOfScalar(u8, key[1..], '"')) |end| {
            if (end > 0) return key[1 .. 1 + end];
        }
    }
    return key;
}

pub fn jsonRpcParamsStringLiteralAlloc(body: []const u8, key: []const u8, fallback: []const u8, emit_null_if_missing: bool) ![]u8 {
    const lookup_key = jsonRpcParamLookupKey(key);
    if (lookup_key.len != 0) {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch null;
        if (parsed) |*document| {
            defer document.deinit();
            if (jsonObjectGetValue(document.value, "params")) |params| {
                if (jsonObjectGetValue(params, lookup_key)) |value| {
                    if (jsonTextSlice(value)) |text| {
                        return try jsonStringLiteralAlloc(std.heap.page_allocator, text);
                    }
                }
            }
        }
    }

    if (emit_null_if_missing) return try std.heap.page_allocator.dupe(u8, "null");
    return try jsonStringLiteralAlloc(std.heap.page_allocator, fallback);
}

pub fn jsonObjectGetValue(value: std.json.Value, key: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(key),
        else => null,
    };
}

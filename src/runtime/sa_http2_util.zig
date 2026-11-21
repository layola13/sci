const std = @import("std");
const sa_std = @import("sa_http2.zig");
const sio = @import("sa_http2.zig").sio;

pub fn u64ToUsize(v: u64) ?usize {
    return std.math.cast(usize, v);
}

pub fn registerBuffer(bytes: []u8) u64 {
    sa_std.buffer_registry_mutex.lockUncancelable(sio.io());
    defer sa_std.buffer_registry_mutex.unlock(sio.io());
    var i: usize = 0;
    while (i < sa_std.buffer_slots.items.len) : (i += 1) {
        if (sa_std.buffer_slots.items[i] == null) {
            sa_std.buffer_slots.items[i] = .{ .bytes = bytes };
            return @intCast(i + 1);
        }
    }
    sa_std.buffer_slots.append(std.heap.page_allocator, .{ .bytes = bytes }) catch {
        std.heap.page_allocator.free(bytes);
        return 0;
    };
    return @intCast(sa_std.buffer_slots.items.len);
}

pub fn takeBuffer(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    sa_std.buffer_registry_mutex.lockUncancelable(sio.io());
    defer sa_std.buffer_registry_mutex.unlock(sio.io());
    const idx: usize = @intCast(handle - 1);
    if (idx >= sa_std.buffer_slots.items.len) return null;
    const entry = sa_std.buffer_slots.items[idx] orelse return null;
    return entry.bytes;
}

pub fn registerOwnedString(text: []const u8) u64 {
    const owned = std.heap.page_allocator.dupe(u8, text) catch return 0;
    return registerBuffer(owned);
}

pub fn managedPrint(list: *std.array_list.Managed(u8), comptime fmt: []const u8, args: anytype) !void {
    var aw: std.Io.Writer.Allocating = .init(list.allocator);
    defer aw.deinit();
    try aw.writer.print(fmt, args);
    try list.appendSlice(aw.written());
}

pub fn jsonEscapeAppend(out: *std.array_list.Managed(u8), bytes: []const u8) !void {
    for (bytes) |b| switch (b) {
        '"' => try out.appendSlice("\\\""),
        '\\' => try out.appendSlice("\\\\"),
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        else => if (b < 0x20) try managedPrint(out, "\\u{x:0>4}", .{b}) else try out.append(b),
    };
}

pub fn appendJsonString(out: *std.array_list.Managed(u8), bytes: []const u8) !void {
    try out.append('"');
    try jsonEscapeAppend(out, bytes);
    try out.append('"');
}

pub fn appendStringArray(out: *std.array_list.Managed(u8), items: []const []const u8) !void {
    try out.append('[');
    for (items, 0..) |item, i| {
        if (i != 0) try out.append(',');
        try appendJsonString(out, item);
    }
    try out.append(']');
}

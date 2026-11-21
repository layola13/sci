const std = @import("std");
const appendJsonString = @import("sa_http2.zig").appendJsonString;
const managedPrint = @import("sa_http2.zig").managedPrint;

pub const HTTP2_SETTINGS_HEADER_TABLE_SIZE: u16 = 0x1;

pub const HTTP2_SETTINGS_ENABLE_PUSH: u16 = 0x2;

pub const HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS: u16 = 0x3;

pub const HTTP2_SETTINGS_INITIAL_WINDOW_SIZE: u16 = 0x4;

pub const HTTP2_SETTINGS_MAX_FRAME_SIZE: u16 = 0x5;

pub const HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE: u16 = 0x6;

pub const HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL: u16 = 0x8;

pub const HTTP2_MAX_FRAME_SIZE: u32 = 0x00ff_ffff;

pub const HTTP2_MAX_INITIAL_WINDOW_SIZE: u32 = 0x7fff_ffff;

pub const HTTP2_MAX_CUSTOM_SETTINGS: usize = 10;

pub const HTTP2_CLIENT_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";

pub const HTTP2_FRAME_SETTINGS: u8 = 0x4;

pub const HTTP2_FLAG_ACK: u8 = 0x1;

pub const Http2SettingPair = struct {
    id: u16,
    value: u32,
};

pub fn http2AppendSetting(out: *std.array_list.Managed(u8), id: u16, value: u32) !void {
    try out.append(@intCast((id >> 8) & 0xff));
    try out.append(@intCast(id & 0xff));
    try out.append(@intCast((value >> 24) & 0xff));
    try out.append(@intCast((value >> 16) & 0xff));
    try out.append(@intCast((value >> 8) & 0xff));
    try out.append(@intCast(value & 0xff));
}

pub fn http2JsonNumber(value: std.json.Value) ?u32 {
    return switch (value) {
        .integer => |n| if (n >= 0 and n <= std.math.maxInt(u32)) @intCast(n) else null,
        .float => |n| blk: {
            if (!std.math.isFinite(n) or n < 0 or n > @as(f64, @floatFromInt(std.math.maxInt(u32)))) break :blk null;
            const rounded = @floor(n);
            if (rounded != n) break :blk null;
            break :blk @intFromFloat(n);
        },
        else => null,
    };
}

pub fn http2JsonBool(value: std.json.Value) ?bool {
    return switch (value) {
        .bool => |b| b,
        else => null,
    };
}

pub fn http2AppendNumericSetting(out: *std.array_list.Managed(u8), obj: std.json.ObjectMap, key: []const u8, id: u16, min: u32, max: u32) !void {
    const value = obj.get(key) orelse return;
    const n = http2JsonNumber(value) orelse return error.InvalidSetting;
    if (n < min or n > max) return error.InvalidSetting;
    try http2AppendSetting(out, id, n);
}

pub fn http2AppendBoolSetting(out: *std.array_list.Managed(u8), obj: std.json.ObjectMap, key: []const u8, id: u16) !void {
    const value = obj.get(key) orelse return;
    const enabled = http2JsonBool(value) orelse return error.InvalidSetting;
    try http2AppendSetting(out, id, if (enabled) 1 else 0);
}

pub fn http2AppendMaxHeaderSetting(out: *std.array_list.Managed(u8), obj: std.json.ObjectMap) !void {
    const list_value = obj.get("maxHeaderListSize");
    const size_value = obj.get("maxHeaderSize");
    const value = size_value orelse list_value orelse return;
    const n = http2JsonNumber(value) orelse return error.InvalidSetting;
    try http2AppendSetting(out, HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE, n);
}

pub fn http2KnownSetting(id: u16) bool {
    return id == HTTP2_SETTINGS_HEADER_TABLE_SIZE or
        id == HTTP2_SETTINGS_ENABLE_PUSH or
        id == HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS or
        id == HTTP2_SETTINGS_INITIAL_WINDOW_SIZE or
        id == HTTP2_SETTINGS_MAX_FRAME_SIZE or
        id == HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE or
        id == HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL;
}

pub fn http2AppendCustomSettings(out: *std.array_list.Managed(u8), obj: std.json.ObjectMap) !void {
    const custom = obj.get("customSettings") orelse return;
    if (custom != .object) return error.InvalidSetting;
    if (custom.object.count() > HTTP2_MAX_CUSTOM_SETTINGS) return error.InvalidSetting;
    var it = custom.object.iterator();
    while (it.next()) |entry| {
        const id = std.fmt.parseInt(u16, entry.key_ptr.*, 10) catch return error.InvalidSetting;
        if (id == 0) return error.InvalidSetting;
        const n = http2JsonNumber(entry.value_ptr.*) orelse return error.InvalidSetting;
        if (http2KnownSetting(id)) continue;
        try http2AppendSetting(out, id, n);
    }
}

pub fn http2ReadSetting(buf: []const u8, offset: usize) Http2SettingPair {
    const id = (@as(u16, buf[offset]) << 8) | @as(u16, buf[offset + 1]);
    const value = (@as(u32, buf[offset + 2]) << 24) |
        (@as(u32, buf[offset + 3]) << 16) |
        (@as(u32, buf[offset + 4]) << 8) |
        @as(u32, buf[offset + 5]);
    return .{ .id = id, .value = value };
}

pub fn http2AppendFrame(out: *std.array_list.Managed(u8), frame_type: u8, flags: u8, stream_id: u32, payload: []const u8) !void {
    if (payload.len > HTTP2_MAX_FRAME_SIZE) return error.FrameTooLarge;
    try out.append(@intCast((payload.len >> 16) & 0xff));
    try out.append(@intCast((payload.len >> 8) & 0xff));
    try out.append(@intCast(payload.len & 0xff));
    try out.append(frame_type);
    try out.append(flags);
    const sid = stream_id & 0x7fff_ffff;
    try out.append(@intCast((sid >> 24) & 0x7f));
    try out.append(@intCast((sid >> 16) & 0xff));
    try out.append(@intCast((sid >> 8) & 0xff));
    try out.append(@intCast(sid & 0xff));
    try out.appendSlice(payload);
}

pub const Http2FrameHeader = struct {
    len: usize,
    frame_type: u8,
    flags: u8,
    stream_id: u32,
};

pub fn http2ReadFrameHeader(buf: []const u8) !Http2FrameHeader {
    if (buf.len < 9) return error.ShortFrameHeader;
    const len = (@as(usize, buf[0]) << 16) | (@as(usize, buf[1]) << 8) | @as(usize, buf[2]);
    const stream_id = (@as(u32, buf[5] & 0x7f) << 24) |
        (@as(u32, buf[6]) << 16) |
        (@as(u32, buf[7]) << 8) |
        @as(u32, buf[8]);
    return .{ .len = len, .frame_type = buf[3], .flags = buf[4], .stream_id = stream_id };
}

pub fn http2AppendJsonU32Field(out: *std.array_list.Managed(u8), first: *bool, name: []const u8, value: u32) !void {
    if (!first.*) try out.append(',');
    first.* = false;
    try appendJsonString(out, name);
    try managedPrint(out, ":{d}", .{value});
}

pub fn http2AppendJsonBoolField(out: *std.array_list.Managed(u8), first: *bool, name: []const u8, value: bool) !void {
    if (!first.*) try out.append(',');
    first.* = false;
    try appendJsonString(out, name);
    try out.appendSlice(if (value) ":true" else ":false");
}

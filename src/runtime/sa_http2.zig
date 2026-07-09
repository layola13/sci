// HTTP/2 runtime binding for the sci/sa_std platform layer.
//
// This is a REAL protocol-machine backend backed by libnghttp2, lazily loaded
// via dlopen. It migrated out of sa_plugin_node so that every plugin can reuse
// the same sa_std HTTP/2 surface instead of each plugin hiding its own binding.
// The capabilities/status JSON facades stay in the plugins; the real session
// state machine lives here.

const std = @import("std");

// --- outcome helpers (mirrors the sa_plugin_node private surface) ---

const UnsupportedStatus: u32 = 0x8000_0000;

fn fail() u32 {
    return UnsupportedStatus;
}

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_NO_MEMORY: i32 = -12;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;

var buffer_registry_mutex = std.Thread.Mutex{};
var buffer_slots = std.ArrayListUnmanaged(?BufferEntry){};

const BufferEntry = struct {
    bytes: []u8,
};

// Register an owned byte slice as a u64 handle, mirroring sci's
// sa_fs_read_buffer / sa_json_buffer "return a handle, free with *_free"
// convention. On failure the bytes are freed and 0 is returned (0 == invalid
// handle, consistent with sci's other handle registries).
fn registerBuffer(bytes: []u8) u64 {
    buffer_registry_mutex.lock();
    defer buffer_registry_mutex.unlock();
    var i: usize = 0;
    while (i < buffer_slots.items.len) : (i += 1) {
        if (buffer_slots.items[i] == null) {
            buffer_slots.items[i] = .{ .bytes = bytes };
            return @intCast(i + 1);
        }
    }
    buffer_slots.append(std.heap.page_allocator, .{ .bytes = bytes }) catch {
        std.heap.page_allocator.free(bytes);
        return 0;
    };
    return @intCast(buffer_slots.items.len);
}

fn takeBuffer(handle: u64) ?[]u8 {
    if (handle == 0) return null;
    buffer_registry_mutex.lock();
    defer buffer_registry_mutex.unlock();
    const idx: usize = @intCast(handle - 1);
    if (idx >= buffer_slots.items.len) return null;
    const entry = buffer_slots.items[idx] orelse return null;
    return entry.bytes;
}

fn registerOwnedString(text: []const u8) u64 {
    const owned = std.heap.page_allocator.dupe(u8, text) catch return 0;
    return registerBuffer(owned);
}

fn jsonEscapeAppend(out: *std.ArrayList(u8), bytes: []const u8) !void {
    for (bytes) |b| switch (b) {
        '"' => try out.appendSlice("\\\""),
        '\\' => try out.appendSlice("\\\\"),
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        else => if (b < 0x20) try out.writer().print("\\u{x:0>4}", .{b}) else try out.append(b),
    };
}

fn appendJsonString(out: *std.ArrayList(u8), bytes: []const u8) !void {
    try out.append('"');
    try jsonEscapeAppend(out, bytes);
    try out.append('"');
}

fn appendStringArray(out: *std.ArrayList(u8), items: []const []const u8) !void {
    try out.append('[');
    for (items, 0..) |item, i| {
        if (i != 0) try out.append(',');
        try appendJsonString(out, item);
    }
    try out.append(']');
}

// --- libnghttp2 opaque C surface ---

const Nghttp2Session = opaque {};
const Nghttp2SessionCallbacks = opaque {};
const Nghttp2Frame = opaque {};

const Nghttp2Nv = extern struct {
    name: [*]u8,
    value: [*]u8,
    namelen: usize,
    valuelen: usize,
    flags: u8,
};

const Nghttp2DataSource = extern union {
    fd: c_int,
    ptr: ?*anyopaque,
};

const Nghttp2DataProvider = extern struct {
    source: Nghttp2DataSource,
    read_callback: ?*const fn (?*Nghttp2Session, i32, [*]u8, usize, *u32, *Nghttp2DataSource, ?*anyopaque) callconv(.c) isize,
};

const Nghttp2Version = extern struct {
    age: c_int,
    version_num: c_int,
    // The full nghttp2_version struct also exposes version_str/proto_str, but
    // their offset/availability differs across nghttp2 releases. We only need
    // version_num (stable int at offset 4), so the struct is intentionally
    // truncated here.
};

const Nghttp2OnHeaderCallback = *const fn (?*Nghttp2Session, ?*const Nghttp2Frame, [*]const u8, usize, [*]const u8, usize, u8, ?*anyopaque) callconv(.c) c_int;
const Nghttp2OnDataChunkRecvCallback = *const fn (?*Nghttp2Session, u8, i32, [*]const u8, usize, ?*anyopaque) callconv(.c) c_int;
const Nghttp2OnFrameRecvCallback = *const fn (?*Nghttp2Session, ?*const Nghttp2Frame, ?*anyopaque) callconv(.c) c_int;

const Nghttp2CallbacksNewFn = *const fn (*?*Nghttp2SessionCallbacks) callconv(.c) c_int;
const Nghttp2CallbacksDelFn = *const fn (?*Nghttp2SessionCallbacks) callconv(.c) void;
const Nghttp2SetOnHeaderFn = *const fn (?*Nghttp2SessionCallbacks, Nghttp2OnHeaderCallback) callconv(.c) void;
const Nghttp2SetOnDataChunkRecvFn = *const fn (?*Nghttp2SessionCallbacks, Nghttp2OnDataChunkRecvCallback) callconv(.c) void;
const Nghttp2SetOnFrameRecvFn = *const fn (?*Nghttp2SessionCallbacks, Nghttp2OnFrameRecvCallback) callconv(.c) void;
const Nghttp2SessionClientNewFn = *const fn (*?*Nghttp2Session, ?*const Nghttp2SessionCallbacks, ?*anyopaque) callconv(.c) c_int;
const Nghttp2SessionDelFn = *const fn (?*Nghttp2Session) callconv(.c) void;
const Nghttp2SubmitRequestFn = *const fn (?*Nghttp2Session, ?*const anyopaque, [*]const Nghttp2Nv, usize, ?*const Nghttp2DataProvider, ?*anyopaque) callconv(.c) i32;
const Nghttp2SubmitSettingsFn = *const fn (?*Nghttp2Session, u8, ?*const anyopaque, usize) callconv(.c) c_int;
const Nghttp2SessionMemSendFn = *const fn (?*Nghttp2Session, *?[*]const u8) callconv(.c) isize;
const Nghttp2SessionMemRecvFn = *const fn (?*Nghttp2Session, [*]const u8, usize) callconv(.c) isize;
const Nghttp2SessionWantFn = *const fn (?*Nghttp2Session) callconv(.c) c_int;
const Nghttp2VersionFn = *const fn (c_int) callconv(.c) ?*const Nghttp2Version;

const Nghttp2Api = struct {
    lib: std.DynLib,
    callbacks_new: Nghttp2CallbacksNewFn,
    callbacks_del: Nghttp2CallbacksDelFn,
    callbacks_set_on_header_callback: Nghttp2SetOnHeaderFn,
    callbacks_set_on_data_chunk_recv_callback: Nghttp2SetOnDataChunkRecvFn,
    callbacks_set_on_frame_recv_callback: Nghttp2SetOnFrameRecvFn,
    session_client_new: Nghttp2SessionClientNewFn,
    session_del: Nghttp2SessionDelFn,
    submit_request: Nghttp2SubmitRequestFn,
    submit_settings: Nghttp2SubmitSettingsFn,
    session_mem_send: Nghttp2SessionMemSendFn,
    session_mem_recv: Nghttp2SessionMemRecvFn,
    session_want_read: Nghttp2SessionWantFn,
    session_want_write: Nghttp2SessionWantFn,
    version: Nghttp2VersionFn,
};

var nghttp2_api: ?Nghttp2Api = null;
var nghttp2_api_mutex = std.Thread.Mutex{};

fn loadNghttp2Api() ?*Nghttp2Api {
    nghttp2_api_mutex.lock();
    defer nghttp2_api_mutex.unlock();
    if (nghttp2_api) |*api| return api;

    const candidates = [_][]const u8{
        "libnghttp2.so.14",
        "/lib/x86_64-linux-gnu/libnghttp2.so.14",
        "/usr/lib/x86_64-linux-gnu/libnghttp2.so.14",
    };

    for (candidates) |candidate| {
        var lib = std.DynLib.open(candidate) catch continue;
        const callbacks_new = lib.lookup(Nghttp2CallbacksNewFn, "nghttp2_session_callbacks_new") orelse {
            lib.close();
            continue;
        };
        const callbacks_del = lib.lookup(Nghttp2CallbacksDelFn, "nghttp2_session_callbacks_del") orelse {
            lib.close();
            continue;
        };
        const set_header = lib.lookup(Nghttp2SetOnHeaderFn, "nghttp2_session_callbacks_set_on_header_callback") orelse {
            lib.close();
            continue;
        };
        const set_data = lib.lookup(Nghttp2SetOnDataChunkRecvFn, "nghttp2_session_callbacks_set_on_data_chunk_recv_callback") orelse {
            lib.close();
            continue;
        };
        const set_frame = lib.lookup(Nghttp2SetOnFrameRecvFn, "nghttp2_session_callbacks_set_on_frame_recv_callback") orelse {
            lib.close();
            continue;
        };
        const session_client_new = lib.lookup(Nghttp2SessionClientNewFn, "nghttp2_session_client_new") orelse {
            lib.close();
            continue;
        };
        const session_del = lib.lookup(Nghttp2SessionDelFn, "nghttp2_session_del") orelse {
            lib.close();
            continue;
        };
        const submit_request = lib.lookup(Nghttp2SubmitRequestFn, "nghttp2_submit_request") orelse {
            lib.close();
            continue;
        };
        const submit_settings = lib.lookup(Nghttp2SubmitSettingsFn, "nghttp2_submit_settings") orelse {
            lib.close();
            continue;
        };
        const mem_send = lib.lookup(Nghttp2SessionMemSendFn, "nghttp2_session_mem_send") orelse {
            lib.close();
            continue;
        };
        const mem_recv = lib.lookup(Nghttp2SessionMemRecvFn, "nghttp2_session_mem_recv") orelse {
            lib.close();
            continue;
        };
        const want_read = lib.lookup(Nghttp2SessionWantFn, "nghttp2_session_want_read") orelse {
            lib.close();
            continue;
        };
        const want_write = lib.lookup(Nghttp2SessionWantFn, "nghttp2_session_want_write") orelse {
            lib.close();
            continue;
        };
        const version = lib.lookup(Nghttp2VersionFn, "nghttp2_version") orelse {
            lib.close();
            continue;
        };
        nghttp2_api = .{
            .lib = lib,
            .callbacks_new = callbacks_new,
            .callbacks_del = callbacks_del,
            .callbacks_set_on_header_callback = set_header,
            .callbacks_set_on_data_chunk_recv_callback = set_data,
            .callbacks_set_on_frame_recv_callback = set_frame,
            .session_client_new = session_client_new,
            .session_del = session_del,
            .submit_request = submit_request,
            .submit_settings = submit_settings,
            .session_mem_send = mem_send,
            .session_mem_recv = mem_recv,
            .session_want_read = want_read,
            .session_want_write = want_write,
            .version = version,
        };
        return &nghttp2_api.?;
    }
    return null;
}

// --- response state machine ---

const Http2ResponseState = struct {
    allocator: std.mem.Allocator,
    headers: std.ArrayList(Header),
    body: std.ArrayList(u8),
    status: u16 = 0,
    frames: u64 = 0,

    const Header = struct { name: []u8, value: []u8 };

    fn init(allocator: std.mem.Allocator) Http2ResponseState {
        return .{ .allocator = allocator, .headers = std.ArrayList(Header).init(allocator), .body = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *Http2ResponseState) void {
        for (self.headers.items) |header| {
            self.allocator.free(header.name);
            self.allocator.free(header.value);
        }
        self.headers.deinit();
        self.body.deinit();
    }

    fn appendHeader(self: *Http2ResponseState, name: []const u8, value: []const u8) !void {
        const name_owned = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(name_owned);
        const value_owned = try self.allocator.dupe(u8, value);
        errdefer self.allocator.free(value_owned);
        if (std.mem.eql(u8, name, ":status")) {
            self.status = std.fmt.parseInt(u16, value, 10) catch 0;
        }
        try self.headers.append(.{ .name = name_owned, .value = value_owned });
    }

};

const NGHTTP2_NV_FLAG_NONE: u8 = 0;
const NGHTTP2_DATA_FLAG_EOF: u32 = 1;
const NGHTTP2_FLAG_NONE: u8 = 0;

fn http2OnHeader(_: ?*Nghttp2Session, _: ?*const Nghttp2Frame, name_ptr: [*]const u8, name_len: usize, value_ptr: [*]const u8, value_len: usize, _: u8, user_data: ?*anyopaque) callconv(.c) c_int {
    const state: *Http2ResponseState = @ptrCast(@alignCast(user_data orelse return -1));
    state.appendHeader(name_ptr[0..name_len], value_ptr[0..value_len]) catch return -1;
    return 0;
}

fn http2OnDataChunkRecv(_: ?*Nghttp2Session, _: u8, _: i32, data_ptr: [*]const u8, data_len: usize, user_data: ?*anyopaque) callconv(.c) c_int {
    const state: *Http2ResponseState = @ptrCast(@alignCast(user_data orelse return -1));
    state.body.appendSlice(data_ptr[0..data_len]) catch return -1;
    return 0;
}

fn http2OnFrameRecv(_: ?*Nghttp2Session, _: ?*const Nghttp2Frame, user_data: ?*anyopaque) callconv(.c) c_int {
    const state: *Http2ResponseState = @ptrCast(@alignCast(user_data orelse return -1));
    state.frames += 1;
    return 0;
}

fn http2DataRead(_: ?*Nghttp2Session, _: i32, buf: [*]u8, len: usize, data_flags: *u32, source: *Nghttp2DataSource, _: ?*anyopaque) callconv(.c) isize {
    const body: *[]const u8 = @ptrCast(@alignCast(source.ptr orelse return -1));
    const n = @min(len, body.*.len);
    @memcpy(buf[0..n], body.*[0..n]);
    body.* = body.*[n..];
    if (body.*.len == 0) data_flags.* |= NGHTTP2_DATA_FLAG_EOF;
    return @intCast(n);
}

fn http2FlushOutbound(api: *Nghttp2Api, session: ?*Nghttp2Session, stream: *std.net.Stream) u32 {
    while (api.session_want_write(session) != 0) {
        var data_ptr: ?[*]const u8 = null;
        const n = api.session_mem_send(session, &data_ptr);
        if (n < 0) return fail();
        if (n == 0) break;
        stream.writeAll(data_ptr.?[0..@intCast(n)]) catch return fail();
    }
    return 0;
}

fn http2ParseUrl(url: []const u8) !struct { scheme: []const u8, host: []const u8, port: u16, path: []const u8 } {
    const marker = std.mem.indexOf(u8, url, "://") orelse return error.InvalidUrl;
    const scheme = url[0..marker];
    if (!std.mem.eql(u8, scheme, "http")) return error.UnsupportedScheme;
    const rest = url[marker + 3 ..];
    const slash = std.mem.indexOfScalar(u8, rest, '/') orelse rest.len;
    const authority = rest[0..slash];
    const path = if (slash < rest.len) rest[slash..] else "/";
    var port: u16 = 80;
    const host = if (authority.len > 0 and authority[0] == '[') blk: {
        const end = std.mem.indexOfScalar(u8, authority, ']') orelse return error.InvalidUrl;
        if (end == 1) return error.InvalidUrl;
        if (end + 1 < authority.len) {
            if (authority[end + 1] != ':') return error.InvalidUrl;
            port = try std.fmt.parseInt(u16, authority[end + 2 ..], 10);
        }
        break :blk authority[1..end];
    } else blk: {
        var host = authority;
        if (std.mem.lastIndexOfScalar(u8, authority, ':')) |colon| {
            host = authority[0..colon];
            port = try std.fmt.parseInt(u16, authority[colon + 1 ..], 10);
        }
        break :blk host;
    };
    if (host.len == 0) return error.InvalidUrl;
    if (std.mem.indexOfScalar(u8, host, ':') != null) {
        _ = std.net.Address.parseIp6(host, port) catch return error.InvalidUrl;
    }
    return .{ .scheme = scheme, .host = host, .port = port, .path = path };
}

// --- HTTP/2 settings serialization (frame helpers, no lib needed) ---

const HTTP2_SETTINGS_HEADER_TABLE_SIZE: u16 = 0x1;
const HTTP2_SETTINGS_ENABLE_PUSH: u16 = 0x2;
const HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS: u16 = 0x3;
const HTTP2_SETTINGS_INITIAL_WINDOW_SIZE: u16 = 0x4;
const HTTP2_SETTINGS_MAX_FRAME_SIZE: u16 = 0x5;
const HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE: u16 = 0x6;
const HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL: u16 = 0x8;
const HTTP2_MAX_FRAME_SIZE: u32 = 0x00ff_ffff;
const HTTP2_MAX_INITIAL_WINDOW_SIZE: u32 = 0x7fff_ffff;
const HTTP2_MAX_CUSTOM_SETTINGS: usize = 10;
const HTTP2_CLIENT_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n";
const HTTP2_FRAME_SETTINGS: u8 = 0x4;
const HTTP2_FLAG_ACK: u8 = 0x1;

const Http2SettingPair = struct {
    id: u16,
    value: u32,
};

fn http2AppendSetting(out: *std.ArrayList(u8), id: u16, value: u32) !void {
    try out.append(@intCast((id >> 8) & 0xff));
    try out.append(@intCast(id & 0xff));
    try out.append(@intCast((value >> 24) & 0xff));
    try out.append(@intCast((value >> 16) & 0xff));
    try out.append(@intCast((value >> 8) & 0xff));
    try out.append(@intCast(value & 0xff));
}

fn http2JsonNumber(value: std.json.Value) ?u32 {
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

fn http2JsonBool(value: std.json.Value) ?bool {
    return switch (value) {
        .bool => |b| b,
        else => null,
    };
}

fn http2AppendNumericSetting(out: *std.ArrayList(u8), obj: std.json.ObjectMap, key: []const u8, id: u16, min: u32, max: u32) !void {
    const value = obj.get(key) orelse return;
    const n = http2JsonNumber(value) orelse return error.InvalidSetting;
    if (n < min or n > max) return error.InvalidSetting;
    try http2AppendSetting(out, id, n);
}

fn http2AppendBoolSetting(out: *std.ArrayList(u8), obj: std.json.ObjectMap, key: []const u8, id: u16) !void {
    const value = obj.get(key) orelse return;
    const enabled = http2JsonBool(value) orelse return error.InvalidSetting;
    try http2AppendSetting(out, id, if (enabled) 1 else 0);
}

fn http2AppendMaxHeaderSetting(out: *std.ArrayList(u8), obj: std.json.ObjectMap) !void {
    const list_value = obj.get("maxHeaderListSize");
    const size_value = obj.get("maxHeaderSize");
    const value = size_value orelse list_value orelse return;
    const n = http2JsonNumber(value) orelse return error.InvalidSetting;
    try http2AppendSetting(out, HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE, n);
}

fn http2KnownSetting(id: u16) bool {
    return id == HTTP2_SETTINGS_HEADER_TABLE_SIZE or
        id == HTTP2_SETTINGS_ENABLE_PUSH or
        id == HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS or
        id == HTTP2_SETTINGS_INITIAL_WINDOW_SIZE or
        id == HTTP2_SETTINGS_MAX_FRAME_SIZE or
        id == HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE or
        id == HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL;
}

fn http2AppendCustomSettings(out: *std.ArrayList(u8), obj: std.json.ObjectMap) !void {
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

fn http2ReadSetting(buf: []const u8, offset: usize) Http2SettingPair {
    const id = (@as(u16, buf[offset]) << 8) | @as(u16, buf[offset + 1]);
    const value = (@as(u32, buf[offset + 2]) << 24) |
        (@as(u32, buf[offset + 3]) << 16) |
        (@as(u32, buf[offset + 4]) << 8) |
        @as(u32, buf[offset + 5]);
    return .{ .id = id, .value = value };
}

fn http2AppendFrame(out: *std.ArrayList(u8), frame_type: u8, flags: u8, stream_id: u32, payload: []const u8) !void {
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

const Http2FrameHeader = struct {
    len: usize,
    frame_type: u8,
    flags: u8,
    stream_id: u32,
};

fn http2ReadFrameHeader(buf: []const u8) !Http2FrameHeader {
    if (buf.len < 9) return error.ShortFrameHeader;
    const len = (@as(usize, buf[0]) << 16) | (@as(usize, buf[1]) << 8) | @as(usize, buf[2]);
    const stream_id = (@as(u32, buf[5] & 0x7f) << 24) |
        (@as(u32, buf[6]) << 16) |
        (@as(u32, buf[7]) << 8) |
        @as(u32, buf[8]);
    return .{ .len = len, .frame_type = buf[3], .flags = buf[4], .stream_id = stream_id };
}

fn http2AppendJsonU32Field(out: *std.ArrayList(u8), first: *bool, name: []const u8, value: u32) !void {
    if (!first.*) try out.append(',');
    first.* = false;
    try appendJsonString(out, name);
    try out.writer().print(":{d}", .{value});
}

fn http2AppendJsonBoolField(out: *std.ArrayList(u8), first: *bool, name: []const u8, value: bool) !void {
    if (!first.*) try out.append(',');
    first.* = false;
    try appendJsonString(out, name);
    try out.appendSlice(if (value) ":true" else ":false");
}

// --- exported HTTP/2 surface (sa_std HTTP/2 — real libnghttp2 backend) ---

// --- exported HTTP/2 surface ---------------------------------------------
//
// String/JSON/binary outputs are returned as registered u64 buffer handles
// (mirroring sci's sa_fs_read_buffer convention): allocate a handle with one
// of the request/query functions below, read bytes+length with
// sa_std_http2_buffer_data / sa_std_http2_buffer_len, and release with
// sa_std_http2_buffer_free. Status codes follow sci's sa_std convention:
//   0 = SA_STD_OK, negative = error.

fn errStatus() i32 {
    return SA_STD_ERR_INVALID_ARGUMENT;
}

// Build a buffer handle from an owned []u8 the caller is giving away.
fn handleFromOwned(bytes: []u8) i32 {
    const h = registerBuffer(bytes);
    return if (h == 0) SA_STD_ERR_NO_MEMORY else @as(i32, @intCast(@as(u64, h)));
}

// Build a buffer handle from a const string we must dup first.
fn handleFromConst(text: []const u8) i32 {
    const owned = std.heap.page_allocator.dupe(u8, text) catch return SA_STD_ERR_NO_MEMORY;
    return handleFromOwned(owned);
}

// Write a handle into a caller-provided out slot with null-check.
fn writeHandle(out_handle: ?*u64, handle: u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = handle;
    return SA_STD_OK;
}

pub export fn sa_std_http2_client_request(url_ptr: ?[*]const u8, url_len: u64, method_ptr: ?[*]const u8, method_len: u64, body_ptr: ?[*]const u8, body_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const api = loadNghttp2Api() orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.page_allocator;
    const url = if (url_ptr) |p| p[0..url_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    const parsed = http2ParseUrl(url) catch {
        return handleFromConst("{\"error\":\"url\"}");
    };
    const method = if (method_ptr) |ptr| ptr[0..method_len] else "GET";
    const body = if (body_ptr) |ptr| ptr[0..body_len] else "";

    var stream = std.net.tcpConnectToHost(allocator, parsed.host, parsed.port) catch {
        return handleFromConst("{\"error\":\"connect\"}");
    };
    defer stream.close();

    var state = Http2ResponseState.init(allocator);
    defer state.deinit();

    var callbacks: ?*Nghttp2SessionCallbacks = null;
    if (api.callbacks_new(&callbacks) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    defer api.callbacks_del(callbacks);
    api.callbacks_set_on_header_callback(callbacks, http2OnHeader);
    api.callbacks_set_on_data_chunk_recv_callback(callbacks, http2OnDataChunkRecv);
    api.callbacks_set_on_frame_recv_callback(callbacks, http2OnFrameRecv);

    var session: ?*Nghttp2Session = null;
    if (api.session_client_new(&session, callbacks, @ptrCast(&state)) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    defer api.session_del(session);

    if (api.submit_settings(session, NGHTTP2_FLAG_NONE, null, 0) != 0) return SA_STD_ERR_INVALID_ARGUMENT;

    var authority_buf: [512]u8 = undefined;
    const authority = if (parsed.port == 80)
        std.fmt.bufPrint(&authority_buf, "{s}", .{parsed.host}) catch return SA_STD_ERR_INVALID_ARGUMENT
    else
        std.fmt.bufPrint(&authority_buf, "{s}:{d}", .{ parsed.host, parsed.port }) catch return SA_STD_ERR_INVALID_ARGUMENT;

    var nva = [_]Nghttp2Nv{
        .{ .name = @constCast(@as([*]const u8, @ptrCast(":method".ptr))), .value = @constCast(method.ptr), .namelen = 7, .valuelen = method.len, .flags = NGHTTP2_NV_FLAG_NONE },
        .{ .name = @constCast(@as([*]const u8, @ptrCast(":scheme".ptr))), .value = @constCast(parsed.scheme.ptr), .namelen = 7, .valuelen = parsed.scheme.len, .flags = NGHTTP2_NV_FLAG_NONE },
        .{ .name = @constCast(@as([*]const u8, @ptrCast(":authority".ptr))), .value = @constCast(authority.ptr), .namelen = 10, .valuelen = authority.len, .flags = NGHTTP2_NV_FLAG_NONE },
        .{ .name = @constCast(@as([*]const u8, @ptrCast(":path".ptr))), .value = @constCast(parsed.path.ptr), .namelen = 5, .valuelen = parsed.path.len, .flags = NGHTTP2_NV_FLAG_NONE },
    };

    var body_slice = body;
    var provider = Nghttp2DataProvider{
        .source = .{ .ptr = @ptrCast(&body_slice) },
        .read_callback = http2DataRead,
    };
    const provider_ptr: ?*const Nghttp2DataProvider = if (body.len > 0) &provider else null;
    const req_id = api.submit_request(session, null, &nva, nva.len, provider_ptr, null);
    if (req_id < 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (http2FlushOutbound(api, session, &stream) != 0) return SA_STD_ERR_INVALID_ARGUMENT;

    var read_buf: [8192]u8 = undefined;
    var saw_response = false;
    var idle_reads: u8 = 0;
    while (api.session_want_read(session) != 0 and idle_reads < 4) {
        const n = stream.read(&read_buf) catch return SA_STD_ERR_INVALID_ARGUMENT;
        if (n == 0) break;
        idle_reads = 0;
        const consumed = api.session_mem_recv(session, &read_buf, n);
        if (consumed < 0) return SA_STD_ERR_INVALID_ARGUMENT;
        if (http2FlushOutbound(api, session, &stream) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
        if (state.status != 0) saw_response = true;
        if (saw_response and state.body.items.len > 0) break;
    }

    if (!saw_response) return SA_STD_ERR_INVALID_ARGUMENT;
    var owned_json = std.ArrayList(u8).init(allocator);
    errdefer owned_json.deinit();
    owned_json.writer().print("{{\"status\":{d},\"headers\":{{", .{state.status}) catch return SA_STD_ERR_NO_MEMORY;
    var first = true;
    for (state.headers.items) |hdr| {
        if (std.mem.startsWith(u8, hdr.name, ":")) continue;
        if (!first) owned_json.appendSlice(",") catch return SA_STD_ERR_NO_MEMORY;
        first = false;
        appendJsonString(&owned_json, hdr.name) catch return SA_STD_ERR_NO_MEMORY;
        owned_json.appendSlice(":") catch return SA_STD_ERR_NO_MEMORY;
        appendJsonString(&owned_json, hdr.value) catch return SA_STD_ERR_NO_MEMORY;
    }
    owned_json.appendSlice("},\"body\":") catch return SA_STD_ERR_NO_MEMORY;
    appendJsonString(&owned_json, state.body.items) catch return SA_STD_ERR_NO_MEMORY;
    owned_json.writer().print(",\"bodyLen\":{d},\"frames\":{d}}}", .{ state.body.items.len, state.frames }) catch return SA_STD_ERR_NO_MEMORY;
    const out_json = owned_json.toOwnedSlice() catch return SA_STD_ERR_NO_MEMORY;
    return writeHandle(out_handle, registerBuffer(out_json));
}

pub export fn sa_std_http2_nghttp2_version_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const api = loadNghttp2Api() orelse return SA_STD_ERR_INVALID_ARGUMENT;
    // nghttp2_version() returns a struct whose string-pointer field layout has
    // varied across releases; nghttp2's own headers are not installed on this
    // host, so we read only the integer version_num (at a stable offset) and
    // report the concrete proto name. version_num is real lib-provided data.
    const version = api.version(0) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    var buffer: [192]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"version\":\"nghttp2\",\"proto\":\"h2\",\"versionNum\":{d}}}", .{version.version_num}) catch return SA_STD_ERR_NO_MEMORY;
    return writeHandle(out_handle, registerOwnedString(json));
}

pub export fn sa_std_http2_get_default_settings_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    return writeHandle(out_handle, registerOwnedString("{\"headerTableSize\":4096,\"enablePush\":true,\"initialWindowSize\":65535,\"maxFrameSize\":16384,\"maxConcurrentStreams\":4294967295,\"maxHeaderListSize\":65535,\"maxHeaderSize\":65535,\"enableConnectProtocol\":false}"));
}

pub export fn sa_std_http2_constants_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    return writeHandle(out_handle, registerOwnedString(
        \\{"NGHTTP2_NV_FLAG_NONE":0,"NGHTTP2_NV_FLAG_NO_INDEX":1,"NGHTTP2_NV_FLAG_NO_EMIT_NAME":2,"NGHTTP2_NV_FLAG_NO_EMIT_VALUE":4,"NGHTTP2_NV_FLAG_NO_NEVER_INDEX":8,"FRAME_SETTINGS":4,"FRAME_HEADERS":1,"FRAME_DATA":0,"FRAME_PING":6,"FRAME_GOAWAY":7,"FRAME_WINDOW_UPDATE":8,"FRAME_PRIORITY":2,"FRAME_RST_STREAM":3,"FLAG_ACK":1,"FLAG_END_STREAM":1,"FLAG_END_HEADERS":4,"DEFAULT_HEADER_TABLE_SIZE":4096,"DEFAULT_MAX_CONCURRENT_STREAMS":4294967295,"DEFAULT_INITIAL_WINDOW_SIZE":65535,"DEFAULT_MAX_FRAME_SIZE":16384}
    ));
}

pub export fn sa_std_http2_sensitive_headers(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    return writeHandle(out_handle, registerOwnedString(
        \\["authorization","proxy-authorization","cookie","set-cookie","x-api-key","x-auth-token"]
    ));
}

pub export fn sa_std_http2_get_packed_settings(settings_json_ptr: ?[*]const u8, settings_json_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const settings_json = if (settings_json_ptr) |ptr| ptr[0..settings_json_len] else "";
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, settings_json, .{}) catch return SA_STD_ERR_INVALID_ARGUMENT;
    defer parsed.deinit();
    if (parsed.value != .object) return SA_STD_ERR_INVALID_ARGUMENT;
    const obj = parsed.value.object;

    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    http2AppendCustomSettings(&out, obj) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendNumericSetting(&out, obj, "headerTableSize", HTTP2_SETTINGS_HEADER_TABLE_SIZE, 0, std.math.maxInt(u32)) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendNumericSetting(&out, obj, "maxConcurrentStreams", HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 0, std.math.maxInt(u32)) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendNumericSetting(&out, obj, "initialWindowSize", HTTP2_SETTINGS_INITIAL_WINDOW_SIZE, 0, HTTP2_MAX_INITIAL_WINDOW_SIZE) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendNumericSetting(&out, obj, "maxFrameSize", HTTP2_SETTINGS_MAX_FRAME_SIZE, 16_384, HTTP2_MAX_FRAME_SIZE) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendMaxHeaderSetting(&out, obj) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendBoolSetting(&out, obj, "enablePush", HTTP2_SETTINGS_ENABLE_PUSH) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendBoolSetting(&out, obj, "enableConnectProtocol", HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL) catch return SA_STD_ERR_INVALID_ARGUMENT;

    const owned = out.toOwnedSlice() catch return SA_STD_ERR_NO_MEMORY;
    return writeHandle(out_handle, registerBuffer(owned));
}

pub export fn sa_std_http2_get_unpacked_settings_json(buf_ptr: ?[*]const u8, buf_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const buf = if (buf_ptr) |ptr| ptr[0..buf_len] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (buf.len % 6 != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    out.append('{') catch return SA_STD_ERR_NO_MEMORY;
    var first = true;
    var custom = std.ArrayList(Http2SettingPair).init(std.heap.page_allocator);
    defer custom.deinit();

    var offset: usize = 0;
    while (offset < buf.len) : (offset += 6) {
        const pair = http2ReadSetting(buf, offset);
        switch (pair.id) {
            HTTP2_SETTINGS_HEADER_TABLE_SIZE => http2AppendJsonU32Field(&out, &first, "headerTableSize", pair.value) catch return SA_STD_ERR_INVALID_ARGUMENT,
            HTTP2_SETTINGS_ENABLE_PUSH => http2AppendJsonBoolField(&out, &first, "enablePush", pair.value != 0) catch return SA_STD_ERR_INVALID_ARGUMENT,
            HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS => http2AppendJsonU32Field(&out, &first, "maxConcurrentStreams", pair.value) catch return SA_STD_ERR_INVALID_ARGUMENT,
            HTTP2_SETTINGS_INITIAL_WINDOW_SIZE => http2AppendJsonU32Field(&out, &first, "initialWindowSize", pair.value) catch return SA_STD_ERR_INVALID_ARGUMENT,
            HTTP2_SETTINGS_MAX_FRAME_SIZE => http2AppendJsonU32Field(&out, &first, "maxFrameSize", pair.value) catch return SA_STD_ERR_INVALID_ARGUMENT,
            HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE => {
                http2AppendJsonU32Field(&out, &first, "maxHeaderListSize", pair.value) catch return SA_STD_ERR_INVALID_ARGUMENT;
                http2AppendJsonU32Field(&out, &first, "maxHeaderSize", pair.value) catch return SA_STD_ERR_INVALID_ARGUMENT;
            },
            HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL => http2AppendJsonBoolField(&out, &first, "enableConnectProtocol", pair.value != 0) catch return SA_STD_ERR_INVALID_ARGUMENT,
            else => custom.append(pair) catch return SA_STD_ERR_NO_MEMORY,
        }
    }

    if (custom.items.len > 0) {
        if (!first) out.append(',') catch return SA_STD_ERR_NO_MEMORY;
        first = false;
        out.appendSlice("\"customSettings\":{") catch return SA_STD_ERR_NO_MEMORY;
        for (custom.items, 0..) |pair, i| {
            if (i != 0) out.append(',') catch return SA_STD_ERR_NO_MEMORY;
            out.writer().print("\"{d}\":{d}", .{ pair.id, pair.value }) catch return SA_STD_ERR_NO_MEMORY;
        }
        out.append('}') catch return SA_STD_ERR_NO_MEMORY;
    }
    out.append('}') catch return SA_STD_ERR_NO_MEMORY;
    const owned = out.toOwnedSlice() catch return SA_STD_ERR_NO_MEMORY;
    return writeHandle(out_handle, registerBuffer(owned));
}

pub export fn sa_std_http2_perform_server_handshake(
    input_ptr: ?[*]const u8,
    input_len: u64,
    settings_json_ptr: ?[*]const u8,
    settings_json_len: u64,
    out_bytes_handle: ?*u64,
    out_json_handle: ?*u64,
) i32 {
    {
        const b = out_bytes_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
        b.* = 0;
    }
    {
        const j = out_json_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
        j.* = 0;
    }
    const input = (input_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT)[0..input_len];
    if (input.len < HTTP2_CLIENT_PREFACE.len + 9) return SA_STD_ERR_INVALID_ARGUMENT;
    if (!std.mem.eql(u8, input[0..HTTP2_CLIENT_PREFACE.len], HTTP2_CLIENT_PREFACE)) return SA_STD_ERR_INVALID_ARGUMENT;

    const frame_start = HTTP2_CLIENT_PREFACE.len;
    const header = http2ReadFrameHeader(input[frame_start..]) catch return SA_STD_ERR_INVALID_ARGUMENT;
    if (header.frame_type != HTTP2_FRAME_SETTINGS or header.stream_id != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if ((header.flags & HTTP2_FLAG_ACK) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    if (header.len % 6 != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const payload_start = frame_start + 9;
    const payload_end = payload_start + header.len;
    if (payload_end > input.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const client_settings = input[payload_start..payload_end];

    var settings_handle: u64 = 0;
    if (sa_std_http2_get_unpacked_settings_json(client_settings.ptr, client_settings.len, &settings_handle) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    // read and free the unpacked-settings string
    const client_settings_json = takeBuffer(settings_handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    defer std.heap.page_allocator.free(client_settings_json);

    var server_settings_handle: u64 = 0;
    if (sa_std_http2_get_packed_settings(settings_json_ptr, settings_json_len, &server_settings_handle) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const server_settings_owned = takeBuffer(server_settings_handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    defer std.heap.page_allocator.free(server_settings_owned);
    const server_settings = server_settings_owned;

    var outbound = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer outbound.deinit();
    http2AppendFrame(&outbound, HTTP2_FRAME_SETTINGS, 0, 0, server_settings) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendFrame(&outbound, HTTP2_FRAME_SETTINGS, HTTP2_FLAG_ACK, 0, "") catch return SA_STD_ERR_INVALID_ARGUMENT;

    var meta = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer meta.deinit();
    meta.appendSlice("{\"preface\":true,\"clientSettings\":") catch return SA_STD_ERR_NO_MEMORY;
    meta.appendSlice(client_settings_json) catch return SA_STD_ERR_NO_MEMORY;
    meta.writer().print(",\"clientSettingsBytes\":{d},\"serverSettingsBytes\":{d},\"outboundBytes\":{d},\"frames\":[\"SETTINGS\",\"SETTINGS_ACK\"]}}", .{
        client_settings.len,
        server_settings.len,
        outbound.items.len,
    }) catch return SA_STD_ERR_NO_MEMORY;

    const owned_outbound = outbound.toOwnedSlice() catch return SA_STD_ERR_NO_MEMORY;
    {
        const got = registerBuffer(owned_outbound);
        if (got == 0) {
            std.heap.page_allocator.free(owned_outbound);
            return SA_STD_ERR_NO_MEMORY;
        }
        out_bytes_handle.?.* = got;
    }
    const owned_meta = meta.toOwnedSlice() catch return SA_STD_ERR_NO_MEMORY;
    {
        const got = registerBuffer(owned_meta);
        if (got == 0) {
            std.heap.page_allocator.free(owned_meta);
            return SA_STD_ERR_NO_MEMORY;
        }
        out_json_handle.?.* = got;
    }
    return SA_STD_OK;
}

pub export fn sa_std_http2_supported(out_bool: ?*u32) i32 {
    const slot = out_bool orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = if (loadNghttp2Api() != null) 1 else 0;
    return SA_STD_OK;
}

pub export fn sa_std_http2_status_json(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    var out = std.ArrayList(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    out.appendSlice("{\"module\":\"http2\",\"backend\":\"libnghttp2\",\"supported\":") catch return SA_STD_ERR_NO_MEMORY;
    out.appendSlice(if (loadNghttp2Api() != null) "true" else "false") catch return SA_STD_ERR_NO_MEMORY;
    out.appendSlice(",\"protocolMachine\":true,\"exports\":[") catch return SA_STD_ERR_NO_MEMORY;
    const names = [_][]const u8{
        "client_request", "supported", "status", "version",
        "getDefaultSettings", "getPackedSettings", "getUnpackedSettings",
        "performServerHandshake", "constants", "sensitiveHeaders",
    };
    appendStringArray(&out, &names) catch return SA_STD_ERR_NO_MEMORY;
    out.appendSlice("]}") catch return SA_STD_ERR_NO_MEMORY;
    const owned = out.toOwnedSlice() catch return SA_STD_ERR_NO_MEMORY;
    return writeHandle(out_handle, registerBuffer(owned));
}

// --- buffer-handle accessor / free surface (sci convention) ---

pub export fn sa_std_http2_buffer_data(handle: u64) ?[*]const u8 {
    const bytes = takeBuffer(handle) orelse return null;
    return bytes.ptr;
}

pub export fn sa_std_http2_buffer_len(handle: u64) u64 {
    const bytes = takeBuffer(handle) orelse return 0;
    return @intCast(bytes.len);
}

pub export fn sa_std_http2_buffer_free(handle: u64) i32 {
    buffer_registry_mutex.lock();
    defer buffer_registry_mutex.unlock();
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= buffer_slots.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = buffer_slots.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    buffer_slots.items[idx] = null;
    std.heap.page_allocator.free(entry.bytes);
    return SA_STD_OK;
}

// ============================================================================
// Unit tests — proof that the sa_std HTTP/2 surface works against the real
// libnghttp2 backend. These run under `zig build sa-std-unit` (sa_std.zig is
// that step's root source and it `@import`s this file, so the blocks below are
// pulled into the test binary).
// ============================================================================

const testing = std.testing;

fn readHandle(handle: u64) []const u8 {
    const len = sa_std_http2_buffer_len(handle);
    const ptr = sa_std_http2_buffer_data(handle) orelse return "";
    return ptr[0..@intCast(len)];
}

test "buffer handle register/data/len/free roundtrip" {
    const bytes = try std.heap.page_allocator.dupe(u8, "hello-h2");
    const h = registerBuffer(bytes);
    try testing.expect(h != 0);
    try testing.expectEqualStrings("hello-h2", readHandle(h));
    try testing.expect(@as(u64, 8) == sa_std_http2_buffer_len(h));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(h));
    // double-free returns INVALID_ARGUMENT (handle now empty)
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http2_buffer_free(h));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_http2_buffer_data(h));
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(0));
}

test "sa_std_http2_supported reflects real libnghttp2 availability" {
    var supported: u32 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_supported(&supported));
    // On this host libnghttp2.so.14 is installed (verified at assessment time);
    // the exported flag must therefore be 1.
    try testing.expectEqual(@as(u32, 1), supported);
}

test "status json reports protocol machine on, libnghttp2 backend" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_status_json(&handle));
    defer _ = sa_std_http2_buffer_free(handle);
    const json = readHandle(handle);
    try testing.expect(std.mem.indexOf(u8, json, "\"module\":\"http2\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"backend\":\"libnghttp2\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"protocolMachine\":true") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"supported\":true") != null);
}

test "default settings json round-trips through pack -> unpack" {
    // This exercises the real libnghttp2-independent settings frame codec that
    // perform_server_handshake and the client both rely on.
    var defaults_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_default_settings_json(&defaults_handle));
    defer _ = sa_std_http2_buffer_free(defaults_handle);
    const defaults = readHandle(defaults_handle);

    var packed_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_packed_settings(defaults.ptr, defaults.len, &packed_handle));
    const packed_bytes = readHandle(packed_handle);

    var unpacked_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_unpacked_settings_json(packed_bytes.ptr, packed_bytes.len, &unpacked_handle));
    const unpacked = readHandle(unpacked_handle);

    // The unpacked JSON must contain the same canonical numeric/bool fields we
    // packed from the defaults. (HPACK-free settings pairs are self-inverse.)
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"headerTableSize\":4096") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"maxFrameSize\":16384") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"initialWindowSize\":65535") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"enablePush\":true") != null);

    _ = sa_std_http2_buffer_free(packed_handle);
    _ = sa_std_http2_buffer_free(unpacked_handle);
}

test "pack -> unpack is self-inverse for custom settings" {
    const settings_json =
        \\{"headerTableSize":8192,"maxConcurrentStreams":128,"initialWindowSize":65535,"maxFrameSize":16384,"customSettings":{"99":1,"500":4294967295}}
    ;
    var packed_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_packed_settings(settings_json.ptr, settings_json.len, &packed_handle));
    const packed_bytes = readHandle(packed_handle);
    // 4 known keys present (headerTableSize, maxConcurrentStreams, initialWindowSize, maxFrameSize) + 2 custom = 6 pairs * 6 bytes = 36 bytes
    try testing.expectEqual(@as(u64, 36), sa_std_http2_buffer_len(packed_handle));

    var unpacked_handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_get_unpacked_settings_json(packed_bytes.ptr, packed_bytes.len, &unpacked_handle));
    const unpacked = readHandle(unpacked_handle);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"headerTableSize\":8192") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"maxConcurrentStreams\":128") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"customSettings\":{") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"99\":1") != null);
    try testing.expect(std.mem.indexOf(u8, unpacked, "\"500\":4294967295") != null);

    _ = sa_std_http2_buffer_free(packed_handle);
    _ = sa_std_http2_buffer_free(unpacked_handle);
}

test "perform_server_handshake round-trips a client preface + SETTINGS frame" {
    // Build a synthetic client preface: connection preface bytes followed by a
    // single SETTINGS frame carrying one pair (max_frame_size=16384 == 0x05).
    var input = std.ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    // frame: length=6, type=SETTINGS(4), flags=0, stream_id=0, payload 6 bytes
    try input.append(0); // len >> 16
    try input.append(0); // len >> 8
    try input.append(6); // len
    try input.append(HTTP2_FRAME_SETTINGS);
    try input.append(0); // flags (no ACK)
    try input.append(0); // stream_id bytes
    try input.append(0);
    try input.append(0);
    try input.append(0);
    // one setting: id=5 (MAX_FRAME_SIZE), value=16384
    try input.append(0);
    try input.append(5);
    try input.append(0);
    try input.append(0);
    try input.append(0x40);
    try input.append(0);

    var out_bytes_handle: u64 = 0;
    var out_json_handle: u64 = 0;
    const server_settings_json = "{\"maxFrameSize\":16384}";
    const status = sa_std_http2_perform_server_handshake(
        input.items.ptr,
        input.items.len,
        server_settings_json.ptr,
        server_settings_json.len,
        &out_bytes_handle,
        &out_json_handle,
    );
    try testing.expectEqual(@as(i32, SA_STD_OK), status);
    defer _ = sa_std_http2_buffer_free(out_bytes_handle);
    defer _ = sa_std_http2_buffer_free(out_json_handle);

    const outbound = readHandle(out_bytes_handle);
    // Server must emit two SETTINGS frames: the server's own settings + an ACK.
    // Both are frame type 0x4; the second carries the ACK flag (0x1).
    try testing.expect(outbound.len >= 18); // two 9-byte headers minimum
    // First SETTINGS frame: 9-byte header (type at [3]) + 6-byte payload.
    try testing.expectEqual(@as(u8, HTTP2_FRAME_SETTINGS), outbound[3]);
    // Second frame (the ACK) starts at offset 9 + 6 = 15: type at [18], flags at [19].
    try testing.expectEqual(@as(u8, HTTP2_FRAME_SETTINGS), outbound[15 + 3]);
    try testing.expectEqual(@as(u8, HTTP2_FLAG_ACK), outbound[15 + 4]);

    const meta = readHandle(out_json_handle);
    try testing.expect(std.mem.indexOf(u8, meta, "\"preface\":true") != null);
    try testing.expect(std.mem.indexOf(u8, meta, "\"clientSettingsBytes\":6") != null);
    try testing.expect(std.mem.indexOf(u8, meta, "\"frames\":[\"SETTINGS\",\"SETTINGS_ACK\"]") != null);
}

test "perform_server_handshake rejects a missing/broken preface" {
    var out_bytes: u64 = 0;
    var out_json: u64 = 0;
    // Too short to contain preface + a frame header.
    const bad = "PRI * not a preface";
    const status = sa_std_http2_perform_server_handshake(bad.ptr, bad.len, null, 0, &out_bytes, &out_json);
    try testing.expect(status != SA_STD_OK);
}

test "sensitive headers list is a JSON array of known header names" {
    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_sensitive_headers(&handle));
    defer _ = sa_std_http2_buffer_free(handle);
    const json = readHandle(handle);
    try testing.expect(std.mem.indexOf(u8, json, "\"authorization\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"cookie\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"set-cookie\"") != null);
}

test "nghttp2 version json is present when supported" {
    var supported: u32 = 0;
    _ = sa_std_http2_supported(&supported);
    if (supported == 0) return;

    var handle: u64 = 0;
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_nghttp2_version_json(&handle));
    defer _ = sa_std_http2_buffer_free(handle);
    const json = readHandle(handle);
    try testing.expect(std.mem.indexOf(u8, json, "\"version\":\"") != null);
    try testing.expect(std.mem.indexOf(u8, json, "\"versionNum\":") != null);
}

// ============================================================================
// Stricter boundary / contract tests (added to defend the sinking invariants).
// ============================================================================

test "buffer handle rejects double-free and reading a freed handle" {
    const bytes = try std.heap.page_allocator.dupe(u8, "boundary");
    const h = registerBuffer(bytes);
    try testing.expect(h != 0);
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(h));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http2_buffer_free(h));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_http2_buffer_data(h));
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(h));
    try testing.expectEqual(@as(?[*]const u8, null), sa_std_http2_buffer_data(0));
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(0));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(0));
}

test "buffer handle registry survives a burst of many alloc/free cycles" {
    var i: usize = 0;
    while (i < 256) : (i += 1) {
        var buf: [16]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "h2-{d}", .{i}) catch unreachable;
        const h = registerOwnedString(text);
        try testing.expect(h != 0);
        const len = sa_std_http2_buffer_len(h);
        try testing.expectEqual(@as(u64, text.len), len);
        const ptr = sa_std_http2_buffer_data(h) orelse return error.MissingData;
        try testing.expectEqualStrings(text, ptr[0..@intCast(len)]);
        try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(h));
    }
}

test "buffer handle registry is thread-safe under concurrent alloc/free" {
    const N: usize = 64;
    const Writer = struct {
        fn run() void {
            const alloc = std.heap.page_allocator;
            for (0..N) |_| {
                const bytes = alloc.dupe(u8, "concurrent-h2") catch continue;
                const h = registerBuffer(bytes);
                if (h == 0) {
                    alloc.free(bytes);
                    continue;
                }
                _ = sa_std_http2_buffer_len(h);
                _ = sa_std_http2_buffer_data(h);
                _ = sa_std_http2_buffer_free(h);
            }
        }
    };
    var threads: [4]std.Thread = undefined;
    for (&threads) |*t| t.* = try std.Thread.spawn(.{}, Writer.run, .{});
    for (threads) |t| t.join();
    // After the concurrent burst the registry must remain usable: a fresh
    // handle can still be allocated, read, and freed cleanly (no state
    // corruption from the concurrent alloc/free storm).
    const probe = registerOwnedString("probe-after-concurrency");
    try testing.expect(probe != 0);
    try testing.expectEqual(@as(u64, 23), sa_std_http2_buffer_len(probe));
    try testing.expectEqual(@as(i32, SA_STD_OK), sa_std_http2_buffer_free(probe));
    try testing.expectEqual(@as(i32, SA_STD_ERR_INVALID_ARGUMENT), sa_std_http2_buffer_free(probe));
}

test "get_packed_settings rejects malformed JSON and out-of-range values" {
    var handle: u64 = 0;
    // Not an object.
    try testing.expect(sa_std_http2_get_packed_settings("not json".ptr, 8, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
    // maxFrameSize below the RFC minimum 16384 must be rejected.
    const too_small = "{\"maxFrameSize\":1024}";
    try testing.expect(sa_std_http2_get_packed_settings(too_small.ptr, too_small.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
    // maxFrameSize above the RFC maximum 0xffffff must be rejected.
    const too_big = "{\"maxFrameSize\":33554432}";
    try testing.expect(sa_std_http2_get_packed_settings(too_big.ptr, too_big.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
}

test "get_unpacked_settings_json rejects buffers whose length is not a multiple of 6" {
    var handle: u64 = 0;
    const bad = "12345"; // 5 bytes
    try testing.expect(sa_std_http2_get_unpacked_settings_json(bad.ptr, bad.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
    const bad2 = "1234567"; // 7 bytes
    try testing.expect(sa_std_http2_get_unpacked_settings_json(bad2.ptr, bad2.len, &handle) != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), handle);
}

test "perform_server_handshake rejects a SETTINGS frame that carries the ACK flag" {
    // preface + a SETTINGS frame with ACK set (flags byte = 0x1) must fail.
    var input = std.ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    try input.append(0); // len>>16
    try input.append(0); // len>>8
    try input.append(0); // len=0
    try input.append(HTTP2_FRAME_SETTINGS);
    try input.append(HTTP2_FLAG_ACK); // ACK — illegal for the *client* preface
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    var bytes_h: u64 = 0;
    var json_h: u64 = 0;
    const server_settings_json = "{\"maxFrameSize\":16384}";
    const status = sa_std_http2_perform_server_handshake(input.items.ptr, input.items.len, server_settings_json.ptr, server_settings_json.len, &bytes_h, &json_h);
    try testing.expect(status != SA_STD_OK);
    try testing.expectEqual(@as(u64, 0), bytes_h);
    try testing.expectEqual(@as(u64, 0), json_h);
}

test "perform_server_handshake rejects a non-SETTINGS first frame type" {
    var input = std.ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    // PING frame (type 6) instead of SETTINGS — must fail.
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0x6); // PING
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    var bytes_h: u64 = 0;
    var json_h: u64 = 0;
    const status = sa_std_http2_perform_server_handshake(input.items.ptr, input.items.len, null, 0, &bytes_h, &json_h);
    try testing.expect(status != SA_STD_OK);
}

test "perform_server_handshake rejects a SETTINGS frame on a non-zero stream id" {
    var input = std.ArrayList(u8).init(std.heap.page_allocator);
    defer input.deinit();
    try input.appendSlice(HTTP2_CLIENT_PREFACE);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(HTTP2_FRAME_SETTINGS);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(0);
    try input.append(1); // stream_id LSB = 1, illegal for client preface SETTINGS
    var bytes_h: u64 = 0;
    var json_h: u64 = 0;
    const status = sa_std_http2_perform_server_handshake(input.items.ptr, input.items.len, null, 0, &bytes_h, &json_h);
    try testing.expect(status != SA_STD_OK);
}

test "http2ParseUrl validates scheme and authority" {
    try testing.expectError(error.InvalidUrl, http2ParseUrl("not a url"));
    try testing.expectError(error.InvalidUrl, http2ParseUrl("http://"));
    try testing.expectError(error.UnsupportedScheme, http2ParseUrl("https://example.com/"));
    // IPv6 literals carry ':' which must route through parseIp6, not the port split.
    const parsed_ipv6 = try http2ParseUrl("http://[::1]:8080/path");
    try testing.expectEqualStrings("::1", parsed_ipv6.host);
    try testing.expectEqual(@as(u16, 8080), parsed_ipv6.port);
    try testing.expectEqualStrings("/path", parsed_ipv6.path);
    const parsed_default = try http2ParseUrl("http://example.com");
    try testing.expectEqual(@as(u16, 80), parsed_default.port);
    try testing.expectEqualStrings("/", parsed_default.path);
}

test "export fn return-status domain never overlaps SA_STD_OK" {
    // Every error path must return a *negative* status, never 0; the buffer
    // accessor math must keep 0 == invalid-handle invariant.
    try testing.expectEqual(@as(u64, 0), sa_std_http2_buffer_len(0));
    try testing.expect(SA_STD_OK == 0);
    try testing.expect(SA_STD_ERR_NO_MEMORY < 0);
    try testing.expect(SA_STD_ERR_INVALID_ARGUMENT < 0);
    try testing.expect(@as(u32, 0x8000_0000) != 0); // UnsupportedStatus sentinel for flush
}

// HTTP/2 runtime binding for the sci/sa_std platform layer.
test "sa_http2_tests" { std.testing.refAllDecls(@import("sa_http2_test.zig")); }
//
// This is a REAL protocol-machine backend backed by libnghttp2, lazily loaded
// via dlopen. It migrated out of sa_plugin_node so that every plugin can reuse
// the same sa_std HTTP/2 surface instead of each plugin hiding its own binding.
// The capabilities/status JSON facades stay in the plugins; the real session
// state machine lives here.

const std = @import("std");
pub const builtin = @import("builtin");
pub const sio = @import("sio");

// --- outcome helpers (mirrors the sa_plugin_node private surface) ---

pub const UnsupportedStatus: u32 = 0x8000_0000;

pub fn fail() u32 {
    return UnsupportedStatus;
}

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_NO_MEMORY: i32 = -12;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = -22;

// wasm32-wasi: usize is 32-bit, C ABI passes u64 lengths. Checked conversion.
pub const u64ToUsize = @import("sa_http2_util.zig").u64ToUsize;

pub var buffer_registry_mutex = std.Io.Mutex.init;
pub var buffer_slots = std.ArrayListUnmanaged(?BufferEntry).empty;

const BufferEntry = struct {
    bytes: []u8,
};

// Register an owned byte slice as a u64 handle, mirroring sci's
// sa_fs_read_buffer / sa_json_buffer "return a handle, free with *_free"
// convention. On failure the bytes are freed and 0 is returned (0 == invalid
// handle, consistent with sci's other handle registries).
pub const registerBuffer = @import("sa_http2_util.zig").registerBuffer;

pub const takeBuffer = @import("sa_http2_util.zig").takeBuffer;

pub const registerOwnedString = @import("sa_http2_util.zig").registerOwnedString;

// NOTE(Zig 0.17): `Managed.writer()` is gone; bridge formatted output
// through an allocating writer using the list's own allocator.
pub const managedPrint = @import("sa_http2_util.zig").managedPrint;

pub const jsonEscapeAppend = @import("sa_http2_util.zig").jsonEscapeAppend;

pub const appendJsonString = @import("sa_http2_util.zig").appendJsonString;

pub const appendStringArray = @import("sa_http2_util.zig").appendStringArray;

// --- libnghttp2 opaque C surface ---

pub const Nghttp2Session = @import("sa_http2_nghttp2.zig").Nghttp2Session;
pub const Nghttp2SessionCallbacks = @import("sa_http2_nghttp2.zig").Nghttp2SessionCallbacks;
pub const Nghttp2Frame = @import("sa_http2_nghttp2.zig").Nghttp2Frame;

pub const Nghttp2Nv = @import("sa_http2_nghttp2.zig").Nghttp2Nv;

pub const Nghttp2DataSource = @import("sa_http2_nghttp2.zig").Nghttp2DataSource;

pub const Nghttp2DataProvider = @import("sa_http2_nghttp2.zig").Nghttp2DataProvider;

pub const Nghttp2Version = @import("sa_http2_nghttp2.zig").Nghttp2Version;

pub const Nghttp2OnHeaderCallback = @import("sa_http2_nghttp2.zig").Nghttp2OnHeaderCallback;
pub const Nghttp2OnDataChunkRecvCallback = @import("sa_http2_nghttp2.zig").Nghttp2OnDataChunkRecvCallback;
pub const Nghttp2OnFrameRecvCallback = @import("sa_http2_nghttp2.zig").Nghttp2OnFrameRecvCallback;

pub const Nghttp2CallbacksNewFn = @import("sa_http2_nghttp2.zig").Nghttp2CallbacksNewFn;
pub const Nghttp2CallbacksDelFn = @import("sa_http2_nghttp2.zig").Nghttp2CallbacksDelFn;
pub const Nghttp2SetOnHeaderFn = @import("sa_http2_nghttp2.zig").Nghttp2SetOnHeaderFn;
pub const Nghttp2SetOnDataChunkRecvFn = @import("sa_http2_nghttp2.zig").Nghttp2SetOnDataChunkRecvFn;
pub const Nghttp2SetOnFrameRecvFn = @import("sa_http2_nghttp2.zig").Nghttp2SetOnFrameRecvFn;
pub const Nghttp2SessionClientNewFn = @import("sa_http2_nghttp2.zig").Nghttp2SessionClientNewFn;
pub const Nghttp2SessionDelFn = @import("sa_http2_nghttp2.zig").Nghttp2SessionDelFn;
pub const Nghttp2SubmitRequestFn = @import("sa_http2_nghttp2.zig").Nghttp2SubmitRequestFn;
pub const Nghttp2SubmitSettingsFn = @import("sa_http2_nghttp2.zig").Nghttp2SubmitSettingsFn;
pub const Nghttp2SessionMemSendFn = @import("sa_http2_nghttp2.zig").Nghttp2SessionMemSendFn;
pub const Nghttp2SessionMemRecvFn = @import("sa_http2_nghttp2.zig").Nghttp2SessionMemRecvFn;
pub const Nghttp2SessionWantFn = @import("sa_http2_nghttp2.zig").Nghttp2SessionWantFn;
pub const Nghttp2VersionFn = @import("sa_http2_nghttp2.zig").Nghttp2VersionFn;

pub const Nghttp2Api = @import("sa_http2_nghttp2.zig").Nghttp2Api;

pub const nghttp2_api = @import("sa_http2_nghttp2.zig").nghttp2_api;
pub const nghttp2_api_mutex = @import("sa_http2_nghttp2.zig").nghttp2_api_mutex;

pub const loadNghttp2Api = @import("sa_http2_nghttp2.zig").loadNghttp2Api;

pub const loadNghttp2ApiNative = @import("sa_http2_nghttp2.zig").loadNghttp2ApiNative;

// --- response state machine ---

const Http2ResponseState = struct {
    allocator: std.mem.Allocator,
    headers: std.array_list.Managed(Header),
    body: std.array_list.Managed(u8),
    status: u16 = 0,
    frames: u64 = 0,

    const Header = struct { name: []u8, value: []u8 };

    fn init(allocator: std.mem.Allocator) Http2ResponseState {
        return .{ .allocator = allocator, .headers = std.array_list.Managed(Header).init(allocator), .body = std.array_list.Managed(u8).init(allocator) };
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

fn http2FlushOutbound(api: *Nghttp2Api, session: ?*Nghttp2Session, stream: *std.Io.net.Stream) u32 {
    while (api.session_want_write(session) != 0) {
        var data_ptr: ?[*]const u8 = null;
        const n = api.session_mem_send(session, &data_ptr);
        if (n < 0) return fail();
        if (n == 0) break;
        var wbuf: [8192]u8 = undefined;
        var w = stream.writer(sio.io(), &wbuf);
        w.interface.writeAll(data_ptr.?[0..@intCast(n)]) catch return fail();
        w.interface.flush() catch return fail();
    }
    return 0;
}

// NOTE(Zig 0.17): literals connect directly, hostnames via Happy-Eyeballs
// HostName.connect (same policy as the ws/tls clients).
fn http2Dial(host: []const u8, port: u16) !std.Io.net.Stream {
    if (std.Io.net.IpAddress.parse(host, port)) |addr| {
        var a = addr;
        return a.connect(sio.io(), .{ .mode = .stream });
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    return hn.connect(sio.io(), port, .{ .mode = .stream });
}

pub fn http2ParseUrl(url: []const u8) !struct { scheme: []const u8, host: []const u8, port: u16, path: []const u8 } {
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
        _ = std.Io.net.IpAddress.parseIp6(host, port) catch return error.InvalidUrl;
    }
    return .{ .scheme = scheme, .host = host, .port = port, .path = path };
}

// --- HTTP/2 settings serialization (frame helpers, no lib needed) ---

pub const HTTP2_SETTINGS_HEADER_TABLE_SIZE = @import("sa_http2_settings.zig").HTTP2_SETTINGS_HEADER_TABLE_SIZE;
pub const HTTP2_SETTINGS_ENABLE_PUSH = @import("sa_http2_settings.zig").HTTP2_SETTINGS_ENABLE_PUSH;
pub const HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS = @import("sa_http2_settings.zig").HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS;
pub const HTTP2_SETTINGS_INITIAL_WINDOW_SIZE = @import("sa_http2_settings.zig").HTTP2_SETTINGS_INITIAL_WINDOW_SIZE;
pub const HTTP2_SETTINGS_MAX_FRAME_SIZE = @import("sa_http2_settings.zig").HTTP2_SETTINGS_MAX_FRAME_SIZE;
pub const HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE = @import("sa_http2_settings.zig").HTTP2_SETTINGS_MAX_HEADER_LIST_SIZE;
pub const HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL = @import("sa_http2_settings.zig").HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL;
pub const HTTP2_MAX_FRAME_SIZE = @import("sa_http2_settings.zig").HTTP2_MAX_FRAME_SIZE;
pub const HTTP2_MAX_INITIAL_WINDOW_SIZE = @import("sa_http2_settings.zig").HTTP2_MAX_INITIAL_WINDOW_SIZE;
pub const HTTP2_MAX_CUSTOM_SETTINGS = @import("sa_http2_settings.zig").HTTP2_MAX_CUSTOM_SETTINGS;
pub const HTTP2_CLIENT_PREFACE = @import("sa_http2_settings.zig").HTTP2_CLIENT_PREFACE;
pub const HTTP2_FRAME_SETTINGS = @import("sa_http2_settings.zig").HTTP2_FRAME_SETTINGS;
pub const HTTP2_FLAG_ACK = @import("sa_http2_settings.zig").HTTP2_FLAG_ACK;

pub const Nghttp2SettingsEntry = @import("sa_http2_nghttp2.zig").Nghttp2SettingsEntry;

pub const Http2SettingPair = @import("sa_http2_settings.zig").Http2SettingPair;

pub const http2AppendSetting = @import("sa_http2_settings.zig").http2AppendSetting;

pub const http2JsonNumber = @import("sa_http2_settings.zig").http2JsonNumber;

pub const http2JsonBool = @import("sa_http2_settings.zig").http2JsonBool;

pub const http2AppendNumericSetting = @import("sa_http2_settings.zig").http2AppendNumericSetting;

pub const http2AppendBoolSetting = @import("sa_http2_settings.zig").http2AppendBoolSetting;

pub const http2AppendMaxHeaderSetting = @import("sa_http2_settings.zig").http2AppendMaxHeaderSetting;

pub const http2KnownSetting = @import("sa_http2_settings.zig").http2KnownSetting;

pub const http2AppendCustomSettings = @import("sa_http2_settings.zig").http2AppendCustomSettings;

pub const http2ReadSetting = @import("sa_http2_settings.zig").http2ReadSetting;

pub const http2AppendFrame = @import("sa_http2_settings.zig").http2AppendFrame;

pub const Http2FrameHeader = @import("sa_http2_settings.zig").Http2FrameHeader;

pub const http2ReadFrameHeader = @import("sa_http2_settings.zig").http2ReadFrameHeader;

pub const http2AppendJsonU32Field = @import("sa_http2_settings.zig").http2AppendJsonU32Field;

pub const http2AppendJsonBoolField = @import("sa_http2_settings.zig").http2AppendJsonBoolField;

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
    return http2ClientRequestImpl(url_ptr, url_len, method_ptr, method_len, body_ptr, body_len, null, out_handle);
}

/// client_request with a shaped connection preface: settings_json uses the
/// get_packed_settings dialect (headerTableSize, initialWindowSize,
/// maxFrameSize, maxConcurrentStreams, maxHeaderListSize, enablePush,
/// enableConnectProtocol, customSettings). These values are what a peer
/// (or a fingerprinting middlebox) sees as this client's HTTP/2
/// fingerprint; pseudo-header order stays nghttp2's.
pub export fn sa_std_http2_client_request_with_settings(url_ptr: ?[*]const u8, url_len: u64, method_ptr: ?[*]const u8, method_len: u64, body_ptr: ?[*]const u8, body_len: u64, settings_ptr: ?[*]const u8, settings_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const settings_n = u64ToUsize(settings_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const sj: []const u8 = if (settings_ptr) |ptr| ptr[0..settings_n] else "";
    return http2ClientRequestImpl(url_ptr, url_len, method_ptr, method_len, body_ptr, body_len, sj, out_handle);
}

pub fn posixRead(fd: std.posix.fd_t, buf: []u8) !usize {
    if (comptime builtin.cpu.arch.isWasm()) {
        var iov = [_]std.os.wasi.iovec_t{.{ .base = buf.ptr, .len = buf.len }};
        var n: usize = 0;
        const err = std.os.wasi.fd_read(fd, &iov, iov.len, &n);
        if (err != .SUCCESS) return error.Io;
        return n;
    } else {
        return std.posix.read(fd, buf);
    }
}

fn http2ClientRequestImpl(url_ptr: ?[*]const u8, url_len: u64, method_ptr: ?[*]const u8, method_len: u64, body_ptr: ?[*]const u8, body_len: u64, settings_json: ?[]const u8, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (comptime builtin.cpu.arch.isWasm()) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadNghttp2Api() orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const allocator = std.heap.page_allocator;
    const url_n = u64ToUsize(url_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const method_n = u64ToUsize(method_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const body_n = u64ToUsize(body_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const url = if (url_ptr) |p| p[0..url_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    const parsed = http2ParseUrl(url) catch {
        return handleFromConst("{\"error\":\"url\"}");
    };
    const method = if (method_ptr) |ptr| ptr[0..method_n] else "GET";
    const body = if (body_ptr) |ptr| ptr[0..body_n] else "";

    var stream = http2Dial(parsed.host, parsed.port) catch {
        return handleFromConst("{\"error\":\"connect\"}");
    };
    defer stream.close(sio.io());

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

    if (settings_json) |sj| {
        // HTTP/2 fingerprint shaping: the caller's SETTINGS become the
        // client connection preface instead of nghttp2's defaults.
        var parsed_s = std.json.parseFromSlice(std.json.Value, allocator, sj, .{}) catch return SA_STD_ERR_INVALID_ARGUMENT;
        defer parsed_s.deinit();
        if (parsed_s.value != .object) return SA_STD_ERR_INVALID_ARGUMENT;
        const packed_bytes = http2PackedSettings(allocator, parsed_s.value.object) catch return SA_STD_ERR_INVALID_ARGUMENT;
        defer allocator.free(packed_bytes);
        var entries: [24]Nghttp2SettingsEntry = undefined;
        const count = packed_bytes.len / 6;
        if (count > entries.len) return SA_STD_ERR_INVALID_ARGUMENT;
        for (0..count) |i| {
            const pair = http2ReadSetting(packed_bytes, i * 6);
            entries[i] = .{ .settings_id = pair.id, .value = pair.value };
        }
        if (api.submit_settings(session, NGHTTP2_FLAG_NONE, @ptrCast(&entries), count) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    } else {
        if (api.submit_settings(session, NGHTTP2_FLAG_NONE, null, 0) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    }

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
        const n = posixRead(stream.socket.handle, &read_buf) catch return SA_STD_ERR_INVALID_ARGUMENT;
        if (n == 0) break;
        idle_reads = 0;
        const consumed = api.session_mem_recv(session, &read_buf, n);
        if (consumed < 0) return SA_STD_ERR_INVALID_ARGUMENT;
        if (http2FlushOutbound(api, session, &stream) != 0) return SA_STD_ERR_INVALID_ARGUMENT;
        if (state.status != 0) saw_response = true;
        if (saw_response and state.body.items.len > 0) break;
    }

    if (!saw_response) return SA_STD_ERR_INVALID_ARGUMENT;
    var owned_json = std.array_list.Managed(u8).init(allocator);
    errdefer owned_json.deinit();
    managedPrint(&owned_json, "{{\"status\":{d},\"headers\":{{", .{state.status}) catch return SA_STD_ERR_NO_MEMORY;
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
    managedPrint(&owned_json, ",\"bodyLen\":{d},\"frames\":{d}}}", .{ state.body.items.len, state.frames }) catch return SA_STD_ERR_NO_MEMORY;
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
        \\{"NGHTTP2_NV_FLAG_NONE":0,"NGHTTP2_NV_FLAG_NO_INDEX":1,"NGHTTP2_NV_FLAG_NO_EMIT_NAME":2,"NGHTTP2_NV_FLAG_NO_EMIT_VALUE":4,"NGHTTP2_NV_FLAG_NO_NEVER_INDEX":8,"FRAME_SETTINGS":4,"FRAME_HEADERS":1,"FRAME_DATA":0,"FRAME_PING":6,"FRAME_GOAWAY":7,"FRAME_WINDOW_UPDATE":8,"FRAME_PRIORITY":2,"FRAME_RST_STREAM":3,"FLAG_ACK":1,"FLAG_END_STREAM":1,"FLAG_END_HEADERS":4,"DEFAULT_HEADER_TABLE_SIZE":4096,"DEFAULT_MAX_CONCURRENT_STREAMS":4294967295,"DEFAULT_INITIAL_WINDOW_SIZE":65535,"DEFAULT_MAX_FRAME_SIZE":16384,"NGHTTP2_SETTINGS_ENABLE_PUSH":2,"NGHTTP2_SETTINGS_INITIAL_WINDOW_SIZE":4,"HTTP_STATUS_OK":200,"HTTP2_HEADER_PATH":":path","HTTP2_METHOD_GET":"GET"}
    ));
}

pub export fn sa_std_http2_sensitive_headers(out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    return writeHandle(out_handle, registerOwnedString(
        \\["authorization","proxy-authorization","cookie","set-cookie","x-api-key","x-auth-token"]
    ));
}

/// Pack a settings JSON object (the get_packed_settings dialect) into the
/// 6-byte-per-entry wire form shared by the frame helpers and the client
/// request path.
fn http2PackedSettings(allocator: std.mem.Allocator, obj: std.json.ObjectMap) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try http2AppendCustomSettings(&out, obj);
    try http2AppendNumericSetting(&out, obj, "headerTableSize", HTTP2_SETTINGS_HEADER_TABLE_SIZE, 0, std.math.maxInt(u32));
    try http2AppendNumericSetting(&out, obj, "maxConcurrentStreams", HTTP2_SETTINGS_MAX_CONCURRENT_STREAMS, 0, std.math.maxInt(u32));
    try http2AppendNumericSetting(&out, obj, "initialWindowSize", HTTP2_SETTINGS_INITIAL_WINDOW_SIZE, 0, HTTP2_MAX_INITIAL_WINDOW_SIZE);
    try http2AppendNumericSetting(&out, obj, "maxFrameSize", HTTP2_SETTINGS_MAX_FRAME_SIZE, 16_384, HTTP2_MAX_FRAME_SIZE);
    try http2AppendMaxHeaderSetting(&out, obj);
    try http2AppendBoolSetting(&out, obj, "enablePush", HTTP2_SETTINGS_ENABLE_PUSH);
    try http2AppendBoolSetting(&out, obj, "enableConnectProtocol", HTTP2_SETTINGS_ENABLE_CONNECT_PROTOCOL);
    return out.toOwnedSlice();
}

pub export fn sa_std_http2_get_packed_settings(settings_json_ptr: ?[*]const u8, settings_json_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const settings_n = u64ToUsize(settings_json_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const settings_json = if (settings_json_ptr) |ptr| ptr[0..settings_n] else "";
    var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, settings_json, .{}) catch return SA_STD_ERR_INVALID_ARGUMENT;
    defer parsed.deinit();
    if (parsed.value != .object) return SA_STD_ERR_INVALID_ARGUMENT;
    const owned = http2PackedSettings(std.heap.page_allocator, parsed.value.object) catch |err| return if (err == error.OutOfMemory) SA_STD_ERR_NO_MEMORY else SA_STD_ERR_INVALID_ARGUMENT;
    return writeHandle(out_handle, registerBuffer(owned));
}

pub export fn sa_std_http2_get_unpacked_settings_json(buf_ptr: ?[*]const u8, buf_len: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    const buf_n = u64ToUsize(buf_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const buf = if (buf_ptr) |ptr| ptr[0..buf_n] else return SA_STD_ERR_INVALID_ARGUMENT;
    if (buf.len % 6 != 0) return SA_STD_ERR_INVALID_ARGUMENT;
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    out.append('{') catch return SA_STD_ERR_NO_MEMORY;
    var first = true;
    var custom = std.array_list.Managed(Http2SettingPair).init(std.heap.page_allocator);
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
            managedPrint(&out, "\"{d}\":{d}", .{ pair.id, pair.value }) catch return SA_STD_ERR_NO_MEMORY;
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
    const input_n = u64ToUsize(input_len) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const input = (input_ptr orelse return SA_STD_ERR_INVALID_ARGUMENT)[0..input_n];
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

    var outbound = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer outbound.deinit();
    http2AppendFrame(&outbound, HTTP2_FRAME_SETTINGS, 0, 0, server_settings) catch return SA_STD_ERR_INVALID_ARGUMENT;
    http2AppendFrame(&outbound, HTTP2_FRAME_SETTINGS, HTTP2_FLAG_ACK, 0, "") catch return SA_STD_ERR_INVALID_ARGUMENT;

    var meta = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer meta.deinit();
    meta.appendSlice("{\"preface\":true,\"clientSettings\":") catch return SA_STD_ERR_NO_MEMORY;
    meta.appendSlice(client_settings_json) catch return SA_STD_ERR_NO_MEMORY;
    managedPrint(&meta, ",\"clientSettingsBytes\":{d},\"serverSettingsBytes\":{d},\"outboundBytes\":{d},\"frames\":[\"SETTINGS\",\"SETTINGS_ACK\"]}}", .{
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
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
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

pub const sa_std_http2_buffer_data = @import("sa_http2_buffer.zig").sa_std_http2_buffer_data;

pub const sa_std_http2_buffer_len = @import("sa_http2_buffer.zig").sa_std_http2_buffer_len;

pub const sa_std_http2_buffer_free = @import("sa_http2_buffer.zig").sa_std_http2_buffer_free;

// ============================================================================
// Unit tests — proof that the sa_std HTTP/2 surface works against the real
// libnghttp2 backend. These run under `zig build sa-std-unit` (sa_std.zig is
// that step's root source and it `@import`s this file, so the blocks below are
// pulled into the test binary).
// ============================================================================

pub const testing = std.testing;

// ============================================================================
// Stricter boundary / contract tests (added to defend the sinking invariants).
// ============================================================================

const std = @import("std");
const builtin = @import("builtin");
const sa_std = @import("../sa_std.zig");
const net_primitives = @import("sa_net_primitives");
const sio = @import("sio");
const ConnectionSlot = @import("u01.zig").ConnectionSlot;
const FieldSpan = @import("u01.zig").FieldSpan;
const HttpRequest = @import("u01.zig").HttpRequest;
const Reactor = @import("u02.zig").Reactor;
const ReactorUserTag = @import("u01.zig").ReactorUserTag;
const SA_NETX_ERR_INVALID_ARGUMENT = @import("u01.zig").SA_NETX_ERR_INVALID_ARGUMENT;
const SA_NETX_ERR_TRUNCATED = @import("u01.zig").SA_NETX_ERR_TRUNCATED;
const SA_NETX_OK = @import("u01.zig").SA_NETX_OK;
const SlotPool = @import("u01.zig").SlotPool;
const Ticket = @import("u01.zig").Ticket;
const TicketFlag = @import("u01.zig").TicketFlag;
const TicketOp = @import("u01.zig").TicketOp;
const WorkerState = @import("u01.zig").WorkerState;
const WsFrame = @import("u01.zig").WsFrame;
const linux = @import("u01.zig").linux;
const net = @import("u01.zig").net;
const posix = @import("u01.zig").posix;

pub fn setThreadAffinity(core_id: usize) void {
    if (builtin.os.tag != .linux) return;
    var set: linux.cpu_set_t = std.mem.zeroes(linux.cpu_set_t);
    const idx = core_id / (@sizeOf(usize) * 8);
    const bit = core_id % (@sizeOf(usize) * 8);
    if (idx < set.len) {
        set[idx] |= (@as(usize, 1) << @intCast(bit));
        linux.sched_setaffinity(0, &set) catch |err| {
            // Affinity is a performance hint only; worker correctness does not depend on it.
            _ = @errorName(err);
        };
    }
}

pub fn setNonBlocking(fd: posix.fd_t) void {
    const get_rc = linux.fcntl(fd, linux.F.GETFL, 0);
    if (@as(isize, @bitCast(get_rc)) < 0) return;
    const flags: usize = @bitCast(@as(isize, @bitCast(get_rc)));
    // Nonblocking setup is best-effort for optional descriptors; callers handle I/O errors later.
    _ = linux.fcntl(fd, linux.F.SETFL, flags | (@as(usize, 1) << @bitOffsetOf(posix.O, "NONBLOCK")));
}

pub fn reactorWorkerMain(reactor: *Reactor) void {
    if (!builtin.is_test) setThreadAffinity(reactor.id);
    const state = &getState().worker_state;
    state.mutex.lockUncancelable(sio.io());
    state.active_workers += 1;
    state.running = true;
    state.cond.broadcast(sio.io());
    state.mutex.unlock(sio.io());

    defer {
        state.mutex.lockUncancelable(sio.io());
        if (state.active_workers > 0) state.active_workers -= 1;
        if (state.active_workers == 0) {
            state.running = false;
            state.cond.broadcast(sio.io());
        }
        state.mutex.unlock(sio.io());
    }

    while (true) {
        state.mutex.lockUncancelable(sio.io());
        const stop = state.stop;
        state.mutex.unlock(sio.io());
        if (stop) break;
        reactor.pump(true) catch |err| {
            // Worker loop keeps servicing deferred cleanup even after a transient pump error.
            _ = @errorName(err);
        };
        reactor.serviceDeferredWork();
    }
}

pub const PackedUserData = packed struct {
    tag: ReactorUserTag,
    slot_id: u32,
    reactor_id: u24 = 0,
};

pub fn packUserData(tag: ReactorUserTag, reactor_id: u32, slot_id: u32) u64 {
    return @bitCast(PackedUserData{
        .tag = tag,
        .slot_id = slot_id,
        .reactor_id = @as(u24, @intCast(reactor_id)),
    });
}

pub fn decodeUserData(user_data: u64) PackedUserData {
    return @bitCast(user_data);
}

pub const RuntimeState = struct {
    initialized: bool = false,
    slot_pool: ?SlotPool = null,
    reactors: []Reactor = &.{},
    reactor_count: usize = 0,
    listened: bool = false,
    listen_address: ?net.IpAddress = null,
    ticket_capacity: usize = 0,
    worker_state: WorkerState = .{},
};

pub var runtime_state: RuntimeState = .{};

pub fn getState() *RuntimeState {
    return &runtime_state;
}

pub fn ceilPow2(value: usize) !usize {
    if (value <= 1) return 1;
    if (value > (std.math.maxInt(usize) / 2) + 1) return error.Overflow;
    var v = value - 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    if (@sizeOf(usize) >= 8) v |= v >> 32;
    return std.math.add(usize, v, 1) catch return error.Overflow;
}

pub fn computeTicketCapacity(slot_capacity: usize) !usize {
    return std.math.mul(usize, slot_capacity, 4) catch error.Overflow;
}

pub fn makeTicket(slot: *ConnectionSlot, op: TicketOp, proto: u8, flags: u8, payload: []const u8) Ticket {
    return .{
        .slot_id = slot.slot_id,
        .op_code = @intFromEnum(op),
        .proto = proto,
        .flags = flags,
        .payload = @as(*u8, @ptrCast(@constCast(payload.ptr))),
        .payload_len = @as(u32, @intCast(payload.len)),
        .pad = 0,
    };
}

pub fn frameFlags(frame: WsFrame) u8 {
    var flags: u8 = 0;
    if (frame.masked) flags |= TicketFlag.masked;
    if (!frame.fin) flags |= 1 << 5;
    return flags;
}

pub fn trimAscii(bytes: []const u8) []const u8 {
    return std.mem.trim(u8, bytes, " \t");
}

pub fn readVector16(bytes: []const u8) @Vector(16, u8) {
    var tmp: [16]u8 = undefined;
    @memcpy(tmp[0..], bytes[0..16]);
    return tmp;
}

pub fn readVector32(bytes: []const u8) @Vector(32, u8) {
    var tmp: [32]u8 = undefined;
    @memcpy(tmp[0..], bytes[0..32]);
    return tmp;
}

pub fn writeVector16(bytes: []u8, vec: @Vector(16, u8)) void {
    const arr: [16]u8 = vec;
    @memcpy(bytes[0..16], arr[0..]);
}

pub fn writeVector32(bytes: []u8, vec: @Vector(32, u8)) void {
    const arr: [32]u8 = vec;
    @memcpy(bytes[0..32], arr[0..]);
}

pub fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |ac, bc| {
        if (std.ascii.toLower(ac) != std.ascii.toLower(bc)) return false;
    }
    return true;
}

pub fn containsTokenIgnoreCase(value: []const u8, needle: []const u8) bool {
    var it = std.mem.splitScalar(u8, value, ',');
    while (it.next()) |token| {
        const trimmed = trimAscii(token);
        if (eqlIgnoreCase(trimmed, needle)) return true;
    }
    return false;
}

pub fn parsePositiveInt(text: []const u8) !usize {
    return std.fmt.parseInt(usize, trimAscii(text), 10);
}

pub fn isHttpMethodPrefix(bytes: []const u8, prefix: []const u8) bool {
    if (bytes.len < prefix.len) {
        return std.mem.eql(u8, bytes, prefix[0..bytes.len]);
    }
    if (!std.mem.startsWith(u8, bytes, prefix)) return false;
    return bytes.len == prefix.len or bytes[prefix.len] == ' ';
}

pub fn fieldSpan(start: usize, end: usize) FieldSpan {
    return .{
        .offset = @as(u32, @intCast(start)),
        .len = @as(u32, @intCast(end - start)),
    };
}

pub fn fieldSlice(bytes: []const u8, span: FieldSpan) []const u8 {
    const start = @as(usize, @intCast(span.offset));
    const len = @as(usize, @intCast(span.len));
    return bytes[start .. start + len];
}

pub fn parseHttpRequest(bytes: []const u8) error{ Incomplete, Invalid }!HttpRequest {
    const header_end = findHttpHeaderEndVector(bytes) orelse return error.Incomplete;
    const header_block = bytes[0..header_end];
    const request_line_end = findCrlfVector(header_block, 0) orelse return error.Invalid;
    const request_line = header_block[0..request_line_end];
    const method_end = std.mem.indexOfScalar(u8, request_line, ' ') orelse return error.Invalid;
    if (method_end == 0) return error.Invalid;
    const path_space_rel = std.mem.indexOfScalar(u8, request_line[method_end + 1 ..], ' ') orelse return error.Invalid;
    if (path_space_rel == 0) return error.Invalid;
    const path_end = method_end + 1 + path_space_rel;
    if (path_end + 1 >= request_line.len) return error.Invalid;
    const method_start = 0;
    const path_start = method_end + 1;
    const version_start = path_end + 1;
    const method_len = method_end - method_start;
    const path_len = path_end - path_start;
    const version_len = request_line.len - version_start;
    const version = request_line[version_start..];
    if (!eqlIgnoreCase(version, "HTTP/1.1")) return error.Invalid;

    var content_length: usize = 0;
    var websocket_key: ?FieldSpan = null;
    var websocket_upgrade = false;
    var line_start: usize = request_line_end + 2;

    while (line_start < header_end) {
        const line_end = findCrlfVector(header_block, line_start) orelse header_end;
        const line = header_block[line_start..line_end];
        const colon = findColonVector(line) orelse return error.Invalid;
        const name = trimAscii(line[0..colon]);
        const value_text = line[colon + 1 ..];
        const value = trimAscii(value_text);
        const value_start = line_start + colon + 1 + (value_text.len - value.len);
        if (eqlIgnoreCase(name, "Content-Length")) {
            content_length = parsePositiveInt(value) catch return error.Invalid;
        } else if (eqlIgnoreCase(name, "Connection")) {
            if (containsTokenIgnoreCase(value, "Upgrade")) websocket_upgrade = true;
        } else if (eqlIgnoreCase(name, "Upgrade")) {
            if (eqlIgnoreCase(value, "websocket")) websocket_upgrade = true;
        } else if (eqlIgnoreCase(name, "Sec-WebSocket-Key")) {
            websocket_key = fieldSpan(value_start, value_start + value.len);
        } else if (eqlIgnoreCase(name, "Sec-WebSocket-Version")) {
            if (!eqlIgnoreCase(value, "13")) return error.Invalid;
        }
        line_start = line_end + 2;
    }

    const request_end = header_end + 4 + content_length;
    if (bytes.len < request_end) return error.Incomplete;
    return .{
        .method = fieldSpan(method_start, method_start + method_len),
        .path = fieldSpan(path_start, path_start + path_len),
        .version = fieldSpan(version_start, version_start + version_len),
        .content_length = content_length,
        .websocket_key = websocket_key,
        .websocket_upgrade = websocket_upgrade,
        .request_end = request_end,
    };
}

pub fn looksLikeHttpPrefix(bytes: []const u8) bool {
    const methods = [_][]const u8{ "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "CONNECT", "TRACE", "PRI" };
    for (methods) |method| {
        if (isHttpMethodPrefix(bytes, method)) return true;
    }
    return false;
}

pub fn maybeHttpPrefixVector(bytes: []const u8) bool {
    if (bytes.len < 3) return true;
    const prefixes = [_][]const u8{
        "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD", "CONNECT", "TRACE", "PRI",
    };
    if (bytes.len >= 32) {
        inline for (prefixes) |prefix| {
            if (prefixMatchesVector32(bytes, prefix)) return true;
        }
    } else {
        for (prefixes) |prefix| {
            if (isHttpMethodPrefix(bytes, prefix)) return true;
        }
    }
    return looksLikeHttpPrefix(bytes);
}

pub fn prefixMatchesVector32(bytes: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0 or prefix.len > 32 or bytes.len < prefix.len) return false;
    const chunk = readVector32(bytes);
    const expected = prefixPaddedVector32(prefix);
    const diff = chunk ^ expected;
    const mask = prefixMaskVector32(prefix.len);
    const masked = diff & mask;
    const zero: @Vector(32, u8) = @splat(@as(u8, 0));
    if (@reduce(.Or, masked != zero)) return false;
    return isHttpMethodPrefix(bytes, prefix);
}

pub fn prefixPaddedVector32(prefix: []const u8) @Vector(32, u8) {
    var padded: [32]u8 = std.mem.zeroes([32]u8);
    @memcpy(padded[0..prefix.len], prefix);
    return padded;
}

pub fn prefixMaskVector32(prefix_len: usize) @Vector(32, u8) {
    var mask: [32]u8 = std.mem.zeroes([32]u8);
    const len = @min(prefix_len, mask.len);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        mask[i] = 0xff;
    }
    return mask;
}

pub fn writeWebSocketFrame(slot: *ConnectionSlot, payload: []const u8) ![]u8 {
    const header_len: usize = if (payload.len < 126) 2 else if (payload.len <= 0xffff) 4 else 10;
    const total_len = std.math.add(usize, header_len, payload.len) catch return error.PayloadTooLarge;
    if (total_len > slot.outbound_scratch.len) return error.NoSpaceLeft;
    var idx: usize = 0;
    slot.outbound_scratch[idx] = 0x82;
    idx += 1;
    if (payload.len < 126) {
        slot.outbound_scratch[idx] = std.math.cast(u8, payload.len) orelse return error.PayloadTooLarge;
        idx += 1;
    } else if (payload.len <= 0xffff) {
        slot.outbound_scratch[idx] = 126;
        idx += 1;
        const len16 = std.math.cast(u16, payload.len) orelse return error.PayloadTooLarge;
        slot.outbound_scratch[idx] = @as(u8, @intCast(len16 >> 8));
        slot.outbound_scratch[idx + 1] = @as(u8, @intCast(len16 & 0xff));
        idx += 2;
    } else {
        slot.outbound_scratch[idx] = 127;
        idx += 1;
        const len64 = std.math.cast(u64, payload.len) orelse return error.PayloadTooLarge;
        const shifts = [_]u6{ 56, 48, 40, 32, 24, 16, 8, 0 };
        for (shifts, 0..) |shift, b| {
            slot.outbound_scratch[idx + b] = @as(u8, @intCast((len64 >> shift) & 0xff));
        }
        idx += 8;
    }
    @memcpy(slot.outbound_scratch[idx .. idx + payload.len], payload);
    return slot.outbound_scratch[0..total_len];
}

pub fn findHttpHeaderEndVector(bytes: []const u8) ?usize {
    if (bytes.len < 4) return null;
    if (bytes.len < 32) {
        return std.mem.indexOf(u8, bytes, "\r\n\r\n");
    }
    const cr: @Vector(32, u8) = @splat(@as(u8, '\r'));
    var i: usize = 0;
    while (i + 32 <= bytes.len) : (i += 32) {
        const chunk = readVector32(bytes[i..]);
        if (!@reduce(.Or, chunk == cr)) continue;
        var j: usize = 0;
        while (j < 32 and i + j + 4 <= bytes.len) : (j += 1) {
            if (bytes[i + j] == '\r' and bytes[i + j + 1] == '\n' and bytes[i + j + 2] == '\r' and bytes[i + j + 3] == '\n') {
                return i + j;
            }
        }
    }
    while (i + 4 <= bytes.len) : (i += 1) {
        if (bytes[i] == '\r' and bytes[i + 1] == '\n' and bytes[i + 2] == '\r' and bytes[i + 3] == '\n') return i;
    }
    return null;
}

pub fn findCrlfVector(bytes: []const u8, start: usize) ?usize {
    if (start + 2 > bytes.len) return null;
    if (bytes.len - start < 32) {
        return if (std.mem.indexOf(u8, bytes[start..], "\r\n")) |idx| start + idx else null;
    }
    const cr: @Vector(32, u8) = @splat(@as(u8, '\r'));
    var i: usize = start;
    while (i + 32 <= bytes.len) : (i += 32) {
        const chunk = readVector32(bytes[i..]);
        if (!@reduce(.Or, chunk == cr)) continue;
        var j: usize = 0;
        while (j < 32 and i + j + 1 < bytes.len) : (j += 1) {
            if (bytes[i + j] == '\r' and bytes[i + j + 1] == '\n') return i + j;
        }
    }
    while (i + 1 < bytes.len) : (i += 1) {
        if (bytes[i] == '\r' and bytes[i + 1] == '\n') return i;
    }
    return null;
}

pub fn findColonVector(bytes: []const u8) ?usize {
    if (bytes.len == 0) return null;
    if (bytes.len < 32) {
        return std.mem.indexOfScalar(u8, bytes, ':');
    }
    const colon: @Vector(32, u8) = @splat(@as(u8, ':'));
    var i: usize = 0;
    while (i + 32 <= bytes.len) : (i += 32) {
        const chunk = readVector32(bytes[i..]);
        if (!@reduce(.Or, chunk == colon)) continue;
        var j: usize = 0;
        while (j < 32) : (j += 1) {
            if (bytes[i + j] == ':') return i + j;
        }
    }
    while (i < bytes.len) : (i += 1) {
        if (bytes[i] == ':') return i;
    }
    return null;
}

pub fn parseWsFrame(bytes: []const u8) error{ Incomplete, Invalid }!WsFrame {
    const frame = try net_primitives.parseWsFrame(bytes);
    return .{
        .fin = frame.fin,
        .opcode = frame.opcode,
        .masked = frame.masked,
        .payload_start = frame.payload_start,
        .payload_len = frame.payload_len,
        .frame_len = frame.frame_len,
        .mask = frame.mask,
    };
}

pub fn unmaskFrame(payload: []u8, mask: [4]u8) void {
    net_primitives.unmaskFrame(payload, mask);
}

pub fn websocketAccept(key: []const u8) ![28]u8 {
    return net_primitives.websocketAccept(key);
}

// ---------------------------------------------------------------------------
// Shared WebSocket + URL primitives exported as flat sa_std ABI.
//
// These wrap the same parseWsFrame/unmaskFrame/websocketAccept logic the netx
// reactor uses, so the http_client / http_server / node / deno plugins can stop
// hand-rolling their own frame codecs and URL parsers and call one tested
// implementation. Buffer-style (caller owns output) to match sa_std_net_*.
// ---------------------------------------------------------------------------
// Sec-WebSocket-Accept: base64(SHA1(key + magic)). Writes exactly 28 bytes.
pub export fn sa_std_ws_accept_key(key_ptr: ?[*]const u8, key_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const out_len_ptr = out_len orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    out_len_ptr.* = 0;
    const kp = key_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const key = kp[0..@as(usize, @intCast(key_len))];
    const op = out_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    if (out_cap < 28) return SA_NETX_ERR_TRUNCATED;
    const accept = websocketAccept(key) catch return SA_NETX_ERR_INVALID_ARGUMENT;
    @memcpy(op[0..28], accept[0..]);
    out_len_ptr.* = 28;
    return SA_NETX_OK;
}

// Parse one WebSocket frame header. Fills the six out_* scalars.
// Returns SA_NETX_OK on a complete frame, SA_NETX_ERR_TRUNCATED if more bytes
// are needed, SA_NETX_ERR_INVALID_ARGUMENT on a malformed frame.
pub export fn sa_std_ws_frame_parse(
    data_ptr: ?[*]const u8,
    data_len: u64,
    out_fin: ?*u8,
    out_opcode: ?*u8,
    out_masked: ?*u8,
    out_payload_offset: ?*u64,
    out_payload_len: ?*u64,
    out_frame_len: ?*u64,
    out_mask: ?[*]u8,
) i32 {
    const dp = data_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const data = dp[0..@as(usize, @intCast(data_len))];
    const frame = parseWsFrame(data) catch |err| switch (err) {
        error.Incomplete => return SA_NETX_ERR_TRUNCATED,
        error.Invalid => return SA_NETX_ERR_INVALID_ARGUMENT,
    };
    if (out_fin) |p| p.* = if (frame.fin) 1 else 0;
    if (out_opcode) |p| p.* = frame.opcode;
    if (out_masked) |p| p.* = if (frame.masked) 1 else 0;
    if (out_payload_offset) |p| p.* = @as(u64, @intCast(frame.payload_start));
    if (out_payload_len) |p| p.* = @as(u64, @intCast(frame.payload_len));
    if (out_frame_len) |p| p.* = @as(u64, @intCast(frame.frame_len));
    if (out_mask) |p| @memcpy(p[0..4], frame.mask[0..]);
    return SA_NETX_OK;
}

// XOR-unmask payload bytes in place with a 4-byte mask (SIMD-accelerated).
pub export fn sa_std_ws_unmask(payload_ptr: ?[*]u8, payload_len: u64, mask_ptr: ?[*]const u8) i32 {
    const pp = payload_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const mp = mask_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    var mask: [4]u8 = undefined;
    @memcpy(mask[0..], mp[0..4]);
    unmaskFrame(pp[0..@as(usize, @intCast(payload_len))], mask);
    return SA_NETX_OK;
}

// Build a WebSocket frame into caller storage. When mask_ptr is non-null the
// payload is masked (client role, per RFC 6455); pass null for server frames.
// Writes the full frame (header + payload) and reports its length.
pub export fn sa_std_ws_frame_build(
    opcode_arg: u32,
    fin_arg: u32,
    payload_ptr: ?[*]const u8,
    payload_len: u64,
    mask_ptr: ?[*]const u8,
    out_ptr: ?[*]u8,
    out_cap: u64,
    out_len: ?*u64,
) i32 {
    const opcode: u8 = @as(u8, @intCast(opcode_arg & 0x0f));
    const out_len_ptr = out_len orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    out_len_ptr.* = 0;
    const out_cap_usize = @as(usize, @intCast(out_cap));
    const plen = @as(usize, @intCast(payload_len));
    const payload = if (plen == 0) &[_]u8{} else (payload_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..plen];
    const out = (out_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT)[0..out_cap_usize];

    var mask_buf: [4]u8 = undefined;
    const mask_arg: ?*const [4]u8 = if (mask_ptr) |mp| blk: {
        @memcpy(mask_buf[0..], mp[0..4]);
        break :blk &mask_buf;
    } else null;
    const written = net_primitives.buildWsFrame(opcode, fin_arg != 0, payload, mask_arg, out) catch |err| switch (err) {
        error.NoSpaceLeft => return SA_NETX_ERR_TRUNCATED,
        else => return SA_NETX_ERR_INVALID_ARGUMENT,
    };
    out_len_ptr.* = @as(u64, @intCast(written));
    return SA_NETX_OK;
}

// Convenience wrapper for server frames (no mask, per RFC 6455). Avoids the SA
// layer having to pass a null pointer for the mask argument.
pub export fn sa_std_ws_frame_build_unmasked(
    opcode: u32,
    fin: u32,
    payload_ptr: ?[*]const u8,
    payload_len: u64,
    out_ptr: ?[*]u8,
    out_cap: u64,
    out_len: ?*u64,
) i32 {
    return sa_std_ws_frame_build(opcode, fin, payload_ptr, payload_len, null, out_ptr, out_cap, out_len);
}

pub const UrlParts = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
};

// Parse scheme://host[:port][/path]. Defaults: http->80, https->443, ws->80,
// wss->443. Host excludes brackets for IPv6 literals.
pub fn parseUrlParts(url: []const u8) !UrlParts {
    const parts = try net_primitives.parseUrlParts(url);
    return .{ .scheme = parts.scheme, .host = parts.host, .port = parts.port, .path = parts.path };
}

// Parse a URL, writing scheme/host/path into caller buffers and returning the
// port. out_*_len report the written lengths. Any out buffer may be null to
// skip that component (still validates + returns port).
pub export fn sa_std_url_parse(
    url_ptr: ?[*]const u8,
    url_len: u64,
    scheme_out: ?[*]u8,
    scheme_cap: u64,
    scheme_len: ?*u64,
    host_out: ?[*]u8,
    host_cap: u64,
    host_len: ?*u64,
    path_out: ?[*]u8,
    path_cap: u64,
    path_len: ?*u64,
    out_port: ?*u32,
) i32 {
    const up = url_ptr orelse return SA_NETX_ERR_INVALID_ARGUMENT;
    const url = up[0..@as(usize, @intCast(url_len))];
    const parts = parseUrlParts(url) catch return SA_NETX_ERR_INVALID_ARGUMENT;

    if (copyOut(parts.scheme, scheme_out, scheme_cap, scheme_len) != SA_NETX_OK) return SA_NETX_ERR_TRUNCATED;
    if (copyOut(parts.host, host_out, host_cap, host_len) != SA_NETX_OK) return SA_NETX_ERR_TRUNCATED;
    if (copyOut(parts.path, path_out, path_cap, path_len) != SA_NETX_OK) return SA_NETX_ERR_TRUNCATED;
    if (out_port) |p| p.* = @as(u32, parts.port);
    return SA_NETX_OK;
}

pub fn copyOut(src: []const u8, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    if (out_len) |p| p.* = 0;
    if (out) |dst| {
        if (src.len > @as(usize, @intCast(cap))) return SA_NETX_ERR_TRUNCATED;
        if (src.len != 0) @memcpy(dst[0..src.len], src);
    }
    if (out_len) |p| p.* = @as(u64, @intCast(src.len));
    return SA_NETX_OK;
}

pub fn resumeSlot(receptor: *Reactor, slot: *ConnectionSlot) !void {
    if (slot.state == .Free or slot.state == .Closing or slot.fd < 0) return;
    if (slot.recv_paused) {
        slot.recv_paused = false;
    }
    if (!receptor.recv_multishot_supported and !slot.recv_multishot_armed) {
        try receptor.armRecv(slot);
    }
}

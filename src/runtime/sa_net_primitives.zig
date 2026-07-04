const std = @import("std");

pub const WsFrame = struct {
    fin: bool,
    opcode: u8,
    masked: bool,
    payload_start: usize,
    payload_len: usize,
    frame_len: usize,
    mask: [4]u8,
};

pub const UrlParts = struct {
    scheme: []const u8,
    host: []const u8,
    port: u16,
    path: []const u8,
};

pub fn websocketAccept(key: []const u8) ![28]u8 {
    var sha1 = std.crypto.hash.Sha1.init(.{});
    sha1.update(key);
    sha1.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [20]u8 = undefined;
    sha1.final(&digest);

    var out: [28]u8 = undefined;
    _ = std.base64.standard.Encoder.encode(out[0..], digest[0..]);
    return out;
}

pub fn parseWsFrame(bytes: []const u8) error{ Incomplete, Invalid }!WsFrame {
    if (bytes.len < 2) return error.Incomplete;
    const b0 = bytes[0];
    const b1 = bytes[1];
    const fin = (b0 & 0x80) != 0;
    const opcode = b0 & 0x0f;
    const masked = (b1 & 0x80) != 0;
    var payload_len: usize = b1 & 0x7f;
    var idx: usize = 2;
    if (payload_len == 126) {
        if (bytes.len < 4) return error.Incomplete;
        payload_len = std.mem.readInt(u16, bytes[2..4], .big);
        idx = 4;
    } else if (payload_len == 127) {
        if (bytes.len < 10) return error.Incomplete;
        const raw = std.mem.readInt(u64, bytes[2..10], .big);
        payload_len = std.math.cast(usize, raw) orelse return error.Invalid;
        idx = 10;
    }

    var mask: [4]u8 = .{ 0, 0, 0, 0 };
    if (masked) {
        if (bytes.len < idx + 4) return error.Incomplete;
        @memcpy(mask[0..], bytes[idx .. idx + 4]);
        idx += 4;
    }

    if (bytes.len < idx + payload_len) return error.Incomplete;
    return .{
        .fin = fin,
        .opcode = opcode,
        .masked = masked,
        .payload_start = idx,
        .payload_len = payload_len,
        .frame_len = idx + payload_len,
        .mask = mask,
    };
}

pub fn unmaskFrame(payload: []u8, mask: [4]u8) void {
    if (payload.len == 0) return;
    const vec_len = 16;
    if (payload.len >= 32) {
        const mask16: @Vector(16, u8) = .{
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
        };
        const mask32: @Vector(32, u8) = .{
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
            mask[0], mask[1], mask[2], mask[3],
        };
        var i: usize = 0;
        while (i + 32 <= payload.len) : (i += 32) {
            const chunk: @Vector(32, u8) = payload[i..][0..32].*;
            payload[i..][0..32].* = chunk ^ mask32;
        }
        while (i + vec_len <= payload.len) : (i += vec_len) {
            const chunk: @Vector(16, u8) = payload[i..][0..16].*;
            payload[i..][0..16].* = chunk ^ mask16;
        }
        while (i < payload.len) : (i += 1) {
            payload[i] ^= mask[i & 3];
        }
        return;
    }
    for (payload, 0..) |*byte, i| byte.* ^= mask[i & 3];
}

pub fn buildWsFrame(opcode: u8, fin: bool, payload: []const u8, mask: ?*const [4]u8, out: []u8) !usize {
    const plen = payload.len;
    const len_field_len: usize = if (plen < 126) 1 else if (plen <= 0xffff) 3 else 9;
    const mask_field_len: usize = if (mask != null) 4 else 0;
    const header_len = 1 + len_field_len + mask_field_len;
    const total = try std.math.add(usize, header_len, plen);
    if (total > out.len) return error.NoSpaceLeft;

    var idx: usize = 0;
    out[idx] = (if (fin) @as(u8, 0x80) else 0) | (opcode & 0x0f);
    idx += 1;
    const mask_bit: u8 = if (mask != null) 0x80 else 0;
    if (plen < 126) {
        out[idx] = mask_bit | @as(u8, @intCast(plen));
        idx += 1;
    } else if (plen <= 0xffff) {
        out[idx] = mask_bit | 126;
        idx += 1;
        out[idx] = @as(u8, @intCast((plen >> 8) & 0xff));
        out[idx + 1] = @as(u8, @intCast(plen & 0xff));
        idx += 2;
    } else {
        out[idx] = mask_bit | 127;
        idx += 1;
        const shifts = [_]u6{ 56, 48, 40, 32, 24, 16, 8, 0 };
        for (shifts, 0..) |shift, b| {
            out[idx + b] = @as(u8, @intCast((@as(u64, @intCast(plen)) >> shift) & 0xff));
        }
        idx += 8;
    }

    if (mask) |m| {
        out[idx] = m[0];
        out[idx + 1] = m[1];
        out[idx + 2] = m[2];
        out[idx + 3] = m[3];
        idx += 4;
        var i: usize = 0;
        while (i < plen) : (i += 1) {
            out[idx + i] = payload[i] ^ m[i & 3];
        }
    } else if (plen != 0) {
        @memcpy(out[idx .. idx + plen], payload);
    }

    return total;
}

pub fn parseUrlParts(url: []const u8) !UrlParts {
    const scheme_sep = std.mem.indexOf(u8, url, "://") orelse return error.Invalid;
    const scheme = url[0..scheme_sep];
    if (scheme.len == 0) return error.Invalid;
    var rest = url[scheme_sep + 3 ..];

    var path: []const u8 = "/";
    if (std.mem.indexOfScalar(u8, rest, '/')) |slash| {
        path = rest[slash..];
        rest = rest[0..slash];
    }
    if (std.mem.indexOfScalar(u8, rest, '@')) |at| {
        rest = rest[at + 1 ..];
    }

    const default_port: u16 = if (std.mem.eql(u8, scheme, "https") or std.mem.eql(u8, scheme, "wss")) 443 else 80;
    var host: []const u8 = rest;
    var port: u16 = default_port;
    if (rest.len != 0 and rest[0] == '[') {
        const close = std.mem.indexOfScalar(u8, rest, ']') orelse return error.Invalid;
        host = rest[1..close];
        const after = rest[close + 1 ..];
        if (after.len != 0 and after[0] == ':') {
            port = std.fmt.parseInt(u16, after[1..], 10) catch return error.Invalid;
        }
    } else if (std.mem.lastIndexOfScalar(u8, rest, ':')) |colon| {
        host = rest[0..colon];
        port = std.fmt.parseInt(u16, rest[colon + 1 ..], 10) catch return error.Invalid;
    }
    if (host.len == 0) return error.Invalid;
    return .{ .scheme = scheme, .host = host, .port = port, .path = path };
}

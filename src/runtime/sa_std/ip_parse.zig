const std = @import("std");
const AFT = @import("../sa_std.zig").AFT;
const NetAddress = @import("../sa_std.zig").NetAddress;
const builtin = @import("../sa_std.zig").builtin;
const constBytes = @import("../sa_std.zig").constBytes;
const netGetAddressList = @import("../sa_std.zig").netGetAddressList;
extern fn if_nametoindex(ifname: [*:0]const u8) c_uint;

pub fn hostBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const host = try constBytes(ptr, len);
    if (host.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, host, 0) != null) return error.InvalidArgument;
    return host;
}

pub fn portFromU32(port: u32) !u16 {
    if (port > std.math.maxInt(u16)) return error.InvalidArgument;
    return @as(u16, @intCast(port));
}

pub fn parseIp4Address(host_ptr: ?[*]const u8, host_len: u64, port: u32) !NetAddress {
    const host = hostBytes(host_ptr, host_len) catch |err| return err;
    const port16 = portFromU32(port) catch |err| return err;
    // FreeBSD: the old net resolveIp bottoms out in if_nametoindex,
    // which zig 0.14 leaves unimplemented for freebsd. Numeric literals
    // parse locally; DNS names go through getAddressList below.
    if (comptime builtin.os.tag == .freebsd) {
        const parts = parseIpv4Ascii(host) orelse return error.InvalidArgument;
        return NetAddress.initIp4(parts, port16);
    }
    const address = try NetAddress.resolveIp(host, port16);
    if (address.storage.family != AFT.INET) return error.InvalidArgument;
    return address;
}

fn parseV6HalfFreebsd(s: []const u8, out: *[16]u8) ?usize {
    if (s.len == 0) return null;
    var n: usize = 0;
    var it = std.mem.splitScalar(u8, s, ':');
    while (it.next()) |part| {
        if (part.len == 0) return null;
        if (std.mem.indexOfScalar(u8, part, '.') != null) {
            if (it.peek() != null) return null; // embedded IPv4 must be last
            const v4 = parseIpv4Ascii(part) orelse return null;
            if (n > 6) return null;
            out[n * 2] = v4[0];
            out[n * 2 + 1] = v4[1];
            out[n * 2 + 2] = v4[2];
            out[n * 2 + 3] = v4[3];
            n += 2;
        } else {
            if (part.len > 4 or n > 7) return null;
            const g = std.fmt.parseInt(u16, part, 16) catch return null;
            out[n * 2] = @as(u8, @intCast(g >> 8));
            out[n * 2 + 1] = @as(u8, @intCast(g & 0xff));
            n += 1;
        }
    }
    return n;
}

pub fn parseIpv6NumericFreebsd(text: []const u8) ?[16]u8 {
    if (text.len == 0 or text.len > 45) return null;
    var left = text;
    var right: []const u8 = "";
    var compressed = false;
    if (std.mem.indexOf(u8, text, "::")) |idx| {
        if (std.mem.indexOf(u8, text[idx + 2 ..], "::") != null) return null;
        left = text[0..idx];
        right = text[idx + 2 ..];
        compressed = true;
    } else if (text[0] == ':' or text[text.len - 1] == ':') {
        return null;
    }
    var addr: [16]u8 = std.mem.zeroes([16]u8);
    var head_n: usize = 0;
    if (left.len > 0 or !compressed) {
        head_n = parseV6HalfFreebsd(left, &addr) orelse return null;
    }
    if (compressed) {
        if (right.len > 0) {
            var tail: [16]u8 = std.mem.zeroes([16]u8);
            const tail_n = parseV6HalfFreebsd(right, &tail) orelse return null;
            const tail_bytes = tail_n * 2;
            if (head_n * 2 + tail_bytes > 16) return null;
            if (head_n == 8) return null; // "::" must compress at least one group
            @memcpy(addr[16 - tail_bytes ..], tail[0..tail_bytes]);
        } else if (head_n == 8) {
            return null; // trailing "::" with nothing compressed
        }
    } else if (head_n != 8) {
        return null;
    }
    return addr;
}

pub fn parseIp6FreebsdParts(host: []const u8) ?struct { addr: [16]u8, scope_id: u32 } {
    var addr_text = host;
    var scope_id: u32 = 0;
    if (std.mem.indexOfScalar(u8, host, '%')) |pct| {
        addr_text = host[0..pct];
        const zone = host[pct + 1 ..];
        if (zone.len == 0) return null;
        scope_id = std.fmt.parseInt(u32, zone, 10) catch blk: {
            if (zone.len >= std.c.IFNAMESIZE) return null;
            var zbuf: [std.c.IFNAMESIZE:0]u8 = undefined;
            @memcpy(zbuf[0..zone.len], zone);
            zbuf[zone.len] = 0;
            const idx = if_nametoindex(@as([*:0]const u8, @ptrCast(&zbuf)));
            if (idx == 0) return null;
            break :blk idx;
        };
    }
    const octets = parseIpv6NumericFreebsd(addr_text) orelse return null;
    return .{ .addr = octets, .scope_id = scope_id };
}

pub fn parseIp6Address(host_ptr: ?[*]const u8, host_len: u64, port: u32) !NetAddress {
    const host = hostBytes(host_ptr, host_len) catch |err| return err;
    const port16 = portFromU32(port) catch |err| return err;
    if (comptime builtin.os.tag == .freebsd) {
        const parsed = parseIp6FreebsdParts(host) orelse return error.InvalidArgument;
        return NetAddress.initIp6(parsed.addr, port16, 0, parsed.scope_id);
    }
    const address = try NetAddress.resolveIp(host, port16);
    if (address.storage.family != AFT.INET6) return error.InvalidArgument;
    return address;
}

pub fn resolveFirstAddressFromParts(host: []const u8, port16: u16) !NetAddress {
    var list = try netGetAddressList(std.heap.page_allocator, host, port16);
    defer list.deinit();
    if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
    return list.addrs[0];
}

pub fn resolveFirstSocketAddress(host_ptr: ?[*]const u8, host_len: u64, port: u32) !NetAddress {
    const host = hostBytes(host_ptr, host_len) catch |err| return err;
    const port16 = portFromU32(port) catch |err| return err;
    return resolveFirstAddressFromParts(host, port16);
}

pub fn parseIpv4Ascii(text: []const u8) ?[4]u8 {
    var parts: [4]u8 = undefined;
    var index: usize = 0;
    var part_index: usize = 0;

    while (part_index < 4) : (part_index += 1) {
        if (index >= text.len) return null;
        var value: u32 = 0;
        var digits: usize = 0;
        while (index < text.len and text[index] != '.') : (index += 1) {
            const byte = text[index];
            if (byte < '0' or byte > '9') return null;
            value = value * 10 + @as(u32, byte - '0');
            if (value > 255) return null;
            digits += 1;
        }
        if (digits == 0) return null;
        parts[part_index] = @as(u8, @intCast(value));
        if (part_index < 3) {
            if (index >= text.len or text[index] != '.') return null;
            index += 1;
        }
    }
    if (index != text.len) return null;
    return parts;
}

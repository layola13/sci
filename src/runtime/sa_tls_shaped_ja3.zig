const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_shaped.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_tls_shaped.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_TRUNCATED = @import("sa_tls_shaped.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_OK = @import("sa_tls_shaped.zig").SA_STD_OK;
const handleFromU64 = @import("sa_tls_shaped.zig").handleFromU64;
const u64ToUsize = @import("sa_tls_shaped.zig").u64ToUsize;

pub fn writeOut(out: ?[*]u8, out_cap: u64, out_len: ?*u64, bytes: []const u8) i32 {
    const len_ptr = out_len orelse return SA_STD_ERR_INVALID_ARGUMENT;
    len_ptr.* = @intCast(bytes.len);
    if (out_cap == 0) return SA_STD_OK;
    const buf = out orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const cap = u64ToUsize(out_cap) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const n = @min(cap, bytes.len);
    @memcpy(buf[0..n], bytes[0..n]);
    if (n != bytes.len) return SA_STD_ERR_TRUNCATED;
    return SA_STD_OK;
}

pub fn isGrease(v: u16) bool {
    return (v & 0x00ff) == (v >> 8) and (v & 0x000f) == 0x000a;
}

pub const HelloInfo = struct {
    legacy_version: u16 = 0,
    ciphers: [128]u16 = undefined,
    cipher_count: usize = 0,
    extensions: [128]u16 = undefined,
    extension_count: usize = 0,
    curves: [64]u16 = undefined,
    curve_count: usize = 0,
    point_formats: [32]u8 = undefined,
    point_format_count: usize = 0,
    supported_versions: [16]u16 = undefined,
    supported_version_count: usize = 0,
    sigalgs: [64]u16 = undefined,
    sigalg_count: usize = 0,
    has_sni: bool = false,
    alpn_first_char: u8 = 0,
    alpn_last_char: u8 = 0,
};

pub const Reader = struct {
    b: []const u8,
    i: usize = 0,
    fn u8v(r: *Reader) ?u8 {
        if (r.i + 1 > r.b.len) return null;
        defer r.i += 1;
        return r.b[r.i];
    }
    fn u16v(r: *Reader) ?u16 {
        if (r.i + 2 > r.b.len) return null;
        defer r.i += 2;
        return std.mem.readInt(u16, r.b[r.i..][0..2], .big);
    }
    fn skip(r: *Reader, n: usize) ?void {
        if (r.i + n > r.b.len) return null;
        r.i += n;
    }
    fn take(r: *Reader, n: usize) ?[]const u8 {
        if (r.i + n > r.b.len) return null;
        defer r.i += n;
        return r.b[r.i..][0..n];
    }
};

pub fn parseHello(msg: []const u8) ?HelloInfo {
    var info = HelloInfo{};
    var r = Reader{ .b = msg };
    const mtype = r.u8v() orelse return null;
    if (mtype != 1) return null; // msg type ClientHello
    _ = r.u8v() orelse return null; // length (3 bytes)
    _ = r.u8v() orelse return null;
    _ = r.u8v() orelse return null;
    info.legacy_version = r.u16v() orelse return null;
    r.skip(32) orelse return null; // random
    const sid_len = r.u8v() orelse return null;
    r.skip(sid_len) orelse return null;
    const cipher_len = r.u16v() orelse return null;
    const cipher_bytes = r.take(cipher_len) orelse return null;
    var ci: usize = 0;
    while (ci + 2 <= cipher_bytes.len) : (ci += 2) {
        const v = std.mem.readInt(u16, cipher_bytes[ci..][0..2], .big);
        if (isGrease(v)) continue;
        if (info.cipher_count < info.ciphers.len) {
            info.ciphers[info.cipher_count] = v;
            info.cipher_count += 1;
        }
    }
    const comp_len = r.u8v() orelse return null;
    r.skip(comp_len) orelse return null;
    if (r.i >= r.b.len) return info; // extensions are optional on the wire
    const ext_total = r.u16v() orelse return null;
    const ext_bytes = r.take(ext_total) orelse return null;
    var er = Reader{ .b = ext_bytes };
    while (er.i + 4 <= ext_bytes.len) {
        const etype = er.u16v() orelse break;
        const elen = er.u16v() orelse break;
        const edata = er.take(elen) orelse break;
        if (!isGrease(etype)) {
            if (info.extension_count < info.extensions.len) {
                info.extensions[info.extension_count] = etype;
                info.extension_count += 1;
            }
        }
        switch (etype) {
            0 => info.has_sni = true,
            10 => {
                var gr = Reader{ .b = edata };
                const glen = gr.u16v() orelse continue;
                const gbytes = gr.take(glen) orelse continue;
                var gi: usize = 0;
                while (gi + 2 <= gbytes.len) : (gi += 2) {
                    const v = std.mem.readInt(u16, gbytes[gi..][0..2], .big);
                    if (isGrease(v)) continue;
                    if (info.curve_count < info.curves.len) {
                        info.curves[info.curve_count] = v;
                        info.curve_count += 1;
                    }
                }
            },
            11 => {
                if (edata.len >= 1) {
                    const n = edata[0];
                    for (edata[1..][0..@min(@as(usize, n), edata.len - 1)]) |f| {
                        if (info.point_format_count < info.point_formats.len) {
                            info.point_formats[info.point_format_count] = f;
                            info.point_format_count += 1;
                        }
                    }
                }
            },
            13 => {
                var sr = Reader{ .b = edata };
                const slen = sr.u16v() orelse continue;
                const sbytes = sr.take(slen) orelse continue;
                var si: usize = 0;
                while (si + 2 <= sbytes.len) : (si += 2) {
                    const v = std.mem.readInt(u16, sbytes[si..][0..2], .big);
                    if (info.sigalg_count < info.sigalgs.len) {
                        info.sigalgs[info.sigalg_count] = v;
                        info.sigalg_count += 1;
                    }
                }
            },
            16 => {
                var ar = Reader{ .b = edata };
                const alen = ar.u16v() orelse continue;
                const abytes = ar.take(alen) orelse continue;
                var ai: usize = 0;
                var first = true;
                while (ai < abytes.len) {
                    const plen = abytes[ai];
                    ai += 1;
                    if (ai + plen > abytes.len) break;
                    const proto = abytes[ai..][0..plen];
                    if (proto.len > 0) {
                        if (first) {
                            info.alpn_first_char = proto[0];
                            first = false;
                        }
                        info.alpn_last_char = proto[proto.len - 1];
                    }
                    ai += plen;
                }
            },
            43 => {
                if (edata.len >= 1) {
                    const n = edata[0];
                    const vbytes = edata[1..][0..@min(@as(usize, n), edata.len - 1)];
                    var vi: usize = 0;
                    while (vi + 2 <= vbytes.len) : (vi += 2) {
                        const v = std.mem.readInt(u16, vbytes[vi..][0..2], .big);
                        if (isGrease(v)) continue;
                        if (info.supported_version_count < info.supported_versions.len) {
                            info.supported_versions[info.supported_version_count] = v;
                            info.supported_version_count += 1;
                        }
                    }
                }
            },
            else => {},
        }
    }
    return info;
}

pub fn appendDec(list: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, v: u32) !void {
    var tmp: [16]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{v});
    try list.appendSlice(alloc, s);
}

pub fn joinDecU16(list: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, vals: []const u16, sep: u8) !void {
    for (vals, 0..) |v, i| {
        if (i > 0) try list.append(alloc, sep);
        try appendDec(list, alloc, v);
    }
}

pub fn buildJa3String(alloc: std.mem.Allocator, info: *const HelloInfo) ![]u8 {
    var list = std.ArrayListUnmanaged(u8).empty;
    errdefer list.deinit(alloc);
    try appendDec(&list, alloc, info.legacy_version);
    try list.append(alloc, ',');
    try joinDecU16(&list, alloc, info.ciphers[0..info.cipher_count], '-');
    try list.append(alloc, ',');
    try joinDecU16(&list, alloc, info.extensions[0..info.extension_count], '-');
    try list.append(alloc, ',');
    try joinDecU16(&list, alloc, info.curves[0..info.curve_count], '-');
    try list.append(alloc, ',');
    for (info.point_formats[0..info.point_format_count], 0..) |f, i| {
        if (i > 0) try list.append(alloc, '-');
        try appendDec(&list, alloc, f);
    }
    return list.toOwnedSlice(alloc);
}

pub fn hex4(buf: *[4]u8, v: u16) []const u8 {
    return std.fmt.bufPrint(buf, "{x:0>4}", .{v}) catch unreachable;
}

pub fn buildJa4(alloc: std.mem.Allocator, info: *const HelloInfo) ![]u8 {
    // Version: highest supported_versions entry wins, else legacy.
    var ver: u16 = info.legacy_version;
    for (info.supported_versions[0..info.supported_version_count]) |v| {
        if (v > ver) ver = v;
    }
    const ver_code: []const u8 = switch (ver) {
        0x0304 => "13",
        0x0303 => "12",
        0x0302 => "11",
        0x0301 => "10",
        else => "00",
    };
    // Cipher hash: sha256 over the sorted cipher ids, lowercase 4-hex,
    // comma-joined; first 12 hex chars of the digest.
    var sorted_ciphers: [128]u16 = undefined;
    @memcpy(sorted_ciphers[0..info.cipher_count], info.ciphers[0..info.cipher_count]);
    const cs = sorted_ciphers[0..info.cipher_count];
    std.mem.sort(u16, cs, {}, std.sort.asc(u16));
    var cipher_input = std.ArrayListUnmanaged(u8).empty;
    defer cipher_input.deinit(alloc);
    for (cs, 0..) |v, i| {
        if (i > 0) try cipher_input.append(alloc, ',');
        var b: [4]u8 = undefined;
        try cipher_input.appendSlice(alloc, hex4(&b, v));
    }
    var cipher_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(cipher_input.items, &cipher_hash, .{});
    const cipher_hex = std.fmt.bytesToHex(cipher_hash, .lower);
    const cipher_part: []const u8 = if (info.cipher_count == 0) "000000000000" else cipher_hex[0..12];

    // Extension hash: sorted extension ids excluding SNI (0) and ALPN
    // (16), then "_" + signature algorithms in wire order.
    var exts: [128]u16 = undefined;
    var ext_n: usize = 0;
    for (info.extensions[0..info.extension_count]) |e| {
        if (e == 0 or e == 16) continue;
        exts[ext_n] = e;
        ext_n += 1;
    }
    const es = exts[0..ext_n];
    std.mem.sort(u16, es, {}, std.sort.asc(u16));
    var ext_input = std.ArrayListUnmanaged(u8).empty;
    defer ext_input.deinit(alloc);
    for (es, 0..) |v, i| {
        if (i > 0) try ext_input.append(alloc, ',');
        var b: [4]u8 = undefined;
        try ext_input.appendSlice(alloc, hex4(&b, v));
    }
    if (info.sigalg_count > 0) {
        try ext_input.append(alloc, '_');
        for (info.sigalgs[0..info.sigalg_count], 0..) |v, i| {
            if (i > 0) try ext_input.append(alloc, ',');
            var b: [4]u8 = undefined;
            try ext_input.appendSlice(alloc, hex4(&b, v));
        }
    }
    var ext_hash: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(ext_input.items, &ext_hash, .{});
    const ext_hex = std.fmt.bytesToHex(ext_hash, .lower);
    const ext_part: []const u8 = if (ext_n == 0 and info.sigalg_count == 0) "000000000000" else ext_hex[0..12];

    const cc: u32 = @intCast(@min(info.cipher_count, 99));
    const ec: u32 = @intCast(@min(info.extension_count, 99));
    const a: u8 = if (info.alpn_first_char != 0) info.alpn_first_char else '0';
    const l: u8 = if (info.alpn_last_char != 0) info.alpn_last_char else '0';
    return std.fmt.allocPrint(alloc, "t{s}{s}{d:0>2}{d:0>2}{c}{c}_{s}_{s}", .{
        ver_code,
        if (info.has_sni) "d" else "i",
        cc,
        ec,
        a,
        l,
        cipher_part,
        ext_part,
    });
}

pub fn helloInfoFor(handle: u64) ?HelloInfo {
    const h = handleFromU64(handle) orelse return null;
    if (h.hello_len == 0) return null;
    return parseHello(h.hello_buf[0..h.hello_len]);
}

pub export fn sa_std_tls_shaped_hello_ja3_string(handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const info = helloInfoFor(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = buildJa3String(std.heap.page_allocator, &info) catch return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(s);
    return writeOut(out, out_cap, out_len, s);
}

pub export fn sa_std_tls_shaped_hello_ja3(handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const info = helloInfoFor(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = buildJa3String(std.heap.page_allocator, &info) catch return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(s);
    var digest: [16]u8 = undefined;
    std.crypto.hash.Md5.hash(s, &digest, .{});
    const hex = std.fmt.bytesToHex(digest, .lower);
    return writeOut(out, out_cap, out_len, &hex);
}

pub export fn sa_std_tls_shaped_hello_ja4(handle: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const info = helloInfoFor(handle) orelse return SA_STD_ERR_INVALID_ARGUMENT;
    const s = buildJa4(std.heap.page_allocator, &info) catch return SA_STD_ERR_NO_MEMORY;
    defer std.heap.page_allocator.free(s);
    return writeOut(out, out_cap, out_len, s);
}

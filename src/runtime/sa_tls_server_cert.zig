const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_server.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_tls_server.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("sa_tls_server.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("sa_tls_server.zig").SA_STD_OK;
const Ssl = @import("sa_tls_server.zig").Ssl;
const SslApi = @import("sa_tls_server.zig").SslApi;
const X509 = @import("sa_tls_server.zig").X509;
const X509Name = @import("sa_tls_server.zig").X509Name;
const loadSslApi = @import("sa_tls_server.zig").loadSslApi;
const ptrFromU64 = @import("sa_tls_server.zig").ptrFromU64;
const registerString = @import("sa_tls_server.zig").registerString;

pub export fn sa_std_tls_server_session_verify_result(ssl_handle: u64, out_code: ?*u32) i32 {
    const slot = out_code orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const rc = api.get_verify_result(ptrFromU64(Ssl, ssl_handle));
    slot.* = @intCast(@as(u64, @bitCast(@as(i64, rc))));
    return SA_STD_OK;
}

pub export fn sa_std_tls_server_negotiated_json(ssl_handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const ssl = ptrFromU64(Ssl, ssl_handle);
    const version = std.mem.span(api.get_version(ssl));
    const cipher_ptr = api.get_current_cipher(ssl);
    const cipher = if (cipher_ptr) |c| std.mem.span(api.cipher_get_name(c)) else "NONE";
    var alpn_data: ?[*]const u8 = null;
    var alpn_len: c_uint = 0;
    api.get_alpn_selected(ssl, &alpn_data, &alpn_len);
    const alpn: []const u8 = if (alpn_data) |d| d[0..alpn_len] else "";
    var buffer: [512]u8 = undefined;
    const json = std.fmt.bufPrint(&buffer, "{{\"version\":\"{s}\",\"cipher\":\"{s}\",\"alpn\":\"{s}\"}}", .{ version, cipher, alpn }) catch return SA_STD_ERR_NO_MEMORY;
    const owned = std.heap.page_allocator.dupe(u8, json) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(owned, slot);
}

pub export fn sa_std_tls_server_peer_cert_chain_json(ssl_handle: u64, out_handle: ?*u64) i32 {
    const slot = out_handle orelse return SA_STD_ERR_INVALID_ARGUMENT;
    slot.* = 0;
    if (ssl_handle == 0) return SA_STD_ERR_INVALID_ARGUMENT;
    const api = loadSslApi() orelse return SA_STD_ERR_UNSUPPORTED;
    const json = buildPeerCertChainJson(api, ptrFromU64(Ssl, ssl_handle)) catch return SA_STD_ERR_NO_MEMORY;
    return registerString(json, slot);
}

pub fn appendJsonEscaped(list: *std.ArrayList(u8), alloc: std.mem.Allocator, s: []const u8) !void {
    for (s) |ch| {
        switch (ch) {
            '"' => try list.appendSlice(alloc, "\\\""),
            '\\' => try list.appendSlice(alloc, "\\\\"),
            '\n' => try list.appendSlice(alloc, "\\n"),
            '\r' => try list.appendSlice(alloc, "\\r"),
            '\t' => try list.appendSlice(alloc, "\\t"),
            0x00...0x08, 0x0b, 0x0c, 0x0e...0x1f => {
                var tmp: [8]u8 = undefined;
                const t = try std.fmt.bufPrint(&tmp, "\\u{x:0>4}", .{ch});
                try list.appendSlice(alloc, t);
            },
            else => try list.append(alloc, ch),
        }
    }
}

pub fn appendHexUpper(list: *std.ArrayList(u8), alloc: std.mem.Allocator, bytes: []const u8, colon: bool) !void {
    const digits = "0123456789ABCDEF";
    for (bytes, 0..) |b, i| {
        if (colon and i != 0) try list.append(alloc, ':');
        try list.append(alloc, digits[b >> 4]);
        try list.append(alloc, digits[b & 0x0f]);
    }
}

pub fn serialHex(alloc: std.mem.Allocator, der_bytes: []const u8) !?[]u8 {
    const der = std.crypto.Certificate.der;
    const outer = der.Element.parse(der_bytes, 0) catch return null;
    const tbs = der.Element.parse(der_bytes, outer.slice.start) catch return null;
    var idx = tbs.slice.start;
    var el = der.Element.parse(der_bytes, idx) catch return null;
    if (el.identifier.class == .context_specific and @intFromEnum(el.identifier.tag) == 0) {
        idx = el.slice.end;
        el = der.Element.parse(der_bytes, idx) catch return null;
    }
    if (el.identifier.class != .universal or @intFromEnum(el.identifier.tag) != 2) return null;
    const bytes = der_bytes[el.slice.start..el.slice.end];
    var out = try alloc.alloc(u8, bytes.len * 2);
    errdefer alloc.free(out);
    const digits = "0123456789ABCDEF";
    for (bytes, 0..) |b, i| {
        out[i * 2] = digits[b >> 4];
        out[i * 2 + 1] = digits[b & 0x0f];
    }
    return out;
}

pub fn collectSans(parsed: *const std.crypto.Certificate.Parsed, dns: *std.ArrayList([]const u8), ips: *std.ArrayList([]const u8), alloc: std.mem.Allocator) !void {
    const der = std.crypto.Certificate.der;
    const san = parsed.subjectAltName();
    if (san.len == 0) return;
    const seq = der.Element.parse(san, 0) catch return;
    var idx = seq.slice.start;
    while (idx < seq.slice.end) {
        const el = der.Element.parse(san, idx) catch break;
        const content = san[el.slice.start..el.slice.end];
        if (el.identifier.class == .context_specific and @intFromEnum(el.identifier.tag) == 2) {
            try dns.append(alloc, content);
        } else if (el.identifier.class == .context_specific and @intFromEnum(el.identifier.tag) == 7) {
            try ips.append(alloc, content);
        }
        idx = el.slice.end;
    }
}

pub const X509_NAME_DISPLAY_FLAGS: c_ulong = 0x82031f;

pub fn appendX509DisplayName(api: *SslApi, out: *std.ArrayList(u8), alloc: std.mem.Allocator, name: ?*const X509Name) !void {
    const nm = name orelse return;
    const meth = api.bio_s_mem() orelse return;
    const bio = api.bio_new(meth) orelse return;
    defer _ = api.bio_free(bio);
    if (api.x509_name_print_ex(bio, nm, 0, X509_NAME_DISPLAY_FLAGS) <= 0) return;
    var chunk: [512]u8 = undefined;
    while (true) {
        const n = api.bio_read(bio, &chunk, @intCast(chunk.len));
        if (n <= 0) break;
        try appendJsonEscaped(out, alloc, chunk[0..@intCast(n)]);
    }
}

pub fn buildPeerCertChainJson(api: *SslApi, ssl: *Ssl) ![]u8 {
    const alloc = std.heap.page_allocator;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(alloc);
    try out.appendSlice(alloc, "{\"certificates\":[");
    var first = true;
    // Chain source: OpenSSL does not expose a server-side received chain
    // through SSL_get_peer_cert_chain (it stays empty for accepted
    // sessions on both TLS 1.2 and 1.3); the verified chain is the
    // populated view there, and the leaf certificate is the last resort.
    // All three are OpenSSL's own views of the same peer certificates --
    // whichever is populated is reported verbatim.
    var chain = api.get_peer_cert_chain(ssl);
    if (chain == null or api.sk_num(chain) == 0) {
        if (api.get_verified_chain(ssl)) |vc| {
            if (api.sk_num(vc) > 0) chain = vc;
        }
    }
    var leaf: ?*X509 = null;
    defer if (leaf) |x| api.x509_free(x);
    if (chain == null or api.sk_num(chain) == 0) {
        leaf = api.get1_peer_certificate(ssl);
    }
    {
        const n: c_int = if (chain) |c| api.sk_num(c) else if (leaf != null) 1 else 0;
        var i: c_int = 0;
        while (i < n) : (i += 1) {
            const x: *X509 = if (chain) |c| @ptrCast(@alignCast(api.sk_value(c, i) orelse continue)) else leaf.?;
            const dlen = api.i2d_x509(x, null);
            if (dlen <= 0) continue;
            const derbuf = try alloc.alloc(u8, @intCast(dlen));
            defer alloc.free(derbuf);
            var p: ?[*]u8 = derbuf.ptr;
            if (api.i2d_x509(x, &p) != dlen) continue;

            if (!first) try out.append(alloc, ',');
            first = false;
            try out.append(alloc, '{');
            try out.appendSlice(alloc, "\"subject\":\"");
            try appendX509DisplayName(api, &out, alloc, api.x509_get_subject_name(x));
            try out.appendSlice(alloc, "\",\"issuer\":\"");
            try appendX509DisplayName(api, &out, alloc, api.x509_get_issuer_name(x));
            try out.appendSlice(alloc, "\",\"sha256_fingerprint\":\"");
            var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(derbuf, &digest, .{});
            try appendHexUpper(&out, alloc, &digest, true);
            try out.append(alloc, '"');

            const cert = std.crypto.Certificate{ .buffer = derbuf, .index = 0 };
            if (cert.parse()) |parsed| {
                var dns: std.ArrayList([]const u8) = .empty;
                defer dns.deinit(alloc);
                var ips: std.ArrayList([]const u8) = .empty;
                defer ips.deinit(alloc);
                try collectSans(&parsed, &dns, &ips, alloc);
                try out.appendSlice(alloc, ",\"common_name\":\"");
                try appendJsonEscaped(&out, alloc, parsed.commonName());
                try out.appendSlice(alloc, "\",\"san_dns\":[");
                for (dns.items, 0..) |name, j| {
                    if (j != 0) try out.append(alloc, ',');
                    try out.append(alloc, '"');
                    try appendJsonEscaped(&out, alloc, name);
                    try out.append(alloc, '"');
                }
                try out.appendSlice(alloc, "],\"san_ip\":[");
                for (ips.items, 0..) |ip, j| {
                    if (j != 0) try out.append(alloc, ',');
                    try out.append(alloc, '"');
                    if (ip.len == 4) {
                        var tmp: [24]u8 = undefined;
                        const t = try std.fmt.bufPrint(&tmp, "{d}.{d}.{d}.{d}", .{ ip[0], ip[1], ip[2], ip[3] });
                        try out.appendSlice(alloc, t);
                    } else {
                        try appendHexUpper(&out, alloc, ip, true);
                    }
                    try out.append(alloc, '"');
                }
                var num_buf: [64]u8 = undefined;
                try out.appendSlice(alloc, "],\"not_before\":");
                try out.appendSlice(alloc, try std.fmt.bufPrint(&num_buf, "{d}", .{parsed.validity.not_before}));
                try out.appendSlice(alloc, ",\"not_after\":");
                try out.appendSlice(alloc, try std.fmt.bufPrint(&num_buf, "{d}", .{parsed.validity.not_after}));
                try out.appendSlice(alloc, ",\"serial_hex\":\"");
                if (try serialHex(alloc, derbuf)) |sh| {
                    defer alloc.free(sh);
                    try out.appendSlice(alloc, sh);
                }
                try out.append(alloc, '"');
            } else |_| {
                try out.appendSlice(alloc, ",\"fields_parsed\":false");
            }
            try out.append(alloc, '}');
        }
    }
    try out.appendSlice(alloc, "]}");
    return out.toOwnedSlice(alloc);
}

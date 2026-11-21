const std = @import("std");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_tls_shaped.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_NO_MEMORY = @import("sa_tls_shaped.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("sa_tls_shaped.zig").SA_STD_ERR_UNSUPPORTED;
const sa_std_tls_shaped_session_blob = @import("sa_tls_shaped.zig").sa_std_tls_shaped_session_blob;

pub const Profile = struct {
    preset: ?[]const u8 = null,
    alpn: ?[]const []const u8 = null,
    ciphersuites: ?[]const u8 = null,
    ciphers: ?[]const u8 = null,
    groups: ?[]const u8 = null,
    sigalgs: ?[]const u8 = null,
    min_version: ?[]const u8 = null,
    max_version: ?[]const u8 = null,
    ca_file: ?[]const u8 = null,
    ca_pem: ?[]const u8 = null,
    sni: ?[]const u8 = null,
    verify_host: ?[]const u8 = null,
    cert_file: ?[]const u8 = null,
    key_file: ?[]const u8 = null,
    insecure_skip_verify: bool = false,
    session: ?[]const u8 = null,
    grease: bool = false,
};

pub const Effective = struct {
    alpn: []const []const u8 = &.{},
    ciphersuites: ?[]const u8 = null,
    ciphers: ?[]const u8 = null,
    groups: ?[]const u8 = null,
    sigalgs: ?[]const u8 = null,
    min_version: ?[]const u8 = null,
    max_version: ?[]const u8 = null,
    ca_file: ?[]const u8 = null,
    ca_pem: ?[]const u8 = null,
    sni: ?[]const u8 = null,
    verify_host: ?[]const u8 = null,
    cert_file: ?[]const u8 = null,
    key_file: ?[]const u8 = null,
    insecure_skip_verify: bool = false,
    session_der: ?[]const u8 = null,
};

pub const TLS13_SUITES = "TLS_AES_128_GCM_SHA256:TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256";

pub const BROWSER_SIGALGS = "ecdsa_secp256r1_sha256:rsa_pss_rsae_sha256:rsa_pkcs1_sha256:ecdsa_secp384r1_sha384:rsa_pss_rsae_sha384:rsa_pkcs1_sha384:rsa_pss_rsae_sha512:rsa_pkcs1_sha512";

pub fn presetEffective(name: []const u8) ?Effective {
    if (std.mem.eql(u8, name, "chrome")) {
        return .{
            .alpn = &.{ "h2", "http/1.1" },
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-SHA:ECDHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA:AES256-SHA",
            .groups = "X25519:P-256:P-384",
            .sigalgs = BROWSER_SIGALGS,
        };
    }
    if (std.mem.eql(u8, name, "firefox")) {
        return .{
            .alpn = &.{ "h2", "http/1.1" },
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES128-SHA",
            .groups = "X25519:P-256:P-384:P-521:ffdhe2048:ffdhe3072",
            .sigalgs = BROWSER_SIGALGS,
        };
    }
    if (std.mem.eql(u8, name, "safari")) {
        return .{
            .alpn = &.{ "h2", "http/1.1" },
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES256-SHA:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA:ECDHE-ECDSA-AES128-SHA:AES256-GCM-SHA384:AES128-GCM-SHA256:AES256-SHA:AES128-SHA",
            .groups = "X25519:P-256:P-384:P-521",
            .sigalgs = BROWSER_SIGALGS,
        };
    }
    if (std.mem.eql(u8, name, "go")) {
        return .{
            .alpn = &.{},
            .ciphersuites = TLS13_SUITES,
            .ciphers = "ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA",
            .groups = "X25519:P-256:P-384:P-521",
            .sigalgs = "ecdsa_secp256r1_sha256:ecdsa_secp384r1_sha384:ecdsa_secp521r1_sha512:rsa_pss_rsae_sha256:rsa_pss_rsae_sha384:rsa_pss_rsae_sha512:rsa_pkcs1_sha256:rsa_pkcs1_sha384:rsa_pkcs1_sha512",
        };
    }
    if (std.mem.eql(u8, name, "default")) return .{};
    return null;
}

pub fn versionConst(name: []const u8) ?c_long {
    if (std.mem.eql(u8, name, "1.0")) return 0x0301;
    if (std.mem.eql(u8, name, "1.1")) return 0x0302;
    if (std.mem.eql(u8, name, "1.2")) return 0x0303;
    if (std.mem.eql(u8, name, "1.3")) return 0x0304;
    return null;
}

pub const ResolveResult = union(enum) { ok: Effective, err: i32 };

pub fn effectiveFromProfile(p: *const Profile) ResolveResult {
    if (p.grease) return .{ .err = SA_STD_ERR_UNSUPPORTED };
    var eff: Effective = .{};
    if (p.preset) |name| {
        eff = presetEffective(name) orelse return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
    }
    if (p.alpn) |v| eff.alpn = v;
    if (p.ciphersuites) |v| eff.ciphersuites = v;
    if (p.ciphers) |v| eff.ciphers = v;
    if (p.groups) |v| eff.groups = v;
    if (p.sigalgs) |v| eff.sigalgs = v;
    if (p.min_version) |v| {
        if (versionConst(v) == null) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.min_version = v;
    }
    if (p.max_version) |v| {
        if (versionConst(v) == null) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.max_version = v;
    }
    if (p.ca_file) |v| eff.ca_file = v;
    if (p.ca_pem) |v| eff.ca_pem = v;
    if (eff.ca_file != null and eff.ca_pem != null) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
    if (p.sni) |v| {
        if (v.len == 0) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.sni = v;
    }
    if (p.verify_host) |v| {
        if (v.len == 0) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.verify_host = v;
    }
    if (p.cert_file) |v| eff.cert_file = v;
    if (p.key_file) |v| eff.key_file = v;
    if ((eff.cert_file == null) != (eff.key_file == null)) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
    eff.insecure_skip_verify = p.insecure_skip_verify;
    if (p.session) |v| {
        // The blob travels as base64 DER (from sa_std_tls_shaped_session_blob);
        // decode once here so a malformed blob fails before any dial.
        const dec = std.base64.standard.decoderWithIgnore(" \t\r\n");
        const buf = std.heap.page_allocator.alloc(u8, v.len) catch return .{ .err = SA_STD_ERR_NO_MEMORY };
        defer std.heap.page_allocator.free(buf);
        const n = dec.decode(buf, v) catch return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        if (n == 0) return .{ .err = SA_STD_ERR_INVALID_ARGUMENT };
        eff.session_der = std.heap.page_allocator.dupe(u8, buf[0..n]) catch return .{ .err = SA_STD_ERR_NO_MEMORY };
    }
    return .{ .ok = eff };
}

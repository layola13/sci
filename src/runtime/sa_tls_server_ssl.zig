const std = @import("std");
const sa_std = @import("sa_tls_server.zig");
const AlpnSelectCb = @import("sa_tls_server.zig").AlpnSelectCb;
const Bio = @import("sa_tls_server.zig").Bio;
const Ssl = @import("sa_tls_server.zig").Ssl;
const SslAccept = @import("sa_tls_server.zig").SslAccept;
const SslApi = @import("sa_tls_server.zig").SslApi;
const SslCtx = @import("sa_tls_server.zig").SslCtx;
const SslCtxFree = @import("sa_tls_server.zig").SslCtxFree;
const SslCtxNew = @import("sa_tls_server.zig").SslCtxNew;
const SslCtxUseCertFile = @import("sa_tls_server.zig").SslCtxUseCertFile;
const SslCtxUseKeyFile = @import("sa_tls_server.zig").SslCtxUseKeyFile;
const SslFree = @import("sa_tls_server.zig").SslFree;
const SslMethodNew = @import("sa_tls_server.zig").SslMethodNew;
const SslNew = @import("sa_tls_server.zig").SslNew;
const SslRead = @import("sa_tls_server.zig").SslRead;
const SslSetFd = @import("sa_tls_server.zig").SslSetFd;
const SslShutdown = @import("sa_tls_server.zig").SslShutdown;
const SslStack = @import("sa_tls_server.zig").SslStack;
const SslWrite = @import("sa_tls_server.zig").SslWrite;
const X509 = @import("sa_tls_server.zig").X509;
const X509Name = @import("sa_tls_server.zig").X509Name;
const builtin = @import("sa_tls_server.zig").builtin;
const sio = @import("sa_tls_server.zig").sio;

pub fn loadSslApiNative() ?*SslApi {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    sa_std.ssl_api_mutex.lockUncancelable(sio.io());
    defer sa_std.ssl_api_mutex.unlock(sio.io());
    if (sa_std.ssl_api) |*api| return api;

    const ssl_candidates = [_][]const u8{
        "libssl.so.3",
        "libssl.so",
        "/lib/x86_64-linux-gnu/libssl.so.3",
        "/usr/lib/x86_64-linux-gnu/libssl.so.3",
    };
    var lib: ?std.DynLib = null;
    for (ssl_candidates) |c| {
        if (std.DynLib.open(c)) |l| {
            lib = l;
            break;
        } else |_| {}
    }
    var l = lib orelse return null;

    const method_new = l.lookup(SslMethodNew, "TLS_server_method") orelse {
        l.close();
        return null;
    };
    const ctx_new = l.lookup(SslCtxNew, "SSL_CTX_new") orelse {
        l.close();
        return null;
    };
    const ctx_free = l.lookup(SslCtxFree, "SSL_CTX_free") orelse {
        l.close();
        return null;
    };
    const use_cert = l.lookup(SslCtxUseCertFile, "SSL_CTX_use_certificate_file") orelse {
        l.close();
        return null;
    };
    const use_key = l.lookup(SslCtxUseKeyFile, "SSL_CTX_use_PrivateKey_file") orelse {
        l.close();
        return null;
    };
    const new = l.lookup(SslNew, "SSL_new") orelse {
        l.close();
        return null;
    };
    const free = l.lookup(SslFree, "SSL_free") orelse {
        l.close();
        return null;
    };
    const set_fd = l.lookup(SslSetFd, "SSL_set_fd") orelse {
        l.close();
        return null;
    };
    const accept = l.lookup(SslAccept, "SSL_accept") orelse {
        l.close();
        return null;
    };
    const read = l.lookup(SslRead, "SSL_read") orelse {
        l.close();
        return null;
    };
    const write = l.lookup(SslWrite, "SSL_write") orelse {
        l.close();
        return null;
    };
    const shutdown = l.lookup(SslShutdown, "SSL_shutdown") orelse {
        l.close();
        return null;
    };
    const ctx_set_verify = l.lookup(*const fn (?*SslCtx, c_int, ?*const anyopaque) callconv(.c) void, "SSL_CTX_set_verify") orelse {
        l.close();
        return null;
    };
    const ctx_load_verify_locations = l.lookup(*const fn (?*SslCtx, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int, "SSL_CTX_load_verify_locations") orelse {
        l.close();
        return null;
    };
    const ctx_set_default_verify_paths = l.lookup(*const fn (?*SslCtx) callconv(.c) c_int, "SSL_CTX_set_default_verify_paths") orelse {
        l.close();
        return null;
    };
    const ctx_ctrl = l.lookup(*const fn (?*SslCtx, c_int, c_long, ?*anyopaque) callconv(.c) c_long, "SSL_CTX_ctrl") orelse {
        l.close();
        return null;
    };
    const use_cert_asn1 = l.lookup(*const fn (?*SslCtx, c_int, [*]const u8) callconv(.c) c_int, "SSL_CTX_use_certificate_ASN1") orelse {
        l.close();
        return null;
    };
    const use_key_asn1 = l.lookup(*const fn (c_int, ?*SslCtx, [*]const u8, c_long) callconv(.c) c_int, "SSL_CTX_use_PrivateKey_ASN1") orelse {
        l.close();
        return null;
    };
    const check_private_key = l.lookup(*const fn (?*const SslCtx) callconv(.c) c_int, "SSL_CTX_check_private_key") orelse {
        l.close();
        return null;
    };
    const d2i_x509 = l.lookup(*const fn (?*?*X509, *?[*]const u8, c_long) callconv(.c) ?*X509, "d2i_X509") orelse {
        l.close();
        return null;
    };
    const x509_free = l.lookup(*const fn (?*X509) callconv(.c) void, "X509_free") orelse {
        l.close();
        return null;
    };
    const ctx_set_alpn_select_cb = l.lookup(*const fn (?*SslCtx, AlpnSelectCb, ?*anyopaque) callconv(.c) void, "SSL_CTX_set_alpn_select_cb") orelse {
        l.close();
        return null;
    };
    const get_alpn_selected = l.lookup(*const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void, "SSL_get0_alpn_selected") orelse {
        l.close();
        return null;
    };
    const get_version = l.lookup(*const fn (?*const Ssl) callconv(.c) [*:0]const u8, "SSL_get_version") orelse {
        l.close();
        return null;
    };
    const get_current_cipher = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*const anyopaque, "SSL_get_current_cipher") orelse {
        l.close();
        return null;
    };
    const cipher_get_name = l.lookup(*const fn (?*const anyopaque) callconv(.c) [*:0]const u8, "SSL_CIPHER_get_name") orelse {
        l.close();
        return null;
    };
    const get_verify_result = l.lookup(*const fn (?*const Ssl) callconv(.c) c_long, "SSL_get_verify_result") orelse {
        l.close();
        return null;
    };
    const get_peer_cert_chain = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslStack, "SSL_get_peer_cert_chain") orelse {
        l.close();
        return null;
    };
    const get_verified_chain = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslStack, "SSL_get0_verified_chain") orelse {
        l.close();
        return null;
    };
    const get1_peer_certificate = l.lookup(*const fn (?*Ssl) callconv(.c) ?*X509, "SSL_get1_peer_certificate") orelse {
        l.close();
        return null;
    };
    const sk_num = l.lookup(*const fn (?*const SslStack) callconv(.c) c_int, "OPENSSL_sk_num") orelse {
        l.close();
        return null;
    };
    const sk_value = l.lookup(*const fn (?*const SslStack, c_int) callconv(.c) ?*anyopaque, "OPENSSL_sk_value") orelse {
        l.close();
        return null;
    };
    const i2d_x509 = l.lookup(*const fn (?*X509, ?*?[*]u8) callconv(.c) c_int, "i2d_X509") orelse {
        l.close();
        return null;
    };
    const x509_get_subject_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_subject_name") orelse {
        l.close();
        return null;
    };
    const x509_get_issuer_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_issuer_name") orelse {
        l.close();
        return null;
    };
    const x509_name_print_ex = l.lookup(*const fn (?*Bio, ?*const X509Name, c_int, c_ulong) callconv(.c) c_int, "X509_NAME_print_ex") orelse {
        l.close();
        return null;
    };
    const bio_s_mem = l.lookup(*const fn () callconv(.c) ?*anyopaque, "BIO_s_mem") orelse {
        l.close();
        return null;
    };
    const bio_new = l.lookup(*const fn (?*anyopaque) callconv(.c) ?*Bio, "BIO_new") orelse {
        l.close();
        return null;
    };
    const bio_read = l.lookup(*const fn (?*Bio, [*]u8, c_int) callconv(.c) c_int, "BIO_read") orelse {
        l.close();
        return null;
    };
    const bio_free = l.lookup(*const fn (?*Bio) callconv(.c) c_int, "BIO_free") orelse {
        l.close();
        return null;
    };

    sa_std.ssl_api = .{
        .lib = l,
        .ctx_new = ctx_new,
        .ctx_free = ctx_free,
        .use_cert_file = use_cert,
        .use_key_file = use_key,
        .new = new,
        .free = free,
        .set_fd = set_fd,
        .accept = accept,
        .read = read,
        .write = write,
        .shutdown = shutdown,
        .method_new = method_new,
        .ctx_set_verify = ctx_set_verify,
        .ctx_load_verify_locations = ctx_load_verify_locations,
        .ctx_set_default_verify_paths = ctx_set_default_verify_paths,
        .ctx_ctrl = ctx_ctrl,
        .use_cert_asn1 = use_cert_asn1,
        .use_key_asn1 = use_key_asn1,
        .check_private_key = check_private_key,
        .d2i_x509 = d2i_x509,
        .x509_free = x509_free,
        .ctx_set_alpn_select_cb = ctx_set_alpn_select_cb,
        .get_alpn_selected = get_alpn_selected,
        .get_version = get_version,
        .get_current_cipher = get_current_cipher,
        .cipher_get_name = cipher_get_name,
        .get_verify_result = get_verify_result,
        .get_peer_cert_chain = get_peer_cert_chain,
        .get_verified_chain = get_verified_chain,
        .get1_peer_certificate = get1_peer_certificate,
        .sk_num = sk_num,
        .sk_value = sk_value,
        .i2d_x509 = i2d_x509,
        .x509_get_subject_name = x509_get_subject_name,
        .x509_get_issuer_name = x509_get_issuer_name,
        .x509_name_print_ex = x509_name_print_ex,
        .bio_s_mem = bio_s_mem,
        .bio_new = bio_new,
        .bio_read = bio_read,
        .bio_free = bio_free,
    };
    return &sa_std.ssl_api.?;
}

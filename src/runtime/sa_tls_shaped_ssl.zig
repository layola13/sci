const std = @import("std");
const sa_std = @import("sa_tls_shaped.zig");
const Bio = @import("sa_tls_shaped.zig").Bio;
const MsgCallback = @import("sa_tls_shaped.zig").MsgCallback;
const Ssl = @import("sa_tls_shaped.zig").Ssl;
const SslApi = @import("sa_tls_shaped.zig").SslApi;
const SslCipher = @import("sa_tls_shaped.zig").SslCipher;
const SslCtx = @import("sa_tls_shaped.zig").SslCtx;
const SslMethod = @import("sa_tls_shaped.zig").SslMethod;
const SslSession = @import("sa_tls_shaped.zig").SslSession;
const SslStack = @import("sa_tls_shaped.zig").SslStack;
const X509 = @import("sa_tls_shaped.zig").X509;
const X509Name = @import("sa_tls_shaped.zig").X509Name;
const X509Store = @import("sa_tls_shaped.zig").X509Store;
const builtin = @import("sa_tls_shaped.zig").builtin;
const sio = @import("sa_tls_shaped.zig").sio;

pub fn loadSslApiNative() ?*SslApi {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    sa_std.ssl_api_mutex.lockUncancelable(sio.io());
    defer sa_std.ssl_api_mutex.unlock(sio.io());
    if (sa_std.ssl_api) |*api| return api;

    const candidates = [_][]const u8{
        "libssl.so.3",
        "libssl.so",
        "/lib/x86_64-linux-gnu/libssl.so.3",
        "/usr/lib/x86_64-linux-gnu/libssl.so.3",
    };
    var lib: ?std.DynLib = null;
    for (candidates) |c| {
        if (std.DynLib.open(c)) |l| {
            lib = l;
            break;
        } else |_| {}
    }
    var l = lib orelse return null;

    const api = SslApi{
        .lib = l,
        .method_new = l.lookup(*const fn () callconv(.c) ?*const SslMethod, "TLS_client_method") orelse return null,
        .ctx_new = l.lookup(*const fn (?*const SslMethod) callconv(.c) ?*SslCtx, "SSL_CTX_new") orelse return null,
        .ctx_free = l.lookup(*const fn (?*SslCtx) callconv(.c) void, "SSL_CTX_free") orelse return null,
        .ctx_set_ciphersuites = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_set_ciphersuites") orelse return null,
        .ctx_set_cipher_list = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_set_cipher_list") orelse return null,
        // SSL_CTX_set1_groups_list / SSL_CTX_set1_sigalgs_list are
        // NOT exported symbols: openssl/ssl.h defines them as
        // macros over SSL_CTX_ctrl (SET_GROUPS_LIST=92,
        // SET_SIGALGS_LIST=98). The call sites below issue those
        // ctrls directly; hard-looking the names up made the whole
        // API table fail to load on every conforming OpenSSL 3.
        .ctx_ctrl = l.lookup(*const fn (?*SslCtx, c_int, c_long, ?*anyopaque) callconv(.c) c_long, "SSL_CTX_ctrl") orelse return null,
        .ctx_set_default_verify_paths = l.lookup(*const fn (?*SslCtx) callconv(.c) c_int, "SSL_CTX_set_default_verify_paths") orelse return null,
        .ctx_load_verify_locations = l.lookup(*const fn (?*SslCtx, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int, "SSL_CTX_load_verify_locations") orelse return null,
        .ctx_set_verify = l.lookup(*const fn (?*SslCtx, c_int, ?*const anyopaque) callconv(.c) void, "SSL_CTX_set_verify") orelse return null,
        .new = l.lookup(*const fn (?*SslCtx) callconv(.c) ?*Ssl, "SSL_new") orelse return null,
        .free = l.lookup(*const fn (?*Ssl) callconv(.c) void, "SSL_free") orelse return null,
        .set_fd = l.lookup(*const fn (?*Ssl, c_int) callconv(.c) c_int, "SSL_set_fd") orelse return null,
        .ctrl = l.lookup(*const fn (?*Ssl, c_int, c_long, ?*anyopaque) callconv(.c) c_long, "SSL_ctrl") orelse return null,
        .set_alpn_protos = l.lookup(*const fn (?*Ssl, [*]const u8, c_uint) callconv(.c) c_int, "SSL_set_alpn_protos") orelse return null,
        .set_msg_callback = l.lookup(*const fn (?*Ssl, MsgCallback) callconv(.c) void, "SSL_set_msg_callback") orelse return null,
        // SSL_set_msg_callback_arg is likewise a header macro
        // (SSL_ctrl SET_MSG_CALLBACK_ARG=16); see the call site.
        .set1_host = l.lookup(*const fn (?*Ssl, [*:0]const u8) callconv(.c) c_int, "SSL_set1_host") orelse return null,
        .connect = l.lookup(*const fn (?*Ssl) callconv(.c) c_int, "SSL_connect") orelse return null,
        .read = l.lookup(*const fn (?*Ssl, [*]u8, c_int) callconv(.c) c_int, "SSL_read") orelse return null,
        .write = l.lookup(*const fn (?*Ssl, [*]const u8, c_int) callconv(.c) c_int, "SSL_write") orelse return null,
        .shutdown = l.lookup(*const fn (?*Ssl) callconv(.c) c_int, "SSL_shutdown") orelse return null,
        .get_error = l.lookup(*const fn (?*const Ssl, c_int) callconv(.c) c_int, "SSL_get_error") orelse return null,
        .get_verify_result = l.lookup(*const fn (?*const Ssl) callconv(.c) c_long, "SSL_get_verify_result") orelse return null,
        .get_version = l.lookup(*const fn (?*const Ssl) callconv(.c) [*:0]const u8, "SSL_get_version") orelse return null,
        .get_current_cipher = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*const SslCipher, "SSL_get_current_cipher") orelse return null,
        .cipher_get_name = l.lookup(*const fn (?*const SslCipher) callconv(.c) [*:0]const u8, "SSL_CIPHER_get_name") orelse return null,
        .get_alpn_selected = l.lookup(*const fn (?*const Ssl, *?[*]const u8, *c_uint) callconv(.c) void, "SSL_get0_alpn_selected") orelse return null,
        .bio_new_mem_buf = l.lookup(*const fn ([*]const u8, c_int) callconv(.c) ?*Bio, "BIO_new_mem_buf") orelse return null,
        .bio_free = l.lookup(*const fn (?*Bio) callconv(.c) c_int, "BIO_free") orelse return null,
        .pem_read_bio_x509 = l.lookup(*const fn (?*Bio, ?*?*X509, ?*const anyopaque, ?*anyopaque) callconv(.c) ?*X509, "PEM_read_bio_X509") orelse return null,
        .x509_store_add_cert = l.lookup(*const fn (?*X509Store, ?*X509) callconv(.c) c_int, "X509_STORE_add_cert") orelse return null,
        .ctx_get_cert_store = l.lookup(*const fn (?*const SslCtx) callconv(.c) ?*X509Store, "SSL_CTX_get_cert_store") orelse return null,
        .x509_free = l.lookup(*const fn (?*X509) callconv(.c) void, "X509_free") orelse return null,
        .get_peer_cert_chain = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslStack, "SSL_get_peer_cert_chain") orelse return null,
        .sk_num = l.lookup(*const fn (?*const SslStack) callconv(.c) c_int, "OPENSSL_sk_num") orelse return null,
        .sk_value = l.lookup(*const fn (?*const SslStack, c_int) callconv(.c) ?*anyopaque, "OPENSSL_sk_value") orelse return null,
        .i2d_x509 = l.lookup(*const fn (?*X509, ?*?[*]u8) callconv(.c) c_int, "i2d_X509") orelse return null,
        .x509_get_subject_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_subject_name") orelse return null,
        .x509_get_issuer_name = l.lookup(*const fn (?*const X509) callconv(.c) ?*X509Name, "X509_get_issuer_name") orelse return null,
        .x509_name_print_ex = l.lookup(*const fn (?*Bio, ?*const X509Name, c_int, c_ulong) callconv(.c) c_int, "X509_NAME_print_ex") orelse return null,
        .bio_s_mem = l.lookup(*const fn () callconv(.c) ?*anyopaque, "BIO_s_mem") orelse return null,
        .bio_new = l.lookup(*const fn (?*anyopaque) callconv(.c) ?*Bio, "BIO_new") orelse return null,
        .bio_read = l.lookup(*const fn (?*Bio, [*]u8, c_int) callconv(.c) c_int, "BIO_read") orelse return null,
        .get1_session = l.lookup(*const fn (?*const Ssl) callconv(.c) ?*SslSession, "SSL_get1_session") orelse return null,
        .set_session = l.lookup(*const fn (?*Ssl, ?*SslSession) callconv(.c) c_int, "SSL_set_session") orelse return null,
        .d2i_session = l.lookup(*const fn (?*?*SslSession, *?[*]const u8, c_long) callconv(.c) ?*SslSession, "d2i_SSL_SESSION") orelse return null,
        .i2d_session = l.lookup(*const fn (?*SslSession, ?*?[*]u8) callconv(.c) c_int, "i2d_SSL_SESSION") orelse return null,
        .session_free = l.lookup(*const fn (?*SslSession) callconv(.c) void, "SSL_SESSION_free") orelse return null,
        .session_reused = l.lookup(*const fn (?*const Ssl) callconv(.c) c_int, "SSL_session_reused") orelse return null,
        .ctx_use_cert_chain_file = l.lookup(*const fn (?*SslCtx, [*:0]const u8) callconv(.c) c_int, "SSL_CTX_use_certificate_chain_file") orelse return null,
        .ctx_use_key_file = l.lookup(*const fn (?*SslCtx, [*:0]const u8, c_int) callconv(.c) c_int, "SSL_CTX_use_PrivateKey_file") orelse return null,
        .ctx_check_private_key = l.lookup(*const fn (?*const SslCtx) callconv(.c) c_int, "SSL_CTX_check_private_key") orelse return null,
    };
    sa_std.ssl_api = api;
    return &sa_std.ssl_api.?;
}

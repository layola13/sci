const std = @import("std");
const inst = @import("../common/instruction.zig");
const cFuncName = @import("ident.zig").cFuncName;
const kRuntimeHelpers = @import("helpers.zig").kRuntimeHelpers;

/// True iff the already-emitted body text calls `func_name` directly
/// (rendered as `sa_fn_<name>(`). Externs are only reachable via direct
/// calls, so this scan is exact; unrenderable names stay conservative.
pub fn bodyCallsFunction(body_text: []const u8, func_name: []const u8) bool {
    var nbuf: [1024]u8 = undefined;
    var fw = std.Io.Writer.fixed(&nbuf);
    cFuncName(&fw, func_name) catch return true;
    const needle = fw.buffered();
    if (needle.len + 1 > nbuf.len) return true;
    nbuf[needle.len] = '(';
    return std.mem.indexOf(u8, body_text, nbuf[0 .. needle.len + 1]) != null;
}


/// Seed `used` from textual references in the already-emitted body text
/// (`init` + function bodies): a helper is needed iff `name ++ "("`
/// occurs. Comments can only add false positives (safe direction: an
/// extra helper emitted, never a missing one).
pub fn collectUsedHelpers(allocator: std.mem.Allocator, body_text: []const u8) !std.StringHashMap(void) {
    var used = std.StringHashMap(void).init(allocator);
    errdefer used.deinit();
    var needle: [64]u8 = undefined;
    for (kRuntimeHelpers) |h| {
        if (h.name.len + 1 > needle.len) continue;
        @memcpy(needle[0..h.name.len], h.name);
        needle[h.name.len] = '(';
        if (std.mem.indexOf(u8, body_text, needle[0 .. h.name.len + 1]) != null) {
            try used.put(h.name, {});
        }
    }
    // Fixpoint over deps (table order preserved at emission).
    var changed = true;
    while (changed) {
        changed = false;
        for (kRuntimeHelpers) |h| {
            if (used.get(h.name) == null) continue;
            for (h.deps) |dep| {
                if (used.get(dep) == null) {
                    try used.put(dep, {});
                    changed = true;
                }
            }
        }
    }
    return used;
}


/// True for staged bindings that dispatch guest code host-side (via
/// sa_call_indirect): programs calling them force need_indirect so the
/// dispatcher+ftable are emitted even without a call_indirect inst.
pub fn bindingNeedsDispatcher(norm_name: []const u8) bool {
    return std.mem.eql(u8, norm_name, "pthread_spawn") or bindingNeedsTaskEntry(norm_name);
}


/// True for the goroutine bindings whose host side runs guest code
/// (spawn / supervised spawn / once_do): their C1 glue trampolines
/// call sa_call_indirect, so programs calling them force
/// need_indirect exactly like pthread_spawn, and the emit pass adds
/// the trampoline block (see the need_task_entry emission).
pub fn bindingNeedsTaskEntry(norm_name: []const u8) bool {
    return std.mem.eql(u8, norm_name, "sa_task_spawn") or
        std.mem.eql(u8, norm_name, "sa_task_spawn_supervised") or
        std.mem.eql(u8, norm_name, "sa_sync_once_do");
}


/// Staged host bindings for well-known externs (fd/mmap/signal/npm).
/// These mirror the interpreter/JS staged semantics the demos assert on
/// (fake fds, echo signal, byte-level npm checks) — NOT real syscalls,
/// so output stays deterministic with no host dependencies. Emits the
/// definition with the uniform-arity signature and returns true; unknown
/// names return false and the caller falls back to the trap stub.
/// True for externs bound directly to libsa_std.a entry points (the
/// cookie, TLS client-config and sockopt passthrough families). Their
/// rendered bindings call the real sa_std functions through the
/// sa_glue_* adapters, so a program using any of them needs the
/// preamble's prototype block and the catalog helpers the adapters
/// call (both keyed off this predicate), and its final link must
/// include libsa_std.a.
pub fn isStdlinkExtern(norm_name: []const u8) bool {
    if (std.mem.startsWith(u8, norm_name, "sa_cookie_")) return true;
    // Goroutine family (C1): the whole task.sai surface — sa_task_*,
    // sa_chan_*, sa_sync_* — is real in libsa_std.a, so these bind
    // for real instead of trap-stubbing. Delimitation: the binding
    // renderer below covers exactly the 36 names declared in
    // sa_std/task.sai (locked by the C1 unit test); the archive's
    // task runtime itself only supports x86_64 Linux hosts, so on
    // other hosts the calls surface the runtime's ERR_UNSUPPORTED.
    if (std.mem.startsWith(u8, norm_name, "sa_task_")) return true;
    if (std.mem.startsWith(u8, norm_name, "sa_chan_")) return true;
    if (std.mem.startsWith(u8, norm_name, "sa_sync_")) return true;
    const names = [_][]const u8{
        "sa_std_tls_client_config_new",
        "sa_std_tls_client_config_free",
        "sa_std_tls_client_config_set_server_name",
        "sa_std_tls_client_config_add_ca_file",
        "sa_std_tls_client_config_add_ca_memory",
        "sa_std_tls_client_config_set_insecure_no_verification",
        "sa_std_tls_client_config_set_verify_self_signed",
        "sa_std_tls_client_peer_cert_json",
        "sa_std_tls_shaped_supported",
        "sa_std_tls_shaped_connect",
        "sa_std_tls_client_buffer_data",
        "sa_std_tls_client_buffer_len",
        "sa_std_tls_client_buffer_free",
        "sa_net_addr_family",
        "sa_net_addr_free",
        "sa_net_addr_port",
        "sa_std_net_addr_format",
        "sa_std_net_socket_getsockopt",
        "sa_std_net_socket_getsockopt_int",
        "sa_std_net_socket_setsockopt",
        "sa_std_net_socket_setsockopt_int",
        "sa_std_net_to_socket_addr_first",
        "sa_std_net_udp_bind",
        "sa_std_net_udp_broadcast",
        "sa_std_net_udp_connect_addr",
        "sa_std_net_udp_local_addr",
        "sa_std_net_udp_recv_msg",
        "sa_std_net_udp_recv_multi",
        "sa_std_net_udp_send",
        "sa_std_net_udp_set_read_timeout",
        "sa_std_net_udp_ttl",
        "sa_std_net_unix_datagram_pair",
        "sa_std_net_unix_datagram_peer_cred",
        "sa_std_net_unix_datagram_unbound",
        "sa_std_process_id",
        "sa_std_process_user_id",
    };
    for (names) |n| {
        if (std.mem.eql(u8, norm_name, n)) return true;
    }
    return false;
}

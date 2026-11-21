const std = @import("std");

const emit_options = @import("emit_options.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const call = @import("referee/call.zig");
const const_decl = @import("common/const_decl.zig");

pub const EmitOptions = emit_options.EmitOptions;
pub const CEmitError = error{ Failed, InvalidOperand, UnknownFunction, UnsupportedInstruction, UnsupportedVariadic, OutOfMemory };

/// Last instruction raw text seen by the emitter (diagnostics only).
pub threadlocal var last_c_inst: []const u8 = "";
pub threadlocal var last_c_func: []const u8 = "";

pub const CEmitOptions = @import("emit_c/types.zig").CEmitOptions;
pub const emitCToString = @import("emit_c/emit_top.zig").emitCToString;
pub const emitCToFile = @import("emit_c/emit_top.zig").emitCToFile;
const cIdent = @import("emit_c/ident.zig").cIdent;
const isStdlinkExtern = @import("emit_c/helpers_util.zig").isStdlinkExtern;
const memPrimType = @import("emit_c/values.zig").memPrimType;
const writeExternBinding = @import("emit_c/binding_emit.zig").writeExternBinding;

test "c ident sanitizes names" {
    var buf: [64]u8 = undefined;
    var fbs = std.Io.Writer.fixed(&buf);
    try cIdent(&fbs, "hello-world.foo");
    try std.testing.expectEqualStrings("hello_world_foo", fbs.buffered());
}

test "c memPrimType untyped fallbacks match reference widths" {
    // Regression lock: the untyped fallback used to be u8, which
    // truncated untyped pointer takes (sa_vec_push's `take vec+Vec_ptr`)
    // to the pointer's low byte and corrupted every Vec grow copy on
    // the C backend. Reference widths are interp.zig's: take -> ptr,
    // load/store -> i64, atomics -> atomic_value_ty else i64.
    const take = inst.makeInstruction(.take, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.ptr, memPrimType(take));
    const load = inst.makeInstruction(.load, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.i64, memPrimType(load));
    const store = inst.makeInstruction(.store, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.i64, memPrimType(store));
    var atomic = inst.makeInstruction(.atomic_load, 0, 0, null, "");
    try std.testing.expectEqual(sig.PrimType.i64, memPrimType(atomic));
    atomic.atomic_value_ty = @backingInt(sig.PrimType.u8);
    try std.testing.expectEqual(sig.PrimType.u8, memPrimType(atomic));
    var typed = inst.makeInstruction(.load, 0, 0, null, "");
    typed.operands[3] = .{ .ty = @backingInt(sig.PrimType.u16) };
    try std.testing.expectEqual(sig.PrimType.u16, memPrimType(typed));
}

test "c stdlink bindings cover the cookie/tls/sockopt gap lists" {
    // Regression lock for the BQ-registered sa2c binding gaps: the
    // cookie family (the 17 names BQ hit plus the rest of the
    // http_cookie.sai surface), the TLS config face (10 names plus
    // the client-buffer accessors peer_cert_json is consumed
    // through) and the sockopt passthrough family (23 names). Every
    // name must render a real direct-link binding instead of falling
    // through to the trap stub.
    const names = [_][]const u8{
        "sa_cookie_parse_set_cookie",
        "sa_cookie_last_error",
        "sa_cookie_free",
        "sa_cookie_new",
        "sa_cookie_name",
        "sa_cookie_value",
        "sa_cookie_domain",
        "sa_cookie_path",
        "sa_cookie_expires",
        "sa_cookie_max_age",
        "sa_cookie_flags",
        "sa_cookie_same_site",
        "sa_cookie_is_host_only",
        "sa_cookie_set_domain",
        "sa_cookie_set_path",
        "sa_cookie_set_expires",
        "sa_cookie_set_max_age",
        "sa_cookie_clear_expiry",
        "sa_cookie_set_secure",
        "sa_cookie_set_http_only",
        "sa_cookie_set_partitioned",
        "sa_cookie_set_same_site",
        "sa_cookie_serialize",
        "sa_cookie_serialize_pair",
        "sa_cookie_is_expired",
        "sa_cookie_domain_match",
        "sa_cookie_path_match",
        "sa_cookie_header_pair_count",
        "sa_cookie_header_pair_at",
        "sa_cookie_jar_new",
        "sa_cookie_jar_free",
        "sa_cookie_jar_set_policy",
        "sa_cookie_jar_policy",
        "sa_cookie_jar_store",
        "sa_cookie_jar_header",
        "sa_cookie_jar_count",
        "sa_cookie_jar_at",
        "sa_cookie_jar_clear",
        "sa_cookie_jar_evict_expired",
        "sa_cookie_jar_save",
        "sa_cookie_jar_load",
        "sa_cookie_jar_request_header",
        "sa_cookie_jar_store_response",
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
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try std.testing.expect(try writeExternBinding(&aw.writer, n, 12, false));
        try std.testing.expect(isStdlinkExtern(n));
    }
}

test "c extern binding maps sa_mem_free to the runtime sa_free" {
    // DEF deep-drop batch (DESIGN §3): @sa_mem_free is the only memory
    // free extern in sa_std. Without this binding every @sa_vec_free
    // on the C route rendered a trapping stub, so no program that
    // frees could run there at all.
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try std.testing.expect(try writeExternBinding(&aw.writer, "sa_mem_free", 12, false));
    try std.testing.expect(std.mem.indexOf(u8, aw.writer.buffered(), "{ sa_free(a0); return 0; }") != null);
}

test "c extern binding maps memcpy to a guest-memory copy" {
    // Class-A batch: sa_std core/mem.sa binds
    // @sa_mem_copy_nonoverlapping to @extern memcpy. Without this
    // binding the C route rendered a trapping stub and every Vec
    // bulk-extend trapped there.
    var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer aw.deinit();
    try std.testing.expect(try writeExternBinding(&aw.writer, "memcpy", 12, false));
    try std.testing.expect(std.mem.indexOf(u8, aw.writer.buffered(), "memcpy(&sa_mem[x], &sa_mem[y], (size_t)a2)") != null);
}

test "c stdlink bindings cover the goroutine task family (C1)" {
    // The whole sa_std/task.sai surface (36 names) must render a real
    // direct-link binding into libsa_std.a instead of falling through
    // to the trap stub, and every rendered body must stay balanced
    // with all uniform-arity parameters covered.
    const names = [_][]const u8{
        "sa_task_spawn",
        "sa_task_spawn_supervised",
        "sa_task_trap_info",
        "sa_task_monitor",
        "sa_task_yield",
        "sa_task_sleep_ns",
        "sa_task_sleep_ms",
        "sa_task_join",
        "sa_task_detach",
        "sa_task_current",
        "sa_task_live_count",
        "sa_task_deadlock_guard_arm",
        "sa_task_net_wait",
        "sa_chan_make",
        "sa_chan_destroy",
        "sa_chan_close",
        "sa_chan_send",
        "sa_chan_recv",
        "sa_chan_len",
        "sa_chan_cap",
        "sa_chan_select",
        "sa_sync_mutex_new",
        "sa_sync_rwlock_new",
        "sa_sync_waitgroup_new",
        "sa_sync_once_new",
        "sa_sync_destroy",
        "sa_sync_mutex_lock",
        "sa_sync_mutex_try_lock",
        "sa_sync_mutex_unlock",
        "sa_sync_rwlock_rlock",
        "sa_sync_rwlock_runlock",
        "sa_sync_rwlock_lock",
        "sa_sync_rwlock_unlock",
        "sa_sync_waitgroup_add",
        "sa_sync_waitgroup_done",
        "sa_sync_waitgroup_wait",
        "sa_sync_once_do",
    };
    for (names) |n| {
        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer aw.deinit();
        try std.testing.expect(try writeExternBinding(&aw.writer, n, 12, false));
        try std.testing.expect(isStdlinkExtern(n));
        try std.testing.expect(cBodyBalanced(aw.writer.buffered()));
        try std.testing.expect(cParamsCovered(aw.writer.buffered(), 12));
    }
}

/// True iff every param a0..aN in a rendered binding body occurs at
/// least twice (declaration plus a (void) cast or real use), so no
/// -Wunused-parameter can fire. Enforces voids-mask precision forever.
fn cParamsCovered(t: []const u8, uniform_arity: usize) bool {
    if (uniform_arity == 0) return true;
    var i: usize = 0;
    while (i < uniform_arity) : (i += 1) {
        var nbuf: [32]u8 = undefined;
        const needle = std.fmt.bufPrint(&nbuf, "a{d}", .{i}) catch return false;
        var count: usize = 0;
        var pos: usize = 0;
        while (pos + needle.len <= t.len) {
            if (std.mem.startsWith(u8, t[pos..], needle)) {
                const before_ok = pos == 0 or !(std.ascii.isAlphanumeric(t[pos - 1]) or t[pos - 1] == '_');
                const after = pos + needle.len;
                const after_ok = after >= t.len or !(std.ascii.isAlphanumeric(t[after]) or t[after] == '_');
                if (before_ok and after_ok) count += 1;
            }
            pos += 1;
        }
        if (count < 2) return false;
    }
    return true;
}

/// True iff t is a brace-balanced function body ending with "}\n",
/// ignoring braces inside strings/chars. Used to self-check every
/// rendered extern binding (an unclosed body would swallow following
/// definitions; fail the build loudly instead of emitting broken C).
/// NOTE: emit_c unit tests are not wired into any test binary, so this
/// runtime check (not a test block) is the enforced guard.
fn cBodyBalanced(t: []const u8) bool {
    if (!std.mem.endsWith(u8, t, "}\n")) return false;
    return cBracesBalanced(t);
}

/// Brace balance ignoring string/char literals. Used for catalog helper
/// bodies (which the preamble writes with its own trailing newline).
fn cBracesBalanced(t: []const u8) bool {
    var depth: i32 = 0;
    var in_str = false;
    var in_chr = false;
    var esc = false;
    for (t) |c| {
        if (in_str) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == '"') {
                in_str = false;
            }
        } else if (in_chr) {
            if (esc) {
                esc = false;
            } else if (c == '\\') {
                esc = true;
            } else if (c == '\'') {
                in_chr = false;
            }
        } else if (c == '"') {
            in_str = true;
        } else if (c == '\'') {
            in_chr = true;
        } else if (c == '{') {
            depth += 1;
        } else if (c == '}') {
            depth -= 1;
            if (depth < 0) return false;
        }
    }
    return depth == 0;
}


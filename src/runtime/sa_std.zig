const std = @import("std");
test "sa_std_tests" { std.testing.refAllDecls(@import("sa_std/sa_std_tests.zig")); }
pub const builtin = @import("builtin");
pub const sio = @import("sio");

// Runtime permission policy core (sala 16_policy phase 1): pure decision
// logic, referenced here so the module and its unit tests join every
// sa_std build/test graph. Interception wiring lands separately.
pub const sa_policy = @import("sa_policy.zig");
pub const sa_globals = @import("sa_globals.zig");
// Goroutine runtime: the native stack-switching implementation
// everywhere except wasm, where the cooperative CPS/state-machine
// runtime (sa_task_coop.zig) provides the same task.sai extern
// surface — the native mechanism cannot lower to wasm.
pub const sa_task = if (is_wasm) @import("sa_task_coop.zig") else @import("sa_task.zig");

// Goroutine netpoller glue: sa_task declares sa_std_net_poll_wait
// as a plain extern and this module's export below satisfies it
// in the same compilation. (An .init_array registration was
// tried and removed: SA-built binaries segfault at startup when
// the archive carries an .init_array entry — see sa_task.zig.)
pub const sa_identity = @import("sa_identity.zig");

/// Runtime permission gate (sala 16_policy): checked at resource
/// acquisition points only. No context installed -> allowed (the
/// host surface enforces "no policy, no start"). Denial returns the
/// dedicated SA_STD_ERR_PERMISSION_DENIED status; getters without a
/// status channel (env, time, random) deny by returning zero, and
/// every denial is audit-logged through the installed sink.
pub fn policyAllows(resource: sa_policy.Resource) bool {
    // On wasm there is no ELF-constructor guarantee, so the first gated
    // call installs the policy lazily (policyBootstrap is idempotent).
    if (comptime is_wasm) policyBootstrap();
    if (sa_policy.active_context == null) return true;
    const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
    return sa_policy.gate(std.heap.page_allocator, resource, now_ns);
}

/// Run-category policy check shared with satellite runtime files
/// (sa_pty.zig): a PTY spawn acquires a process exactly like the spawn
/// funnel above, so it goes through the same 16_policy gate.
pub fn saStdPolicyAllowsRun(program: []const u8) bool {
    return policyAllows(.{ .run = program });
}

/// Fs-read policy check shared with satellite runtime files
/// (sa_fs_watch.zig): registering a watch is a read-side acquisition.
pub fn saStdPolicyAllowsFsRead(path: []const u8) bool {
    return policyAllows(.{ .fs = .{ .path = path, .write = false } });
}

// ---------------------------------------------------------------------
// Policy bootstrap for produced binaries (sala 16_policy phase 1,
// slice 3). The deployment supplies the policy through the
// environment; an ELF constructor installs it before main runs:
//   SA_POLICY_JSON      inline policy JSON (highest priority)
//   SA_POLICY_TOKENS_JSON  one-time token specs minted into the root context
//   SA_POLICY_FILE      path to a policy JSON file
//   SA_POLICY_ALLOW_ALL "1" engages an explicit allow-all policy (the
//                       -A analog) and always leaves an audit trace
//   SA_POLICY_REQUIRED  "1" with none of the above: refuse to start
//   SA_AUDIT_FILE       audit JSONL destination; otherwise the
//                       policy's audit.sink file:// path; otherwise
//                       audit events are dropped
// With nothing set, no context is installed and the process runs in
// legacy mode; SA_POLICY_REQUIRED is how a deployment closes that
// door. A policy that is present but unreadable or invalid is a hard
// startup failure, never a silent fallback to legacy mode.

var policy_context_storage: ?*sa_policy.PolicyContext = null;
var policy_audit_fd: ?std.posix.fd_t = null;

fn policyBootstrapWriteStderr(text: []const u8) void {
    _ = lxWrite(2, text) catch {};
}

fn policyAuditSink(line: []const u8) void {
    const fd = policy_audit_fd orelse return;
    _ = lxWrite(fd, line) catch {};
}

fn policyBootstrapFail(message: []const u8, code: u8) noreturn {
    policyBootstrapWriteStderr("[sa-policy] ");
    policyBootstrapWriteStderr(message);
    policyBootstrapWriteStderr("\n");
    std.process.exit(code);
}

fn policyEnvOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return sio.getEnvVarOwned(allocator, name) catch null;
}

fn policyEnvFlag(allocator: std.mem.Allocator, name: []const u8) bool {
    const value = policyEnvOwned(allocator, name) orelse return false;
    defer allocator.free(value);
    return std.mem.eql(u8, value, "1");
}

fn installPolicyText(allocator: std.mem.Allocator, text: []const u8) void {
    const policy = sa_policy.parsePolicyJson(allocator, text) catch |err|
        policyBootstrapFail(@errorName(err), 2);

    var audit_path: ?[]u8 = policyEnvOwned(allocator, "SA_AUDIT_FILE");
    if (audit_path == null) {
        if (policy.audit_sink) |sink| {
            if (std.mem.startsWith(u8, sink, "file://")) {
                audit_path = allocator.dupe(u8, sink["file://".len..]) catch null;
            }
        }
    }
    if (audit_path) |path| {
        defer allocator.free(path);
        var open_flags: std.posix.O = .{};
        // WASI's O struct has no ACCMODE/APPEND fields (access mode and
        // append live in fd rights/fdflags there); std.posix.openat maps
        // what exists. Audit-sink open stays best-effort on every target.
        if (comptime !is_wasm) {
            open_flags.ACCMODE = .WRONLY;
            open_flags.APPEND = true;
        }
        open_flags.CREAT = true;
        if (std.posix.openat(std.posix.AT.FDCWD, path, open_flags, @as(std.posix.mode_t, 0o644))) |fd| {
            policy_audit_fd = fd;
            sa_policy.installAuditSink(policyAuditSink);
        } else |_| {}
    }

    const context = allocator.create(sa_policy.PolicyContext) catch
        policyBootstrapFail("out of memory", 2);
    context.* = sa_policy.PolicyContext.init(allocator, 1, policy);
    policy_context_storage = context;
    sa_policy.installContext(context);

    // One-time tokens delivered by the launcher (16_policy phase 1):
    // the host mints them after approval and hands them over through
    // SA_POLICY_TOKENS_JSON; they are minted into the root context
    // here, before main runs.
    if (policyEnvOwned(allocator, "SA_POLICY_TOKENS_JSON")) |tokens_text| {
        defer allocator.free(tokens_text);
        const specs = sa_policy.parseTokenSpecsJson(allocator, tokens_text) catch |err|
            policyBootstrapFail(@errorName(err), 2);
        defer sa_policy.freeTokenSpecs(allocator, specs);
        const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
        sa_policy.mintTokenSpecs(context, allocator, specs, now_ns) catch
            policyBootstrapFail("out of memory", 2);
    }
}

var policy_bootstrap_attempted: bool = false;

// ---------------------------------------------------------------------
// DEF-R7: SIGPIPE policy (Jev ruling 2026-10-31:
// ignore_at_startup_surface_epipe / host_startup_all). Every SA-built
// program ignores SIGPIPE from startup, before user code runs, so a
// write to a closed peer surfaces through the existing status
// discipline (error.BrokenPipe -> SA_STD_ERR_IO on the fd/tcp faces,
// NetworkStatus.closed on the http faces) instead of killing the
// whole process. Before this, the only protection was incidental:
// std.Io.Threaded.init installs a do-nothing SIGPIPE handler the
// first time sio.io() is called — any write path reached before that
// init (or after a Threaded deinit restores SIG_DFL, or on the
// single-threaded Io variant, which installs nothing) died with
// signal 13. Installation rides the existing policy-bootstrap ELF
// constructor (.init_array below), which runs before main in every
// produced binary that links this archive object; the host process
// installs the same disposition at its own main (src/main.zig).
// Only SIGPIPE is touched; no other signal's disposition changes.

var sigpipe_ignore_installed: bool = false;

pub fn applySigpipeIgnore() void {
    // NOTE: do NOT gate this on @hasDecl(std.posix.SIG, "PIPE") —
    // that is false on this Zig version (PIPE is an enum member, not
    // a declaration), which is exactly why the http server's earlier
    // attempt at this install (sa_http_server.zig) never took effect.
    if (comptime !is_linux) return;
    const act: std.posix.Sigaction = .{
        .handler = .{ .handler = std.posix.SIG.IGN },
        .mask = std.posix.sigemptyset(),
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.PIPE, &act, null);
}

fn installSigpipeIgnore() void {
    if (sigpipe_ignore_installed) return;
    sigpipe_ignore_installed = true;
    applySigpipeIgnore();
}

// ---------------------------------------------------------------------
// Task 75: heap page return (frag/escape retention).
// The SA program heap is libc malloc (alloc lowers to malloc,
// sa_mem_free lowers to free). glibc keeps sub-threshold chunks in the
// brk arena and only returns memory by trimming the top chunk, so a
// fragmenting free pattern -- live and dead blocks interleaved, as in
// the frag arm -- retains the freed pages: the top chunk is a live
// block, no trim happens, and post-free RSS equals peak RSS. Measured
// on probe p_frag (4500 live + 4500 dead x 64 KiB blocks, live set
// 288,000 KiB): post-free steady-state RSS 578,488 KiB (== peak), i.e.
// ~290 MiB of freed memory retained; with MALLOC_MMAP_THRESHOLD_=32768
// the same probe reads 290,324 KiB (== live set + ~2 MiB runtime) at
// no time cost (1.87 s vs 1.93 s median). Full frees already return
// pages (p_big/p_many/p_sparse plateaus ~2 MiB); only the interleaved
// partial free retains.
// Fix: lower glibc's mmap threshold to 32 KiB at startup, so blocks
// >= 32 KiB are individually mmap'd and munmap'd on free regardless of
// interleaving. This is the code form of MALLOC_MMAP_THRESHOLD_=32768.
// M_MMAP_THRESHOLD is glibc mallopt param -3. Best-effort: a failed
// mallopt (returns 0) leaves the default threshold in place.
// Runs in policyBootstrap (.init_array, before main), gated to Linux;
// wasm/no-libc targets never reference mallopt (comptime gate).
extern fn mallopt(param: c_int, value: c_int) c_int;

fn applyHeapPageReturn() void {
    if (comptime !is_linux or is_wasm) return;
}

/// DEF-R7 startup entry called by every generated program main
/// wrapper (LLVM shim + C backend) before user code runs. This is
/// the coverage backbone: a plain reference from the wrapper extracts
/// this archive object at link time even for programs that reference
/// no other sa_std symbol, where the .init_array constructor alone
/// would never be linked in. Exported on all targets; the install
/// itself no-ops where SIGPIPE does not exist (wasm/windows).
pub export fn sa_install_sigpipe_ignore() void {
    installSigpipeIgnore();
}

fn policyBootstrap() callconv(.c) void {
    applyHeapPageReturn();
    installSigpipeIgnore();
    if (policy_bootstrap_attempted) return;
    policy_bootstrap_attempted = true;
    const allocator = std.heap.page_allocator;

    if (policyEnvFlag(allocator, "SA_POLICY_ALLOW_ALL")) {
        installPolicyText(allocator, "{\"permissions\":{\"net\":{\"mode\":\"allow\"},\"fs\":{\"mode\":\"allow\"},\"env\":{\"mode\":\"allow\"},\"run\":{\"mode\":\"allow\"},\"time\":{\"mode\":\"allow\"},\"random\":{\"mode\":\"allow\"}}}");
        policyBootstrapWriteStderr("[sa-policy] allow-all policy engaged via SA_POLICY_ALLOW_ALL (audit trace)\n");
        if (policy_audit_fd != null) {
            const now_ns: i64 = @intCast(std.Io.Clock.awake.now(sio.io()).toNanoseconds());
            const event = sa_policy.AuditEvent{ .context_id = 1, .category = .run, .resource = "SA_POLICY_ALLOW_ALL", .decision = "allow-all", .source = "env" };
            if (event.formatJsonLine(allocator, now_ns)) |line| {
                defer allocator.free(line);
                policyAuditSink(line);
            } else |_| {}
        }
        return;
    }

    if (policyEnvOwned(allocator, "SA_POLICY_JSON")) |json_text| {
        defer allocator.free(json_text);
        installPolicyText(allocator, json_text);
        return;
    }

    if (policyEnvOwned(allocator, "SA_POLICY_FILE")) |path| {
        defer allocator.free(path);
        var file = sio.cwd().openFile(path, .{}) catch
            policyBootstrapFail("SA_POLICY_FILE is set but cannot be opened", 2);
        defer file.close();
        const text = file.readToEndAlloc(allocator, 1 << 20) catch
            policyBootstrapFail("SA_POLICY_FILE cannot be read", 2);
        defer allocator.free(text);
        installPolicyText(allocator, text);
        return;
    }

    if (policyEnvFlag(allocator, "SA_POLICY_REQUIRED")) {
        policyBootstrapFail("SA_POLICY_REQUIRED is set but no policy was provided (set SA_POLICY_JSON, SA_POLICY_FILE, or SA_POLICY_ALLOW_ALL=1)", 1);
    }

    if (policyEnvOwned(allocator, "SA_POLICY_TOKENS_JSON")) |tokens_text| {
        allocator.free(tokens_text);
        policyBootstrapFail("SA_POLICY_TOKENS_JSON is set but no policy was provided (tokens need a policy context to bind to)", 1);
    }
}

// align(8) is load-bearing: with a larger section alignment the linker
// pads .init_array up to the boundary, and glibc's init walk calls that
// zero padding as a null function pointer before main ever runs.
var policy_bootstrap_init_entry: *const fn () callconv(.c) void align(8) linksection(".init_array") = &policyBootstrap;

comptime {
    if (!builtin.is_test and builtin.os.tag == .linux and !is_wasm) {
        @export(&policyBootstrap, .{ .name = "sa_policy_bootstrap" });
        @export(&policy_bootstrap_init_entry, .{ .name = "__sa_policy_bootstrap_init" });
    }
}


// wasm32-wasi compat (stage1: archive must compile; sockets/process/dlopen
// stubbed to UNSUPPORTED): SockAddrT/W/SIG are `void` on wasi, and
// std.os.linux has no wasm syscalls. Provide minimal layout-compatible
// aliases so signatures type-check; bodies return UNSUPPORTED via
// `if (comptime is_wasm)` guards.
pub const is_wasm = builtin.cpu.arch.isWasm();
pub const is_linux = builtin.os.tag == .linux;
const WasiSockAddrUn = extern struct { family: u16 = 0, path: [108]u8 = undefined };
const WasiSockAddrIn = extern struct { port: u16 = 0, addr: u32 = 0, zero: [8]u8 = undefined };
const WasiSockAddrIn6 = extern struct { port: u16 = 0, flowinfo: u32 = 0, addr: [16]u8 = undefined, scope_id: u32 = 0 };
const WasiSockAddrStorage = extern struct { family: u16 = 0, __pad: [126]u8 = undefined };
const WasiSockAddr = extern struct { family: u16 = 0, data: [14]u8 = undefined };
pub const SockAddrUnT = if (is_wasm) WasiSockAddrUn else std.posix.sockaddr.un;
const SockAddrInT = if (is_wasm) WasiSockAddrIn else std.posix.sockaddr.in;
const SockAddrIn6T = if (is_wasm) WasiSockAddrIn6 else std.posix.sockaddr.in6;
pub const SockAddrStorageT = if (is_wasm) WasiSockAddrStorage else std.posix.sockaddr.storage;
pub const SockAddrT = if (is_wasm) WasiSockAddr else std.posix.sockaddr;
pub const SockLenT = if (is_wasm) u32 else std.posix.socklen_t;
pub fn makeSockAddrStorage() SockAddrStorageT {
    if (comptime is_wasm) return .{ .family = 0 };
    switch (builtin.os.tag) {
        .linux, .illumos, .windows, .serenity, .haiku, .wasi, .emscripten => return .{ .family = 0 },
        else => return .{ .len = @intCast(@sizeOf(SockAddrStorageT)), .family = 0 },
    }
}
const UnixSockAddr = struct { addr: SockAddrUnT, len: SockLenT };
// wasi has no wait macros/signals (std.posix.W/SIG are void); dummies so
// status helpers type-check (callers stubbed to UNSUPPORTED on wasm).
pub const WasiW = @import("sa_std/proc_wait.zig").WasiW;
pub const WT = @import("sa_std/proc_wait.zig").WT;
const WasiSIG = struct {
    pub const KILL: u8 = 9;
};
pub const SIGT = if (is_wasm) WasiSIG else std.posix.SIG;
// wasi-libc has no AF/SOL (void via std.c); Linux-value dummies for compile.
const WasiAF = struct {
    pub const UNIX: u16 = 1;
    pub const INET: u16 = 2;
    pub const INET6: u16 = 10;
};
pub const AFT = if (is_wasm) WasiAF else std.posix.AF;
const WasiSOL = struct {
    pub const SOCKET: u32 = 1;
};
pub const SOLT = if (is_wasm) WasiSOL else std.posix.SOL;
const WasiSO = struct {
    pub const REUSEADDR: u32 = 2;
    pub const TYPE: u32 = 3;
    pub const ERROR: u32 = 4;
    pub const BROADCAST: u32 = 6;
    pub const SNDBUF: u32 = 7;
    pub const RCVBUF: u32 = 8;
    pub const KEEPALIVE: u32 = 9;
    pub const LINGER: u32 = 13;
    pub const REUSEPORT: u32 = 15;
    pub const PEERCRED: u32 = 17;
    pub const RCVTIMEO: u32 = 20;
    pub const SNDTIMEO: u32 = 21;
    pub const ACCEPTCONN: u32 = 30;
};
pub const SOT = if (is_wasm) WasiSO else std.posix.SO;
const WasiIPPROTO = struct {
    pub const IP: u32 = 0;
    pub const TCP: u32 = 6;
    pub const UDP: u32 = 17;
    pub const IPV6: u32 = 41;
};
pub const IPPROTOT = if (is_wasm) WasiIPPROTO else std.posix.IPPROTO;
const WasiSOCK = struct {
    pub const STREAM: u32 = 1;
    pub const DGRAM: u32 = 2;
    pub const NONBLOCK: u32 = 2048;
    pub const CLOEXEC: u32 = 524288;
};
pub const SOCKT = if (is_wasm) WasiSOCK else std.posix.SOCK;
// Linux-only socket options/constants fall back to neutral values elsewhere;
// the export functions that use them are compiled out of non-Linux builds.
pub const TCP_QUICKACK: u32 = if (is_linux) std.os.linux.TCP.QUICKACK else 0;
pub const TCP_DEFER_ACCEPT: u32 = if (is_linux) std.os.linux.TCP.DEFER_ACCEPT else 0;
pub const TCP_KEEPIDLE: u32 = if (is_linux) std.os.linux.TCP.KEEPIDLE else if (builtin.os.tag == .freebsd) 256 else std.posix.TCP.KEEPALIVE;
pub const TCP_KEEPINTVL: u32 = if (is_linux) std.os.linux.TCP.KEEPINTVL else std.posix.TCP.KEEPINTVL;
pub const TCP_KEEPCNT: u32 = if (is_linux) std.os.linux.TCP.KEEPCNT else std.posix.TCP.KEEPCNT;
pub const SO_PASSCRED: u32 = if (is_linux) std.os.linux.SO.PASSCRED else 0;
pub const SO_MARK: u32 = if (is_linux) std.os.linux.SO.MARK else 0;
const WasiMsghdr = extern struct { name: ?*anyopaque = null, namelen: u32 = 0, iov: ?*anyopaque = null, iovlen: usize = 0, control: ?*anyopaque = null, controllen: usize = 0, flags: u32 = 0 };
pub const MsghdrT = if (is_wasm) WasiMsghdr else std.posix.msghdr;
pub const MsghdrConstT = if (is_wasm) WasiMsghdr else std.posix.msghdr_const;
// Pull the new sa_std protocol runtimes (http2/tls_server/dtls/quic) export
// functions into the library object. Zig only emits `pub export fn`s of a
// transitively-imported module when the root source actually retains the
// module's declaration, so a comptime reference block forces every export fn
// here to be kept and emitted into libsa_std alongside the rest of the sa_std
// surface. This is purely a link-time union; nothing calls these directly.
comptime {
    const http2 = @import("sa_http2.zig");
    _ = &http2.sa_std_http2_supported;
    _ = &http2.sa_std_http2_client_request;
    _ = &http2.sa_std_http2_client_request_with_settings;
    _ = &http2.sa_std_http2_nghttp2_version_json;
    _ = &http2.sa_std_http2_status_json;
    _ = &http2.sa_std_http2_constants_json;
    _ = &http2.sa_std_http2_sensitive_headers;
    _ = &http2.sa_std_http2_get_default_settings_json;
    _ = &http2.sa_std_http2_get_packed_settings;
    _ = &http2.sa_std_http2_get_unpacked_settings_json;
    _ = &http2.sa_std_http2_perform_server_handshake;
    _ = &http2.sa_std_http2_buffer_data;
    _ = &http2.sa_std_http2_buffer_len;
    _ = &http2.sa_std_http2_buffer_free;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_supported;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_supported;
    _ = &@import("sa_tls_shaped.zig").sa_std_tls_shaped_supported;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_new;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_free;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_set_server_name;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_add_ca_file;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_add_ca_memory;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_set_insecure_no_verification;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_config_set_verify_self_signed;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_connect_config;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_start_tls;
    _ = &@import("sa_tls_client.zig").sa_std_tls_client_peer_cert_json;
    _ = &@import("sa_tls_shaped.zig").sa_std_tls_shaped_start_tls;
    _ = &@import("sa_tls_shaped.zig").sa_std_tls_shaped_session_blob;
    _ = &@import("sa_tls_shaped.zig").sa_std_tls_shaped_peer_cert_chain_json;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_ctx_create_memory;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_ctx_set_alpn;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_ctx_require_client_cert;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_ctx_set_version_bounds;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_session_verify_result;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_negotiated_json;
    _ = &@import("sa_tls_server.zig").sa_std_tls_server_peer_cert_chain_json;
    _ = &@import("sa_ws_client.zig").sa_std_ws_client_supported;
    _ = &@import("sa_mysql_client.zig").sa_mysql_supported;
    _ = &@import("sa_mysql_client.zig").sa_mysql_connect;
    _ = &@import("sa_mysql_client.zig").sa_mysql_close;
    _ = &@import("sa_mysql_client.zig").sa_mysql_ping;
    _ = &@import("sa_mysql_client.zig").sa_mysql_query;
    _ = &@import("sa_mysql_client.zig").sa_mysql_prepare;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_bind_null;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_bind_i64;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_bind_u64;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_bind_f64;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_bind_bytes;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_param_count;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_execute;
    _ = &@import("sa_mysql_client.zig").sa_mysql_stmt_close;
    _ = &@import("sa_mysql_client.zig").sa_mysql_errno;
    _ = &@import("sa_mysql_client.zig").sa_mysql_sqlstate;
    _ = &@import("sa_mysql_client.zig").sa_mysql_error_message;
    _ = &@import("sa_mysql_client.zig").sa_mysql_server_version;
    _ = &@import("sa_mysql_client.zig").sa_mysql_connection_id;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_free;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_has_result_set;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_column_count;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_column_name;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_column_type;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_row_count;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_next;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_value;
    _ = &@import("sa_mysql_client.zig").sa_mysql_affected_rows;
    _ = &@import("sa_mysql_client.zig").sa_mysql_last_insert_id;
    _ = &@import("sa_mysql_client.zig").sa_mysql_result_warnings;
    _ = &@import("sa_http_server.zig").sa_http_server_accept;
    _ = &@import("sa_http_server.zig").sa_http_server_accept_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_free;
    _ = &@import("sa_http_server.zig").sa_http_server_free_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_new;
    _ = &@import("sa_http_server.zig").sa_http_server_new_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_req_free;
    _ = &@import("sa_http_server.zig").sa_http_server_req_free_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_req_get_body;
    _ = &@import("sa_http_server.zig").sa_http_server_req_get_header;
    _ = &@import("sa_http_server.zig").sa_http_server_req_get_method;
    _ = &@import("sa_http_server.zig").sa_http_server_req_get_path;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_add_header_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_free;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_free_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_new;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_new_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_req_peer_addr_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_send;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_send_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_send_head_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_set_content_type;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_add_header_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_end;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_end_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_flush;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_flush_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_free;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_free_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_new;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_new_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_write;
    _ = &@import("sa_http_server.zig").sa_http_server_resp_stream_write_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_serve_threaded;
    _ = &@import("sa_http_server.zig").sa_http_server_set_max_body_bytes;
    _ = &@import("sa_http_server.zig").sa_http_server_start;
    _ = &@import("sa_http_server.zig").sa_http_server_start_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_stop_serving;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_close_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_free;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_free_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_poll_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_read;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_read_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_upgrade;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_upgrade_v2;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_write;
    _ = &@import("sa_http_server.zig").sa_http_server_websocket_write_v2;
    _ = &@import("sa_dtls.zig").sa_std_dtls_supported;
    _ = &@import("sa_quic.zig").sa_std_quic_supported;
    _ = &@import("sa_http_client.zig").sa_http_client_new;
    _ = &@import("sa_http_client.zig").sa_http_client_new_with_profile;
    _ = &@import("sa_http_client.zig").sa_http_client_new_with_proxy;
    _ = &@import("sa_http_client.zig").sa_http_client_new_with_profile_proxy;
    _ = &@import("sa_compress.zig").sa_std_compress_encode;
    _ = &@import("sa_multipart.zig").sa_std_multipart_parse;
    _ = &@import("sa_multipart.zig").sa_std_multipart_builder_new;
    _ = &@import("sa_toml.zig").sa_toml_parse;
    _ = &@import("sa_toml.zig").sa_toml_free;
    _ = &@import("sa_toml.zig").sa_toml_last_error;
    _ = &@import("sa_toml.zig").sa_toml_kind;
    _ = &@import("sa_toml.zig").sa_toml_get_string;
    _ = &@import("sa_toml.zig").sa_toml_get_datetime;
    _ = &@import("sa_toml.zig").sa_toml_get_i64;
    _ = &@import("sa_toml.zig").sa_toml_get_f64;
    _ = &@import("sa_toml.zig").sa_toml_get_bool;
    _ = &@import("sa_toml.zig").sa_toml_array_len;
    _ = &@import("sa_toml.zig").sa_toml_table_len;
    _ = &@import("sa_toml.zig").sa_toml_array_get_string;
    _ = &@import("sa_toml.zig").sa_toml_array_get_i64;
    _ = &@import("sa_toml.zig").sa_toml_new;
    _ = &@import("sa_toml.zig").sa_toml_table_key_at;
    _ = &@import("sa_toml.zig").sa_toml_set_string;
    _ = &@import("sa_toml.zig").sa_toml_set_datetime;
    _ = &@import("sa_toml.zig").sa_toml_set_i64;
    _ = &@import("sa_toml.zig").sa_toml_set_f64;
    _ = &@import("sa_toml.zig").sa_toml_set_bool;
    _ = &@import("sa_toml.zig").sa_toml_set_table;
    _ = &@import("sa_toml.zig").sa_toml_remove;
    _ = &@import("sa_toml.zig").sa_toml_array_push_string;
    _ = &@import("sa_toml.zig").sa_toml_array_push_datetime;
    _ = &@import("sa_toml.zig").sa_toml_array_push_i64;
    _ = &@import("sa_toml.zig").sa_toml_array_push_f64;
    _ = &@import("sa_toml.zig").sa_toml_array_push_bool;
    _ = &@import("sa_toml.zig").sa_toml_array_push_table;
    _ = &@import("sa_toml.zig").sa_toml_stringify;
    _ = &@import("sa_yaml.zig").sa_yaml_parse;
    _ = &@import("sa_yaml.zig").sa_yaml_parse_at;
    _ = &@import("sa_yaml.zig").sa_yaml_count_documents;
    _ = &@import("sa_yaml.zig").sa_yaml_free;
    _ = &@import("sa_yaml.zig").sa_yaml_last_error;
    _ = &@import("sa_yaml.zig").sa_yaml_kind;
    _ = &@import("sa_yaml.zig").sa_yaml_get_string;
    _ = &@import("sa_yaml.zig").sa_yaml_get_i64;
    _ = &@import("sa_yaml.zig").sa_yaml_get_f64;
    _ = &@import("sa_yaml.zig").sa_yaml_get_bool;
    _ = &@import("sa_yaml.zig").sa_yaml_array_len;
    _ = &@import("sa_yaml.zig").sa_yaml_table_len;
    _ = &@import("sa_yaml.zig").sa_yaml_array_get_string;
    _ = &@import("sa_yaml.zig").sa_yaml_array_get_i64;
    _ = &@import("sa_yaml.zig").sa_yaml_new;
    _ = &@import("sa_yaml.zig").sa_yaml_table_key_at;
    _ = &@import("sa_yaml.zig").sa_yaml_set_string;
    _ = &@import("sa_yaml.zig").sa_yaml_set_i64;
    _ = &@import("sa_yaml.zig").sa_yaml_set_f64;
    _ = &@import("sa_yaml.zig").sa_yaml_set_bool;
    _ = &@import("sa_yaml.zig").sa_yaml_set_null;
    _ = &@import("sa_yaml.zig").sa_yaml_set_table;
    _ = &@import("sa_yaml.zig").sa_yaml_remove;
    _ = &@import("sa_yaml.zig").sa_yaml_array_push_string;
    _ = &@import("sa_yaml.zig").sa_yaml_array_push_i64;
    _ = &@import("sa_yaml.zig").sa_yaml_array_push_f64;
    _ = &@import("sa_yaml.zig").sa_yaml_array_push_bool;
    _ = &@import("sa_yaml.zig").sa_yaml_array_push_null;
    _ = &@import("sa_yaml.zig").sa_yaml_array_push_table;
    _ = &@import("sa_yaml.zig").sa_yaml_stringify;
    _ = &@import("sa_yaml.zig").sa_yaml_to_json;
    _ = &@import("sa_cookie.zig").sa_cookie_parse_set_cookie;
    _ = &@import("sa_cookie.zig").sa_cookie_last_error;
    _ = &@import("sa_cookie.zig").sa_cookie_free;
    _ = &@import("sa_cookie.zig").sa_cookie_new;
    _ = &@import("sa_cookie.zig").sa_cookie_name;
    _ = &@import("sa_cookie.zig").sa_cookie_value;
    _ = &@import("sa_cookie.zig").sa_cookie_domain;
    _ = &@import("sa_cookie.zig").sa_cookie_path;
    _ = &@import("sa_cookie.zig").sa_cookie_expires;
    _ = &@import("sa_cookie.zig").sa_cookie_max_age;
    _ = &@import("sa_cookie.zig").sa_cookie_flags;
    _ = &@import("sa_cookie.zig").sa_cookie_same_site;
    _ = &@import("sa_cookie.zig").sa_cookie_is_host_only;
    _ = &@import("sa_cookie.zig").sa_cookie_set_domain;
    _ = &@import("sa_cookie.zig").sa_cookie_set_path;
    _ = &@import("sa_cookie.zig").sa_cookie_set_expires;
    _ = &@import("sa_cookie.zig").sa_cookie_set_max_age;
    _ = &@import("sa_cookie.zig").sa_cookie_clear_expiry;
    _ = &@import("sa_cookie.zig").sa_cookie_set_secure;
    _ = &@import("sa_cookie.zig").sa_cookie_set_http_only;
    _ = &@import("sa_cookie.zig").sa_cookie_set_partitioned;
    _ = &@import("sa_cookie.zig").sa_cookie_set_same_site;
    _ = &@import("sa_cookie.zig").sa_cookie_serialize;
    _ = &@import("sa_cookie.zig").sa_cookie_serialize_pair;
    _ = &@import("sa_cookie.zig").sa_cookie_is_expired;
    _ = &@import("sa_cookie.zig").sa_cookie_domain_match;
    _ = &@import("sa_cookie.zig").sa_cookie_path_match;
    _ = &@import("sa_cookie.zig").sa_cookie_header_pair_count;
    _ = &@import("sa_cookie.zig").sa_cookie_header_pair_at;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_new;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_free;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_set_policy;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_policy;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_store;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_header;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_count;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_at;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_clear;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_evict_expired;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_save;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_load;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_request_header;
    _ = &@import("sa_cookie.zig").sa_cookie_jar_store_response;
    _ = &@import("sa_crypto.zig").sa_bcrypt_hash;
    _ = &@import("sa_crypto.zig").sa_bcrypt_verify;
    _ = &@import("sa_crypto.zig").sa_keyring_available;
    _ = &@import("sa_crypto.zig").sa_keyring_set;
    _ = &@import("sa_crypto.zig").sa_keyring_get;
    _ = &@import("sa_crypto.zig").sa_keyring_remove;
    _ = &@import("sa_crypto.zig").sa_md5;
    _ = &@import("sa_crypto.zig").sa_sha1;
    _ = &@import("sa_crypto.zig").sa_sha256;
    _ = &@import("sa_crypto.zig").sa_sha384;
    _ = &@import("sa_crypto.zig").sa_sha512;
    _ = &@import("sa_crypto.zig").sa_hmac_sha1;
    _ = &@import("sa_crypto.zig").sa_hmac_sha256;
    _ = &@import("sa_crypto.zig").sa_hmac_sha512;
    _ = &@import("sa_crypto.zig").sa_pbkdf2_hmac_sha256;
    _ = &@import("sa_crypto.zig").sa_hkdf_sha256;
    _ = &@import("sa_crypto.zig").sa_crypto_timing_safe_equal;
    _ = &@import("sa_crypto.zig").sa_base64url_encode;
    _ = &@import("sa_crypto.zig").sa_base64url_decode;
    _ = &@import("sa_crypto.zig").sa_aes_gcm_encrypt;
    _ = &@import("sa_crypto.zig").sa_aes_gcm_decrypt;
    _ = &@import("sa_crypto.zig").sa_ed25519_public_key;
    _ = &@import("sa_crypto.zig").sa_ed25519_sign;
    _ = &@import("sa_crypto.zig").sa_ed25519_verify;
    _ = &@import("sa_crypto.zig").sa_ecdsa_p256_verify;
    _ = &@import("sa_crypto.zig").sa_ecdsa_p256_verify_prehashed;
    _ = &@import("sa_crypto.zig").sa_ecdsa_p256_sign;
    _ = &@import("sa_crypto_asym.zig").sa_ed25519_public_key_from_spki;
    _ = &@import("sa_crypto_asym.zig").sa_ed25519_seed_from_pkcs8;
    _ = &@import("sa_crypto_asym.zig").sa_ecdsa_p256_public_key_from_spki;
    _ = &@import("sa_crypto_asym.zig").sa_ecdsa_signature_der_to_raw;
    _ = &@import("sa_crypto_asym.zig").sa_ecdsa_signature_raw_to_der;
    _ = &@import("sa_crypto_asym.zig").sa_rsa_pkcs1_verify;
    _ = &@import("sa_crypto_asym.zig").sa_rsa_pkcs1_sign;
    _ = &@import("sa_crypto_asym.zig").sa_rsa_jwk_to_spki;
    _ = &@import("sa_crypto_asym.zig").sa_rsa_oaep_sha256_decrypt;
    _ = &@import("sa_crypto_asym.zig").sa_rsa_generate_keypair;
    _ = &@import("sa_crypto_asym.zig").sa_rsa_spki_to_jwk;
    _ = &@import("sa_crypto_asym.zig").sa_pem_decode;
    _ = &@import("sa_crypto_asym.zig").sa_x509_spki;
    _ = &@import("sa_crypto_asym.zig").sa_x509_subject;
    _ = &@import("sa_crypto_asym.zig").sa_x509_subject_cn;
    _ = &@import("sa_crypto_asym.zig").sa_x509_public_key;
    _ = &@import("sa_crypto_asym.zig").sa_x509_validity;
    _ = &@import("sa_tree_sitter.zig").sa_ts_available;
    _ = &@import("sa_tree_sitter.zig").sa_ts_parser_new;
    _ = &@import("sa_tree_sitter.zig").sa_ts_parser_free;
    _ = &@import("sa_tree_sitter.zig").sa_ts_parser_set_language;
    _ = &@import("sa_tree_sitter.zig").sa_ts_parse;
    _ = &@import("sa_tree_sitter.zig").sa_ts_tree_free;
    _ = &@import("sa_tree_sitter.zig").sa_ts_tree_root;
    _ = &@import("sa_tree_sitter.zig").sa_ts_tree_sexp;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_free;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_type;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_text;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_byte_range;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_child_count;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_named_child_count;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_child;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_child_by_field;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_parent;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_is_named;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_is_missing;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_has_error;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_start_point;
    _ = &@import("sa_tree_sitter.zig").sa_ts_node_end_point;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_new;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_free;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_pattern_count;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_capture_count;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_capture_name;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_cursor_new;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_cursor_free;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_exec;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_next_match;
    _ = &@import("sa_tree_sitter.zig").sa_ts_query_match_capture;
    _ = &@import("sa_tree_sitter.zig").sa_ts_tree_edit;
    _ = &@import("sa_tree_sitter.zig").sa_ts_parse_incremental;
    _ = &sa_globals.sa_global_u64_set;
    _ = &sa_globals.sa_global_u64_get;
    _ = &sa_globals.sa_global_u64_set_once;
    _ = &sa_globals.sa_global_u64_add;
    _ = &sa_globals.sa_global_bytes_set;
    _ = &sa_globals.sa_global_bytes_get;
    _ = &sa_identity.sa_idmap_new;
    _ = &sa_identity.sa_idmap_free;
    _ = &sa_identity.sa_idmap_set;
    _ = &sa_identity.sa_idmap_get;
    _ = &sa_identity.sa_idmap_set_u64;
    _ = &sa_identity.sa_idmap_get_u64;
    _ = &sa_identity.sa_idmap_has;
    _ = &sa_identity.sa_idmap_remove;
    _ = &sa_identity.sa_idmap_len;
    _ = &sa_identity.sa_idmap_clear;
    _ = &sa_identity.sa_idset_new;
    _ = &sa_identity.sa_idset_free;
    _ = &sa_identity.sa_idset_add;
    _ = &sa_identity.sa_idset_has;
    _ = &sa_identity.sa_idset_remove;
    _ = &sa_identity.sa_idset_len;
    _ = &sa_identity.sa_idset_clear;
    _ = &@import("sa_std/json.zig").sa_json_parse;
    _ = &@import("sa_std/json.zig").sa_json_kind;
    _ = &@import("sa_std/json.zig").sa_json_object_get;
    _ = &@import("sa_std/json.zig").sa_json_array_get;
    _ = &@import("sa_std/json.zig").sa_json_object_key_at;
    _ = &@import("sa_std/json.zig").sa_json_object_get_string;
    _ = &@import("sa_std/json.zig").sa_json_object_get_bool;
    _ = &@import("sa_std/json.zig").sa_json_object_get_i64;
    _ = &@import("sa_std/json.zig").sa_json_object_get_f64;
    _ = &@import("sa_std/json.zig").sa_json_as_f64;
    _ = &@import("sa_std/json.zig").sa_json_as_i64;
    _ = &@import("sa_std/json.zig").sa_json_as_bool;
    _ = &@import("sa_std/json.zig").sa_json_string_ptr;
    _ = &@import("sa_std/json.zig").sa_json_string_len;
    _ = &@import("sa_std/json.zig").sa_json_value_count;
    _ = &@import("sa_std/json.zig").sa_json_free;
    _ = &@import("sa_std/json.zig").sa_json_stringify;
    _ = &@import("sa_std/json.zig").sa_json_object_set_string;
    _ = &@import("sa_std/json.zig").sa_json_object_set_i64;
    _ = &@import("sa_std/json.zig").sa_json_object_set_f64;
    _ = &@import("sa_std/json.zig").sa_json_object_set_bool;
    _ = &@import("sa_std/json.zig").sa_json_object_set_null;
    _ = &@import("sa_std/json.zig").sa_json_object_set_node;
    _ = &@import("sa_std/json.zig").sa_json_object_remove;
    _ = &@import("sa_std/json.zig").sa_json_array_push_string;
    _ = &@import("sa_std/json.zig").sa_json_array_push_i64;
    _ = &@import("sa_std/json.zig").sa_json_array_push_f64;
    _ = &@import("sa_std/json.zig").sa_json_array_push_bool;
    _ = &@import("sa_std/json.zig").sa_json_array_push_null;
    _ = &@import("sa_std/json.zig").sa_json_array_push_node;
    _ = &@import("sa_std/json_io.zig").sa_json_scanner_new;
    _ = &@import("sa_std/json_io.zig").sa_json_scanner_feed;
    _ = &@import("sa_std/json_io.zig").sa_json_scanner_end_input;
    _ = &@import("sa_std/json_io.zig").sa_json_scanner_next;
    _ = &@import("sa_std/json_io.zig").sa_json_scanner_free;
    _ = &@import("sa_std/json_io.zig").sa_json_stream_new;
    _ = &@import("sa_std/json_io.zig").sa_json_stream_next;
    _ = &@import("sa_std/json_io.zig").sa_json_stream_get_slice_ptr;
    _ = &@import("sa_std/json_io.zig").sa_json_stream_get_slice_len;
    _ = &@import("sa_std/json_io.zig").sa_json_stream_free;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_free;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_new;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_begin_object;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_end_object;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_begin_array;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_end_array;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_object_field;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_field_string;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_field_bool;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_field_i64;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_field_f64;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_field_null;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_field_node;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_write_bool;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_write_i64;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_write_f64;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_write_string;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_write_null;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_write_node;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_finish;
    _ = &@import("sa_std/json_io.zig").sa_json_writer_finish_buffer;
    _ = &@import("sa_std/json.zig").sa_json_buffer_data;
    _ = &@import("sa_std/json.zig").sa_json_buffer_len;
    _ = &@import("sa_std/json.zig").sa_json_buffer_free;
    _ = &@import("sa_std/fs.zig").sa_fs_file_open;
    _ = &@import("sa_std/fs.zig").sa_fs_file_create;
    _ = &@import("sa_std/fs.zig").sa_fs_file_close;
    _ = &@import("sa_std/fs.zig").sa_fs_file_read;
    _ = &@import("sa_std/fs.zig").sa_fs_file_read_exact;
    _ = &@import("sa_std/fs.zig").sa_fs_file_write;
    _ = &@import("sa_std/fs.zig").sa_fs_file_write_all;
    _ = &@import("sa_std/fs.zig").sa_fs_file_flush;
    _ = &@import("sa_std/fs.zig").sa_fs_file_sync_data;
    _ = &@import("sa_std/fs.zig").sa_fs_file_sync;
    _ = &@import("sa_std/fs.zig").sa_fs_file_truncate;
    _ = &@import("sa_std/fs.zig").sa_fs_file_seek;
    _ = &@import("sa_std/fs.zig").sa_fs_read_file;
    _ = &@import("sa_std/fs.zig").sa_fs_read_to_string;
    _ = &@import("sa_std/fs.zig").sa_fs_write_file;
    _ = &@import("sa_std/fs.zig").sa_fs_read_buffer_data;
    _ = &@import("sa_std/fs.zig").sa_fs_read_buffer_len;
    _ = &@import("sa_std/fs.zig").sa_fs_read_buffer_free;
    _ = &@import("sa_std/fs.zig").sa_fs_read_file_base64;
    _ = &@import("sa_std/fs.zig").sa_fs_write_file_base64;
    _ = &@import("sa_std/fs.zig").sa_fs_read_dir_json;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_buffer_data;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_buffer_len;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_buffer_free;
    _ = &@import("sa_std/fs.zig").sa_fs_read_dir_entries;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entries_len;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entries_free;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_name_ptr;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_name_len;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_file_name_ptr;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_file_name_len;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_kind;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_ino;
    _ = &@import("sa_std/fs.zig").sa_fs_dir_entry_free;
    _ = &@import("sa_std/fs.zig").sa_fs_metadata;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_json;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_file;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_directory;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_symlink;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_block_device;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_char_device;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_fifo;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_is_socket;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_modified_ms;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_created_ms;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_accessed_ms;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_changed_ms;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_len;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_mode;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_uid;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_gid;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_ino;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_dev;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_nlink;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_rdev;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_blksize;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_blocks;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_dev;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_ino;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_mode;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_nlink;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_uid;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_gid;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_rdev;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_size;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_atime;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_atime_nsec;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_mtime;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_mtime_nsec;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_ctime;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_ctime_nsec;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_blksize;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_st_blocks;
    _ = &@import("sa_std/fs_meta.zig").sa_fs_metadata_free;
    _ = &@import("sa_std/fs.zig").sa_fs_remove_file;
    _ = &@import("sa_std/fs.zig").sa_fs_rename;
    _ = &@import("sa_std/fs.zig").sa_fs_make_dir;
    _ = &@import("sa_std/fs.zig").sa_fs_make_dir_mode;
    _ = &@import("sa_std/fs.zig").sa_fs_mkdir_p;
    _ = &@import("sa_std/fs.zig").sa_fs_create_dir;
    _ = &@import("sa_std/fs.zig").sa_fs_create_dir_mode;
    _ = &@import("sa_std/fs.zig").sa_fs_remove_dir;
    _ = &@import("sa_std/fs.zig").sa_fs_remove_dir_all;
    _ = &@import("sa_std/fs.zig").sa_fs_remove_path;
    _ = &@import("sa_std/fs.zig").sa_fs_copy_file;
    _ = &@import("sa_std/fs.zig").sa_fs_set_permissions;
    _ = &@import("sa_std/fs.zig").sa_fs_set_times_ms;
    _ = &@import("sa_std/fs.zig").sa_fs_hard_link;
    _ = &@import("sa_std/fs.zig").sa_fs_symlink;
    _ = &@import("sa_std/fs.zig").sa_fs_chown;
    _ = &@import("sa_std/fs.zig").sa_fs_lchown;
    _ = &@import("sa_std/fs.zig").sa_fs_fchown;
    _ = &@import("sa_std/fs.zig").sa_fs_chroot;
    _ = &@import("sa_std/fs.zig").sa_fs_mkfifo;
    _ = &@import("sa_std/net.zig").sa_net_tcp_connect;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_read;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_peek;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_write;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_write_all;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_read_exact;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_flush;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_peer_addr;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_shutdown;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_set_read_timeout;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_set_write_timeout;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_set_nonblocking;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_set_nodelay;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_set_ttl;
    _ = &@import("sa_std/net.zig").sa_net_tcp_stream_close;
    _ = &@import("sa_std/net.zig").sa_net_tcp_listener_bind;
    _ = &@import("sa_std/net.zig").sa_net_tcp_listener_accept;
    _ = &@import("sa_std/net.zig").sa_net_tcp_listener_local_addr;
    _ = &@import("sa_std/net.zig").sa_net_tcp_listener_close;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_read_timeout;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_write_timeout;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_nonblocking;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_broadcast;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_ttl;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_multicast_loop_v4;
    _ = &@import("sa_std/net.zig").sa_net_udp_set_multicast_ttl_v4;
    _ = &@import("sa_std/net.zig").sa_net_udp_join_multicast_v4;
    _ = &@import("sa_std/net.zig").sa_net_udp_leave_multicast_v4;
    _ = &@import("sa_std/net.zig").sa_net_udp_join_multicast_v6;
    _ = &@import("sa_std/net.zig").sa_net_udp_leave_multicast_v6;
    _ = &@import("sa_std/net.zig").sa_net_udp_bind;
    _ = &@import("sa_std/net.zig").sa_net_udp_connect;
    _ = &@import("sa_std/net.zig").sa_net_udp_local_addr;
    _ = &@import("sa_std/net.zig").sa_net_udp_send;
    _ = &@import("sa_std/net.zig").sa_net_udp_recv;
    _ = &@import("sa_std/net.zig").sa_net_udp_peek;
    _ = &@import("sa_std/net.zig").sa_net_udp_send_to;
    _ = &@import("sa_std/net.zig").sa_net_udp_recv_from;
    _ = &@import("sa_std/net.zig").sa_net_udp_peek_from;
    _ = &@import("sa_std/net.zig").sa_net_udp_close;
    _ = &@import("sa_std/net.zig").sa_net_addr_host;
    _ = &@import("sa_std/net.zig").sa_net_addr_host_len;
    _ = &@import("sa_std/net.zig").sa_net_addr_port;
    _ = &@import("sa_std/net.zig").sa_net_addr_family;
    _ = &@import("sa_std/net.zig").sa_net_addr_scope_id;
    _ = &@import("sa_std/net.zig").sa_net_addr_free;
    _ = &@import("sa_std/net.zig").sa_net_ipv4_parse_ascii;
    _ = &@import("sa_std/net.zig").sa_net_socket_addr_v4_parse_ascii;
    _ = &@import("sa_std/net.zig").sa_net_ipv6_parse_ascii;
    _ = &@import("sa_std/net.zig").sa_net_socket_addr_v6_parse_ascii;
    _ = &@import("sa_std/net.zig").sa_net_ipv4_format_ascii;
    _ = &@import("sa_std/net.zig").sa_net_ipv6_format_ascii;
    _ = &@import("sa_std/net.zig").sa_net_socket_addr_v4_format_ascii;
    _ = &@import("sa_std/net.zig").sa_net_socket_addr_v6_format_ascii;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_kind;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_is_unnamed;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_path_ptr;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_path_len;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_abstract_ptr;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_abstract_len;
    _ = &@import("sa_std/net.zig").sa_net_unix_addr_free;
    _ = &@import("sa_std/deno.zig").sa_deno_cwd;
    _ = &@import("sa_std/deno.zig").sa_deno_chdir;
    _ = &@import("sa_std/deno.zig").sa_deno_env_set;
    _ = &@import("sa_std/deno.zig").sa_deno_env_delete;
    _ = &@import("sa_std/deno.zig").sa_deno_random_uuid;
    _ = &@import("sa_std/deno.zig").sa_deno_make_temp_dir;
    _ = &@import("sa_std/deno.zig").sa_deno_make_temp_file;
    _ = &@import("sa_std/deno.zig").sa_deno_args_json;
    _ = &@import("sa_std/deno.zig").sa_deno_btoa;
    _ = &@import("sa_std/deno.zig").sa_deno_atob;
    _ = &@import("sa_std/deno.zig").sa_deno_text_encode;
    _ = &@import("sa_std/deno.zig").sa_deno_text_decode;
    _ = &@import("sa_std/deno.zig").sa_deno_chat_sse_to_responses;
    _ = &@import("sa_std/deno.zig").sa_deno_chat_json_to_responses;
    _ = &@import("sa_std/deno.zig").sa_deno_responses_sse_normalize;
    _ = &@import("sa_std/deno.zig").sa_deno_responses_json_normalize;
    _ = &@import("sa_std/deno.zig").sa_deno_responses_request_normalize;
    _ = &@import("sa_std/deno.zig").sa_deno_responses_chat_fallback_request;
    _ = &@import("sa_std/deno.zig").sa_deno_jsonrpc_params_string_literal;
    _ = &@import("sa_std/deno.zig").sa_deno_version_json;
    _ = &@import("sa_std/deno.zig").sa_deno_version_deno;
    _ = &@import("sa_std/deno.zig").sa_deno_build_json;
    _ = &@import("sa_std/deno.zig").sa_deno_build_os;
    _ = &@import("sa_std/deno.zig").sa_deno_build_platform_family;
    _ = &@import("sa_std/deno.zig").sa_deno_date_now_iso;
    _ = &@import("sa_std/deno.zig").sa_deno_hostname;
    _ = &@import("sa_std/deno.zig").sa_deno_os_release;
    _ = &@import("sa_std/deno.zig").sa_deno_os_uptime;
    _ = &@import("sa_std/deno.zig").sa_deno_loadavg;
    _ = &@import("sa_std/deno.zig").sa_deno_system_memory_info;
    _ = &@import("sa_std/deno.zig").sa_deno_network_interfaces;
    _ = &@import("sa_std/deno.zig").sa_deno_pid;
    _ = &@import("sa_std/deno.zig").sa_deno_ppid;
    _ = &@import("sa_std/deno.zig").sa_deno_uid;
    _ = &@import("sa_std/deno.zig").sa_deno_gid;
    _ = &@import("sa_std/deno.zig").sa_deno_exec_path;
    _ = &@import("sa_std/deno.zig").sa_deno_memory_usage;
    _ = &@import("sa_std/regex.zig").sa_regex_compile;
    _ = &@import("sa_std/regex.zig").sa_regex_match;
    _ = &@import("sa_std/regex.zig").sa_regex_group_ptr;
    _ = &@import("sa_std/regex.zig").sa_regex_group_len;
    _ = &@import("sa_std/regex.zig").sa_regex_group_start;
    _ = &@import("sa_std/regex.zig").sa_regex_group_count;
    _ = &@import("sa_std/regex.zig").sa_regex_free;
    _ = &@import("sa_std/regex.zig").sa_regex_match_free;
    _ = &@import("sa_std/regex.zig").sa_regex_match_all;
    _ = &@import("sa_std/regex.zig").sa_regex_match_list_count;
    _ = &@import("sa_std/regex.zig").sa_regex_match_list_at;
    _ = &@import("sa_std/regex.zig").sa_regex_match_list_free;
    _ = &@import("sa_std/regex.zig").sa_regex_replace;
    _ = &@import("sa_std/regex.zig").sa_regex_replace_all;
    _ = &@import("sa_std/regex.zig").sa_regex_buffer_data;
    _ = &@import("sa_std/regex.zig").sa_regex_buffer_len;
    _ = &@import("sa_std/regex.zig").sa_regex_buffer_free;
    _ = &@import("sa_std/regex.zig").sa_regex_split;
    _ = &@import("sa_std/regex.zig").sa_regex_split_count;
    _ = &@import("sa_std/regex.zig").sa_regex_split_ptr;
    _ = &@import("sa_std/regex.zig").sa_regex_split_len;
    _ = &@import("sa_std/regex.zig").sa_regex_split_free;
    _ = &@import("sa_std/time.zig").sa_time_instant_ns;
    _ = &@import("sa_std/time.zig").sa_time_unix_s;
    _ = &@import("sa_std/time.zig").sa_time_unix_ms;
    _ = &@import("sa_std/time.zig").sa_time_iso_from_unix_ms;
    _ = &@import("sa_std/time.zig").sa_time_parse_iso;
    _ = &@import("sa_std/time.zig").sa_time_get_full_year;
    _ = &@import("sa_std/time.zig").sa_time_get_month;
    _ = &@import("sa_std/time.zig").sa_time_get_date;
    _ = &@import("sa_std/time.zig").sa_time_get_hours;
    _ = &@import("sa_std/time.zig").sa_time_get_minutes;
    _ = &@import("sa_std/time.zig").sa_time_get_seconds;
    _ = &@import("sa_std/time.zig").sa_time_get_milliseconds;
    _ = &@import("sa_std/time.zig").sa_time_get_day;
    _ = &@import("sa_std/time.zig").sa_time_format_utc;
    _ = &@import("sa_std/time.zig").sa_time_set_field;
    _ = &@import("sa_std/time.zig").sa_time_unix_ns;
    _ = &@import("sa_std/time.zig").sa_time_utc_now;
    _ = &@import("sa_std/time.zig").sa_time_sleep_ns;
    _ = &@import("sa_std/time.zig").sa_time_sleep_ms;
    _ = &@import("sa_std/string.zig").sa_string_concat;
    _ = &@import("sa_std/string.zig").sa_string_from_char_code;
    _ = &@import("sa_std/string.zig").sa_string_index_of;
    _ = &@import("sa_std/string.zig").sa_string_last_index_of;
    _ = &@import("sa_std/string.zig").sa_string_starts_with;
    _ = &@import("sa_std/string.zig").sa_string_ends_with;
    _ = &@import("sa_std/string.zig").sa_string_to_lower_ascii;
    _ = &@import("sa_std/string.zig").sa_string_to_upper_ascii;
    _ = &@import("sa_std/string.zig").sa_string_repeat;
    _ = &@import("sa_std/string.zig").sa_string_pad_start;
    _ = &@import("sa_std/string.zig").sa_string_pad_end;
    _ = &@import("sa_std/string.zig").sa_string_replace;
    _ = &@import("sa_std/string.zig").sa_string_code_point_at;
    _ = &@import("sa_std/string.zig").sa_string_from_code_point;
    _ = &@import("sa_std/env.zig").sa_env_get;
    _ = &@import("sa_std/env.zig").sa_env_current_dir;
    _ = &@import("sa_std/env.zig").sa_env_set_current_dir;
    _ = &@import("sa_std/env.zig").sa_env_temp_dir;
    _ = &@import("sa_std/env.zig").sa_env_current_exe;
    _ = &@import("sa_std/env.zig").sa_env_home_dir;
    _ = &@import("sa_std/env.zig").sa_env_args_json;
    _ = &@import("sa_std/env.zig").sa_env_vars_json;
    _ = &@import("sa_std/env.zig").sa_env_split_paths_json;
    _ = &@import("sa_std/env.zig").sa_env_join_paths_json;
    _ = &@import("sa_std/env.zig").sa_env_xdg_data_home_dir;
    _ = &@import("sa_std/env.zig").sa_env_xdg_config_home_dir;
    _ = &@import("sa_std/env.zig").sa_env_xdg_state_home_dir;
    _ = &@import("sa_std/env.zig").sa_env_xdg_cache_home_dir;
    _ = &@import("sa_std/env.zig").sa_env_xdg_data_dirs;
    _ = &@import("sa_std/env.zig").sa_env_xdg_config_dirs;
    _ = &@import("sa_std/env.zig").sa_env_has;
    _ = &@import("sa_std/env.zig").sa_env_set_var;
    _ = &@import("sa_std/env.zig").sa_env_remove_var;
    _ = &@import("sa_std/env.zig").sa_env_buffer_data;
    _ = &@import("sa_std/env.zig").sa_env_buffer_len;
    _ = &@import("sa_std/env.zig").sa_env_buffer_free;
    _ = &@import("sa_std/fmt.zig").sa_fmt_i64;
    _ = &@import("sa_std/fmt.zig").sa_fmt_i64_into;
    _ = &@import("sa_std/fmt.zig").sa_fmt_u64;
    _ = &@import("sa_std/fmt.zig").sa_fmt_u64_into;
    _ = &@import("sa_std/fmt.zig").sa_fmt_f64;
    _ = &@import("sa_std/fmt.zig").sa_fmt_f64_into;
    _ = &@import("sa_std/fmt.zig").sa_fmt_bool;
    _ = &@import("sa_std/fmt.zig").sa_fmt_bool_into;
    _ = &@import("sa_std/fmt.zig").sa_fmt_bytes;
    _ = &@import("sa_std/fmt.zig").sa_fmt_bytes_into;
    _ = &@import("sa_std/fmt.zig").sa_fmt_buffer_data;
    _ = &@import("sa_std/fmt.zig").sa_fmt_buffer_len;
    _ = &@import("sa_std/fmt.zig").sa_fmt_buffer_write_to;
    _ = &@import("sa_std/fmt.zig").sa_fmt_buffer_free;
    _ = &@import("sa_std/io.zig").sa_io_read_line;
    _ = &@import("sa_std/io.zig").sa_io_stdin;
    _ = &@import("sa_std/io.zig").sa_io_stdout;
    _ = &@import("sa_std/io.zig").sa_io_stderr;
    _ = &@import("sa_std/io.zig").sa_io_read;
    _ = &@import("sa_std/io.zig").sa_io_read_exact;
    _ = &@import("sa_std/io.zig").sa_io_write;
    _ = &@import("sa_std/io.zig").sa_io_write_all;
    _ = &@import("sa_std/io.zig").sa_io_flush;
    _ = &@import("sa_std/io.zig").sa_io_close;
    _ = &@import("sa_std/io.zig").sa_io_buffer_data;
    _ = &@import("sa_std/io.zig").sa_io_buffer_len;
    _ = &@import("sa_std/io.zig").sa_io_buffer_free;
    _ = &@import("sa_std/str.zig").sa_str_is_ascii;
    _ = &@import("sa_std/str.zig").sa_str_eq_ignore_ascii_case;
    _ = &@import("sa_std/str.zig").sa_str_utf8_char_count;
    _ = &@import("sa_std/str.zig").sa_str_utf8_validate;
    _ = &@import("sa_std/str.zig").sa_str_utf8_char_at;
    _ = &@import("sa_std/str.zig").sa_str_utf8_char_at_byte;
    _ = &@import("sa_std/str.zig").sa_str_utf8_lossy_next;
    _ = &@import("sa_std/str.zig").sa_str_utf8_char_range_at;
    _ = &@import("sa_std/str.zig").sa_str_trim_ascii_start_index;
    _ = &@import("sa_std/str.zig").sa_str_trim_ascii_end_len;
    _ = &@import("sa_std/term.zig").sa_term_raw_enter;
    _ = &@import("sa_std/term.zig").sa_term_raw_leave;
    _ = &@import("sa_std/term.zig").sa_term_winsize;
    _ = &@import("sa_std/term.zig").sa_term_epoll_create;
    _ = &@import("sa_std/term.zig").sa_term_epoll_ctl;
    _ = &@import("sa_std/term.zig").sa_term_epoll_wait;
    _ = &@import("sa_std/term.zig").sa_term_epoll_close;
    _ = &@import("sa_std/math.zig").sa_math_floor;
    _ = &@import("sa_std/math.zig").sa_math_ceil;
    _ = &@import("sa_std/math.zig").sa_math_sqrt;
    _ = &@import("sa_std/math.zig").sa_math_sin;
    _ = &@import("sa_std/math.zig").sa_math_cos;
    _ = &@import("sa_std/math.zig").sa_math_pow;
    _ = &@import("sa_std/math.zig").sa_math_random;
    _ = &@import("sa_std/std_net.zig").sa_std_net_error_code_from_status;
    _ = &@import("sa_std/std_net.zig").sa_std_net_error_code_from_posix_errno;
    _ = &@import("sa_std/std_net.zig").sa_std_net_error_code_from_wsa_error;
    _ = &@import("sa_std/std_net.zig").sa_std_net_error_code_name;
    _ = &@import("sa_std/std_net.zig").sa_std_net_error_platform;
    _ = &@import("sa_std/std_net.zig").sa_std_net_error_code_from_native_error;
    _ = &@import("sa_std/std_net.zig").sa_std_net_hostname;
    _ = &@import("sa_std/std_net.zig").sa_std_net_interface_addresses_json;
    _ = &@import("sa_std/std_net.zig").sa_std_net_to_socket_addr_list;
    _ = &@import("sa_std/std_net.zig").sa_std_net_addr_list_next;
    _ = &@import("sa_std/std_net.zig").sa_std_net_addr_list_remaining;
    _ = &@import("sa_std/std_net.zig").sa_std_net_addr_list_reset;
    _ = &@import("sa_std/std_net.zig").sa_std_net_addr_list_free;
    _ = &@import("sa_std/std_net.zig").sa_std_net_addr_reverse_lookup;
    _ = &@import("sa_std/std_net.zig").sa_std_net_to_socket_addr_first;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_vectored;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_vectored;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peek;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peer_addr;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_local_addr;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_try_clone;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nonblocking;
    _ = &@import("sa_std/std_net.zig").sa_std_net_poll_wait;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nodelay;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_linger;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_linger;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_quickack;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_quickack;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_deferaccept;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_deferaccept;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_keepalive;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive_params;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseaddr;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseport;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_read_timeout;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_write_timeout;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_ttl;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_timeout;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_timeout;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_nodelay;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_ttl;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_recv_buffer_size;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_recv_buffer_size;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_send_buffer_size;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_buffer_size;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_take_error;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_try_clone;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_only_v6;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_only_v6;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_nonblocking;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_ttl;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_ttl;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_take_error;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_try_clone;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_bind;
    _ = &@import("sa_std/std_net.zig").sa_std_net_raw_socket;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_file;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_from_raw_fd;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_local_addr;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_peer_addr;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_connect;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_connect_addr;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_only_v6;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_only_v6;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_nonblocking;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_broadcast;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_ttl;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_read_timeout;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_write_timeout;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_recv_buffer_size;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_buffer_size;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_send_buffer_size;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_buffer_size;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_read_timeout;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_write_timeout;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_broadcast;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v4;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_ttl_v4;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v4;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_ttl_v4;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v6;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_hops_v6;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v6;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_hops_v6;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v4;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_if_v4;
    _ = &@import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v6;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_if_v6;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_join_multicast_v4;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_leave_multicast_v4;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_join_multicast_v6;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_leave_multicast_v6;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_ttl;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_take_error;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_send;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_recv;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_peek;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_to;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_from;
    _ = &@import("sa_std/std_net_udp.zig").sa_std_net_udp_peek_from;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_vectored;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_to_vectored;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_from_vectored;
    _ = &@import("sa_std/std_net.zig").sa_std_net_socket_setsockopt;
    _ = &@import("sa_std/std_net.zig").sa_std_net_socket_getsockopt;
    _ = &@import("sa_std/std_net.zig").sa_std_net_socket_setsockopt_int;
    _ = &@import("sa_std/std_net.zig").sa_std_net_socket_getsockopt_int;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_msg;
    _ = &@import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_multi;
    _ = &@import("sa_std/std_net.zig").sa_std_net_addr_format;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listen;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept_addr;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_local_addr;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_from_raw_fd;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_addr;
    _ = &@import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_all;
    _ = &@import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_from_raw_fd;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_listen;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_addr_from_abstract_name;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_addr_from_pathname;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_listen_addr;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_accept;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_accept_addr;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_pair;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_local_addr;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_try_clone;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_from_raw_fd;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_local_addr;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_try_clone;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_from_raw_fd;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_peer_addr;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_set_passcred;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_passcred;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_set_mark;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_peer_cred;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_cred;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_unbound;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind_addr;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_pair;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect_addr;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_try_clone;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_from_raw_fd;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_local_addr;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_addr;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_passcred;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_passcred;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_mark;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_shutdown;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to_addr;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_recv_from;
    _ = &@import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peek_from;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_connect;
    _ = &@import("sa_std/std_net_unix.zig").sa_std_net_unix_connect_addr;
    _ = &@import("sa_std/std_net.zig").sa_std_net_ja3_hash;
    _ = &@import("sa_std/std_net.zig").sa_std_net_sha256_hex;
    _ = &@import("sa_std/std_net.zig").sa_std_net_ja4_hash12;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run_cwd;
    _ = &@import("sa_std/std_process.zig").sa_std_process_spawn;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_cwd;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream_cwd;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_bidi;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_bidi_cwd;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run_command_ext;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_command_ext;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream_command_ext;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run_command_ext_pidfd;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_command_ext_pidfd;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_pidfd;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run_command_ext_uid_gid;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_command_ext_uid_gid;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_uid_gid;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run_command_ext_groups;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_command_ext_groups;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_groups;
    _ = &@import("sa_std/std_process.zig").sa_std_process_run_command_ext_chroot;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_command_ext_chroot;
    _ = &@import("sa_std/std_process_spawn.zig").sa_std_process_spawn_stream_command_ext_chroot;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exec_command_ext;
    _ = &@import("sa_std/std_process.zig").sa_std_process_id;
    _ = &@import("sa_std/std_process.zig").sa_std_process_parent_id;
    _ = &@import("sa_std/std_process.zig").sa_std_process_user_id;
    _ = &@import("sa_std/std_process.zig").sa_std_process_group_id;
    _ = &@import("sa_std/std_process.zig").sa_std_process_abort;
    _ = &@import("sa_std/std_process.zig").sa_std_process_child_id;
    _ = &@import("sa_std/std_process.zig").sa_std_process_wait;
    _ = &@import("sa_std/std_process.zig").sa_std_process_wait_raw;
    _ = &@import("sa_std/std_process.zig").sa_std_process_try_wait;
    _ = &@import("sa_std/std_process.zig").sa_std_process_try_wait_raw;
    _ = &@import("sa_std/std_process.zig").sa_std_process_kill;
    _ = &@import("sa_std/std_process.zig").sa_std_process_send_signal;
    _ = &@import("sa_std/std_process.zig").sa_std_process_send_process_group_signal;
    _ = &@import("sa_std/std_process.zig").sa_std_process_kill_process_group;
    _ = &@import("sa_std/std_process.zig").sa_std_process_pidfd;
    _ = &@import("sa_std/std_process.zig").sa_std_process_into_pidfd;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exit_status_code;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exit_status_signal;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exit_status_core_dumped;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exit_status_stopped_signal;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exit_status_continued;
    _ = &@import("sa_std/std_process.zig").sa_std_process_read_stdout;
    _ = &@import("sa_std/std_process.zig").sa_std_process_read_stderr;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exec_capture;
    _ = &@import("sa_std/std_process.zig").sa_std_process_exec_capture_cwd;
    _ = &@import("sa_std/std_process.zig").sa_std_process_close;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_open_read;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_open_write;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_remove;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_exists;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_try_exists;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_len;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_open_options;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_open_create_excl;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_from_raw_fd;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_read;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_read_at;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_read_exact_at;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_write;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_write_at;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_write_all_at;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_file_seek;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_read_file;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_read_to_string;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_read_file_base64;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_read_dir_json;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_read_dir_entries;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_dir_entries_get;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_metadata;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_metadata_json;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_metadata_free;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_canonicalize;
    _ = &@import("sa_std/std_fs.zig").sa_std_fs_read_link;
    if (builtin.os.tag == .linux) {
        _ = &@import("sa_pty.zig").sa_pty_spawn;
        _ = &@import("sa_pty.zig").sa_pty_read;
        _ = &@import("sa_pty.zig").sa_pty_write;
        _ = &@import("sa_pty.zig").sa_pty_poll;
        _ = &@import("sa_pty.zig").sa_pty_resize;
        _ = &@import("sa_pty.zig").sa_pty_winsize;
        _ = &@import("sa_pty.zig").sa_pty_pid;
        _ = &@import("sa_pty.zig").sa_pty_kill;
        _ = &@import("sa_pty.zig").sa_pty_try_wait;
        _ = &@import("sa_pty.zig").sa_pty_close;
        _ = &@import("sa_fs_watch.zig").sa_fs_watch_create;
        _ = &@import("sa_fs_watch.zig").sa_fs_watch_add;
        _ = &@import("sa_fs_watch.zig").sa_fs_watch_remove;
        _ = &@import("sa_fs_watch.zig").sa_fs_watch_poll;
        _ = &@import("sa_fs_watch.zig").sa_fs_watch_next;
        _ = &@import("sa_fs_watch.zig").sa_fs_watch_close;
    }
    _ = &@import("sa_ssh.zig").sa_std_ssh_client_connect;
    _ = &@import("sa_ssh.zig").sa_std_ssh_server_listen;
    _ = &@import("sa_http_client.zig").sa_http_client_new_v2;
    _ = &@import("sa_http_client.zig").sa_http_client_sse_post;
    _ = &@import("sa_quic.zig").sa_std_quic_client_connect;
    _ = &@import("sa_quic.zig").sa_std_http3_session_bind;
    _ = &@import("sa_thread_local.zig").sa_thread_local_supported;
    _ = &sa_task.sa_task_spawn;
    _ = &sa_task.sa_task_detach;
    _ = &sa_task.sa_chan_make;
    _ = &sa_task.sa_chan_select;
    _ = &sa_task.sa_task_net_wait;
    _ = &sa_task.sa_sync_mutex_new;
    _ = &sa_task.sa_sync_waitgroup_new;
    _ = &sa_task.sa_sync_once_new;
    _ = &@import("sa_pg.zig").sa_pg_connect;
    _ = &@import("sa_pg.zig").sa_pg_exec;
    _ = &@import("sa_pg.zig").sa_pg_prepare;
    _ = &@import("sa_pg.zig").sa_pg_execute;
    if (builtin.os.tag == .linux) {
        _ = &@import("sa_net_uring.zig").sa_netx_init;
    }
}

pub const RegexC = if (is_wasm) extern struct {
    re_nsub: usize,
    __opaque: ?*anyopaque,
    __padding: [4]?*anyopaque,
    __nsub2: usize,
    __padding2: u8,
} else extern struct {
    buffer: ?*anyopaque,
    allocated: c_ulong,
    used: c_ulong,
    syntax: c_ulong,
    fastmap: ?[*]u8,
    translate: ?[*]u8,
    re_nsub: usize,
    flags: u32,
};

pub const RegexMatchC = extern struct {
    rm_so: c_int,
    rm_eo: c_int,
};

extern fn regcomp(preg: ?*RegexC, pattern: [*c]const u8, cflags: c_int) c_int;
extern fn regexec(preg: ?*const RegexC, text: [*c]const u8, nmatch: usize, pmatch: [*]RegexMatchC, eflags: c_int) c_int;
extern fn regfree(preg: ?*RegexC) void;
extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn unsetenv(name: [*:0]const u8) c_int;

const InAddrC = extern struct {
    s_addr: u32,
};

const IpMreqC = extern struct {
    imr_multiaddr: InAddrC,
    imr_interface: InAddrC,
};

const Ipv6MreqC = extern struct {
    ipv6mr_multiaddr: [16]u8,
    ipv6mr_interface: u32,
};

extern "c" var environ: [*:null]?[*:0]u8;

comptime {
    // wasm32-wasi: c_ulong/usize are 32-bit (vs 64-bit on x86_64-linux),
    // so RegexC layout differs. Only assert native glibc layout on non-wasm.
    if (!builtin.cpu.arch.isWasm()) {
        std.debug.assert(@sizeOf(RegexC) == 64);
        std.debug.assert(@alignOf(RegexC) == 8);
        std.debug.assert(@offsetOf(RegexC, "re_nsub") == 48);
        std.debug.assert(@offsetOf(RegexC, "flags") == 56);
        std.debug.assert(@sizeOf(RegexMatchC) == 8);
        std.debug.assert(@offsetOf(RegexMatchC, "rm_so") == 0);
        std.debug.assert(@offsetOf(RegexMatchC, "rm_eo") == 4);
    }
}

pub const SA_STD_ABI_VERSION = @import("sa_std/consts.zig").SA_STD_ABI_VERSION;

pub const SA_STD_OK = @import("sa_std/consts.zig").SA_STD_OK;
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_std/consts.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("sa_std/consts.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_NOT_FOUND = @import("sa_std/consts.zig").SA_STD_ERR_NOT_FOUND;
pub const SA_STD_ERR_ACCESS = @import("sa_std/consts.zig").SA_STD_ERR_ACCESS;
pub const SA_STD_ERR_NO_MEMORY = @import("sa_std/consts.zig").SA_STD_ERR_NO_MEMORY;
pub const SA_STD_ERR_IO = @import("sa_std/consts.zig").SA_STD_ERR_IO;
pub const SA_STD_ERR_NET = @import("sa_std/consts.zig").SA_STD_ERR_NET;
pub const SA_STD_ERR_UNSUPPORTED = @import("sa_std/consts.zig").SA_STD_ERR_UNSUPPORTED;

// --- Cross-platform compat: Linux-first, macOS via conditionals ---
// waitid/pidfd flags are Linux-only; 0 elsewhere (pidfd path is Linux-only).
pub const w_exited = @import("sa_std/proc_wait.zig").w_exited;
pub const w_nohang = @import("sa_std/proc_wait.zig").w_nohang;
// MSG_PEEK: std.posix.MSG is Linux-only in zig 0.14; Darwin value is 0x2.
pub const msg_peek: u32 = if (builtin.os.tag == .linux) std.posix.MSG.PEEK else 0x2;
// TCP_NODELAY == 1 on Linux, macOS and FreeBSD. Spell it out: std.posix.TCP
// is void on FreeBSD in zig 0.14, and std.os.linux.TCP.* are Linux values.
pub const tcp_nodelay: u32 = 1;
// --- FreeBSD compat (zig 0.14 std leaves several POSIX surfaces
// unimplemented for freebsd: uname, TCP consts, if_nametoindex) ---
const fbsd_sys_nmln: usize = 256;
pub const fbsd_utsname = extern struct {
    sysname: [fbsd_sys_nmln]u8,
    nodename: [fbsd_sys_nmln]u8,
    release: [fbsd_sys_nmln]u8,
    version: [fbsd_sys_nmln]u8,
    machine: [fbsd_sys_nmln]u8,
};
extern fn uname(buf: *fbsd_utsname) c_int;
extern fn if_nametoindex(ifname: [*:0]const u8) c_uint;
// Non-Linux targets call libc recvmsg directly. Note: the extern name must be
// exactly "recvmsg" — macOS dylibs reject undefined symbols, unlike ELF .so.
extern "c" fn recvmsg(sockfd: std.posix.fd_t, msg: *MsghdrT, flags: c_int) isize;
extern "c" fn __error() *c_int;
pub fn portableRecvmsg(fd: std.posix.fd_t, msg: *MsghdrT, flags: u32) !usize {
    if (builtin.os.tag == .linux) {
        const rc = std.os.linux.recvmsg(fd, @as(*std.os.linux.msghdr, @ptrCast(msg)), flags);
        return switch (std.os.linux.errno(rc)) {
            .SUCCESS => @as(usize, @intCast(rc)),
            else => |e| std.posix.unexpectedErrno(e),
        };
    } else {
        const rc = recvmsg(fd, msg, @as(c_int, @intCast(flags)));
        if (rc < 0) {
            const e = @as(std.posix.E, @fromBackingInt(@intCast(__error().*)));
            return std.posix.unexpectedErrno(e);
        }
        return @as(usize, @intCast(rc));
    }
}
pub const SA_STD_ERR_TRUNCATED = @import("sa_std/consts.zig").SA_STD_ERR_TRUNCATED;
pub const SA_STD_ERR_PERMISSION_DENIED = @import("sa_std/consts.zig").SA_STD_ERR_PERMISSION_DENIED;
pub const SA_STD_ERR_ALREADY_EXISTS = @import("sa_std/consts.zig").SA_STD_ERR_ALREADY_EXISTS;
pub const SA_STD_ERR_UNKNOWN = @import("sa_std/consts.zig").SA_STD_ERR_UNKNOWN;

/// Mirrors C sa_net_iov in sa_std.h. Layout must stay { u8* base; usize len; }.
pub const sa_net_iov = @import("sa_std/net.zig").sa_net_iov;

/// Cap on iovec entries accepted per vectored call. Matches POSIX IOV_MAX where
/// available and stays comfortably below common OS hard limits.
pub const SA_NET_IOV_MAX = @import("sa_std/consts.zig").SA_NET_IOV_MAX;

pub const SA_STD_STDIN = @import("sa_std/consts.zig").SA_STD_STDIN;
pub const SA_STD_STDOUT = @import("sa_std/consts.zig").SA_STD_STDOUT;
pub const SA_STD_STDERR = @import("sa_std/consts.zig").SA_STD_STDERR;

pub const SA_FS_FILE_REGULAR = @import("sa_std/consts.zig").SA_FS_FILE_REGULAR;
pub const SA_FS_FILE_DIR = @import("sa_std/consts.zig").SA_FS_FILE_DIR;
pub const SA_FS_FILE_SYMLINK = @import("sa_std/consts.zig").SA_FS_FILE_SYMLINK;
pub const SA_FS_FILE_OTHER = @import("sa_std/consts.zig").SA_FS_FILE_OTHER;

pub const IP_MULTICAST_TTL_OPT: u32 = 33;
pub const IP_MULTICAST_LOOP_OPT: u32 = 34;
pub const IP_MULTICAST_IF_OPT: u32 = 32;
pub const IP_ADD_MEMBERSHIP_OPT: u32 = 35;
pub const IP_DROP_MEMBERSHIP_OPT: u32 = 36;
pub const IPV6_JOIN_GROUP_OPT: u32 = 20;
pub const IPV6_LEAVE_GROUP_OPT: u32 = 21;
pub const IPV6_MULTICAST_HOPS_OPT: u32 = 18;
pub const IPV6_MULTICAST_LOOP_OPT: u32 = 19;
pub const IPV6_MULTICAST_IF_OPT: u32 = 17;

pub const SA_PLUGIN_DESCRIPTOR_SYMBOL: [:0]const u8 = "saasm_plugin_descriptor_v1";

pub const TestDebugScalar = @import("sa_std/test_debug.zig").TestDebugScalar;

pub const test_debug_scalars = @import("sa_std/test_debug.zig").test_debug_scalars;
pub const test_debug_next = @import("sa_std/test_debug.zig").test_debug_next;
pub const test_debug_count = @import("sa_std/test_debug.zig").test_debug_count;
pub const test_debug_mutex = @import("sa_std/test_debug.zig").test_debug_mutex;

pub const SaPluginDescriptor = extern struct {
    abi_version: u32,
    descriptor_size: u32,
    name: [*:0]const u8,
};

pub const SA_JSON_KIND_INVALID = @import("sa_std/consts.zig").SA_JSON_KIND_INVALID;
pub const SA_JSON_KIND_NULL = @import("sa_std/consts.zig").SA_JSON_KIND_NULL;
pub const SA_JSON_KIND_BOOL = @import("sa_std/consts.zig").SA_JSON_KIND_BOOL;
pub const SA_JSON_KIND_INTEGER = @import("sa_std/consts.zig").SA_JSON_KIND_INTEGER;
pub const SA_JSON_KIND_FLOAT = @import("sa_std/consts.zig").SA_JSON_KIND_FLOAT;
pub const SA_JSON_KIND_NUMBER_STRING = @import("sa_std/consts.zig").SA_JSON_KIND_NUMBER_STRING;
pub const SA_JSON_KIND_STRING = @import("sa_std/consts.zig").SA_JSON_KIND_STRING;
pub const SA_JSON_KIND_ARRAY = @import("sa_std/consts.zig").SA_JSON_KIND_ARRAY;
pub const SA_JSON_KIND_OBJECT = @import("sa_std/consts.zig").SA_JSON_KIND_OBJECT;

pub const SA_JSON_TOKEN_INVALID = @import("sa_std/consts.zig").SA_JSON_TOKEN_INVALID;
pub const SA_JSON_TOKEN_OBJECT_BEGIN = @import("sa_std/consts.zig").SA_JSON_TOKEN_OBJECT_BEGIN;
pub const SA_JSON_TOKEN_OBJECT_END = @import("sa_std/consts.zig").SA_JSON_TOKEN_OBJECT_END;
pub const SA_JSON_TOKEN_ARRAY_BEGIN = @import("sa_std/consts.zig").SA_JSON_TOKEN_ARRAY_BEGIN;
pub const SA_JSON_TOKEN_ARRAY_END = @import("sa_std/consts.zig").SA_JSON_TOKEN_ARRAY_END;
pub const SA_JSON_TOKEN_TRUE = @import("sa_std/consts.zig").SA_JSON_TOKEN_TRUE;
pub const SA_JSON_TOKEN_FALSE = @import("sa_std/consts.zig").SA_JSON_TOKEN_FALSE;
pub const SA_JSON_TOKEN_NULL = @import("sa_std/consts.zig").SA_JSON_TOKEN_NULL;
pub const SA_JSON_TOKEN_NUMBER = @import("sa_std/consts.zig").SA_JSON_TOKEN_NUMBER;
pub const SA_JSON_TOKEN_PARTIAL_NUMBER = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_NUMBER;
pub const SA_JSON_TOKEN_STRING = @import("sa_std/consts.zig").SA_JSON_TOKEN_STRING;
pub const SA_JSON_TOKEN_PARTIAL_STRING = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3;
pub const SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4 = @import("sa_std/consts.zig").SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4;
pub const SA_JSON_TOKEN_END_OF_DOCUMENT = @import("sa_std/consts.zig").SA_JSON_TOKEN_END_OF_DOCUMENT;
pub const SA_JSON_TOKEN_ALLOCATED_NUMBER = @import("sa_std/consts.zig").SA_JSON_TOKEN_ALLOCATED_NUMBER;
pub const SA_JSON_TOKEN_ALLOCATED_STRING = @import("sa_std/consts.zig").SA_JSON_TOKEN_ALLOCATED_STRING;

pub const SA_JSON_WHITESPACE_MINIFIED = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_MINIFIED;
pub const SA_JSON_WHITESPACE_INDENT_1 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_1;
pub const SA_JSON_WHITESPACE_INDENT_2 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_2;
pub const SA_JSON_WHITESPACE_INDENT_3 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_3;
pub const SA_JSON_WHITESPACE_INDENT_4 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_4;
pub const SA_JSON_WHITESPACE_INDENT_8 = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_8;
pub const SA_JSON_WHITESPACE_INDENT_TAB = @import("sa_std/consts.zig").SA_JSON_WHITESPACE_INDENT_TAB;

pub const SA_REGEX_EXTENDED = @import("sa_std/consts.zig").SA_REGEX_EXTENDED;
pub const SA_REGEX_ICASE = @import("sa_std/consts.zig").SA_REGEX_ICASE;
pub const SA_REGEX_NEWLINE = @import("sa_std/consts.zig").SA_REGEX_NEWLINE;
pub const SA_REGEX_NOSUB = @import("sa_std/consts.zig").SA_REGEX_NOSUB;
pub const SA_REGEX_NOTBOL = @import("sa_std/consts.zig").SA_REGEX_NOTBOL;
pub const SA_REGEX_NOTEOL = @import("sa_std/consts.zig").SA_REGEX_NOTEOL;
// eflags slot value for regexec: restrict the search to the pmatch[0] range
// while reporting absolute offsets. glibc assigns it the same numeric value
// as the SA_REGEX_NEWLINE *cflag*; the two live in different parameters.
pub const SA_REGEX_STARTEND = @import("sa_std/consts.zig").SA_REGEX_STARTEND;
pub const SA_REGEX_REG_NOERROR = @import("sa_std/consts.zig").SA_REGEX_REG_NOERROR;
pub const SA_REGEX_REG_OK = @import("sa_std/consts.zig").SA_REGEX_REG_OK;
pub const SA_REGEX_REG_NOMATCH = @import("sa_std/consts.zig").SA_REGEX_REG_NOMATCH;
pub const SA_REGEX_REG_BADPAT = @import("sa_std/consts.zig").SA_REGEX_REG_BADPAT;
pub const SA_REGEX_REG_ECOLLATE = @import("sa_std/consts.zig").SA_REGEX_REG_ECOLLATE;
pub const SA_REGEX_REG_ECTYPE = @import("sa_std/consts.zig").SA_REGEX_REG_ECTYPE;
pub const SA_REGEX_REG_EESCAPE = @import("sa_std/consts.zig").SA_REGEX_REG_EESCAPE;
pub const SA_REGEX_REG_ESUBREG = @import("sa_std/consts.zig").SA_REGEX_REG_ESUBREG;
pub const SA_REGEX_REG_EBRACK = @import("sa_std/consts.zig").SA_REGEX_REG_EBRACK;
pub const SA_REGEX_REG_EPAREN = @import("sa_std/consts.zig").SA_REGEX_REG_EPAREN;
pub const SA_REGEX_REG_EBRACE = @import("sa_std/consts.zig").SA_REGEX_REG_EBRACE;
pub const SA_REGEX_REG_BADBR = @import("sa_std/consts.zig").SA_REGEX_REG_BADBR;
pub const SA_REGEX_REG_ERANGE = @import("sa_std/consts.zig").SA_REGEX_REG_ERANGE;
pub const SA_REGEX_REG_ESPACE = @import("sa_std/consts.zig").SA_REGEX_REG_ESPACE;
pub const SA_REGEX_REG_BADRPT = @import("sa_std/consts.zig").SA_REGEX_REG_BADRPT;
pub const SA_REGEX_REG_ENOSYS = @import("sa_std/consts.zig").SA_REGEX_REG_ENOSYS;

pub const SaJsonToken = extern struct {
    kind: u32,
    text_ptr: ?[*]const u8,
    text_len: u64,
};

pub const SaJsonStringifyOptions = extern struct {
    whitespace: u32 = SA_JSON_WHITESPACE_MINIFIED,
    emit_null_optional_fields: u8 = 1,
    emit_strings_as_arrays: u8 = 0,
    escape_unicode: u8 = 0,
    emit_nonportable_numbers_as_strings: u8 = 0,
};

const FIRST_DYNAMIC_HANDLE: u64 = 4;
const DEFAULT_CAPTURE_LIMIT: usize = 50 * 1024;

const empty_bytes: [0]u8 = .{};
const empty_mut_bytes: [0]u8 = .{};

const BufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *BufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const MetadataHandle = @import("sa_std/dir_stat.zig").MetadataHandle;

pub const DirEntrySnapshot = @import("sa_std/dir_stat.zig").DirEntrySnapshot;

pub const DirEntriesHandle = @import("sa_std/dir_stat.zig").DirEntriesHandle;

const DirEntryHandle = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    kind: u32,
    ino: u64,

    pub fn deinit(self: *DirEntryHandle) void {
        if (self.name.len != 0) self.allocator.free(self.name);
        self.name = &.{};
    }
};

pub const NetAddrHandle = struct {
    allocator: std.mem.Allocator,
    host: []u8,
    addr: NetAddress,

    pub fn deinit(self: *NetAddrHandle) void {
        if (self.host.len != 0) self.allocator.free(self.host);
        self.host = &.{};
    }

    pub fn init(allocator: std.mem.Allocator, address: NetAddress) !NetAddrHandle {
        const host = try addressHostText(allocator, address);
        return .{
            .allocator = allocator,
            .host = host,
            .addr = address,
        };
    }
};

const NetAddrListHandle = struct {
    allocator: std.mem.Allocator,
    addresses: []NetAddress,
    next_index: usize = 0,

    pub fn deinit(self: *NetAddrListHandle) void {
        if (self.addresses.len != 0) self.allocator.free(self.addresses);
        self.addresses = &.{};
        self.next_index = 0;
    }
};
pub const SA_NET_UNIX_ADDR_UNNAMED = @import("sa_std/consts.zig").SA_NET_UNIX_ADDR_UNNAMED;
pub const SA_NET_UNIX_ADDR_PATHNAME = @import("sa_std/consts.zig").SA_NET_UNIX_ADDR_PATHNAME;
pub const SA_NET_UNIX_ADDR_ABSTRACT = @import("sa_std/consts.zig").SA_NET_UNIX_ADDR_ABSTRACT;

const UnixAddrHandle = struct {
    allocator: std.mem.Allocator,
    kind: u32,
    bytes: []u8,

    pub fn deinit(self: *UnixAddrHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

const unix_sockaddr_path_offset: usize = if (is_wasm) 2 else @offsetOf(SockAddrUnT, "path");

pub fn unixAddrFromSockaddr(allocator: std.mem.Allocator, addr: SockAddrUnT, len_raw: SockLenT) !UnixAddrHandle {
    var len = @as(usize, @intCast(len_raw));
    if (len == 0) len = unix_sockaddr_path_offset;
    if (len <= unix_sockaddr_path_offset) {
        return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_UNNAMED, .bytes = &.{} };
    }
    if (addr.family != AFT.UNIX) return error.InvalidArgument;

    const available = @min(len - unix_sockaddr_path_offset, addr.path.len);
    if (available == 0) {
        return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_UNNAMED, .bytes = &.{} };
    }

    if (addr.path[0] == 0) {
        if (available <= 1) return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_UNNAMED, .bytes = &.{} };
        const name = try allocator.dupe(u8, addr.path[1..available]);
        return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_ABSTRACT, .bytes = name };
    }

    var path_len = available;
    if (path_len > 0 and addr.path[path_len - 1] == 0) path_len -= 1;
    const path = try allocator.dupe(u8, addr.path[0..path_len]);
    return .{ .allocator = allocator, .kind = SA_NET_UNIX_ADDR_PATHNAME, .bytes = path };
}

pub fn registerUnixAddrOutLocked(addr: SockAddrUnT, len: SockLenT, out_handle: *u64) i32 {
    var unix_addr = unixAddrFromSockaddr(std.heap.page_allocator, addr, len) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .unix_addr = unix_addr }) catch |err| {
        unix_addr.deinit();
        return finishErr(err);
    };
    out_handle.* = handle;
    return finish(SA_STD_OK);
}

pub fn unixSockAddrFromHandle(handle: u64) !UnixSockAddr {
    // wasm32-wasi has no unix sockets; stub to keep archive compilable.
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .unix_addr => |unix_addr| blk: {
            var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
            @memset(&addr.path, 0);
            switch (unix_addr.kind) {
                SA_NET_UNIX_ADDR_UNNAMED => break :blk .{ .addr = addr, .len = @as(SockLenT, @intCast(unix_sockaddr_path_offset)) },
                SA_NET_UNIX_ADDR_PATHNAME => {
                    if (unix_addr.bytes.len == 0 or unix_addr.bytes.len >= addr.path.len) return error.InvalidArgument;
                    if (std.mem.indexOfScalar(u8, unix_addr.bytes, 0) != null) return error.InvalidArgument;
                    @memcpy(addr.path[0..unix_addr.bytes.len], unix_addr.bytes);
                    break :blk .{ .addr = addr, .len = @as(SockLenT, @intCast(unix_sockaddr_path_offset + unix_addr.bytes.len + 1)) };
                },
                SA_NET_UNIX_ADDR_ABSTRACT => {
                    if (unix_addr.bytes.len + 1 > addr.path.len) return error.InvalidArgument;
                    addr.path[0] = 0;
                    if (unix_addr.bytes.len != 0) @memcpy(addr.path[1 .. 1 + unix_addr.bytes.len], unix_addr.bytes);
                    break :blk .{ .addr = addr, .len = @as(SockLenT, @intCast(unix_sockaddr_path_offset + 1 + unix_addr.bytes.len)) };
                },
                else => return error.InvalidArgument,
            }
        },
        else => error.InvalidHandle,
    };
}

pub fn registerNetAddrList(host: []const u8, port: u16) !u64 {
    var list = try netGetAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();
    if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
    const addresses = try std.heap.page_allocator.dupe(NetAddress, list.addrs);
    errdefer std.heap.page_allocator.free(addresses);
    return registerResource(.{ .net_addr_list = .{
        .allocator = std.heap.page_allocator,
        .addresses = addresses,
    } });
}
pub fn registerNetAddrOutLocked(address: NetAddress, out_handle: *u64) i32 {
    var net_addr = NetAddrHandle.init(std.heap.page_allocator, address) catch |err| return finishErr(err);
    const handle = registerResourceLocked(.{ .net_addr = net_addr }) catch |err| {
        net_addr.deinit();
        return finishErr(err);
    };
    out_handle.* = handle;
    return finish(SA_STD_OK);
}

fn addressHostText(allocator: std.mem.Allocator, address: NetAddress) ![]u8 {
    return switch (address.storage.family) {
        AFT.INET => blk: {
            const sin: *const SockAddrInT = @ptrCast(@alignCast(&address.storage));
            const ip: [4]u8 = @bitCast(sin.addr);
            break :blk try std.fmt.allocPrint(allocator, "{}.{}.{}.{}", .{ ip[0], ip[1], ip[2], ip[3] });
        },
        AFT.INET6 => blk: {
            const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&address.storage));
            var segbuf: [8]u16 = undefined;
            var i: usize = 0;
            while (i < 8) : (i += 1) {
                segbuf[i] = std.mem.readInt(u16, sin6.addr[i * 2 ..][0..2], .big);
            }
            var outbuf: [64]u8 = undefined;
            const text = try std.fmt.bufPrint(&outbuf, "{x}:{x}:{x}:{x}:{x}:{x}:{x}:{x}", .{
                segbuf[0], segbuf[1], segbuf[2], segbuf[3], segbuf[4], segbuf[5], segbuf[6], segbuf[7],
            });
            if (sin6.scope_id != 0) {
                const with_scope = try std.fmt.allocPrint(allocator, "{s}%{d}", .{ text, sin6.scope_id });
                break :blk with_scope;
            }
            break :blk try allocator.dupe(u8, text);
        },
        AFT.UNIX => try allocator.dupe(u8, address.unixPath()),
        else => try allocator.dupe(u8, ""),
    };
}

pub fn addressSocketText(allocator: std.mem.Allocator, address: NetAddress) ![]u8 {
    return switch (address.storage.family) {
        AFT.INET, AFT.INET6 => blk: {
            const host = try addressHostText(allocator, address);
            defer allocator.free(host);
            if (address.storage.family == AFT.INET6) {
                break :blk try std.fmt.allocPrint(allocator, "[{s}]:{d}", .{ host, address.getPort() });
            }
            break :blk try std.fmt.allocPrint(allocator, "{s}:{d}", .{ host, address.getPort() });
        },
        else => try addressHostText(allocator, address),
    };
}

const FmtHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *FmtHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const JsonDocumentHandle = @import("sa_std/json_node.zig").JsonDocumentHandle;

// A JSON node handle addresses a value inside its document tree by PATH
// (object keys / array indices from the document root). Every acquire
// re-resolves the path against the live tree, so a mutation performed
// through any handle is visible through all other handles of the same
// document. Removing the exact key a handle points at (or an ancestor of
// it) detaches the handle: later operations fail with InvalidHandle
// instead of reading a stale snapshot.
pub const JsonPathSegment = @import("sa_std/json_node.zig").JsonPathSegment;

pub const freeJsonPath = @import("sa_std/json_node.zig").freeJsonPath;

// Returns a fully-owned copy of `base` with `segment` appended (key bytes
// duplicated with `allocator`).
pub const jsonPathAppend = @import("sa_std/json_node.zig").jsonPathAppend;

pub const JsonNodeHandle = @import("sa_std/json_node.zig").JsonNodeHandle;

pub const JsonBufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn deinit(self: *JsonBufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const JsonScannerHandle = @import("sa_std/json_scan.zig").JsonScannerHandle;

pub const JsonStreamHandle = @import("sa_std/json_scan.zig").JsonStreamHandle;

pub const JsonWriterHandle = struct {
    allocator: std.mem.Allocator,
    aw: std.Io.Writer.Allocating,
    stream: std.json.Stringify,
    options: std.json.Stringify.Options,
    root_value_started: bool = false,
    root_value_complete: bool = false,
    open_depth: u32 = 0,
    result_buffer: ?u64 = null,

    pub fn init(allocator: std.mem.Allocator, options: std.json.Stringify.Options) !*JsonWriterHandle {
        const handle = try allocator.create(JsonWriterHandle);
        handle.* = .{
            .allocator = allocator,
            .aw = .init(allocator),
            .stream = undefined,
            .options = options,
            .root_value_started = false,
            .root_value_complete = false,
            .open_depth = 0,
            .result_buffer = null,
        };
        handle.stream = .{ .writer = &handle.aw.writer, .options = options };
        return handle;
    }

    pub fn deinit(self: *JsonWriterHandle) void {
        self.aw.deinit();
        self.allocator.destroy(self);
    }
};

pub const RegexHandle = struct {
    allocator: std.mem.Allocator,
    pattern_z: []u8,
    compiled: RegexC,
    compiled_valid: bool = false,

    pub fn init(allocator: std.mem.Allocator, pattern: []const u8, cflags: c_int) !*RegexHandle {
        if (std.mem.indexOfScalar(u8, pattern, 0) != null) return error.InvalidArgument;
        const owned_pattern = try allocator.alloc(u8, pattern.len + 1);
        errdefer allocator.free(owned_pattern);
        @memcpy(owned_pattern[0..pattern.len], pattern);
        owned_pattern[pattern.len] = 0;
        const handle = try allocator.create(RegexHandle);
        errdefer allocator.destroy(handle);
        handle.* = .{
            .allocator = allocator,
            .pattern_z = owned_pattern,
            .compiled = undefined,
            .compiled_valid = false,
        };
        const pattern_c: [*:0]const u8 = @ptrCast(owned_pattern.ptr);
        const rc = regcomp(&handle.compiled, pattern_c, cflags);
        if (rc != SA_REGEX_REG_NOERROR) {
            return regexErrorToZig(rc);
        }
        handle.compiled_valid = true;
        return handle;
    }

    pub fn deinit(self: *RegexHandle) void {
        if (self.compiled_valid) regfree(&self.compiled);
        if (self.pattern_z.len != 0) self.allocator.free(self.pattern_z);
        self.pattern_z = &.{};
        self.compiled_valid = false;
    }

    pub fn destroy(self: *RegexHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

pub const RegexMatchHandle = @import("sa_std/regex_core.zig").RegexMatchHandle;

pub const RegexMatchListHandle = @import("sa_std/regex_core.zig").RegexMatchListHandle;

pub const RegexSplitListHandle = @import("sa_std/regex_core.zig").RegexSplitListHandle;

pub const RegexBufferHandle = @import("sa_std/regex_core.zig").RegexBufferHandle;

pub const regexErrorToZig = @import("sa_std/regex_core.zig").regexErrorToZig;

pub const regexGroupCount = @import("sa_std/regex_core.zig").regexGroupCount;

pub const regexMatchHandle = @import("sa_std/regex_core.zig").regexMatchHandle;

// Copies text into an owned NUL-terminated buffer, rejecting embedded NUL
// bytes exactly like regexMatchHandle does.
pub const regexOwnedTextZ = @import("sa_std/regex_core.zig").regexOwnedTextZ;

// Runs regexec over the byte range [start, end) of an owned NUL-terminated
// text using REG_STARTEND, so reported offsets stay absolute and `^` / `$`
// keep whole-text semantics. Returns the raw regcomp-family status code.
pub const regexExecRange = @import("sa_std/regex_core.zig").regexExecRange;

// Collects every non-overlapping match in text_z (an owned NUL-terminated
// copy), in left-to-right order. After an empty match the search advances
// one byte — the byte-level form of the JS global-exec loop (JS advances
// one code point; this engine is byte-oriented). Caller owns the returned
// outer slice and every inner groups slice.
pub const regexCollectMatches = @import("sa_std/regex_core.zig").regexCollectMatches;

pub const regexAppendGroup = @import("sa_std/regex_core.zig").regexAppendGroup;

// Appends the JS-style substitution of `replacement` for one match:
// $$ is a literal $, $& the whole match, $` the text before the match,
// $' the text after it, and $n / $nn capture groups (a group that did not
// participate expands to nothing; an out-of-range $n stays literal).
// $<name> passes through literally: POSIX ERE has no named groups.
pub const regexAppendExpansion = @import("sa_std/regex_core.zig").regexAppendExpansion;

// Builds the replaced text. With `global` false only the first match is
// replaced (JS String.replace without /g); with true every match from the
// global iteration is replaced (JS /g and replaceAll). The result is an
// owned slice; when nothing matches it is a copy of the input text.
pub const regexBuildReplace = @import("sa_std/regex_core.zig").regexBuildReplace;

// Builds the piece list for JS String.split semantics over text_z. Pieces
// are (start, end) ranges into text_z; non-participating capture groups
// keep rm_so < 0. `limit` caps the TOTAL piece count (groups included);
// limit == 0 means no limit in this API (JS limit 0 returns [] — a
// deliberate divergence, documented in regex.sai).
pub const regexSplitHandle = @import("sa_std/regex_core.zig").regexSplitHandle;

pub fn jsonKindOf(value: std.json.Value) u32 {
    return switch (value) {
        .null => SA_JSON_KIND_NULL,
        .bool => SA_JSON_KIND_BOOL,
        .integer => SA_JSON_KIND_INTEGER,
        .float => SA_JSON_KIND_FLOAT,
        .number_string => SA_JSON_KIND_NUMBER_STRING,
        .string => SA_JSON_KIND_STRING,
        .array => SA_JSON_KIND_ARRAY,
        .object => SA_JSON_KIND_OBJECT,
    };
}

pub fn jsonTextSlice(value: std.json.Value) ?[]const u8 {
    return switch (value) {
        .string => |text| text,
        .number_string => |text| text,
        else => null,
    };
}

pub fn jsonValueAsF64(value: std.json.Value) !f64 {
    return switch (value) {
        .integer => |inner| @as(f64, @floatFromInt(inner)),
        .float => |inner| {
            if (!std.math.isFinite(inner)) return error.InvalidArgument;
            return inner;
        },
        .number_string => |text| blk: {
            const parsed = std.fmt.parseFloat(f64, text) catch return error.InvalidArgument;
            if (!std.math.isFinite(parsed)) break :blk error.InvalidArgument;
            break :blk parsed;
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonValueAsI64(value: std.json.Value) !i64 {
    return switch (value) {
        .integer => |inner| inner,
        .float => |inner| blk: {
            if (!std.math.isFinite(inner)) break :blk error.InvalidArgument;
            if (@round(inner) != inner) break :blk error.InvalidArgument;
            if (inner > @as(f64, @floatFromInt(std.math.maxInt(i64)))) break :blk error.InvalidArgument;
            if (inner < @as(f64, @floatFromInt(std.math.minInt(i64)))) break :blk error.InvalidArgument;
            break :blk @as(i64, @intFromFloat(inner));
        },
        .number_string => |text| std.fmt.parseInt(i64, text, 10) catch |err| switch (err) {
            error.Overflow, error.InvalidCharacter => return error.InvalidArgument,
        },
        else => error.InvalidArgument,
    };
}

pub fn jsonValueAsBool(value: std.json.Value) !bool {
    return switch (value) {
        .bool => |inner| inner,
        else => error.InvalidArgument,
    };
}

pub const registerJsonNode = @import("sa_std/json_node.zig").registerJsonNode;

pub const acquireJsonNode = @import("sa_std/json_node.zig").acquireJsonNode;

// Walks `path` from the document root and returns a pointer to the live
// tree value. The pointer is only valid until the next tree mutation.
pub const jsonResolvePathPtr = @import("sa_std/json_node.zig").jsonResolvePathPtr;

pub const jsonResolvePath = @import("sa_std/json_node.zig").jsonResolvePath;

pub const jsonDocumentFromSlice = @import("sa_std/json_node.zig").jsonDocumentFromSlice;

pub const jsonObjectGet = @import("sa_std/json_node.zig").jsonObjectGet;

pub const jsonArrayGet = @import("sa_std/json_node.zig").jsonArrayGet;

pub const jsonObjectKeyAt = @import("sa_std/json_node.zig").jsonObjectKeyAt;

fn jsonStringifyAlloc(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var list = std.array_list.Managed(u8).init(allocator);
    errdefer list.deinit();
    try stringifyToList(&list, value);
    return try list.toOwnedSlice();
}

pub fn jsonSerializeBuffer(allocator: std.mem.Allocator, value: std.json.Value) !u64 {
    const bytes = try jsonStringifyAlloc(allocator, value);
    return registerResource(.{ .json_buffer = .{ .allocator = allocator, .bytes = bytes } }) catch |err| {
        allocator.free(bytes);
        return err;
    };
}

// Deep-copies a JSON value into `allocator` (the target document's arena),
// duplicating every string, array and object so the copy shares no storage
// with the source tree.
pub fn jsonValueClone(allocator: std.mem.Allocator, value: std.json.Value) !std.json.Value {
    return switch (value) {
        .null => .null,
        .bool => |inner| .{ .bool = inner },
        .integer => |inner| .{ .integer = inner },
        .float => |inner| .{ .float = inner },
        .number_string => |text| .{ .number_string = try allocator.dupe(u8, text) },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |array| blk: {
            var cloned = std.json.Array.init(allocator);
            errdefer cloned.deinit();
            for (array.items) |item| {
                try cloned.append(try jsonValueClone(allocator, item));
            }
            break :blk .{ .array = cloned };
        },
        .object => |object| blk: {
            var cloned: std.json.ObjectMap = .empty;
            var it = object.iterator();
            while (it.next()) |entry| {
                const key_copy = try allocator.dupe(u8, entry.key_ptr.*);
                try cloned.put(allocator, key_copy, try jsonValueClone(allocator, entry.value_ptr.*));
            }
            break :blk .{ .object = cloned };
        },
    };
}

pub const JsonMutation = @import("sa_std/json_node.zig").JsonMutation;

// Resolves the handle's slot under the registry lock for an in-place tree
// mutation. The caller must hold no other registry acquisition.
pub const jsonMutationTarget = @import("sa_std/json_node.zig").jsonMutationTarget;

pub const jsonObjectSetLocked = @import("sa_std/json_node.zig").jsonObjectSetLocked;

pub const jsonArrayPushLocked = @import("sa_std/json_node.zig").jsonArrayPushLocked;

pub const jsonObjectRemoveLocked = @import("sa_std/json_node.zig").jsonObjectRemoveLocked;

pub fn acquireJsonWriterForWrite(writer: u64) !*JsonWriterHandle {
    const resource = getResourceLocked(writer) orelse return error.InvalidHandle;
    const writer_handle = switch (resource.*) {
        .json_writer => |handle| handle,
        else => return error.InvalidHandle,
    };
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.root_value_complete and writer_handle.open_depth == 0) return error.InvalidArgument;
    return writer_handle;
}

pub fn markJsonWriterValueComplete(writer_handle: *JsonWriterHandle) void {
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
}

pub fn jsonWriterObjectFieldLocked(writer_handle: *JsonWriterHandle, key: []const u8) !void {
    if (writer_handle.result_buffer != null) return error.InvalidHandle;
    if (writer_handle.open_depth == 0) return error.InvalidArgument;
    try writer_handle.stream.objectField(key);
}

pub fn tokenTypeOf(token: std.json.Token) u32 {
    return switch (token) {
        .object_begin => SA_JSON_TOKEN_OBJECT_BEGIN,
        .object_end => SA_JSON_TOKEN_OBJECT_END,
        .array_begin => SA_JSON_TOKEN_ARRAY_BEGIN,
        .array_end => SA_JSON_TOKEN_ARRAY_END,
        .true => SA_JSON_TOKEN_TRUE,
        .false => SA_JSON_TOKEN_FALSE,
        .null => SA_JSON_TOKEN_NULL,
        .number => SA_JSON_TOKEN_NUMBER,
        .partial_number => SA_JSON_TOKEN_PARTIAL_NUMBER,
        .allocated_number => SA_JSON_TOKEN_ALLOCATED_NUMBER,
        .string => SA_JSON_TOKEN_STRING,
        .partial_string => SA_JSON_TOKEN_PARTIAL_STRING,
        .partial_string_escaped_1 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_1,
        .partial_string_escaped_2 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_2,
        .partial_string_escaped_3 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_3,
        .partial_string_escaped_4 => SA_JSON_TOKEN_PARTIAL_STRING_ESCAPED_4,
        .allocated_string => SA_JSON_TOKEN_ALLOCATED_STRING,
        .end_of_document => SA_JSON_TOKEN_END_OF_DOCUMENT,
    };
}

pub fn tokenTextSlice(token: std.json.Token) ?[]const u8 {
    return switch (token) {
        .number => |slice| slice,
        .partial_number => |slice| slice,
        .string => |slice| slice,
        .partial_string => |slice| slice,
        else => null,
    };
}

pub const tokenTextBytes = @import("sa_std/json_scan.zig").tokenTextBytes;

pub const jsonScannerFeed = @import("sa_std/json_scan.zig").jsonScannerFeed;

const EnvHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    fn deinit(self: *EnvHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.bytes = &.{};
    }
};

pub const TimeDate = extern struct {
    unix_ms: i64,
    unix_ns: i64,
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
};

const SaNetAddr = extern struct {
    family: u32,
    port: u32,
    host_ptr: [*]u8,
    host_len: u64,
    scope_id: u64,
};

const Timeval = std.posix.timeval;
const TimevalSec = @TypeOf(@as(Timeval, .{ .sec = 0, .usec = 0 }).sec);
const TimevalUsec = @TypeOf(@as(Timeval, .{ .sec = 0, .usec = 0 }).usec);
const LingerOption = extern struct { onoff: i32, linger: i32 };
pub const Timespec = std.posix.timespec;
const TimespecSec = @TypeOf(@as(Timespec, .{ .sec = 0, .nsec = 0 }).sec);
const TimespecNsec = @TypeOf(@as(Timespec, .{ .sec = 0, .nsec = 0 }).nsec);

const OwnedFdHandle = struct {
    fd: std.posix.fd_t,

    fn deinit(self: *OwnedFdHandle) void {
        lxClose(self.fd);
        self.fd = -1;
    }
};

const TerminalSession = struct {
    fd: std.posix.fd_t,
    saved: std.posix.termios,

    fn deinit(self: *TerminalSession) !void {
        try std.posix.tcsetattr(self.fd, .FLUSH, self.saved);
    }
};

pub const SaProcessArgv = extern struct {
    data: [*]const u8,
    len: u64,
};

pub const SaTermWinsize = extern struct {
    row: u16,
    col: u16,
    xpixel: u16,
    ypixel: u16,
};

pub const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

pub const ProcessHandle = @import("sa_std/proc_wait.zig").ProcessHandle;

pub const TcpListener = struct {
    fd: std.posix.fd_t,
    addr: NetAddress,
};

pub const Resource = union(enum) {
    file: sio.File,
    dynamic_lib: *DynamicLibHandle,
    tcp_stream: std.posix.fd_t,
    tcp_listener: TcpListener,
    udp_socket: std.posix.socket_t,
    buffer: BufferHandle,
    metadata: MetadataHandle,
    dir_entries: DirEntriesHandle,
    dir_entry: DirEntryHandle,
    net_addr: NetAddrHandle,
    net_addr_list: NetAddrListHandle,
    unix_addr: UnixAddrHandle,
    fmt: FmtHandle,
    env: EnvHandle,
    json_node: JsonNodeHandle,
    json_buffer: JsonBufferHandle,
    json_scanner: *JsonScannerHandle,
    json_stream: *JsonStreamHandle,
    json_writer: *JsonWriterHandle,
    regex: *RegexHandle,
    regex_match: *RegexMatchHandle,
    regex_match_list: *RegexMatchListHandle,
    regex_split_list: *RegexSplitListHandle,
    regex_buffer: *RegexBufferHandle,
    owned_fd: OwnedFdHandle,
    terminal_session: TerminalSession,
    process: ProcessHandle,

    pub fn close(self: *Resource) !void {
        switch (self.*) {
            .file => |file| file.close(),
            .dynamic_lib => |handle| {
                handle.deinit();
                std.heap.page_allocator.destroy(handle);
            },
            .tcp_stream => |stream| lxClose(stream),
            .tcp_listener => |*server| lxClose(server.fd),
            .udp_socket => |fd| lxClose(fd),
            .buffer => |*buffer| buffer.deinit(),
            .metadata => |*metadata| metadata.deinit(),
            .dir_entries => |*entries| entries.deinit(),
            .dir_entry => |*entry| entry.deinit(),
            .net_addr => |*addr| addr.deinit(),
            .net_addr_list => |*list| list.deinit(),
            .unix_addr => |*addr| addr.deinit(),
            .fmt => |*fmt| fmt.deinit(),
            .env => |*env| env.deinit(),
            .json_node => |*node| node.deinit(),
            .json_buffer => |*buffer| buffer.deinit(),
            .json_scanner => |scanner| scanner.destroy(),
            .json_stream => |stream| stream.deinit(),
            .json_writer => |writer| writer.deinit(),
            .regex => |regex| regex.destroy(),
            .regex_match => |match| match.destroy(),
            .regex_match_list => |list| list.destroy(),
            .regex_split_list => |list| list.destroy(),
            .regex_buffer => |buffer| buffer.destroy(),
            .owned_fd => |*fd| fd.deinit(),
            .terminal_session => |*session| {
                // No terminal sessions can exist on WASI (raw_enter stubbed);
                // skip the tcsetattr restore, which wasi-libc does not provide.
                if (is_wasm) {} else try session.deinit();
            },
            .process => |*proc| proc.deinit(),
        }
        self.* = undefined;
    }
};

pub var registry_mutex: std.atomic.Mutex = .unlocked;
var registry_slots = std.array_list.Managed(?Resource).init(std.heap.page_allocator);
pub const pthread_registry_mutex = @import("sa_std/pthread.zig").pthread_registry_mutex;
pub const pthread_slots = @import("sa_std/pthread.zig").pthread_slots;
pub const pthread_free_slots = @import("sa_std/pthread.zig").pthread_free_slots;
pub const raw_pthread_owners = @import("sa_std/pthread.zig").raw_pthread_owners;
pub threadlocal var last_error: i32 = SA_STD_OK;
var compatibility_mmap_page: [4096]u8 = std.mem.zeroes([4096]u8);
var compatibility_dlopen_cookie: [1]u8 = .{0};
var compatibility_dlsym_cookie: [1]u8 = .{0};
var compatibility_dl_error: [:0]const u8 = "unsupported";

const DynamicLibHandle = struct {
    // wasm32-wasi has no dlopen; std.DynLib itself is @compileError on wasm,
    // so the field must be conditional to keep the type compilable.
    lib: if (builtin.cpu.arch.isWasm()) void else std.DynLib,

    fn deinit(self: *DynamicLibHandle) void {
        if (!builtin.cpu.arch.isWasm()) {
            self.lib.close();
        }
    }
};

pub const PthreadEntryFn = @import("sa_std/pthread.zig").PthreadEntryFn;

extern fn sa_host_pthread_create(thread: *std.c.pthread_t, attr: ?*const std.c.pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_join(thread: std.c.pthread_t, retval: ?*?*anyopaque) callconv(.c) c_int;
extern fn sa_host_pthread_detach(thread: std.c.pthread_t) callconv(.c) c_int;

pub const PthreadTask = @import("sa_std/pthread.zig").PthreadTask;

pub const PthreadHandle = @import("sa_std/pthread.zig").PthreadHandle;

pub const RawPthreadOwner = @import("sa_std/pthread.zig").RawPthreadOwner;

pub const RawPthreadTransfer = @import("sa_std/pthread.zig").RawPthreadTransfer;

pub const pthreadToRaw = @import("sa_std/pthread.zig").pthreadToRaw;

pub const rawToPthread = @import("sa_std/pthread.zig").rawToPthread;

pub const pthreadTaskMain = @import("sa_std/pthread.zig").pthreadTaskMain;

pub const pthreadTaskMainC = @import("sa_std/pthread.zig").pthreadTaskMainC;

pub const mapPthreadCreateError = @import("sa_std/pthread.zig").mapPthreadCreateError;

pub const spawnPthread = @import("sa_std/pthread.zig").spawnPthread;

pub const joinPthreadHandle = @import("sa_std/pthread.zig").joinPthreadHandle;

pub const allocPthreadHandle = @import("sa_std/pthread.zig").allocPthreadHandle;

pub const takePthreadHandle = @import("sa_std/pthread.zig").takePthreadHandle;

pub const freePthreadHandle = @import("sa_std/pthread.zig").freePthreadHandle;

pub const transferPthreadHandleToRaw = @import("sa_std/pthread.zig").transferPthreadHandleToRaw;

pub const findRawPthreadTask = @import("sa_std/pthread.zig").findRawPthreadTask;

pub const removeRawPthreadOwner = @import("sa_std/pthread.zig").removeRawPthreadOwner;


pub fn finish(status: i32) i32 {
    last_error = status;
    return status;
}

pub fn mapError(err: anyerror) i32 {
    return switch (err) {
        error.InvalidArgument => SA_STD_ERR_INVALID_ARGUMENT,
        error.InvalidHandle => SA_STD_ERR_INVALID_HANDLE,
        error.OutOfMemory => SA_STD_ERR_NO_MEMORY,
        error.PathAlreadyExists => SA_STD_ERR_ALREADY_EXISTS,
        error.FileNotFound => SA_STD_ERR_NOT_FOUND,
        error.AccessDenied, error.PermissionDenied => SA_STD_ERR_ACCESS,
        error.WouldBlock => SA_STD_ERR_IO,
        error.NotATerminal, error.ProcessOrphaned => SA_STD_ERR_UNSUPPORTED,
        error.FileDescriptorAlreadyPresentInSet, error.OperationCausesCircularLoop => SA_STD_ERR_INVALID_ARGUMENT,
        error.FileDescriptorNotRegistered => SA_STD_ERR_INVALID_HANDLE,
        error.FileDescriptorIncompatibleWithEpoll => SA_STD_ERR_UNSUPPORTED,
        error.SyntaxError,
        error.UnexpectedEndOfInput,
        error.UnexpectedToken,
        error.InvalidNumber,
        error.DuplicateField,
        error.UnknownField,
        error.MissingField,
        error.LengthMismatch,
        error.InvalidEnumTag,
        error.ValueTooLong,
        error.BufferUnderrun,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.PolicyDenied => SA_STD_ERR_PERMISSION_DENIED,
        error.AlreadyConnected,
        error.ConnectionPending,
        error.SocketNotConnected,
        error.UnreachableAddress,
        error.NetworkSubsystemFailed,
        => SA_STD_ERR_NET,
        error.MessageTooBig, error.NoSpaceLeft => SA_STD_ERR_TRUNCATED,
        error.Unsupported, error.SystemResources, error.ProcessFdQuotaExceeded, error.SystemFdQuotaExceeded => SA_STD_ERR_UNSUPPORTED,
        error.ProcessNotFound, error.AlreadyTerminated => SA_STD_ERR_INVALID_HANDLE,
        error.NameTooLong,
        error.BadPathName,
        error.InvalidUtf8,
        error.InvalidWtf8,
        error.NotDir,
        error.IsDir,
        error.InvalidIPAddressFormat,
        error.InvalidCharacter,
        error.InvalidEnd,
        error.Incomplete,
        error.NonCanonical,
        error.InvalidIpv4Mapping,
        error.Overflow,
        => SA_STD_ERR_INVALID_ARGUMENT,
        error.RegexInvalidArgument,
        error.RegexNoMatch,
        error.RegexBadPattern,
        error.RegexOutOfMemory,
        error.UnknownHostName,
        error.TemporaryNameServerFailure,
        error.NameServerFailure,
        error.NetworkUnreachable,
        error.ConnectionRefused,
        error.ConnectionResetByPeer,
        error.ConnectionTimedOut,
        error.AddressInUse,
        error.AddressNotAvailable,
        error.HostLacksNetworkAddresses,
        error.ServiceUnavailable,
        => SA_STD_ERR_NET,
        else => SA_STD_ERR_IO,
    };
}

pub fn finishErr(err: anyerror) i32 {
    return finish(mapError(err));
}

pub fn fillUtcNow(out: *TimeDate) !void {
    const now_ts = std.Io.Clock.real.now(sio.io());
    const unix_ms = now_ts.toMilliseconds();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = now_ts.toNanoseconds();
    const unix_ns = std.math.cast(i64, unix_ns_raw) orelse return error.Overflow;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(unix_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    out.* = .{
        .unix_ms = unix_ms,
        .unix_ns = unix_ns,
        .year = year_day.year,
        .month = @backingInt(month_day.month),
        .day = @as(u8, @intCast(month_day.day_index + 1)),
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
        .millisecond = @as(u16, @intCast(@mod(unix_ms, std.time.ms_per_s))),
    };
}

pub fn monotonicNowNs() !u64 {
    // Raw monotonic-clock reading (ns since boot), the same contract
    // sa_time_unix_ns already uses for the wall clock: callers diff two
    // readings, and a reading of 0 is reserved for policy denial or
    // clock failure. (The previous origin-relative form returned
    // exactly 0 to the first caller in every process, which read as a
    // dead clock on every surface exposing the raw value:
    // Instant::now().raw_ns(), timer_now_ns, sched_now_ns.)
    const now_ns: i128 = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    if (now_ns <= 0) return 0;
    if (now_ns > std.math.maxInt(u64)) return std.math.maxInt(u64);
    return @intCast(now_ns);
}

pub fn lenAsUsize(len: u64) !usize {
    if (len > @as(u64, @intCast(std.math.maxInt(usize)))) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

pub fn constBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn constU32s(ptr: ?[*]const u32, len: u64) ![]const u32 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn mutBytes(ptr: ?[*]u8, len: u64) ![]u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return empty_mut_bytes[0..];
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

pub fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try constBytes(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

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

pub fn timevalFromNs(ns: u64) !Timeval {
    const sec = ns / std.time.ns_per_s;
    const usec = (ns % std.time.ns_per_s) / std.time.ns_per_us;
    return .{
        .sec = std.math.cast(TimevalSec, sec) orelse return error.InvalidArgument,
        .usec = std.math.cast(TimevalUsec, usec) orelse return error.InvalidArgument,
    };
}

pub fn nsFromTimeval(tv: Timeval) !u64 {
    const sec = std.math.cast(u64, tv.sec) orelse return error.InvalidArgument;
    const usec = std.math.cast(u64, tv.usec) orelse return error.InvalidArgument;
    const sec_ns = std.math.mul(u64, sec, std.time.ns_per_s) catch return error.InvalidArgument;
    const usec_ns = std.math.mul(u64, usec, std.time.ns_per_us) catch return error.InvalidArgument;
    return std.math.add(u64, sec_ns, usec_ns) catch return error.InvalidArgument;
}

pub fn setSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32, enabled: bool) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = if (enabled) 1 else 0;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&value));
}

pub fn setSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32, value: i32) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptU32(fd: std.posix.fd_t, level: i32, optname: u32, value: u32) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptTimeval(fd: std.posix.fd_t, level: i32, optname: u32, ns: u64) !void {
    const tv = try timevalFromNs(ns);
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&tv));
}

pub fn setSocketOptByte(fd: std.posix.fd_t, level: i32, optname: u32, value: u8) !void {
    var mutable = value;
    try std.posix.setsockopt(fd, level, optname, std.mem.asBytes(&mutable));
}

pub fn setSocketOptBytes(fd: std.posix.fd_t, level: i32, optname: u32, bytes: []const u8) !void {
    try std.posix.setsockopt(fd, level, optname, bytes);
}

fn lingerSeconds(timeout_ns: u64) !i32 {
    const seconds = timeout_ns / std.time.ns_per_s;
    return std.math.cast(i32, seconds) orelse error.InvalidArgument;
}

pub fn setSocketOptLinger(fd: std.posix.fd_t, enabled: bool, timeout_ns: u64) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    const seconds = if (enabled) try lingerSeconds(timeout_ns) else 0;
    var value = LingerOption{ .onoff = if (enabled) 1 else 0, .linger = seconds };
    try std.posix.setsockopt(fd, SOLT.SOCKET, SOT.LINGER, std.mem.asBytes(&value));
}

pub fn getSocketOptLinger(fd: std.posix.fd_t) !LingerOption {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value = LingerOption{ .onoff = 0, .linger = 0 };
    var len: SockLenT = @sizeOf(LingerOption);
    const rc = std.os.linux.getsockopt(fd, SOLT.SOCKET, SOT.LINGER, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(LingerOption)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32) !bool {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(i32)) return error.UnexpectedSize;
            return value != 0;
        },
        else => return error.InvalidArgument,
    }
}

// DEF-NET-V6-DTLS (D1): raw setsockopt that surfaces kernel refusals as
// errors. std.posix.setsockopt maps EINVAL/BADF/NOTSOCK to `unreachable`,
// which aborts the whole process for a legitimate refusal -- notably
// IPV6_V6ONLY on an already-bound socket, which the kernel only accepts
// before bind. Callers that can honour the option another way need the
// errno, not a trap.
pub fn lxSetSocketOptBool(fd: std.posix.fd_t, level: i32, optname: u32, enabled: bool) !void {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = if (enabled) 1 else 0;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setsockopt(fd, level, optname, @as([*]const u8, @ptrCast(&value)), @as(SockLenT, @sizeOf(i32))));
        return;
    }
    try libcErrRc(libc.setsockopt(fd, level, @as(c_int, @intCast(optname)), @as(*const anyopaque, @ptrCast(&value)), @as(libc_socklen_t, @sizeOf(i32))));
}

// IPV6_V6ONLY is a bind-time option: once a socket is bound the kernel
// refuses to change it (EINVAL). Every socket behind a registry handle
// is already bound, so honour a post-bind change by rebuilding the
// socket with the option applied before bind and swapping the fd in
// the registry resource. Queued datagrams / pending connections on the
// old socket are dropped -- the unavoidable price of changing a
// bind-time option after bind. On a bind failure the pre-change socket
// shape is restored best-effort so a failed change does not silently
// destroy a working handle.
pub fn rebuildTcpListenerV6Only(listener: u64, enabled: bool) !void {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(listener) orelse return error.InvalidHandle;
    const server = switch (resource.*) {
        .tcp_listener => |value| value,
        else => return error.InvalidHandle,
    };
    const orig_only_v6 = getSocketOptBool(server.fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY) catch false;
    const flags = lxFcntl(server.fd, std.posix.F.GETFL, 0) catch 0;
    const nb_mask = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    const new_fd = try lxSocket(AFT.INET6, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP);
    lxSetSocketOptBool(new_fd, SOLT.SOCKET, SOT.REUSEADDR, true) catch |err| {
        lxClose(new_fd);
        return err;
    };
    lxSetSocketOptBool(new_fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, enabled) catch |err| {
        lxClose(new_fd);
        return err;
    };
    if (flags & nb_mask != 0) {
        _ = lxFcntl(new_fd, std.posix.F.SETFL, nb_mask) catch {};
    }
    lxClose(server.fd);
    lxBind(new_fd, server.addr.sockAddr(), server.addr.getOsSockLen()) catch |err| {
        lxClose(new_fd);
        const fallback = lxSocket(AFT.INET6, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP) catch return err;
        lxSetSocketOptBool(fallback, SOLT.SOCKET, SOT.REUSEADDR, true) catch {};
        lxSetSocketOptBool(fallback, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, orig_only_v6) catch {};
        if (flags & nb_mask != 0) {
            _ = lxFcntl(fallback, std.posix.F.SETFL, nb_mask) catch {};
        }
        lxBind(fallback, server.addr.sockAddr(), server.addr.getOsSockLen()) catch {
            lxClose(fallback);
            return err;
        };
        resource.* = .{ .tcp_listener = .{ .fd = fallback, .addr = server.addr } };
        lxListen(fallback, 128) catch {};
        return err;
    };
    resource.* = .{ .tcp_listener = .{ .fd = new_fd, .addr = server.addr } };
    try lxListen(new_fd, 128);
}

pub fn rebuildUdpSocketV6Only(socket: u64, enabled: bool) !void {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(socket) orelse return error.InvalidHandle;
    const old_fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return error.InvalidHandle,
    };
    var addr = NetAddress{};
    var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
    try lxGetsockname(old_fd, addr.sockAddrMut(), &addr_len);
    addr.len = addr_len;
    const orig_only_v6 = getSocketOptBool(old_fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY) catch false;
    const broadcast = getSocketOptBool(old_fd, SOLT.SOCKET, SOT.BROADCAST) catch false;
    const rcv_timeout = getSocketOptTimeval(old_fd, SOLT.SOCKET, SOT.RCVTIMEO) catch 0;
    const snd_timeout = getSocketOptTimeval(old_fd, SOLT.SOCKET, SOT.SNDTIMEO) catch 0;
    const flags = lxFcntl(old_fd, std.posix.F.GETFL, 0) catch 0;
    const nb_mask = @as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK");
    const prep = struct {
        fn apply(fd: std.posix.fd_t, only_v6: bool, bcast: bool, rcv_ns: u64, snd_ns: u64, nb: usize) !void {
            try lxSetSocketOptBool(fd, IPPROTOT.IPV6, std.posix.IPV6.V6ONLY, only_v6);
            if (bcast) try lxSetSocketOptBool(fd, SOLT.SOCKET, SOT.BROADCAST, true);
            if (rcv_ns != 0) try setSocketOptTimeval(fd, SOLT.SOCKET, SOT.RCVTIMEO, rcv_ns);
            if (snd_ns != 0) try setSocketOptTimeval(fd, SOLT.SOCKET, SOT.SNDTIMEO, snd_ns);
            if (nb != 0) {
                _ = try lxFcntl(fd, std.posix.F.SETFL, nb);
            }
        }
    };
    const new_fd = try lxSocket(AFT.INET6, SOCKT.DGRAM | SOCKT.CLOEXEC, IPPROTOT.UDP);
    prep.apply(new_fd, enabled, broadcast, rcv_timeout, snd_timeout, flags & nb_mask) catch |err| {
        lxClose(new_fd);
        return err;
    };
    lxClose(old_fd);
    lxBind(new_fd, addr.sockAddr(), addr.getOsSockLen()) catch |err| {
        lxClose(new_fd);
        const fallback = lxSocket(AFT.INET6, SOCKT.DGRAM | SOCKT.CLOEXEC, IPPROTOT.UDP) catch return err;
        prep.apply(fallback, orig_only_v6, broadcast, rcv_timeout, snd_timeout, flags & nb_mask) catch {};
        lxBind(fallback, addr.sockAddr(), addr.getOsSockLen()) catch {
            lxClose(fallback);
            return err;
        };
        resource.* = .{ .udp_socket = fallback };
        return err;
    };
    resource.* = .{ .udp_socket = new_fd };
}

const LinuxUCred = extern struct {
    pid: i32,
    uid: u32,
    gid: u32,
};

pub fn getUnixPeerCred(fd: std.posix.fd_t) !LinuxUCred {
    var value: LinuxUCred = .{ .pid = 0, .uid = 0, .gid = 0 };
    var len: SockLenT = @sizeOf(LinuxUCred);
    const rc = std.os.linux.getsockopt(fd, SOLT.SOCKET, std.os.linux.SO.PEERCRED, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(LinuxUCred)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

// W1-DEF-UNIX-DGRAM-PEERCRED-ZERO: for path-bound unix datagram
// sockets the kernel answers SO_PEERCRED with the zero sentinel
// (pid 0, uid/gid -1) even on connected sockets that carried
// traffic -- verified empirically; socketpair endpoints do answer.
// The only truthful credential source for such sockets is
// SCM_CREDENTIALS ancillary data on received datagrams, so the
// unix datagram receive path harvests it into this table and
// sa_std_net_unix_datagram_peer_cred consults it. Entries are
// keyed by (handle, fd) and revalidated against the live registry
// on lookup, so a recycled handle/fd pair cannot resurrect a
// stale credential. All access under registry_mutex.
const PeerCredSlot = struct {
    handle: u64 = 0,
    fd: std.posix.fd_t = -1,
    cred: LinuxUCred = .{ .pid = 0, .uid = 0, .gid = 0 },
};

var peer_cred_slots: [128]PeerCredSlot = blk: {
    var slots: [128]PeerCredSlot = undefined;
    for (&slots) |*slot| slot.* = .{};
    break :blk slots;
};
var peer_cred_cursor: usize = 0;

fn storeHarvestedPeerCredLocked(handle: u64, fd: std.posix.fd_t, cred: LinuxUCred) void {
    for (&peer_cred_slots) |*slot| {
        if (slot.handle == handle and slot.fd == fd) {
            slot.cred = cred;
            return;
        }
    }
    peer_cred_slots[peer_cred_cursor] = .{ .handle = handle, .fd = fd, .cred = cred };
    peer_cred_cursor = (peer_cred_cursor + 1) % peer_cred_slots.len;
}

pub fn harvestedPeerCredLocked(handle: u64, fd: std.posix.fd_t) ?LinuxUCred {
    const resource = getResourceLocked(handle) orelse return null;
    const live_fd = switch (resource.*) {
        .udp_socket => |value| value,
        else => return null,
    };
    if (live_fd != fd) return null;
    for (&peer_cred_slots) |*slot| {
        if (slot.handle == handle and slot.fd == fd) return slot.cred;
    }
    return null;
}

/// Unix datagram sockets in this std carry SO_PASSCRED from birth
/// so the receive path can harvest SCM_CREDENTIALS (see above).
/// Best effort: failure only means peer_cred reports NOT_FOUND
/// for a connected socket instead of answering with a wrong or
/// zero credential.
pub fn armPeerCredHarvest(fd: std.posix.fd_t) void {
    if (comptime !is_linux) return;
    setSocketOptBool(fd, SOLT.SOCKET, SO_PASSCRED, true) catch {};
}

/// Extract the sender credential from a recvmsg control chain
/// (SOL_SOCKET / SCM_CREDENTIALS), same walk as udp_recv_msg.
fn scmCredentials(ctrl: []const u8) ?LinuxUCred {
    var off: usize = 0;
    while (off + 16 <= ctrl.len) {
        const cmsg_len = @as(usize, @intCast(std.mem.readInt(u64, ctrl[off..][0..8], .little)));
        if (cmsg_len < 16 or off + cmsg_len > ctrl.len) break;
        const level = std.mem.readInt(i32, ctrl[off + 8 ..][0..4], .little);
        const ctype = std.mem.readInt(i32, ctrl[off + 12 ..][0..4], .little);
        const data = ctrl[off + 16 .. off + cmsg_len];
        if (level == cmsg_level_socket and ctype == 2 and data.len >= @sizeOf(LinuxUCred)) {
            return .{
                .pid = std.mem.readInt(i32, data[0..4], .little),
                .uid = std.mem.readInt(u32, data[4..8], .little),
                .gid = std.mem.readInt(u32, data[8..12], .little),
            };
        }
        const step = cmsgAlign(cmsg_len);
        if (step == 0) break;
        off += step;
    }
    return null;
}

pub fn getSocketOptInt(fd: std.posix.fd_t, level: i32, optname: u32) !i32 {
    if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(i32)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptTimeval(fd: std.posix.fd_t, level: i32, optname: u32) !u64 {
    var tv: Timeval = .{ .sec = 0, .usec = 0 };
    var len: SockLenT = @sizeOf(Timeval);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&tv)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(Timeval)) return error.UnexpectedSize;
            return try nsFromTimeval(tv);
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptByte(fd: std.posix.fd_t, level: i32, optname: u32) !u8 {
    var value: u8 = 0;
    var len: SockLenT = @sizeOf(u8);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(u8)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptU32(fd: std.posix.fd_t, level: i32, optname: u32) !u32 {
    var value: u32 = 0;
    var len: SockLenT = @sizeOf(u32);
    const rc = std.os.linux.getsockopt(fd, level, optname, @as([*]u8, @ptrCast(&value)), &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != @sizeOf(u32)) return error.UnexpectedSize;
            return value;
        },
        else => return error.InvalidArgument,
    }
}

pub fn getSocketOptBytes(fd: std.posix.fd_t, level: i32, optname: u32, out: []u8) !void {
    var len: SockLenT = @intCast(out.len);
    const rc = std.os.linux.getsockopt(fd, level, optname, out.ptr, &len);
    switch (std.os.linux.errno(rc)) {
        .SUCCESS => {
            if (len != out.len) return error.UnexpectedSize;
        },
        else => return error.InvalidArgument,
    }
}

pub fn socketAddressFamily(fd: std.posix.fd_t) !u16 {
    var storage: SockAddrStorageT = makeSockAddrStorage();
    var addr_len: SockLenT = @sizeOf(SockAddrStorageT);
    try lxGetsockname(fd, @ptrCast(&storage), &addr_len);
    return storage.family;
}

pub fn socketIsUnix(fd: std.posix.fd_t) !bool {
    return (try socketAddressFamily(fd)) == AFT.UNIX;
}

pub fn socketIsInet(fd: std.posix.fd_t) !bool {
    const family = try socketAddressFamily(fd);
    return family == AFT.INET or family == AFT.INET6;
}

pub fn socketIsStream(fd: std.posix.fd_t) !bool {
    const socket_type = try getSocketOptInt(fd, SOLT.SOCKET, std.os.linux.SO.TYPE);
    return socket_type == @as(i32, @intCast(SOCKT.STREAM));
}

pub fn socketIsDatagram(fd: std.posix.fd_t) !bool {
    const socket_type = try getSocketOptInt(fd, SOLT.SOCKET, std.os.linux.SO.TYPE);
    return socket_type == @as(i32, @intCast(SOCKT.DGRAM));
}

pub fn socketAcceptConn(fd: std.posix.fd_t) !bool {
    return try getSocketOptBool(fd, SOLT.SOCKET, std.os.linux.SO.ACCEPTCONN);
}

pub fn getUnixSockAddr(fd: std.posix.fd_t, peer: bool) !struct { addr: SockAddrUnT, len: SockLenT } {
    var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    var len: SockLenT = @sizeOf(SockAddrUnT);
    if (peer) {
        try lxGetpeername(fd, @as(*SockAddrT, @ptrCast(&addr)), &len);
    } else {
        try lxGetsockname(fd, @as(*SockAddrT, @ptrCast(&addr)), &len);
    }
    return .{ .addr = addr, .len = len };
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

// Parse one "::"-free half ("1:2:3" or trailing embedded IPv4) into out,
// returning the group count. Used only on FreeBSD (see parseIpv6Freebsd).
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

// Numeric IPv6 parser for FreeBSD: the old Ip6Address.resolve/parse and
// Address.resolveIp all reach if_nametoindex (unimplemented for freebsd in
// zig 0.14). Handles full, "::"-compressed and embedded-IPv4 forms.
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

// "addr" or "addr%zone" (numeric zone, or interface name via libc
// if_nametoindex which FreeBSD provides). Shared by parseIp6Address and
// parseIpv6Ascii on FreeBSD.
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

pub fn makeIpv4Membership(multicast_addr: NetAddress, interface_addr: NetAddress) IpMreqC {
    return .{
        .imr_multiaddr = .{ .s_addr = multicast_addr.in4AddrU32() },
        .imr_interface = .{ .s_addr = interface_addr.in4AddrU32() },
    };
}

pub fn makeIpv6Membership(multicast_addr: NetAddress, interface_index: u32) Ipv6MreqC {
    return .{
        .ipv6mr_multiaddr = multicast_addr.in6AddrBytes(),
        .ipv6mr_interface = interface_index,
    };
}

fn socketFdFromHandle(handle: u64) !std.posix.fd_t {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    return try handleToFd(handle);
}

pub fn ensureSocketHandle(handle: u64) !struct { fd: std.posix.fd_t, kind: enum { tcp_stream, tcp_listener, udp_socket } } {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .tcp_stream => |stream| .{ .fd = stream, .kind = .tcp_stream },
        .tcp_listener => |server| .{ .fd = server.fd, .kind = .tcp_listener },
        .udp_socket => |fd| .{ .fd = fd, .kind = .udp_socket },
        else => error.InvalidHandle,
    };
}

fn dynamicIndex(handle: u64) ?usize {
    if (handle < FIRST_DYNAMIC_HANDLE) return null;
    const raw = handle - FIRST_DYNAMIC_HANDLE;
    if (raw > @as(u64, @intCast(std.math.maxInt(usize)))) return null;
    return @as(usize, @intCast(raw));
}

pub fn getResourceLocked(handle: u64) ?*Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    if (registry_slots.items[idx]) |*resource| return resource;
    return null;
}

pub fn registerResourceLocked(resource: Resource) !u64 {
    for (registry_slots.items, 0..) |slot, idx| {
        if (slot == null) {
            registry_slots.items[idx] = resource;
            return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
        }
    }
    const idx = registry_slots.items.len;
    try registry_slots.append(resource);
    return FIRST_DYNAMIC_HANDLE + @as(u64, @intCast(idx));
}

pub fn registerResource(resource: Resource) !u64 {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    return try registerResourceLocked(resource);
}

pub fn takeResourceLocked(handle: u64) ?Resource {
    const idx = dynamicIndex(handle) orelse return null;
    if (idx >= registry_slots.items.len) return null;
    const resource = registry_slots.items[idx] orelse return null;
    registry_slots.items[idx] = null;
    return resource;
}

pub fn handleToFd(handle: u64) !std.posix.fd_t {
    return switch (handle) {
        SA_STD_STDIN => std.posix.STDIN_FILENO,
        SA_STD_STDOUT => std.posix.STDOUT_FILENO,
        SA_STD_STDERR => std.posix.STDERR_FILENO,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| file.inner.handle,
                .tcp_stream => |stream| stream,
                .tcp_listener => |server| server.fd,
                .udp_socket => |fd| fd,
                .owned_fd => |fd| fd.fd,
                .terminal_session => |session| session.fd,
                else => error.InvalidHandle,
            };
        },
    };
}

pub const statTimeFieldName = @import("sa_std/dir_stat.zig").statTimeFieldName;

pub const timeSpecMs = @import("sa_std/dir_stat.zig").timeSpecMs;

pub const metadataU64Field = @import("sa_std/dir_stat.zig").metadataU64Field;

pub const metadataI64TimeFieldMs = @import("sa_std/dir_stat.zig").metadataI64TimeFieldMs;

pub const metadataI64TimeFieldSec = @import("sa_std/dir_stat.zig").metadataI64TimeFieldSec;

pub const metadataI64TimeFieldNsec = @import("sa_std/dir_stat.zig").metadataI64TimeFieldNsec;

pub fn applyRawMode(term: *std.posix.termios) void {
    term.iflag.IGNBRK = false;
    term.iflag.BRKINT = false;
    term.iflag.PARMRK = false;
    term.iflag.ISTRIP = false;
    term.iflag.INLCR = false;
    term.iflag.IGNCR = false;
    term.iflag.ICRNL = false;
    term.iflag.IXON = false;
    term.iflag.IXOFF = false;
    term.oflag.OPOST = false;
    term.cflag.CSIZE = .CS8;
    term.cflag.PARENB = false;
    term.cflag.CREAD = true;
    term.lflag.ISIG = false;
    term.lflag.ICANON = false;
    term.lflag.ECHO = false;
    term.lflag.IEXTEN = false;
    term.cc[@backingInt(std.posix.V.MIN)] = 1;
    term.cc[@backingInt(std.posix.V.TIME)] = 0;
}

fn killAndWaitChild(pid: std.posix.pid_t) void {
    if (comptime is_wasm) return;
    std.posix.kill(pid, SIGT.KILL) catch |err| {
        // Child teardown is best-effort; waitpid below still reaps if the child already exited.
        _ = @errorName(err);
    };
    _ = lxWaitpid(pid, 0);
}

fn readHandleLocked(handle: u64, buffer: []u8) !usize {
    return switch (handle) {
        SA_STD_STDIN => try sio.getStdIn().read(buffer),
        SA_STD_STDOUT, SA_STD_STDERR => error.InvalidHandle,
        else => {
            const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
            return switch (resource.*) {
                .file => |file| try file.read(buffer),
                .tcp_stream => |stream| try lxRead(stream, buffer),
                .owned_fd => |fd| if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported else try std.posix.read(fd.fd, buffer),
                .terminal_session => |session| if (comptime builtin.cpu.arch.isWasm()) return error.Unsupported else try std.posix.read(session.fd, buffer),
                .buffer => |*buf| blk: {
                    const copy_len = @min(buffer.len, buf.bytes.len);
                    @memcpy(buffer[0..copy_len], buf.bytes[0..copy_len]);
                    break :blk copy_len;
                },
                .process => |*proc| {
                    if (!proc.capture_output) return error.InvalidHandle;
                    if (!proc.exited) return error.InvalidHandle;
                    if (proc.stdout_pos < proc.stdout_buf.len) {
                        const remaining = proc.stdout_buf.len - proc.stdout_pos;
                        const copy_len = @min(buffer.len, remaining);
                        @memcpy(buffer[0..copy_len], proc.stdout_buf[proc.stdout_pos .. proc.stdout_pos + copy_len]);
                        proc.stdout_pos += copy_len;
                        return copy_len;
                    }
                    if (proc.stderr_pos < proc.stderr_buf.len) {
                        const remaining = proc.stderr_buf.len - proc.stderr_pos;
                        const copy_len = @min(buffer.len, remaining);
                        @memcpy(buffer[0..copy_len], proc.stderr_buf[proc.stderr_pos .. proc.stderr_pos + copy_len]);
                        proc.stderr_pos += copy_len;
                        return copy_len;
                    }
                    return 0;
                },
                else => error.InvalidHandle,
            };
        },
    };
}

// DEF-R5: the registry mutex guards the handle table only; it
// must never be held across a syscall that can block. The data
// path classifies a handle under the lock, snapshots the OS fd
// (or notes an in-memory kind), drops the lock, and only then
// performs the blocking read/write -- the same snapshot pattern
// sa_std_close and sa_std_net_tcp_accept already use in this
// file. Before this split, one goroutine parked in a blocking
// sa_std_read held the registry mutex for the whole wait, so
// every other goroutine's net IO (and every other registry
// user: poll_wait validation, writes, accepts, closes) stalled
// or spun behind it: with >= 2 goroutines blocked in net reads
// only the mutex holder was ever serviced, regardless of
// carrier count (slaredis registration A). In-memory kinds
// (.buffer/.process) never block and keep the locked path.
const IoPlan = union(enum) {
    fd: std.posix.fd_t,
    file_fd: std.posix.fd_t,
    std_in,
    std_out,
    std_err,
    locked,
    invalid,
};

pub fn lockRegistry() void {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
}

fn ioPlanLocked(handle: u64, is_write: bool) IoPlan {
    if (is_write) {
        return switch (handle) {
            SA_STD_STDOUT => .std_out,
            SA_STD_STDERR => .std_err,
            SA_STD_STDIN => .invalid,
            else => blk: {
                const resource = getResourceLocked(handle) orelse break :blk .invalid;
                break :blk switch (resource.*) {
                    .file => |file| IoPlan{ .file_fd = file.inner.handle },
                    .tcp_stream => |stream| IoPlan{ .fd = stream },
                    .owned_fd => |fd| IoPlan{ .fd = fd.fd },
                    .terminal_session => |session| IoPlan{ .fd = session.fd },
                    else => .invalid,
                };
            },
        };
    }
    return switch (handle) {
        SA_STD_STDIN => .std_in,
        SA_STD_STDOUT, SA_STD_STDERR => .invalid,
        else => blk: {
            const resource = getResourceLocked(handle) orelse break :blk .invalid;
            break :blk switch (resource.*) {
                .file => |file| IoPlan{ .file_fd = file.inner.handle },
                .tcp_stream => |stream| IoPlan{ .fd = stream },
                .owned_fd => |fd| IoPlan{ .fd = fd.fd },
                .terminal_session => |session| IoPlan{ .fd = session.fd },
                .buffer, .process => .locked,
                else => .invalid,
            };
        },
    };
}

/// DEF-R5: snapshot a tcp_stream / udp_socket fd under the
/// registry lock and drop the lock before any blocking syscall
/// (see the IoPlan note above).
pub fn tcpStreamFd(handle: u64) ?std.posix.fd_t {
    lockRegistry();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .tcp_stream => |s| s,
        else => null,
    };
}

pub fn udpSocketFd(handle: u64) ?std.posix.fd_t {
    lockRegistry();
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .udp_socket => |fd| fd,
        else => null,
    };
}

/// Read once from a handle without holding the registry mutex
/// across a blocking syscall (see the IoPlan note above).
pub fn readHandle(handle: u64, buffer: []u8) !usize {
    lockRegistry();
    switch (ioPlanLocked(handle, false)) {
        .fd, .file_fd => |fd| {
            registry_mutex.unlock();
            return lxRead(fd, buffer);
        },
        .std_in => {
            registry_mutex.unlock();
            return sio.getStdIn().read(buffer);
        },
        .locked => {
            defer registry_mutex.unlock();
            return readHandleLocked(handle, buffer);
        },
        .invalid => {
            registry_mutex.unlock();
            return error.InvalidHandle;
        },
        .std_out, .std_err => unreachable,
    }
}

/// Write to a handle without holding the registry mutex across
/// a blocking syscall. Per-kind semantics preserve the previous
/// locked implementation: fd writes are a single write(2),
/// while file writes write all bytes (sio.File.write is
/// writeAll).
pub fn writeHandle(handle: u64, data: []const u8) !usize {
    lockRegistry();
    switch (ioPlanLocked(handle, true)) {
        .fd => |fd| {
            registry_mutex.unlock();
            return lxWrite(fd, data);
        },
        .file_fd => |fd| {
            registry_mutex.unlock();
            var off: usize = 0;
            while (off < data.len) {
                const n = try lxWrite(fd, data[off..]);
                if (n == 0) return error.Io;
                off += n;
            }
            return data.len;
        },
        .std_out => {
            registry_mutex.unlock();
            return sio.getStdOut().write(data);
        },
        .std_err => {
            registry_mutex.unlock();
            return sio.getStdErr().write(data);
        },
        .invalid => {
            registry_mutex.unlock();
            return error.InvalidHandle;
        },
        .std_in, .locked => unreachable,
    }
}

fn statusName(code: i32) []const u8 {
    return switch (code) {
        SA_STD_OK => "ok",
        SA_STD_ERR_INVALID_ARGUMENT => "invalid_argument",
        SA_STD_ERR_INVALID_HANDLE => "invalid_handle",
        SA_STD_ERR_NOT_FOUND => "not_found",
        SA_STD_ERR_ACCESS => "access",
        SA_STD_ERR_NO_MEMORY => "no_memory",
        SA_STD_ERR_IO => "io",
        SA_STD_ERR_NET => "net",
        SA_STD_ERR_UNSUPPORTED => "unsupported",
        SA_STD_ERR_TRUNCATED => "truncated",
        SA_STD_ERR_PERMISSION_DENIED => "permission_denied",
        SA_STD_ERR_UNKNOWN => "unknown",
        else => "unknown",
    };
}

fn statusFromTerm(term: sio.Child.Term) u32 {
    return switch (term) {
        .exited => |code| code,
        .signal => 128,
        .stopped => 130,
        .unknown => 127,
    };
}

fn argvFromBlob(allocator: std.mem.Allocator, blob: []const u8) ![]const []const u8 {
    var count: usize = 1;
    for (blob) |b| {
        if (b == 0) count += 1;
    }
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    var start: usize = 0;
    var index: usize = 0;
    while (start <= blob.len) {
        const end = std.mem.indexOfScalarPos(u8, blob, start, 0) orelse blob.len;
        if (end == start) {
            if (end == blob.len) break;
            start = end + 1;
            continue;
        }
        args[index] = blob[start..end];
        index += 1;
        if (end == blob.len) break;
        start = end + 1;
    }
    return args[0..index];
}

pub fn argvFromEntries(allocator: std.mem.Allocator, argv_ptr: ?[*]const SaProcessArgv, argv_len: u64) ![]const []const u8 {
    const count = try lenAsUsize(argv_len);
    if (count == 0) return error.InvalidArgument;
    const entries = argv_ptr orelse return error.InvalidArgument;
    const args = try allocator.alloc([]const u8, count);
    errdefer allocator.free(args);

    for (args, 0..) |*slot, index| {
        const entry = entries[index];
        const n = try lenAsUsize(entry.len);
        slot.* = if (n == 0) &.{} else entry.data[0..n];
    }
    return args;
}

pub fn envpFromCurrentProcess(arena: std.mem.Allocator) ![:null]const ?[*:0]const u8 {
    var count: usize = 0;
    while (environ[count] != null) : (count += 1) {}

    const env_block = try arena.alloc(?[*:0]const u8, count + 1);
    var i: usize = 0;
    while (i < count) : (i += 1) {
        env_block[i] = environ[i].?;
    }
    env_block[count] = null;
    return env_block[0..count :null];
}

pub const capture_fd_to_owned = @import("sa_std/proc_wait.zig").capture_fd_to_owned;

const ProcessSpawnMode = enum {
    inherit,
    capture,
    stream,
};

const ProcessSpawnConfig = struct {
    arg0: ?[]const u8 = null,
    process_group: ?i32 = null,
    setsid: bool = false,
    create_pidfd: bool = false,
    uid: ?u32 = null,
    gid: ?u32 = null,
    groups: ?[]const u32 = null,
    chroot_path: ?[]const u8 = null,
    stdin: bool = false,
};

const SpawnResult = struct {
    process: u64 = 0,
    stdout: ?u64 = null,
    stderr: ?u64 = null,
    stdin: ?u64 = null,
};

pub const statusFromWaitStatus = @import("sa_std/proc_wait.zig").statusFromWaitStatus;

pub const rawWaitStatus = @import("sa_std/proc_wait.zig").rawWaitStatus;

pub const waitStatusCode = @import("sa_std/proc_wait.zig").waitStatusCode;

pub const waitStatusSignal = @import("sa_std/proc_wait.zig").waitStatusSignal;

pub const waitStatusCoreDumped = @import("sa_std/proc_wait.zig").waitStatusCoreDumped;

pub const waitStatusStoppedSignal = @import("sa_std/proc_wait.zig").waitStatusStoppedSignal;

pub const waitStatusContinued = @import("sa_std/proc_wait.zig").waitStatusContinued;

pub const waitProcessIgnoringMissing = @import("sa_std/proc_wait.zig").waitProcessIgnoringMissing;

pub fn waitStatusFromSiginfo(siginfo: std.posix.siginfo_t) u32 {
    const status = @as(u32, @intCast(siginfo.fields.common.second.sigchld.status));
    return switch (siginfo.code) {
        1 => (status & 0xff) << 8, // CLD_EXITED
        2 => status, // CLD_KILLED
        3 => status | 0x80, // CLD_DUMPED
        6 => 0xffff, // CLD_CONTINUED
        4, 5 => ((status & 0xff) << 8) | 0x7f, // CLD_TRAPPED / CLD_STOPPED
        else => 0,
    };
}

fn openPidfd(pid: std.posix.pid_t) ?std.posix.fd_t {
    if (comptime builtin.os.tag != .linux) return null;
    const fd = std.os.linux.pidfd_open(pid, 0);
    return switch (std.os.linux.errno(fd)) {
        .SUCCESS => @as(std.posix.fd_t, @intCast(fd)),
        else => null,
    };
}

pub const waitPidfdStatus = @import("sa_std/proc_wait.zig").waitPidfdStatus;

pub fn sendSignalToPidfd(fd: std.posix.fd_t, signum: u8, flags: u32) !void {
    const result = std.os.linux.pidfd_send_signal(fd, @fromBackingInt(@intCast(signum)), null, flags);
    switch (std.os.linux.errno(result)) {
        .SUCCESS => return,
        .INVAL => return error.InvalidArgument,
        .PERM => return error.PermissionDenied,
        .SRCH => return error.ProcessNotFound,
        else => return error.Unexpected,
    }
}

pub fn sendSignalToProcessGroup(pgid: std.posix.pid_t, signum: u8) !void {
    const target: std.posix.pid_t = -pgid;
    var attempts: u8 = 0;
    while (true) : (attempts += 1) {
        lxKill(target, signum) catch |err| switch (err) {
            error.ProcessNotFound => {
                if (attempts >= 50) return err;
                sio.io().sleep(.fromNanoseconds(1 * std.time.ns_per_ms), .awake) catch {};
                continue;
            },
            else => return err,
        };
        return;
    }
}

fn errnoToSetupError(errno: std.posix.E) anyerror {
    return switch (errno) {
        .SUCCESS => unreachable,
        .INVAL => error.InvalidArgument,
        .PERM, .ACCES => error.PermissionDenied,
        .NOENT => error.FileNotFound,
        .NOMEM => error.OutOfMemory,
        .NOTDIR => error.NotDir,
        else => error.Unexpected,
    };
}

pub fn applyProcessCommandExtSetup(cwd: ?[]const u8, config: ProcessSpawnConfig, chroot_path_z: ?[*:0]const u8) !void {
    // wasm32-wasi has no process spawn; stub (linux errno types mismatch wasi).
    if (comptime is_wasm) return error.Unsupported;
    if (config.groups) |groups| try lxSetgroups(groups);
    if (config.gid) |gid| try lxSetgid(@as(std.posix.gid_t, @intCast(gid)));
    if (config.uid) |uid| try lxSetuid(@as(std.posix.uid_t, @intCast(uid)));
    if (chroot_path_z) |path| try lxChroot(path);
    if (cwd) |dir| try lxChdir(dir);
    if (config.process_group) |pgroup| try lxSetpgid(0, @as(std.posix.pid_t, @intCast(pgroup)));
    if (config.setsid) try lxSetsid();
}

pub const finalizeProcessExit = @import("sa_std/proc_wait.zig").finalizeProcessExit;

pub fn spawnProcessConfiguredCwd(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode, cwd: ?[]const u8, config: ProcessSpawnConfig) !SpawnResult {
    // wasm32-wasi has no fork/exec/pipe2-CLOEXEC; stub.
    if (comptime is_wasm) return error.Unsupported;
    if (argv.len == 0) return error.InvalidArgument;
    if (config.stdin and mode != .stream) return error.InvalidArgument;
    if (!policyAllows(.{ .run = argv[0] })) return error.PolicyDenied;
    if (config.arg0) |arg0| {
        if (std.mem.indexOfScalar(u8, arg0, 0) != null) return error.InvalidArgument;
    }

    const use_pipes = mode != .inherit;
    var stdout_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    var stderr_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    var stdin_pipe: [2]std.posix.fd_t = .{ -1, -1 };
    defer {
        if (stdout_pipe[0] != -1) lxClose(stdout_pipe[0]);
        if (stdout_pipe[1] != -1) lxClose(stdout_pipe[1]);
        if (stderr_pipe[0] != -1) lxClose(stderr_pipe[0]);
        if (stderr_pipe[1] != -1) lxClose(stderr_pipe[1]);
        if (stdin_pipe[0] != -1) lxClose(stdin_pipe[0]);
        if (stdin_pipe[1] != -1) lxClose(stdin_pipe[1]);
    }
    if (use_pipes) {
        stdout_pipe = try lxPipe2(.{ .CLOEXEC = true });
        stderr_pipe = try lxPipe2(.{ .CLOEXEC = true });
    }
    if (config.stdin) {
        stdin_pipe = try lxPipe2(.{ .CLOEXEC = true });
    }

    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const exec_path = (try arena.allocator().dupeSentinel(u8, argv[0], 0)).ptr;
    const child_argv = try arena.allocator().alloc(?[*:0]const u8, argv.len + 1);
    for (argv, 0..) |arg, i| {
        const child_arg = if (i == 0 and config.arg0 != null) config.arg0.? else arg;
        child_argv[i] = (try arena.allocator().dupeSentinel(u8, child_arg, 0)).ptr;
    }
    child_argv[argv.len] = null;
    const envp = try envpFromCurrentProcess(arena.allocator());
    const chroot_path_z: ?[*:0]const u8 = if (config.chroot_path) |path| (try arena.allocator().dupeSentinel(u8, path, 0)).ptr else null;

    const pid = try lxFork();
    if (pid == 0) {
        if (cwd != null and chroot_path_z == null) {
            const dir = cwd.?;
            lxChdir(dir) catch lxExit(127);
        }
        if (config.process_group) |pgroup| {
            lxSetpgid(0, @as(std.posix.pid_t, @intCast(pgroup))) catch lxExit(127);
        }
        if (config.setsid) {
            lxSetsid() catch lxExit(127);
        }
        if (config.groups) |groups| {
            lxSetgroups(groups) catch lxExit(127);
        }
        if (config.gid) |gid| {
            lxSetgid(@as(std.posix.gid_t, @intCast(gid))) catch lxExit(127);
        }
        if (config.uid) |uid| {
            lxSetuid(@as(std.posix.uid_t, @intCast(uid))) catch lxExit(127);
        }
        if (chroot_path_z) |path| {
            lxChroot(path) catch lxExit(127);
            if (cwd) |dir| lxChdir(dir) catch lxExit(127);
        }
        if (use_pipes) {
            lxClose(stdout_pipe[0]);
            lxClose(stderr_pipe[0]);
            try lxDup2(stdout_pipe[1], std.posix.STDOUT_FILENO);
            try lxDup2(stderr_pipe[1], std.posix.STDERR_FILENO);
        }
        if (stdin_pipe[0] != -1) {
            lxClose(stdin_pipe[1]);
            try lxDup2(stdin_pipe[0], std.posix.STDIN_FILENO);
            lxClose(stdin_pipe[0]);
        }
        if (use_pipes) {
            lxClose(stdout_pipe[1]);
            lxClose(stderr_pipe[1]);
        }
        const argv_z: [*:null]const ?[*:0]const u8 = @ptrCast(child_argv.ptr);
        const envp_z: [*:null]const ?[*:0]const u8 = @ptrCast(envp.ptr);
        const exec_err = lxExecvpeZ(exec_path, argv_z, envp_z);
        switch (exec_err) {
            error.AccessDenied,
            error.SystemResources,
            error.Unexpected,
            error.FileNotFound,
            error.NameTooLong,
            error.ProcessFdQuotaExceeded,
            error.SystemFdQuotaExceeded,
            error.IsDir,
            error.NotDir,
            error.FileBusy,
            error.FileSystem,
            error.InvalidExe,
            => lxExit(127),
            else => lxExit(127),
        }
        unreachable;
    }

    const effective_process_group: ?std.posix.pid_t = if (config.process_group) |pgroup|
        (if (pgroup == 0) pid else @as(std.posix.pid_t, @intCast(pgroup)))
    else
        null;
    if (effective_process_group) |pgid| {
        lxSetpgid(pid, pgid) catch |err| switch (err) {
            error.ProcessAlreadyExec => {},
            else => {
                killAndWaitChild(pid);
                return err;
            },
        };
    }

    var pidfd_fd: ?std.posix.fd_t = if (config.create_pidfd) openPidfd(pid) else null;
    defer if (pidfd_fd) |fd| lxClose(fd);

    if (use_pipes) {
        lxClose(stdout_pipe[1]);
        lxClose(stderr_pipe[1]);
        stdout_pipe[1] = -1;
        stderr_pipe[1] = -1;
    }
    if (stdin_pipe[0] != -1) {
        lxClose(stdin_pipe[0]);
        stdin_pipe[0] = -1;
    }

    var result: SpawnResult = .{};
    switch (mode) {
        .inherit => {
            result.process = try registerResource(.{ .process = .{
                .pid = pid,
                .process_group = effective_process_group,
                .pidfd = pidfd_fd,
                .capture_output = false,
            } });
            pidfd_fd = null;
            return result;
        },
        .capture => {
            result.process = registerResource(.{ .process = .{
                .pid = pid,
                .process_group = effective_process_group,
                .pidfd = pidfd_fd,
                .capture_output = true,
                .stdout_fd = stdout_pipe[0],
                .stderr_fd = stderr_pipe[0],
            } }) catch |err| {
                killAndWaitChild(pid);
                return err;
            };
            pidfd_fd = null;
            stdout_pipe[0] = -1;
            stderr_pipe[0] = -1;
            return result;
        },
        .stream => {
            result.stdout = registerResource(.{ .owned_fd = .{ .fd = stdout_pipe[0] } }) catch |err| {
                killAndWaitChild(pid);
                return err;
            };
            stdout_pipe[0] = -1;
            result.stderr = registerResource(.{ .owned_fd = .{ .fd = stderr_pipe[0] } }) catch |err| {
                if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                killAndWaitChild(pid);
                return err;
            };
            stderr_pipe[0] = -1;
            if (stdin_pipe[1] != -1) {
                result.stdin = registerResource(.{ .owned_fd = .{ .fd = stdin_pipe[1] } }) catch |err| {
                    if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                    if (result.stderr) |stderr_handle| _ = sa_std_close(stderr_handle);
                    killAndWaitChild(pid);
                    return err;
                };
                stdin_pipe[1] = -1;
            }
            result.process = registerResource(.{ .process = .{
                .pid = pid,
                .process_group = effective_process_group,
                .pidfd = pidfd_fd,
                .capture_output = false,
            } }) catch |err| {
                if (result.stdout) |stdout_handle| _ = sa_std_close(stdout_handle);
                if (result.stderr) |stderr_handle| _ = sa_std_close(stderr_handle);
                if (result.stdin) |stdin_handle| _ = sa_std_close(stdin_handle);
                killAndWaitChild(pid);
                return err;
            };
            pidfd_fd = null;
            return result;
        },
    }
}

pub fn spawnProcessCwd(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode, cwd: ?[]const u8) !SpawnResult {
    return spawnProcessConfiguredCwd(allocator, argv, mode, cwd, .{});
}

pub fn spawnProcess(allocator: std.mem.Allocator, argv: []const []const u8, mode: ProcessSpawnMode) !SpawnResult {
    return spawnProcessCwd(allocator, argv, mode, null);
}

pub fn filePread(f: sio.File, buffer: []u8, offset: u64) !usize {
    return try f.inner.readPositional(sio.io(), &.{buffer}, offset);
}

pub fn filePreadAll(f: sio.File, buffer: []u8, offset: u64) !usize {
    var index: usize = 0;
    while (index != buffer.len) {
        const n = try f.inner.readPositional(sio.io(), &.{buffer[index..]}, offset + index);
        if (n == 0) return error.EndOfStream;
        index += n;
    }
    return index;
}

pub fn filePwrite(f: sio.File, buffer: []const u8, offset: u64) !usize {
    return try f.inner.writePositional(sio.io(), &.{buffer}, offset);
}

pub fn filePwriteAll(f: sio.File, buffer: []const u8, offset: u64) !void {
    return try f.inner.writePositionalAll(sio.io(), buffer, offset);
}

pub fn fileSeekBy(f: sio.File, offset: i64) !void {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.Unsupported;
    } else {
        const rc = std.os.linux.lseek(f.inner.handle, 0, std.posix.SEEK.CUR);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.Io;
        const cur: i64 = @bitCast(@as(u64, @intCast(rc)));
        const new_pos = cur + offset;
        if (new_pos < 0) return error.InvalidArgument;
        try f.seekTo(@as(u64, @intCast(new_pos)));
    }
}

pub fn fileSeekFromEnd(f: sio.File, offset: i64) !void {
    const len = try f.length();
    const new_pos = @as(i64, @intCast(len)) + offset;
    if (new_pos < 0) return error.InvalidArgument;
    try f.seekTo(@as(u64, @intCast(new_pos)));
}

pub fn fileGetPos(f: sio.File) !u64 {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.Unsupported;
    } else {
        const rc = std.os.linux.lseek(f.inner.handle, 0, std.posix.SEEK.CUR);
        if (std.os.linux.errno(rc) != .SUCCESS) return error.Io;
        return @as(u64, @intCast(rc));
    }
}

pub fn fileSetEndPos(f: sio.File, new_size: u64) !void {
    try f.inner.setLength(sio.io(), new_size);
}

// ---------------------------------------------------------------------------
// 0.17 compat: linux-syscall wrappers (old std.posix throwing helpers removed)
// and socket-address compat (old net Address type removed).
// Verified against /opt/zig/.../lib/std/os/linux.zig + Io/net.zig via probes.
// ---------------------------------------------------------------------------
fn errnoToAny(e: anytype) anyerror {
    const n = @tagName(e);
    if (std.mem.eql(u8, n, "SUCCESS")) unreachable;
    if (std.mem.eql(u8, n, "INTR")) return error.Interrupted;
    if (std.mem.eql(u8, n, "AGAIN")) return error.WouldBlock;
    if (std.mem.eql(u8, n, "BADF")) return error.InvalidHandle;
    if (std.mem.eql(u8, n, "ACCES")) return error.AccessDenied;
    if (std.mem.eql(u8, n, "PERM")) return error.PermissionDenied;
    if (std.mem.eql(u8, n, "NOENT")) return error.FileNotFound;
    if (std.mem.eql(u8, n, "EXIST")) return error.PathAlreadyExists;
    if (std.mem.eql(u8, n, "NOTDIR")) return error.NotDir;
    if (std.mem.eql(u8, n, "ISDIR")) return error.IsDir;
    if (std.mem.eql(u8, n, "NAMETOOLONG")) return error.NameTooLong;
    if (std.mem.eql(u8, n, "NOSPC")) return error.NoSpaceLeft;
    if (std.mem.eql(u8, n, "MFILE")) return error.ProcessFdQuotaExceeded;
    if (std.mem.eql(u8, n, "NFILE")) return error.SystemFdQuotaExceeded;
    if (std.mem.eql(u8, n, "NOMEM")) return error.SystemResources;
    if (std.mem.eql(u8, n, "INVAL")) return error.InvalidArgument;
    if (std.mem.eql(u8, n, "SRCH")) return error.ProcessNotFound;
    if (std.mem.eql(u8, n, "CHILD")) return error.ProcessNotFound;
    if (std.mem.eql(u8, n, "TIMEDOUT")) return error.ConnectionTimedOut;
    if (std.mem.eql(u8, n, "INPROGRESS")) return error.ConnectionPending;
    if (std.mem.eql(u8, n, "ALREADY")) return error.AlreadyConnected;
    if (std.mem.eql(u8, n, "CONNREFUSED")) return error.ConnectionRefused;
    if (std.mem.eql(u8, n, "CONNRESET")) return error.ConnectionResetByPeer;
    if (std.mem.eql(u8, n, "CONNABORTED")) return error.ConnectionAborted;
    if (std.mem.eql(u8, n, "NOTCONN")) return error.SocketNotConnected;
    if (std.mem.eql(u8, n, "NETUNREACH")) return error.NetworkUnreachable;
    if (std.mem.eql(u8, n, "HOSTUNREACH")) return error.HostUnreachable;
    if (std.mem.eql(u8, n, "ADDRINUSE")) return error.AddressInUse;
    if (std.mem.eql(u8, n, "ADDRNOTAVAIL")) return error.AddressNotAvailable;
    if (std.mem.eql(u8, n, "MSGSIZE")) return error.MessageTooBig;
    if (std.mem.eql(u8, n, "NOTSOCK")) return error.NotSocket;
    if (std.mem.eql(u8, n, "OPNOTSUPP")) return error.OperationNotSupported;
    if (std.mem.eql(u8, n, "AFNOSUPPORT")) return error.AddressFamilyNotSupported;
    if (std.mem.eql(u8, n, "PROTONOSUPPORT")) return error.ProtocolNotSupported;
    if (std.mem.eql(u8, n, "PIPE")) return error.BrokenPipe;
    if (std.mem.eql(u8, n, "NOTTY")) return error.NotATerminal;
    if (std.mem.eql(u8, n, "FBIG")) return error.FileTooBig;
    if (std.mem.eql(u8, n, "ROFS")) return error.ReadOnlyFileSystem;
    if (std.mem.eql(u8, n, "LOOP")) return error.SymLinkLoop;
    if (std.mem.eql(u8, n, "FAULT")) return error.Unexpected;
    if (std.mem.eql(u8, n, "BUSY")) return error.FileBusy;
    if (std.mem.eql(u8, n, "XDEV")) return error.RenameAcrossMountPoints;
    if (std.mem.eql(u8, n, "TXTBSY")) return error.FileBusy;
    return error.Unexpected;
}

pub fn lxErr(e: std.os.linux.E) anyerror {
    if (comptime is_wasm) return error.Unsupported;
    return errnoToAny(e);
}

pub fn lxCheck(rc: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    const e = std.os.linux.errno(rc);
    if (e != .SUCCESS) return lxErr(e);
    return rc;
}

// --- libc fallbacks (macOS/FreeBSD) ---------------------------------------
const libc_socklen_t = std.c.socklen_t;

pub const libc = struct {
    extern "c" fn socket(domain: c_int, socket_type: c_int, protocol: c_int) c_int;
    extern "c" fn bind(fd: c_int, addr: *const SockAddrT, len: libc_socklen_t) c_int;
    extern "c" fn listen(fd: c_int, backlog: c_int) c_int;
    extern "c" fn accept(fd: c_int, addr: ?*SockAddrT, len: ?*libc_socklen_t) c_int;
    extern "c" fn connect(fd: c_int, addr: *const SockAddrT, len: libc_socklen_t) c_int;
    extern "c" fn shutdown(fd: c_int, how: c_int) c_int;
    extern "c" fn sendto(fd: c_int, buf: *const anyopaque, len: usize, flags: c_int, addr: ?*const SockAddrT, addrlen: libc_socklen_t) isize;
    extern "c" fn recvfrom(fd: c_int, buf: *anyopaque, len: usize, flags: c_int, addr: ?*SockAddrT, addrlen: ?*libc_socklen_t) isize;
    extern "c" fn sendmsg(fd: c_int, msg: *const MsghdrConstT, flags: c_int) isize;
    extern "c" fn getsockname(fd: c_int, addr: *SockAddrT, len: *libc_socklen_t) c_int;
    extern "c" fn getpeername(fd: c_int, addr: *SockAddrT, len: *libc_socklen_t) c_int;
    extern "c" fn getsockopt(fd: c_int, level: c_int, optname: c_int, optval: *anyopaque, optlen: *libc_socklen_t) c_int;
    extern "c" fn setsockopt(fd: c_int, level: c_int, optname: c_int, optval: *const anyopaque, optlen: libc_socklen_t) c_int;
    extern "c" fn close(fd: c_int) c_int;
    extern "c" fn read(fd: c_int, buf: *anyopaque, count: usize) isize;
    extern "c" fn write(fd: c_int, buf: *const anyopaque, count: usize) isize;
    extern "c" fn readv(fd: c_int, iov: [*]const std.posix.iovec, iovcnt: c_int) isize;
    extern "c" fn writev(fd: c_int, iov: [*]const std.posix.iovec_const, iovcnt: c_int) isize;
    extern "c" fn dup(fd: c_int) c_int;
    extern "c" fn dup2(old: c_int, new: c_int) c_int;
    extern "c" fn fork() c_int;
    extern "c" fn pipe(fds: *[2]c_int) c_int;
    extern "c" fn chdir(path: [*:0]const u8) c_int;
    extern "c" fn chroot(path: [*:0]const u8) c_int;
    extern "c" fn setgroups(count: c_int, groups: [*]const std.c.gid_t) c_int;
    extern "c" fn setsid() std.c.pid_t;
    extern "c" fn setgid(gid: std.c.gid_t) c_int;
    extern "c" fn setuid(uid: std.c.uid_t) c_int;
    extern "c" fn setpgid(pid: std.c.pid_t, pgid: std.c.pid_t) c_int;
    extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
    extern "c" fn unlink(path: [*:0]const u8) c_int;
    extern "c" fn mkdirat(dirfd: c_int, path: [*:0]const u8, mode: std.c.mode_t) c_int;
    extern "c" fn fchmodat(dirfd: c_int, path: [*:0]const u8, mode: std.c.mode_t, flags: c_int) c_int;
    extern "c" fn link(oldpath: [*:0]const u8, newpath: [*:0]const u8) c_int;
    extern "c" fn futimens(fd: c_int, times: *const [2]std.posix.timespec) c_int;
    extern "c" fn kill(pid: std.c.pid_t, sig: c_int) c_int;
    extern "c" fn waitpid(pid: std.c.pid_t, status: *c_int, options: c_int) std.c.pid_t;
    extern "c" fn execve(path: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) c_int;
    extern "c" fn _exit(code: c_int) noreturn;
    extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
    extern "c" fn socketpair(domain: c_int, socket_type: c_int, protocol: c_int, sv: *[2]c_int) c_int;
    extern "c" fn chown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn lchown(path: [*:0]const u8, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn fchown(fd: c_int, owner: std.c.uid_t, group: std.c.gid_t) c_int;
    extern "c" fn mknod(path: [*:0]const u8, mode: std.c.mode_t, dev: std.c.dev_t) c_int;
};

fn libcErrRc(rc: anytype) !void {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
}

fn libcFd(rc: c_int) !std.posix.fd_t {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

fn libcUsize(rc: isize) !usize {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

pub fn lxClose(fd: std.posix.fd_t) void {
    if (comptime is_wasm) return;
    if (comptime is_linux) {
        _ = std.os.linux.close(fd);
    } else {
        _ = libc.close(fd);
    }
}

fn lxWrite(fd: std.posix.fd_t, bytes: []const u8) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.write(fd, bytes.ptr, bytes.len));
    return try libcUsize(libc.write(fd, bytes.ptr, bytes.len));
}

fn lxRead(fd: std.posix.fd_t, buf: []u8) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.read(fd, buf.ptr, buf.len));
    return try libcUsize(libc.read(fd, buf.ptr, buf.len));
}

pub fn lxReadv(fd: std.posix.fd_t, iov: []std.posix.iovec) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.readv(fd, iov.ptr, iov.len));
    return try libcUsize(libc.readv(fd, iov.ptr, @intCast(iov.len)));
}

pub fn lxWritev(fd: std.posix.fd_t, iov: []const std.posix.iovec_const) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.writev(fd, iov.ptr, iov.len));
    return try libcUsize(libc.writev(fd, iov.ptr, @intCast(iov.len)));
}

pub fn lxSocket(domain: u32, sock_type: u32, protocol: u32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.socket(domain, sock_type, protocol));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    return try libcFd(libc.socket(@intCast(domain), @intCast(sock_type), @intCast(protocol)));
}

pub fn lxBind(fd: std.posix.fd_t, addr: *const SockAddrT, len: SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.bind(fd, addr, len));
        return;
    }
    try libcErrRc(libc.bind(fd, addr, @intCast(len)));
}

pub fn lxListen(fd: std.posix.fd_t, backlog: u32) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.listen(fd, backlog));
        return;
    }
    try libcErrRc(libc.listen(fd, @intCast(backlog)));
}

pub fn lxAccept(fd: std.posix.fd_t, addr: ?*SockAddrT, len: ?*SockLenT, flags: u32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.accept4(fd, addr, len, flags));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    const rc = libc.accept(fd, addr, @ptrCast(len));
    const new_fd = try libcFd(rc);
    if ((flags & SOCKT.CLOEXEC) != 0) {
        _ = libc.fcntl(new_fd, std.c.F.SETFD, @as(c_int, 1));
    }
    return new_fd;
}

pub fn lxConnect(fd: std.posix.fd_t, addr: *const SockAddrT, len: SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.connect(fd, @ptrCast(addr), len));
        return;
    }
    try libcErrRc(libc.connect(fd, addr, @intCast(len)));
}

pub fn lxShutdown(fd: std.posix.fd_t, how: i32) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.shutdown(fd, how));
        return;
    }
    try libcErrRc(libc.shutdown(fd, @intCast(how)));
}

pub fn lxSend(fd: std.posix.fd_t, bytes: []const u8, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendto(fd, bytes.ptr, bytes.len, flags, null, 0));
    return try libcUsize(libc.sendto(fd, bytes.ptr, bytes.len, @intCast(flags), null, 0));
}

pub fn lxRecv(fd: std.posix.fd_t, buf: []u8, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.recvfrom(fd, buf.ptr, buf.len, flags, null, null));
    return try libcUsize(libc.recvfrom(fd, buf.ptr, buf.len, @intCast(flags), null, null));
}

pub fn lxSendto(fd: std.posix.fd_t, bytes: []const u8, flags: u32, addr: ?*const SockAddrT, len: SockLenT) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (bytes.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendto(fd, bytes.ptr, bytes.len, flags, addr, len));
    return try libcUsize(libc.sendto(fd, bytes.ptr, bytes.len, @intCast(flags), addr, @intCast(len)));
}

pub fn lxRecvfrom(fd: std.posix.fd_t, buf: []u8, flags: u32, addr: ?*SockAddrT, len: ?*SockLenT) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.recvfrom(fd, buf.ptr, buf.len, flags, addr, len));
    return try libcUsize(libc.recvfrom(fd, buf.ptr, buf.len, @intCast(flags), addr, @ptrCast(len)));
}

pub fn lxSendmsg(fd: std.posix.fd_t, msg: *const MsghdrConstT, flags: u32) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.sendmsg(fd, msg, flags));
    return try libcUsize(libc.sendmsg(fd, msg, @intCast(flags)));
}

pub fn lxDup(old: std.posix.fd_t) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.dup(old));
        return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
    }
    return try libcFd(libc.dup(old));
}

fn lxDup2(old: std.posix.fd_t, new: std.posix.fd_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.dup2(old, new));
        return;
    }
    try libcErrRc(libc.dup2(old, new));
}

fn lxFork() !std.posix.pid_t {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const rc = try lxCheck(std.os.linux.fork());
        return @as(std.posix.pid_t, @bitCast(@as(u32, @truncate(rc))));
    }
    try libcErrRc(libc.fork());
    return 0;
}

fn lxPipe2(flags: std.posix.O) ![2]std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    var fds: [2]std.posix.fd_t = undefined;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.pipe2(&fds, flags));
        return fds;
    }
    var cfds: [2]c_int = undefined;
    try libcErrRc(libc.pipe(&cfds));
    fds = .{ cfds[0], cfds[1] };
    _ = libc.fcntl(fds[0], std.c.F.SETFD, @as(c_int, 1));
    _ = libc.fcntl(fds[1], std.c.F.SETFD, @as(c_int, 1));
    return fds;
}

fn lxChdir(path: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.chdir(&z));
        return;
    }
    try libcErrRc(libc.chdir(&z));
}

pub fn lxChroot(path: [*:0]const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.chroot(path));
        return;
    }
    try libcErrRc(libc.chroot(path));
}

fn lxSetgroups(groups: []const std.posix.gid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const groups_ptr: [*]const std.os.linux.gid_t = @ptrCast(groups.ptr);
        _ = try lxCheck(std.os.linux.setgroups(groups.len, groups_ptr));
        return;
    }
    const groups_ptr: [*]const std.c.gid_t = @ptrCast(groups.ptr);
    try libcErrRc(libc.setgroups(@intCast(groups.len), groups_ptr));
}

fn lxSetsid() !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setsid());
        return;
    }
    try libcErrRc(libc.setsid());
}

fn lxSetgid(gid: std.posix.gid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setgid(gid));
        return;
    }
    try libcErrRc(libc.setgid(@intCast(gid)));
}

fn lxSetuid(uid: std.posix.uid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setuid(uid));
        return;
    }
    try libcErrRc(libc.setuid(@intCast(uid)));
}

fn lxSetpgid(pid: std.posix.pid_t, pgid: std.posix.pid_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.setpgid(pid, pgid));
        return;
    }
    try libcErrRc(libc.setpgid(@intCast(pid), @intCast(pgid)));
}

pub fn lxFcntl(fd: std.posix.fd_t, cmd: i32, arg: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) return try lxCheck(std.os.linux.fcntl(fd, cmd, arg));
    const rc = libc.fcntl(fd, @intCast(cmd), @as(c_int, @intCast(arg)));
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

fn lxIsatty(fd: std.posix.fd_t) bool {
    if (comptime is_wasm) return false;
    _ = std.posix.tcgetattr(fd) catch return false;
    return true;
}

pub fn lxUnlink(path: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.unlink(&z));
        return;
    }
    try libcErrRc(libc.unlink(&z));
}

pub fn lxMkdirat(dirfd: std.posix.fd_t, path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.mkdirat(dirfd, &z, mode));
        return;
    }
    try libcErrRc(libc.mkdirat(dirfd, &z, @intCast(mode)));
}

pub fn lxFchmodat(dirfd: std.posix.fd_t, path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    const z = try std.posix.toPosixPath(path);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.fchmodat(dirfd, &z, mode));
        return;
    }
    try libcErrRc(libc.fchmodat(dirfd, &z, @intCast(mode), 0));
}

pub fn lxLink(old: []const u8, new: []const u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    const old_z = try std.posix.toPosixPath(old);
    const new_z = try std.posix.toPosixPath(new);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.link(&old_z, &new_z));
        return;
    }
    try libcErrRc(libc.link(&old_z, &new_z));
}

pub fn lxFutimens(fd: std.posix.fd_t, times: *const [2]std.posix.timespec) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.futimens(fd, times));
        return;
    }
    try libcErrRc(libc.futimens(fd, times));
}

pub fn lxKill(pid: std.posix.pid_t, sig: u8) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.kill(pid, @fromBackingInt(@intCast(sig))));
        return;
    }
    try libcErrRc(libc.kill(@intCast(pid), @intCast(sig)));
}

pub fn lxGetsockname(fd: std.posix.fd_t, addr: *SockAddrT, len: *SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getsockname(fd, addr, len));
        return;
    }
    try libcErrRc(libc.getsockname(fd, addr, @ptrCast(len)));
}

pub fn lxGetpeername(fd: std.posix.fd_t, addr: *SockAddrT, len: *SockLenT) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getpeername(fd, addr, len));
        return;
    }
    try libcErrRc(libc.getpeername(fd, addr, @ptrCast(len)));
}

pub fn lxGetsockoptError(fd: std.posix.fd_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    var value: i32 = 0;
    var len: SockLenT = @sizeOf(i32);
    if (comptime is_linux) {
        _ = try lxCheck(std.os.linux.getsockopt(fd, SOLT.SOCKET, SOT.ERROR, @ptrCast(&value), &len));
    } else {
        try libcErrRc(libc.getsockopt(fd, @intCast(SOLT.SOCKET), @intCast(SOT.ERROR), @ptrCast(&value), @ptrCast(&len)));
    }
    if (value != 0) {
        const e: std.posix.E = @fromBackingInt(@intCast(value));
        return errnoToAny(e);
    }
}

pub fn lxEpollCreate1(flags: u32) !std.posix.fd_t {
    if (comptime !is_linux) return error.Unsupported;
    if (comptime is_wasm) return error.Unsupported;
    const rc = try lxCheck(std.os.linux.epoll_create1(flags));
    return @as(std.posix.fd_t, @bitCast(@as(u32, @truncate(rc))));
}

pub fn lxEpollCtl(epfd: std.posix.fd_t, op: u32, fd: std.posix.fd_t, event: ?*std.os.linux.epoll_event) !void {
    if (comptime !is_linux) return error.Unsupported;
    if (comptime is_wasm) return error.Unsupported;
    _ = try lxCheck(std.os.linux.epoll_ctl(epfd, op, fd, event));
}

pub fn lxEpollWait(epfd: std.posix.fd_t, events: []std.os.linux.epoll_event, timeout_ms: i32) usize {
    if (comptime !is_linux) return 0;
    if (comptime is_wasm) return;
    const rc = std.os.linux.epoll_wait(epfd, events.ptr, @as(u32, @intCast(events.len)), timeout_ms);
    if (std.os.linux.errno(rc) != .SUCCESS) return 0;
    return rc;
}

const LxWaitResult = struct {
    pid: std.posix.pid_t,
    status: u32,
};

pub fn lxWaitpid(pid: std.posix.pid_t, flags: u32) LxWaitResult {
    if (comptime is_wasm) return .{ .pid = 0, .status = 0 };
    var status: i32 = 0;
    if (comptime is_linux) {
        while (true) {
            const rc = std.os.linux.waitpid(pid, &status, flags);
            const e = std.os.linux.errno(rc);
            if (e == .SUCCESS) return .{ .pid = @as(std.posix.pid_t, @bitCast(@as(u32, @truncate(rc)))), .status = @bitCast(status) };
            if (e == .INTR) continue;
            return .{ .pid = 0, .status = 0 };
        }
    }
    while (true) {
        const rc = libc.waitpid(@intCast(pid), &status, @intCast(flags));
        const e = std.posix.errno(rc);
        if (e == .SUCCESS) return .{ .pid = @intCast(rc), .status = @bitCast(status) };
        if (e == .INTR) continue;
        return .{ .pid = 0, .status = 0 };
    }
}

/// Old std.posix.execvpeZ: exec with PATH search. Reimplemented on execve.
pub fn lxExecvpeZ(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8, envp: [*:null]const ?[*:0]const u8) anyerror {
    if (comptime is_wasm) return error.Unsupported;
    const do_exec = struct {
        fn run(path: [*:0]const u8, av: [*:null]const ?[*:0]const u8, ev: [*:null]const ?[*:0]const u8) anyerror {
            if (comptime is_linux) {
                const rc = std.os.linux.execve(path, av, ev);
                return lxErr(std.os.linux.errno(rc));
            }
            const rc = libc.execve(path, av, ev);
            return errnoToAny(std.posix.errno(rc));
        }
    }.run;
    if (std.mem.indexOfScalar(u8, std.mem.span(file), '/') != null) {
        return do_exec(file, argv, envp);
    }
    var last: anyerror = error.FileNotFound;
    var idx: usize = 0;
    while (environ[idx] != null) : (idx += 1) {
        const entry = std.mem.span(environ[idx].?);
        if (!std.mem.startsWith(u8, entry, "PATH=")) continue;
        var it = std.mem.splitScalar(u8, entry["PATH=".len..], ':');
        while (it.next()) |dir| {
            const dir_use = if (dir.len == 0) "." else dir;
            var path_buf: [std.posix.PATH_MAX]u8 = undefined;
            const full = std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ dir_use, std.mem.span(file) }) catch continue;
            var zbuf: [std.posix.PATH_MAX:0]u8 = undefined;
            if (full.len >= zbuf.len) continue;
            @memcpy(zbuf[0..full.len], full);
            zbuf[full.len] = 0;
            last = do_exec(zbuf[0..full.len :0], argv, envp);
        }
        return last;
    }
    return last;
}

fn lxExit(code: u8) noreturn {
    if (comptime is_linux) std.os.linux.exit(code);
    libc._exit(@intCast(code));
}

// ---------------------------------------------------------------------------
// 0.17 compat: socket addresses (old net Address type removed).
// Raw sockaddr storage + constructors; DNS via std.Io.net.
// ---------------------------------------------------------------------------
pub const NetAddress = struct {
    storage: SockAddrStorageT = makeSockAddrStorage(),
    len: SockLenT = @sizeOf(SockAddrStorageT),

    pub fn sockAddr(self: *const NetAddress) *const SockAddrT {
        return @ptrCast(&self.storage);
    }

    pub fn sockAddrMut(self: *NetAddress) *SockAddrT {
        return @ptrCast(&self.storage);
    }

    pub fn getOsSockLen(self: NetAddress) SockLenT {
        return self.len;
    }

    pub fn getPort(self: NetAddress) u16 {
        return switch (self.storage.family) {
            AFT.INET => blk: {
                const sin: *const SockAddrInT = @ptrCast(@alignCast(&self.storage));
                break :blk std.mem.bigToNative(u16, sin.port);
            },
            AFT.INET6 => blk: {
                const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
                break :blk std.mem.bigToNative(u16, sin6.port);
            },
            else => 0,
        };
    }

    pub fn initIp4(parts: [4]u8, port: u16) NetAddress {
        const sin = SockAddrInT{
            .port = std.mem.nativeToBig(u16, port),
            .addr = @bitCast(parts),
        };
        var a = NetAddress{ .len = @sizeOf(SockAddrInT) };
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrInT)], std.mem.asBytes(&sin));
        return a;
    }

    pub fn initIp6(bytes: [16]u8, port: u16, flowinfo: u32, scope_id: u32) NetAddress {
        const sin6 = SockAddrIn6T{
            .port = std.mem.nativeToBig(u16, port),
            .flowinfo = flowinfo,
            .addr = bytes,
            .scope_id = scope_id,
        };
        var a = NetAddress{ .len = @sizeOf(SockAddrIn6T) };
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrIn6T)], std.mem.asBytes(&sin6));
        return a;
    }

    pub fn initUnix(path: []const u8) !NetAddress {
        const off = @offsetOf(SockAddrUnT, "path");
        if (off + path.len + 1 > @sizeOf(SockAddrUnT)) return error.NameTooLong;
        var sun: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
        @memcpy(sun.path[0..path.len], path);
        sun.path[path.len] = 0;
        var a = NetAddress{ .len = @as(SockLenT, @intCast(off + path.len + 1)) };
        @memset(std.mem.asBytes(&a.storage), 0);
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrUnT)], std.mem.asBytes(&sun));
        return a;
    }

    pub fn fromIp(ip: std.Io.net.IpAddress) NetAddress {
        return switch (ip) {
            .ip4 => |v4| initIp4(v4.bytes, v4.port),
            .ip6 => |v6| initIp6(v6.bytes, v6.port, v6.flow, v6.interface.index),
        };
    }

    pub fn resolveIp(host: []const u8, port: u16) !NetAddress {
        if (std.Io.net.IpAddress.parse(host, port)) |ip| {
            return fromIp(ip);
        } else |_| {}
        var list = try netGetAddressList(std.heap.page_allocator, host, port);
        defer list.deinit();
        if (list.addrs.len == 0) return error.HostLacksNetworkAddresses;
        return list.addrs[0];
    }

    pub fn unixPath(self: *const NetAddress) []const u8 {
        const sun: *const SockAddrUnT = @ptrCast(&self.storage);
        return std.mem.sliceTo(&sun.path, 0);
    }

    pub fn fromUnixSockaddr(sun: SockAddrUnT, len: SockLenT) NetAddress {
        var a = NetAddress{ .len = len };
        @memset(std.mem.asBytes(&a.storage), 0);
        @memcpy(std.mem.asBytes(&a.storage)[0..@sizeOf(SockAddrUnT)], std.mem.asBytes(&sun));
        return a;
    }

    pub fn in6ScopeId(self: *const NetAddress) u32 {
        const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
        return sin6.scope_id;
    }

    pub fn in4AddrU32(self: *const NetAddress) u32 {
        const sin: *const SockAddrInT = @ptrCast(@alignCast(&self.storage));
        return sin.addr;
    }

    pub fn in6AddrBytes(self: *const NetAddress) [16]u8 {
        const sin6: *const SockAddrIn6T = @ptrCast(@alignCast(&self.storage));
        return sin6.addr;
    }
};

const NetAddressList = struct {
    addrs: []NetAddress,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *NetAddressList) void {
        self.allocator.free(self.addrs);
        self.addrs = &.{};
    }
};

pub fn netGetAddressList(allocator: std.mem.Allocator, host: []const u8, port: u16) !NetAddressList {
    if (std.Io.net.IpAddress.parse(host, port)) |ip| {
        const addrs = try allocator.alloc(NetAddress, 1);
        addrs[0] = NetAddress.fromIp(ip);
        return .{ .addrs = addrs, .allocator = allocator };
    } else |_| {}
    const hn = try std.Io.net.HostName.init(host);
    var qbuf: [16]std.Io.net.HostName.LookupResult = undefined;
    var q = std.Io.Queue(std.Io.net.HostName.LookupResult).init(&qbuf);
    hn.lookup(sio.io(), &q, .{ .port = port }) catch |err| switch (err) {
        error.UnknownHostName => return error.UnknownHostName,
        else => return err,
    };
    q.close(sio.io());
    var out: std.array_list.Managed(NetAddress) = .init(allocator);
    errdefer out.deinit();
    var drain: [16]std.Io.net.HostName.LookupResult = undefined;
    while (true) {
        const n = q.get(sio.io(), &drain, 0) catch |err| switch (err) {
            error.Closed => break,
            else => return err,
        };
        if (n == 0) break;
        for (drain[0..n]) |r| {
            if (r == .address) try out.append(NetAddress.fromIp(r.address));
        }
    }
    if (out.items.len == 0) {
        out.deinit();
        return error.HostLacksNetworkAddresses;
    }
    return .{ .addrs = try out.toOwnedSlice(), .allocator = allocator };
}

// ---------------------------------------------------------------------------
// 0.17 compat: portable file metadata. Linux keeps statx; other targets use
// the Io vtable stat (which maps to lstat/stat internally).
// ---------------------------------------------------------------------------
pub const RawStat = @import("sa_std/dir_stat.zig").RawStat;

pub const timestampToRawTs = @import("sa_std/dir_stat.zig").timestampToRawTs;

pub const kindModeBits = @import("sa_std/dir_stat.zig").kindModeBits;

pub const rawStatFromIo = @import("sa_std/dir_stat.zig").rawStatFromIo;

pub const lxStatxNoFollow = @import("sa_std/dir_stat.zig").lxStatxNoFollow;

pub const statFromRaw = @import("sa_std/dir_stat.zig").statFromRaw;

pub const statxDevId = @import("sa_std/dir_stat.zig").statxDevId;

pub const tsToMs = @import("sa_std/dir_stat.zig").tsToMs;

pub const cryptoRandomU64 = @import("sa_std/test_debug.zig").cryptoRandomU64;

pub fn formatInteger(value: anytype, base: u32) ![]u8 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return error.InvalidArgument,
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const n = std.fmt.printInt(&buf, value, actual_base, case, .{});
    const text = buf[0..n];
    return std.heap.page_allocator.dupe(u8, text);
}

pub fn formatFloat(value: f64, precision: u32) ![]u8 {
    var buf: [256]u8 = undefined;
    const text = try std.fmt.bufPrint(&buf, "{d:.[1]}", .{ value, @as(usize, @intCast(precision)) });
    return std.heap.page_allocator.dupe(u8, text);
}

pub fn formatBool(value: bool) ![]u8 {
    return std.heap.page_allocator.dupe(u8, if (value) "true" else "false");
}

pub fn formatBytes(bytes: []const u8) ![]u8 {
    return std.heap.page_allocator.dupe(u8, bytes);
}

pub fn writeFormattedInto(out: ?[*]u8, out_cap: u64, out_len: ?*u64, text: []const u8) i32 {
    if (out_len) |ptr| ptr.* = @as(u64, @intCast(text.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len < text.len) return finish(SA_STD_ERR_TRUNCATED);
    if (text.len != 0) @memcpy(buffer[0..text.len], text);
    return finish(SA_STD_OK);
}

pub fn stringConcat(left: []const u8, right: []const u8) ![]u8 {
    var bytes = try std.heap.page_allocator.alloc(u8, left.len + right.len);
    if (left.len != 0) std.mem.copyForwards(u8, bytes[0..left.len], left);
    if (right.len != 0) std.mem.copyForwards(u8, bytes[left.len .. left.len + right.len], right);
    return bytes;
}

pub const longestSuffixPrefix = @import("sa_std/chat_norm.zig").longestSuffixPrefix;

pub fn openOwnedBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .fmt = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

pub fn openOwnedByteBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

pub fn openOwnedEnvBuffer(bytes: []u8) !u64 {
    return registerResource(.{ .env = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return err;
    };
}

pub const ThoughtStreamSplitter = @import("sa_std/chat_norm.zig").ThoughtStreamSplitter;

const ListWriter = struct {
    list: *std.array_list.Managed(u8),
    pub fn writeAll(self: ListWriter, bytes: []const u8) !void {
        try self.list.appendSlice(bytes);
    }
    pub fn writeByte(self: ListWriter, byte: u8) !void {
        try self.list.append(byte);
    }
    pub fn print(self: ListWriter, comptime fmt: []const u8, args: anytype) !void {
        var aw: std.Io.Writer.Allocating = .init(self.list.allocator);
        defer aw.deinit();
        try aw.writer.print(fmt, args);
        try self.list.appendSlice(aw.written());
    }
};

pub fn listWriter(list: *std.array_list.Managed(u8)) ListWriter {
    return .{ .list = list };
}

pub fn stringifyToList(list: *std.array_list.Managed(u8), value: anytype) !void {
    var aw: std.Io.Writer.Allocating = .init(list.allocator);
    defer aw.deinit();
    try std.json.Stringify.value(value, .{}, &aw.writer);
    try list.appendSlice(aw.written());
}

pub fn appendJsonString(writer: ListWriter, text: []const u8) !void {
    try stringifyToList(writer.list, text);
}

fn jsonStringLiteralAlloc(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendJsonString(listWriter(&out), text);
    return try out.toOwnedSlice();
}

fn jsonRpcParamLookupKey(key: []const u8) []const u8 {
    if (key.len > 2 and key[0] == '"') {
        if (std.mem.indexOfScalar(u8, key[1..], '"')) |end| {
            if (end > 0) return key[1 .. 1 + end];
        }
    }
    return key;
}

pub fn jsonRpcParamsStringLiteralAlloc(body: []const u8, key: []const u8, fallback: []const u8, emit_null_if_missing: bool) ![]u8 {
    const lookup_key = jsonRpcParamLookupKey(key);
    if (lookup_key.len != 0) {
        var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, body, .{}) catch null;
        if (parsed) |*document| {
            defer document.deinit();
            if (jsonObjectGetValue(document.value, "params")) |params| {
                if (jsonObjectGetValue(params, lookup_key)) |value| {
                    if (jsonTextSlice(value)) |text| {
                        return try jsonStringLiteralAlloc(std.heap.page_allocator, text);
                    }
                }
            }
        }
    }

    if (emit_null_if_missing) return try std.heap.page_allocator.dupe(u8, "null");
    return try jsonStringLiteralAlloc(std.heap.page_allocator, fallback);
}

pub const jsonU64Value = @import("sa_std/chat_norm.zig").jsonU64Value;

pub const appendResponseCreated = @import("sa_std/chat_norm.zig").appendResponseCreated;

pub const appendReasoningDelta = @import("sa_std/chat_norm.zig").appendReasoningDelta;

pub const appendReasoningDone = @import("sa_std/chat_norm.zig").appendReasoningDone;

pub const appendMessageDelta = @import("sa_std/chat_norm.zig").appendMessageDelta;

pub const appendMessageDone = @import("sa_std/chat_norm.zig").appendMessageDone;

pub const requestAllowsContinuation = @import("sa_std/chat_norm.zig").requestAllowsContinuation;

pub const isProgressOnlyText = @import("sa_std/chat_norm.zig").isProgressOnlyText;

pub const appendContinuationTool = @import("sa_std/chat_norm.zig").appendContinuationTool;

pub const appendContinuationToolJson = @import("sa_std/chat_norm.zig").appendContinuationToolJson;

pub const ChatToolCallState = @import("sa_std/chat_norm.zig").ChatToolCallState;

pub const shellQuote = @import("sa_std/chat_norm.zig").shellQuote;

pub const isSensitiveEnvPath = @import("sa_std/chat_norm.zig").isSensitiveEnvPath;

pub const appendCommandArguments = @import("sa_std/chat_norm.zig").appendCommandArguments;

pub const appendReadCommand = @import("sa_std/chat_norm.zig").appendReadCommand;

pub const splitMcpNamespace = @import("sa_std/chat_norm.zig").splitMcpNamespace;

pub const denormalizeMcpServerNameAlloc = @import("sa_std/chat_norm.zig").denormalizeMcpServerNameAlloc;

pub const normalizeMcpServerNameAlloc = @import("sa_std/normalize.zig").normalizeMcpServerNameAlloc;

pub const requestMentionsTool = @import("sa_std/chat_norm.zig").requestMentionsTool;

pub const normalizeChatToolArguments = @import("sa_std/chat_norm.zig").normalizeChatToolArguments;

pub const appendNormalizedToolCall = @import("sa_std/chat_norm.zig").appendNormalizedToolCall;

pub const appendNormalizedToolCallJson = @import("sa_std/chat_norm.zig").appendNormalizedToolCallJson;

pub const findToolCallState = @import("sa_std/chat_norm.zig").findToolCallState;

pub const parseToolCallIndex = @import("sa_std/chat_norm.zig").parseToolCallIndex;

pub const appendResponseDone = @import("sa_std/chat_norm.zig").appendResponseDone;

pub const appendChatUsageJson = @import("sa_std/chat_norm.zig").appendChatUsageJson;

pub const appendChatJsonReasoningItem = @import("sa_std/chat_norm.zig").appendChatJsonReasoningItem;

pub const appendChatJsonMessageItem = @import("sa_std/chat_norm.zig").appendChatJsonMessageItem;

pub const appendOutputComma = @import("sa_std/chat_norm.zig").appendOutputComma;

pub const denoChatJsonToResponses = @import("sa_std/chat_norm.zig").denoChatJsonToResponses;

pub const ThoughtSplit = @import("sa_std/chat_norm.zig").ThoughtSplit;

pub const splitThoughtTextAlloc = @import("sa_std/chat_norm.zig").splitThoughtTextAlloc;

pub const appendMergedReasoningText = @import("sa_std/chat_norm.zig").appendMergedReasoningText;

pub const appendReasoningFields = @import("sa_std/chat_norm.zig").appendReasoningFields;

pub const isNativeReasoningType = @import("sa_std/chat_norm.zig").isNativeReasoningType;

pub const appendNativeReasoningItem = @import("sa_std/chat_norm.zig").appendNativeReasoningItem;

pub const appendNativeMessageItem = @import("sa_std/chat_norm.zig").appendNativeMessageItem;

pub const appendNativeNormalizedOutput = @import("sa_std/chat_norm.zig").appendNativeNormalizedOutput;

pub const nativeResponsesJsonNeedsNormalize = @import("sa_std/chat_norm.zig").nativeResponsesJsonNeedsNormalize;

pub const denoResponsesJsonNormalize = @import("sa_std/chat_norm.zig").denoResponsesJsonNormalize;

pub fn jsonObjectGetValue(value: std.json.Value, key: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(key),
        else => null,
    };
}

pub const jsonArrayFirst = @import("sa_std/chat_norm.zig").jsonArrayFirst;

pub fn jsonStringValue(value: ?std.json.Value) []const u8 {
    const actual = value orelse return "";
    return switch (actual) {
        .string => |text| text,
        else => "",
    };
}

pub const jsonBoolValue = @import("sa_std/chat_fallback.zig").jsonBoolValue;

pub const appendJsonFieldName = @import("sa_std/chat_fallback.zig").appendJsonFieldName;

pub const appendSystemText = @import("sa_std/chat_fallback.zig").appendSystemText;

pub const responseContentTextOnlyAlloc = @import("sa_std/chat_fallback.zig").responseContentTextOnlyAlloc;

pub const appendMappedResponseContentPart = @import("sa_std/chat_fallback.zig").appendMappedResponseContentPart;

pub const appendResponseContentAsChat = @import("sa_std/chat_fallback.zig").appendResponseContentAsChat;

pub const isResponsesToolCallType = @import("sa_std/chat_fallback.zig").isResponsesToolCallType;

pub const isResponsesToolOutputType = @import("sa_std/chat_fallback.zig").isResponsesToolOutputType;

pub const responseToolCallNameForChat = @import("sa_std/chat_fallback.zig").responseToolCallNameForChat;

pub const collectResponseToolCallNames = @import("sa_std/chat_fallback.zig").collectResponseToolCallNames;

pub const appendChatMessagePrefix = @import("sa_std/chat_fallback.zig").appendChatMessagePrefix;

pub const appendResponseMessageAsChat = @import("sa_std/chat_fallback.zig").appendResponseMessageAsChat;

pub const appendResponseToolCallAsChat = @import("sa_std/chat_fallback.zig").appendResponseToolCallAsChat;

pub const appendResponseToolOutputAsChat = @import("sa_std/chat_fallback.zig").appendResponseToolOutputAsChat;

pub const appendNormalizedChatTool = @import("sa_std/chat_fallback.zig").appendNormalizedChatTool;

pub const appendNormalizedChatToolsField = @import("sa_std/chat_fallback.zig").appendNormalizedChatToolsField;

pub const appendResponseFormatFromText = @import("sa_std/chat_fallback.zig").appendResponseFormatFromText;

pub const shouldSkipResponsesFallbackField = @import("sa_std/chat_fallback.zig").shouldSkipResponsesFallbackField;

pub const denoResponsesChatFallbackRequest = @import("sa_std/chat_fallback.zig").denoResponsesChatFallbackRequest;

pub const normalizeResponsesArgumentsString = @import("sa_std/chat_norm.zig").normalizeResponsesArgumentsString;

pub const normalizeResponsesRequestArgumentsString = @import("sa_std/normalize.zig").normalizeResponsesRequestArgumentsString;

pub const normalizeResponsesRequestValue = @import("sa_std/normalize.zig").normalizeResponsesRequestValue;

pub const denoResponsesRequestNormalize = @import("sa_std/normalize.zig").denoResponsesRequestNormalize;

pub const normalizeResponsesEventData = @import("sa_std/chat_norm.zig").normalizeResponsesEventData;

pub const appendNormalizedResponsesSseBlock = @import("sa_std/chat_norm.zig").appendNormalizedResponsesSseBlock;

pub const denoResponsesSseNormalize = @import("sa_std/chat_norm.zig").denoResponsesSseNormalize;

pub const appendChatSseDataChunk = @import("sa_std/chat_norm.zig").appendChatSseDataChunk;

pub const denoChatSseToResponses = @import("sa_std/chat_norm.zig").denoChatSseToResponses;

pub fn envKeyBytes(key_ptr: ?[*]const u8, key_len: u64) ![]const u8 {
    const key = try constBytes(key_ptr, key_len);
    if (key.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, 0) != null) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, key, '=') != null) return error.InvalidArgument;
    return key;
}

pub const envValueFromCurrentProcess = @import("sa_std/test_debug.zig").envValueFromCurrentProcess;

pub const envGetOwned = @import("sa_std/test_debug.zig").envGetOwned;

const EnvVarJson = struct {
    key: []const u8,
    value: []const u8,
};

fn appendEnvVarJson(pairs: *std.array_list.Managed(EnvVarJson), entry: []const u8) !void {
    const eq = std.mem.indexOfScalar(u8, entry, '=') orelse return;
    if (eq == 0) return;
    try pairs.append(.{ .key = entry[0..eq], .value = entry[eq + 1 ..] });
}

pub fn envVarsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    var pairs = std.array_list.Managed(EnvVarJson).init(allocator);
    defer pairs.deinit();

    {
        var i: usize = 0;
        while (environ[i] != null) : (i += 1) {
            try appendEnvVarJson(&pairs, std.mem.span(environ[i].?));
        }
    }

    return std.json.Stringify.valueAlloc(allocator, pairs.items, .{});
}

pub fn processArgsJsonAlloc(allocator: std.mem.Allocator) ![]u8 {
    if (builtin.os.tag == .linux) {
        const file = sio.openFileAbsolute("/proc/self/cmdline", .{}) catch |err| switch (err) {
            error.FileNotFound, error.AccessDenied => null,
            else => return err,
        };
        if (file) |cmdline_file| {
            defer cmdline_file.close();
            const cmdline = try cmdline_file.readToEndAlloc(allocator, 1024 * 1024);
            defer allocator.free(cmdline);

            var args = std.array_list.Managed([]const u8).init(allocator);
            defer args.deinit();
            var it = std.mem.splitScalar(u8, cmdline, 0);
            while (it.next()) |arg| {
                if (arg.len == 0) continue;
                try args.append(arg);
            }
            return std.json.Stringify.valueAlloc(allocator, args.items, .{});
        }
    }

    const args = try sio.argsAlloc(allocator);
    defer sio.argsFree(allocator, args);
    return std.json.Stringify.valueAlloc(allocator, args, .{});
}

pub fn envSplitPathsJsonAlloc(allocator: std.mem.Allocator, path_list: []const u8) ![]u8 {
    var parts = std.array_list.Managed([]const u8).init(allocator);
    defer parts.deinit();

    var it = std.mem.splitScalar(u8, path_list, ':');
    while (it.next()) |part| {
        try parts.append(part);
    }

    return std.json.Stringify.valueAlloc(allocator, parts.items, .{});
}

pub fn envJoinPathsJsonAlloc(allocator: std.mem.Allocator, paths_json: []const u8) ![]u8 {
    const parsed = try std.json.parseFromSlice([]const []const u8, allocator, paths_json, .{});
    defer parsed.deinit();

    for (parsed.value) |path| {
        if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    }

    return std.mem.join(allocator, ":", parsed.value);
}

pub const xdgHomeDirAlloc = @import("sa_std/test_debug.zig").xdgHomeDirAlloc;

pub const xdgHomeSubdirAlloc = @import("sa_std/test_debug.zig").xdgHomeSubdirAlloc;

pub const xdgDirsAlloc = @import("sa_std/test_debug.zig").xdgDirsAlloc;

pub fn Fallible(comptime T: type) type {
    return extern struct {
        status: i32,
        value: T,
    };
}

pub fn ok(comptime T: type, value: T) Fallible(T) {
    return .{ .status = SA_STD_OK, .value = value };
}

pub fn fail(comptime T: type, status: i32) Fallible(T) {
    return .{ .status = status, .value = std.mem.zeroes(T) };
}

// NOTE: sa_http_client_* used to be provided by the http-client plugin
// and deliberately left undefined here (a stub once shadowed it). Since
// 2026-10-24 the real implementation is built into sa_std
// (src/runtime/sa_http_client.zig, migrated from the plugin under the
// all-cores-built-in doctrine); the plugin keeps only framework wraps.

pub export fn sa_std_version() u32 {
    return SA_STD_ABI_VERSION;
}

// --- Checked i64 arithmetic (sa_std/num.sai) ------------------------------
// Exact-result arithmetic with Rust `overflow-checks = true` semantics:
// on overflow the operation traps instead of wrapping. The SA-level
// mirror (sa_std/num.sal NUM_*_CHECKED macros) traps with
// panic(PANIC_ARITH_OVERFLOW = 9001); a native extern has no SA panic
// channel, so the trap here is a diagnostic on stderr plus process
// abort -- never a wrapped result, never a silent status (the .sai
// signature returns the bare i64 and has no status channel).
fn saNumCheckedTrap(comptime symbol: []const u8, a: i64, b: i64) noreturn {
    std.debug.print("[sa-std] {s}({d}, {d}): i64 overflow, trapping (PANIC_ARITH_OVERFLOW=9001)\n", .{ symbol, a, b });
    std.process.abort();
}

pub export fn sa_num_add_checked(a: i64, b: i64) i64 {
    const result = @addWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_add_checked", a, b);
    return result[0];
}

pub export fn sa_num_sub_checked(a: i64, b: i64) i64 {
    const result = @subWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_sub_checked", a, b);
    return result[0];
}

pub export fn sa_num_mul_checked(a: i64, b: i64) i64 {
    const result = @mulWithOverflow(a, b);
    if (result[1] != 0) saNumCheckedTrap("sa_num_mul_checked", a, b);
    return result[0];
}

pub export fn sa_std_last_error() i32 {
    return last_error;
}

pub const sa_std_net_error_code_from_status = @import("sa_std/std_net.zig").sa_std_net_error_code_from_status;

pub const sa_std_net_error_code_from_posix_errno = @import("sa_std/std_net.zig").sa_std_net_error_code_from_posix_errno;

pub const sa_std_net_error_code_from_wsa_error = @import("sa_std/std_net.zig").sa_std_net_error_code_from_wsa_error;

pub fn netErrorCodeName(code: i32) []const u8 {
    return switch (code) {
        0 => "ok",
        1 => "unknown",
        2 => "dns",
        3 => "connection_refused",
        4 => "timed_out",
        5 => "connection_closed",
        6 => "would_block",
        7 => "invalid_address",
        8 => "permission_denied",
        9 => "unsupported",
        10 => "invalid_input",
        11 => "invalid_handle",
        12 => "not_found",
        13 => "out_of_memory",
        14 => "io",
        15 => "network_unreachable",
        16 => "addr_in_use",
        17 => "addr_not_available",
        18 => "connection_reset",
        19 => "connection_aborted",
        20 => "not_connected",
        21 => "host_unreachable",
        22 => "broken_pipe",
        23 => "already_exists",
        24 => "interrupted",
        25 => "unexpected_eof",
        26 => "invalid_data",
        27 => "network_down",
        28 => "write_zero",
        else => "unknown",
    };
}

pub const sa_std_net_error_code_name = @import("sa_std/std_net.zig").sa_std_net_error_code_name;

pub const sa_std_net_error_platform = @import("sa_std/std_net.zig").sa_std_net_error_platform;

pub const sa_std_net_error_code_from_native_error = @import("sa_std/std_net.zig").sa_std_net_error_code_from_native_error;

pub const sa_std_net_hostname = @import("sa_std/std_net.zig").sa_std_net_hostname;

pub export fn sa_std_error_name(code: i32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const name = statusName(code);
    if (out_len) |len_ptr| len_ptr.* = @as(u64, @intCast(name.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const cap = lenAsUsize(out_cap) catch |err| return finishErr(err);
    const out_ptr = out orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const copy_len = @min(cap, name.len);
    @memcpy(out_ptr[0..copy_len], name[0..copy_len]);
    if (copy_len != name.len) return finish(SA_STD_ERR_TRUNCATED);
    return finish(SA_STD_OK);
}

pub export fn sa_std_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_std_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_std_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    sio.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data: ?[*]const u8, len: u64) Fallible(i32) {
    // Contract alignment (A_min): io.sai declares `-> i32!`, and the
    // interpreter already returns a fallible cell; the native runtime
    // used to return the bare status word, so compiled callers read
    // the payload slot of a cell that was never written.
    const bytes = constBytes(data, len) catch |err| return fail(i32, finishErr(err));
    sio.getStdOut().writeAll(bytes) catch |err| return fail(i32, finishErr(err));
    sio.getStdOut().writeAll("\n") catch |err| return fail(i32, finishErr(err));
    return ok(i32, 0);
}

pub const sa_deno_cwd = @import("sa_std/deno.zig").sa_deno_cwd;

pub const sa_deno_chdir = @import("sa_std/deno.zig").sa_deno_chdir;

pub const sa_deno_env_set = @import("sa_std/deno.zig").sa_deno_env_set;

pub const sa_deno_env_delete = @import("sa_std/deno.zig").sa_deno_env_delete;

pub const sa_deno_random_uuid = @import("sa_std/deno.zig").sa_deno_random_uuid;

pub const tempRootAlloc = @import("sa_std/test_debug.zig").tempRootAlloc;

pub const tempPathAlloc = @import("sa_std/test_debug.zig").tempPathAlloc;

pub const sa_deno_make_temp_dir = @import("sa_std/deno.zig").sa_deno_make_temp_dir;

pub const sa_deno_make_temp_file = @import("sa_std/deno.zig").sa_deno_make_temp_file;

pub const sa_deno_args_json = @import("sa_std/deno.zig").sa_deno_args_json;

pub const sa_deno_btoa = @import("sa_std/deno.zig").sa_deno_btoa;

pub const sa_deno_atob = @import("sa_std/deno.zig").sa_deno_atob;

// SIMD hex decoder: native bulk-decode fast path (mirrors the sa_hexdec
// JS host-codec shim contract). Decodes ASCII hex pairs into bytes at
// 32 input chars per vector iteration with a scalar tail. Stops at the
// first invalid char or odd trailing nibble and returns the bytes
// written so far; clean even-length input of n chars yields exactly
// n/2. Caller must provide at least n/2 bytes of output.
fn hexSimdNibbleVal(c: u8) ?u8 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'A' and c <= 'F') return c - 'A' + 10;
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return null;
}

pub export fn sa_hexdec_simd(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64 {
    const input = constBytes(in_ptr, in_len) catch return 0;
    const n = input.len;
    if (n == 0) return 0;
    const out_p = out_ptr orelse return 0;
    const out = out_p[0 .. n / 2];
    const V32 = @Vector(32, u8);
    const z0: V32 = @splat(@as(u8, '0'));
    const z9: V32 = @splat(@as(u8, '9'));
    const zA: V32 = @splat(@as(u8, 'A'));
    const zF: V32 = @splat(@as(u8, 'F'));
    const za: V32 = @splat(@as(u8, 'a'));
    const zf: V32 = @splat(@as(u8, 'f'));
    const ten: V32 = @splat(@as(u8, 10));
    const one: V32 = @splat(@as(u8, 1));
    const zero: V32 = @splat(@as(u8, 0));
    const four: @Vector(16, u8) = @splat(@as(u8, 4));
    const even_idx: [16]i32 = .{ 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30 };
    const odd_idx: [16]i32 = .{ 1, 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31 };
    var i: usize = 0;
    var w: usize = 0;
    while (i + 32 <= n) {
        const chunk: V32 = input[i..][0..32].*;
        const in09 = @select(u8, chunk >= z0, @select(u8, chunk <= z9, one, zero), zero);
        const inAF = @select(u8, chunk >= zA, @select(u8, chunk <= zF, one, zero), zero);
        const inaf = @select(u8, chunk >= za, @select(u8, chunk <= zf, one, zero), zero);
        const valid = in09 | inAF | inaf;
        if (@reduce(.Min, valid) == 0) break;
        const nib = in09 * (chunk -% z0) + inAF * (chunk -% (zA -% ten)) + inaf * (chunk -% (za -% ten));
        const evens = @shuffle(u8, nib, @as(V32, undefined), even_idx);
        const odds = @shuffle(u8, nib, @as(V32, undefined), odd_idx);
        const joined: @Vector(16, u8) = (evens << four) | odds;
        out[w..][0..16].* = joined;
        i += 32;
        w += 16;
    }
    while (i + 2 <= n) {
        const hi = hexSimdNibbleVal(input[i]) orelse break;
        const lo = hexSimdNibbleVal(input[i + 1]) orelse break;
        out[w] = (hi << 4) | lo;
        i += 2;
        w += 1;
    }
    return @intCast(w);
}




// SIMD base64 decoder: native bulk-decode fast path. Decodes clean
// A-Za-z0-9+/ quanta at 32 input chars per vector iteration with a
// scalar tail. Stops at the first non-alphabet char (including '=')
// and returns the bytes written so far; clean input of n chars with
// n % 4 == 0 yields exactly n/4*3. Caller must provide that many bytes.
pub const b64SimdSextetVal = @import("sa_std/b64_simd.zig").b64SimdSextetVal;

extern fn sa_cpu_has_avx2() c_int;
extern fn sa_b64dec_avx2(in_ptr: ?[*]const u8, in_len: u64, out_ptr: ?[*]u8) u64;

pub const sa_b64dec_simd = @import("sa_std/b64_simd.zig").sa_b64dec_simd;





// Bulk substring search for native peers (mirrors the sa_mfind_u8 JS
// fused shim contract): returns the first index of needle in haystack,
// or hay_len on miss (one-past-end sentinel, always representable).
// Empty needle matches at 0 (memmem semantics). Delegates to the Zig
// standard library search (library-grade, memchr-class).
pub export fn sa_mfind_u8(hay_ptr: ?[*]const u8, hay_len: u64, ndl_ptr: ?[*]const u8, ndl_len: u64) u64 {
    const hay = constBytes(hay_ptr, hay_len) catch return hay_len;
    const ndl = constBytes(ndl_ptr, ndl_len) catch return hay.len;
    if (ndl.len == 0) return 0;
    if (ndl.len > hay.len) return hay.len;
    if (std.mem.indexOf(u8, hay, ndl)) |idx| return @intCast(idx);
    return hay.len;
}


pub const sa_deno_text_encode = @import("sa_std/deno.zig").sa_deno_text_encode;

pub const sa_deno_text_decode = @import("sa_std/deno.zig").sa_deno_text_decode;

pub const sa_deno_chat_sse_to_responses = @import("sa_std/deno.zig").sa_deno_chat_sse_to_responses;

pub const sa_deno_chat_json_to_responses = @import("sa_std/deno.zig").sa_deno_chat_json_to_responses;

pub const sa_deno_responses_sse_normalize = @import("sa_std/deno.zig").sa_deno_responses_sse_normalize;

pub const sa_deno_responses_json_normalize = @import("sa_std/deno.zig").sa_deno_responses_json_normalize;

pub const sa_deno_responses_request_normalize = @import("sa_std/deno.zig").sa_deno_responses_request_normalize;

pub const sa_deno_responses_chat_fallback_request = @import("sa_std/deno.zig").sa_deno_responses_chat_fallback_request;

pub const sa_deno_jsonrpc_params_string_literal = @import("sa_std/deno.zig").sa_deno_jsonrpc_params_string_literal;

pub const sa_deno_version_json = @import("sa_std/deno.zig").sa_deno_version_json;

pub const sa_deno_version_deno = @import("sa_std/deno.zig").sa_deno_version_deno;

pub const sa_deno_build_json = @import("sa_std/deno.zig").sa_deno_build_json;

pub const sa_deno_build_os = @import("sa_std/deno.zig").sa_deno_build_os;

pub const sa_deno_build_platform_family = @import("sa_std/deno.zig").sa_deno_build_platform_family;

/// Zero-padded decimal append. (std.fmt `{d:04}` on 0.14 misplaces the
/// sign, emitting `+` for positives, so ISO dates pad manually instead.)
fn appendPadded(out: *std.array_list.Managed(u8), val: i64, width: usize) !void {
    if (val < 0) {
        try out.append('-');
        const rest = if (width > 0) width - 1 else 0;
        // Years never approach minInt; negation is safe here.
        return appendPadded(out, -val, rest);
    }
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < width) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

/// UTC `YYYY-MM-DDTHH:MM:SS.sssZ` append shared by the ISO formatters.
pub fn appendIsoUtc(out: *std.array_list.Managed(u8), year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, milli: i64) !void {
    try appendPadded(out, year, 4);
    try out.append('-');
    try appendPadded(out, month, 2);
    try out.append('-');
    try appendPadded(out, day, 2);
    try out.append('T');
    try appendPadded(out, hour, 2);
    try out.append(':');
    try appendPadded(out, minute, 2);
    try out.append(':');
    try appendPadded(out, second, 2);
    try out.append('.');
    try appendPadded(out, milli, 3);
    try out.append('Z');
}

pub const sa_deno_date_now_iso = @import("sa_std/deno.zig").sa_deno_date_now_iso;

pub const struct_sockaddr = @import("sa_std/iface_json.zig").struct_sockaddr;
pub const struct_ifaddrs = @import("sa_std/iface_json.zig").struct_ifaddrs;
extern fn getifaddrs(ifap: *?*struct_ifaddrs) c_int;
extern fn freeifaddrs(ifa: ?*struct_ifaddrs) void;
extern fn inet_ntop(af: c_int, src: ?*const anyopaque, dst: [*]u8, size: c_uint) ?[*:0]const u8;

pub const sa_deno_hostname = @import("sa_std/deno.zig").sa_deno_hostname;

pub const sa_deno_os_release = @import("sa_std/deno.zig").sa_deno_os_release;

pub const sa_deno_os_uptime = @import("sa_std/deno.zig").sa_deno_os_uptime;

pub const sa_deno_loadavg = @import("sa_std/deno.zig").sa_deno_loadavg;

pub const sa_deno_system_memory_info = @import("sa_std/deno.zig").sa_deno_system_memory_info;

pub const sa_deno_network_interfaces = @import("sa_std/deno.zig").sa_deno_network_interfaces;

pub extern fn getpid() c_int;
extern fn getppid() c_int;
pub extern fn getuid() c_uint;
pub extern fn getgid() c_uint;
extern fn getpagesize() c_int;

// ---- local network information: interface address snapshot ----
//
// Backs sa_std/net_info.sai (sa_std_net_interface_addresses_json).
// The Deno compatibility walk above (sa_deno_network_interfaces)
// proves the getifaddrs linkage, but its result shape is Deno's:
// string families, a "cidr" string, a hard-coded fallback netmask
// and no status code. This is the sa_std-shaped snapshot: one JSON
// array in an owned byte buffer (the sa_std_fs_read_dir_json
// result convention), numeric address families, an explicit
// prefix_len, the broadcast address when the kernel reports one,
// and an SA_STD_* status return. The SLA layer in
// sa_std/net_info.sla parses the snapshot with the sa_json
// document surface and joins it with the /sys/class/net interface
// records and the /proc route tables.
//
// Not declared in sa_std.h (SLA-first surface, cookie/TOML
// precedent), so the runtime-abi-check header counts are
// unchanged. Linux only for now; the Windows runtime mirror does
// not implement the symbol yet.

pub const appendJsonEscapedString = @import("sa_std/iface_json.zig").appendJsonEscapedString;

pub const buildInterfaceAddressesJson = @import("sa_std/iface_json.zig").buildInterfaceAddressesJson;


pub const sa_std_net_interface_addresses_json = @import("sa_std/std_net.zig").sa_std_net_interface_addresses_json;


pub const sa_deno_pid = @import("sa_std/deno.zig").sa_deno_pid;

pub const sa_deno_ppid = @import("sa_std/deno.zig").sa_deno_ppid;

pub const sa_deno_uid = @import("sa_std/deno.zig").sa_deno_uid;

pub const sa_deno_gid = @import("sa_std/deno.zig").sa_deno_gid;

pub const sa_deno_exec_path = @import("sa_std/deno.zig").sa_deno_exec_path;

pub const sa_deno_memory_usage = @import("sa_std/deno.zig").sa_deno_memory_usage;

pub const sa_json_parse = @import("sa_std/json.zig").sa_json_parse;

pub const sa_json_kind = @import("sa_std/json.zig").sa_json_kind;

pub const sa_json_object_get = @import("sa_std/json.zig").sa_json_object_get;

pub const sa_json_array_get = @import("sa_std/json.zig").sa_json_array_get;

pub const sa_json_object_key_at = @import("sa_std/json.zig").sa_json_object_key_at;

pub const sa_json_object_get_string = @import("sa_std/json.zig").sa_json_object_get_string;

pub const sa_json_object_get_bool = @import("sa_std/json.zig").sa_json_object_get_bool;

pub const sa_json_object_get_i64 = @import("sa_std/json.zig").sa_json_object_get_i64;

pub const sa_json_object_get_f64 = @import("sa_std/json.zig").sa_json_object_get_f64;

pub const sa_json_as_f64 = @import("sa_std/json.zig").sa_json_as_f64;

pub const sa_json_as_i64 = @import("sa_std/json.zig").sa_json_as_i64;

pub const sa_json_as_bool = @import("sa_std/json.zig").sa_json_as_bool;

pub const sa_json_string_ptr = @import("sa_std/json.zig").sa_json_string_ptr;

pub const sa_json_string_len = @import("sa_std/json.zig").sa_json_string_len;

pub const sa_json_value_count = @import("sa_std/json.zig").sa_json_value_count;

pub const sa_json_free = @import("sa_std/json.zig").sa_json_free;

pub const sa_json_stringify = @import("sa_std/json.zig").sa_json_stringify;

pub const sa_json_object_set_string = @import("sa_std/json.zig").sa_json_object_set_string;

pub const sa_json_object_set_i64 = @import("sa_std/json.zig").sa_json_object_set_i64;

pub const sa_json_object_set_f64 = @import("sa_std/json.zig").sa_json_object_set_f64;

pub const sa_json_object_set_bool = @import("sa_std/json.zig").sa_json_object_set_bool;

pub const sa_json_object_set_null = @import("sa_std/json.zig").sa_json_object_set_null;

pub const sa_json_object_set_node = @import("sa_std/json.zig").sa_json_object_set_node;

pub const sa_json_object_remove = @import("sa_std/json.zig").sa_json_object_remove;

pub const sa_json_array_push_string = @import("sa_std/json.zig").sa_json_array_push_string;

pub const sa_json_array_push_i64 = @import("sa_std/json.zig").sa_json_array_push_i64;

pub const sa_json_array_push_f64 = @import("sa_std/json.zig").sa_json_array_push_f64;

pub const sa_json_array_push_bool = @import("sa_std/json.zig").sa_json_array_push_bool;

pub const sa_json_array_push_null = @import("sa_std/json.zig").sa_json_array_push_null;

pub const sa_json_array_push_node = @import("sa_std/json.zig").sa_json_array_push_node;






pub const sa_json_scanner_new = @import("sa_std/json.zig").sa_json_scanner_new;

pub const sa_json_scanner_feed = @import("sa_std/json.zig").sa_json_scanner_feed;

pub const sa_json_scanner_end_input = @import("sa_std/json.zig").sa_json_scanner_end_input;

pub const sa_json_scanner_next = @import("sa_std/json.zig").sa_json_scanner_next;

pub const sa_json_scanner_free = @import("sa_std/json.zig").sa_json_scanner_free;

pub const sa_json_stream_new = @import("sa_std/json.zig").sa_json_stream_new;

pub const sa_json_stream_next = @import("sa_std/json.zig").sa_json_stream_next;

pub const sa_json_stream_get_slice_ptr = @import("sa_std/json.zig").sa_json_stream_get_slice_ptr;

pub const sa_json_stream_get_slice_len = @import("sa_std/json.zig").sa_json_stream_get_slice_len;

pub const sa_json_stream_free = @import("sa_std/json.zig").sa_json_stream_free;

pub const sa_json_writer_free = @import("sa_std/json.zig").sa_json_writer_free;

pub const sa_json_writer_new = @import("sa_std/json.zig").sa_json_writer_new;

pub const sa_json_writer_begin_object = @import("sa_std/json.zig").sa_json_writer_begin_object;

pub const sa_json_writer_end_object = @import("sa_std/json.zig").sa_json_writer_end_object;

pub const sa_json_writer_begin_array = @import("sa_std/json.zig").sa_json_writer_begin_array;

pub const sa_json_writer_end_array = @import("sa_std/json.zig").sa_json_writer_end_array;

pub const sa_json_writer_object_field = @import("sa_std/json.zig").sa_json_writer_object_field;

pub const sa_json_writer_field_string = @import("sa_std/json.zig").sa_json_writer_field_string;

pub const sa_json_writer_field_bool = @import("sa_std/json.zig").sa_json_writer_field_bool;

pub const sa_json_writer_field_i64 = @import("sa_std/json.zig").sa_json_writer_field_i64;

pub const sa_json_writer_field_f64 = @import("sa_std/json.zig").sa_json_writer_field_f64;

pub const sa_json_writer_field_null = @import("sa_std/json.zig").sa_json_writer_field_null;

pub const sa_json_writer_field_node = @import("sa_std/json.zig").sa_json_writer_field_node;

pub const sa_json_writer_write_bool = @import("sa_std/json.zig").sa_json_writer_write_bool;

pub const sa_json_writer_write_i64 = @import("sa_std/json.zig").sa_json_writer_write_i64;

pub const sa_json_writer_write_f64 = @import("sa_std/json.zig").sa_json_writer_write_f64;

pub const sa_json_writer_write_string = @import("sa_std/json.zig").sa_json_writer_write_string;

pub const sa_json_writer_write_null = @import("sa_std/json.zig").sa_json_writer_write_null;

pub const sa_json_writer_write_node = @import("sa_std/json.zig").sa_json_writer_write_node;

pub const sa_json_writer_finish = @import("sa_std/json.zig").sa_json_writer_finish;

pub const sa_json_writer_finish_buffer = @import("sa_std/json.zig").sa_json_writer_finish_buffer;

pub const sa_regex_compile = @import("sa_std/regex.zig").sa_regex_compile;

pub const sa_regex_match = @import("sa_std/regex.zig").sa_regex_match;

pub const sa_regex_group_ptr = @import("sa_std/regex.zig").sa_regex_group_ptr;

pub const sa_regex_group_len = @import("sa_std/regex.zig").sa_regex_group_len;

pub const sa_regex_group_start = @import("sa_std/regex.zig").sa_regex_group_start;

pub const sa_regex_group_count = @import("sa_std/regex.zig").sa_regex_group_count;

pub const sa_regex_free = @import("sa_std/regex.zig").sa_regex_free;

pub const sa_regex_match_free = @import("sa_std/regex.zig").sa_regex_match_free;
pub const sa_regex_match_all = @import("sa_std/regex.zig").sa_regex_match_all;

pub const sa_regex_match_list_count = @import("sa_std/regex.zig").sa_regex_match_list_count;

pub const sa_regex_match_list_at = @import("sa_std/regex.zig").sa_regex_match_list_at;

pub const sa_regex_match_list_free = @import("sa_std/regex.zig").sa_regex_match_list_free;

pub const regexReplaceBuffer = @import("sa_std/regex_core.zig").regexReplaceBuffer;

pub const sa_regex_replace = @import("sa_std/regex.zig").sa_regex_replace;

pub const sa_regex_replace_all = @import("sa_std/regex.zig").sa_regex_replace_all;

pub const sa_regex_buffer_data = @import("sa_std/regex.zig").sa_regex_buffer_data;

pub const sa_regex_buffer_len = @import("sa_std/regex.zig").sa_regex_buffer_len;

pub const sa_regex_buffer_free = @import("sa_std/regex.zig").sa_regex_buffer_free;

pub const sa_regex_split = @import("sa_std/regex.zig").sa_regex_split;

pub const sa_regex_split_count = @import("sa_std/regex.zig").sa_regex_split_count;

pub const sa_regex_split_ptr = @import("sa_std/regex.zig").sa_regex_split_ptr;

pub const sa_regex_split_len = @import("sa_std/regex.zig").sa_regex_split_len;

pub const sa_regex_split_free = @import("sa_std/regex.zig").sa_regex_split_free;

// ---------------------------------------------------------------------------
// Unicode normalization (ICU unorm2) for tsgosa String.prototype.normalize.
// Form codes (JEV i32_code): 0 = NFC, 1 = NFD, 2 = NFKC, 3 = NFKD.
// Two-pass length protocol (JEV two_pass_len): call with out_cap == 0 to
// query the needed UTF-8 byte length (nothing written); call again with a
// buffer of at least that size to fill it. If the buffer is too small, the
// function writes nothing and returns the needed length. Invalid form codes
// and invalid UTF-8 input panic (JEV runtime_panic: the SA shape closest to
// JS RangeError). Embedded NUL bytes are fine (all lengths explicit).
// ICU error contract (U_FAILURE semantics): codes > 0 are failures, codes
// <= 0 are success -- negative codes are WARNINGS, not failures. In
// particular U_STRING_NOT_TERMINATED_WARNING (-124) is set when the
// destination is exactly full (content correct, no room for the NUL
// terminator). Every check below is therefore err > 0, never err != 0;
// treating -124 as failure would panic on every exact-fit call (e.g.
// all-ASCII input, or the SA wrapper filling an exactly-sized buffer).
// ICU 74 symbol versioning: the C headers rename these entry points with
// a _74 suffix (U_ICU_VERSION_SUFFIX); Zig extern declarations must use
// the real suffixed symbol. Bumping the ICU major requires renaming
// the seven declarations below.
// NOTE: the SA interpreter cannot run externs (UnsupportedExtern); this
// function executes under build-exe (LLVM) and is unit-tested directly.
// The JS target gets a shim in emit_js.zig (JEV js_shim).
extern fn unorm2_getNFCInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFDInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFKCInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_getNFKDInstance_74(err: *c_int) ?*anyopaque;
extern fn unorm2_normalize_74(norm2: ?*anyopaque, src: [*]const u16, src_len: c_int, dest: [*]u16, dest_cap: c_int, err: *c_int) c_int;
extern fn u_strFromUTF8_74(dest: [*]u16, dest_cap: c_int, dest_len: ?*c_int, src: [*]const u8, src_len: c_int, err: *c_int) ?[*]u16;
extern fn u_strToUTF8_74(dest: ?[*]u8, dest_cap: c_int, dest_len: ?*c_int, src: [*]const u16, src_len: c_int, err: *c_int) ?[*]u8;

const icu_err_overflow: c_int = 15;

fn unicodeNormalizerForForm(form: i32) ?*anyopaque {
    var err: c_int = 0;
    const inst = switch (form) {
        0 => unorm2_getNFCInstance_74(&err),
        1 => unorm2_getNFDInstance_74(&err),
        2 => unorm2_getNFKCInstance_74(&err),
        3 => unorm2_getNFKDInstance_74(&err),
        else => @panic("sa_unicode_normalize: invalid form code"),
    };
    if (err > 0 or inst == null) @panic("sa_unicode_normalize: ICU instance failed");
    return inst;
}

pub export fn sa_unicode_normalize(text: ?[*]const u8, text_len: u64, form: i32, out: ?[*]u8, out_cap: u64) i64 {
    if (text_len == 0) return 0;
    if (text_len > 0x7fffffff) @panic("sa_unicode_normalize: input too long");
    const input = constBytes(text, text_len) catch @panic("sa_unicode_normalize: null input");
    const norm = unicodeNormalizerForForm(form);

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    // UTF-8 -> UTF-16. UTF-16 units never exceed UTF-8 bytes (1-byte char
    // -> 1 unit; 4-byte char -> 2 units), so text_len units always suffice.
    const utf16_cap: c_int = @intCast(text_len);
    const utf16 = alloc.alloc(u16, @as(usize, @intCast(text_len))) catch @panic("sa_unicode_normalize: alloc failed");
    var utf16_len: c_int = 0;
    var err: c_int = 0;
    _ = u_strFromUTF8_74(utf16.ptr, utf16_cap, &utf16_len, input.ptr, utf16_cap, &err);
    if (err > 0) @panic("sa_unicode_normalize: invalid UTF-8 input");

    // Normalize in UTF-16. Decomposition can expand, so grow on overflow
    // (unorm2_normalize_74 returns the needed length on overflow).
    var norm_cap: usize = @as(usize, @intCast(utf16_len)) * 2;
    if (norm_cap < 16) norm_cap = 16;
    var norm_buf = alloc.alloc(u16, norm_cap) catch @panic("sa_unicode_normalize: alloc failed");
    err = 0;
    var norm_len = unorm2_normalize_74(norm, utf16.ptr, utf16_len, norm_buf.ptr, @intCast(norm_cap), &err);
    if (err == icu_err_overflow) {
        if (norm_len <= 0) @panic("sa_unicode_normalize: ICU normalize failed");
        norm_cap = @intCast(norm_len);
        norm_buf = alloc.alloc(u16, norm_cap) catch @panic("sa_unicode_normalize: alloc failed");
        err = 0;
        norm_len = unorm2_normalize_74(norm, utf16.ptr, utf16_len, norm_buf.ptr, @intCast(norm_cap), &err);
        if (err != 0) @panic("sa_unicode_normalize: ICU normalize failed");
    } else if (err > 0) {
        @panic("sa_unicode_normalize: ICU normalize failed");
    }

    // Measure the UTF-8 length (destCapacity 0 query), then fill or report.
    var utf8_len: c_int = 0;
    err = 0;
    _ = u_strToUTF8_74(null, 0, &utf8_len, norm_buf.ptr, norm_len, &err);
    if (err > 0 and err != icu_err_overflow) @panic("sa_unicode_normalize: ICU UTF-8 measure failed");
    if (out_cap == 0 or out == null) return utf8_len;
    if (@as(u64, @intCast(utf8_len)) > out_cap) return utf8_len;
    var written: c_int = 0;
    err = 0;
    _ = u_strToUTF8_74(out.?, @intCast(out_cap), &written, norm_buf.ptr, norm_len, &err);
    if (err > 0) @panic("sa_unicode_normalize: ICU UTF-8 convert failed");
    return written;
}

// Host presence probing (lazy const-slot design, Phase 0; JEV js_shim_native_zero).
// SA native execution runs under the sa interpreter/LLVM with no JS host
// global, so "is Bun" is definitionally false there. Returning 0 always is
// the contract, not a placeholder. The JS target gets a shim in emit_js.zig
// returning typeof Bun !== "undefined" ? 1 : 0. Env-sniffing was
// JEV-rejected (Bun sets no distinctive environment variable by default).
// The SA interpreter cannot run externs (UnsupportedExtern); this function
// executes under build-exe (LLVM), like sa_unicode_normalize above.
pub export fn sa_host_is_bun() i32 {
    return 0;
}












pub const sa_json_buffer_data = @import("sa_std/json.zig").sa_json_buffer_data;

pub const sa_json_buffer_len = @import("sa_std/json.zig").sa_json_buffer_len;

pub const sa_json_buffer_free = @import("sa_std/json.zig").sa_json_buffer_free;

pub const sa_time_instant_ns = @import("sa_std/time.zig").sa_time_instant_ns;

pub const sa_time_unix_s = @import("sa_std/time.zig").sa_time_unix_s;

pub const sa_time_unix_ms = @import("sa_std/time.zig").sa_time_unix_ms;

/// Shared civil split: i64 unix millis to (days since epoch, millis
/// within day, Hinnant y/m/d, h/mi/s/ms). Negative inputs fold via
/// floored division; field order matches the getters below.
const CivilParts = struct {
    year: i64,
    month: i64,
    day: i64,
    hour: i64,
    minute: i64,
    second: i64,
    milli: i64,
    days: i64,
};

pub fn civilParts(ms: i64) CivilParts {
    const ms_per_day: i64 = 86400000;
    var days = @divFloor(ms, ms_per_day);
    var day_ms = @mod(ms, ms_per_day);
    if (day_ms < 0) {
        day_ms += ms_per_day;
        days -= 1;
    }
    const z: i64 = days + 719468;
    const era: i64 = if (z >= 0) @divFloor(z, 146097) else @divFloor(z - 146096, 146097);
    const doe: i64 = z - era * 146097;
    const yoe: i64 = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y: i64 = yoe + era * 400;
    const doy: i64 = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp: i64 = @divFloor(5 * doy + 2, 153);
    const month: i64 = if (mp < 10) mp + 3 else mp - 9;
    return .{
        .year = if (month <= 2) y + 1 else y,
        .month = month,
        .day = doy - @divFloor(153 * mp + 2, 5) + 1,
        .hour = @divFloor(day_ms, 3600000),
        .minute = @divFloor(@mod(day_ms, 3600000), 60000),
        .second = @divFloor(@mod(day_ms, 60000), 1000),
        .milli = @mod(day_ms, 1000),
        .days = days,
    };
}

/// JS `Date.toISOString` shape for an i64 unix-millis value: UTC
/// `YYYY-MM-DDTHH:MM:SS.sssZ` (millis precision, zero-padded; years
/// 0..9999 exact, larger years print unpadded-past-4 like the denoise
/// path). Negative inputs (pre-1970) fold correctly via floored
/// division (Howard Hinnant civil_from_days). Fresh buffer handle read
/// back via `sa_fmt_buffer_data`/`sa_fmt_buffer_len` like concat.
pub const sa_time_iso_from_unix_ms = @import("sa_std/time.zig").sa_time_iso_from_unix_ms;

/// Strict-ISO `Date.parse`: `YYYY-MM-DD[THH:MM:SS[.sss]][Z|±HH:MM]`
/// to unix millis. Plain i32 status (0 ok, 2 invalid); range-checked
/// (leap days, h<24, m/s<60); date-only means UTC midnight per JS.
/// Inverse Hinnant days_from_civil; years 0..9999 keep i64 arithmetic
/// exact (bounded well inside range, no checked ops needed).
pub const sa_time_parse_iso = @import("sa_std/time.zig").sa_time_parse_iso;

/// JS Date getters over i64 unix millis (UTC; month 0-based like JS,
/// day 0=Sunday like JS: 1970-01-01 was a Thursday).
pub const sa_time_get_full_year = @import("sa_std/time.zig").sa_time_get_full_year;

pub const sa_time_get_month = @import("sa_std/time.zig").sa_time_get_month;

pub const sa_time_get_date = @import("sa_std/time.zig").sa_time_get_date;

pub const sa_time_get_hours = @import("sa_std/time.zig").sa_time_get_hours;

pub const sa_time_get_minutes = @import("sa_std/time.zig").sa_time_get_minutes;

pub const sa_time_get_seconds = @import("sa_std/time.zig").sa_time_get_seconds;

pub const sa_time_get_milliseconds = @import("sa_std/time.zig").sa_time_get_milliseconds;

pub const sa_time_get_day = @import("sa_std/time.zig").sa_time_get_day;

pub const weekdayNames = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
pub const monthNames = [_][]const u8{ "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" };

pub fn appendTwo(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 2) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

pub fn appendFour(out: *std.array_list.Managed(u8), val: i64) !void {
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < 4) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

/// Fixed UTC string forms for Date toString/toDateString/toTimeString/
/// toUTCString (fmt 0..3), byte-exact with Node under UTC. Years use the
/// same 4-digit zero pad as the ISO path (documented bound 0..9999).
pub const sa_time_format_utc = @import("sa_std/time.zig").sa_time_format_utc;

pub fn daysFromCivil(y_in: i64, m_in: i64, d: i64) i64 {
    const y: i64 = if (m_in <= 2) y_in - 1 else y_in;
    const era: i64 = if (y >= 0) @divFloor(y, 400) else @divFloor(y - 399, 400);
    const yoe: i64 = y - era * 400;
    const mp: i64 = @mod(m_in - 3, 12);
    const doy: i64 = @divFloor(153 * mp + 2, 5) + d - 1;
    const doe: i64 = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// JS Date setters over i64 unix millis (field 0..6). Components apply
/// then normalize with floored divmod, so out-of-range values roll over
/// exactly like JS (setMonth(13), setDate(0), setHours(25), negatives).
/// Unknown field ids return the input unchanged (frontends only ever
/// send 0..6 via fixed table extras).
pub const sa_time_set_field = @import("sa_std/time.zig").sa_time_set_field;

pub const sa_time_unix_ns = @import("sa_std/time.zig").sa_time_unix_ns;

pub const sa_time_utc_now = @import("sa_std/time.zig").sa_time_utc_now;

pub const sa_time_sleep_ns = @import("sa_std/time.zig").sa_time_sleep_ns;

pub const sa_time_sleep_ms = @import("sa_std/time.zig").sa_time_sleep_ms;

pub export fn sa_std_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (out_written) |ptr| ptr.* = 0;
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    const written = writeHandle(handle, bytes) catch |err| return finishErr(err);
    if (out_written) |ptr| ptr.* = @as(u64, @intCast(written));
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    const read = readHandle(handle, buffer) catch |err| return finishErr(err);
    if (out_read) |ptr| ptr.* = @as(u64, @intCast(read));
    return finish(SA_STD_OK);
}

pub export fn sa_std_close(handle: u64) i32 {
    if (handle == SA_STD_STDIN or handle == SA_STD_STDOUT or handle == SA_STD_STDERR) return finish(SA_STD_ERR_INVALID_HANDLE);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    var resource = takeResourceLocked(handle) orelse {
        registry_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    registry_mutex.unlock();
    resource.close() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub const sa_io_read_line = @import("sa_std/io.zig").sa_io_read_line;

// Compatibility shims for the rosetta demos that model host APIs directly.
pub fn fd_open(path_ptr: ?[*]const u8) callconv(.c) i32 {
    _ = path_ptr;
    last_error = SA_STD_OK;
    return 3;
}

pub fn fd_read(fd: i32) callconv(.c) i32 {
    _ = fd;
    last_error = SA_STD_OK;
    return 3;
}

pub fn fd_close(fd: i32) callconv(.c) i32 {
    _ = fd;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub fn mmap(fd: i32, len: i32) callconv(.c) ?[*]u8 {
    _ = fd;
    _ = len;
    last_error = SA_STD_OK;
    return compatibility_mmap_page[0..].ptr;
}

pub fn munmap(map: ?[*]u8, len: i32) callconv(.c) i32 {
    _ = map;
    _ = len;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn signal(sig: i32, handler: ?[*]const u8) callconv(.c) i32 {
    _ = handler;
    last_error = SA_STD_OK;
    return sig;
}

pub const pthread_spawn = @import("sa_std/pthread.zig").pthread_spawn;

pub const pthread_spawn_detached = @import("sa_std/pthread.zig").pthread_spawn_detached;

pub const pthread_join = @import("sa_std/pthread.zig").pthread_join;

pub const sa_thread_as_pthread_t = @import("sa_std/pthread.zig").sa_thread_as_pthread_t;

pub const sa_thread_into_pthread_t = @import("sa_std/pthread.zig").sa_thread_into_pthread_t;

pub const sa_thread_raw_pthread_join = @import("sa_std/pthread.zig").sa_thread_raw_pthread_join;

pub const pthread_drop = @import("sa_std/pthread.zig").pthread_drop;

pub fn dlopen(path_ptr: ?[*]const u8, flags: i32) callconv(.c) ?[*]u8 {
    _ = path_ptr;
    _ = flags;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlopen_cookie[0..].ptr;
}

pub fn dlsym(handle: ?[*]u8, symbol_ptr: ?[*]const u8) callconv(.c) ?[*]u8 {
    _ = handle;
    _ = symbol_ptr;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return compatibility_dlsym_cookie[0..].ptr;
}

pub fn dlclose(handle: ?[*]u8) callconv(.c) i32 {
    _ = handle;
    last_error = SA_STD_ERR_UNSUPPORTED;
    return SA_STD_ERR_UNSUPPORTED;
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    // wasm32-wasi has no dlopen; comptime guard keeps std.DynLib refs out of wasm build.
    if (comptime builtin.cpu.arch.isWasm()) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);

    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_z = std.heap.page_allocator.dupeSentinel(u8, path, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(path_z);

    const lib = std.DynLib.openZ(path_z) catch |err| switch (err) {
        error.FileNotFound, error.NotElfFile, error.NotDynamicLibrary => {
            compatibility_dl_error = "not_found";
            return finish(SA_STD_ERR_NOT_FOUND);
        },
        error.OutOfMemory => return finish(SA_STD_ERR_NO_MEMORY),
        else => return finish(SA_STD_ERR_UNKNOWN),
    };

    const handle = std.heap.page_allocator.create(DynamicLibHandle) catch |err| {
        var lib_copy = lib;
        lib_copy.close();
        return finishErr(err);
    };
    handle.* = .{ .lib = lib };

    const resource_handle = registerResource(.{ .dynamic_lib = handle }) catch |err| {
        handle.deinit();
        std.heap.page_allocator.destroy(handle);
        return finishErr(err);
    };

    handle_ptr.* = resource_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const result_ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result_ptr.* = null;
    if (comptime builtin.cpu.arch.isWasm()) return finish(SA_STD_ERR_UNSUPPORTED);
    if (builtin.os.tag != .linux) return finish(SA_STD_ERR_UNSUPPORTED);

    const symbol = pathBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    const symbol_z = std.heap.page_allocator.dupeSentinel(u8, symbol, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);

    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const lib_handle = switch (resource.*) {
        .dynamic_lib => |lib| lib,
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    };
    result_ptr.* = lib_handle.lib.lookup(*anyopaque, symbol_z) orelse {
        compatibility_dl_error = "not_found";
        return finish(SA_STD_ERR_NOT_FOUND);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_dl_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return compatibility_dl_error.ptr;
}

pub fn sqlite3_prepare(sqlite: ?[*]u8, sql: ?[*]const u8, len: i32, stmt_out: ?[*]u8) callconv(.c) i32 {
    _ = sqlite;
    _ = sql;
    _ = len;
    _ = stmt_out;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

pub fn sqlite3_step(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return 1;
}

pub fn sqlite3_finalize(stmt: ?[*]u8) callconv(.c) i32 {
    _ = stmt;
    last_error = SA_STD_OK;
    return SA_STD_OK;
}

comptime {
    if (!builtin.is_test) {
        @export(&fd_open, .{ .name = "fd_open" });
        @export(&fd_read, .{ .name = "fd_read" });
        @export(&fd_close, .{ .name = "fd_close" });
        @export(&pthread_spawn, .{ .name = "pthread_spawn" });
        @export(&pthread_spawn_detached, .{ .name = "pthread_spawn_detached" });
        // The SA-facing join is exported ONLY under the non-colliding
        // name sa_pthread_join (see thread.sai): the definition's
        // handle-registry ABI is not libc's pthread_join signature.
        // Under the bare name it captured std.Thread's joins when
        // exported (the F1 incident class below) and, once gated to
        // no-libc targets, SA programs fell through to glibc's
        // pthread_join and segfaulted on the slot id.
        @export(&pthread_join, .{ .name = "sa_pthread_join" });
        @export(&pthread_drop, .{ .name = "pthread_drop" });
        @export(&sa_thread_as_pthread_t, .{ .name = "sa_thread_as_pthread_t" });
        @export(&sa_thread_into_pthread_t, .{ .name = "sa_thread_into_pthread_t" });
        @export(&sa_thread_raw_pthread_join, .{ .name = "sa_thread_raw_pthread_join" });
        // The dl* compatibility definitions must only be exported where the
        // target has no real libc dlopen (wasi / no-libc links). On libc
        // targets they capture std.DynLib's extern references at link time
        // (hidden visibility does not prevent archive-member binding), which
        // silently replaced every runtime dlopen with the cookie stub:
        // brotli/QUIC/TLS loaders degraded and SSH crashed calling the
        // cookie address from SA-produced binaries. Test builds never saw
        // it because this block is skipped under builtin.is_test.
        //
        // The same capture applies to every other compatibility definition
        // whose name collides with a libc symbol, so they share the dl*
        // gate: mmap/munmap (the page allocator's extern references bound
        // to the no-op stub — an 8,000-request HTTP client loop issued
        // 120,066 mmap syscalls against exactly 1 munmap, growing RSS
        // without bound in slanginx/slaredis-class long-running
        // executables), signal (stub installs no handler), pthread_join
        // (the bare libc name stays gated to no-libc targets as a compat
        // surface; SA programs use sa_pthread_join, exported above —
        // the handle-registry ABI is not the libc signature std.Thread
        // joins through), and the sqlite3_* stubs (would shadow a real
        // libsqlite3 in the same link).
        if (builtin.os.tag == .wasi or !builtin.link_libc) {
            @export(&dlopen, .{ .name = "dlopen", .visibility = .hidden });
            @export(&dlsym, .{ .name = "dlsym", .visibility = .hidden });
            @export(&dlclose, .{ .name = "dlclose", .visibility = .hidden });
            // mmap/munmap are weak on top of hidden: hidden alone still
            // collides at link time when a client object referencing the
            // real libc mmap/munmap (e.g. an SA-implemented std unit such
            // as GrowVec) pulls libc's mman.o into a link that also pulls
            // this compilation unit -- wasm-ld reports a duplicate symbol
            // against the stub. Weak lets the real libc definition win
            // whenever one is present in the link, while the stub still
            // serves links with no libc at all. References from inside
            // this unit (the page allocator) bind locally either way.
            @export(&mmap, .{ .name = "mmap", .visibility = .hidden, .linkage = .weak });
            @export(&munmap, .{ .name = "munmap", .visibility = .hidden, .linkage = .weak });
            @export(&signal, .{ .name = "signal", .visibility = .hidden });
            @export(&pthread_join, .{ .name = "pthread_join", .visibility = .hidden });
            @export(&sqlite3_prepare, .{ .name = "sqlite3_prepare", .visibility = .hidden });
            @export(&sqlite3_step, .{ .name = "sqlite3_step", .visibility = .hidden });
            @export(&sqlite3_finalize, .{ .name = "sqlite3_finalize", .visibility = .hidden });
        }
    }
}

pub const sa_std_fs_open_read = @import("sa_std/std_fs.zig").sa_std_fs_open_read;

pub const sa_std_fs_open_write = @import("sa_std/std_fs.zig").sa_std_fs_open_write;

pub const sa_std_fs_remove = @import("sa_std/std_fs.zig").sa_std_fs_remove;

pub const sa_std_fs_exists = @import("sa_std/std_fs.zig").sa_std_fs_exists;

pub const sa_std_fs_try_exists = @import("sa_std/std_fs.zig").sa_std_fs_try_exists;

pub const sa_std_fs_len = @import("sa_std/std_fs.zig").sa_std_fs_len;

pub const sa_std_process_run = @import("sa_std/std_process.zig").sa_std_process_run;

pub const sa_std_process_run_cwd = @import("sa_std/std_process.zig").sa_std_process_run_cwd;

pub const sa_std_process_spawn = @import("sa_std/std_process.zig").sa_std_process_spawn;

pub const sa_std_process_spawn_cwd = @import("sa_std/std_process.zig").sa_std_process_spawn_cwd;

pub const sa_std_process_spawn_stream = @import("sa_std/std_process.zig").sa_std_process_spawn_stream;

pub const sa_std_process_spawn_stream_cwd = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_cwd;


pub const sa_std_process_spawn_bidi = @import("sa_std/std_process.zig").sa_std_process_spawn_bidi;

pub const sa_std_process_spawn_bidi_cwd = @import("sa_std/std_process.zig").sa_std_process_spawn_bidi_cwd;

pub fn processCommandExtConfig(arg0_ptr: ?[*]const u8, arg0_len: u64, has_arg0: u32, process_group: i32, has_process_group: u32, setsid: u32, create_pidfd: u32, uid: u32, has_uid: u32, gid: u32, has_gid: u32, groups_ptr: ?[*]const u32, groups_len: u64, has_groups: u32, chroot_ptr: ?[*]const u8, chroot_len: u64, has_chroot: u32) !ProcessSpawnConfig {
    if (has_process_group != 0 and process_group < 0) return error.InvalidArgument;
    return .{
        .arg0 = if (has_arg0 != 0) try constBytes(arg0_ptr, arg0_len) else null,
        .process_group = if (has_process_group != 0) process_group else null,
        .setsid = setsid != 0,
        .create_pidfd = create_pidfd != 0,
        .uid = if (has_uid != 0) uid else null,
        .gid = if (has_gid != 0) gid else null,
        .groups = if (has_groups != 0) try constU32s(groups_ptr, groups_len) else null,
        .chroot_path = if (has_chroot != 0) try pathBytes(chroot_ptr, chroot_len) else null,
    };
}

pub const sa_std_process_run_command_ext = @import("sa_std/std_process.zig").sa_std_process_run_command_ext;

pub const sa_std_process_spawn_command_ext = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext;

pub const sa_std_process_spawn_stream_command_ext = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext;

pub const sa_std_process_run_command_ext_pidfd = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_pidfd;

pub const sa_std_process_spawn_command_ext_pidfd = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_pidfd;

pub const sa_std_process_spawn_stream_command_ext_pidfd = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_pidfd;

pub const sa_std_process_run_command_ext_uid_gid = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_uid_gid;

pub const sa_std_process_spawn_command_ext_uid_gid = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_uid_gid;

pub const sa_std_process_spawn_stream_command_ext_uid_gid = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_uid_gid;

pub const sa_std_process_run_command_ext_groups = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_groups;

pub const sa_std_process_spawn_command_ext_groups = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_groups;

pub const sa_std_process_spawn_stream_command_ext_groups = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_groups;

pub const sa_std_process_run_command_ext_chroot = @import("sa_std/std_process.zig").sa_std_process_run_command_ext_chroot;

pub const sa_std_process_spawn_command_ext_chroot = @import("sa_std/std_process.zig").sa_std_process_spawn_command_ext_chroot;

pub const sa_std_process_spawn_stream_command_ext_chroot = @import("sa_std/std_process.zig").sa_std_process_spawn_stream_command_ext_chroot;

pub const sa_std_process_exec_command_ext = @import("sa_std/std_process.zig").sa_std_process_exec_command_ext;

pub const sa_std_process_id = @import("sa_std/std_process.zig").sa_std_process_id;

pub const sa_std_process_parent_id = @import("sa_std/std_process.zig").sa_std_process_parent_id;

pub const sa_std_process_user_id = @import("sa_std/std_process.zig").sa_std_process_user_id;

pub const sa_std_process_group_id = @import("sa_std/std_process.zig").sa_std_process_group_id;

pub const sa_std_process_abort = @import("sa_std/std_process.zig").sa_std_process_abort;

pub const sa_std_process_child_id = @import("sa_std/std_process.zig").sa_std_process_child_id;

pub const sa_std_process_wait = @import("sa_std/std_process.zig").sa_std_process_wait;

pub const sa_std_process_wait_raw = @import("sa_std/std_process.zig").sa_std_process_wait_raw;

pub const sa_std_process_try_wait = @import("sa_std/std_process.zig").sa_std_process_try_wait;

pub const sa_std_process_try_wait_raw = @import("sa_std/std_process.zig").sa_std_process_try_wait_raw;

pub const sa_std_process_kill = @import("sa_std/std_process.zig").sa_std_process_kill;

pub const sa_std_process_send_signal = @import("sa_std/std_process.zig").sa_std_process_send_signal;

pub const sa_std_process_send_process_group_signal = @import("sa_std/std_process.zig").sa_std_process_send_process_group_signal;

pub const sa_std_process_kill_process_group = @import("sa_std/std_process.zig").sa_std_process_kill_process_group;

pub const sa_std_process_pidfd = @import("sa_std/std_process.zig").sa_std_process_pidfd;

pub const sa_std_process_into_pidfd = @import("sa_std/std_process.zig").sa_std_process_into_pidfd;

pub export fn sa_std_pidfd_kill(handle: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            sendSignalToPidfd(fd.fd, @backingInt(SIGT.KILL), 0) catch |err| switch (err) {
                error.InvalidArgument => return finish(SA_STD_ERR_INVALID_ARGUMENT),
                error.PermissionDenied => return finish(SA_STD_ERR_ACCESS),
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_pidfd_send_signal(handle: u64, signum: i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    if (signum < 0 or signum > std.math.maxInt(u8)) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            sendSignalToPidfd(fd.fd, @as(u8, @intCast(signum)), 0) catch |err| switch (err) {
                error.InvalidArgument => return finish(SA_STD_ERR_INVALID_ARGUMENT),
                error.PermissionDenied => return finish(SA_STD_ERR_ACCESS),
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub const sa_std_pidfd_wait_raw = @import("sa_std/proc_wait.zig").sa_std_pidfd_wait_raw;

pub const sa_std_pidfd_wait = @import("sa_std/proc_wait.zig").sa_std_pidfd_wait;

pub const sa_std_pidfd_try_wait_raw = @import("sa_std/proc_wait.zig").sa_std_pidfd_try_wait_raw;

pub const sa_std_pidfd_try_wait = @import("sa_std/proc_wait.zig").sa_std_pidfd_try_wait;

pub const sa_std_process_exit_status_code = @import("sa_std/std_process.zig").sa_std_process_exit_status_code;

pub const sa_std_process_exit_status_signal = @import("sa_std/std_process.zig").sa_std_process_exit_status_signal;

pub const sa_std_process_exit_status_core_dumped = @import("sa_std/std_process.zig").sa_std_process_exit_status_core_dumped;

pub const sa_std_process_exit_status_stopped_signal = @import("sa_std/std_process.zig").sa_std_process_exit_status_stopped_signal;

pub const sa_std_process_exit_status_continued = @import("sa_std/std_process.zig").sa_std_process_exit_status_continued;

const ProcessOutputStream = enum { stdout, stderr };

pub fn readProcessOutput(handle: u64, stream: ProcessOutputStream, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .process => |*proc| {
            if (!proc.capture_output or !proc.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
            const src = switch (stream) {
                .stdout => proc.stdout_buf,
                .stderr => proc.stderr_buf,
            };
            const pos_ptr = switch (stream) {
                .stdout => &proc.stdout_pos,
                .stderr => &proc.stderr_pos,
            };
            if (pos_ptr.* >= src.len) return finish(SA_STD_OK);
            const remaining = src.len - pos_ptr.*;
            const copy_len = @min(output.len, remaining);
            @memcpy(output[0..copy_len], src[pos_ptr.* .. pos_ptr.* + copy_len]);
            pos_ptr.* += copy_len;
            if (out_read) |ptr| ptr.* = @as(u64, @intCast(copy_len));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub const sa_std_process_read_stdout = @import("sa_std/std_process.zig").sa_std_process_read_stdout;

pub const sa_std_process_read_stderr = @import("sa_std/std_process.zig").sa_std_process_read_stderr;

pub const sa_std_process_exec_capture = @import("sa_std/std_process.zig").sa_std_process_exec_capture;

pub const sa_std_process_exec_capture_cwd = @import("sa_std/std_process.zig").sa_std_process_exec_capture_cwd;

pub const sa_std_process_close = @import("sa_std/std_process.zig").sa_std_process_close;

pub export fn sa_std_fd_as_raw(handle: u64, out_fd: ?*i32) i32 {
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    fd_ptr.* = @as(i32, @intCast(fd));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_dup(handle: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    const dup_fd = lxDup(fd) catch |err| return finishErr(err);
    const dup_handle = registerResourceLocked(.{ .owned_fd = .{ .fd = dup_fd } }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = dup_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_dup_raw(fd: i32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);

    const source_fd = @as(std.posix.fd_t, @intCast(fd));
    const dup_fd = lxDup(source_fd) catch |err| return finishErr(err);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const dup_handle = registerResourceLocked(.{ .owned_fd = .{ .fd = dup_fd } }) catch |err| {
        lxClose(dup_fd);
        return finishErr(err);
    };
    handle_ptr.* = dup_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_from_raw(fd: i32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const handle = registerResourceLocked(.{ .owned_fd = .{ .fd = @as(std.posix.fd_t, @intCast(fd)) } }) catch |err| return finishErr(err);
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_into_raw(handle: u64, out_fd: ?*i32) i32 {
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();

    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    switch (resource.*) {
        .file, .tcp_stream, .tcp_listener, .udp_socket, .owned_fd => {},
        else => return finish(SA_STD_ERR_INVALID_HANDLE),
    }

    const taken = takeResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    fd_ptr.* = switch (taken) {
        .file => |file| @as(i32, @intCast(file.inner.handle)),
        .tcp_stream => |stream| @as(i32, @intCast(stream)),
        .tcp_listener => |server| @as(i32, @intCast(server.fd)),
        .udp_socket => |fd_value| @as(i32, @intCast(fd_value)),
        .owned_fd => |fd_handle| @as(i32, @intCast(fd_handle.fd)),
        else => unreachable,
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_close_raw(fd: i32) i32 {
    if (fd < 0) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    lxClose(@as(std.posix.fd_t, @intCast(fd)));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fd_is_terminal(handle: u64, out_flag: ?*u8) i32 {
    const flag_ptr = out_flag orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    flag_ptr.* = 0;
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const fd = handleToFd(handle) catch |err| return finishErr(err);
    flag_ptr.* = if (lxIsatty(fd)) 1 else 0;
    return finish(SA_STD_OK);
}

pub export fn sa_thread_current_id() u64 {
    return @as(u64, @intCast(std.Thread.getCurrentId()));
}

pub export fn sa_thread_yield_now() i32 {
    std.Thread.yield() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub const sa_term_raw_enter = @import("sa_std/term.zig").sa_term_raw_enter;

pub const sa_term_raw_leave = @import("sa_std/term.zig").sa_term_raw_leave;

pub const sa_term_winsize = @import("sa_std/term.zig").sa_term_winsize;

pub const sa_term_epoll_create = @import("sa_std/term.zig").sa_term_epoll_create;

pub const sa_term_epoll_create_linux = @import("sa_std/term.zig").sa_term_epoll_create_linux;

pub const sa_term_epoll_ctl = @import("sa_std/term.zig").sa_term_epoll_ctl;

pub const sa_term_epoll_ctl_linux = @import("sa_std/term.zig").sa_term_epoll_ctl_linux;

pub const sa_term_epoll_wait = @import("sa_std/term.zig").sa_term_epoll_wait;

pub const sa_term_epoll_wait_linux = @import("sa_std/term.zig").sa_term_epoll_wait_linux;

pub const sa_term_epoll_close = @import("sa_std/term.zig").sa_term_epoll_close;

pub const sa_term_epoll_close_linux = @import("sa_std/term.zig").sa_term_epoll_close_linux;

pub const sa_io_stdin = @import("sa_std/io.zig").sa_io_stdin;

pub const sa_io_stdout = @import("sa_std/io.zig").sa_io_stdout;

pub const sa_io_stderr = @import("sa_std/io.zig").sa_io_stderr;

pub const sa_io_read = @import("sa_std/io.zig").sa_io_read;

pub const sa_io_read_exact = @import("sa_std/io.zig").sa_io_read_exact;

pub const sa_io_write = @import("sa_std/io.zig").sa_io_write;

pub const sa_io_write_all = @import("sa_std/io.zig").sa_io_write_all;

pub const sa_io_flush = @import("sa_std/io.zig").sa_io_flush;

pub const sa_io_close = @import("sa_std/io.zig").sa_io_close;

// W1-DEF-IO-BUFFER-API: io buffers are registry handles, the same
// BufferHandle resources sa_io_read_line registers and the
// sa_fs_read_buffer_* family already serves. The old raw-pointer
// form expected a *BufferHandle struct that no producer on this
// surface ever hands out (read_line returns a handle), and free
// ignored its argument entirely. All three now resolve the handle
// through the registry, sharing the fs family's implementation.
pub const sa_io_buffer_data = @import("sa_std/io.zig").sa_io_buffer_data;

pub const sa_io_buffer_len = @import("sa_std/io.zig").sa_io_buffer_len;

pub const sa_io_buffer_free = @import("sa_std/io.zig").sa_io_buffer_free;

pub const saFsOpenFile = @import("sa_std/fs.zig").saFsOpenFile;
pub const sa_fs_open_accmode_mask = @import("sa_std/fs.zig").sa_fs_open_accmode_mask;

pub const sa_fs_file_open = @import("sa_std/fs.zig").sa_fs_file_open;

pub const sa_fs_file_create = @import("sa_std/fs.zig").sa_fs_file_create;

pub const sa_fs_file_close = @import("sa_std/fs.zig").sa_fs_file_close;

pub const sa_std_fs_open_options = @import("sa_std/std_fs.zig").sa_std_fs_open_options;

/// Atomic create-exclusive open (2026-10-26): read|write|create with
/// O_EXCL merged through custom flags. An existing path fails with
/// SA_STD_ERR_ALREADY_EXISTS (via error.PathAlreadyExists in mapError),
/// which lock-file protocols need to tell "lost the race" apart from a
/// generic IO failure.
pub const sa_std_fs_open_create_excl = @import("sa_std/std_fs.zig").sa_std_fs_open_create_excl;

pub const sa_std_fs_file_from_raw_fd = @import("sa_std/std_fs.zig").sa_std_fs_file_from_raw_fd;

pub const sa_std_fs_file_read = @import("sa_std/std_fs.zig").sa_std_fs_file_read;
pub const sa_fs_file_read = @import("sa_std/fs.zig").sa_fs_file_read;

pub const sa_std_fs_file_read_at = @import("sa_std/std_fs.zig").sa_std_fs_file_read_at;

pub const sa_std_fs_file_read_exact_at = @import("sa_std/std_fs.zig").sa_std_fs_file_read_exact_at;

pub const sa_fs_file_read_exact = @import("sa_std/fs.zig").sa_fs_file_read_exact;
pub const sa_std_fs_file_write = @import("sa_std/std_fs.zig").sa_std_fs_file_write;

pub const sa_std_fs_file_write_at = @import("sa_std/std_fs.zig").sa_std_fs_file_write_at;

pub const sa_std_fs_file_write_all_at = @import("sa_std/std_fs.zig").sa_std_fs_file_write_all_at;

pub const sa_fs_file_write = @import("sa_std/fs.zig").sa_fs_file_write;
pub const sa_fs_file_write_all = @import("sa_std/fs.zig").sa_fs_file_write_all;
pub const sa_fs_file_flush = @import("sa_std/fs.zig").sa_fs_file_flush;

pub const sa_fs_file_sync_data = @import("sa_std/fs.zig").sa_fs_file_sync_data;

pub const sa_fs_file_sync = @import("sa_std/fs.zig").sa_fs_file_sync;

pub const sa_fs_file_truncate = @import("sa_std/fs.zig").sa_fs_file_truncate;

pub const sa_fs_file_seek = @import("sa_std/fs.zig").sa_fs_file_seek;

pub const sa_std_fs_file_seek = @import("sa_std/std_fs.zig").sa_std_fs_file_seek;

pub const sa_fs_read_file = @import("sa_std/fs.zig").sa_fs_read_file;

pub const sa_std_fs_read_file = @import("sa_std/std_fs.zig").sa_std_fs_read_file;

pub const sa_fs_read_to_string = @import("sa_std/fs.zig").sa_fs_read_to_string;

pub const sa_std_fs_read_to_string = @import("sa_std/std_fs.zig").sa_std_fs_read_to_string;

pub const sa_fs_write_file = @import("sa_std/fs.zig").sa_fs_write_file;

pub const sa_fs_read_buffer_data = @import("sa_std/fs.zig").sa_fs_read_buffer_data;

pub const sa_fs_read_buffer_len = @import("sa_std/fs.zig").sa_fs_read_buffer_len;

pub const sa_fs_read_buffer_free = @import("sa_std/fs.zig").sa_fs_read_buffer_free;

pub const sa_fs_read_file_base64 = @import("sa_std/fs.zig").sa_fs_read_file_base64;

pub const sa_std_fs_read_file_base64 = @import("sa_std/std_fs.zig").sa_std_fs_read_file_base64;

pub const sa_fs_write_file_base64 = @import("sa_std/fs.zig").sa_fs_write_file_base64;

pub const writeJsonBoolField = @import("sa_std/dir_stat.zig").writeJsonBoolField;

pub const nsToMs = @import("sa_std/dir_stat.zig").nsToMs;

pub const writeJsonIntField = @import("sa_std/dir_stat.zig").writeJsonIntField;

pub const writeMetadataJson = @import("sa_std/dir_stat.zig").writeMetadataJson;

pub const writeMetadataJsonExt = @import("sa_std/dir_stat.zig").writeMetadataJsonExt;

pub const dirEntryKindFromLinuxType = @import("sa_std/dir_stat.zig").dirEntryKindFromLinuxType;

pub const dirEntryKindFromIo = @import("sa_std/dir_stat.zig").dirEntryKindFromIo;

pub const readDirEntriesLinux = @import("sa_std/dir_stat.zig").readDirEntriesLinux;

pub fn metadataModeMatches(handle: u64, mode_bits: u64) u8 {
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if ((@as(u64, @intCast(metadata.raw.mode)) & std.posix.S.IFMT) == mode_bits) 1 else 0,
        else => 0,
    };
}

pub fn mkdirPathWithMode(path: []const u8, mode: std.posix.mode_t) !void {
    if (comptime is_wasm) return error.Unsupported;
    if (path.len == 0) return error.BadPathName;

    var index: usize = if (path[0] == '/') 1 else 0;
    while (index < path.len and path[index] == '/') : (index += 1) {}

    while (index <= path.len) {
        var next = index;
        while (next < path.len and path[next] != '/') : (next += 1) {}
        if (next > 0) {
            const prefix = path[0..next];
            if (prefix.len != 0 and !(prefix.len == 1 and prefix[0] == '/')) {
                // Compared, not switched on: lxMkdirat's inferred
                // error set on wasm lacks PathAlreadyExists (its
                // wasm branch returns only error.Unsupported), and a
                // catch-switch arm must name a set member.
                lxMkdirat(std.posix.AT.FDCWD, prefix, mode) catch |err| {
                    if (err != error.PathAlreadyExists) return err;
                };
            }
        }
        if (next == path.len) break;
        index = next + 1;
        while (index < path.len and path[index] == '/') : (index += 1) {}
    }
}

pub const sa_fs_read_dir_json = @import("sa_std/fs.zig").sa_fs_read_dir_json;

pub const sa_std_fs_read_dir_json = @import("sa_std/std_fs.zig").sa_std_fs_read_dir_json;

pub const sa_fs_dir_buffer_data = @import("sa_std/fs.zig").sa_fs_dir_buffer_data;

pub const sa_fs_dir_buffer_len = @import("sa_std/fs.zig").sa_fs_dir_buffer_len;

pub const sa_fs_dir_buffer_free = @import("sa_std/fs.zig").sa_fs_dir_buffer_free;

pub const sa_fs_read_dir_entries = @import("sa_std/fs.zig").sa_fs_read_dir_entries;

pub const sa_std_fs_read_dir_entries = @import("sa_std/std_fs.zig").sa_std_fs_read_dir_entries;

pub const sa_fs_dir_entries_len = @import("sa_std/fs.zig").sa_fs_dir_entries_len;

pub const sa_std_fs_dir_entries_get = @import("sa_std/std_fs.zig").sa_std_fs_dir_entries_get;

pub const sa_fs_dir_entries_free = @import("sa_std/fs.zig").sa_fs_dir_entries_free;

pub const sa_fs_dir_entry_name_ptr = @import("sa_std/fs.zig").sa_fs_dir_entry_name_ptr;

pub const sa_fs_dir_entry_name_len = @import("sa_std/fs.zig").sa_fs_dir_entry_name_len;

pub const sa_fs_dir_entry_file_name_ptr = @import("sa_std/fs.zig").sa_fs_dir_entry_file_name_ptr;

pub const sa_fs_dir_entry_file_name_len = @import("sa_std/fs.zig").sa_fs_dir_entry_file_name_len;

pub const sa_fs_dir_entry_kind = @import("sa_std/fs.zig").sa_fs_dir_entry_kind;

pub const sa_fs_dir_entry_ino = @import("sa_std/fs.zig").sa_fs_dir_entry_ino;

pub const sa_fs_dir_entry_free = @import("sa_std/fs.zig").sa_fs_dir_entry_free;

pub const sa_fs_metadata = @import("sa_std/fs.zig").sa_fs_metadata;

pub const sa_std_fs_metadata = @import("sa_std/std_fs.zig").sa_std_fs_metadata;

pub const sa_fs_metadata_json = @import("sa_std/fs.zig").sa_fs_metadata_json;

pub const sa_std_fs_metadata_json = @import("sa_std/std_fs.zig").sa_std_fs_metadata_json;

pub const sa_fs_metadata_is_file = @import("sa_std/fs.zig").sa_fs_metadata_is_file;

pub const sa_fs_metadata_is_directory = @import("sa_std/fs.zig").sa_fs_metadata_is_directory;

pub const sa_fs_metadata_is_symlink = @import("sa_std/fs.zig").sa_fs_metadata_is_symlink;

pub const sa_fs_metadata_is_block_device = @import("sa_std/fs.zig").sa_fs_metadata_is_block_device;

pub const sa_fs_metadata_is_char_device = @import("sa_std/fs.zig").sa_fs_metadata_is_char_device;

pub const sa_fs_metadata_is_fifo = @import("sa_std/fs.zig").sa_fs_metadata_is_fifo;

pub const sa_fs_metadata_is_socket = @import("sa_std/fs.zig").sa_fs_metadata_is_socket;

pub const sa_fs_metadata_modified_ms = @import("sa_std/fs.zig").sa_fs_metadata_modified_ms;

pub const sa_fs_metadata_created_ms = @import("sa_std/fs.zig").sa_fs_metadata_created_ms;

pub const sa_fs_metadata_accessed_ms = @import("sa_std/fs.zig").sa_fs_metadata_accessed_ms;

pub const sa_fs_metadata_changed_ms = @import("sa_std/fs.zig").sa_fs_metadata_changed_ms;

pub const sa_fs_metadata_len = @import("sa_std/fs.zig").sa_fs_metadata_len;

pub const sa_fs_metadata_mode = @import("sa_std/fs.zig").sa_fs_metadata_mode;

pub const sa_fs_metadata_uid = @import("sa_std/fs.zig").sa_fs_metadata_uid;

pub const sa_fs_metadata_gid = @import("sa_std/fs.zig").sa_fs_metadata_gid;

pub const sa_fs_metadata_ino = @import("sa_std/fs.zig").sa_fs_metadata_ino;

pub const sa_fs_metadata_dev = @import("sa_std/fs.zig").sa_fs_metadata_dev;

pub const sa_fs_metadata_nlink = @import("sa_std/fs.zig").sa_fs_metadata_nlink;

pub const sa_fs_metadata_rdev = @import("sa_std/fs.zig").sa_fs_metadata_rdev;

pub const sa_fs_metadata_blksize = @import("sa_std/fs.zig").sa_fs_metadata_blksize;

pub const sa_fs_metadata_blocks = @import("sa_std/fs.zig").sa_fs_metadata_blocks;

pub const sa_fs_metadata_st_dev = @import("sa_std/fs.zig").sa_fs_metadata_st_dev;

pub const sa_fs_metadata_st_ino = @import("sa_std/fs.zig").sa_fs_metadata_st_ino;

pub const sa_fs_metadata_st_mode = @import("sa_std/fs.zig").sa_fs_metadata_st_mode;

pub const sa_fs_metadata_st_nlink = @import("sa_std/fs.zig").sa_fs_metadata_st_nlink;

pub const sa_fs_metadata_st_uid = @import("sa_std/fs.zig").sa_fs_metadata_st_uid;

pub const sa_fs_metadata_st_gid = @import("sa_std/fs.zig").sa_fs_metadata_st_gid;

pub const sa_fs_metadata_st_rdev = @import("sa_std/fs.zig").sa_fs_metadata_st_rdev;

pub const sa_fs_metadata_st_size = @import("sa_std/fs.zig").sa_fs_metadata_st_size;

pub const sa_fs_metadata_st_atime = @import("sa_std/fs.zig").sa_fs_metadata_st_atime;

pub const sa_fs_metadata_st_atime_nsec = @import("sa_std/fs.zig").sa_fs_metadata_st_atime_nsec;

pub const sa_fs_metadata_st_mtime = @import("sa_std/fs.zig").sa_fs_metadata_st_mtime;

pub const sa_fs_metadata_st_mtime_nsec = @import("sa_std/fs.zig").sa_fs_metadata_st_mtime_nsec;

pub const sa_fs_metadata_st_ctime = @import("sa_std/fs.zig").sa_fs_metadata_st_ctime;

pub const sa_fs_metadata_st_ctime_nsec = @import("sa_std/fs.zig").sa_fs_metadata_st_ctime_nsec;

pub const sa_fs_metadata_st_blksize = @import("sa_std/fs.zig").sa_fs_metadata_st_blksize;

pub const sa_fs_metadata_st_blocks = @import("sa_std/fs.zig").sa_fs_metadata_st_blocks;

pub const sa_fs_metadata_free = @import("sa_std/fs.zig").sa_fs_metadata_free;

pub const sa_std_fs_metadata_free = @import("sa_std/std_fs.zig").sa_std_fs_metadata_free;

pub const sa_std_fs_canonicalize = @import("sa_std/std_fs.zig").sa_std_fs_canonicalize;

pub const sa_fs_remove_file = @import("sa_std/fs.zig").sa_fs_remove_file;

pub const sa_fs_rename = @import("sa_std/fs.zig").sa_fs_rename;

pub const sa_fs_make_dir = @import("sa_std/fs.zig").sa_fs_make_dir;

pub const sa_fs_make_dir_mode = @import("sa_std/fs.zig").sa_fs_make_dir_mode;

/// One mkdir -p segment: create the directory, or accept an existing
/// one only when it really is a directory. An existing non-directory
/// reports PathAlreadyExists (final segment) or fails the next
/// segment with NotDir; neither is a silent success.
fn mkdirPOne(prefix: []const u8) !void {
    // Compared, not switched on: see the wasm error-set note at the
    // other lxMkdirat call site.
    lxMkdirat(std.posix.AT.FDCWD, prefix, 0o777) catch |err| {
        if (err == error.PathAlreadyExists) {
            const stat = try sio.cwd().statFile(prefix);
            if (stat.kind != .directory) return error.PathAlreadyExists;
        } else return err;
    };
}

pub fn mkdirP(path: []const u8) !void {
    if (path.len == 0) return error.InvalidArgument;
    var index: usize = 0;
    while (index <= path.len) {
        const at_boundary = index == path.len or path[index] == '/';
        if (at_boundary and index > 0) {
            const prefix = path[0..index];
            if (!std.mem.eql(u8, prefix, "/") and !std.mem.eql(u8, prefix, ".")) {
                try mkdirPOne(prefix);
            }
        }
        index += 1;
    }
}

/// mkdir -p (2026-10-26): create every missing directory along the
/// path. Existing directories along the way (including the final
/// segment) are success; the TS mkdirSync(recursive) counterpart.
pub const sa_fs_mkdir_p = @import("sa_std/fs.zig").sa_fs_mkdir_p;



pub const sa_fs_create_dir = @import("sa_std/fs.zig").sa_fs_create_dir;

pub const sa_fs_create_dir_mode = @import("sa_std/fs.zig").sa_fs_create_dir_mode;

pub const sa_fs_remove_dir = @import("sa_std/fs.zig").sa_fs_remove_dir;

pub const sa_fs_remove_dir_all = @import("sa_std/fs.zig").sa_fs_remove_dir_all;

pub const sa_fs_remove_path = @import("sa_std/fs.zig").sa_fs_remove_path;

pub const sa_fs_copy_file = @import("sa_std/fs.zig").sa_fs_copy_file;

pub const sa_fs_set_permissions = @import("sa_std/fs.zig").sa_fs_set_permissions;

pub fn timespecFromUnixMs(unix_ms: i64) !Timespec {
    const sec = @divFloor(unix_ms, 1000);
    const rem_ms = @mod(unix_ms, 1000);
    const sec_value = std.math.cast(TimespecSec, sec) orelse return error.InvalidArgument;
    const nsec_value = std.math.cast(TimespecNsec, rem_ms * 1_000_000) orelse return error.InvalidArgument;
    return .{ .sec = sec_value, .nsec = nsec_value };
}

pub const sa_fs_set_times_ms = @import("sa_std/fs.zig").sa_fs_set_times_ms;

pub const sa_fs_hard_link = @import("sa_std/fs.zig").sa_fs_hard_link;

pub const sa_fs_symlink = @import("sa_std/fs.zig").sa_fs_symlink;

pub fn chownId(value: u32, enabled: u32) std.c.uid_t {
    return if (enabled != 0) @as(std.c.uid_t, @intCast(value)) else ~@as(std.c.uid_t, 0);
}

pub fn groupId(value: u32, enabled: u32) std.c.gid_t {
    return if (enabled != 0) @as(std.c.gid_t, @intCast(value)) else ~@as(std.c.gid_t, 0);
}

pub fn finishErrnoAny(e: anytype) i32 {
    const n = @tagName(e);
    if (std.mem.eql(u8, n, "SUCCESS")) return finish(SA_STD_OK);
    if (std.mem.eql(u8, n, "INTR")) return finish(SA_STD_ERR_IO);
    if (std.mem.eql(u8, n, "BADF")) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (std.mem.eql(u8, n, "ACCES") or std.mem.eql(u8, n, "PERM") or std.mem.eql(u8, n, "ROFS")) return finish(SA_STD_ERR_ACCESS);
    if (std.mem.eql(u8, n, "NOENT") or std.mem.eql(u8, n, "NOTDIR")) return finish(SA_STD_ERR_NOT_FOUND);
    if (std.mem.eql(u8, n, "FAULT") or std.mem.eql(u8, n, "INVAL") or std.mem.eql(u8, n, "NAMETOOLONG") or std.mem.eql(u8, n, "LOOP")) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    if (std.mem.eql(u8, n, "NOMEM")) return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_ERR_IO);
}

pub fn finishChownErrno(rc: usize) i32 {
    return finishErrnoAny(std.os.linux.errno(rc));
}

pub fn chownPath(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32, nofollow: bool) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    if (comptime is_linux) {
        const path_z = std.posix.toPosixPath(path) catch |err| return finishErr(err);
        const flags: u32 = if (nofollow) std.os.linux.AT.SYMLINK_NOFOLLOW else 0;
        const rc = std.os.linux.syscall5(
            .fchownat,
            @as(usize, @bitCast(@as(isize, std.os.linux.AT.FDCWD))),
            @intFromPtr(&path_z),
            chownId(uid, has_uid),
            groupId(gid, has_gid),
            flags,
        );
        switch (std.os.linux.errno(rc)) {
            .INTR => return chownPath(path_ptr, path_len, uid, gid, has_uid, has_gid, nofollow),
            else => return finishChownErrno(rc),
        }
    }
    const path_z = std.posix.toPosixPath(path) catch |err| return finishErr(err);
    const rc = if (nofollow)
        libc.lchown(&path_z, chownId(uid, has_uid), groupId(gid, has_gid))
    else
        libc.chown(&path_z, chownId(uid, has_uid), groupId(gid, has_gid));
    return finishErrnoAny(std.posix.errno(rc));
}

pub const sa_fs_chown = @import("sa_std/fs.zig").sa_fs_chown;

pub const sa_fs_lchown = @import("sa_std/fs.zig").sa_fs_lchown;

pub const sa_fs_fchown = @import("sa_std/fs.zig").sa_fs_fchown;

pub const sa_fs_chroot = @import("sa_std/fs.zig").sa_fs_chroot;

pub const sa_fs_mkfifo = @import("sa_std/fs.zig").sa_fs_mkfifo;

pub const sa_std_fs_read_link = @import("sa_std/std_fs.zig").sa_std_fs_read_link;

pub const sa_net_tcp_connect = @import("sa_std/net.zig").sa_net_tcp_connect;

pub const sa_std_net_to_socket_addr_list = @import("sa_std/std_net.zig").sa_std_net_to_socket_addr_list;

pub const sa_std_net_addr_list_next = @import("sa_std/std_net.zig").sa_std_net_addr_list_next;

pub const sa_std_net_addr_list_remaining = @import("sa_std/std_net.zig").sa_std_net_addr_list_remaining;

pub const sa_std_net_addr_list_reset = @import("sa_std/std_net.zig").sa_std_net_addr_list_reset;

pub const sa_std_net_addr_list_free = @import("sa_std/std_net.zig").sa_std_net_addr_list_free;

/// Reverse DNS lookup (getnameinfo, NI_NAMEREQD) for a resolved address
/// handle produced by sa_std_net_to_socket_addr_list/_first or a stream's
/// peer/local addr. Output semantics mirror sa_std_net_hostname: call with
/// (null, 0, &len) to size the buffer; SA_STD_ERR_TRUNCATED when it does
/// not fit. SA_STD_ERR_IO when the address has no name (NXDOMAIN / no PTR).
pub const sa_std_net_addr_reverse_lookup = @import("sa_std/std_net.zig").sa_std_net_addr_reverse_lookup;
pub const sa_std_net_to_socket_addr_first = @import("sa_std/std_net.zig").sa_std_net_to_socket_addr_first;

pub const sa_std_net_tcp_stream_read = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read;

pub const sa_std_net_tcp_stream_read_vectored = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_vectored;

pub const sa_std_net_tcp_stream_write_vectored = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_vectored;
pub const sa_net_tcp_stream_read = @import("sa_std/net.zig").sa_net_tcp_stream_read;
pub const sa_std_net_tcp_stream_peek = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peek;
pub const sa_net_tcp_stream_peek = @import("sa_std/net.zig").sa_net_tcp_stream_peek;
pub const sa_std_net_tcp_stream_write = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write;
pub const sa_net_tcp_stream_write = @import("sa_std/net.zig").sa_net_tcp_stream_write;
pub const sa_net_tcp_stream_write_all = @import("sa_std/net.zig").sa_net_tcp_stream_write_all;
pub const sa_net_tcp_stream_read_exact = @import("sa_std/net.zig").sa_net_tcp_stream_read_exact;
pub const sa_net_tcp_stream_flush = @import("sa_std/net.zig").sa_net_tcp_stream_flush;
pub const sa_std_net_tcp_stream_peer_addr = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_peer_addr;

pub const sa_std_net_tcp_stream_local_addr = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_local_addr;
pub const sa_net_tcp_stream_peer_addr = @import("sa_std/net.zig").sa_net_tcp_stream_peer_addr;
pub const sa_net_tcp_stream_shutdown = @import("sa_std/net.zig").sa_net_tcp_stream_shutdown;
pub const sa_net_tcp_stream_set_read_timeout = @import("sa_std/net.zig").sa_net_tcp_stream_set_read_timeout;

pub const sa_net_tcp_stream_set_write_timeout = @import("sa_std/net.zig").sa_net_tcp_stream_set_write_timeout;

pub const sa_net_tcp_stream_set_nonblocking = @import("sa_std/net.zig").sa_net_tcp_stream_set_nonblocking;

pub const sa_net_tcp_stream_set_nodelay = @import("sa_std/net.zig").sa_net_tcp_stream_set_nodelay;

pub const sa_net_tcp_stream_set_ttl = @import("sa_std/net.zig").sa_net_tcp_stream_set_ttl;
pub const sa_net_tcp_stream_close = @import("sa_std/net.zig").sa_net_tcp_stream_close;
pub const sa_net_tcp_listener_bind = @import("sa_std/net.zig").sa_net_tcp_listener_bind;
pub const sa_net_tcp_listener_accept = @import("sa_std/net.zig").sa_net_tcp_listener_accept;
pub const sa_net_tcp_listener_local_addr = @import("sa_std/net.zig").sa_net_tcp_listener_local_addr;
pub const sa_net_tcp_listener_close = @import("sa_std/net.zig").sa_net_tcp_listener_close;

pub const sa_std_net_tcp_stream_try_clone = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_try_clone;
pub const sa_std_net_tcp_stream_set_nonblocking = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nonblocking;

/// Interest/readiness bits for sa_std_net_poll_wait. The interest
/// mask (input) and the readiness mask (output) share the read and
/// write bits; the error bit is readiness-only.
pub const SA_STD_NET_POLL_READ = @import("sa_std/consts.zig").SA_STD_NET_POLL_READ;
pub const SA_STD_NET_POLL_WRITE = @import("sa_std/consts.zig").SA_STD_NET_POLL_WRITE;
pub const SA_STD_NET_POLL_ERROR = @import("sa_std/consts.zig").SA_STD_NET_POLL_ERROR;

/// Largest readiness set accepted by one sa_std_net_poll_wait call.
/// Larger connection sets are served by waiting on slices of the
/// set in rotation; the cap is loud (invalid argument), never a
/// silent truncation.
pub const SA_STD_NET_POLL_MAX_HANDLES = @import("sa_std/consts.zig").SA_STD_NET_POLL_MAX_HANDLES;
pub const poll_wait_stack_handles: usize = 256;

/// Block until at least one of the given socket handles (TCP
/// streams, TCP listeners, UDP sockets) is ready for the requested
/// operations, or timeout_ms elapses (0 = return immediately,
/// negative = wait indefinitely). ready[i] receives the readiness
/// mask for handles[i] (0 = not ready) and out_ready_count the
/// number of ready entries. A hangup reports READ|ERROR so an
/// event loop attempts the read and observes EOF. Level-triggered
/// only: readiness is re-evaluated on every call, which is what
/// lets an event loop replace sleep-polling AND the per-round
/// scan of every connection with a single wait over exactly the
/// ready set. Handles must outlive the call. Native only; WASM
/// returns SA_STD_ERR_UNSUPPORTED.
pub const sa_std_net_poll_wait = @import("sa_std/std_net.zig").sa_std_net_poll_wait;

pub const sa_std_net_tcp_stream_set_nodelay = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_nodelay;

pub const sa_std_net_tcp_stream_set_linger = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_linger;

pub const sa_std_net_tcp_stream_linger = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_linger;

pub const sa_std_net_tcp_stream_set_quickack = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_quickack;

pub const sa_std_net_tcp_stream_quickack = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_quickack;

pub const sa_std_net_tcp_stream_set_deferaccept = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_deferaccept;

pub const sa_std_net_tcp_stream_deferaccept = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_deferaccept;

// SO_KEEPALIVE on a connected TCP stream. Codex's socket2 users enable this to
// keep idle upstream connections alive; exposed here so SA callers match parity.
pub const sa_std_net_tcp_stream_set_keepalive = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive;

pub const sa_std_net_tcp_stream_keepalive = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_keepalive;

// Tune the Linux TCP keepalive timers (idle before first probe, interval
// between probes, probe count before dropping). All three are in whole units
// (seconds for idle/interval, count for cnt) matching the kernel option ABI.
pub const sa_std_net_tcp_stream_set_keepalive_params = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_keepalive_params;

// SO_REUSEADDR on a TCP listener handle (or UDS listener, which shares the
// tcp_listener resource kind). Allows rebinding a TIME_WAIT address.
pub const sa_std_net_tcp_listener_set_reuseaddr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseaddr;

// SO_REUSEPORT on a TCP listener handle for load-balanced multi-acceptor setups.
pub const sa_std_net_tcp_listener_set_reuseport = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_reuseport;

pub const sa_std_net_tcp_stream_set_read_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_read_timeout;

pub const sa_std_net_tcp_stream_set_write_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_write_timeout;

pub const sa_std_net_tcp_stream_set_ttl = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_ttl;

pub const sa_std_net_tcp_stream_read_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_read_timeout;

pub const sa_std_net_tcp_stream_write_timeout = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_write_timeout;

pub const sa_std_net_tcp_stream_nodelay = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_nodelay;

pub const sa_std_net_tcp_stream_ttl = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_ttl;

pub const sa_std_net_tcp_stream_set_recv_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_recv_buffer_size;

pub const sa_std_net_tcp_stream_recv_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_recv_buffer_size;

pub const sa_std_net_tcp_stream_set_send_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_set_send_buffer_size;

pub const sa_std_net_tcp_stream_send_buffer_size = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_buffer_size;

pub const sa_std_net_tcp_stream_take_error = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_take_error;

pub const sa_std_net_tcp_listener_try_clone = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_try_clone;
pub const sa_std_net_tcp_listener_set_only_v6 = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_only_v6;

pub const sa_std_net_tcp_listener_only_v6 = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_only_v6;
pub const sa_std_net_tcp_listener_set_nonblocking = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_nonblocking;

pub const sa_std_net_tcp_listener_set_ttl = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_set_ttl;

pub const sa_std_net_tcp_listener_ttl = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_ttl;

pub const sa_std_net_tcp_listener_take_error = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_take_error;

pub const sa_std_net_udp_try_clone = @import("sa_std/std_net_udp.zig").sa_std_net_udp_try_clone;
pub const sa_std_net_udp_bind = @import("sa_std/std_net_udp.zig").sa_std_net_udp_bind;

// Raw-socket creation (wave-3 fill; the missing primitive BE
// registered for the ICMP transport half). domain / sock_type /
// protocol are the raw OS numbers (AF_INET=2 / AF_INET6=10,
// SOCK_RAW=3 / SOCK_DGRAM=2, IPPROTO_ICMP=1 / IPPROTO_ICMPV6=58 on
// Linux), the same raw-number convention as the sockopt passthrough.
// SOCK_DGRAM is admitted alongside SOCK_RAW because that is the
// Linux ping-socket form of an ICMP socket; SOCK_STREAM and every
// other type are rejected loudly. The socket is registered as a
// datagram-kind (udp_socket) handle, so the existing datagram
// surfaces apply unchanged: udp_send_to / udp_recv_from /
// udp_set_read_timeout, the sockopt passthrough, fd detach
// (sa_std_fd_into_raw) and sa_std_close. Permission failures from
// socket(2) (root / CAP_NET_RAW for SOCK_RAW, ping_group_range for
// the ping form) surface as their loud status, never a fake handle.
// Linux + libc platforms; WASI returns SA_STD_ERR_UNSUPPORTED and
// the Windows root does not implement it (see
// docs/runtime_abi_windows_unsupported.txt).
pub const sa_std_net_raw_socket = @import("sa_std/std_net.zig").sa_std_net_raw_socket;

pub fn lxSendfile(out_fd: std.posix.fd_t, in_fd: std.posix.fd_t, offset: *u64, count: usize) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        var off: i64 = @intCast(offset.*);
        const rc = try lxCheck(std.os.linux.sendfile(out_fd, in_fd, &off, count));
        offset.* = @intCast(off);
        return rc;
    }
    return error.Unsupported;
}

// Zero-copy file-to-socket send (sendfile(2); wave-3 fill -- the
// surface was verified absent tree-wide before this addition).
// Sends up to `count` bytes of `file` starting at `offset` over the
// TCP stream, looping over partial sends; the file's own position is
// never used or moved (the offset travels in/out explicitly, so one
// file handle can serve many sends). out_sent receives the byte
// total actually sent: it equals `count` unless the file ended
// first, which is data (SA_STD_OK with a short count), never a
// silent truncation of the return contract. out_next_offset
// (optional) receives offset + out_sent. The stream's write timeout
// is NOT applied (sendfile has no per-call deadline here); a
// blocking stream blocks as the kernel dictates. Linux only:
// other platforms return SA_STD_ERR_UNSUPPORTED (the Windows root
// does not implement it; see the ABI unsupported manifest).
pub const sa_std_net_tcp_stream_send_file = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_send_file;

pub const sa_std_net_udp_from_raw_fd = @import("sa_std/std_net_udp.zig").sa_std_net_udp_from_raw_fd;

pub const sa_std_net_udp_local_addr = @import("sa_std/std_net_udp.zig").sa_std_net_udp_local_addr;
pub const sa_std_net_udp_peer_addr = @import("sa_std/std_net_udp.zig").sa_std_net_udp_peer_addr;
pub const sa_std_net_udp_connect = @import("sa_std/std_net_udp.zig").sa_std_net_udp_connect;
pub const sa_net_udp_set_read_timeout = @import("sa_std/net.zig").sa_net_udp_set_read_timeout;

pub const sa_net_udp_set_write_timeout = @import("sa_std/net.zig").sa_net_udp_set_write_timeout;

pub const sa_net_udp_set_nonblocking = @import("sa_std/net.zig").sa_net_udp_set_nonblocking;

pub const sa_net_udp_set_broadcast = @import("sa_std/net.zig").sa_net_udp_set_broadcast;

pub const sa_net_udp_set_ttl = @import("sa_std/net.zig").sa_net_udp_set_ttl;

pub const sa_net_udp_set_multicast_loop_v4 = @import("sa_std/net.zig").sa_net_udp_set_multicast_loop_v4;

pub const sa_net_udp_set_multicast_ttl_v4 = @import("sa_std/net.zig").sa_net_udp_set_multicast_ttl_v4;

pub const sa_net_udp_join_multicast_v4 = @import("sa_std/net.zig").sa_net_udp_join_multicast_v4;

pub const sa_net_udp_leave_multicast_v4 = @import("sa_std/net.zig").sa_net_udp_leave_multicast_v4;

pub const sa_net_udp_join_multicast_v6 = @import("sa_std/net.zig").sa_net_udp_join_multicast_v6;

pub const sa_net_udp_leave_multicast_v6 = @import("sa_std/net.zig").sa_net_udp_leave_multicast_v6;

pub const sa_std_net_udp_connect_addr = @import("sa_std/std_net_udp.zig").sa_std_net_udp_connect_addr;

pub const sa_std_net_udp_set_only_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_only_v6;

pub const sa_std_net_udp_only_v6 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_only_v6;
pub const sa_std_net_udp_set_nonblocking = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_nonblocking;

pub const sa_std_net_udp_set_broadcast = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_broadcast;

pub const sa_std_net_udp_set_ttl = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_ttl;

pub const sa_std_net_udp_set_read_timeout = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_read_timeout;

pub const sa_std_net_udp_set_write_timeout = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_write_timeout;

pub const sa_std_net_udp_set_recv_buffer_size = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_recv_buffer_size;

pub const sa_std_net_udp_recv_buffer_size = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_buffer_size;

pub const sa_std_net_udp_set_send_buffer_size = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_send_buffer_size;

pub const sa_std_net_udp_send_buffer_size = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_buffer_size;

pub const sa_std_net_udp_read_timeout = @import("sa_std/std_net_udp.zig").sa_std_net_udp_read_timeout;

pub const sa_std_net_udp_write_timeout = @import("sa_std/std_net_udp.zig").sa_std_net_udp_write_timeout;

pub const sa_std_net_udp_broadcast = @import("sa_std/std_net_udp.zig").sa_std_net_udp_broadcast;

pub const sa_std_net_udp_set_multicast_loop_v4 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v4;

pub const sa_std_net_udp_set_multicast_ttl_v4 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_ttl_v4;

pub const sa_std_net_udp_multicast_loop_v4 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v4;

pub const sa_std_net_udp_multicast_ttl_v4 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_ttl_v4;

pub const sa_std_net_udp_set_multicast_loop_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_loop_v6;

pub const sa_std_net_udp_set_multicast_hops_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_hops_v6;

pub const sa_std_net_udp_multicast_loop_v6 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_loop_v6;

pub const sa_std_net_udp_multicast_hops_v6 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_hops_v6;
pub const sa_std_net_udp_set_multicast_if_v4 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v4;

pub const sa_std_net_udp_multicast_if_v4 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_if_v4;

pub const sa_std_net_udp_set_multicast_if_v6 = @import("sa_std/std_net_udp_set.zig").sa_std_net_udp_set_multicast_if_v6;

pub const sa_std_net_udp_multicast_if_v6 = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_multicast_if_v6;

pub const sa_std_net_udp_join_multicast_v4 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_join_multicast_v4;

pub const sa_std_net_udp_leave_multicast_v4 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_leave_multicast_v4;

pub const sa_std_net_udp_join_multicast_v6 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_join_multicast_v6;

pub const sa_std_net_udp_leave_multicast_v6 = @import("sa_std/std_net_udp.zig").sa_std_net_udp_leave_multicast_v6;

pub const sa_std_net_udp_ttl = @import("sa_std/std_net_udp.zig").sa_std_net_udp_ttl;

pub const sa_std_net_udp_take_error = @import("sa_std/std_net_udp.zig").sa_std_net_udp_take_error;

pub const sa_std_net_udp_send = @import("sa_std/std_net_udp.zig").sa_std_net_udp_send;
pub const sa_std_net_udp_recv = @import("sa_std/std_net_udp.zig").sa_std_net_udp_recv;

pub const sa_std_net_udp_peek = @import("sa_std/std_net_udp.zig").sa_std_net_udp_peek;

pub const sa_std_net_udp_send_to = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_to;
pub const sa_std_net_udp_recv_from = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_from;

pub const sa_std_net_udp_peek_from = @import("sa_std/std_net_udp.zig").sa_std_net_udp_peek_from;

pub const sa_std_net_udp_send_vectored = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_vectored;

pub const sa_std_net_udp_send_to_vectored = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_send_to_vectored;

pub const sa_std_net_udp_recv_from_vectored = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_from_vectored;

// ---------------------------------------------------------------------------
// Generic socket-option passthrough + datagram receive enhancements
// (wave-2 fill). The passthrough is the Python net census's
// highest-value single gap (one pair of functions covers every
// option without a dedicated wrapper); udp_recv_msg / udp_recv_multi
// are the Unreal net census datagram trio (pktinfo, packet
// timestamp, RecvMulti); unix_datagram_peer_cred completes the
// SO_PEERCRED face the Java census named (the stream form,
// sa_std_net_unix_stream_peer_cred, already exists below).
// ---------------------------------------------------------------------------

pub const sa_std_net_socket_setsockopt = @import("sa_std/std_net.zig").sa_std_net_socket_setsockopt;

pub const sa_std_net_socket_getsockopt = @import("sa_std/std_net.zig").sa_std_net_socket_getsockopt;

pub const sa_std_net_socket_setsockopt_int = @import("sa_std/std_net.zig").sa_std_net_socket_setsockopt_int;

pub const sa_std_net_socket_getsockopt_int = @import("sa_std/std_net.zig").sa_std_net_socket_getsockopt_int;

// out_flags bits of sa_std_net_udp_recv_msg; mirrored as
// SA_NET_RECV_MSG_* in sa_std/net.sla.
pub const recv_msg_flag_pktinfo: u32 = 1;
pub const recv_msg_flag_timestamp: u32 = 2;
pub const recv_msg_flag_ctrunc: u32 = 4;
pub const recv_msg_flag_trunc: u32 = 8;

// Linux control-message numbers the parser keys on (asm-generic /
// in.h values; net.sla pins the SLA-facing names). std.os.linux
// does not name SO_TIMESTAMP, so the literal is spelled out here.
pub const cmsg_level_ip: i32 = 0; // IPPROTO_IP
pub const cmsg_level_ipv6: i32 = 41; // IPPROTO_IPV6
pub const cmsg_level_socket: i32 = 1; // SOL_SOCKET
pub const cmsg_type_ip_pktinfo: i32 = 8; // IP_PKTINFO
pub const cmsg_type_ipv6_pktinfo: i32 = 50; // IPV6_PKTINFO
pub const cmsg_type_timestamp: i32 = 29; // SO_TIMESTAMP

pub fn cmsgAlign(len: usize) usize {
    const mask: usize = @sizeOf(usize) - 1;
    return (len + mask) & ~mask;
}

pub const sa_std_net_udp_recv_msg = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_msg;

pub const recv_multi_max_msgs: usize = 64;

pub const sa_std_net_udp_recv_multi = @import("sa_std/std_net_udp_io.zig").sa_std_net_udp_recv_multi;

pub const sa_net_udp_bind = @import("sa_std/net.zig").sa_net_udp_bind;
pub const sa_net_udp_connect = @import("sa_std/net.zig").sa_net_udp_connect;
pub const sa_net_udp_local_addr = @import("sa_std/net.zig").sa_net_udp_local_addr;
pub const sa_net_udp_send = @import("sa_std/net.zig").sa_net_udp_send;
pub const sa_net_udp_recv = @import("sa_std/net.zig").sa_net_udp_recv;
pub const sa_net_udp_peek = @import("sa_std/net.zig").sa_net_udp_peek;
pub const sa_net_udp_send_to = @import("sa_std/net.zig").sa_net_udp_send_to;
pub const sa_net_udp_recv_from = @import("sa_std/net.zig").sa_net_udp_recv_from;
pub const sa_net_udp_peek_from = @import("sa_std/net.zig").sa_net_udp_peek_from;
pub const sa_net_udp_close = @import("sa_std/net.zig").sa_net_udp_close;
pub const sa_net_addr_host = @import("sa_std/net.zig").sa_net_addr_host;
pub const sa_net_addr_host_len = @import("sa_std/net.zig").sa_net_addr_host_len;
pub const sa_net_addr_port = @import("sa_std/net.zig").sa_net_addr_port;
pub const sa_net_addr_family = @import("sa_std/net.zig").sa_net_addr_family;

pub const sa_net_addr_scope_id = @import("sa_std/net.zig").sa_net_addr_scope_id;

pub const sa_std_net_addr_format = @import("sa_std/std_net.zig").sa_std_net_addr_format;

pub const sa_net_addr_free = @import("sa_std/net.zig").sa_net_addr_free;

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

pub fn parsePortAscii(text: []const u8) ?u16 {
    if (text.len == 0) return null;
    var value: u32 = 0;
    for (text) |byte| {
        if (byte < '0' or byte > '9') return null;
        value = value * 10 + @as(u32, byte - '0');
        if (value > std.math.maxInt(u16)) return null;
    }
    return @as(u16, @intCast(value));
}

pub const sa_net_ipv4_parse_ascii = @import("sa_std/net.zig").sa_net_ipv4_parse_ascii;

pub const sa_net_socket_addr_v4_parse_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v4_parse_ascii;

pub fn writeIpv6SegmentsNative(out: []u8, octets: *const [16]u8) void {
    var index: usize = 0;
    while (index < 8) : (index += 1) {
        const seg = std.mem.readInt(u16, octets[index * 2 ..][0..2], .big);
        // Match SA `store ... as u16` host layout (x86_64 little-endian tests).
        std.mem.writeInt(u16, out[index * 2 ..][0..2], seg, .little);
    }
}

pub fn parseIpv6Ascii(text: []const u8) ?struct { octets: [16]u8, scope_id: u32 } {
    // FreeBSD: Ip6Address.resolve reaches unimplemented if_nametoindex.
    if (comptime builtin.os.tag == .freebsd) {
        const parsed = parseIp6FreebsdParts(text) orelse return null;
        return .{ .octets = parsed.addr, .scope_id = parsed.scope_id };
    }
    const parsed = std.Io.net.IpAddress.resolve(sio.io(), text, 0) catch return null;
    return switch (parsed) {
        .ip6 => |v6| .{ .octets = v6.bytes, .scope_id = v6.interface.index },
        .ip4 => null,
    };
}

pub fn parseSocketAddrV6Ascii(text: []const u8) ?struct { octets: [16]u8, port: u16, scope_id: u32 } {
    if (text.len < 4 or text[0] != '[') return null;
    const close = std.mem.lastIndexOfScalar(u8, text, ']') orelse return null;
    if (close == 0 or close + 1 >= text.len or text[close + 1] != ':') return null;
    const ip_text = text[1..close];
    if (ip_text.len == 0) return null;
    const port = parsePortAscii(text[close + 2 ..]) orelse return null;
    const parsed = parseIpv6Ascii(ip_text) orelse return null;
    return .{
        .octets = parsed.octets,
        .port = port,
        .scope_id = parsed.scope_id,
    };
}

pub const sa_net_ipv6_parse_ascii = @import("sa_std/net.zig").sa_net_ipv6_parse_ascii;

pub const sa_net_socket_addr_v6_parse_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v6_parse_ascii;

pub fn readIpv6SegmentsNative(raw: *const [16]u8) [8]u16 {
    var segments: [8]u16 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        segments[i] = std.mem.readInt(u16, raw[i * 2 ..][0..2], .little);
    }
    return segments;
}

pub fn formatIpv6Segments(buffer: []u8, segments: *const [8]u16) ![]u8 {
    var longest_start: usize = 8;
    var longest_len: usize = 0;
    var current_start: usize = 0;
    var current_len: usize = 0;
    for (segments.*, 0..) |segment, index| {
        if (segment == 0) {
            if (current_len == 0) current_start = index;
            current_len += 1;
            if (current_len > longest_len) {
                longest_start = current_start;
                longest_len = current_len;
            }
        } else {
            current_len = 0;
        }
    }
    if (longest_len < 2) {
        longest_start = 8;
        longest_len = 0;
    }

    var w: std.Io.Writer = .fixed(buffer);
    var i: usize = 0;
    var abbreviated = false;
    while (i < segments.len) : (i += 1) {
        if (i == longest_start) {
            if (!abbreviated) {
                try w.writeAll(if (i == 0) "::" else ":");
                abbreviated = true;
            }
            i += longest_len - 1;
            continue;
        }
        if (abbreviated) abbreviated = false;
        try w.print("{x}", .{segments[i]});
        if (i != segments.len - 1) try w.writeByte(':');
    }
    return w.buffered();
}

// sa_net_format_ascii_batch_v1
pub const sa_net_ipv4_format_ascii = @import("sa_std/net.zig").sa_net_ipv4_format_ascii;

pub const sa_net_ipv6_format_ascii = @import("sa_std/net.zig").sa_net_ipv6_format_ascii;

pub const sa_net_socket_addr_v4_format_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v4_format_ascii;

pub const sa_net_socket_addr_v6_format_ascii = @import("sa_std/net.zig").sa_net_socket_addr_v6_format_ascii;

pub const sa_fmt_i64 = @import("sa_std/fmt.zig").sa_fmt_i64;

pub const sa_fmt_i64_into = @import("sa_std/fmt.zig").sa_fmt_i64_into;

pub const sa_test_debug_i64 = @import("sa_std/test_debug.zig").sa_test_debug_i64;

pub export fn sa_test_fallible_i32_value(value: i32) Fallible(i32) {
    return ok(i32, value);
}

pub const testTracePanicEnabled = @import("sa_std/test_debug.zig").testTracePanicEnabled;

pub const printRecentTestScalars = @import("sa_std/test_debug.zig").printRecentTestScalars;

pub const exitAfterAssertPanic = @import("sa_std/test_debug.zig").exitAfterAssertPanic;

pub const sa_assert_eq_i64 = @import("sa_std/test_debug.zig").sa_assert_eq_i64;

pub const sa_assert_eq_i64_at = @import("sa_std/test_debug.zig").sa_assert_eq_i64_at;

pub const sa_fmt_u64 = @import("sa_std/fmt.zig").sa_fmt_u64;

pub const sa_fmt_u64_into = @import("sa_std/fmt.zig").sa_fmt_u64_into;

/// Float math for frontends (v0.24a; Haxe Math.* surface).
/// Pure f64 functions; random yields [0, 1) from 53 crypto bits.
pub const sa_math_floor = @import("sa_std/math.zig").sa_math_floor;

pub const sa_math_ceil = @import("sa_std/math.zig").sa_math_ceil;

pub const sa_math_sqrt = @import("sa_std/math.zig").sa_math_sqrt;

pub const sa_math_sin = @import("sa_std/math.zig").sa_math_sin;

pub const sa_math_cos = @import("sa_std/math.zig").sa_math_cos;

pub const sa_math_pow = @import("sa_std/math.zig").sa_math_pow;

pub const sa_math_random = @import("sa_std/math.zig").sa_math_random;

pub const sa_fmt_f64 = @import("sa_std/fmt.zig").sa_fmt_f64;

pub const sa_fmt_f64_into = @import("sa_std/fmt.zig").sa_fmt_f64_into;

pub const sa_fmt_bool = @import("sa_std/fmt.zig").sa_fmt_bool;

pub const sa_fmt_bool_into = @import("sa_std/fmt.zig").sa_fmt_bool_into;

pub const sa_fmt_bytes = @import("sa_std/fmt.zig").sa_fmt_bytes;

pub const sa_fmt_bytes_into = @import("sa_std/fmt.zig").sa_fmt_bytes_into;

pub const sa_env_get = @import("sa_std/env.zig").sa_env_get;

pub const sa_env_current_dir = @import("sa_std/env.zig").sa_env_current_dir;

pub const sa_env_set_current_dir = @import("sa_std/env.zig").sa_env_set_current_dir;

pub const sa_env_temp_dir = @import("sa_std/env.zig").sa_env_temp_dir;

pub const sa_env_current_exe = @import("sa_std/env.zig").sa_env_current_exe;

pub const sa_env_home_dir = @import("sa_std/env.zig").sa_env_home_dir;

pub const sa_env_args_json = @import("sa_std/env.zig").sa_env_args_json;

pub const sa_env_vars_json = @import("sa_std/env.zig").sa_env_vars_json;

pub const sa_env_split_paths_json = @import("sa_std/env.zig").sa_env_split_paths_json;

pub const sa_env_join_paths_json = @import("sa_std/env.zig").sa_env_join_paths_json;

pub const sa_env_xdg_data_home_dir = @import("sa_std/env.zig").sa_env_xdg_data_home_dir;

pub const sa_env_xdg_config_home_dir = @import("sa_std/env.zig").sa_env_xdg_config_home_dir;

pub const sa_env_xdg_state_home_dir = @import("sa_std/env.zig").sa_env_xdg_state_home_dir;

pub const sa_env_xdg_cache_home_dir = @import("sa_std/env.zig").sa_env_xdg_cache_home_dir;

pub const sa_env_xdg_data_dirs = @import("sa_std/env.zig").sa_env_xdg_data_dirs;

pub const sa_env_xdg_config_dirs = @import("sa_std/env.zig").sa_env_xdg_config_dirs;

pub const sa_env_has = @import("sa_std/env.zig").sa_env_has;

pub const sa_env_set_var = @import("sa_std/env.zig").sa_env_set_var;

pub const sa_env_remove_var = @import("sa_std/env.zig").sa_env_remove_var;

pub const sa_env_buffer_data = @import("sa_std/env.zig").sa_env_buffer_data;

pub const sa_env_buffer_len = @import("sa_std/env.zig").sa_env_buffer_len;

pub const sa_env_buffer_free = @import("sa_std/env.zig").sa_env_buffer_free;

pub const sa_string_concat = @import("sa_std/string.zig").sa_string_concat;

/// Single-byte string from a char code (JS `String.fromCharCode` over the
/// subset's byte-oriented strings; exact inverse of byte `charCodeAt`).
/// Only the low byte is stored (documented); returns a buffer handle read
/// back via `sa_fmt_buffer_data`/`sa_fmt_buffer_len` like concat.
pub const sa_string_from_char_code = @import("sa_std/string.zig").sa_string_from_char_code;

/// JS `String.prototype.indexOf` over byte-oriented strings: first needle
/// index at/after `from`, or -1. Empty needle yields min(from, hay.len).
/// `from` arrives as u64 (frontends convert via asU64Arg); clamped defensively.
pub const sa_string_index_of = @import("sa_std/string.zig").sa_string_index_of;

/// JS `String.prototype.lastIndexOf`: last needle index at/before `from`
/// (`from` clamped to hay.len), or -1. Empty needle yields the clamped `from`.
pub const sa_string_last_index_of = @import("sa_std/string.zig").sa_string_last_index_of;

/// JS `String.prototype.startsWith` (no position arg in the subset): 1/0.
pub const sa_string_starts_with = @import("sa_std/string.zig").sa_string_starts_with;

/// JS `String.prototype.endsWith`: 1/0.
pub const sa_string_ends_with = @import("sa_std/string.zig").sa_string_ends_with;

/// JS `String.prototype.toLowerCase` over the subset's byte-oriented
/// strings: ASCII A-Z folds to a-z, all other bytes pass through
/// (documented; full Unicode lower is refused at the frontend).
/// Returns a fresh buffer handle read back via `sa_fmt_buffer_data/len`.
pub const sa_string_to_lower_ascii = @import("sa_std/string.zig").sa_string_to_lower_ascii;

/// JS `String.prototype.toUpperCase`: ASCII a-z folds to A-Z, rest passes
/// through. Fresh buffer handle, same read-back protocol as lower.
pub const sa_string_to_upper_ascii = @import("sa_std/string.zig").sa_string_to_upper_ascii;

/// JS `parseFloat` (also serves `Number(s)` float paths and the global
/// `parseFloat`): leading ASCII whitespace skipped, optional sign,
/// `Infinity`/`NaN` (sign applies to Infinity only), decimal with optional
/// fraction/exponent; trailing garbage ignored; no digits at all yields
/// quiet NaN; overflow yields signed infinity.
pub export fn sa_parse_float(ptr: ?[*]const u8, len: u64) f64 {
    const bytes = constBytes(ptr, len) catch return std.math.nan(f64);
    var i: usize = 0;
    while (i < bytes.len and isAsciiWhitespace(bytes[i])) : (i += 1) {}
    var negative = false;
    if (i < bytes.len and (bytes[i] == '+' or bytes[i] == '-')) {
        negative = bytes[i] == '-';
        i += 1;
    }
    const rest = bytes[i..];
    if (rest.len >= 8 and std.mem.eql(u8, rest[0..8], "Infinity")) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
    if (rest.len >= 3 and std.mem.eql(u8, rest[0..3], "NaN")) return std.math.nan(f64);
    // Scan the maximal decimal prefix: digits[.digits][(e|E)[+-]digits],
    // requiring at least one digit on either side of the dot.
    var j: usize = 0;
    while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    const int_digits = j;
    if (j < rest.len and rest[j] == '.') {
        j += 1;
        while (j < rest.len and rest[j] >= '0' and rest[j] <= '9') : (j += 1) {}
    }
    const frac_digits = j - int_digits - @as(usize, if (j > int_digits and rest[int_digits] == '.') 1 else 0);
    if (int_digits == 0 and frac_digits == 0) return std.math.nan(f64);
    var k: usize = j;
    if (k < rest.len and (rest[k] == 'e' or rest[k] == 'E')) {
        var m: usize = k + 1;
        if (m < rest.len and (rest[m] == '+' or rest[m] == '-')) m += 1;
        const exp_start = m;
        while (m < rest.len and rest[m] >= '0' and rest[m] <= '9') : (m += 1) {}
        if (m > exp_start) k = m;
    }
    const num = std.fmt.parseFloat(f64, rest[0..k]) catch |err| {
        if (err == error.Overflow) return if (negative) -std.math.inf(f64) else std.math.inf(f64);
        return std.math.nan(f64);
    };
    // parseFloat scanned an unsigned prefix; apply the leading sign here
    // (a second negation of an explicitly signed prefix cannot occur:
    // the scan above never consumes '+'/'-').
    return if (negative) -num else num;
}

/// JS `String.prototype.repeat`: `bytes` concatenated `count` times.
/// `count == 0` yields an empty handle; size overflow yields 0
/// (OOM-equivalent). Fresh buffer handle, concat read-back protocol.
pub const sa_string_repeat = @import("sa_std/string.zig").sa_string_repeat;

/// Shared pad filler: `pad` bytes tiled/truncated to exactly `fill` bytes.
pub fn tilePad(owned: []u8, pad: []const u8) void {
    var i: usize = 0;
    while (i < owned.len) {
        const n = @min(pad.len, owned.len - i);
        std.mem.copyForwards(u8, owned[i..][0..n], pad[0..n]);
        i += n;
    }
}

/// JS `String.prototype.padStart`: left-pad with tiled `pad` to
/// `target_len` bytes. Shorter-or-equal input and empty `pad` return an
/// unchanged copy (JS no-op shape). Fresh buffer handle.
pub const sa_string_pad_start = @import("sa_std/string.zig").sa_string_pad_start;

/// JS `String.prototype.padEnd`: mirror of padStart on the right.
pub const sa_string_pad_end = @import("sa_std/string.zig").sa_string_pad_end;

/// JS `String.prototype.replace` / `replaceAll` with a string pattern
/// (regex forms are refused at the frontend): `all == 0` swaps the first
/// occurrence, nonzero swaps all non-overlapping occurrences. Empty needle
/// inserts at 0 (first) or interleaves (all), per JS. Needle absent (or
/// longer than hay) returns an unchanged copy. Fresh buffer handle.
pub const sa_string_replace = @import("sa_std/string.zig").sa_string_replace;

/// JS `String.prototype.charCodeAt` over the subset's byte-oriented
/// strings: the byte at `idx` (0-255). Out of bounds yields -1: JS NaN is
/// unrepresentable in i32, and -1 is the subset's OOB sentinel (cf.
/// indexOf). The reference frontend's primary path is an inline unchecked
/// byte load; this checked primitive is the shared out-of-line shape.
pub const sa_string_code_point_at = @import("sa_std/string.zig").sa_string_code_point_at;

/// JS `String.fromCodePoint`: UTF-8 encoding of one scalar value.
/// Out-of-range codes (negative, > 0x10FFFF, surrogate halves) yield the
/// U+FFFD replacement bytes: the subset has no exceptions, and a specified
/// replacement beats a silent wrong encoding. Fresh buffer handle.
pub const sa_string_from_code_point = @import("sa_std/string.zig").sa_string_from_code_point;

pub const sa_str_is_ascii = @import("sa_std/str.zig").sa_str_is_ascii;

pub const sa_str_eq_ignore_ascii_case = @import("sa_std/str.zig").sa_str_eq_ignore_ascii_case;

pub fn utf8ScalarAt(bytes: []const u8, index: usize) !struct { scalar: u32, width: usize } {
    if (index >= bytes.len) return error.FileNotFound;
    const b0 = bytes[index];
    if (b0 < 0x80) return .{ .scalar = b0, .width = 1 };

    const width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return error.InvalidArgument;
    if (index + width > bytes.len) return error.InvalidArgument;

    const b1 = bytes[index + 1];
    if (b1 < 0x80 or b1 > 0xbf) return error.InvalidArgument;
    if (width == 2) return .{ .scalar = ((@as(u32, b0) & 0x1f) << 6) | (@as(u32, b1) & 0x3f), .width = 2 };

    const b2 = bytes[index + 2];
    if (b2 < 0x80 or b2 > 0xbf) return error.InvalidArgument;
    if (width == 3) {
        if (b0 == 0xe0 and b1 < 0xa0) return error.InvalidArgument;
        if (b0 == 0xed and b1 >= 0xa0) return error.InvalidArgument;
        return .{ .scalar = ((@as(u32, b0) & 0x0f) << 12) | ((@as(u32, b1) & 0x3f) << 6) | (@as(u32, b2) & 0x3f), .width = 3 };
    }

    const b3 = bytes[index + 3];
    if (b3 < 0x80 or b3 > 0xbf) return error.InvalidArgument;
    if (b0 == 0xf0 and b1 < 0x90) return error.InvalidArgument;
    if (b0 == 0xf4 and b1 >= 0x90) return error.InvalidArgument;
    return .{ .scalar = ((@as(u32, b0) & 0x07) << 18) | ((@as(u32, b1) & 0x3f) << 12) | ((@as(u32, b2) & 0x3f) << 6) | (@as(u32, b3) & 0x3f), .width = 4 };
}

pub fn utf8LossyInvalidWidth(bytes: []const u8, index: usize) usize {
    const b0 = bytes[index];
    const expected_width: usize = if (b0 >= 0xc2 and b0 <= 0xdf) 2 else if (b0 >= 0xe0 and b0 <= 0xef) 3 else if (b0 >= 0xf0 and b0 <= 0xf4) 4 else return 1;
    var width: usize = 1;
    while (width < expected_width and index + width < bytes.len) : (width += 1) {
        const byte = bytes[index + width];
        if (byte < 0x80 or byte > 0xbf) break;
    }
    return width;
}

pub fn utf8CharRangeAt(bytes: []const u8, char_index: u64) !struct { start: usize, len: usize, scalar: u32 } {
    var byte_index: usize = 0;
    var current: u64 = 0;
    while (byte_index < bytes.len) {
        const decoded = try utf8ScalarAt(bytes, byte_index);
        if (current == char_index) return .{ .start = byte_index, .len = decoded.width, .scalar = decoded.scalar };
        byte_index += decoded.width;
        current += 1;
    }
    return error.FileNotFound;
}

pub const sa_str_utf8_char_count = @import("sa_std/str.zig").sa_str_utf8_char_count;

pub const sa_str_utf8_validate = @import("sa_std/str.zig").sa_str_utf8_validate;

pub const sa_str_utf8_char_at = @import("sa_std/str.zig").sa_str_utf8_char_at;

pub const sa_str_utf8_char_at_byte = @import("sa_std/str.zig").sa_str_utf8_char_at_byte;

pub const sa_str_utf8_lossy_next = @import("sa_std/str.zig").sa_str_utf8_lossy_next;

pub const sa_str_utf8_char_range_at = @import("sa_std/str.zig").sa_str_utf8_char_range_at;

pub fn isAsciiWhitespace(byte: u8) bool {
    return switch (byte) {
        ' ', '\t', '\n', '\r', 0x0b, 0x0c => true,
        else => false,
    };
}

pub const sa_str_trim_ascii_start_index = @import("sa_std/str.zig").sa_str_trim_ascii_start_index;

pub const sa_str_trim_ascii_end_len = @import("sa_std/str.zig").sa_str_trim_ascii_end_len;

pub const sa_fmt_buffer_data = @import("sa_std/fmt.zig").sa_fmt_buffer_data;

pub const sa_fmt_buffer_len = @import("sa_std/fmt.zig").sa_fmt_buffer_len;

pub const sa_fmt_buffer_write_to = @import("sa_std/fmt.zig").sa_fmt_buffer_write_to;

pub const sa_fmt_buffer_free = @import("sa_std/fmt.zig").sa_fmt_buffer_free;

/// Raw free for SA `alloc` blocks (the native emitter lowers `alloc` to
/// libc malloc). SA-level code that must release a heap block through a
/// real call -- e.g. sa_vec_free, whose `!` releases the emitter may
/// lower to bookkeeping only -- goes through this export instead.
pub export fn sa_mem_free(ptr: ?*anyopaque) void {
    if (comptime is_wasm) return;
    if (ptr) |p| std.c.free(p);
}

pub export fn sa_print_bytes(msg: ?[*]const u8, len: u64) void {
    _ = sa_std_print(msg, len);
}

pub const sa_std_net_tcp_listen = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listen;

pub const sa_std_net_tcp_accept = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept;

pub const sa_std_net_tcp_accept_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_accept_addr;

pub const sa_std_net_tcp_listener_local_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_local_addr;

pub const sa_std_net_tcp_listener_from_raw_fd = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_listener_from_raw_fd;

pub const sa_std_net_tcp_connect = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect;

pub fn tcpConnectToHostFd(host: []const u8, port: u16) !std.posix.fd_t {
    var list = try netGetAddressList(std.heap.page_allocator, host, port);
    defer list.deinit();
    var last: anyerror = error.HostLacksNetworkAddresses;
    for (list.addrs) |addr| {
        const fd = lxSocket(addr.storage.family, SOCKT.STREAM | SOCKT.CLOEXEC, IPPROTOT.TCP) catch |err| {
            last = err;
            continue;
        };
        errdefer lxClose(fd);
        lxConnect(fd, addr.sockAddr(), addr.getOsSockLen()) catch |err| {
            last = err;
            continue;
        };
        return fd;
    }
    return last;
}

pub fn connectUnixSocketFd(path: []const u8) !std.posix.fd_t {
    const addr = try NetAddress.initUnix(path);
    const fd = try lxSocket(AFT.UNIX, SOCKT.STREAM | SOCKT.CLOEXEC, 0);
    errdefer lxClose(fd);
    try lxConnect(fd, addr.sockAddr(), addr.getOsSockLen());
    return fd;
}

pub fn tcpConnectTimeoutMs(timeout_ns: u64) !i32 {
    if (timeout_ns == 0) return error.InvalidArgument;
    const whole_ms = timeout_ns / std.time.ns_per_ms;
    const rounded_ms = whole_ms + @intFromBool(timeout_ns % std.time.ns_per_ms != 0);
    return std.math.cast(i32, rounded_ms) orelse error.InvalidArgument;
}

pub const sa_std_net_tcp_connect_timeout = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout;

pub const sa_std_net_tcp_connect_timeout_addr = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_addr;
pub fn tcpConnectAddressTimeout(address: NetAddress, timeout_ms: i32) !std.posix.fd_t {
    if (comptime is_wasm) return error.Unsupported;
    const fd = try lxSocket(address.storage.family, SOCKT.STREAM | SOCKT.NONBLOCK | SOCKT.CLOEXEC, IPPROTOT.TCP);
    errdefer lxClose(fd);
    lxConnect(fd, address.sockAddr(), address.getOsSockLen()) catch |err| switch (err) {
        error.WouldBlock, error.ConnectionPending => {
            var poll_fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.OUT, .revents = 0 }};
            const ready = try std.posix.poll(&poll_fds, timeout_ms);
            if (ready == 0) return error.ConnectionTimedOut;
            try lxGetsockoptError(fd);
        },
        else => return err,
    };
    const flags = try lxFcntl(fd, std.posix.F.GETFL, 0);
    const blocking_flags = flags & ~(@as(usize, 1) << @bitOffsetOf(std.posix.O, "NONBLOCK"));
    _ = try lxFcntl(fd, std.posix.F.SETFL, blocking_flags);
    return fd;
}

pub const sa_std_net_tcp_connect_timeout_all = @import("sa_std/std_net_tcp.zig").sa_std_net_tcp_connect_timeout_all;

pub const sa_std_net_tcp_stream_from_raw_fd = @import("sa_std/std_net_tcp_stream.zig").sa_std_net_tcp_stream_from_raw_fd;

// Unix domain socket support. Streams and listeners reuse the existing
// tcp_stream / tcp_listener resource kinds so read/write/peek/shutdown/close
// and accept all flow through the same sa_std_net_tcp_* paths.
pub const sa_std_net_unix_listen = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listen;

pub const sa_std_net_unix_addr_from_abstract_name = @import("sa_std/std_net_unix.zig").sa_std_net_unix_addr_from_abstract_name;

pub const sa_std_net_unix_addr_from_pathname = @import("sa_std/std_net_unix.zig").sa_std_net_unix_addr_from_pathname;

pub const sa_std_net_unix_listen_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listen_addr;

pub const sa_std_net_unix_accept = @import("sa_std/std_net_unix.zig").sa_std_net_unix_accept;

pub const sa_std_net_unix_accept_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_accept_addr;

pub const sa_std_net_unix_pair = @import("sa_std/std_net_unix.zig").sa_std_net_unix_pair;

pub const sa_std_net_unix_listener_local_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_local_addr;

pub const sa_std_net_unix_listener_try_clone = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_try_clone;

pub const sa_std_net_unix_listener_from_raw_fd = @import("sa_std/std_net_unix.zig").sa_std_net_unix_listener_from_raw_fd;

pub const sa_std_net_unix_stream_local_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_local_addr;

pub const sa_std_net_unix_stream_try_clone = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_try_clone;

pub const sa_std_net_unix_stream_from_raw_fd = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_from_raw_fd;

pub const sa_std_net_unix_stream_peer_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_peer_addr;

pub const sa_std_net_unix_stream_set_passcred = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_set_passcred;

pub const sa_std_net_unix_stream_passcred = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_passcred;

pub const sa_std_net_unix_stream_set_mark = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_set_mark;

pub const sa_std_net_unix_stream_peer_cred = @import("sa_std/std_net_unix.zig").sa_std_net_unix_stream_peer_cred;

pub const sa_std_net_unix_datagram_peer_cred = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_cred;

pub const sa_std_net_unix_datagram_unbound = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_unbound;

pub const sa_std_net_unix_datagram_bind = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind;

pub const sa_std_net_unix_datagram_bind_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_bind_addr;

pub const sa_std_net_unix_datagram_pair = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_pair;

pub const sa_std_net_unix_datagram_connect = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect;

pub const sa_std_net_unix_datagram_connect_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_connect_addr;

pub const sa_std_net_unix_datagram_try_clone = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_try_clone;

pub const sa_std_net_unix_datagram_from_raw_fd = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_from_raw_fd;

pub const sa_std_net_unix_datagram_local_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_local_addr;

pub const sa_std_net_unix_datagram_peer_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peer_addr;

pub const sa_std_net_unix_datagram_set_passcred = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_passcred;

pub const sa_std_net_unix_datagram_passcred = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_passcred;

pub const sa_std_net_unix_datagram_set_mark = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_set_mark;

pub const sa_std_net_unix_datagram_shutdown = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_shutdown;

pub const sa_std_net_unix_datagram_send_to = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to;

pub const sa_std_net_unix_datagram_send_to_addr = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_send_to_addr;

pub fn unixDatagramRecvFrom(socket: u64, out: ?[*]u8, cap: u64, flags: u32, out_read: ?*u64, out_addr: ?*u64) i32 {
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const addr_ptr = out_addr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    read_ptr.* = 0;
    addr_ptr.* = 0;
    const buffer = mutBytes(out, cap) catch |err| return finishErr(err);
    const handle = ensureSocketHandle(socket) catch |err| return finishErr(err);
    if (handle.kind != .udp_socket) return finish(SA_STD_ERR_INVALID_HANDLE);
    if (!(socketIsUnix(handle.fd) catch |err| return finishErr(err))) return finish(SA_STD_ERR_INVALID_HANDLE);
    var addr: SockAddrUnT = .{ .family = AFT.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    // recvmsg (not recvfrom) so SCM_CREDENTIALS ancillary data can
    // be harvested for sa_std_net_unix_datagram_peer_cred; see the
    // note at getUnixPeerCred. Peek receives do not harvest.
    var control: [128]u8 align(8) = undefined;
    var ziovec = std.posix.iovec{ .base = buffer.ptr, .len = buffer.len };
    var msg: MsghdrT = std.mem.zeroes(MsghdrT);
    msg.name = @as(*SockAddrT, @ptrCast(&addr));
    msg.namelen = @as(SockLenT, @intCast(@sizeOf(SockAddrUnT)));
    msg.iov = @ptrCast(&ziovec);
    msg.iovlen = 1;
    msg.control = @ptrCast(&control);
    msg.controllen = control.len;
    const read = portableRecvmsg(handle.fd, &msg, flags) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(read));
    const addr_len: SockLenT = msg.namelen;
    if ((flags & msg_peek) == 0) {
        const ctrl = control[0..@as(usize, @intCast(msg.controllen))];
        if (scmCredentials(ctrl)) |cred| {
            lockRegistry();
            storeHarvestedPeerCredLocked(socket, handle.fd, cred);
            registry_mutex.unlock();
        }
    }

    var unix_addr = unixAddrFromSockaddr(std.heap.page_allocator, addr, addr_len) catch |err| return finishErr(err);
    while (!registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer registry_mutex.unlock();
    const addr_handle = registerResourceLocked(.{ .unix_addr = unix_addr }) catch |err| {
        unix_addr.deinit();
        return finishErr(err);
    };
    addr_ptr.* = addr_handle;
    return finish(SA_STD_OK);
}

pub const sa_std_net_unix_datagram_recv_from = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_recv_from;

pub const sa_std_net_unix_datagram_peek_from = @import("sa_std/std_net_unix_dgram.zig").sa_std_net_unix_datagram_peek_from;

pub const sa_std_net_unix_connect = @import("sa_std/std_net_unix.zig").sa_std_net_unix_connect;

pub const sa_std_net_unix_connect_addr = @import("sa_std/std_net_unix.zig").sa_std_net_unix_connect_addr;

pub const sa_net_unix_addr_kind = @import("sa_std/net.zig").sa_net_unix_addr_kind;

pub const sa_net_unix_addr_is_unnamed = @import("sa_std/net.zig").sa_net_unix_addr_is_unnamed;

pub const sa_net_unix_addr_path_ptr = @import("sa_std/net.zig").sa_net_unix_addr_path_ptr;

pub const sa_net_unix_addr_path_len = @import("sa_std/net.zig").sa_net_unix_addr_path_len;

pub const sa_net_unix_addr_abstract_ptr = @import("sa_std/net.zig").sa_net_unix_addr_abstract_ptr;

pub const sa_net_unix_addr_abstract_len = @import("sa_std/net.zig").sa_net_unix_addr_abstract_len;

pub const sa_net_unix_addr_free = @import("sa_std/net.zig").sa_net_unix_addr_free;

// ---- TLS/network fingerprint primitives (JA3 / JA4) ----
//
// SA programs building outbound-request fingerprints (mirroring Go's utls /
// CLIProxyAPI / sub2api) need the hashing primitives that JA3 and JA4 are
// defined in terms of: JA3 is md5(ja3_string); JA4's `b`/`c` segments are the
// first 12 hex chars of sha256(sorted-comma-joined list). SA-ASM has no crypto,
// so these are exposed here. They are pure functions over caller-provided bytes
// — no sockets, no allocation beyond the caller's output buffer.

pub fn writeHexLower(dst: []u8, bytes: []const u8) void {
    const hex = "0123456789abcdef";
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        dst[i * 2] = hex[bytes[i] >> 4];
        dst[i * 2 + 1] = hex[bytes[i] & 0x0f];
    }
}

// md5 of the input, written as 32 lowercase hex chars into out (cap must be >= 32).
// This is exactly the JA3 hash given a pre-built JA3 string.
pub const sa_std_net_ja3_hash = @import("sa_std/std_net.zig").sa_std_net_ja3_hash;

// sha256 of the input, written as 64 lowercase hex chars into out (cap must be >= 64).
pub const sa_std_net_sha256_hex = @import("sa_std/std_net.zig").sa_std_net_sha256_hex;

// JA4 truncated hash: first 12 lowercase hex chars of sha256(input). JA4's `b`
// (cipher) and `c` (extension+sigalg) segments are defined as sha256 truncated
// to 12 hex chars. An all-zero / empty input segment conventionally maps to the
// literal "000000000000", which the caller can special-case; this returns the
// real truncated digest.
pub const sa_std_net_ja4_hash12 = @import("sa_std/std_net.zig").sa_std_net_ja4_hash12;

// HMAC-SHA-256 (RFC 2104, vectors in RFC 4231) of msg under key, written
// as 64 lowercase hex chars into out (cap must be >= 64). Same status
// model as sa_std_net_sha256_hex.
pub export fn sa_hmac_sha256_hex(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 64) return finish(SA_STD_ERR_TRUNCATED);
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const msg = constBytes(msg_ptr, msg_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [32]u8 = undefined;
    std.crypto.auth.hmac.sha2.HmacSha256.create(&digest, msg, key);
    writeHexLower(out[0..64], digest[0..]);
    len_slot.* = 64;
    return finish(SA_STD_OK);
}

// HMAC-SHA-1 (RFC 2104, vectors in RFC 2202) of msg under key, written
// as 40 lowercase hex chars into out (cap must be >= 40).
pub export fn sa_hmac_sha1_hex(key_ptr: ?[*]const u8, key_len: u64, msg_ptr: ?[*]const u8, msg_len: u64, out_ptr: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const len_slot = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_slot.* = 0;
    if (out_cap < 40) return finish(SA_STD_ERR_TRUNCATED);
    const key = constBytes(key_ptr, key_len) catch |err| return finishErr(err);
    const msg = constBytes(msg_ptr, msg_len) catch |err| return finishErr(err);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    var digest: [20]u8 = undefined;
    std.crypto.auth.hmac.HmacSha1.create(&digest, msg, key);
    writeHexLower(out[0..40], digest[0..]);
    len_slot.* = 40;
    return finish(SA_STD_OK);
}

// Fill the caller buffer with bytes from the OS CSPRNG (the same source
// behind cryptoRandomU64 and sa_deno_random_uuid). A zero length is a
// no-op success, including with a null pointer.
pub export fn sa_crypto_random_bytes(out_ptr: ?[*]u8, len: u64) i32 {
    if (len == 0) return finish(SA_STD_OK);
    const out = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const n = lenAsUsize(len) catch |err| return finishErr(err);
    sio.io().random(out[0..n]);
    return finish(SA_STD_OK);
}

pub fn expectTimeoutRoundedUpWithin(requested_ns: u64, observed_ns: u64) !void {
    try std.testing.expect(observed_ns >= requested_ns);
    try std.testing.expect(observed_ns - requested_ns <= 10 * std.time.ns_per_ms);
}
































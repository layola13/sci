const std = @import("std");
pub const JsonWriterHandle = @import("../sa_std.zig").JsonWriterHandle;
pub const SO_PASSCRED = @import("../sa_std.zig").SO_PASSCRED;
pub const WasiSOL = @import("../sa_std.zig").WasiSOL;
pub const errnoToAny = @import("../sa_std.zig").errnoToAny;
pub const is_linux = @import("../sa_std.zig").is_linux;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const policyAllows = @import("../sa_std.zig").policyAllows;
const setSocketOptBool = @import("../sa_std.zig").setSocketOptBool;
pub const sio = @import("../sa_std.zig").sio;

pub fn saStdPolicyAllowsRun(program: []const u8) bool {
    return policyAllows(.{ .run = program });
}

pub fn saStdPolicyAllowsFsRead(path: []const u8) bool {
    return policyAllows(.{ .fs = .{ .path = path, .write = false } });
}

pub fn policyEnvOwned(allocator: std.mem.Allocator, name: []const u8) ?[]u8 {
    return sio.getEnvVarOwned(allocator, name) catch null;
}

pub const SOLT = if (is_wasm) WasiSOL else std.posix.SOL;

pub const RegexMatchC = extern struct {
    rm_so: c_int,
    rm_eo: c_int,
};

pub fn markJsonWriterValueComplete(writer_handle: *JsonWriterHandle) void {
    writer_handle.root_value_started = true;
    writer_handle.root_value_complete = writer_handle.open_depth == 0;
}

pub const SaTermEpollEvent = extern struct {
    events: u32,
    data: u64,
};

pub fn lingerSeconds(timeout_ns: u64) !i32 {
    const seconds = timeout_ns / std.time.ns_per_s;
    return std.math.cast(i32, seconds) orelse error.InvalidArgument;
}

// DEF-NET-V6-DTLS (D1): raw setsockopt that surfaces kernel refusals as
// errors. std.posix.setsockopt maps EINVAL/BADF/NOTSOCK to `unreachable`,
// which aborts the whole process for a legitimate refusal -- notably
// IPV6_V6ONLY on an already-bound socket, which the kernel only accepts
// before bind. Callers that can honour the option another way need the
// errno, not a trap.
// IPV6_V6ONLY is a bind-time option: once a socket is bound the kernel
// refuses to change it (EINVAL). Every socket behind a registry handle
// is already bound, so honour a post-bind change by rebuilding the
// socket with the option applied before bind and swapping the fd in
// the registry resource. Queued datagrams / pending connections on the
// old socket are dropped -- the unavoidable price of changing a
// bind-time option after bind. On a bind failure the pre-change socket
// shape is restored best-effort so a failed change does not silently
// destroy a working handle.

pub const LinuxUCred = extern struct {
    pid: i32,
    uid: u32,
    gid: u32,
};

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
/// Unix datagram sockets in this std carry SO_PASSCRED from birth
/// so the receive path can harvest SCM_CREDENTIALS (see above).
/// Best effort: failure only means peer_cred reports NOT_FOUND
/// for a connected socket instead of answering with a wrong or
/// zero credential.

pub fn armPeerCredHarvest(fd: std.posix.fd_t) void {
    if (comptime !is_linux) return;
    setSocketOptBool(fd, SOLT.SOCKET, SO_PASSCRED, true) catch {};
}

pub fn libcErrRc(rc: anytype) !void {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
}

pub fn libcUsize(rc: isize) !usize {
    if (rc < 0) return errnoToAny(std.posix.errno(rc));
    return @intCast(rc);
}

pub const EnvVarJson = struct {
    key: []const u8,
    value: []const u8,
};

// --- Checked i64 arithmetic (sa_std/num.sai) ------------------------------
// Exact-result arithmetic with Rust `overflow-checks = true` semantics:
// on overflow the operation traps instead of wrapping. The SA-level
// mirror (sa_std/num.sal NUM_*_CHECKED macros) traps with
// panic(PANIC_ARITH_OVERFLOW = 9001); a native extern has no SA panic
// channel, so the trap here is a diagnostic on stderr plus process
// abort -- never a wrapped result, never a silent status (the .sai
// signature returns the bare i64 and has no status channel).

pub fn saNumCheckedTrap(comptime symbol: []const u8, a: i64, b: i64) noreturn {
    std.debug.print("[sa-std] {s}({d}, {d}): i64 overflow, trapping (PANIC_ARITH_OVERFLOW=9001)\n", .{ symbol, a, b });
    std.process.abort();
}

// JS `Date.toISOString` shape for an i64 unix-millis value: UTC
// `YYYY-MM-DDTHH:MM:SS.sssZ` (millis precision, zero-padded; years
// 0..9999 exact, larger years print unpadded-past-4 like the denoise
// path). Negative inputs (pre-1970) fold correctly via floored
// division (Howard Hinnant civil_from_days). Fresh buffer handle read
// back via `sa_fmt_buffer_data`/`sa_fmt_buffer_len` like concat.
// Strict-ISO `Date.parse`: `YYYY-MM-DD[THH:MM:SS[.sss]][Z|±HH:MM]`
// to unix millis. Plain i32 status (0 ok, 2 invalid); range-checked
// (leap days, h<24, m/s<60); date-only means UTC midnight per JS.
// Inverse Hinnant days_from_civil; years 0..9999 keep i64 arithmetic
// exact (bounded well inside range, no checked ops needed).
/// JS Date getters over i64 unix millis (UTC; month 0-based like JS,
/// day 0=Sunday like JS: 1970-01-01 was a Thursday).

pub const weekdayNames = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };

pub fn groupId(value: u32, enabled: u32) std.c.gid_t {
    return if (enabled != 0) @as(std.c.gid_t, @intCast(value)) else ~@as(std.c.gid_t, 0);
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
// out_flags bits of sa_std_net_udp_recv_msg; mirrored as
// SA_NET_RECV_MSG_* in sa_std/net.sla.

pub const recv_msg_flag_pktinfo: u32 = 1;

pub const recv_msg_flag_timestamp: u32 = 2;

pub const recv_msg_flag_ctrunc: u32 = 4;

pub const recv_msg_flag_trunc: u32 = 8;

pub fn expectTimeoutRoundedUpWithin(requested_ns: u64, observed_ns: u64) !void {
    try std.testing.expect(observed_ns >= requested_ns);
    try std.testing.expect(observed_ns - requested_ns <= 10 * std.time.ns_per_ms);
}

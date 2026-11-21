//! sa_std SSH core: client (dlopen libssh2) + server (dlopen libssh).
//!
//! Built into sa_std under the all-cores-built-in doctrine: no plugin
//! is required for SSH exec/SFTP or for serving SSH sessions. Both
//! libraries are dlopen-bound; hosts without them report
//! supported-bits = 0 and constructors return ERR_UNSUPPORTED.
//!
//! Interop note: servers should not emit output, exit status, EOF
//! and CLOSE in a single burst — libssh2 clients drop payload that
//! arrives in the same transport batch as the CLOSE. Real exec
//! servers pace this naturally via command execution time.
//!
//! Client: connect (TCP + handshake), SHA-256 host-key fingerprint
//! (base64), password / key-file auth, exec with captured
//! stdout/stderr/exit status, SFTP read/write/stat.
//! Server: listen with a host key, accept, caller-driven auth
//! (password or public key: the caller inspects user + secret/key and
//! accepts or denies), one session channel with exec/shell requests,
//! channel IO, exit status.
//! Status codes mirror sa_std.zig (0 ok, 1 invalid, 2 bad handle,
//! 3 not found, 4 access, 5 no memory, 6 io, 7 net, 8 unsupported).

test "sa_ssh_tests" { std.testing.refAllDecls(@import("sa_ssh_test.zig")); }

const std = @import("std");
const builtin = @import("builtin");
pub const sio = @import("sio");

pub const OK: i32 = 0;
pub const ERR_INVALID: i32 = 1;
pub const ERR_HANDLE: i32 = 2;
const ERR_ACCESS: i32 = 4;
pub const ERR_NOMEM: i32 = 5;
pub const ERR_IO: i32 = 6;
pub const ERR_NET: i32 = 7;
pub const ERR_UNSUPPORTED: i32 = 8;

pub const ALLOC = std.heap.page_allocator;

// ---------------- buffer handles ----------------
var buffers_mu = std.Io.Mutex.init;
var buffers: std.AutoHashMapUnmanaged(u64, []u8) = .empty;
var buffers_next: u64 = 1;

pub fn registerBuffer(data: []u8) !u64 {
    buffers_mu.lockUncancelable(sio.io());
    defer buffers_mu.unlock(sio.io());
    const h = buffers_next;
    buffers_next += 1;
    try buffers.put(ALLOC, h, data);
    return h;
}

pub export fn sa_std_ssh_buffer_data(handle: u64) ?[*]const u8 {
    buffers_mu.lockUncancelable(sio.io());
    defer buffers_mu.unlock(sio.io());
    const b = buffers.get(handle) orelse return null;
    return b.ptr;
}

pub export fn sa_std_ssh_buffer_len(handle: u64) u64 {
    buffers_mu.lockUncancelable(sio.io());
    defer buffers_mu.unlock(sio.io());
    const b = buffers.get(handle) orelse return 0;
    return b.len;
}

pub export fn sa_std_ssh_buffer_free(handle: u64) i32 {
    buffers_mu.lockUncancelable(sio.io());
    const kv = buffers.fetchRemove(handle);
    buffers_mu.unlock(sio.io());
    const b = (kv orelse return ERR_HANDLE).value;
    ALLOC.free(b);
    return OK;
}

// ---------------- libssh2 (client) ----------------
const Ssh2 = struct {
    init: *const fn (c_int) callconv(.c) c_int,
    exit_fn: *const fn () callconv(.c) void,
    session_init: *const fn (?*const anyopaque, ?*const anyopaque, ?*const anyopaque, ?*const anyopaque) callconv(.c) ?*anyopaque,
    session_handshake: *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    session_disconnect: *const fn (?*anyopaque, c_int, [*:0]const u8, [*:0]const u8) callconv(.c) c_int,
    session_free: *const fn (?*anyopaque) callconv(.c) c_int,
    session_set_blocking: *const fn (?*anyopaque, c_int) callconv(.c) void,
    hostkey_hash: *const fn (?*anyopaque, c_int) callconv(.c) ?[*]const u8,
    auth_password: *const fn (?*anyopaque, [*:0]const u8, c_uint, [*:0]const u8, c_uint, ?*const anyopaque) callconv(.c) c_int,
    auth_keyfile: *const fn (?*anyopaque, [*:0]const u8, c_uint, ?[*:0]const u8, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int,
    channel_open: *const fn (?*anyopaque, [*:0]const u8, c_uint, c_uint, c_uint, ?[*]const u8, c_uint) callconv(.c) ?*anyopaque,
    channel_startup: *const fn (?*anyopaque, [*:0]const u8, c_uint, ?[*]const u8, c_uint) callconv(.c) c_int,
    channel_read: *const fn (?*anyopaque, c_int, [*]u8, usize) callconv(.c) isize,
    channel_eof: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_wait_eof: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_exit_status: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_close: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_free: *const fn (?*anyopaque) callconv(.c) c_int,
    sftp_init: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    sftp_shutdown: *const fn (?*anyopaque) callconv(.c) c_int,
    sftp_open: *const fn (?*anyopaque, [*]const u8, c_uint, c_ulong, c_long, c_int) callconv(.c) ?*anyopaque,
    sftp_read: *const fn (?*anyopaque, [*]u8, usize) callconv(.c) isize,
    sftp_write: *const fn (?*anyopaque, [*]const u8, usize) callconv(.c) isize,
    sftp_close: *const fn (?*anyopaque) callconv(.c) c_int,
    sftp_stat: *const fn (?*anyopaque, [*]const u8, c_uint, c_int, [*]u8) callconv(.c) c_int,
};

var ssh2_api: ?Ssh2 = null;
var ssh2_tried: bool = false;
var ssh2_mu = std.Io.Mutex.init;

fn loadSsh2() ?*const Ssh2 {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadSsh2Native();
    }
}

fn loadSsh2Native() ?*const Ssh2 {
    ssh2_mu.lockUncancelable(sio.io());
    defer ssh2_mu.unlock(sio.io());
    if (ssh2_api) |*a| return a;
    if (ssh2_tried) return null;
    ssh2_tried = true;
    var lib = std.DynLib.open("libssh2.so.1") catch return null;
    const api = Ssh2{
        .init = lib.lookup(*const fn (c_int) callconv(.c) c_int, "libssh2_init") orelse return null,
        .exit_fn = lib.lookup(*const fn () callconv(.c) void, "libssh2_exit") orelse return null,
        .session_init = lib.lookup(*const fn (?*const anyopaque, ?*const anyopaque, ?*const anyopaque, ?*const anyopaque) callconv(.c) ?*anyopaque, "libssh2_session_init_ex") orelse return null,
        .session_handshake = lib.lookup(*const fn (?*anyopaque, c_int) callconv(.c) c_int, "libssh2_session_handshake") orelse return null,
        .session_disconnect = lib.lookup(*const fn (?*anyopaque, c_int, [*:0]const u8, [*:0]const u8) callconv(.c) c_int, "libssh2_session_disconnect_ex") orelse return null,
        .session_free = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_session_free") orelse return null,
        .session_set_blocking = lib.lookup(*const fn (?*anyopaque, c_int) callconv(.c) void, "libssh2_session_set_blocking") orelse return null,
        .hostkey_hash = lib.lookup(*const fn (?*anyopaque, c_int) callconv(.c) ?[*]const u8, "libssh2_hostkey_hash") orelse return null,
        .auth_password = lib.lookup(*const fn (?*anyopaque, [*:0]const u8, c_uint, [*:0]const u8, c_uint, ?*const anyopaque) callconv(.c) c_int, "libssh2_userauth_password_ex") orelse return null,
        .auth_keyfile = lib.lookup(*const fn (?*anyopaque, [*:0]const u8, c_uint, ?[*:0]const u8, [*:0]const u8, ?[*:0]const u8) callconv(.c) c_int, "libssh2_userauth_publickey_fromfile_ex") orelse return null,
        .channel_open = lib.lookup(*const fn (?*anyopaque, [*:0]const u8, c_uint, c_uint, c_uint, ?[*]const u8, c_uint) callconv(.c) ?*anyopaque, "libssh2_channel_open_ex") orelse return null,
        .channel_startup = lib.lookup(*const fn (?*anyopaque, [*:0]const u8, c_uint, ?[*]const u8, c_uint) callconv(.c) c_int, "libssh2_channel_process_startup") orelse return null,
        .channel_read = lib.lookup(*const fn (?*anyopaque, c_int, [*]u8, usize) callconv(.c) isize, "libssh2_channel_read_ex") orelse return null,
        .channel_eof = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_channel_eof") orelse return null,
        .channel_wait_eof = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_channel_wait_eof") orelse return null,
        .channel_exit_status = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_channel_get_exit_status") orelse return null,
        .channel_close = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_channel_close") orelse return null,
        .channel_free = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_channel_free") orelse return null,
        .sftp_init = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?*anyopaque, "libssh2_sftp_init") orelse return null,
        .sftp_shutdown = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_sftp_shutdown") orelse return null,
        .sftp_open = lib.lookup(*const fn (?*anyopaque, [*]const u8, c_uint, c_ulong, c_long, c_int) callconv(.c) ?*anyopaque, "libssh2_sftp_open_ex") orelse return null,
        .sftp_read = lib.lookup(*const fn (?*anyopaque, [*]u8, usize) callconv(.c) isize, "libssh2_sftp_read") orelse return null,
        .sftp_write = lib.lookup(*const fn (?*anyopaque, [*]const u8, usize) callconv(.c) isize, "libssh2_sftp_write") orelse return null,
        .sftp_close = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "libssh2_sftp_close_handle") orelse return null,
        .sftp_stat = lib.lookup(*const fn (?*anyopaque, [*]const u8, c_uint, c_int, [*]u8) callconv(.c) c_int, "libssh2_sftp_stat_ex") orelse return null,
    };
    if (api.init(0) != 0) return null;
    ssh2_api = api;
    return &ssh2_api.?;
}

const Client = struct {
    api: *const Ssh2,
    session: ?*anyopaque,
    fd: i32,
    sftp: ?*anyopaque = null,
};

fn clientOf(handle: ?*anyopaque) ?*Client {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

pub fn toZ(allocator: std.mem.Allocator, s: []const u8) ?[:0]u8 {
    const buf = allocator.allocSentinel(u8, s.len, 0) catch return null;
    @memcpy(buf[0..s.len], s);
    return buf;
}

fn tcpConnect(host: []const u8, port: u16) !i32 {
    if (comptime builtin.cpu.arch.isWasm()) {
        return error.UnsupportedPlatform;
    } else {
        return tcpConnectNative(host, port);
    }
}

fn tcpConnectNative(host: []const u8, port: u16) !i32 {
    const host_z = toZ(ALLOC, host) orelse return error.OutOfMemory;
    defer ALLOC.free(host_z);
    var port_buf: [8]u8 = undefined;
    const port_s = std.fmt.bufPrint(&port_buf, "{d}", .{port}) catch unreachable;
    const port_z = toZ(ALLOC, port_s) orelse return error.OutOfMemory;
    defer ALLOC.free(port_z);
    var hints: std.c.addrinfo = std.mem.zeroes(std.c.addrinfo);
    hints.family = std.posix.AF.INET;
    hints.socktype = std.posix.SOCK.STREAM;
    var res: ?*std.c.addrinfo = null;
    if (@intFromEnum(std.c.getaddrinfo(host_z.ptr, port_z.ptr, &hints, &res)) != 0) return error.UnknownHost;
    defer if (res) |r| std.c.freeaddrinfo(r);
    const first = res orelse return error.UnknownHost;
    const rc = std.os.linux.socket(std.posix.AF.INET, std.os.linux.SOCK.STREAM | std.os.linux.SOCK.CLOEXEC, 0);
    if (@as(isize, @bitCast(rc)) < 0) return error.SocketFailed;
    const fd: i32 = @intCast(rc);
    errdefer lxClose(fd);
    // 20 s send/recv timeouts so blocking libssh2 calls cannot hang forever
    const tv = std.posix.timeval{ .sec = 20, .usec = 0 };
    _ = std.os.linux.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, std.mem.asBytes(&tv).ptr, @sizeOf(std.posix.timeval));
    _ = std.os.linux.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, std.mem.asBytes(&tv).ptr, @sizeOf(std.posix.timeval));
    const addr = first.addr orelse return error.UnknownHost;
    if (@as(isize, @bitCast(std.os.linux.connect(fd, addr, first.addrlen))) < 0) return error.ConnectFailed;
    return fd;
}

pub export fn sa_std_ssh_supported(out_flags: ?*u32) i32 {
    const slot = out_flags orelse return ERR_INVALID;
    var flags: u32 = 0;
    if (loadSsh2() != null) flags |= 1;
    if (loadSsh() != null) flags |= 2;
    slot.* = flags;
    return OK;
}

pub export fn sa_std_ssh_client_connect(host: ?[*]const u8, host_len: u64, port: u32, out_session: ?*?*anyopaque) i32 {
    const slot = out_session orelse return ERR_INVALID;
    slot.* = null;
    const api = loadSsh2() orelse return ERR_UNSUPPORTED;
    const host_ptr = host orelse return ERR_INVALID;
    if (port == 0 or port > 65535) return ERR_INVALID;
    const fd = tcpConnect(host_ptr[0..@intCast(host_len)], @intCast(port)) catch return ERR_NET;
    const session = api.session_init(null, null, null, null) orelse {
        lxClose(fd);
        return ERR_IO;
    };
    api.session_set_blocking(session, 1);
    if (api.session_handshake(session, fd) != 0) {
        _ = api.session_free(session);
        lxClose(fd);
        return ERR_NET;
    }
    const client = ALLOC.create(Client) catch {
        _ = api.session_free(session);
        lxClose(fd);
        return ERR_NOMEM;
    };
    client.* = .{ .api = api, .session = session, .fd = fd };
    slot.* = client;
    return OK;
}

pub export fn sa_std_ssh_hostkey_fingerprint(session: ?*anyopaque, out: ?[*]u8, cap: u64, out_len: ?*u64) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const len_slot = out_len orelse return ERR_INVALID;
    const hash = client.api.hostkey_hash(client.session, 3) orelse return ERR_IO; // SHA256
    const digest = hash[0..32];
    const b64 = std.base64.standard.Encoder;
    var encoded: [64]u8 = undefined;
    const text = b64.encode(&encoded, digest);
    len_slot.* = text.len;
    if (cap < text.len) return 9; // truncated
    const buf = out orelse return ERR_INVALID;
    @memcpy(buf[0..text.len], text);
    return OK;
}

pub export fn sa_std_ssh_auth_password(session: ?*anyopaque, user: ?[*]const u8, user_len: u64, password: ?[*]const u8, password_len: u64) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const user_ptr = user orelse return ERR_INVALID;
    const pass_ptr = password orelse return ERR_INVALID;
    const user_z = toZ(ALLOC, user_ptr[0..@intCast(user_len)]) orelse return ERR_NOMEM;
    defer ALLOC.free(user_z);
    const pass_z = toZ(ALLOC, pass_ptr[0..@intCast(password_len)]) orelse return ERR_NOMEM;
    defer ALLOC.free(pass_z);
    const rc = client.api.auth_password(client.session, user_z.ptr, @intCast(user_len), pass_z.ptr, @intCast(password_len), null);
    return if (rc == 0) OK else ERR_ACCESS;
}

pub export fn sa_std_ssh_auth_keyfile(session: ?*anyopaque, user: ?[*]const u8, user_len: u64, pub_path: ?[*]const u8, pub_path_len: u64, priv_path: ?[*]const u8, priv_path_len: u64, passphrase: ?[*]const u8, passphrase_len: u64) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const user_ptr = user orelse return ERR_INVALID;
    const priv_ptr = priv_path orelse return ERR_INVALID;
    const user_z = toZ(ALLOC, user_ptr[0..@intCast(user_len)]) orelse return ERR_NOMEM;
    defer ALLOC.free(user_z);
    const priv_z = toZ(ALLOC, priv_ptr[0..@intCast(priv_path_len)]) orelse return ERR_NOMEM;
    defer ALLOC.free(priv_z);
    var pub_z: ?[:0]u8 = null;
    defer if (pub_z) |z| ALLOC.free(z);
    if (pub_path) |pp| {
        if (pub_path_len > 0) pub_z = toZ(ALLOC, pp[0..@intCast(pub_path_len)]) orelse return ERR_NOMEM;
    }
    var pass_z: ?[:0]u8 = null;
    defer if (pass_z) |z| ALLOC.free(z);
    if (passphrase) |pp| {
        if (passphrase_len > 0) pass_z = toZ(ALLOC, pp[0..@intCast(passphrase_len)]) orelse return ERR_NOMEM;
    }
    const rc = client.api.auth_keyfile(client.session, user_z.ptr, @intCast(user_len), if (pub_z) |z| z.ptr else null, priv_z.ptr, if (pass_z) |z| z.ptr else null);
    return if (rc == 0) OK else ERR_ACCESS;
}

const MAX_CAPTURE: usize = 64 * 1024 * 1024;

pub fn lxClose(fd: i32) void {
    if (comptime builtin.cpu.arch.isWasm()) {
    } else {
        _ = std.os.linux.close(fd);
    }
}

fn sleepMs(ms: u32) void {
    if (comptime builtin.cpu.arch.isWasm()) {
        var start: std.os.wasi.timestamp_t = 0;
        _ = std.os.wasi.clock_time_get(.MONOTONIC, 0, &start);
        const want: std.os.wasi.timestamp_t = @as(std.os.wasi.timestamp_t, ms) * std.time.ns_per_ms;
        while (true) {
            var now: std.os.wasi.timestamp_t = 0;
            _ = std.os.wasi.clock_time_get(.MONOTONIC, 0, &now);
            if (now - start >= want) break;
        }
    } else {
        _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = @as(i64, @intCast(ms)) * std.time.ns_per_ms }, null);
    }
}

fn readChannelAll(api: *const Ssh2, channel: ?*anyopaque, stream: c_int, list: *std.array_list.Managed(u8)) !void {
    var buf: [16384]u8 = undefined;
    var eagain_spins: usize = 0;
    while (true) {
        const n = api.channel_read(channel, stream, &buf, buf.len);
        if (n > 0) {
            try list.appendSlice(buf[0..@intCast(n)]);
            if (list.items.len > MAX_CAPTURE) return error.Io;
            eagain_spins = 0;
        } else if (n == 0) {
            break;
        } else if (n == -37) {
            // LIBSSH2_ERROR_EAGAIN: even in blocking mode libssh2 can
            // surface EAGAIN while the transport flushes; retry.
            eagain_spins += 1;
            if (eagain_spins > 15000) return error.Io;
            sleepMs(2);
        } else if (n == -43) {
            // LIBSSH2_ERROR_CHANNEL_CLOSED: a fast server that sends
            // data + exit status + EOF + CLOSE in one burst makes
            // libssh2 answer -43 once the queued data is drained
            // (verified against a libssh server). Queued data is
            // always delivered first, so -43 here means the stream
            // is complete; the exit status stays readable.
            break;
        } else {
            return error.Io;
        }
    }
}

pub export fn sa_std_ssh_exec(session: ?*anyopaque, command: ?[*]const u8, command_len: u64, out_stdout: ?*u64, out_stderr: ?*u64, out_exit: ?*i32) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const cmd_ptr = command orelse return ERR_INVALID;
    const so_slot = out_stdout orelse return ERR_INVALID;
    const se_slot = out_stderr orelse return ERR_INVALID;
    const ex_slot = out_exit orelse return ERR_INVALID;
    so_slot.* = 0;
    se_slot.* = 0;
    ex_slot.* = -1;
    const api = client.api;
    const channel = api.channel_open(client.session, "session", 7, 2 * 1024 * 1024, 32768, null, 0) orelse return ERR_IO;
    defer {
        _ = api.channel_close(channel);
        _ = api.channel_free(channel);
    }
    const cmd = cmd_ptr[0..@intCast(command_len)];
    var startup_spins: usize = 0;
    while (true) {
        const src = api.channel_startup(channel, "exec", 4, cmd.ptr, @intCast(cmd.len));
        if (src == 0) break;
        if (src != -37 or startup_spins >= 5000) return ERR_IO;
        startup_spins += 1;
        sleepMs(2);
    }
    var out_list = std.array_list.Managed(u8).init(ALLOC);
    errdefer out_list.deinit();
    var err_list = std.array_list.Managed(u8).init(ALLOC);
    errdefer err_list.deinit();
    readChannelAll(api, channel, 0, &out_list) catch return ERR_IO;
    readChannelAll(api, channel, 1, &err_list) catch return ERR_IO;
    _ = api.channel_wait_eof(channel);
    ex_slot.* = api.channel_exit_status(channel);
    so_slot.* = registerBuffer(out_list.toOwnedSlice() catch return ERR_NOMEM) catch return ERR_NOMEM;
    se_slot.* = registerBuffer(err_list.toOwnedSlice() catch return ERR_NOMEM) catch return ERR_NOMEM;
    return OK;
}

fn ensureSftp(client: *Client) ?*anyopaque {
    if (client.sftp) |s| return s;
    const s = client.api.sftp_init(client.session) orelse return null;
    client.sftp = s;
    return s;
}

pub export fn sa_std_ssh_sftp_read(session: ?*anyopaque, path: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const slot = out_handle orelse return ERR_INVALID;
    slot.* = 0;
    const path_ptr = path orelse return ERR_INVALID;
    const sftp = ensureSftp(client) orelse return ERR_IO;
    const p = path_ptr[0..@intCast(path_len)];
    const fh = client.api.sftp_open(sftp, p.ptr, @intCast(p.len), 0x00000001, 0, 0) orelse return ERR_IO; // FXF_READ, OPENFILE
    defer _ = client.api.sftp_close(fh);
    var list = std.array_list.Managed(u8).init(ALLOC);
    errdefer list.deinit();
    var buf: [32768]u8 = undefined;
    var sftp_spins: usize = 0;
    while (true) {
        const n = client.api.sftp_read(fh, &buf, buf.len);
        if (n > 0) {
            list.appendSlice(buf[0..@intCast(n)]) catch return ERR_NOMEM;
            if (list.items.len > MAX_CAPTURE) return ERR_IO;
            sftp_spins = 0;
        } else if (n == 0) {
            break;
        } else if (n == -37) {
            sftp_spins += 1;
            if (sftp_spins > 15000) return ERR_IO;
            sleepMs(2);
        } else return ERR_IO;
    }
    slot.* = registerBuffer(list.toOwnedSlice() catch return ERR_NOMEM) catch return ERR_NOMEM;
    return OK;
}

pub export fn sa_std_ssh_sftp_write(session: ?*anyopaque, path: ?[*]const u8, path_len: u64, data: ?[*]const u8, data_len: u64) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const path_ptr = path orelse return ERR_INVALID;
    const data_ptr = data orelse return ERR_INVALID;
    const sftp = ensureSftp(client) orelse return ERR_IO;
    const p = path_ptr[0..@intCast(path_len)];
    const flags: c_ulong = 0x00000002 | 0x00000008 | 0x00000010; // WRITE|CREAT|TRUNC
    const fh = client.api.sftp_open(sftp, p.ptr, @intCast(p.len), flags, 0o644, 0) orelse return ERR_IO;
    defer _ = client.api.sftp_close(fh);
    const bytes = data_ptr[0..@intCast(data_len)];
    var off: usize = 0;
    var write_spins: usize = 0;
    while (off < bytes.len) {
        const n = client.api.sftp_write(fh, bytes[off..].ptr, bytes.len - off);
        if (n == -37) {
            write_spins += 1;
            if (write_spins > 15000) return ERR_IO;
            sleepMs(2);
            continue;
        }
        if (n <= 0) return ERR_IO;
        off += @intCast(n);
    }
    return OK;
}

pub export fn sa_std_ssh_sftp_stat(session: ?*anyopaque, path: ?[*]const u8, path_len: u64, out_size: ?*u64, out_is_dir: ?*u32) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    const path_ptr = path orelse return ERR_INVALID;
    const size_slot = out_size orelse return ERR_INVALID;
    const dir_slot = out_is_dir orelse return ERR_INVALID;
    const sftp = ensureSftp(client) orelse return ERR_IO;
    const p = path_ptr[0..@intCast(path_len)];
    var attrs: [56]u8 = @splat(0);
    if (client.api.sftp_stat(sftp, p.ptr, @intCast(p.len), 0, &attrs) != 0) return 3; // not found
    const flags = std.mem.readInt(u64, attrs[0..8], .little);
    if (flags & 1 != 0) size_slot.* = std.mem.readInt(u64, attrs[8..16], .little) else size_slot.* = 0;
    const perm = std.mem.readInt(u64, attrs[32..40], .little);
    dir_slot.* = if ((perm & 0o170000) == 0o040000) 1 else 0;
    return OK;
}

pub export fn sa_std_ssh_session_close(session: ?*anyopaque) i32 {
    const client = clientOf(session) orelse return ERR_HANDLE;
    if (client.sftp) |s| _ = client.api.sftp_shutdown(s);
    _ = client.api.session_disconnect(client.session, 11, "bye", "");
    _ = client.api.session_free(client.session);
    lxClose(client.fd);
    ALLOC.destroy(client);
    return OK;
}

// ---------------- libssh (server) ----------------
pub const Ssh = struct {
    bind_new: *const fn () callconv(.c) ?*anyopaque,
    bind_options_set: *const fn (?*anyopaque, c_int, ?*const anyopaque) callconv(.c) c_int,
    bind_listen: *const fn (?*anyopaque) callconv(.c) c_int,
    bind_accept: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int,
    bind_free: *const fn (?*anyopaque) callconv(.c) void,
    new_session: *const fn () callconv(.c) ?*anyopaque,
    free_session: *const fn (?*anyopaque) callconv(.c) void,
    disconnect: *const fn (?*anyopaque) callconv(.c) void,
    handle_key_exchange: *const fn (?*anyopaque) callconv(.c) c_int,
    message_get: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    message_free: *const fn (?*anyopaque) callconv(.c) void,
    message_get_type: *const fn (?*anyopaque) callconv(.c) c_int,
    message_subtype: *const fn (?*anyopaque) callconv(.c) c_int,
    message_reply_default: *const fn (?*anyopaque) callconv(.c) c_int,
    auth_user: *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8,
    auth_password: *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8,
    auth_reply_success: *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    auth_pubkey: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    auth_publickey_state: *const fn (?*anyopaque) callconv(.c) c_int,
    auth_reply_pk_ok_simple: *const fn (?*anyopaque) callconv(.c) c_int,
    pki_export_pubkey_base64: *const fn (?*anyopaque, *?[*:0]u8) callconv(.c) c_int,
    string_free_char: *const fn (?[*:0]u8) callconv(.c) void,
    channel_open_reply_accept: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    channel_request_reply_success: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_request_command: *const fn (?*anyopaque) callconv(.c) ?[*:0]const u8,
    channel_write: *const fn (?*anyopaque, [*]const u8, u32) callconv(.c) c_int,
    channel_write_stderr: *const fn (?*anyopaque, [*]const u8, u32) callconv(.c) c_int,
    channel_read: *const fn (?*anyopaque, [*]u8, u32, c_int) callconv(.c) c_int,
    channel_send_eof: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_exit_status: *const fn (?*anyopaque, c_int) callconv(.c) c_int,
    channel_close: *const fn (?*anyopaque) callconv(.c) c_int,
    channel_free: *const fn (?*anyopaque) callconv(.c) void,
};

var ssh_api: ?Ssh = null;
var ssh_tried: bool = false;
var ssh_mu = std.Io.Mutex.init;

pub fn loadSsh() ?*const Ssh {
    if (comptime builtin.cpu.arch.isWasm()) {
        return null;
    } else {
        return loadSshNative();
    }
}

fn loadSshNative() ?*const Ssh {
    ssh_mu.lockUncancelable(sio.io());
    defer ssh_mu.unlock(sio.io());
    if (ssh_api) |*a| return a;
    if (ssh_tried) return null;
    ssh_tried = true;
    var lib = std.DynLib.open("libssh.so.4") catch return null;
    const api = Ssh{
        .bind_new = lib.lookup(*const fn () callconv(.c) ?*anyopaque, "ssh_bind_new") orelse return null,
        .bind_options_set = lib.lookup(*const fn (?*anyopaque, c_int, ?*const anyopaque) callconv(.c) c_int, "ssh_bind_options_set") orelse return null,
        .bind_listen = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_bind_listen") orelse return null,
        .bind_accept = lib.lookup(*const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int, "ssh_bind_accept") orelse return null,
        .bind_free = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "ssh_bind_free") orelse return null,
        .new_session = lib.lookup(*const fn () callconv(.c) ?*anyopaque, "ssh_new") orelse return null,
        .free_session = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "ssh_free") orelse return null,
        .disconnect = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "ssh_disconnect") orelse return null,
        .handle_key_exchange = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_handle_key_exchange") orelse return null,
        .message_get = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?*anyopaque, "ssh_message_get") orelse return null,
        .message_free = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "ssh_message_free") orelse return null,
        // libssh >= 0.11 names it ssh_message_get_type; 0.10 ssh_message_type
        .message_get_type = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_get_type") orelse lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_type") orelse return null,
        .message_subtype = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_subtype") orelse return null,
        .message_reply_default = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_reply_default") orelse return null,
        .auth_user = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?[*:0]const u8, "ssh_message_auth_user") orelse return null,
        .auth_password = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?[*:0]const u8, "ssh_message_auth_password") orelse return null,
        .auth_reply_success = lib.lookup(*const fn (?*anyopaque, c_int) callconv(.c) c_int, "ssh_message_auth_reply_success") orelse return null,
        .auth_pubkey = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?*anyopaque, "ssh_message_auth_pubkey") orelse return null,
        .auth_publickey_state = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_auth_publickey_state") orelse return null,
        .auth_reply_pk_ok_simple = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_auth_reply_pk_ok_simple") orelse return null,
        .pki_export_pubkey_base64 = lib.lookup(*const fn (?*anyopaque, *?[*:0]u8) callconv(.c) c_int, "ssh_pki_export_pubkey_base64") orelse return null,
        .string_free_char = lib.lookup(*const fn (?[*:0]u8) callconv(.c) void, "ssh_string_free_char") orelse return null,
        .channel_open_reply_accept = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?*anyopaque, "ssh_message_channel_request_open_reply_accept") orelse return null,
        .channel_request_reply_success = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_channel_request_reply_success") orelse return null,
        .channel_request_command = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?[*:0]const u8, "ssh_message_channel_request_command") orelse return null,
        .channel_write = lib.lookup(*const fn (?*anyopaque, [*]const u8, u32) callconv(.c) c_int, "ssh_channel_write") orelse return null,
        .channel_write_stderr = lib.lookup(*const fn (?*anyopaque, [*]const u8, u32) callconv(.c) c_int, "ssh_channel_write_stderr") orelse return null,
        .channel_read = lib.lookup(*const fn (?*anyopaque, [*]u8, u32, c_int) callconv(.c) c_int, "ssh_channel_read") orelse return null,
        .channel_send_eof = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_channel_send_eof") orelse return null,
        .channel_exit_status = lib.lookup(*const fn (?*anyopaque, c_int) callconv(.c) c_int, "ssh_channel_request_send_exit_status") orelse return null,
        .channel_close = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_channel_close") orelse return null,
        .channel_free = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "ssh_channel_free") orelse return null,
    };
    ssh_api = api;
    return &ssh_api.?;
}

pub const ServerBind = @import("sa_ssh_server.zig").ServerBind;
pub const ServerSession = @import("sa_ssh_server.zig").ServerSession;
pub const ServerChannel = @import("sa_ssh_server.zig").ServerChannel;

pub const sa_std_ssh_server_listen = @import("sa_ssh_server.zig").sa_std_ssh_server_listen;

pub const sa_std_ssh_server_bind_close = @import("sa_ssh_server.zig").sa_std_ssh_server_bind_close;

pub const sa_std_ssh_server_accept = @import("sa_ssh_server.zig").sa_std_ssh_server_accept;

pub const serverSessionOf = @import("sa_ssh_server.zig").serverSessionOf;

/// Pumps messages until an auth attempt arrives. out_kind: 1 =
/// password (secret = password), 2 = public key (secret = base64 key
/// blob; out_state: 0 = query only, 1 = signed). The caller decides
/// with server_auth_accept / server_auth_deny.
pub const sa_std_ssh_server_auth_next = @import("sa_ssh_server.zig").sa_std_ssh_server_auth_next;

pub const sa_std_ssh_server_auth_accept = @import("sa_ssh_server.zig").sa_std_ssh_server_auth_accept;

pub const sa_std_ssh_server_auth_deny = @import("sa_ssh_server.zig").sa_std_ssh_server_auth_deny;

/// Pumps messages until a session channel open arrives and accepts it.
pub const sa_std_ssh_server_channel_accept = @import("sa_ssh_server.zig").sa_std_ssh_server_channel_accept;

/// Pumps channel requests until an exec or shell request arrives.
/// out_kind: 1 = exec (command in buffer handle), 2 = shell (empty).
pub const sa_std_ssh_server_channel_exec = @import("sa_ssh_server.zig").sa_std_ssh_server_channel_exec;

pub const serverChannelOf = @import("sa_ssh_server.zig").serverChannelOf;

pub const sa_std_ssh_channel_write = @import("sa_ssh_server.zig").sa_std_ssh_channel_write;

pub const sa_std_ssh_channel_read = @import("sa_ssh_server.zig").sa_std_ssh_channel_read;

pub const sa_std_ssh_channel_send_exit = @import("sa_ssh_server.zig").sa_std_ssh_channel_send_exit;

pub const sa_std_ssh_channel_close = @import("sa_ssh_server.zig").sa_std_ssh_channel_close;

pub const sa_std_ssh_server_session_close = @import("sa_ssh_server.zig").sa_std_ssh_server_session_close;

// ======================= loopback tests =======================
pub const testing = @import("sa_ssh_test.zig").testing;

pub const stackOrSkip = @import("sa_ssh_test.zig").stackOrSkip;

pub const sh = @import("sa_ssh_test.zig").sh;

pub const freePort = @import("sa_ssh_test.zig").freePort;


pub const test_dir_counter = @import("sa_ssh_test.zig").test_dir_counter;

pub const makeTestDir = @import("sa_ssh_test.zig").makeTestDir;

pub const removeTestDir = @import("sa_ssh_test.zig").removeTestDir;

pub const bufferText = @import("sa_ssh_test.zig").bufferText;


pub const ServerOutcome = @import("sa_ssh_test.zig").ServerOutcome;

pub const runTestServer = @import("sa_ssh_test.zig").runTestServer;




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

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_ACCESS: i32 = 4;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_NET: i32 = 7;
const ERR_UNSUPPORTED: i32 = 8;

const ALLOC = std.heap.page_allocator;

// ---------------- buffer handles ----------------
var buffers_mu = std.Io.Mutex.init;
var buffers: std.AutoHashMapUnmanaged(u64, []u8) = .empty;
var buffers_next: u64 = 1;

fn registerBuffer(data: []u8) !u64 {
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

fn toZ(allocator: std.mem.Allocator, s: []const u8) ?[:0]u8 {
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

fn lxClose(fd: i32) void {
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
const Ssh = struct {
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
    auth_publickey: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    auth_publickey_state: *const fn (?*anyopaque) callconv(.c) c_int,
    auth_reply_pk_ok_simple: *const fn (?*anyopaque) callconv(.c) c_int,
    publickey_to_string: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    string_data: *const fn (?*anyopaque) callconv(.c) ?[*]u8,
    string_len: *const fn (?*anyopaque) callconv(.c) usize,
    string_free: *const fn (?*anyopaque) callconv(.c) void,
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

fn loadSsh() ?*const Ssh {
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
        .auth_publickey = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?*anyopaque, "ssh_message_auth_publickey") orelse return null,
        .auth_publickey_state = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_auth_publickey_state") orelse return null,
        .auth_reply_pk_ok_simple = lib.lookup(*const fn (?*anyopaque) callconv(.c) c_int, "ssh_message_auth_reply_pk_ok_simple") orelse return null,
        .publickey_to_string = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?*anyopaque, "publickey_to_string") orelse return null,
        .string_data = lib.lookup(*const fn (?*anyopaque) callconv(.c) ?[*]u8, "ssh_string_data") orelse return null,
        .string_len = lib.lookup(*const fn (?*anyopaque) callconv(.c) usize, "ssh_string_len") orelse return null,
        .string_free = lib.lookup(*const fn (?*anyopaque) callconv(.c) void, "ssh_string_free") orelse return null,
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

const ServerBind = struct { api: *const Ssh, bind: ?*anyopaque };
const ServerSession = struct {
    api: *const Ssh,
    session: ?*anyopaque,
    pending_msg: ?*anyopaque = null,
    pending_kind: u32 = 0,
    pending_state: i32 = 0,
};
const ServerChannel = struct { api: *const Ssh, channel: ?*anyopaque };

pub export fn sa_std_ssh_server_listen(bind_addr: ?[*]const u8, bind_addr_len: u64, port: u32, hostkey_path: ?[*]const u8, hostkey_path_len: u64, out_bind: ?*?*anyopaque) i32 {
    const slot = out_bind orelse return ERR_INVALID;
    slot.* = null;
    const api = loadSsh() orelse return ERR_UNSUPPORTED;
    const hk_ptr = hostkey_path orelse return ERR_INVALID;
    const bind = api.bind_new() orelse return ERR_IO;
    errdefer api.bind_free(bind);
    const hk_z = toZ(ALLOC, hk_ptr[0..@intCast(hostkey_path_len)]) orelse return ERR_NOMEM;
    defer ALLOC.free(hk_z);
    if (api.bind_options_set(bind, 3, hk_z.ptr) != 0) return ERR_IO; // HOSTKEY
    if (bind_addr) |ba| {
        if (bind_addr_len > 0) {
            const addr_z = toZ(ALLOC, ba[0..@intCast(bind_addr_len)]) orelse return ERR_NOMEM;
            defer ALLOC.free(addr_z);
            if (api.bind_options_set(bind, 0, addr_z.ptr) != 0) return ERR_IO; // BINDADDR
        }
    }
    var port_v: c_uint = @intCast(port);
    if (api.bind_options_set(bind, 1, &port_v) != 0) return ERR_IO; // BINDPORT
    if (api.bind_listen(bind) != 0) return ERR_IO;
    const out = ALLOC.create(ServerBind) catch return ERR_NOMEM;
    out.* = .{ .api = api, .bind = bind };
    slot.* = out;
    return OK;
}

pub export fn sa_std_ssh_server_bind_close(bind_handle: ?*anyopaque) i32 {
    const h = bind_handle orelse return ERR_HANDLE;
    const b: *ServerBind = @ptrCast(@alignCast(h));
    b.api.bind_free(b.bind);
    ALLOC.destroy(b);
    return OK;
}

pub export fn sa_std_ssh_server_accept(bind_handle: ?*anyopaque, out_session: ?*?*anyopaque) i32 {
    const slot = out_session orelse return ERR_INVALID;
    slot.* = null;
    const h = bind_handle orelse return ERR_HANDLE;
    const b: *ServerBind = @ptrCast(@alignCast(h));
    const session = b.api.new_session() orelse return ERR_IO;
    errdefer b.api.free_session(session);
    if (b.api.bind_accept(b.bind, session) != 0) return ERR_NET;
    if (b.api.handle_key_exchange(session) != 0) return ERR_NET;
    const out = ALLOC.create(ServerSession) catch return ERR_NOMEM;
    out.* = .{ .api = b.api, .session = session };
    slot.* = out;
    return OK;
}

fn serverSessionOf(handle: ?*anyopaque) ?*ServerSession {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

/// Pumps messages until an auth attempt arrives. out_kind: 1 =
/// password (secret = password), 2 = public key (secret = base64 key
/// blob; out_state: 0 = query only, 1 = signed). The caller decides
/// with server_auth_accept / server_auth_deny.
pub export fn sa_std_ssh_server_auth_next(session_handle: ?*anyopaque, out_kind: ?*u32, out_user: ?*u64, out_secret: ?*u64, out_state: ?*i32) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const kind_slot = out_kind orelse return ERR_INVALID;
    const user_slot = out_user orelse return ERR_INVALID;
    const secret_slot = out_secret orelse return ERR_INVALID;
    const state_slot = out_state orelse return ERR_INVALID;
    if (ss.pending_msg != null) return ERR_INVALID;
    while (true) {
        const msg = ss.api.message_get(ss.session) orelse return ERR_IO;
        const mtype = ss.api.message_get_type(msg);
        if (mtype != 1) { // not AUTH
            _ = ss.api.message_reply_default(msg);
            ss.api.message_free(msg);
            continue;
        }
        const method = ss.api.message_subtype(msg);
        const user = ss.api.auth_user(msg) orelse "";
        if (method == 2) { // password
            const pass = ss.api.auth_password(msg) orelse "";
            const user_buf = ALLOC.dupe(u8, std.mem.span(user)) catch return ERR_NOMEM;
            const pass_buf = ALLOC.dupe(u8, std.mem.span(pass)) catch {
                ALLOC.free(user_buf);
                return ERR_NOMEM;
            };
            user_slot.* = registerBuffer(user_buf) catch return ERR_NOMEM;
            secret_slot.* = registerBuffer(pass_buf) catch return ERR_NOMEM;
            kind_slot.* = 1;
            state_slot.* = 0;
            ss.pending_msg = msg;
            ss.pending_kind = 1;
            return OK;
        }
        if (method == 4) { // publickey
            // ssh_message_auth_publickey returns the legacy
            // ssh_public_key (message-owned; never freed here). The
            // ssh_key exporters (ssh_pki_export_pubkey_base64) expect
            // the newer ssh_key and segfault on it in libssh 0.10, so
            // take the legacy publickey_to_string blob and base64 it.
            const key = ss.api.auth_publickey(msg) orelse {
                _ = ss.api.message_reply_default(msg);
                ss.api.message_free(msg);
                continue;
            };
            const blob = ss.api.publickey_to_string(key) orelse {
                _ = ss.api.message_reply_default(msg);
                ss.api.message_free(msg);
                continue;
            };
            defer ss.api.string_free(blob);
            const blob_len = ss.api.string_len(blob);
            const blob_data = ss.api.string_data(blob) orelse {
                _ = ss.api.message_reply_default(msg);
                ss.api.message_free(msg);
                continue;
            };
            const raw = blob_data[0..blob_len];
            const user_buf = ALLOC.dupe(u8, std.mem.span(user)) catch return ERR_NOMEM;
            const key_buf = ALLOC.alloc(u8, std.base64.standard.Encoder.calcSize(raw.len)) catch {
                ALLOC.free(user_buf);
                return ERR_NOMEM;
            };
            _ = std.base64.standard.Encoder.encode(key_buf, raw);
            user_slot.* = registerBuffer(user_buf) catch return ERR_NOMEM;
            secret_slot.* = registerBuffer(key_buf) catch return ERR_NOMEM;
            kind_slot.* = 2;
            state_slot.* = ss.api.auth_publickey_state(msg);
            ss.pending_msg = msg;
            ss.pending_kind = 2;
            ss.pending_state = state_slot.*;
            return OK;
        }
        _ = ss.api.message_reply_default(msg);
        ss.api.message_free(msg);
    }
}

pub export fn sa_std_ssh_server_auth_accept(session_handle: ?*anyopaque) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const msg = ss.pending_msg orelse return ERR_INVALID;
    const rc = if (ss.pending_kind == 2 and ss.pending_state == 0)
        ss.api.auth_reply_pk_ok_simple(msg)
    else
        ss.api.auth_reply_success(msg, 0);
    ss.api.message_free(msg);
    ss.pending_msg = null;
    ss.pending_kind = 0;
    return if (rc == 0) OK else ERR_IO;
}

pub export fn sa_std_ssh_server_auth_deny(session_handle: ?*anyopaque) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const msg = ss.pending_msg orelse return ERR_INVALID;
    _ = ss.api.message_reply_default(msg);
    ss.api.message_free(msg);
    ss.pending_msg = null;
    ss.pending_kind = 0;
    return OK;
}

/// Pumps messages until a session channel open arrives and accepts it.
pub export fn sa_std_ssh_server_channel_accept(session_handle: ?*anyopaque, out_channel: ?*?*anyopaque) i32 {
    const slot = out_channel orelse return ERR_INVALID;
    slot.* = null;
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    while (true) {
        const msg = ss.api.message_get(ss.session) orelse return ERR_IO;
        const mtype = ss.api.message_get_type(msg);
        if (mtype == 2 and ss.api.message_subtype(msg) == 1) { // CHANNEL_OPEN / SESSION
            const channel = ss.api.channel_open_reply_accept(msg) orelse {
                ss.api.message_free(msg);
                return ERR_IO;
            };
            ss.api.message_free(msg);
            const out = ALLOC.create(ServerChannel) catch return ERR_NOMEM;
            out.* = .{ .api = ss.api, .channel = channel };
            slot.* = out;
            return OK;
        }
        _ = ss.api.message_reply_default(msg);
        ss.api.message_free(msg);
    }
}

/// Pumps channel requests until an exec or shell request arrives.
/// out_kind: 1 = exec (command in buffer handle), 2 = shell (empty).
pub export fn sa_std_ssh_server_channel_exec(session_handle: ?*anyopaque, out_kind: ?*u32, out_command: ?*u64) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    const kind_slot = out_kind orelse return ERR_INVALID;
    const cmd_slot = out_command orelse return ERR_INVALID;
    cmd_slot.* = 0;
    while (true) {
        const msg = ss.api.message_get(ss.session) orelse return ERR_IO;
        const mtype = ss.api.message_get_type(msg);
        if (mtype == 3) { // CHANNEL request
            const subtype = ss.api.message_subtype(msg);
            if (subtype == 2) { // EXEC
                if (ss.api.channel_request_reply_success(msg) != 0) {
                    ss.api.message_free(msg);
                    return ERR_IO;
                }
                const cmd = ss.api.channel_request_command(msg) orelse "";
                const buf = ALLOC.dupe(u8, std.mem.span(cmd)) catch return ERR_NOMEM;
                cmd_slot.* = registerBuffer(buf) catch return ERR_NOMEM;
                kind_slot.* = 1;
                ss.api.message_free(msg);
                return OK;
            }
            if (subtype == 3) { // SHELL
                if (ss.api.channel_request_reply_success(msg) != 0) {
                    ss.api.message_free(msg);
                    return ERR_IO;
                }
                kind_slot.* = 2;
                ss.api.message_free(msg);
                return OK;
            }
            // PTY / ENV / others: accept and keep pumping
            _ = ss.api.channel_request_reply_success(msg);
            ss.api.message_free(msg);
            continue;
        }
        _ = ss.api.message_reply_default(msg);
        ss.api.message_free(msg);
    }
}

fn serverChannelOf(handle: ?*anyopaque) ?*ServerChannel {
    const h = handle orelse return null;
    return @ptrCast(@alignCast(h));
}

pub export fn sa_std_ssh_channel_write(channel_handle: ?*anyopaque, stream: u32, data: ?[*]const u8, data_len: u64, out_written: ?*u64) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    const data_ptr = data orelse return ERR_INVALID;
    const slot = out_written orelse return ERR_INVALID;
    const bytes = data_ptr[0..@intCast(data_len)];
    var off: usize = 0;
    while (off < bytes.len) {
        const n = if (stream == 1)
            ch.api.channel_write_stderr(ch.channel, bytes[off..].ptr, @intCast(bytes.len - off))
        else
            ch.api.channel_write(ch.channel, bytes[off..].ptr, @intCast(bytes.len - off));
        if (n < 0) return ERR_IO;
        off += @intCast(n);
    }
    slot.* = off;
    return OK;
}

pub export fn sa_std_ssh_channel_read(channel_handle: ?*anyopaque, stream: u32, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    const buf = out orelse return ERR_INVALID;
    const slot = out_read orelse return ERR_INVALID;
    const n = ch.api.channel_read(ch.channel, buf, @intCast(@min(cap, std.math.maxInt(u32))), @intCast(stream));
    if (n == -127) { // SSH_EOF
        slot.* = 0;
        return OK;
    }
    if (n < 0) return ERR_IO;
    slot.* = @intCast(n);
    return OK;
}

pub export fn sa_std_ssh_channel_send_exit(channel_handle: ?*anyopaque, exit_code: i32) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    return if (ch.api.channel_exit_status(ch.channel, exit_code) == 0) OK else ERR_IO;
}

pub export fn sa_std_ssh_channel_close(channel_handle: ?*anyopaque) i32 {
    const ch = serverChannelOf(channel_handle) orelse return ERR_HANDLE;
    _ = ch.api.channel_send_eof(ch.channel);
    _ = ch.api.channel_close(ch.channel);
    ch.api.channel_free(ch.channel);
    ALLOC.destroy(ch);
    return OK;
}

pub export fn sa_std_ssh_server_session_close(session_handle: ?*anyopaque) i32 {
    const ss = serverSessionOf(session_handle) orelse return ERR_HANDLE;
    if (ss.pending_msg) |msg| ss.api.message_free(msg);
    ss.api.disconnect(ss.session);
    ss.api.free_session(ss.session);
    ALLOC.destroy(ss);
    return OK;
}

// ======================= loopback tests =======================
const testing = std.testing;

fn stackOrSkip() !bool {
    var flags: u32 = 0;
    _ = sa_std_ssh_supported(&flags);
    if (flags & 3 == 3) return true;
    // Hard-fail when the environment demands SSH coverage.
    if (std.c.getenv("SCI_REQUIRE_SSH")) |v| {
        if (v[0] == '1') return error.SshStackRequiredButMissing;
    }
    return false;
}

fn sh(cmd: []const u8) !void {
    const result = try sio.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sh", "-c", cmd },
        .max_output_bytes = 1024 * 1024,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.ShellFailed,
        else => return error.ShellFailed,
    }
}

fn freePort() !u16 {
    const rc = std.os.linux.socket(std.posix.AF.INET, std.os.linux.SOCK.STREAM | std.os.linux.SOCK.CLOEXEC, 0);
    if (@as(isize, @bitCast(rc)) < 0) return error.SocketFailed;
    const fd: i32 = @intCast(rc);
    defer lxClose(fd);
    var addr = std.posix.sockaddr.in{ .family = std.posix.AF.INET, .port = 0, .addr = @bitCast([4]u8{ 127, 0, 0, 1 }) };
    if (@as(isize, @bitCast(std.os.linux.bind(fd, @ptrCast(&addr), @sizeOf(std.posix.sockaddr.in)))) < 0) return error.BindFailed;
    var alen: std.posix.socklen_t = @sizeOf(std.posix.sockaddr.in);
    if (@as(isize, @bitCast(std.os.linux.getsockname(fd, @ptrCast(&addr), &alen))) < 0) return error.GetsocknameFailed;
    return std.mem.bigToNative(u16, addr.port);
}


var test_dir_counter = std.atomic.Value(u64).init(0);

fn makeTestDir(buf: []u8) ![]const u8 {
    const n = test_dir_counter.fetchAdd(1, .monotonic);
    const dir = try std.fmt.bufPrint(buf, "/tmp/sa_ssh_test_{d}_{d}", .{ std.os.linux.getpid(), n });
    var cmd_buf: [1024]u8 = undefined;
    const cmd = try std.fmt.bufPrint(&cmd_buf, "rm -rf {s} && mkdir -p {s}", .{ dir, dir });
    try sh(cmd);
    return dir;
}

fn removeTestDir(dir: []const u8) void {
    var cmd_buf: [1024]u8 = undefined;
    const cmd = std.fmt.bufPrint(&cmd_buf, "rm -rf {s}", .{dir}) catch return;
    sh(cmd) catch {};
}

fn bufferText(handle: u64) []const u8 {
    const p = sa_std_ssh_buffer_data(handle) orelse return "";
    return p[0..@intCast(sa_std_ssh_buffer_len(handle))];
}

test "ssh client vs system sshd: key auth, exec, sftp round trip" {
    if (!try stackOrSkip()) return;
    var dir_buf: [512]u8 = undefined;
    const dir = try makeTestDir(&dir_buf);
    defer removeTestDir(dir);

    var cmd_buf: [2048]u8 = undefined;
    const setup = try std.fmt.bufPrint(&cmd_buf,
        \\mkdir -p /run/sshd
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/hostkey
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/userkey
        \\cp {s}/userkey.pub {s}/authorized_keys
        \\chmod 600 {s}/authorized_keys
    , .{ dir, dir, dir, dir, dir });
    try sh(setup);

    const port = try freePort();
    var cfg_buf: [2048]u8 = undefined;
    const cfg = try std.fmt.bufPrint(&cfg_buf,
        \\Port {d}
        \\ListenAddress 127.0.0.1
        \\HostKey {s}/hostkey
        \\AuthorizedKeysFile {s}/authorized_keys
        \\PermitRootLogin yes
        \\PasswordAuthentication no
        \\PubkeyAuthentication yes
        \\StrictModes no
        \\UsePAM no
        \\Subsystem sftp internal-sftp
        \\PidFile {s}/sshd.pid
    , .{ port, dir, dir, dir });
    var cfgpath_buf: [1024]u8 = undefined;
    const cfgpath = try std.fmt.bufPrint(&cfgpath_buf, "{s}/sshd_config", .{dir});
    const cfg_file = try sio.cwd().createFile(cfgpath, .{});
    try cfg_file.writeAll(cfg);
    cfg_file.close();
    var start_buf: [1024]u8 = undefined;
    const start_cmd = try std.fmt.bufPrint(&start_buf, "/usr/sbin/sshd -f {s}", .{cfgpath});
    try sh(start_cmd);
    defer {
        var kill_buf: [1024]u8 = undefined;
        if (std.fmt.bufPrint(&kill_buf, "kill $(cat {s}/sshd.pid) 2>/dev/null; true", .{dir}) catch null) |c| sh(c) catch {};
    }

    // connect (retry briefly while sshd comes up)
    var session: ?*anyopaque = null;
    var attempt: usize = 0;
    while (attempt < 40) : (attempt += 1) {
        const host = "127.0.0.1";
        if (sa_std_ssh_client_connect(host.ptr, host.len, port, &session) == OK) break;
        _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = 100 * std.time.ns_per_ms }, null);
    }
    try testing.expect(session != null);
    defer _ = sa_std_ssh_session_close(session);

    var fp_buf: [128]u8 = undefined;
    var fp_len: u64 = 0;
    try testing.expectEqual(OK, sa_std_ssh_hostkey_fingerprint(session, &fp_buf, fp_buf.len, &fp_len));
    try testing.expect(fp_len > 20);

    var keypath_buf: [1024]u8 = undefined;
    const keypath = try std.fmt.bufPrint(&keypath_buf, "{s}/userkey", .{dir});
    const user = "root";
    try testing.expectEqual(OK, sa_std_ssh_auth_keyfile(session, user.ptr, user.len, null, 0, keypath.ptr, keypath.len, null, 0));

    const command = "echo hello-from-sshd";
    var so: u64 = 0;
    var se: u64 = 0;
    var exit_code: i32 = -1;
    try testing.expectEqual(OK, sa_std_ssh_exec(session, command.ptr, command.len, &so, &se, &exit_code));
    defer _ = sa_std_ssh_buffer_free(so);
    defer _ = sa_std_ssh_buffer_free(se);
    try testing.expectEqual(@as(i32, 0), exit_code);
    try testing.expectEqualStrings("hello-from-sshd\n", bufferText(so));

    // sftp write + read back
    var remote_buf: [1024]u8 = undefined;
    const remote = try std.fmt.bufPrint(&remote_buf, "{s}/via-sftp.txt", .{dir});
    const payload = "sftp-payload-123";
    try testing.expectEqual(OK, sa_std_ssh_sftp_write(session, remote.ptr, remote.len, payload.ptr, payload.len));
    var back: u64 = 0;
    try testing.expectEqual(OK, sa_std_ssh_sftp_read(session, remote.ptr, remote.len, &back));
    defer _ = sa_std_ssh_buffer_free(back);
    try testing.expectEqualStrings(payload, bufferText(back));
    var size: u64 = 0;
    var is_dir: u32 = 0;
    try testing.expectEqual(OK, sa_std_ssh_sftp_stat(session, remote.ptr, remote.len, &size, &is_dir));
    try testing.expectEqual(@as(u64, payload.len), size);
    try testing.expectEqual(@as(u32, 0), is_dir);
}

const ServerOutcome = struct {
    auth_user: [128]u8 = @splat(0),
    auth_user_len: usize = 0,
    command: [256]u8 = @splat(0),
    command_len: usize = 0,
    err: i32 = -999,
};

fn runTestServer(bind_handle: ?*anyopaque, expect_password: bool, outcome: *ServerOutcome) void {
    var session: ?*anyopaque = null;
    if (sa_std_ssh_server_accept(bind_handle, &session) != OK) {
        outcome.err = -1;
        return;
    }
    defer _ = sa_std_ssh_server_session_close(session);
    // auth pump: pubkey clients do query (state 0) then signed (state 1)
    var authed = false;
    var rounds: usize = 0;
    while (!authed and rounds < 4) : (rounds += 1) {
        var kind: u32 = 0;
        var user_h: u64 = 0;
        var secret_h: u64 = 0;
        var state: i32 = 0;
        if (sa_std_ssh_server_auth_next(session, &kind, &user_h, &secret_h, &state) != OK) {
            outcome.err = -2;
            return;
        }
        const user_text = bufferText(user_h);
        @memcpy(outcome.auth_user[0..user_text.len], user_text);
        outcome.auth_user_len = user_text.len;
        if (expect_password) {
            if (kind == 1 and std.mem.eql(u8, bufferText(secret_h), "s3cret")) {
                _ = sa_std_ssh_server_auth_accept(session);
                authed = true;
            } else {
                _ = sa_std_ssh_server_auth_deny(session);
            }
        } else {
            // pubkey: accept query (pk_ok) and the signed attempt
            _ = sa_std_ssh_server_auth_accept(session);
            if (kind == 2 and state == 1) authed = true;
            if (kind == 1) authed = true;
        }
        _ = sa_std_ssh_buffer_free(user_h);
        _ = sa_std_ssh_buffer_free(secret_h);
    }
    if (!authed) {
        outcome.err = -3;
        return;
    }
    var channel: ?*anyopaque = null;
    if (sa_std_ssh_server_channel_accept(session, &channel) != OK) {
        outcome.err = -4;
        return;
    }
    defer _ = sa_std_ssh_channel_close(channel);
    var kind: u32 = 0;
    var cmd_h: u64 = 0;
    if (sa_std_ssh_server_channel_exec(session, &kind, &cmd_h) != OK) {
        outcome.err = -5;
        return;
    }
    const cmd_text = bufferText(cmd_h);
    @memcpy(outcome.command[0..cmd_text.len], cmd_text);
    outcome.command_len = cmd_text.len;
    // build the greeting BEFORE freeing cmd_h (cmd_text borrows it)
    var greeting_buf: [320]u8 = undefined;
    const greeting = std.fmt.bufPrint(&greeting_buf, "pong:{s}", .{cmd_text}) catch "pong";
    _ = sa_std_ssh_buffer_free(cmd_h);
    var written: u64 = 0;
    _ = sa_std_ssh_channel_write(channel, 0, greeting.ptr, greeting.len, &written);
    // Pace the teardown like a real exec server (a real command takes
    // time between producing output and exiting): a data + exit + EOF
    // + CLOSE burst in one transport batch makes libssh2 clients drop
    // the payload (verified against libssh/libssh2 C probes).
    _ = std.os.linux.nanosleep(&.{ .sec = 0, .nsec = 150 * std.time.ns_per_ms }, null);
    _ = sa_std_ssh_channel_send_exit(channel, 3);
    outcome.err = 0;
}

test "ssh server vs system ssh client: pubkey auth + exec" {
    if (!try stackOrSkip()) return;
    var dir_buf: [512]u8 = undefined;
    const dir = try makeTestDir(&dir_buf);
    defer removeTestDir(dir);
    var cmd_buf: [2048]u8 = undefined;
    const setup = try std.fmt.bufPrint(&cmd_buf,
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/hostkey
        \\ssh-keygen -q -t ed25519 -N '' -f {s}/userkey
    , .{ dir, dir });
    try sh(setup);

    const port = try freePort();
    var hk_buf: [1024]u8 = undefined;
    const hk = try std.fmt.bufPrint(&hk_buf, "{s}/hostkey", .{dir});
    const addr = "127.0.0.1";
    var bind_handle: ?*anyopaque = null;
    try testing.expectEqual(OK, sa_std_ssh_server_listen(addr.ptr, addr.len, port, hk.ptr, hk.len, &bind_handle));
    defer _ = sa_std_ssh_server_bind_close(bind_handle);

    var outcome = ServerOutcome{};
    const thread = try std.Thread.spawn(.{}, runTestServer, .{ bind_handle, false, &outcome });
    defer thread.join();

    var ssh_buf: [2048]u8 = undefined;
    const ssh_cmd = try std.fmt.bufPrint(&ssh_buf, "ssh -i {s}/userkey -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p {d} root@127.0.0.1 'echo marker-cmd'", .{ dir, port });
    const result = try sio.Child.run(.{
        .allocator = testing.allocator,
        .argv = &.{ "sh", "-c", ssh_cmd },
        .max_output_bytes = 1024 * 1024,
    });
    defer testing.allocator.free(result.stdout);
    defer testing.allocator.free(result.stderr);
    try testing.expectEqual(@as(i32, 0), outcome.err);
    try testing.expectEqualStrings("echo marker-cmd", outcome.command[0..outcome.command_len]);
    try testing.expectEqualStrings("pong:echo marker-cmd", result.stdout);
    switch (result.term) {
        .exited => |code| try testing.expectEqual(@as(u32, 3), code),
        else => return error.BadTerm,
    }
}

test "ssh client+server: password auth + exec round trip" {
    if (!try stackOrSkip()) return;
    var dir_buf: [512]u8 = undefined;
    const dir = try makeTestDir(&dir_buf);
    defer removeTestDir(dir);
    var cmd_buf: [1024]u8 = undefined;
    const setup = try std.fmt.bufPrint(&cmd_buf, "ssh-keygen -q -t ed25519 -N '' -f {s}/hostkey", .{dir});
    try sh(setup);

    const port = try freePort();
    var hk_buf: [1024]u8 = undefined;
    const hk = try std.fmt.bufPrint(&hk_buf, "{s}/hostkey", .{dir});
    const addr = "127.0.0.1";
    var bind_handle: ?*anyopaque = null;
    try testing.expectEqual(OK, sa_std_ssh_server_listen(addr.ptr, addr.len, port, hk.ptr, hk.len, &bind_handle));
    defer _ = sa_std_ssh_server_bind_close(bind_handle);

    var outcome = ServerOutcome{};
    const thread = try std.Thread.spawn(.{}, runTestServer, .{ bind_handle, true, &outcome });
    defer thread.join();

    var session: ?*anyopaque = null;
    try testing.expectEqual(OK, sa_std_ssh_client_connect(addr.ptr, addr.len, port, &session));
    defer _ = sa_std_ssh_session_close(session);
    const user = "alice";
    const pass = "s3cret";
    try testing.expectEqual(OK, sa_std_ssh_auth_password(session, user.ptr, user.len, pass.ptr, pass.len));
    const command = "ping";
    var so: u64 = 0;
    var se: u64 = 0;
    var exit_code: i32 = -1;
    try testing.expectEqual(OK, sa_std_ssh_exec(session, command.ptr, command.len, &so, &se, &exit_code));
    defer _ = sa_std_ssh_buffer_free(so);
    defer _ = sa_std_ssh_buffer_free(se);
    try testing.expectEqual(@as(i32, 0), outcome.err);
    try testing.expectEqualStrings("alice", outcome.auth_user[0..outcome.auth_user_len]);
    try testing.expectEqualStrings("pong:ping", bufferText(so));
    try testing.expectEqual(@as(i32, 3), exit_code);
}


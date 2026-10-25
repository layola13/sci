//! sa_std PTY (P0-2): pseudo-terminal sessions for terminal surfaces
//! (CXU terminalPty). Linux only in this phase.
//!
//! Model: sa_pty_spawn opens a pty pair (openpty), forks, and execs the
//! program in the child with the slave as its controlling terminal on
//! stdin/stdout/stderr. The caller owns the master side through an
//! opaque u64 handle: poll/read/write, resize, kill, try_wait, close.
//! Read/write are blocking; use sa_pty_poll for event-driven loops.
//! When the child exits and the slave side is gone, reads report EOF
//! (Linux raises EIO on the master, surfaced as a zero-length read).
//! try_wait status: the exit code, or 128 + signal when signalled.
//! An exec failure in the child surfaces as exit code 127.
//! Spawning goes through the 16_policy run gate (same as process spawn).
//! Status codes mirror sa_std.zig (0 ok, 1 invalid argument, 2 invalid
//! handle, 5 no memory, 6 io, 8 unsupported, 10 permission denied).

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const sa_std_root = @import("sa_std.zig");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_PERMISSION: i32 = 10;

const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

const TIOCSCTTY: c_ulong = 0x540E;
const TIOCGWINSZ: c_ulong = 0x5413;
const TIOCSWINSZ: c_ulong = 0x5414;

extern "c" fn openpty(master: *c_int, slave: *c_int, name: ?[*]u8, termp: ?*const anyopaque, winp: ?*const Winsize) c_int;
extern "c" fn fork() c_int;
extern "c" fn setsid() c_int;
extern "c" fn execvp(file: [*:0]const u8, argv: [*:null]const ?[*:0]const u8) c_int;
extern "c" fn dup2(old_fd: c_int, new_fd: c_int) c_int;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn ioctl(fd: c_int, request: c_ulong, ...) c_int;
extern "c" fn kill(pid: c_int, sig: c_int) c_int;
extern "c" fn _exit(status: c_int) noreturn;

pub const PtyArgvEntry = extern struct {
    ptr: ?[*]const u8,
    len: u64,
};

const Pty = struct {
    master_fd: c_int,
    pid: c_int,
};

var ptys_mu = std.Io.Mutex.init;
var ptys_map: std.AutoHashMapUnmanaged(u64, *Pty) = .empty;
var ptys_next: u64 = 1;

fn registerPty(pty: *Pty) !u64 {
    ptys_mu.lockUncancelable(sio.io());
    defer ptys_mu.unlock(sio.io());
    const h = ptys_next;
    ptys_next += 1;
    try ptys_map.put(std.heap.page_allocator, h, pty);
    return h;
}

fn getPty(handle: u64) ?*Pty {
    ptys_mu.lockUncancelable(sio.io());
    defer ptys_mu.unlock(sio.io());
    return ptys_map.get(handle);
}

fn removePty(handle: u64) ?*Pty {
    ptys_mu.lockUncancelable(sio.io());
    defer ptys_mu.unlock(sio.io());
    const kv = ptys_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

fn dupeZ(alloc: std.mem.Allocator, slice: []const u8) ![:0]u8 {
    const buf = try alloc.allocSentinel(u8, slice.len, 0);
    @memcpy(buf[0..slice.len], slice);
    return buf;
}

pub export fn sa_pty_spawn(file_ptr: ?[*]const u8, file_len: u64, argv_ptr: ?[*]const PtyArgvEntry, argv_len: u64, cols: u16, rows: u16, out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const file_p = file_ptr orelse return ERR_INVALID;
    if (file_len == 0) return ERR_INVALID;
    const file = file_p[0..@intCast(file_len)];
    const argv_entries = argv_ptr orelse return ERR_INVALID;
    if (argv_len == 0) return ERR_INVALID;
    const entries = argv_entries[0..@intCast(argv_len)];
    for (entries) |e| {
        if (e.ptr == null) return ERR_INVALID;
    }
    if (!sa_std_root.saStdPolicyAllowsRun(file)) return ERR_PERMISSION;

    const alloc = std.heap.page_allocator;
    // Build the child's argv (NUL-terminated copies) before forking.
    const file_z = dupeZ(alloc, file) catch return ERR_NOMEM;
    defer alloc.free(file_z);
    const args_z = alloc.allocSentinel(?[*:0]const u8, entries.len, null) catch return ERR_NOMEM;
    defer alloc.free(args_z);
    var arg_slices = alloc.alloc([:0]u8, entries.len) catch return ERR_NOMEM;
    defer alloc.free(arg_slices);
    var made: usize = 0;
    defer {
        for (arg_slices[0..made]) |s| alloc.free(s);
    }
    for (entries, 0..) |e, i| {
        const s = e.ptr.?[0..@intCast(e.len)];
        arg_slices[i] = dupeZ(alloc, s) catch return ERR_NOMEM;
        made += 1;
        args_z[i] = arg_slices[i].ptr;
    }

    var master: c_int = -1;
    var slave: c_int = -1;
    const ws = Winsize{ .ws_row = rows, .ws_col = cols, .ws_xpixel = 0, .ws_ypixel = 0 };
    if (openpty(&master, &slave, null, null, &ws) != 0) return ERR_IO;

    const pid = fork();
    if (pid < 0) {
        _ = close(master);
        _ = close(slave);
        return ERR_IO;
    }
    if (pid == 0) {
        // Child: new session, slave as controlling terminal on 0/1/2.
        _ = close(master);
        _ = setsid();
        _ = dup2(slave, 0);
        _ = dup2(slave, 1);
        _ = dup2(slave, 2);
        if (slave > 2) _ = close(slave);
        _ = ioctl(0, TIOCSCTTY, @as(c_int, 0));
        _ = execvp(file_z.ptr, args_z.ptr);
        _exit(127);
    }
    // Parent keeps only the master side.
    _ = close(slave);
    const pty = alloc.create(Pty) catch {
        _ = close(master);
        return ERR_NOMEM;
    };
    pty.* = .{ .master_fd = master, .pid = pid };
    const handle = registerPty(pty) catch {
        _ = close(master);
        alloc.destroy(pty);
        return ERR_NOMEM;
    };
    out.* = handle;
    return OK;
}

pub export fn sa_pty_read(handle: u64, buf_ptr: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    const out = out_read orelse return ERR_INVALID;
    out.* = 0;
    const buf = buf_ptr orelse return ERR_INVALID;
    const pty = getPty(handle) orelse return ERR_HANDLE;
    const rc = std.os.linux.read(pty.master_fd, buf, @intCast(cap));
    const err = std.os.linux.errno(rc);
    if (err == .SUCCESS) {
        out.* = @intCast(rc);
        return OK;
    }
    if (err == .IO) {
        // Linux: master read after the slave side vanished -> EIO = EOF.
        out.* = 0;
        return OK;
    }
    if (err == .INTR) return OK; // zero bytes; caller retries via poll
    return ERR_IO;
}

pub export fn sa_pty_write(handle: u64, buf_ptr: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    const out = out_written orelse return ERR_INVALID;
    out.* = 0;
    const buf = buf_ptr orelse return ERR_INVALID;
    const pty = getPty(handle) orelse return ERR_HANDLE;
    var written: usize = 0;
    const total: usize = @intCast(len);
    while (written < total) {
        const rc = std.os.linux.write(pty.master_fd, buf + written, total - written);
        const err = std.os.linux.errno(rc);
        if (err == .SUCCESS) {
            written += rc;
            continue;
        }
        if (err == .INTR) continue;
        out.* = @intCast(written);
        return ERR_IO;
    }
    out.* = @intCast(written);
    return OK;
}

pub export fn sa_pty_poll(handle: u64, timeout_ms: i32, out_events: ?*u32) i32 {
    const out = out_events orelse return ERR_INVALID;
    out.* = 0;
    const pty = getPty(handle) orelse return ERR_HANDLE;
    var fds = [1]std.os.linux.pollfd{.{ .fd = pty.master_fd, .events = std.os.linux.POLL.IN, .revents = 0 }};
    const rc = std.os.linux.poll(&fds, 1, timeout_ms);
    const err = std.os.linux.errno(rc);
    if (err != .SUCCESS) {
        if (err == .INTR) return OK;
        return ERR_IO;
    }
    const rev = fds[0].revents;
    var events: u32 = 0;
    if (rev & std.os.linux.POLL.IN != 0) events |= 1;
    if (rev & (std.os.linux.POLL.HUP | std.os.linux.POLL.ERR) != 0) events |= 2;
    out.* = events;
    return OK;
}

pub export fn sa_pty_resize(handle: u64, cols: u16, rows: u16) i32 {
    const pty = getPty(handle) orelse return ERR_HANDLE;
    var ws = Winsize{ .ws_row = rows, .ws_col = cols, .ws_xpixel = 0, .ws_ypixel = 0 };
    if (ioctl(pty.master_fd, TIOCSWINSZ, &ws) != 0) return ERR_IO;
    return OK;
}

pub export fn sa_pty_winsize(handle: u64, out_cols: ?*u16, out_rows: ?*u16) i32 {
    const c_out = out_cols orelse return ERR_INVALID;
    const r_out = out_rows orelse return ERR_INVALID;
    const pty = getPty(handle) orelse return ERR_HANDLE;
    var ws = Winsize{ .ws_row = 0, .ws_col = 0, .ws_xpixel = 0, .ws_ypixel = 0 };
    if (ioctl(pty.master_fd, TIOCGWINSZ, &ws) != 0) return ERR_IO;
    c_out.* = ws.ws_col;
    r_out.* = ws.ws_row;
    return OK;
}

pub export fn sa_pty_pid(handle: u64, out_pid: ?*i32) i32 {
    const out = out_pid orelse return ERR_INVALID;
    out.* = 0;
    const pty = getPty(handle) orelse return ERR_HANDLE;
    out.* = pty.pid;
    return OK;
}

pub export fn sa_pty_kill(handle: u64, sig: u32) i32 {
    const pty = getPty(handle) orelse return ERR_HANDLE;
    if (kill(pty.pid, @intCast(sig)) != 0) return ERR_IO;
    return OK;
}

pub export fn sa_pty_try_wait(handle: u64, out_done: ?*u32, out_status: ?*i32) i32 {
    const done_out = out_done orelse return ERR_INVALID;
    const status_out = out_status orelse return ERR_INVALID;
    done_out.* = 0;
    status_out.* = 0;
    const pty = getPty(handle) orelse return ERR_HANDLE;
    var status: i32 = 0;
    const rc = std.os.linux.waitpid(pty.pid, &status, std.os.linux.W.NOHANG);
    if (rc == 0) return OK; // still running
    if (std.os.linux.errno(rc) != .SUCCESS) return ERR_IO;
    done_out.* = 1;
    const st: u32 = @bitCast(status);
    if (std.os.linux.W.IFEXITED(st)) {
        status_out.* = @intCast(std.os.linux.W.EXITSTATUS(st));
    } else if (std.os.linux.W.IFSIGNALED(st)) {
        const sig_num: i32 = @intCast(@intFromEnum(std.os.linux.W.TERMSIG(st)));
        status_out.* = 128 + sig_num;
    } else {
        status_out.* = status;
    }
    return OK;
}

pub export fn sa_pty_close(handle: u64) i32 {
    const pty = removePty(handle) orelse return ERR_HANDLE;
    _ = close(pty.master_fd);
    std.heap.page_allocator.destroy(pty);
    return OK;
}

// ---------------- tests ----------------

fn spawnArgv(file: []const u8, args: []const []const u8, cols: u16, rows: u16) !u64 {
    var entries_buf: [8]PtyArgvEntry = undefined;
    entries_buf[0] = .{ .ptr = file.ptr, .len = file.len };
    for (args, 0..) |a, i| entries_buf[i + 1] = .{ .ptr = a.ptr, .len = a.len };
    var handle: u64 = 0;
    const rc = sa_pty_spawn(file.ptr, file.len, &entries_buf, @intCast(args.len + 1), cols, rows, &handle);
    if (rc != OK) return error.SpawnFailed;
    return handle;
}

fn readUntilContains(handle: u64, needle: []const u8, acc: *std.array_list.Managed(u8)) !bool {
    var buf: [512]u8 = undefined;
    var rounds: usize = 0;
    while (rounds < 200) : (rounds += 1) {
        if (std.mem.indexOf(u8, acc.items, needle) != null) return true;
        var events: u32 = 0;
        if (sa_pty_poll(handle, 100, &events) != OK) return error.PollFailed;
        if (events & 1 != 0) {
            var n: u64 = 0;
            if (sa_pty_read(handle, &buf, buf.len, &n) != OK) return error.ReadFailed;
            if (n == 0) break;
            try acc.appendSlice(buf[0..@intCast(n)]);
        }
        if (events & 2 != 0) {
            var n: u64 = 0;
            if (sa_pty_read(handle, &buf, buf.len, &n) == OK and n > 0) {
                try acc.appendSlice(buf[0..@intCast(n)]);
                continue;
            }
            break;
        }
    }
    return std.mem.indexOf(u8, acc.items, needle) != null;
}

fn waitDone(handle: u64) !i32 {
    var rounds: usize = 0;
    while (rounds < 200) : (rounds += 1) {
        var done: u32 = 0;
        var status: i32 = 0;
        if (sa_pty_try_wait(handle, &done, &status) != OK) return error.WaitFailed;
        if (done == 1) return status;
        var events: u32 = 0;
        _ = sa_pty_poll(handle, 50, &events);
    }
    return error.WaitTimeout;
}

test "pty: echo output is read back and exit status is 0" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const alloc = std.testing.allocator;
    const handle = try spawnArgv("/bin/echo", &.{"pty-hello"}, 80, 24);
    defer _ = sa_pty_close(handle);
    var acc = std.array_list.Managed(u8).init(alloc);
    defer acc.deinit();
    try std.testing.expect(try readUntilContains(handle, "pty-hello", &acc));
    try std.testing.expectEqual(@as(i32, 0), try waitDone(handle));
}

test "pty: winsize applies at spawn and on resize; stty reports it" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const alloc = std.testing.allocator;
    const handle = try spawnArgv("/bin/sh", &.{ "-c", "stty size" }, 111, 33);
    defer _ = sa_pty_close(handle);
    var acc = std.array_list.Managed(u8).init(alloc);
    defer acc.deinit();
    try std.testing.expect(try readUntilContains(handle, "33 111", &acc));
    try std.testing.expectEqual(@as(i32, 0), try waitDone(handle));

    const cat = try spawnArgv("/bin/cat", &.{}, 80, 24);
    defer _ = sa_pty_close(cat);
    try std.testing.expectEqual(OK, sa_pty_resize(cat, 111, 33));
    var cols: u16 = 0;
    var rows: u16 = 0;
    try std.testing.expectEqual(OK, sa_pty_winsize(cat, &cols, &rows));
    try std.testing.expectEqual(@as(u16, 111), cols);
    try std.testing.expectEqual(@as(u16, 33), rows);
    // cat echoes input back through the pty (line discipline + cat).
    var written: u64 = 0;
    try std.testing.expectEqual(OK, sa_pty_write(cat, "hello\n".ptr, 6, &written));
    var acc2 = std.array_list.Managed(u8).init(alloc);
    defer acc2.deinit();
    try std.testing.expect(try readUntilContains(cat, "hello", &acc2));
    try std.testing.expectEqual(OK, sa_pty_kill(cat, 9));
    try std.testing.expectEqual(@as(i32, 137), try waitDone(cat));
}

test "pty: exec failure surfaces as exit 127" {
    if (comptime builtin.os.tag != .linux) return error.SkipZigTest;
    const handle = try spawnArgv("/nonexistent/definitely-missing", &.{}, 80, 24);
    defer _ = sa_pty_close(handle);
    try std.testing.expectEqual(@as(i32, 127), try waitDone(handle));
}

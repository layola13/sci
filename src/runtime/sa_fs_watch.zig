//! sa_std fs watch (P0-3): directory/file change notification for the
//! CXU fs.watch surface. Linux inotify in this phase.
//!
//! Model: sa_fs_watch_create makes a nonblocking inotify instance;
//! sa_fs_watch_add registers a path with a raw inotify mask;
//! sa_fs_watch_next serves parsed events one at a time from an
//! internal buffer (wd, mask, cookie, name), with out_ready = 0 when
//! no complete event is pending. Combine with sa_fs_watch_poll for
//! event-loop integration. Watching a path is a read-side acquisition,
//! so add goes through the 16_policy fs gate (read).
//! Status codes mirror sa_std.zig (0 ok, 1 invalid argument, 2 invalid
//! handle, 5 no memory, 6 io, 9 truncated, 10 permission denied).

const std = @import("std");
const sio = @import("sio");
const sa_std_root = @import("sa_std.zig");

const OK: i32 = 0;
const ERR_INVALID: i32 = 1;
const ERR_HANDLE: i32 = 2;
const ERR_NOMEM: i32 = 5;
const ERR_IO: i32 = 6;
const ERR_TRUNCATED: i32 = 9;
const ERR_PERMISSION: i32 = 10;

const EVENT_HDR: usize = 16; // wd i32, mask u32, cookie u32, len u32
const BUF_CAP: usize = 8192;

const Watcher = struct {
    fd: i32,
    buf: [BUF_CAP]u8 = undefined,
    start: usize = 0,
    end: usize = 0,
};

var watchers_mu = std.Io.Mutex.init;
var watchers_map: std.AutoHashMapUnmanaged(u64, *Watcher) = .empty;
var watchers_next: u64 = 1;

fn register(w: *Watcher) !u64 {
    watchers_mu.lockUncancelable(sio.io());
    defer watchers_mu.unlock(sio.io());
    const h = watchers_next;
    watchers_next += 1;
    try watchers_map.put(std.heap.page_allocator, h, w);
    return h;
}

fn getWatcher(handle: u64) ?*Watcher {
    watchers_mu.lockUncancelable(sio.io());
    defer watchers_mu.unlock(sio.io());
    return watchers_map.get(handle);
}

fn removeWatcher(handle: u64) ?*Watcher {
    watchers_mu.lockUncancelable(sio.io());
    defer watchers_mu.unlock(sio.io());
    const kv = watchers_map.fetchRemove(handle) orelse return null;
    return kv.value;
}

pub export fn sa_fs_watch_create(out_handle: ?*u64) i32 {
    const out = out_handle orelse return ERR_INVALID;
    out.* = 0;
    const rc = std.os.linux.inotify_init1(std.os.linux.IN.CLOEXEC | std.os.linux.IN.NONBLOCK);
    if (std.os.linux.errno(rc) != .SUCCESS) return ERR_IO;
    const alloc = std.heap.page_allocator;
    const w = alloc.create(Watcher) catch return ERR_NOMEM;
    w.* = .{ .fd = @intCast(rc) };
    const handle = register(w) catch {
        _ = std.os.linux.close(w.fd);
        alloc.destroy(w);
        return ERR_NOMEM;
    };
    out.* = handle;
    return OK;
}

pub export fn sa_fs_watch_add(handle: u64, path_ptr: ?[*]const u8, path_len: u64, mask: u32, out_wd: ?*i32) i32 {
    const out = out_wd orelse return ERR_INVALID;
    out.* = -1;
    const pp = path_ptr orelse return ERR_INVALID;
    if (path_len == 0) return ERR_INVALID;
    const path = pp[0..@intCast(path_len)];
    const w = getWatcher(handle) orelse return ERR_HANDLE;
    if (!sa_std_root.saStdPolicyAllowsFsRead(path)) return ERR_PERMISSION;
    const alloc = std.heap.page_allocator;
    const path_z = alloc.allocSentinel(u8, path.len, 0) catch return ERR_NOMEM;
    defer alloc.free(path_z);
    @memcpy(path_z[0..path.len], path);
    const rc = std.os.linux.inotify_add_watch(w.fd, path_z.ptr, mask);
    if (std.os.linux.errno(rc) != .SUCCESS) return ERR_IO;
    out.* = @intCast(rc);
    return OK;
}

pub export fn sa_fs_watch_remove(handle: u64, wd: i32) i32 {
    const w = getWatcher(handle) orelse return ERR_HANDLE;
    const rc = std.os.linux.inotify_rm_watch(w.fd, wd);
    if (std.os.linux.errno(rc) != .SUCCESS) return ERR_IO;
    return OK;
}

pub export fn sa_fs_watch_poll(handle: u64, timeout_ms: i32, out_pending: ?*u32) i32 {
    const out = out_pending orelse return ERR_INVALID;
    out.* = 0;
    const w = getWatcher(handle) orelse return ERR_HANDLE;
    if (w.end > w.start) {
        out.* = 1;
        return OK;
    }
    var fds = [1]std.os.linux.pollfd{.{ .fd = w.fd, .events = std.os.linux.POLL.IN, .revents = 0 }};
    const rc = std.os.linux.poll(&fds, 1, timeout_ms);
    const err = std.os.linux.errno(rc);
    if (err != .SUCCESS) {
        if (err == .INTR) return OK;
        return ERR_IO;
    }
    out.* = if (rc > 0 and fds[0].revents & std.os.linux.POLL.IN != 0) 1 else 0;
    return OK;
}

/// Compacts and refills the event buffer. Returns the number of new
/// bytes read (0 = would block, nothing available right now).
fn fill(w: *Watcher) !usize {
    if (w.start > 0) {
        const remaining = w.end - w.start;
        if (remaining > 0) std.mem.copyForwards(u8, w.buf[0..remaining], w.buf[w.start..w.end]);
        w.start = 0;
        w.end = remaining;
    }
    if (w.end == BUF_CAP) return 0; // full of one huge event; serve it first
    const rc = std.os.linux.read(w.fd, w.buf[w.end..BUF_CAP].ptr, BUF_CAP - w.end);
    const err = std.os.linux.errno(rc);
    if (err == .SUCCESS) {
        w.end += rc;
        return rc;
    }
    if (err == .AGAIN) return 0;
    if (err == .INTR) return 0;
    return error.IoError;
}

pub export fn sa_fs_watch_next(handle: u64, out_ready: ?*u32, out_wd: ?*i32, out_mask: ?*u32, out_cookie: ?*u32, name_ptr: ?[*]u8, name_cap: u64, out_name_len: ?*u64) i32 {
    const ready_out = out_ready orelse return ERR_INVALID;
    const wd_out = out_wd orelse return ERR_INVALID;
    const mask_out = out_mask orelse return ERR_INVALID;
    const cookie_out = out_cookie orelse return ERR_INVALID;
    const name_len_out = out_name_len orelse return ERR_INVALID;
    ready_out.* = 0;
    wd_out.* = -1;
    mask_out.* = 0;
    cookie_out.* = 0;
    name_len_out.* = 0;
    const w = getWatcher(handle) orelse return ERR_HANDLE;

    var attempts: usize = 0;
    while (attempts < 4) : (attempts += 1) {
        const avail = w.end - w.start;
        if (avail >= EVENT_HDR) {
            const hdr = w.buf[w.start..][0..EVENT_HDR];
            const name_len: usize = @intCast(std.mem.readInt(u32, hdr[12..16], .little));
            const ev_total = EVENT_HDR + name_len;
            if (avail >= ev_total) {
                const wd: i32 = std.mem.readInt(i32, hdr[0..4], .little);
                const ev_mask: u32 = std.mem.readInt(u32, hdr[4..8], .little);
                const cookie: u32 = std.mem.readInt(u32, hdr[8..12], .little);
                if (name_len > 0) {
                    const nb = name_ptr orelse return ERR_INVALID;
                    // The kernel NUL-pads names; report the true length.
                    var true_len: usize = name_len;
                    while (true_len > 0 and w.buf[w.start + EVENT_HDR + true_len - 1] == 0) true_len -= 1;
                    if (true_len > name_cap) return ERR_TRUNCATED;
                    @memcpy(nb[0..true_len], w.buf[w.start + EVENT_HDR ..][0..true_len]);
                    name_len_out.* = @intCast(true_len);
                }
                w.start += ev_total;
                if (w.start == w.end) {
                    w.start = 0;
                    w.end = 0;
                }
                wd_out.* = wd;
                mask_out.* = ev_mask;
                cookie_out.* = cookie;
                ready_out.* = 1;
                return OK;
            }
        }
        const got = fill(w) catch return ERR_IO;
        if (got == 0) return OK; // nothing more available; ready stays 0
    }
    return OK;
}

pub export fn sa_fs_watch_close(handle: u64) i32 {
    const w = removeWatcher(handle) orelse return ERR_HANDLE;
    _ = std.os.linux.close(w.fd);
    std.heap.page_allocator.destroy(w);
    return OK;
}

// ---------------- tests ----------------

const IN_CREATE: u32 = 0x0000_0100;
const IN_MODIFY: u32 = 0x0000_0002;
const IN_DELETE: u32 = 0x0000_0200;
const IN_CLOSE_WRITE: u32 = 0x0000_0008;

fn waitForEvent(handle: u64, want_mask: u32, want_name: []const u8) !bool {
    var rounds: usize = 0;
    while (rounds < 300) : (rounds += 1) {
        var pending: u32 = 0;
        if (sa_fs_watch_poll(handle, 50, &pending) != OK) return error.PollFailed;
        var ready: u32 = 0;
        var wd: i32 = -1;
        var mask: u32 = 0;
        var cookie: u32 = 0;
        var name_buf: [256]u8 = undefined;
        var name_len: u64 = 0;
        const rc = sa_fs_watch_next(handle, &ready, &wd, &mask, &cookie, &name_buf, name_buf.len, &name_len);
        if (rc != OK) return error.NextFailed;
        if (ready == 1) {
            if (mask & want_mask != 0 and std.mem.eql(u8, name_buf[0..@intCast(name_len)], want_name)) return true;
            continue;
        }
    }
    return false;
}

fn writeText(dir: std.Io.Dir, path: []const u8, data: []const u8) !void {
    var f = try dir.createFile(std.testing.io, path, .{ .truncate = true });
    defer f.close(std.testing.io);
    var wbuf: [256]u8 = undefined;
    var w = f.writer(std.testing.io, &wbuf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

test "fs watch: create/modify/delete events on a directory" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}", .{&tmp.sub_path});
    defer alloc.free(dir_path);

    var handle: u64 = 0;
    try std.testing.expectEqual(OK, sa_fs_watch_create(&handle));
    defer _ = sa_fs_watch_close(handle);
    var wd: i32 = -1;
    try std.testing.expectEqual(OK, sa_fs_watch_add(handle, dir_path.ptr, dir_path.len, IN_CREATE | IN_MODIFY | IN_DELETE | IN_CLOSE_WRITE, &wd));
    try std.testing.expect(wd >= 0);

    {
        var f = try tmp.dir.createFile(std.testing.io, "a.txt", .{});
        f.close(std.testing.io);
    }
    try std.testing.expect(try waitForEvent(handle, IN_CREATE, "a.txt"));

    try writeText(tmp.dir, "a.txt", "hello");
    try std.testing.expect(try waitForEvent(handle, IN_CLOSE_WRITE, "a.txt"));

    try tmp.dir.deleteFile(std.testing.io, "a.txt");
    try std.testing.expect(try waitForEvent(handle, IN_DELETE, "a.txt"));

    try std.testing.expectEqual(OK, sa_fs_watch_remove(handle, wd));
}

test "fs watch: file watch events carry an empty name; closed handle errors" {
    const alloc = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const file_path = try std.fmt.allocPrint(alloc, ".zig-cache/tmp/{s}/b.txt", .{&tmp.sub_path});
    defer alloc.free(file_path);
    {
        var f = try tmp.dir.createFile(std.testing.io, "b.txt", .{});
        f.close(std.testing.io);
    }

    var handle: u64 = 0;
    try std.testing.expectEqual(OK, sa_fs_watch_create(&handle));
    var wd: i32 = -1;
    try std.testing.expectEqual(OK, sa_fs_watch_add(handle, file_path.ptr, file_path.len, IN_MODIFY | IN_CLOSE_WRITE, &wd));

    try writeText(tmp.dir, "b.txt", "x");
    try std.testing.expect(try waitForEvent(handle, IN_CLOSE_WRITE, ""));

    try std.testing.expectEqual(OK, sa_fs_watch_close(handle));
    var ready: u32 = 0;
    var dummy_i: i32 = 0;
    var dummy_u: u32 = 0;
    var dummy_len: u64 = 0;
    var name_buf: [16]u8 = undefined;
    try std.testing.expectEqual(ERR_HANDLE, sa_fs_watch_next(handle, &ready, &dummy_i, &dummy_u, &dummy_u, &name_buf, name_buf.len, &dummy_len));
}

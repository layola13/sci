const std = @import("std");
const sa_std = @import("../sa_std.zig");
const ProcessOutputStream = @import("../sa_std.zig").ProcessOutputStream;
const SA_STD_ERR_INVALID_HANDLE = @import("consts.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_TRUNCATED = @import("consts.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNSUPPORTED = @import("consts.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("consts.zig").SA_STD_OK;
const builtin = @import("../sa_std.zig").builtin;
const finish = @import("../sa_std.zig").finish;
const finishChownErrno = @import("../sa_std.zig").finishChownErrno;
const finishErr = @import("../sa_std.zig").finishErr;
const finishErrnoAny = @import("../sa_std.zig").finishErrnoAny;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const groupId = @import("../sa_std.zig").groupId;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const libc = @import("../sa_std.zig").libc;
const lxMkdirat = @import("../sa_std.zig").lxMkdirat;
const mutBytes = @import("../sa_std.zig").mutBytes;
const pathBytes = @import("../sa_std.zig").pathBytes;
const registerResource = @import("../sa_std.zig").registerResource;
const sio = @import("../sa_std.zig").sio;

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

pub fn writeFormattedInto(out: ?[*]u8, out_cap: u64, out_len: ?*u64, text: []const u8) i32 {
    if (out_len) |ptr| ptr.* = @as(u64, @intCast(text.len));
    if (out_cap == 0) return finish(SA_STD_OK);
    const buffer = mutBytes(out, out_cap) catch |err| return finishErr(err);
    if (buffer.len < text.len) return finish(SA_STD_ERR_TRUNCATED);
    if (text.len != 0) @memcpy(buffer[0..text.len], text);
    return finish(SA_STD_OK);
}

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

pub fn readProcessOutput(handle: u64, stream: ProcessOutputStream, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
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

pub fn chownId(value: u32, enabled: u32) std.c.uid_t {
    return if (enabled != 0) @as(std.c.uid_t, @intCast(value)) else ~@as(std.c.uid_t, 0);
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

pub fn writeIpv6SegmentsNative(out: []u8, octets: *const [16]u8) void {
    var index: usize = 0;
    while (index < 8) : (index += 1) {
        const seg = std.mem.readInt(u16, octets[index * 2 ..][0..2], .big);
        // Match SA `store ... as u16` host layout (x86_64 little-endian tests).
        std.mem.writeInt(u16, out[index * 2 ..][0..2], seg, .little);
    }
}

pub fn readIpv6SegmentsNative(raw: *const [16]u8) [8]u16 {
    var segments: [8]u16 = undefined;
    var i: usize = 0;
    while (i < 8) : (i += 1) {
        segments[i] = std.mem.readInt(u16, raw[i * 2 ..][0..2], .little);
    }
    return segments;
}

// Unix domain socket support. Streams and listeners reuse the existing
// tcp_stream / tcp_listener resource kinds so read/write/peek/shutdown/close
// and accept all flow through the same sa_std_net_tcp_* paths.
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

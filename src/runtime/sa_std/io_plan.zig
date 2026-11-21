const std = @import("std");
const sa_std = @import("../sa_std.zig");
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SA_STD_STDERR = @import("../sa_std.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("../sa_std.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("../sa_std.zig").SA_STD_STDOUT;
const builtin = @import("../sa_std.zig").builtin;
const constBytes = @import("../sa_std.zig").constBytes;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const libc = @import("../sa_std.zig").libc;
const libcUsize = @import("../sa_std.zig").libcUsize;
const lockRegistry = @import("../sa_std.zig").lockRegistry;
const lxCheck = @import("../sa_std.zig").lxCheck;
const lxWrite = @import("../sa_std.zig").lxWrite;
const mutBytes = @import("../sa_std.zig").mutBytes;
const sio = @import("../sa_std.zig").sio;

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

const IoPlan = union(enum) {
    fd: std.posix.fd_t,
    file_fd: std.posix.fd_t,
    std_in,
    std_out,
    std_err,
    locked,
    invalid,
};

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

pub fn readHandle(handle: u64, buffer: []u8) !usize {
    lockRegistry();
    switch (ioPlanLocked(handle, false)) {
        .fd, .file_fd => |fd| {
            sa_std.registry_mutex.unlock();
            return lxRead(fd, buffer);
        },
        .std_in => {
            sa_std.registry_mutex.unlock();
            return sio.getStdIn().read(buffer);
        },
        .locked => {
            defer sa_std.registry_mutex.unlock();
            return readHandleLocked(handle, buffer);
        },
        .invalid => {
            sa_std.registry_mutex.unlock();
            return error.InvalidHandle;
        },
        .std_out, .std_err => unreachable,
    }
}

pub fn writeHandle(handle: u64, data: []const u8) !usize {
    lockRegistry();
    switch (ioPlanLocked(handle, true)) {
        .fd => |fd| {
            sa_std.registry_mutex.unlock();
            return lxWrite(fd, data);
        },
        .file_fd => |fd| {
            sa_std.registry_mutex.unlock();
            var off: usize = 0;
            while (off < data.len) {
                const n = try lxWrite(fd, data[off..]);
                if (n == 0) return error.Io;
                off += n;
            }
            return data.len;
        },
        .std_out => {
            sa_std.registry_mutex.unlock();
            return sio.getStdOut().write(data);
        },
        .std_err => {
            sa_std.registry_mutex.unlock();
            return sio.getStdErr().write(data);
        },
        .invalid => {
            sa_std.registry_mutex.unlock();
            return error.InvalidHandle;
        },
        .std_in, .locked => unreachable,
    }
}

fn lxRead(fd: std.posix.fd_t, buf: []u8) !usize {
    if (comptime is_wasm) return error.Unsupported;
    if (buf.len == 0) return 0;
    if (comptime is_linux) return try lxCheck(std.os.linux.read(fd, buf.ptr, buf.len));
    return try libcUsize(libc.read(fd, buf.ptr, buf.len));
}

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

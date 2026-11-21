const std = @import("std");
pub const sa_std = @import("../sa_std.zig");
pub const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
pub const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
pub const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
pub const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
pub const builtin = @import("../sa_std.zig").builtin;
pub const finish = @import("../sa_std.zig").finish;
pub const finishErr = @import("../sa_std.zig").finishErr;
pub const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const lxClose = @import("../sa_std.zig").lxClose;
pub const waitStatusFromSiginfo = @import("../sa_std.zig").waitStatusFromSiginfo;

pub const WasiW = struct {
    pub const EXITED: u32 = 0;
    pub const NOHANG: u32 = 0;
    pub fn IFEXITED(_: u32) bool {
        return false;
    }
    pub fn EXITSTATUS(_: u32) u8 {
        return 0;
    }
    pub fn IFSIGNALED(_: u32) bool {
        return false;
    }
    pub fn TERMSIG(_: u32) u8 {
        return 0;
    }
    pub fn IFSTOPPED(_: u32) bool {
        return false;
    }
    pub fn STOPSIG(_: u32) u8 {
        return 0;
    }
};

pub const WT = if (is_wasm) WasiW else std.posix.W;

pub const w_exited: u32 = if (builtin.os.tag == .linux) WT.EXITED else 0;

pub const w_nohang: u32 = if (builtin.os.tag == .linux) WT.NOHANG else 0;

pub const ProcessHandle = struct {
    pid: std.posix.pid_t,
    process_group: ?std.posix.pid_t = null,
    pidfd: ?std.posix.fd_t = null,
    capture_output: bool = false,
    stdout_fd: ?std.posix.fd_t = null,
    stderr_fd: ?std.posix.fd_t = null,
    stdout_buf: []u8 = &.{},
    stderr_buf: []u8 = &.{},
    stdout_pos: usize = 0,
    stderr_pos: usize = 0,
    exited: bool = false,
    code: u32 = 0,
    raw_status: u32 = 0,

    pub fn deinit(self: *ProcessHandle) void {
        if (!self.exited) {
            _ = waitProcessIgnoringMissing(self.pid);
            self.exited = true;
        }
        if (self.pidfd) |fd| lxClose(fd);
        if (self.stdout_fd) |fd| lxClose(fd);
        if (self.stderr_fd) |fd| lxClose(fd);
        if (self.stdout_buf.len != 0) std.heap.page_allocator.free(self.stdout_buf);
        if (self.stderr_buf.len != 0) std.heap.page_allocator.free(self.stderr_buf);
        self.stdout_buf = &.{};
        self.stderr_buf = &.{};
        self.stdout_pos = 0;
        self.stderr_pos = 0;
        self.stdout_fd = null;
        self.stderr_fd = null;
    }
};

pub fn capture_fd_to_owned(allocator: std.mem.Allocator, fd: std.posix.fd_t) ![]u8 {
    var list = std.array_list.Managed(u8).init(allocator);
    defer list.deinit();
    var buf: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &buf) catch |err| switch (err) {
            error.WouldBlock => break,
            else => return err,
        };
        if (n == 0) break;
        try list.appendSlice(buf[0..n]);
    }
    return try list.toOwnedSlice();
}

pub fn statusFromWaitStatus(status: u32) u32 {
    if (WT.IFEXITED(status)) return @as(u32, @intCast(WT.EXITSTATUS(status)));
    if (WT.IFSIGNALED(status)) return 128 + @as(u32, @backingInt(WT.TERMSIG(status)));
    if (WT.IFSTOPPED(status)) return 130;
    return 127;
}

pub fn rawWaitStatus(status: i32) u32 {
    return @bitCast(status);
}

pub fn waitStatusCode(raw: i32) u32 {
    return statusFromWaitStatus(rawWaitStatus(raw));
}

pub fn waitStatusSignal(raw: i32) i32 {
    const status = rawWaitStatus(raw);
    if (!WT.IFSIGNALED(status)) return -1;
    return @as(i32, @bitCast(@backingInt(WT.TERMSIG(status))));
}

pub fn waitStatusCoreDumped(raw: i32) u8 {
    const status = rawWaitStatus(raw);
    if (!WT.IFSIGNALED(status)) return 0;
    return if ((status & 0x80) != 0) 1 else 0;
}

pub fn waitStatusStoppedSignal(raw: i32) i32 {
    const status = rawWaitStatus(raw);
    if (!WT.IFSTOPPED(status)) return -1;
    return @as(i32, @bitCast(@backingInt(WT.STOPSIG(status))));
}

pub fn waitStatusContinued(raw: i32) u8 {
    return if (rawWaitStatus(raw) == 0xffff) 1 else 0;
}

pub fn waitProcessIgnoringMissing(pid: std.posix.pid_t) ?u32 {
    if (comptime builtin.cpu.arch.isWasm()) return null;
    var status: i32 = 0;
    while (true) {
        const result = std.os.linux.wait4(pid, &status, 0, null);
        switch (std.os.linux.errno(result)) {
            .SUCCESS => return @bitCast(status),
            .INTR => continue,
            .CHILD => return null,
            else => return null,
        }
    }
}

pub fn waitPidfdStatus(fd: std.posix.fd_t, options: u32) error{ ProcessNotFound, InvalidArgument, PermissionDenied, Unexpected }!?u32 {
    if (comptime builtin.os.tag != .linux) return null;
    var siginfo: std.posix.siginfo_t = undefined;
    while (true) {
        const result = std.os.linux.waitid(.PIDFD, fd, &siginfo, options, null);
        switch (std.os.linux.errno(result)) {
            .SUCCESS => break,
            .INTR => continue,
            .CHILD => return error.ProcessNotFound,
            .INVAL => return error.InvalidArgument,
            .PERM => return error.PermissionDenied,
            else => return error.Unexpected,
        }
    }
    if (siginfo.fields.common.first.piduid.pid == 0) return null;
    return waitStatusFromSiginfo(siginfo);
}

pub fn finalizeProcessExit(proc: *ProcessHandle, status: u32) !void {
    proc.code = statusFromWaitStatus(status);
    proc.raw_status = status;
    proc.exited = true;
    if (proc.capture_output) {
        if (proc.stdout_fd) |fd| {
            const captured = try capture_fd_to_owned(std.heap.page_allocator, fd);
            proc.stdout_buf = captured;
            lxClose(fd);
            proc.stdout_fd = null;
        }
        if (proc.stderr_fd) |fd| {
            const captured = try capture_fd_to_owned(std.heap.page_allocator, fd);
            proc.stderr_buf = captured;
            lxClose(fd);
            proc.stderr_fd = null;
        }
    }
    proc.stdout_pos = 0;
    proc.stderr_pos = 0;
}

pub export fn sa_std_pidfd_wait_raw(handle: u64, out_raw: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    raw_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            const raw_status = waitPidfdStatus(fd.fd, w_exited) catch |err| switch (err) {
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            raw_ptr.* = @bitCast(raw_status orelse return finish(SA_STD_OK));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_pidfd_wait(handle: u64, out_code: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            const raw_status = waitPidfdStatus(fd.fd, w_exited) catch |err| switch (err) {
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            code_ptr.* = statusFromWaitStatus(raw_status orelse return finish(SA_STD_OK));
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_pidfd_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const raw_ptr = out_raw orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    raw_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            const raw_status = waitPidfdStatus(fd.fd, w_exited | w_nohang) catch |err| switch (err) {
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            if (raw_status == null) return finish(SA_STD_OK);
            ready_ptr.* = 1;
            raw_ptr.* = @bitCast(raw_status.?);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_std_pidfd_try_wait(handle: u64, out_ready: ?*i32, out_code: ?*u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const ready_ptr = out_ready orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    ready_ptr.* = 0;
    code_ptr.* = 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .owned_fd => |fd| {
            const raw_status = waitPidfdStatus(fd.fd, w_exited | w_nohang) catch |err| switch (err) {
                error.ProcessNotFound => return finish(SA_STD_ERR_INVALID_HANDLE),
                else => return finishErr(err),
            };
            if (raw_status == null) return finish(SA_STD_OK);
            ready_ptr.* = 1;
            code_ptr.* = statusFromWaitStatus(raw_status.?);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

const std = @import("std");
const builtin = @import("builtin");

const empty_argv: [0][:0]u8 = .{};

// NOTE(Zig 0.17): this file is compiled standalone via `zig build-obj` inside
// tests, so it cannot use the named `sio` import. It keeps a tiny
// process-global `std.Io.Threaded` (same shape as `sio.io()`) and calls the
// explicit-`Io` filesystem APIs directly.
var global_threaded: ?std.Io.Threaded = null;
var global_mu: std.atomic.Mutex = .unlocked;

fn io() std.Io {
    while (!global_mu.tryLock()) std.atomic.spinLoopHint();
    defer global_mu.unlock();
    if (global_threaded) |*t| return t.io();
    global_threaded = std.Io.Threaded.init(std.heap.page_allocator, .{});
    return (&global_threaded.?).io();
}

const ArgvState = struct {
    // NOTE(Zig 0.17): `std.Thread.Mutex` was removed. This file must stay
    // self-contained (it is compiled standalone via `zig build-obj` in tests),
    // so use a small spinlock instead of `std.Io.Mutex` (which needs an `Io`).
    mutex: std.atomic.Mutex = .unlocked,
    initialized: bool = false,
    argc: i32 = 0,
    argv: [][:0]u8 = empty_argv[0..],

    fn ensure(self: *ArgvState) void {
        while (!self.mutex.tryLock()) std.atomic.spinLoopHint();
        defer self.mutex.unlock();
        if (self.initialized) return;
        self.argv = loadArgv() catch empty_argv[0..];
        self.argc = @as(i32, @intCast(self.argv.len));
        self.initialized = true;
    }
};

var argv_state: ArgvState = .{};

fn loadArgv() ![][:0]u8 {
    return switch (builtin.os.tag) {
        .linux => loadProcCmdline(),
        else => loadProcessArgs(),
    };
}

fn loadProcessArgs() ![][:0]u8 {
    // NOTE(Zig 0.17): standalone argv access without `std.process.Init` is
    // unsupported (the old `argsWithAllocator` was removed and `Args` values
    // only come from `main(init)`). Non-Linux callers get an empty argv;
    // `ensure()` already falls back to `empty_argv` on error.
    return error.UnsupportedOs;
}

fn loadProcCmdline() ![][:0]u8 {
    const alloc = std.heap.page_allocator;
    var file = try std.Io.Dir.openFileAbsolute(io(), "/proc/self/cmdline", .{});
    defer file.close(io());

    var rbuf: [4096]u8 = undefined;
    var r = file.readerStreaming(io(), &rbuf);
    const blob = try r.interface.allocRemaining(alloc, .limited(1 << 20));
    defer alloc.free(blob);

    var args: std.ArrayList([:0]u8) = .empty;
    errdefer {
        for (args.items) |arg| alloc.free(arg);
        args.deinit(alloc);
    }

    var it = std.mem.splitScalar(u8, blob, 0);
    while (it.next()) |part| {
        if (part.len == 0) continue;
        try args.append(alloc, try alloc.dupeSentinel(u8, part, 0));
    }

    return try args.toOwnedSlice(alloc);
}

fn lenAsUsize(len: u64) !usize {
    if (len > std.math.maxInt(usize)) return error.InvalidArgument;
    return @as(usize, @intCast(len));
}

fn bytesFromConst(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const n = try lenAsUsize(len);
    if (n == 0) return &.{};
    const p = ptr orelse return error.InvalidArgument;
    return p[0..n];
}

fn pathBytes(ptr: ?[*]const u8, len: u64) ![]const u8 {
    const path = try bytesFromConst(ptr, len);
    if (path.len == 0) return error.InvalidArgument;
    if (std.mem.indexOfScalar(u8, path, 0) != null) return error.InvalidArgument;
    return path;
}

pub export fn sys_print(data: ?[*]const u8, len: u64) void {
    const bytes = bytesFromConst(data, len) catch return;
    var wbuf: [8192]u8 = undefined;
    var w = std.Io.File.stdout().writerStreaming(io(), &wbuf);
    w.interface.writeAll(bytes) catch |err| {
        // Native sys_print is fire-and-forget ABI surface; callers cannot observe stdout failures here.
        _ = @errorName(err);
    };
    w.interface.flush() catch {};
}

pub export fn sys_exit(code: i32) noreturn {
    std.process.exit(@as(u8, @truncate(@as(u32, @bitCast(code)))));
}

pub export fn sys_argc() i32 {
    argv_state.ensure();
    return argv_state.argc;
}

pub export fn sys_argv(index: u64) ?[*:0]const u8 {
    argv_state.ensure();
    const idx = lenAsUsize(index) catch return null;
    if (idx >= argv_state.argv.len) return null;
    return argv_state.argv[idx].ptr;
}

pub export fn sys_read_file(path: ?[*]const u8, path_len: u64, out_len: ?*u64) ?[*]u8 {
    const len_ptr = out_len orelse return null;
    len_ptr.* = 0;
    const path_bytes = pathBytes(path, path_len) catch return null;
    var file = std.Io.Dir.cwd().openFile(io(), path_bytes, .{}) catch return null;
    defer file.close(io());
    var rbuf: [8192]u8 = undefined;
    var r = file.readerStreaming(io(), &rbuf);
    const data = r.interface.allocRemaining(std.heap.c_allocator, .limited(1 << 30)) catch return null;
    len_ptr.* = @as(u64, @intCast(data.len));
    return data.ptr;
}

pub export fn sys_write_file(path: ?[*]const u8, path_len: u64, data: ?[*]const u8, data_len: u64) i32 {
    const path_bytes = pathBytes(path, path_len) catch return -1;
    const bytes = bytesFromConst(data, data_len) catch return -1;
    var file = std.Io.Dir.cwd().createFile(io(), path_bytes, .{ .truncate = true }) catch return -1;
    defer file.close(io());
    var wbuf: [8192]u8 = undefined;
    var w = file.writerStreaming(io(), &wbuf);
    w.interface.writeAll(bytes) catch return -1;
    w.interface.flush() catch return -1;
    if (bytes.len > std.math.maxInt(i32)) return -1;
    return @as(i32, @intCast(bytes.len));
}

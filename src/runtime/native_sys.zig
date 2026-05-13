const std = @import("std");

const empty_argv: [0][:0]u8 = .{};

const ArgvState = struct {
    mutex: std.Thread.Mutex = .{},
    initialized: bool = false,
    argc: i32 = 0,
    argv: [][:0]u8 = empty_argv[0..],

    fn ensure(self: *ArgvState) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        if (self.initialized) return;
        self.argv = loadProcCmdline() catch empty_argv[0..];
        self.argc = @as(i32, @intCast(self.argv.len));
        self.initialized = true;
    }
};

var argv_state: ArgvState = .{};

fn loadProcCmdline() ![][:0]u8 {
    var file = try std.fs.openFileAbsolute("/proc/self/cmdline", .{});
    defer file.close();

    const blob = try file.readToEndAlloc(std.heap.page_allocator, 1 << 20);
    errdefer std.heap.page_allocator.free(blob);

    var args = std.ArrayList([:0]u8).init(std.heap.page_allocator);
    errdefer {
        for (args.items) |arg| std.heap.page_allocator.free(arg);
        args.deinit();
    }

    var it = std.mem.splitScalar(u8, blob, 0);
    while (it.next()) |part| {
        if (part.len == 0) continue;
        try args.append(try std.heap.page_allocator.dupeZ(u8, part));
    }

    std.heap.page_allocator.free(blob);
    return try args.toOwnedSlice();
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
    std.io.getStdOut().writeAll(bytes) catch {};
}

pub export fn sys_exit(code: i32) noreturn {
    std.posix.exit(@as(u8, @truncate(@as(u32, @bitCast(code)))));
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
    var file = std.fs.cwd().openFile(path_bytes, .{}) catch return null;
    defer file.close();
    const data = file.readToEndAlloc(std.heap.c_allocator, 1 << 30) catch return null;
    len_ptr.* = @as(u64, @intCast(data.len));
    return data.ptr;
}

pub export fn sys_write_file(path: ?[*]const u8, path_len: u64, data: ?[*]const u8, data_len: u64) i32 {
    const path_bytes = pathBytes(path, path_len) catch return -1;
    const bytes = bytesFromConst(data, data_len) catch return -1;
    var file = std.fs.cwd().createFile(path_bytes, .{ .truncate = true }) catch return -1;
    defer file.close();
    file.writeAll(bytes) catch return -1;
    if (bytes.len > std.math.maxInt(i32)) return -1;
    return @as(i32, @intCast(bytes.len));
}

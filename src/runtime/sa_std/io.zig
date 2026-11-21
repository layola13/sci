const std = @import("std");
const sa_std = @import("../sa_std.zig");
const Resource = @import("../sa_std.zig").Resource;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const SA_STD_STDERR = @import("../sa_std.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("../sa_std.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("../sa_std.zig").SA_STD_STDOUT;
const finish = @import("../sa_std.zig").finish;
const finishErr = @import("../sa_std.zig").finishErr;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const lockRegistry = @import("../sa_std.zig").lockRegistry;
const readHandle = @import("../sa_std.zig").readHandle;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_fs_read_buffer_data = @import("../sa_std.zig").sa_fs_read_buffer_data;
const sa_fs_read_buffer_free = @import("../sa_std.zig").sa_fs_read_buffer_free;
const sa_fs_read_buffer_len = @import("../sa_std.zig").sa_fs_read_buffer_len;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sa_std_read = @import("../sa_std.zig").sa_std_read;
const sa_std_write = @import("../sa_std.zig").sa_std_write;

pub export fn sa_io_read_line(handle: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const limit = lenAsUsize(max_bytes) catch |err| return finishErr(err);

    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer list.deinit();

    var count: usize = 0;
    while (count < limit) {
        var ch: [1]u8 = undefined;
        const read = readHandle(handle, ch[0..]) catch |err| return finishErr(err);
        if (read == 0) break;
        if (ch[0] == '\n') break;
        if (ch[0] == '\r') continue;
        list.append(ch[0]) catch |err| return finishErr(err);
        count += 1;
    }

    const bytes = list.toOwnedSlice() catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(bytes);
    const resource = Resource{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } };
    lockRegistry();
    defer sa_std.registry_mutex.unlock();
    const buf_handle = registerResourceLocked(resource) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = buf_handle;
    return finish(SA_STD_OK);
}

pub export fn sa_io_stdin() u64 {
    return SA_STD_STDIN;
}

pub export fn sa_io_stdout() u64 {
    return SA_STD_STDOUT;
}

pub export fn sa_io_stderr() u64 {
    return SA_STD_STDERR;
}

pub export fn sa_io_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, out_cap, out_read);
}

pub export fn sa_io_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    var count: u64 = 0;
    const status = sa_std_read(handle, out, len, &count);
    if (status != SA_STD_OK or count != len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_io_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_io_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    var written: u64 = 0;
    const status = sa_std_write(handle, data, len, &written);
    if (status != SA_STD_OK or written != len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_io_flush(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_io_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_io_buffer_data(buffer: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(buffer);
}

pub export fn sa_io_buffer_len(buffer: u64) u64 {
    return sa_fs_read_buffer_len(buffer);
}

pub export fn sa_io_buffer_free(buffer: u64) i32 {
    return sa_fs_read_buffer_free(buffer);
}

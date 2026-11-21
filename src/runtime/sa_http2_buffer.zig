const std = @import("std");
const sa_std = @import("sa_http2.zig");
const SA_STD_ERR_INVALID_ARGUMENT = @import("sa_http2.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_OK = @import("sa_http2.zig").SA_STD_OK;
const sio = @import("sa_http2.zig").sio;
const takeBuffer = @import("sa_http2.zig").takeBuffer;

pub export fn sa_std_http2_buffer_data(handle: u64) ?[*]const u8 {
    const bytes = takeBuffer(handle) orelse return null;
    return bytes.ptr;
}

pub export fn sa_std_http2_buffer_len(handle: u64) u64 {
    const bytes = takeBuffer(handle) orelse return 0;
    return @intCast(bytes.len);
}

pub export fn sa_std_http2_buffer_free(handle: u64) i32 {
    sa_std.buffer_registry_mutex.lockUncancelable(sio.io());
    defer sa_std.buffer_registry_mutex.unlock(sio.io());
    if (handle == 0) return SA_STD_OK;
    const idx: usize = @intCast(handle - 1);
    if (idx >= sa_std.buffer_slots.items.len) return SA_STD_ERR_INVALID_ARGUMENT;
    const entry = sa_std.buffer_slots.items[idx] orelse return SA_STD_ERR_INVALID_ARGUMENT;
    sa_std.buffer_slots.items[idx] = null;
    std.heap.page_allocator.free(entry.bytes);
    return SA_STD_OK;
}

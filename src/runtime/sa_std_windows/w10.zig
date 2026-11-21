const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const FreeLibrary = @import("w01.zig").FreeLibrary;
const GetProcAddress = @import("w01.zig").GetProcAddress;
const LoadLibraryW = @import("w01.zig").LoadLibraryW;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_TRUNCATED = @import("w01.zig").SA_STD_ERR_TRUNCATED;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SA_STD_STDERR = @import("w01.zig").SA_STD_STDERR;
const SA_STD_STDIN = @import("w01.zig").SA_STD_STDIN;
const SA_STD_STDOUT = @import("w01.zig").SA_STD_STDOUT;
const SaProcessArgv = @import("w01.zig").SaProcessArgv;
const SaTermWinsize = @import("w01.zig").SaTermWinsize;
const SetFilePointerEx = @import("w01.zig").SetFilePointerEx;
const bufferSlot = @import("w02.zig").bufferSlot;
const buffers = @import("w01.zig").buffers;
const closeDirEntriesHandle = @import("w04.zig").closeDirEntriesHandle;
const closeDirEntryHandle = @import("w04.zig").closeDirEntryHandle;
const closeDynamicLibrary = @import("w03.zig").closeDynamicLibrary;
const closeJsonHandle = @import("w03.zig").closeJsonHandle;
const closeJsonWriter = @import("w03.zig").closeJsonWriter;
const closeMetadataHandle = @import("w04.zig").closeMetadataHandle;
const closeNetAddr = @import("w03.zig").closeNetAddr;
const closeNetAddrList = @import("w03.zig").closeNetAddrList;
const closeProcessHandle = @import("w04.zig").closeProcessHandle;
const closeStreamHandle = @import("w04.zig").closeStreamHandle;
const closeTcpHandle = @import("w03.zig").closeTcpHandle;
const closeTokenizer = @import("w03.zig").closeTokenizer;
const closeUdp = @import("w03.zig").closeUdp;
const constBytes = @import("w02.zig").constBytes;
const dir_entries_handle_tag = @import("w01.zig").dir_entries_handle_tag;
const dir_entry_handle_tag = @import("w01.zig").dir_entry_handle_tag;
const dynamicLibraryErrorStatus = @import("w03.zig").dynamicLibraryErrorStatus;
const dynamicLibrarySlotLocked = @import("w03.zig").dynamicLibrarySlotLocked;
const dynamic_library_error = @import("w02.zig").dynamic_library_error;
const dynamic_library_handle_tag = @import("w01.zig").dynamic_library_handle_tag;
const dynamic_library_mutex = @import("w02.zig").dynamic_library_mutex;
const dynamic_library_slots = @import("w02.zig").dynamic_library_slots;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const free_slots = @import("w01.zig").free_slots;
const json_handle_tag = @import("w01.zig").json_handle_tag;
const json_tokenizer_handle_tag = @import("w01.zig").json_tokenizer_handle_tag;
const json_writer_handle_tag = @import("w01.zig").json_writer_handle_tag;
const lenAsUsize = @import("w02.zig").lenAsUsize;
const metadata_handle_tag = @import("w01.zig").metadata_handle_tag;
const mutBytes = @import("w02.zig").mutBytes;
const net_addr_handle_tag = @import("w02.zig").net_addr_handle_tag;
const net_addr_list_handle_tag = @import("w02.zig").net_addr_list_handle_tag;
const pathBytes = @import("w02.zig").pathBytes;
const processSlotLocked = @import("w03.zig").processSlotLocked;
const process_handle_tag = @import("w01.zig").process_handle_tag;
const process_mutex = @import("w02.zig").process_mutex;
const process_slots = @import("w02.zig").process_slots;
const registerBuffer = @import("w02.zig").registerBuffer;
const registerDynamicLibrary = @import("w03.zig").registerDynamicLibrary;
const registry_mutex = @import("w01.zig").registry_mutex;
const sa_fs_read_buffer_data = @import("w06.zig").sa_fs_read_buffer_data;
const sa_fs_read_buffer_free = @import("w06.zig").sa_fs_read_buffer_free;
const sa_fs_read_buffer_len = @import("w06.zig").sa_fs_read_buffer_len;
const sa_std_process_run = @import("w09.zig").sa_std_process_run;
const sa_std_process_run_cwd = @import("w09.zig").sa_std_process_run_cwd;
const sa_std_process_wait = @import("w09.zig").sa_std_process_wait;
const streamSlotLocked = @import("w03.zig").streamSlotLocked;
const stream_handle_tag = @import("w01.zig").stream_handle_tag;
const stream_mutex = @import("w02.zig").stream_mutex;
const stream_slots = @import("w02.zig").stream_slots;
const tagged_handle_mask = @import("w02.zig").tagged_handle_mask;
const tcp_listener_handle_tag = @import("w02.zig").tcp_listener_handle_tag;
const tcp_stream_handle_tag = @import("w02.zig").tcp_stream_handle_tag;
const udp_handle_tag = @import("w02.zig").udp_handle_tag;
const writeHandle = @import("w02.zig").writeHandle;

pub fn readCapturedProcess(handle: u64, use_stderr: bool, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer process_mutex.unlock();
    const idx = processSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = process_slots.items[idx].?;
    if (resource.mode != .capture or !resource.exited) return finish(SA_STD_ERR_INVALID_HANDLE);
    const source = if (use_stderr) resource.stderr_buf else resource.stdout_buf;
    const pos = if (use_stderr) &resource.stderr_pos else &resource.stdout_pos;
    const copy_len = @min(output.len, source.len - @min(pos.*, source.len));
    if (copy_len != 0) @memcpy(output[0..copy_len], source[pos.* .. pos.* + copy_len]);
    pos.* += copy_len;
    if (out_read) |ptr| ptr.* = @as(u64, @intCast(copy_len));
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_read_stdout(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return readCapturedProcess(handle, false, out, out_cap, out_read);
}

pub export fn sa_std_process_read_stderr(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return readCapturedProcess(handle, true, out, out_cap, out_read);
}

pub export fn sa_std_process_exec_capture(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    var process: u64 = 0;
    var status = sa_std_process_run(argv_ptr, argv_len, &process);
    if (status != SA_STD_OK) return status;
    defer _ = closeProcessHandle(process);
    status = sa_std_process_wait(process, code_ptr);
    if (status != SA_STD_OK) return status;

    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = processSlotLocked(process) orelse {
        process_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const resource = process_slots.items[idx].?;
    const stdout_owned = std.heap.page_allocator.dupe(u8, resource.stdout_buf) catch |err| {
        process_mutex.unlock();
        return finishErr(err);
    };
    const stderr_owned = std.heap.page_allocator.dupe(u8, resource.stderr_buf) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        process_mutex.unlock();
        return finishErr(err);
    };
    process_mutex.unlock();
    stdout_ptr.* = registerBuffer(stdout_owned) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    stderr_ptr.* = registerBuffer(stderr_owned) catch |err| {
        _ = sa_std_close(stdout_ptr.*);
        stdout_ptr.* = 0;
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub export fn sa_std_process_exec_capture_cwd(argv_ptr: ?[*]const SaProcessArgv, argv_len: u64, cwd_ptr: ?[*]const u8, cwd_len: u64, out_code: ?*u32, out_stdout: ?*u64, out_stderr: ?*u64) i32 {
    const code_ptr = out_code orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stdout_ptr = out_stdout orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const stderr_ptr = out_stderr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    code_ptr.* = 0;
    stdout_ptr.* = 0;
    stderr_ptr.* = 0;
    var process: u64 = 0;
    var status = sa_std_process_run_cwd(argv_ptr, argv_len, cwd_ptr, cwd_len, &process);
    if (status != SA_STD_OK) return status;
    defer _ = closeProcessHandle(process);
    status = sa_std_process_wait(process, code_ptr);
    if (status != SA_STD_OK) return status;

    while (!process_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = processSlotLocked(process) orelse {
        process_mutex.unlock();
        return finish(SA_STD_ERR_INVALID_HANDLE);
    };
    const resource = process_slots.items[idx].?;
    const stdout_owned = std.heap.page_allocator.dupe(u8, resource.stdout_buf) catch |err| {
        process_mutex.unlock();
        return finishErr(err);
    };
    const stderr_owned = std.heap.page_allocator.dupe(u8, resource.stderr_buf) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        process_mutex.unlock();
        return finishErr(err);
    };
    process_mutex.unlock();
    stdout_ptr.* = registerBuffer(stdout_owned) catch |err| {
        std.heap.page_allocator.free(stdout_owned);
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    stderr_ptr.* = registerBuffer(stderr_owned) catch |err| {
        _ = sa_std_close(stdout_ptr.*);
        stdout_ptr.* = 0;
        std.heap.page_allocator.free(stderr_owned);
        return finishErr(err);
    };
    return finish(SA_STD_OK);
}

pub fn readStreamHandle(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.read(output) catch |err| return finishErr(err);
    if (out_read) |ptr| ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_std_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    if (handle == SA_STD_STDIN) {
        const output = mutBytes(out, out_cap) catch |err| return finishErr(err);
        const count = sio.getStdIn().read(output) catch |err| return finishErr(err);
        if (out_read) |ptr| ptr.* = @as(u64, @intCast(count));
        return finish(SA_STD_OK);
    }
    if ((handle & tagged_handle_mask) == stream_handle_tag) return readStreamHandle(handle, out, out_cap, out_read);
    return finish(SA_STD_ERR_INVALID_HANDLE);
}

pub export fn sa_io_read(handle: u64, out: ?[*]u8, out_cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, out_cap, out_read);
}

pub export fn sa_io_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    const output = mutBytes(out, len) catch |err| return finishErr(err);
    if (handle == SA_STD_STDIN) {
        sio.getStdIn().readAll(output) catch |err| return finishErr(err);
        return finish(SA_STD_OK);
    }
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.readAll(output) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    if (out_written) |ptr| ptr.* = 0;
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) {
        const count = writeHandle(handle, bytes) catch |err| return finishErr(err);
        if (out_written) |ptr| ptr.* = @as(u64, @intCast(count));
        return finish(SA_STD_OK);
    }
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = stream_slots.items[idx].?.file.write(bytes) catch |err| return finishErr(err);
    if (out_written) |ptr| ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_io_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_io_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) {
        const writer = if (handle == SA_STD_STDOUT) sio.getStdOut() else sio.getStdErr();
        writer.writeAll(bytes) catch |err| return finishErr(err);
        return finish(SA_STD_OK);
    }
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_io_flush(handle: u64) i32 {
    if (handle == SA_STD_STDOUT or handle == SA_STD_STDERR) return finish(SA_STD_OK);
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = streamSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const resource = stream_slots.items[idx].?;
    if (resource.kind != .file) return finish(SA_STD_OK);
    resource.file.sync() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

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

pub fn fileSetEndPos(f: sio.File, new_size: u64) !void {
    try f.inner.setLength(sio.io(), new_size);
}

pub fn fileSeekBy(f: sio.File, offset: i64) !void {
    try sio.io().vtable.fileSeekBy(sio.io().userdata, f.inner, offset);
}

pub fn fileSeekFromEnd(f: sio.File, offset: i64) !void {
    const len = try f.length();
    const new_pos = @as(i64, @intCast(len)) + offset;
    if (new_pos < 0) return error.InvalidArgument;
    try f.seekTo(@as(u64, @intCast(new_pos)));
}

pub fn fileGetPos(f: sio.File) !u64 {
    var new_pos: i64 = 0;
    if (!SetFilePointerEx(f.inner.handle, 0, &new_pos, 1).toBool()) return error.Io;
    if (new_pos < 0) return error.InvalidArgument;
    return @intCast(new_pos);
}

pub fn fileSlotLocked(handle: u64) ?usize {
    const idx = streamSlotLocked(handle) orelse return null;
    if (stream_slots.items[idx].?.kind != .file) return null;
    return idx;
}

pub export fn sa_std_fs_file_read(handle: u64, out: ?[*]u8, cap: u64, out_read: ?*u64) i32 {
    return sa_std_read(handle, out, cap, out_read);
}

pub export fn sa_fs_file_read(handle: u64, out: ?[*]u8, cap: u64) i32 {
    return sa_std_read(handle, out, cap, null);
}

pub export fn sa_std_fs_file_read_at(handle: u64, out: ?[*]u8, cap: u64, offset: u64, out_read: ?*u64) i32 {
    if (out_read) |ptr| ptr.* = 0;
    const read_ptr = out_read orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const output = mutBytes(out, cap) catch |err| return finishErr(err);
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = filePread(stream_slots.items[idx].?.file, output, offset) catch |err| return finishErr(err);
    read_ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_read_exact_at(handle: u64, out: ?[*]u8, len: u64, offset: u64) i32 {
    const output = mutBytes(out, len) catch |err| return finishErr(err);
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = filePreadAll(stream_slots.items[idx].?.file, output, offset) catch |err| return finishErr(err);
    return finish(if (count == output.len) SA_STD_OK else SA_STD_ERR_TRUNCATED);
}

pub export fn sa_fs_file_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    return sa_io_read_exact(handle, out, len);
}

pub export fn sa_std_fs_file_write(handle: u64, data: ?[*]const u8, len: u64, out_written: ?*u64) i32 {
    return sa_std_write(handle, data, len, out_written);
}

pub export fn sa_std_fs_file_write_at(handle: u64, data: ?[*]const u8, len: u64, offset: u64, out_written: ?*u64) i32 {
    if (out_written) |ptr| ptr.* = 0;
    const written_ptr = out_written orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const count = filePwrite(stream_slots.items[idx].?.file, bytes, offset) catch |err| return finishErr(err);
    written_ptr.* = @as(u64, @intCast(count));
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_write_all_at(handle: u64, data: ?[*]const u8, len: u64, offset: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    filePwriteAll(stream_slots.items[idx].?.file, bytes, offset) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_write(handle: u64, data: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, data, len);
}

pub export fn sa_fs_file_write_all(handle: u64, data: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, data, len);
}

pub export fn sa_fs_file_flush(handle: u64) i32 {
    return sa_io_flush(handle);
}

pub export fn sa_fs_file_sync_data(handle: u64) i32 {
    return sa_fs_file_sync(handle);
}

pub export fn sa_fs_file_sync(handle: u64) i32 {
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    stream_slots.items[idx].?.file.sync() catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_truncate(handle: u64, new_size: u64) i32 {
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    fileSetEndPos(stream_slots.items[idx].?.file, new_size) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub fn seekFileLocked(file: sio.File, whence: u32, offset: i64) !void {
    switch (whence) {
        0 => {
            if (offset < 0) return error.InvalidArgument;
            try file.seekTo(@as(u64, @intCast(offset)));
        },
        1 => try fileSeekBy(file, offset),
        2 => try fileSeekFromEnd(file, offset),
        else => return error.InvalidArgument,
    }
}

pub export fn sa_fs_file_seek(handle: u64, whence: u32, offset: i64) i32 {
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    seekFileLocked(stream_slots.items[idx].?.file, whence, offset) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_file_seek(handle: u64, whence: u32, offset: i64, out_pos: ?*u64) i32 {
    const pos_ptr = out_pos orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pos_ptr.* = 0;
    while (!stream_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer stream_mutex.unlock();
    const idx = fileSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const file = stream_slots.items[idx].?.file;
    seekFileLocked(file, whence, offset) catch |err| return finishErr(err);
    pos_ptr.* = fileGetPos(file) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_process_wait_raw(handle: u64, out_raw: ?*i32) i32 {
    _ = handle;
    _ = out_raw;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_try_wait_raw(handle: u64, out_ready: ?*i32, out_raw: ?*i32) i32 {
    _ = handle;
    _ = out_ready;
    _ = out_raw;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_send_signal(handle: u64, signal: i32) i32 {
    _ = handle;
    _ = signal;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_send_process_group_signal(handle: u64, signal: i32) i32 {
    _ = handle;
    _ = signal;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_kill_process_group(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    const pidfd_ptr = out_pidfd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    pidfd_ptr.* = 0;
    _ = handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_process_into_pidfd(handle: u64, out_pidfd: ?*u64) i32 {
    return sa_std_process_pidfd(handle, out_pidfd);
}

pub export fn sa_std_process_close(handle: u64) i32 {
    return closeProcessHandle(handle);
}

pub export fn sa_std_fd_as_raw(handle: u64, out_fd: ?*i32) i32 {
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    if ((handle & tagged_handle_mask) == process_handle_tag) {
        fd_ptr.* = @as(i32, @intCast(handle));
        return finish(SA_STD_OK);
    }
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_dup(handle: u64, out_handle: ?*u64) i32 {
    _ = handle;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_dup_raw(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_from_raw(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_into_raw(handle: u64, out_fd: ?*i32) i32 {
    _ = handle;
    const fd_ptr = out_fd orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    fd_ptr.* = -1;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_close_raw(fd: i32) i32 {
    _ = fd;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fd_is_terminal(handle: u64, out_flag: ?*u8) i32 {
    _ = handle;
    const flag_ptr = out_flag orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    flag_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_raw_enter(handle: u64, out_session: ?*u64) i32 {
    _ = handle;
    if (out_session == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_raw_leave(session_handle: u64) i32 {
    _ = session_handle;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_term_winsize(handle: u64, out_size: ?*SaTermWinsize) i32 {
    _ = handle;
    if (out_size == null) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_close(handle: u64) i32 {
    if ((handle & tagged_handle_mask) == process_handle_tag) return closeProcessHandle(handle);
    if ((handle & tagged_handle_mask) == stream_handle_tag) return closeStreamHandle(handle);
    if ((handle & tagged_handle_mask) == json_handle_tag) return closeJsonHandle(handle);
    if ((handle & tagged_handle_mask) == json_writer_handle_tag) return closeJsonWriter(handle);
    if ((handle & tagged_handle_mask) == json_tokenizer_handle_tag) return closeTokenizer(handle);
    if ((handle & tagged_handle_mask) == metadata_handle_tag) return closeMetadataHandle(handle);
    if ((handle & tagged_handle_mask) == dir_entries_handle_tag) return closeDirEntriesHandle(handle);
    if ((handle & tagged_handle_mask) == dir_entry_handle_tag) return closeDirEntryHandle(handle);
    if ((handle & tagged_handle_mask) == dynamic_library_handle_tag) return closeDynamicLibrary(handle);
    if ((handle & tagged_handle_mask) == net_addr_handle_tag) return closeNetAddr(handle);
    if ((handle & tagged_handle_mask) == net_addr_list_handle_tag) return closeNetAddrList(handle);
    if ((handle & tagged_handle_mask) == tcp_stream_handle_tag or (handle & tagged_handle_mask) == tcp_listener_handle_tag) return closeTcpHandle(handle);
    if ((handle & tagged_handle_mask) == udp_handle_tag) return closeUdp(handle);
    while (!registry_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer registry_mutex.unlock();
    const idx = bufferSlot(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    var resource = buffers.items[idx].?;
    resource.close();
    buffers.items[idx] = null;
    free_slots.append(idx) catch return finish(SA_STD_ERR_NO_MEMORY);
    return finish(SA_STD_OK);
}

pub export fn sa_io_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_io_read_line(handle: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const limit = lenAsUsize(max_bytes) catch |err| return finishErr(err);
    var list = std.array_list.Managed(u8).init(std.heap.page_allocator);
    defer list.deinit();

    var count: usize = 0;
    while (count < limit) {
        var ch: [1]u8 = undefined;
        var read: u64 = 0;
        const status = sa_std_read(handle, &ch, 1, &read);
        if (status != SA_STD_OK) return status;
        if (read == 0) break;
        if (ch[0] == '\n') break;
        if (ch[0] == '\r') continue;
        list.append(ch[0]) catch |err| return finishErr(err);
        count += 1;
    }

    const bytes = list.toOwnedSlice() catch |err| return finishErr(err);
    errdefer std.heap.page_allocator.free(bytes);
    handle_ptr.* = registerBuffer(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

// W1-DEF-IO-BUFFER-API (windows twin of the sa_std.zig change):
// io buffers are registry handles; see io.sai.
pub export fn sa_io_buffer_data(buffer: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(buffer);
}

pub export fn sa_io_buffer_len(buffer: u64) u64 {
    return sa_fs_read_buffer_len(buffer);
}

pub export fn sa_io_buffer_free(buffer: u64) i32 {
    return sa_fs_read_buffer_free(buffer);
}

pub export fn sa_dl_open(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, path) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(path_w);
    const module = LoadLibraryW(path_w.ptr) orelse {
        dynamic_library_error = "LoadLibraryW failed";
        return finish(dynamicLibraryErrorStatus());
    };
    handle_ptr.* = registerDynamicLibrary(module) catch |err| {
        _ = FreeLibrary(module);
        return finishErr(err);
    };
    dynamic_library_error = "";
    return finish(SA_STD_OK);
}

pub export fn sa_dl_sym(handle: u64, symbol_ptr: ?[*]const u8, symbol_len: u64, out_ptr: ?*?*anyopaque) i32 {
    const result_ptr = out_ptr orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    result_ptr.* = null;
    const symbol = pathBytes(symbol_ptr, symbol_len) catch |err| return finishErr(err);
    const symbol_z = std.heap.page_allocator.dupeSentinel(u8, symbol, 0) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(symbol_z);
    while (!dynamic_library_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dynamic_library_mutex.unlock();
    const idx = dynamicLibrarySlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const address = GetProcAddress(dynamic_library_slots.items[idx].?.module, symbol_z.ptr) orelse {
        dynamic_library_error = "GetProcAddress failed";
        return finish(SA_STD_ERR_NOT_FOUND);
    };
    result_ptr.* = @ptrCast(address);
    dynamic_library_error = "";
    return finish(SA_STD_OK);
}

pub export fn sa_dl_close(handle: u64) i32 {
    return closeDynamicLibrary(handle);
}

pub export fn sa_dl_error() ?[*:0]const u8 {
    return dynamic_library_error.ptr;
}

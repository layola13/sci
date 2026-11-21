const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const DirEntriesResource = @import("w01.zig").DirEntriesResource;
const DirEntrySnapshot = @import("w01.zig").DirEntrySnapshot;
const FallibleI32 = @import("w01.zig").FallibleI32;
const FallibleU64 = @import("w01.zig").FallibleU64;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_NOT_FOUND = @import("w01.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const TimeDate = @import("w01.zig").TimeDate;
const constBytes = @import("w02.zig").constBytes;
const dirEntriesSlotLocked = @import("w03.zig").dirEntriesSlotLocked;
const dirEntrySlotLocked = @import("w03.zig").dirEntrySlotLocked;
const dir_entries_slots = @import("w02.zig").dir_entries_slots;
const dir_entry_slots = @import("w02.zig").dir_entry_slots;
const dir_mutex = @import("w02.zig").dir_mutex;
const envGetOwned = @import("w02.zig").envGetOwned;
const envHas = @import("w02.zig").envHas;
const envJoinPathsJsonAlloc = @import("w02.zig").envJoinPathsJsonAlloc;
const envKeyBytes = @import("w02.zig").envKeyBytes;
const envSplitPathsJsonAlloc = @import("w02.zig").envSplitPathsJsonAlloc;
const envVarsJsonAlloc = @import("w02.zig").envVarsJsonAlloc;
const failU64 = @import("w02.zig").failU64;
const fillUtcNow = @import("w02.zig").fillUtcNow;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const homeDirAlloc = @import("w02.zig").homeDirAlloc;
const lenAsUsize = @import("w02.zig").lenAsUsize;
const mapError = @import("w02.zig").mapError;
const metadataAtime = @import("w06.zig").metadataAtime;
const okU64 = @import("w02.zig").okU64;
const openOwnedByteBuffer = @import("w02.zig").openOwnedByteBuffer;
const pathBytes = @import("w02.zig").pathBytes;
const processArgsJsonAlloc = @import("w02.zig").processArgsJsonAlloc;
const registerBuffer = @import("w02.zig").registerBuffer;
const registerDirEntriesLocked = @import("w03.zig").registerDirEntriesLocked;
const registerDirEntryLocked = @import("w03.zig").registerDirEntryLocked;
const registerFile = @import("w03.zig").registerFile;
const registerMetadata = @import("w03.zig").registerMetadata;
const sa_deno_chdir = @import("w04.zig").sa_deno_chdir;
const sa_deno_cwd = @import("w04.zig").sa_deno_cwd;
const sa_deno_env_delete = @import("w04.zig").sa_deno_env_delete;
const sa_deno_env_set = @import("w04.zig").sa_deno_env_set;
const sa_fs_read_buffer_data = @import("w06.zig").sa_fs_read_buffer_data;
const sa_fs_read_buffer_free = @import("w06.zig").sa_fs_read_buffer_free;
const sa_fs_read_buffer_len = @import("w06.zig").sa_fs_read_buffer_len;
const sa_std_close = @import("w10.zig").sa_std_close;
const tempRootAlloc = @import("w02.zig").tempRootAlloc;
const xdgDirsAlloc = @import("w02.zig").xdgDirsAlloc;
const xdgHomeAlloc = @import("w02.zig").xdgHomeAlloc;

pub export fn sa_deno_build_json() u64 {
    const os = @tagName(builtin.os.tag);
    const arch = @tagName(builtin.cpu.arch);
    const abi = @tagName(builtin.abi);
    const json = std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"os\":\"{s}\",\"arch\":\"{s}\",\"target\":\"{s}-{s}\"}}",
        .{ os, arch, arch, abi },
    ) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_deno_build_os() u64 {
    const owned = std.heap.page_allocator.dupe(u8, @tagName(builtin.os.tag)) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_deno_build_platform_family() u64 {
    const owned = std.heap.page_allocator.dupe(u8, "windows") catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

/// Zero-padded decimal append (mirrors the non-Windows variant; std.fmt
/// `{d:04}` on 0.14 misplaces the sign).
pub fn appendPaddedWin(out: *std.array_list.Managed(u8), val: i64, width: usize) !void {
    if (val < 0) {
        try out.append('-');
        const rest = if (width > 0) width - 1 else 0;
        return appendPaddedWin(out, -val, rest);
    }
    var tmp: [32]u8 = undefined;
    const s = try std.fmt.bufPrint(&tmp, "{d}", .{val});
    var i: usize = s.len;
    while (i < width) : (i += 1) try out.append('0');
    try out.appendSlice(s);
}

/// UTC ISO append (mirrors the non-Windows variant).
pub fn appendIsoUtcWin(out: *std.array_list.Managed(u8), year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, milli: i64) !void {
    try appendPaddedWin(out, year, 4);
    try out.append('-');
    try appendPaddedWin(out, month, 2);
    try out.append('-');
    try appendPaddedWin(out, day, 2);
    try out.append('T');
    try appendPaddedWin(out, hour, 2);
    try out.append(':');
    try appendPaddedWin(out, minute, 2);
    try out.append(':');
    try appendPaddedWin(out, second, 2);
    try out.append('.');
    try appendPaddedWin(out, milli, 3);
    try out.append('Z');
}

pub export fn sa_deno_date_now_iso() u64 {
    var date: TimeDate = undefined;
    fillUtcNow(&date) catch return 0;
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    appendIsoUtcWin(&out, date.year, date.month, date.day, date.hour, date.minute, date.second, date.millisecond) catch return 0;
    return openOwnedByteBuffer(out.toOwnedSlice() catch return 0) catch return 0;
}

pub export fn sa_env_get(key_ptr: ?[*]const u8, key_len: u64) u64 {
    const key = envKeyBytes(key_ptr, key_len) catch return 0;
    const owned = envGetOwned(key) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_env_has(key_ptr: ?[*]const u8, key_len: u64) i32 {
    const key = envKeyBytes(key_ptr, key_len) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return finish(if (envHas(key)) SA_STD_OK else SA_STD_ERR_NOT_FOUND);
}

pub export fn sa_env_set_var(key_ptr: ?[*]const u8, key_len: u64, value_ptr: ?[*]const u8, value_len: u64) i32 {
    return sa_deno_env_set(key_ptr, key_len, value_ptr, value_len);
}

pub export fn sa_env_remove_var(key_ptr: ?[*]const u8, key_len: u64) i32 {
    return sa_deno_env_delete(key_ptr, key_len);
}

pub export fn sa_env_current_dir() u64 {
    return sa_deno_cwd();
}

pub export fn sa_env_set_current_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_deno_chdir(path_ptr, path_len);
}

pub export fn sa_env_current_exe() u64 {
    const path = sio.selfExePathAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_temp_dir() u64 {
    const path = tempRootAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_home_dir() u64 {
    const path = homeDirAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_data_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_DATA_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_config_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_CONFIG_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_state_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_STATE_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_cache_home_dir() u64 {
    const path = xdgHomeAlloc(std.heap.page_allocator, "XDG_CACHE_HOME") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_data_dirs() u64 {
    const path = xdgDirsAlloc(std.heap.page_allocator, "XDG_DATA_DIRS") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_xdg_config_dirs() u64 {
    const path = xdgDirsAlloc(std.heap.page_allocator, "XDG_CONFIG_DIRS") catch return 0;
    return openOwnedByteBuffer(path) catch return 0;
}

pub export fn sa_env_args_json() u64 {
    const json = processArgsJsonAlloc(std.heap.page_allocator, false) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_env_vars_json() u64 {
    const json = envVarsJsonAlloc(std.heap.page_allocator) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_env_split_paths_json(path_list_ptr: ?[*]const u8, path_list_len: u64) u64 {
    const path_list = constBytes(path_list_ptr, path_list_len) catch return 0;
    const json = envSplitPathsJsonAlloc(std.heap.page_allocator, path_list) catch return 0;
    return openOwnedByteBuffer(json) catch return 0;
}

pub export fn sa_env_join_paths_json(paths_json_ptr: ?[*]const u8, paths_json_len: u64) u64 {
    const paths_json = constBytes(paths_json_ptr, paths_json_len) catch return 0;
    const joined = envJoinPathsJsonAlloc(std.heap.page_allocator, paths_json) catch return 0;
    return openOwnedByteBuffer(joined) catch return 0;
}

pub export fn sa_env_buffer_data(buffer: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(buffer);
}

pub export fn sa_env_buffer_len(buffer: u64) u64 {
    return sa_fs_read_buffer_len(buffer);
}

pub export fn sa_env_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_std_print(data: ?[*]const u8, len: u64) i32 {
    const bytes = constBytes(data, len) catch |err| return finishErr(err);
    sio.getStdOut().writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_println(data: ?[*]const u8, len: u64) FallibleI32 {
    // Contract alignment (A_min): io.sai declares `-> i32!`, and the
    // interpreter already returns a fallible cell; the native runtime
    // used to return the bare status word, so compiled callers read
    // the payload slot of a cell that was never written.
    const bytes = constBytes(data, len) catch |err| return .{ .status = finishErr(err), .value = 0 };
    sio.getStdOut().writeAll(bytes) catch |err| return .{ .status = finishErr(err), .value = 0 };
    sio.getStdOut().writeAll("\n") catch |err| return .{ .status = finishErr(err), .value = 0 };
    return .{ .status = finish(SA_STD_OK), .value = 0 };
}

pub export fn sa_print_bytes(data: ?[*]const u8, len: u64) void {
    _ = sa_std_print(data, len);
}

pub export fn sa_std_process_exit_status_code(raw: i32) u32 {
    if (raw < 0) return 0;
    // On Windows, processTermCode returns the exit code as u32
    // The test expects code to be 0 for success, which matches our raw
    return @as(u32, @intCast(raw));
}

pub export fn sa_std_process_exit_status_signal(raw: i32) i32 {
    _ = raw;
    return 0;
}

pub export fn sa_std_process_exit_status_core_dumped(raw: i32) u8 {
    _ = raw;
    return 0;
}

pub export fn sa_std_process_exit_status_stopped_signal(raw: i32) i32 {
    _ = raw;
    return -1;
}

pub export fn sa_std_process_exit_status_continued(raw: i32) u8 {
    _ = raw;
    return 0;
}

pub export fn sa_test_fallible_i32_value(value: i32) FallibleI32 {
    return .{ .status = SA_STD_OK, .value = value };
}

pub export fn sa_assert_eq_i64(actual: i64, expected: i64, code: i32) void {
    if (actual == expected) return;
    std.debug.print("PANIC[{d}]: expected={d} actual={d}\n", .{ code, expected, actual });
    std.process.exit(if (code < 0) 1 else @as(u8, @truncate(@as(u32, @bitCast(code)))));
}

pub export fn sa_assert_eq_i64_at(actual: i64, expected: i64, code: i32, file: ?[*]const u8, file_len: u64, line: u32, col: u32) void {
    if (actual == expected) return;
    const file_slice = if (file) |ptr| ptr[0..@as(usize, @intCast(file_len))] else "";
    std.debug.print("PANIC[{d}]: {s}:{d}:{d}: expected={d} actual={d}\n", .{ code, file_slice, line, col, expected, actual });
    std.process.exit(if (code < 0) 1 else @as(u8, @truncate(@as(u32, @bitCast(code)))));
}

pub const test_debug_slots = 16;

pub const TestDebugScalar = struct {
    name: [32]u8,
    name_len: usize,
    value: i64,
};

pub var test_debug_scalars: [test_debug_slots]TestDebugScalar = .{
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
    .{ .name = undefined, .name_len = 0, .value = 0 },
};

pub var test_debug_next: usize = 0;

pub var test_debug_count: usize = 0;

pub var test_debug_mutex = std.atomic.Mutex.unlocked;

pub export fn sa_test_debug_i64(name: ?[*]const u8, name_len: u64, value: i64) void {
    const raw_name = name orelse return;
    while (!test_debug_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer test_debug_mutex.unlock();
    const slot_index = test_debug_next % test_debug_scalars.len;
    var slot = &test_debug_scalars[slot_index];
    const requested_len = std.math.cast(usize, name_len) orelse slot.name.len;
    const copy_len = @min(requested_len, slot.name.len);
    @memset(slot.name[0..], 0);
    if (copy_len != 0) @memcpy(slot.name[0..copy_len], raw_name[0..copy_len]);
    slot.name_len = copy_len;
    slot.value = value;
    test_debug_next = (test_debug_next + 1) % test_debug_scalars.len;
    if (test_debug_count < test_debug_scalars.len) test_debug_count += 1;
}

pub export fn sa_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) FallibleU64 {
    const path = pathBytes(path_ptr, path_len) catch |err| return failU64(mapError(err));
    const file = sio.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return failU64(mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return failU64(mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return failU64(mapError(err));
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_file(path_ptr, path_len, max_bytes);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) FallibleU64 {
    return sa_fs_read_file(path_ptr, path_len, max_bytes);
}

pub export fn sa_std_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    return sa_std_fs_read_file(path_ptr, path_len, max_bytes, out_handle);
}

pub export fn sa_std_fs_open_read(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = sio.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    const handle = registerFile(file) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_write(path_ptr: ?[*]const u8, path_len: u64, truncate: u32, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = sio.cwd().createFile(path, .{ .read = true, .truncate = truncate != 0 }) catch |err| return finishErr(err);
    const handle = registerFile(file) catch |err| {
        file.close();
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_open_options(path_ptr: ?[*]const u8, path_len: u64, flags: u32, create_mode: u32, custom_flags: u32, out_handle: ?*u64) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = flags;
    _ = create_mode;
    _ = custom_flags;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fs_file_from_raw_fd(fd: i32, out_handle: ?*u64) i32 {
    _ = fd;
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fs_remove(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().deleteFile(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_exists(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().access(path, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_try_exists(path_ptr: ?[*]const u8, path_len: u64, out_exists: ?*u8) i32 {
    const exists_ptr = out_exists orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    exists_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().access(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return finish(SA_STD_OK),
        else => return finishErr(err),
    };
    exists_ptr.* = 1;
    return finish(SA_STD_OK);
}

pub export fn sa_std_fs_len(path_ptr: ?[*]const u8, path_len: u64, out_len: ?*u64) i32 {
    const len_ptr = out_len orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    len_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const stat = sio.cwd().statFile(path) catch |err| return finishErr(err);
    len_ptr.* = stat.size;
    return finish(SA_STD_OK);
}

pub fn dirEntryKind(kind: std.Io.File.Kind) u32 {
    return switch (kind) {
        .file => 1,
        .directory => 2,
        .sym_link => 3,
        else => 255,
    };
}

pub fn readDirSnapshots(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) !DirEntriesResource {
    const path = try pathBytes(path_ptr, path_len);
    const limit = try lenAsUsize(max_entries);
    var dir = try sio.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var list = std.array_list.Managed(DirEntrySnapshot).init(std.heap.page_allocator);
    errdefer {
        for (list.items) |entry| std.heap.page_allocator.free(entry.name);
        list.deinit();
    }
    var iterator = dir.iterate();
    while (list.items.len < limit) {
        const entry = try iterator.next() orelse break;
        const name = try std.heap.page_allocator.dupe(u8, entry.name);
        errdefer std.heap.page_allocator.free(name);
        try list.append(.{ .name = name, .kind = dirEntryKind(entry.kind) });
    }
    return .{ .entries = try list.toOwnedSlice() };
}

pub export fn sa_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) FallibleU64 {
    var snapshots = readDirSnapshots(path_ptr, path_len, max_entries) catch |err| return failU64(mapError(err));
    defer snapshots.close();
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    out.appendSlice("{\"entries\":[") catch |err| return failU64(mapError(err));
    for (snapshots.entries, 0..) |entry, index| {
        if (index != 0) out.append(',') catch |err| return failU64(mapError(err));
        var entry_aw: std.Io.Writer.Allocating = .init(std.heap.page_allocator);
        defer entry_aw.deinit();
        std.json.Stringify.value(.{
            .name = entry.name,
            .isDirectory = entry.kind == 2,
            .isFile = entry.kind == 1,
        }, .{}, &entry_aw.writer) catch |err| return failU64(mapError(err));
        out.appendSlice(entry_aw.written()) catch |err| return failU64(mapError(err));
    }
    out.appendSlice("]}") catch |err| return failU64(mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return failU64(mapError(err));
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_dir_json(path_ptr, path_len, max_entries);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_buffer_data(handle: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(handle);
}

pub export fn sa_fs_dir_buffer_len(handle: u64) u64 {
    return sa_fs_read_buffer_len(handle);
}

pub export fn sa_fs_dir_buffer_free(handle: u64) i32 {
    return sa_fs_read_buffer_free(handle);
}

pub export fn sa_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) FallibleU64 {
    var snapshots = readDirSnapshots(path_ptr, path_len, max_entries) catch |err| return failU64(mapError(err));
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const handle = registerDirEntriesLocked(snapshots) catch |err| {
        dir_mutex.unlock();
        snapshots.close();
        return failU64(mapError(err));
    };
    dir_mutex.unlock();
    return okU64(handle);
}

pub export fn sa_std_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_dir_entries(path_ptr, path_len, max_entries);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_entries_len(handle: u64) u64 {
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const idx = dirEntriesSlotLocked(handle) orelse return 0;
    return @as(u64, @intCast(dir_entries_slots.items[idx].?.entries.len));
}

pub export fn sa_std_fs_dir_entries_get(handle: u64, index: u64, out_entry_handle: ?*u64) i32 {
    const handle_ptr = out_entry_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const idx = std.math.cast(usize, index) orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const parent_idx = dirEntriesSlotLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const entries = dir_entries_slots.items[parent_idx].?.entries;
    if (idx >= entries.len) return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const name = std.heap.page_allocator.dupe(u8, entries[idx].name) catch |err| return finishErr(err);
    const child = registerDirEntryLocked(.{ .name = name, .kind = entries[idx].kind }) catch |err| {
        std.heap.page_allocator.free(name);
        return finishErr(err);
    };
    handle_ptr.* = child;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_dir_entries_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_dir_entry_name_ptr(handle: u64) ?[*]u8 {
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return null;
    return dir_entry_slots.items[idx].?.name.ptr;
}

pub export fn sa_fs_dir_entry_name_len(handle: u64) u64 {
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return 0;
    return @as(u64, @intCast(dir_entry_slots.items[idx].?.name.len));
}

pub export fn sa_fs_dir_entry_file_name_ptr(handle: u64) ?[*]u8 {
    return sa_fs_dir_entry_name_ptr(handle);
}

pub export fn sa_fs_dir_entry_file_name_len(handle: u64) u64 {
    return sa_fs_dir_entry_name_len(handle);
}

pub export fn sa_fs_dir_entry_kind(handle: u64) u32 {
    while (!dir_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer dir_mutex.unlock();
    const idx = dirEntrySlotLocked(handle) orelse return 0;
    return dir_entry_slots.items[idx].?.kind;
}

pub export fn sa_fs_dir_entry_ino(handle: u64) u64 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_dir_entry_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub fn metadataStat(path_ptr: ?[*]const u8, path_len: u64) !sio.Stat {
    const path = try pathBytes(path_ptr, path_len);
    return sio.cwd().statFile(path) catch |err| switch (err) {
        error.IsDir => {
            var dir = try sio.cwd().openDir(path, .{});
            defer dir.close();
            return dir.stat();
        },
        else => return err,
    };
}

pub export fn sa_fs_metadata(path_ptr: ?[*]const u8, path_len: u64) FallibleU64 {
    const stat = metadataStat(path_ptr, path_len) catch |err| return failU64(mapError(err));
    const handle = registerMetadata(stat) catch |err| return failU64(mapError(err));
    return okU64(handle);
}

pub export fn sa_std_fs_metadata(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_metadata(path_ptr, path_len);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub fn nsToMs(ts: std.Io.Timestamp) i64 {
    return @as(i64, @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_ms)));
}

pub fn metadataJsonAlloc(stat: sio.Stat) ![]u8 {
    return std.fmt.allocPrint(
        std.heap.page_allocator,
        "{{\"createdAtMs\":{d},\"isDirectory\":{s},\"isFile\":{s},\"isSymlink\":{s},\"modifiedAtMs\":{d},\"accessedAtMs\":{d},\"changedAtMs\":{d},\"size\":{d},\"mode\":0,\"uid\":0,\"gid\":0,\"dev\":0,\"ino\":{d},\"nlink\":0,\"rdev\":0,\"blksize\":0,\"blocks\":0}}",
        .{ nsToMs(stat.ctime), if (stat.kind == .directory) "true" else "false", if (stat.kind == .file) "true" else "false", if (stat.kind == .sym_link) "true" else "false", nsToMs(stat.mtime), nsToMs(metadataAtime(stat)), nsToMs(stat.ctime), stat.size, stat.inode },
    );
}

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const CreateHardLinkW = @import("w01.zig").CreateHardLinkW;
const FallibleI32 = @import("w01.zig").FallibleI32;
const FallibleU64 = @import("w01.zig").FallibleU64;
const SA_STD_ERR_INVALID_ARGUMENT = @import("w01.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("w01.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("w01.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NO_MEMORY = @import("w01.zig").SA_STD_ERR_NO_MEMORY;
const SA_STD_ERR_UNSUPPORTED = @import("w01.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("w01.zig").SA_STD_OK;
const SetFileTime = @import("w01.zig").SetFileTime;
const bufferSlot = @import("w02.zig").bufferSlot;
const buffers = @import("w01.zig").buffers;
const constBytes = @import("w02.zig").constBytes;
const failU64 = @import("w02.zig").failU64;
const finish = @import("w02.zig").finish;
const finishErr = @import("w02.zig").finishErr;
const formatBool = @import("w02.zig").formatBool;
const formatBytes = @import("w02.zig").formatBytes;
const formatFloat = @import("w02.zig").formatFloat;
const formatInteger = @import("w02.zig").formatInteger;
const mapError = @import("w02.zig").mapError;
const metadataJsonAlloc = @import("w05.zig").metadataJsonAlloc;
const metadataSlotLocked = @import("w03.zig").metadataSlotLocked;
const metadataStat = @import("w05.zig").metadataStat;
const metadata_mutex = @import("w02.zig").metadata_mutex;
const metadata_slots = @import("w02.zig").metadata_slots;
const nanoSecondsToFileTime = @import("w01.zig").nanoSecondsToFileTime;
const nsToMs = @import("w05.zig").nsToMs;
const okU64 = @import("w02.zig").okU64;
const openOwnedByteBuffer = @import("w02.zig").openOwnedByteBuffer;
const pathBytes = @import("w02.zig").pathBytes;
const registerBuffer = @import("w02.zig").registerBuffer;
const registry_mutex = @import("w01.zig").registry_mutex;
const sa_fs_read_file = @import("w05.zig").sa_fs_read_file;
const sa_std_close = @import("w10.zig").sa_std_close;
const sa_std_fs_remove = @import("w05.zig").sa_std_fs_remove;
const stringConcat = @import("w02.zig").stringConcat;
const writeFormattedInto = @import("w02.zig").writeFormattedInto;
const writeHandle = @import("w02.zig").writeHandle;
const wsaError = @import("w01.zig").wsaError;

pub export fn sa_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64) FallibleU64 {
    const stat = metadataStat(path_ptr, path_len) catch |err| return failU64(mapError(err));
    const bytes = metadataJsonAlloc(stat) catch |err| return failU64(mapError(err));
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_metadata_json(path_ptr, path_len);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub fn metadataKindIs(handle: u64, kind: std.Io.File.Kind) u8 {
    while (!metadata_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer metadata_mutex.unlock();
    const idx = metadataSlotLocked(handle) orelse return 0;
    return if (metadata_slots.items[idx].?.stat.kind == kind) 1 else 0;
}

pub fn metadataStatCopy(handle: u64) ?sio.Stat {
    while (!metadata_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer metadata_mutex.unlock();
    const idx = metadataSlotLocked(handle) orelse return null;
    return metadata_slots.items[idx].?.stat;
}

pub export fn sa_fs_metadata_is_file(handle: u64) u8 {
    return metadataKindIs(handle, .file);
}

pub export fn sa_fs_metadata_is_directory(handle: u64) u8 {
    return metadataKindIs(handle, .directory);
}

pub export fn sa_fs_metadata_is_symlink(handle: u64) u8 {
    return metadataKindIs(handle, .sym_link);
}

pub export fn sa_fs_metadata_is_block_device(handle: u64) u8 {
    return metadataKindIs(handle, .block_device);
}

pub export fn sa_fs_metadata_is_char_device(handle: u64) u8 {
    return metadataKindIs(handle, .character_device);
}

pub export fn sa_fs_metadata_is_fifo(handle: u64) u8 {
    return metadataKindIs(handle, .named_pipe);
}

pub export fn sa_fs_metadata_is_socket(handle: u64) u8 {
    return metadataKindIs(handle, .unix_domain_socket);
}

pub export fn sa_fs_metadata_modified_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.mtime) else 0;
}

pub export fn sa_fs_metadata_created_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.ctime) else 0;
}

pub export fn sa_fs_metadata_accessed_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(metadataAtime(stat)) else 0;
}

pub export fn sa_fs_metadata_changed_ms(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| nsToMs(stat.ctime) else 0;
}

pub export fn sa_fs_metadata_len(handle: u64) u64 {
    return if (metadataStatCopy(handle)) |stat| stat.size else 0;
}

pub export fn sa_fs_metadata_mode(handle: u64) u32 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_uid(handle: u64) u32 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_gid(handle: u64) u32 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_ino(handle: u64) u64 {
    return if (metadataStatCopy(handle)) |stat| @as(u64, @intCast(stat.inode)) else 0;
}

pub export fn sa_fs_metadata_dev(handle: u64) u64 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_nlink(handle: u64) u64 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_rdev(handle: u64) u64 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_blksize(handle: u64) u64 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_blocks(handle: u64) u64 {
    _ = handle;
    return 0;
}

pub export fn sa_fs_metadata_st_dev(handle: u64) u64 {
    return sa_fs_metadata_dev(handle);
}

pub export fn sa_fs_metadata_st_ino(handle: u64) u64 {
    return sa_fs_metadata_ino(handle);
}

pub export fn sa_fs_metadata_st_mode(handle: u64) u32 {
    return sa_fs_metadata_mode(handle);
}

pub export fn sa_fs_metadata_st_nlink(handle: u64) u64 {
    return sa_fs_metadata_nlink(handle);
}

pub export fn sa_fs_metadata_st_uid(handle: u64) u32 {
    return sa_fs_metadata_uid(handle);
}

pub export fn sa_fs_metadata_st_gid(handle: u64) u32 {
    return sa_fs_metadata_gid(handle);
}

pub export fn sa_fs_metadata_st_rdev(handle: u64) u64 {
    return sa_fs_metadata_rdev(handle);
}

pub export fn sa_fs_metadata_st_size(handle: u64) u64 {
    return sa_fs_metadata_len(handle);
}

pub fn metadataSeconds(ts: std.Io.Timestamp) i64 {
    return @as(i64, @intCast(@divFloor(ts.nanoseconds, std.time.ns_per_s)));
}

pub fn metadataNanoseconds(ts: std.Io.Timestamp) i64 {
    return @as(i64, @intCast(@mod(ts.nanoseconds, std.time.ns_per_s)));
}

pub fn metadataAtime(stat: sio.Stat) std.Io.Timestamp {
    return stat.atime orelse .zero;
}

pub export fn sa_fs_metadata_st_atime(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataSeconds(metadataAtime(stat)) else 0;
}

pub export fn sa_fs_metadata_st_atime_nsec(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataNanoseconds(metadataAtime(stat)) else 0;
}

pub export fn sa_fs_metadata_st_mtime(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataSeconds(stat.mtime) else 0;
}

pub export fn sa_fs_metadata_st_mtime_nsec(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataNanoseconds(stat.mtime) else 0;
}

pub export fn sa_fs_metadata_st_ctime(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataSeconds(stat.ctime) else 0;
}

pub export fn sa_fs_metadata_st_ctime_nsec(handle: u64) i64 {
    return if (metadataStatCopy(handle)) |stat| metadataNanoseconds(stat.ctime) else 0;
}

pub export fn sa_fs_metadata_st_blksize(handle: u64) u64 {
    return sa_fs_metadata_blksize(handle);
}

pub export fn sa_fs_metadata_st_blocks(handle: u64) u64 {
    return sa_fs_metadata_blocks(handle);
}

pub export fn sa_std_fs_metadata_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_metadata_free(handle: u64) FallibleI32 {
    const status = sa_std_close(handle);
    return if (status == SA_STD_OK) .{ .status = SA_STD_OK, .value = 0 } else .{ .status = status, .value = 0 };
}

pub export fn sa_std_fs_canonicalize(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = sio.cwd().realpathAlloc(std.heap.page_allocator, path) catch |err| return finishErr(err);
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_write_file(path_ptr: ?[*]const u8, path_len: u64, buf: ?[*]const u8, len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const file = sio.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_file(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_std_fs_remove(path_ptr, path_len);
}

pub export fn sa_fs_rename(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    sio.cwd().rename(from, sio.cwd(), to) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().makePath(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_make_dir_mode(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_create_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().makeDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_create_dir_mode(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_remove_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().deleteDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_dir_all(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_remove_path(path_ptr: ?[*]const u8, path_len: u64) i32 {
    return sa_fs_remove_dir_all(path_ptr, path_len);
}

pub export fn sa_fs_copy_file(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    sio.cwd().copyFile(from, sio.cwd(), to, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_set_permissions(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_set_times_ms(path_ptr: ?[*]const u8, path_len: u64, accessed_ms: i64, modified_ms: i64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = sio.cwd().openFile(path, .{ .mode = .read_write }) catch |err| return finishErr(err);
    defer file.close();
    const accessed_ns = std.math.mul(i128, accessed_ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const modified_ns = std.math.mul(i128, modified_ms, std.time.ns_per_ms) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const accessed = nanoSecondsToFileTime(accessed_ns);
    const modified = nanoSecondsToFileTime(modified_ns);
    if (!SetFileTime(file.inner.handle, null, &accessed, &modified).toBool()) return finishErr(wsaError());
    return finish(SA_STD_OK);
}

pub export fn sa_fs_hard_link(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    const from_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, from) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(from_w);
    const to_w = std.unicode.utf8ToUtf16LeAllocZ(std.heap.page_allocator, to) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(to_w);
    if (!CreateHardLinkW(to_w.ptr, from_w.ptr, null).toBool()) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_symlink(target_path: ?[*]const u8, target_len: u64, link_path: ?[*]const u8, link_len: u64) i32 {
    const target = pathBytes(target_path, target_len) catch |err| return finishErr(err);
    const link = pathBytes(link_path, link_len) catch |err| return finishErr(err);
    sio.cwd().symLink(target, link, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_chown(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = uid;
    _ = gid;
    _ = has_uid;
    _ = has_gid;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_lchown(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = uid;
    _ = gid;
    _ = has_uid;
    _ = has_gid;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_fchown(handle: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    _ = handle;
    _ = uid;
    _ = gid;
    _ = has_uid;
    _ = has_gid;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_chroot(path_ptr: ?[*]const u8, path_len: u64) i32 {
    _ = path_ptr;
    _ = path_len;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_fs_mkfifo(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    _ = path_ptr;
    _ = path_len;
    _ = mode;
    return finish(SA_STD_ERR_UNSUPPORTED);
}

pub export fn sa_std_fs_read_link(path_ptr: ?[*]const u8, path_len: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    var stack_buf: [sio.max_path_bytes]u8 = undefined;
    const target = sio.cwd().readLink(path, stack_buf[0..]) catch |err| return finishErr(err);
    const bytes = std.heap.page_allocator.dupe(u8, target) catch |err| return finishErr(err);
    const handle = registerBuffer(bytes) catch |err| {
        std.heap.page_allocator.free(bytes);
        return finishErr(err);
    };
    handle_ptr.* = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_buffer_data(handle: u64) ?[*]u8 {
    while (!registry_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer registry_mutex.unlock();
    const idx = bufferSlot(handle) orelse return null;
    return buffers.items[idx].?.bytes.ptr;
}

pub export fn sa_fs_read_buffer_len(handle: u64) u64 {
    while (!registry_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer registry_mutex.unlock();
    const idx = bufferSlot(handle) orelse return 0;
    return @as(u64, @intCast(buffers.items[idx].?.bytes.len));
}

pub export fn sa_fs_read_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_read_file_base64(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) FallibleU64 {
    const result = sa_fs_read_file(path_ptr, path_len, max_bytes);
    if (result.status != SA_STD_OK) return result;

    while (!registry_mutex.tryLock()) { std.Thread.yield() catch {}; }
    const idx = bufferSlot(result.value) orelse {
        registry_mutex.unlock();
        return failU64(SA_STD_ERR_INVALID_HANDLE);
    };
    const bytes = buffers.items[idx].?.bytes;
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch {
        registry_mutex.unlock();
        _ = sa_std_close(result.value);
        return failU64(SA_STD_ERR_NO_MEMORY);
    };
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    registry_mutex.unlock();
    _ = sa_std_close(result.value);

    const handle = openOwnedByteBuffer(encoded) catch |err| {
        std.heap.page_allocator.free(encoded);
        return failU64(mapError(err));
    };
    return okU64(handle);
}

pub export fn sa_std_fs_read_file_base64(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64, out_handle: ?*u64) i32 {
    const handle_ptr = out_handle orelse return finish(SA_STD_ERR_INVALID_ARGUMENT);
    handle_ptr.* = 0;
    const result = sa_fs_read_file_base64(path_ptr, path_len, max_bytes);
    if (result.status != SA_STD_OK) return finish(result.status);
    handle_ptr.* = result.value;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_write_file_base64(path_ptr: ?[*]const u8, path_len: u64, encoded_ptr: ?[*]const u8, encoded_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const encoded = constBytes(encoded_ptr, encoded_len) catch |err| return finishErr(err);
    const decoded_len = std.base64.standard.Decoder.calcSizeForSlice(encoded) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const decoded = std.heap.page_allocator.alloc(u8, decoded_len) catch |err| return finishErr(err);
    defer std.heap.page_allocator.free(decoded);
    std.base64.standard.Decoder.decode(decoded, encoded) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    const file = sio.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(decoded) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fmt_i64(value: i64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_i64_into(value: i64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = buf[0..std.fmt.printInt(&buf, value, actual_base, case, .{})];
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_u64(value: u64, base: u32) u64 {
    const bytes = formatInteger(value, base) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_u64_into(value: u64, base: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const actual_base: u8 = switch (base) {
        2, 8, 10 => @as(u8, @intCast(base)),
        16, 17 => 16,
        else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
    };
    const case: std.fmt.Case = if (base == 17) .upper else .lower;
    var buf: [128]u8 = undefined;
    const text = buf[0..std.fmt.printInt(&buf, value, actual_base, case, .{})];
    return writeFormattedInto(out, out_cap, out_len, text);
}

/// Float math for frontends (v0.24a; Haxe Math.* surface).
/// Pure f64 functions; random yields [0, 1) from 53 crypto bits.
pub export fn sa_math_floor(x: f64) f64 {
    return @floor(x);
}

pub export fn sa_math_ceil(x: f64) f64 {
    return @ceil(x);
}

pub export fn sa_math_sqrt(x: f64) f64 {
    return @sqrt(x);
}

pub export fn sa_math_sin(x: f64) f64 {
    return @sin(x);
}

pub export fn sa_math_cos(x: f64) f64 {
    return @cos(x);
}

pub export fn sa_math_pow(base: f64, exp: f64) f64 {
    return std.math.pow(f64, base, exp);
}

pub export fn sa_math_random() f64 {
    var ubuf: [8]u8 = undefined;
    sio.io().random(&ubuf);
    const u = std.mem.readInt(u64, &ubuf, .little);
    return @as(f64, @floatFromInt(u >> 11)) * (1.0 / 9007199254740992.0);
}

pub export fn sa_fmt_f64(value: f64, precision: u32) u64 {
    const bytes = formatFloat(value, precision) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_f64_into(value: f64, precision: u32, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    var buf: [256]u8 = undefined;
    const text = std.fmt.float.render(&buf, value, .{ .mode = .decimal, .precision = @as(usize, @intCast(precision)) }) catch return finish(SA_STD_ERR_INVALID_ARGUMENT);
    return writeFormattedInto(out, out_cap, out_len, text);
}

pub export fn sa_fmt_bool(value: bool) u64 {
    const bytes = formatBool(value) catch return 0;
    return openOwnedByteBuffer(bytes) catch return 0;
}

pub export fn sa_fmt_bool_into(value: bool, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    return writeFormattedInto(out, out_cap, out_len, if (value) "true" else "false");
}

pub export fn sa_fmt_bytes(buf: ?[*]const u8, len: u64) u64 {
    const bytes = constBytes(buf, len) catch return 0;
    const owned = formatBytes(bytes) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

pub export fn sa_fmt_bytes_into(buf: ?[*]const u8, len: u64, out: ?[*]u8, out_cap: u64, out_len: ?*u64) i32 {
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    return writeFormattedInto(out, out_cap, out_len, bytes);
}

pub export fn sa_fmt_buffer_data(buffer: u64) ?[*]u8 {
    return sa_fs_read_buffer_data(buffer);
}

pub export fn sa_fmt_buffer_len(buffer: u64) u64 {
    return sa_fs_read_buffer_len(buffer);
}

pub export fn sa_fmt_buffer_write_to(buffer: u64, writer: u64) i32 {
    while (!registry_mutex.tryLock()) { std.Thread.yield() catch {}; }
    defer registry_mutex.unlock();
    const idx = bufferSlot(buffer) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    const bytes = buffers.items[idx].?.bytes;
    const written = writeHandle(writer, bytes) catch |err| return finishErr(err);
    if (written != bytes.len) return finish(SA_STD_ERR_IO);
    return finish(SA_STD_OK);
}

pub export fn sa_fmt_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_string_concat(left_ptr: ?[*]const u8, left_len: u64, right_ptr: ?[*]const u8, right_len: u64) u64 {
    const left = constBytes(left_ptr, left_len) catch return 0;
    const right = constBytes(right_ptr, right_len) catch return 0;
    const owned = stringConcat(left, right) catch return 0;
    return openOwnedByteBuffer(owned) catch return 0;
}

/// Single-byte string from a char code (mirrors the non-Windows variant;
/// low byte only, buffer handle read back uniformly).
pub export fn sa_string_from_char_code(code: i32) u64 {
    const byte: u8 = @truncate(@as(u32, @bitCast(code)));
    const owned = std.heap.page_allocator.alloc(u8, 1) catch return 0;
    owned[0] = byte;
    return openOwnedByteBuffer(owned) catch return 0;
}

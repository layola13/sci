const std = @import("std");
const Fallible = @import("../sa_std.zig").Fallible;
const SA_STD_ERR_ACCESS = @import("../sa_std.zig").SA_STD_ERR_ACCESS;
const SA_STD_ERR_INVALID_ARGUMENT = @import("../sa_std.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_INVALID_HANDLE = @import("../sa_std.zig").SA_STD_ERR_INVALID_HANDLE;
const SA_STD_ERR_IO = @import("../sa_std.zig").SA_STD_ERR_IO;
const SA_STD_ERR_NOT_FOUND = @import("../sa_std.zig").SA_STD_ERR_NOT_FOUND;
const SA_STD_ERR_UNSUPPORTED = @import("../sa_std.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const Timespec = @import("../sa_std.zig").Timespec;
const builtin = @import("../sa_std.zig").builtin;
const chownId = @import("../sa_std.zig").chownId;
const chownPath = @import("../sa_std.zig").chownPath;
const constBytes = @import("../sa_std.zig").constBytes;
const fail = @import("../sa_std.zig").fail;
const fileSeekBy = @import("../sa_std.zig").fileSeekBy;
const fileSeekFromEnd = @import("../sa_std.zig").fileSeekFromEnd;
const fileSetEndPos = @import("../sa_std.zig").fileSetEndPos;
const finish = @import("../sa_std.zig").finish;
const finishChownErrno = @import("../sa_std.zig").finishChownErrno;
const finishErr = @import("../sa_std.zig").finishErr;
const finishErrnoAny = @import("../sa_std.zig").finishErrnoAny;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const groupId = @import("../sa_std.zig").groupId;
const handleToFd = @import("../sa_std.zig").handleToFd;
const is_linux = @import("../sa_std.zig").is_linux;
const is_wasm = @import("../sa_std.zig").is_wasm;
const lenAsUsize = @import("../sa_std.zig").lenAsUsize;
const libc = @import("../sa_std.zig").libc;
const listWriter = @import("../sa_std.zig").listWriter;
const lxChroot = @import("../sa_std.zig").lxChroot;
const lxFchmodat = @import("../sa_std.zig").lxFchmodat;
const lxFutimens = @import("../sa_std.zig").lxFutimens;
const lxLink = @import("../sa_std.zig").lxLink;
const lxMkdirat = @import("../sa_std.zig").lxMkdirat;
const lxStatxNoFollow = @import("../sa_std.zig").lxStatxNoFollow;
const mapError = @import("../sa_std.zig").mapError;
const metadataI64TimeFieldMs = @import("../sa_std.zig").metadataI64TimeFieldMs;
const metadataI64TimeFieldNsec = @import("../sa_std.zig").metadataI64TimeFieldNsec;
const metadataI64TimeFieldSec = @import("../sa_std.zig").metadataI64TimeFieldSec;
const metadataModeMatches = @import("../sa_std.zig").metadataModeMatches;
const metadataU64Field = @import("../sa_std.zig").metadataU64Field;
const mkdirP = @import("../sa_std.zig").mkdirP;
const mkdirPathWithMode = @import("../sa_std.zig").mkdirPathWithMode;
const ok = @import("../sa_std.zig").ok;
const openOwnedByteBuffer = @import("../sa_std.zig").openOwnedByteBuffer;
const pathBytes = @import("../sa_std.zig").pathBytes;
const readDirEntriesLinux = @import("../sa_std.zig").readDirEntriesLinux;
const registerResource = @import("../sa_std.zig").registerResource;
const sa_std = @import("../sa_std.zig");
const sa_io_read_exact = @import("../sa_std.zig").sa_io_read_exact;
const sa_io_write_all = @import("../sa_std.zig").sa_io_write_all;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const sa_std_fs_open_write = @import("../sa_std.zig").sa_std_fs_open_write;
const sa_std_fs_remove = @import("../sa_std.zig").sa_std_fs_remove;
const sa_std_read = @import("../sa_std.zig").sa_std_read;
const sio = @import("../sa_std.zig").sio;
const statFromRaw = @import("../sa_std.zig").statFromRaw;
const stringifyToList = @import("../sa_std.zig").stringifyToList;
const timespecFromUnixMs = @import("../sa_std.zig").timespecFromUnixMs;
const tsToMs = @import("../sa_std.zig").tsToMs;
const writeJsonBoolField = @import("../sa_std.zig").writeJsonBoolField;
const writeMetadataJsonExt = @import("../sa_std.zig").writeMetadataJsonExt;

const sa_fs_open_accmode_mask: u32 = 0x3;

pub fn saFsOpenFile(path: []const u8, flags: u32, create_mode: u32, custom_flags: u32) !sio.File {
    if (builtin.os.tag != .linux) return error.Unsupported;

    const read = (flags & 1) != 0;
    const write = (flags & 2) != 0;
    const create = (flags & 4) != 0;
    const truncate = (flags & 8) != 0;
    const append = (flags & 16) != 0;
    const wants_write = write or append;

    var open_flags: std.posix.O = .{};
    open_flags.ACCMODE = if (read and wants_write)
        .RDWR
    else if (wants_write)
        .WRONLY
    else
        .RDONLY;
    open_flags.CREAT = create;
    open_flags.TRUNC = truncate;
    open_flags.APPEND = append;

    const merged_bits = @as(u32, @bitCast(open_flags)) | (custom_flags & ~sa_fs_open_accmode_mask);
    const merged_flags: std.posix.O = @bitCast(merged_bits);
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, merged_flags, @as(std.posix.mode_t, @intCast(create_mode)));
    return .{ .inner = .{ .handle = fd, .flags = .{ .nonblocking = false } } };
}

pub export fn sa_fs_file_open(path_ptr: ?[*]const u8, path_len: u64, flags: u32) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const file = saFsOpenFile(path, flags, 0o666, 0) catch |err| return finishErr(err);
    const handle = registerResource(.{ .file = file }) catch |err| return finishErr(err);
    return @as(i32, @intCast(handle));
}

pub export fn sa_fs_file_create(path_ptr: ?[*]const u8, path_len: u64) i32 {
    // W1-DEF-FS-CREATE: this entry reports a status, not a handle --
    // it creates (or truncates) the file and closes it immediately.
    // The old delegation passed out=null to sa_std_fs_open_write,
    // which rejects a null out slot, so create always failed with
    // ERR_INVALID_ARGUMENT. Callers that need the open file use
    // sa_fs_file_open / sa_std_fs_open_write instead.
    var handle: u64 = 0;
    const status = sa_std_fs_open_write(path_ptr, path_len, 1, &handle);
    if (status != SA_STD_OK) return status;
    return sa_std_close(handle);
}

pub export fn sa_fs_file_close(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_file_read(handle: u64, out: ?[*]u8, cap: u64) i32 {
    return sa_std_read(handle, out, cap, null);
}

pub export fn sa_fs_file_read_exact(handle: u64, out: ?[*]u8, len: u64) i32 {
    return sa_io_read_exact(handle, out, len);
}

pub export fn sa_fs_file_write(handle: u64, out: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, out, len);
}

pub export fn sa_fs_file_write_all(handle: u64, out: ?[*]const u8, len: u64) i32 {
    return sa_io_write_all(handle, out, len);
}

pub export fn sa_fs_file_flush(handle: u64) i32 {
    _ = handle;
    return finish(SA_STD_OK);
}

pub export fn sa_fs_file_sync_data(handle: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            std.posix.fdatasync(f.inner.handle) catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_sync(handle: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            f.sync() catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_truncate(handle: u64, new_size: u64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            fileSetEndPos(f, new_size) catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_file_seek(handle: u64, whence: u32, offset: i64) i32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return finish(SA_STD_ERR_INVALID_HANDLE);
    return switch (resource.*) {
        .file => |f| {
            const seek_result = switch (whence) {
                0 => f.seekTo(@as(u64, @intCast(offset))),
                1 => fileSeekBy(f, offset),
                2 => fileSeekFromEnd(f, offset),
                else => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            };
            seek_result catch |err| return finishErr(err);
            return finish(SA_STD_OK);
        },
        else => finish(SA_STD_ERR_INVALID_HANDLE),
    };
}

pub export fn sa_fs_read_file(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const file = sio.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return fail(u64, mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return fail(u64, mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_read_to_string(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const file = sio.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return fail(u64, mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return fail(u64, mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return fail(u64, mapError(err));
    if (!std.unicode.utf8ValidateSlice(bytes)) {
        std.heap.page_allocator.free(bytes);
        return fail(u64, SA_STD_ERR_INVALID_ARGUMENT);
    }
    const handle = openOwnedByteBuffer(bytes) catch |err| return fail(u64, mapError(err));
    return ok(u64, handle);
}

pub export fn sa_fs_write_file(path_ptr: ?[*]const u8, path_len: u64, buf: ?[*]const u8, len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const bytes = constBytes(buf, len) catch |err| return finishErr(err);
    const file = sio.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |err| return finishErr(err);
    defer file.close();
    file.writeAll(bytes) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_read_buffer_data(handle: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .buffer => |*buf| buf.bytes.ptr,
        else => null,
    };
}

pub export fn sa_fs_read_buffer_len(handle: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .buffer => |*buf| @as(u64, @intCast(buf.bytes.len)),
        else => 0,
    };
}

pub export fn sa_fs_read_buffer_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_read_file_base64(path_ptr: ?[*]const u8, path_len: u64, max_bytes: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const file = sio.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return fail(u64, mapError(err));
    defer file.close();
    const cap = lenAsUsize(max_bytes) catch |err| return fail(u64, mapError(err));
    const bytes = file.readToEndAlloc(std.heap.page_allocator, cap) catch |err| return fail(u64, mapError(err));
    defer std.heap.page_allocator.free(bytes);
    const encoded_len = std.base64.standard.Encoder.calcSize(bytes.len);
    const encoded = std.heap.page_allocator.alloc(u8, encoded_len) catch |err| return fail(u64, mapError(err));
    _ = std.base64.standard.Encoder.encode(encoded, bytes);
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = encoded } }) catch |err| {
        std.heap.page_allocator.free(encoded);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
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

pub export fn sa_fs_read_dir_json(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    var dir = sio.cwd().openDir(path, .{ .iterate = true }) catch |err| return fail(u64, mapError(err));
    defer dir.close();

    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    const writer = listWriter(&out);
    writer.writeAll("{\"entries\":[") catch |err| return fail(u64, mapError(err));
    const limit = lenAsUsize(max_entries) catch |err| return fail(u64, mapError(err));
    var it = dir.iterate();
    var count: usize = 0;
    var first = true;
    while (count < limit) {
        const maybe_entry = it.next() catch |err| return fail(u64, mapError(err));
        const entry = maybe_entry orelse break;
        if (!first) writer.writeAll(",") catch |err| return fail(u64, mapError(err));
        first = false;
        writer.writeAll("{\"name\":") catch |err| return fail(u64, mapError(err));
        stringifyToList(writer.list, entry.name) catch |err| return fail(u64, mapError(err));
        writer.writeAll(",") catch |err| return fail(u64, mapError(err));
        writeJsonBoolField(writer, "isDirectory", entry.kind == .directory) catch |err| return fail(u64, mapError(err));
        writer.writeAll(",") catch |err| return fail(u64, mapError(err));
        writeJsonBoolField(writer, "isFile", entry.kind == .file) catch |err| return fail(u64, mapError(err));
        writer.writeAll("}") catch |err| return fail(u64, mapError(err));
        count += 1;
    }
    writer.writeAll("]}") catch |err| return fail(u64, mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
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

pub export fn sa_fs_read_dir_entries(path_ptr: ?[*]const u8, path_len: u64, max_entries: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const limit = lenAsUsize(max_entries) catch |err| return fail(u64, mapError(err));
    var entries = readDirEntriesLinux(path, limit) catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .dir_entries = entries }) catch |err| {
        entries.deinit();
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_dir_entries_len(handle: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entries => |*entries| @as(u64, @intCast(entries.entries.len)),
        else => 0,
    };
}

pub export fn sa_fs_dir_entries_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_dir_entry_name_ptr(handle: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return null;
    return switch (resource.*) {
        .dir_entry => |*entry| entry.name.ptr,
        else => null,
    };
}

pub export fn sa_fs_dir_entry_name_len(handle: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entry => |*entry| @as(u64, @intCast(entry.name.len)),
        else => 0,
    };
}

pub export fn sa_fs_dir_entry_file_name_ptr(handle: u64) ?[*]u8 {
    return sa_fs_dir_entry_name_ptr(handle);
}

pub export fn sa_fs_dir_entry_file_name_len(handle: u64) u64 {
    return sa_fs_dir_entry_name_len(handle);
}

pub export fn sa_fs_dir_entry_kind(handle: u64) u32 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entry => |*entry| entry.kind,
        else => 0,
    };
}

pub export fn sa_fs_dir_entry_ino(handle: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .dir_entry => |*entry| entry.ino,
        else => 0,
    };
}

pub export fn sa_fs_dir_entry_free(handle: u64) i32 {
    return sa_std_close(handle);
}

pub export fn sa_fs_metadata(path_ptr: ?[*]const u8, path_len: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const stx = lxStatxNoFollow(path) catch |err| return fail(u64, mapError(err));
    const stat = statFromRaw(stx);
    const handle = registerResource(.{ .metadata = .{ .allocator = std.heap.page_allocator, .stat = stat, .raw = stx } }) catch |err| return fail(u64, mapError(err));
    return ok(u64, handle);
}

pub const sa_fs_metadata_json = @import("fs_meta.zig").sa_fs_metadata_json;

pub const sa_fs_metadata_is_file = @import("fs_meta.zig").sa_fs_metadata_is_file;

pub const sa_fs_metadata_is_directory = @import("fs_meta.zig").sa_fs_metadata_is_directory;

pub const sa_fs_metadata_is_symlink = @import("fs_meta.zig").sa_fs_metadata_is_symlink;

pub const sa_fs_metadata_is_block_device = @import("fs_meta.zig").sa_fs_metadata_is_block_device;

pub const sa_fs_metadata_is_char_device = @import("fs_meta.zig").sa_fs_metadata_is_char_device;

pub const sa_fs_metadata_is_fifo = @import("fs_meta.zig").sa_fs_metadata_is_fifo;

pub const sa_fs_metadata_is_socket = @import("fs_meta.zig").sa_fs_metadata_is_socket;

pub const sa_fs_metadata_modified_ms = @import("fs_meta.zig").sa_fs_metadata_modified_ms;

pub const sa_fs_metadata_created_ms = @import("fs_meta.zig").sa_fs_metadata_created_ms;

pub const sa_fs_metadata_accessed_ms = @import("fs_meta.zig").sa_fs_metadata_accessed_ms;

pub const sa_fs_metadata_changed_ms = @import("fs_meta.zig").sa_fs_metadata_changed_ms;

pub const sa_fs_metadata_len = @import("fs_meta.zig").sa_fs_metadata_len;

pub const sa_fs_metadata_mode = @import("fs_meta.zig").sa_fs_metadata_mode;

pub const sa_fs_metadata_uid = @import("fs_meta.zig").sa_fs_metadata_uid;

pub const sa_fs_metadata_gid = @import("fs_meta.zig").sa_fs_metadata_gid;

pub const sa_fs_metadata_ino = @import("fs_meta.zig").sa_fs_metadata_ino;

pub const sa_fs_metadata_dev = @import("fs_meta.zig").sa_fs_metadata_dev;

pub const sa_fs_metadata_nlink = @import("fs_meta.zig").sa_fs_metadata_nlink;

pub const sa_fs_metadata_rdev = @import("fs_meta.zig").sa_fs_metadata_rdev;

pub const sa_fs_metadata_blksize = @import("fs_meta.zig").sa_fs_metadata_blksize;

pub const sa_fs_metadata_blocks = @import("fs_meta.zig").sa_fs_metadata_blocks;

pub const sa_fs_metadata_st_dev = @import("fs_meta.zig").sa_fs_metadata_st_dev;

pub const sa_fs_metadata_st_ino = @import("fs_meta.zig").sa_fs_metadata_st_ino;

pub const sa_fs_metadata_st_mode = @import("fs_meta.zig").sa_fs_metadata_st_mode;

pub const sa_fs_metadata_st_nlink = @import("fs_meta.zig").sa_fs_metadata_st_nlink;

pub const sa_fs_metadata_st_uid = @import("fs_meta.zig").sa_fs_metadata_st_uid;

pub const sa_fs_metadata_st_gid = @import("fs_meta.zig").sa_fs_metadata_st_gid;

pub const sa_fs_metadata_st_rdev = @import("fs_meta.zig").sa_fs_metadata_st_rdev;

pub const sa_fs_metadata_st_size = @import("fs_meta.zig").sa_fs_metadata_st_size;

pub const sa_fs_metadata_st_atime = @import("fs_meta.zig").sa_fs_metadata_st_atime;

pub const sa_fs_metadata_st_atime_nsec = @import("fs_meta.zig").sa_fs_metadata_st_atime_nsec;

pub const sa_fs_metadata_st_mtime = @import("fs_meta.zig").sa_fs_metadata_st_mtime;

pub const sa_fs_metadata_st_mtime_nsec = @import("fs_meta.zig").sa_fs_metadata_st_mtime_nsec;

pub const sa_fs_metadata_st_ctime = @import("fs_meta.zig").sa_fs_metadata_st_ctime;

pub const sa_fs_metadata_st_ctime_nsec = @import("fs_meta.zig").sa_fs_metadata_st_ctime_nsec;

pub const sa_fs_metadata_st_blksize = @import("fs_meta.zig").sa_fs_metadata_st_blksize;

pub const sa_fs_metadata_st_blocks = @import("fs_meta.zig").sa_fs_metadata_st_blocks;

pub const sa_fs_metadata_free = @import("fs_meta.zig").sa_fs_metadata_free;

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
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    mkdirPathWithMode(path, @as(std.posix.mode_t, @intCast(mode))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_mkdir_p(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    mkdirP(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_create_dir(path_ptr: ?[*]const u8, path_len: u64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().makeDir(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_create_dir_mode(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    lxMkdirat(std.posix.AT.FDCWD, path, @as(std.posix.mode_t, @intCast(mode))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
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
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    sio.cwd().deleteTree(path) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_copy_file(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    sio.cwd().copyFile(from, sio.cwd(), to, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_set_permissions(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    lxFchmodat(std.posix.AT.FDCWD, path, @as(std.posix.mode_t, @intCast(mode))) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_set_times_ms(path_ptr: ?[*]const u8, path_len: u64, accessed_ms: i64, modified_ms: i64) i32 {
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const atime = timespecFromUnixMs(accessed_ms) catch |err| return finishErr(err);
    const mtime = timespecFromUnixMs(modified_ms) catch |err| return finishErr(err);
    const file = sio.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return finishErr(err);
    defer file.close();
    var times = [2]Timespec{ atime, mtime };
    lxFutimens(file.inner.handle, &times) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_hard_link(from_path: ?[*]const u8, from_len: u64, to_path: ?[*]const u8, to_len: u64) i32 {
    const from = pathBytes(from_path, from_len) catch |err| return finishErr(err);
    const to = pathBytes(to_path, to_len) catch |err| return finishErr(err);
    lxLink(from, to) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_symlink(target_path: ?[*]const u8, target_len: u64, link_path: ?[*]const u8, link_len: u64) i32 {
    const target = pathBytes(target_path, target_len) catch |err| return finishErr(err);
    const link = pathBytes(link_path, link_len) catch |err| return finishErr(err);
    sio.cwd().symLink(target, link, .{}) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_chown(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    return chownPath(path_ptr, path_len, uid, gid, has_uid, has_gid, false);
}

pub export fn sa_fs_lchown(path_ptr: ?[*]const u8, path_len: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    return chownPath(path_ptr, path_len, uid, gid, has_uid, has_gid, true);
}

pub export fn sa_fs_fchown(handle: u64, uid: u32, gid: u32, has_uid: u32, has_gid: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const fd = handleToFd(handle) catch return finish(SA_STD_ERR_INVALID_HANDLE);
    if (comptime is_linux) {
        const rc = std.os.linux.fchown(fd, chownId(uid, has_uid), groupId(gid, has_gid));
        switch (std.os.linux.errno(rc)) {
            .INTR => return finish(SA_STD_ERR_IO),
            else => return finishChownErrno(rc),
        }
    }
    const rc = libc.fchown(fd, chownId(uid, has_uid), groupId(gid, has_gid));
    return finishErrnoAny(std.posix.errno(rc));
}

pub export fn sa_fs_chroot(path_ptr: ?[*]const u8, path_len: u64) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_z = std.posix.toPosixPath(path) catch |err| return finishErr(err);
    lxChroot(&path_z) catch |err| return finishErr(err);
    return finish(SA_STD_OK);
}

pub export fn sa_fs_mkfifo(path_ptr: ?[*]const u8, path_len: u64, mode: u32) i32 {
    if (comptime is_wasm) return finish(SA_STD_ERR_UNSUPPORTED);
    const path = pathBytes(path_ptr, path_len) catch |err| return finishErr(err);
    const path_z = std.posix.toPosixPath(path) catch |err| return finishErr(err);
    const file_mode: std.c.mode_t = @intCast(std.posix.S.IFIFO | mode);
    if (comptime is_linux) {
        const result = std.os.linux.mknodat(std.posix.AT.FDCWD, &path_z, std.posix.S.IFIFO | mode, 0);
        switch (std.os.linux.errno(result)) {
            .SUCCESS => return finish(SA_STD_OK),
            .INTR => return sa_fs_mkfifo(path_ptr, path_len, mode),
            .ACCES, .PERM => return finish(SA_STD_ERR_ACCESS),
            .EXIST => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            .NOENT => return finish(SA_STD_ERR_NOT_FOUND),
            .NAMETOOLONG, .INVAL => return finish(SA_STD_ERR_INVALID_ARGUMENT),
            else => return finish(SA_STD_ERR_IO),
        }
    }
    const result = libc.mknod(&path_z, file_mode, 0);
    if (std.posix.errno(result) == .INTR) return sa_fs_mkfifo(path_ptr, path_len, mode);
    return finishErrnoAny(std.posix.errno(result));
}

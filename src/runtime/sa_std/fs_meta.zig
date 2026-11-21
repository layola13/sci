const std = @import("std");
const sa_std = @import("../sa_std.zig");
const Fallible = @import("../sa_std.zig").Fallible;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const fail = @import("../sa_std.zig").fail;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const listWriter = @import("../sa_std.zig").listWriter;
const lxStatxNoFollow = @import("../sa_std.zig").lxStatxNoFollow;
const mapError = @import("../sa_std.zig").mapError;
const metadataI64TimeFieldMs = @import("../sa_std.zig").metadataI64TimeFieldMs;
const metadataI64TimeFieldNsec = @import("../sa_std.zig").metadataI64TimeFieldNsec;
const metadataI64TimeFieldSec = @import("../sa_std.zig").metadataI64TimeFieldSec;
const metadataModeMatches = @import("../sa_std.zig").metadataModeMatches;
const metadataU64Field = @import("../sa_std.zig").metadataU64Field;
const ok = @import("../sa_std.zig").ok;
const pathBytes = @import("../sa_std.zig").pathBytes;
const registerResource = @import("../sa_std.zig").registerResource;
const registry_mutex = @import("../sa_std.zig").registry_mutex;
const sa_std_close = @import("../sa_std.zig").sa_std_close;
const statFromRaw = @import("../sa_std.zig").statFromRaw;
const tsToMs = @import("../sa_std.zig").tsToMs;
const writeMetadataJsonExt = @import("../sa_std.zig").writeMetadataJsonExt;

pub export fn sa_fs_metadata_json(path_ptr: ?[*]const u8, path_len: u64) Fallible(u64) {
    const path = pathBytes(path_ptr, path_len) catch |err| return fail(u64, mapError(err));
    const stx = lxStatxNoFollow(path) catch |err| return fail(u64, mapError(err));
    const stat = statFromRaw(stx);
    var out = std.array_list.Managed(u8).init(std.heap.page_allocator);
    errdefer out.deinit();
    writeMetadataJsonExt(listWriter(&out), stat, stx) catch |err| return fail(u64, mapError(err));
    const bytes = out.toOwnedSlice() catch |err| return fail(u64, mapError(err));
    const handle = registerResource(.{ .buffer = .{ .allocator = std.heap.page_allocator, .bytes = bytes } }) catch |err| {
        std.heap.page_allocator.free(bytes);
        return fail(u64, mapError(err));
    };
    return ok(u64, handle);
}

pub export fn sa_fs_metadata_is_file(handle: u64) u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if (metadata.stat.kind == .file) 1 else 0,
        else => 0,
    };
}

pub export fn sa_fs_metadata_is_directory(handle: u64) u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if (metadata.stat.kind == .directory) 1 else 0,
        else => 0,
    };
}

pub export fn sa_fs_metadata_is_symlink(handle: u64) u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| if (metadata.stat.kind == .sym_link) 1 else 0,
        else => 0,
    };
}

pub export fn sa_fs_metadata_is_block_device(handle: u64) u8 {
    return metadataModeMatches(handle, std.posix.S.IFBLK);
}

pub export fn sa_fs_metadata_is_char_device(handle: u64) u8 {
    return metadataModeMatches(handle, std.posix.S.IFCHR);
}

pub export fn sa_fs_metadata_is_fifo(handle: u64) u8 {
    return metadataModeMatches(handle, std.posix.S.IFIFO);
}

pub export fn sa_fs_metadata_is_socket(handle: u64) u8 {
    return metadataModeMatches(handle, std.posix.S.IFSOCK);
}

pub export fn sa_fs_metadata_modified_ms(handle: u64) i64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| tsToMs(metadata.stat.mtime),
        else => 0,
    };
}

pub export fn sa_fs_metadata_created_ms(handle: u64) i64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| tsToMs(metadata.stat.ctime),
        else => 0,
    };
}

pub export fn sa_fs_metadata_accessed_ms(handle: u64) i64 {
    return metadataI64TimeFieldMs(handle, "atim");
}

pub export fn sa_fs_metadata_changed_ms(handle: u64) i64 {
    return metadataI64TimeFieldMs(handle, "ctim");
}

pub export fn sa_fs_metadata_len(handle: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| metadata.stat.size,
        else => 0,
    };
}

pub export fn sa_fs_metadata_mode(handle: u64) u32 {
    return @as(u32, @intCast(metadataU64Field(handle, "mode")));
}

pub export fn sa_fs_metadata_uid(handle: u64) u32 {
    return @as(u32, @intCast(metadataU64Field(handle, "uid")));
}

pub export fn sa_fs_metadata_gid(handle: u64) u32 {
    return @as(u32, @intCast(metadataU64Field(handle, "gid")));
}

pub export fn sa_fs_metadata_ino(handle: u64) u64 {
    return metadataU64Field(handle, "ino");
}

pub export fn sa_fs_metadata_dev(handle: u64) u64 {
    return metadataU64Field(handle, "dev");
}

pub export fn sa_fs_metadata_nlink(handle: u64) u64 {
    return metadataU64Field(handle, "nlink");
}

pub export fn sa_fs_metadata_rdev(handle: u64) u64 {
    return metadataU64Field(handle, "rdev");
}

pub export fn sa_fs_metadata_blksize(handle: u64) u64 {
    return metadataU64Field(handle, "blksize");
}

pub export fn sa_fs_metadata_blocks(handle: u64) u64 {
    return metadataU64Field(handle, "blocks");
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

pub export fn sa_fs_metadata_st_atime(handle: u64) i64 {
    return metadataI64TimeFieldSec(handle, "atim");
}

pub export fn sa_fs_metadata_st_atime_nsec(handle: u64) i64 {
    return metadataI64TimeFieldNsec(handle, "atim");
}

pub export fn sa_fs_metadata_st_mtime(handle: u64) i64 {
    return metadataI64TimeFieldSec(handle, "mtim");
}

pub export fn sa_fs_metadata_st_mtime_nsec(handle: u64) i64 {
    return metadataI64TimeFieldNsec(handle, "mtim");
}

pub export fn sa_fs_metadata_st_ctime(handle: u64) i64 {
    return metadataI64TimeFieldSec(handle, "ctim");
}

pub export fn sa_fs_metadata_st_ctime_nsec(handle: u64) i64 {
    return metadataI64TimeFieldNsec(handle, "ctim");
}

pub export fn sa_fs_metadata_st_blksize(handle: u64) u64 {
    return sa_fs_metadata_blksize(handle);
}

pub export fn sa_fs_metadata_st_blocks(handle: u64) u64 {
    return sa_fs_metadata_blocks(handle);
}

pub export fn sa_fs_metadata_free(handle: u64) Fallible(i32) {
    const status = sa_std_close(handle);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

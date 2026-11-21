const std = @import("std");
pub const sa_std = @import("../sa_std.zig");
pub const SA_FS_FILE_DIR = @import("../sa_std.zig").SA_FS_FILE_DIR;
pub const SA_FS_FILE_OTHER = @import("../sa_std.zig").SA_FS_FILE_OTHER;
pub const SA_FS_FILE_REGULAR = @import("../sa_std.zig").SA_FS_FILE_REGULAR;
pub const SA_FS_FILE_SYMLINK = @import("../sa_std.zig").SA_FS_FILE_SYMLINK;
pub const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const is_linux = @import("../sa_std.zig").is_linux;
pub const is_wasm = @import("../sa_std.zig").is_wasm;
pub const lxCheck = @import("../sa_std.zig").lxCheck;
pub const lxClose = @import("../sa_std.zig").lxClose;
pub const sio = @import("../sa_std.zig").sio;

pub const MetadataHandle = struct {
    allocator: std.mem.Allocator,
    stat: sio.Stat,
    raw: RawStat,

    pub fn deinit(self: *MetadataHandle) void {
        _ = self;
    }
};

pub const DirEntrySnapshot = struct {
    name: []u8,
    kind: u32,
    ino: u64,
};

pub const DirEntriesHandle = struct {
    allocator: std.mem.Allocator,
    entries: []DirEntrySnapshot,

    pub fn deinit(self: *DirEntriesHandle) void {
        for (self.entries) |entry| {
            if (entry.name.len != 0) self.allocator.free(entry.name);
        }
        if (self.entries.len != 0) self.allocator.free(self.entries);
        self.entries = &.{};
    }
};

pub fn statTimeFieldName(comptime field: []const u8) []const u8 {
    // statx names fields atime/mtime/ctime/btime.
    if (std.mem.eql(u8, field, "atim")) return "atime";
    if (std.mem.eql(u8, field, "mtim")) return "mtime";
    if (std.mem.eql(u8, field, "ctim")) return "ctime";
    return field;
}

pub fn timeSpecMs(ts: anytype) i64 {
    const sec = @as(i128, @intCast(ts.sec));
    const nsec = @as(i128, @intCast(ts.nsec));
    return nsToMs(sec * std.time.ns_per_s + nsec);
}

pub fn metadataU64Field(handle: u64, comptime field: []const u8) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| blk: {
            const Which = enum { mode, uid, gid, ino, nlink, size, blocks, blksize, dev, rdev };
            const which: Which = comptime std.meta.stringToEnum(Which, field) orelse @compileError("unknown metadata u64 field: " ++ field);
            const raw = &metadata.raw;
            break :blk switch (which) {
                .mode => @as(u64, raw.mode),
                .uid => @as(u64, raw.uid),
                .gid => @as(u64, raw.gid),
                .ino => @as(u64, raw.ino),
                .nlink => @as(u64, raw.nlink),
                .size => @as(u64, raw.size),
                .blocks => @as(u64, raw.blocks),
                .blksize => @as(u64, raw.blksize),
                .dev => statxDevId(raw.dev_major, raw.dev_minor),
                .rdev => statxDevId(raw.rdev_major, raw.rdev_minor),
            };
        },
        else => 0,
    };
}

pub fn metadataI64TimeFieldMs(handle: u64, comptime field: []const u8) i64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| timeSpecMs(@field(metadata.raw, statTimeFieldName(field))),
        else => 0,
    };
}

pub fn metadataI64TimeFieldSec(handle: u64, comptime field: []const u8) i64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| @as(i64, @intCast(@field(metadata.raw, statTimeFieldName(field)).sec)),
        else => 0,
    };
}

pub fn metadataI64TimeFieldNsec(handle: u64, comptime field: []const u8) i64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return 0;
    return switch (resource.*) {
        .metadata => |*metadata| @as(i64, @intCast(@field(metadata.raw, statTimeFieldName(field)).nsec)),
        else => 0,
    };
}

pub const RawStat = struct {
    ino: u64,
    nlink: u64,
    size: u64,
    mode: u16,
    uid: u32,
    gid: u32,
    dev_major: u32,
    dev_minor: u32,
    rdev_major: u32,
    rdev_minor: u32,
    blksize: u32,
    blocks: u64,
    atime: RawTs,
    mtime: RawTs,
    ctime: RawTs,

    const RawTs = struct { sec: i64, nsec: u32 };
};

pub fn timestampToRawTs(ts: std.Io.Timestamp) RawStat.RawTs {
    const total = @as(i128, ts.toNanoseconds());
    const sec = @divFloor(total, std.time.ns_per_s);
    const nsec = total - sec * std.time.ns_per_s;
    return .{ .sec = @intCast(sec), .nsec = @intCast(nsec) };
}

pub fn kindModeBits(kind: std.Io.File.Kind) u32 {
    return switch (kind) {
        .directory => std.posix.S.IFDIR,
        .file => std.posix.S.IFREG,
        .sym_link => std.posix.S.IFLNK,
        .named_pipe => std.posix.S.IFIFO,
        .character_device => std.posix.S.IFCHR,
        .block_device => std.posix.S.IFBLK,
        .unix_domain_socket => std.posix.S.IFSOCK,
        else => 0,
    };
}

pub fn rawStatFromIo(st: sio.Stat) RawStat {
    const perm = @as(u32, @intCast(@backingInt(st.permissions)));
    const epoch: RawStat.RawTs = .{ .sec = 0, .nsec = 0 };
    return .{
        .ino = @intCast(st.inode),
        .nlink = @intCast(st.nlink),
        .size = st.size,
        .mode = @intCast(perm | kindModeBits(st.kind)),
        .uid = 0,
        .gid = 0,
        .dev_major = 0,
        .dev_minor = 0,
        .rdev_major = 0,
        .rdev_minor = 0,
        .blksize = @intCast(st.block_size),
        .blocks = (st.size + 511) / 512,
        .atime = if (st.atime) |t| timestampToRawTs(t) else epoch,
        .mtime = timestampToRawTs(st.mtime),
        .ctime = timestampToRawTs(st.ctime),
    };
}

pub fn lxStatxNoFollow(path: []const u8) !RawStat {
    if (comptime is_wasm) return error.Unsupported;
    if (comptime is_linux) {
        const z = try std.posix.toPosixPath(path);
        var stx: std.os.linux.Statx = undefined;
        _ = try lxCheck(std.os.linux.statx(std.posix.AT.FDCWD, &z, 0x100, std.os.linux.STATX.BASIC_STATS, &stx));
        return .{
            .ino = stx.ino,
            .nlink = stx.nlink,
            .size = stx.size,
            .mode = stx.mode,
            .uid = stx.uid,
            .gid = stx.gid,
            .dev_major = stx.dev_major,
            .dev_minor = stx.dev_minor,
            .rdev_major = stx.rdev_major,
            .rdev_minor = stx.rdev_minor,
            .blksize = stx.blksize,
            .blocks = stx.blocks,
            .atime = .{ .sec = @intCast(stx.atime.sec), .nsec = stx.atime.nsec },
            .mtime = .{ .sec = @intCast(stx.mtime.sec), .nsec = stx.mtime.nsec },
            .ctime = .{ .sec = @intCast(stx.ctime.sec), .nsec = stx.ctime.nsec },
        };
    }
    const st = try sio.cwd().inner.statFile(sio.io(), path, .{ .follow_symlinks = false });
    return rawStatFromIo(st);
}

pub fn statFromRaw(raw: RawStat) sio.Stat {
    const kind: std.Io.File.Kind = switch (raw.mode & std.posix.S.IFMT) {
        std.posix.S.IFDIR => .directory,
        std.posix.S.IFREG => .file,
        std.posix.S.IFLNK => .sym_link,
        std.posix.S.IFIFO => .named_pipe,
        std.posix.S.IFCHR => .character_device,
        std.posix.S.IFBLK => .block_device,
        std.posix.S.IFSOCK => .unix_domain_socket,
        else => .unknown,
    };
    return .{
        .inode = raw.ino,
        .nlink = @intCast(raw.nlink),
        .size = raw.size,
        .permissions = @fromBackingInt(@intCast(@as(std.posix.mode_t, @intCast(raw.mode)))),
        .kind = kind,
        .atime = .{ .nanoseconds = @as(i96, raw.atime.sec) * std.time.ns_per_s + @as(i96, raw.atime.nsec) },
        .mtime = .{ .nanoseconds = @as(i96, raw.mtime.sec) * std.time.ns_per_s + @as(i96, raw.mtime.nsec) },
        .ctime = .{ .nanoseconds = @as(i96, raw.ctime.sec) * std.time.ns_per_s + @as(i96, raw.ctime.nsec) },
        .block_size = raw.blksize,
    };
}

pub fn statxDevId(major: u32, minor: u32) u64 {
    return (@as(u64, major) << 32) | @as(u64, minor);
}

pub fn tsToMs(ts: std.Io.Timestamp) i64 {
    return nsToMs(@as(i128, ts.toNanoseconds()));
}

pub fn writeJsonBoolField(writer: anytype, name: []const u8, value: bool) !void {
    try writer.writeAll("\"");
    try writer.writeAll(name);
    try writer.writeAll("\":");
    try writer.writeAll(if (value) "true" else "false");
}

pub fn nsToMs(ns: i128) i64 {
    const ms = @divTrunc(ns, std.time.ns_per_ms);
    if (ms > std.math.maxInt(i64)) return std.math.maxInt(i64);
    if (ms < std.math.minInt(i64)) return std.math.minInt(i64);
    return @intCast(ms);
}

pub fn writeJsonIntField(writer: anytype, name: []const u8, value: anytype) !void {
    try writer.writeAll("\"");
    try writer.writeAll(name);
    try writer.writeAll("\":");
    try writer.print("{}", .{value});
}

pub fn writeMetadataJson(writer: anytype, stat: sio.Stat) !void {
    try writer.writeAll("{");
    try writeJsonIntField(writer, "createdAtMs", tsToMs(stat.ctime));
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isDirectory", stat.kind == .directory);
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isFile", stat.kind == .file);
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isSymlink", stat.kind == .sym_link);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "modifiedAtMs", tsToMs(stat.mtime));
    try writer.writeAll("}");
}

pub fn writeMetadataJsonExt(writer: anytype, stat: sio.Stat, raw: RawStat) !void {
    try writer.writeAll("{");
    try writeJsonIntField(writer, "createdAtMs", tsToMs(stat.ctime));
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isDirectory", stat.kind == .directory);
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isFile", stat.kind == .file);
    try writer.writeAll(",");
    try writeJsonBoolField(writer, "isSymlink", stat.kind == .sym_link);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "modifiedAtMs", tsToMs(stat.mtime));
    try writer.writeAll(",");
    try writeJsonIntField(writer, "accessedAtMs", timeSpecMs(raw.atime));
    try writer.writeAll(",");
    try writeJsonIntField(writer, "changedAtMs", timeSpecMs(raw.ctime));
    try writer.writeAll(",");
    try writeJsonIntField(writer, "size", raw.size);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "mode", raw.mode);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "uid", raw.uid);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "gid", raw.gid);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "dev", statxDevId(raw.dev_major, raw.dev_minor));
    try writer.writeAll(",");
    try writeJsonIntField(writer, "ino", raw.ino);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "nlink", raw.nlink);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "rdev", statxDevId(raw.rdev_major, raw.rdev_minor));
    try writer.writeAll(",");
    try writeJsonIntField(writer, "blksize", raw.blksize);
    try writer.writeAll(",");
    try writeJsonIntField(writer, "blocks", raw.blocks);
    try writer.writeAll("}");
}

pub fn dirEntryKindFromLinuxType(kind: u8) u32 {
    return switch (kind) {
        std.posix.DT.REG => SA_FS_FILE_REGULAR,
        std.posix.DT.DIR => SA_FS_FILE_DIR,
        std.posix.DT.LNK => SA_FS_FILE_SYMLINK,
        else => SA_FS_FILE_OTHER,
    };
}

pub fn dirEntryKindFromIo(kind: std.Io.File.Kind) u32 {
    return switch (kind) {
        .file => SA_FS_FILE_REGULAR,
        .directory => SA_FS_FILE_DIR,
        .sym_link => SA_FS_FILE_SYMLINK,
        else => SA_FS_FILE_OTHER,
    };
}

pub fn readDirEntriesLinux(path: []const u8, max_entries: usize) !DirEntriesHandle {
    if (comptime is_wasm) return error.Unsupported;

    var out = std.array_list.Managed(DirEntrySnapshot).init(std.heap.page_allocator);
    errdefer {
        for (out.items) |entry| if (entry.name.len != 0) std.heap.page_allocator.free(entry.name);
        out.deinit();
    }

    if (comptime is_linux) {
        const flags: std.posix.O = .{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true };
        const fd = try std.posix.openat(std.posix.AT.FDCWD, path, flags, 0);
        defer lxClose(fd);

        var buf: [4096]u8 = undefined;
        while (out.items.len < max_entries) {
            const rc = std.os.linux.getdents64(fd, &buf, buf.len);
            switch (std.os.linux.errno(rc)) {
                .SUCCESS => {},
                .BADF => unreachable,
                .FAULT => unreachable,
                .NOTDIR => unreachable,
                .NOENT => return error.FileNotFound,
                .INVAL => return error.Unexpected,
                .ACCES => return error.AccessDenied,
                else => |err| return std.posix.unexpectedErrno(err),
            }
            if (rc == 0) break;

            var index: usize = 0;
            while (index < rc and out.items.len < max_entries) {
                const linux_entry = @as(*align(1) std.os.linux.dirent64, @ptrCast(&buf[index]));
                index += linux_entry.reclen;

                const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&linux_entry.name)), 0);
                if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

                const owned_name = try std.heap.page_allocator.dupe(u8, name);
                errdefer std.heap.page_allocator.free(owned_name);
                // getdents d_ino is not canonical on all filesystems:
                // on overlayfs a directory entry's d_ino differs from
                // the inode statx reports for the same path, while
                // FS_METADATA_INO reports the statx inode. Resolve
                // through statx so FS_DIR_ENTRY_INO agrees with
                // FS_METADATA_INO; fall back to d_ino when the entry
                // cannot be statted (it vanished mid-read, or the
                // joined path is too long).
                var entry_ino: u64 = linux_entry.ino;
                {
                    var full_buf: [std.posix.PATH_MAX]u8 = undefined;
                    const full_path = std.fmt.bufPrint(
                        &full_buf,
                        "{s}/{s}",
                        .{ std.mem.trimEnd(u8, path, "/"), name },
                    ) catch null;
                    if (full_path) |fp| {
                        if (lxStatxNoFollow(fp)) |stx| {
                            entry_ino = stx.ino;
                        } else |_| {}
                    }
                }
                try out.append(.{
                    .name = owned_name,
                    .kind = dirEntryKindFromLinuxType(linux_entry.type),
                    .ino = entry_ino,
                });
            }
        }
    } else {
        var dir = try sio.cwd().openDir(path, .{ .iterate = true });
        defer dir.close();
        var it = dir.iterate();
        while (out.items.len < max_entries) {
            const next = try it.next();
            const entry = next orelse break;
            if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
            const owned_name = try std.heap.page_allocator.dupe(u8, entry.name);
            errdefer std.heap.page_allocator.free(owned_name);
            try out.append(.{
                .name = owned_name,
                .kind = dirEntryKindFromIo(entry.kind),
                .ino = @intCast(entry.inode),
            });
        }
    }

    return .{ .allocator = std.heap.page_allocator, .entries = try out.toOwnedSlice() };
}

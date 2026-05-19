const std = @import("std");

pub const defaultSegmentSize: u64 = 256 * 1024 * 1024;

const record_alignment: usize = 8;
const record_header_size: usize = 16;
const handle_segment_shift: u6 = 40;
const handle_offset_mask: u64 = (@as(u64, 1) << handle_segment_shift) - 1;
const handle_segment_mask: u64 = (@as(u64, 1) << 24) - 1;

pub const BlobError = error{
    OutOfMemory,
    InvalidFormat,
    InvalidPath,
    NotFound,
    InvalidHandle,
    CapacityOverflow,
};

pub const BlobHandle = u64;

pub const HandleParts = struct {
    segment_id: u32,
    offset: u64,
};

pub const OpenOptions = struct {
    segment_size: u64 = defaultSegmentSize,
};

pub const HandleRemap = struct {
    old_handle: BlobHandle,
    new_handle: BlobHandle,
};

pub const CompactionResult = struct {
    rewritten_segments: usize,
    moved_records: usize,
    remaps: []HandleRemap,

    pub fn deinit(self: *CompactionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.remaps);
        self.* = undefined;
    }
};

const MetaFile = struct {
    magic: []const u8,
    version: u32,
    table_name: []const u8,
    segment_size: u64,
    next_segment_id: u32,
    segment_ids: []u32,
};

const Record = struct {
    handle: BlobHandle,
    len: u64,
    tombstone: bool,
    record_start: u64,
    payload_start: u64,
    record_bytes: u64,
};

const Segment = struct {
    id: u32,
    capacity: u64,
    used: u64,
    live_bytes: u64,
    dead_bytes: u64,
    path: []u8,
    file: std.fs.File,
    map: []align(std.heap.page_size_min) u8,
    records: std.ArrayList(Record),

    fn deinit(self: *Segment, allocator: std.mem.Allocator) void {
        self.records.deinit();
        std.posix.munmap(self.map);
        self.file.close();
        allocator.free(self.path);
        self.* = undefined;
    }

    fn flush(self: *Segment) BlobError!void {
        std.posix.msync(self.map, std.posix.MSF.SYNC) catch |err| return mapSyncError(err);
        self.file.sync() catch |err| return mapFileError(err);
    }
};

pub const BlobArena = struct {
    allocator: std.mem.Allocator,
    root_dir: []u8,
    table_name: []u8,
    segment_size: u64,
    next_segment_id: u32,
    segments: std.ArrayList(Segment),

    pub fn open(
        allocator: std.mem.Allocator,
        root_dir: []const u8,
        table_name: []const u8,
        options: OpenOptions,
    ) BlobError!BlobArena {
        if (options.segment_size == 0 or options.segment_size > handle_offset_mask) return BlobError.CapacityOverflow;
        const owned_root = try allocator.dupe(u8, root_dir);
        errdefer allocator.free(owned_root);
        const owned_table = try allocator.dupe(u8, table_name);
        errdefer allocator.free(owned_table);

        var arena = BlobArena{
            .allocator = allocator,
            .root_dir = owned_root,
            .table_name = owned_table,
            .segment_size = options.segment_size,
            .next_segment_id = 0,
            .segments = std.ArrayList(Segment).init(allocator),
        };
        errdefer arena.deinit();

        if (try arena.loadMeta()) |meta| {
            defer freeMeta(allocator, meta);
            if (!std.mem.eql(u8, meta.magic, "sa-db-blob-meta")) return BlobError.InvalidFormat;
            if (meta.version != 1) return BlobError.InvalidFormat;
            if (!std.mem.eql(u8, meta.table_name, owned_table)) return BlobError.InvalidFormat;
            if (meta.segment_size == 0 or meta.segment_size > handle_offset_mask) return BlobError.InvalidFormat;
            arena.segment_size = meta.segment_size;
            arena.next_segment_id = meta.next_segment_id;
            var max_seen: u32 = 0;
            var have_seen = false;
            for (meta.segment_ids) |segment_id| {
                if (segment_id > @as(u32, @intCast(handle_segment_mask))) return BlobError.InvalidFormat;
                const segment = try arena.openSegment(segment_id, arena.segment_size);
                try arena.segments.append(segment);
                if (!have_seen or segment_id > max_seen) {
                    max_seen = segment_id;
                    have_seen = true;
                }
            }
            if (have_seen and arena.next_segment_id <= max_seen) {
                arena.next_segment_id = max_seen + 1;
            }
        }

        return arena;
    }

    pub fn deinit(self: *BlobArena) void {
        for (self.segments.items) |*segment| {
            segment.deinit(self.allocator);
        }
        self.segments.deinit();
        self.allocator.free(self.root_dir);
        self.allocator.free(self.table_name);
        self.* = undefined;
    }

    pub fn allocateText(self: *BlobArena, bytes: []const u8) BlobError!BlobHandle {
        if (bytes.len == 0) return BlobError.InvalidFormat;
        if (bytes.len > handle_offset_mask - record_header_size) return BlobError.CapacityOverflow;
        var index: usize = if (self.segments.items.len == 0) 0 else self.segments.items.len - 1;
        if (self.segments.items.len == 0 or !self.segmentHasRoom(&self.segments.items[index], bytes.len)) {
            try self.appendNewSegment();
            index = self.segments.items.len - 1;
        }
        const handle = try self.appendRecordToSegment(&self.segments.items[index], bytes);
        try self.persistMeta();
        return handle;
    }

    pub fn readText(self: *const BlobArena, handle: BlobHandle) BlobError![]const u8 {
        const lookup = try self.lookupHandle(handle);
        const segment = &self.segments.items[lookup.segment_index];
        const record = segment.records.items[lookup.record_index];
        if (record.tombstone) return BlobError.InvalidHandle;
        return segment.map[@as(usize, @intCast(record.payload_start)) .. @as(usize, @intCast(record.payload_start + record.len))];
    }

    pub fn delete(self: *BlobArena, handle: BlobHandle) BlobError!void {
        const lookup = try self.lookupHandle(handle);
        const segment = &self.segments.items[lookup.segment_index];
        const record = &segment.records.items[lookup.record_index];
        if (record.tombstone) return BlobError.InvalidHandle;

        const tombstone_offset = @as(usize, @intCast(record.record_start));
        segment.map[tombstone_offset] = 1;
        record.tombstone = true;
        segment.live_bytes -= record.record_bytes;
        segment.dead_bytes += record.record_bytes;
        try segment.flush();
        try self.persistMeta();
    }

    pub fn compact(self: *BlobArena) BlobError!CompactionResult {
        var remaps = std.ArrayList(HandleRemap).init(self.allocator);
        errdefer remaps.deinit();

        var rewritten_segments: usize = 0;
        var moved_records: usize = 0;

        var i: usize = 0;
        while (i < self.segments.items.len) : (i += 1) {
            if (!self.segmentNeedsCompaction(self.segments.items[i])) continue;
            var report = try self.compactSegmentAtIndex(i);
            rewritten_segments += 1;
            moved_records += report.moved_records;
            try remaps.appendSlice(report.remaps);
            report.deinit(self.allocator);
        }

        if (rewritten_segments != 0) try self.persistMeta();
        return .{
            .rewritten_segments = rewritten_segments,
            .moved_records = moved_records,
            .remaps = try remaps.toOwnedSlice(),
        };
    }

    pub fn segmentCount(self: *const BlobArena) usize {
        return self.segments.items.len;
    }

    pub fn segmentDeathRatio(self: *const BlobArena, segment_index: usize) f64 {
        const segment = self.segments.items[segment_index];
        if (segment.used == 0) return 0;
        return @as(f64, @floatFromInt(segment.dead_bytes)) / @as(f64, @floatFromInt(segment.used));
    }

    fn loadMeta(self: *BlobArena) BlobError!?MetaFile {
        const path = try self.metaPath();
        defer self.allocator.free(path);
        const source = readFileAlloc(self.allocator, path, 16 * 1024 * 1024) catch |err| switch (err) {
            BlobError.NotFound => return null,
            else => return err,
        };
        defer self.allocator.free(source);
        const parsed = std.json.parseFromSlice(MetaFile, self.allocator, source, .{}) catch |err| return mapJsonError(err);
        defer parsed.deinit();
        return try cloneMetaFile(self.allocator, parsed.value);
    }

    fn persistMeta(self: *BlobArena) BlobError!void {
        var segment_ids = try self.allocator.alloc(u32, self.segments.items.len);
        errdefer self.allocator.free(segment_ids);
        for (self.segments.items, 0..) |segment, idx| {
            segment_ids[idx] = segment.id;
        }

        const meta = MetaFile{
            .magic = "sa-db-blob-meta",
            .version = 1,
            .table_name = self.table_name,
            .segment_size = self.segment_size,
            .next_segment_id = self.next_segment_id,
            .segment_ids = segment_ids,
        };

        const json = std.json.stringifyAlloc(self.allocator, meta, .{}) catch |err| return mapJsonError(err);
        defer self.allocator.free(json);
        self.allocator.free(segment_ids);

        const path = try self.metaPath();
        defer self.allocator.free(path);
        try writeFile(path, json);
    }

    fn metaPath(self: *const BlobArena) BlobError![]u8 {
        const basename = try std.fmt.allocPrint(self.allocator, "{s}.blob.meta", .{self.table_name});
        defer self.allocator.free(basename);
        return try activePath(self.allocator, self.root_dir, basename);
    }

    fn segmentPath(self: *const BlobArena, id: u32) BlobError![]u8 {
        const basename = try std.fmt.allocPrint(self.allocator, "{s}.blob.{d}.bin", .{ self.table_name, id });
        defer self.allocator.free(basename);
        return try activePath(self.allocator, self.root_dir, basename);
    }

    fn appendNewSegment(self: *BlobArena) BlobError!void {
        if (self.next_segment_id > handle_segment_mask) return BlobError.CapacityOverflow;
        const segment = try self.openSegment(self.next_segment_id, self.segment_size);
        self.next_segment_id += 1;
        try self.segments.append(segment);
    }

    fn openSegment(self: *BlobArena, id: u32, capacity: u64) BlobError!Segment {
        const path = try self.segmentPath(id);
        errdefer self.allocator.free(path);
        var file = openSegmentFile(path, capacity) catch |err| return err;
        errdefer file.close();

        const mapped = std.posix.mmap(
            null,
            @as(usize, @intCast(capacity)),
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        ) catch |err| switch (err) {
            error.OutOfMemory => return BlobError.OutOfMemory,
            else => return BlobError.InvalidFormat,
        };

        var segment = Segment{
            .id = id,
            .capacity = capacity,
            .used = 0,
            .live_bytes = 0,
            .dead_bytes = 0,
            .path = path,
            .file = file,
            .map = mapped,
            .records = std.ArrayList(Record).init(self.allocator),
        };
        errdefer segment.deinit(self.allocator);

        try self.scanSegment(&segment);
        try segment.flush();
        return segment;
    }

    fn scanSegment(self: *BlobArena, segment: *Segment) BlobError!void {
        _ = self;
        var pos: usize = 0;
        while (pos + record_header_size <= segment.map.len) {
            pos = std.mem.alignForward(usize, pos, record_alignment);
            if (pos + record_header_size > segment.map.len) break;
            const header = segment.map[pos .. pos + record_header_size];
            if (isZero(header)) break;
            const len = std.mem.readInt(u64, header[8..16], .little);
            if (len == 0) return BlobError.InvalidFormat;
            const payload_start = pos + record_header_size;
            const payload_end = payload_start + @as(usize, @intCast(len));
            if (payload_end > segment.map.len) return BlobError.InvalidFormat;
            const record_end = std.mem.alignForward(usize, payload_end, record_alignment);
            const handle = try packHandle(segment.id, @as(u64, @intCast(payload_start)));
            const tombstone = header[0] != 0;
            const record = Record{
                .handle = handle,
                .len = len,
                .tombstone = tombstone,
                .record_start = pos,
                .payload_start = payload_start,
                .record_bytes = @as(u64, @intCast(record_end - pos)),
            };
            try segment.records.append(record);
            segment.used = @as(u64, @intCast(record_end));
            if (tombstone) {
                segment.dead_bytes += record.record_bytes;
            } else {
                segment.live_bytes += record.record_bytes;
            }
            pos = record_end;
        }
    }

    fn segmentHasRoom(self: *const BlobArena, segment: *const Segment, len: usize) bool {
        _ = self;
        const start = std.mem.alignForward(usize, @as(usize, @intCast(segment.used)), record_alignment);
        const end = start + record_header_size + len;
        const rounded = std.mem.alignForward(usize, end, record_alignment);
        return rounded <= segment.map.len;
    }

    fn appendRecordToSegment(self: *BlobArena, segment: *Segment, bytes: []const u8) BlobError!BlobHandle {
        _ = self;
        const start = std.mem.alignForward(usize, @as(usize, @intCast(segment.used)), record_alignment);
        const payload_start = start + record_header_size;
        const payload_end = payload_start + bytes.len;
        const next_used = std.mem.alignForward(usize, payload_end, record_alignment);
        if (next_used > segment.capacity) return BlobError.OutOfMemory;

        const header = segment.map[start .. start + record_header_size];
        header[0] = 0;
        @memset(header[1..8], 0);
        std.mem.writeInt(u64, header[8..16], @as(u64, @intCast(bytes.len)), .little);
        std.mem.copyForwards(u8, segment.map[payload_start .. payload_end], bytes);
        if (next_used > payload_end) @memset(segment.map[payload_end .. next_used], 0);

        const handle = try packHandle(segment.id, @as(u64, @intCast(payload_start)));
        const record_bytes = @as(u64, @intCast(next_used - start));
        try segment.records.append(.{
            .handle = handle,
            .len = @as(u64, @intCast(bytes.len)),
            .tombstone = false,
            .record_start = @as(u64, @intCast(start)),
            .payload_start = @as(u64, @intCast(payload_start)),
            .record_bytes = record_bytes,
        });
        segment.used = @as(u64, @intCast(next_used));
        segment.live_bytes += record_bytes;
        try segment.flush();
        return handle;
    }

    fn lookupHandle(self: *const BlobArena, handle: BlobHandle) BlobError!struct { segment_index: usize, record_index: usize } {
        const parts = unpackHandle(handle);
        if (parts.segment_id > handle_segment_mask) return BlobError.InvalidHandle;
        for (self.segments.items, 0..) |segment, seg_idx| {
            if (segment.id != parts.segment_id) continue;
            if (parts.offset < record_header_size or parts.offset >= segment.capacity) return BlobError.InvalidHandle;
            for (segment.records.items, 0..) |record, rec_idx| {
                if (record.handle == handle) return .{ .segment_index = seg_idx, .record_index = rec_idx };
            }
            return BlobError.InvalidHandle;
        }
        return BlobError.InvalidHandle;
    }

    fn segmentNeedsCompaction(self: *const BlobArena, segment: Segment) bool {
        _ = self;
        if (segment.used == 0 or segment.records.items.len == 0) return false;
        return segment.dead_bytes * 2 >= segment.used;
    }

    fn compactSegmentAtIndex(self: *BlobArena, index: usize) BlobError!CompactionResult {
        const old_segment = self.segments.items[index];
        var new_segment = try self.openSegment(self.next_segment_id, old_segment.capacity);
        self.next_segment_id += 1;
        errdefer new_segment.deinit(self.allocator);

        var remaps = std.ArrayList(HandleRemap).init(self.allocator);
        errdefer remaps.deinit();
        var moved_records: usize = 0;

        for (old_segment.records.items) |record| {
            if (record.tombstone) continue;
            const payload = old_segment.map[@as(usize, @intCast(record.payload_start)) .. @as(usize, @intCast(record.payload_start + record.len))];
            const new_handle = try self.appendRecordToSegment(&new_segment, payload);
            try remaps.append(.{ .old_handle = record.handle, .new_handle = new_handle });
            moved_records += 1;
        }

        try new_segment.flush();
        try deleteFile(old_segment.path);

        var replaced = old_segment;
        replaced.deinit(self.allocator);
        self.segments.items[index] = new_segment;

        return .{
            .rewritten_segments = 1,
            .moved_records = moved_records,
            .remaps = try remaps.toOwnedSlice(),
        };
    }
};

fn isZero(bytes: []const u8) bool {
    for (bytes) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

fn trim(text: []const u8) []const u8 {
    return std.mem.trim(u8, text, " \t\r\n");
}

fn rootPrefix(root_dir: []const u8) []const u8 {
    const trimmed = trim(root_dir);
    if (trimmed.len == 0 or std.mem.eql(u8, trimmed, ".")) return "";
    return trimmed;
}

fn joinPath(allocator: std.mem.Allocator, parts: []const []const u8) BlobError![]u8 {
    return std.fs.path.join(allocator, parts) catch |err| return mapFileError(err);
}

fn activePath(allocator: std.mem.Allocator, root_dir: []const u8, basename: []const u8) BlobError![]u8 {
    const prefix = rootPrefix(root_dir);
    if (prefix.len == 0) return allocator.dupe(u8, basename) catch BlobError.OutOfMemory;
    return joinPath(allocator, &.{ prefix, basename });
}

fn writeFile(path: []const u8, bytes: []const u8) BlobError!void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) std.fs.cwd().makePath(dir) catch |err| return mapFileError(err);
    }
    var file = std.fs.cwd().createFile(path, .{ .truncate = true }) catch |err| return mapFileError(err);
    defer file.close();
    file.writeAll(bytes) catch |err| return mapFileError(err);
}

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) BlobError![]u8 {
    var file = std.fs.cwd().openFile(path, .{ .mode = .read_only }) catch |err| return switch (err) {
        error.FileNotFound => BlobError.NotFound,
        else => mapFileError(err),
    };
    defer file.close();
    return file.readToEndAlloc(allocator, max_bytes) catch |err| return mapFileError(err);
}

fn mapFileError(err: anyerror) BlobError {
    return switch (err) {
        error.OutOfMemory => BlobError.OutOfMemory,
        error.FileNotFound => BlobError.NotFound,
        error.InvalidPath => BlobError.InvalidPath,
        error.AccessDenied => BlobError.InvalidPath,
        error.PathAlreadyExists => BlobError.InvalidFormat,
        error.FileTooBig => BlobError.InvalidFormat,
        error.IsDir => BlobError.InvalidFormat,
        error.Unexpected => BlobError.InvalidFormat,
        else => BlobError.InvalidFormat,
    };
}

fn mapJsonError(err: anyerror) BlobError {
    return switch (err) {
        error.OutOfMemory => BlobError.OutOfMemory,
        else => BlobError.InvalidFormat,
    };
}

fn mapSyncError(err: anyerror) BlobError {
    return switch (err) {
        error.OutOfMemory => BlobError.OutOfMemory,
        else => BlobError.InvalidFormat,
    };
}

fn freeMeta(allocator: std.mem.Allocator, meta: MetaFile) void {
    allocator.free(meta.magic);
    allocator.free(meta.table_name);
    allocator.free(meta.segment_ids);
}

fn cloneMetaFile(allocator: std.mem.Allocator, meta: MetaFile) BlobError!MetaFile {
    const magic = try allocator.dupe(u8, meta.magic);
    errdefer allocator.free(magic);
    const table_name = try allocator.dupe(u8, meta.table_name);
    errdefer allocator.free(table_name);
    const segment_ids = try allocator.dupe(u32, meta.segment_ids);
    errdefer allocator.free(segment_ids);
    return .{
        .magic = magic,
        .version = meta.version,
        .table_name = table_name,
        .segment_size = meta.segment_size,
        .next_segment_id = meta.next_segment_id,
        .segment_ids = segment_ids,
    };
}

fn openSegmentFile(path: []const u8, capacity: u64) BlobError!std.fs.File {
    var file = std.fs.cwd().openFile(path, .{ .mode = .read_write }) catch |err| switch (err) {
        error.FileNotFound => blk: {
            if (std.fs.path.dirname(path)) |dir| {
                if (dir.len != 0) std.fs.cwd().makePath(dir) catch |make_err| return mapFileError(make_err);
            }
            var created = std.fs.cwd().createFile(path, .{ .read = true, .truncate = true }) catch |create_err| return mapFileError(create_err);
            errdefer created.close();
            created.setEndPos(capacity) catch |size_err| return mapFileError(size_err);
            break :blk created;
        },
        else => return mapFileError(err),
    };

    const size = file.getEndPos() catch |err| return mapFileError(err);
    if (size > capacity) return BlobError.InvalidFormat;
    if (size < capacity) file.setEndPos(capacity) catch |err| return mapFileError(err);
    return file;
}

fn deleteFile(path: []const u8) BlobError!void {
    std.fs.cwd().deleteFile(path) catch |err| return mapFileError(err);
}

fn packHandle(segment_id: u32, offset: u64) BlobError!BlobHandle {
    if (segment_id > handle_segment_mask) return BlobError.InvalidHandle;
    if (offset > handle_offset_mask) return BlobError.InvalidHandle;
    return (@as(u64, segment_id) << handle_segment_shift) | offset;
}

fn unpackHandle(handle: BlobHandle) HandleParts {
    return .{
        .segment_id = @as(u32, @intCast((handle >> handle_segment_shift) & handle_segment_mask)),
        .offset = handle & handle_offset_mask,
    };
}

test "blob handle pack and unpack" {
    const handle = try packHandle(42, 4096);
    const parts = unpackHandle(handle);
    try std.testing.expectEqual(@as(u32, 42), parts.segment_id);
    try std.testing.expectEqual(@as(u64, 4096), parts.offset);
}

test "blob arena allocates, deletes, persists, and compacts" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    try tmp_dir.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    var remapped_handle: BlobHandle = 0;
    {
        var arena = try BlobArena.open(std.testing.allocator, ".", "flash_sale", .{ .segment_size = 128 });
        defer arena.deinit();

        const h1 = try arena.allocateText("alpha");
        const h2 = try arena.allocateText("beta");
        const h3 = try arena.allocateText("gamma");
        const h4 = try arena.allocateText("delta");

        try std.testing.expectEqualStrings("alpha", try arena.readText(h1));
        try std.testing.expectEqualStrings("beta", try arena.readText(h2));
        try std.testing.expectEqualStrings("gamma", try arena.readText(h3));
        try std.testing.expectEqualStrings("delta", try arena.readText(h4));

        try arena.delete(h2);
        try arena.delete(h3);
        try arena.delete(h4);
        try std.testing.expectError(BlobError.InvalidHandle, arena.readText(h2));

        var compacted = try arena.compact();
        defer compacted.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), compacted.rewritten_segments);
        try std.testing.expectEqual(@as(usize, 1), compacted.moved_records);
        remapped_handle = compacted.remaps[0].new_handle;
        try std.testing.expectEqualStrings("alpha", try arena.readText(remapped_handle));
        try std.testing.expectError(BlobError.InvalidHandle, arena.readText(h1));
    }

    var reopened = try BlobArena.open(std.testing.allocator, ".", "flash_sale", .{ .segment_size = 128 });
    defer reopened.deinit();
    try std.testing.expectEqual(@as(usize, 1), reopened.segmentCount());
    try std.testing.expectEqualStrings("alpha", try reopened.readText(remapped_handle));
}

const std = @import("std");
extern fn regexec(preg: ?*const RegexC, text: [*c]const u8, nmatch: usize, pmatch: [*]RegexMatchC, eflags: c_int) c_int;
const RegexC = @import("../sa_std.zig").RegexC;
pub const sa_std = @import("../sa_std.zig");
pub const RegexHandle = @import("../sa_std.zig").RegexHandle;
pub const RegexMatchC = @import("../sa_std.zig").RegexMatchC;
pub const SA_REGEX_REG_BADPAT = @import("../sa_std.zig").SA_REGEX_REG_BADPAT;
pub const SA_REGEX_REG_ENOSYS = @import("../sa_std.zig").SA_REGEX_REG_ENOSYS;
pub const SA_REGEX_REG_ESPACE = @import("../sa_std.zig").SA_REGEX_REG_ESPACE;
pub const SA_REGEX_REG_NOERROR = @import("../sa_std.zig").SA_REGEX_REG_NOERROR;
pub const SA_REGEX_REG_NOMATCH = @import("../sa_std.zig").SA_REGEX_REG_NOMATCH;
pub const SA_REGEX_STARTEND = @import("../sa_std.zig").SA_REGEX_STARTEND;
pub const constBytes = @import("../sa_std.zig").constBytes;
pub const finishErr = @import("../sa_std.zig").finishErr;
pub const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;

pub const RegexMatchHandle = struct {
    allocator: std.mem.Allocator,
    text_z: []u8,
    matches: []RegexMatchC,

    pub fn init(allocator: std.mem.Allocator, text: []const u8, group_count: usize) !*RegexMatchHandle {
        const owned_text = try allocator.alloc(u8, text.len + 1);
        errdefer allocator.free(owned_text);
        @memcpy(owned_text[0..text.len], text);
        owned_text[text.len] = 0;
        const matches = try allocator.alloc(RegexMatchC, group_count);
        errdefer allocator.free(matches);
        const handle = try allocator.create(RegexMatchHandle);
        errdefer allocator.destroy(handle);
        handle.* = .{
            .allocator = allocator,
            .text_z = owned_text,
            .matches = matches,
        };
        return handle;
    }

    pub fn deinit(self: *RegexMatchHandle) void {
        if (self.matches.len != 0) self.allocator.free(self.matches);
        if (self.text_z.len != 0) self.allocator.free(self.text_z);
        self.matches = &.{};
        self.text_z = &.{};
    }

    pub fn destroy(self: *RegexMatchHandle) void {
        self.deinit();
        self.allocator.destroy(self);
    }
};

pub const RegexMatchListHandle = struct {
    allocator: std.mem.Allocator,
    text_z: []u8,
    // One group-offset array per match; every inner slice has
    // regexGroupCount(regex) entries (group 0 = the whole match).
    matches: [][]RegexMatchC,

    pub fn destroy(self: *RegexMatchListHandle) void {
        for (self.matches) |groups| {
            if (groups.len != 0) self.allocator.free(groups);
        }
        if (self.matches.len != 0) self.allocator.free(self.matches);
        if (self.text_z.len != 0) self.allocator.free(self.text_z);
        self.allocator.destroy(self);
    }
};

pub const RegexSplitListHandle = struct {
    allocator: std.mem.Allocator,
    text_z: []u8,
    // Pieces are (start, end) byte ranges into text_z; rm_so < 0 marks a
    // capture group that did not participate (JS `undefined`, surfaced as
    // an empty piece by the accessors).
    pieces: []RegexMatchC,

    pub fn destroy(self: *RegexSplitListHandle) void {
        if (self.pieces.len != 0) self.allocator.free(self.pieces);
        if (self.text_z.len != 0) self.allocator.free(self.text_z);
        self.allocator.destroy(self);
    }
};

pub const RegexBufferHandle = struct {
    allocator: std.mem.Allocator,
    bytes: []u8,

    pub fn destroy(self: *RegexBufferHandle) void {
        if (self.bytes.len != 0) self.allocator.free(self.bytes);
        self.allocator.destroy(self);
    }
};

pub fn regexErrorToZig(rc: c_int) anyerror {
    return switch (rc) {
        SA_REGEX_REG_NOMATCH => error.FileNotFound,
        SA_REGEX_REG_BADPAT => error.SyntaxError,
        SA_REGEX_REG_ESPACE => error.OutOfMemory,
        SA_REGEX_REG_ENOSYS => error.Unsupported,
        else => error.InvalidArgument,
    };
}

pub fn regexGroupCount(regex_handle: *RegexHandle) usize {
    return @as(usize, @intCast(regex_handle.compiled.re_nsub)) + 1;
}

pub fn regexMatchHandle(regex_handle: *RegexHandle, text: []const u8) !*RegexMatchHandle {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidArgument;
    const allocator = regex_handle.allocator;
    const owned_text = try allocator.alloc(u8, text.len + 1);
    errdefer allocator.free(owned_text);
    @memcpy(owned_text[0..text.len], text);
    owned_text[text.len] = 0;

    const groups = try allocator.alloc(RegexMatchC, regexGroupCount(regex_handle));
    errdefer allocator.free(groups);

    const rc = regexec(&regex_handle.compiled, @ptrCast(owned_text.ptr), groups.len, groups.ptr, 0);
    // NOTE: no explicit frees here: the errdefers above own cleanup on every
    // error return. Explicit frees + errdefer double-free (freelist corruption
    // on wasm32 dlmalloc: later allocs overlap live objects).
    if (rc == SA_REGEX_REG_NOMATCH) {
        return error.FileNotFound;
    }
    if (rc != SA_REGEX_REG_NOERROR) {
        return regexErrorToZig(rc);
    }

    const handle = try allocator.create(RegexMatchHandle);
    handle.* = .{
        .allocator = allocator,
        .text_z = owned_text,
        .matches = groups,
    };
    return handle;
}

pub fn regexOwnedTextZ(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidArgument;
    const owned = try allocator.alloc(u8, text.len + 1);
    @memcpy(owned[0..text.len], text);
    owned[text.len] = 0;
    return owned;
}

pub fn regexExecRange(regex_handle: *RegexHandle, text_z: []const u8, start: usize, end: usize, groups: []RegexMatchC) c_int {
    groups[0].rm_so = @intCast(start);
    groups[0].rm_eo = @intCast(end);
    return regexec(&regex_handle.compiled, @ptrCast(text_z.ptr), groups.len, groups.ptr, SA_REGEX_STARTEND);
}

pub fn regexCollectMatches(allocator: std.mem.Allocator, regex_handle: *RegexHandle, text_z: []const u8) ![][]RegexMatchC {
    const text_len = text_z.len - 1;
    const group_count = regexGroupCount(regex_handle);
    var list = std.array_list.Managed([]RegexMatchC).init(allocator);
    errdefer {
        for (list.items) |groups| allocator.free(groups);
        list.deinit();
    }
    var pos: usize = 0;
    while (pos <= text_len) {
        const groups = try allocator.alloc(RegexMatchC, group_count);
        const rc = regexExecRange(regex_handle, text_z, pos, text_len, groups);
        if (rc == SA_REGEX_REG_NOMATCH) {
            allocator.free(groups);
            break;
        }
        if (rc != SA_REGEX_REG_NOERROR) {
            allocator.free(groups);
            return regexErrorToZig(rc);
        }
        list.append(groups) catch |err| {
            allocator.free(groups);
            return err;
        };
        const match_start: usize = @intCast(groups[0].rm_so);
        const match_end: usize = @intCast(groups[0].rm_eo);
        pos = if (match_end == match_start) match_end + 1 else match_end;
    }
    return list.toOwnedSlice();
}

pub fn regexAppendGroup(out: *std.array_list.Managed(u8), text: []const u8, groups: []RegexMatchC, idx: usize) !void {
    if (idx >= groups.len) return;
    const reg = groups[idx];
    if (reg.rm_so < 0 or reg.rm_eo < 0) return;
    const start: usize = @intCast(reg.rm_so);
    const end: usize = @intCast(reg.rm_eo);
    try out.appendSlice(text[start..end]);
}

pub fn regexAppendExpansion(out: *std.array_list.Managed(u8), text: []const u8, groups: []RegexMatchC, replacement: []const u8) !void {
    const group_total = groups.len - 1;
    var i: usize = 0;
    while (i < replacement.len) {
        const c = replacement[i];
        if (c != '$' or i + 1 >= replacement.len) {
            try out.append(c);
            i += 1;
            continue;
        }
        const next = replacement[i + 1];
        if (next == '$') {
            try out.append('$');
            i += 2;
        } else if (next == '&') {
            try regexAppendGroup(out, text, groups, 0);
            i += 2;
        } else if (next == '`') {
            const start: usize = @intCast(groups[0].rm_so);
            try out.appendSlice(text[0..start]);
            i += 2;
        } else if (next == '\'') {
            const end: usize = @intCast(groups[0].rm_eo);
            try out.appendSlice(text[end..]);
            i += 2;
        } else if (next >= '1' and next <= '9') {
            const d1: usize = @intCast(next - '0');
            var consumed: usize = 0;
            if (i + 2 < replacement.len and replacement[i + 2] >= '0' and replacement[i + 2] <= '9') {
                const nn = d1 * 10 + @as(usize, @intCast(replacement[i + 2] - '0'));
                if (nn >= 1 and nn <= group_total) {
                    try regexAppendGroup(out, text, groups, nn);
                    consumed = 3;
                }
            }
            if (consumed == 0 and d1 <= group_total) {
                try regexAppendGroup(out, text, groups, d1);
                consumed = 2;
            }
            if (consumed == 0) {
                try out.append('$');
                i += 1;
            } else {
                i += consumed;
            }
        } else {
            try out.append('$');
            i += 1;
        }
    }
}

pub fn regexBuildReplace(allocator: std.mem.Allocator, regex_handle: *RegexHandle, text_z: []const u8, replacement: []const u8, global: bool) ![]u8 {
    const text = text_z[0 .. text_z.len - 1];
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    if (!global) {
        const group_count = regexGroupCount(regex_handle);
        const groups = try allocator.alloc(RegexMatchC, group_count);
        defer allocator.free(groups);
        const rc = regexExecRange(regex_handle, text_z, 0, text.len, groups);
        if (rc == SA_REGEX_REG_NOMATCH) {
            try out.appendSlice(text);
            return out.toOwnedSlice();
        }
        if (rc != SA_REGEX_REG_NOERROR) return regexErrorToZig(rc);
        const start: usize = @intCast(groups[0].rm_so);
        const end: usize = @intCast(groups[0].rm_eo);
        try out.appendSlice(text[0..start]);
        try regexAppendExpansion(&out, text, groups, replacement);
        try out.appendSlice(text[end..]);
        return out.toOwnedSlice();
    }
    const matches = try regexCollectMatches(allocator, regex_handle, text_z);
    defer {
        for (matches) |groups| allocator.free(groups);
        allocator.free(matches);
    }
    var last: usize = 0;
    for (matches) |groups| {
        const start: usize = @intCast(groups[0].rm_so);
        const end: usize = @intCast(groups[0].rm_eo);
        try out.appendSlice(text[last..start]);
        try regexAppendExpansion(&out, text, groups, replacement);
        last = end;
    }
    try out.appendSlice(text[last..]);
    return out.toOwnedSlice();
}

pub fn regexSplitHandle(allocator: std.mem.Allocator, regex_handle: *RegexHandle, text_z: []u8, limit: u64) !*RegexSplitListHandle {
    const text_len = text_z.len - 1;
    errdefer allocator.free(text_z);
    const group_count = regexGroupCount(regex_handle);
    const limit_n: usize = if (limit == 0) std.math.maxInt(usize) else @intCast(limit);
    var pieces = std.array_list.Managed(RegexMatchC).init(allocator);
    errdefer pieces.deinit();
    const groups = try allocator.alloc(RegexMatchC, group_count);
    defer allocator.free(groups);
    if (text_len == 0) {
        // JS: empty input yields [] when the pattern matches at 0,
        // otherwise a single empty piece.
        const rc = regexExecRange(regex_handle, text_z, 0, 0, groups);
        if (rc != SA_REGEX_REG_NOMATCH and rc != SA_REGEX_REG_NOERROR) return regexErrorToZig(rc);
        if (rc == SA_REGEX_REG_NOMATCH) {
            try pieces.append(.{ .rm_so = 0, .rm_eo = 0 });
        }
    } else {
        var p: usize = 0;
        var q: usize = 0;
        var done = false;
        while (!done and q <= text_len) {
            const rc = regexExecRange(regex_handle, text_z, q, text_len, groups);
            if (rc == SA_REGEX_REG_NOMATCH) break;
            if (rc != SA_REGEX_REG_NOERROR) return regexErrorToZig(rc);
            const m_start: usize = @intCast(groups[0].rm_so);
            const m_end: usize = @intCast(groups[0].rm_eo);
            if (m_end == p) {
                // Empty match exactly at the previous match end: JS split
                // skips it and retries one byte later.
                q = m_end + 1;
                continue;
            }
            try pieces.append(.{ .rm_so = @intCast(p), .rm_eo = @intCast(m_start) });
            if (pieces.items.len >= limit_n) {
                done = true;
                break;
            }
            for (groups[1..]) |g| {
                try pieces.append(g);
                if (pieces.items.len >= limit_n) {
                    done = true;
                    break;
                }
            }
            if (done) break;
            p = m_end;
            q = p;
        }
        if (!done) {
            try pieces.append(.{ .rm_so = @intCast(p), .rm_eo = @intCast(text_len) });
        }
    }
    const handle = try allocator.create(RegexSplitListHandle);
    errdefer allocator.destroy(handle);
    handle.* = .{
        .allocator = allocator,
        .text_z = text_z,
        .pieces = try pieces.toOwnedSlice(),
    };
    return handle;
}

pub fn regexReplaceBuffer(regex: u64, text: ?[*]const u8, text_len: u64, replacement: ?[*]const u8, replacement_len: u64, global: bool) u64 {
    const input = constBytes(text, text_len) catch return 0;
    const repl = constBytes(replacement, replacement_len) catch return 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(regex) orelse return 0;
    const regex_handle = switch (resource.*) {
        .regex => |handle| handle,
        else => return 0,
    };
    const allocator = regex_handle.allocator;
    const text_z = regexOwnedTextZ(allocator, input) catch return 0;
    defer allocator.free(text_z);
    const bytes = regexBuildReplace(allocator, regex_handle, text_z, repl, global) catch return 0;
    const handle = allocator.create(RegexBufferHandle) catch {
        allocator.free(bytes);
        return 0;
    };
    handle.* = .{ .allocator = allocator, .bytes = bytes };
    return registerResourceLocked(.{ .regex_buffer = handle }) catch |err| {
        handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

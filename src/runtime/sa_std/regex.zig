const std = @import("std");
const sa_std = @import("../sa_std.zig");
const Fallible = @import("../sa_std.zig").Fallible;
const RegexHandle = @import("../sa_std.zig").RegexHandle;
const RegexMatchHandle = @import("../sa_std.zig").RegexMatchHandle;
const RegexMatchListHandle = @import("../sa_std.zig").RegexMatchListHandle;
const SA_STD_OK = @import("../sa_std.zig").SA_STD_OK;
const constBytes = @import("../sa_std.zig").constBytes;
const fail = @import("../sa_std.zig").fail;
const finishErr = @import("../sa_std.zig").finishErr;
const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
const ok = @import("../sa_std.zig").ok;
const regexCollectMatches = @import("../sa_std.zig").regexCollectMatches;
const regexGroupCount = @import("../sa_std.zig").regexGroupCount;
const regexMatchHandle = @import("../sa_std.zig").regexMatchHandle;
const regexOwnedTextZ = @import("../sa_std.zig").regexOwnedTextZ;
const regexReplaceBuffer = @import("../sa_std.zig").regexReplaceBuffer;
const regexSplitHandle = @import("../sa_std.zig").regexSplitHandle;
const registerResource = @import("../sa_std.zig").registerResource;
const registerResourceLocked = @import("../sa_std.zig").registerResourceLocked;
const sa_std_close = @import("../sa_std.zig").sa_std_close;

pub export fn sa_regex_compile(pattern: ?[*]const u8, pattern_len: u64, cflags: i32) u64 {
    const input = constBytes(pattern, pattern_len) catch return 0;
    const handle = RegexHandle.init(std.heap.page_allocator, input, cflags) catch return 0;
    return registerResource(.{ .regex = handle }) catch |err| {
        handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_match(regex: u64, text: ?[*]const u8, text_len: u64) u64 {
    const input = constBytes(text, text_len) catch return 0;
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(regex) orelse return 0;
    const regex_handle = switch (resource.*) {
        .regex => |handle| handle,
        else => return 0,
    };
    const match_handle = regexMatchHandle(regex_handle, input) catch return 0;
    return registerResourceLocked(.{ .regex_match = match_handle }) catch |err| {
        match_handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_group_ptr(match: u64, group_idx: u32) ?[*]const u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(match) orelse return null;
    const match_handle = switch (resource.*) {
        .regex_match => |handle| handle,
        else => return null,
    };
    const idx = @as(usize, @intCast(group_idx));
    if (idx >= match_handle.matches.len) return null;
    const reg = match_handle.matches[idx];
    if (reg.rm_so < 0 or reg.rm_eo < 0) return null;
    const start: usize = @intCast(reg.rm_so);
    return match_handle.text_z[start..].ptr;
}

pub export fn sa_regex_group_len(match: u64, group_idx: u32) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(match) orelse return 0;
    const match_handle = switch (resource.*) {
        .regex_match => |handle| handle,
        else => return 0,
    };
    const idx = @as(usize, @intCast(group_idx));
    if (idx >= match_handle.matches.len) return 0;
    const reg = match_handle.matches[idx];
    if (reg.rm_so < 0 or reg.rm_eo < 0) return 0;
    return @as(u64, @intCast(reg.rm_eo - reg.rm_so));
}

pub export fn sa_regex_group_start(match: u64, group_idx: u32) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(match) orelse return 0;
    const match_handle = switch (resource.*) {
        .regex_match => |handle| handle,
        else => return 0,
    };
    const idx = @as(usize, @intCast(group_idx));
    if (idx >= match_handle.matches.len) return 0;
    const reg = match_handle.matches[idx];
    if (reg.rm_so < 0 or reg.rm_eo < 0) return 0;
    return @as(u64, @intCast(reg.rm_so));
}

pub export fn sa_regex_group_count(regex: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(regex) orelse return 0;
    const regex_handle = switch (resource.*) {
        .regex => |handle| handle,
        else => return 0,
    };
    return @as(u64, @intCast(regexGroupCount(regex_handle)));
}

pub export fn sa_regex_free(regex: u64) Fallible(i32) {
    const status = sa_std_close(regex);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_regex_match_free(match: u64) Fallible(i32) {
    const status = sa_std_close(match);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_regex_match_all(regex: u64, text: ?[*]const u8, text_len: u64) u64 {
    const input = constBytes(text, text_len) catch return 0;
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
    const matches = regexCollectMatches(allocator, regex_handle, text_z) catch {
        allocator.free(text_z);
        return 0;
    };
    const handle = allocator.create(RegexMatchListHandle) catch {
        for (matches) |groups| allocator.free(groups);
        allocator.free(matches);
        allocator.free(text_z);
        return 0;
    };
    handle.* = .{ .allocator = allocator, .text_z = text_z, .matches = matches };
    return registerResourceLocked(.{ .regex_match_list = handle }) catch |err| {
        handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_match_list_count(list: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list) orelse return 0;
    return switch (resource.*) {
        .regex_match_list => |handle| @as(u64, @intCast(handle.matches.len)),
        else => 0,
    };
}

pub export fn sa_regex_match_list_at(list: u64, index: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list) orelse return 0;
    const list_handle = switch (resource.*) {
        .regex_match_list => |handle| handle,
        else => return 0,
    };
    const idx: usize = @intCast(index);
    if (idx >= list_handle.matches.len) return 0;
    const allocator = list_handle.allocator;
    const text = list_handle.text_z[0 .. list_handle.text_z.len - 1];
    const match_handle = RegexMatchHandle.init(allocator, text, list_handle.matches[idx].len) catch return 0;
    @memcpy(match_handle.matches, list_handle.matches[idx]);
    return registerResourceLocked(.{ .regex_match = match_handle }) catch |err| {
        match_handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_match_list_free(list: u64) Fallible(i32) {
    const status = sa_std_close(list);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_regex_replace(regex: u64, text: ?[*]const u8, text_len: u64, replacement: ?[*]const u8, replacement_len: u64) u64 {
    return regexReplaceBuffer(regex, text, text_len, replacement, replacement_len, false);
}

pub export fn sa_regex_replace_all(regex: u64, text: ?[*]const u8, text_len: u64, replacement: ?[*]const u8, replacement_len: u64) u64 {
    return regexReplaceBuffer(regex, text, text_len, replacement, replacement_len, true);
}

pub export fn sa_regex_buffer_data(buffer: u64) ?[*]u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return null;
    return switch (resource.*) {
        .regex_buffer => |handle| handle.bytes.ptr,
        else => null,
    };
}

pub export fn sa_regex_buffer_len(buffer: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(buffer) orelse return 0;
    return switch (resource.*) {
        .regex_buffer => |handle| @as(u64, @intCast(handle.bytes.len)),
        else => 0,
    };
}

pub export fn sa_regex_buffer_free(buffer: u64) Fallible(i32) {
    const status = sa_std_close(buffer);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

pub export fn sa_regex_split(regex: u64, text: ?[*]const u8, text_len: u64, limit: u64) u64 {
    const input = constBytes(text, text_len) catch return 0;
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
    const handle = regexSplitHandle(allocator, regex_handle, text_z, limit) catch return 0;
    return registerResourceLocked(.{ .regex_split_list = handle }) catch |err| {
        handle.destroy();
        _ = finishErr(err);
        return 0;
    };
}

pub export fn sa_regex_split_count(list: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list) orelse return 0;
    return switch (resource.*) {
        .regex_split_list => |handle| @as(u64, @intCast(handle.pieces.len)),
        else => 0,
    };
}

pub export fn sa_regex_split_ptr(list: u64, index: u64) ?[*]const u8 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list) orelse return null;
    const list_handle = switch (resource.*) {
        .regex_split_list => |handle| handle,
        else => return null,
    };
    const idx: usize = @intCast(index);
    if (idx >= list_handle.pieces.len) return null;
    const piece = list_handle.pieces[idx];
    if (piece.rm_so < 0) return null;
    const start: usize = @intCast(piece.rm_so);
    return list_handle.text_z[start..].ptr;
}

pub export fn sa_regex_split_len(list: u64, index: u64) u64 {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(list) orelse return 0;
    const list_handle = switch (resource.*) {
        .regex_split_list => |handle| handle,
        else => return 0,
    };
    const idx: usize = @intCast(index);
    if (idx >= list_handle.pieces.len) return 0;
    const piece = list_handle.pieces[idx];
    if (piece.rm_so < 0 or piece.rm_eo < 0) return 0;
    return @as(u64, @intCast(piece.rm_eo - piece.rm_so));
}

pub export fn sa_regex_split_free(list: u64) Fallible(i32) {
    const status = sa_std_close(list);
    if (status != SA_STD_OK) return fail(i32, status);
    return ok(i32, 0);
}

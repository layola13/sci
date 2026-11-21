const std = @import("std");
pub const sa_std = @import("../sa_std.zig");
pub const getResourceLocked = @import("../sa_std.zig").getResourceLocked;
pub const registerResource = @import("../sa_std.zig").registerResource;

pub const JsonDocumentHandle = struct {
    allocator: std.mem.Allocator,
    parsed: std.json.Parsed(std.json.Value),
    ref_count: std.atomic.Value(usize) = std.atomic.Value(usize).init(1),

    pub fn retain(self: *JsonDocumentHandle) void {
        _ = self.ref_count.fetchAdd(1, .monotonic);
    }

    pub fn release(self: *JsonDocumentHandle) void {
        const previous = self.ref_count.fetchSub(1, .release);
        if (previous == 0) {
            _ = self.ref_count.fetchAdd(1, .monotonic);
            return;
        }
        if (previous == 1) {
            _ = self.ref_count.load(.acquire);
            self.parsed.deinit();
            self.allocator.destroy(self);
        }
    }
};

pub const JsonPathSegment = union(enum) {
    key: []const u8,
    index: usize,
};

pub fn freeJsonPath(allocator: std.mem.Allocator, path: []const JsonPathSegment) void {
    if (path.len == 0) return;
    for (path) |segment| {
        switch (segment) {
            .key => |key| allocator.free(key),
            .index => {},
        }
    }
    allocator.free(path);
}

pub fn jsonPathAppend(allocator: std.mem.Allocator, base: []const JsonPathSegment, segment: JsonPathSegment) ![]JsonPathSegment {
    const path = try allocator.alloc(JsonPathSegment, base.len + 1);
    errdefer allocator.free(path);
    for (base, 0..) |seg, i| {
        path[i] = switch (seg) {
            .key => |key| .{ .key = try allocator.dupe(u8, key) },
            .index => |idx| .{ .index = idx },
        };
    }
    path[base.len] = switch (segment) {
        .key => |key| .{ .key = try allocator.dupe(u8, key) },
        .index => |idx| .{ .index = idx },
    };
    return path;
}

pub const JsonNodeHandle = struct {
    document: *JsonDocumentHandle,
    // Resolved snapshot of the tree value at acquire time. The copy stored
    // in a registry slot is a placeholder; acquires always re-resolve.
    value: std.json.Value,
    path: []const JsonPathSegment = &.{},
    // Only the handle stored in a registry slot (and the transient child
    // handle handed to registerJsonNode) owns its path allocation.
    path_owned: bool = false,

    pub fn deinit(self: *JsonNodeHandle) void {
        if (self.path_owned) {
            freeJsonPath(self.document.allocator, self.path);
            self.path = &.{};
            self.path_owned = false;
        }
        self.document.release();
    }
};

pub fn registerJsonNode(document: *JsonDocumentHandle, path: []const JsonPathSegment, retain_document: bool) !u64 {
    if (retain_document) document.retain();
    return registerResource(.{ .json_node = .{ .document = document, .value = .null, .path = path, .path_owned = true } }) catch |err| {
        freeJsonPath(document.allocator, path);
        document.release();
        return err;
    };
}

pub fn acquireJsonNode(handle: u64) !JsonNodeHandle {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    return switch (resource.*) {
        .json_node => |slot| blk: {
            slot.document.retain();
            const resolved = jsonResolvePath(slot.document, slot.path) catch |err| {
                slot.document.release();
                return err;
            };
            break :blk .{
                .document = slot.document,
                .value = resolved,
                .path = slot.path,
                .path_owned = false,
            };
        },
        else => error.InvalidHandle,
    };
}

pub fn jsonResolvePathPtr(document: *JsonDocumentHandle, path: []const JsonPathSegment) !*std.json.Value {
    var current: *std.json.Value = &document.parsed.value;
    for (path) |segment| {
        switch (segment) {
            .key => |key| {
                switch (current.*) {
                    .object => |*map| {
                        const idx = map.getIndex(key) orelse return error.InvalidHandle;
                        current = &map.values()[idx];
                    },
                    else => return error.InvalidHandle,
                }
            },
            .index => |idx| {
                switch (current.*) {
                    .array => |*array| {
                        if (idx >= array.items.len) return error.InvalidHandle;
                        current = &array.items[idx];
                    },
                    else => return error.InvalidHandle,
                }
            },
        }
    }
    return current;
}

pub fn jsonResolvePath(document: *JsonDocumentHandle, path: []const JsonPathSegment) !std.json.Value {
    const target = try jsonResolvePathPtr(document, path);
    return target.*;
}

pub fn jsonDocumentFromSlice(allocator: std.mem.Allocator, input: []const u8) !*JsonDocumentHandle {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, input, .{});
    errdefer parsed.deinit();
    const document = try allocator.create(JsonDocumentHandle);
    document.* = .{
        .allocator = allocator,
        .parsed = parsed,
        .ref_count = std.atomic.Value(usize).init(1),
    };
    return document;
}

pub fn jsonObjectGet(node: JsonNodeHandle, key: []const u8) !JsonNodeHandle {
    return switch (node.value) {
        .object => |object| {
            const child = object.get(key) orelse return error.FileNotFound;
            const path = try jsonPathAppend(node.document.allocator, node.path, .{ .key = key });
            return .{
                .document = node.document,
                .value = child,
                .path = path,
                .path_owned = true,
            };
        },
        else => error.InvalidHandle,
    };
}

pub fn jsonArrayGet(node: JsonNodeHandle, index: u64) !JsonNodeHandle {
    return switch (node.value) {
        .array => |array| {
            const idx: usize = @intCast(index);
            if (idx >= array.items.len) return error.FileNotFound;
            const path = try jsonPathAppend(node.document.allocator, node.path, .{ .index = idx });
            return .{
                .document = node.document,
                .value = array.items[idx],
                .path = path,
                .path_owned = true,
            };
        },
        else => error.InvalidHandle,
    };
}

pub fn jsonObjectKeyAt(node: JsonNodeHandle, index: u64) ![]const u8 {
    return switch (node.value) {
        .object => |object| {
            const idx: usize = @intCast(index);
            if (idx >= object.count()) return error.FileNotFound;
            var it = object.iterator();
            var current: usize = 0;
            while (it.next()) |entry| : (current += 1) {
                if (current == idx) return entry.key_ptr.*;
            }
            return error.FileNotFound;
        },
        else => error.InvalidHandle,
    };
}

pub const JsonMutation = struct {
    document: *JsonDocumentHandle,
    target: *std.json.Value,
};

pub fn jsonMutationTarget(handle: u64) !JsonMutation {
    const resource = getResourceLocked(handle) orelse return error.InvalidHandle;
    const slot = switch (resource.*) {
        .json_node => |*node| node,
        else => return error.InvalidHandle,
    };
    return .{
        .document = slot.document,
        .target = try jsonResolvePathPtr(slot.document, slot.path),
    };
}

pub fn jsonObjectSetLocked(handle: u64, key: []const u8, value: std.json.Value) !void {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const mutation = try jsonMutationTarget(handle);
    switch (mutation.target.*) {
        .object => |*map| {
            const arena = mutation.document.parsed.arena.allocator();
            // put() keeps the stored key slice for an existing key, so the
            // caller's key only needs an arena copy when it is inserted.
            if (map.getIndex(key) != null) {
                try map.put(arena, key, value);
            } else {
                try map.put(arena, try arena.dupe(u8, key), value);
            }
        },
        else => return error.InvalidHandle,
    }
}

pub fn jsonArrayPushLocked(handle: u64, value: std.json.Value) !void {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const mutation = try jsonMutationTarget(handle);
    switch (mutation.target.*) {
        .array => |*array| try array.append(value),
        else => return error.InvalidHandle,
    }
}

pub fn jsonObjectRemoveLocked(handle: u64, key: []const u8) !void {
    while (!sa_std.registry_mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer sa_std.registry_mutex.unlock();
    const mutation = try jsonMutationTarget(handle);
    switch (mutation.target.*) {
        .object => |*map| {
            if (!map.orderedRemove(key)) return error.FileNotFound;
        },
        else => return error.InvalidHandle,
    }
}

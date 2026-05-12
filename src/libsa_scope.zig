const std = @import("std");

const EMPTY_CSTR = [_:0]u8{0};

const ScopeState = enum(u8) {
    active,
    moved,
    released,
};

const Binding = struct {
    name: []const u8,
    state: ScopeState = .active,
};

const BranchSnapshot = struct {
    active_names: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator) BranchSnapshot {
        return .{
            .active_names = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *BranchSnapshot) void {
        self.active_names.deinit();
        self.* = undefined;
    }
};

const BranchState = struct {
    snapshots: std.ArrayList(BranchSnapshot),

    fn init(allocator: std.mem.Allocator) BranchState {
        return .{
            .snapshots = std.ArrayList(BranchSnapshot).init(allocator),
        };
    }

    fn deinit(self: *BranchState) void {
        for (self.snapshots.items) |*snapshot| snapshot.deinit();
        self.snapshots.deinit();
        self.* = undefined;
    }
};

const ScopeFrame = struct {
    bindings: std.ArrayList(Binding),
    branch: ?BranchState = null,

    fn init(allocator: std.mem.Allocator) ScopeFrame {
        return .{
            .bindings = std.ArrayList(Binding).init(allocator),
            .branch = null,
        };
    }

    fn deinit(self: *ScopeFrame) void {
        if (self.branch) |*branch| branch.deinit();
        self.bindings.deinit();
        self.* = undefined;
    }
};

pub const ScopeTracker = struct {
    allocator: std.mem.Allocator,
    frames: std.ArrayList(ScopeFrame),
    owned_names: std.ArrayList([]u8),
    releases: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) !ScopeTracker {
        var frames = std.ArrayList(ScopeFrame).init(allocator);
        errdefer frames.deinit();

        try frames.append(ScopeFrame.init(allocator));

        return .{
            .allocator = allocator,
            .frames = frames,
            .owned_names = std.ArrayList([]u8).init(allocator),
            .releases = std.ArrayList(u8).init(allocator),
        };
    }

    fn deinit(self: *ScopeTracker) void {
        for (self.frames.items) |*frame| frame.deinit();
        self.frames.deinit();
        for (self.owned_names.items) |name| self.allocator.free(name);
        self.owned_names.deinit();
        self.releases.deinit();
        self.* = undefined;
    }

    fn clearReleases(self: *ScopeTracker) void {
        self.releases.clearRetainingCapacity();
    }

    fn ensureOutputTerminator(self: *ScopeTracker) !void {
        if (self.releases.items.len == 0 or self.releases.items[self.releases.items.len - 1] != 0) {
            try self.releases.append(0);
        }
    }

    fn currentFrame(self: *ScopeTracker) *ScopeFrame {
        return &self.frames.items[self.frames.items.len - 1];
    }

    fn duplicateName(self: *ScopeTracker, name: []const u8) ![]const u8 {
        const dup = try self.allocator.dupe(u8, name);
        try self.owned_names.append(dup);
        return dup;
    }

    fn findBinding(self: *ScopeTracker, name: []const u8) ?struct { frame_idx: usize, binding_idx: usize } {
        var frame_idx = self.frames.items.len;
        while (frame_idx > 0) : (frame_idx -= 1) {
            const idx = frame_idx - 1;
            const frame = &self.frames.items[idx];
            var binding_idx: usize = frame.bindings.items.len;
            while (binding_idx > 0) : (binding_idx -= 1) {
                const inner = binding_idx - 1;
                if (std.mem.eql(u8, frame.bindings.items[inner].name, name)) {
                    return .{ .frame_idx = idx, .binding_idx = inner };
                }
            }
        }
        return null;
    }

    fn appendRelease(self: *ScopeTracker, name: []const u8) !void {
        try self.releases.appendSlice("!");
        try self.releases.appendSlice(name);
        try self.releases.append('\n');
    }

    fn captureBranchSnapshot(frame: *ScopeFrame, allocator: std.mem.Allocator) !BranchSnapshot {
        var snapshot = BranchSnapshot.init(allocator);
        errdefer snapshot.deinit();
        for (frame.bindings.items) |binding| {
            if (binding.state == .active) {
                try snapshot.active_names.append(binding.name);
            }
        }
        return snapshot;
    }

};

fn trackerFromHandle(handle: ?*anyopaque) ?*ScopeTracker {
    return if (handle) |ptr| @ptrCast(@alignCast(ptr)) else null;
}

fn bindInTracker(tracker: *ScopeTracker, name: []const u8) !void {
    const dup = try tracker.duplicateName(name);
    const frame = tracker.currentFrame();
    try frame.bindings.append(.{ .name = dup, .state = .active });
}

fn markInTracker(tracker: *ScopeTracker, name: []const u8, state: ScopeState) bool {
    if (tracker.findBinding(name)) |loc| {
        tracker.frames.items[loc.frame_idx].bindings.items[loc.binding_idx].state = state;
        return true;
    }
    return false;
}

fn emitCurrentScopeExits(tracker: *ScopeTracker) !void {
    const frame = tracker.currentFrame();
    for (frame.bindings.items) |*binding| {
        if (binding.state == .active) {
            try tracker.appendRelease(binding.name);
            binding.state = .released;
        }
    }
}

pub export fn scope_new() ?*anyopaque {
    const tracker = ScopeTracker.init(std.heap.page_allocator) catch return null;
    const boxed = std.heap.page_allocator.create(ScopeTracker) catch {
        var tmp = tracker;
        tmp.deinit();
        return null;
    };
    boxed.* = tracker;
    return @ptrCast(boxed);
}

pub export fn scope_drop(handle: ?*anyopaque) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.deinit();
    std.heap.page_allocator.destroy(tracker);
}

pub export fn scope_enter(handle: ?*anyopaque) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    tracker.frames.append(ScopeFrame.init(tracker.allocator)) catch return;
}

pub export fn scope_exit(handle: ?*anyopaque) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    if (tracker.frames.items.len <= 1) return;
    const frame_idx = tracker.frames.items.len - 1;
    const frame = &tracker.frames.items[frame_idx];
    emitCurrentScopeExits(tracker) catch return;
    frame.deinit();
    _ = tracker.frames.pop();
}

pub export fn scope_bind(handle: ?*anyopaque, reg_name: [*:0]const u8) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    const name = std.mem.span(reg_name);
    if (markInTracker(tracker, name, .active)) return;
    bindInTracker(tracker, name) catch return;
}

pub export fn scope_move(handle: ?*anyopaque, reg_name: [*:0]const u8) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    _ = markInTracker(tracker, std.mem.span(reg_name), .moved);
}

pub export fn scope_release(handle: ?*anyopaque, reg_name: [*:0]const u8) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    const name = std.mem.span(reg_name);
    if (tracker.findBinding(name)) |loc| {
        const binding = &tracker.frames.items[loc.frame_idx].bindings.items[loc.binding_idx];
        if (binding.state == .active) {
            tracker.appendRelease(binding.name) catch return;
        }
        binding.state = .released;
    }
}

pub export fn scope_branch_begin(handle: ?*anyopaque) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    const frame = tracker.currentFrame();
    if (frame.branch) |*branch| {
        branch.deinit();
    }
    frame.branch = BranchState.init(tracker.allocator);
}

pub export fn scope_branch_add_path(handle: ?*anyopaque) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    const frame = tracker.currentFrame();
    if (frame.branch) |*branch| {
        var snapshot = ScopeTracker.captureBranchSnapshot(frame, tracker.allocator) catch return;
        branch.snapshots.append(snapshot) catch {
            snapshot.deinit();
            return;
        };
    }
}

fn nameActiveInAllSnapshots(name: []const u8, snapshots: []const BranchSnapshot) bool {
    if (snapshots.len == 0) return false;
    for (snapshots) |snapshot| {
        var found = false;
        for (snapshot.active_names.items) |path_name| {
            if (std.mem.eql(u8, path_name, name)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}

pub export fn scope_branch_merge(handle: ?*anyopaque) void {
    const tracker = trackerFromHandle(handle) orelse return;
    tracker.clearReleases();
    const frame = tracker.currentFrame();
    if (frame.branch) |*branch| {
        defer {
            branch.deinit();
            frame.branch = null;
        }

        if (branch.snapshots.items.len == 0) return;

        var seen = std.StringHashMap(void).init(tracker.allocator);
        defer seen.deinit();
        for (branch.snapshots.items) |snapshot| {
            for (snapshot.active_names.items) |name| {
                seen.put(name, {}) catch return;
            }
        }

        var it = seen.iterator();
        while (it.next()) |entry| {
            const name = entry.key_ptr.*;
            if (!nameActiveInAllSnapshots(name, branch.snapshots.items)) {
                tracker.appendRelease(name) catch return;
                _ = markInTracker(tracker, name, .released);
            }
        }
    }
}

pub export fn scope_emit_releases(handle: ?*anyopaque) [*:0]const u8 {
    const tracker = trackerFromHandle(handle) orelse return &EMPTY_CSTR;
    tracker.ensureOutputTerminator() catch return &EMPTY_CSTR;
    return @ptrCast(tracker.releases.items.ptr);
}

test "scope exit emits release lines for active bindings in order" {
    const tracker_ptr = scope_new() orelse return error.TestUnexpectedResult;
    defer scope_drop(tracker_ptr);

    scope_bind(tracker_ptr, "a");
    scope_bind(tracker_ptr, "b");
    scope_exit(tracker_ptr);

    const text = std.mem.span(scope_emit_releases(tracker_ptr));
    try std.testing.expectEqualStrings("!a\n!b\n", text);
}

test "scope move suppresses later exit emission" {
    const tracker_ptr = scope_new() orelse return error.TestUnexpectedResult;
    defer scope_drop(tracker_ptr);

    scope_bind(tracker_ptr, "a");
    scope_bind(tracker_ptr, "b");
    scope_move(tracker_ptr, "a");
    scope_exit(tracker_ptr);

    const text = std.mem.span(scope_emit_releases(tracker_ptr));
    try std.testing.expectEqualStrings("!b\n", text);
}

test "nested scopes release only their own bindings" {
    const tracker_ptr = scope_new() orelse return error.TestUnexpectedResult;
    defer scope_drop(tracker_ptr);

    scope_bind(tracker_ptr, "outer");
    scope_enter(tracker_ptr);
    scope_bind(tracker_ptr, "inner");
    scope_exit(tracker_ptr);
    try std.testing.expectEqualStrings("!inner\n", std.mem.span(scope_emit_releases(tracker_ptr)));

    scope_exit(tracker_ptr);
    try std.testing.expectEqualStrings("!outer\n", std.mem.span(scope_emit_releases(tracker_ptr)));
}

test "branch merge emits releases for bindings missing in a path" {
    const tracker_ptr = scope_new() orelse return error.TestUnexpectedResult;
    defer scope_drop(tracker_ptr);

    scope_bind(tracker_ptr, "a");
    scope_bind(tracker_ptr, "b");
    scope_branch_begin(tracker_ptr);
    scope_branch_add_path(tracker_ptr);
    scope_move(tracker_ptr, "b");
    scope_branch_add_path(tracker_ptr);
    scope_branch_merge(tracker_ptr);

    try std.testing.expectEqualStrings("!b\n", std.mem.span(scope_emit_releases(tracker_ptr)));
}

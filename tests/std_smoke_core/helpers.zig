//! Shared helpers for the tests/std_smoke_core/*.zig split.
//! Verbatim from the former tests/std_smoke_core.zig (only `pub` added).
const std = @import("std");
const common = @import("../std_smoke_common.zig");
const saasm = common.saasm;

pub fn flattenFixture(allocator: std.mem.Allocator, path: []const u8, source: []const u8) !saasm.flattener.FlattenResult {
    return try saasm.flattener.flattenFile(allocator, path, source);
}

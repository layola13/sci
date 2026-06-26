const std = @import("std");

pub const flattener = @import("flattener.zig");
pub const sab = @import("sab.zig");

pub fn flattenSaFile(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !flattener.FlattenResult {
    return flattener.flattenFile(allocator, source_path, source);
}

pub fn encodeSabFromFlat(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
) ![]u8 {
    return sab.encodeProgramWithConsts(
        allocator,
        flat.symbols.names.items,
        flat.const_decls,
        flat.function_sigs,
        flat.instructions,
    );
}

pub fn disasmSabAlloc(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try sab.disasmModule(allocator, bytes, out.writer());
    return try out.toOwnedSlice();
}

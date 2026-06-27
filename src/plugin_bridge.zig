const std = @import("std");

pub const flattener = @import("flattener.zig");
pub const sab = @import("sab.zig");
pub const verifier = @import("verifier.zig");

pub fn flattenSaFile(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !flattener.FlattenResult {
    return flattener.flattenFile(allocator, source_path, source);
}

pub fn encodeSabFromFlat(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
) ![]u8 {
    const verified = try verifier.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            return sab.encodeProgramWithConsts(
                allocator,
                flat.symbols.names.items,
                flat.const_decls,
                owned.function_sigs,
                flat.instructions,
            );
        },
        .trap => return error.VerificationTrap,
    }
}

test "encodeSabFromFlat writes verified register metadata" {
    const source =
        \\@sla__create_point(x: i32, y: i32) -> ptr:
        \\L_ENTRY:
        \\    tmp_0 = alloc 8
        \\    store tmp_0+0, x as i32
        \\    store tmp_0+4, y as i32
        \\    return tmp_0
        \\
        \\@test "sab struct metadata"():
        \\L_TEST_ENTRY:
        \\    tmp_1 = 10
        \\    tmp_2 = 20
        \\    tmp_3 = call @sla__create_point(tmp_1, tmp_2)
        \\    !tmp_1
        \\    !tmp_2
        \\    point = tmp_3
        \\    x = load point+0 as i32
        \\    y = load point+4 as i32
        \\    sum = add x, y
        \\    expected = 30
        \\    failed = ne sum, expected
        \\    !sum
        \\    !expected
        \\    br failed -> L_FAIL, L_OK
        \\
        \\L_FAIL:
        \\    !failed
        \\    panic(5)
        \\
        \\L_OK:
        \\    !failed
        \\    !x
        \\    !y
        \\    !point
        \\    return
    ;

    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    const bytes = try encodeSabFromFlat(std.testing.allocator, &flat);
    defer std.testing.allocator.free(bytes);

    var decoded = try sab.decodeModule(std.testing.allocator, bytes);
    defer decoded.deinit(std.testing.allocator);

    var saw_test = false;
    for (decoded.function_sigs) |fsig| {
        if (fsig.kind == .test_func) {
            saw_test = true;
            try std.testing.expect(fsig.reg_ids.len != 0);
        }
    }
    try std.testing.expect(saw_test);

    const verified = try verifier.verifyWithOptions(std.testing.allocator, decoded.instructions, decoded.const_decls, .{
        .jobs = 1,
        .predecoded_symbol_names = decoded.symbols,
        .predecoded_function_sigs = decoded.function_sigs,
    });
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len != 0);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

pub fn encodeSabFromFlatUnchecked(
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

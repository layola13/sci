const std = @import("std");

pub const flattener = @import("flattener.zig");
pub const sab = @import("sab.zig");
pub const verifier = @import("verifier.zig");
const common_signature = @import("common/signature.zig");

pub fn flattenSaFile(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !flattener.FlattenResult {
    return flattener.flattenFile(allocator, source_path, source);
}

const ParamSpec = common_signature.ParamSpec;

fn cloneParamSpecs(allocator: std.mem.Allocator, params: []const ParamSpec) ![]ParamSpec {
    if (params.len == 0) return &.{};
    const out = try allocator.alloc(ParamSpec, params.len);
    errdefer allocator.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |param| allocator.free(param.name);
    for (params, 0..) |param, idx| {
        out[idx] = .{
            .name = try allocator.dupe(u8, param.name),
            .ty = param.ty,
            .cap = param.cap,
        };
        initialized += 1;
    }
    return out;
}

fn remapSymbolIdsByName(
    allocator: std.mem.Allocator,
    ids: []const u32,
    from_symbols: *const flattener.SymbolTable,
    to_symbols: *const flattener.SymbolTable,
) ![]const u32 {
    if (ids.len == 0) return &.{};
    const out = try allocator.alloc(u32, ids.len);
    errdefer allocator.free(out);
    for (ids, 0..) |id, idx| {
        const name = from_symbols.lookupName(id) orelse return error.InvalidOperand;
        out[idx] = to_symbols.findId(name) orelse return error.InvalidOperand;
    }
    return out;
}

fn cloneFunctionSigForSymbolTable(
    allocator: std.mem.Allocator,
    source: flattener.FunctionSig,
    from_symbols: *const flattener.SymbolTable,
    to_symbols: *const flattener.SymbolTable,
) !flattener.FunctionSig {
    var out = flattener.FunctionSig{
        .id = source.id,
        .name = try allocator.dupe(u8, source.name),
        .params = &.{},
        .kind = source.kind,
        .return_cap = source.return_cap,
        .return_ty = source.return_ty,
        .return_fallible = source.return_fallible,
        .entry_inst_idx = source.entry_inst_idx,
        .is_ffi_wrapper = source.is_ffi_wrapper,
        .upstream_file = null,
        .upstream_loc = null,
        .param_ids = &.{},
        .reg_ids = &.{},
        .llvm_name = null,
        .ignored = source.ignored,
        .should_panic = source.should_panic,
    };
    errdefer out.deinit(allocator);

    out.params = try cloneParamSpecs(allocator, source.params);
    out.param_ids = try remapSymbolIdsByName(allocator, source.param_ids, from_symbols, to_symbols);
    out.reg_ids = try remapSymbolIdsByName(allocator, source.reg_ids, from_symbols, to_symbols);
    if (source.upstream_loc) |loc| {
        const file_copy = try allocator.dupe(u8, loc.file);
        out.upstream_file = file_copy;
        out.upstream_loc = .{ .file = file_copy, .line = loc.line, .col = loc.col };
    } else if (source.upstream_file) |file| {
        out.upstream_file = try allocator.dupe(u8, file);
    }
    if (source.llvm_name) |llvm_name| {
        out.llvm_name = try allocator.dupe(u8, llvm_name);
    }
    return out;
}

fn remapFunctionSigsForFlatSymbols(
    allocator: std.mem.Allocator,
    function_sigs: []const flattener.FunctionSig,
    verified_symbols: *const flattener.SymbolTable,
    flat_symbols: *const flattener.SymbolTable,
) ![]flattener.FunctionSig {
    if (function_sigs.len == 0) return &.{};
    const out = try allocator.alloc(flattener.FunctionSig, function_sigs.len);
    errdefer allocator.free(out);
    var initialized: usize = 0;
    errdefer for (out[0..initialized]) |*item| item.deinit(allocator);
    for (function_sigs, 0..) |fsig, idx| {
        out[idx] = try cloneFunctionSigForSymbolTable(allocator, fsig, verified_symbols, flat_symbols);
        initialized += 1;
    }
    return out;
}

fn freeFunctionSigs(allocator: std.mem.Allocator, function_sigs: []flattener.FunctionSig) void {
    for (function_sigs) |*fsig| fsig.deinit(allocator);
    if (function_sigs.len != 0) allocator.free(function_sigs);
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
            const function_sigs = try remapFunctionSigsForFlatSymbols(allocator, owned.function_sigs, &owned.symbols, &flat.symbols);
            defer freeFunctionSigs(allocator, function_sigs);
            return sab.encodeProgramWithConsts(
                allocator,
                flat.symbols.names.items,
                flat.const_decls,
                function_sigs,
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

test "encodeSabFromFlat preserves panic_msg argument body" {
    const source =
        \\@const MSG = utf8:"boom"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    panic_msg(17, *MSG, 4)
    ;

    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);
    const bytes = try encodeSabFromFlat(std.testing.allocator, &flat);
    defer std.testing.allocator.free(bytes);

    var decoded = try sab.decodeModule(std.testing.allocator, bytes);
    defer decoded.deinit(std.testing.allocator);

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

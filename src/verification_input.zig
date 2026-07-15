const std = @import("std");

const const_decl = @import("common/const_decl.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const pkg_manifest = @import("pkg/manifest.zig");

/// Strongly typed, canonical key for a verdict-only Referee result.
/// Source locations are intentionally excluded because failures are never
/// cached; expanded ordering remains included because metadata construction
/// interleaves instructions and const declarations by expanded line.
pub const Digest = struct {
    bytes: [32]u8,
};

pub const Metadata = union(enum) {
    rebuild: void,
    predecoded: struct {
        symbol_names: []const []const u8,
        function_sigs: []const sig.FunctionSig,
    },
};

/// Every input that can change a Referee success verdict. Runtime-only
/// scheduling and reporting options deliberately live outside this value.
pub const Input = struct {
    instructions: []const inst.Instruction,
    const_decls: []const const_decl.ConstDecl,
    package_grants: []const pkg_manifest.RequireEntry,
    sax_component_name: ?[]const u8,
    metadata: Metadata,
    check_exit_leaks: bool,
};

const Sha256 = std.crypto.hash.sha2.Sha256;

fn hashU64(hasher: *Sha256, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hasher.update(&bytes);
}

fn hashU32(hasher: *Sha256, value: u32) void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .little);
    hasher.update(&bytes);
}

fn hashBool(hasher: *Sha256, value: bool) void {
    hasher.update(&.{@intFromBool(value)});
}

fn hashBytes(hasher: *Sha256, value: []const u8) void {
    hashU64(hasher, @intCast(value.len));
    hasher.update(value);
}

fn hashOptionalBytes(hasher: *Sha256, value: ?[]const u8) void {
    hashBool(hasher, value != null);
    if (value) |bytes| hashBytes(hasher, bytes);
}

fn hashOptionalDigest(hasher: *Sha256, value: ?[32]u8) void {
    hashBool(hasher, value != null);
    if (value) |digest| hasher.update(&digest);
}

fn hashOptionalU32(hasher: *Sha256, value: ?u32) void {
    hashBool(hasher, value != null);
    if (value) |number| hashU32(hasher, number);
}

fn hashOptionalCap(hasher: *Sha256, value: ?inst.CapPrefix) void {
    hashBool(hasher, value != null);
    if (value) |capability| hashU64(hasher, @intFromEnum(capability));
}

fn hashOperand(hasher: *Sha256, operand: inst.Operand) void {
    hashU64(hasher, @intFromEnum(std.meta.activeTag(operand)));
    switch (operand) {
        .none => {},
        .reg, .symbol, .label, .func, .offset, .ty => |value| hashU32(hasher, value),
        .imm_i64, .imm_int => |value| hashU64(hasher, @bitCast(value)),
        .imm_u64 => |value| hashU64(hasher, value),
        .imm_float => |value| hashU64(hasher, @bitCast(value)),
        .op_code => |value| hashU64(hasher, @intFromEnum(value)),
        .cap_prefix => |value| hashU64(hasher, @intFromEnum(value)),
        .text, .native_text => |value| hashBytes(hasher, value),
    }
}

fn hashInstruction(hasher: *Sha256, instruction: inst.Instruction) void {
    hashU64(hasher, @intFromEnum(instruction.kind));
    hashU32(hasher, instruction.expanded_line);
    hashOptionalBytes(hasher, instruction.package_identity);
    hashOptionalDigest(hasher, instruction.package_source_sha256);
    hashBool(hasher, instruction.op_kind != null);
    if (instruction.op_kind) |op_kind| hashU64(hasher, @intFromEnum(op_kind));
    for (instruction.operands) |operand| hashOperand(hasher, operand);
    hashBytes(hasher, instruction.raw_text);
    hashOptionalU32(hasher, instruction.atomic_value_ty);
    hashBool(hasher, instruction.atomic_ordering != null);
    if (instruction.atomic_ordering) |ordering| hashU64(hasher, @intFromEnum(ordering));
    hashBool(hasher, instruction.atomic_second_ordering != null);
    if (instruction.atomic_second_ordering) |ordering| hashU64(hasher, @intFromEnum(ordering));
    hashBool(hasher, instruction.atomic_rmw_op != null);
    if (instruction.atomic_rmw_op) |op| hashU64(hasher, @intFromEnum(op));
    hashOptionalBytes(hasher, instruction.atomic_expected_text);
    hashOptionalBytes(hasher, instruction.atomic_new_text);
    hashU64(hasher, @intCast(instruction.native_reg_names.len));
    for (instruction.native_reg_names) |name| hashBytes(hasher, name);
}

fn hashBytesLiteral(hasher: *Sha256, literal: const_decl.BytesLiteral) void {
    hashU64(hasher, @intFromEnum(literal.kind));
    hashBytes(hasher, literal.bytes);
    hashBool(hasher, literal.repeat_count != null);
    if (literal.repeat_count) |count| hashU64(hasher, count);
    hashBool(hasher, literal.repeat_byte != null);
    if (literal.repeat_byte) |byte| hasher.update(&.{byte});
}

fn hashConstValue(hasher: *Sha256, value: const_decl.ConstValue) void {
    hashU64(hasher, @intFromEnum(std.meta.activeTag(value)));
    switch (value) {
        .hex, .utf8, .repeat => |literal| hashBytesLiteral(hasher, literal),
        .struct_ => |literal| {
            hashU64(hasher, @intCast(literal.fields.len));
            for (literal.fields) |field| {
                hashBytes(hasher, field.name);
                hashU64(hasher, field.size);
                hashConstValue(hasher, field.value);
            }
        },
        .vtable => |literal| {
            hashU64(hasher, @intCast(literal.slots.len));
            for (literal.slots) |slot| {
                hashBytes(hasher, slot.name);
                hashBytes(hasher, slot.func_name);
            }
        },
    }
}

fn hashConstDecl(hasher: *Sha256, declaration: const_decl.ConstDecl) void {
    hashU32(hasher, declaration.expanded_line);
    hashBytes(hasher, declaration.raw_text);
    hashBytes(hasher, declaration.name);
    hashBytes(hasher, declaration.literal_text);
    hashConstValue(hasher, declaration.value);
}

fn hashFunctionSig(hasher: *Sha256, function_sig: sig.FunctionSig) void {
    hashU32(hasher, function_sig.id);
    hashBytes(hasher, function_sig.name);
    hashU64(hasher, @intCast(function_sig.params.len));
    for (function_sig.params) |param| {
        hashBytes(hasher, param.name);
        hashU64(hasher, @intFromEnum(param.ty));
        hashU64(hasher, @intFromEnum(param.cap));
    }
    hashU64(hasher, @intFromEnum(function_sig.kind));
    hashOptionalCap(hasher, function_sig.return_cap);
    hashU64(hasher, @intFromEnum(function_sig.return_ty));
    hashBool(hasher, function_sig.return_fallible);
    hashU32(hasher, function_sig.entry_inst_idx);
    hashBool(hasher, function_sig.is_ffi_wrapper);
    hashU64(hasher, @intCast(function_sig.param_ids.len));
    for (function_sig.param_ids) |id| hashU32(hasher, id);
    hashU64(hasher, @intCast(function_sig.reg_ids.len));
    for (function_sig.reg_ids) |id| hashU32(hasher, id);
    hashOptionalBytes(hasher, function_sig.llvm_name);
    hashBool(hasher, function_sig.ignored);
    hashBool(hasher, function_sig.should_panic);
}

const CanonicalGrant = struct {
    url: []const u8,
    source_sha256: [32]u8,
    capability_mask: u64,
};

fn canonicalGrantLessThan(_: void, lhs: CanonicalGrant, rhs: CanonicalGrant) bool {
    const url_order = std.mem.order(u8, lhs.url, rhs.url);
    if (url_order != .eq) return url_order == .lt;
    const digest_order = std.mem.order(u8, lhs.source_sha256[0..], rhs.source_sha256[0..]);
    if (digest_order != .eq) return digest_order == .lt;
    return lhs.capability_mask < rhs.capability_mask;
}

fn hashPackageGrants(allocator: std.mem.Allocator, hasher: *Sha256, grants: []const pkg_manifest.RequireEntry) !void {
    const canonical = try allocator.alloc(CanonicalGrant, grants.len);
    defer allocator.free(canonical);
    for (grants, 0..) |grant, index| {
        var capability_mask: u64 = 0;
        for (grant.grants) |capability| {
            capability_mask |= @as(u64, 1) << @intCast(@intFromEnum(capability));
        }
        canonical[index] = .{
            .url = grant.url,
            .source_sha256 = grant.source_sha256,
            .capability_mask = capability_mask,
        };
    }
    std.mem.sort(CanonicalGrant, canonical, {}, canonicalGrantLessThan);
    if (canonical.len > 1) {
        for (canonical[1..], canonical[0 .. canonical.len - 1]) |current, previous| {
            if (std.mem.eql(u8, current.url, previous.url)) return error.DuplicatePackageGrant;
        }
    }
    hashU64(hasher, @intCast(canonical.len));
    for (canonical) |grant| {
        hashBytes(hasher, grant.url);
        hasher.update(&grant.source_sha256);
        hashU64(hasher, grant.capability_mask);
    }
}

pub fn compute(allocator: std.mem.Allocator, input: Input) !Digest {
    var hasher = Sha256.init(.{});
    hashBytes(&hasher, "sa-verification-input/v2");
    hashBytes(&hasher, "referee-semantics/v1");

    hashU64(&hasher, @intCast(input.instructions.len));
    for (input.instructions) |instruction| hashInstruction(&hasher, instruction);

    hashU64(&hasher, @intCast(input.const_decls.len));
    for (input.const_decls) |declaration| hashConstDecl(&hasher, declaration);

    try hashPackageGrants(allocator, &hasher, input.package_grants);
    hashOptionalBytes(&hasher, input.sax_component_name);
    hashU64(&hasher, @intFromEnum(std.meta.activeTag(input.metadata)));
    switch (input.metadata) {
        .rebuild => {},
        .predecoded => |metadata| {
            hashU64(&hasher, @intCast(metadata.symbol_names.len));
            for (metadata.symbol_names) |name| hashBytes(&hasher, name);
            hashU64(&hasher, @intCast(metadata.function_sigs.len));
            for (metadata.function_sigs) |function_sig| hashFunctionSig(&hasher, function_sig);
        },
    }
    hashBool(&hasher, input.check_exit_leaks);

    var bytes: [32]u8 = undefined;
    hasher.final(&bytes);
    return .{ .bytes = bytes };
}

fn emptyInput(instructions: []const inst.Instruction) Input {
    return .{
        .instructions = instructions,
        .const_decls = &.{},
        .package_grants = &.{},
        .sax_component_name = null,
        .metadata = .{ .rebuild = {} },
        .check_exit_leaks = true,
    };
}

fn expectDigestEqual(lhs: Digest, rhs: Digest) !void {
    try std.testing.expectEqualSlices(u8, &lhs.bytes, &rhs.bytes);
}

fn expectDigestDifferent(lhs: Digest, rhs: Digest) !void {
    try std.testing.expect(!std.mem.eql(u8, &lhs.bytes, &rhs.bytes));
}

test "verification input v2 is canonical and includes expanded instruction structure" {
    var first = inst.makeInstruction(.return_, 1, 7, null, "return 0");
    var moved = first;
    moved.source_line = 99;
    try expectDigestEqual(try compute(std.testing.allocator, emptyInput(&.{first})), try compute(std.testing.allocator, emptyInput(&.{moved})));

    moved.expanded_line = 8;
    try expectDigestDifferent(try compute(std.testing.allocator, emptyInput(&.{first})), try compute(std.testing.allocator, emptyInput(&.{moved})));

    first.native_reg_names = &.{ "ab", "c" };
    moved = first;
    moved.native_reg_names = &.{ "a", "bc" };
    try expectDigestDifferent(try compute(std.testing.allocator, emptyInput(&.{first})), try compute(std.testing.allocator, emptyInput(&.{moved})));

    var absent_package = inst.makeInstruction(.return_, 1, 1, null, "return 0");
    var zero_package = absent_package;
    zero_package.package_identity = "\x00";
    try expectDigestDifferent(try compute(std.testing.allocator, emptyInput(&.{absent_package})), try compute(std.testing.allocator, emptyInput(&.{zero_package})));

    absent_package = inst.makeInstruction(.return_, 1, 1, null, "return 0");
    zero_package = absent_package;
    zero_package.package_source_sha256 = [_]u8{0} ** 32;
    try expectDigestDifferent(try compute(std.testing.allocator, emptyInput(&.{absent_package})), try compute(std.testing.allocator, emptyInput(&.{zero_package})));

    absent_package.atomic_value_ty = null;
    zero_package = absent_package;
    zero_package.atomic_value_ty = 0;
    try expectDigestDifferent(try compute(std.testing.allocator, emptyInput(&.{absent_package})), try compute(std.testing.allocator, emptyInput(&.{zero_package})));
}

test "verification input v2 changes for const policy and metadata fields" {
    const instruction = inst.makeInstruction(.return_, 1, 1, null, "return 0");
    var bytes_a = [_]u8{'a'};
    var bytes_b = [_]u8{'b'};
    const decl_a = const_decl.ConstDecl{
        .source_line = 1,
        .expanded_line = 1,
        .raw_text = @constCast("@const C = utf8:\"a\""),
        .name = @constCast("C"),
        .literal_text = @constCast("utf8:\"a\""),
        .value = .{ .utf8 = .{ .kind = .utf8, .bytes = &bytes_a } },
    };
    const decl_b = const_decl.ConstDecl{
        .source_line = 1,
        .expanded_line = 1,
        .raw_text = @constCast("@const C = utf8:\"b\""),
        .name = @constCast("C"),
        .literal_text = @constCast("utf8:\"b\""),
        .value = .{ .utf8 = .{ .kind = .utf8, .bytes = &bytes_b } },
    };
    var base = emptyInput(&.{instruction});
    base.const_decls = &.{decl_a};
    var changed = base;
    changed.const_decls = &.{decl_b};
    try expectDigestDifferent(try compute(std.testing.allocator, base), try compute(std.testing.allocator, changed));

    var slots_a = [_]const_decl.VTableSlot{.{ .name = @constCast("run"), .func_name = @constCast("main") }};
    var slots_b = [_]const_decl.VTableSlot{.{ .name = @constCast("run"), .func_name = @constCast("other") }};
    const vtable_a = const_decl.ConstDecl{
        .source_line = 1,
        .expanded_line = 1,
        .raw_text = @constCast("@const VT = vtable { run = @main }"),
        .name = @constCast("VT"),
        .literal_text = @constCast("vtable { run = @main }"),
        .value = .{ .vtable = .{ .slots = slots_a[0..] } },
    };
    const vtable_b = const_decl.ConstDecl{
        .source_line = 1,
        .expanded_line = 1,
        .raw_text = @constCast("@const VT = vtable { run = @other }"),
        .name = @constCast("VT"),
        .literal_text = @constCast("vtable { run = @other }"),
        .value = .{ .vtable = .{ .slots = slots_b[0..] } },
    };
    var vtable_input = emptyInput(&.{instruction});
    vtable_input.const_decls = &.{vtable_a};
    var vtable_changed = vtable_input;
    vtable_changed.const_decls = &.{vtable_b};
    try expectDigestDifferent(try compute(std.testing.allocator, vtable_input), try compute(std.testing.allocator, vtable_changed));

    changed = base;
    changed.sax_component_name = "Other";
    try expectDigestDifferent(try compute(std.testing.allocator, base), try compute(std.testing.allocator, changed));

    changed = base;
    changed.check_exit_leaks = false;
    try expectDigestDifferent(try compute(std.testing.allocator, base), try compute(std.testing.allocator, changed));

    const function_sig = sig.FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
    };
    changed = base;
    changed.metadata = .{ .predecoded = .{ .symbol_names = &.{"main"}, .function_sigs = &.{function_sig} } };
    try expectDigestDifferent(try compute(std.testing.allocator, base), try compute(std.testing.allocator, changed));

    var changed_symbols = changed;
    changed_symbols.metadata = .{ .predecoded = .{ .symbol_names = &.{"other"}, .function_sigs = &.{function_sig} } };
    try expectDigestDifferent(try compute(std.testing.allocator, changed), try compute(std.testing.allocator, changed_symbols));

    var changed_sig = function_sig;
    changed_sig.return_ty = .i64;
    var changed_metadata = changed;
    changed_metadata.metadata = .{ .predecoded = .{ .symbol_names = &.{"main"}, .function_sigs = &.{changed_sig} } };
    try expectDigestDifferent(try compute(std.testing.allocator, changed), try compute(std.testing.allocator, changed_metadata));
}

test "verification input v2 canonicalizes grant and capability order" {
    const read_write = [_]pkg_manifest.Capability{ .io_read, .io_write };
    const write_read = [_]pkg_manifest.Capability{ .io_write, .io_read };
    const only_read = [_]pkg_manifest.Capability{.io_read};
    const location = pkg_manifest.UpstreamLoc{ .file = "manifest", .line = 1, .col = 1 };
    const grant_a = pkg_manifest.RequireEntry{ .url = "a", .ref = "1", .source_sha256 = [_]u8{1} ** 32, .grants = &read_write, .upstream_loc = location };
    const grant_a_permuted = pkg_manifest.RequireEntry{ .url = "a", .ref = "ignored-by-referee", .source_sha256 = [_]u8{1} ** 32, .grants = &write_read, .upstream_loc = location };
    const grant_b = pkg_manifest.RequireEntry{ .url = "b", .ref = "1", .source_sha256 = [_]u8{2} ** 32, .grants = &only_read, .upstream_loc = location };
    const instruction = inst.makeInstruction(.return_, 1, 1, null, "return 0");

    var first = emptyInput(&.{instruction});
    first.package_grants = &.{ grant_a, grant_b };
    var permuted = first;
    permuted.package_grants = &.{ grant_b, grant_a_permuted };
    try expectDigestEqual(try compute(std.testing.allocator, first), try compute(std.testing.allocator, permuted));

    var tightened = first;
    tightened.package_grants = &.{ pkg_manifest.RequireEntry{ .url = "a", .ref = "1", .source_sha256 = [_]u8{1} ** 32, .grants = &only_read, .upstream_loc = location }, grant_b };
    try expectDigestDifferent(try compute(std.testing.allocator, first), try compute(std.testing.allocator, tightened));

    var duplicate = first;
    duplicate.package_grants = &.{ grant_a, grant_a_permuted };
    try std.testing.expectError(error.DuplicatePackageGrant, compute(std.testing.allocator, duplicate));
}

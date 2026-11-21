const std = @import("std");
const classifier = @import("line_classifier.zig");
const common_instruction = @import("../common/instruction.zig");
const common_const_decl = @import("../common/const_decl.zig");
const common_signature = @import("../common/signature.zig");
const ConstDecl = @import("../common/const_decl.zig").ConstDecl;
const DefDict = @import("def_dict.zig").DefDict;
const FunctionSig = @import("../common/signature.zig").FunctionSig;
const InstKind = @import("../common/instruction.zig").InstKind;
const Instruction = @import("../common/instruction.zig").Instruction;
const InstructionForm = @import("line_classifier.zig").InstructionForm;
const LineKind = @import("line_classifier.zig").LineKind;
const Operand = @import("../common/instruction.zig").Operand;
const SymbolTable = @import("symbol.zig").SymbolTable;
const ArithmeticExpr = @import("expandimportsinto.zig").ArithmeticExpr;
const LayoutVersion = @import("importexpansion.zig").LayoutVersion;
const buildSymbolIdRemap = @import("cloneremappedsymboltext.zig").buildSymbolIdRemap;
const cloneRemappedFunctionSig = @import("cloneremappedsymboltext.zig").cloneRemappedFunctionSig;
const cloneRemappedInstruction = @import("injectimportedfile.zig").cloneRemappedInstruction;
const cloneRemappedSymbolIdSlice = @import("cloneremappedsymboltext.zig").cloneRemappedSymbolIdSlice;
const countSourceLines = @import("cloneremappedsymboltext.zig").countSourceLines;
const mergeConstDeclsAllowingIdentical = @import("cloneremappedsymboltext.zig").mergeConstDeclsAllowingIdentical;
const mergeDefDictAllowingIdentical = @import("cloneremappedsymboltext.zig").mergeDefDictAllowingIdentical;
const mergeLayoutVersionsAllowingIdentical = @import("cloneremappedsymboltext.zig").mergeLayoutVersionsAllowingIdentical;
const mergePackageIdentities = @import("cloneremappedsymboltext.zig").mergePackageIdentities;
const remapInstructionSymbolIds = @import("cloneremappedsymboltext.zig").remapInstructionSymbolIds;
const remapOperandSymbolIds = @import("cloneremappedsymboltext.zig").remapOperandSymbolIds;
const scanSource = @import("cloneremappedsymboltext.zig").scanSource;


pub fn buildArithmeticExpr(allocator: std.mem.Allocator, random: std.Random, depth: u8) !ArithmeticExpr {
    if (depth == 0 or random.intRangeAtMost(u8, 0, 3) == 0) {
        const raw = @as(i64, @intCast(random.intRangeAtMost(u32, 0, 9)));
        const signed = if (random.intRangeLessThan(u8, 0, 2) == 0) raw else -raw;
        return .{
            .text = try std.fmt.allocPrint(allocator, "{d}", .{signed}),
            .value = signed,
        };
    }

    var left = try buildArithmeticExpr(allocator, random, depth - 1);
    defer left.deinit(allocator);
    var right = try buildArithmeticExpr(allocator, random, depth - 1);
    defer right.deinit(allocator);

    const op_index = random.intRangeLessThan(u8, 0, 3);
    const op: u8 = switch (op_index) {
        0 => '+',
        1 => '-',
        else => '*',
    };
    const value: i64 = switch (op) {
        '+' => left.value + right.value,
        '-' => left.value - right.value,
        '*' => left.value * right.value,
        else => unreachable,
    };

    return .{
        .text = try std.fmt.allocPrint(allocator, "({s} {c} {s})", .{ left.text, op, right.text }),
        .value = value,
    };
}

pub fn expectOperandReg(inst: Instruction, index: usize, expected: u32) !void {
    switch (inst.operands[index]) {
        .reg => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestUnexpectedResult,
    }
}

pub fn expectOperandImmU64(inst: Instruction, index: usize, expected: u64) !void {
    switch (inst.operands[index]) {
        .imm_u64 => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestUnexpectedResult,
    }
}

pub fn expectOperandImmI64(inst: Instruction, index: usize, expected: i64) !void {
    switch (inst.operands[index]) {
        .imm_i64 => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestUnexpectedResult,
    }
}

pub fn expectRawText(inst: Instruction, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, inst.raw_text);
}

test "scanSource preserves line order and classification" {
    const source =
        \\#def SIZE = 16
        \\L_LOOP:
        \\node = alloc 8
    ;
    const lines = try scanSource(std.testing.allocator, source, &.{}, &.{});
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqual(@as(u32, 1), lines[0].line_no);
    try std.testing.expectEqual(LineKind.def, lines[0].classified.kind);
    try std.testing.expectEqual(LineKind.label, lines[1].classified.kind);
    try std.testing.expectEqual(LineKind.instruction, lines[2].classified.kind);
    try std.testing.expectEqual(InstructionForm.alloc, lines[2].classified.inst_form.?);
}

test "countSourceLines matches splitScalar line count" {
    try std.testing.expectEqual(@as(usize, 1), countSourceLines(""));
    try std.testing.expectEqual(@as(usize, 1), countSourceLines("one"));
    try std.testing.expectEqual(@as(usize, 2), countSourceLines("one\ntwo"));
    try std.testing.expectEqual(@as(usize, 3), countSourceLines("one\ntwo\n"));
}

test "symbol id remap rewrites instruction symbol operands" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    const reg_id = try source_symbols.intern("value");
    const label_id = try source_symbols.intern("L_DONE");
    const func_id = try source_symbols.intern("callee");

    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    _ = try target_symbols.intern("preexisting");

    const remap = try buildSymbolIdRemap(std.testing.allocator, &source_symbols, &target_symbols);
    defer std.testing.allocator.free(remap);

    var instruction = common_instruction.makeInstruction(.call, 1, 0, null, "dst = call callee(value)");
    instruction.operands[0] = .{ .reg = reg_id };
    instruction.operands[1] = .{ .symbol = label_id };
    instruction.operands[2] = .{ .label = label_id };
    instruction.operands[3] = .{ .func = func_id };

    try remapInstructionSymbolIds(&instruction, remap);
    try std.testing.expectEqual(target_symbols.findId("value").?, instruction.operands[0].reg);
    try std.testing.expectEqual(target_symbols.findId("L_DONE").?, instruction.operands[1].symbol);
    try std.testing.expectEqual(target_symbols.findId("L_DONE").?, instruction.operands[2].label);
    try std.testing.expectEqual(target_symbols.findId("callee").?, instruction.operands[3].func);
    try std.testing.expect(target_symbols.findId("value").? != reg_id);
}

test "symbol id remap leaves non-symbol operands unchanged and rejects unknown ids" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    _ = try source_symbols.intern("value");

    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();

    const remap = try buildSymbolIdRemap(std.testing.allocator, &source_symbols, &target_symbols);
    defer std.testing.allocator.free(remap);

    var text_operand = Operand{ .text = "value" };
    try remapOperandSymbolIds(&text_operand, remap);
    try std.testing.expectEqualStrings("value", text_operand.text);

    var imm_operand = Operand{ .imm_u64 = 42 };
    try remapOperandSymbolIds(&imm_operand, remap);
    try std.testing.expectEqual(@as(u64, 42), imm_operand.imm_u64);

    var invalid_operand = Operand{ .reg = 99 };
    try std.testing.expectError(error.InvalidOperand, remapOperandSymbolIds(&invalid_operand, remap));
}

test "symbol id remap clones function signature id slices" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    const a = try source_symbols.intern("a");
    const b = try source_symbols.intern("b");
    const c = try source_symbols.intern("c");

    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    _ = try target_symbols.intern("occupied");

    const remap = try buildSymbolIdRemap(std.testing.allocator, &source_symbols, &target_symbols);
    defer std.testing.allocator.free(remap);

    const original = [_]u32{ a, b, c };
    const cloned = try cloneRemappedSymbolIdSlice(std.testing.allocator, original[0..], remap);
    defer std.testing.allocator.free(cloned);
    try std.testing.expectEqualSlices(u32, &.{ target_symbols.findId("a").?, target_symbols.findId("b").?, target_symbols.findId("c").? }, cloned);
    try std.testing.expect(cloned.ptr != original[0..].ptr);

    const empty = try cloneRemappedSymbolIdSlice(std.testing.allocator, &.{}, remap);
    try std.testing.expectEqual(@as(usize, 0), empty.len);
    try std.testing.expectError(error.InvalidOperand, cloneRemappedSymbolIdSlice(std.testing.allocator, &.{99}, remap));
}

test "symbol id remap clones full function signatures" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    _ = try source_symbols.intern("work");
    const lhs_id = try source_symbols.intern("lhs");
    const rhs_id = try source_symbols.intern("rhs");
    const tmp_id = try source_symbols.intern("tmp");

    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    _ = try target_symbols.intern("occupied");
    const remap = try buildSymbolIdRemap(std.testing.allocator, &source_symbols, &target_symbols);
    defer std.testing.allocator.free(remap);

    const source_params = try std.testing.allocator.alloc(common_signature.ParamSpec, 2);
    source_params[0] = .{ .name = try std.testing.allocator.dupe(u8, "lhs"), .ty = .i64, .cap = .borrow };
    source_params[1] = .{ .name = try std.testing.allocator.dupe(u8, "rhs"), .ty = .i64, .cap = .move };

    var source_sig = FunctionSig{
        .id = 7,
        .name = try std.testing.allocator.dupe(u8, "work"),
        .params = source_params,
        .kind = .test_func,
        .return_cap = .move,
        .return_ty = .i64,
        .return_fallible = true,
        .entry_inst_idx = 12,
        .is_ffi_wrapper = false,
        .upstream_file = try std.testing.allocator.dupe(u8, "test.sa"),
        .upstream_loc = null,
        .param_ids = try std.testing.allocator.dupe(u32, &.{ lhs_id, rhs_id }),
        .reg_ids = try std.testing.allocator.dupe(u32, &.{ lhs_id, rhs_id, tmp_id }),
        .llvm_name = try std.testing.allocator.dupe(u8, "_saasm_test_7"),
        .ignored = true,
        .should_panic = true,
    };
    source_sig.upstream_loc = .{ .file = source_sig.upstream_file.?, .line = 9, .col = 4 };
    defer source_sig.deinit(std.testing.allocator);

    var cloned = try cloneRemappedFunctionSig(std.testing.allocator, source_sig, remap, 100, 200);
    defer cloned.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 107), cloned.id);
    try std.testing.expectEqual(@as(u32, 212), cloned.entry_inst_idx);
    try std.testing.expectEqualSlices(u32, &.{ target_symbols.findId("lhs").?, target_symbols.findId("rhs").? }, cloned.param_ids);
    try std.testing.expectEqualSlices(u32, &.{ target_symbols.findId("lhs").?, target_symbols.findId("rhs").?, target_symbols.findId("tmp").? }, cloned.reg_ids);
    try std.testing.expectEqualStrings("work", cloned.name);
    try std.testing.expectEqualStrings("lhs", cloned.params[0].name);
    try std.testing.expectEqual(common_signature.PrimType.i64, cloned.params[0].ty);
    try std.testing.expectEqual(common_instruction.CapPrefix.borrow, cloned.params[0].cap);
    try std.testing.expectEqualStrings("_saasm_test_107", cloned.llvm_name.?);
    try std.testing.expect(cloned.ignored);
    try std.testing.expect(cloned.should_panic);
    try std.testing.expect(cloned.name.ptr != source_sig.name.ptr);
    try std.testing.expect(cloned.params[0].name.ptr != source_sig.params[0].name.ptr);
    try std.testing.expect(cloned.param_ids.ptr != source_sig.param_ids.ptr);
    try std.testing.expect(cloned.reg_ids.ptr != source_sig.reg_ids.ptr);
    try std.testing.expect(cloned.upstream_file.?.ptr != source_sig.upstream_file.?.ptr);
    try std.testing.expectEqualStrings("test.sa", cloned.upstream_file.?);
    try std.testing.expectEqualStrings(cloned.upstream_file.?, cloned.upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 9), cloned.upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 4), cloned.upstream_loc.?.col);
}

test "symbol id remap rejects function signatures with unknown ids" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    const known = try source_symbols.intern("known");
    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    const remap = try buildSymbolIdRemap(std.testing.allocator, &source_symbols, &target_symbols);
    defer std.testing.allocator.free(remap);

    var source_sig = FunctionSig{
        .id = 0,
        .name = try std.testing.allocator.dupe(u8, "missing"),
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .void,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .param_ids = try std.testing.allocator.dupe(u32, &.{known}),
        .reg_ids = try std.testing.allocator.dupe(u32, &.{99}),
    };
    defer source_sig.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidOperand, cloneRemappedFunctionSig(std.testing.allocator, source_sig, remap, 0, 0));
}

test "frontend cache merge keeps identical defs and rejects conflicts" {
    var target = DefDict.init(std.testing.allocator);
    defer target.deinit();
    try target.putExpression("A", "1");

    var source = DefDict.init(std.testing.allocator);
    defer source.deinit();
    try source.putExpression("A", "1");
    try source.putExpression("B", "A + 1");

    const source_b = source.get("B").?;
    try mergeDefDictAllowingIdentical(&target, &source);
    try std.testing.expectEqual(@as(usize, 2), target.entries.count());
    try std.testing.expectEqualStrings("1", target.get("A").?);
    try std.testing.expectEqualStrings("2", target.get("B").?);
    try std.testing.expect(target.get("B").?.ptr != source_b.ptr);

    var conflict = DefDict.init(std.testing.allocator);
    defer conflict.deinit();
    try conflict.putExpression("A", "2");
    try std.testing.expectError(error.DuplicateDef, mergeDefDictAllowingIdentical(&target, &conflict));
}

test "frontend cache merge clones const declarations and rejects conflicts" {
    const upstream_file = try std.testing.allocator.dupe(u8, "module.sa");
    var source_decl = try common_const_decl.parseConstDecl(
        std.testing.allocator,
        "@const HELLO = utf8:\"hello\"",
        3,
        5,
        .{ .file = upstream_file, .line = 9, .col = 2 },
    );
    defer source_decl.deinit(std.testing.allocator);

    var target = std.array_list.Managed(ConstDecl).init(std.testing.allocator);
    defer {
        for (target.items) |*decl| decl.deinit(std.testing.allocator);
        target.deinit();
    }

    try mergeConstDeclsAllowingIdentical(std.testing.allocator, &target, &.{source_decl}, 10, 20);
    try std.testing.expectEqual(@as(usize, 1), target.items.len);
    try std.testing.expectEqual(@as(u32, 13), target.items[0].source_line);
    try std.testing.expectEqual(@as(u32, 25), target.items[0].expanded_line);
    try std.testing.expectEqualStrings("HELLO", target.items[0].name);
    try std.testing.expectEqualStrings("utf8:\"hello\"", target.items[0].literal_text);
    try std.testing.expect(target.items[0].raw_text.ptr != source_decl.raw_text.ptr);
    try std.testing.expect(target.items[0].name.ptr != source_decl.name.ptr);
    try std.testing.expect(target.items[0].literal_text.ptr != source_decl.literal_text.ptr);
    try std.testing.expect(target.items[0].upstream_loc.?.file.ptr != source_decl.upstream_loc.?.file.ptr);
    switch (target.items[0].value) {
        .utf8 => |literal| switch (source_decl.value) {
            .utf8 => |source_literal| {
                try std.testing.expectEqualStrings("hello", literal.bytes);
                try std.testing.expect(literal.bytes.ptr != source_literal.bytes.ptr);
            },
            else => return error.TestUnexpectedResult,
        },
        else => return error.TestUnexpectedResult,
    }

    try mergeConstDeclsAllowingIdentical(std.testing.allocator, &target, &.{source_decl}, 100, 100);
    try std.testing.expectEqual(@as(usize, 1), target.items.len);

    var conflict = try common_const_decl.parseConstDecl(
        std.testing.allocator,
        "@const HELLO = utf8:\"bye\"",
        4,
        6,
        null,
    );
    defer conflict.deinit(std.testing.allocator);
    try std.testing.expectError(error.DuplicateConstDecl, mergeConstDeclsAllowingIdentical(std.testing.allocator, &target, &.{conflict}, 0, 0));
}

test "frontend cache clone remaps instruction symbols and owned metadata" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    const dst_id = try source_symbols.intern("dst");
    const callee_id = try source_symbols.intern("callee");

    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    _ = try target_symbols.intern("occupied");
    const remap = try buildSymbolIdRemap(std.testing.allocator, &source_symbols, &target_symbols);
    defer std.testing.allocator.free(remap);

    var source = common_instruction.makeInstruction(
        .call,
        7,
        3,
        .{ .file = try std.testing.allocator.dupe(u8, "source.sa"), .line = 40, .col = 5 },
        "dst = call callee(value)",
    );
    defer std.testing.allocator.free(source.upstream_loc.?.file);
    source.package_identity = try std.testing.allocator.dupe(u8, "pkg/core");
    defer std.testing.allocator.free(source.package_identity.?);
    source.package_source_sha256 = @splat(@as(u8, 7));
    source.operands[0] = .{ .reg = dst_id };
    source.operands[1] = .{ .func = callee_id };
    source.operands[2] = .{ .text = "borrow" };
    source.atomic_expected_text = "old";
    source.atomic_new_text = "new";

    var owned_text = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer {
        for (owned_text.items) |text| std.testing.allocator.free(text);
        owned_text.deinit();
    }
    const cloned = try cloneRemappedInstruction(std.testing.allocator, &owned_text, source, &source_symbols, &target_symbols, remap, 10, 20);
    defer {
        if (cloned.package_identity) |identity| std.testing.allocator.free(identity);
        if (cloned.upstream_loc) |loc| std.testing.allocator.free(loc.file);
        if (cloned.native_reg_names.len != 0) std.testing.allocator.free(cloned.native_reg_names);
    }

    try std.testing.expectEqual(InstKind.call, cloned.kind);
    try std.testing.expectEqual(@as(u32, 17), cloned.source_line);
    try std.testing.expectEqual(@as(u32, 23), cloned.expanded_line);
    try std.testing.expectEqual(target_symbols.findId("dst").?, cloned.operands[0].reg);
    try std.testing.expectEqual(target_symbols.findId("callee").?, cloned.operands[1].func);
    try std.testing.expectEqualStrings("borrow", cloned.operands[2].text);
    try std.testing.expect(cloned.operands[2].text.ptr != source.operands[2].text.ptr);
    try std.testing.expectEqualStrings("dst = call callee(value)", cloned.raw_text);
    try std.testing.expect(cloned.raw_text.ptr != source.raw_text.ptr);
    try std.testing.expectEqualStrings("pkg/core", cloned.package_identity.?);
    try std.testing.expect(cloned.package_identity.?.ptr != source.package_identity.?.ptr);
    try std.testing.expectEqual(@as(u8, 7), cloned.package_source_sha256.?[0]);
    try std.testing.expectEqualStrings("source.sa", cloned.upstream_loc.?.file);
    try std.testing.expect(cloned.upstream_loc.?.file.ptr != source.upstream_loc.?.file.ptr);
    try std.testing.expectEqual(@as(u32, 40), cloned.upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 5), cloned.upstream_loc.?.col);
    try std.testing.expectEqualStrings("old", cloned.atomic_expected_text.?);
    try std.testing.expectEqualStrings("new", cloned.atomic_new_text.?);
    try std.testing.expect(cloned.atomic_expected_text.?.ptr != source.atomic_expected_text.?.ptr);
    try std.testing.expect(cloned.atomic_new_text.?.ptr != source.atomic_new_text.?.ptr);
}

test "frontend cache clone remaps embedded call text tokens with operands" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    const dst_id = try source_symbols.intern("dst");
    const tmp_id = try source_symbols.intern("tmp_0");
    const callee_id = try source_symbols.intern("callee");
    const opaque_arg_id = try source_symbols.intern("__sla_macro_arg_0");

    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();
    _ = try target_symbols.intern("occupied");
    const remapped_dst_id = try target_symbols.intern("__frag0_dst");
    const remapped_tmp_id = try target_symbols.intern("__frag1_tmp_0");
    const remapped_callee_id = try target_symbols.intern("renamed_callee");
    const remapped_opaque_arg_id = try target_symbols.intern("__frag2_arg");

    const remap = [_]u32{ remapped_dst_id, remapped_tmp_id, remapped_callee_id, remapped_opaque_arg_id };

    var source = common_instruction.makeInstruction(
        .call,
        11,
        4,
        null,
        "dst = call @callee(^tmp_0, &__sla_macro_arg_0, \"tmp_0\")",
    );
    source.operands[0] = .{ .reg = dst_id };
    source.operands[1] = .{ .text = "@callee(^tmp_0, &__sla_macro_arg_0, \"tmp_0\")" };
    source.atomic_expected_text = "tmp_0";
    source.atomic_new_text = "__sla_macro_arg_0";
    _ = tmp_id;
    _ = callee_id;
    _ = opaque_arg_id;

    var owned_text = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer {
        for (owned_text.items) |text| std.testing.allocator.free(text);
        owned_text.deinit();
    }
    const cloned = try cloneRemappedInstruction(std.testing.allocator, &owned_text, source, &source_symbols, &target_symbols, remap[0..], 0, 0);
    defer {
        if (cloned.package_identity) |identity| std.testing.allocator.free(identity);
        if (cloned.upstream_loc) |loc| std.testing.allocator.free(loc.file);
        if (cloned.native_reg_names.len != 0) std.testing.allocator.free(cloned.native_reg_names);
    }

    try std.testing.expectEqual(remapped_dst_id, cloned.operands[0].reg);
    try std.testing.expectEqualStrings("@renamed_callee(^__frag1_tmp_0, &__sla_macro_arg_0, \"tmp_0\")", cloned.operands[1].text);
    try std.testing.expectEqualStrings("__frag0_dst = call @renamed_callee(^__frag1_tmp_0, &__sla_macro_arg_0, \"tmp_0\")", cloned.raw_text);
    try std.testing.expectEqualStrings("__frag1_tmp_0", cloned.atomic_expected_text.?);
    try std.testing.expectEqualStrings("__sla_macro_arg_0", cloned.atomic_new_text.?);
}

test "frontend cache clone rebuilds native register name slices" {
    var source_symbols = SymbolTable.init(std.testing.allocator);
    defer source_symbols.deinit();
    var target_symbols = SymbolTable.init(std.testing.allocator);
    defer target_symbols.deinit();

    const native_text = "call side(ptr value, i32 7)";
    var source = common_instruction.makeInstruction(.native, 2, 1, null, "$call side(ptr value, i32 7)$");
    source.operands[0] = .{ .native_text = native_text };
    source.native_reg_names = try classifier.collectNativeRegisterNames(std.testing.allocator, native_text);
    defer std.testing.allocator.free(source.native_reg_names);

    var owned_text = std.array_list.Managed([]const u8).init(std.testing.allocator);
    defer {
        for (owned_text.items) |text| std.testing.allocator.free(text);
        owned_text.deinit();
    }
    const cloned = try cloneRemappedInstruction(std.testing.allocator, &owned_text, source, &source_symbols, &target_symbols, &.{}, 4, 8);
    defer {
        if (cloned.package_identity) |identity| std.testing.allocator.free(identity);
        if (cloned.upstream_loc) |loc| std.testing.allocator.free(loc.file);
        if (cloned.native_reg_names.len != 0) std.testing.allocator.free(cloned.native_reg_names);
    }

    try std.testing.expectEqual(InstKind.native, cloned.kind);
    try std.testing.expectEqual(@as(u32, 6), cloned.source_line);
    try std.testing.expectEqual(@as(u32, 9), cloned.expanded_line);
    try std.testing.expectEqualStrings(native_text, cloned.operands[0].native_text);
    try std.testing.expect(cloned.operands[0].native_text.ptr != source.operands[0].native_text.ptr);
    try std.testing.expectEqual(@as(usize, 5), cloned.native_reg_names.len);
    try std.testing.expectEqualStrings("call", cloned.native_reg_names[0]);
    try std.testing.expectEqualStrings("side", cloned.native_reg_names[1]);
    try std.testing.expectEqualStrings("ptr", cloned.native_reg_names[2]);
    try std.testing.expectEqualStrings("value", cloned.native_reg_names[3]);
    try std.testing.expectEqualStrings("i32", cloned.native_reg_names[4]);
    try std.testing.expect(cloned.native_reg_names[0].ptr != source.native_reg_names[0].ptr);
}

test "frontend cache merge package identities deep copies new keys" {
    var target = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var it = target.iterator();
        while (it.next()) |entry| std.testing.allocator.free(entry.key_ptr.*);
        target.deinit();
    }
    try target.put(try std.testing.allocator.dupe(u8, "pkg/a"), {});

    var source = std.StringHashMap(void).init(std.testing.allocator);
    defer {
        var it = source.iterator();
        while (it.next()) |entry| std.testing.allocator.free(entry.key_ptr.*);
        source.deinit();
    }
    try source.put(try std.testing.allocator.dupe(u8, "pkg/a"), {});
    try source.put(try std.testing.allocator.dupe(u8, "pkg/b"), {});
    const source_b_key = source.getKeyPtr("pkg/b").?.*;

    try mergePackageIdentities(std.testing.allocator, &target, &source);
    try std.testing.expectEqual(@as(u32, 2), target.count());
    const target_b_key = target.getKeyPtr("pkg/b").?.*;
    try std.testing.expectEqualStrings("pkg/b", target_b_key);
    try std.testing.expect(target_b_key.ptr != source_b_key.ptr);

    try mergePackageIdentities(std.testing.allocator, &target, &source);
    try std.testing.expectEqual(@as(u32, 2), target.count());
}

test "frontend cache merge layout versions skips identical and rejects conflicts" {
    var target = std.array_list.Managed(LayoutVersion).init(std.testing.allocator);
    defer {
        for (target.items) |*item| item.deinit(std.testing.allocator);
        target.deinit();
    }
    try target.append(.{ .path = try std.testing.allocator.dupe(u8, "a.sal"), .version = 1 });

    var source = [_]LayoutVersion{
        .{ .path = try std.testing.allocator.dupe(u8, "a.sal"), .version = 1 },
        .{ .path = try std.testing.allocator.dupe(u8, "b.sal"), .version = 2 },
    };
    defer for (&source) |*item| item.deinit(std.testing.allocator);

    try mergeLayoutVersionsAllowingIdentical(std.testing.allocator, &target, source[0..]);
    try std.testing.expectEqual(@as(usize, 2), target.items.len);
    try std.testing.expectEqualStrings("b.sal", target.items[1].path);
    try std.testing.expectEqual(@as(u64, 2), target.items[1].version);
    try std.testing.expect(target.items[1].path.ptr != source[1].path.ptr);

    var conflict = [_]LayoutVersion{
        .{ .path = try std.testing.allocator.dupe(u8, "a.sal"), .version = 99 },
    };
    defer for (&conflict) |*item| item.deinit(std.testing.allocator);
    try std.testing.expectError(error.LayoutVersionConflict, mergeLayoutVersionsAllowingIdentical(std.testing.allocator, &target, conflict[0..]));
}

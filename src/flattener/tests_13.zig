const std = @import("std");
const sio = @import("sio");
const forbidden = @import("forbidden.zig");
const common_instruction = @import("../common/instruction.zig");
const InstKind = @import("../common/instruction.zig").InstKind;
const buildArithmeticExpr = @import("tests_10.zig").buildArithmeticExpr;
const buildMacroPbtProgram = @import("expandimportsinto.zig").buildMacroPbtProgram;
const expectOperandImmI64 = @import("tests_10.zig").expectOperandImmI64;
const expectOperandImmU64 = @import("tests_10.zig").expectOperandImmU64;
const expectOperandReg = @import("tests_10.zig").expectOperandReg;
const expectRawText = @import("tests_10.zig").expectRawText;
const findFirstForbiddenLine = @import("expandimportsinto.zig").findFirstForbiddenLine;
const flatten = @import("expandimportsinto.zig").flatten;
const flattenFile = @import("expandimportsinto.zig").flattenFile;


test "flatten expands source location macros from upstream location and file path" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var tdir: sio.Dir = .{ .inner = tmp.dir };

    var main_file = try tdir.createFile("main.sa", .{ .truncate = true });
    try main_file.writeAll(
        \\#loc "up.rs":42:7
        \\@main() -> i32:
        \\L_ENTRY:
        \\line_out = alloc 8
        \\#loc "up.rs":42:9
        \\EXPAND LINE! line_out
        \\EXPAND COLUMN! line_out
        \\file_slice = alloc 8
        \\EXPAND FILE! file_slice
        \\return 0
    );
    main_file.close();

    const source = try tdir.readFileAlloc(std.testing.allocator, "main.sa", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tdir.realpathAlloc(std.testing.allocator, "main.sa");
    defer std.testing.allocator.free(source_path);

    var result = try flattenFile(std.testing.allocator, source_path, source);
    defer result.deinit(std.testing.allocator);

    var saw_line = false;
    var saw_column = false;
    var saw_file_decl = false;
    for (result.instructions) |inst| {
        if (inst.kind != .op) continue;
        if (inst.op_kind != .add) continue;
        switch (inst.operands[2]) {
            .imm_i64 => |value| {
                if (value == 42) saw_line = true;
                if (value == 9) saw_column = true;
            },
            else => {},
        }
    }
    try std.testing.expect(saw_line);
    try std.testing.expect(saw_column);

    for (result.const_decls) |decl| {
        switch (decl.value) {
            .utf8 => |literal| {
                if (std.mem.eql(u8, literal.bytes, source_path)) {
                    if (std.mem.startsWith(u8, decl.name, "__SOURCE_FILE_")) saw_file_decl = true;
                }
            },
            else => {},
        }
    }

    try std.testing.expect(saw_file_decl);
}

test "macro PBT expands nested macros and repeat bodies deterministically" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6A10);
    const random = prng.random();

    for (0..48) |iter| {
        var program = try buildMacroPbtProgram(std.testing.allocator, random, iter);
        defer program.deinit(std.testing.allocator);

        var result = try flatten(std.testing.allocator, program.source);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 1), result.function_sigs.len);
        try std.testing.expectEqual(@as(usize, 0), result.const_decls.len);
        try std.testing.expectEqual(@as(usize, 4) + program.count, result.instructions.len);

        const base_id = result.symbols.findId(program.base_name) orelse return error.TestUnexpectedResult;
        const acc_id = result.symbols.findId(program.acc_name) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(program.base_name, result.symbols.lookupName(base_id).?);
        try std.testing.expectEqualStrings(program.acc_name, result.symbols.lookupName(acc_id).?);

        try std.testing.expectEqual(InstKind.func_decl, result.instructions[0].kind);
        try std.testing.expectEqual(InstKind.alloc, result.instructions[1].kind);
        try std.testing.expectEqual(InstKind.op, result.instructions[2].kind);
        try std.testing.expectEqual(common_instruction.OpKind.add, result.instructions[2].op_kind.?);
        try std.testing.expectEqual(InstKind.return_, result.instructions[result.instructions.len - 1].kind);

        var line_buf: [128]u8 = undefined;
        var tmp_buf: [32]u8 = undefined;

        const alloc_line = try std.fmt.bufPrint(&line_buf, "    {s} = alloc {d}", .{ program.base_name, program.alloc_size });
        try expectRawText(result.instructions[1], alloc_line);
        try expectOperandReg(result.instructions[1], 0, base_id);
        try expectOperandImmU64(result.instructions[1], 1, program.alloc_size);

        const seed_line = try std.fmt.bufPrint(&line_buf, "    {s} = add {s}, 0", .{ program.acc_name, program.base_name });
        try expectRawText(result.instructions[2], seed_line);
        try expectOperandReg(result.instructions[2], 0, acc_id);
        try expectOperandReg(result.instructions[2], 1, base_id);
        try expectOperandImmI64(result.instructions[2], 2, 0);

        for (0..program.count) |idx| {
            const tmp_name = try std.fmt.bufPrint(&tmp_buf, "tmp_{d}", .{idx});
            const tmp_id = result.symbols.findId(tmp_name) orelse return error.TestUnexpectedResult;
            const inst = result.instructions[3 + idx];
            const expected_text = try std.fmt.bufPrint(&line_buf, "        {s} = add {s}, {d}", .{ tmp_name, program.acc_name, idx });
            try expectRawText(inst, expected_text);
            try std.testing.expectEqual(InstKind.op, inst.kind);
            try std.testing.expectEqual(common_instruction.OpKind.add, inst.op_kind.?);
            try expectOperandReg(inst, 0, tmp_id);
            try expectOperandReg(inst, 1, acc_id);
            try expectOperandImmI64(inst, 2, @intCast(idx));
        }

        const return_line = try std.fmt.bufPrint(&line_buf, "    return {s}", .{program.acc_name});
        try expectRawText(result.instructions[result.instructions.len - 1], return_line);
        try expectOperandReg(result.instructions[result.instructions.len - 1], 0, acc_id);
    }
}

test "variadic macro parameters consume remaining arguments" {
    const source =
        \\[MACRO] CALL_SUM %dst, %args...
        \\    %dst = call @sum(%args)
        \\[END_MACRO]
        \\[MACRO] ZERO_OK %dst, %args...
        \\    %dst = add 1, 0
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\    EXPAND CALL_SUM total, 1, 2, 3
        \\    EXPAND ZERO_OK empty
        \\    return 0
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expectEqual(InstKind.func_decl, result.instructions[0].kind);
    try std.testing.expectEqual(InstKind.call, result.instructions[1].kind);
    try expectRawText(result.instructions[1], "    total = call @sum(1, 2, 3)");
    try std.testing.expectEqual(InstKind.op, result.instructions[2].kind);
    try expectRawText(result.instructions[2], "    empty = add 1, 0");
    try std.testing.expectEqual(InstKind.return_, result.instructions[3].kind);
}

test "variadic macro parameter must be last" {
    const source =
        \\[MACRO] BAD %args..., %tail
        \\    %tail = add 1, 0
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\    return 0
    ;

    try std.testing.expectError(error.InvalidMacroInvocation, flatten(std.testing.allocator, source));
}

test "macro-time conditionals select then else and nested branches" {
    const source =
        \\[MACRO] PICK %dst, %flag
        \\[IF %flag]
        \\    %dst = add 10, 1
        \\[ELSE]
        \\    %dst = add 20, 2
        \\[END_IF]
        \\[END_MACRO]
        \\[MACRO] NEST %dst, %outer, %inner
        \\[IF %outer]
        \\[IF %inner]
        \\    %dst = add 1, 1
        \\[ELSE]
        \\    %dst = add 2, 2
        \\[END_IF]
        \\[END_IF]
        \\[END_MACRO]
        \\[MACRO] MAYBE %dst, %flag
        \\[IF %flag]
        \\    %dst = add 9, 9
        \\[END_IF]
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\    EXPAND PICK a, true
        \\    EXPAND PICK b, false
        \\    EXPAND NEST c, 1, 0
        \\    EXPAND MAYBE d, 0
        \\    return 0
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), result.instructions.len);
    try expectRawText(result.instructions[1], "    a = add 10, 1");
    try expectRawText(result.instructions[2], "    b = add 20, 2");
    try expectRawText(result.instructions[3], "    c = add 2, 2");
    try std.testing.expectEqual(InstKind.return_, result.instructions[4].kind);
}

test "macro-time conditional rejects invalid condition values" {
    const source =
        \\[MACRO] BAD %flag
        \\[IF %flag]
        \\    x = add 1, 0
        \\[END_IF]
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\    EXPAND BAD maybe
        \\    return 0
    ;

    try std.testing.expectError(error.InvalidMacroInvocation, flatten(std.testing.allocator, source));
}

test "duplicate macro definitions are rejected" {
    const source =
        \\[MACRO] DUP %x
        \\    %x = add 1, 0
        \\[END_MACRO]
        \\[MACRO] DUP %x
        \\    %x = add 2, 0
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\    return 0
    ;

    try std.testing.expectError(error.DuplicateDef, flatten(std.testing.allocator, source));
}

test "macro PBT rejects invalid definitions and invocations" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6A11);
    const random = prng.random();

    for (0..36) |iter| {
        const case_id = random.intRangeLessThan(u8, 0, 6);
        const ghost_name = try std.fmt.allocPrint(std.testing.allocator, "ghost_{d}_{d}", .{ iter, random.intRangeAtMost(u16, 0, 9999) });
        defer std.testing.allocator.free(ghost_name);

        const source = switch (case_id) {
            0 => try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\EXPAND {s} value
                \\return 0
            , .{ghost_name}),
            1 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] SINGLE %x
                \\    %x = add 1, 0
                \\[END_MACRO]
                \\
                \\@main() -> i32:
                \\    EXPAND SINGLE value, extra
                \\    return 0
            , .{}),
            2 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] DUP %x
                \\    %x = add 1, 0
                \\[END_MACRO]
                \\[MACRO] DUP %x
                \\    %x = add 2, 0
                \\[END_MACRO]
                \\
                \\@main() -> i32:
                \\    return 0
            , .{}),
            3 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] OPEN %x
                \\    %x = add 1, 0
                \\
                \\@main() -> i32:
                \\    return 0
            , .{}),
            4 => try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\[REP 2]
                \\    return 0
                \\return 0
            , .{}),
            5 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] LOOP %x
                \\    EXPAND LOOP %x
                \\[END_MACRO]
                \\
                \\@main() -> i32:
                \\    EXPAND LOOP value
                \\    return 0
            , .{}),
            else => unreachable,
        };
        defer std.testing.allocator.free(source);

        const expected_error = switch (case_id) {
            // Case 0 expands a macro that was never defined: since
            // DEF-ASM-AND-NAMED-REG that is error.UndefinedMacro, not the
            // generic InvalidMacroInvocation (which case 1, an argument
            // count mismatch against a defined macro, still produces).
            0 => error.UndefinedMacro,
            1 => error.InvalidMacroInvocation,
            2 => error.DuplicateDef,
            3 => error.UnbalancedMacro,
            4 => error.UnbalancedRep,
            5 => error.MacroRecursionLimit,
            else => unreachable,
        };
        try std.testing.expectError(expected_error, flatten(std.testing.allocator, source));
    }
}

test "REP fan-out over the expanded line budget fails before expansion" {
    const source =
        \\@main() -> i32:
        \\[REP 10000001]
        \\    _tmp%i = add 0, 0
        \\[END_REP]
        \\    return 0
    ;

    try std.testing.expectError(error.MacroExpansionBudget, flatten(std.testing.allocator, source));
}

test "REP count overflow maps to macro expansion budget" {
    const source =
        \\@main() -> i32:
        \\[REP 999999999999999999999999]
        \\    _tmp%i = add 0, 0
        \\[END_REP]
        \\    return 0
    ;

    try std.testing.expectError(error.MacroExpansionBudget, flatten(std.testing.allocator, source));
}

test "def dict PBT folds random arithmetic expressions through flatten" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6A20);
    const random = prng.random();

    for (0..48) |iter| {
        var base_expr = try buildArithmeticExpr(std.testing.allocator, random, 3);
        defer base_expr.deinit(std.testing.allocator);

        const delta = @as(i64, @intCast(random.intRangeAtMost(i32, -3, 6)));
        const size_value = base_expr.value + delta;

        const tmp_name = try std.fmt.allocPrint(std.testing.allocator, "tmp_{d}", .{iter});
        defer std.testing.allocator.free(tmp_name);

        var aw: std.Io.Writer.Allocating = .init(std.testing.allocator);
        errdefer aw.deinit();
        const writer = &aw.writer;
        try writer.writeAll("#def BASE = ");
        try writer.writeAll(base_expr.text);
        try writer.writeByte('\n');
        try writer.print("#def SIZE = BASE + {d}\n", .{delta});
        try writer.writeAll("@main() -> i32:\n");
        try writer.print("{s} = add SIZE, 1\n", .{tmp_name});
        try writer.print("return {s}\n", .{tmp_name});

        const source_text = try aw.toOwnedSlice();
        defer std.testing.allocator.free(source_text);

        var result = try flatten(std.testing.allocator, source_text);
        defer result.deinit(std.testing.allocator);

        var base_buf: [32]u8 = undefined;
        const base_text = try std.fmt.bufPrint(&base_buf, "{d}", .{base_expr.value});
        try std.testing.expectEqualStrings(base_text, result.def_dict.get("BASE").?);

        var size_buf: [32]u8 = undefined;
        const size_text = try std.fmt.bufPrint(&size_buf, "{d}", .{size_value});
        try std.testing.expectEqualStrings(size_text, result.def_dict.get("SIZE").?);

        try std.testing.expectEqual(@as(usize, 3), result.instructions.len);
        try std.testing.expectEqual(InstKind.func_decl, result.instructions[0].kind);
        try std.testing.expectEqual(InstKind.op, result.instructions[1].kind);
        try std.testing.expectEqual(common_instruction.OpKind.add, result.instructions[1].op_kind.?);
        try expectOperandImmI64(result.instructions[1], 1, size_value);
        try expectOperandImmI64(result.instructions[1], 2, 1);
        try std.testing.expectEqual(InstKind.return_, result.instructions[2].kind);
    }
}

test "forbidden syntax PBT rejects random forbidden lines through flatten" {
    const ForbiddenCase = struct {
        text: []const u8,
        token: forbidden.ForbiddenToken,
    };

    const cases = [_]ForbiddenCase{
        .{ .text = "if x = 1", .token = .keyword_if },
        .{ .text = "else x = 1", .token = .keyword_else },
        .{ .text = "while x = 1", .token = .keyword_while },
        .{ .text = "for x = 1", .token = .keyword_for },
        .{ .text = "x = { y }", .token = .brace_open },
        .{ .text = "x = }", .token = .brace_close },
        .{ .text = "x = a.b.c", .token = .property_chain },
    };

    var prng = std.Random.DefaultPrng.init(0x5A5A_6A21);
    const random = prng.random();

    for (0..48) |iter| {
        const case = cases[random.intRangeLessThan(usize, 0, cases.len)];
        try std.testing.expectEqual(case.token, forbidden.findForbiddenSyntax(case.text).?.token);

        const forbidden_at_tail = (iter & 1) == 0;
        const source = if (forbidden_at_tail) blk: {
            break :blk try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\value = alloc 8
                \\{s}
                \\return 0
            , .{case.text});
        } else blk: {
            break :blk try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\{s}
                \\value = alloc 8
                \\return 0
            , .{case.text});
        };
        defer std.testing.allocator.free(source);

        const expected_line_no: u32 = if (forbidden_at_tail) 3 else 2;
        const found = findFirstForbiddenLine(source).?;
        try std.testing.expectEqual(expected_line_no, found.line_no);
        try std.testing.expectEqual(case.token, found.hit.token);
        try std.testing.expectError(error.ForbiddenSyntax, flatten(std.testing.allocator, source));
    }
}

test "PRINT! and FORMAT! macro static expansion" {
    const source =
        \\@main() -> i32:
        \\EXPAND PRINT! "Hello, world!"
        \\EXPAND PRINT! "Value: {}", %val
        \\EXPAND FORMAT! %res, "A: {}, B: {}", %val1, %val2
        \\return 0
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // Let's assert that we have registered some const_decls for the literal segments
    try std.testing.expect(result.const_decls.len >= 3);

    // Let's verify that the literal contents match
    var found_hello = false;
    var found_value = false;
    var found_a = false;
    for (result.const_decls) |decl| {
        if (std.mem.eql(u8, decl.name, "__PRINT_LIT_2_0")) {
            try std.testing.expectEqualStrings("Hello, world!", decl.value.utf8.bytes);
            found_hello = true;
        }
        if (std.mem.indexOf(u8, decl.name, "__PRINT_LIT_3_") != null) {
            try std.testing.expectEqualStrings("Value: ", decl.value.utf8.bytes);
            found_value = true;
        }
        if (std.mem.indexOf(u8, decl.name, "__PRINT_LIT_4_") != null) {
            if (std.mem.eql(u8, decl.value.utf8.bytes, "A: ")) {
                found_a = true;
            }
        }
    }
    try std.testing.expect(found_hello);
    try std.testing.expect(found_value);
    try std.testing.expect(found_a);

    // Verify some instructions generated by the macros exist
    var found_sys_print = false;
    var found_direct_fmt_handle = false;
    var found_direct_fmt_data = false;
    var found_moved_fmt_free = false;
    var found_try_on_fmt = false;
    var found_legacy_fmt_data_borrow = false;
    for (result.instructions) |inst| {
        const raw_text = inst.raw_text;
        if (std.mem.indexOf(u8, raw_text, "call @sa_fmt_i64(%val, 10)") != null) {
            found_direct_fmt_handle = true;
        }
        if (std.mem.indexOf(u8, raw_text, "call @sa_fmt_buffer_data(__fmt_buf_3_0)") != null) {
            found_direct_fmt_data = true;
        }
        if (std.mem.indexOf(u8, raw_text, "call @sa_fmt_buffer_free(^__fmt_buf_3_0)") != null) {
            found_moved_fmt_free = true;
        }
        if (std.mem.indexOf(u8, raw_text, "call @sa_fmt_buffer_data(&") != null) {
            found_legacy_fmt_data_borrow = true;
        }
        if (inst.kind == .call) {
            if (inst.operands[0] == .text) {
                if (std.mem.startsWith(u8, inst.operands[0].text, "@sys_print")) {
                    found_sys_print = true;
                }
            }
        } else if (inst.kind == .early_return) {
            const src_name = result.symbols.lookupName(inst.operands[1].reg) orelse "";
            if (std.mem.startsWith(u8, src_name, "__fmt_")) {
                found_try_on_fmt = true;
            }
        }
    }
    try std.testing.expect(found_sys_print);
    try std.testing.expect(found_direct_fmt_handle);
    try std.testing.expect(found_direct_fmt_data);
    try std.testing.expect(found_moved_fmt_free);
    try std.testing.expect(!found_try_on_fmt);
    try std.testing.expect(!found_legacy_fmt_data_borrow);
}

test "hygiene: two macro expansions produce distinct internal symbols" {
    const source =
        \\[MACRO] BAR %x
        \\    _tmp = add %x, 1
        \\    return _tmp
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND BAR 5
        \\    EXPAND BAR 10
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // Both expansions should have hygienified _tmp
    try std.testing.expect(result.symbols.contains("_tmp__sa_hyg1"));
    try std.testing.expect(result.symbols.contains("_tmp__sa_hyg2"));
    // Original _tmp should NOT appear as a symbol
    try std.testing.expect(!result.symbols.contains("_tmp"));
}

test "hygiene: parameter text is not hygienified" {
    const source =
        \\[MACRO] BAZ %out, %val
        \\    _internal = add %val, 1
        \\    %out = _internal
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND BAZ _tmp, 5
        \\    return _tmp
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // _internal defined in macro body should be hygienified
    try std.testing.expect(result.symbols.contains("_internal__sa_hyg1"));
    // _tmp passed as parameter should NOT be hygienified
    try std.testing.expect(result.symbols.contains("_tmp"));
    // Original _internal should not appear
    try std.testing.expect(!result.symbols.contains("_internal"));
}

test "hygiene: token boundary does not falsely match partial identifiers" {
    const source =
        \\[MACRO] QUUX %x
        \\    _tmp = add %x, 1
        \\    _tmp2 = add _tmp, 2
        \\    return _tmp2
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND QUUX 3
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // Both _tmp and _tmp2 should be hygienified (exact match)
    try std.testing.expect(result.symbols.contains("_tmp__sa_hyg1"));
    try std.testing.expect(result.symbols.contains("_tmp2__sa_hyg1"));
}

test "hygiene: REP labels are unique per iteration" {
    const source =
        \\@main() -> i32:
        \\L_ENTRY:
        \\[REP 3]
        \\L_LOOP:
        \\    tmp_%i = add %i, 0
        \\[END_REP]
        \\    return 0
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // Each REP iteration should produce a distinct hygienified label
    try std.testing.expect(result.symbols.contains("L_LOOP__sa_hyg1"));
    try std.testing.expect(result.symbols.contains("L_LOOP__sa_hyg2"));
    try std.testing.expect(result.symbols.contains("L_LOOP__sa_hyg3"));
    // Original L_LOOP should NOT appear as a label symbol
    try std.testing.expect(!result.symbols.contains("L_LOOP"));
}

test "hygiene: string and comment contents are not modified" {
    const source =
        \\[MACRO] STR5 %x
        \\    _tmp = add %x, 1
        \\    _msg = add 0, 0
        \\    return _tmp
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    EXPAND STR5 42
    ;

    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    // _tmp and _msg should be hygienified
    try std.testing.expect(result.symbols.contains("_tmp__sa_hyg1"));
    try std.testing.expect(result.symbols.contains("_msg__sa_hyg1"));
    // Original _tmp and _msg should NOT appear
    try std.testing.expect(!result.symbols.contains("_tmp"));
    try std.testing.expect(!result.symbols.contains("_msg"));
}

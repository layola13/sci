const std = @import("std");
const upstream = @import("../common/upstream_loc.zig");
const inst = instruction;
const sig = signature;

const Cursor = @import("instruction.zig").Cursor;
const Module = @import("instruction.zig").Module;
const decodeModule = @import("read_const_value.zig").decodeModule;
const decodeSleb128 = @import("instruction.zig").decodeSleb128;
const disasmModule = @import("read_const_value.zig").disasmModule;
const encodeModule = @import("read_const_value.zig").encodeModule;
const encodeProgram = @import("read_const_value.zig").encodeProgram;
const encodeSleb128 = @import("instruction.zig").encodeSleb128;
const instruction = @import("instruction.zig").instruction;
const signature = @import("instruction.zig").signature;

pub fn writeDisasmInstruction(writer: *std.Io.Writer, item: inst.Instruction, symbols: []const []const u8) !void {
    if (item.kind == .call or item.kind == .call_indirect) {
        if (try writeDisasmCallInstruction(writer, item, symbols)) return;
    }

    try writer.print("{s}", .{@tagName(item.kind)});
    if (item.op_kind) |ok| {
        try writer.print(".{s}", .{@tagName(ok)});
    }
    var has_operand = false;
    for (item.operands) |operand| {
        switch (operand) {
            .none => continue,
            else => {},
        }
        if (has_operand) {
            try writer.writeAll(",");
        } else {
            try writer.writeAll(" ");
        }
        has_operand = true;
        try writeDisasmOperand(writer, operand, symbols);
    }
    try writer.writeByte('\n');
}

pub fn splitCallBody(body: []const u8) ?struct { target: []const u8, args: []const u8 } {
    const trimmed = std.mem.trim(u8, body, " \t");
    const open = std.mem.indexOfScalar(u8, trimmed, '(') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, trimmed, ')') orelse return null;
    if (close < open) return null;
    if (std.mem.trim(u8, trimmed[close + 1 ..], " \t").len != 0) return null;
    const target = std.mem.trim(u8, trimmed[0..open], " \t");
    if (target.len == 0) return null;
    return .{ .target = target, .args = std.mem.trim(u8, trimmed[open + 1 .. close], " \t") };
}

pub fn writeDisasmCallInstruction(writer: *std.Io.Writer, item: inst.Instruction, symbols: []const []const u8) !bool {
    const has_dst = item.operands[0] == .reg;
    const body_operand = if (has_dst) item.operands[1] else item.operands[0];
    const body = switch (body_operand) {
        .text => |text| text,
        else => return false,
    };
    const split = splitCallBody(body) orelse return false;

    try writer.print("{s}", .{@tagName(item.kind)});
    if (has_dst) {
        try writer.writeByte(' ');
        try writeDisasmOperand(writer, item.operands[0], symbols);
        try writer.writeByte(',');
    } else {
        try writer.writeByte(' ');
    }
    try writer.print("\"{s}\",\"{s}\"\n", .{ split.target, split.args });
    return true;
}

pub fn writeDisasmOperand(writer: *std.Io.Writer, operand: inst.Operand, symbols: []const []const u8) !void {
    switch (operand) {
        .none => {},
        .reg => |v| try writer.print("r{d}", .{v}),
        .symbol => |v| {
            if (v < symbols.len) {
                try writer.print("${s}", .{symbols[v]});
            } else {
                try writer.print("sym:{d}", .{v});
            }
        },
        .label => |v| try writer.print("L{d}", .{v}),
        .func => |v| try writer.print("fn:{d}", .{v}),
        .imm_i64 => |v| try writer.print("{d}", .{v}),
        .imm_u64 => |v| try writer.print("{d}u", .{v}),
        .imm_int => |v| try writer.print("{d}", .{v}),
        .imm_float => |v| try writer.print("{d}", .{v}),
        .op_code => |v| try writer.print("op:{s}", .{@tagName(v)}),
        .cap_prefix => |v| try writer.print("cap:{s}", .{@tagName(v)}),
        .offset => |v| try writer.print("+{d}", .{v}),
        .ty => |v| try writer.print("ty:{d}", .{v}),
        .text => |v| try writer.print("\"{s}\"", .{v}),
        .native_text => |v| try writer.print("native:\"{s}\"", .{v}),
    }
}

test "sleb128 roundtrip" {
    const values = [_]i64{ -129, -1, 0, 1, 127, 128, 4096 };
    for (values) |value| {
        var buf: std.Io.Writer.Allocating = .init(std.testing.allocator);
        defer buf.deinit();
        try encodeSleb128(&buf.writer, value);
        var cursor = Cursor{ .bytes = buf.writer.buffered() };
        try std.testing.expectEqual(value, try decodeSleb128(&cursor));
    }
}

test "sab instruction roundtrip keeps semantics without raw source text" {
    const symbols = [_][]const u8{ "main", "value" };
    var item = inst.makeInstruction(.assign, 2, 0, null, "value = 7");
    item.operands[0] = .{ .reg = 1 };
    item.operands[1] = .{ .imm_i64 = 7 };

    const encoded = try encodeModule(std.testing.allocator, symbols[0..], &.{item});
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "value = 7") == null);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.instructions.len);
    try std.testing.expectEqual(inst.InstKind.assign, decoded.instructions[0].kind);
    try std.testing.expectEqual(@as(u32, 1), decoded.instructions[0].operands[0].reg);
    try std.testing.expectEqual(@as(i64, 7), decoded.instructions[0].operands[1].imm_i64);
    try std.testing.expectEqualStrings("", decoded.instructions[0].raw_text);
}

test "sab text operands roundtrip without raw source text" {
    var item = inst.makeInstruction(.panic, 3, 0, null, "panic(7)");
    item.operands[0] = .{ .text = "7" };

    const encoded = try encodeModule(std.testing.allocator, &.{}, &.{item});
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "panic(7)") == null);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "7") != null);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(inst.InstKind.panic, decoded.instructions[0].kind);
    try std.testing.expectEqualStrings("7", decoded.instructions[0].operands[0].text);
    try std.testing.expectEqualStrings("", decoded.instructions[0].raw_text);
}

test "sab borrow roundtrip preserves structured operands" {
    const symbols = [_][]const u8{ "GLOBAL", "view" };
    var item = inst.makeInstruction(.borrow, 4, 0, null, "view = &GLOBAL");
    item.operands[0] = .{ .reg = 1 };
    item.operands[1] = .{ .reg = 0 };
    item.operands[2] = .{ .text = "read" };
    item.operands[3] = .{ .cap_prefix = .borrow };

    const encoded = try encodeModule(std.testing.allocator, symbols[0..], &.{item});
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(inst.InstKind.borrow, decoded.instructions[0].kind);
    try std.testing.expectEqual(@as(u32, 1), decoded.instructions[0].operands[0].reg);
    try std.testing.expectEqual(@as(u32, 0), decoded.instructions[0].operands[1].reg);
    try std.testing.expectEqualStrings("read", decoded.instructions[0].operands[2].text);
    try std.testing.expectEqualStrings("", decoded.instructions[0].raw_text);
}

test "sab roundtrip preserves expanded_line from SA-text" {
    // SA-text 为语义标准：解码不得以指令序号覆盖 expanded_line（宏展开行号），
    // 否则 Referee 诊断行号/const 交错与文本路径分歧。
    const symbols = [_][]const u8{ "a", "b", "c" };
    var items = [_]inst.Instruction{
        inst.makeInstruction(.assign, 5, 10, null, ""),
        inst.makeInstruction(.assign, 9, 42, null, ""),
        inst.makeInstruction(.assign, 30, 7, null, ""),
        // 边界：expanded_line = 0 必须原样保留（旧逻辑会写成指令序号 3）。
        inst.makeInstruction(.assign, 100, 0, null, ""),
    };
    items[0].operands[0] = .{ .reg = 0 };
    items[0].operands[1] = .{ .imm_i64 = 1 };
    items[1].operands[0] = .{ .reg = 1 };
    items[1].operands[1] = .{ .imm_i64 = 2 };
    items[2].operands[0] = .{ .reg = 2 };
    items[2].operands[1] = .{ .imm_i64 = 3 };
    items[3].operands[0] = .{ .reg = 0 };
    items[3].operands[1] = .{ .imm_i64 = 4 };

    const encoded = try encodeModule(std.testing.allocator, symbols[0..], items[0..]);
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 4), decoded.instructions.len);
    try std.testing.expectEqual(@as(u32, 5), decoded.instructions[0].source_line);
    try std.testing.expectEqual(@as(u32, 10), decoded.instructions[0].expanded_line);
    try std.testing.expectEqual(@as(u32, 9), decoded.instructions[1].source_line);
    try std.testing.expectEqual(@as(u32, 42), decoded.instructions[1].expanded_line);
    try std.testing.expectEqual(@as(u32, 30), decoded.instructions[2].source_line);
    try std.testing.expectEqual(@as(u32, 7), decoded.instructions[2].expanded_line);
    try std.testing.expectEqual(@as(u32, 100), decoded.instructions[3].source_line);
    try std.testing.expectEqual(@as(u32, 0), decoded.instructions[3].expanded_line);
}

pub fn decodedOwnsPooledText(module: *const Module, text: []const u8) bool {
    for (module.owned_text) |owned| {
        if (owned.ptr == text.ptr) return true;
    }
    return false;
}

pub fn expectOperandEqual(expected: inst.Operand, got: inst.Operand) !void {
    try std.testing.expectEqual(std.meta.activeTag(expected), std.meta.activeTag(got));
    switch (expected) {
        .none => {},
        .reg => |value| try std.testing.expectEqual(value, got.reg),
        .symbol => |value| try std.testing.expectEqual(value, got.symbol),
        .label => |value| try std.testing.expectEqual(value, got.label),
        .func => |value| try std.testing.expectEqual(value, got.func),
        .imm_i64 => |value| try std.testing.expectEqual(value, got.imm_i64),
        .imm_u64 => |value| try std.testing.expectEqual(value, got.imm_u64),
        .imm_int => |value| try std.testing.expectEqual(value, got.imm_int),
        .imm_float => |value| try std.testing.expectEqual(@as(u64, @bitCast(value)), @as(u64, @bitCast(got.imm_float))),
        .op_code => |value| try std.testing.expectEqual(value, got.op_code),
        .cap_prefix => |value| try std.testing.expectEqual(value, got.cap_prefix),
        .offset => |value| try std.testing.expectEqual(value, got.offset),
        .ty => |value| try std.testing.expectEqual(value, got.ty),
        .text => |value| try std.testing.expectEqualStrings(value, got.text),
        .native_text => |value| try std.testing.expectEqualStrings(value, got.native_text),
    }
}

test "sab v4 preserves structured instruction metadata required by SA backends" {
    const symbols = [_][]const u8{ "ok", "slot", "base", "offset", "old", "new", "pkg", "pkg/main.sa", "native_name" };
    var hash: [32]u8 = std.mem.zeroes([32]u8);
    hash[0] = 0xaa;

    var item = inst.makeInstruction(.cmpxchg, 9, 0, .{ .file = "pkg/main.sa", .line = 9, .col = 5 }, "ok, old = cmpxchg base+offset, old => new seq_cst seq_cst as i64");
    item.operands[0] = .{ .reg = 0 };
    item.operands[1] = .{ .reg = 1 };
    item.operands[2] = .{ .reg = 2 };
    item.operands[3] = .{ .reg = 3 };
    item.atomic_value_ty = @intFromEnum(sig.PrimType.i64);
    item.atomic_ordering = .seq_cst;
    item.atomic_second_ordering = .seq_cst;
    item.atomic_expected_text = "old";
    item.atomic_new_text = "new";
    item.native_reg_names = &.{"native_name"};
    item.package_identity = "pkg";
    item.package_source_sha256 = hash;

    const encoded = try encodeModule(std.testing.allocator, symbols[0..], &.{item});
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    const got = decoded.instructions[0];
    try std.testing.expectEqual(inst.InstKind.cmpxchg, got.kind);
    try std.testing.expectEqualStrings("old", got.atomic_expected_text.?);
    try std.testing.expectEqualStrings("new", got.atomic_new_text.?);
    try std.testing.expectEqual(@as(usize, 1), got.native_reg_names.len);
    try std.testing.expectEqualStrings("native_name", got.native_reg_names[0]);
    try std.testing.expectEqualStrings("pkg", got.package_identity.?);
    try std.testing.expectEqual(@as(u8, 0xaa), got.package_source_sha256.?[0]);
    try std.testing.expectEqualStrings("pkg/main.sa", got.upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 9), got.upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 5), got.upstream_loc.?.col);
    try std.testing.expectEqualStrings("", got.raw_text);
    try std.testing.expect(!decodedOwnsPooledText(&decoded, got.package_identity.?));
    try std.testing.expect(!decodedOwnsPooledText(&decoded, got.upstream_loc.?.file));
}

test "sab roundtrip covers every SA instruction and op kind" {
    var instructions = std.array_list.Managed(inst.Instruction).init(std.testing.allocator);
    defer instructions.deinit();

    inline for (std.meta.tags(inst.InstKind).*) |kind| {
        var item = inst.makeInstruction(kind, 10, @intCast(instructions.items.len), null, @tagName(kind));
        item.operands[0] = .{ .reg = 0 };
        item.operands[1] = .{ .symbol = 1 };
        item.operands[2] = .{ .label = 2 };
        item.operands[3] = if (kind == .native) .{ .native_text = "mov native" } else .{ .text = @tagName(kind) };
        try instructions.append(item);
    }

    inline for (std.meta.tags(inst.OpKind).*) |op_kind| {
        var item = inst.makeInstruction(.op, 20, @intCast(instructions.items.len), null, @tagName(op_kind));
        item.op_kind = op_kind;
        item.operands[0] = .{ .reg = 0 };
        item.operands[1] = .{ .reg = 1 };
        item.operands[2] = .{ .reg = 2 };
        try instructions.append(item);
    }

    const encoded = try encodeModule(std.testing.allocator, &.{ "r0", "sym", "label" }, instructions.items);
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(instructions.items.len, decoded.instructions.len);
    for (instructions.items, decoded.instructions) |expected, got| {
        try std.testing.expectEqual(expected.kind, got.kind);
        try std.testing.expectEqual(expected.op_kind, got.op_kind);
        try std.testing.expectEqualStrings("", got.raw_text);
    }
}

test "sab roundtrip covers every SA operand kind" {
    var instructions = std.array_list.Managed(inst.Instruction).init(std.testing.allocator);
    defer instructions.deinit();

    const samples = [_]inst.Operand{
        .{ .none = {} },
        .{ .reg = 0 },
        .{ .symbol = 1 },
        .{ .label = 2 },
        .{ .func = 3 },
        .{ .imm_i64 = -42 },
        .{ .imm_u64 = 42 },
        .{ .imm_int = -7 },
        .{ .imm_float = 3.5 },
        .{ .op_code = .add },
        .{ .cap_prefix = .borrow },
        .{ .offset = 99 },
        .{ .ty = 4 },
        .{ .text = "plain operand text" },
        .{ .native_text = "mov %rax, %rbx" },
    };

    for (samples, 0..) |operand, idx| {
        var item = inst.makeInstruction(.assign, 30, @intCast(idx), null, "operand sample");
        item.operands[0] = operand;
        try instructions.append(item);
    }

    inline for (std.meta.tags(inst.OpCode).*) |value| {
        var item = inst.makeInstruction(.op, 40, @intCast(instructions.items.len), null, @tagName(value));
        item.operands[0] = .{ .op_code = value };
        try instructions.append(item);
    }

    inline for (std.meta.tags(inst.CapPrefix).*) |value| {
        var item = inst.makeInstruction(.borrow, 50, @intCast(instructions.items.len), null, @tagName(value));
        item.operands[0] = .{ .cap_prefix = value };
        try instructions.append(item);
    }

    const encoded = try encodeModule(std.testing.allocator, &.{ "r0", "sym", "label", "fn", "ty" }, instructions.items);
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(instructions.items.len, decoded.instructions.len);
    for (instructions.items, decoded.instructions) |expected, got| {
        try expectOperandEqual(expected.operands[0], got.operands[0]);
    }
}

test "sab parenthesized panic operand stays structured" {
    var item = inst.makeInstruction(.panic, 3, 0, null, "");
    item.operands[0] = .{ .text = "(1701)" };

    const encoded = try encodeModule(std.testing.allocator, &.{}, &.{item});
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(inst.InstKind.panic, decoded.instructions[0].kind);
    try std.testing.expectEqualStrings("(1701)", decoded.instructions[0].operands[0].text);
    try std.testing.expectEqualStrings("", decoded.instructions[0].raw_text);
}

test "sab no-destination call stays structured" {
    var item = inst.makeInstruction(.call, 3, 0, null, "");
    item.operands[0] = .{ .text = "@sink(value)" };

    const encoded = try encodeModule(std.testing.allocator, &.{}, &.{item});
    defer std.testing.allocator.free(encoded);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(inst.InstKind.call, decoded.instructions[0].kind);
    try std.testing.expectEqualStrings("@sink(value)", decoded.instructions[0].operands[0].text);
    try std.testing.expectEqualStrings("", decoded.instructions[0].raw_text);
}

test "sab function signatures roundtrip without function header text" {
    const params = try std.testing.allocator.alloc(sig.ParamSpec, 1);
    defer std.testing.allocator.free(params);
    params[0] = .{ .name = "argc", .ty = .i32, .cap = .by_value };
    const param_ids = [_]u32{1};
    const reg_ids = [_]u32{1};
    const fsig = sig.FunctionSig{
        .id = 0,
        .name = "main",
        .params = params,
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .upstream_file = "src/main.sa",
        .upstream_loc = .{ .file = "src/main.sa", .line = 11, .col = 2 },
        .param_ids = param_ids[0..],
        .reg_ids = reg_ids[0..],
        .llvm_name = "saasm_main",
    };

    const encoded = try encodeProgram(std.testing.allocator, &.{}, &.{fsig}, &.{});
    defer std.testing.allocator.free(encoded);
    try std.testing.expect(std.mem.indexOf(u8, encoded, "@main") == null);

    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), decoded.function_sigs.len);
    try std.testing.expectEqualStrings("main", decoded.function_sigs[0].name);
    try std.testing.expectEqual(sig.PrimType.i32, decoded.function_sigs[0].return_ty);
    try std.testing.expectEqualStrings("argc", decoded.function_sigs[0].params[0].name);
    try std.testing.expectEqualStrings("src/main.sa", decoded.function_sigs[0].upstream_file.?);
    try std.testing.expectEqualStrings("src/main.sa", decoded.function_sigs[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 11), decoded.function_sigs[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 2), decoded.function_sigs[0].upstream_loc.?.col);
    try std.testing.expectEqualStrings("saasm_main", decoded.function_sigs[0].llvm_name.?);
}

test "disasmModule produces readable text from binary SAB" {
    const reg_ids = [_]u32{1};
    const fsig_val = sig.FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = inst.makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = inst.makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 42 };
    var ret = inst.makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };

    const encoded = try encodeProgram(std.testing.allocator, &.{ "main", "value" }, &.{fsig_val}, &.{ decl, assign, ret });
    defer std.testing.allocator.free(encoded);

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try disasmModule(std.testing.allocator, encoded, &output.writer);

    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "func_decl") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "assign") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "return_") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "@main") != null);
}

test "disasmModule separates call target from call args" {
    const reg_ids = [_]u32{1};
    const fsig_val = sig.FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = inst.makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var call_item = inst.makeInstruction(.call, 2, 1, null, "");
    call_item.operands[0] = .{ .reg = 1 };
    call_item.operands[1] = .{ .text = "@sink(&arg, value)" };

    const encoded = try encodeProgram(std.testing.allocator, &.{ "main", "out" }, &.{fsig_val}, &.{ decl, call_item });
    defer std.testing.allocator.free(encoded);

    var output: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer output.deinit();
    try disasmModule(std.testing.allocator, encoded, &output.writer);

    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "call r1,\"@sink\",\"&arg, value\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.writer.buffered(), "@sink(") == null);
}

test "decoded sab verifies through predecoded metadata without text parser" {
    const reg_ids = [_]u32{1};
    const fsig = sig.FunctionSig{
        .id = 0,
        .name = "main",
        .params = &.{},
        .kind = .normal,
        .return_cap = null,
        .return_ty = .i32,
        .entry_inst_idx = 0,
        .is_ffi_wrapper = false,
        .reg_ids = reg_ids[0..],
    };
    var decl = inst.makeInstruction(.func_decl, 1, 0, null, "");
    decl.operands[0] = .{ .symbol = 0 };
    decl.operands[1] = .{ .func = 0 };
    var assign = inst.makeInstruction(.assign, 2, 1, null, "");
    assign.operands[0] = .{ .reg = 1 };
    assign.operands[1] = .{ .imm_i64 = 7 };
    var ret = inst.makeInstruction(.return_, 3, 2, null, "");
    ret.operands[0] = .{ .reg = 1 };

    const encoded = try encodeProgram(std.testing.allocator, &.{ "main", "value" }, &.{fsig}, &.{ decl, assign, ret });
    defer std.testing.allocator.free(encoded);
    var decoded = try decodeModule(std.testing.allocator, encoded);
    defer decoded.deinit(std.testing.allocator);

    const verifier = @import("../verifier.zig");
    const verified = try verifier.verifyWithOptions(std.testing.allocator, decoded.instructions, &.{}, .{
        .predecoded_symbol_names = decoded.symbols,
        .predecoded_function_sigs = decoded.function_sigs,
    });
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

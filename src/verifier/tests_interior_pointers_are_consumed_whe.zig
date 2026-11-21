const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const call = @import("../referee/call.zig");
const cap = @import("../common/capability.zig");
const atomic = @import("../common/atomic.zig");
const gas = @import("../common/gas.zig");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const upstream = @import("../common/upstream_loc.zig");
const classifier = @import("../flattener/line_classifier.zig");
const symbol = @import("../flattener/symbol.zig");

const maskOf = @import("reg_state_change.zig").maskOf;
const verify = @import("free_annotated_slice.zig").verify;
const verifyWithOptions = @import("free_annotated_slice.zig").verifyWithOptions;

test "interior pointers are consumed when their parent borrow is released" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "base = alloc 8",
        },
        .{
            .kind = .borrow,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .reg = 2 },
                .{ .text = "read" },
                .{ .reg = 1 },
                .{ .none = {} },
            },
            .raw_text = "view = & base",
        },
        .{
            .kind = .take,
            .source_line = 4,
            .expanded_line = 3,
            .operands = .{
                .{ .reg = 3 },
                .{ .reg = 2 },
                .{ .imm_u64 = 4 },
                .{ .none = {} },
            },
            .raw_text = "ip = take view+4",
        },
        .{
            .kind = .release,
            .source_line = 5,
            .expanded_line = 4,
            .operands = .{
                .{ .reg = 2 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "!view",
        },
        .{
            .kind = .return_,
            .source_line = 6,
            .expanded_line = 5,
            .operands = .{
                .{ .reg = 1 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return base",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 6), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "interior pointers trap when passed to extern calls" {
    const source =
        \\@ffi_wrapper sink(*p: ptr) -> i32:
        \\return 0
        \\@ffi_wrapper wrap() -> i32:
        \\base = alloc 8
        \\view = & base
        \\ip = take view+4
        \\call @sink(*ip)
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| {
            try std.testing.expectEqual(trap.Trap.interior_ptr_escape, report.trap);
        },
        .ok => return error.TestUnexpectedResult,
    }
}

test "borrowed views can upgrade to mutable write when unique" {
    const source =
        \\@main() -> i32:
        \\base = alloc 8
        \\view = & base
        \\store view+0, 7 as i8
        \\!view
        \\!base
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 7), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "borrowed parameters can be written through when unique" {
    const source =
        \\@bump(&box: ptr) -> void:
        \\value = load box+0 as i32
        \\next = add value, 1
        \\store box+0, next as i32
        \\!value
        \\!next
        \\!box
        \\return
        \\@main() -> i32:
        \\box = alloc 4
        \\store box+0, 9 as i32
        \\call @bump(&box)
        \\value = load box+0 as i32
        \\!value
        \\!box
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s}\n", .{ @tagName(report.trap), report.message });
            return error.TestUnexpectedResult;
        },
    }
}

test "borrowed parameters can be released without origin index overflow" {
    const source =
        \\@bump(&box: ptr) -> void:
        \\!box
        \\return
        \\@main() -> i32:
        \\box = alloc 4
        \\call @bump(&box)
        \\!box
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("trap={s} msg={s}\n", .{ @tagName(report.trap), report.message });
            return error.TestUnexpectedResult;
        },
    }
}

test "borrowed views trap on write when shared" {
    const source =
        \\@main() -> i32:
        \\base = alloc 8
        \\view_a = & base
        \\view_b = & base
        \\store view_a+0, 7 as i8
        \\!view_a
        \\!view_b
        \\!base
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.read_write_conflict, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "borrow view of stack_alloc traps on return escape" {
    const source =
        \\@helper() -> &ptr:
        \\tmp = stack_alloc 8
        \\view = & tmp
        \\return view
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.stack_escape, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "borrow view of stack_alloc traps on move escape" {
    const source =
        \\@extern sink(^owned: ptr) -> i32
        \\@main() -> i32:
        \\tmp = stack_alloc 8
        \\view = & tmp
        \\value = call @sink(^view)
        \\!view
        \\!tmp
        \\return value
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.stack_escape, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

pub fn fieldBorrowInstruction(kind: inst.InstKind, source_line: u32, expanded_line: u32, raw_text: []const u8, operands: [4]inst.Operand) inst.Instruction {
    var item = inst.makeInstruction(kind, source_line, expanded_line, null, raw_text);
    item.operands = operands;
    return item;
}

test "borrowed views trap when escaping across ffi boundary" {
    const source =
        \\@ffi_wrapper sink(*p: ptr) -> i32:
        \\return 0
        \\@ffi_wrapper wrap() -> i32:
        \\base = alloc 8
        \\view = & base
        \\ip = take view+0
        \\call @sink(*ip)
        \\!view
        \\!base
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.interior_ptr_escape, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "borrowed views trap when source is released while borrowed" {
    const source =
        \\@main() -> i32:
        \\base = alloc 8
        \\view = & base
        \\!base
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.borrow_conflict, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "field-level mutable borrows allow distinct static offsets" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 16", .{ .{ .reg = 1 }, .{ .imm_u64 = 16 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 3, 2, "field_a = ptr_add base, 0", .{ .{ .reg = 2 }, .{ .reg = 1 }, .{ .imm_i64 = 0 }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 4, 3, "field_b = ptr_add base, 8", .{ .{ .reg = 3 }, .{ .reg = 1 }, .{ .imm_i64 = 8 }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 5, 4, "view_a = borrow mut field_a", .{ .{ .reg = 4 }, .{ .text = "mut" }, .{ .reg = 2 }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 6, 5, "view_b = borrow mut field_b", .{ .{ .reg = 5 }, .{ .text = "mut" }, .{ .reg = 3 }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 7, 6, "!view_b", .{ .{ .reg = 5 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 8, 7, "!view_a", .{ .{ .reg = 4 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 9, 8, "!field_b", .{ .{ .reg = 3 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 10, 9, "!field_a", .{ .{ .reg = 2 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 11, 10, "!base", .{ .{ .reg = 1 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.return_, 12, 11, "return 0", .{ .{ .imm_i64 = 0 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "field-level mutable borrows reject identical static offsets" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 16", .{ .{ .reg = 1 }, .{ .imm_u64 = 16 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 3, 2, "field_a = ptr_add base, 0", .{ .{ .reg = 2 }, .{ .reg = 1 }, .{ .imm_i64 = 0 }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 4, 3, "field_b = ptr_add base, 0", .{ .{ .reg = 3 }, .{ .reg = 1 }, .{ .imm_i64 = 0 }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 5, 4, "view_a = borrow mut field_a", .{ .{ .reg = 4 }, .{ .text = "mut" }, .{ .reg = 2 }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 6, 5, "view_b = borrow mut field_b", .{ .{ .reg = 5 }, .{ .text = "mut" }, .{ .reg = 3 }, .{ .none = {} } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.read_write_conflict, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "ptr_add beyond allocation size traps borrow_conflict" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 8", .{ .{ .reg = 1 }, .{ .imm_u64 = 8 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 3, 2, "far = ptr_add base, 8", .{ .{ .reg = 2 }, .{ .reg = 1 }, .{ .imm_i64 = 8 }, .{ .none = {} } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.borrow_conflict, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "borrow view ptr_add beyond allocation size traps borrow_conflict" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 8", .{ .{ .reg = 1 }, .{ .imm_u64 = 8 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 3, 2, "view = borrow base", .{ .{ .reg = 2 }, .{ .text = "read" }, .{ .reg = 1 }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 4, 3, "far = ptr_add view, 8", .{ .{ .reg = 3 }, .{ .reg = 2 }, .{ .imm_i64 = 8 }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 5, 4, "!view", .{ .{ .reg = 2 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 6, 5, "!far", .{ .{ .reg = 3 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 7, 6, "!base", .{ .{ .reg = 1 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.return_, 8, 7, "return 0", .{ .{ .imm_i64 = 0 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.borrow_conflict, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "load with offset beyond allocation size traps borrow_conflict" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 8", .{ .{ .reg = 1 }, .{ .imm_u64 = 8 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.load, 3, 2, "v = load base+8 as u64", .{ .{ .reg = 2 }, .{ .reg = 1 }, .{ .imm_u64 = 8 }, .{ .ty = @intFromEnum(sig.PrimType.u64) } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.borrow_conflict, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "in-bounds borrow view offsets still verify" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 16", .{ .{ .reg = 1 }, .{ .imm_u64 = 16 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 3, 2, "view = borrow base", .{ .{ .reg = 2 }, .{ .text = "read" }, .{ .reg = 1 }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 4, 3, "field = ptr_add view, 8", .{ .{ .reg = 3 }, .{ .reg = 2 }, .{ .imm_i64 = 8 }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 5, 4, "!field", .{ .{ .reg = 3 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 6, 5, "!view", .{ .{ .reg = 2 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.release, 7, 6, "!base", .{ .{ .reg = 1 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.return_, 8, 7, "return 0", .{ .{ .imm_i64 = 0 }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "whole-object mutable borrow rejects active field borrow" {
    const program = [_]inst.Instruction{
        fieldBorrowInstruction(.func_decl, 1, 0, "@main() -> i32:", .{ .{ .symbol = 0 }, .{ .func = 0 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.alloc, 2, 1, "base = alloc 16", .{ .{ .reg = 1 }, .{ .imm_u64 = 16 }, .{ .none = {} }, .{ .none = {} } }),
        fieldBorrowInstruction(.ptr_add, 3, 2, "field_a = ptr_add base, 0", .{ .{ .reg = 2 }, .{ .reg = 1 }, .{ .imm_i64 = 0 }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 4, 3, "view_a = borrow mut field_a", .{ .{ .reg = 3 }, .{ .text = "mut" }, .{ .reg = 2 }, .{ .none = {} } }),
        fieldBorrowInstruction(.borrow, 5, 4, "view_base = borrow mut base", .{ .{ .reg = 4 }, .{ .text = "mut" }, .{ .reg = 1 }, .{ .none = {} } }),
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.read_write_conflict, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "sax verifier hook maps state writes outside ffi wrappers to sax trap" {
    const source =
        \\@main() -> i32:
        \\state = alloc 8
        \\store state+0, 1 as i64
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .sax_context = .{ .component_name = "App" } });
    switch (verified) {
        .trap => |report| {
            try std.testing.expectEqual(trap.Trap.sax_state_write_from_outside, report.trap);
            try std.testing.expectEqualStrings("App", std.mem.sliceTo(&report.function_buf, 0));
        },
        .ok => return error.TestUnexpectedResult,
    }
}

test "sax verifier hook maps render outside ffi wrappers to sax trap" {
    const source =
        \\@main() -> i32:
        \\call @render()
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .sax_context = .{ .component_name = "App" } });
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.sax_render_outside_handler, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "mutable borrow of the same source after shared borrow traps borrow conflict" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "base = alloc 8",
        },
        .{
            .kind = .borrow,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .reg = 2 },
                .{ .text = "read" },
                .{ .reg = 1 },
                .{ .none = {} },
            },
            .raw_text = "view_a = & base",
        },
        .{
            .kind = .borrow,
            .source_line = 4,
            .expanded_line = 3,
            .operands = .{
                .{ .reg = 3 },
                .{ .text = "mut" },
                .{ .reg = 1 },
                .{ .none = {} },
            },
            .raw_text = "view_b = borrow mut base",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..], &.{});
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.read_write_conflict, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "assume_borrow marks ffi borrow state and release clears it without freeing" {
    const source =
        \\@ffi_wrapper wrap(*raw: ptr) -> i32:
        \\view = assume_borrow raw
        \\!view
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            var saw_assume = false;
            var saw_release = false;
            for (owned.annotated) |item| {
                if (item.base.kind == .assume_borrow) {
                    saw_assume = true;
                    var found = false;
                    for (item.delta.changes) |change| {
                        if (change.reg == item.base.operands[0].reg) {
                            found = true;
                            try std.testing.expect((change.after & maskOf(.ffi_borrow)) != 0);
                            try std.testing.expect((change.after & maskOf(.borrow_view)) != 0);
                            break;
                        }
                    }
                    try std.testing.expect(found);
                } else if (item.base.kind == .release) {
                    saw_release = true;
                    var found = false;
                    for (item.delta.changes) |change| {
                        if (change.reg == item.base.operands[0].reg) {
                            found = true;
                            try std.testing.expectEqual(@as(u16, 0), change.after);
                            break;
                        }
                    }
                    try std.testing.expect(found);
                }
            }
            try std.testing.expect(saw_assume);
            try std.testing.expect(saw_release);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

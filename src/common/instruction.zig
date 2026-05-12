const std = @import("std");
const atomic = @import("atomic.zig");
const upstream = @import("upstream_loc.zig");

pub const CapPrefix = enum(u8) {
    by_value = 0,
    borrow = 1,
    move = 2,
    raw = 3,
};

pub const OpCode = enum(u8) {
    add,
    sub,
    mul,
    div,
    gt,
    lt,
    eq,
    ne,
    @"and",
    @"or",
    shl,
    shr,
};

pub const AtomicOrdering = atomic.AtomicOrdering;
pub const AtomicRmwOp = atomic.AtomicRmwOp;

pub const Operand = union(enum) {
    none: void,
    reg: u32,
    symbol: u32,
    label: u32,
    func: u32,
    imm_i64: i64,
    imm_u64: u64,
    imm_int: i64,
    imm_float: f64,
    op_code: OpCode,
    cap_prefix: CapPrefix,
    offset: u32,
    ty: u32,
    text: []const u8,
    native_text: []const u8,
};

pub const InstKind = enum(u8) {
    alloc,
    stack_alloc,
    load,
    store,
    atomic_load,
    atomic_store,
    cmpxchg,
    atomic_rmw,
    fence,
    borrow,
    move_,
    release,
    op,
    ptr_add,
    jmp,
    br,
    br_null,
    call,
    call_indirect,
    try_,
    early_return,
    panic,
    panic_msg,
    return_,
    take,
    func_decl,
    ffi_wrapper_decl,
    extern_decl,
    export_decl,
    label,
    raw_cast,
    assume_safe,
    assume_borrow,
    native,
};

pub const Instruction = struct {
    kind: InstKind,
    source_line: u32,
    expanded_line: u32,
    upstream_loc: ?upstream.UpstreamLoc = null,
    operands: [4]Operand,
    raw_text: []const u8,
    atomic_value_ty: ?u32 = null,
    atomic_ordering: ?AtomicOrdering = null,
    atomic_second_ordering: ?AtomicOrdering = null,
    atomic_rmw_op: ?AtomicRmwOp = null,
    atomic_expected_text: ?[]const u8 = null,
    atomic_new_text: ?[]const u8 = null,
};

pub fn makeInstruction(kind: InstKind, source_line: u32, expanded_line: u32, upstream_loc: ?upstream.UpstreamLoc, raw_text: []const u8) Instruction {
    return .{
        .kind = kind,
        .source_line = source_line,
        .expanded_line = expanded_line,
        .upstream_loc = upstream_loc,
        .operands = .{ operandNone(), operandNone(), operandNone(), operandNone() },
        .raw_text = raw_text,
        .atomic_value_ty = null,
        .atomic_ordering = null,
        .atomic_second_ordering = null,
        .atomic_rmw_op = null,
        .atomic_expected_text = null,
        .atomic_new_text = null,
    };
}

pub fn operandNone() Operand {
    return .{ .none = {} };
}

test "instruction layout keeps four operands and tags" {
    const inst = makeInstruction(.alloc, 7, 11, null, "x = alloc 8");
    try std.testing.expectEqual(@as(u32, 7), inst.source_line);
    try std.testing.expectEqual(@as(u32, 11), inst.expanded_line);
    try std.testing.expect(inst.upstream_loc == null);
    try std.testing.expectEqual(@as(usize, 4), inst.operands.len);
    try std.testing.expectEqual(InstKind.alloc, inst.kind);
    try std.testing.expect(std.mem.eql(u8, inst.raw_text, "x = alloc 8"));
}

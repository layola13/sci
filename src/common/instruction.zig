const std = @import("std");
const atomic = @import("atomic.zig");
const const_decl = @import("const_decl.zig");
const upstream = @import("upstream_loc.zig");

pub const CapPrefix = enum(u8) {
    by_value = 0,
    borrow = 1,
    move = 2,
    raw = 3,
};

pub const OpKind = enum(u8) {
    // Integer arithmetic
    add,
    sub,
    mul,
    sdiv,
    udiv,
    srem,
    urem,
    neg,

    // Bitwise
    @"and",
    @"or",
    xor,
    shl,
    lshr,
    ashr,
    not,

    // Integer comparison
    eq,
    ne,
    slt,
    sle,
    sgt,
    sge,
    ult,
    ule,
    ugt,
    uge,

    // Compatibility aliases kept for existing demos and tests.
    div,
    rem,
    gt,
    lt,
    shr,

    // Floating-point arithmetic
    fadd,
    fsub,
    fmul,
    fdiv,
    fneg,

    // Floating-point comparison
    fcmp_eq,
    fcmp_ne,
    fcmp_lt,
    fcmp_le,
    fcmp_gt,
    fcmp_ge,

    // Type conversion
    trunc,
    zext,
    sext,
    fptosi,
    sitofp,
    uitofp,
    fptrunc,
    fpext,
    bitcast,

    // SIMD minimum set
    add_v128,
    sub_v128,
    mul_v128,
    shuffle_v128,
    extract_lane,
    insert_lane,
};

const op_kind_by_name = std.StaticStringMap(OpKind).initComptime(.{
    .{ "add", .add },
    .{ "sub", .sub },
    .{ "mul", .mul },
    .{ "sdiv", .sdiv },
    .{ "udiv", .udiv },
    .{ "srem", .srem },
    .{ "urem", .urem },
    .{ "neg", .neg },
    .{ "and", .@"and" },
    .{ "or", .@"or" },
    .{ "xor", .xor },
    .{ "shl", .shl },
    .{ "lshr", .lshr },
    .{ "ashr", .ashr },
    .{ "not", .not },
    .{ "eq", .eq },
    .{ "ne", .ne },
    .{ "slt", .slt },
    .{ "sle", .sle },
    .{ "sgt", .sgt },
    .{ "sge", .sge },
    .{ "ult", .ult },
    .{ "ule", .ule },
    .{ "ugt", .ugt },
    .{ "uge", .uge },
    .{ "div", .div },
    .{ "rem", .rem },
    .{ "gt", .gt },
    .{ "lt", .lt },
    .{ "shr", .shr },
    .{ "fadd", .fadd },
    .{ "fsub", .fsub },
    .{ "fmul", .fmul },
    .{ "fdiv", .fdiv },
    .{ "fneg", .fneg },
    .{ "fcmp_eq", .fcmp_eq },
    .{ "fcmp_ne", .fcmp_ne },
    .{ "fcmp_lt", .fcmp_lt },
    .{ "fcmp_le", .fcmp_le },
    .{ "fcmp_gt", .fcmp_gt },
    .{ "fcmp_ge", .fcmp_ge },
    .{ "trunc", .trunc },
    .{ "zext", .zext },
    .{ "sext", .sext },
    .{ "fptosi", .fptosi },
    .{ "sitofp", .sitofp },
    .{ "uitofp", .uitofp },
    .{ "fptrunc", .fptrunc },
    .{ "fpext", .fpext },
    .{ "bitcast", .bitcast },
    .{ "add_v128", .add_v128 },
    .{ "sub_v128", .sub_v128 },
    .{ "mul_v128", .mul_v128 },
    .{ "shuffle_v128", .shuffle_v128 },
    .{ "extract_lane", .extract_lane },
    .{ "insert_lane", .insert_lane },
});

pub fn parseOpKind(text: []const u8) ?OpKind {
    return op_kind_by_name.get(text);
}

pub fn isTypeConversionOpKind(kind: OpKind) bool {
    return switch (kind) {
        .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => true,
        else => false,
    };
}

pub fn isUnaryOpKind(kind: OpKind) bool {
    return switch (kind) {
        .neg, .not, .fneg, .zext, .sext, .trunc, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => true,
        else => false,
    };
}

pub fn isBinaryOpKind(kind: OpKind) bool {
    return switch (kind) {
        .add, .sub, .mul, .sdiv, .udiv, .srem, .urem, .div, .rem, .gt, .lt, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule, .@"and", .@"or", .xor, .shl, .lshr, .ashr, .shr, .eq, .ne, .fadd, .fsub, .fmul, .fdiv, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge, .extract_lane, .add_v128, .sub_v128, .mul_v128 => true,
        else => false,
    };
}

pub fn isTernaryOpKind(kind: OpKind) bool {
    return switch (kind) {
        .shuffle_v128, .insert_lane => true,
        else => false,
    };
}

pub const OpCode = enum(u8) {
    add,
    sub,
    mul,
    div,
    sdiv,
    udiv,
    rem,
    srem,
    urem,
    gt,
    lt,
    sgt,
    slt,
    sge,
    sle,
    ugt,
    ult,
    uge,
    ule,
    eq,
    ne,
    @"and",
    @"or",
    shl,
    shr,
};

const op_code_by_name = std.StaticStringMap(OpCode).initComptime(.{
    .{ "add", .add },
    .{ "sub", .sub },
    .{ "mul", .mul },
    .{ "div", .div },
    .{ "sdiv", .sdiv },
    .{ "udiv", .udiv },
    .{ "rem", .rem },
    .{ "srem", .srem },
    .{ "urem", .urem },
    .{ "gt", .gt },
    .{ "lt", .lt },
    .{ "sgt", .sgt },
    .{ "slt", .slt },
    .{ "sge", .sge },
    .{ "sle", .sle },
    .{ "ugt", .ugt },
    .{ "ult", .ult },
    .{ "uge", .uge },
    .{ "ule", .ule },
    .{ "eq", .eq },
    .{ "ne", .ne },
    .{ "and", .@"and" },
    .{ "or", .@"or" },
    .{ "shl", .shl },
    .{ "shr", .shr },
});

pub fn parseOpCode(text: []const u8) ?OpCode {
    return op_code_by_name.get(text);
}

pub const AtomicOrdering = atomic.AtomicOrdering;
pub const AtomicRmwOp = atomic.AtomicRmwOp;
pub const ConstDecl = const_decl.ConstDecl;
pub const ConstValue = const_decl.ConstValue;
pub const BytesLiteral = const_decl.BytesLiteral;
pub const VTableLiteral = const_decl.VTableLiteral;
pub const VTableSlot = const_decl.VTableSlot;

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
    assign,
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
    test_decl,
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
    package_identity: ?[]const u8 = null,
    package_source_sha256: ?[32]u8 = null,
    upstream_loc: ?upstream.UpstreamLoc = null,
    op_kind: ?OpKind = null,
    operands: [4]Operand,
    raw_text: []const u8,
    atomic_value_ty: ?u32 = null,
    atomic_ordering: ?AtomicOrdering = null,
    atomic_second_ordering: ?AtomicOrdering = null,
    atomic_rmw_op: ?AtomicRmwOp = null,
    atomic_expected_text: ?[]const u8 = null,
    atomic_new_text: ?[]const u8 = null,
    native_reg_names: []const []const u8 = &.{},
};

pub fn makeInstruction(kind: InstKind, source_line: u32, expanded_line: u32, upstream_loc: ?upstream.UpstreamLoc, raw_text: []const u8) Instruction {
    return .{
        .kind = kind,
        .source_line = source_line,
        .expanded_line = expanded_line,
        .package_identity = null,
        .package_source_sha256 = null,
        .upstream_loc = upstream_loc,
        .op_kind = null,
        .operands = .{ operandNone(), operandNone(), operandNone(), operandNone() },
        .raw_text = raw_text,
        .atomic_value_ty = null,
        .atomic_ordering = null,
        .atomic_second_ordering = null,
        .atomic_rmw_op = null,
        .atomic_expected_text = null,
        .atomic_new_text = null,
        .native_reg_names = &.{},
    };
}

pub fn operandNone() Operand {
    return .{ .none = {} };
}

test "instruction layout keeps four operands and tags" {
    const inst = makeInstruction(.alloc, 7, 11, null, "x = alloc 8");
    try std.testing.expectEqual(@as(u32, 7), inst.source_line);
    try std.testing.expectEqual(@as(u32, 11), inst.expanded_line);
    try std.testing.expect(inst.package_identity == null);
    try std.testing.expect(inst.package_source_sha256 == null);
    try std.testing.expect(inst.upstream_loc == null);
    try std.testing.expect(inst.op_kind == null);
    try std.testing.expectEqual(@as(usize, 4), inst.operands.len);
    try std.testing.expectEqual(InstKind.alloc, inst.kind);
    try std.testing.expect(std.mem.eql(u8, inst.raw_text, "x = alloc 8"));
}

test "op code parsing covers signed and unsigned aliases" {
    try std.testing.expectEqual(OpCode.sgt, parseOpCode("sgt").?);
    try std.testing.expectEqual(OpCode.sle, parseOpCode("sle").?);
    try std.testing.expectEqual(OpCode.ult, parseOpCode("ult").?);
    try std.testing.expectEqual(OpCode.srem, parseOpCode("srem").?);
    try std.testing.expectEqual(OpCode.udiv, parseOpCode("udiv").?);
    try std.testing.expect(parseOpCode("nonsense") == null);
}

test "op kind parsing covers new and compatibility names" {
    try std.testing.expectEqual(OpKind.zext, parseOpKind("zext").?);
    try std.testing.expectEqual(OpKind.fcmp_ge, parseOpKind("fcmp_ge").?);
    try std.testing.expectEqual(OpKind.insert_lane, parseOpKind("insert_lane").?);
    try std.testing.expectEqual(OpKind.gt, parseOpKind("gt").?);
    try std.testing.expectEqual(OpKind.div, parseOpKind("div").?);
    try std.testing.expectEqual(OpKind.shr, parseOpKind("shr").?);
    try std.testing.expect(isBinaryOpKind(OpKind.shr));
    try std.testing.expect(parseOpKind("nonsense") == null);
}

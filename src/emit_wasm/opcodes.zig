const std = @import("std");
const encoder = @import("encoder.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");

pub const Opcode = std.wasm.Opcode;
pub const MiscOpcode = std.wasm.MiscOpcode;
pub const SimdOpcode = std.wasm.SimdOpcode;
pub const AtomicsOpcode = std.wasm.AtomicsOpcode;
pub const ValueType = std.wasm.Valtype;

pub const Target = enum {
    wasm32,
    wasm64,
};

pub const AtomicExtension = enum {
    load,
    store,
    cmpxchg,
    rmw,
    fence,
};

pub const SimdExtension = enum {
    load,
    store,
    add,
    sub,
    mul,
    shuffle,
    extract_lane,
    insert_lane,
};

pub const WasiImport = enum {
    fd_write,
    fd_read,
    path_open,
    proc_exit,
    args_get,
    args_sizes_get,
};

pub const MapError = error{
    InvalidOperand,
    InvalidType,
    MissingTypeHint,
    UnsupportedInstruction,
    UnsupportedAtomic,
    UnsupportedSimd,
    UnsupportedWasiImport,
};

pub const MapOptions = struct {
    target: Target = .wasm32,
    value_ty: ?sig.PrimType = null,
    malloc_module: []const u8 = "env",
};

pub const NumericPreload = enum {
    none,
    zero,
    all_ones,
};

pub const NumericDescriptor = struct {
    opcode: Opcode,
    prim_ty: sig.PrimType,
    wasm_ty: ValueType,
    preload: NumericPreload = .none,
};

pub const MemArg = struct {
    offset: u64 = 0,
    align_log2: u32 = 0,
    memory_index: u32 = 0,
};

pub const MemoryDescriptor = struct {
    opcode: Opcode,
    prim_ty: sig.PrimType,
    wasm_ty: ValueType,
    memarg: MemArg = .{},
};

pub const ImportBinding = struct {
    module: []const u8,
    name: []const u8,
    params: []const ValueType,
    result_prim_ty: ?sig.PrimType = null,
    result_wasm_ty: ?ValueType = null,
    call_opcode: Opcode = .call,
};

pub const Mapping = union(enum) {
    noop: void,
    opcode: Opcode,
    numeric: NumericDescriptor,
    memory: MemoryDescriptor,
    import_call: ImportBinding,
};

const malloc_params32 = [_]ValueType{.i32};
const malloc_params64 = [_]ValueType{.i64};

pub const wasi_module_name = "wasi_snapshot_preview1";

pub fn opcodeByte(op: Opcode) u8 {
    return @intFromEnum(op);
}

pub fn writeOpcode(writer: anytype, op: Opcode) !void {
    try writer.writeByte(opcodeByte(op));
}

pub fn writePrefixedOpcode(writer: anytype, prefix: Opcode, subopcode: anytype) !void {
    try writeOpcode(writer, prefix);
    try encoder.writeUleb32(writer, @intFromEnum(subopcode));
}

pub fn atomicExtensionName(kind: AtomicExtension) []const u8 {
    return switch (kind) {
        .load => "load",
        .store => "store",
        .cmpxchg => "cmpxchg",
        .rmw => "rmw",
        .fence => "fence",
    };
}

pub fn simdExtensionName(kind: SimdExtension) []const u8 {
    return switch (kind) {
        .load => "load",
        .store => "store",
        .add => "add",
        .sub => "sub",
        .mul => "mul",
        .shuffle => "shuffle",
        .extract_lane => "extract_lane",
        .insert_lane => "insert_lane",
    };
}

pub fn wasiImportName(kind: WasiImport) []const u8 {
    return switch (kind) {
        .fd_write => "fd_write",
        .fd_read => "fd_read",
        .path_open => "path_open",
        .proc_exit => "proc_exit",
        .args_get => "args_get",
        .args_sizes_get => "args_sizes_get",
    };
}

pub fn pointerValueType(target: Target) ValueType {
    return switch (target) {
        .wasm32 => .i32,
        .wasm64 => .i64,
    };
}

pub fn wasmValueTypeForPrim(ty: sig.PrimType, target: Target) MapError!ValueType {
    return switch (ty) {
        .void => error.InvalidType,
        .i1, .i8, .i16, .i32, .u8, .u16, .u32 => .i32,
        .i64, .u64 => .i64,
        .f32 => .f32,
        .f64 => .f64,
        .ptr => pointerValueType(target),
        .v128 => .v128,
    };
}

pub fn allocImportBinding(target: Target, module: []const u8) ImportBinding {
    return .{
        .module = module,
        .name = "malloc",
        .params = if (target == .wasm32) malloc_params32[0..] else malloc_params64[0..],
        .result_prim_ty = .ptr,
        .result_wasm_ty = pointerValueType(target),
    };
}

pub fn controlOpcode(kind: inst.InstKind) MapError!Opcode {
    return switch (kind) {
        .jmp => .br,
        .br => .br_if,
        .call => .call,
        .call_indirect => .call_indirect,
        .panic => .@"unreachable",
        .return_ => .@"return",
        else => error.UnsupportedInstruction,
    };
}

fn isFloatPrim(ty: sig.PrimType) bool {
    return ty == .f32 or ty == .f64;
}

fn isUnsignedIntegerPrim(ty: sig.PrimType) bool {
    return switch (ty) {
        .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

fn isSignedIntegerPrim(ty: sig.PrimType) bool {
    return switch (ty) {
        .i1, .i8, .i16, .i32, .i64 => true,
        else => false,
    };
}

fn isIntegerLikePrim(ty: sig.PrimType) bool {
    return isSignedIntegerPrim(ty) or isUnsignedIntegerPrim(ty) or ty == .ptr;
}

fn isSimdPrim(ty: sig.PrimType) bool {
    return ty == .v128;
}

fn integerWidthOpcode(ty: ValueType, op32: Opcode, op64: Opcode) Opcode {
    return switch (ty) {
        .i32 => op32,
        .i64 => op64,
        else => op32,
    };
}

fn naturalAlignLog2ForPrim(ty: sig.PrimType, target: Target) u32 {
    return switch (ty) {
        .i1, .i8, .u8 => 0,
        .i16, .u16 => 1,
        .i32, .u32, .f32 => 2,
        .i64, .u64, .f64 => 3,
        .ptr => switch (target) {
            .wasm32 => 2,
            .wasm64 => 3,
        },
        .v128 => 4,
        .void => 0,
    };
}

fn parseOffset(operand: inst.Operand) MapError!u64 {
    return switch (operand) {
        .imm_u64 => |value| value,
        .imm_i64 => |value| if (value > 0) @as(u64, @intCast(value)) else 0,
        .imm_int => |value| if (value > 0) @as(u64, @intCast(value)) else 0,
        .text => |text| std.fmt.parseInt(u64, std.mem.trim(u8, text, " \t"), 10) catch error.InvalidOperand,
        .none => 0,
        else => error.InvalidOperand,
    };
}

fn typeFromOperand(
    operand: inst.Operand,
    default_ty: ?sig.PrimType,
) MapError!?sig.PrimType {
    return switch (operand) {
        .ty => |tag| sig.primTypeFromTag(tag) orelse error.InvalidType,
        else => default_ty,
    };
}

fn loadStorePrimType(kind: inst.InstKind, type_operand: inst.Operand, hint: ?sig.PrimType) MapError!sig.PrimType {
    if (try typeFromOperand(type_operand, hint)) |ty| return ty;
    return switch (kind) {
        .take => .ptr,
        .load, .store => .i64,
        else => error.InvalidType,
    };
}

fn loadOpcodeForPrim(ty: sig.PrimType, target: Target) MapError!Opcode {
    return switch (ty) {
        .i1 => .i32_load8_u,
        .i8 => .i32_load8_s,
        .u8 => .i32_load8_u,
        .i16 => .i32_load16_s,
        .u16 => .i32_load16_u,
        .i32, .u32 => .i32_load,
        .i64, .u64 => .i64_load,
        .ptr => switch (pointerValueType(target)) {
            .i32 => .i32_load,
            .i64 => .i64_load,
            else => unreachable,
        },
        .f32 => .f32_load,
        .f64 => .f64_load,
        .v128 => error.UnsupportedSimd,
        .void => error.InvalidType,
    };
}

fn storeOpcodeForPrim(ty: sig.PrimType, target: Target) MapError!Opcode {
    return switch (ty) {
        .i1, .i8, .u8 => .i32_store8,
        .i16, .u16 => .i32_store16,
        .i32, .u32 => .i32_store,
        .i64, .u64 => .i64_store,
        .ptr => switch (pointerValueType(target)) {
            .i32 => .i32_store,
            .i64 => .i64_store,
            else => unreachable,
        },
        .f32 => .f32_store,
        .f64 => .f64_store,
        .v128 => error.UnsupportedSimd,
        .void => error.InvalidType,
    };
}

fn comparisonOpcode(kind: inst.OpKind, ty: sig.PrimType, target: Target) MapError!Opcode {
    if (isFloatPrim(ty)) {
        return switch (kind) {
            .eq, .fcmp_eq => if (ty == .f32) .f32_eq else .f64_eq,
            .ne, .fcmp_ne => if (ty == .f32) .f32_ne else .f64_ne,
            .lt, .fcmp_lt => if (ty == .f32) .f32_lt else .f64_lt,
            .gt, .fcmp_gt => if (ty == .f32) .f32_gt else .f64_gt,
            .fcmp_le => if (ty == .f32) .f32_le else .f64_le,
            .fcmp_ge => if (ty == .f32) .f32_ge else .f64_ge,
            else => error.InvalidType,
        };
    }

    if (!isIntegerLikePrim(ty)) return error.InvalidType;
    const wasm_ty = if (ty == .ptr) pointerValueType(target) else try wasmValueTypeForPrim(ty, target);
    return switch (kind) {
        .eq => if (wasm_ty == .i64) .i64_eq else .i32_eq,
        .ne => if (wasm_ty == .i64) .i64_ne else .i32_ne,
        .slt => if (!isSignedIntegerPrim(ty)) error.InvalidType else if (wasm_ty == .i64) .i64_lt_s else .i32_lt_s,
        .sle => if (!isSignedIntegerPrim(ty)) error.InvalidType else if (wasm_ty == .i64) .i64_le_s else .i32_le_s,
        .sgt => if (!isSignedIntegerPrim(ty)) error.InvalidType else if (wasm_ty == .i64) .i64_gt_s else .i32_gt_s,
        .sge => if (!isSignedIntegerPrim(ty)) error.InvalidType else if (wasm_ty == .i64) .i64_ge_s else .i32_ge_s,
        .ult => if (wasm_ty == .i64) .i64_lt_u else .i32_lt_u,
        .ule => if (wasm_ty == .i64) .i64_le_u else .i32_le_u,
        .ugt => if (wasm_ty == .i64) .i64_gt_u else .i32_gt_u,
        .uge => if (wasm_ty == .i64) .i64_ge_u else .i32_ge_u,
        .gt => if (wasm_ty == .i64) (if (isSignedIntegerPrim(ty)) .i64_gt_s else .i64_gt_u) else (if (isSignedIntegerPrim(ty)) .i32_gt_s else .i32_gt_u),
        .lt => if (wasm_ty == .i64) (if (isSignedIntegerPrim(ty)) .i64_lt_s else .i64_lt_u) else (if (isSignedIntegerPrim(ty)) .i32_lt_s else .i32_lt_u),
        .div, .rem, .shr, .add, .sub, .mul, .@"and", .@"or", .xor, .shl, .lshr, .ashr, .neg, .not, .fadd, .fsub, .fmul, .fdiv, .fneg => error.InvalidType,
        else => error.InvalidType,
    };
}

pub fn mapNumericOp(kind: inst.OpKind, prim_ty: sig.PrimType, target: Target) MapError!NumericDescriptor {
    if (isSimdPrim(prim_ty)) return error.UnsupportedSimd;
    if (prim_ty == .void) return error.InvalidType;

    if (prim_ty == .ptr) {
        return switch (kind) {
            .eq, .ne => .{
                .opcode = try comparisonOpcode(kind, prim_ty, target),
                .prim_ty = prim_ty,
                .wasm_ty = try wasmValueTypeForPrim(prim_ty, target),
            },
            else => error.InvalidType,
        };
    }

    const wasm_ty = try wasmValueTypeForPrim(prim_ty, target);
    if (wasm_ty == .v128) return error.UnsupportedSimd;

    return switch (kind) {
        .add => .{
            .opcode = integerWidthOpcode(wasm_ty, if (wasm_ty == .f32) .f32_add else if (wasm_ty == .f64) .f64_add else .i32_add, if (wasm_ty == .f32) .f32_add else if (wasm_ty == .f64) .f64_add else .i64_add),
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .sub => .{
            .opcode = integerWidthOpcode(wasm_ty, if (wasm_ty == .f32) .f32_sub else if (wasm_ty == .f64) .f64_sub else .i32_sub, if (wasm_ty == .f32) .f32_sub else if (wasm_ty == .f64) .f64_sub else .i64_sub),
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .mul => .{
            .opcode = integerWidthOpcode(wasm_ty, if (wasm_ty == .f32) .f32_mul else if (wasm_ty == .f64) .f64_mul else .i32_mul, if (wasm_ty == .f32) .f32_mul else if (wasm_ty == .f64) .f64_mul else .i64_mul),
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .sdiv => if (!isSignedIntegerPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_div_s else .i32_div_s,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .udiv => if (isFloatPrim(prim_ty)) error.InvalidType else if (isSignedIntegerPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_div_u else .i32_div_u,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .srem => if (!isSignedIntegerPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_rem_s else .i32_rem_s,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .urem => if (isFloatPrim(prim_ty)) error.InvalidType else if (isSignedIntegerPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_rem_u else .i32_rem_u,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .@"and" => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_and else .i32_and,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .@"or" => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_or else .i32_or,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .xor => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_xor else .i32_xor,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .shl => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_shl else .i32_shl,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .lshr => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_shr_u else .i32_shr_u,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .shr => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) (if (isSignedIntegerPrim(prim_ty)) .i64_shr_s else .i64_shr_u) else (if (isSignedIntegerPrim(prim_ty)) .i32_shr_s else .i32_shr_u),
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .ashr => if (!isSignedIntegerPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_shr_s else .i32_shr_s,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .neg => if (isFloatPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .f32) .f32_neg else .f64_neg,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        } else if (isIntegerLikePrim(prim_ty) and !isSimdPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .i64) .i64_sub else .i32_sub,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
            .preload = .zero,
        } else error.InvalidType,
        .not => if (!isIntegerLikePrim(prim_ty) or isSimdPrim(prim_ty) or isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .i64) .i64_xor else .i32_xor,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
            .preload = .all_ones,
        },
        .div => if (isFloatPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .f32) .f32_div else .f64_div,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        } else if (isSignedIntegerPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .i64) .i64_div_s else .i32_div_s,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        } else if (isUnsignedIntegerPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .i64) .i64_div_u else .i32_div_u,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        } else error.InvalidType,
        .rem => if (isSignedIntegerPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .i64) .i64_rem_s else .i32_rem_s,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        } else if (isUnsignedIntegerPrim(prim_ty)) .{
            .opcode = if (wasm_ty == .i64) .i64_rem_u else .i32_rem_u,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        } else error.InvalidType,
        .gt, .lt, .eq, .ne, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => .{
            .opcode = try comparisonOpcode(kind, prim_ty, target),
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .fadd => if (!isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .f32) .f32_add else .f64_add,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .fsub => if (!isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .f32) .f32_sub else .f64_sub,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .fmul => if (!isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .f32) .f32_mul else .f64_mul,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .fdiv => if (!isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .f32) .f32_div else .f64_div,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .fneg => if (!isFloatPrim(prim_ty)) error.InvalidType else .{
            .opcode = if (wasm_ty == .f32) .f32_neg else .f64_neg,
            .prim_ty = prim_ty,
            .wasm_ty = wasm_ty,
        },
        .add_v128, .sub_v128, .mul_v128, .shuffle_v128, .extract_lane, .insert_lane => error.UnsupportedSimd,
        .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => error.UnsupportedInstruction,
    };
}

pub fn mapLoadStore(kind: inst.InstKind, prim_ty: sig.PrimType, target: Target, offset: u64) MapError!MemoryDescriptor {
    const opcode = try switch (kind) {
        .load, .take => loadOpcodeForPrim(prim_ty, target),
        .store => storeOpcodeForPrim(prim_ty, target),
        else => error.UnsupportedInstruction,
    };
    const wasm_ty = try wasmValueTypeForPrim(prim_ty, target);
    return .{
        .opcode = opcode,
        .prim_ty = prim_ty,
        .wasm_ty = wasm_ty,
        .memarg = .{
            .offset = offset,
            .align_log2 = naturalAlignLog2ForPrim(prim_ty, target),
        },
    };
}

pub fn mapInstruction(base: inst.Instruction, options: MapOptions) MapError!Mapping {
    return switch (base.kind) {
        .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .borrow, .move_, .release, .assign, .raw_cast, .assume_safe, .assume_borrow => .{ .noop = {} },
        .alloc => .{ .import_call = allocImportBinding(options.target, options.malloc_module) },
        .stack_alloc => error.UnsupportedInstruction,
        .load, .take, .store => blk: {
            const ty = try loadStorePrimType(base.kind, base.operands[3], options.value_ty);
            const offset = try parseOffset(base.operands[2]);
            break :blk .{ .memory = try mapLoadStore(base.kind, ty, options.target, offset) };
        },
        .op => blk: {
            const op_kind = base.op_kind orelse return error.InvalidOperand;
            const ty = options.value_ty orelse return error.MissingTypeHint;
            break :blk .{ .numeric = try mapNumericOp(op_kind, ty, options.target) };
        },
        .ptr_add => blk: {
            const ty = pointerValueType(options.target);
            break :blk .{
                .numeric = .{
                    .opcode = if (ty == .i64) .i64_add else .i32_add,
                    .prim_ty = .ptr,
                    .wasm_ty = ty,
                },
            };
        },
        .jmp, .br, .call, .call_indirect, .panic, .return_ => .{ .opcode = try controlOpcode(base.kind) },
        .br_null => error.UnsupportedInstruction,
        .panic_msg => error.UnsupportedWasiImport,
        .try_, .early_return => error.UnsupportedInstruction,
        .atomic_load, .atomic_store, .cmpxchg, .atomic_rmw, .fence => error.UnsupportedAtomic,
        .native => error.UnsupportedInstruction,
    };
}

test "opcode aliases match wasm core bytes" {
    try std.testing.expectEqual(@as(u8, 0x00), opcodeByte(.@"unreachable"));
    try std.testing.expectEqual(@as(u8, 0x10), opcodeByte(.call));
    try std.testing.expectEqual(@as(u8, 0x0F), opcodeByte(.@"return"));
    try std.testing.expectEqual(@as(u8, 0x6A), opcodeByte(.i32_add));
}

test "alloc maps to malloc import binding" {
    const binding32 = allocImportBinding(.wasm32, "env");
    try std.testing.expectEqualStrings("env", binding32.module);
    try std.testing.expectEqualStrings("malloc", binding32.name);
    try std.testing.expectEqual(@as(usize, 1), binding32.params.len);
    try std.testing.expectEqual(ValueType.i32, binding32.params[0]);
    try std.testing.expectEqual(ValueType.i32, binding32.result_wasm_ty.?);
    try std.testing.expectEqual(sig.PrimType.ptr, binding32.result_prim_ty.?);

    const binding64 = allocImportBinding(.wasm64, "env");
    try std.testing.expectEqual(ValueType.i64, binding64.params[0]);
    try std.testing.expectEqual(ValueType.i64, binding64.result_wasm_ty.?);
}

test "numeric mapping covers integer and float descriptors" {
    const add = try mapNumericOp(.add, .i64, .wasm64);
    try std.testing.expectEqual(.i64_add, add.opcode);
    try std.testing.expectEqual(sig.PrimType.i64, add.prim_ty);
    try std.testing.expectEqual(ValueType.i64, add.wasm_ty);
    try std.testing.expectEqual(NumericPreload.none, add.preload);

    const neg = try mapNumericOp(.neg, .u32, .wasm32);
    try std.testing.expectEqual(.i32_sub, neg.opcode);
    try std.testing.expectEqual(NumericPreload.zero, neg.preload);

    const not_ = try mapNumericOp(.not, .i32, .wasm32);
    try std.testing.expectEqual(.i32_xor, not_.opcode);
    try std.testing.expectEqual(NumericPreload.all_ones, not_.preload);

    const float_gt = try mapNumericOp(.gt, .f32, .wasm32);
    try std.testing.expectEqual(.f32_gt, float_gt.opcode);
    try std.testing.expectEqual(ValueType.f32, float_gt.wasm_ty);
}

test "memory mapping chooses width-aware load and store opcodes" {
    const load_u8 = try mapLoadStore(.load, .u8, .wasm32, 16);
    try std.testing.expectEqual(.i32_load8_u, load_u8.opcode);
    try std.testing.expectEqual(@as(u32, 0), load_u8.memarg.align_log2);
    try std.testing.expectEqual(@as(u64, 16), load_u8.memarg.offset);
    try std.testing.expectEqual(ValueType.i32, load_u8.wasm_ty);

    const load_ptr64 = try mapLoadStore(.take, .ptr, .wasm64, 8);
    try std.testing.expectEqual(.i64_load, load_ptr64.opcode);
    try std.testing.expectEqual(ValueType.i64, load_ptr64.wasm_ty);
    try std.testing.expectEqual(@as(u32, 3), load_ptr64.memarg.align_log2);

    const store_i16 = try mapLoadStore(.store, .i16, .wasm32, 4);
    try std.testing.expectEqual(.i32_store16, store_i16.opcode);
    try std.testing.expectEqual(ValueType.i32, store_i16.wasm_ty);
}

test "instruction mapping covers panic, control flow, and explicit errors" {
    const panic_inst = inst.makeInstruction(.panic, 1, 1, null, "panic(7)");
    const panic_mapping = try mapInstruction(panic_inst, .{});
    switch (panic_mapping) {
        .opcode => |op| try std.testing.expectEqual(.@"unreachable", op),
        else => return error.TestUnexpectedResult,
    }

    const jmp_inst = inst.makeInstruction(.jmp, 1, 1, null, "jmp L_END");
    const jmp_mapping = try mapInstruction(jmp_inst, .{});
    switch (jmp_mapping) {
        .opcode => |op| try std.testing.expectEqual(.br, op),
        else => return error.TestUnexpectedResult,
    }

    const atomic_inst = inst.makeInstruction(.atomic_load, 1, 1, null, "x = atomic_load node+0 seq_cst");
    try std.testing.expectError(MapError.UnsupportedAtomic, mapInstruction(atomic_inst, .{}));

    var simd_inst = inst.makeInstruction(.op, 1, 1, null, "v = add_v128 a, b");
    simd_inst.op_kind = .add_v128;
    try std.testing.expectError(MapError.UnsupportedSimd, mapInstruction(simd_inst, .{ .value_ty = .v128 }));

    const panic_msg_inst = inst.makeInstruction(.panic_msg, 1, 1, null, "panic_msg(1, msg, len)");
    try std.testing.expectError(MapError.UnsupportedWasiImport, mapInstruction(panic_msg_inst, .{}));
}

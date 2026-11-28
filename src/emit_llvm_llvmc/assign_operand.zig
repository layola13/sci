const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const emit_options = @import("../emit_options.zig");
const flattener = @import("../flattener.zig");
const inst = @import("../common/instruction.zig");
const atomic = @import("../common/atomic.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");
const upstream = @import("../common/upstream_loc.zig");
const sio = @import("sio");

const BuildState = @import("sa_llvmc_free.zig").BuildState;
const CAtomicOrdering = @import("sa_llvmc_free.zig").CAtomicOrdering;
const CAtomicRmwOp = @import("sa_llvmc_free.zig").CAtomicRmwOp;
const CDebugLoc = @import("sa_llvmc_free.zig").CDebugLoc;
const CDebugVar = @import("sa_llvmc_free.zig").CDebugVar;
const CFuncKind = @import("sa_llvmc_free.zig").CFuncKind;
const CFunction = @import("sa_llvmc_free.zig").CFunction;
const CInstruction = @import("sa_llvmc_free.zig").CInstruction;
const COperand = @import("sa_llvmc_free.zig").COperand;
const CParam = @import("sa_llvmc_free.zig").CParam;
const CType = @import("sa_llvmc_free.zig").CType;
const EmitOptions = @import("sa_llvmc_free.zig").EmitOptions;
const SharedEmitTables = @import("atomic_rmw_op.zig").SharedEmitTables;
const assignTy = @import("atomic_rmw_op.zig").assignTy;
const atomicOrdering = @import("sa_llvmc_free.zig").atomicOrdering;
const atomicRmwOp = @import("atomic_rmw_op.zig").atomicRmwOp;
const atomicValueType = @import("atomic_rmw_op.zig").atomicValueType;
const binaryOp = @import("sa_llvmc_free.zig").binaryOp;
const buildDebugVars = @import("sa_llvmc_free.zig").buildDebugVars;
const builtinReturnType = @import("atomic_rmw_op.zig").builtinReturnType;
const cType = @import("sa_llvmc_free.zig").cType;
const conversionOp = @import("atomic_rmw_op.zig").conversionOp;
const debugLocForInstruction = @import("sa_llvmc_free.zig").debugLocForInstruction;
const emittedFunctionName = @import("sa_llvmc_free.zig").emittedFunctionName;
const functionUsesGlobalRegIds = @import("atomic_rmw_op.zig").functionUsesGlobalRegIds;
const inferIndirectSigIndexFromLoad = @import("atomic_rmw_op.zig").inferIndirectSigIndexFromLoad;
const isFloatOp = @import("atomic_rmw_op.zig").isFloatOp;
const labelNameZ = @import("sa_llvmc_free.zig").labelNameZ;
const localizedRegName = @import("atomic_rmw_op.zig").localizedRegName;
const opConversionTy = @import("atomic_rmw_op.zig").opConversionTy;
const parseCarriedIndirectSig = @import("sa_llvmc_free.zig").parseCarriedIndirectSig;
const returnTypeForSig = @import("sa_llvmc_free.zig").returnTypeForSig;
const sourceDirName = @import("sa_llvmc_free.zig").sourceDirName;
const sourceFileName = @import("sa_llvmc_free.zig").sourceFileName;
const valueTypeForPrefix = @import("sa_llvmc_free.zig").valueTypeForPrefix;

pub fn assignOperand(state: *BuildState, base: inst.Instruction) !COperand {
    return switch (base.operands[1]) {
        .reg => |id| blk: {
            if (localizedRegName(state, id)) |name| {
                if (state.const_names.contains(name)) break :blk try state.textOperand(name);
            }
            break :blk try state.operand(base.operands[1]);
        },
        .symbol => |id| blk: {
            const name = state.symbols.lookupName(id) orelse return error.InvalidOperand;
            break :blk try state.textOperand(name);
        },
        .func => |id| blk: {
            const name = state.symbols.lookupName(id) orelse return error.InvalidOperand;
            break :blk try state.textOperand(name);
        },
        .label => |id| blk: {
            const name = state.symbols.lookupName(id) orelse return error.InvalidOperand;
            break :blk try state.textOperand(name);
        },
        else => try state.operand(base.operands[1]),
    };
}

pub fn lowerInstruction(allocator: std.mem.Allocator, state: *BuildState, body_item: referee.AnnotatedInstruction) !?CInstruction {
    const base = body_item.base;
    const none = COperand{ .kind = .none, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .void, .name = null };
    const default_ordering: CAtomicOrdering = .seq_cst;
    const default_rmw: CAtomicRmwOp = .add;
    return switch (base.kind) {
        .label => .{ .op = .label, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = try labelNameZ(allocator, state.symbols, base.operands[1]), .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .alloc, .stack_alloc => |k| .{ .op = if (k == .alloc) .alloc else .stack_alloc, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = .ptr, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = (k == .alloc) },
        .load, .take => |k| blk: {
            const loaded_ty = if (base.operands[3] == .ty) sig.primTypeFromTag(base.operands[3].ty) orelse .i64 else sig.PrimType.i64;
            const indirect_sig_index: u32 = if (loaded_ty == .ptr)
                if (inferIndirectSigIndexFromLoad(state, base)) |idx| @intCast(idx) else std.math.maxInt(u32)
            else
                std.math.maxInt(u32);
            break :blk .{ .op = if (k == .load) .load else .take, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = try cType(loaded_ty), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = indirect_sig_index, .is_malloc = (k == .take) };
        },
        .atomic_load => .{ .op = .atomic_load, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .atomic_store => .{ .op = .atomic_store, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = try state.operand(base.operands[1]), .operand2 = try state.operand(base.operands[2]), .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .atomic_rmw => .{ .op = .atomic_rmw, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = try state.operand(base.operands[3]), .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = try atomicRmwOp(base.atomic_rmw_op), .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .cmpxchg => blk: {
            const args = try allocator.alloc(COperand, 2);
            args[0] = try state.textOperand(base.atomic_new_text orelse return error.InvalidOperand);
            args[1] = .{ .kind = .reg, .reg = try state.regSlot(base.operands[1].reg), .i64_value = 0, .u64_value = 0, .f64_value = 0, .ty = .i1, .name = null };
            break :blk .{ .op = .cmpxchg, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[2]), .operand1 = try state.operand(base.operands[3]), .operand2 = try state.textOperand(base.atomic_expected_text orelse return error.InvalidOperand), .ty = try cType(atomicValueType(base, .i64)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = args.ptr, .arg_count = args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = atomicOrdering(base.atomic_second_ordering), .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
        },
        .fence => .{ .op = .fence, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = atomicOrdering(base.atomic_ordering), .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .store => .{ .op = .store, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = try state.operand(base.operands[1]), .operand2 = try state.operand(base.operands[2]), .ty = if (base.operands[3] == .ty) try cType(sig.primTypeFromTag(base.operands[3].ty) orelse .i64) else .i64, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .op => blk: {
            const opcode = base.op_kind orelse return error.InvalidOperand;
            if (inst.isTypeConversionOpKind(opcode)) {
                break :blk .{ .op = conversionOp(opcode), .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = try opConversionTy(base), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            if (opcode == .fneg) {
                break :blk .{ .op = .op, .dst = try state.regSlot(base.operands[0].reg), .operand0 = .{ .kind = .imm_f64, .reg = 0, .i64_value = 0, .u64_value = 0, .f64_value = 0.0, .ty = .f64, .name = null }, .operand1 = try state.operand(base.operands[1]), .operand2 = none, .ty = .f64, .binary_op = try binaryOp(opcode), .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            break :blk .{ .op = .op, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = if (isFloatOp(opcode)) .f64 else .i64, .binary_op = try binaryOp(opcode), .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
        },
        .ptr_add => .{ .op = .ptr_add, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = try state.operand(base.operands[2]), .operand2 = none, .ty = .ptr, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .jmp => .{ .op = .jmp, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = try labelNameZ(allocator, state.symbols, base.operands[1]), .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .br => .{ .op = .br, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = try labelNameZ(allocator, state.symbols, base.operands[1]), .false_label = try labelNameZ(allocator, state.symbols, base.operands[3]), .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .call, .call_indirect, .panic, .panic_msg => blk: {
            var parsed = call.parseInstructionCall(allocator, base, state) catch return error.InvalidOperand;
            defer parsed.deinit(allocator);
            if (base.kind == .panic) {
                if (parsed.args.len != 1) return error.InvalidOperand;
                break :blk .{ .op = .panic, .dst = 0, .operand0 = try state.callArgOperand(parsed.args[0]), .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            if (base.kind == .panic_msg) {
                if (parsed.args.len != 3) return error.InvalidOperand;
                const panic_args = try allocator.alloc(COperand, 3);
                errdefer allocator.free(panic_args);
                panic_args[0] = try state.callArgOperand(parsed.args[0]);
                panic_args[1] = try state.callArgOperand(parsed.args[1]);
                panic_args[2] = try state.callArgOperand(parsed.args[2]);
                break :blk .{ .op = .call, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = "panic_msg", .args = panic_args.ptr, .arg_count = panic_args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            }
            if (base.kind != .call and base.kind != .call_indirect) break :blk .{ .op = .panic, .dst = 0, .operand0 = none, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) };
            const args = try allocator.alloc(COperand, parsed.args.len);
            for (parsed.args, 0..) |arg, idx| args[idx] = try state.callArgOperand(arg);
            const resolved = state.calleeSig(parsed.callee);
            const dst: u32 = if (parsed.dest) |dest| blk2: {
                const id = state.symbols.findId(dest) orelse return error.InvalidOperand;
                break :blk2 state.fsig.slotOf(id) orelse return error.InvalidOperand;
            } else 0;
            var is_malloc_val = false;
            if (parsed.dest) |dest_name| {
                if (state.symbols.findId(dest_name)) |dst_id| {
                    for (body_item.delta.changes) |change| {
                        if (change.reg == dst_id) {
                            if ((change.after & (0x10 | 0x20 | 0x40 | 0x0200)) == 0) {
                                is_malloc_val = true;
                            }
                            break;
                        }
                    }
                }
            }
            if (parsed.is_indirect) {
                const callee_op = try state.textOperand(parsed.callee);
                // C2 sab_carried_indirect_sig: when the frontend
                // carried the fn-pointer signature on this call, hand
                // its fixed params / return / variadic flag to the
                // shim, which trusts them over inference.
                var carried_param_tys: []const CType = &.{};
                var carried_ret_ty: CType = .void;
                var carried_is_variadic = false;
                var has_carried_sig = false;
                if (parsed.carried_sig_text) |carried_text| {
                    const carried = parseCarriedIndirectSig(allocator, carried_text) catch return error.InvalidOperand;
                    carried_param_tys = carried.params;
                    carried_ret_ty = carried.ret_ty;
                    carried_is_variadic = carried.is_variadic;
                    has_carried_sig = true;
                }
                break :blk .{ .op = .call_indirect, .dst = dst, .operand0 = callee_op, .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = args.ptr, .arg_count = args.len, .indirect_param_tys = carried_param_tys.ptr, .indirect_param_count = carried_param_tys.len, .has_dst = parsed.dest != null, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = is_malloc_val, .indirect_ret_ty = carried_ret_ty, .indirect_is_variadic = carried_is_variadic, .indirect_has_carried_sig = has_carried_sig };
            }
            const callee_name = if (resolved) |resolved_sig| emittedFunctionName(resolved_sig) else parsed.callee;
            const callee = try allocator.dupeSentinel(u8, callee_name, 0);
            const call_ty = if (resolved) |resolved_sig| try cType(returnTypeForSig(resolved_sig.return_cap, resolved_sig.return_ty)) else builtinReturnType(parsed.callee) orelse CType.void;
            const call_fallible = if (resolved) |resolved_sig| resolved_sig.return_fallible else false;
            break :blk .{ .op = .call, .dst = dst, .operand0 = none, .operand1 = none, .operand2 = none, .ty = call_ty, .binary_op = .add, .label = null, .false_label = null, .callee = callee.ptr, .args = args.ptr, .arg_count = args.len, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = parsed.dest != null, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = call_fallible, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = is_malloc_val };
        },
        .va_start => .{ .op = .va_start, .dst = try state.regSlot(base.operands[0].reg), .operand0 = none, .operand1 = none, .operand2 = none, .ty = .ptr, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .va_arg => .{ .op = .va_arg, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = try cType(sig.primTypeFromTag(base.operands[2].ty) orelse return error.InvalidOperand), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .va_end => .{ .op = .va_end, .dst = 0, .operand0 = try state.operand(base.operands[0]), .operand1 = none, .operand2 = none, .ty = .void, .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = false, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .try_, .early_return => .{ .op = .try_, .dst = try state.regSlot(base.operands[0].reg), .operand0 = try state.operand(base.operands[1]), .operand1 = none, .operand2 = none, .ty = try cType(returnTypeForSig(state.fsig.return_cap, state.fsig.return_ty)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .assign, .borrow, .raw_cast, .assume_safe, .assume_borrow => blk: {
            const value = try assignOperand(state, base);
            const assign_ty = assignTy(base, value);
            const is_ptr = (assign_ty == .ptr);
            var is_malloc_val = false;
            const dst_global_id = try state.regGlobalId(base.operands[0].reg);
            if (is_ptr) {
                for (body_item.delta.changes) |change| {
                    if (change.reg == dst_global_id) {
                        if ((change.after & (0x10 | 0x20 | 0x40 | 0x0200)) == 0) {
                            is_malloc_val = true;
                        }
                        break;
                    }
                }
            }
            break :blk .{ .op = .assign, .dst = try state.regSlot(base.operands[0].reg), .operand0 = value, .operand1 = none, .operand2 = none, .ty = assignTy(base, value), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = true, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32), .is_malloc = is_malloc_val };
        },
        .return_ => .{ .op = .ret, .dst = 0, .operand0 = if (base.operands[0] == .none) none else try state.operand(base.operands[0]), .operand1 = none, .operand2 = none, .ty = try cType(returnTypeForSig(state.fsig.return_cap, state.fsig.return_ty)), .binary_op = .add, .label = null, .false_label = null, .callee = null, .args = &.{}, .arg_count = 0, .indirect_param_tys = &.{}, .indirect_param_count = 0, .has_dst = base.operands[0] != .none, .atomic_ordering = default_ordering, .atomic_second_ordering = default_ordering, .atomic_rmw_op = default_rmw, .return_fallible = false, .indirect_sig_index = std.math.maxInt(u32) },
        .move_ => null,
        // Ownership-transfer annotation: the preceding `store` already moved
        // the bytes; the Referee consumed the semantic fact. No machine code.
        .transfer => null,
        .release => .{
            .op = .release,
            .dst = 0,
            .operand0 = try state.operand(base.operands[0]),
            .operand1 = none,
            .operand2 = none,
            // DEF-R8: the shim's SA_OP_RELEASE emits `free` only when the
            // instruction type is SA_T_PTR (provenance is then decided by
            // the per-register is_malloc flag). Release operands are
            // registers holding owned values; hardcoding .void here made
            // the shim's free path unreachable, so every SA-level `alloc`
            // released with `!reg` leaked on the native LLVM backend.
            .ty = if (base.operands[0] == .reg) .ptr else .void,
            .binary_op = .add,
            .label = null,
            .false_label = null,
            .callee = null,
            .args = &.{},
            .arg_count = 0,
            .indirect_param_tys = &.{},
            .indirect_param_count = 0,
            .has_dst = false,
            .atomic_ordering = default_ordering,
            .atomic_second_ordering = default_ordering,
            .atomic_rmw_op = default_rmw,
            .return_fallible = false,
            .indirect_sig_index = std.math.maxInt(u32),
            .is_malloc = false,
        },
        else => error.UnsupportedInstruction,
    };
}

pub const ParallelEmitTask = struct {
    fsig: sig.FunctionSig,
    sig_idx: usize,
    kind: CFuncKind,
    emit_main_wrapper: bool,
    start_idx: usize,
    end_idx: usize,
    decl_kind: inst.InstKind,
};

pub const ParallelEmitJob = struct {
    arena: std.heap.ArenaAllocator,
    err: ?anyerror = null,
    result: ?CFunction = null,
};

pub fn ParallelEmitContext(comptime VerifiedType: type) type {
    return struct {
        allocator: std.mem.Allocator,
        verified: VerifiedType,
        loc_table: upstream.LocTable,
        source_path: []const u8,
        options: EmitOptions,
        anon_string_names: *const std.StringHashMap([*:0]const u8),
        function_sig_index: *const std.StringHashMap(usize),
        shared_tables: *const SharedEmitTables,
        tasks: []const ParallelEmitTask,
        jobs: []ParallelEmitJob,
        next_task: std.atomic.Value(usize),
    };
}

pub fn chooseEmitWorkerCount(requested_jobs: ?usize, task_count: usize) usize {
    if (task_count < 2) return 1;
    if (requested_jobs) |jobs| {
        return if (jobs <= 1) 1 else @min(jobs, task_count);
    }
    const cpu_count = std.Thread.getCpuCount() catch 1;
    return if (cpu_count <= 1) 1 else @min(cpu_count, task_count);
}

pub fn emitJobBackingAllocator(parent_allocator: std.mem.Allocator, worker_count: usize) std.mem.Allocator {
    return if (worker_count <= 1) parent_allocator else std.heap.page_allocator;
}

pub fn emitWorker(comptime VerifiedType: type, context_ptr: *anyopaque) void {
    const context: *ParallelEmitContext(VerifiedType) = @ptrCast(@alignCast(context_ptr));
    while (true) {
        const task_idx = context.next_task.fetchAdd(1, .monotonic);
        if (task_idx >= context.tasks.len) return;

        const task = context.tasks[task_idx];
        const job = &context.jobs[task_idx];
        const a = job.arena.allocator();

        const fsig = task.fsig;
        const entry_loc: CDebugLoc = if (fsig.upstream_loc) |loc|
            .{ .line = loc.line, .col = loc.col }
        else
            .{ .line = fsig.entry_inst_idx + 1, .col = 1 };

        const func_source_path = if (fsig.upstream_loc) |loc| loc.file else context.source_path;
        const func_source_file = a.dupeSentinel(u8, sourceFileName(func_source_path), 0) catch |err| {
            job.err = err;
            return;
        };
        const func_source_dir = a.dupeSentinel(u8, sourceDirName(func_source_path), 0) catch |err| {
            job.err = err;
            return;
        };

        const params = a.alloc(CParam, fsig.params.len) catch |err| {
            job.err = err;
            return;
        };
        for (fsig.params, 0..) |param, pidx| {
            const pname = a.dupeSentinel(u8, param.name, 0) catch |err| {
                job.err = err;
                return;
            };
            const reg_id = fsig.param_ids[pidx];
            // DEF-R8-FIX (F1b): a `^` (move-cap) pointer parameter takes
            // ownership of the caller's heap allocation (e.g. a Box cell
            // or a struct materialisation). The callee's bare release of
            // that register is the intended free, but the shim's
            // per-function provenance starts every parameter slot as
            // non-malloc, so the free was unreachable for parameters
            // exactly as it was for locals before F1. Seed is_malloc for
            // move-cap pointer params only: by-value pointer params are
            // ambiguous at the signature layer (an owned aggregate and
            // a raw `*T` view share cap/ty), and borrow/raw params are
            // non-owning by construction.
            params[pidx] = .{ .name = pname.ptr, .ty = cType(valueTypeForPrefix(param.cap, param.ty)) catch |err| {
                job.err = err;
                return;
            }, .slot = fsig.slotOf(reg_id) orelse @intCast(pidx), .is_malloc = param.cap == .move and param.ty == .ptr };
        }

        const debug_vars = if (context.options.debug and task.decl_kind != .extern_decl)
            buildDebugVars(a, &context.verified.symbols, fsig, entry_loc) catch |err| {
                job.err = err;
                return;
            }
        else
            @as([]CDebugVar, &.{});

        var insts = std.array_list.Managed(CInstruction).init(a);
        var debug_locs = std.array_list.Managed(CDebugLoc).init(a);

        if (task.decl_kind != .extern_decl) {
            const body = context.verified.annotated[task.start_idx + 1 .. task.end_idx];
            var state = BuildState.init(a, &context.verified.symbols, fsig, functionUsesGlobalRegIds(fsig, body), context.verified.function_sigs, context.function_sig_index, context.shared_tables, context.anon_string_names);
            for (body, task.start_idx + 1..) |body_item, annotated_idx| {
                if (lowerInstruction(a, &state, body_item) catch |err| {
                    job.err = err;
                    return;
                }) |ci| {
                    if (std.mem.eql(u8, fsig.name, "sla__imported_json_get_type") or std.mem.eql(u8, fsig.name, "sla__imported_json_struct") or std.mem.eql(u8, fsig.name, "sla__imported_json_struct_field_key")) {
                        std.debug.print("emit {s} inst#{d} kind={s} c_op={s} dst={d} op0_kind={s} op0_reg={d} op1_kind={s} op1_reg={d}\n", .{ fsig.name, annotated_idx - (task.start_idx + 1), @tagName(body_item.base.kind), @tagName(ci.op), ci.dst, @tagName(ci.operand0.kind), ci.operand0.reg, @tagName(ci.operand1.kind), ci.operand1.reg });
                    }
                    insts.append(ci) catch |err| {
                        job.err = err;
                        return;
                    };
                    if (context.options.debug) {
                        debug_locs.append(debugLocForInstruction(body_item.base, context.loc_table[annotated_idx], entry_loc)) catch |err| {
                            job.err = err;
                            return;
                        };
                    }
                }
            }
        }

        const name = a.dupeSentinel(u8, emittedFunctionName(fsig), 0) catch |err| {
            job.err = err;
            return;
        };
        const ret_ty = cType(returnTypeForSig(fsig.return_cap, fsig.return_ty)) catch |err| {
            job.err = err;
            return;
        };

        job.result = .{
            .name = name.ptr,
            .kind = task.kind,
            .ret_ty = ret_ty,
            .return_fallible = fsig.return_fallible,
            .params = params.ptr,
            .param_count = params.len,
            .instructions = insts.items.ptr,
            .instruction_count = insts.items.len,
            .source_file = if (context.options.debug) func_source_file.ptr else null,
            .source_dir = if (context.options.debug) func_source_dir.ptr else null,
            .entry_line = if (context.options.debug) entry_loc.line else 0,
            .entry_col = if (context.options.debug) entry_loc.col else 0,
            .debug_locs = debug_locs.items.ptr,
            .debug_loc_count = if (context.options.debug) debug_locs.items.len else 0,
            .debug_vars = debug_vars.ptr,
            .debug_var_count = if (context.options.debug) debug_vars.len else 0,
            .emit_main_wrapper = task.emit_main_wrapper,
            .is_variadic = fsig.is_variadic,
        };
    }
}

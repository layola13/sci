const std = @import("std");
const call = @import("../referee/call.zig");
const sig = @import("../common/signature.zig");
const FrameRegs = @import("memory.zig").FrameRegs;
const FunctionRange = @import("memory.zig").FunctionRange;
const FunctionSymbolLookup = @import("memory.zig").FunctionSymbolLookup;
const Interpreter = @import("interpreter.zig").Interpreter;
const RegValue = @import("memory.zig").RegValue;
const RunError = @import("memory.zig").RunError;
const atomicValueType = @import("memory.zig").atomicValueType;
const interpreter_max_call_depth = @import("memory.zig").interpreter_max_call_depth;
const packFallible = @import("memory.zig").packFallible;
const readRawValue = @import("memory.zig").readRawValue;
const readValue = @import("memory.zig").readValue;
const resolveOperandValue = @import("memory.zig").resolveOperandValue;
const returnTypeForSig = @import("memory.zig").returnTypeForSig;
const unpackSuccess = @import("memory.zig").unpackSuccess;
const valueTypeForPrefix = @import("memory.zig").valueTypeForPrefix;

pub fn execFunctionImpl(self: *Interpreter, sig_index: usize, arg_values: []const RegValue) !RegValue {
    if (self.call_depth >= interpreter_max_call_depth) return RunError.CallStackOverflow;
    self.call_depth += 1;
    defer self.call_depth -= 1;

    const fsig = self.program.function_sigs[sig_index];
    if (fsig.is_variadic) return RunError.UnsupportedVariadic;
    if (fsig.kind == .external) {
        self.stderr.print(
            "sa run unsupported extern: {s}; native build may work if the providing plugin or library is installed, but the interpreter has no broker/FFI bridge for this symbol yet\n",
            .{fsig.name},
        ) catch |err| {
            // Diagnostic emission must not mask the interpreter failure.
            _ = @errorName(err);
        };
        return RunError.UnsupportedExtern;
    }
    const range = &self.ranges[sig_index];
    const body = self.program.annotated[range.start..range.end];

    var regs = try FrameRegs.init(self.allocator, &fsig);
    defer regs.deinit(self.allocator);
    var stack_allocs = std.array_list.Managed(u64).init(self.allocator);
    defer {
        for (stack_allocs.items) |addr| {
            self.memory.free(addr) catch |err| {
                // Stack allocations are cleaned up during frame teardown; execution result is already decided.
                _ = @errorName(err);
            };
        }
        stack_allocs.deinit();
    }

    for (fsig.params, 0..) |param, idx| {
        if (idx >= arg_values.len) return RunError.InvalidOperand;
        const id = range.slotOf(fsig.param_ids[idx]) orelse return RunError.InvalidOperand;
        const target_ty = valueTypeForPrefix(param.cap, param.ty);
        const value = try self.coerce(arg_values[idx], target_ty);
        try regs.put(id, .{
            .ty = value.ty,
            .bits = value.bits,
            .fallible = value.fallible,
            .status = value.status,
            .interior_ptr = value.interior_ptr or arg_values[idx].interior_ptr,
            .borrow_view = arg_values[idx].borrow_view,
            .ffi_borrow = arg_values[idx].ffi_borrow,
            .extern_handle = value.extern_handle or arg_values[idx].extern_handle,
            .from_try = value.from_try,
            .const_name = value.const_name,
            .vtable_slot_name = value.vtable_slot_name,
            .call_target_name = value.call_target_name,
        });
    }

    var pc: usize = 0;
    while (pc < body.len) {
        const item = body[pc];
        const base = item.base;
        if (self.trace_runtime) {
            self.stderr.print("trace {s}:{d} {s}: {s}\n", .{ fsig.name, base.source_line, @tagName(base.kind), base.raw_text }) catch |err| {
                // Runtime tracing is diagnostic-only and must not alter interpreter behavior.
                _ = @errorName(err);
            };
        }
        switch (base.kind) {
            .label => {},
            .alloc => {
                const dst = base.operands[0].reg;
                const size = try self.resolveSizeOperand(&regs, base.operands[1]);
                const addr = try self.memory.alloc(@intCast(size));
                try regs.put(dst, .{ .ty = .ptr, .bits = addr });
            },
            .borrow => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const mode = if (base.operands[2] == .text) base.operands[2].text else "";
                _ = mode;
                const basev = try readValue(self, &regs, src);
                const ptrv = try self.coerce(basev, .ptr);
                try regs.put(dst, .{
                    .ty = .ptr,
                    .bits = ptrv.bits,
                    .interior_ptr = ptrv.interior_ptr,
                    .const_name = ptrv.const_name,
                    .vtable_slot_name = ptrv.vtable_slot_name,
                    .call_target_name = ptrv.call_target_name,
                });
            },
            .stack_alloc => {
                const dst = base.operands[0].reg;
                const size = try self.resolveSizeOperand(&regs, base.operands[1]);
                const addr = try self.memory.alloc(@intCast(size));
                try regs.put(dst, .{ .ty = .ptr, .bits = addr });
                try stack_allocs.append(addr);
            },
            .load, .take => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const off = switch (base.operands[2]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                    else => return RunError.InvalidOperand,
                };
                const ty: sig.PrimType = if (base.operands[3] == .ty) blk: {
                    break :blk sig.primTypeFromTag(base.operands[3].ty) orelse {
                        if (base.kind == .take) break :blk .ptr;
                        break :blk .i64;
                    };
                } else if (base.kind == .take) .ptr else .i64;
                const srcv = try readValue(self, &regs, src);
                const addr = srcv.bits + off;
                const loaded = try self.loadFromMemory(addr, ty);
                const source_meta = self.memory.ptrMetaAt(addr, @intCast(sig.primTypeBytes(ty)));
                const block_meta = self.memory.blockMeta(addr);
                const selected_meta = source_meta orelse block_meta;
                const src_is_borrowed = srcv.borrow_view or srcv.ffi_borrow or srcv.interior_ptr;
                try regs.put(dst, .{
                    .ty = loaded.ty,
                    .bits = loaded.bits,
                    .fallible = loaded.fallible,
                    .status = loaded.status,
                    .interior_ptr = loaded.interior_ptr or
                        (selected_meta != null and selected_meta.?.interior_ptr) or
                        (loaded.ty == .ptr and src_is_borrowed),
                    .const_name = if (selected_meta) |m| m.const_name else null,
                    .vtable_slot_name = if (selected_meta) |m| m.vtable_slot_name else null,
                    .call_target_name = if (selected_meta) |m| m.call_target_name else null,
                });
            },
            .store => {
                const base_reg = base.operands[0].reg;
                const off = switch (base.operands[1]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                    else => return RunError.InvalidOperand,
                };
                const basev = try readValue(self, &regs, base_reg);
                const ty: sig.PrimType = if (base.operands[3] == .ty) blk: {
                    break :blk sig.primTypeFromTag(base.operands[3].ty) orelse .i64;
                } else if (base.operands[2] == .reg) (try readValue(self, &regs, base.operands[2].reg)).ty else .i64;
                const value = try resolveOperandValue(self, range, &regs, base.operands[2]);
                const coerced = try self.coerce(value, ty);
                try self.storeToMemory(basev.bits + off, coerced, ty);
                // When storing a ptr value into another allocation, mark the
                // source register as interior_ptr so that a subsequent `!`
                // does not physically free the transferred pointer.
                if (ty == .ptr and base.operands[2] == .reg) {
                    if (regs.getPtr(base.operands[2].reg)) |entry| {
                        entry.interior_ptr = true;
                    }
                }
            },
            .atomic_load => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const off = switch (base.operands[2]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                    else => return RunError.InvalidOperand,
                };
                const srcv = try readValue(self, &regs, src);
                const ty = atomicValueType(base, .i64);
                const loaded = try self.loadFromMemory(srcv.bits + off, ty);
                try regs.put(dst, loaded);
            },
            .atomic_store => {
                const base_reg = base.operands[0].reg;
                const off = switch (base.operands[1]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                    else => return RunError.InvalidOperand,
                };
                const basev = try readValue(self, &regs, base_reg);
                const ty = atomicValueType(base, .i64);
                const value = try resolveOperandValue(self, range, &regs, base.operands[2]);
                const coerced = try self.coerce(value, ty);
                try self.storeToMemory(basev.bits + off, coerced, ty);
            },
            .cmpxchg => {
                const dst = base.operands[0].reg;
                const ok = base.operands[1].reg;
                const src = base.operands[2].reg;
                const off = switch (base.operands[3]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                    else => return RunError.InvalidOperand,
                };
                const basev = try readValue(self, &regs, src);
                const ty = atomicValueType(base, .i64);
                const expected_text = base.atomic_expected_text orelse return RunError.InvalidOperand;
                const new_text = base.atomic_new_text orelse return RunError.InvalidOperand;
                const expected_value = try resolveOperandValue(self, range, &regs, .{ .text = expected_text });
                const new_value = try resolveOperandValue(self, range, &regs, .{ .text = new_text });
                const expected = try self.coerce(expected_value, ty);
                const new_coerced = try self.coerce(new_value, ty);
                const current = try self.loadFromMemory(basev.bits + off, ty);
                const success = current.bits == expected.bits;
                if (success) {
                    try self.storeToMemory(basev.bits + off, new_coerced, ty);
                }
                try regs.put(dst, current);
                try regs.put(ok, .{ .ty = .i1, .bits = if (success) 1 else 0 });
            },
            .atomic_rmw => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const off = switch (base.operands[2]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                    else => return RunError.InvalidOperand,
                };
                const basev = try readValue(self, &regs, src);
                const ty = atomicValueType(base, .i64);
                const value = try resolveOperandValue(self, range, &regs, base.operands[3]);
                const coerced = try self.coerce(value, ty);
                const current = try self.loadFromMemory(basev.bits + off, ty);
                const updated = try atomicRmwApply(base.atomic_rmw_op orelse return RunError.InvalidOperand, current, coerced);
                try self.storeToMemory(basev.bits + off, updated, ty);
                try regs.put(dst, current);
            },
            .fence => {},
            .op => {
                const dst = base.operands[0].reg;
                const op = base.op_kind orelse return RunError.InvalidInstruction;
                const result = try switch (op) {
                    .neg, .not, .fneg => blk: {
                        const value = try resolveOperandValue(self, range, &regs, base.operands[1]);
                        break :blk self.opUnary(op, value, null);
                    },
                    .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => blk: {
                        const value = try resolveOperandValue(self, range, &regs, base.operands[1]);
                        const target = if (base.operands[2] == .ty) sig.primTypeFromTag(base.operands[2].ty) else null;
                        break :blk self.opUnary(op, value, target);
                    },
                    .extract_lane => blk: {
                        const value = try resolveOperandValue(self, range, &regs, base.operands[1]);
                        const lane = try resolveOperandValue(self, range, &regs, base.operands[2]);
                        _ = value;
                        _ = lane;
                        break :blk RunError.UnsupportedInstruction;
                    },
                    .shuffle_v128, .insert_lane, .add_v128, .sub_v128, .mul_v128 => RunError.UnsupportedInstruction,
                    else => blk: {
                        const lhs = try resolveOperandValue(self, range, &regs, base.operands[1]);
                        const rhs = try resolveOperandValue(self, range, &regs, base.operands[2]);
                        break :blk self.opBinary(op, lhs, rhs);
                    },
                };
                try regs.put(dst, result);
            },
            .ptr_add => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const basev = try readValue(self, &regs, src);
                const ptrv = try self.coerce(basev, .ptr);
                const offset = try resolveOperandValue(self, range, &regs, base.operands[2]);
                const delta = @as(u64, @bitCast(intValueAsOffset(offset)));
                try regs.put(dst, .{
                    .ty = .ptr,
                    .bits = ptrv.bits +% delta,
                    .interior_ptr = true,
                    .const_name = ptrv.const_name,
                });
            },
            .raw_cast => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const value = try readValue(self, &regs, src);
                try regs.put(dst, .{
                    .ty = .u64,
                    .bits = value.bits,
                    .const_name = value.const_name,
                    .interior_ptr = value.interior_ptr,
                });
            },
            .assume_safe, .assume_borrow => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const value = try readValue(self, &regs, src);
                try regs.put(dst, .{
                    .ty = .ptr,
                    .bits = value.bits,
                    .interior_ptr = value.interior_ptr,
                    .const_name = value.const_name,
                });
            },
            .assign => {
                const dst = base.operands[0].reg;
                const value = try resolveOperandValue(self, range, &regs, base.operands[1]);
                try regs.put(dst, value);
            },
            .move_ => {
                // Referee already enforced ownership semantics.
            },
            .transfer => {
                // Ownership-transfer annotation: the preceding `store`
                // already moved the bytes; the Referee consumed the fact.
                // No interpreter-side effect.
            },
            .release => {
                const reg_id = base.operands[0].reg;
                if (regs.get(reg_id)) |value| {
                    if (value.borrow_view or value.ffi_borrow) {
                        // Borrow views do not physically free.
                    } else {
                        if (value.interior_ptr or value.const_name != null) {
                            // Interior pointers are derived views into an allocation.
                        } else {
                            var is_stack_alloc = false;
                            for (stack_allocs.items) |addr| {
                                if (addr == value.bits) {
                                    is_stack_alloc = true;
                                    break;
                                }
                            }
                            if (!is_stack_alloc and value.ty == .ptr and value.bits != 0) {
                                try self.memory.free(value.bits);
                            }
                        }
                    }
                }
            },
            .jmp => {
                const label_id = base.operands[1].label;
                pc = range.labels.get(label_id) orelse return RunError.InvalidInstruction;
                continue;
            },
            .br => {
                const cond = try readValue(self, &regs, base.operands[0].reg);
                const jump = cond.bits != 0;
                const label_id = if (jump) base.operands[1].label else base.operands[3].label;
                pc = range.labels.get(label_id) orelse return RunError.InvalidInstruction;
                continue;
            },
            .br_null => {
                const cond = try readValue(self, &regs, base.operands[0].reg);
                const jump = cond.bits == 0;
                const label_id = if (jump) base.operands[1].label else base.operands[3].label;
                pc = range.labels.get(label_id) orelse return RunError.InvalidInstruction;
                continue;
            },
            .call, .call_indirect, .panic, .panic_msg => call_case: {
                const lookup = FunctionSymbolLookup{ .symbols = &self.program.symbols, .fsig = &fsig };
                var parsed = call.parseInstructionCall(self.allocator, base, lookup) catch return RunError.InvalidOperand;
                defer parsed.deinit(self.allocator);

                if (parsed.is_indirect) {
                    const callee_id = self.program.symbols.findId(parsed.callee) orelse return RunError.UnknownFunction;
                    const callee = if (range.slotOf(callee_id)) |slot|
                        try readRawValue(self, &regs, slot)
                    else
                        self.constPointerValue(callee_id) orelse return RunError.UnknownFunction;
                    if (callee.ty != .ptr) return RunError.MissingIndirectCallProvenance;
                    const target_name = blk: {
                        if (callee.call_target_name) |name| break :blk name;
                        if (callee.vtable_slot_name) |name| break :blk name;
                        const callee_meta = self.memory.ptrMetaAt(callee.bits, @sizeOf(u64)) orelse self.memory.blockMeta(callee.bits);
                        if (callee_meta) |meta| {
                            if (meta.call_target_name) |name| break :blk name;
                            if (meta.vtable_slot_name) |name| break :blk name;
                        }
                        break :blk null;
                    } orelse return RunError.MissingIndirectCallProvenance;
                    const callee_index = self.findFunctionIndex(target_name) orelse return RunError.UnknownFunction;
                    const target_sig = self.program.function_sigs[callee_index];
                    if (target_sig.is_variadic) return RunError.UnsupportedVariadic;
                    if (parsed.args.len != target_sig.params.len) return RunError.InvalidOperand;
                    const args = try self.collectArgs(range, parsed, &regs, target_sig.params);
                    defer self.allocator.free(args);
                    const ret = try self.execFunction(callee_index, args);
                    if (parsed.dest) |dest| {
                        if (self.program.symbols.findId(dest)) |id| {
                            const slot = range.slotOf(id) orelse return RunError.InvalidOperand;
                            try regs.put(slot, ret);
                        }
                    }
                    break :call_case;
                }

                const call_values = try self.collectCallValues(range, parsed, &regs);
                defer self.allocator.free(call_values);

                switch (try self.handleSysCall(parsed.callee, call_values)) {
                    .handled => |ret_or_null| {
                        if (ret_or_null) |ret| {
                            if (parsed.dest) |dest| {
                                if (self.program.symbols.findId(dest)) |id| {
                                    const slot = range.slotOf(id) orelse return RunError.InvalidOperand;
                                    try regs.put(slot, ret);
                                }
                            }
                        }
                    },
                    .not_syscall => {
                        const callee_sig_index = self.findFunctionIndex(parsed.callee) orelse return RunError.UnknownFunction;
                        const callee_sig = self.program.function_sigs[callee_sig_index];
                        if (callee_sig.is_variadic) return RunError.UnsupportedVariadic;
                        const args = try self.collectArgs(range, parsed, &regs, callee_sig.params);
                        defer self.allocator.free(args);
                        const ret = try self.execFunction(callee_sig_index, args);
                        if (parsed.dest) |dest| {
                            if (self.program.symbols.findId(dest)) |id| {
                                const slot = range.slotOf(id) orelse return RunError.InvalidOperand;
                                try regs.put(slot, ret);
                            }
                        }
                    },
                }
            },
            .try_, .early_return => {
                const dst = base.operands[0].reg;
                const src = base.operands[1].reg;
                const value = try readRawValue(self, &regs, src);
                if (!value.fallible) return RunError.InvalidOperand;
                if (value.status != 0) {
                    return value;
                }
                var success = unpackSuccess(value);
                success.from_try = true;
                try regs.put(dst, success);
            },
            .return_ => {
                if (base.operands[0] == .none) {
                    if (fsig.return_fallible) return RunError.InvalidOperand;
                    return .{ .ty = .void, .bits = 0 };
                }
                if (fsig.return_fallible) {
                    const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
                    if (ret_ty == .void) return RunError.InvalidOperand;
                    const value = try resolveOperandValue(self, range, &regs, base.operands[0]);
                    if (value.fallible) return value;
                    const coerced = try self.coerce(value, ret_ty);
                    var ret_value = packFallible(0, coerced);
                    ret_value.from_try = value.from_try;
                    return ret_value;
                }
                const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
                if (ret_ty == .void) {
                    return .{ .ty = .void, .bits = 0 };
                }
                const value = try resolveOperandValue(self, range, &regs, base.operands[0]);
                return try self.coerce(value, ret_ty);
            },
            .va_start, .va_arg, .va_end => {
                // Extern variadic batch: the interpreter has no
                // va_list model; fail loudly instead of skipping.
                return RunError.UnsupportedVariadic;
            },
            .native => {
                // Native escape is not supported by the interpreter.
                return RunError.UnsupportedInstruction;
            },
            else => return RunError.UnsupportedInstruction,
        }
        pc += 1;
    }

    if (fsig.return_ty == .void) return .{ .ty = .void, .bits = 0 };
    return RunError.InvalidInstruction;
}
pub fn collectCallValuesImpl(self: *Interpreter, range: *const FunctionRange, parsed: call.ParsedCall, regs: *FrameRegs) ![]RegValue {
    const out = try self.allocator.alloc(RegValue, parsed.args.len);
    errdefer self.allocator.free(out);
    for (parsed.args, 0..) |arg, idx| {
        out[idx] = self.callArgValue(range, regs, arg) catch |err| {
            self.stderr.print("interp call arg parse failed in {s}: {s} ({})\n", .{ parsed.callee, arg.text, err }) catch |print_err| {
                // The parse error is returned below; stderr output is extra context only.
                _ = @errorName(print_err);
            };
            return err;
        };
    }
    return out;
}
pub fn collectArgsImpl(self: *Interpreter, range: *const FunctionRange, parsed: call.ParsedCall, regs: *FrameRegs, params: []const sig.ParamSpec) ![]RegValue {
    if (parsed.args.len != params.len) return RunError.InvalidOperand;
    const out = try self.allocator.alloc(RegValue, parsed.args.len);
    errdefer self.allocator.free(out);
    for (parsed.args, params, 0..) |arg, param, idx| {
        const raw = self.callArgValue(range, regs, arg) catch |err| {
            self.stderr.print("interp indirect arg parse failed in {s}: {s} ({})\n", .{ parsed.callee, arg.text, err }) catch |print_err| {
                // The parse error is returned below; stderr output is extra context only.
                _ = @errorName(print_err);
            };
            return err;
        };
        const coerced = try self.coerce(raw, valueTypeForPrefix(param.cap, param.ty));
        out[idx] = .{
            .ty = coerced.ty,
            .bits = coerced.bits,
            .fallible = coerced.fallible,
            .status = coerced.status,
            .interior_ptr = coerced.interior_ptr or raw.interior_ptr,
            .borrow_view = raw.borrow_view or arg.prefix == .borrow,
            .ffi_borrow = raw.ffi_borrow or arg.prefix == .raw,
            .extern_handle = coerced.extern_handle or raw.extern_handle,
            .from_try = coerced.from_try,
            .const_name = coerced.const_name,
            .vtable_slot_name = coerced.vtable_slot_name,
            .call_target_name = coerced.call_target_name,
        };
    }
    return out;
}

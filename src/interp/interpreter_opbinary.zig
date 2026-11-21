const std = @import("std");
const call = @import("../referee/call.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const sio = @import("sio");
const floatValue = @import("interpreter_init.zig").floatValueImpl;
const intValue = @import("interpreter_init.zig").intValueImpl;
const intValueAsOffset = @import("interpreter_init.zig").intValueAsOffsetImpl;
const isFloatLike = @import("interpreter_init.zig").isFloatLikeImpl;
const isIntLike = @import("interpreter_init.zig").isIntLikeImpl;
const isSignedInt = @import("interpreter_init.zig").isSignedIntImpl;
const numKind = @import("interpreter_init.zig").numKindImpl;
const valueFromFloat = @import("interpreter_init.zig").valueFromFloatImpl;
const valueFromInt = @import("interpreter_init.zig").valueFromIntImpl;
const FrameRegs = @import("memory.zig").FrameRegs;
const FunctionRange = @import("memory.zig").FunctionRange;
const Interpreter = @import("interpreter.zig").Interpreter;
const Memory = @import("memory.zig").Memory;
const RegValue = @import("memory.zig").RegValue;
const RunError = @import("memory.zig").RunError;
const SA_STD_ERR_INVALID_ARGUMENT = @import("memory.zig").SA_STD_ERR_INVALID_ARGUMENT;
const SA_STD_ERR_IO = @import("memory.zig").SA_STD_ERR_IO;
const SA_STD_ERR_PERMISSION_DENIED = @import("memory.zig").SA_STD_ERR_PERMISSION_DENIED;
const SA_STD_ERR_UNKNOWN = @import("memory.zig").SA_STD_ERR_UNKNOWN;
const SA_STD_ERR_UNSUPPORTED = @import("memory.zig").SA_STD_ERR_UNSUPPORTED;
const SA_STD_OK = @import("memory.zig").SA_STD_OK;
const SysCallOutcome = @import("memory.zig").SysCallOutcome;
const TimeDate = @import("memory.zig").TimeDate;
const isIdentLike = @import("memory.zig").isIdentLike;
const isRawQuotedStringArg = @import("memory.zig").isRawQuotedStringArg;
const makeFallibleI32 = @import("memory.zig").makeFallibleI32;
const materializeConstValue = @import("memory.zig").materializeConstValue;
const policyGateAllows = @import("installpolicyfromenv.zig").policyGateAllows;
const readValue = @import("memory.zig").readValue;
const stripTextOperandPrefix = @import("memory.zig").stripTextOperandPrefix;
const valueTypeForPrefix = @import("memory.zig").valueTypeForPrefix;

pub fn opBinaryImpl(self: *Interpreter, op: inst.OpKind, a: RegValue, b: RegValue) !RegValue {
    _ = self;
    if (a.fallible or b.fallible) return RunError.InvalidOperand;
    if (a.ty == .v128 or b.ty == .v128) return RunError.UnsupportedInstruction;

    if (op == .add or op == .sub) {
        if (a.ty == .ptr or b.ty == .ptr) {
            if (a.ty == .ptr and b.ty == .ptr) return RunError.InvalidOperand;
            if (op == .sub and b.ty == .ptr) return RunError.InvalidOperand;
            const ptr = if (a.ty == .ptr) a else b;
            const offset = if (a.ty == .ptr) b else a;
            if (!isIntLike(offset.ty)) return RunError.InvalidOperand;
            const delta = @as(u64, @bitCast(intValueAsOffset(offset)));
            return switch (op) {
                .add => .{ .ty = .ptr, .bits = ptr.bits +% delta, .interior_ptr = true },
                .sub => .{ .ty = .ptr, .bits = ptr.bits -% delta, .interior_ptr = true },
                else => RunError.InvalidOperand,
            };
        }
    }

    const kind = switch (op) {
        .fadd, .fsub, .fmul, .fdiv => .float,
        .lshr => .unsigned,
        .ashr => .signed,
        .sdiv, .srem, .sgt, .slt, .sge, .sle => .signed,
        .udiv, .urem, .ugt, .ult, .uge, .ule => .unsigned,
        else => numKind(a, b),
    };
    const lhs_signed = intValue(a, true);
    const rhs_signed = intValue(b, true);
    const lhs_unsigned: u128 = @as(u128, @intCast(intValue(a, false)));
    const rhs_unsigned: u128 = @as(u128, @intCast(intValue(b, false)));

    switch (op) {
        .add, .fadd => return switch (kind) {
            .float => try valueFromFloat(.f64, floatValue(a) + floatValue(b)),
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed + rhs_signed))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned + rhs_unsigned)) },
        },
        .sub, .fsub => return switch (kind) {
            .float => try valueFromFloat(.f64, floatValue(a) - floatValue(b)),
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed - rhs_signed))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned - rhs_unsigned)) },
        },
        .mul, .fmul => return switch (kind) {
            .float => try valueFromFloat(.f64, floatValue(a) * floatValue(b)),
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed * rhs_signed))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned * rhs_unsigned)) },
        },
        .div, .fdiv => return switch (kind) {
            .float => try valueFromFloat(.f64, floatValue(a) / floatValue(b)),
            .signed => blk: {
                if (rhs_signed == 0) return RunError.DivByZero;
                break :blk try valueFromInt(.i64, @as(i64, @intCast(@divTrunc(lhs_signed, rhs_signed))));
            },
            .unsigned => blk: {
                if (rhs_unsigned == 0) return RunError.DivByZero;
                break :blk .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned / rhs_unsigned)) };
            },
        },
        .rem => return switch (kind) {
            .float => RunError.InvalidOperand,
            .signed => blk: {
                if (rhs_signed == 0) return RunError.DivByZero;
                break :blk try valueFromInt(.i64, @as(i64, @intCast(@rem(lhs_signed, rhs_signed))));
            },
            .unsigned => blk: {
                if (rhs_unsigned == 0) return RunError.DivByZero;
                break :blk .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned % rhs_unsigned)) };
            },
        },
        .sdiv => {
            if (kind == .float) return RunError.InvalidOperand;
            if (rhs_signed == 0) return RunError.DivByZero;
            return try valueFromInt(.i64, @as(i64, @intCast(@divTrunc(lhs_signed, rhs_signed))));
        },
        .udiv => {
            if (kind == .float) return RunError.InvalidOperand;
            if (rhs_unsigned == 0) return RunError.DivByZero;
            return .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned / rhs_unsigned)) };
        },
        .srem => {
            if (kind == .float) return RunError.InvalidOperand;
            if (rhs_signed == 0) return RunError.DivByZero;
            return try valueFromInt(.i64, @as(i64, @intCast(@rem(lhs_signed, rhs_signed))));
        },
        .urem => {
            if (kind == .float) return RunError.InvalidOperand;
            if (rhs_unsigned == 0) return RunError.DivByZero;
            return .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned % rhs_unsigned)) };
        },
        .eq, .ne, .gt, .lt => {
            return switch (kind) {
                .float => blk: {
                    const lhs = floatValue(a);
                    const rhs = floatValue(b);
                    const result = switch (op) {
                        .gt => lhs > rhs,
                        .lt => lhs < rhs,
                        .eq => lhs == rhs,
                        .ne => lhs != rhs,
                        else => unreachable,
                    };
                    break :blk try valueFromInt(.i1, @intFromBool(result));
                },
                .signed => blk: {
                    const result = switch (op) {
                        .gt => lhs_signed > rhs_signed,
                        .lt => lhs_signed < rhs_signed,
                        .eq => lhs_signed == rhs_signed,
                        .ne => lhs_signed != rhs_signed,
                        else => unreachable,
                    };
                    break :blk try valueFromInt(.i1, @intFromBool(result));
                },
                .unsigned => blk: {
                    const result = switch (op) {
                        .gt => lhs_unsigned > rhs_unsigned,
                        .lt => lhs_unsigned < rhs_unsigned,
                        .eq => lhs_unsigned == rhs_unsigned,
                        .ne => lhs_unsigned != rhs_unsigned,
                        else => unreachable,
                    };
                    break :blk try valueFromInt(.i1, @intFromBool(result));
                },
            };
        },
        .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => {
            if (!isFloatLike(a.ty) and !isFloatLike(b.ty)) return RunError.InvalidOperand;
            const lhs = floatValue(a);
            const rhs = floatValue(b);
            const result = switch (op) {
                .fcmp_eq => lhs == rhs,
                .fcmp_ne => lhs != rhs,
                .fcmp_lt => lhs < rhs,
                .fcmp_le => lhs <= rhs,
                .fcmp_gt => lhs > rhs,
                .fcmp_ge => lhs >= rhs,
                else => unreachable,
            };
            return try valueFromInt(.i1, @intFromBool(result));
        },
        .sgt, .slt, .sge, .sle => {
            if (kind == .float) return RunError.InvalidOperand;
            const result = switch (op) {
                .sgt => lhs_signed > rhs_signed,
                .slt => lhs_signed < rhs_signed,
                .sge => lhs_signed >= rhs_signed,
                .sle => lhs_signed <= rhs_signed,
                else => unreachable,
            };
            return try valueFromInt(.i1, @intFromBool(result));
        },
        .ugt, .ult, .uge, .ule => {
            if (kind == .float) return RunError.InvalidOperand;
            const result = switch (op) {
                .ugt => lhs_unsigned > rhs_unsigned,
                .ult => lhs_unsigned < rhs_unsigned,
                .uge => lhs_unsigned >= rhs_unsigned,
                .ule => lhs_unsigned <= rhs_unsigned,
                else => unreachable,
            };
            return try valueFromInt(.i1, @intFromBool(result));
        },
        .@"and" => return switch (kind) {
            .float => RunError.InvalidOperand,
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed & rhs_signed))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned & rhs_unsigned)) },
        },
        .@"or" => return switch (kind) {
            .float => RunError.InvalidOperand,
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed | rhs_signed))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned | rhs_unsigned)) },
        },
        .xor => return switch (kind) {
            .float => RunError.InvalidOperand,
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed ^ rhs_signed))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned ^ rhs_unsigned)) },
        },
        .shl => return switch (kind) {
            .float => RunError.InvalidOperand,
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed << @as(u6, @intCast(rhs_unsigned & 0x3f))))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned << @as(u6, @intCast(rhs_unsigned & 0x3f)))) },
        },
        .lshr => {
            if (kind == .float) return RunError.InvalidOperand;
            return .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned >> @as(u6, @intCast(rhs_unsigned & 0x3f)))) };
        },
        .ashr => {
            if (kind == .float) return RunError.InvalidOperand;
            return try valueFromInt(.i64, @as(i64, @intCast(lhs_signed >> @as(u6, @intCast(rhs_unsigned & 0x3f)))));
        },
        .shr => return switch (kind) {
            .float => RunError.InvalidOperand,
            .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed >> @as(u6, @intCast(rhs_unsigned & 0x3f))))),
            .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned >> @as(u6, @intCast(rhs_unsigned & 0x3f)))) },
        },
        .fptosi, .sitofp, .uitofp, .trunc, .zext, .sext, .fptrunc, .fpext, .bitcast, .neg, .not, .fneg, .add_v128, .sub_v128, .mul_v128, .shuffle_v128, .extract_lane, .insert_lane => return RunError.UnsupportedInstruction,
    }
}
pub fn findFunctionIndexImpl(self: *Interpreter, name: []const u8) ?usize {
    return self.function_index_by_name.get(name);
}
pub fn resolveTextOperandImpl(self: *Interpreter, range: *const FunctionRange, regs: *FrameRegs, text: []const u8) !RegValue {
    const candidate = stripTextOperandPrefix(text);
    if (candidate.len == 0) return RunError.InvalidOperand;
    if (isIdentLike(candidate)) {
        if (self.program.symbols.findId(candidate)) |id| {
            if (range.slotOf(id)) |slot| {
                return readValue(self, regs, slot);
            }
            return self.constPointerValue(id) orelse RunError.InvalidOperand;
        }
        if (self.findFunctionIndex(candidate)) |idx| {
            return .{ .ty = .ptr, .bits = 0, .call_target_name = self.program.function_sigs[idx].name };
        }
    }
    return try Interpreter.parseImmediateValue(self.allocator, &self.memory, candidate);
}
pub fn callArgValueImpl(self: *Interpreter, range: *const FunctionRange, regs: *FrameRegs, arg: call.ParsedArg) !RegValue {
    if (isRawQuotedStringArg(arg)) {
        const addr = self.anon_const_addrs.get(arg.text) orelse return RunError.InvalidOperand;
        return .{ .ty = .ptr, .bits = addr };
    }
    if (arg.prefix == .raw and arg.text.len >= 2 and arg.text[0] == '"' and arg.text[arg.text.len - 1] == '"') {
        return RunError.InvalidOperand;
    }
    return try self.resolveTextOperand(range, regs, arg.text);
}
pub fn resolveSizeOperandImpl(self: *Interpreter, regs: *FrameRegs, operand: inst.Operand) !u64 {
    return switch (operand) {
        .imm_u64 => |v| v,
        .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
        .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
        .text => |text| try std.fmt.parseInt(u64, std.mem.trim(u8, text, " \t"), 10),
        .reg => |id| blk: {
            const value = try readValue(self, regs, id);
            if (!isIntLike(value.ty)) return RunError.InvalidOperand;
            if (isSignedInt(value.ty)) {
                const signed = intValue(value, true);
                break :blk if (signed > 0) @as(u64, @intCast(signed)) else 0;
            }
            break :blk @as(u64, @intCast(intValue(value, false)));
        },
        else => RunError.InvalidOperand,
    };
}
pub fn materializeConstsImpl(self: *Interpreter) !void {
    for (self.program.const_decls) |decl| {
        const bytes = try materializeConstValue(self.allocator, decl.value);
        defer self.allocator.free(bytes);
        var slot_names: []?[]const u8 = &.{};
        if (decl.value == .vtable) {
            const slots = decl.value.vtable.slots;
            slot_names = try self.allocator.alloc(?[]const u8, slots.len);
            errdefer self.allocator.free(slot_names);
            for (slots, 0..) |slot, idx| {
                slot_names[idx] = slot.func_name;
            }
        }
        const addr = try self.memory.allocConst(bytes.len, decl.name, slot_names);
        if (slot_names.len != 0) self.allocator.free(slot_names);
        const dst = try self.memory.sliceAt(addr, bytes.len);
        @memcpy(dst, bytes);
        if (decl.value == .vtable) {
            const slots = decl.value.vtable.slots;
            for (slots, 0..) |slot, idx| {
                const slot_addr = addr + @as(u64, @intCast(idx * @sizeOf(u64)));
                try self.memory.writePtrMeta(slot_addr, @sizeOf(u64), .{
                    .const_name = decl.name,
                    .vtable_slot_name = slot.name,
                    .call_target_name = slot.func_name,
                    .interior_ptr = false,
                });
            }
        }
        try self.const_addrs.put(decl.name, addr);
    }
}
pub fn decodeBinaryValueImpl(self: *Interpreter, ty: sig.PrimType, bytes: []const u8) !RegValue {
    _ = self;
    return switch (ty) {
        .void => RunError.InvalidOperand,
        .i1 => blk: {
            if (bytes.len != 1) return RunError.InvalidOperand;
            break :blk .{ .ty = .i1, .bits = @as(u64, bytes[0] & 1) };
        },
        .i8 => blk: {
            if (bytes.len != 1) return RunError.InvalidOperand;
            const buf: *const [1]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.i8, @as(i128, std.mem.readInt(i8, buf, .little)));
        },
        .u8 => blk: {
            if (bytes.len != 1) return RunError.InvalidOperand;
            const buf: *const [1]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.u8, @as(i128, std.mem.readInt(u8, buf, .little)));
        },
        .i16 => blk: {
            if (bytes.len != 2) return RunError.InvalidOperand;
            const buf: *const [2]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.i16, @as(i128, std.mem.readInt(i16, buf, .little)));
        },
        .u16 => blk: {
            if (bytes.len != 2) return RunError.InvalidOperand;
            const buf: *const [2]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.u16, @as(i128, std.mem.readInt(u16, buf, .little)));
        },
        .i32 => blk: {
            if (bytes.len != 4) return RunError.InvalidOperand;
            const buf: *const [4]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.i32, @as(i128, std.mem.readInt(i32, buf, .little)));
        },
        .u32 => blk: {
            if (bytes.len != 4) return RunError.InvalidOperand;
            const buf: *const [4]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.u32, @as(i128, std.mem.readInt(u32, buf, .little)));
        },
        .i64 => blk: {
            if (bytes.len != 8) return RunError.InvalidOperand;
            const buf: *const [8]u8 = @ptrCast(bytes.ptr);
            break :blk try valueFromInt(.i64, @as(i128, std.mem.readInt(i64, buf, .little)));
        },
        .u64, .ptr, .blob_handle => blk: {
            if (bytes.len != 8) return RunError.InvalidOperand;
            const buf: *const [8]u8 = @ptrCast(bytes.ptr);
            const raw = std.mem.readInt(u64, buf, .little);
            break :blk .{ .ty = ty, .bits = raw };
        },
        .f32 => blk: {
            if (bytes.len != 4) return RunError.InvalidOperand;
            const buf: *const [4]u8 = @ptrCast(bytes.ptr);
            const raw = std.mem.readInt(u32, buf, .little);
            break :blk .{ .ty = .f32, .bits = @as(u64, raw) };
        },
        .f64 => blk: {
            if (bytes.len != 8) return RunError.InvalidOperand;
            const buf: *const [8]u8 = @ptrCast(bytes.ptr);
            break :blk .{ .ty = .f64, .bits = std.mem.readInt(u64, buf, .little) };
        },
        .v128 => RunError.UnsupportedInstruction,
    };
}
pub fn decodeBinaryArgsImpl(self: *Interpreter, sig_index: usize, arg_blob: []const u8) ![]RegValue {
    const fsig = self.program.function_sigs[sig_index];
    var offset: usize = 0;
    const out = try self.allocator.alloc(RegValue, fsig.params.len);
    errdefer self.allocator.free(out);
    for (fsig.params, 0..) |param, idx| {
        const target_ty = valueTypeForPrefix(param.cap, param.ty);
        const width = @as(usize, @intCast(sig.primTypeBytes(target_ty)));
        if (offset + width > arg_blob.len) return RunError.InvalidOperand;
        out[idx] = try self.decodeBinaryValue(target_ty, arg_blob[offset .. offset + width]);
        offset += width;
    }
    if (offset != arg_blob.len) return RunError.InvalidOperand;
    return out;
}
pub fn parseImmediateValueImpl(allocator: std.mem.Allocator, mem: *Memory, text: []const u8) !RegValue {
    _ = allocator;
    _ = mem;
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) {
        std.debug.print("interp.parseImmediateValue empty input\n", .{});
        return RunError.InvalidOperand;
    }
    if (std.mem.indexOfScalar(u8, trimmed, '.') != null) {
        const value = try std.fmt.parseFloat(f64, trimmed);
        return .{ .ty = .f64, .bits = @bitCast(value) };
    }
    const value = try std.fmt.parseInt(i64, trimmed, 10);
    return .{ .ty = .i64, .bits = @as(u64, @bitCast(value)) };
}
pub fn recordPanicImpl(self: *Interpreter, code: u8, message: ?[]const u8) void {
    self.exit_code = @as(u8, @intCast(128 + (@as(u32, code) & 0x7f)));
    if (message) |msg| {
        self.stderr.print("PANIC[{d}]: {s}\n", .{ code, msg }) catch |err| {
            // Panic recording must not fail just because diagnostic output is unavailable.
            _ = @errorName(err);
        };
    } else {
        self.stderr.print("PANIC: code={d}\n", .{code}) catch |err| {
            // Panic recording must not fail just because diagnostic output is unavailable.
            _ = @errorName(err);
        };
    }
}
pub fn printBytesImpl(self: *Interpreter, ptr: u64, len: usize) !void {
    if (len == 0) return;
    const slice = try self.memory.sliceAt(ptr, len);
    try self.stdout.writeAll(slice);
}
pub fn monotonicNowNsImpl(self: *Interpreter) !u64 {
    _ = self;
    // NOTE(Zig 0.17): `std.time.Instant` is gone; `Clock.awake` is the
    // monotonic clock ("will not go backwards"). Return the raw
    // reading, matching the native runtime: 0 means clock failure,
    // never a legitimate first reading (the previous
    // origin-relative form returned exactly 0 to the first caller
    // of every interpreter session).
    const now_ns: i128 = std.Io.Clock.awake.now(sio.io()).toNanoseconds();
    if (now_ns <= 0) return 0;
    if (now_ns > std.math.maxInt(u64)) return std.math.maxInt(u64);
    return @intCast(now_ns);
}
pub fn writeUtcNowImpl(self: *Interpreter, ptr: u64) !void {
    const out = try self.memory.sliceAt(ptr, @sizeOf(TimeDate));
    @memset(out, 0);

    const unix_ms = std.Io.Clock.real.now(sio.io()).toMilliseconds();
    const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
    if (unix_s < 0) return error.Unsupported;

    const unix_ns_raw = std.Io.Clock.real.now(sio.io()).toNanoseconds();
    const unix_ns = std.math.cast(i64, unix_ns_raw) orelse return error.Overflow;
    const epoch_seconds = std.time.epoch.EpochSeconds{ .secs = @as(u64, @intCast(unix_s)) };
    const epoch_day = epoch_seconds.getEpochDay();
    const year_day = epoch_day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch_seconds.getDaySeconds();

    const off_unix_ms = @offsetOf(TimeDate, "unix_ms");
    const off_unix_ns = @offsetOf(TimeDate, "unix_ns");
    const off_year = @offsetOf(TimeDate, "year");
    const off_month = @offsetOf(TimeDate, "month");
    const off_day = @offsetOf(TimeDate, "day");
    const off_hour = @offsetOf(TimeDate, "hour");
    const off_minute = @offsetOf(TimeDate, "minute");
    const off_second = @offsetOf(TimeDate, "second");
    const off_millisecond = @offsetOf(TimeDate, "millisecond");

    std.mem.writeInt(u64, @as(*[8]u8, @ptrCast(out[off_unix_ms..].ptr)), @as(u64, @bitCast(unix_ms)), .little);
    std.mem.writeInt(u64, @as(*[8]u8, @ptrCast(out[off_unix_ns..].ptr)), @as(u64, @bitCast(unix_ns)), .little);
    std.mem.writeInt(u16, @as(*[2]u8, @ptrCast(out[off_year..].ptr)), year_day.year, .little);
    out[off_month] = @as(u8, @intFromEnum(month_day.month));
    out[off_day] = @as(u8, @intCast(month_day.day_index + 1));
    out[off_hour] = day_seconds.getHoursIntoDay();
    out[off_minute] = day_seconds.getMinutesIntoHour();
    out[off_second] = day_seconds.getSecondsIntoMinute();
    std.mem.writeInt(u16, @as(*[2]u8, @ptrCast(out[off_millisecond..].ptr)), @as(u16, @intCast(@mod(unix_ms, std.time.ms_per_s))), .little);
}
pub fn handleSysCallImpl(
    self: *Interpreter,
    name: []const u8,
    args: []const RegValue,
) !SysCallOutcome {
    if (std.mem.eql(u8, name, "sa_mem_copy")) {
        if (args.len != 3) return RunError.InvalidOperand;
        const dst_addr = args[0].bits;
        const src_addr = args[1].bits;
        const count = @as(usize, @intCast(args[2].bits));
        if (count == 0) return .{ .handled = null };
        const src_data = try self.memory.sliceAt(src_addr, count);
        const dst_data = try self.memory.sliceAt(dst_addr, count);
        @memcpy(dst_data, src_data);
        // Also copy PtrMeta for each pointer-sized aligned chunk.
        const ptr_size = @sizeOf(u64);
        var off: usize = 0;
        while (off + ptr_size <= count) : (off += ptr_size) {
            const meta = self.memory.ptrMetaAt(src_addr + @as(u64, @intCast(off)), ptr_size);
            try self.memory.writePtrMeta(dst_addr + @as(u64, @intCast(off)), ptr_size, meta);
        }
        return .{ .handled = null };
    }
    if (std.mem.eql(u8, name, "panic")) {
        if (args.len != 1) return RunError.InvalidOperand;
        self.recordPanic(@as(u8, @truncate(args[0].bits)), null);
        return RunError.UserExit;
    }
    if (std.mem.eql(u8, name, "panic_msg")) {
        if (args.len != 3) return RunError.InvalidOperand;
        const code = @as(u8, @truncate(args[0].bits));
        const msg_ptr = args[1].bits;
        const msg_len = @as(usize, @intCast(args[2].bits));
        const message = if (msg_ptr != 0 and msg_len != 0) try self.memory.sliceAt(msg_ptr, msg_len) else null;
        self.recordPanic(code, message);
        return RunError.UserExit;
    }
    if (std.mem.eql(u8, name, "sa_print_bytes")) {
        if (args.len != 2) return RunError.InvalidOperand;
        try self.printBytes(args[0].bits, @as(usize, @intCast(args[1].bits)));
        return .{ .handled = null };
    }
    if (std.mem.eql(u8, name, "sa_std_println")) {
        if (args.len != 2) return RunError.InvalidOperand;
        const len = @as(usize, @intCast(args[1].bits));
        if (len != 0) {
            const bytes = self.memory.sliceAt(args[0].bits, len) catch |err| switch (err) {
                error.InvalidAddress => return .{ .handled = makeFallibleI32(SA_STD_ERR_INVALID_ARGUMENT) },
                else => return err,
            };
            self.stdout.writeAll(bytes) catch return .{ .handled = makeFallibleI32(SA_STD_ERR_IO) };
        }
        self.stdout.writeByte('\n') catch return .{ .handled = makeFallibleI32(SA_STD_ERR_IO) };
        return .{ .handled = makeFallibleI32(SA_STD_OK) };
    }
    if (std.mem.eql(u8, name, "sa_time_instant_ns")) {
        if (args.len != 0) return RunError.InvalidOperand;
        return .{ .handled = .{ .ty = .u64, .bits = if (policyGateAllows(self.allocator, .time)) (self.monotonicNowNs() catch 0) else 0 } };
    }
    if (std.mem.eql(u8, name, "sa_time_unix_s")) {
        if (args.len != 0) return RunError.InvalidOperand;
        return .{ .handled = .{ .ty = .i64, .bits = if (policyGateAllows(self.allocator, .time)) @as(u64, @bitCast(sio.timestampSeconds())) else 0 } };
    }
    if (std.mem.eql(u8, name, "sa_time_unix_ms")) {
        if (args.len != 0) return RunError.InvalidOperand;
        return .{ .handled = .{ .ty = .i64, .bits = if (policyGateAllows(self.allocator, .time)) @as(u64, @bitCast(std.Io.Clock.real.now(sio.io()).toMilliseconds())) else 0 } };
    }
    if (std.mem.eql(u8, name, "sa_time_unix_ns")) {
        if (args.len != 0) return RunError.InvalidOperand;
        if (!policyGateAllows(self.allocator, .time)) return .{ .handled = .{ .ty = .i64, .bits = 0 } };
        const ts = std.Io.Clock.real.now(sio.io()).toNanoseconds();
        const unix_ns = @as(i64, @intCast(ts));
        return .{ .handled = .{ .ty = .i64, .bits = @as(u64, @bitCast(unix_ns)) } };
    }
    if (std.mem.eql(u8, name, "sa_time_utc_now")) {
        if (args.len != 1) return RunError.InvalidOperand;
        if (!policyGateAllows(self.allocator, .time)) return .{ .handled = makeFallibleI32(SA_STD_ERR_PERMISSION_DENIED) };
        self.writeUtcNow(args[0].bits) catch |err| {
            const status = switch (err) {
                error.InvalidAddress => SA_STD_ERR_INVALID_ARGUMENT,
                error.Unsupported => SA_STD_ERR_UNSUPPORTED,
                error.Overflow => SA_STD_ERR_INVALID_ARGUMENT,
                else => SA_STD_ERR_UNKNOWN,
            };
            return .{ .handled = makeFallibleI32(status) };
        };
        return .{ .handled = makeFallibleI32(SA_STD_OK) };
    }
    if (std.mem.eql(u8, name, "sa_time_sleep_ns")) {
        if (args.len != 1) return RunError.InvalidOperand;
        sio.io().sleep(.fromNanoseconds(@as(i96, @intCast(args[0].bits))), .awake) catch {};
        return .{ .handled = makeFallibleI32(SA_STD_OK) };
    }
    if (std.mem.eql(u8, name, "sa_time_sleep_ms")) {
        if (args.len != 1) return RunError.InvalidOperand;
        const ns = std.math.mul(u64, args[0].bits, std.time.ns_per_ms) catch return .{ .handled = makeFallibleI32(SA_STD_ERR_INVALID_ARGUMENT) };
        sio.io().sleep(.fromNanoseconds(@as(i96, @intCast(ns))), .awake) catch {};
        return .{ .handled = makeFallibleI32(SA_STD_OK) };
    }
    if (!std.mem.startsWith(u8, name, "sys_")) return .not_syscall;

    if (std.mem.eql(u8, name, "sys_print")) {
        if (args.len != 2) return RunError.InvalidOperand;
        try self.printBytes(args[0].bits, @as(usize, @intCast(args[1].bits)));
        return .{ .handled = null };
    }
    if (std.mem.eql(u8, name, "sys_exit")) {
        if (args.len != 1) return RunError.InvalidOperand;
        self.exit_code = @as(u8, @truncate(args[0].bits));
        return RunError.UserExit;
    }
    if (std.mem.eql(u8, name, "sys_argc")) {
        if (args.len != 0) return RunError.InvalidOperand;
        return .{ .handled = .{ .ty = .i32, .bits = self.argv.len } };
    }
    if (std.mem.eql(u8, name, "sys_argv")) {
        if (args.len != 1) return RunError.InvalidOperand;
        const idx = @as(usize, @intCast(args[0].bits));
        if (idx >= self.argv.len) return .{ .handled = .{ .ty = .ptr, .bits = 0 } };
        const text = self.argv[idx];
        const addr = try self.memory.alloc(text.len + 1);
        const slice = try self.memory.sliceAt(addr, text.len + 1);
        @memcpy(slice[0..text.len], text);
        slice[text.len] = 0;
        return .{ .handled = .{ .ty = .ptr, .bits = addr } };
    }
    if (std.mem.eql(u8, name, "sys_read_file")) {
        if (args.len != 3) return RunError.InvalidOperand;
        const path = try self.memory.sliceAt(args[0].bits, @as(usize, @intCast(args[1].bits)));
        if (!policyGateAllows(self.allocator, .{ .fs = .{ .path = path, .write = false } })) {
            self.stderr.print("[sa-policy] denied fs read: {s}\n", .{path}) catch {};
            return RunError.PolicyDenied;
        }
        var file = try sio.cwd().openFile(path, .{});
        defer file.close();
        const data = try file.readToEndAlloc(self.allocator, 1 << 30);
        errdefer self.allocator.free(data);
        const addr = try self.memory.alloc(data.len);
        const buf = try self.memory.sliceAt(addr, data.len);
        @memcpy(buf, data);
        const out_len_addr = args[2].bits;
        try self.storeToMemory(out_len_addr, .{ .ty = .u64, .bits = data.len }, .u64);
        self.allocator.free(data);
        return .{ .handled = .{ .ty = .ptr, .bits = addr } };
    }
    if (std.mem.eql(u8, name, "sys_write_file")) {
        if (args.len != 4) return RunError.InvalidOperand;
        const path = try self.memory.sliceAt(args[0].bits, @as(usize, @intCast(args[1].bits)));
        const data = try self.memory.sliceAt(args[2].bits, @as(usize, @intCast(args[3].bits)));
        if (!policyGateAllows(self.allocator, .{ .fs = .{ .path = path, .write = true } })) {
            self.stderr.print("[sa-policy] denied fs write: {s}\n", .{path}) catch {};
            return RunError.PolicyDenied;
        }
        var file = try sio.cwd().createFile(path, .{ .truncate = true });
        defer file.close();
        try file.writeAll(data);
        return .{ .handled = .{ .ty = .i32, .bits = data.len } };
    }
    return RunError.UnsupportedSysIntrinsic;
}

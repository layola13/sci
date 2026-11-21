const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const atomic = @import("../common/atomic.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const sio = @import("sio");

// Local aliases: the split renamed these helpers to *Impl below, but the
// moved bodies still call them by their original short names.
const bitcastValue = bitcastValueImpl;
const floatValue = floatValueImpl;
const intValue = intValueImpl;
const isFloatLike = isFloatLikeImpl;
const isIntLike = isIntLikeImpl;
const isSignedInt = isSignedIntImpl;
const maskForWidth = maskForWidthImpl;
const primWidth = primWidthImpl;
const traceRuntime = traceRuntimeImpl;
const valueFromFloat = valueFromFloatImpl;
const valueFromInt = valueFromIntImpl;
const FunctionRange = @import("memory.zig").FunctionRange;
const Interpreter = @import("interpreter.zig").Interpreter;
const Memory = @import("memory.zig").Memory;
const RegValue = @import("memory.zig").RegValue;
const RunError = @import("memory.zig").RunError;
const decodeQuotedBytes = @import("memory.zig").decodeQuotedBytes;
const isRawQuotedStringArg = @import("memory.zig").isRawQuotedStringArg;
const ptrMetaFromValue = @import("memory.zig").ptrMetaFromValue;

pub fn initImpl(
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    argv: []const []const u8,
    stdout: *std.Io.Writer,
    stderr: *std.Io.Writer,
) !Interpreter {
    var ranges = try allocator.alloc(FunctionRange, program.function_sigs.len);
    var initialized_ranges: usize = 0;
    var ranges_owned_by_interp = false;
    errdefer if (!ranges_owned_by_interp) {
        for (ranges[0..initialized_ranges]) |*range| range.deinit();
        allocator.free(ranges);
    };

    var decl_indices = try allocator.alloc(usize, program.function_sigs.len);
    defer allocator.free(decl_indices);

    var decl_count: usize = 0;
    for (program.annotated, 0..) |item, idx| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                if (decl_count < decl_indices.len) {
                    decl_indices[decl_count] = idx;
                    decl_count += 1;
                }
            },
            else => {},
        }
    }

    if (decl_count != program.function_sigs.len) return RunError.InvalidFunction;

    for (decl_indices, 0..) |decl_idx, i| {
        const start = decl_idx + 1;
        const end = if (i + 1 < decl_indices.len) decl_indices[i + 1] else program.annotated.len;
        ranges[i] = try FunctionRange.init(allocator, program, i, start, end);
        initialized_ranges += 1;
    }

    var function_index_by_name = std.StringHashMap(usize).init(allocator);
    errdefer function_index_by_name.deinit();
    for (program.function_sigs, 0..) |fsig, idx| {
        if (!function_index_by_name.contains(fsig.name)) {
            try function_index_by_name.put(fsig.name, idx);
        }
    }

    var argv_storage = try allocator.alloc([]u8, argv.len);
    errdefer allocator.free(argv_storage);
    for (argv, 0..) |arg, i| {
        argv_storage[i] = try allocator.dupe(u8, arg);
    }

    const argv_view = try allocator.alloc([]const u8, argv.len);
    errdefer allocator.free(argv_view);
    for (argv_storage, 0..) |arg, i| {
        argv_view[i] = arg;
    }

    var interp = Interpreter{
        .allocator = allocator,
        .program = program,
        .ranges = ranges,
        .function_index_by_name = function_index_by_name,
        .argv = argv_view,
        .argv_storage = argv_storage,
        .stdout = stdout,
        .stderr = stderr,
        .const_addrs = std.StringHashMap(u64).init(allocator),
        .anon_const_addrs = std.StringHashMap(u64).init(allocator),
        .anon_const_keys = std.array_list.Managed([]u8).init(allocator),
        .memory = Memory.init(allocator),
        .trace_runtime = traceRuntime(allocator) catch false,
        .exit_code = null,
        .call_depth = 0,
    };
    ranges_owned_by_interp = true;
    errdefer interp.deinit();
    try interp.materializeConsts();
    try interp.materializeAnonStringConsts();
    return interp;
}
pub fn deinitImpl(self: *Interpreter) void {
    for (self.anon_const_keys.items) |key| self.allocator.free(key);
    self.anon_const_keys.deinit();
    self.anon_const_addrs.deinit();
    self.const_addrs.deinit();
    self.function_index_by_name.deinit();
    self.memory.deinit();
    for (self.argv_storage) |arg| self.allocator.free(arg);
    self.allocator.free(self.argv_storage);
    self.allocator.free(self.argv);
    for (self.ranges) |*range| range.deinit();
    self.allocator.free(self.ranges);
    self.* = undefined;
}
pub fn materializeAnonStringConstsImpl(self: *Interpreter) !void {
    for (self.program.annotated) |item| {
        switch (item.base.kind) {
            .call, .call_indirect, .panic, .panic_msg => {},
            else => continue,
        }

        var parsed = call.parseInstructionCall(self.allocator, item.base, &self.program.symbols) catch |err| switch (err) {
            error.InvalidCallSyntax => continue,
            else => return err,
        };
        defer parsed.deinit(self.allocator);

        for (parsed.args) |arg| {
            if (!isRawQuotedStringArg(arg)) continue;
            if (self.anon_const_addrs.contains(arg.text)) continue;

            const bytes = try decodeQuotedBytes(self.allocator, arg.text);
            defer self.allocator.free(bytes);
            if (!std.unicode.utf8ValidateSlice(bytes)) return RunError.InvalidOperand;

            const key = try self.allocator.dupe(u8, arg.text);
            errdefer self.allocator.free(key);

            const addr = try self.memory.allocConst(bytes.len, null, &.{});
            const dst = try self.memory.sliceAt(addr, bytes.len);
            @memcpy(dst, bytes);
            try self.anon_const_keys.append(key);
            try self.anon_const_addrs.put(key, addr);
        }
    }
}
pub fn traceRuntimeImpl(allocator: std.mem.Allocator) !bool {
    const value = sio.getEnvVarOwned(allocator, "SAASM_TRACE_RUNTIME") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return false,
        else => return err,
    };
    defer allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0");
}
pub fn constPointerValueImpl(self: *Interpreter, id: u32) ?RegValue {
    const name = self.program.symbols.lookupName(id) orelse return null;
    const addr = self.const_addrs.get(name) orelse return null;
    return .{
        .ty = .ptr,
        .bits = addr,
        .const_name = name,
    };
}
pub fn primWidthImpl(ty: sig.PrimType) u32 {
    return sig.primTypeBits(ty);
}
pub fn isSignedIntImpl(ty: sig.PrimType) bool {
    return switch (ty) {
        .i8, .i16, .i32, .i64 => true,
        else => false,
    };
}
pub fn isIntLikeImpl(ty: sig.PrimType) bool {
    return switch (ty) {
        .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle => true,
        else => false,
    };
}
pub fn isFloatLikeImpl(ty: sig.PrimType) bool {
    return ty == .f32 or ty == .f64;
}
pub fn intValueAsOffsetImpl(value: RegValue) i64 {
    if (isSignedInt(value.ty)) {
        return @as(i64, @intCast(intValue(value, true)));
    }
    const raw = @as(u64, @intCast(intValue(value, false)));
    return @as(i64, @bitCast(raw));
}
pub fn maskForWidthImpl(width: u32) u64 {
    return if (width >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(width)) - 1;
}
pub fn valueFromIntImpl(ty: sig.PrimType, value: i128) !RegValue {
    const bits = switch (ty) {
        .i1 => @as(u64, if (value != 0) 1 else 0),
        .i8, .i16, .i32, .i64 => @as(u64, @bitCast(@as(i64, @intCast(value)))),
        .u8, .u16, .u32, .u64, .ptr, .blob_handle => @as(u64, @intCast(@as(u128, @intCast(value)))),
        .void, .f32, .f64, .v128 => return RunError.UnsupportedInstruction,
    };
    return .{ .ty = ty, .bits = bits };
}
pub fn valueFromFloatImpl(ty: sig.PrimType, value: f64) !RegValue {
    return switch (ty) {
        .f32 => blk: {
            const bits: u32 = @bitCast(@as(f32, @floatCast(value)));
            break :blk .{ .ty = .f32, .bits = @as(u64, bits) };
        },
        .f64 => .{ .ty = .f64, .bits = @bitCast(value) },
        else => RunError.UnsupportedInstruction,
    };
}
pub fn intValueImpl(value: RegValue, signed: bool) i128 {
    const width = primWidth(value.ty);
    const raw = value.bits & maskForWidth(width);
    if (width <= 1) {
        return @as(i128, @intCast(raw));
    }
    if (signed) {
        const sign_bit = if (width == 0) 0 else (@as(u64, 1) << @intCast(width - 1));
        if (width != 0 and (raw & sign_bit) != 0) {
            const extended = raw | (~maskForWidth(width));
            return @as(i128, @intCast(@as(i64, @bitCast(extended))));
        }
        return @as(i128, @intCast(@as(i64, @bitCast(raw))));
    }
    return @as(i128, @intCast(raw));
}
pub fn floatValueImpl(value: RegValue) f64 {
    return switch (value.ty) {
        .f32 => blk: {
            const bits: u32 = @intCast(value.bits & 0xffff_ffff);
            break :blk @floatCast(@as(f32, @bitCast(bits)));
        },
        .f64 => @bitCast(value.bits),
        else => @as(f64, @floatFromInt(intValue(value, true))),
    };
}
pub fn coerceImpl(self: *Interpreter, value: RegValue, target: sig.PrimType) !RegValue {
    _ = self;
    if (value.fallible) return RunError.InvalidOperand;
    if (value.ty == target) return value;
    if (value.ty == .v128 or target == .v128) return RunError.UnsupportedInstruction;
    if (target == .ptr) {
        return .{
            .ty = .ptr,
            .bits = value.bits,
            .interior_ptr = value.interior_ptr,
            .extern_handle = value.extern_handle,
            .const_name = value.const_name,
            .vtable_slot_name = value.vtable_slot_name,
            .call_target_name = value.call_target_name,
        };
    }
    if (isFloatLike(target)) {
        return try valueFromFloat(target, floatValue(value));
    }
    if (isIntLike(target)) {
        const raw = if (value.ty == .f32 or value.ty == .f64) blk: {
            const fv = floatValue(value);
            if (isSignedInt(target)) {
                break :blk @as(u64, @bitCast(@as(i64, @intFromFloat(fv))));
            } else {
                break :blk @as(u64, @intCast(@as(u128, @intFromFloat(fv))));
            }
        } else blk: {
            const src_bits = primWidth(value.ty);
            const width = primWidth(target);
            const mask = maskForWidth(src_bits);
            const raw_bits = value.bits & mask;
            if (width <= src_bits) {
                break :blk raw_bits & maskForWidth(width);
            }
            if (isSignedInt(value.ty) and src_bits != 0 and src_bits < 64 and ((raw_bits >> @intCast(src_bits - 1)) & 1) == 1) {
                break :blk raw_bits | (~mask);
            }
            break :blk raw_bits;
        };
        return .{ .ty = target, .bits = raw };
    }
    return value;
}
pub fn regValueToBytesImpl(value: RegValue) u64 {
    return value.bits;
}
pub fn loadFromMemoryImpl(self: *Interpreter, addr: u64, ty: sig.PrimType) !RegValue {
    const base = try self.memory.sliceAt(addr, @intCast(sig.primTypeBytes(ty)));
    return switch (ty) {
        .void => RunError.InvalidOperand,
        .i1 => .{ .ty = .i1, .bits = @as(u64, base[0] & 1) },
        .i8 => .{ .ty = .i8, .bits = @as(u64, base[0]) },
        .u8 => .{ .ty = .u8, .bits = base[0] },
        .i16 => blk: {
            const buf: *const [2]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .i16, .bits = @as(u64, @bitCast(@as(i64, std.mem.readInt(i16, buf, .little)))) };
        },
        .u16 => blk: {
            const buf: *const [2]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .u16, .bits = @as(u64, std.mem.readInt(u16, buf, .little)) };
        },
        .i32 => blk: {
            const buf: *const [4]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .i32, .bits = @as(u64, @bitCast(@as(i64, std.mem.readInt(i32, buf, .little)))) };
        },
        .u32 => blk: {
            const buf: *const [4]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .u32, .bits = @as(u64, std.mem.readInt(u32, buf, .little)) };
        },
        .i64 => blk: {
            const buf: *const [8]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .i64, .bits = @as(u64, @bitCast(std.mem.readInt(i64, buf, .little))) };
        },
        .u64 => blk: {
            const buf: *const [8]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .u64, .bits = std.mem.readInt(u64, buf, .little) };
        },
        .f32 => blk: {
            const buf: *const [4]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .f32, .bits = @as(u64, std.mem.readInt(u32, buf, .little)) };
        },
        .f64 => blk: {
            const buf: *const [8]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .f64, .bits = std.mem.readInt(u64, buf, .little) };
        },
        .ptr => blk: {
            const buf: *const [8]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .ptr, .bits = std.mem.readInt(u64, buf, .little) };
        },
        .blob_handle => blk: {
            const buf: *const [8]u8 = @ptrCast(base.ptr);
            break :blk .{ .ty = .blob_handle, .bits = std.mem.readInt(u64, buf, .little) };
        },
        .v128 => return RunError.UnsupportedInstruction,
    };
}
pub fn storeToMemoryImpl(self: *Interpreter, addr: u64, value: RegValue, ty: sig.PrimType) !void {
    const base = try self.memory.sliceAt(addr, @intCast(sig.primTypeBytes(ty)));
    switch (ty) {
        .void => return RunError.InvalidOperand,
        .i1 => base[0] = @as(u8, @intCast(value.bits & 1)),
        .i8, .u8 => base[0] = @as(u8, @intCast(value.bits & 0xff)),
        .i16, .u16 => {
            const buf: *[2]u8 = @ptrCast(base.ptr);
            std.mem.writeInt(u16, buf, @as(u16, @intCast(value.bits & 0xffff)), .little);
        },
        .i32, .u32 => {
            const buf: *[4]u8 = @ptrCast(base.ptr);
            std.mem.writeInt(u32, buf, @as(u32, @intCast(value.bits & 0xffff_ffff)), .little);
        },
        .i64, .u64, .ptr, .blob_handle => {
            const buf: *[8]u8 = @ptrCast(base.ptr);
            std.mem.writeInt(u64, buf, value.bits, .little);
        },
        .f32 => {
            const buf: *[4]u8 = @ptrCast(base.ptr);
            const bits: u32 = @bitCast(@as(f32, @floatCast(floatValue(value))));
            std.mem.writeInt(u32, buf, bits, .little);
        },
        .f64 => {
            const buf: *[8]u8 = @ptrCast(base.ptr);
            std.mem.writeInt(u64, buf, @bitCast(floatValue(value)), .little);
        },
        .v128 => return RunError.UnsupportedInstruction,
    }
    const width = sig.primTypeBytes(ty);
    if (width == @sizeOf(u64)) {
        try self.memory.writePtrMeta(addr, @intCast(width), ptrMetaFromValue(value));
    } else {
        try self.memory.writePtrMeta(addr, @intCast(width), null);
    }
}
pub fn atomicRmwApplyImpl(op: atomic.AtomicRmwOp, target: RegValue, value: RegValue) !RegValue {
    if (target.fallible or value.fallible) return RunError.InvalidOperand;
    if (target.ty == .void) return RunError.InvalidOperand;
    const rhs = value;
    const ty = target.ty;
    const width = primWidth(ty);
    const mask = maskForWidth(width);
    const lhs_bits = target.bits & mask;
    const rhs_bits = rhs.bits & mask;
    const result_bits: u64 = switch (op) {
        .add => lhs_bits + rhs_bits,
        .sub => lhs_bits - rhs_bits,
        .@"and" => lhs_bits & rhs_bits,
        .@"or" => lhs_bits | rhs_bits,
        .xor => lhs_bits ^ rhs_bits,
        .xchg => rhs_bits,
        .min => if (intValue(target, true) <= intValue(rhs, true)) lhs_bits else rhs_bits,
        .max => if (intValue(target, true) >= intValue(rhs, true)) lhs_bits else rhs_bits,
        .umin => if (lhs_bits <= rhs_bits) lhs_bits else rhs_bits,
        .umax => if (lhs_bits >= rhs_bits) lhs_bits else rhs_bits,
    };
    return .{ .ty = ty, .bits = result_bits & mask };
}
pub fn numKindImpl(a: RegValue, b: RegValue) enum { signed, unsigned, float } {
    if (isFloatLike(a.ty) or isFloatLike(b.ty)) return .float;
    if (isSignedInt(a.ty) or isSignedInt(b.ty)) return .signed;
    return .unsigned;
}
pub fn opUnaryImpl(self: *Interpreter, op: inst.OpKind, value: RegValue, target: ?sig.PrimType) !RegValue {
    _ = self;
    if (value.fallible) return RunError.InvalidOperand;
    if (value.ty == .v128) return RunError.UnsupportedInstruction;

    switch (op) {
        .neg => {
            if (isFloatLike(value.ty)) {
                return try valueFromFloat(value.ty, -floatValue(value));
            }
            const width = primWidth(value.ty);
            const mask = maskForWidth(width);
            const bits = (0 -% (value.bits & mask)) & mask;
            return .{ .ty = value.ty, .bits = bits, .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name };
        },
        .not => {
            if (!isIntLike(value.ty)) return RunError.InvalidOperand;
            const width = primWidth(value.ty);
            const mask = maskForWidth(width);
            return .{ .ty = value.ty, .bits = (~value.bits) & mask, .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name };
        },
        .fneg => {
            if (!isFloatLike(value.ty)) return RunError.InvalidOperand;
            return try valueFromFloat(value.ty, -floatValue(value));
        },
        .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext => {
            const target_ty = target orelse return RunError.InvalidOperand;
            if (target_ty == .v128) return RunError.UnsupportedInstruction;
            if (value.ty == .v128) return RunError.UnsupportedInstruction;
            if (op == .trunc or op == .zext or op == .sext) {
                if (!isIntLike(value.ty) or !isIntLike(target_ty)) return RunError.InvalidOperand;
                const src_bits = primWidth(value.ty);
                const dst_bits = primWidth(target_ty);
                const raw_bits = value.bits & maskForWidth(src_bits);
                if (op == .trunc or dst_bits < src_bits) {
                    return try valueFromInt(target_ty, @as(i128, @intCast(raw_bits)));
                }
                if (op == .zext) {
                    return .{ .ty = target_ty, .bits = raw_bits & maskForWidth(dst_bits), .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name };
                }
                if (op == .sext) {
                    const signed_raw = intValue(value, true);
                    return try valueFromInt(target_ty, signed_raw);
                }
                return RunError.InvalidInstruction;
            }
            if (op == .fptrunc or op == .fpext) {
                if (!isFloatLike(value.ty) or !isFloatLike(target_ty)) return RunError.InvalidOperand;
                if (op == .fptrunc and primWidth(target_ty) >= primWidth(value.ty)) {
                    return .{ .ty = target_ty, .bits = value.bits, .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name };
                }
                if (op == .fpext and primWidth(target_ty) <= primWidth(value.ty)) {
                    return .{ .ty = target_ty, .bits = value.bits, .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name };
                }
                return switch (target_ty) {
                    .f32 => .{ .ty = .f32, .bits = @as(u64, @as(u32, @bitCast(@as(f32, @floatCast(floatValue(value)))))), .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name },
                    .f64 => .{ .ty = .f64, .bits = @bitCast(@as(f64, @floatCast(floatValue(value)))), .interior_ptr = value.interior_ptr, .const_name = value.const_name, .vtable_slot_name = value.vtable_slot_name, .call_target_name = value.call_target_name },
                    else => RunError.InvalidOperand,
                };
            }
            if (op == .sitofp or op == .uitofp or op == .fptosi) {
                if (op == .fptosi) {
                    if (!isFloatLike(value.ty) or !isIntLike(target_ty)) return RunError.InvalidOperand;
                    return try valueFromInt(target_ty, @as(i128, @intFromFloat(floatValue(value))));
                }
                if (!isIntLike(value.ty) or !isFloatLike(target_ty)) return RunError.InvalidOperand;
                if (op == .sitofp) {
                    return try valueFromFloat(target_ty, @as(f64, @floatFromInt(intValue(value, true))));
                }
                return try valueFromFloat(target_ty, @as(f64, @floatFromInt(intValue(value, false))));
            }
            return RunError.InvalidInstruction;
        },
        .bitcast => {
            const target_ty = target orelse return RunError.InvalidOperand;
            return try bitcastValue(value, target_ty);
        },
        else => return RunError.InvalidInstruction,
    }
}
pub fn bitcastValueImpl(value: RegValue, target: sig.PrimType) !RegValue {
    if (sig.primTypeBits(value.ty) != sig.primTypeBits(target)) return RunError.UnsupportedInstruction;
    return .{
        .ty = target,
        .bits = value.bits,
        .fallible = value.fallible,
        .status = value.status,
        .interior_ptr = value.interior_ptr,
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
    };
}

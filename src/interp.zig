const std = @import("std");

const call = @import("referee/call.zig");
const referee = @import("referee.zig");
const const_decl = @import("common/const_decl.zig");
const symbol = @import("flattener/symbol.zig");
const atomic = @import("common/atomic.zig");
const cap = @import("common/capability.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");

pub const RunError = error{
    OutOfMemory,
    InvalidOperand,
    InvalidAddress,
    InvalidInstruction,
    InvalidFunction,
    UnknownFunction,
    MissingIndirectCallProvenance,
    UnsupportedInstruction,
    UnsupportedSysIntrinsic,
    UserExit,
};

const RegValue = struct {
    ty: sig.PrimType,
    bits: u64,
    fallible: bool = false,
    status: u32 = 0,
    interior_ptr: bool = false,
    const_name: ?[]const u8 = null,
    vtable_slot_name: ?[]const u8 = null,
    call_target_name: ?[]const u8 = null,
};

const SysCallOutcome = union(enum) {
    not_syscall,
    handled: ?RegValue,
};

const PtrMeta = struct {
    const_name: ?[]const u8 = null,
    vtable_slot_name: ?[]const u8 = null,
    call_target_name: ?[]const u8 = null,
    interior_ptr: bool = false,
};

fn valueTypeForPrefix(prefix: inst.CapPrefix, declared: sig.PrimType) sig.PrimType {
    return switch (prefix) {
        .by_value => declared,
        .borrow, .move, .raw => .ptr,
    };
}

fn returnTypeForSig(return_cap: ?inst.CapPrefix, return_ty: sig.PrimType) sig.PrimType {
    if (return_ty == .void) return .void;
    return switch (return_cap orelse .by_value) {
        .raw, .borrow => .ptr,
        .move, .by_value => return_ty,
    };
}

fn atomicValueType(item: inst.Instruction, fallback: sig.PrimType) sig.PrimType {
    if (item.atomic_value_ty) |tag| {
        if (sig.primTypeFromTag(tag)) |ty| return ty;
    }
    return fallback;
}

fn packFallible(status: u32, value: RegValue) RegValue {
    return .{
        .ty = value.ty,
        .bits = value.bits,
        .fallible = true,
        .status = status,
        .interior_ptr = value.interior_ptr,
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
    };
}

fn unpackSuccess(value: RegValue) RegValue {
    return .{
        .ty = value.ty,
        .bits = value.bits,
        .interior_ptr = value.interior_ptr,
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
    };
}

fn requireNonFallible(value: RegValue) !RegValue {
    if (value.fallible) return RunError.InvalidOperand;
    return value;
}

fn readReg(regs: *std.AutoHashMap(u32, RegValue), id: u32) !RegValue {
    return try requireNonFallible(regs.get(id) orelse return RunError.InvalidOperand);
}

fn readRawReg(regs: *std.AutoHashMap(u32, RegValue), id: u32) !RegValue {
    return regs.get(id) orelse return RunError.InvalidOperand;
}

fn readValue(self: *Interpreter, regs: *std.AutoHashMap(u32, RegValue), id: u32) !RegValue {
    if (regs.get(id)) |value| return try requireNonFallible(value);
    return self.constPointerValue(id) orelse RunError.InvalidOperand;
}

fn readRawValue(self: *Interpreter, regs: *std.AutoHashMap(u32, RegValue), id: u32) !RegValue {
    if (regs.get(id)) |value| return value;
    return self.constPointerValue(id) orelse RunError.InvalidOperand;
}

fn ptrMetaFromValue(value: RegValue) ?PtrMeta {
    if (value.const_name == null and value.vtable_slot_name == null and value.call_target_name == null and !value.interior_ptr) return null;
    return .{
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
        .interior_ptr = value.interior_ptr,
    };
}

fn withPtrMeta(value: RegValue, meta: ?PtrMeta) RegValue {
    if (meta) |m| {
        return .{
            .ty = value.ty,
            .bits = value.bits,
            .fallible = value.fallible,
            .status = value.status,
            .interior_ptr = value.interior_ptr or m.interior_ptr,
            .const_name = m.const_name orelse value.const_name,
            .vtable_slot_name = m.vtable_slot_name orelse value.vtable_slot_name,
            .call_target_name = m.call_target_name orelse value.call_target_name,
        };
    }
    return value;
}

fn appendConstBytes(out: *std.ArrayList(u8), value: const_decl.ConstValue) !void {
    switch (value) {
        .hex => |literal| try out.appendSlice(literal.bytes),
        .utf8 => |literal| try out.appendSlice(literal.bytes),
        .repeat => |literal| try out.appendSlice(literal.bytes),
        .struct_ => |literal| {
            for (literal.fields) |field| {
                try appendConstBytes(out, field.value);
            }
        },
        .vtable => |literal| {
            try out.appendNTimes(0, literal.slots.len * @sizeOf(u64));
        },
    }
}

fn materializeConstValue(allocator: std.mem.Allocator, value: const_decl.ConstValue) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try appendConstBytes(&out, value);
    return try out.toOwnedSlice();
}

fn isIdentLike(text: []const u8) bool {
    return text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
}

fn stripTextOperandPrefix(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return trimmed;
    return switch (trimmed[0]) {
        '&', '^', '*', '@' => std.mem.trim(u8, trimmed[1..], " \t"),
        else => trimmed,
    };
}

fn resolveOperandValue(
    self: *Interpreter,
    regs: *std.AutoHashMap(u32, RegValue),
    operand: inst.Operand,
) !RegValue {
    return switch (operand) {
        .reg => |id| try readValue(self, regs, id),
        .text => |text| try self.resolveTextOperand(regs, text),
        .imm_u64 => |v| .{ .ty = .u64, .bits = v },
        .imm_i64 => |v| .{ .ty = .i64, .bits = @as(u64, @bitCast(v)) },
        .imm_int => |v| .{ .ty = .i64, .bits = @as(u64, @bitCast(v)) },
        .imm_float => |v| .{ .ty = .f64, .bits = @bitCast(v) },
        else => RunError.InvalidOperand,
    };
}

const Block = struct {
    addr: u64,
    data: []u8,
    ptr_meta: []?PtrMeta = &.{},
    const_name: ?[]const u8 = null,
    vtable_slot_names: []?[]const u8 = &.{},
};

const Memory = struct {
    allocator: std.mem.Allocator,
    blocks: std.ArrayList(Block),

    fn init(allocator: std.mem.Allocator) Memory {
        return .{
            .allocator = allocator,
            .blocks = std.ArrayList(Block).init(allocator),
        };
    }

    fn deinit(self: *Memory) void {
        for (self.blocks.items) |blk| {
            if (blk.ptr_meta.len != 0) self.allocator.free(blk.ptr_meta);
            if (blk.vtable_slot_names.len != 0) self.allocator.free(blk.vtable_slot_names);
            self.allocator.free(blk.data);
        }
        self.blocks.deinit();
    }

    fn alloc(self: *Memory, size: usize) !u64 {
        const actual = if (size == 0) @as(usize, 1) else size;
        const data = try self.allocator.alloc(u8, actual);
        const ptr_meta = try self.allocator.alloc(?PtrMeta, actual);
        @memset(ptr_meta, null);
        const addr = @as(u64, @intFromPtr(data.ptr));
        try self.blocks.append(.{ .addr = addr, .data = data, .ptr_meta = ptr_meta });
        return addr;
    }

    fn allocConst(self: *Memory, size: usize, const_name: ?[]const u8, vtable_slot_names: []?[]const u8) !u64 {
        const actual = if (size == 0) @as(usize, 1) else size;
        const data = try self.allocator.alloc(u8, actual);
        const ptr_meta = try self.allocator.alloc(?PtrMeta, actual);
        @memset(ptr_meta, null);
        const slot_copy = if (vtable_slot_names.len != 0)
            try self.allocator.dupe(?[]const u8, vtable_slot_names)
        else
            try self.allocator.alloc(?[]const u8, 0);
        const addr = @as(u64, @intFromPtr(data.ptr));
        try self.blocks.append(.{ .addr = addr, .data = data, .ptr_meta = ptr_meta, .const_name = const_name, .vtable_slot_names = slot_copy });
        return addr;
    }

    fn free(self: *Memory, addr: u64) !void {
        for (self.blocks.items, 0..) |blk, idx| {
            if (blk.addr == addr) {
                if (blk.ptr_meta.len != 0) self.allocator.free(blk.ptr_meta);
                if (blk.vtable_slot_names.len != 0) self.allocator.free(blk.vtable_slot_names);
                self.allocator.free(blk.data);
                _ = self.blocks.swapRemove(idx);
                return;
            }
        }
    }

    fn blockIndexAt(self: *const Memory, addr: u64) ?usize {
        for (self.blocks.items, 0..) |blk, idx| {
            const start = blk.addr;
            const end = start + @as(u64, @intCast(blk.data.len));
            if (addr >= start and addr < end) return idx;
        }
        return null;
    }

    fn sliceAt(self: *Memory, addr: u64, len: usize) ![]u8 {
        const idx = self.blockIndexAt(addr) orelse return RunError.InvalidAddress;
        const blk = self.blocks.items[idx];
        const offset = @as(usize, @intCast(addr - blk.addr));
        if (offset > blk.data.len or blk.data.len - offset < len) return RunError.InvalidAddress;
        return blk.data[offset .. offset + len];
    }

    fn writePtrMeta(self: *Memory, addr: u64, len: usize, meta: ?PtrMeta) !void {
        const idx = self.blockIndexAt(addr) orelse return RunError.InvalidAddress;
        const blk = &self.blocks.items[idx];
        const offset = @as(usize, @intCast(addr - blk.addr));
        if (offset > blk.ptr_meta.len or blk.ptr_meta.len - offset < len) return RunError.InvalidAddress;
        for (blk.ptr_meta[offset .. offset + len]) |*slot| {
            slot.* = meta;
        }
    }

    fn ptrMetaAt(self: *const Memory, addr: u64, len: usize) ?PtrMeta {
        const idx = self.blockIndexAt(addr) orelse return null;
        const blk = self.blocks.items[idx];
        const offset = @as(usize, @intCast(addr - blk.addr));
        if (offset > blk.ptr_meta.len or blk.ptr_meta.len - offset < len) return null;
        const first = blk.ptr_meta[offset] orelse return self.blockMeta(addr);
        for (blk.ptr_meta[offset + 1 .. offset + len]) |entry| {
            if (entry == null) return self.blockMeta(addr);
            const meta = entry.?;
            if (!std.meta.eql(meta, first)) return self.blockMeta(addr);
        }
        return first;
    }

    fn blockConstName(self: *const Memory, addr: u64) ?[]const u8 {
        const idx = self.blockIndexAt(addr) orelse return null;
        return self.blocks.items[idx].const_name;
    }

    fn blockVtableSlotName(self: *const Memory, addr: u64) ?[]const u8 {
        const idx = self.blockIndexAt(addr) orelse return null;
        const blk = self.blocks.items[idx];
        if (blk.vtable_slot_names.len == 0) return null;
        const offset = @as(usize, @intCast(addr - blk.addr));
        const slot_idx = offset / @sizeOf(u64);
        if (slot_idx >= blk.vtable_slot_names.len) return null;
        return blk.vtable_slot_names[slot_idx];
    }

    fn blockMeta(self: *const Memory, addr: u64) ?PtrMeta {
        const idx = self.blockIndexAt(addr) orelse return null;
        const blk = self.blocks.items[idx];
        var meta = PtrMeta{
            .const_name = blk.const_name,
            .vtable_slot_name = null,
            .call_target_name = null,
            .interior_ptr = false,
        };
        if (blk.vtable_slot_names.len != 0) {
            const offset = @as(usize, @intCast(addr - blk.addr));
            const slot_idx = offset / @sizeOf(u64);
            if (slot_idx < blk.vtable_slot_names.len) {
                meta.vtable_slot_name = blk.vtable_slot_names[slot_idx];
                meta.call_target_name = blk.vtable_slot_names[slot_idx];
            }
        }
        return meta;
    }
};

const FunctionRange = struct {
    start: usize,
    end: usize,
};

const Interpreter = struct {
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    ranges: []FunctionRange,
    argv: [][]const u8,
    argv_storage: [][]u8,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
    const_addrs: std.StringHashMap(u64),
    memory: Memory,
    exit_code: ?u8 = null,

    fn init(
        allocator: std.mem.Allocator,
        program: *const referee.VerifyOk,
        argv: []const []const u8,
        stdout: std.io.AnyWriter,
        stderr: std.io.AnyWriter,
    ) !Interpreter {
        var ranges = try allocator.alloc(FunctionRange, program.function_sigs.len);
        errdefer allocator.free(ranges);

        var decl_indices = try allocator.alloc(usize, program.function_sigs.len);
        defer allocator.free(decl_indices);

        var decl_count: usize = 0;
        for (program.annotated, 0..) |item, idx| {
            switch (item.base.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl => {
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
            ranges[i] = .{ .start = start, .end = end };
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
            .argv = argv_view,
            .argv_storage = argv_storage,
            .stdout = stdout,
            .stderr = stderr,
            .const_addrs = std.StringHashMap(u64).init(allocator),
            .memory = Memory.init(allocator),
            .exit_code = null,
        };
        errdefer interp.deinit();
        try interp.materializeConsts();
        return interp;
    }

    fn deinit(self: *Interpreter) void {
        self.const_addrs.deinit();
        self.memory.deinit();
        for (self.argv_storage) |arg| self.allocator.free(arg);
        self.allocator.free(self.argv_storage);
        self.allocator.free(self.argv);
        self.allocator.free(self.ranges);
        self.* = undefined;
    }

    fn constPointerValue(self: *Interpreter, id: u32) ?RegValue {
        const name = self.program.symbols.lookupName(id) orelse return null;
        const addr = self.const_addrs.get(name) orelse return null;
        return .{
            .ty = .ptr,
            .bits = addr,
            .const_name = name,
        };
    }

    fn primWidth(ty: sig.PrimType) u32 {
        return sig.primTypeBits(ty);
    }

    fn isSignedInt(ty: sig.PrimType) bool {
        return switch (ty) {
            .i8, .i16, .i32, .i64 => true,
            else => false,
        };
    }

    fn isIntLike(ty: sig.PrimType) bool {
        return switch (ty) {
            .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr => true,
            else => false,
        };
    }

    fn isFloatLike(ty: sig.PrimType) bool {
        return ty == .f32 or ty == .f64;
    }

    fn intValueAsOffset(value: RegValue) i64 {
        if (isSignedInt(value.ty)) {
            return @as(i64, @intCast(intValue(value, true)));
        }
        const raw = @as(u64, @intCast(intValue(value, false)));
        return @as(i64, @bitCast(raw));
    }

    fn maskForWidth(width: u32) u64 {
        return if (width >= 64) ~@as(u64, 0) else (@as(u64, 1) << @intCast(width)) - 1;
    }

    fn valueFromInt(ty: sig.PrimType, value: i128) !RegValue {
        const bits = switch (ty) {
            .i1 => @as(u64, if (value != 0) 1 else 0),
            .i8, .i16, .i32, .i64 => @as(u64, @bitCast(@as(i64, @intCast(value)))),
            .u8, .u16, .u32, .u64, .ptr => @as(u64, @intCast(@as(u128, @intCast(value)))),
            .void, .f32, .f64, .v128 => return RunError.UnsupportedInstruction,
        };
        return .{ .ty = ty, .bits = bits };
    }

    fn valueFromFloat(ty: sig.PrimType, value: f64) !RegValue {
        return switch (ty) {
            .f32 => blk: {
                const bits: u32 = @bitCast(@as(f32, @floatCast(value)));
                break :blk .{ .ty = .f32, .bits = @as(u64, bits) };
            },
            .f64 => .{ .ty = .f64, .bits = @bitCast(value) },
            else => RunError.UnsupportedInstruction,
        };
    }

    fn intValue(value: RegValue, signed: bool) i128 {
        const width = primWidth(value.ty);
        const raw = value.bits & maskForWidth(width);
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

    fn floatValue(value: RegValue) f64 {
        return switch (value.ty) {
            .f32 => blk: {
                const bits: u32 = @intCast(value.bits & 0xffff_ffff);
                break :blk @floatCast(@as(f32, @bitCast(bits)));
            },
            .f64 => @bitCast(value.bits),
            else => @as(f64, @floatFromInt(intValue(value, true))),
        };
    }

    fn coerce(_: *Interpreter, value: RegValue, target: sig.PrimType) !RegValue {
        if (value.fallible) return RunError.InvalidOperand;
        if (value.ty == target) return value;
        if (value.ty == .v128 or target == .v128) return RunError.UnsupportedInstruction;
        if (target == .ptr) {
            return .{ .ty = .ptr, .bits = value.bits, .interior_ptr = value.interior_ptr };
        }
        if (isFloatLike(target)) {
            return try valueFromFloat(target, floatValue(value));
        }
        if (isIntLike(target)) {
            const signed = isSignedInt(target);
            const width = primWidth(target);
            const raw = if (value.ty == .f32 or value.ty == .f64) blk: {
                const fv = floatValue(value);
                if (signed) {
                    break :blk @as(u64, @bitCast(@as(i64, @intFromFloat(fv))));
                } else {
                    break :blk @as(u64, @intCast(@as(u128, @intFromFloat(fv))));
                }
            } else blk: {
                const iv = intValue(value, signed);
                break :blk @as(u64, @bitCast(@as(i64, @intCast(iv))));
            };
            const mask = maskForWidth(width);
            const bits = raw & mask;
            if (signed and width < 64 and width != 0 and ((bits >> @intCast(width - 1)) & 1) == 1) {
                const ext = bits | (~mask);
                return .{ .ty = target, .bits = ext };
            }
            return .{ .ty = target, .bits = bits };
        }
        return value;
    }

    fn regValueToBytes(value: RegValue) u64 {
        return value.bits;
    }

    fn loadFromMemory(self: *Interpreter, addr: u64, ty: sig.PrimType) !RegValue {
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
            .v128 => return RunError.UnsupportedInstruction,
        };
    }

    fn storeToMemory(self: *Interpreter, addr: u64, value: RegValue, ty: sig.PrimType) !void {
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
            .i64, .u64, .ptr => {
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

    fn atomicRmwApply(op: atomic.AtomicRmwOp, target: RegValue, value: RegValue) !RegValue {
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

    fn numKind(a: RegValue, b: RegValue) enum { signed, unsigned, float } {
        if (isFloatLike(a.ty) or isFloatLike(b.ty)) return .float;
        if (isSignedInt(a.ty) or isSignedInt(b.ty)) return .signed;
        return .unsigned;
    }

    fn opBinary(self: *Interpreter, op: inst.OpCode, a: RegValue, b: RegValue) !RegValue {
        _ = self;
        if (a.fallible or b.fallible) return RunError.InvalidOperand;

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
                    else => unreachable,
                };
            }
        }

        const kind = numKind(a, b);
        const lhs_signed = intValue(a, true);
        const rhs_signed = intValue(b, true);
        const lhs_unsigned: u128 = @as(u128, @intCast(intValue(a, false)));
        const rhs_unsigned: u128 = @as(u128, @intCast(intValue(b, false)));

        switch (op) {
            .add => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a) + floatValue(b)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed + rhs_signed))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned + rhs_unsigned)) },
            },
            .sub => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a) - floatValue(b)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed - rhs_signed))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned - rhs_unsigned)) },
            },
            .mul => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a) * floatValue(b)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed * rhs_signed))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned * rhs_unsigned)) },
            },
            .div => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a) / floatValue(b)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(@divTrunc(lhs_signed, rhs_signed)))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned / rhs_unsigned)) },
            },
            .rem => return switch (kind) {
                .float => RunError.InvalidOperand,
                .signed => try valueFromInt(.i64, @as(i64, @intCast(@rem(lhs_signed, rhs_signed)))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned % rhs_unsigned)) },
            },
            .sdiv => {
                if (kind == .float) return RunError.InvalidOperand;
                return try valueFromInt(.i64, @as(i64, @intCast(@divTrunc(lhs_signed, rhs_signed))));
            },
            .udiv => {
                if (kind == .float) return RunError.InvalidOperand;
                return .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned / rhs_unsigned)) };
            },
            .srem => {
                if (kind == .float) return RunError.InvalidOperand;
                return try valueFromInt(.i64, @as(i64, @intCast(@rem(lhs_signed, rhs_signed))));
            },
            .urem => {
                if (kind == .float) return RunError.InvalidOperand;
                return .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned % rhs_unsigned)) };
            },
            .gt, .lt, .eq, .ne => {
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
                        break :blk try valueFromInt(.i64, @intFromBool(result));
                    },
                    .signed => blk: {
                        const result = switch (op) {
                            .gt => lhs_signed > rhs_signed,
                            .lt => lhs_signed < rhs_signed,
                            .eq => lhs_signed == rhs_signed,
                            .ne => lhs_signed != rhs_signed,
                            else => unreachable,
                        };
                        break :blk try valueFromInt(.i64, @intFromBool(result));
                    },
                    .unsigned => blk: {
                        const result = switch (op) {
                            .gt => lhs_unsigned > rhs_unsigned,
                            .lt => lhs_unsigned < rhs_unsigned,
                            .eq => lhs_unsigned == rhs_unsigned,
                            .ne => lhs_unsigned != rhs_unsigned,
                            else => unreachable,
                        };
                        break :blk try valueFromInt(.i64, @intFromBool(result));
                    },
                };
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
                return try valueFromInt(.i64, @intFromBool(result));
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
                return try valueFromInt(.i64, @intFromBool(result));
            },
            .@"and" => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed & rhs_signed))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned & rhs_unsigned)) },
            },
            .@"or" => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed | rhs_signed))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned | rhs_unsigned)) },
            },
            .shl => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed << @as(u6, @intCast(rhs_unsigned & 0x3f))))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned << @as(u6, @intCast(rhs_unsigned & 0x3f)))) },
            },
            .shr => return switch (kind) {
                .float => try valueFromFloat(.f64, floatValue(a)),
                .signed => try valueFromInt(.i64, @as(i64, @intCast(lhs_signed >> @as(u6, @intCast(rhs_unsigned & 0x3f))))),
                .unsigned => .{ .ty = .u64, .bits = @as(u64, @intCast(lhs_unsigned >> @as(u6, @intCast(rhs_unsigned & 0x3f)))) },
            },
        }
    }

    fn buildLabelMap(
        self: *Interpreter,
        body: []const referee.AnnotatedInstruction,
    ) !std.AutoHashMap(u32, usize) {
        var labels = std.AutoHashMap(u32, usize).init(self.allocator);
        errdefer labels.deinit();
        for (body, 0..) |item, idx| {
            if (item.base.kind == .label) {
                const id = item.base.operands[1].label;
                try labels.put(id, idx);
            }
        }
        return labels;
    }

    fn findFunctionIndex(self: *Interpreter, name: []const u8) ?usize {
        for (self.program.function_sigs, 0..) |fsig, idx| {
            if (std.mem.eql(u8, fsig.name, name)) return idx;
        }
        return null;
    }

    fn resolveTextOperand(self: *Interpreter, regs: *std.AutoHashMap(u32, RegValue), text: []const u8) !RegValue {
        const candidate = stripTextOperandPrefix(text);
        if (candidate.len == 0) return RunError.InvalidOperand;
        if (isIdentLike(candidate)) {
            if (self.program.symbols.findId(candidate)) |id| {
                return try readValue(self, regs, id);
            }
        }
        return try Interpreter.parseImmediateValue(self.allocator, &self.memory, candidate);
    }

    fn materializeConsts(self: *Interpreter) !void {
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

    fn decodeArg(
        self: *Interpreter,
        frame_regs: *std.AutoHashMap(u32, RegValue),
        arg: call.ParsedArg,
    ) !RegValue {
        return try self.resolveTextOperand(frame_regs, arg.text);
    }

    fn parseImmediateValue(allocator: std.mem.Allocator, mem: *Memory, text: []const u8) !RegValue {
        _ = allocator;
        _ = mem;
        const trimmed = std.mem.trim(u8, text, " \t");
        if (trimmed.len == 0) return RunError.InvalidOperand;
        if (std.mem.indexOfScalar(u8, trimmed, '.') != null) {
            const value = try std.fmt.parseFloat(f64, trimmed);
            return .{ .ty = .f64, .bits = @bitCast(value) };
        }
        const value = try std.fmt.parseInt(i64, trimmed, 10);
        return .{ .ty = .i64, .bits = @as(u64, @bitCast(value)) };
    }

    fn recordPanic(self: *Interpreter, code: u8, message: ?[]const u8) void {
        self.exit_code = @as(u8, @intCast(128 + (@as(u32, code) & 0x7f)));
        if (message) |msg| {
            self.stderr.print("PANIC[{d}]: {s}\n", .{ code, msg }) catch {};
        } else {
            self.stderr.print("PANIC: code={d}\n", .{code}) catch {};
        }
    }

    fn printBytes(self: *Interpreter, ptr: u64, len: usize) !void {
        const slice = try self.memory.sliceAt(ptr, len);
        try self.stdout.writeAll(slice);
    }

    fn handleSysCall(
        self: *Interpreter,
        name: []const u8,
        args: []const RegValue,
    ) !SysCallOutcome {
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
            var file = try std.fs.cwd().openFile(path, .{});
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
            var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
            defer file.close();
            try file.writeAll(data);
            return .{ .handled = .{ .ty = .i32, .bits = data.len } };
        }
        return RunError.UnsupportedSysIntrinsic;
    }

    fn execFunction(self: *Interpreter, sig_index: usize, arg_values: []const RegValue) !RegValue {
        const fsig = self.program.function_sigs[sig_index];
        const range = self.ranges[sig_index];
        const body = self.program.annotated[range.start..range.end];

        var regs = std.AutoHashMap(u32, RegValue).init(self.allocator);
        defer regs.deinit();
        var labels = try self.buildLabelMap(body);
        defer labels.deinit();
        var stack_allocs = std.ArrayList(u64).init(self.allocator);
        defer {
            for (stack_allocs.items) |addr| {
                self.memory.free(addr) catch {};
            }
            stack_allocs.deinit();
        }

        for (fsig.params, 0..) |param, idx| {
            if (idx >= arg_values.len) return RunError.InvalidOperand;
            const id = fsig.param_ids[idx];
            const target_ty = valueTypeForPrefix(param.cap, param.ty);
            const value = try self.coerce(arg_values[idx], target_ty);
            try regs.put(id, value);
        }

        var pc: usize = 0;
        while (pc < body.len) {
            const item = body[pc];
            const base = item.base;
            switch (base.kind) {
                .label => {},
                .alloc => {
                    const dst = base.operands[0].reg;
                    const size = switch (base.operands[1]) {
                        .imm_u64 => |v| v,
                        .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                        .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                        .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                        else => return RunError.InvalidOperand,
                    };
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
                    const size = switch (base.operands[1]) {
                        .imm_u64 => |v| v,
                        .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                        .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                        .text => |t| std.fmt.parseInt(u64, t, 10) catch return RunError.InvalidOperand,
                        else => return RunError.InvalidOperand,
                    };
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
                    try regs.put(dst, .{
                        .ty = loaded.ty,
                        .bits = loaded.bits,
                        .fallible = loaded.fallible,
                        .status = loaded.status,
                        .interior_ptr = loaded.interior_ptr or (selected_meta != null and selected_meta.?.interior_ptr),
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
                    const value = try resolveOperandValue(self, &regs, base.operands[2]);
                    const coerced = try self.coerce(value, ty);
                    try self.storeToMemory(basev.bits + off, coerced, ty);
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
                    const value = try resolveOperandValue(self, &regs, base.operands[2]);
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
                    const expected_value = try resolveOperandValue(self, &regs, .{ .text = expected_text });
                    const new_value = try resolveOperandValue(self, &regs, .{ .text = new_text });
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
                    const value = try resolveOperandValue(self, &regs, base.operands[3]);
                    const coerced = try self.coerce(value, ty);
                    const current = try self.loadFromMemory(basev.bits + off, ty);
                    const updated = try atomicRmwApply(base.atomic_rmw_op orelse return RunError.InvalidOperand, current, coerced);
                    try self.storeToMemory(basev.bits + off, updated, ty);
                    try regs.put(dst, current);
                },
                .fence => {},
                .op => {
                    const dst = base.operands[0].reg;
                    const op = base.operands[1].op_code;
                    const lhs = try resolveOperandValue(self, &regs, base.operands[2]);
                    const rhs = try resolveOperandValue(self, &regs, base.operands[3]);
                    const result = try self.opBinary(op, lhs, rhs);
                    try regs.put(dst, result);
                },
                .ptr_add => {
                    const dst = base.operands[0].reg;
                    const src = base.operands[1].reg;
                    const basev = try readValue(self, &regs, src);
                    const ptrv = try self.coerce(basev, .ptr);
                    const offset = try resolveOperandValue(self, &regs, base.operands[2]);
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
                    const value = try resolveOperandValue(self, &regs, base.operands[1]);
                    try regs.put(dst, value);
                },
                .move_ => {
                    // Referee already enforced ownership semantics.
                },
                .release => {
                    const reg_id = base.operands[0].reg;
                    const mask = item.entry_caps[@intCast(reg_id)];
                    if ((mask & @intFromEnum(cap.CapabilityMask.borrow_view)) != 0 or (mask & @intFromEnum(cap.CapabilityMask.ffi_borrow)) != 0) {
                        // Borrow views do not physically free.
                    } else if (regs.get(reg_id)) |value| {
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
                                self.memory.free(value.bits) catch {};
                            }
                        }
                    }
                },
                .jmp => {
                    const label_id = base.operands[1].label;
                    pc = labels.get(label_id) orelse return RunError.InvalidInstruction;
                    continue;
                },
                .br => {
                    const cond = try readValue(self, &regs, base.operands[0].reg);
                    const jump = cond.bits != 0;
                    const label_id = if (jump) base.operands[1].label else base.operands[3].label;
                    pc = labels.get(label_id) orelse return RunError.InvalidInstruction;
                    continue;
                },
                .br_null => {
                    const cond = try readValue(self, &regs, base.operands[0].reg);
                    const jump = cond.bits == 0;
                    const label_id = if (jump) base.operands[1].label else base.operands[3].label;
                    pc = labels.get(label_id) orelse return RunError.InvalidInstruction;
                    continue;
                },
                .call, .call_indirect, .panic, .panic_msg => call_case: {
                    var parsed = call.parseCall(self.allocator, base.raw_text) catch return RunError.InvalidOperand;
                    defer parsed.deinit(self.allocator);

                    if (parsed.is_indirect) {
                        const callee_id = self.program.symbols.findId(parsed.callee) orelse return RunError.UnknownFunction;
                        const callee = try readRawValue(self, &regs, callee_id);
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
                        if (parsed.args.len != target_sig.params.len) return RunError.InvalidOperand;
                        const args = try self.collectArgs(parsed, &regs, target_sig.params);
                        defer self.allocator.free(args);
                        const ret = try self.execFunction(callee_index, args);
                        if (parsed.dest) |dest| {
                            if (self.program.symbols.findId(dest)) |id| {
                                try regs.put(id, ret);
                            }
                        }
                        break :call_case;
                    }

                    const call_values = try self.collectCallValues(parsed, &regs);
                    defer self.allocator.free(call_values);

                    switch (try self.handleSysCall(parsed.callee, call_values)) {
                        .handled => |ret_or_null| {
                            if (ret_or_null) |ret| {
                                if (parsed.dest) |dest| {
                                    if (self.program.symbols.findId(dest)) |id| try regs.put(id, ret);
                                }
                            }
                        },
                        .not_syscall => {
                            const callee_sig_index = self.findFunctionIndex(parsed.callee) orelse return RunError.UnknownFunction;
                            const callee_sig = self.program.function_sigs[callee_sig_index];
                            const args = try self.collectArgs(parsed, &regs, callee_sig.params);
                            defer self.allocator.free(args);
                            const ret = try self.execFunction(callee_sig_index, args);
                            if (parsed.dest) |dest| {
                                if (self.program.symbols.findId(dest)) |id| try regs.put(id, ret);
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
                    try regs.put(dst, unpackSuccess(value));
                },
                .return_ => {
                    if (base.operands[0] == .none) {
                        if (fsig.return_fallible) return RunError.InvalidOperand;
                        return .{ .ty = .void, .bits = 0 };
                    }
                    if (fsig.return_fallible) {
                        const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
                        if (ret_ty == .void) return RunError.InvalidOperand;
                        const value = try resolveOperandValue(self, &regs, base.operands[0]);
                        if (value.fallible) return value;
                        const coerced = try self.coerce(value, ret_ty);
                        return packFallible(0, coerced);
                    }
                    const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
                    if (ret_ty == .void) {
                        return .{ .ty = .void, .bits = 0 };
                    }
                    const value = try resolveOperandValue(self, &regs, base.operands[0]);
                    return try self.coerce(value, ret_ty);
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

    fn collectCallValues(self: *Interpreter, parsed: call.ParsedCall, regs: *std.AutoHashMap(u32, RegValue)) ![]RegValue {
        const out = try self.allocator.alloc(RegValue, parsed.args.len);
        errdefer self.allocator.free(out);
        for (parsed.args, 0..) |arg, idx| {
            out[idx] = self.resolveTextOperand(regs, arg.text) catch |err| {
                self.stderr.print("interp call arg parse failed in {s}: {s} ({})\n", .{ parsed.callee, arg.text, err }) catch {};
                return err;
            };
        }
        return out;
    }

    fn collectArgs(self: *Interpreter, parsed: call.ParsedCall, regs: *std.AutoHashMap(u32, RegValue), params: []const sig.ParamSpec) ![]RegValue {
        if (parsed.args.len != params.len) return RunError.InvalidOperand;
        const out = try self.allocator.alloc(RegValue, parsed.args.len);
        errdefer self.allocator.free(out);
        for (parsed.args, params, 0..) |arg, param, idx| {
            const raw = self.resolveTextOperand(regs, arg.text) catch |err| {
                self.stderr.print("interp indirect arg parse failed in {s}: {s} ({})\n", .{ parsed.callee, arg.text, err }) catch {};
                return err;
            };
            out[idx] = try self.coerce(raw, valueTypeForPrefix(param.cap, param.ty));
        }
        return out;
    }
};

pub fn runWithWriters(
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    argv: []const []const u8,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
) !u8 {
    var interp = try Interpreter.init(allocator, program, argv, stdout, stderr);
    defer interp.deinit();

    const main_index = blk: {
        for (program.function_sigs, 0..) |fsig, idx| {
            if (fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main")) break :blk idx;
        }
        if (program.function_sigs.len != 0) break :blk @as(usize, 0);
        return 0;
    };

    const args = try allocator.alloc(RegValue, 0);
    defer allocator.free(args);

    const result = interp.execFunction(main_index, args) catch |err| switch (err) {
        error.UserExit => return interp.exit_code orelse 0,
        else => return err,
    };

    if (interp.exit_code) |code| return code;
    if (result.fallible) return @as(u8, @truncate(result.status));
    return @as(u8, @truncate(result.bits));
}

pub fn run(
    allocator: std.mem.Allocator,
    program: *const referee.VerifyOk,
    argv: []const []const u8,
) !u8 {
    return runWithWriters(
        allocator,
        program,
        argv,
        std.io.getStdOut().writer().any(),
        std.io.getStdErr().writer().any(),
    );
}

test "interpreter exports" {
    _ = run;
}

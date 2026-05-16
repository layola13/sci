const std = @import("std");

const call = @import("referee/call.zig");
const referee = @import("referee.zig");
const const_decl = @import("common/const_decl.zig");
const symbol = @import("flattener/symbol.zig");
const atomic = @import("common/atomic.zig");
const cap = @import("common/capability.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");

const SA_STD_OK: i32 = 0;
const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
const SA_STD_ERR_INVALID_HANDLE: i32 = 2;
const SA_STD_ERR_NOT_FOUND: i32 = 3;
const SA_STD_ERR_ACCESS: i32 = 4;
const SA_STD_ERR_NO_MEMORY: i32 = 5;
const SA_STD_ERR_IO: i32 = 6;
const SA_STD_ERR_NET: i32 = 7;
const SA_STD_ERR_UNSUPPORTED: i32 = 8;
const SA_STD_ERR_TRUNCATED: i32 = 9;
const SA_STD_ERR_UNKNOWN: i32 = 127;

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

const TimeDate = extern struct {
    unix_ms: i64,
    unix_ns: i64,
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
    millisecond: u16,
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

fn makeFallibleI32(status: i32) RegValue {
    const status_bits = @as(u64, @intCast(status));
    return packFallible(@as(u32, @intCast(status)), .{ .ty = .i32, .bits = status_bits });
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
    monotonic_origin: ?std.time.Instant = null,
    trace_runtime: bool = false,
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
            .monotonic_origin = null,
            .trace_runtime = traceRuntime(allocator) catch false,
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

    fn traceRuntime(allocator: std.mem.Allocator) !bool {
        const value = std.process.getEnvVarOwned(allocator, "SAASM_TRACE_RUNTIME") catch |err| switch (err) {
            error.EnvironmentVariableNotFound => return false,
            else => return err,
        };
        defer allocator.free(value);
        return value.len != 0 and !std.mem.eql(u8, value, "0");
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

    fn opUnary(self: *Interpreter, op: inst.OpKind, value: RegValue, target: ?sig.PrimType) !RegValue {
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

    fn bitcastValue(value: RegValue, target: sig.PrimType) !RegValue {
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

    fn opBinary(self: *Interpreter, op: inst.OpKind, a: RegValue, b: RegValue) !RegValue {
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

    fn resolveSizeOperand(self: *Interpreter, regs: *std.AutoHashMap(u32, RegValue), operand: inst.Operand) !u64 {
        return switch (operand) {
            .imm_u64 => |v| v,
            .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
            .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
            .text => |text| std.fmt.parseInt(u64, std.mem.trim(u8, text, " \t"), 10) catch return RunError.InvalidOperand,
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
        if (len == 0) return;
        const slice = try self.memory.sliceAt(ptr, len);
        try self.stdout.writeAll(slice);
    }

    fn monotonicNowNs(self: *Interpreter) !u64 {
        const current = try std.time.Instant.now();
        if (self.monotonic_origin) |origin| {
            return current.since(origin);
        }
        self.monotonic_origin = current;
        return 0;
    }

    fn writeUtcNow(self: *Interpreter, ptr: u64) !void {
        const out = try self.memory.sliceAt(ptr, @sizeOf(TimeDate));
        @memset(out, 0);

        const unix_ms = std.time.milliTimestamp();
        const unix_s = @divFloor(unix_ms, std.time.ms_per_s);
        if (unix_s < 0) return error.Unsupported;

        const unix_ns_raw = std.time.nanoTimestamp();
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
            return .{ .handled = .{ .ty = .u64, .bits = self.monotonicNowNs() catch 0 } };
        }
        if (std.mem.eql(u8, name, "sa_time_unix_s")) {
            if (args.len != 0) return RunError.InvalidOperand;
            return .{ .handled = .{ .ty = .i64, .bits = @as(u64, @bitCast(std.time.timestamp())) } };
        }
        if (std.mem.eql(u8, name, "sa_time_unix_ms")) {
            if (args.len != 0) return RunError.InvalidOperand;
            return .{ .handled = .{ .ty = .i64, .bits = @as(u64, @bitCast(std.time.milliTimestamp())) } };
        }
        if (std.mem.eql(u8, name, "sa_time_unix_ns")) {
            if (args.len != 0) return RunError.InvalidOperand;
            const ts = std.time.nanoTimestamp();
            const unix_ns = @as(i64, @intCast(ts));
            return .{ .handled = .{ .ty = .i64, .bits = @as(u64, @bitCast(unix_ns)) } };
        }
        if (std.mem.eql(u8, name, "sa_time_utc_now")) {
            if (args.len != 1) return RunError.InvalidOperand;
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
            std.Thread.sleep(args[0].bits);
            return .{ .handled = makeFallibleI32(SA_STD_OK) };
        }
        if (std.mem.eql(u8, name, "sa_time_sleep_ms")) {
            if (args.len != 1) return RunError.InvalidOperand;
            const ns = std.math.mul(u64, args[0].bits, std.time.ns_per_ms) catch return .{ .handled = makeFallibleI32(SA_STD_ERR_INVALID_ARGUMENT) };
            std.Thread.sleep(ns);
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
            if (self.trace_runtime) {
                self.stderr.print("trace {s}:{d} {s}: {s}\n", .{ fsig.name, base.source_line, @tagName(base.kind), base.raw_text }) catch {};
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
                    const op = base.op_kind orelse return RunError.InvalidInstruction;
                    const result = try switch (op) {
                        .neg, .not, .fneg => blk: {
                            const value = try resolveOperandValue(self, &regs, base.operands[1]);
                            break :blk self.opUnary(op, value, null);
                        },
                        .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext, .bitcast => blk: {
                            const value = try resolveOperandValue(self, &regs, base.operands[1]);
                            const target = if (base.operands[2] == .ty) sig.primTypeFromTag(base.operands[2].ty) else null;
                            break :blk self.opUnary(op, value, target);
                        },
                        .extract_lane => blk: {
                            const value = try resolveOperandValue(self, &regs, base.operands[1]);
                            const lane = try resolveOperandValue(self, &regs, base.operands[2]);
                            _ = value;
                            _ = lane;
                            break :blk RunError.UnsupportedInstruction;
                        },
                        .shuffle_v128, .insert_lane, .add_v128, .sub_v128, .mul_v128 => RunError.UnsupportedInstruction,
                        else => blk: {
                            const lhs = try resolveOperandValue(self, &regs, base.operands[1]);
                            const rhs = try resolveOperandValue(self, &regs, base.operands[2]);
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

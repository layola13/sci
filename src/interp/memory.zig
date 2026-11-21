const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const const_decl = @import("../common/const_decl.zig");
const symbol = @import("../flattener/symbol.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const Interpreter = @import("interpreter.zig").Interpreter;

pub const SA_STD_OK: i32 = 0;
pub const SA_STD_ERR_INVALID_ARGUMENT: i32 = 1;
const SA_STD_ERR_INVALID_HANDLE: i32 = 2;
const SA_STD_ERR_NOT_FOUND: i32 = 3;
const SA_STD_ERR_ACCESS: i32 = 4;
const SA_STD_ERR_NO_MEMORY: i32 = 5;
pub const SA_STD_ERR_IO: i32 = 6;
const SA_STD_ERR_NET: i32 = 7;
pub const SA_STD_ERR_UNSUPPORTED: i32 = 8;
const SA_STD_ERR_TRUNCATED: i32 = 9;
pub const SA_STD_ERR_PERMISSION_DENIED: i32 = 10;
pub const SA_STD_ERR_UNKNOWN: i32 = 127;

pub const RunError = error{
    OutOfMemory,
    InvalidOperand,
    InvalidAddress,
    InvalidInstruction,
    InvalidFunction,
    UnknownFunction,
    DivByZero,
    CallStackOverflow,
    MissingIndirectCallProvenance,
    UnsupportedExtern,
    UnsupportedVariadic,
    UnsupportedInstruction,
    UnsupportedSysIntrinsic,
    PolicyDenied,
    UserExit,
};

pub const interpreter_max_call_depth: usize = 1024;

pub const RegValue = struct {
    ty: sig.PrimType,
    bits: u64,
    fallible: bool = false,
    status: u32 = 0,
    interior_ptr: bool = false,
    borrow_view: bool = false,
    ffi_borrow: bool = false,
    extern_handle: bool = false,
    from_try: bool = false,
    const_name: ?[]const u8 = null,
    vtable_slot_name: ?[]const u8 = null,
    call_target_name: ?[]const u8 = null,
};

pub const TimeDate = extern struct {
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

pub const SysCallOutcome = union(enum) {
    not_syscall,
    handled: ?RegValue,
};

const PtrMeta = struct {
    const_name: ?[]const u8 = null,
    vtable_slot_name: ?[]const u8 = null,
    call_target_name: ?[]const u8 = null,
    interior_ptr: bool = false,
    extern_handle: bool = false,
};

pub fn valueTypeForPrefix(prefix: inst.CapPrefix, declared: sig.PrimType) sig.PrimType {
    return switch (prefix) {
        .by_value => declared,
        .borrow, .move, .raw => .ptr,
    };
}

pub fn returnTypeForSig(return_cap: ?inst.CapPrefix, return_ty: sig.PrimType) sig.PrimType {
    if (return_ty == .void) return .void;
    return switch (return_cap orelse .by_value) {
        .raw, .borrow => .ptr,
        .move, .by_value => return_ty,
    };
}

pub fn atomicValueType(item: inst.Instruction, fallback: sig.PrimType) sig.PrimType {
    if (item.atomic_value_ty) |tag| {
        if (sig.primTypeFromTag(tag)) |ty| return ty;
    }
    return fallback;
}

pub fn packFallible(status: u32, value: RegValue) RegValue {
    return .{
        .ty = value.ty,
        .bits = value.bits,
        .fallible = true,
        .status = status,
        .interior_ptr = value.interior_ptr,
        .extern_handle = value.extern_handle,
        .from_try = value.from_try,
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
    };
}

pub fn unpackSuccess(value: RegValue) RegValue {
    return .{
        .ty = value.ty,
        .bits = value.bits,
        .interior_ptr = value.interior_ptr,
        .extern_handle = value.extern_handle,
        .from_try = value.from_try,
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
    };
}

pub fn cloneValue(value: RegValue) RegValue {
    return .{
        .ty = value.ty,
        .bits = value.bits,
        .fallible = value.fallible,
        .status = value.status,
        .interior_ptr = value.interior_ptr,
        .extern_handle = value.extern_handle,
        .from_try = value.from_try,
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
    };
}

pub fn withExternHandle(value: RegValue) RegValue {
    var out = cloneValue(value);
    out.extern_handle = true;
    return out;
}

pub fn makeFallibleI32(status: i32) RegValue {
    const status_bits = @as(u64, @intCast(status));
    return packFallible(@as(u32, @intCast(status)), .{ .ty = .i32, .bits = status_bits });
}

pub fn requireNonFallible(value: RegValue) !RegValue {
    if (value.fallible) return RunError.InvalidOperand;
    return value;
}

pub const FrameRegs = struct {
    fsig: *const sig.FunctionSig,
    values: []?RegValue,

    pub fn init(allocator: std.mem.Allocator, fsig: *const sig.FunctionSig) !FrameRegs {
        const values = try allocator.alloc(?RegValue, fsig.reg_ids.len);
        @memset(values, null);
        return .{
            .fsig = fsig,
            .values = values,
        };
    }

    pub fn deinit(self: *FrameRegs, allocator: std.mem.Allocator) void {
        if (self.values.len != 0) allocator.free(self.values);
        self.* = undefined;
    }

    pub fn get(self: *const FrameRegs, id: u32) ?RegValue {
        const idx: usize = @intCast(id);
        if (idx >= self.values.len) return null;
        return self.values[idx];
    }

    pub fn getPtr(self: *FrameRegs, id: u32) ?*RegValue {
        const idx: usize = @intCast(id);
        if (idx >= self.values.len) return null;
        if (self.values[idx]) |*value| return value;
        return null;
    }

    pub fn put(self: *FrameRegs, id: u32, value: RegValue) !void {
        const idx: usize = @intCast(id);
        if (idx >= self.values.len) return RunError.InvalidOperand;
        self.values[idx] = value;
    }
};

pub fn readReg(regs: *FrameRegs, id: u32) !RegValue {
    return try requireNonFallible(regs.get(id) orelse return RunError.InvalidOperand);
}

pub fn readRawReg(regs: *FrameRegs, id: u32) !RegValue {
    return regs.get(id) orelse return RunError.InvalidOperand;
}

pub fn readValue(self: *Interpreter, regs: *FrameRegs, id: u32) !RegValue {
    if (regs.get(id)) |value| return try requireNonFallible(value);
    if (id >= regs.fsig.reg_ids.len) return RunError.InvalidOperand;
    const global_id = regs.fsig.globalId(id);
    return self.constPointerValue(global_id) orelse RunError.InvalidOperand;
}

pub fn readRawValue(self: *Interpreter, regs: *FrameRegs, id: u32) !RegValue {
    if (regs.get(id)) |value| return value;
    if (id >= regs.fsig.reg_ids.len) return RunError.InvalidOperand;
    const global_id = regs.fsig.globalId(id);
    return self.constPointerValue(global_id) orelse RunError.InvalidOperand;
}

pub fn ptrMetaFromValue(value: RegValue) ?PtrMeta {
    if (value.const_name == null and value.vtable_slot_name == null and value.call_target_name == null and !value.interior_ptr and !value.extern_handle) return null;
    return .{
        .const_name = value.const_name,
        .vtable_slot_name = value.vtable_slot_name,
        .call_target_name = value.call_target_name,
        .interior_ptr = value.interior_ptr,
        .extern_handle = value.extern_handle,
    };
}

pub fn withPtrMeta(value: RegValue, meta: ?PtrMeta) RegValue {
    if (meta) |m| {
        return .{
            .ty = value.ty,
            .bits = value.bits,
            .fallible = value.fallible,
            .status = value.status,
            .interior_ptr = value.interior_ptr or m.interior_ptr,
            .extern_handle = value.extern_handle or m.extern_handle,
            .const_name = m.const_name orelse value.const_name,
            .vtable_slot_name = m.vtable_slot_name orelse value.vtable_slot_name,
            .call_target_name = m.call_target_name orelse value.call_target_name,
        };
    }
    return value;
}

pub fn appendConstBytes(out: *std.array_list.Managed(u8), value: const_decl.ConstValue) !void {
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
            // NOTE(Zig 0.17): `Managed.appendNTimes` is gone.
            const zeros = literal.slots.len * @sizeOf(u64);
            try out.ensureUnusedCapacity(zeros);
            for (0..zeros) |_| out.appendAssumeCapacity(0);
        },
    }
}

pub fn materializeConstValue(allocator: std.mem.Allocator, value: const_decl.ConstValue) ![]u8 {
    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();
    try appendConstBytes(&out, value);
    return try out.toOwnedSlice();
}

pub fn parseHexDigitPair(text: []const u8) !u8 {
    if (text.len != 2) return RunError.InvalidOperand;
    const hi = std.fmt.charToDigit(text[0], 16) catch return RunError.InvalidOperand;
    const lo = std.fmt.charToDigit(text[1], 16) catch return RunError.InvalidOperand;
    return @as(u8, @intCast((hi << 4) | lo));
}

pub fn decodeQuotedBytes(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return RunError.InvalidOperand;

    var out = std.array_list.Managed(u8).init(allocator);
    errdefer out.deinit();

    var i: usize = 1;
    while (i < raw.len - 1) {
        const c = raw[i];
        if (c != '\\') {
            try out.append(c);
            i += 1;
            continue;
        }

        if (i + 1 >= raw.len - 1) return RunError.InvalidOperand;
        switch (raw[i + 1]) {
            '\\' => {
                try out.append('\\');
                i += 2;
            },
            '"' => {
                try out.append('"');
                i += 2;
            },
            'n' => {
                try out.append('\n');
                i += 2;
            },
            'r' => {
                try out.append('\r');
                i += 2;
            },
            't' => {
                try out.append('\t');
                i += 2;
            },
            '0' => {
                try out.append(0);
                i += 2;
            },
            'x' => {
                if (i + 3 >= raw.len - 1) return RunError.InvalidOperand;
                try out.append(try parseHexDigitPair(raw[i + 2 .. i + 4]));
                i += 4;
            },
            else => return RunError.InvalidOperand,
        }
    }

    return try out.toOwnedSlice();
}

pub fn isRawQuotedStringArg(arg: call.ParsedArg) bool {
    return arg.prefix == .raw and arg.text.len >= 2 and arg.text[0] == '"' and arg.text[arg.text.len - 1] == '"';
}

pub fn isIdentLike(text: []const u8) bool {
    return text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
}

pub fn stripTextOperandPrefix(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return trimmed;
    return switch (trimmed[0]) {
        '&', '^', '*', '@' => std.mem.trim(u8, trimmed[1..], " \t"),
        else => trimmed,
    };
}

pub fn resolveOperandValue(
    self: *Interpreter,
    range: *const FunctionRange,
    regs: *FrameRegs,
    operand: inst.Operand,
) !RegValue {
    return switch (operand) {
        .reg => |id| try readValue(self, regs, id),
        .text => |text| try self.resolveTextOperand(range, regs, text),
        .imm_u64 => |v| .{ .ty = .u64, .bits = v },
        .imm_i64 => |v| .{ .ty = .i64, .bits = @as(u64, @bitCast(v)) },
        .imm_int => |v| .{ .ty = .i64, .bits = @as(u64, @bitCast(v)) },
        .imm_float => |v| .{ .ty = .f64, .bits = @bitCast(v) },
        else => {
            std.debug.print("interp.resolveOperandValue failed for operand kind {s}\n", .{@tagName(operand)});
            return RunError.InvalidOperand;
        },
    };
}

const Block = struct {
    addr: u64,
    data: []u8,
    ptr_meta: []?PtrMeta = &.{},
    const_name: ?[]const u8 = null,
    vtable_slot_names: []?[]const u8 = &.{},
};

pub const Memory = struct {
    allocator: std.mem.Allocator,
    blocks: std.array_list.Managed(Block),

    pub fn init(allocator: std.mem.Allocator) Memory {
        return .{
            .allocator = allocator,
            .blocks = std.array_list.Managed(Block).init(allocator),
        };
    }

    pub fn deinit(self: *Memory) void {
        for (self.blocks.items) |blk| {
            if (blk.ptr_meta.len != 0) self.allocator.free(blk.ptr_meta);
            if (blk.vtable_slot_names.len != 0) self.allocator.free(blk.vtable_slot_names);
            self.allocator.free(blk.data);
        }
        self.blocks.deinit();
    }

    pub fn alloc(self: *Memory, size: usize) !u64 {
        const actual = if (size == 0) @as(usize, 1) else size;
        const data = try self.allocator.alloc(u8, actual);
        errdefer self.allocator.free(data);
        const ptr_meta = try self.allocator.alloc(?PtrMeta, actual);
        errdefer self.allocator.free(ptr_meta);
        @memset(ptr_meta, null);
        const addr = @as(u64, @intFromPtr(data.ptr));
        try self.insertBlock(.{ .addr = addr, .data = data, .ptr_meta = ptr_meta });
        return addr;
    }

    pub fn allocConst(self: *Memory, size: usize, const_name: ?[]const u8, vtable_slot_names: []?[]const u8) !u64 {
        const actual = if (size == 0) @as(usize, 1) else size;
        const data = try self.allocator.alloc(u8, actual);
        errdefer self.allocator.free(data);
        const ptr_meta = try self.allocator.alloc(?PtrMeta, actual);
        errdefer self.allocator.free(ptr_meta);
        @memset(ptr_meta, null);
        const slot_copy = if (vtable_slot_names.len != 0)
            try self.allocator.dupe(?[]const u8, vtable_slot_names)
        else
            try self.allocator.alloc(?[]const u8, 0);
        errdefer if (slot_copy.len != 0) self.allocator.free(slot_copy);
        const addr = @as(u64, @intFromPtr(data.ptr));
        try self.insertBlock(.{ .addr = addr, .data = data, .ptr_meta = ptr_meta, .const_name = const_name, .vtable_slot_names = slot_copy });
        return addr;
    }

    pub fn insertBlock(self: *Memory, block: Block) !void {
        const idx = self.lowerBoundBlock(block.addr);
        try self.blocks.insert(idx, block);
    }

    pub fn free(self: *Memory, addr: u64) !void {
        if (self.blockIndexByBase(addr)) |idx| {
            const blk = self.blocks.items[idx];
            if (blk.ptr_meta.len != 0) self.allocator.free(blk.ptr_meta);
            if (blk.vtable_slot_names.len != 0) self.allocator.free(blk.vtable_slot_names);
            self.allocator.free(blk.data);
            _ = self.blocks.orderedRemove(idx);
        }
    }

    pub fn lowerBoundBlock(self: *const Memory, addr: u64) usize {
        var lo: usize = 0;
        var hi: usize = self.blocks.items.len;
        while (lo < hi) {
            const mid = lo + (hi - lo) / 2;
            if (self.blocks.items[mid].addr < addr) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
        return lo;
    }

    pub fn blockIndexByBase(self: *const Memory, addr: u64) ?usize {
        const idx = self.lowerBoundBlock(addr);
        if (idx < self.blocks.items.len and self.blocks.items[idx].addr == addr) return idx;
        return null;
    }

    pub fn blockIndexAt(self: *const Memory, addr: u64) ?usize {
        const upper = self.lowerBoundBlock(addr +| 1);
        if (upper == 0) return null;
        const idx = upper - 1;
        const blk = self.blocks.items[idx];
        const start = blk.addr;
        const end = start +| @as(u64, @intCast(blk.data.len));
        return if (addr >= start and addr < end) idx else null;
    }

    pub fn sliceAt(self: *Memory, addr: u64, len: usize) ![]u8 {
        const idx = self.blockIndexAt(addr) orelse return RunError.InvalidAddress;
        const blk = self.blocks.items[idx];
        const offset = @as(usize, @intCast(addr - blk.addr));
        if (offset > blk.data.len or blk.data.len - offset < len) return RunError.InvalidAddress;
        return blk.data[offset .. offset + len];
    }

    pub fn writePtrMeta(self: *Memory, addr: u64, len: usize, meta: ?PtrMeta) !void {
        const idx = self.blockIndexAt(addr) orelse return RunError.InvalidAddress;
        const blk = &self.blocks.items[idx];
        const offset = @as(usize, @intCast(addr - blk.addr));
        if (offset > blk.ptr_meta.len or blk.ptr_meta.len - offset < len) return RunError.InvalidAddress;
        for (blk.ptr_meta[offset .. offset + len]) |*slot| {
            slot.* = meta;
        }
    }

    pub fn ptrMetaAt(self: *const Memory, addr: u64, len: usize) ?PtrMeta {
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

    pub fn blockConstName(self: *const Memory, addr: u64) ?[]const u8 {
        const idx = self.blockIndexAt(addr) orelse return null;
        return self.blocks.items[idx].const_name;
    }

    pub fn blockVtableSlotName(self: *const Memory, addr: u64) ?[]const u8 {
        const idx = self.blockIndexAt(addr) orelse return null;
        const blk = self.blocks.items[idx];
        if (blk.vtable_slot_names.len == 0) return null;
        const offset = @as(usize, @intCast(addr - blk.addr));
        const slot_idx = offset / @sizeOf(u64);
        if (slot_idx >= blk.vtable_slot_names.len) return null;
        return blk.vtable_slot_names[slot_idx];
    }

    pub fn blockMeta(self: *const Memory, addr: u64) ?PtrMeta {
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

test "interpreter memory keeps block lookup sorted and range aware" {
    var memory = Memory.init(std.testing.allocator);
    defer memory.deinit();

    const first = try memory.alloc(8);
    const second = try memory.alloc(16);
    const third = try memory.alloc(4);

    for (memory.blocks.items[1..], 1..) |blk, idx| {
        try std.testing.expect(memory.blocks.items[idx - 1].addr < blk.addr);
    }

    try std.testing.expect(memory.blockIndexAt(first) != null);
    try std.testing.expect(memory.blockIndexAt(first + 7) != null);
    try std.testing.expect(memory.blockIndexAt(second + 15) != null);
    try std.testing.expect(memory.blockIndexAt(third + 3) != null);

    try memory.free(second);
    try std.testing.expect(memory.blockIndexAt(second) == null);
    try std.testing.expect(memory.blockIndexAt(first + 7) != null);
    try std.testing.expect(memory.blockIndexAt(third + 3) != null);
}

test "interpreter rejects integer divide and remainder by zero" {
    var interp: Interpreter = undefined;
    const lhs = RegValue{ .ty = .i64, .bits = @as(u64, @bitCast(@as(i64, 42))) };
    const zero = RegValue{ .ty = .i64, .bits = 0 };

    try std.testing.expectError(RunError.DivByZero, interp.opBinary(.sdiv, lhs, zero));
    try std.testing.expectError(RunError.DivByZero, interp.opBinary(.srem, lhs, zero));
    try std.testing.expectError(RunError.DivByZero, interp.opBinary(.udiv, .{ .ty = .u64, .bits = 42 }, .{ .ty = .u64, .bits = 0 }));
    try std.testing.expectError(RunError.DivByZero, interp.opBinary(.urem, .{ .ty = .u64, .bits = 42 }, .{ .ty = .u64, .bits = 0 }));
}

test "interpreter call depth guard fails before host stack growth" {
    var interp: Interpreter = undefined;
    interp.call_depth = interpreter_max_call_depth;
    try std.testing.expectError(RunError.CallStackOverflow, interp.execFunction(0, &.{}));
}

pub const FunctionRange = struct {
    start: usize,
    end: usize,
    labels: std.AutoHashMap(u32, usize),
    slot_by_id: std.AutoHashMap(u32, u32),

    pub fn init(
        allocator: std.mem.Allocator,
        program: *const referee.VerifyOk,
        sig_index: usize,
        start: usize,
        end: usize,
    ) !FunctionRange {
        var labels = std.AutoHashMap(u32, usize).init(allocator);
        errdefer labels.deinit();
        for (program.annotated[start..end], 0..) |item, body_idx| {
            if (item.base.kind == .label) {
                const id = item.base.operands[1].label;
                try labels.put(id, body_idx);
            }
        }

        const fsig = program.function_sigs[sig_index];
        var slot_by_id = std.AutoHashMap(u32, u32).init(allocator);
        errdefer slot_by_id.deinit();
        try slot_by_id.ensureTotalCapacity(@intCast(fsig.reg_ids.len));
        for (fsig.reg_ids, 0..) |reg_id, idx| {
            slot_by_id.putAssumeCapacity(reg_id, @intCast(idx));
        }

        return .{
            .start = start,
            .end = end,
            .labels = labels,
            .slot_by_id = slot_by_id,
        };
    }

    pub fn deinit(self: *FunctionRange) void {
        self.labels.deinit();
        self.slot_by_id.deinit();
        self.* = undefined;
    }

    pub fn slotOf(self: *const FunctionRange, global_id: u32) ?u32 {
        return self.slot_by_id.get(global_id);
    }
};

pub const FunctionSymbolLookup = struct {
    symbols: *const symbol.SymbolTable,
    fsig: *const sig.FunctionSig,

    pub fn lookupName(self: FunctionSymbolLookup, id: u32) ?[]const u8 {
        const slot_index: usize = @intCast(id);
        if (slot_index < self.fsig.reg_ids.len) {
            return self.symbols.lookupName(self.fsig.globalId(id));
        }
        return self.symbols.lookupName(id);
    }
};

pub fn runPrepared(
    interp: *Interpreter,
    sig_index: usize,
    arg_values: []const RegValue,
) !u8 {
    const result = interp.execFunction(sig_index, arg_values) catch |err| switch (err) {
        error.UserExit => return interp.exit_code orelse 0,
        error.DivByZero => return 100,
        error.CallStackOverflow => return 108,
        else => return err,
    };

    if (interp.exit_code) |code| return code;
    if (result.fallible) {
        if (result.status != 0) return @as(u8, @truncate(result.status));
        if (result.from_try) return 0;
        return @as(u8, @truncate(result.bits));
    }
    return @as(u8, @truncate(result.bits));
}

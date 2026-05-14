const std = @import("std");

const call = @import("referee/call.zig");
const trap = @import("common/trap.zig");
const atomic = @import("common/atomic.zig");
const common_const_decl = @import("common/const_decl.zig");
const cap = @import("common/capability.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const upstream = @import("common/upstream_loc.zig");
const flattener = @import("flattener.zig");
const referee = @import("referee.zig");
const symbol = @import("flattener/symbol.zig");

pub const EmitError = error{
    OutOfMemory,
    InvalidOperand,
    UnsupportedInstruction,
    UnsupportedType,
    UnknownFunction,
    MissingIndirectCallProvenance,
};

pub const EmitOptions = struct {
    debug: bool = false,
    wasm_compat: bool = false,
};

const Value = struct {
    expr: []const u8,
    ty: sig.PrimType,
    fallible: bool = false,
    interior_ptr: bool = false,
    borrow_view: bool = false,
    ffi_borrow: bool = false,
    const_ref: ?[]const u8 = null,
    origin: PointerOrigin = .{},
};

const BuiltinCallResult = union(enum) {
    not_builtin,
    handled_void,
    handled_value: Value,
};

const PointerOrigin = struct {
    const_name: ?[]const u8 = null,
    const_offset: u64 = 0,
    indirect_sig_index: ?usize = null,
};

const register_slot_bytes: u64 = 64;
const register_slot_align: u32 = 16;

const MemoryPtrMeta = struct {
    base_expr: []const u8,
    offset: u64,
    origin: PointerOrigin = .{},
    interior_ptr: bool = false,
};

const DirectCallResult = union(enum) {
    not_direct,
    handled_void,
    handled_value: Value,
};

fn isIdentLike(text: []const u8) bool {
    return text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
}

const FunctionState = struct {
    sig: sig.FunctionSig,
    emitted_name: []const u8,
    regs: std.AutoHashMap(u32, Value),
    reg_slots: []?[]const u8,
    owned: std.ArrayList([]const u8),
    memory_ptrs: std.ArrayList(MemoryPtrMeta),
    temp_index: usize = 0,
    block_open: bool = true,
    const_ref_names: std.StringHashMap(void),

    fn init(allocator: std.mem.Allocator, sig_: sig.FunctionSig, reg_count: usize) !FunctionState {
        const reg_slots = try allocator.alloc(?[]const u8, reg_count);
        @memset(reg_slots, null);
        return .{
            .sig = sig_,
            .emitted_name = emittedFunctionName(sig_),
            .regs = std.AutoHashMap(u32, Value).init(allocator),
            .reg_slots = reg_slots,
            .owned = std.ArrayList([]const u8).init(allocator),
            .memory_ptrs = std.ArrayList(MemoryPtrMeta).init(allocator),
            .const_ref_names = std.StringHashMap(void).init(allocator),
        };
    }

    fn deinit(self: *FunctionState, allocator: std.mem.Allocator) void {
        self.regs.deinit();
        self.const_ref_names.deinit();
        self.memory_ptrs.deinit();
        allocator.free(self.reg_slots);
        for (self.owned.items) |item| allocator.free(item);
        self.owned.deinit();
        self.* = undefined;
    }

    fn own(self: *FunctionState, allocator: std.mem.Allocator, text: []const u8) ![]const u8 {
        const dup = try allocator.dupe(u8, text);
        try self.owned.append(dup);
        return dup;
    }

    fn ownFmt(self: *FunctionState, allocator: std.mem.Allocator, comptime fmt: []const u8, args: anytype) ![]const u8 {
        const text = try std.fmt.allocPrint(allocator, fmt, args);
        try self.owned.append(text);
        return text;
    }

    fn tempName(self: *FunctionState, allocator: std.mem.Allocator) ![]const u8 {
        const name = try self.ownFmt(allocator, "%t{d}", .{self.temp_index});
        self.temp_index += 1;
        return name;
    }

    fn setReg(self: *FunctionState, allocator: std.mem.Allocator, out: ?*std.ArrayList(u8), id: u32, value: Value) !void {
        if (self.regs.getPtr(id)) |slot| {
            slot.* = value;
        } else {
            try self.regs.put(id, value);
        }
        if (out) |stmt| {
            const slot_name = try self.ensureSlot(allocator, stmt, id);
            try stmt.writer().writeAll("  store ");
            try writeValueType(stmt.writer(), value);
            try stmt.writer().print(" {s}, ptr {s}, align {d}\n", .{ value.expr, slot_name, register_slot_align });
        }
    }

    fn ensureSlot(self: *FunctionState, allocator: std.mem.Allocator, out: ?*std.ArrayList(u8), id: u32) ![]const u8 {
        const idx: usize = @intCast(id);
        if (self.reg_slots[idx]) |slot| return slot;
        const slot = try self.ownFmt(allocator, "%slot_{d}", .{id});
        self.reg_slots[idx] = slot;
        if (out) |stmt| {
            try stmt.writer().print("  {s} = alloca i8, i64 {d}, align {d}\n", .{ slot, register_slot_bytes, register_slot_align });
        }
        return slot;
    }

    fn getReg(self: *FunctionState, id: u32) ?Value {
        return self.regs.get(id);
    }

    fn setConstRef(self: *FunctionState, name: []const u8) !void {
        try self.const_ref_names.put(name, {});
    }

    fn hasConstRef(self: *FunctionState, name: []const u8) bool {
        return self.const_ref_names.contains(name);
    }

    fn normalizePointerOrigin(value: Value) PointerOrigin {
        var origin = value.origin;
        if (origin.const_name == null) {
            origin.const_name = value.const_ref;
        }
        return origin;
    }

    fn clearMemoryPtrMeta(self: *FunctionState, base_expr: []const u8, offset: u64) void {
        var idx: usize = self.memory_ptrs.items.len;
        while (idx > 0) {
            idx -= 1;
            const item = self.memory_ptrs.items[idx];
            if (item.offset == offset and std.mem.eql(u8, item.base_expr, base_expr)) {
                _ = self.memory_ptrs.swapRemove(idx);
                return;
            }
        }
    }

    fn recordMemoryPtrMeta(self: *FunctionState, base_expr: []const u8, offset: u64, value: Value) !void {
        const origin = normalizePointerOrigin(value);
        const has_meta = value.ty == .ptr and (value.interior_ptr or origin.const_name != null or origin.indirect_sig_index != null);
        if (!has_meta) {
            self.clearMemoryPtrMeta(base_expr, offset);
            return;
        }

        const entry = MemoryPtrMeta{
            .base_expr = base_expr,
            .offset = offset,
            .origin = origin,
            .interior_ptr = value.interior_ptr,
        };

        for (self.memory_ptrs.items, 0..) |*item, idx| {
            if (item.offset == offset and std.mem.eql(u8, item.base_expr, base_expr)) {
                item.* = entry;
                return;
            }
            _ = idx;
        }
        try self.memory_ptrs.append(entry);
    }

    fn lookupMemoryPtrMeta(self: *const FunctionState, base_expr: []const u8, offset: u64) ?MemoryPtrMeta {
        var idx: usize = self.memory_ptrs.items.len;
        while (idx > 0) {
            idx -= 1;
            const item = self.memory_ptrs.items[idx];
            if (item.offset == offset and std.mem.eql(u8, item.base_expr, base_expr)) {
                return item;
            }
        }
        return null;
    }

    fn reloadLiveRegs(self: *FunctionState, allocator: std.mem.Allocator, out: *std.ArrayList(u8), live_caps: []const u16) !void {
        for (live_caps, 0..) |mask, idx| {
            if (mask == 0 or mask == maskOf(.consumed) or mask == maskOf(.untracked)) continue;
            const reg_id: u32 = @intCast(idx);
            const value = self.getReg(reg_id) orelse continue;
            const slot = self.reg_slots[idx] orelse return EmitError.InvalidOperand;
            const tmp = try self.tempName(allocator);
            try out.writer().print("  {s} = load ", .{tmp});
            try writeValueType(out.writer(), value);
            try out.writer().print(", ptr {s}, align {d}\n", .{ slot, register_slot_align });
            var loaded = value;
            loaded.expr = tmp;
            try self.setReg(allocator, null, reg_id, loaded);
        }
    }
};

const DebugFile = struct {
    id: u32,
    filename: []const u8,
    directory: []const u8,
};

const DebugFunction = struct {
    id: u32,
    name: []const u8,
    linkage_name: []const u8,
    file_id: u32,
    line: u32,
};

const DebugLocation = struct {
    id: u32,
    scope_id: u32,
    line: u32,
    col: u32,
};

const DebugFunctionContext = struct {
    subprogram_id: u32,
    file_id: u32,
};

const DebugInfo = struct {
    source_path: []const u8,
    source_file_id: u32 = 3,
    subroutine_type_id: u32 = 4,
    next_id: u32 = 5,
    files: std.StringHashMap(u32),
    file_nodes: std.ArrayList(DebugFile),
    functions: std.ArrayList(DebugFunction),
    locations: std.ArrayList(DebugLocation),
    location_ids: std.AutoHashMap(u128, u32),

    fn init(allocator: std.mem.Allocator, source_path: []const u8) !DebugInfo {
        var files = std.StringHashMap(u32).init(allocator);
        errdefer files.deinit();
        var file_nodes = std.ArrayList(DebugFile).init(allocator);
        errdefer file_nodes.deinit();
        var functions = std.ArrayList(DebugFunction).init(allocator);
        errdefer functions.deinit();
        var locations = std.ArrayList(DebugLocation).init(allocator);
        errdefer locations.deinit();
        var location_ids = std.AutoHashMap(u128, u32).init(allocator);
        errdefer location_ids.deinit();

        const source_dir = std.fs.path.dirname(source_path) orelse ".";
        const source_name = std.fs.path.basename(source_path);
        try files.put(source_path, 3);
        try file_nodes.append(.{
            .id = 3,
            .filename = source_name,
            .directory = source_dir,
        });

        return .{
            .source_path = source_path,
            .files = files,
            .file_nodes = file_nodes,
            .functions = functions,
            .locations = locations,
            .location_ids = location_ids,
        };
    }

    fn deinit(self: *DebugInfo) void {
        self.files.deinit();
        self.file_nodes.deinit();
        self.functions.deinit();
        self.locations.deinit();
        self.location_ids.deinit();
        self.* = undefined;
    }

    fn splitPath(path: []const u8) struct { filename: []const u8, directory: []const u8 } {
        return .{
            .filename = std.fs.path.basename(path),
            .directory = std.fs.path.dirname(path) orelse ".",
        };
    }

    fn ensureFile(self: *DebugInfo, path: []const u8) !u32 {
        if (self.files.get(path)) |id| return id;
        const id: u32 = self.next_id;
        self.next_id += 1;
        try self.files.put(path, id);
        const parts = splitPath(path);
        try self.file_nodes.append(.{
            .id = id,
            .filename = parts.filename,
            .directory = parts.directory,
        });
        return id;
    }

    fn ensureFunction(self: *DebugInfo, name: []const u8, linkage_name: []const u8, file_path: []const u8, line: u32) !DebugFunctionContext {
        const file_id = try self.ensureFile(file_path);
        const id: u32 = self.next_id;
        self.next_id += 1;
        try self.functions.append(.{
            .id = id,
            .name = name,
            .linkage_name = linkage_name,
            .file_id = file_id,
            .line = line,
        });
        return .{
            .subprogram_id = id,
            .file_id = file_id,
        };
    }

    fn ensureLocation(self: *DebugInfo, ctx: DebugFunctionContext, file_path: []const u8, line: u32, col: u32) !u32 {
        const file_id = try self.ensureFile(file_path);
        const key: u128 =
            (@as(u128, ctx.subprogram_id) << 96) |
            (@as(u128, file_id) << 64) |
            (@as(u128, line) << 32) |
            @as(u128, col);
        if (self.location_ids.get(key)) |id| return id;
        const id: u32 = self.next_id;
        self.next_id += 1;
        try self.location_ids.put(key, id);
        try self.locations.append(.{
            .id = id,
            .scope_id = ctx.subprogram_id,
            .line = line,
            .col = col,
        });
        return id;
    }

    fn emit(self: *DebugInfo, out: *std.ArrayList(u8)) !void {
        try emitLine(out, "");
        try emitLine(out, "!llvm.module.flags = !{!0, !1}");
        try emitLine(out, "!0 = !{i32 2, !\"Dwarf Version\", i32 4}");
        try emitLine(out, "!1 = !{i32 2, !\"Debug Info Version\", i32 3}");
        try out.writer().print("!llvm.dbg.cu = !{{!{d}}}\n", .{self.compileUnitId()});
        try out.writer().print("!{d} = distinct !DICompileUnit(language: DW_LANG_C99, file: !{d}, producer: \"saasm\", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)\n", .{ self.compileUnitId(), self.source_file_id });
        try out.writer().print("!{d} = !DISubroutineType(types: !{{}})\n", .{self.subroutine_type_id});

        for (self.file_nodes.items) |file| {
            try out.writer().print("!{d} = !DIFile(filename: \"{s}\", directory: \"{s}\")\n", .{ file.id, file.filename, file.directory });
        }

        for (self.functions.items) |func| {
            try out.writer().print("!{d} = distinct !DISubprogram(name: \"{s}\", linkageName: \"{s}\", scope: !{d}, file: !{d}, line: {d}, type: !{d}, unit: !{d}, scopeLine: {d}, spFlags: DISPFlagDefinition | DISPFlagOptimized)\n", .{ func.id, func.name, func.linkage_name, func.file_id, func.file_id, func.line, self.subroutine_type_id, self.compileUnitId(), func.line });
        }

        for (self.locations.items) |location| {
            try out.writer().print("!{d} = !DILocation(line: {d}, column: {d}, scope: !{d})\n", .{ location.id, location.line, location.col, location.scope_id });
        }
    }

    fn compileUnitId(self: *const DebugInfo) u32 {
        _ = self;
        return 2;
    }
};

fn emittedFunctionName(fsig: sig.FunctionSig) []const u8 {
    if (fsig.kind == .normal and fsig.params.len == 0 and std.mem.eql(u8, fsig.name, "main")) {
        return "saasm_main";
    }
    return fsig.name;
}

fn findFunctionSig(sigs: []const sig.FunctionSig, name: []const u8) ?sig.FunctionSig {
    for (sigs) |item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    }
    return null;
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

fn maskOf(tag: cap.CapabilityMask) u16 {
    return @intFromEnum(tag);
}

const NumericKind = enum {
    signed,
    unsigned,
    float,
};

fn numericKind(lhs: sig.PrimType, rhs: sig.PrimType) NumericKind {
    if (isFloatLike(lhs) or isFloatLike(rhs)) return .float;
    if (isSignedInt(lhs) or isSignedInt(rhs)) return .signed;
    return .unsigned;
}

fn opNumericKind(op: inst.OpKind, lhs: sig.PrimType, rhs: sig.PrimType) NumericKind {
    return switch (op) {
        .sdiv, .srem, .sgt, .slt, .sge, .sle, .ashr => .signed,
        .udiv, .urem, .ugt, .ult, .uge, .ule, .lshr => .unsigned,
        else => numericKind(lhs, rhs),
    };
}

fn opTargetType(op: inst.OpKind, lhs: sig.PrimType, rhs: sig.PrimType) sig.PrimType {
    const bits = @max(sig.primTypeBits(lhs), sig.primTypeBits(rhs));
    return switch (op) {
        .sdiv, .srem, .sgt, .slt, .sge, .sle, .ashr => intTypeForBits(bits, true),
        .udiv, .urem, .ugt, .ult, .uge, .ule, .lshr => intTypeForBits(bits, false),
        else => commonNumericType(lhs, rhs),
    };
}

fn legacyCompareMnemonic(op: inst.OpKind, kind: NumericKind) []const u8 {
    return switch (kind) {
        .float => switch (op) {
            .gt => "ogt",
            .lt => "olt",
            .eq => "oeq",
            .ne => "one",
            else => unreachable,
        },
        .signed => switch (op) {
            .gt => "sgt",
            .lt => "slt",
            .eq => "eq",
            .ne => "ne",
            else => unreachable,
        },
        .unsigned => switch (op) {
            .gt => "ugt",
            .lt => "ult",
            .eq => "eq",
            .ne => "ne",
            else => unreachable,
        },
    };
}

fn signedCompareMnemonic(op: inst.OpKind) []const u8 {
    return switch (op) {
        .sgt => "sgt",
        .slt => "slt",
        .sge => "sge",
        .sle => "sle",
        else => unreachable,
    };
}

fn floatCompareMnemonic(op: inst.OpKind) []const u8 {
    return switch (op) {
        .fcmp_eq => "oeq",
        .fcmp_ne => "one",
        .fcmp_lt => "olt",
        .fcmp_le => "ole",
        .fcmp_gt => "ogt",
        .fcmp_ge => "oge",
        else => unreachable,
    };
}

fn unsignedCompareMnemonic(op: inst.OpKind) []const u8 {
    return switch (op) {
        .ugt => "ugt",
        .ult => "ult",
        .uge => "uge",
        .ule => "ule",
        else => unreachable,
    };
}

fn intTypeForBits(bits: u32, signed: bool) sig.PrimType {
    if (bits <= 1) return .i1;
    if (bits <= 8) return if (signed) .i8 else .u8;
    if (bits <= 16) return if (signed) .i16 else .u16;
    if (bits <= 32) return if (signed) .i32 else .u32;
    return if (signed) .i64 else .u64;
}

fn commonFloatType(lhs: sig.PrimType, rhs: sig.PrimType) sig.PrimType {
    if (lhs == .f64 or rhs == .f64) return .f64;
    return .f32;
}

fn commonNumericType(lhs: sig.PrimType, rhs: sig.PrimType) sig.PrimType {
    return switch (numericKind(lhs, rhs)) {
        .float => commonFloatType(lhs, rhs),
        .signed => intTypeForBits(@max(sig.primTypeBits(lhs), sig.primTypeBits(rhs)), true),
        .unsigned => intTypeForBits(@max(sig.primTypeBits(lhs), sig.primTypeBits(rhs)), false),
    };
}

fn llvmTypeName(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .void => "void",
        .i1 => "i1",
        .i8, .u8 => "i8",
        .i16, .u16 => "i16",
        .i32, .u32 => "i32",
        .i64, .u64 => "i64",
        .f32 => "float",
        .f64 => "double",
        .ptr => "ptr",
        .v128 => "<16 x i8>",
    };
}

fn llvmAlign(ty: sig.PrimType) u32 {
    return switch (ty) {
        .void => 1,
        .i1 => 1,
        .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32, .f32 => 4,
        .i64, .u64, .f64, .ptr => 8,
        .v128 => 16,
    };
}

fn writeValueType(writer: anytype, value: Value) !void {
    if (value.fallible) {
        try writer.writeAll("{i32, ");
        try writer.writeAll(llvmTypeName(value.ty));
        try writer.writeAll("}");
        return;
    }
    try writer.writeAll(llvmTypeName(value.ty));
}

fn sizePrimType(size_bits: u16) sig.PrimType {
    return if (size_bits == 32) .u32 else .u64;
}

fn sizeTypeName(size_bits: u16) []const u8 {
    return llvmTypeName(sizePrimType(size_bits));
}

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

fn atomicOrderingName(item: inst.Instruction) []const u8 {
    return atomic.llvmOrderingName(item.atomic_ordering orelse .seq_cst);
}

fn atomicSecondOrderingName(item: inst.Instruction) []const u8 {
    return atomic.llvmOrderingName(item.atomic_second_ordering orelse .acquire);
}

fn writeCmpxchgResultType(writer: anytype, value_ty: sig.PrimType) !void {
    try writer.writeByte('{');
    try writer.writeAll(llvmTypeName(value_ty));
    try writer.writeAll(", i1}");
}

fn writeReturnAbiType(
    writer: anytype,
    return_cap: ?inst.CapPrefix,
    return_ty: sig.PrimType,
    return_fallible: bool,
) !void {
    const value_ty = returnTypeForSig(return_cap, return_ty);
    if (return_fallible) {
        try writer.writeAll("{i32, ");
        try writer.writeAll(llvmTypeName(value_ty));
        try writer.writeByte('}');
        return;
    }
    try writer.writeAll(llvmTypeName(value_ty));
}

fn emitLine(out: *std.ArrayList(u8), text: []const u8) !void {
    try out.appendSlice(text);
    try out.append('\n');
}

fn emitIndented(out: *std.ArrayList(u8), text: []const u8) !void {
    try out.appendSlice("  ");
    try emitLine(out, text);
}

fn parseImmediateValue(allocator: std.mem.Allocator, state: *FunctionState, text: []const u8) !Value {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return EmitError.InvalidOperand;
    if (std.mem.indexOfScalar(u8, trimmed, '.') != null) {
        const num = try std.fmt.parseFloat(f64, trimmed);
        return .{ .expr = try state.ownFmt(allocator, "{d}", .{num}), .ty = .f64 };
    }
    const num = try std.fmt.parseInt(i64, trimmed, 10);
    return .{ .expr = try state.ownFmt(allocator, "{d}", .{num}), .ty = .i64 };
}

fn valueFromOperand(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    op: inst.Operand,
) !Value {
    return switch (op) {
        .reg => |id| state.getReg(id) orelse EmitError.InvalidOperand,
        .text => |t| blk: {
            if (t.len >= 2 and t[0] == '&' and (std.ascii.isAlphabetic(t[1]) or t[1] == '_')) {
                const name = t[1..];
                if (state.hasConstRef(name)) {
                    break :blk .{ .expr = try state.ownFmt(allocator, "@{s}", .{name}), .ty = .ptr, .const_ref = name, .origin = .{ .const_name = name } };
                }
                if (symbols.findId(name)) |id| {
                    break :blk state.getReg(id) orelse EmitError.InvalidOperand;
                }
            }
            if (t.len != 0 and (std.ascii.isAlphabetic(t[0]) or t[0] == '_')) {
                if (state.hasConstRef(t)) {
                    break :blk .{ .expr = try state.ownFmt(allocator, "@{s}", .{t}), .ty = .ptr, .const_ref = t, .origin = .{ .const_name = t } };
                }
                if (symbols.findId(t)) |id| {
                    break :blk state.getReg(id) orelse EmitError.InvalidOperand;
                }
            }
            break :blk try parseImmediateValue(allocator, state, t);
        },
        .imm_i64 => |v| .{ .expr = try state.ownFmt(allocator, "{d}", .{v}), .ty = .i64 },
        .imm_u64 => |v| .{ .expr = try state.ownFmt(allocator, "{d}", .{v}), .ty = .u64 },
        .imm_int => |v| .{ .expr = try state.ownFmt(allocator, "{d}", .{v}), .ty = .i64 },
        .imm_float => |v| .{ .expr = try state.ownFmt(allocator, "{d}", .{v}), .ty = .f64 },
        else => EmitError.InvalidOperand,
    };
}

fn castValue(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    value: Value,
    target: sig.PrimType,
) !Value {
    if (value.fallible) return EmitError.InvalidOperand;
    if (value.ty == target) return value;

    if (target == .ptr) {
        if (value.ty == .ptr) return value;
        if (!isIntLike(value.ty)) return EmitError.UnsupportedType;
        const tmp = try state.tempName(allocator);
        try out.writer().print("  {s} = inttoptr {s} {s} to ptr\n", .{ tmp, llvmTypeName(value.ty), value.expr });
        return .{ .expr = tmp, .ty = .ptr, .interior_ptr = value.interior_ptr };
    }

    if (value.ty == .ptr) {
        if (!isIntLike(target)) return EmitError.UnsupportedType;
        const tmp = try state.tempName(allocator);
        try out.writer().print("  {s} = ptrtoint ptr {s} to {s}\n", .{ tmp, value.expr, llvmTypeName(target) });
        return .{ .expr = tmp, .ty = target };
    }

    if (isIntLike(value.ty) and isIntLike(target)) {
        const src_bits = sig.primTypeBits(value.ty);
        const dst_bits = sig.primTypeBits(target);
        const tmp = try state.tempName(allocator);
        if (src_bits == dst_bits) {
            return .{ .expr = value.expr, .ty = target };
        } else if (src_bits < dst_bits) {
            const op = if (isSignedInt(value.ty)) "sext" else "zext";
            try out.writer().print("  {s} = {s} {s} {s} to {s}\n", .{ tmp, op, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        } else {
            try out.writer().print("  {s} = trunc {s} {s} to {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        }
        return .{ .expr = tmp, .ty = target };
    }

    if (isFloatLike(value.ty) and isFloatLike(target)) {
        const tmp = try state.tempName(allocator);
        if (sig.primTypeBits(value.ty) == sig.primTypeBits(target)) return value;
        if (sig.primTypeBits(value.ty) < sig.primTypeBits(target)) {
            try out.writer().print("  {s} = fpext {s} {s} to {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        } else {
            try out.writer().print("  {s} = fptrunc {s} {s} to {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        }
        return .{ .expr = tmp, .ty = target };
    }

    if (isIntLike(value.ty) and isFloatLike(target)) {
        const tmp = try state.tempName(allocator);
        const op = if (isSignedInt(value.ty)) "sitofp" else "uitofp";
        try out.writer().print("  {s} = {s} {s} {s} to {s}\n", .{ tmp, op, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        return .{ .expr = tmp, .ty = target };
    }

    if (isFloatLike(value.ty) and isIntLike(target)) {
        const tmp = try state.tempName(allocator);
        const op = if (isSignedInt(target)) "fptosi" else "fptoui";
        try out.writer().print("  {s} = {s} {s} {s} to {s}\n", .{ tmp, op, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        return .{ .expr = tmp, .ty = target };
    }

    return EmitError.UnsupportedType;
}

fn emitPointerArithmetic(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    opcode: inst.OpKind,
    lhs: Value,
    rhs: Value,
) !Value {
    const ptr_value = if (lhs.ty == .ptr) lhs else rhs;
    const offset_value = if (lhs.ty == .ptr) rhs else lhs;
    const ptr_expr = try castValue(allocator, out, state, ptr_value, .ptr);
    var offset_expr = try castValue(allocator, out, state, offset_value, .i64);

    if (opcode == .sub) {
        const neg = try state.tempName(allocator);
        try out.writer().print("  {s} = sub i64 0, {s}\n", .{ neg, offset_expr.expr });
        offset_expr = .{ .expr = neg, .ty = .i64 };
    }

    const gep = try state.tempName(allocator);
    try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {s}\n", .{ gep, ptr_expr.expr, offset_expr.expr });
    var origin = ptr_expr.origin;
    if (origin.const_name != null) {
        if (std.fmt.parseInt(i64, offset_expr.expr, 10)) |delta| {
            const base_off: i128 = @intCast(origin.const_offset);
            const signed_delta: i128 = if (opcode == .sub) -@as(i128, delta) else @as(i128, delta);
            const next = base_off + signed_delta;
            if (next >= 0 and next <= std.math.maxInt(u64)) {
                origin.const_offset = @as(u64, @intCast(next));
            }
        } else |_| {}
    }
    return .{
        .expr = gep,
        .ty = .ptr,
        .interior_ptr = true,
        .const_ref = ptr_expr.const_ref,
        .origin = origin,
    };
}

fn emitHelpers(out: *std.ArrayList(u8), size_bits: u16, options: EmitOptions) !void {
    const size_ty_name = sizeTypeName(size_bits);
    try emitLine(out, "; SA-ASM LLVM IR");
    try emitLine(out, "");
    try emitLine(out, "@saasm_argc = internal global i32 0");
    try emitLine(out, "@saasm_argv = internal global ptr null");
    try emitLine(out, "@.mode_rb = private unnamed_addr constant [3 x i8] c\"rb\\00\"");
    try emitLine(out, "@.mode_wb = private unnamed_addr constant [3 x i8] c\"wb\\00\"");
    try emitLine(out, "");
    try out.writer().print("declare ptr @malloc({s})\n", .{size_ty_name});
    try emitLine(out, "declare void @free(ptr)");
    try out.writer().print("declare ptr @memcpy(ptr, ptr, {s})\n", .{size_ty_name});
    try emitLine(out, "declare ptr @fopen(ptr, ptr)");
    try emitLine(out, "declare i32 @fseek(ptr, i64, i32)");
    try emitLine(out, "declare i64 @ftell(ptr)");
    try emitLine(out, "declare void @rewind(ptr)");
    try out.writer().print("declare {s} @fread(ptr, {s}, {s}, ptr)\n", .{ size_ty_name, size_ty_name, size_ty_name });
    try out.writer().print("declare {s} @fwrite(ptr, {s}, {s}, ptr)\n", .{ size_ty_name, size_ty_name, size_ty_name });
    try emitLine(out, "declare i32 @fclose(ptr)");
    try out.writer().print("declare {s} @write(i32, ptr, {s})\n", .{ size_ty_name, size_ty_name });
    try emitLine(out, "declare void @exit(i32)");
    try emitLine(out, "declare i32 @fprintf(ptr, ptr, ...)");
    try emitLine(out, "@stderr = external global ptr");
    try out.writer().print("@.panic_code_fmt = private unnamed_addr constant [{d} x i8] c\"PANIC: code=%d\\0A\\00\"\n", .{"PANIC: code=%d\n".len + 1});
    try out.writer().print("@.panic_msg_fmt = private unnamed_addr constant [{d} x i8] c\"PANIC[%d]: %.*s\\0A\\00\"\n", .{"PANIC[%d]: %.*s\n".len + 1});
    try emitLine(out, "");

    const stderr_align: u32 = if (size_bits == 32) 4 else 8;
    try out.writer().print("define void @__sa_panic(i32 %code, ptr %msg, {s} %len) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try out.writer().print("  %stderr = load ptr, ptr @stderr, align {d}\n", .{stderr_align});
    try emitLine(out, "  %has_msg_ptr = icmp ne ptr %msg, null");
    try out.writer().print("  %has_msg_len = icmp ne {s} %len, 0\n", .{size_ty_name});
    try emitLine(out, "  %has_msg = and i1 %has_msg_ptr, %has_msg_len");
    try emitLine(out, "  br i1 %has_msg, label %with_msg, label %no_msg");
    try emitLine(out, "with_msg:");
    try emitLine(out, "  %msg_fmt_ptr = getelementptr [17 x i8], ptr @.panic_msg_fmt, i32 0, i32 0");
    if (size_bits == 32) {
        try emitLine(out, "  %_msg = call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr %msg_fmt_ptr, i32 %code, i32 %len, ptr %msg)");
    } else {
        try emitLine(out, "  %msg_len32 = trunc i64 %len to i32");
        try emitLine(out, "  %_msg = call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr %msg_fmt_ptr, i32 %code, i32 %msg_len32, ptr %msg)");
    }
    try emitLine(out, "  br label %done");
    try emitLine(out, "no_msg:");
    try emitLine(out, "  %code_fmt_ptr = getelementptr [16 x i8], ptr @.panic_code_fmt, i32 0, i32 0");
    try emitLine(out, "  %_code = call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr %code_fmt_ptr, i32 %code)");
    try emitLine(out, "  br label %done");
    try emitLine(out, "done:");
    try emitLine(out, "  %code_masked = and i32 %code, 127");
    try emitLine(out, "  %exit_code = add i32 %code_masked, 128");
    try emitLine(out, "  call void @exit(i32 %exit_code)");
    try emitLine(out, "  unreachable");
    try emitLine(out, "}");
    try emitLine(out, "");

    try out.writer().print("define ptr @saasm_strdupz(ptr %src, {s} %len) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try out.writer().print("  %size = add {s} %len, 1\n", .{size_ty_name});
    try out.writer().print("  %buf = call ptr @malloc({s} %size)\n", .{size_ty_name});
    try out.writer().print("  %copy = call ptr @memcpy(ptr %buf, ptr %src, {s} %len)\n", .{size_ty_name});
    try out.writer().print("  %end = getelementptr i8, ptr %buf, {s} %len\n", .{size_ty_name});
    try emitLine(out, "  store i8 0, ptr %end, align 1");
    try emitLine(out, "  ret ptr %buf");
    try emitLine(out, "}");
    try emitLine(out, "");

    try out.writer().print("define void @sys_print(ptr %msg, {s} %len) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try out.writer().print("  %_ = call {s} @write(i32 1, ptr %msg, {s} %len)\n", .{ size_ty_name, size_ty_name });
    try emitLine(out, "  ret void");
    try emitLine(out, "}");
    try emitLine(out, "");

    if (options.wasm_compat) {
        try emitLine(out, "define void @sa_print_bytes(ptr %msg, i64 %len) {");
        try emitLine(out, "entry:");
        if (size_bits == 32) {
            try emitLine(out, "  %len32 = trunc i64 %len to i32");
            try emitLine(out, "  %_ = call i32 @write(i32 1, ptr %msg, i32 %len32)");
        } else {
            try emitLine(out, "  %_ = call i64 @write(i32 1, ptr %msg, i64 %len)");
        }
        try emitLine(out, "  ret void");
        try emitLine(out, "}");
        try emitLine(out, "");
    }

    try emitLine(out, "define void @sys_exit(i32 %code) {");
    try emitLine(out, "entry:");
    try emitLine(out, "  call void @exit(i32 %code)");
    try emitLine(out, "  unreachable");
    try emitLine(out, "}");
    try emitLine(out, "");

    try emitLine(out, "define i32 @sys_argc() {");
    try emitLine(out, "entry:");
    try emitLine(out, "  %argc = load i32, ptr @saasm_argc, align 4");
    try emitLine(out, "  ret i32 %argc");
    try emitLine(out, "}");
    try emitLine(out, "");

    try out.writer().print("define ptr @sys_argv({s} %index) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try emitLine(out, "  %argv = load ptr, ptr @saasm_argv, align 8");
    try out.writer().print("  %slot = getelementptr ptr, ptr %argv, {s} %index\n", .{size_ty_name});
    try emitLine(out, "  %res = load ptr, ptr %slot, align 8");
    try emitLine(out, "  ret ptr %res");
    try emitLine(out, "}");
    try emitLine(out, "");

    if (size_bits == 32) {
        try emitLine(out, "define ptr @sys_read_file(ptr %path, i32 %path_len, ptr %out_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @saasm_strdupz(ptr %path, i32 %path_len)");
        try emitLine(out, "  %mode_ptr = getelementptr [3 x i8], ptr @.mode_rb, i32 0, i32 0");
        try emitLine(out, "  %file = call ptr @fopen(ptr %path_c, ptr %mode_ptr)");
        try emitLine(out, "  call void @free(ptr %path_c)");
        try emitLine(out, "  %is_null = icmp eq ptr %file, null");
        try emitLine(out, "  br i1 %is_null, label %fail, label %ok");
        try emitLine(out, "fail:");
        try emitLine(out, "  store i32 0, ptr %out_len, align 4");
        try emitLine(out, "  ret ptr null");
        try emitLine(out, "ok:");
        try emitLine(out, "  %seek = call i32 @fseek(ptr %file, i64 0, i32 2)");
        try emitLine(out, "  %size64 = call i64 @ftell(ptr %file)");
        try emitLine(out, "  call void @rewind(ptr %file)");
        try emitLine(out, "  %size = trunc i64 %size64 to i32");
        try emitLine(out, "  %buf = call ptr @malloc(i32 %size)");
        try emitLine(out, "  %read = call i32 @fread(ptr %buf, i32 1, i32 %size, ptr %file)");
        try emitLine(out, "  call i32 @fclose(ptr %file)");
        try emitLine(out, "  store i32 %size, ptr %out_len, align 4");
        try emitLine(out, "  ret ptr %buf");
        try emitLine(out, "}");
        try emitLine(out, "");

        try emitLine(out, "define i32 @sys_write_file(ptr %path, i32 %path_len, ptr %data, i32 %data_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @saasm_strdupz(ptr %path, i32 %path_len)");
        try emitLine(out, "  %mode_ptr = getelementptr [3 x i8], ptr @.mode_wb, i32 0, i32 0");
        try emitLine(out, "  %file = call ptr @fopen(ptr %path_c, ptr %mode_ptr)");
        try emitLine(out, "  call void @free(ptr %path_c)");
        try emitLine(out, "  %is_null = icmp eq ptr %file, null");
        try emitLine(out, "  br i1 %is_null, label %fail, label %ok");
        try emitLine(out, "fail:");
        try emitLine(out, "  ret i32 -1");
        try emitLine(out, "ok:");
        try emitLine(out, "  %written = call i32 @fwrite(ptr %data, i32 1, i32 %data_len, ptr %file)");
        try emitLine(out, "  call i32 @fclose(ptr %file)");
        try emitLine(out, "  ret i32 %written");
        try emitLine(out, "}");
        try emitLine(out, "");
    } else {
        try emitLine(out, "define ptr @sys_read_file(ptr %path, i64 %path_len, ptr %out_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @saasm_strdupz(ptr %path, i64 %path_len)");
        try emitLine(out, "  %mode_ptr = getelementptr [3 x i8], ptr @.mode_rb, i32 0, i32 0");
        try emitLine(out, "  %file = call ptr @fopen(ptr %path_c, ptr %mode_ptr)");
        try emitLine(out, "  call void @free(ptr %path_c)");
        try emitLine(out, "  %is_null = icmp eq ptr %file, null");
        try emitLine(out, "  br i1 %is_null, label %fail, label %ok");
        try emitLine(out, "fail:");
        try emitLine(out, "  store i64 0, ptr %out_len, align 8");
        try emitLine(out, "  ret ptr null");
        try emitLine(out, "ok:");
        try emitLine(out, "  %seek = call i32 @fseek(ptr %file, i64 0, i32 2)");
        try emitLine(out, "  %size64 = call i64 @ftell(ptr %file)");
        try emitLine(out, "  call void @rewind(ptr %file)");
        try emitLine(out, "  %buf = call ptr @malloc(i64 %size64)");
        try emitLine(out, "  %read = call i64 @fread(ptr %buf, i64 1, i64 %size64, ptr %file)");
        try emitLine(out, "  call i32 @fclose(ptr %file)");
        try emitLine(out, "  store i64 %size64, ptr %out_len, align 8");
        try emitLine(out, "  ret ptr %buf");
        try emitLine(out, "}");
        try emitLine(out, "");

        try emitLine(out, "define i32 @sys_write_file(ptr %path, i64 %path_len, ptr %data, i64 %data_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @saasm_strdupz(ptr %path, i64 %path_len)");
        try emitLine(out, "  %mode_ptr = getelementptr [3 x i8], ptr @.mode_wb, i32 0, i32 0");
        try emitLine(out, "  %file = call ptr @fopen(ptr %path_c, ptr %mode_ptr)");
        try emitLine(out, "  call void @free(ptr %path_c)");
        try emitLine(out, "  %is_null = icmp eq ptr %file, null");
        try emitLine(out, "  br i1 %is_null, label %fail, label %ok");
        try emitLine(out, "fail:");
        try emitLine(out, "  ret i32 -1");
        try emitLine(out, "ok:");
        try emitLine(out, "  %written = call i64 @fwrite(ptr %data, i64 1, i64 %data_len, ptr %file)");
        try emitLine(out, "  call i32 @fclose(ptr %file)");
        try emitLine(out, "  %status = trunc i64 %written to i32");
        try emitLine(out, "  ret i32 %status");
        try emitLine(out, "}");
        try emitLine(out, "");
    }
}

fn emitFunctionHeader(out: *std.ArrayList(u8), state: *FunctionState, dbg_id: ?u32) !void {
    try out.appendSlice("define ");
    try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, state.sig.return_fallible);
    try out.writer().print(" @{s}(", .{state.emitted_name});
    for (state.sig.params, 0..) |param, idx| {
        if (idx != 0) try out.appendSlice(", ");
        const ty = valueTypeForPrefix(param.cap, param.ty);
        try out.writer().print("{s} %{s}", .{ llvmTypeName(ty), param.name });
    }
    try out.appendSlice(")");
    if (dbg_id) |id| {
        try out.writer().print(" !dbg !{d}", .{id});
    }
    try emitLine(out, " {");
    try emitLine(out, "entry:");
}

fn emitFunctionFooter(out: *std.ArrayList(u8)) !void {
    try emitLine(out, "}");
    try emitLine(out, "");
}

fn emitArgList(
    allocator: std.mem.Allocator,
    prelude: *std.ArrayList(u8),
    stmt: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    args: []const call.ParsedArg,
    params: []const sig.ParamSpec,
) !void {
    for (args, params, 0..) |arg, param, idx| {
        if (idx != 0) try stmt.appendSlice(", ");
        const expected = valueTypeForPrefix(param.cap, param.ty);
        const value = try valueFromArgText(allocator, state, symbols, arg.text);
        const coerced = try castValue(allocator, prelude, state, value, expected);
        try stmt.writer().print("{s} {s}", .{ llvmTypeName(expected), coerced.expr });
    }
}

fn valueFromArgText(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    text: []const u8,
) !Value {
    if (text.len >= 2 and text[0] == '&' and (std.ascii.isAlphabetic(text[1]) or text[1] == '_')) {
        const name = text[1..];
        if (state.hasConstRef(name)) {
            return .{ .expr = try state.ownFmt(allocator, "@{s}", .{name}), .ty = .ptr, .const_ref = name, .origin = .{ .const_name = name } };
        }
    }
    if (text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_')) {
        if (state.hasConstRef(text)) {
            return .{ .expr = try state.ownFmt(allocator, "@{s}", .{text}), .ty = .ptr, .const_ref = text, .origin = .{ .const_name = text } };
        }
        if (symbols.findId(text)) |id| {
            return state.getReg(id) orelse EmitError.InvalidOperand;
        }
    }
    return try parseImmediateValue(allocator, state, text);
}

fn valueFromRegOrConst(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    reg_id: u32,
) !Value {
    if (state.getReg(reg_id)) |value| return value;
    const name = symbols.lookupName(reg_id) orelse return EmitError.InvalidOperand;
    if (!state.hasConstRef(name)) return EmitError.InvalidOperand;
    return .{
        .expr = try state.ownFmt(allocator, "@{s}", .{name}),
        .ty = .ptr,
        .const_ref = name,
        .origin = .{ .const_name = name },
    };
}

fn emitByteEscape(out: *std.ArrayList(u8), byte: u8) !void {
    switch (byte) {
        '\\' => try out.appendSlice("\\5C"),
        '"' => try out.appendSlice("\\22"),
        '\n' => try out.appendSlice("\\0A"),
        '\r' => try out.appendSlice("\\0D"),
        '\t' => try out.appendSlice("\\09"),
        else => {
            const hex = "0123456789ABCDEF";
            try out.append('\\');
            try out.append(hex[(byte >> 4) & 0x0f]);
            try out.append(hex[byte & 0x0f]);
        },
    }
}

fn findConstDeclByName(const_decls: []const common_const_decl.ConstDecl, name: []const u8) ?common_const_decl.ConstDecl {
    for (const_decls) |decl| {
        if (std.mem.eql(u8, decl.name, name)) return decl;
    }
    return null;
}

fn findFunctionSigIndex(sigs: []const sig.FunctionSig, name: []const u8) ?usize {
    for (sigs, 0..) |item, idx| {
        if (std.mem.eql(u8, item.name, name)) return idx;
    }
    return null;
}

fn constByteLen(value: common_const_decl.ConstValue) !u64 {
    return switch (value) {
        .hex => |literal| @as(u64, @intCast(literal.bytes.len)),
        .utf8 => |literal| @as(u64, @intCast(literal.bytes.len)),
        .repeat => |literal| @as(u64, @intCast(literal.bytes.len)),
        .struct_ => |literal| blk: {
            var total: u64 = 0;
            for (literal.fields) |field| {
                const len = try constByteLen(field.value);
                if (len != field.size) return EmitError.InvalidOperand;
                total = std.math.add(u64, total, len) catch return EmitError.InvalidOperand;
            }
            break :blk total;
        },
        .vtable => return EmitError.UnsupportedType,
    };
}

fn appendConstBytes(out: *std.ArrayList(u8), value: common_const_decl.ConstValue) !void {
    switch (value) {
        .hex => |literal| try out.appendSlice(literal.bytes),
        .utf8 => |literal| try out.appendSlice(literal.bytes),
        .repeat => |literal| try out.appendSlice(literal.bytes),
        .struct_ => |literal| {
            for (literal.fields) |field| {
                try appendConstBytes(out, field.value);
            }
        },
        .vtable => return EmitError.UnsupportedType,
    }
}

fn emitConstDecls(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
) !void {
    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                if (literal.slots.len == 0) return EmitError.InvalidOperand;
                try out.writer().print("@{s} = private unnamed_addr constant [{d} x ptr] [", .{ decl.name, literal.slots.len });
                for (literal.slots, 0..) |slot, idx| {
                    if (idx != 0) try out.appendSlice(", ");
                    const fn_sig = findFunctionSigIndex(sigs, slot.func_name) orelse return EmitError.UnknownFunction;
                    _ = fn_sig;
                    try out.writer().print("ptr @{s}", .{emittedFunctionName(sigs[findFunctionSigIndex(sigs, slot.func_name).?])});
                }
                try emitLine(out, "]");
            },
            else => {
                const len = try constByteLen(decl.value);
                var bytes = std.ArrayList(u8).init(allocator);
                defer bytes.deinit();
                try appendConstBytes(&bytes, decl.value);
                if (bytes.items.len != len) return EmitError.InvalidOperand;
                try out.writer().print("@{s} = private unnamed_addr constant [{d} x i8] c\"", .{ decl.name, len });
                for (bytes.items) |byte| {
                    try emitByteEscape(out, byte);
                }
                try out.appendSlice("\"\n");
            },
        }
    }
    if (const_decls.len != 0) try emitLine(out, "");
}

fn resolveConstValueOrigin(
    value: common_const_decl.ConstValue,
    const_name: []const u8,
    offset: u64,
    loaded_ty: sig.PrimType,
    sigs: []const sig.FunctionSig,
) PointerOrigin {
    const base: PointerOrigin = .{ .const_name = const_name, .const_offset = offset };
    return switch (value) {
        .vtable => |literal| blk: {
            if (loaded_ty != .ptr or offset % 8 != 0) break :blk base;
            const slot_index: usize = @intCast(offset / 8);
            if (slot_index >= literal.slots.len) break :blk base;
            const sig_index = findFunctionSigIndex(sigs, literal.slots[slot_index].func_name) orelse break :blk base;
            break :blk .{ .const_name = const_name, .const_offset = offset, .indirect_sig_index = sig_index };
        },
        .struct_ => |literal| blk: {
            var cursor: u64 = 0;
            for (literal.fields) |field| {
                const next = std.math.add(u64, cursor, field.size) catch break :blk base;
                if (offset < next) {
                    const nested = resolveConstValueOrigin(field.value, const_name, offset - cursor, loaded_ty, sigs);
                    break :blk nested;
                }
                cursor = next;
            }
            break :blk base;
        },
        else => base,
    };
}

fn resolveLoadOrigin(
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    src: Value,
    offset: u64,
    loaded_ty: sig.PrimType,
) PointerOrigin {
    const const_name = src.origin.const_name orelse src.const_ref orelse return .{};
    const decl = findConstDeclByName(const_decls, const_name) orelse return .{ .const_name = const_name };
    return resolveConstValueOrigin(decl.value, const_name, offset, loaded_ty, sigs);
}

fn findVtableSlotSigIndexByName(
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    slot_name: []const u8,
) ?usize {
    var resolved: ?usize = null;
    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                for (literal.slots) |slot| {
                    if (!std.mem.eql(u8, slot.name, slot_name)) continue;
                    const sig_index = findFunctionSigIndex(sigs, slot.func_name) orelse return null;
                    if (resolved) |existing| {
                        const existing_sig = sigs[existing];
                        const candidate_sig = sigs[sig_index];
                        if (!functionSigsCompatible(existing_sig, candidate_sig)) return null;
                    } else {
                        resolved = sig_index;
                    }
                }
            },
            else => {},
        }
    }
    return resolved;
}

fn functionSigsCompatible(a: sig.FunctionSig, b: sig.FunctionSig) bool {
    if (a.return_cap != b.return_cap) return false;
    if (a.return_ty != b.return_ty) return false;
    if (a.return_fallible != b.return_fallible) return false;
    if (a.params.len != b.params.len) return false;
    for (a.params, b.params) |ap, bp| {
        if (ap.cap != bp.cap) return false;
        if (ap.ty != bp.ty) return false;
    }
    return true;
}

fn inferIndirectSigIndexFromLoadText(
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    raw_text: []const u8,
) ?usize {
    const load_idx = std.mem.indexOf(u8, raw_text, "load") orelse return null;
    const after_load = std.mem.trimLeft(u8, raw_text[load_idx + "load".len ..], " \t");
    const as_idx = std.mem.indexOf(u8, after_load, " as") orelse after_load.len;
    const address = std.mem.trim(u8, after_load[0..as_idx], " \t");
    const plus = std.mem.lastIndexOfScalar(u8, address, '+') orelse return null;
    const offset_token = std.mem.trim(u8, address[plus + 1 ..], " \t");
    if (offset_token.len == 0) return null;

    if (findVtableSlotSigIndexByName(const_decls, sigs, offset_token)) |sig_index| {
        return sig_index;
    }

    var search_start: usize = 0;
    while (std.mem.indexOfScalarPos(u8, offset_token, search_start, '_')) |underscore| : (search_start = underscore + 1) {
        const candidate = std.mem.trim(u8, offset_token[underscore + 1 ..], " \t");
        if (candidate.len == 0 or !isIdentLike(candidate)) continue;
        if (findVtableSlotSigIndexByName(const_decls, sigs, candidate)) |sig_index| {
            return sig_index;
        }
    }
    return null;
}

fn emitBuiltinCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    options: EmitOptions,
    size_bits: u16,
    parsed: call.ParsedCall,
) !BuiltinCallResult {
    _ = options;
    const size_ty_name = sizeTypeName(size_bits);
    const name = parsed.callee;
    if (std.mem.eql(u8, name, "panic")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        if (parsed.args.len != 1) return EmitError.InvalidOperand;
        const code = try valueFromArgText(allocator, state, symbols, parsed.args[0].text);
        const code_i32 = try castValue(allocator, &prelude, state, code, .i32);
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @__sa_panic(i32 {s}, ptr null, {s} 0)\n", .{ code_i32.expr, size_ty_name });
        try emitLine(out, "  unreachable");
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "panic_msg")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        if (parsed.args.len != 3) return EmitError.InvalidOperand;
        const code = try castValue(allocator, &prelude, state, try valueFromArgText(allocator, state, symbols, parsed.args[0].text), .i32);
        const msg = try castValue(allocator, &prelude, state, try valueFromArgText(allocator, state, symbols, parsed.args[1].text), .ptr);
        const len_ty: sig.PrimType = sizePrimType(size_bits);
        const len = try castValue(allocator, &prelude, state, try valueFromArgText(allocator, state, symbols, parsed.args[2].text), len_ty);
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @__sa_panic(i32 {s}, ptr {s}, {s} {s})\n", .{ code.expr, msg.expr, size_ty_name, len.expr });
        try emitLine(out, "  unreachable");
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "sys_argc")) {
        const tmp = try state.tempName(allocator);
        try out.writer().print("  {s} = call i32 @sys_argc()\n", .{tmp});
        return .{ .handled_value = .{ .expr = tmp, .ty = .i32 } };
    }
    if (std.mem.eql(u8, name, "sys_argv")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "index", .ty = .i64, .cap = .by_value }});
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call ptr @sys_argv({s})\n", .{ tmp, args_buf.items });
        return .{ .handled_value = .{ .expr = tmp, .ty = .ptr } };
    }
    if (std.mem.eql(u8, name, "sys_print")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{ .{ .name = "msg", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value } });
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @sys_print({s})\n", .{args_buf.items});
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "sys_exit")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "code", .ty = .i32, .cap = .by_value }});
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @sys_exit({s})\n", .{args_buf.items});
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "sys_read_file")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{ .{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "out_len", .ty = .ptr, .cap = .raw } });
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call ptr @sys_read_file({s})\n", .{ tmp, args_buf.items });
        return .{ .handled_value = .{ .expr = tmp, .ty = .ptr } };
    }
    if (std.mem.eql(u8, name, "sys_write_file")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{ .{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "data", .ty = .ptr, .cap = .raw }, .{ .name = "dlen", .ty = .i64, .cap = .by_value } });
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call i32 @sys_write_file({s})\n", .{ tmp, args_buf.items });
        return .{ .handled_value = .{ .expr = tmp, .ty = .i32 } };
    }
    return .not_builtin;
}

fn emitDirectCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    parsed: call.ParsedCall,
) !DirectCallResult {
    _ = options;
    const resolved = findFunctionSig(sigs, parsed.callee) orelse return .not_direct;
    const ret_ty = returnTypeForSig(resolved.return_cap, resolved.return_ty);
    if (parsed.args.len != resolved.params.len) return EmitError.InvalidOperand;

    if (ret_ty != .void) {
        if (resolved.return_fallible and ret_ty == .void) return EmitError.UnsupportedType;
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, resolved.params);
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call ", .{tmp});
        try writeReturnAbiType(out.writer(), resolved.return_cap, resolved.return_ty, resolved.return_fallible);
        try out.writer().print(" @{s}({s})\n", .{ emittedFunctionName(resolved), args_buf.items });
        return .{ .handled_value = .{ .expr = tmp, .ty = ret_ty, .fallible = resolved.return_fallible } };
    } else {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, resolved.params);
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @{s}({s})\n", .{ emittedFunctionName(resolved), args_buf.items });
        return .handled_void;
    }
}

fn emitIndirectCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    parsed: call.ParsedCall,
) !?Value {
    const callee_id = symbols.findId(parsed.callee) orelse return EmitError.UnknownFunction;
    const callee = state.getReg(callee_id) orelse return EmitError.InvalidOperand;
    if (callee.origin.indirect_sig_index == null) {
        if (options.debug) {
            std.debug.print(
                "emit indirect missing provenance for {s}: expr={s} const={?s}\n",
                .{ parsed.callee, callee.expr, callee.origin.const_name },
            );
        }
        return EmitError.MissingIndirectCallProvenance;
    }
    const sig_index = callee.origin.indirect_sig_index.?;
    if (sig_index >= sigs.len) {
        if (options.debug) {
            std.debug.print(
                "emit indirect provenance out of range for {s}: expr={s} sig_index={d} sigs_len={d}\n",
                .{ parsed.callee, callee.expr, sig_index, sigs.len },
            );
        }
        return EmitError.MissingIndirectCallProvenance;
    }

    const resolved = sigs[sig_index];
    if (parsed.args.len != resolved.params.len) return EmitError.InvalidOperand;

    var prelude = std.ArrayList(u8).init(allocator);
    defer prelude.deinit();
    var args_buf = std.ArrayList(u8).init(allocator);
    defer args_buf.deinit();
    try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, resolved.params);
    try out.appendSlice(prelude.items);

    const call_ty = returnTypeForSig(resolved.return_cap, resolved.return_ty);
    const tmp = if (call_ty == .void) null else try state.tempName(allocator);
    if (tmp) |tmp_name| {
        try out.writer().print("  {s} = call {s} {s}({s})\n", .{ tmp_name, llvmTypeName(call_ty), callee.expr, args_buf.items });
        return .{ .expr = tmp_name, .ty = call_ty, .fallible = resolved.return_fallible };
    }
    try out.writer().print("  call void {s}({s})\n", .{ callee.expr, args_buf.items });
    return null;
}

fn emitCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    size_bits: u16,
    parsed: call.ParsedCall,
) !?Value {
    if (parsed.is_indirect) {
        return try emitIndirectCall(allocator, out, state, symbols, sigs, options, parsed);
    }

    switch (try emitBuiltinCall(allocator, out, state, symbols, options, size_bits, parsed)) {
        .handled_void => return null,
        .handled_value => |value| return value,
        .not_builtin => {},
    }
    switch (try emitDirectCall(allocator, out, state, symbols, sigs, options, parsed)) {
        .not_direct => {},
        .handled_void => return null,
        .handled_value => |value| return value,
    }
    return EmitError.UnknownFunction;
}

fn emitInstruction(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    const_decls: []const common_const_decl.ConstDecl,
    options: EmitOptions,
    size_bits: u16,
    dbg_id: ?u32,
    item: anytype,
) !void {
    const size_ty_name = sizeTypeName(size_bits);
    const base = item.base;
    switch (base.kind) {
        .label => {
            const label_id = base.operands[1].label;
            const label_name = symbols.lookupName(label_id) orelse return EmitError.InvalidOperand;
            if (state.block_open) {
                try out.writer().print("  br label %{s}\n", .{label_name});
            }
            if (dbg_id) |id| {
                try out.writer().print("  ; label dbg !{d}\n", .{id});
            }
            try out.writer().print("{s}:\n", .{label_name});
            try state.reloadLiveRegs(allocator, out, item.entry_caps);
            state.block_open = true;
        },
        .alloc => {
            const dst = base.operands[0].reg;
            const size = switch (base.operands[1]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = call ptr @malloc({s} {d})", .{ tmp, size_ty_name, size });
            if (dbg_id) |id| {
                try out.writer().print(", !dbg !{d}", .{id});
            }
            try out.appendSlice("\n");
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = .ptr });
        },
        .stack_alloc => {
            const dst = base.operands[0].reg;
            const size = switch (base.operands[1]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = alloca i8, i64 {d}, align 1", .{ tmp, size });
            if (dbg_id) |id| {
                try out.writer().print(", !dbg !{d}", .{id});
            }
            try out.appendSlice("\n");
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = .ptr });
        },
        .borrow => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const srcv = try valueFromRegOrConst(allocator, state, symbols, src);
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const mode = if (base.operands[2] == .text) base.operands[2].text else "";
            try state.setReg(allocator, out, dst, .{
                .expr = ptrv.expr,
                .ty = .ptr,
                .interior_ptr = ptrv.interior_ptr,
                .borrow_view = true,
                .ffi_borrow = srcv.ffi_borrow or std.mem.eql(u8, mode, "raw"),
                .const_ref = ptrv.const_ref,
                .origin = ptrv.origin,
            });
        },
        .load, .take => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const off = switch (base.operands[2]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const ty: sig.PrimType = blk: {
                if (base.operands[3] == .ty) {
                    break :blk sig.primTypeFromTag(base.operands[3].ty) orelse if (base.kind == .take) .ptr else .i64;
                }
                break :blk if (base.kind == .take) .ptr else .i64;
            };
            const srcv = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = load {s}, ptr {s}, align {d}\n", .{ tmp, llvmTypeName(ty), gep, llvmAlign(ty) });
            var loaded_origin: PointerOrigin = .{};
            var loaded_interior_ptr = false;
            if (ty == .ptr) {
                if (state.lookupMemoryPtrMeta(ptrv.expr, off)) |meta| {
                    loaded_origin = meta.origin;
                    loaded_interior_ptr = meta.interior_ptr;
                } else {
                    loaded_origin = resolveLoadOrigin(const_decls, sigs, ptrv, off, ty);
                    if (loaded_origin.indirect_sig_index == null) {
                        if (inferIndirectSigIndexFromLoadText(const_decls, sigs, base.raw_text)) |sig_index| {
                            loaded_origin.indirect_sig_index = sig_index;
                            if (options.debug) {
                                std.debug.print(
                                    "emit load inferred indirect sig {d} from {s}\n",
                                    .{ sig_index, base.raw_text },
                                );
                            }
                        }
                    }
                }
                if (ptrv.borrow_view or ptrv.ffi_borrow or ptrv.interior_ptr) {
                    loaded_interior_ptr = true;
                }
            }
            try state.setReg(allocator, out, dst, .{
                .expr = tmp,
                .ty = ty,
                .interior_ptr = loaded_interior_ptr,
                .const_ref = loaded_origin.const_name,
                .origin = loaded_origin,
            });
        },
        .atomic_load => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const off = switch (base.operands[2]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const srcv = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = load atomic {s}, ptr {s} {s}, align {d}\n", .{ tmp, llvmTypeName(ty), gep, atomicOrderingName(base), llvmAlign(ty) });
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = ty });
        },
        .atomic_store => {
            const base_reg = base.operands[0].reg;
            const off = switch (base.operands[1]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const basev = state.getReg(base_reg) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, basev, .ptr);
            const gep = try state.tempName(allocator);
            try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const value = try valueFromOperand(allocator, state, symbols, base.operands[2]);
            const coerced = try castValue(allocator, out, state, value, ty);
            try out.writer().print("  store atomic {s} {s}, ptr {s} {s}, align {d}\n", .{ llvmTypeName(ty), coerced.expr, gep, atomicOrderingName(base), llvmAlign(ty) });
        },
        .cmpxchg => {
            const dst = base.operands[0].reg;
            const ok = base.operands[1].reg;
            const src = base.operands[2].reg;
            const off = switch (base.operands[3]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const srcv = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const expected_text = base.atomic_expected_text orelse return EmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return EmitError.InvalidOperand;
            const expected_value = try valueFromOperand(allocator, state, symbols, .{ .text = expected_text });
            const new_value = try valueFromOperand(allocator, state, symbols, .{ .text = new_text });
            const expected_coerced = try castValue(allocator, out, state, expected_value, ty);
            const new_coerced = try castValue(allocator, out, state, new_value, ty);
            const pair = try state.tempName(allocator);
            try out.writer().print("  {s} = cmpxchg ptr {s}, {s} {s}, {s} {s} {s} {s}\n", .{ pair, gep, llvmTypeName(ty), expected_coerced.expr, llvmTypeName(ty), new_coerced.expr, atomicOrderingName(base), atomicSecondOrderingName(base) });
            const old_tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = extractvalue ", .{old_tmp});
            try writeCmpxchgResultType(out.writer(), ty);
            try out.writer().print(" {s}, 0\n", .{pair});
            const ok_tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = extractvalue ", .{ok_tmp});
            try writeCmpxchgResultType(out.writer(), ty);
            try out.writer().print(" {s}, 1\n", .{pair});
            try state.setReg(allocator, out, dst, .{ .expr = old_tmp, .ty = ty });
            try state.setReg(allocator, out, ok, .{ .expr = ok_tmp, .ty = .i1 });
        },
        .atomic_rmw => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const off = switch (base.operands[2]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const srcv = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const value = try valueFromOperand(allocator, state, symbols, base.operands[3]);
            const coerced = try castValue(allocator, out, state, value, ty);
            const tmp = try state.tempName(allocator);
            const op_name = atomic.rmwOpName(base.atomic_rmw_op orelse return EmitError.InvalidOperand);
            try out.writer().print("  {s} = atomicrmw {s} ptr {s}, {s} {s} {s}\n", .{ tmp, op_name, gep, llvmTypeName(ty), coerced.expr, atomicOrderingName(base) });
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = ty });
        },
        .fence => {
            try out.writer().print("  fence {s}\n", .{atomicOrderingName(base)});
        },
        .store => {
            const base_reg = base.operands[0].reg;
            const off = switch (base.operands[1]) {
                .imm_u64 => |v| v,
                .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .imm_int => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                .text => |t| std.fmt.parseInt(u64, t, 10) catch return EmitError.InvalidOperand,
                else => return EmitError.InvalidOperand,
            };
            const basev = state.getReg(base_reg) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, basev, .ptr);
            const gep = try state.tempName(allocator);
            try out.writer().print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const target_ty = if (base.operands[3] == .ty) sig.primTypeFromTag(base.operands[3].ty) orelse .i64 else blk: {
                if (base.operands[2] == .reg) break :blk state.getReg(base.operands[2].reg).?.ty;
                break :blk .i64;
            };
            const value = try valueFromOperand(allocator, state, symbols, base.operands[2]);
            const coerced = try castValue(allocator, out, state, value, target_ty);
            try out.writer().print("  store {s} {s}, ptr {s}, align {d}\n", .{ llvmTypeName(target_ty), coerced.expr, gep, llvmAlign(target_ty) });
            if (target_ty == .ptr) {
                try state.recordMemoryPtrMeta(ptrv.expr, off, coerced);
            } else {
                state.clearMemoryPtrMeta(ptrv.expr, off);
            }
        },
        .op => {
            const dst = base.operands[0].reg;
            const opcode = base.op_kind orelse return EmitError.InvalidOperand;
            if (opcode == .neg or opcode == .not or opcode == .fneg or opcode == .trunc or opcode == .zext or opcode == .sext or opcode == .fptosi or opcode == .sitofp or opcode == .uitofp or opcode == .fptrunc or opcode == .fpext or opcode == .bitcast) {
                const value = try valueFromOperand(allocator, state, symbols, base.operands[1]);
                const target_ty: ?sig.PrimType = if (base.operands[2] == .ty) sig.primTypeFromTag(base.operands[2].ty) else null;
                const tmp = try state.tempName(allocator);
                switch (opcode) {
                    .neg => {
                        if (value.ty == .ptr) return EmitError.UnsupportedType;
                        if (isFloatLike(value.ty)) {
                            try out.writer().print("  {s} = fneg {s} {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        } else {
                            try out.writer().print("  {s} = sub {s} 0, {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        }
                        try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = value.ty });
                    },
                    .not => {
                        if (!isIntLike(value.ty)) return EmitError.UnsupportedType;
                        try out.writer().print("  {s} = xor {s} {s}, -1\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = value.ty });
                    },
                    .fneg => {
                        if (!isFloatLike(value.ty)) return EmitError.UnsupportedType;
                        try out.writer().print("  {s} = fneg {s} {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = value.ty });
                    },
                    .bitcast => {
                        const target = target_ty orelse return EmitError.InvalidOperand;
                        const casted = try castValue(allocator, out, state, value, target);
                        try state.setReg(allocator, out, dst, casted);
                    },
                    .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext => {
                        const target = target_ty orelse return EmitError.InvalidOperand;
                        const casted = try castValue(allocator, out, state, value, target);
                        try state.setReg(allocator, out, dst, casted);
                    },
                    else => unreachable,
                }
                return;
            }
            const lhs = try valueFromOperand(allocator, state, symbols, base.operands[1]);
            const rhs = try valueFromOperand(allocator, state, symbols, base.operands[2]);
            if (opcode == .add or opcode == .sub) {
                if (lhs.ty == .ptr or rhs.ty == .ptr) {
                    if (lhs.ty == .ptr and rhs.ty == .ptr) return EmitError.UnsupportedType;
                    if (opcode == .sub and rhs.ty == .ptr) return EmitError.UnsupportedType;
                    const result = try emitPointerArithmetic(allocator, out, state, opcode, lhs, rhs);
                    try state.setReg(allocator, out, dst, result);
                    return;
                }
            }
            const base_kind = numericKind(lhs.ty, rhs.ty);
            const kind = opNumericKind(opcode, lhs.ty, rhs.ty);
            if (base_kind == .float) {
                switch (opcode) {
                    .add, .sub, .mul, .div, .gt, .lt, .eq, .ne, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => {},
                    .@"and", .@"or", .shl, .shr, .rem, .sdiv, .udiv, .srem, .urem, .sgt, .slt, .sge, .sle, .ugt, .ult, .uge, .ule => return EmitError.UnsupportedType,
                    else => return EmitError.UnsupportedType,
                }
            }
            const target_ty = opTargetType(opcode, lhs.ty, rhs.ty);
            const l = try castValue(allocator, out, state, lhs, target_ty);
            const r = try castValue(allocator, out, state, rhs, target_ty);
            const tmp = try state.tempName(allocator);
            switch (opcode) {
                .add => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .float) "fadd" else "add", llvmTypeName(target_ty), l.expr, r.expr }),
                .sub => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .float) "fsub" else "sub", llvmTypeName(target_ty), l.expr, r.expr }),
                .mul => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .float) "fmul" else "mul", llvmTypeName(target_ty), l.expr, r.expr }),
                .div => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, switch (kind) {
                    .float => "fdiv",
                    .signed => "sdiv",
                    .unsigned => "udiv",
                }, llvmTypeName(target_ty), l.expr, r.expr }),
                .sdiv => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.writer().print("  {s} = sdiv {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .udiv => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.writer().print("  {s} = udiv {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .rem => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, switch (kind) {
                        .signed => "srem",
                        .unsigned => "urem",
                        else => unreachable,
                    }, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .srem => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.writer().print("  {s} = srem {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .urem => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.writer().print("  {s} = urem {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .@"and" => try out.writer().print("  {s} = and {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .@"or" => try out.writer().print("  {s} = or {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .shl => try out.writer().print("  {s} = shl {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .shr => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .signed) "ashr" else "lshr", llvmTypeName(target_ty), l.expr, r.expr }),
                .gt, .lt, .eq, .ne => {
                    const cmp = legacyCompareMnemonic(opcode, kind);
                    const cmp_inst = if (kind == .float) "fcmp" else "icmp";
                    try out.writer().print("  {s} = {s} {s} {s} {s}, {s}\n", .{ tmp, cmp_inst, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.writer().print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => {
                    if (!isFloatLike(lhs.ty) or !isFloatLike(rhs.ty)) return EmitError.UnsupportedType;
                    const cmp = floatCompareMnemonic(opcode);
                    try out.writer().print("  {s} = fcmp {s} {s} {s}, {s}\n", .{ tmp, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.writer().print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                .sgt, .slt, .sge, .sle => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    const cmp = signedCompareMnemonic(opcode);
                    try out.writer().print("  {s} = icmp {s} {s} {s}, {s}\n", .{ tmp, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.writer().print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                .ugt, .ult, .uge, .ule => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    const cmp = unsignedCompareMnemonic(opcode);
                    try out.writer().print("  {s} = icmp {s} {s} {s}, {s}\n", .{ tmp, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.writer().print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                else => return EmitError.UnsupportedType,
            }
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = target_ty });
        },
        .ptr_add => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const srcv = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const offset = try valueFromOperand(allocator, state, symbols, base.operands[2]);
            const off = try castValue(allocator, out, state, offset, .i64);
            const result = try emitPointerArithmetic(allocator, out, state, .add, ptrv, off);
            try state.setReg(allocator, out, dst, result);
        },
        .raw_cast => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse return EmitError.InvalidOperand;
            const raw = try castValue(allocator, out, state, value, .i64);
            try state.setReg(allocator, out, dst, raw);
        },
        .assume_safe, .assume_borrow => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            try state.setReg(allocator, out, dst, ptrv);
        },
        .assign => {
            const dst = base.operands[0].reg;
            const value = try valueFromOperand(allocator, state, symbols, base.operands[1]);
            try state.setReg(allocator, out, dst, value);
        },
        .move_ => {},
        .release => {
            const reg_id = base.operands[0].reg;
            const mask = item.entry_caps[@intCast(reg_id)];
            if ((mask & @intFromEnum(cap.CapabilityMask.borrow_view)) != 0 or (mask & @intFromEnum(cap.CapabilityMask.ffi_borrow)) != 0) {
                return;
            }
            const value = state.getReg(reg_id) orelse return EmitError.InvalidOperand;
            if (value.borrow_view or value.ffi_borrow) {
                return;
            }
            if (value.ty != .ptr or value.interior_ptr or value.const_ref != null or value.origin.const_name != null) {
                return;
            }
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            try out.writer().print("  call void @free(ptr {s})\n", .{ptrv.expr});
        },
        .jmp => {
            const label_name = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            try out.writer().print("  br label %{s}\n", .{label_name});
            state.block_open = false;
        },
        .br => {
            const cond = try valueFromOperand(allocator, state, symbols, base.operands[0]);
            const condv = try castValue(allocator, out, state, cond, .i64);
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = icmp ne i64 {s}, 0\n", .{ tmp, condv.expr });
            const tname = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            const fname = symbols.lookupName(base.operands[3].label) orelse return EmitError.InvalidOperand;
            try out.writer().print("  br i1 {s}, label %{s}, label %{s}\n", .{ tmp, tname, fname });
            state.block_open = false;
        },
        .br_null => {
            const value = try valueFromOperand(allocator, state, symbols, base.operands[0]);
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = icmp eq ptr {s}, null\n", .{ tmp, ptrv.expr });
            const nname = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            const nnname = symbols.lookupName(base.operands[3].label) orelse return EmitError.InvalidOperand;
            try out.writer().print("  br i1 {s}, label %{s}, label %{s}\n", .{ tmp, nname, nnname });
            state.block_open = false;
        },
        .call, .call_indirect, .panic, .panic_msg => {
            var parsed = call.parseCall(allocator, base.raw_text) catch return EmitError.InvalidOperand;
            defer parsed.deinit(allocator);
            if (try emitCall(allocator, out, state, symbols, sigs, options, size_bits, parsed)) |ret| {
                if (parsed.dest) |dest| {
                    if (symbols.findId(dest)) |id| try state.setReg(allocator, out, id, ret);
                }
            }
            state.block_open = base.kind != .panic and base.kind != .panic_msg;
        },
        .try_, .early_return => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse return EmitError.InvalidOperand;
            if (!value.fallible) return EmitError.InvalidOperand;
            if (!state.sig.return_fallible) return EmitError.InvalidOperand;

            const branch_id = state.temp_index;
            state.temp_index += 1;
            const status_tmp = try state.tempName(allocator);
            const ok_tmp = try state.tempName(allocator);
            const cont_label = try state.ownFmt(allocator, "try_ok_{d}", .{branch_id});
            const early_label = try state.ownFmt(allocator, "try_early_{d}", .{branch_id});

            try out.writer().print("  {s} = extractvalue ", .{status_tmp});
            try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
            try out.writer().print(" {s}, 0\n", .{value.expr});
            try out.writer().print("  {s} = icmp eq i32 {s}, 0\n", .{ ok_tmp, status_tmp });
            try out.writer().print("  br i1 {s}, label %{s}, label %{s}\n", .{ ok_tmp, cont_label, early_label });
            try out.writer().print("{s}:\n", .{early_label});
            try out.appendSlice("  ret ");
            try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
            try out.writer().print(" {s}\n", .{value.expr});
            try out.writer().print("{s}:\n", .{cont_label});

            const payload_tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = extractvalue ", .{payload_tmp});
            try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
            try out.writer().print(" {s}, 1\n", .{value.expr});
            try state.setReg(allocator, out, dst, .{ .expr = payload_tmp, .ty = value.ty });
            state.block_open = true;
        },
        .return_ => {
            const ret_ty = returnTypeForSig(state.sig.return_cap, state.sig.return_ty);
            if (state.sig.return_fallible) {
                if (ret_ty == .void) return EmitError.UnsupportedType;
                if (base.operands[0] == .none) return EmitError.InvalidOperand;
                const value = try valueFromOperand(allocator, state, symbols, base.operands[0]);
                if (value.fallible) {
                    try out.appendSlice("  ret ");
                    try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
                    try out.writer().print(" {s}\n", .{value.expr});
                    state.block_open = false;
                    return;
                }
                const coerced = try castValue(allocator, out, state, value, ret_ty);
                const zero_agg = try state.tempName(allocator);
                try out.writer().print("  {s} = insertvalue ", .{zero_agg});
                try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
                try out.appendSlice(" poison, i32 0, 0\n");
                const packed_value = try state.tempName(allocator);
                try out.writer().print("  {s} = insertvalue ", .{packed_value});
                try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
                try out.writer().print(" {s}, {s} {s}, 1\n", .{ zero_agg, llvmTypeName(ret_ty), coerced.expr });
                try out.appendSlice("  ret ");
                try writeReturnAbiType(out.writer(), state.sig.return_cap, state.sig.return_ty, true);
                try out.writer().print(" {s}\n", .{packed_value});
                state.block_open = false;
                return;
            }

            if (base.operands[0] == .none or ret_ty == .void) {
                try emitIndented(out, "ret void");
                state.block_open = false;
                return;
            }
            const value = try valueFromOperand(allocator, state, symbols, base.operands[0]);
            const coerced = try castValue(allocator, out, state, value, ret_ty);
            try out.writer().print("  ret {s} {s}\n", .{ llvmTypeName(ret_ty), coerced.expr });
            state.block_open = false;
        },
        .native => {
            try out.writer().print("  {s}\n", .{base.operands[0].native_text});
        },
        else => return EmitError.UnsupportedInstruction,
    }
}

fn emitUserFunctions(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    verified: anytype,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    options: EmitOptions,
    size_bits: u16,
) !void {
    if (options.debug and loc_table.len != verified.annotated.len) return EmitError.InvalidOperand;

    try emitConstDecls(allocator, out, verified.const_decls, verified.function_sigs);

    var debug_info: ?DebugInfo = null;
    if (options.debug) {
        debug_info = try DebugInfo.init(allocator, source_path);
    }
    defer if (debug_info) |*info| info.deinit();

    var sig_index: usize = 0;
    var current: ?FunctionState = null;
    var current_debug: ?DebugFunctionContext = null;
    var main_wrapper_dbg: ?u32 = null;
    defer if (current) |*state| state.deinit(allocator);

    for (verified.annotated, 0..) |item, idx| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl => {
                if (current) |*state| {
                    try emitFunctionFooter(out);
                    state.deinit(allocator);
                    current = null;
                }

                if (sig_index >= verified.function_sigs.len) return EmitError.UnknownFunction;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;

                if (item.base.kind == .extern_decl) {
                    if (options.wasm_compat and std.mem.eql(u8, fsig.name, "sa_print_bytes")) {
                        current_debug = null;
                        continue;
                    }
                    try out.appendSlice("declare ");
                    try writeReturnAbiType(out.writer(), fsig.return_cap, fsig.return_ty, fsig.return_fallible);
                    try out.writer().print(" @{s}(", .{fsig.name});
                    for (fsig.params, 0..) |param, pidx| {
                        if (pidx != 0) try out.appendSlice(", ");
                        const ty = valueTypeForPrefix(param.cap, param.ty);
                        try out.writer().print("{s}", .{llvmTypeName(ty)});
                    }
                    try emitLine(out, ")");
                    try emitLine(out, "");
                    current_debug = null;
                    continue;
                }

                current = try FunctionState.init(allocator, fsig, verified.symbols.names.items.len);
                for (verified.const_decls) |item_const| {
                    try current.?.setConstRef(item_const.name);
                }
                if (debug_info) |*info| {
                    const upstream_loc: upstream.UpstreamLoc = if (fsig.upstream_loc) |loc| loc else .{
                        .file = source_path,
                        .line = fsig.entry_inst_idx + 1,
                        .col = 1,
                    };
                    current_debug = try info.ensureFunction(fsig.name, emittedFunctionName(fsig), upstream_loc.file, upstream_loc.line);
                    if (fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0) {
                        main_wrapper_dbg = try info.ensureLocation(current_debug.?, upstream_loc.file, upstream_loc.line, upstream_loc.col);
                    }
                } else {
                    current_debug = null;
                }
                try emitFunctionHeader(out, &current.?, if (current_debug) |ctx| ctx.subprogram_id else null);
                for (fsig.params, 0..) |param, pidx| {
                    const reg_id = fsig.param_ids[pidx];
                    const value = Value{
                        .expr = try current.?.ownFmt(allocator, "%{s}", .{param.name}),
                        .ty = valueTypeForPrefix(param.cap, param.ty),
                        .borrow_view = param.cap == .borrow,
                        .ffi_borrow = param.cap == .raw,
                    };
                    try current.?.setReg(allocator, out, reg_id, value);
                }
                continue;
            },
            else => {},
        }

        if (current) |*state| {
            const inst_dbg_id = if (debug_info) |*info| blk: {
                if (current_debug) |ctx| {
                    if (loc_table[idx]) |loc| {
                        break :blk try info.ensureLocation(ctx, loc.file, loc.line, loc.col);
                    }
                }
                break :blk null;
            } else null;
            try emitInstruction(allocator, out, state, &verified.symbols, verified.function_sigs, verified.const_decls, options, size_bits, inst_dbg_id, item);
        }
    }

    if (current) |*state| {
        try emitFunctionFooter(out);
        state.deinit(allocator);
        current = null;
    }

    // Emit the native entry wrapper if the program defines a zero-arg `main`.
    for (verified.function_sigs) |fsig| {
        if (fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0) {
            const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
            const wrapper_dbg = main_wrapper_dbg;
            try out.writer().print("define i32 @main(i32 %argc, ptr %argv) {{\n", .{});
            try emitLine(out, "entry:");
            if (wrapper_dbg) |dbg_id| {
                try out.writer().print("  store i32 %argc, ptr @saasm_argc, align 4, !dbg !{d}\n", .{dbg_id});
                try out.writer().print("  store ptr %argv, ptr @saasm_argv, align 8, !dbg !{d}\n", .{dbg_id});
            } else {
                try emitLine(out, "  store i32 %argc, ptr @saasm_argc, align 4");
                try emitLine(out, "  store ptr %argv, ptr @saasm_argv, align 8");
            }

            if (fsig.return_fallible) {
                if (wrapper_dbg) |dbg_id| {
                    try out.appendSlice("  %res = call ");
                    try writeReturnAbiType(out.writer(), fsig.return_cap, fsig.return_ty, true);
                    try out.writer().print(" @{s}(), !dbg !{d}\n", .{ emittedFunctionName(fsig), dbg_id });
                    try out.appendSlice("  %status = extractvalue ");
                    try writeReturnAbiType(out.writer(), fsig.return_cap, fsig.return_ty, true);
                    try out.writer().print(" %res, 0, !dbg !{d}\n", .{dbg_id});
                    try out.writer().print("  ret i32 %status, !dbg !{d}\n", .{dbg_id});
                } else {
                    try out.appendSlice("  %res = call ");
                    try writeReturnAbiType(out.writer(), fsig.return_cap, fsig.return_ty, true);
                    try out.writer().print(" @{s}()\n", .{emittedFunctionName(fsig)});
                    try out.appendSlice("  %status = extractvalue ");
                    try writeReturnAbiType(out.writer(), fsig.return_cap, fsig.return_ty, true);
                    try out.appendSlice(" %res, 0\n");
                    try emitLine(out, "  ret i32 %status");
                }
            } else if (ret_ty == .void) {
                if (wrapper_dbg) |dbg_id| {
                    try out.writer().print("  call void @{s}(), !dbg !{d}\n", .{ emittedFunctionName(fsig), dbg_id });
                    try out.writer().print("  ret i32 0, !dbg !{d}\n", .{dbg_id});
                } else {
                    try out.writer().print("  call void @{s}()\n", .{emittedFunctionName(fsig)});
                    try emitLine(out, "  ret i32 0");
                }
            } else if (ret_ty == .i32 or ret_ty == .u32) {
                if (wrapper_dbg) |dbg_id| {
                    try out.writer().print("  %res = call {s} @{s}(), !dbg !{d}\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig), dbg_id });
                    try out.writer().print("  ret i32 %res, !dbg !{d}\n", .{dbg_id});
                } else {
                    try out.writer().print("  %res = call {s} @{s}()\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig) });
                    try out.writer().print("  ret i32 %res\n", .{});
                }
            } else {
                if (wrapper_dbg) |dbg_id| {
                    try out.writer().print("  call {s} @{s}(), !dbg !{d}\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig), dbg_id });
                    try out.writer().print("  ret i32 0, !dbg !{d}\n", .{dbg_id});
                } else {
                    try out.writer().print("  call {s} @{s}()\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig) });
                    try emitLine(out, "  ret i32 0");
                }
            }
            try emitLine(out, "}");
            try emitLine(out, "");
            break;
        }
    }

    if (debug_info) |*info| {
        try info.emit(out);
    }
}

pub fn emitLlvm(
    allocator: std.mem.Allocator,
    verified: anytype,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    size_bits: u16,
    options: EmitOptions,
) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try emitHelpers(&out, size_bits, options);
    try emitUserFunctions(allocator, &out, verified, loc_table, source_path, options, size_bits);

    return try out.toOwnedSlice();
}

fn emitTestSource(source: []const u8) ![]const u8 {
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    return switch (verified) {
        .trap => |report| {
            std.debug.print(
                "emitTestSource verifier trap: {s} line={d} register={?s} message={s}\nsource:\n{s}\n",
                .{ trap.trapName(report.trap), report.line, report.register, report.message, source },
            );
            return error.TestUnexpectedResult;
        },
        .ok => |ok| blk: {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            break :blk try emitLlvm(std.testing.allocator, owned, flat.loc_table, "emit_test.saasm", @as(u16, @bitSizeOf(usize)), .{});
        },
    };
}

fn functionBody(text: []const u8, header_fragment: []const u8) ![]const u8 {
    const header_start = std.mem.indexOf(u8, text, header_fragment) orelse return error.TestUnexpectedResult;
    const body_start = std.mem.indexOfPos(u8, text, header_start, "{\n") orelse return error.TestUnexpectedResult;
    const body_end = std.mem.indexOfPos(u8, text, body_start + 2, "\n}\n") orelse return error.TestUnexpectedResult;
    return text[body_start + 2 .. body_end];
}

fn findExecutableForTest(allocator: std.mem.Allocator, names: []const []const u8) !?[]u8 {
    const path_env = std.process.getEnvVarOwned(allocator, "PATH") catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return null,
        else => return err,
    };
    defer allocator.free(path_env);

    for (names) |name| {
        if (std.fs.path.isAbsolute(name)) {
            std.fs.accessAbsolute(name, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => continue,
            };
            return try allocator.dupe(u8, name);
        }

        var it = std.mem.tokenizeScalar(u8, path_env, std.fs.path.delimiter);
        while (it.next()) |dir_path| {
            const full_path = try std.fs.path.join(allocator, &.{ dir_path, name });
            defer allocator.free(full_path);
            std.fs.cwd().access(full_path, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => continue,
            };
            return try allocator.dupe(u8, full_path);
        }
    }

    return null;
}

fn verifyWithOptIfAvailable(allocator: std.mem.Allocator, llvm_ir: []const u8) !bool {
    const opt_path = (try findExecutableForTest(allocator, &.{
        "opt",
        "opt-18",
        "opt-17",
        "opt-16",
        "opt-15",
        "opt-14",
        "llvm-opt",
        "/usr/lib/llvm-18/bin/opt",
        "/usr/lib/llvm-17/bin/opt",
        "/usr/lib/llvm-16/bin/opt",
        "/usr/lib/llvm-15/bin/opt",
        "/usr/lib/llvm-14/bin/opt",
    })) orelse return false;
    defer allocator.free(opt_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const file = try tmp.dir.createFile("module.ll", .{ .truncate = true });
    defer file.close();
    try file.writeAll(llvm_ir);

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ opt_path, "-opaque-pointers", "-verify", "module.ll", "-disable-output" },
        .cwd_dir = tmp.dir,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("opt -verify stdout:\n{s}\nstderr:\n{s}\nmodule:\n{s}\n", .{ result.stdout, result.stderr, llvm_ir });
                return error.TestUnexpectedResult;
            }
        },
        else => {
            std.debug.print("opt -verify terminated unexpectedly\nstdout:\n{s}\nstderr:\n{s}\nmodule:\n{s}\n", .{ result.stdout, result.stderr, llvm_ir });
            return error.TestUnexpectedResult;
        },
    }

    return true;
}

test "llvm emitter produces a module with builtin helpers" {
    var symbols = symbol.SymbolTable.init(std.testing.allocator);
    defer symbols.deinit();
    _ = try symbols.intern("main");
    const ok = referee.VerifyOk{
        .annotated = &.{},
        .function_sigs = &.{},
        .symbols = symbols,
        .gas = .{
            .max_alloc_bytes = 0,
            .max_instruction_steps = .{ .bounded = 0 },
            .call_depth = 0,
            .has_unbounded_loop = false,
        },
    };
    const empty_loc: upstream.LocTable = &.{};
    const text = try emitLlvm(std.testing.allocator, ok, empty_loc, "test.saasm", @as(u16, @bitSizeOf(usize)), .{});
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "define void @sys_print"));
}

test "llvm emitter preserves native escape bytes verbatim" {
    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\$call void @side_effect()$
        \\!value
        \\return 0
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);

            const text = try emitLlvm(std.testing.allocator, owned, flat.loc_table, "native.saasm", @as(u16, @bitSizeOf(usize)), .{});
            defer std.testing.allocator.free(text);
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "call void @side_effect()"));
        },
    }
}

test "llvm emitter native escape PBT preserves random verbatim snippets" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_8200);
    const random = prng.random();

    for (0..32) |iter| {
        const tag = random.intRangeAtMost(u32, 0, 10_000);
        const snippet = switch (iter % 3) {
            0 => try std.fmt.allocPrint(std.testing.allocator, "call void @native_{d}()", .{tag}),
            1 => try std.fmt.allocPrint(std.testing.allocator, "%tmp{d} = add i64 1, 2", .{tag}),
            else => try std.fmt.allocPrint(std.testing.allocator, "store i8 7, ptr %tmp{d}, align 1", .{tag}),
        };
        defer std.testing.allocator.free(snippet);

        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@main() -> i32:
            \\value = alloc 8
            \\${s}$
            \\!value
            \\return 0
        , .{snippet});
        defer std.testing.allocator.free(source);

        var flat = try flattener.flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
        switch (verified) {
            .trap => return error.TestUnexpectedResult,
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);

                const text = try emitLlvm(std.testing.allocator, owned, flat.loc_table, "native_pbt.saasm", @as(u16, @bitSizeOf(usize)), .{});
                defer std.testing.allocator.free(text);
                try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, snippet));
            },
        }
    }
}

test "llvm emitter maps M01-M07 with typed integer ops and owned release" {
    const source =
        \\@math() -> i64:
        \\base = alloc 8
        \\store base+0, 7 as i32
        \\store base+4, 3 as i32
        \\lhs = load base+0 as i32
        \\rhs = load base+4 as i32
        \\sum = add lhs, rhs
        \\cmp = gt lhs, rhs
        \\!lhs
        \\!rhs
        \\!sum
        \\!base
        \\return cmp
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i64 @math()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call ptr @malloc("));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 2, "getelementptr i8, ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 2, "store i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 2, "load i32, ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "add i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "icmp sgt i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "zext i1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call void @free(ptr "));
}

test "llvm emitter maps M03 borrow release to no-op" {
    const source =
        \\@skip_free(&view: ptr) -> i32:
        \\!view
        \\return 0
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @skip_free(ptr %view)");
    try std.testing.expect(!std.mem.containsAtLeast(u8, body, 1, "call void @free(ptr "));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "ret i32"));
}

test "llvm emitter maps M08-M11 and M13 control flow and direct calls" {
    const source =
        \\@ffi_wrapper callee(*x: i32) -> i32:
        \\return 7
        \\
        \\@noop() -> void:
        \\return
        \\
        \\@jmp_only() -> i32:
        \\jmp L_DONE
        \\L_DONE:
        \\return 7
        \\
        \\@ffi_wrapper branch(*flag: i32) -> i32:
        \\br flag -> L_TRUE, L_FALSE
        \\L_TRUE:
        \\return 1
        \\L_FALSE:
        \\return 0
        \\
        \\@ffi_wrapper branch_null(*p: ptr) -> i32:
        \\br_null p -> L_NULL, L_NONNULL
        \\L_NULL:
        \\return 1
        \\L_NONNULL:
        \\return 0
        \\
        \\@ffi_wrapper call_only(*x: i32) -> i32:
        \\value = call @callee(*x)
        \\return value
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const jmp_body = try functionBody(text, "define i32 @jmp_only()");
    try std.testing.expect(std.mem.containsAtLeast(u8, jmp_body, 1, "br label %L_DONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, jmp_body, 1, "L_DONE:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, jmp_body, 1, "ret i32"));

    const branch_body = try functionBody(text, "define i32 @branch(ptr %flag)");
    try std.testing.expect(std.mem.containsAtLeast(u8, branch_body, 1, "icmp ne i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, branch_body, 1, "br i1 "));
    try std.testing.expect(std.mem.containsAtLeast(u8, branch_body, 2, "ret i32"));

    const branch_null_body = try functionBody(text, "define i32 @branch_null(ptr %p)");
    try std.testing.expect(std.mem.containsAtLeast(u8, branch_null_body, 1, "icmp eq ptr %p, null"));
    try std.testing.expect(std.mem.containsAtLeast(u8, branch_null_body, 1, "br i1 "));
    try std.testing.expect(std.mem.containsAtLeast(u8, branch_null_body, 2, "ret i32"));

    const call_body = try functionBody(text, "define i32 @call_only(ptr %x)");
    try std.testing.expect(std.mem.containsAtLeast(u8, call_body, 1, "call i32 @callee(ptr %x)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, call_body, 1, "ret i32"));

    const noop_body = try functionBody(text, "define void @noop()");
    try std.testing.expect(std.mem.containsAtLeast(u8, noop_body, 1, "ret void"));
}

test "llvm emitter maps M18-M20 airlock casts" {
    const source =
        \\@ffi_wrapper airlock(*raw: ptr) -> ptr:
        \\safe = assume_safe raw
        \\raw2 = *safe
        \\^safe
        \\safe = assume_safe raw2
        \\view = assume_borrow raw2
        \\!view
        \\return safe
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define ptr @airlock(ptr %raw)");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "ptrtoint ptr %"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 2, "inttoptr i64 %"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "ret ptr %"));
}

test "llvm emitter maps M24-M27 atomic instructions directly" {
    const source =
        \\@main() -> i32:
        \\node = alloc 8
        \\atomic_store node+0, 5 seq_cst
        \\fence release
        \\x = atomic_load node+0 seq_cst
        \\old = atomic_rmw_add node+0, 3 seq_cst
        \\cmp_old, ok = cmpxchg node+0, 8, 11 acq_rel acquire
        \\y = atomic_load node+0 seq_cst
        \\^x
        \\^old
        \\^cmp_old
        \\^ok
        \\!node
        \\return y
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @saasm_main()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "store atomic i64 5, ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 2, "load atomic i64, ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "atomicrmw add ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "cmpxchg ptr"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "fence release"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 2, "extractvalue {i64, i1}"));
}

test "llvm emitter maps take to gep plus ptr load" {
    const source =
        \\@main() -> i32:
        \\base = alloc 16
        \\slot = take base+8
        \\!slot
        \\!base
        \\return 0
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);

            const text = try emitLlvm(std.testing.allocator, owned, flat.loc_table, "take.saasm", @as(u16, @bitSizeOf(usize)), .{});
            defer std.testing.allocator.free(text);
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "getelementptr i8, ptr"));
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "load ptr, ptr"));
        },
    }
}

test "llvm emitter PBT lowers index access through mul gep and load" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_8808);
    const random = prng.random();
    const scale_choices = [_]u64{ 1, 2, 4, 8 };

    for (0..24) |iter| {
        _ = iter;
        const index = random.intRangeAtMost(u64, 0, 7);
        const scale = scale_choices[random.intRangeLessThan(usize, 0, scale_choices.len)];
        const value: i32 = @intCast(random.intRangeAtMost(u16, 0, 1024));

        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@main() -> i32:
            \\base = alloc 128
            \\idx_slot = stack_alloc 8
            \\store idx_slot+0, {d} as u64
            \\idx = load idx_slot+0 as u64
            \\offset = mul idx, {d}
            \\ip = ptr_add base, offset
            \\store ip+0, {d} as i32
            \\result = load ip+0 as i32
            \\!ip
            \\!offset
            \\!idx
            \\!base
            \\return result
        , .{ index, scale, value });
        defer std.testing.allocator.free(source);

        const text = try emitTestSource(source);
        defer std.testing.allocator.free(text);

        const body = try functionBody(text, "define i32 @saasm_main()");
        try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "mul i64"));
        try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "getelementptr i8, ptr"));
        try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "load i64, ptr"));
        try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "load i32, ptr"));
    }
}

test "llvm emitter declares externs and preserves exported names" {
    const source =
        \\@extern ext_add(lhs: i32, rhs: i32) -> i32
        \\@export exported() -> i32:
        \\value = call @ext_add(1, 2)
        \\return value
    ;
    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try referee.verify(std.testing.allocator, flat.instructions, flat.const_decls);
    switch (verified) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);

            const text = try emitLlvm(std.testing.allocator, owned, flat.loc_table, "exports.saasm", @as(u16, @bitSizeOf(usize)), .{});
            defer std.testing.allocator.free(text);
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "declare i32 @ext_add(i32, i32)"));
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "define i32 @exported()"));
            try std.testing.expect(std.mem.indexOf(u8, text, "define i32 @_exported()") == null);
        },
    }
}

test "llvm emitter PBT produces modules without Zig imports" {
    var prng = std.Random.DefaultPrng.init(0xA16A_0016);
    const random = prng.random();

    for (0..24) |iter| {
        const lhs: i32 = @intCast(random.intRangeAtMost(u16, 0, 5000));
        const rhs: i32 = @intCast(random.intRangeAtMost(u16, 1, 5000));
        const byte_value: u8 = @intCast(random.intRangeAtMost(u16, 0, 255));
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@helper_{d}(lhs: i32, rhs: i32) -> i32:
            \\sum = add lhs, rhs
            \\cmp = gt lhs, rhs
            \\^sum
            \\return cmp
            \\
            \\@main() -> i32:
            \\node = alloc 8
            \\store node+0, {d} as i32
            \\store node+4, {d} as i32
            \\left = load node+0 as i32
            \\right = load node+4 as i32
            \\value = call @helper_{d}(left, right)
            \\!left
            \\!right
            \\!value
            \\store node+0, {d} as i8
            \\!node
            \\return 0
        , .{ iter, lhs, rhs, iter, byte_value });
        defer std.testing.allocator.free(source);

        const text = try emitTestSource(source);
        defer std.testing.allocator.free(text);

        try std.testing.expect(std.mem.indexOf(u8, text, "@import(") == null);
        try std.testing.expect(std.mem.indexOf(u8, text, "const std =") == null);
        try std.testing.expect(std.mem.indexOf(u8, text, "const builtin =") == null);
    }
}

test "llvm emitter PBT passes opt -verify when LLVM opt is available" {
    var prng = std.Random.DefaultPrng.init(0x0815_0A10);
    const random = prng.random();
    var saw_opt = false;

    for (0..12) |iter| {
        const addend: i32 = @intCast(random.intRangeAtMost(u16, 1, 99));
        const count: u8 = @intCast(random.intRangeAtMost(u16, 1, 7));
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\@callee_{d}(lhs: i32, rhs: i32) -> i32:
            \\sum = add lhs, rhs
            \\^lhs
            \\^rhs
            \\^sum
            \\return {d}
            \\
            \\@main() -> i32:
            \\node = alloc 8
            \\atomic_store node+0, {d} seq_cst
            \\fence release
            \\value = atomic_load node+0 seq_cst
            \\sum = add value, value
            \\ok = call @callee_{d}(sum, {d})
            \\cmp = gt sum, ok
            \\^value
            \\^sum
            \\^ok
            \\^cmp
            \\!node
            \\return 0
        , .{ iter, addend, count, iter, addend });
        defer std.testing.allocator.free(source);

        const text = try emitTestSource(source);
        defer std.testing.allocator.free(text);

        if (try verifyWithOptIfAvailable(std.testing.allocator, text)) {
            saw_opt = true;
        }
    }

    if (!saw_opt) return error.SkipZigTest;
}

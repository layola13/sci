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
    jobs: ?usize = null,
    test_mode: bool = false,
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

fn TextSink(comptime Inner: type) type {
    return struct {
        inner: Inner,

        const Self = @This();

        fn writer(self: *Self) Inner {
            return self.inner;
        }

        fn writeAll(self: *Self, bytes: []const u8) !void {
            try self.inner.writeAll(bytes);
        }

        fn writeByte(self: *Self, byte: u8) !void {
            try self.inner.writeByte(byte);
        }

        fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            try self.inner.print(fmt, args);
        }

        fn appendSlice(self: *Self, bytes: []const u8) !void {
            try self.writeAll(bytes);
        }

        fn append(self: *Self, byte: u8) !void {
            try self.writeByte(byte);
        }
    };
}

const FunctionState = struct {
    sig: sig.FunctionSig,
    emitted_name: []const u8,
    source_name: []const u8,
    regs: std.AutoHashMap(u32, Value),
    reg_slots: []?[]const u8,
    extra_slot_names: std.AutoHashMap(u32, []const u8),
    owned: std.ArrayList([]const u8),
    memory_ptrs: std.ArrayList(MemoryPtrMeta),
    temp_index: usize = 0,
    block_open: bool = true,
    const_ref_names: std.StringHashMap(void),
    string_literals: *const StringLiteralPool,

    fn init(
        allocator: std.mem.Allocator,
        sig_: sig.FunctionSig,
        reg_count: usize,
        string_literals: *const StringLiteralPool,
    ) !FunctionState {
        const reg_slots = try allocator.alloc(?[]const u8, reg_count);
        @memset(reg_slots, null);
        return .{
            .sig = sig_,
            .emitted_name = emittedFunctionName(sig_),
            .source_name = sig_.name,
            .regs = std.AutoHashMap(u32, Value).init(allocator),
            .reg_slots = reg_slots,
            .extra_slot_names = std.AutoHashMap(u32, []const u8).init(allocator),
            .owned = std.ArrayList([]const u8).init(allocator),
            .memory_ptrs = std.ArrayList(MemoryPtrMeta).init(allocator),
            .const_ref_names = std.StringHashMap(void).init(allocator),
            .string_literals = string_literals,
        };
    }

    fn deinit(self: *FunctionState, allocator: std.mem.Allocator) void {
        self.regs.deinit();
        self.extra_slot_names.deinit();
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

    fn resolveSlot(self: *const FunctionState, id: u32) ?u32 {
        if (self.sig.slotOf(id)) |slot| {
            if (slot != id) return slot;
        }
        if (id < self.reg_slots.len) return id;
        return null;
    }

    fn tempName(self: *FunctionState, allocator: std.mem.Allocator) ![]const u8 {
        const name = try self.ownFmt(allocator, "%t{d}", .{self.temp_index});
        self.temp_index += 1;
        return name;
    }

    fn setReg(self: *FunctionState, allocator: std.mem.Allocator, out: anytype, id: u32, value: Value) !void {
        if (self.regs.getPtr(id)) |slot| {
            slot.* = value;
        } else {
            try self.regs.put(id, value);
        }
        if (value.ty == .ptr and (value.origin.indirect_sig_index != null or value.origin.const_name != null or value.const_ref != null)) {
            try self.recordMemoryPtrMeta(value.expr, 0, value);
        }
        const slot_name = try self.ensureSlot(allocator, out, id);
        try out.writeAll("  store ");
        try writeValueType(out, value);
        try out.print(" {s}, ptr {s}, align {d}\n", .{ value.expr, slot_name, register_slot_align });
    }

    fn setRegGlobal(self: *FunctionState, allocator: std.mem.Allocator, out: anytype, id: u32, value: Value) !void {
        if (self.sig.slotOf(id)) |slot| {
            try self.setReg(allocator, out, slot, value);
            if (slot != id) {
                if (self.regs.getPtr(id)) |entry| {
                    entry.* = value;
                } else {
                    try self.regs.put(id, value);
                }
                if (value.ty == .ptr and (value.origin.indirect_sig_index != null or value.origin.const_name != null or value.const_ref != null)) {
                    try self.recordMemoryPtrMeta(value.expr, 0, value);
                }
            }
            return;
        }
        try self.setReg(allocator, out, id, value);
    }

    fn ensureSlot(self: *FunctionState, allocator: std.mem.Allocator, out: anytype, id: u32) ![]const u8 {
        if (self.resolveSlot(id)) |slot| {
            const idx: usize = @intCast(slot);
            if (self.reg_slots[idx]) |slot_name| return slot_name;
            const slot_name = try self.ownFmt(allocator, "%slot_{d}", .{slot});
            self.reg_slots[idx] = slot_name;
            try out.print("  {s} = alloca i8, i64 {d}, align {d}\n", .{ slot_name, register_slot_bytes, register_slot_align });
            return slot_name;
        }

        if (self.extra_slot_names.get(id)) |slot_name| return slot_name;
        const slot_name = try self.ownFmt(allocator, "%slotg_{d}", .{id});
        try self.extra_slot_names.put(id, slot_name);
        try out.print("  {s} = alloca i8, i64 {d}, align {d}\n", .{ slot_name, register_slot_bytes, register_slot_align });
        return slot_name;
    }

    fn ensureSlotGlobal(self: *FunctionState, allocator: std.mem.Allocator, out: anytype, id: u32) ![]const u8 {
        if (id < self.reg_slots.len) return try self.ensureSlot(allocator, out, id);
        if (self.extra_slot_names.get(id)) |slot_name| return slot_name;
        const slot_name = try self.ownFmt(allocator, "%slotg_{d}", .{id});
        try self.extra_slot_names.put(id, slot_name);
        if (out) |stmt| {
            try stmt.print("  {s} = alloca i8, i64 {d}, align {d}\n", .{ slot_name, register_slot_bytes, register_slot_align });
        }
        return slot_name;
    }

    fn getReg(self: *FunctionState, id: u32) ?Value {
        return self.regs.get(id);
    }

    fn getRegGlobal(self: *FunctionState, id: u32) ?Value {
        if (self.sig.slotOf(id)) |slot| {
            return self.getReg(slot);
        }
        return self.getReg(id);
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

    fn enrichPointerValue(self: *const FunctionState, value: Value) Value {
        if (value.ty != .ptr) return value;
        if (value.origin.indirect_sig_index != null and value.origin.const_name != null) return value;
        if (self.lookupMemoryPtrMeta(value.expr, 0)) |meta| {
            var enriched = value;
            if (enriched.origin.const_name == null) enriched.origin.const_name = meta.origin.const_name;
            if (enriched.origin.indirect_sig_index == null) enriched.origin.indirect_sig_index = meta.origin.indirect_sig_index;
            enriched.const_ref = enriched.const_ref orelse meta.origin.const_name;
            enriched.interior_ptr = enriched.interior_ptr or meta.interior_ptr;
            enriched.borrow_view = enriched.borrow_view or meta.interior_ptr;
            return enriched;
        }
        return value;
    }

    fn reloadLiveRegs(self: *FunctionState, allocator: std.mem.Allocator, out: anytype, live_caps: []const u16) !void {
        _ = live_caps;
        for (self.reg_slots, 0..) |maybe_slot, idx| {
            const slot = maybe_slot orelse continue;
            const reg_id: u32 = @intCast(idx);
            const value = self.getReg(reg_id) orelse continue;
            const tmp = try self.tempName(allocator);
            try out.print("  {s} = load ", .{tmp});
            try writeValueType(out, value);
            try out.print(", ptr {s}, align {d}\n", .{ slot, register_slot_align });
            var loaded = value;
            loaded.expr = tmp;
            try self.setReg(allocator, std.io.null_writer, reg_id, loaded);
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

    fn emit(self: *DebugInfo, out: anytype) !void {
        try emitLine(out, "");
        try emitLine(out, "!llvm.module.flags = !{!0, !1}");
        try emitLine(out, "!0 = !{i32 2, !\"Dwarf Version\", i32 4}");
        try emitLine(out, "!1 = !{i32 2, !\"Debug Info Version\", i32 3}");
        try out.print("!llvm.dbg.cu = !{{!{d}}}\n", .{self.compileUnitId()});
        try out.print("!{d} = distinct !DICompileUnit(language: DW_LANG_C99, file: !{d}, producer: \"saasm\", isOptimized: true, runtimeVersion: 0, emissionKind: FullDebug)\n", .{ self.compileUnitId(), self.source_file_id });
        try out.print("!{d} = !DISubroutineType(types: !{{}})\n", .{self.subroutine_type_id});

        for (self.file_nodes.items) |file| {
            try out.print("!{d} = !DIFile(filename: \"{s}\", directory: \"{s}\")\n", .{ file.id, file.filename, file.directory });
        }

        for (self.functions.items) |func| {
            try out.print("!{d} = distinct !DISubprogram(name: \"{s}\", linkageName: \"{s}\", scope: !{d}, file: !{d}, line: {d}, type: !{d}, unit: !{d}, scopeLine: {d}, spFlags: DISPFlagDefinition | DISPFlagOptimized)\n", .{ func.id, func.name, func.linkage_name, func.file_id, func.file_id, func.line, self.subroutine_type_id, self.compileUnitId(), func.line });
        }

        for (self.locations.items) |location| {
            try out.print("!{d} = !DILocation(line: {d}, column: {d}, scope: !{d})\n", .{ location.id, location.line, location.col, location.scope_id });
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
    if (fsig.llvm_name) |name| return name;
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
        .i1, .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64, .ptr, .blob_handle => true,
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
        .i64, .u64, .blob_handle => "i64",
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
        .i64, .u64, .f64, .ptr, .blob_handle => 8,
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

fn decorateCallReturn(value: Value, return_cap: ?inst.CapPrefix) Value {
    var ret = value;
    switch (return_cap orelse .by_value) {
        .borrow => {
            ret.borrow_view = true;
            ret.interior_ptr = true;
        },
        .raw => {
            ret.ffi_borrow = true;
            ret.interior_ptr = true;
        },
        else => {},
    }
    return ret;
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

fn emitLine(out: anytype, text: []const u8) !void {
    try out.writeAll(text);
    try out.writeByte('\n');
}

fn emitIndented(out: anytype, text: []const u8) !void {
    try out.writeAll("  ");
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

fn findRegValueByName(state: *FunctionState, symbols: *const symbol.SymbolTable, name: []const u8) ?Value {
    for (state.sig.reg_ids, 0..) |global_id, slot| {
        if (symbols.lookupName(global_id)) |entry_name| {
            if (std.mem.eql(u8, entry_name, name)) {
                if (state.getReg(@intCast(slot))) |value| return value;
            }
        }
    }
    return null;
}

fn valueFromOperand(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    string_literals: *const StringLiteralPool,
    symbols: *const symbol.SymbolTable,
    op: inst.Operand,
) !Value {
    return switch (op) {
        .reg => |id| blk: {
            if (state.getReg(id)) |reg_value| {
                break :blk state.enrichPointerValue(reg_value);
            }
            const name = if (id < state.sig.reg_ids.len)
                symbols.lookupName(state.sig.globalId(id)) orelse return EmitError.InvalidOperand
            else
                symbols.lookupName(id) orelse return EmitError.InvalidOperand;
            if (findRegValueByName(state, symbols, name)) |reg_value| {
                break :blk state.enrichPointerValue(reg_value);
            }
            break :blk .{
                .expr = try state.ownFmt(allocator, "@{s}", .{name}),
                .ty = .ptr,
                .const_ref = name,
                .origin = .{ .const_name = name },
            };
        },
        .text => |t| blk: {
            var text = std.mem.trim(u8, t, " \t");
            if (text.len == 0) return EmitError.InvalidOperand;
            if (text[0] == '*') {
                text = std.mem.trim(u8, text[1..], " \t");
                if (text.len == 0) return EmitError.InvalidOperand;
            }
            if (text.len >= 5 and std.mem.startsWith(u8, text, "utf8:")) {
                const literal_name = try string_literals.resolve(allocator, text) orelse return EmitError.InvalidOperand;
                break :blk .{ .expr = try state.ownFmt(allocator, "@{s}", .{literal_name}), .ty = .ptr };
            }
            if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
                const literal_name = try string_literals.resolve(allocator, text) orelse return EmitError.InvalidOperand;
                break :blk .{ .expr = try state.ownFmt(allocator, "@{s}", .{literal_name}), .ty = .ptr };
            }
            if (text.len >= 2 and text[0] == '&' and (std.ascii.isAlphabetic(text[1]) or text[1] == '_')) {
                const name = text[1..];
                if (findRegValueByName(state, symbols, name)) |reg_value| {
                    break :blk state.enrichPointerValue(reg_value);
                }
                if (state.hasConstRef(name)) {
                    break :blk .{ .expr = try state.ownFmt(allocator, "@{s}", .{name}), .ty = .ptr, .const_ref = name, .origin = .{ .const_name = name } };
                }
                if (symbols.findId(name)) |id| {
                    if (state.sig.slotOf(id)) |slot| {
                        break :blk state.getReg(slot) orelse EmitError.InvalidOperand;
                    }
                    break :blk state.getReg(id) orelse EmitError.InvalidOperand;
                }
            }
            if (text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_')) {
                if (findRegValueByName(state, symbols, text)) |reg_value| {
                    break :blk state.enrichPointerValue(reg_value);
                }
                if (state.hasConstRef(text)) {
                    break :blk .{ .expr = try state.ownFmt(allocator, "@{s}", .{text}), .ty = .ptr, .const_ref = text, .origin = .{ .const_name = text } };
                }
                if (symbols.findId(text)) |id| {
                    if (state.sig.slotOf(id)) |slot| {
                        break :blk state.getReg(slot) orelse EmitError.InvalidOperand;
                    }
                    break :blk state.getReg(id) orelse EmitError.InvalidOperand;
                }
            }
            break :blk try parseImmediateValue(allocator, state, text);
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
    out: anytype,
    state: *FunctionState,
    value: Value,
    target: sig.PrimType,
) !Value {
    if (value.fallible) return EmitError.InvalidOperand;
        if (value.ty == target) return if (target == .ptr) state.enrichPointerValue(value) else value;

    if (target == .ptr) {
        if (value.ty == .ptr) return state.enrichPointerValue(value);
        if (!isIntLike(value.ty)) return EmitError.UnsupportedType;
        const tmp = try state.tempName(allocator);
        try out.print("  {s} = inttoptr {s} {s} to ptr\n", .{ tmp, llvmTypeName(value.ty), value.expr });
        return .{
            .expr = tmp,
            .ty = .ptr,
            .interior_ptr = value.interior_ptr,
            .borrow_view = value.borrow_view,
            .ffi_borrow = value.ffi_borrow,
            .const_ref = value.const_ref,
            .origin = value.origin,
        };
    }

    if (value.ty == .ptr) {
        if (!isIntLike(target)) return EmitError.UnsupportedType;
        const tmp = try state.tempName(allocator);
        try out.print("  {s} = ptrtoint ptr {s} to {s}\n", .{ tmp, value.expr, llvmTypeName(target) });
        return .{
            .expr = tmp,
            .ty = target,
            .interior_ptr = value.interior_ptr,
            .borrow_view = value.borrow_view,
            .ffi_borrow = value.ffi_borrow,
            .const_ref = value.const_ref,
            .origin = value.origin,
        };
    }

    if (isIntLike(value.ty) and isIntLike(target)) {
        const src_bits = sig.primTypeBits(value.ty);
        const dst_bits = sig.primTypeBits(target);
        const tmp = try state.tempName(allocator);
        if (src_bits == dst_bits) {
            return .{ .expr = value.expr, .ty = target };
        } else if (src_bits < dst_bits) {
            const op = if (isSignedInt(value.ty)) "sext" else "zext";
            try out.print("  {s} = {s} {s} {s} to {s}\n", .{ tmp, op, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        } else {
            try out.print("  {s} = trunc {s} {s} to {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        }
        return .{ .expr = tmp, .ty = target };
    }

    if (isFloatLike(value.ty) and isFloatLike(target)) {
        const tmp = try state.tempName(allocator);
        if (sig.primTypeBits(value.ty) == sig.primTypeBits(target)) return value;
        if (sig.primTypeBits(value.ty) < sig.primTypeBits(target)) {
            try out.print("  {s} = fpext {s} {s} to {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        } else {
            try out.print("  {s} = fptrunc {s} {s} to {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        }
        return .{ .expr = tmp, .ty = target };
    }

    if (isIntLike(value.ty) and isFloatLike(target)) {
        const tmp = try state.tempName(allocator);
        const op = if (isSignedInt(value.ty)) "sitofp" else "uitofp";
        try out.print("  {s} = {s} {s} {s} to {s}\n", .{ tmp, op, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        return .{ .expr = tmp, .ty = target };
    }

    if (isFloatLike(value.ty) and isIntLike(target)) {
        const tmp = try state.tempName(allocator);
        const op = if (isSignedInt(target)) "fptosi" else "fptoui";
        try out.print("  {s} = {s} {s} {s} to {s}\n", .{ tmp, op, llvmTypeName(value.ty), value.expr, llvmTypeName(target) });
        return .{ .expr = tmp, .ty = target };
    }

    return EmitError.UnsupportedType;
}

fn emitPointerArithmetic(
    allocator: std.mem.Allocator,
    out: anytype,
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
        try out.print("  {s} = sub i64 0, {s}\n", .{ neg, offset_expr.expr });
        offset_expr = .{ .expr = neg, .ty = .i64 };
    }

    const gep = try state.tempName(allocator);
    try out.print("  {s} = getelementptr i8, ptr {s}, i64 {s}\n", .{ gep, ptr_expr.expr, offset_expr.expr });
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

fn emitHelpers(out: anytype, size_bits: u16, options: EmitOptions) !void {
    const size_ty_name = sizeTypeName(size_bits);
    try emitLine(out, "; SA-ASM LLVM IR");
    try emitLine(out, "");
    try emitLine(out, "@saasm_argc = internal global i32 0");
    try emitLine(out, "@saasm_argv = internal global ptr null");
    try emitLine(out, "@.mode_rb = private unnamed_addr constant [3 x i8] c\"rb\\00\"");
    try emitLine(out, "@.mode_wb = private unnamed_addr constant [3 x i8] c\"wb\\00\"");
    try emitLine(out, "");
    try out.print("declare ptr @malloc({s})\n", .{size_ty_name});
    try emitLine(out, "declare void @free(ptr)");
    try out.print("declare ptr @memcpy(ptr, ptr, {s})\n", .{size_ty_name});
    try emitLine(out, "declare ptr @fopen(ptr, ptr)");
    try emitLine(out, "declare i32 @fseek(ptr, i64, i32)");
    try emitLine(out, "declare i64 @ftell(ptr)");
    try emitLine(out, "declare void @rewind(ptr)");
    try out.print("declare {s} @fread(ptr, {s}, {s}, ptr)\n", .{ size_ty_name, size_ty_name, size_ty_name });
    try out.print("declare {s} @fwrite(ptr, {s}, {s}, ptr)\n", .{ size_ty_name, size_ty_name, size_ty_name });
    try emitLine(out, "declare i32 @fclose(ptr)");
    try out.print("declare {s} @write(i32, ptr, {s})\n", .{ size_ty_name, size_ty_name });
    try emitLine(out, "declare void @exit(i32)");
    try emitLine(out, "declare i32 @fprintf(ptr, ptr, ...)");
    try emitLine(out, "declare ptr @getenv(ptr)");
    try emitLine(out, "declare i64 @strlen(ptr)");
    try emitLine(out, "declare i32 @memcmp(ptr, ptr, i64)");
    try emitLine(out, "@stderr = external global ptr");
    try out.print("@.panic_code_fmt = private unnamed_addr constant [{d} x i8] c\"PANIC: code=%d\\0A\\00\"\n", .{"PANIC: code=%d\n".len + 1});
    try out.print("@.panic_msg_fmt = private unnamed_addr constant [{d} x i8] c\"PANIC[%d]: %.*s\\0A\\00\"\n", .{"PANIC[%d]: %.*s\n".len + 1});
    try emitLine(out, "");

    const stderr_align: u32 = if (size_bits == 32) 4 else 8;
    try out.print("define internal void @__sa_panic(i32 %code, ptr %msg, {s} %len) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try out.print("  %stderr = load ptr, ptr @stderr, align {d}\n", .{stderr_align});
    try emitLine(out, "  %has_msg_ptr = icmp ne ptr %msg, null");
    try out.print("  %has_msg_len = icmp ne {s} %len, 0\n", .{size_ty_name});
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

    try out.print("define internal ptr @sa_strdupz(ptr %src, {s} %len) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try out.print("  %size = add {s} %len, 1\n", .{size_ty_name});
    try out.print("  %buf = call ptr @malloc({s} %size)\n", .{size_ty_name});
    try out.print("  %copy = call ptr @memcpy(ptr %buf, ptr %src, {s} %len)\n", .{size_ty_name});
    try out.print("  %end = getelementptr i8, ptr %buf, {s} %len\n", .{size_ty_name});
    try emitLine(out, "  store i8 0, ptr %end, align 1");
    try emitLine(out, "  ret ptr %buf");
    try emitLine(out, "}");
    try emitLine(out, "");

    try out.print("define internal i1 @sa_streq(ptr %lhs, ptr %rhs) {{\n", .{});
    try emitLine(out, "entry:");
    try emitLine(out, "  %lhs_len = call i64 @strlen(ptr %lhs)");
    try emitLine(out, "  %len = call i64 @strlen(ptr %rhs)");
    try emitLine(out, "  %len_ok = icmp eq i64 %lhs_len, %len");
    try emitLine(out, "  br i1 %len_ok, label %compare, label %miss");
    try emitLine(out, "compare:");
    try emitLine(out, "  %cmp = call i32 @memcmp(ptr %lhs, ptr %rhs, i64 %len)");
    try emitLine(out, "  %same = icmp eq i32 %cmp, 0");
    try emitLine(out, "  ret i1 %same");
    try emitLine(out, "miss:");
    try emitLine(out, "  ret i1 false");
    try emitLine(out, "}");
    try emitLine(out, "");

    try out.print("define internal void @sys_print(ptr %msg, {s} %len) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try out.print("  %_ = call {s} @write(i32 1, ptr %msg, {s} %len)\n", .{ size_ty_name, size_ty_name });
    try emitLine(out, "  ret void");
    try emitLine(out, "}");
    try emitLine(out, "");

    if (options.wasm_compat) {
        try emitLine(out, "define internal void @sa_print_bytes(ptr %msg, i64 %len) {");
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

    try emitLine(out, "define internal void @sys_exit(i32 %code) {");
    try emitLine(out, "entry:");
    try emitLine(out, "  call void @exit(i32 %code)");
    try emitLine(out, "  unreachable");
    try emitLine(out, "}");
    try emitLine(out, "");

    try emitLine(out, "define internal i32 @sys_argc() {");
    try emitLine(out, "entry:");
    try emitLine(out, "  %argc = load i32, ptr @saasm_argc, align 4");
    try emitLine(out, "  ret i32 %argc");
    try emitLine(out, "}");
    try emitLine(out, "");

    try out.print("define internal ptr @sys_argv({s} %index) {{\n", .{size_ty_name});
    try emitLine(out, "entry:");
    try emitLine(out, "  %argv = load ptr, ptr @saasm_argv, align 8");
    try out.print("  %slot = getelementptr ptr, ptr %argv, {s} %index\n", .{size_ty_name});
    try emitLine(out, "  %res = load ptr, ptr %slot, align 8");
    try emitLine(out, "  ret ptr %res");
    try emitLine(out, "}");
    try emitLine(out, "");

    if (size_bits == 32) {
        try emitLine(out, "define internal ptr @sys_read_file(ptr %path, i32 %path_len, ptr %out_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @sa_strdupz(ptr %path, i32 %path_len)");
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

        try emitLine(out, "define internal i32 @sys_write_file(ptr %path, i32 %path_len, ptr %data, i32 %data_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @sa_strdupz(ptr %path, i32 %path_len)");
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
        try emitLine(out, "define internal ptr @sys_read_file(ptr %path, i64 %path_len, ptr %out_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @sa_strdupz(ptr %path, i64 %path_len)");
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

        try emitLine(out, "define internal i32 @sys_write_file(ptr %path, i64 %path_len, ptr %data, i64 %data_len) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  %path_c = call ptr @sa_strdupz(ptr %path, i64 %path_len)");
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

fn emitFunctionHeader(out: anytype, state: *FunctionState, dbg_id: ?u32) !void {
    try out.writeAll("define ");
    try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, state.sig.return_fallible);
    try out.print(" @{s}(", .{state.emitted_name});
    for (state.sig.params, 0..) |param, idx| {
        if (idx != 0) try out.writeAll(", ");
        const ty = valueTypeForPrefix(param.cap, param.ty);
        try out.print("{s} %{s}", .{ llvmTypeName(ty), param.name });
    }
    try out.writeAll(")");
    if (state.sig.kind == .test_func) {
        try out.writeAll(" noinline optnone");
    }
    if (dbg_id) |id| {
        try out.print(" !dbg !{d}", .{id});
    }
    try emitLine(out, " {");
    try emitLine(out, "entry:");
}

fn emitFunctionFooter(out: anytype) !void {
    try emitLine(out, "}");
    try emitLine(out, "");
}

fn ensureFunctionSlots(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    def_dict: ?*const flattener.DefDict,
    items: []const referee.AnnotatedInstruction,
) !void {
    for (items) |item| {
        for (item.base.operands) |operand| {
            if (operand == .reg) {
                _ = try state.ensureSlot(allocator, out, operand.reg);
            }
        }
        switch (item.base.kind) {
            .call, .call_indirect => {
                const call_text = try instructionCallText(allocator, symbols, def_dict, item.base);
                defer allocator.free(call_text);
                var parsed = call.parseCall(allocator, call_text) catch continue;
                defer parsed.deinit(allocator);
                if (parsed.dest) |dest| {
                    if (symbols.findId(dest)) |id| {
                        if (state.sig.slotOf(id)) |slot| {
                            _ = try state.ensureSlot(allocator, out, slot);
                        }
                    }
                }
            },
            else => {},
        }
    }
}

const EmitFunctionChunk = struct {
    start: usize,
    end: usize,
    sig_index: usize,
    subprogram_id: ?u32,
};

fn shouldEmitMainWrapper(options: EmitOptions) bool {
    return !options.test_mode;
}

fn emitTestHarnessMain(
    allocator: std.mem.Allocator,
    out: anytype,
    function_sigs: []const sig.FunctionSig,
    size_bits: u16,
) !void {
    _ = size_bits;
    try emitPrivateCString(out, ".sa_test_name_env", "SA_TEST_NAME");
    try emitPrivateCString(out, ".sa_test_missing_msg", "error: no matching test\n");

    var test_count: usize = 0;
    for (function_sigs) |fsig| {
        if (fsig.kind == .test_func) test_count += 1;
    }
    if (test_count == 0) {
        try emitLine(out, "define i32 @main(i32 %argc, ptr %argv) {");
        try emitLine(out, "entry:");
        try emitLine(out, "  ret i32 0");
        try emitLine(out, "}");
        try emitLine(out, "");
        return;
    }

    for (function_sigs) |fsig| {
        if (fsig.kind != .test_func) continue;
        const internal = fsig.llvm_name orelse fsig.name;
        try out.print("@.sa_test_name_{d} = private constant [{d} x i8] c\"", .{ fsig.id, internal.len + 1 });
        for (internal) |byte| {
            try emitByteEscape(out, byte);
        }
        try emitLine(out, "\\00\"");
    }
    try emitLine(out, "");

    try out.print("define i32 @main(i32 %argc, ptr %argv) {{\n", .{});
    try emitLine(out, "entry:");
    try emitLine(out, "  %filter = call ptr @getenv(ptr @.sa_test_name_env)");
    try emitLine(out, "  %has_filter = icmp ne ptr %filter, null");
    try emitLine(out, "  br i1 %has_filter, label %select, label %run_all");
    try emitLine(out, "run_all:");
    for (function_sigs) |fsig| {
        if (fsig.kind != .test_func) continue;
        try out.print("  call void @{s}()\n", .{emittedFunctionName(fsig)});
    }
    try emitLine(out, "  ret i32 0");
    try emitLine(out, "select:");
    for (function_sigs) |fsig| {
        if (fsig.kind != .test_func) continue;
        const internal = fsig.llvm_name orelse fsig.name;
        const next_label = try std.fmt.allocPrint(allocator, "next_test_{d}", .{fsig.id});
        defer allocator.free(next_label);
        const run_label = try std.fmt.allocPrint(allocator, "run_test_{d}", .{fsig.id});
        defer allocator.free(run_label);
        _ = internal;
        try out.print("  %match_{d} = call i1 @sa_streq(ptr %filter, ptr @.sa_test_name_{d})\n", .{ fsig.id, fsig.id });
        try out.print("  br i1 %match_{d}, label %{s}, label %{s}\n", .{ fsig.id, run_label, next_label });
        try out.print("{s}:\n", .{run_label});
        try out.print("  call void @{s}()\n", .{emittedFunctionName(fsig)});
        try emitLine(out, "  ret i32 0");
        try out.print("{s}:\n", .{next_label});
    }
    try emitLine(out, "  %stderr = load ptr, ptr @stderr, align 8");
    try emitLine(out, "  call i32 (ptr, ptr, ...) @fprintf(ptr %stderr, ptr @.sa_test_missing_msg)");
    try emitLine(out, "  call void @exit(i32 1)");
    try emitLine(out, "  unreachable");
    try emitLine(out, "}");
    try emitLine(out, "");
}

fn chooseEmitWorkerCount(requested_jobs: ?usize, chunk_count: usize) usize {
    if (chunk_count < 2) return 1;
    // Keep function emission deterministic unless the parallel path is explicitly proven safe.
    _ = requested_jobs;
    return 1;
}

fn emitExternDeclToWriter(
    out: anytype,
    fsig: sig.FunctionSig,
) !void {
    try out.writeAll("declare ");
    try writeReturnAbiType(out, fsig.return_cap, fsig.return_ty, fsig.return_fallible);
    try out.print(" @{s}(", .{fsig.name});
    for (fsig.params, 0..) |param, pidx| {
        if (pidx != 0) try out.writeAll(", ");
        const ty = valueTypeForPrefix(param.cap, param.ty);
        try out.print("{s}", .{llvmTypeName(ty)});
    }
    try emitLine(out, ")");
    try emitLine(out, "");
}

fn emitFunctionChunkToWriter(
    allocator: std.mem.Allocator,
    out: anytype,
    annotated: []const referee.AnnotatedInstruction,
    function_sigs: []const sig.FunctionSig,
    const_decls: []const common_const_decl.ConstDecl,
    def_dict: ?*const flattener.DefDict,
    string_literals: *const StringLiteralPool,
    symbols: *const symbol.SymbolTable,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    options: EmitOptions,
    size_bits: u16,
    chunk: EmitFunctionChunk,
    dbg_ids: []const ?u32,
) !void {
    _ = loc_table;
    _ = source_path;

    if (chunk.start >= chunk.end or chunk.end > annotated.len) return EmitError.InvalidOperand;
    const item = annotated[chunk.start];
    const fsig = function_sigs[chunk.sig_index];

    switch (item.base.kind) {
        .extern_decl => {
            return emitExternDeclToWriter(out, fsig);
        },
        .func_decl, .ffi_wrapper_decl, .export_decl, .test_decl => {
            var state = try FunctionState.init(allocator, fsig, fsig.reg_ids.len, string_literals);
            defer state.deinit(allocator);
            for (const_decls) |item_const| {
                try state.setConstRef(item_const.name);
            }

            try emitFunctionHeader(out, &state, chunk.subprogram_id);
            try ensureFunctionSlots(allocator, out, &state, symbols, def_dict, annotated[chunk.start + 1 .. chunk.end]);
            for (fsig.params, 0..) |param, pidx| {
                const reg_id = fsig.param_ids[pidx];
                const reg_slot = fsig.slotOf(reg_id) orelse return EmitError.InvalidOperand;
                const value = Value{
                    .expr = try state.ownFmt(allocator, "%{s}", .{param.name}),
                    .ty = valueTypeForPrefix(param.cap, param.ty),
                    .borrow_view = param.cap == .borrow,
                    .ffi_borrow = param.cap == .raw,
                };
                try state.setReg(allocator, out, reg_slot, value);
            }

            for (annotated[chunk.start + 1 .. chunk.end], chunk.start + 1 ..) |body_item, idx| {
                const inst_dbg_id = if (options.debug) dbg_ids[idx] else null;
                try emitInstruction(allocator, out, &state, string_literals, symbols, def_dict, function_sigs, const_decls, options, size_bits, inst_dbg_id, body_item);
            }

            try emitFunctionFooter(out);
        },
        else => return EmitError.InvalidOperand,
    }
}

fn emitUserFunctionsParallel(
    allocator: std.mem.Allocator,
    out: anytype,
    annotated: []const referee.AnnotatedInstruction,
    function_sigs: []const sig.FunctionSig,
    const_decls: []const common_const_decl.ConstDecl,
    def_dict: ?*const flattener.DefDict,
    string_literals: *const StringLiteralPool,
    symbols: *const symbol.SymbolTable,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    options: EmitOptions,
    size_bits: u16,
) !void {
    const verified = .{
        .annotated = annotated,
        .function_sigs = function_sigs,
        .const_decls = const_decls,
        .symbols = symbols,
    };
    try emitUserFunctions(allocator, out, verified, def_dict, string_literals, loc_table, source_path, options, size_bits);
}

fn emitArgList(
    allocator: std.mem.Allocator,
    prelude: anytype,
    stmt: anytype,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
    symbols: *const symbol.SymbolTable,
    args: []const call.ParsedArg,
    params: []const sig.ParamSpec,
) !void {
    var prelude_sink = TextSink(@TypeOf(prelude.writer())){ .inner = prelude.writer() };
    var stmt_sink = TextSink(@TypeOf(stmt.writer())){ .inner = stmt.writer() };
    for (args, params, 0..) |arg, param, idx| {
        if (idx != 0) try stmt_sink.writeAll(", ");
        const expected = valueTypeForPrefix(param.cap, param.ty);
        const value = try valueFromArgText(allocator, state, def_dict, symbols, arg.text);
        const coerced = try castValue(allocator, &prelude_sink, state, value, expected);
        try stmt_sink.print("{s} {s}", .{ llvmTypeName(expected), coerced.expr });
    }
}

fn emitCallArgsDirect(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
    symbols: *const symbol.SymbolTable,
    args: []const call.ParsedArg,
    params: []const sig.ParamSpec,
) !std.ArrayList(Value) {
    var values = std.ArrayList(Value).init(allocator);
    errdefer values.deinit();
    try values.ensureTotalCapacity(args.len);
    for (args, params) |arg, param| {
        const expected = valueTypeForPrefix(param.cap, param.ty);
        const value = try valueFromArgText(allocator, state, def_dict, symbols, arg.text);
        try values.append(try castValue(allocator, out, state, value, expected));
    }
    return values;
}

fn emitTypedCallArgs(out: anytype, values: []const Value, params: []const sig.ParamSpec) !void {
    for (values, params, 0..) |value, param, idx| {
        if (idx != 0) try out.writeAll(", ");
        const expected = valueTypeForPrefix(param.cap, param.ty);
        try out.print("{s} {s}", .{ llvmTypeName(expected), value.expr });
    }
}

fn valueFromArgText(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
    symbols: *const symbol.SymbolTable,
    text: []const u8,
) !Value {
    var trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return EmitError.InvalidOperand;

    const raw = if (trimmed[0] == '*') blk: {
        const inner = std.mem.trim(u8, trimmed[1..], " \t");
        if (inner.len == 0) return EmitError.InvalidOperand;
        break :blk inner;
    } else trimmed;

    if (raw.len >= 5 and std.mem.startsWith(u8, raw, "utf8:")) {
        const literal_name = try state.string_literals.resolve(allocator, raw) orelse return EmitError.InvalidOperand;
        return .{ .expr = try state.ownFmt(allocator, "@{s}", .{literal_name}), .ty = .ptr };
    }

    if (raw.len >= 2 and raw[0] == '"' and raw[raw.len - 1] == '"') {
        const literal_name = try state.string_literals.resolve(allocator, raw) orelse return EmitError.InvalidOperand;
        return .{ .expr = try state.ownFmt(allocator, "@{s}", .{literal_name}), .ty = .ptr };
    }

    var resolved = raw;
    var resolved_owned = false;
    if (def_dict) |defs| {
        resolved = try defs.foldText(allocator, raw);
        resolved_owned = true;
    }
    defer if (resolved_owned) allocator.free(resolved);

    if (resolved.len >= 2 and resolved[0] == '&' and (std.ascii.isAlphabetic(resolved[1]) or resolved[1] == '_')) {
        const name = resolved[1..];
        if (findRegValueByName(state, symbols, name)) |value| return state.enrichPointerValue(value);
        if (state.hasConstRef(name)) {
            return .{ .expr = try state.ownFmt(allocator, "@{s}", .{name}), .ty = .ptr, .const_ref = name, .origin = .{ .const_name = name } };
        }
    }
    if (resolved.len != 0 and (std.ascii.isAlphabetic(resolved[0]) or resolved[0] == '_')) {
        if (findRegValueByName(state, symbols, resolved)) |value| return state.enrichPointerValue(value);
        if (state.hasConstRef(resolved)) {
            return .{ .expr = try state.ownFmt(allocator, "@{s}", .{resolved}), .ty = .ptr, .const_ref = resolved, .origin = .{ .const_name = resolved } };
        }
        if (symbols.findId(resolved)) |id| {
            if (state.getReg(id)) |value| return state.enrichPointerValue(value);
            if (findRegValueByName(state, symbols, resolved)) |value| return state.enrichPointerValue(value);
            return .{
                .expr = try state.ownFmt(allocator, "@{s}", .{resolved}),
                .ty = .ptr,
                .const_ref = resolved,
                .origin = .{ .const_name = resolved },
            };
        }
    }
    return try parseImmediateValue(allocator, state, resolved);
}

fn valueFromRegOrConst(
    allocator: std.mem.Allocator,
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    reg_id: u32,
) !Value {
    if (state.getReg(reg_id)) |value| return state.enrichPointerValue(value);
    const name = symbols.lookupName(reg_id) orelse return EmitError.InvalidOperand;
    if (findRegValueByName(state, symbols, name)) |value| return state.enrichPointerValue(value);
    return .{
        .expr = try state.ownFmt(allocator, "@{s}", .{name}),
        .ty = .ptr,
        .const_ref = name,
        .origin = .{ .const_name = name },
    };
}

fn emitByteEscape(out: anytype, byte: u8) !void {
    switch (byte) {
        '\\' => try out.writeAll("\\5C"),
        '"' => try out.writeAll("\\22"),
        '\n' => try out.writeAll("\\0A"),
        '\r' => try out.writeAll("\\0D"),
        '\t' => try out.writeAll("\\09"),
        else => {
            const hex = "0123456789ABCDEF";
            try out.writeByte('\\');
            try out.writeByte(hex[(byte >> 4) & 0x0f]);
            try out.writeByte(hex[byte & 0x0f]);
        },
    }
}

fn emitPrivateCString(out: anytype, name: []const u8, text: []const u8) !void {
    try out.print("@{s} = private unnamed_addr constant [{d} x i8] c\"", .{ name, text.len + 1 });
    for (text) |byte| {
        try emitByteEscape(out, byte);
    }
    try out.writeAll("\\00\"");
    try out.writeByte('\n');
}

fn decodeQuotedStringBytes(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') {
        return EmitError.InvalidOperand;
    }

    var out = try allocator.alloc(u8, raw.len - 2);
    errdefer allocator.free(out);
    var len: usize = 0;

    var i: usize = 1;
    while (i < raw.len - 1) {
        const c = raw[i];
        if (c != '\\') {
            out[len] = c;
            len += 1;
            i += 1;
            continue;
        }

        if (i + 1 >= raw.len - 1) return EmitError.InvalidOperand;
        switch (raw[i + 1]) {
            '\\' => {
                out[len] = '\\';
                len += 1;
                i += 2;
            },
            '"' => {
                out[len] = '"';
                len += 1;
                i += 2;
            },
            'n' => {
                out[len] = '\n';
                len += 1;
                i += 2;
            },
            'r' => {
                out[len] = '\r';
                len += 1;
                i += 2;
            },
            't' => {
                out[len] = '\t';
                len += 1;
                i += 2;
            },
            '0' => {
                out[len] = 0;
                len += 1;
                i += 2;
            },
            'x' => {
                if (i + 3 >= raw.len - 1) return EmitError.InvalidOperand;
                const hi = std.fmt.charToDigit(raw[i + 2], 16) catch return EmitError.InvalidOperand;
                const lo = std.fmt.charToDigit(raw[i + 3], 16) catch return EmitError.InvalidOperand;
                out[len] = @as(u8, @intCast((hi << 4) | lo));
                len += 1;
                i += 4;
            },
            else => return EmitError.InvalidOperand,
        }
    }

    return try allocator.realloc(out, len);
}

const StringLiteralEntry = struct {
    name: []const u8,
    bytes: []const u8,
};

const StringLiteralPool = struct {
    allocator: std.mem.Allocator,
    index: std.StringHashMap(usize),
    entries: std.ArrayList(StringLiteralEntry),
    next_id: usize = 0,

    fn init(allocator: std.mem.Allocator) StringLiteralPool {
        return .{
            .allocator = allocator,
            .index = std.StringHashMap(usize).init(allocator),
            .entries = std.ArrayList(StringLiteralEntry).init(allocator),
        };
    }

    fn deinit(self: *StringLiteralPool) void {
        self.index.deinit();
        for (self.entries.items) |entry| {
            self.allocator.free(entry.name);
            self.allocator.free(entry.bytes);
        }
        self.entries.deinit();
        self.* = undefined;
    }

    fn decodeLiteral(self: *const StringLiteralPool, allocator: std.mem.Allocator, text: []const u8) !?[]u8 {
        _ = self;
        const trimmed = std.mem.trim(u8, text, " \t");
        if (trimmed.len == 0) return null;

        var body = trimmed;
        if (body[0] == '*') {
            body = std.mem.trim(u8, body[1..], " \t");
            if (body.len == 0) return null;
        }
        if (std.mem.startsWith(u8, body, "utf8:")) {
            body = std.mem.trim(u8, body["utf8:".len..], " \t");
        }
        if (body.len < 2 or body[0] != '"') return null;
        return try decodeQuotedStringBytes(allocator, body);
    }

    fn collectText(self: *StringLiteralPool, text: []const u8) !void {
        const bytes_opt = try self.decodeLiteral(self.allocator, text);
        const bytes = bytes_opt orelse return;
        errdefer self.allocator.free(bytes);
        if (self.index.get(bytes)) |_| {
            self.allocator.free(bytes);
            return;
        }

        const name = try std.fmt.allocPrint(self.allocator, ".sa_str_{d}", .{self.next_id});
        self.next_id += 1;
        errdefer self.allocator.free(name);

        const idx: usize = self.entries.items.len;
        try self.entries.append(.{
            .name = name,
            .bytes = bytes,
        });
        try self.index.put(bytes, idx);
    }

    fn intern(self: *StringLiteralPool, text: []const u8) ![]const u8 {
        const bytes_opt = try self.decodeLiteral(self.allocator, text);
        const bytes = bytes_opt orelse return EmitError.InvalidOperand;
        errdefer self.allocator.free(bytes);
        if (self.index.get(bytes)) |idx| {
            self.allocator.free(bytes);
            return self.entries.items[idx].name;
        }

        const name = try std.fmt.allocPrint(self.allocator, ".sa_str_{d}", .{self.next_id});
        self.next_id += 1;
        errdefer self.allocator.free(name);

        const idx: usize = self.entries.items.len;
        try self.entries.append(.{
            .name = name,
            .bytes = bytes,
        });
        try self.index.put(bytes, idx);
        return name;
    }

    fn resolve(self: *const StringLiteralPool, allocator: std.mem.Allocator, text: []const u8) !?[]const u8 {
        const bytes_opt = try self.decodeLiteral(allocator, text);
        const bytes = bytes_opt orelse return null;
        defer allocator.free(bytes);
        if (self.index.get(bytes)) |idx| {
            return self.entries.items[idx].name;
        }
        return null;
    }

    fn emit(self: *const StringLiteralPool, out: anytype) !void {
        for (self.entries.items) |entry| {
            try emitPrivateCString(out, entry.name, entry.bytes);
        }
    }
};

fn collectStringLiterals(
    allocator: std.mem.Allocator,
    pool: *StringLiteralPool,
    annotated: []const referee.AnnotatedInstruction,
) !void {
    for (annotated) |item| {
        switch (item.base.kind) {
            .call, .call_indirect, .panic, .panic_msg => {
                var parsed = try call.parseCall(allocator, item.base.raw_text);
                defer parsed.deinit(allocator);
                for (parsed.args) |arg| {
                    try pool.collectText(arg.text);
                }
            },
            else => {},
        }

        for (item.base.operands) |operand| {
            if (operand == .text) {
                try pool.collectText(operand.text);
            }
        }
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

fn emitConstBytes(out: anytype, value: common_const_decl.ConstValue) !void {
    switch (value) {
        .hex => |literal| for (literal.bytes) |byte| try emitByteEscape(out, byte),
        .utf8 => |literal| for (literal.bytes) |byte| try emitByteEscape(out, byte),
        .repeat => |literal| for (literal.bytes) |byte| try emitByteEscape(out, byte),
        .struct_ => |literal| {
            for (literal.fields) |field| {
                try emitConstBytes(out, field.value);
            }
        },
        .vtable => return EmitError.UnsupportedType,
    }
}

fn emitConstDecls(
    out: anytype,
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
) !void {
    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                if (literal.slots.len == 0) return EmitError.InvalidOperand;
                try out.print("@{s} = private unnamed_addr constant [{d} x ptr] [", .{ decl.name, literal.slots.len });
                for (literal.slots, 0..) |slot, idx| {
                    if (idx != 0) try out.writeAll(", ");
                    const fn_sig = findFunctionSigIndex(sigs, slot.func_name) orelse return EmitError.UnknownFunction;
                    _ = fn_sig;
                    try out.print("ptr @{s}", .{emittedFunctionName(sigs[findFunctionSigIndex(sigs, slot.func_name).?])});
                }
                try emitLine(out, "]");
            },
            else => {
                const len = try constByteLen(decl.value);
                try out.print("@{s} = private unnamed_addr constant [{d} x i8] c\"", .{ decl.name, len });
                try emitConstBytes(out, decl.value);
                try out.writeAll("\"\n");
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
    def_dict: ?*const flattener.DefDict,
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    src: Value,
    offset: u64,
    loaded_ty: sig.PrimType,
) PointerOrigin {
    if (src.origin.indirect_sig_index) |sig_index| {
        return .{
            .const_name = src.origin.const_name orelse src.const_ref,
            .const_offset = offset,
            .indirect_sig_index = sig_index,
        };
    }
    const const_name = src.origin.const_name orelse src.const_ref orelse return .{};
    const decl = findConstDeclByName(const_decls, const_name) orelse return .{ .const_name = const_name };
    _ = def_dict;
    return resolveConstValueOrigin(decl.value, const_name, offset, loaded_ty, sigs);
}

fn resolveIndirectCallOriginFromText(
    def_dict: ?*const flattener.DefDict,
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    text: []const u8,
) PointerOrigin {
    const raw_text = if (def_dict) |defs| defs.foldText(std.heap.page_allocator, text) catch text else text;
    defer if (def_dict != null and raw_text.ptr != text.ptr) std.heap.page_allocator.free(raw_text);
    const trimmed = std.mem.trim(u8, raw_text, " \t");
    if (trimmed.len == 0) return .{};
    if (trimmed[0] == '@' and trimmed.len > 1) {
        const name = trimmed[1..];
        const decl = findConstDeclByName(const_decls, name) orelse return .{ .const_name = name };
        return resolveConstValueOrigin(decl.value, name, 0, .ptr, sigs);
    }
    if (trimmed[0] == '&' and trimmed.len > 1) {
        const name = trimmed[1..];
        const decl = findConstDeclByName(const_decls, name) orelse return .{ .const_name = name };
        return resolveConstValueOrigin(decl.value, name, 0, .ptr, sigs);
    }
    if (std.mem.indexOfScalar(u8, trimmed, '@')) |at_idx| {
        const name = std.mem.trim(u8, trimmed[at_idx + 1 ..], " \t");
        const decl = findConstDeclByName(const_decls, name) orelse return .{ .const_name = name };
        return resolveConstValueOrigin(decl.value, name, 0, .ptr, sigs);
    }
    return .{};
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
    def_dict: ?*const flattener.DefDict,
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

    const folded_offset = if (def_dict) |defs| defs.foldText(std.heap.page_allocator, offset_token) catch offset_token else offset_token;
    defer if (def_dict != null and folded_offset.ptr != offset_token.ptr) std.heap.page_allocator.free(folded_offset);
    const parsed_offset = std.fmt.parseInt(u64, folded_offset, 10) catch {
        if (findVtableSlotSigIndexByName(const_decls, sigs, folded_offset)) |sig_index| return sig_index;
        return null;
    };

    if (findVtableSlotSigIndexByOffset(const_decls, sigs, parsed_offset)) |sig_index| {
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

fn findVtableSlotSigIndexByOffset(
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    offset: u64,
) ?usize {
    if (offset % 8 != 0) return null;
    const slot_index: usize = @intCast(offset / 8);
    var resolved: ?usize = null;
    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                if (slot_index >= literal.slots.len) continue;
                const sig_index = findFunctionSigIndex(sigs, literal.slots[slot_index].func_name) orelse return null;
                if (resolved) |existing| {
                    const existing_sig = sigs[existing];
                    const candidate_sig = sigs[sig_index];
                    if (!functionSigsCompatible(existing_sig, candidate_sig)) return null;
                } else {
                    resolved = sig_index;
                }
            },
            else => {},
        }
    }
    return resolved;
}

fn inferIndirectSigIndexFromExpr(
    const_decls: []const common_const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
    expr: []const u8,
) ?usize {
    const trimmed = std.mem.trim(u8, expr, " \t");
    if (trimmed.len == 0) return null;
    if (trimmed[0] == '@' and trimmed.len > 1) {
        const name = trimmed[1..];
        if (findConstDeclByName(const_decls, name)) |decl| {
            const origin = resolveConstValueOrigin(decl.value, name, 0, .ptr, sigs);
            if (origin.indirect_sig_index) |sig_index| return sig_index;
        }
    }
    if (trimmed[0] == '&' and trimmed.len > 1) {
        const name = trimmed[1..];
        if (findConstDeclByName(const_decls, name)) |decl| {
            const origin = resolveConstValueOrigin(decl.value, name, 0, .ptr, sigs);
            if (origin.indirect_sig_index) |sig_index| return sig_index;
        }
    }
    if (std.mem.indexOfScalar(u8, trimmed, '@')) |at_idx| {
        const name = std.mem.trim(u8, trimmed[at_idx + 1 ..], " \t");
        if (findConstDeclByName(const_decls, name)) |decl| {
            const origin = resolveConstValueOrigin(decl.value, name, 0, .ptr, sigs);
            if (origin.indirect_sig_index) |sig_index| return sig_index;
        }
    }
    return null;
}

fn emitBuiltinCall(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
    symbols: *const symbol.SymbolTable,
    options: EmitOptions,
    size_bits: u16,
    parsed: call.ParsedCall,
) !BuiltinCallResult {
    _ = options;
    const size_ty_name = sizeTypeName(size_bits);
    const name = parsed.callee;
    if (std.mem.eql(u8, name, "panic")) {
        if (parsed.args.len != 1) return EmitError.InvalidOperand;
        const code = try valueFromArgText(allocator, state, def_dict, symbols, parsed.args[0].text);
        const code_i32 = try castValue(allocator, out, state, code, .i32);
        try out.print("  call void @__sa_panic(i32 {s}, ptr null, {s} 0)\n", .{ code_i32.expr, size_ty_name });
        try emitLine(out, "  unreachable");
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "panic_msg")) {
        if (parsed.args.len != 3) return EmitError.InvalidOperand;
        const code = try castValue(allocator, out, state, try valueFromArgText(allocator, state, def_dict, symbols, parsed.args[0].text), .i32);
        const msg = try castValue(allocator, out, state, try valueFromArgText(allocator, state, def_dict, symbols, parsed.args[1].text), .ptr);
        const len_ty: sig.PrimType = sizePrimType(size_bits);
        const len = try castValue(allocator, out, state, try valueFromArgText(allocator, state, def_dict, symbols, parsed.args[2].text), len_ty);
        try out.print("  call void @__sa_panic(i32 {s}, ptr {s}, {s} {s})\n", .{ code.expr, msg.expr, size_ty_name, len.expr });
        try emitLine(out, "  unreachable");
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "sys_argc")) {
        const tmp = try state.tempName(allocator);
        try out.print("  {s} = call i32 @sys_argc()\n", .{tmp});
        return .{ .handled_value = .{ .expr = tmp, .ty = .i32 } };
    }
    if (std.mem.eql(u8, name, "sys_argv")) {
        const tmp = try state.tempName(allocator);
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, &.{.{ .name = "index", .ty = .i64, .cap = .by_value }});
        defer values.deinit();
        if (values.items.len != 1) return EmitError.InvalidOperand;
        try out.print("  {s} = call ptr @sys_argv(i64 {s})\n", .{ tmp, values.items[0].expr });
        return .{ .handled_value = .{ .expr = tmp, .ty = .ptr, .borrow_view = true, .interior_ptr = true } };
    }
    if (std.mem.eql(u8, name, "sys_print")) {
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, &.{ .{ .name = "msg", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value } });
        defer values.deinit();
        try out.writeAll("  call void @sys_print(");
        try emitTypedCallArgs(out, values.items, &.{ .{ .name = "msg", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value } });
        try emitLine(out, ")");
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "sys_exit")) {
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, &.{.{ .name = "code", .ty = .i32, .cap = .by_value }});
        defer values.deinit();
        try out.writeAll("  call void @sys_exit(");
        try emitTypedCallArgs(out, values.items, &.{.{ .name = "code", .ty = .i32, .cap = .by_value }});
        try emitLine(out, ")");
        return .handled_void;
    }
    if (std.mem.eql(u8, name, "sys_read_file")) {
        const tmp = try state.tempName(allocator);
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, &.{ .{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "out_len", .ty = .ptr, .cap = .raw } });
        defer values.deinit();
        try out.print("  {s} = call ptr @sys_read_file(", .{tmp});
        try emitTypedCallArgs(out, values.items, &.{ .{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "out_len", .ty = .ptr, .cap = .raw } });
        try emitLine(out, ")");
        return .{ .handled_value = .{ .expr = tmp, .ty = .ptr, .borrow_view = true, .interior_ptr = true } };
    }
    if (std.mem.eql(u8, name, "sys_write_file")) {
        const tmp = try state.tempName(allocator);
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, &.{ .{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "data", .ty = .ptr, .cap = .raw }, .{ .name = "dlen", .ty = .i64, .cap = .by_value } });
        defer values.deinit();
        try out.print("  {s} = call i32 @sys_write_file(", .{tmp});
        try emitTypedCallArgs(out, values.items, &.{ .{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "data", .ty = .ptr, .cap = .raw }, .{ .name = "dlen", .ty = .i64, .cap = .by_value } });
        try emitLine(out, ")");
        return .{ .handled_value = .{ .expr = tmp, .ty = .i32 } };
    }
    return .not_builtin;
}

fn emitDirectCall(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
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
        const tmp = try state.tempName(allocator);
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, resolved.params);
        defer values.deinit();
        try out.print("  {s} = call ", .{tmp});
        try writeReturnAbiType(out, resolved.return_cap, resolved.return_ty, resolved.return_fallible);
        try out.print(" @{s}(", .{emittedFunctionName(resolved)});
        try emitTypedCallArgs(out, values.items, resolved.params);
        try emitLine(out, ")");
        return .{ .handled_value = decorateCallReturn(.{ .expr = tmp, .ty = ret_ty, .fallible = resolved.return_fallible }, resolved.return_cap) };
    } else {
        const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, resolved.params);
        defer values.deinit();
        try out.print("  call void @{s}(", .{emittedFunctionName(resolved)});
        try emitTypedCallArgs(out, values.items, resolved.params);
        try emitLine(out, ")");
        return .handled_void;
    }
}

fn emitIndirectCall(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
    const_decls: []const common_const_decl.ConstDecl,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    parsed: call.ParsedCall,
) !?Value {
    const callee_id = symbols.findId(parsed.callee) orelse return EmitError.UnknownFunction;
    const callee = state.getReg(callee_id) orelse return EmitError.InvalidOperand;
    var resolved_origin = callee.origin;
    if (resolved_origin.indirect_sig_index == null) {
        if (state.lookupMemoryPtrMeta(callee.expr, 0)) |meta| {
            resolved_origin = meta.origin;
        }
    }
    if (resolved_origin.indirect_sig_index == null) {
        if (callee.origin.const_name) |const_name| {
            var probe = callee;
            probe.origin.const_name = const_name;
            resolved_origin = resolveLoadOrigin(def_dict, const_decls, sigs, probe, probe.origin.const_offset, .ptr);
        } else if (callee.const_ref) |const_name| {
            var probe = callee;
            probe.origin.const_name = const_name;
            probe.const_ref = const_name;
            resolved_origin = resolveLoadOrigin(def_dict, const_decls, sigs, probe, probe.origin.const_offset, .ptr);
        }
    }
    if (resolved_origin.indirect_sig_index == null) {
        resolved_origin = resolveIndirectCallOriginFromText(def_dict, const_decls, sigs, parsed.callee);
    }
    if (resolved_origin.indirect_sig_index == null) {
        if (inferIndirectSigIndexFromExpr(const_decls, sigs, callee.expr)) |sig_index| {
            resolved_origin.indirect_sig_index = sig_index;
        }
    }
    if (resolved_origin.indirect_sig_index == null) {
        std.debug.print(
            "emit indirect missing provenance for {s}: expr={s} ty={s} const={?s} const_ref={?s} origin_const={?s} origin_sig={?d}\n",
            .{ parsed.callee, callee.expr, llvmTypeName(callee.ty), callee.const_ref, callee.const_ref, callee.origin.const_name, callee.origin.indirect_sig_index },
        );
        return EmitError.MissingIndirectCallProvenance;
    }
    const sig_index = resolved_origin.indirect_sig_index.?;
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

    const values = try emitCallArgsDirect(allocator, out, state, def_dict, symbols, parsed.args, resolved.params);
    defer values.deinit();

    const call_ty = returnTypeForSig(resolved.return_cap, resolved.return_ty);
    const tmp = if (call_ty == .void) null else try state.tempName(allocator);
    if (tmp) |tmp_name| {
        try out.print("  {s} = call {s} {s}(", .{ tmp_name, llvmTypeName(call_ty), callee.expr });
        try emitTypedCallArgs(out, values.items, resolved.params);
        try emitLine(out, ")");
        return decorateCallReturn(.{ .expr = tmp_name, .ty = call_ty, .fallible = resolved.return_fallible }, resolved.return_cap);
    }
    try out.print("  call void {s}(", .{callee.expr});
    try emitTypedCallArgs(out, values.items, resolved.params);
    try emitLine(out, ")");
    return null;
}

fn emitCall(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    def_dict: ?*const flattener.DefDict,
    const_decls: []const common_const_decl.ConstDecl,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    size_bits: u16,
    parsed: call.ParsedCall,
) !?Value {
    if (parsed.is_indirect) {
        return try emitIndirectCall(allocator, out, state, def_dict, const_decls, symbols, sigs, options, parsed);
    }

    switch (try emitBuiltinCall(allocator, out, state, def_dict, symbols, options, size_bits, parsed)) {
        .handled_void => return null,
        .handled_value => |value| return value,
        .not_builtin => {},
    }
    switch (try emitDirectCall(allocator, out, state, def_dict, symbols, sigs, options, parsed)) {
        .not_direct => {},
        .handled_void => return null,
        .handled_value => |value| return value,
    }
    return EmitError.UnknownFunction;
}

fn emitInstruction(
    allocator: std.mem.Allocator,
    out: anytype,
    state: *FunctionState,
    string_literals: *const StringLiteralPool,
    symbols: *const symbol.SymbolTable,
    def_dict: ?*const flattener.DefDict,
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
                try out.print("  br label %{s}\n", .{label_name});
            }
            if (dbg_id) |id| {
                try out.print("  ; label dbg !{d}\n", .{id});
            }
            try out.print("{s}:\n", .{label_name});
            try state.reloadLiveRegs(allocator, out, &.{});
            state.block_open = true;
        },
        .alloc => {
            const dst = base.operands[0].reg;
            const size_value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[1]);
            const size_cast = try castValue(allocator, out, state, size_value, sizePrimType(size_bits));
            const tmp = try state.tempName(allocator);
            try out.print("  {s} = call ptr @malloc({s} {s})", .{ tmp, size_ty_name, size_cast.expr });
            if (dbg_id) |id| {
                try out.print(", !dbg !{d}", .{id});
            }
            try out.writeAll("\n");
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = .ptr });
        },
        .stack_alloc => {
            const dst = base.operands[0].reg;
            const size_value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[1]);
            const size_cast = try castValue(allocator, out, state, size_value, sizePrimType(size_bits));
            const tmp = try state.tempName(allocator);
            try out.print("  {s} = alloca i8, {s} {s}, align 1", .{ tmp, size_ty_name, size_cast.expr });
            if (dbg_id) |id| {
                try out.print(", !dbg !{d}", .{id});
            }
            try out.writeAll("\n");
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
            const srcv = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            if (srcv.fallible) {
                if (base.kind == .take) return EmitError.InvalidOperand;
                // Map byte offsets to LLVM aggregate field indices.
                // {i32, <T>}: field 0 (status) is at byte 0; field 1 (data)
                //   is at byte 4 when T is i32/u32, or byte 8 when T is ptr/i64/u64.
                const component_idx: u32 = switch (off) {
                    0 => 0,
                    4, 8 => 1,
                    else => return EmitError.InvalidOperand,
                };
                const extracted = try state.tempName(allocator);
                try out.print("  {s} = extractvalue ", .{extracted});
                try writeValueType(out, srcv);
                try out.print(" {s}, {d}\n", .{ srcv.expr, component_idx });

                const loaded: Value = .{
                    .expr = extracted,
                    .ty = if (component_idx == 0) .i32 else srcv.ty,
                    .interior_ptr = srcv.interior_ptr,
                    .borrow_view = srcv.borrow_view,
                    .ffi_borrow = srcv.ffi_borrow,
                    .const_ref = srcv.const_ref,
                    .origin = srcv.origin,
                };
                const coerced = try castValue(allocator, out, state, loaded, ty);
                try state.setReg(allocator, out, dst, coerced);
                return;
            }
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const tmp = try state.tempName(allocator);
            try out.print("  {s} = load {s}, ptr {s}, align {d}\n", .{ tmp, llvmTypeName(ty), gep, llvmAlign(ty) });
            var loaded_origin: PointerOrigin = ptrv.origin;
            if (loaded_origin.const_name == null) {
                loaded_origin.const_name = ptrv.const_ref;
            }
            var loaded_interior_ptr = false;
            if (ty == .ptr) {
                if (state.lookupMemoryPtrMeta(ptrv.expr, off)) |meta| {
                    loaded_origin = meta.origin;
                    loaded_interior_ptr = meta.interior_ptr;
                }
                var resolved_origin = resolveLoadOrigin(def_dict, const_decls, sigs, ptrv, off, ty);
                if (loaded_origin.const_name != null) {
                    var const_src = ptrv;
                    const_src.origin.const_name = loaded_origin.const_name;
                    const_src.const_ref = loaded_origin.const_name;
                    resolved_origin = resolveLoadOrigin(def_dict, const_decls, sigs, const_src, off, ty);
                    if (loaded_origin.indirect_sig_index == null and resolved_origin.indirect_sig_index != null) {
                        loaded_origin.indirect_sig_index = resolved_origin.indirect_sig_index;
                    }
                } else if (resolved_origin.const_name != null) {
                    loaded_origin.const_name = resolved_origin.const_name;
                }
                if (loaded_origin.indirect_sig_index == null and resolved_origin.indirect_sig_index != null) {
                    loaded_origin.indirect_sig_index = resolved_origin.indirect_sig_index;
                }
                if (loaded_origin.indirect_sig_index == null) {
                    if (inferIndirectSigIndexFromLoadText(def_dict, const_decls, sigs, base.raw_text)) |sig_index| {
                        loaded_origin.indirect_sig_index = sig_index;
                        if (options.debug) {
                            std.debug.print(
                                "emit load inferred indirect sig {d} from {s}\n",
                                .{ sig_index, base.raw_text },
                            );
                        }
                    }
                }
                if (base.kind == .load) {
                    loaded_interior_ptr = true;
                } else if (ptrv.borrow_view or ptrv.ffi_borrow or ptrv.interior_ptr) {
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
            if (options.debug and ty == .ptr) {
                std.debug.print(
                    "emit load resolved {s}: base={s} const={?s} sig={?d} interior={}\n",
                    .{ base.raw_text, ptrv.expr, loaded_origin.const_name, loaded_origin.indirect_sig_index, loaded_interior_ptr },
                );
            }
            if (ty == .ptr) {
                try state.recordMemoryPtrMeta(tmp, 0, .{
                    .expr = tmp,
                    .ty = .ptr,
                    .interior_ptr = loaded_interior_ptr,
                    .borrow_view = ptrv.borrow_view or loaded_interior_ptr,
                    .ffi_borrow = ptrv.ffi_borrow,
                    .const_ref = loaded_origin.const_name,
                    .origin = loaded_origin,
                });
            }
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
            const srcv = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const tmp = try state.tempName(allocator);
            try out.print("  {s} = load atomic {s}, ptr {s} {s}, align {d}\n", .{ tmp, llvmTypeName(ty), gep, atomicOrderingName(base), llvmAlign(ty) });
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
            const basev = state.getReg(base_reg) orelse try valueFromRegOrConst(allocator, state, symbols, base_reg);
            const ptrv = try castValue(allocator, out, state, basev, .ptr);
            const gep = try state.tempName(allocator);
            try out.print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[2]);
            const coerced = try castValue(allocator, out, state, value, ty);
            try out.print("  store atomic {s} {s}, ptr {s} {s}, align {d}\n", .{ llvmTypeName(ty), coerced.expr, gep, atomicOrderingName(base), llvmAlign(ty) });
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
            const srcv = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const expected_text = base.atomic_expected_text orelse return EmitError.InvalidOperand;
            const new_text = base.atomic_new_text orelse return EmitError.InvalidOperand;
            const expected_value = try valueFromOperand(allocator, state, string_literals, symbols, .{ .text = expected_text });
            const new_value = try valueFromOperand(allocator, state, string_literals, symbols, .{ .text = new_text });
            const expected_coerced = try castValue(allocator, out, state, expected_value, ty);
            const new_coerced = try castValue(allocator, out, state, new_value, ty);
            const pair = try state.tempName(allocator);
            try out.print("  {s} = cmpxchg ptr {s}, {s} {s}, {s} {s} {s} {s}\n", .{ pair, gep, llvmTypeName(ty), expected_coerced.expr, llvmTypeName(ty), new_coerced.expr, atomicOrderingName(base), atomicSecondOrderingName(base) });
            const old_tmp = try state.tempName(allocator);
            try out.print("  {s} = extractvalue ", .{old_tmp});
            try writeCmpxchgResultType(out, ty);
            try out.print(" {s}, 0\n", .{pair});
            const ok_tmp = try state.tempName(allocator);
            try out.print("  {s} = extractvalue ", .{ok_tmp});
            try writeCmpxchgResultType(out, ty);
            try out.print(" {s}, 1\n", .{pair});
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
            const srcv = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const gep = try state.tempName(allocator);
            try out.print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const ty = atomicValueType(base, .i64);
            const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[3]);
            const coerced = try castValue(allocator, out, state, value, ty);
            const tmp = try state.tempName(allocator);
            const op_name = atomic.rmwOpName(base.atomic_rmw_op orelse return EmitError.InvalidOperand);
            try out.print("  {s} = atomicrmw {s} ptr {s}, {s} {s} {s}\n", .{ tmp, op_name, gep, llvmTypeName(ty), coerced.expr, atomicOrderingName(base) });
            try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = ty });
        },
        .fence => {
            try out.print("  fence {s}\n", .{atomicOrderingName(base)});
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
            const basev = state.getReg(base_reg) orelse try valueFromRegOrConst(allocator, state, symbols, base_reg);
            const ptrv = try castValue(allocator, out, state, basev, .ptr);
            const gep = try state.tempName(allocator);
            try out.print("  {s} = getelementptr i8, ptr {s}, i64 {d}\n", .{ gep, ptrv.expr, off });
            const target_ty = if (base.operands[3] == .ty) sig.primTypeFromTag(base.operands[3].ty) orelse .i64 else blk: {
                if (base.operands[2] == .reg) break :blk state.getReg(base.operands[2].reg).?.ty;
                break :blk .i64;
            };
            const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[2]);
            const coerced = try castValue(allocator, out, state, value, target_ty);
            try out.print("  store {s} {s}, ptr {s}, align {d}\n", .{ llvmTypeName(target_ty), coerced.expr, gep, llvmAlign(target_ty) });
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
                const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[1]);
                const target_ty: ?sig.PrimType = if (base.operands[2] == .ty) sig.primTypeFromTag(base.operands[2].ty) else null;
                const tmp = try state.tempName(allocator);
                switch (opcode) {
                    .neg => {
                        if (value.ty == .ptr) return EmitError.UnsupportedType;
                        if (isFloatLike(value.ty)) {
                            try out.print("  {s} = fneg {s} {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        } else {
                            try out.print("  {s} = sub {s} 0, {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        }
                        try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = value.ty });
                    },
                    .not => {
                        if (!isIntLike(value.ty)) return EmitError.UnsupportedType;
                        try out.print("  {s} = xor {s} {s}, -1\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = value.ty });
                    },
                    .fneg => {
                        if (!isFloatLike(value.ty)) return EmitError.UnsupportedType;
                        try out.print("  {s} = fneg {s} {s}\n", .{ tmp, llvmTypeName(value.ty), value.expr });
                        try state.setReg(allocator, out, dst, .{ .expr = tmp, .ty = value.ty });
                    },
                    .bitcast => {
                        const target = target_ty orelse return EmitError.InvalidOperand;
                        const casted = try castValue(allocator, out, state, value, target);
                        if (value.ty == .ptr and casted.ty == .ptr) {
                            var carried = casted;
                            carried.origin = value.origin;
                            carried.const_ref = value.const_ref;
                            carried.borrow_view = value.borrow_view or casted.borrow_view;
                            carried.ffi_borrow = value.ffi_borrow or casted.ffi_borrow;
                            carried.interior_ptr = value.interior_ptr or casted.interior_ptr;
                            try state.setReg(allocator, out, dst, carried);
                            return;
                        }
                        try state.setReg(allocator, out, dst, casted);
                    },
                    .trunc, .zext, .sext, .fptosi, .sitofp, .uitofp, .fptrunc, .fpext => {
                        const target = target_ty orelse return EmitError.InvalidOperand;
                        const casted = try castValue(allocator, out, state, value, target);
                        if (value.ty == .ptr and casted.ty == .ptr) {
                            var carried = casted;
                            carried.origin = value.origin;
                            carried.const_ref = value.const_ref;
                            carried.borrow_view = value.borrow_view or casted.borrow_view;
                            carried.ffi_borrow = value.ffi_borrow or casted.ffi_borrow;
                            carried.interior_ptr = value.interior_ptr or casted.interior_ptr;
                            try state.setReg(allocator, out, dst, carried);
                            return;
                        }
                        try state.setReg(allocator, out, dst, casted);
                    },
                    else => unreachable,
                }
                return;
            }
            const lhs = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[1]);
            const rhs = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[2]);
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
                .add => try out.print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .float) "fadd" else "add", llvmTypeName(target_ty), l.expr, r.expr }),
                .sub => try out.print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .float) "fsub" else "sub", llvmTypeName(target_ty), l.expr, r.expr }),
                .mul => try out.print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .float) "fmul" else "mul", llvmTypeName(target_ty), l.expr, r.expr }),
                .div => try out.print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, switch (kind) {
                    .float => "fdiv",
                    .signed => "sdiv",
                    .unsigned => "udiv",
                }, llvmTypeName(target_ty), l.expr, r.expr }),
                .sdiv => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.print("  {s} = sdiv {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .udiv => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.print("  {s} = udiv {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .rem => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, switch (kind) {
                        .signed => "srem",
                        .unsigned => "urem",
                        else => unreachable,
                    }, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .srem => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.print("  {s} = srem {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .urem => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    try out.print("  {s} = urem {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr });
                },
                .@"and" => try out.print("  {s} = and {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .@"or" => try out.print("  {s} = or {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .xor => try out.print("  {s} = xor {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .shl => try out.print("  {s} = shl {s} {s}, {s}\n", .{ tmp, llvmTypeName(target_ty), l.expr, r.expr }),
                .shr => try out.print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (kind == .signed) "ashr" else "lshr", llvmTypeName(target_ty), l.expr, r.expr }),
                .gt, .lt, .eq, .ne => {
                    const cmp = legacyCompareMnemonic(opcode, kind);
                    const cmp_inst = if (kind == .float) "fcmp" else "icmp";
                    try out.print("  {s} = {s} {s} {s} {s}, {s}\n", .{ tmp, cmp_inst, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => {
                    if (!isFloatLike(lhs.ty) or !isFloatLike(rhs.ty)) return EmitError.UnsupportedType;
                    const cmp = floatCompareMnemonic(opcode);
                    try out.print("  {s} = fcmp {s} {s} {s}, {s}\n", .{ tmp, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                .sgt, .slt, .sge, .sle => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    const cmp = signedCompareMnemonic(opcode);
                    try out.print("  {s} = icmp {s} {s} {s}, {s}\n", .{ tmp, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(allocator, out, dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
                .ugt, .ult, .uge, .ule => {
                    if (base_kind == .float) return EmitError.UnsupportedType;
                    const cmp = unsignedCompareMnemonic(opcode);
                    try out.print("  {s} = icmp {s} {s} {s}, {s}\n", .{ tmp, cmp, llvmTypeName(target_ty), l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
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
            const srcv = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            const ptrv = try castValue(allocator, out, state, srcv, .ptr);
            const offset = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[2]);
            const off = try castValue(allocator, out, state, offset, .i64);
            const result = try emitPointerArithmetic(allocator, out, state, .add, ptrv, off);
            try state.setReg(allocator, out, dst, result);
        },
        .raw_cast => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            const raw = try castValue(allocator, out, state, value, .i64);
            var carried = raw;
            carried.origin = value.origin;
            carried.const_ref = value.const_ref;
            carried.borrow_view = value.borrow_view;
            carried.ffi_borrow = value.ffi_borrow;
            carried.interior_ptr = value.interior_ptr;
            try state.setReg(allocator, out, dst, carried);
            return;
        },
        .assume_safe, .assume_borrow => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            var carried = ptrv;
            carried.origin = value.origin;
            carried.const_ref = value.const_ref;
            carried.borrow_view = value.borrow_view or (base.kind == .assume_borrow);
            carried.ffi_borrow = value.ffi_borrow;
            carried.interior_ptr = value.interior_ptr or ptrv.interior_ptr;
            try state.setReg(allocator, out, dst, carried);
        },
        .assign => {
            const dst = base.operands[0].reg;
            const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[1]);
            if (value.ty == .ptr and value.origin.indirect_sig_index != null) {
                try state.recordMemoryPtrMeta(value.expr, 0, value);
            }
            try state.setReg(allocator, out, dst, value);
        },
        .move_ => {
            if (base.operands[0] != .reg) return EmitError.InvalidOperand;
            // Ownership-only instruction: verifier/interpreter enforce the consume.
        },
        .release => {
            const reg_id = base.operands[0].reg;
            const value = state.getReg(reg_id) orelse try valueFromRegOrConst(allocator, state, symbols, reg_id);
            if (value.fallible) {
                return;
            }
            if (value.borrow_view or value.ffi_borrow) {
                return;
            }
            if (value.ty != .ptr or value.interior_ptr or value.const_ref != null or value.origin.const_name != null) {
                return;
            }
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            try out.print("  call void @free(ptr {s})\n", .{ptrv.expr});
        },
        .jmp => {
            const label_name = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            try out.print("  br label %{s}\n", .{label_name});
            state.block_open = false;
        },
        .br => {
            const cond = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[0]);
            const condv = try castValue(allocator, out, state, cond, .i64);
            const tmp = try state.tempName(allocator);
            try out.print("  {s} = icmp ne i64 {s}, 0\n", .{ tmp, condv.expr });
            const tname = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            const fname = symbols.lookupName(base.operands[3].label) orelse return EmitError.InvalidOperand;
            try out.print("  br i1 {s}, label %{s}, label %{s}\n", .{ tmp, tname, fname });
            state.block_open = false;
        },
        .br_null => {
            const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[0]);
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            const tmp = try state.tempName(allocator);
            try out.print("  {s} = icmp eq ptr {s}, null\n", .{ tmp, ptrv.expr });
            const nname = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            const nnname = symbols.lookupName(base.operands[3].label) orelse return EmitError.InvalidOperand;
            try out.print("  br i1 {s}, label %{s}, label %{s}\n", .{ tmp, nname, nnname });
            state.block_open = false;
        },
        .call, .call_indirect, .panic, .panic_msg => {
            const call_text = try instructionCallText(allocator, symbols, def_dict, base);
            defer allocator.free(call_text);
            var parsed = call.parseCall(allocator, call_text) catch return EmitError.InvalidOperand;
            defer parsed.deinit(allocator);
            if (try emitCall(allocator, out, state, def_dict, const_decls, symbols, sigs, options, size_bits, parsed)) |ret| {
                if (parsed.dest) |dest| {
                    if (symbols.findId(dest)) |id| {
                        if (state.sig.slotOf(id)) |slot| {
                            try state.setReg(allocator, out, slot, ret);
                        }
                    }
                }
            }
            state.block_open = base.kind != .panic and base.kind != .panic_msg;
        },
        .try_, .early_return => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse try valueFromRegOrConst(allocator, state, symbols, src);
            if (!value.fallible) return EmitError.InvalidOperand;
            if (!state.sig.return_fallible) return EmitError.InvalidOperand;

            const branch_id = state.temp_index;
            state.temp_index += 1;
            const status_tmp = try state.tempName(allocator);
            const ok_tmp = try state.tempName(allocator);
            const cont_label = try state.ownFmt(allocator, "try_ok_{d}", .{branch_id});
            const early_label = try state.ownFmt(allocator, "try_early_{d}", .{branch_id});

            try out.print("  {s} = extractvalue ", .{status_tmp});
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
            try out.print(" {s}, 0\n", .{value.expr});
            try out.print("  {s} = icmp eq i32 {s}, 0\n", .{ ok_tmp, status_tmp });
            try out.print("  br i1 {s}, label %{s}, label %{s}\n", .{ ok_tmp, cont_label, early_label });
            try out.print("{s}:\n", .{early_label});
            try out.writeAll("  ret ");
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
            try out.print(" {s}\n", .{value.expr});
            try out.print("{s}:\n", .{cont_label});

            const payload_tmp = try state.tempName(allocator);
            try out.print("  {s} = extractvalue ", .{payload_tmp});
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
            try out.print(" {s}, 1\n", .{value.expr});
            try state.setReg(allocator, out, dst, .{ .expr = payload_tmp, .ty = value.ty });
            state.block_open = true;
        },
        .return_ => {
            const ret_ty = returnTypeForSig(state.sig.return_cap, state.sig.return_ty);
            if (state.sig.return_fallible) {
                if (ret_ty == .void) return EmitError.UnsupportedType;
                if (base.operands[0] == .none) return EmitError.InvalidOperand;
                const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[0]);
                if (value.fallible) {
                    try out.writeAll("  ret ");
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
                    try out.print(" {s}\n", .{value.expr});
                    state.block_open = false;
                    return;
                }
                const coerced = try castValue(allocator, out, state, value, ret_ty);
                const zero_agg = try state.tempName(allocator);
                try out.print("  {s} = insertvalue ", .{zero_agg});
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
                try out.writeAll(" poison, i32 0, 0\n");
                const packed_value = try state.tempName(allocator);
                try out.print("  {s} = insertvalue ", .{packed_value});
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
                try out.print(" {s}, {s} {s}, 1\n", .{ zero_agg, llvmTypeName(ret_ty), coerced.expr });
                try out.writeAll("  ret ");
            try writeReturnAbiType(out, state.sig.return_cap, state.sig.return_ty, true);
                try out.print(" {s}\n", .{packed_value});
                state.block_open = false;
                return;
            }

            if (base.operands[0] == .none or ret_ty == .void) {
                try emitIndented(out, "ret void");
                state.block_open = false;
                return;
            }
            const value = try valueFromOperand(allocator, state, string_literals, symbols, base.operands[0]);
            const coerced = try castValue(allocator, out, state, value, ret_ty);
            try out.print("  ret {s} {s}\n", .{ llvmTypeName(ret_ty), coerced.expr });
            state.block_open = false;
        },
        .native => {
            try out.print("  {s}\n", .{base.operands[0].native_text});
        },
        else => return EmitError.UnsupportedInstruction,
    }
}

fn instructionCallText(
    allocator: std.mem.Allocator,
    symbols: *const symbol.SymbolTable,
    def_dict: ?*const flattener.DefDict,
    base: inst.Instruction,
) ![]u8 {
    _ = symbols;
    _ = def_dict;
    return try allocator.dupe(u8, base.raw_text);
}

fn emitUserFunctions(
    allocator: std.mem.Allocator,
    out: anytype,
    verified: anytype,
    def_dict: ?*const flattener.DefDict,
    string_literals: *const StringLiteralPool,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    options: EmitOptions,
    size_bits: u16,
) !void {
    if (options.debug and loc_table.len != verified.annotated.len) return EmitError.InvalidOperand;

    try string_literals.emit(out);
    if (string_literals.entries.items.len != 0) try emitLine(out, "");
    try emitConstDecls(out, verified.const_decls, verified.function_sigs);

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
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl => {
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
                    try out.writeAll("declare ");
                    try writeReturnAbiType(out, fsig.return_cap, fsig.return_ty, fsig.return_fallible);
                    try out.print(" @{s}(", .{fsig.name});
                    for (fsig.params, 0..) |param, pidx| {
                        if (pidx != 0) try out.writeAll(", ");
                        const ty = valueTypeForPrefix(param.cap, param.ty);
                        try out.print("{s}", .{llvmTypeName(ty)});
                    }
                    try emitLine(out, ")");
                    try emitLine(out, "");
                    current_debug = null;
                    continue;
                }

                current = try FunctionState.init(allocator, fsig, fsig.reg_ids.len, string_literals);
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
                    const reg_slot = fsig.slotOf(reg_id) orelse @as(u32, @intCast(pidx));
                    const value = Value{
                        .expr = try current.?.ownFmt(allocator, "%{s}", .{param.name}),
                        .ty = valueTypeForPrefix(param.cap, param.ty),
                        .borrow_view = param.cap == .borrow,
                        .ffi_borrow = param.cap == .raw,
                    };
                    try current.?.setReg(allocator, out, reg_slot, value);
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
            try emitInstruction(allocator, out, state, string_literals, &verified.symbols, def_dict, verified.function_sigs, verified.const_decls, options, size_bits, inst_dbg_id, item);
        }
    }

    if (current) |*state| {
        try emitFunctionFooter(out);
        state.deinit(allocator);
        current = null;
    }

    if (options.test_mode) {
        try emitTestHarnessMain(allocator, out, verified.function_sigs, size_bits);
    } else if (shouldEmitMainWrapper(options)) {
        // Emit the native entry wrapper if the program defines a zero-arg `main`.
        for (verified.function_sigs) |fsig| {
            if (fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0) {
                const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
                const wrapper_dbg = main_wrapper_dbg;
                try out.print("define i32 @main(i32 %argc, ptr %argv) {{\n", .{});
                try emitLine(out, "entry:");
                if (wrapper_dbg) |dbg_id| {
                    try out.print("  store i32 %argc, ptr @saasm_argc, align 4, !dbg !{d}\n", .{dbg_id});
                    try out.print("  store ptr %argv, ptr @saasm_argv, align 8, !dbg !{d}\n", .{dbg_id});
                } else {
                    try emitLine(out, "  store i32 %argc, ptr @saasm_argc, align 4");
                    try emitLine(out, "  store ptr %argv, ptr @saasm_argv, align 8");
                }

                if (fsig.return_fallible) {
                    if (wrapper_dbg) |dbg_id| {
                        try out.writeAll("  %res = call ");
                        try writeReturnAbiType(out, fsig.return_cap, fsig.return_ty, true);
                        try out.print(" @{s}(), !dbg !{d}\n", .{ emittedFunctionName(fsig), dbg_id });
                        try out.writeAll("  %status = extractvalue ");
                        try writeReturnAbiType(out, fsig.return_cap, fsig.return_ty, true);
                        try out.print(" %res, 0, !dbg !{d}\n", .{dbg_id});
                        try out.print("  ret i32 %status, !dbg !{d}\n", .{dbg_id});
                    } else {
                        try out.writeAll("  %res = call ");
                        try writeReturnAbiType(out, fsig.return_cap, fsig.return_ty, true);
                        try out.print(" @{s}()\n", .{emittedFunctionName(fsig)});
                        try out.writeAll("  %status = extractvalue ");
                        try writeReturnAbiType(out, fsig.return_cap, fsig.return_ty, true);
                        try out.writeAll(" %res, 0\n");
                        try emitLine(out, "  ret i32 %status");
                    }
                } else if (ret_ty == .void) {
                    if (wrapper_dbg) |dbg_id| {
                        try out.print("  call void @{s}(), !dbg !{d}\n", .{ emittedFunctionName(fsig), dbg_id });
                        try out.print("  ret i32 0, !dbg !{d}\n", .{dbg_id});
                    } else {
                        try out.print("  call void @{s}()\n", .{emittedFunctionName(fsig)});
                        try emitLine(out, "  ret i32 0");
                    }
                } else if (ret_ty == .i32 or ret_ty == .u32) {
                    if (wrapper_dbg) |dbg_id| {
                        try out.print("  %res = call {s} @{s}(), !dbg !{d}\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig), dbg_id });
                        try out.print("  ret i32 %res, !dbg !{d}\n", .{dbg_id});
                    } else {
                        try out.print("  %res = call {s} @{s}()\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig) });
                        try out.print("  ret i32 %res\n", .{});
                    }
                } else {
                    if (wrapper_dbg) |dbg_id| {
                        try out.print("  call {s} @{s}(), !dbg !{d}\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig), dbg_id });
                        try out.print("  ret i32 0, !dbg !{d}\n", .{dbg_id});
                    } else {
                        try out.print("  call {s} @{s}()\n", .{ llvmTypeName(ret_ty), emittedFunctionName(fsig) });
                        try emitLine(out, "  ret i32 0");
                    }
                }
                try emitLine(out, "}");
                try emitLine(out, "");
                break;
            }
        }
    }

    if (debug_info) |*info| {
        try info.emit(out);
    }
}

pub fn emitLlvmToWriter(
    writer: anytype,
    allocator: std.mem.Allocator,
    verified: anytype,
    def_dict: ?*const flattener.DefDict,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    size_bits: u16,
    options: EmitOptions,
) !void {
    var sink = TextSink(@TypeOf(writer)){ .inner = writer };

    var string_literals = StringLiteralPool.init(allocator);
    defer string_literals.deinit();
    try collectStringLiterals(allocator, &string_literals, verified.annotated);

    try emitHelpers(&sink, size_bits, options);
    try emitUserFunctions(allocator, &sink, verified, def_dict, &string_literals, loc_table, source_path, options, size_bits);
}

pub fn emitLlvm(
    allocator: std.mem.Allocator,
    verified: anytype,
    def_dict: ?*const flattener.DefDict,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    size_bits: u16,
    options: EmitOptions,
) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try emitLlvmToWriter(out.writer(), allocator, verified, def_dict, loc_table, source_path, size_bits, options);

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
            break :blk try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "emit_test.sa", @as(u16, @bitSizeOf(usize)), .{});
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
    const text = try emitLlvm(std.testing.allocator, ok, null, empty_loc, "test.sa", @as(u16, @bitSizeOf(usize)), .{});
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "define internal void @sys_print"));
}

test "llvm emitter produces identical text with serial and parallel jobs" {
    const source =
        \\@helper(value: i32) -> i32:
        \\return value
        \\
        \\@main() -> i32:
        \\value = call @helper(7)
        \\return value
    ;

    var flat = try flattener.flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try referee.verifyWithOptions(std.testing.allocator, flat.instructions, flat.const_decls, .{ .jobs = 1 });
    switch (verified) {
        .trap => return error.TestUnexpectedResult,
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);

            const serial = try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "parallel_emit.sa", @as(u16, @bitSizeOf(usize)), .{ .jobs = 1 });
            defer std.testing.allocator.free(serial);
            const parallel = try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "parallel_emit.sa", @as(u16, @bitSizeOf(usize)), .{ .jobs = 2 });
            defer std.testing.allocator.free(parallel);

            try std.testing.expectEqualStrings(serial, parallel);
            try std.testing.expect(std.mem.containsAtLeast(u8, serial, 1, "define i32 @main(i32 %argc, ptr %argv)"));
            try std.testing.expect(std.mem.containsAtLeast(u8, serial, 1, "define i32 @saasm_main()"));
        },
    }
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

            const text = try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "native.sa", @as(u16, @bitSizeOf(usize)), .{});
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

                const text = try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "native_pbt.sa", @as(u16, @bitSizeOf(usize)), .{});
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

test "llvm emitter treats move as ownership-only no-op" {
    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\^value
        \\return 0
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @saasm_main()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call ptr @malloc("));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "trunc i64 0 to i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "ret i32 %"));
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

            const text = try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "take.sa", @as(u16, @bitSizeOf(usize)), .{});
            defer std.testing.allocator.free(text);
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "getelementptr i8, ptr"));
            try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "load ptr, ptr"));
        },
    }
}

test "llvm emitter extracts fallible result status and payload" {
    const source =
        \\@helper() -> i32!:
        \\return 7
        \\
        \\@main() -> i32:
        \\res = call @helper()
        \\status = load res+0 as u32
        \\ok = eq status, 0
        \\br ok -> L_OK, L_ERR
        \\L_ERR:
        \\!res
        \\return 0
        \\L_OK:
        \\!res
        \\return 7
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @saasm_main()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call {i32, i32} @helper()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "extractvalue {i32, i32}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "icmp eq i64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "br i1 "));
}

test "llvm emitter treats fallible ptr release as consume only" {
    const source =
        \\@helper() -> ptr!:
        \\node = alloc 8
        \\return node
        \\
        \\@main() -> i32:
        \\res = call @helper()
        \\status = load res+0 as u32
        \\value = load res+4 as ptr
        \\!res
        \\!value
        \\return status
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @saasm_main()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call {i32, ptr} @helper()"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "extractvalue {i32, ptr}"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call void @free(ptr "));
    try std.testing.expect(std.mem.count(u8, body, "call void @free(ptr ") == 1);
}

test "llvm emitter accepts raw const pointer arguments" {
    const source =
        \\@const HELLO = utf8:"hello"
        \\
        \\@main() -> i32:
        \\call @sys_print(*HELLO, 5)
        \\return 0
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @saasm_main()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call void @sys_print(ptr @HELLO, i64 5)"));
}

test "llvm emitter accepts quoted string literal arguments" {
    const source =
        \\@main() -> i32:
        \\call @sys_print(*"7", 1)
        \\return 0
    ;
    const text = try emitTestSource(source);
    defer std.testing.allocator.free(text);

    const body = try functionBody(text, "define i32 @saasm_main()");
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "@.sa_str_0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, body, 1, "call void @sys_print(ptr @.sa_str_0, i64 1)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, text, 1, "@.sa_str_0 = private unnamed_addr constant [2 x i8] c\"\\37\\00\""));
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

            const text = try emitLlvm(std.testing.allocator, owned, &flat.def_dict, flat.loc_table, "exports.sa", @as(u16, @bitSizeOf(usize)), .{});
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

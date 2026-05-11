const std = @import("std");

const call = @import("referee/call.zig");
const referee = @import("referee.zig");
const cap = @import("common/capability.zig");
const inst = @import("common/instruction.zig");
const sig = @import("common/signature.zig");
const upstream = @import("common/upstream_loc.zig");
const symbol = @import("flattener/symbol.zig");

pub const EmitError = error{
    OutOfMemory,
    InvalidOperand,
    UnsupportedInstruction,
    UnsupportedType,
    UnknownFunction,
};

pub const EmitOptions = struct {
    debug: bool = false,
    emit_wasm: bool = false,
};

const Value = struct {
    expr: []const u8,
    ty: sig.PrimType,
};

const FunctionState = struct {
    sig: sig.FunctionSig,
    emitted_name: []const u8,
    regs: std.AutoHashMap(u32, Value),
    owned: std.ArrayList([]const u8),
    temp_index: usize = 0,

    fn init(allocator: std.mem.Allocator, sig_: sig.FunctionSig) FunctionState {
        return .{
            .sig = sig_,
            .emitted_name = emittedFunctionName(sig_),
            .regs = std.AutoHashMap(u32, Value).init(allocator),
            .owned = std.ArrayList([]const u8).init(allocator),
        };
    }

    fn deinit(self: *FunctionState, allocator: std.mem.Allocator) void {
        self.regs.deinit();
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

    fn setReg(self: *FunctionState, id: u32, value: Value) !void {
        if (self.regs.getPtr(id)) |slot| {
            slot.* = value;
            return;
        }
        try self.regs.put(id, value);
    }

    fn getReg(self: *FunctionState, id: u32) ?Value {
        return self.regs.get(id);
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
        .i8, .i16, .i32, .i64, .u8, .u16, .u32, .u64 => true,
        else => false,
    };
}

fn isFloatLike(ty: sig.PrimType) bool {
    return ty == .f32 or ty == .f64;
}

fn llvmTypeName(ty: sig.PrimType) []const u8 {
    return switch (ty) {
        .void => "void",
        .i8, .u8 => "i8",
        .i16, .u16 => "i16",
        .i32, .u32 => "i32",
        .i64, .u64 => "i64",
        .f32 => "float",
        .f64 => "double",
        .ptr => "ptr",
    };
}

fn llvmAlign(ty: sig.PrimType) u32 {
    return switch (ty) {
        .void => 1,
        .i8, .u8 => 1,
        .i16, .u16 => 2,
        .i32, .u32, .f32 => 4,
        .i64, .u64, .f64, .ptr => 8,
    };
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
    _ = symbols;
    return switch (op) {
        .reg => |id| state.getReg(id) orelse EmitError.InvalidOperand,
        .text => |t| try parseImmediateValue(allocator, state, t),
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
    if (value.ty == target) return value;

    if (target == .ptr) {
        if (value.ty == .ptr) return value;
        if (!isIntLike(value.ty)) return EmitError.UnsupportedType;
        const tmp = try state.tempName(allocator);
        try out.writer().print("  {s} = inttoptr {s} {s} to ptr\n", .{ tmp, llvmTypeName(value.ty), value.expr });
        return .{ .expr = tmp, .ty = .ptr };
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

fn emitHelpers(out: *std.ArrayList(u8), size_bits: u16) !void {
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
    try emitLine(out, "declare void @__sa_panic(i32, ptr, i64)");
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

fn emitFunctionHeader(out: *std.ArrayList(u8), state: *FunctionState) !void {
    const ret_ty = returnTypeForSig(state.sig.return_cap, state.sig.return_ty);
    try out.writer().print("define {s} @{s}(", .{ llvmTypeName(ret_ty), state.emitted_name });
    for (state.sig.params, 0..) |param, idx| {
        if (idx != 0) try out.appendSlice(", ");
        const ty = valueTypeForPrefix(param.cap, param.ty);
        try out.writer().print("{s} %{s}", .{ llvmTypeName(ty), param.name });
    }
    try emitLine(out, ") {");
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
        var value: Value = undefined;
        if (arg.text.len != 0 and (std.ascii.isAlphabetic(arg.text[0]) or arg.text[0] == '_')) {
            if (symbols.findId(arg.text)) |id| {
                value = state.getReg(id) orelse return EmitError.InvalidOperand;
            } else {
                value = try parseImmediateValue(allocator, state, arg.text);
            }
        } else {
            value = try parseImmediateValue(allocator, state, arg.text);
        }
        const coerced = try castValue(allocator, prelude, state, value, expected);
        try stmt.writer().print("{s} {s}", .{ llvmTypeName(expected), coerced.expr });
    }
}

fn emitBuiltinCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    options: EmitOptions,
    parsed: call.ParsedCall,
) !?Value {
    const name = parsed.callee;
    if (std.mem.eql(u8, name, "panic")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "code", .ty = .i32, .cap = .by_value }});
        try out.appendSlice(prelude.items);
        if (options.emit_wasm) {
            try out.writer().print("  unreachable ; panic({s})\n", .{args_buf.items});
        } else {
            try out.writer().print("  call void @__sa_panic(i32 {s}, ptr null, i64 0)\n", .{args_buf.items});
            try emitLine(out, "  unreachable");
        }
        return null;
    }
    if (std.mem.eql(u8, name, "panic_msg")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{
            .{ .name = "code", .ty = .i32, .cap = .by_value },
            .{ .name = "msg", .ty = .ptr, .cap = .raw },
            .{ .name = "len", .ty = .i64, .cap = .by_value },
        });
        try out.appendSlice(prelude.items);
        if (options.emit_wasm) {
            try out.writer().print("  unreachable ; panic_msg({s})\n", .{args_buf.items});
        } else {
            try out.writer().print("  call void @__sa_panic(i32 {s})\n", .{args_buf.items});
            try emitLine(out, "  unreachable");
        }
        return null;
    }
    if (std.mem.eql(u8, name, "sys_argc")) {
        const tmp = try state.tempName(allocator);
        try out.writer().print("  {s} = call i32 @sys_argc()\n", .{tmp});
        return .{ .expr = tmp, .ty = .i32 };
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
        return .{ .expr = tmp, .ty = .ptr };
    }
    if (std.mem.eql(u8, name, "sys_print")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "msg", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }});
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @sys_print({s})\n", .{args_buf.items});
        return null;
    }
    if (std.mem.eql(u8, name, "sys_exit")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "code", .ty = .i32, .cap = .by_value }});
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @sys_exit({s})\n", .{args_buf.items});
        return null;
    }
    if (std.mem.eql(u8, name, "sys_read_file")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "out_len", .ty = .ptr, .cap = .raw }});
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call ptr @sys_read_file({s})\n", .{ tmp, args_buf.items });
        return .{ .expr = tmp, .ty = .ptr };
    }
    if (std.mem.eql(u8, name, "sys_write_file")) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, &.{.{ .name = "path", .ty = .ptr, .cap = .raw }, .{ .name = "len", .ty = .i64, .cap = .by_value }, .{ .name = "data", .ty = .ptr, .cap = .raw }, .{ .name = "dlen", .ty = .i64, .cap = .by_value }});
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call i32 @sys_write_file({s})\n", .{ tmp, args_buf.items });
        return .{ .expr = tmp, .ty = .i32 };
    }
    return null;
}

fn emitDirectCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    parsed: call.ParsedCall,
) !?Value {
    _ = options;
    const resolved = findFunctionSig(sigs, parsed.callee) orelse return null;
    const ret_ty = returnTypeForSig(resolved.return_cap, resolved.return_ty);
    if (parsed.args.len != resolved.params.len) return EmitError.InvalidOperand;

    if (ret_ty != .void) {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, resolved.params);
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call {s} @{s}({s})\n", .{ tmp, llvmTypeName(ret_ty), emittedFunctionName(resolved), args_buf.items });
        return .{ .expr = tmp, .ty = ret_ty };
    } else {
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        try emitArgList(allocator, &prelude, &args_buf, state, symbols, parsed.args, resolved.params);
        try out.appendSlice(prelude.items);
        try out.writer().print("  call void @{s}({s})\n", .{ emittedFunctionName(resolved), args_buf.items });
        return null;
    }
}

fn emitCall(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    parsed: call.ParsedCall,
) !?Value {
    if (parsed.is_indirect) {
        const callee_id = symbols.findId(parsed.callee) orelse return EmitError.UnknownFunction;
        const callee = state.getReg(callee_id) orelse return EmitError.InvalidOperand;
        var prelude = std.ArrayList(u8).init(allocator);
        defer prelude.deinit();
        var args_buf = std.ArrayList(u8).init(allocator);
        defer args_buf.deinit();
        const tmp = try state.tempName(allocator);
        if (parsed.args.len != 0) {
            for (parsed.args, 0..) |arg, idx| {
                if (idx != 0) try args_buf.appendSlice(", ");
                const value = if (symbols.findId(arg.text)) |id| state.getReg(id) orelse return EmitError.InvalidOperand else try parseImmediateValue(allocator, state, arg.text);
                const coerced = try castValue(allocator, &prelude, state, value, .i64);
                try args_buf.writer().print("i64 {s}", .{coerced.expr});
            }
        }
        try out.appendSlice(prelude.items);
        try out.writer().print("  {s} = call i64 {s}({s})\n", .{ tmp, callee.expr, args_buf.items });
        return .{ .expr = tmp, .ty = .i64 };
    }

    if (try emitBuiltinCall(allocator, out, state, symbols, options, parsed)) |value| {
        return value;
    }
    if (try emitDirectCall(allocator, out, state, symbols, sigs, options, parsed)) |value| {
        return value;
    }
    return EmitError.UnknownFunction;
}

fn emitInstruction(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    state: *FunctionState,
    symbols: *const symbol.SymbolTable,
    sigs: []const sig.FunctionSig,
    options: EmitOptions,
    size_bits: u16,
    item: referee.AnnotatedInstruction,
) !void {
    const size_ty_name = sizeTypeName(size_bits);
    const base = item.base;
    switch (base.kind) {
        .label => {
            const label_id = base.operands[1].label;
            const label_name = symbols.lookupName(label_id) orelse return EmitError.InvalidOperand;
            try out.writer().print("{s}:\n", .{label_name});
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
            try out.writer().print("  {s} = call ptr @malloc({s} {d})\n", .{ tmp, size_ty_name, size });
            try state.setReg(dst, .{ .expr = tmp, .ty = .ptr });
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
            try state.setReg(dst, .{ .expr = tmp, .ty = ty });
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
        },
        .op => {
            const dst = base.operands[0].reg;
            const opcode = base.operands[1].op_code;
            const lhs = try valueFromOperand(allocator, state, symbols, base.operands[2]);
            const rhs = try valueFromOperand(allocator, state, symbols, base.operands[3]);
            const target_ty: sig.PrimType = if (isFloatLike(lhs.ty) or isFloatLike(rhs.ty)) .f64 else .i64;
            const l = try castValue(allocator, out, state, lhs, target_ty);
            const r = try castValue(allocator, out, state, rhs, target_ty);
            const tmp = try state.tempName(allocator);
            switch (opcode) {
                .add => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (target_ty == .f64) "fadd" else "add", llvmTypeName(target_ty), l.expr, r.expr }),
                .sub => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (target_ty == .f64) "fsub" else "sub", llvmTypeName(target_ty), l.expr, r.expr }),
                .mul => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (target_ty == .f64) "fmul" else "mul", llvmTypeName(target_ty), l.expr, r.expr }),
                .div => try out.writer().print("  {s} = {s} {s} {s}, {s}\n", .{ tmp, if (target_ty == .f64) "fdiv" else "sdiv", llvmTypeName(target_ty), l.expr, r.expr }),
                .@"and" => try out.writer().print("  {s} = and i64 {s}, {s}\n", .{ tmp, l.expr, r.expr }),
                .@"or" => try out.writer().print("  {s} = or i64 {s}, {s}\n", .{ tmp, l.expr, r.expr }),
                .shl => try out.writer().print("  {s} = shl i64 {s}, {s}\n", .{ tmp, l.expr, r.expr }),
                .shr => try out.writer().print("  {s} = ashr i64 {s}, {s}\n", .{ tmp, l.expr, r.expr }),
                .gt, .lt, .eq, .ne => {
                    const cmp = switch (opcode) {
                        .gt => if (target_ty == .f64) "ogt" else "sgt",
                        .lt => if (target_ty == .f64) "olt" else "slt",
                        .eq => if (target_ty == .f64) "oeq" else "eq",
                        .ne => if (target_ty == .f64) "one" else "ne",
                        else => unreachable,
                    };
                    try out.writer().print("  {s} = fcmp {s} double {s}, {s}\n", .{ tmp, cmp, l.expr, r.expr });
                    const zext = try state.tempName(allocator);
                    try out.writer().print("  {s} = zext i1 {s} to i64\n", .{ zext, tmp });
                    try state.setReg(dst, .{ .expr = zext, .ty = .i64 });
                    return;
                },
            }
            try state.setReg(dst, .{ .expr = tmp, .ty = target_ty });
        },
        .raw_cast => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse return EmitError.InvalidOperand;
            const raw = try castValue(allocator, out, state, value, .i64);
            try state.setReg(dst, raw);
        },
        .assume_safe, .assume_borrow => {
            const dst = base.operands[0].reg;
            const src = base.operands[1].reg;
            const value = state.getReg(src) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            try state.setReg(dst, ptrv);
        },
        .move_ => {},
        .release => {
            const reg_id = base.operands[0].reg;
            const mask = item.entry_caps[@intCast(reg_id)];
            if ((mask & @intFromEnum(cap.CapabilityMask.borrow_view)) != 0 or (mask & @intFromEnum(cap.CapabilityMask.ffi_borrow)) != 0) {
                return;
            }
            const value = state.getReg(reg_id) orelse return EmitError.InvalidOperand;
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            try out.writer().print("  call void @free(ptr {s})\n", .{ptrv.expr});
        },
        .jmp => {
            const label_name = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            try out.writer().print("  br label %{s}\n", .{label_name});
        },
        .br => {
            const cond = try valueFromOperand(allocator, state, symbols, base.operands[0]);
            const condv = try castValue(allocator, out, state, cond, .i64);
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = icmp ne i64 {s}, 0\n", .{ tmp, condv.expr });
            const tname = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            const fname = symbols.lookupName(base.operands[2].label) orelse return EmitError.InvalidOperand;
            try out.writer().print("  br i1 {s}, label %{s}, label %{s}\n", .{ tmp, tname, fname });
        },
        .br_null => {
            const value = try valueFromOperand(allocator, state, symbols, base.operands[0]);
            const ptrv = try castValue(allocator, out, state, value, .ptr);
            const tmp = try state.tempName(allocator);
            try out.writer().print("  {s} = icmp eq ptr {s}, null\n", .{ tmp, ptrv.expr });
            const nname = symbols.lookupName(base.operands[1].label) orelse return EmitError.InvalidOperand;
            const nnname = symbols.lookupName(base.operands[2].label) orelse return EmitError.InvalidOperand;
            try out.writer().print("  br i1 {s}, label %{s}, label %{s}\n", .{ tmp, nname, nnname });
        },
        .call, .call_indirect, .panic, .panic_msg => {
            var parsed = call.parseCall(allocator, base.raw_text) catch return EmitError.InvalidOperand;
            defer parsed.deinit(allocator);
            if (try emitCall(allocator, out, state, symbols, sigs, options, parsed)) |ret| {
                if (parsed.dest) |dest| {
                    if (symbols.findId(dest)) |id| try state.setReg(id, ret);
                }
            }
        },
        .return_ => {
            const ret_ty = returnTypeForSig(state.sig.return_cap, state.sig.return_ty);
            if (base.operands[0] == .none or ret_ty == .void) {
                try emitIndented(out, "ret void");
                return;
            }
            const value = try valueFromOperand(allocator, state, symbols, base.operands[0]);
            const coerced = try castValue(allocator, out, state, value, ret_ty);
            try out.writer().print("  ret {s} {s}\n", .{ llvmTypeName(ret_ty), coerced.expr });
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
    verified: referee.VerifyOk,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    options: EmitOptions,
    size_bits: u16,
) !void {
    if (options.debug and loc_table.len != verified.annotated.len) return EmitError.InvalidOperand;

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
                    const ret_ty = returnTypeForSig(fsig.return_cap, fsig.return_ty);
                    try out.writer().print("declare {s} @{s}(", .{ llvmTypeName(ret_ty), fsig.name });
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

                current = FunctionState.init(allocator, fsig);
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
                try emitFunctionHeader(out, &current.?);
                for (fsig.params, 0..) |param, pidx| {
                    const reg_id = fsig.param_ids[pidx];
                    const value = Value{
                        .expr = try current.?.ownFmt(allocator, "%{s}", .{param.name}),
                        .ty = valueTypeForPrefix(param.cap, param.ty),
                    };
                    try current.?.setReg(reg_id, value);
                }
                continue;
            },
            else => {},
        }

        if (current) |*state| {
            try emitInstruction(allocator, out, state, &verified.symbols, verified.function_sigs, options, size_bits, item);
            if (debug_info) |*info| {
                if (current_debug) |ctx| {
                    if (loc_table[idx]) |loc| {
                        _ = try info.ensureLocation(ctx, loc.file, loc.line, loc.col);
                    }
                }
            }
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
            if (ret_ty == .void) {
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
    verified: referee.VerifyOk,
    loc_table: upstream.LocTable,
    source_path: []const u8,
    size_bits: u16,
    options: EmitOptions,
) ![]const u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    try emitHelpers(&out, size_bits);
    try emitUserFunctions(allocator, &out, verified, loc_table, source_path, options, size_bits);

    return try out.toOwnedSlice();
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

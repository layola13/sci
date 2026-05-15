const std = @import("std");

const def_dict = @import("flattener/def_dict.zig");
const classifier = @import("flattener/line_classifier.zig");
const forbidden = @import("flattener/forbidden.zig");
const symbol = @import("flattener/symbol.zig");
const common_instruction = @import("common/instruction.zig");
const common_const_decl = @import("common/const_decl.zig");
const atomic = @import("common/atomic.zig");
const common_signature = @import("common/signature.zig");
const common_trap = @import("common/trap.zig");
const common_upstream = @import("common/upstream_loc.zig");

pub const LineKind = classifier.LineKind;
pub const InstructionForm = classifier.InstructionForm;
pub const ClassifiedLine = classifier.ClassifiedLine;
pub const ForbiddenHit = forbidden.ForbiddenHit;
pub const DefDict = def_dict.DefDict;
pub const DefError = def_dict.DefError;
pub const SymbolTable = symbol.SymbolTable;
pub const Instruction = common_instruction.Instruction;
pub const InstKind = common_instruction.InstKind;
pub const Operand = common_instruction.Operand;
pub const ConstDecl = common_const_decl.ConstDecl;
pub const FunctionSig = common_signature.FunctionSig;
pub const FunctionKind = common_signature.FunctionKind;
pub const Trap = common_trap.Trap;
pub const LocTable = common_upstream.LocTable;

const MacroDef = struct {
    params: []const []const u8,
    body_start: usize,
    body_end: usize,

    fn deinit(self: *MacroDef, allocator: std.mem.Allocator) void {
        allocator.free(self.params);
        self.* = undefined;
    }
};

const Replacement = struct {
    needle: []const u8,
    replacement: []const u8,
};

pub const SourceLine = struct {
    line_no: u32,
    text: []const u8,
    classified: ClassifiedLine,
};

pub const ErrorContext = struct {
    source_line: ?u32 = null,
};

fn recordErrorSourceLine(error_ctx: ?*ErrorContext, line_no: u32) void {
    if (error_ctx) |ctx| {
        ctx.source_line = line_no;
    }
}

pub fn takeErrorSourceLine(error_ctx: *ErrorContext) ?u32 {
    const line_no = error_ctx.source_line;
    error_ctx.source_line = null;
    return line_no;
}

const ImportExpansion = struct {
    source: []u8,
    active_paths: std.StringHashMap(void),
    owned_paths: std.ArrayList([]u8),

    fn deinit(self: *ImportExpansion, allocator: std.mem.Allocator) void {
        for (self.owned_paths.items) |path| {
            allocator.free(path);
        }
        self.owned_paths.deinit();
        self.active_paths.deinit();
        allocator.free(self.source);
        self.* = undefined;
    }
};

pub const FlattenResult = struct {
    instructions: []Instruction,
    const_decls: []ConstDecl,
    function_sigs: []FunctionSig,
    def_dict: DefDict,
    symbols: SymbolTable,
    loc_table: LocTable,
    owned_text: [][]const u8,
    trap: ?Trap = null,

    pub fn deinit(self: *FlattenResult, allocator: std.mem.Allocator) void {
        for (self.loc_table) |entry| {
            if (entry) |loc| allocator.free(loc.file);
        }
        allocator.free(self.loc_table);
        for (self.instructions) |item| {
            if (item.upstream_loc) |loc| allocator.free(loc.file);
            if (item.native_reg_names.len != 0) allocator.free(item.native_reg_names);
        }
        for (self.const_decls) |*decl| decl.deinit(allocator);
        allocator.free(self.const_decls);
        for (self.owned_text) |text| allocator.free(text);
        allocator.free(self.owned_text);
        for (self.function_sigs) |*sig| sig.deinit(allocator);
        allocator.free(self.function_sigs);
        allocator.free(self.instructions);
        self.def_dict.deinit();
        self.symbols.deinit();
        self.* = undefined;
    }
};

pub const ForbiddenLine = struct {
    line_no: u32,
    hit: ForbiddenHit,
};

fn parseTokenList(allocator: std.mem.Allocator, text: []const u8) ![]const []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) {
        return try allocator.alloc([]const u8, 0);
    }

    var list = std.ArrayList([]const u8).init(allocator);
    errdefer list.deinit();

    var it = std.mem.splitScalar(u8, trimmed, ',');
    while (it.next()) |item| {
        const token = std.mem.trim(u8, item, " \t");
        if (token.len == 0) return error.InvalidMacroInvocation;
        try list.append(token);
    }

    return try list.toOwnedSlice();
}

fn deinitMacroMap(allocator: std.mem.Allocator, macros: *std.StringHashMap(MacroDef)) void {
    var it = macros.valueIterator();
    while (it.next()) |macro_def| {
        allocator.free(macro_def.params);
    }
    macros.deinit();
}

fn renderWithReplacements(
    allocator: std.mem.Allocator,
    text: []const u8,
    replacements: []const Replacement,
) ![]const u8 {
    if (replacements.len == 0) {
        return try allocator.dupe(u8, text);
    }

    var current = try allocator.dupe(u8, text);
    errdefer allocator.free(current);

    for (replacements) |replacement| {
        if (replacement.needle.len == 0) continue;
        const next = try std.mem.replaceOwned(u8, allocator, current, replacement.needle, replacement.replacement);
        allocator.free(current);
        current = next;
    }

    return current;
}

fn ownText(
    allocator: std.mem.Allocator,
    owned_text: *std.ArrayList([]const u8),
    text: []const u8,
) ![]const u8 {
    const dup = try allocator.dupe(u8, text);
    errdefer allocator.free(dup);
    try owned_text.append(dup);
    return dup;
}

fn ownFoldedText(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    owned_text: *std.ArrayList([]const u8),
    text: []const u8,
) ![]const u8 {
    const folded = try dict.foldText(allocator, text);
    errdefer allocator.free(folded);
    try owned_text.append(folded);
    return folded;
}

fn parseNumericOperand(text: []const u8) ?common_instruction.Operand {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len == 0) return null;

    if (std.fmt.parseInt(i64, trimmed, 10)) |value| {
        return .{ .imm_i64 = value };
    } else |err| switch (err) {
        error.Overflow => {
            if (std.fmt.parseInt(u64, trimmed, 10)) |value| {
                return .{ .imm_u64 = value };
            } else |_| {}
        },
        else => {},
    }

    if (std.mem.indexOfAny(u8, trimmed, ".eE")) |_| {
        if (std.fmt.parseFloat(f64, trimmed)) |value| {
            return .{ .imm_float = value };
        } else |_| {}
    }

    return null;
}

fn resolveOperandText(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    owned_text: *std.ArrayList([]const u8),
    symbols: *SymbolTable,
    text: []const u8,
) !common_instruction.Operand {
    const folded = try ownFoldedText(allocator, dict, owned_text, text);
    if (parseNumericOperand(folded)) |operand| return operand;
    return .{ .reg = try symbols.intern(folded) };
}

fn consumePendingLoc(
    loc_table: *std.ArrayList(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
) !?common_upstream.UpstreamLoc {
    const loc = pending_loc.*;
    try loc_table.append(loc);
    pending_loc.* = null;
    return loc;
}

fn takePendingLoc(
    pending_loc: *?common_upstream.UpstreamLoc,
) ?common_upstream.UpstreamLoc {
    const loc = pending_loc.*;
    pending_loc.* = null;
    return loc;
}

fn appendNullLoc(loc_table: *std.ArrayList(?common_upstream.UpstreamLoc)) !void {
    try loc_table.append(null);
}

fn setPendingLoc(
    allocator: std.mem.Allocator,
    pending_loc: *?common_upstream.UpstreamLoc,
    file: []const u8,
    line: u32,
    col: u32,
) !void {
    if (pending_loc.*) |current| {
        allocator.free(current.file);
        pending_loc.* = null;
    }
    const file_copy = try allocator.dupe(u8, file);
    pending_loc.* = .{
        .file = file_copy,
        .line = line,
        .col = col,
    };
}

fn findBlockEnd(lines: []const SourceLine, start: usize, close_kind: LineKind) ?usize {
    var idx = start;
    while (idx < lines.len) : (idx += 1) {
        if (lines[idx].classified.kind == close_kind) return idx;
    }
    return null;
}

fn findNestedRepEnd(lines: []const SourceLine, start: usize) ?usize {
    var depth: usize = 1;
    var idx = start;
    while (idx < lines.len) : (idx += 1) {
        switch (lines[idx].classified.kind) {
            .rep_start => depth += 1,
            .rep_end => {
                depth -= 1;
                if (depth == 0) return idx;
            },
            else => {},
        }
    }
    return null;
}

fn mapInstKind(form: InstructionForm) InstKind {
    return switch (form) {
        .alloc => .alloc,
        .stack_alloc => .stack_alloc,
        .load => .load,
        .store => .store,
        .atomic_load => .atomic_load,
        .atomic_store => .atomic_store,
        .cmpxchg => .cmpxchg,
        .atomic_rmw => .atomic_rmw,
        .fence => .fence,
        .borrow => .borrow,
        .move_ => .move_,
        .release => .release,
        .assign => .assign,
        .op => .op,
        .ptr_add => .ptr_add,
        .jmp => .jmp,
        .br => .br,
        .br_null => .br_null,
        .call => .call,
        .call_indirect => .call_indirect,
        .try_ => .early_return,
        .panic => .panic,
        .panic_msg => .panic_msg,
        .return_ => .return_,
        .take => .take,
        .raw_cast => .raw_cast,
        .assume_safe => .assume_safe,
        .assume_borrow => .assume_borrow,
        .unknown => .native,
    };
}

fn parseFunctionSigForKind(
    allocator: std.mem.Allocator,
    raw_line: []const u8,
    id: u32,
    entry_idx: u32,
    kind: FunctionKind,
    symbols: *SymbolTable,
) !FunctionSig {
    var sig = try common_signature.parseFunctionHeader(allocator, raw_line, id, entry_idx, kind);
    errdefer sig.deinit(allocator);
    if (sig.params.len == 0) {
        sig.param_ids = &.{};
        return sig;
    }
    const ids = try allocator.alloc(u32, sig.params.len);
    errdefer allocator.free(ids);
    for (sig.params, 0..) |param, idx| {
        ids[idx] = try symbols.intern(param.name);
    }
    sig.param_ids = ids;
    return sig;
}

fn emitParsedLine(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.ArrayList(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    raw_line: []const u8,
    source_line: u32,
    instructions: *std.ArrayList(Instruction),
    const_decls: *std.ArrayList(ConstDecl),
    function_sigs: *std.ArrayList(FunctionSig),
    owned_text: *std.ArrayList([]const u8),
) !void {
    const classified = classifier.classifyLine(raw_line);
    switch (classified.kind) {
        .blank_or_comment => {},
        .import_decl => {},
        .const_decl => {
            const upstream_loc = takePendingLoc(pending_loc);
            errdefer if (upstream_loc) |loc| allocator.free(loc.file);
            var decl = try common_const_decl.parseConstDecl(
                allocator,
                raw_line,
                source_line,
                @intCast(instructions.items.len),
                upstream_loc,
            );
            errdefer decl.deinit(allocator);
            _ = try symbols.intern(decl.name);
            try const_decls.append(decl);
        },
        .loc_hint => {
            const line_no = try std.fmt.parseInt(u32, classified.parts[1], 10);
            const col_no = try std.fmt.parseInt(u32, classified.parts[2], 10);
            try setPendingLoc(allocator, pending_loc, classified.parts[0], line_no, col_no);
        },
        .def => try dict.putExpression(classified.parts[0], classified.parts[1]),
        .native => {
            const inst_loc = try consumePendingLoc(loc_table, pending_loc);
            const raw_copy = try ownText(allocator, owned_text, raw_line);
            const native_copy = try ownText(allocator, owned_text, classified.parts[0]);
            const native_reg_names = try classifier.collectNativeRegisterNames(allocator, native_copy);
            var inst = common_instruction.makeInstruction(.native, source_line, @intCast(instructions.items.len), inst_loc, raw_copy);
            inst.operands[0] = .{ .native_text = native_copy };
            inst.native_reg_names = native_reg_names;
            try instructions.append(inst);
        },
        .label => {
            const label_name = try ownFoldedText(allocator, dict, owned_text, classified.parts[0]);
            try appendNullLoc(loc_table);
            const label_id = try symbols.intern(label_name);
            const raw_copy = try ownText(allocator, owned_text, raw_line);
            var inst = common_instruction.makeInstruction(.label, source_line, @intCast(instructions.items.len), null, raw_copy);
            inst.operands[0] = .{ .symbol = label_id };
            inst.operands[1] = .{ .label = label_id };
            try instructions.append(inst);
        },
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl => {
            const kind = switch (classified.kind) {
                .func_decl => FunctionKind.normal,
                .ffi_wrapper_decl => FunctionKind.ffi_wrapper,
                .extern_decl => FunctionKind.external,
                .export_decl => FunctionKind.exported,
                else => FunctionKind.normal,
            };
            var sig = try parseFunctionSigForKind(
                allocator,
                raw_line,
                @intCast(function_sigs.items.len),
                @intCast(instructions.items.len),
                kind,
                symbols,
            );
            errdefer sig.deinit(allocator);
            var inst_loc: ?common_upstream.UpstreamLoc = null;
            if (pending_loc.*) |loc| {
                const sig_file_copy = try allocator.dupe(u8, loc.file);
                errdefer allocator.free(sig_file_copy);
                const inst_file_copy = try allocator.dupe(u8, loc.file);
                errdefer allocator.free(inst_file_copy);
                sig.upstream_file = sig_file_copy;
                sig.upstream_loc = .{
                    .file = sig_file_copy,
                    .line = loc.line,
                    .col = loc.col,
                };
                inst_loc = .{
                    .file = inst_file_copy,
                    .line = loc.line,
                    .col = loc.col,
                };
            }
            const name_id = try symbols.intern(sig.name);
            const inst_kind: InstKind = switch (kind) {
                .normal => .func_decl,
                .ffi_wrapper => .ffi_wrapper_decl,
                .external => .extern_decl,
                .exported => .export_decl,
            };
            try appendNullLoc(loc_table);
            const raw_copy = try ownText(allocator, owned_text, raw_line);
            var inst = common_instruction.makeInstruction(inst_kind, source_line, @intCast(instructions.items.len), inst_loc, raw_copy);
            inst.operands[0] = .{ .symbol = name_id };
            inst.operands[1] = .{ .func = name_id };
            try instructions.append(inst);
            try function_sigs.append(sig);
        },
        .instruction => {
            const inst_kind = mapInstKind(classified.inst_form.?);
            const inst_loc = try consumePendingLoc(loc_table, pending_loc);
            const raw_copy = try ownText(allocator, owned_text, raw_line);
            var inst = common_instruction.makeInstruction(inst_kind, source_line, @intCast(instructions.items.len), inst_loc, raw_copy);
            switch (classified.inst_form.?) {
                .alloc => {
                    const dst = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = dst };
                    const size_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[1]);
                    inst.operands[1] = .{ .imm_u64 = try std.fmt.parseInt(u64, size_text, 10) };
                },
                .atomic_load => {
                    const parsed = atomic.parseLoad(raw_line) catch |err| switch (err) {
                        error.InvalidAtomicOrdering => return error.InvalidAtomicOrdering,
                        error.UnsupportedType => return error.UnsupportedType,
                        else => return error.InvalidSyntax,
                    };
                    const dst = try symbols.intern(parsed.dst);
                    const base = try symbols.intern(parsed.base);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, parsed.offset);
                    inst.operands[2] = .{ .imm_u64 = try std.fmt.parseInt(u64, offset_text, 10) };
                    inst.atomic_value_ty = if (parsed.ty) |ty| @intFromEnum(ty) else null;
                    inst.atomic_ordering = parsed.ordering;
                },
                .atomic_store => {
                    const parsed = atomic.parseStore(raw_line) catch |err| switch (err) {
                        error.InvalidAtomicOrdering => return error.InvalidAtomicOrdering,
                        error.UnsupportedType => return error.UnsupportedType,
                        else => return error.InvalidSyntax,
                    };
                    const base = try symbols.intern(parsed.base);
                    inst.operands[0] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, parsed.offset);
                    inst.operands[1] = .{ .imm_u64 = try std.fmt.parseInt(u64, offset_text, 10) };
                    const value_text = try ownFoldedText(allocator, dict, owned_text, parsed.value);
                    inst.operands[2] = .{ .text = value_text };
                    inst.atomic_value_ty = if (parsed.ty) |ty| @intFromEnum(ty) else null;
                    inst.atomic_ordering = parsed.ordering;
                },
                .cmpxchg => {
                    const parsed = atomic.parseCmpxchg(raw_line) catch |err| switch (err) {
                        error.InvalidAtomicOrdering => return error.InvalidAtomicOrdering,
                        error.UnsupportedType => return error.UnsupportedType,
                        else => return error.InvalidSyntax,
                    };
                    const dst = try symbols.intern(parsed.dst);
                    const ok = try symbols.intern(parsed.ok);
                    const base = try symbols.intern(parsed.base);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = ok };
                    inst.operands[2] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, parsed.offset);
                    inst.operands[3] = .{ .imm_u64 = try std.fmt.parseInt(u64, offset_text, 10) };
                    inst.atomic_expected_text = try ownFoldedText(allocator, dict, owned_text, parsed.expected);
                    inst.atomic_new_text = try ownFoldedText(allocator, dict, owned_text, parsed.new_value);
                    inst.atomic_value_ty = if (parsed.ty) |ty| @intFromEnum(ty) else null;
                    inst.atomic_ordering = parsed.success_ordering;
                    inst.atomic_second_ordering = parsed.failure_ordering;
                },
                .atomic_rmw => {
                    const parsed = atomic.parseRmw(raw_line) catch |err| switch (err) {
                        error.InvalidAtomicOrdering => return error.InvalidAtomicOrdering,
                        error.UnsupportedType => return error.UnsupportedType,
                        else => return error.InvalidSyntax,
                    };
                    const dst = try symbols.intern(parsed.dst);
                    const base = try symbols.intern(parsed.base);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, parsed.offset);
                    inst.operands[2] = .{ .imm_u64 = try std.fmt.parseInt(u64, offset_text, 10) };
                    const value_text = try ownFoldedText(allocator, dict, owned_text, parsed.value);
                    inst.operands[3] = .{ .text = value_text };
                    inst.atomic_value_ty = if (parsed.ty) |ty| @intFromEnum(ty) else null;
                    inst.atomic_ordering = parsed.ordering;
                    inst.atomic_rmw_op = parsed.op;
                },
                .fence => {
                    const parsed = atomic.parseFence(raw_line) catch |err| switch (err) {
                        error.InvalidAtomicOrdering => return error.InvalidAtomicOrdering,
                        error.UnsupportedType => return error.UnsupportedType,
                        else => return error.InvalidSyntax,
                    };
                    inst.atomic_ordering = parsed.ordering;
                },
                .stack_alloc => {
                    const dst = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = dst };
                    const size_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[1]);
                    inst.operands[1] = .{ .imm_u64 = try std.fmt.parseInt(u64, size_text, 10) };
                },
                .load, .take => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const base = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[2]);
                    inst.operands[2] = .{ .imm_u64 = try std.fmt.parseInt(u64, offset_text, 10) };
                    if (classified.part_count > 3) {
                        const ty = try common_signature.parsePrimType(classified.parts[3]);
                        inst.operands[3] = .{ .ty = @intFromEnum(ty) };
                    }
                },
                .borrow => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const source = try symbols.intern(classified.parts[2]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = source };
                    inst.operands[2] = .{ .text = classified.parts[1] };
                    inst.operands[3] = .{ .cap_prefix = .borrow };
                },
                .move_ => {
                    const reg = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = reg };
                },
                .release => {
                    const reg = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = reg };
                },
                .assign => {
                    const dst = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[1]);
                },
                .store => {
                    const base = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[1]);
                    inst.operands[1] = .{ .imm_u64 = try std.fmt.parseInt(u64, offset_text, 10) };
                    const value_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[2]);
                    inst.operands[2] = .{ .text = value_text };
                    if (classified.part_count > 3) {
                        const ty = try common_signature.parsePrimType(classified.parts[3]);
                        inst.operands[3] = .{ .ty = @intFromEnum(ty) };
                    }
                },
                .op => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const op_name = classified.parts[1];
                    const op_kind = common_instruction.parseOpKind(op_name) orelse return error.InvalidSyntax;
                    inst.operands[0] = .{ .reg = dst };
                    inst.op_kind = op_kind;

                    if (common_instruction.isTernaryOpKind(op_kind)) {
                        inst.operands[1] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[2]);
                        inst.operands[2] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[3]);
                        inst.operands[3] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[4]);
                    } else if (common_instruction.isUnaryOpKind(op_kind)) {
                        inst.operands[1] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[2]);
                        if (common_instruction.isTypeConversionOpKind(op_kind)) {
                            const target_ty: common_signature.PrimType = if (classified.part_count > 3 and classified.parts[3].len != 0)
                                try common_signature.parsePrimType(classified.parts[3])
                            else
                                .i32;
                            inst.operands[2] = .{ .ty = @intFromEnum(target_ty) };
                        }
                    } else if (common_instruction.isBinaryOpKind(op_kind)) {
                        inst.operands[1] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[2]);
                        inst.operands[2] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[3]);
                        if (op_kind == .extract_lane and classified.part_count > 4) {
                            inst.operands[3] = try resolveOperandText(allocator, dict, owned_text, symbols, classified.parts[4]);
                        }
                    } else {
                        return error.InvalidSyntax;
                    }
                },
                .ptr_add => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const base = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[2]);
                    if (std.fmt.parseInt(i64, offset_text, 10)) |offset| {
                        inst.operands[2] = .{ .imm_i64 = offset };
                    } else |err| switch (err) {
                        error.Overflow => return error.InvalidSyntax,
                        else => {
                            if (symbols.findId(offset_text)) |off_reg| {
                                inst.operands[2] = .{ .reg = off_reg };
                            } else {
                                inst.operands[2] = .{ .text = offset_text };
                            }
                        },
                    }
                },
                .jmp => {
                    const target_text = try dict.foldText(allocator, classified.parts[0]);
                    try owned_text.append(target_text);
                    inst.operands[0] = .{ .symbol = try symbols.intern(target_text) };
                    inst.operands[1] = .{ .label = try symbols.intern(target_text) };
                },
                .br => {
                    const cond_text = try dict.foldText(allocator, classified.parts[0]);
                    try owned_text.append(cond_text);
                    inst.operands[0] = .{ .reg = try symbols.intern(cond_text) };

                    const true_text = try dict.foldText(allocator, classified.parts[1]);
                    try owned_text.append(true_text);
                    inst.operands[1] = .{ .label = try symbols.intern(true_text) };
                    inst.operands[2] = .{ .label = try symbols.intern(true_text) };

                    const false_text = try dict.foldText(allocator, classified.parts[2]);
                    try owned_text.append(false_text);
                    inst.operands[3] = .{ .label = try symbols.intern(false_text) };
                },
                .br_null => {
                    const reg_text = try dict.foldText(allocator, classified.parts[0]);
                    try owned_text.append(reg_text);
                    inst.operands[0] = .{ .reg = try symbols.intern(reg_text) };

                    const null_text = try dict.foldText(allocator, classified.parts[1]);
                    try owned_text.append(null_text);
                    inst.operands[1] = .{ .label = try symbols.intern(null_text) };
                    inst.operands[2] = .{ .label = try symbols.intern(null_text) };

                    const not_null_text = try dict.foldText(allocator, classified.parts[2]);
                    try owned_text.append(not_null_text);
                    inst.operands[3] = .{ .label = try symbols.intern(not_null_text) };
                },
                .call, .call_indirect, .try_, .panic, .panic_msg, .return_ => {
                    if (classified.inst_form == .return_ and classified.part_count == 1) {
                        const folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[0]);
                        if (symbols.findId(folded)) |id| {
                            inst.operands[0] = .{ .reg = id };
                        } else {
                            inst.operands[0] = .{ .text = folded };
                        }
                    } else if (classified.inst_form == .try_) {
                        const dst = try symbols.intern(classified.parts[0]);
                        const source = try symbols.intern(classified.parts[1]);
                        inst.operands[0] = .{ .reg = dst };
                        inst.operands[1] = .{ .reg = source };
                    } else if (classified.part_count == 2) {
                        const dst = try symbols.intern(classified.parts[0]);
                        inst.operands[0] = .{ .reg = dst };
                        const folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[1]);
                        inst.operands[1] = .{ .text = folded };
                    } else {
                        for (classified.parts[0..classified.part_count], 0..) |part, idx| {
                            const folded = try ownFoldedText(allocator, dict, owned_text, part);
                            inst.operands[idx] = .{ .text = folded };
                        }
                    }
                },
                .raw_cast => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const source = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = source };
                },
                .assume_safe => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const source = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = source };
                },
                .assume_borrow => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const source = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = source };
                    if (classified.part_count > 2) {
                        const mode = try ownText(allocator, owned_text, classified.parts[2]);
                        inst.operands[2] = .{ .text = mode };
                    }
                },
                .unknown => return error.InvalidSyntax,
            }
            try instructions.append(inst);
        },
        .unknown => return error.InvalidSyntax,
        .macro_start, .macro_end, .rep_start, .rep_end, .expand => return error.InvalidSyntax,
    }
}

fn collectMacroDefinitions(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
    macros: *std.StringHashMap(MacroDef),
    error_ctx: ?*ErrorContext,
) !void {
    var idx: usize = 0;
    while (idx < lines.len) : (idx += 1) {
        const line = lines[idx];
        recordErrorSourceLine(error_ctx, line.line_no);
        switch (line.classified.kind) {
            .blank_or_comment, .def, .const_decl, .import_decl, .loc_hint, .native, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .instruction, .unknown, .expand, .rep_start, .rep_end, .macro_end => {},
            .macro_start => {
                const end = findBlockEnd(lines, idx + 1, .macro_end) orelse return error.UnbalancedMacro;
                const name = line.classified.parts[0];
                const params = try parseTokenList(allocator, line.classified.parts[1]);
                errdefer allocator.free(params);
                if (macros.contains(name)) return error.DuplicateDef;
                try macros.put(name, .{
                    .params = params,
                    .body_start = idx + 1,
                    .body_end = end,
                });
                idx = end;
            },
        }
    }
}

fn emitRange(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
    start: usize,
    end: usize,
    depth: u16,
    source_line_override: ?u32,
    replacements: []const Replacement,
    top_level: bool,
    macros: *std.StringHashMap(MacroDef),
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.ArrayList(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    instructions: *std.ArrayList(Instruction),
    const_decls: *std.ArrayList(ConstDecl),
    function_sigs: *std.ArrayList(FunctionSig),
    owned_text: *std.ArrayList([]const u8),
    error_ctx: ?*ErrorContext,
) !void {
    if (depth > 256) return error.MacroRecursionLimit;

    var idx = start;
    while (idx < end) : (idx += 1) {
        const line = lines[idx];
        const source_line = source_line_override orelse line.line_no;
        recordErrorSourceLine(error_ctx, source_line);

        switch (line.classified.kind) {
            .blank_or_comment, .import_decl => {},
            .const_decl => {
                if (!top_level) return error.InvalidMacroDefinitionContext;
                const upstream_loc = takePendingLoc(pending_loc);
                errdefer if (upstream_loc) |loc| allocator.free(loc.file);
                var decl = try common_const_decl.parseConstDecl(
                    allocator,
                    line.text,
                    source_line,
                    @intCast(instructions.items.len),
                    upstream_loc,
                );
                errdefer decl.deinit(allocator);
                _ = try symbols.intern(decl.name);
                try const_decls.append(decl);
            },
            .loc_hint => {
                const line_no = try std.fmt.parseInt(u32, line.classified.parts[1], 10);
                const col_no = try std.fmt.parseInt(u32, line.classified.parts[2], 10);
                try setPendingLoc(allocator, pending_loc, line.classified.parts[0], line_no, col_no);
            },
            .def, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .instruction, .native, .unknown => {
                const should_render = source_line_override != null or replacements.len != 0;
                if (should_render) {
                    const rendered = try renderWithReplacements(allocator, line.text, replacements);
                    try owned_text.append(rendered);
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, rendered, source_line, instructions, const_decls, function_sigs, owned_text);
                } else {
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, line.text, source_line, instructions, const_decls, function_sigs, owned_text);
                }
            },
            .macro_start => {
                if (!top_level) return error.InvalidMacroDefinitionContext;
                const def = macros.get(line.classified.parts[0]) orelse return error.InvalidMacroInvocation;
                idx = def.body_end;
            },
            .macro_end => return error.UnbalancedMacro,
            .rep_start => {
                const count_text = try dict.foldText(allocator, line.classified.parts[0]);
                try owned_text.append(count_text);
                const count = try std.fmt.parseInt(usize, count_text, 10);
                const rep_end = findNestedRepEnd(lines, idx + 1) orelse return error.UnbalancedRep;

                var rep_index: usize = 0;
                while (rep_index < count) : (rep_index += 1) {
                    const rep_value = try std.fmt.allocPrint(allocator, "{d}", .{rep_index});
                    defer allocator.free(rep_value);

                    const combined = if (replacements.len == 0) blk: {
                        var list = std.ArrayList(Replacement).init(allocator);
                        errdefer list.deinit();
                        try list.append(.{ .needle = "%i", .replacement = rep_value });
                        break :blk try list.toOwnedSlice();
                    } else blk: {
                        var list = std.ArrayList(Replacement).init(allocator);
                        errdefer list.deinit();
                        try list.appendSlice(replacements);
                        try list.append(.{ .needle = "%i", .replacement = rep_value });
                        break :blk try list.toOwnedSlice();
                    };
                    defer allocator.free(combined);

                    try emitRange(
                        allocator,
                        lines,
                        idx + 1,
                        rep_end,
                        depth + 1,
                        source_line_override orelse line.line_no,
                        combined,
                        false,
                        macros,
                        dict,
                        symbols,
                        loc_table,
                        pending_loc,
                        instructions,
                        const_decls,
                        function_sigs,
                        owned_text,
                        error_ctx,
                    );
                }

                idx = rep_end;
            },
            .rep_end => return error.UnbalancedRep,
            .expand => {
                const rendered_line = if (replacements.len == 0) line.text else blk: {
                    const rendered = try renderWithReplacements(allocator, line.text, replacements);
                    try owned_text.append(rendered);
                    break :blk rendered;
                };
                const rendered_classified = classifier.classifyLine(rendered_line);
                if (rendered_classified.kind != .expand) return error.InvalidSyntax;
                const def = macros.get(rendered_classified.parts[0]) orelse return error.InvalidMacroInvocation;
                const args = try parseTokenList(allocator, rendered_classified.parts[1]);
                defer allocator.free(args);
                if (args.len != def.params.len) return error.InvalidMacroInvocation;

                var local_replacements = std.ArrayList(Replacement).init(allocator);
                errdefer local_replacements.deinit();
                for (def.params, 0..) |param, iarg| {
                    try local_replacements.append(.{ .needle = param, .replacement = args[iarg] });
                }
                const local_slice = try local_replacements.toOwnedSlice();
                defer allocator.free(local_slice);
                try emitRange(
                    allocator,
                    lines,
                    def.body_start,
                    def.body_end,
                    depth + 1,
                    source_line_override orelse line.line_no,
                    local_slice,
                    false,
                    macros,
                    dict,
                    symbols,
                    loc_table,
                    pending_loc,
                    instructions,
                    const_decls,
                    function_sigs,
                    owned_text,
                    error_ctx,
                );
            },
        }
    }
}

fn collectLocTableEntries(
    allocator: std.mem.Allocator,
    instructions: []const Instruction,
) !LocTable {
    var table = std.ArrayList(?common_upstream.UpstreamLoc).init(allocator);
    errdefer table.deinit();

    for (instructions) |item| {
        const keep_loc = switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .label => false,
            else => true,
        };
        if (keep_loc) {
            if (item.upstream_loc) |loc| {
                const file_copy = try allocator.dupe(u8, loc.file);
                errdefer allocator.free(file_copy);
                try table.append(.{
                    .file = file_copy,
                    .line = loc.line,
                    .col = loc.col,
                });
            } else {
                try table.append(null);
            }
        } else {
            try table.append(null);
        }
    }

    return try table.toOwnedSlice();
}

pub fn scanSource(allocator: std.mem.Allocator, source: []const u8) ![]SourceLine {
    var lines = std.ArrayList(SourceLine).init(allocator);
    errdefer lines.deinit();

    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iterator.next()) |raw_line| : (line_no += 1) {
        try lines.append(.{
            .line_no = line_no,
            .text = raw_line,
            .classified = classifier.classifyLine(raw_line),
        });
    }

    return try lines.toOwnedSlice();
}

fn appendOwnedSource(out: *std.ArrayList(u8), source: []const u8) !void {
    if (source.len == 0) return;
    try out.appendSlice(source);
    if (source[source.len - 1] != '\n') try out.append('\n');
}

fn parseImportPath(line: []const u8) ?[]const u8 {
    const classified = classifier.classifyLine(line);
    if (classified.kind != .import_decl) return null;
    return classified.parts[0];
}

fn readImportFile(
    allocator: std.mem.Allocator,
    base_dir: []const u8,
    import_path: []const u8,
) !struct { full_path: []u8, source: []u8 } {
    const joined_path = if (std.fs.path.isAbsolute(import_path))
        try allocator.dupe(u8, import_path)
    else
        try std.fs.path.join(allocator, &.{ base_dir, import_path });
    errdefer allocator.free(joined_path);

    // Normalize the import path before we store it in the active path set.
    // This keeps cycles visible even when intermediate imports contain `..`.
    const full_path = try std.fs.cwd().realpathAlloc(allocator, joined_path);
    allocator.free(joined_path);
    errdefer allocator.free(full_path);

    const source = try std.fs.cwd().readFileAlloc(allocator, full_path, 16 * 1024 * 1024);
    errdefer allocator.free(source);

    return .{ .full_path = full_path, .source = source };
}

fn expandImportsInto(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    source: []const u8,
    base_dir: []const u8,
    active_paths: *std.StringHashMap(void),
    owned_paths: *std.ArrayList([]u8),
    error_ctx: ?*ErrorContext,
) !void {
    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iterator.next()) |raw_line| : (line_no += 1) {
        recordErrorSourceLine(error_ctx, line_no);
        if (parseImportPath(raw_line)) |import_path| {
            const imported = try readImportFile(allocator, base_dir, import_path);
            defer allocator.free(imported.source);

            if (active_paths.contains(imported.full_path)) {
                allocator.free(imported.full_path);
                return error.ImportCycle;
            }
            owned_paths.append(imported.full_path) catch |err| {
                allocator.free(imported.full_path);
                return err;
            };
            try active_paths.put(imported.full_path, {});
            defer _ = active_paths.remove(imported.full_path);

            const import_dir = std.fs.path.dirname(imported.full_path) orelse ".";
            try expandImportsInto(allocator, out, imported.source, import_dir, active_paths, owned_paths, error_ctx);
            continue;
        }

        try out.appendSlice(raw_line);
        try out.append('\n');
    }
}

fn expandImports(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_path: ?[]const u8,
    error_ctx: ?*ErrorContext,
) !ImportExpansion {
    var active_paths = std.StringHashMap(void).init(allocator);
    errdefer active_paths.deinit();

    var owned_paths = std.ArrayList([]u8).init(allocator);
    errdefer {
        for (owned_paths.items) |path| allocator.free(path);
        owned_paths.deinit();
    }

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();

    const base_dir = if (source_path) |path| std.fs.path.dirname(path) orelse "." else ".";
    if (source_path) |path| {
        const source_full = if (std.fs.path.isAbsolute(path))
            try allocator.dupe(u8, path)
        else
            try std.fs.cwd().realpathAlloc(allocator, path);
        owned_paths.append(source_full) catch |err| {
            allocator.free(source_full);
            return err;
        };
        try active_paths.put(source_full, {});
    }

    try expandImportsInto(allocator, &out, source, base_dir, &active_paths, &owned_paths, error_ctx);

    return .{
        .source = try out.toOwnedSlice(),
        .active_paths = active_paths,
        .owned_paths = owned_paths,
    };
}

pub fn findFirstForbiddenLine(source: []const u8) ?ForbiddenLine {
    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iterator.next()) |raw_line| : (line_no += 1) {
        const classified = classifier.classifyLine(raw_line);
        if (classified.kind == .native or classified.kind == .import_decl or classified.kind == .const_decl) continue;
        if (forbidden.findForbiddenSyntax(raw_line)) |hit| {
            return .{ .line_no = line_no, .hit = hit };
        }
    }
    return null;
}

fn flattenInternal(
    allocator: std.mem.Allocator,
    source: []const u8,
    source_path: ?[]const u8,
    error_ctx: ?*ErrorContext,
) !FlattenResult {
    if (error_ctx) |ctx| ctx.source_line = null;
    var expanded = try expandImports(allocator, source, source_path, error_ctx);
    defer expanded.deinit(allocator);

    if (findFirstForbiddenLine(expanded.source)) |_| {
        return error.ForbiddenSyntax;
    }

    var dict = DefDict.init(allocator);
    errdefer dict.deinit();
    var symbols = SymbolTable.init(allocator);
    errdefer symbols.deinit();
    var instructions = std.ArrayList(Instruction).init(allocator);
    errdefer instructions.deinit();
    var const_decls = std.ArrayList(ConstDecl).init(allocator);
    errdefer {
        for (const_decls.items) |*decl| decl.deinit(allocator);
        const_decls.deinit();
    }
    var function_sigs = std.ArrayList(FunctionSig).init(allocator);
    errdefer {
        for (function_sigs.items) |*sig_item| sig_item.deinit(allocator);
        function_sigs.deinit();
    }
    var owned_text = std.ArrayList([]const u8).init(allocator);
    errdefer {
        for (owned_text.items) |text| allocator.free(text);
        owned_text.deinit();
    }
    var loc_table = std.ArrayList(?common_upstream.UpstreamLoc).init(allocator);
    errdefer {
        for (loc_table.items) |entry| {
            if (entry) |loc| allocator.free(loc.file);
        }
        loc_table.deinit();
    }
    var pending_loc: ?common_upstream.UpstreamLoc = null;
    errdefer if (pending_loc) |loc| allocator.free(loc.file);

    var macros = std.StringHashMap(MacroDef).init(allocator);
    defer deinitMacroMap(allocator, &macros);

    const lines = try scanSource(allocator, expanded.source);
    defer allocator.free(lines);

    try collectMacroDefinitions(allocator, lines, &macros, error_ctx);
    const empty_replacements = [_]Replacement{};
    try emitRange(
        allocator,
        lines,
        0,
        lines.len,
        0,
        null,
        empty_replacements[0..],
        true,
        &macros,
        &dict,
        &symbols,
        &loc_table,
        &pending_loc,
        &instructions,
        &const_decls,
        &function_sigs,
        &owned_text,
        error_ctx,
    );
    if (pending_loc) |loc| {
        allocator.free(loc.file);
        pending_loc = null;
    }

    const loc_table_slice = try collectLocTableEntries(allocator, instructions.items);
    loc_table.deinit();

    return .{
        .instructions = try instructions.toOwnedSlice(),
        .const_decls = try const_decls.toOwnedSlice(),
        .function_sigs = try function_sigs.toOwnedSlice(),
        .def_dict = dict,
        .symbols = symbols,
        .loc_table = loc_table_slice,
        .owned_text = try owned_text.toOwnedSlice(),
        .trap = null,
    };
}

pub fn flatten(allocator: std.mem.Allocator, source: []const u8) !FlattenResult {
    return flattenInternal(allocator, source, null, null);
}

pub fn flattenWithContext(allocator: std.mem.Allocator, source: []const u8, error_ctx: ?*ErrorContext) !FlattenResult {
    return flattenInternal(allocator, source, null, error_ctx);
}

pub fn flattenFileWithContext(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
    error_ctx: ?*ErrorContext,
) !FlattenResult {
    return flattenInternal(allocator, source, source_path, error_ctx);
}

pub fn flattenFile(allocator: std.mem.Allocator, source_path: []const u8, source: []const u8) !FlattenResult {
    return flattenInternal(allocator, source, source_path, null);
}

const MacroPbtProgram = struct {
    source: []u8,
    base_name: []u8,
    acc_name: []u8,
    alloc_size: u64,
    count: u8,

    fn deinit(self: *MacroPbtProgram, allocator: std.mem.Allocator) void {
        allocator.free(self.source);
        allocator.free(self.base_name);
        allocator.free(self.acc_name);
        self.* = undefined;
    }
};

fn buildMacroPbtProgram(allocator: std.mem.Allocator, random: std.Random, iter: usize) !MacroPbtProgram {
    const count = random.intRangeAtMost(u8, 0, 4);
    const alloc_size = random.intRangeAtMost(u64, 1, 64);
    const salt = random.intRangeAtMost(u32, 0, 9999);

    const base_name = try std.fmt.allocPrint(allocator, "base_{d}_{d}", .{ iter, salt });
    errdefer allocator.free(base_name);
    const acc_name = try std.fmt.allocPrint(allocator, "acc_{d}_{d}", .{ iter, salt });
    errdefer allocator.free(acc_name);

    var source = std.ArrayList(u8).init(allocator);
    errdefer source.deinit();
    const writer = source.writer();
    try writer.writeAll(
        \\#def REP_COUNT = 
    );
    try writer.print("{d}\n", .{count});
    try writer.writeAll(
        \\[MACRO] INIT %acc, %base
        \\    %acc = add %base, 0
        \\[END_MACRO]
        \\
        \\[MACRO] CHAIN %acc, %base
        \\    EXPAND INIT %acc, %base
        \\    [REP REP_COUNT]
        \\        tmp_%i = add %acc, %i
        \\    [END_REP]
        \\[END_MACRO]
        \\
        \\@main() -> i32:
        \\
    );
    try writer.print("    {s} = alloc {d}\n", .{ base_name, alloc_size });
    try writer.print("    EXPAND CHAIN {s}, {s}\n", .{ acc_name, base_name });
    try writer.print("    return {s}\n", .{acc_name});

    return .{
        .source = try source.toOwnedSlice(),
        .base_name = base_name,
        .acc_name = acc_name,
        .alloc_size = alloc_size,
        .count = count,
    };
}

fn expectOperandReg(inst: Instruction, index: usize, expected: u32) !void {
    switch (inst.operands[index]) {
        .reg => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestUnexpectedResult,
    }
}

fn expectOperandImmU64(inst: Instruction, index: usize, expected: u64) !void {
    switch (inst.operands[index]) {
        .imm_u64 => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestUnexpectedResult,
    }
}

fn expectOperandImmI64(inst: Instruction, index: usize, expected: i64) !void {
    switch (inst.operands[index]) {
        .imm_i64 => |actual| try std.testing.expectEqual(expected, actual),
        else => return error.TestUnexpectedResult,
    }
}

fn expectRawText(inst: Instruction, expected: []const u8) !void {
    try std.testing.expectEqualStrings(expected, inst.raw_text);
}

test "scanSource preserves line order and classification" {
    const source =
        \\#def SIZE = 16
        \\L_LOOP:
        \\node = alloc 8
    ;
    const lines = try scanSource(std.testing.allocator, source);
    defer std.testing.allocator.free(lines);

    try std.testing.expectEqual(@as(usize, 3), lines.len);
    try std.testing.expectEqual(@as(u32, 1), lines[0].line_no);
    try std.testing.expectEqual(LineKind.def, lines[0].classified.kind);
    try std.testing.expectEqual(LineKind.label, lines[1].classified.kind);
    try std.testing.expectEqual(LineKind.instruction, lines[2].classified.kind);
    try std.testing.expectEqual(InstructionForm.alloc, lines[2].classified.inst_form.?);
}

test "findFirstForbiddenLine skips native blocks and catches keywords" {
    const source =
        \\$if not scanned$
        \\let x = 1
        \\foo.a.b
    ;
    const hit = findFirstForbiddenLine(source).?;
    try std.testing.expectEqual(@as(u32, 3), hit.line_no);
    try std.testing.expectEqual(forbidden.ForbiddenToken.property_chain, hit.hit.token);
}

test "flatten builds instruction stream with symbol and def tables" {
    const source =
        \\#def SIZE = 8
        \\@entry() -> i32:
        \\L_ENTRY:
        \\node = alloc SIZE
        \\return node
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expectEqual(@as(usize, 1), result.function_sigs.len);
    try std.testing.expectEqual(InstKind.func_decl, result.instructions[0].kind);
    try std.testing.expectEqual(InstKind.label, result.instructions[1].kind);
    try std.testing.expectEqual(InstKind.alloc, result.instructions[2].kind);
    try std.testing.expectEqual(InstKind.return_, result.instructions[3].kind);
    try std.testing.expectEqualStrings("8", result.def_dict.get("SIZE").?);
    try std.testing.expectEqualStrings("entry", result.symbols.lookupName(0).?);
    try std.testing.expectEqualStrings("L_ENTRY", result.symbols.lookupName(1).?);
    try std.testing.expectEqualStrings("entry", result.function_sigs[0].name);
    try std.testing.expectEqual(@as(usize, result.instructions.len), result.loc_table.len);
}

test "flatten preserves structured const declarations separately from instructions" {
    const source =
        \\#loc "main.rs":7:3
        \\@const HELLO = utf8:"hello"
        \\@main() -> i32:
        \\L_ENTRY:
        \\return 0
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), result.instructions.len);
    try std.testing.expectEqual(@as(usize, 1), result.const_decls.len);
    try std.testing.expectEqualStrings("HELLO", result.const_decls[0].name);
    try std.testing.expectEqualStrings("utf8:\"hello\"", result.const_decls[0].literal_text);
    try std.testing.expect(result.const_decls[0].upstream_loc != null);
    try std.testing.expectEqualStrings("main.rs", result.const_decls[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 7), result.const_decls[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 3), result.const_decls[0].upstream_loc.?.col);
    switch (result.const_decls[0].value) {
        .utf8 => |literal| try std.testing.expectEqualStrings("hello", literal.bytes),
        else => return error.TestUnexpectedResult,
    }
}

test "flatten keeps native escape text and extracted register names" {
    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\$call side(ptr value, i32 7, @glob, %tmp)$
        \\return 0
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expectEqual(InstKind.native, result.instructions[2].kind);
    try std.testing.expectEqualStrings("call side(ptr value, i32 7, @glob, %tmp)", result.instructions[2].operands[0].native_text);
    try std.testing.expectEqual(@as(usize, 5), result.instructions[2].native_reg_names.len);
    try std.testing.expectEqualStrings("call", result.instructions[2].native_reg_names[0]);
    try std.testing.expectEqualStrings("side", result.instructions[2].native_reg_names[1]);
    try std.testing.expectEqualStrings("ptr", result.instructions[2].native_reg_names[2]);
    try std.testing.expectEqualStrings("value", result.instructions[2].native_reg_names[3]);
    try std.testing.expectEqualStrings("i32", result.instructions[2].native_reg_names[4]);
}

test "flatten attaches loc hint to the next real instruction only" {
    const source =
        \\#loc "up.rs":12:3
        \\@entry() -> i32:
        \\#loc "up.rs":13:5
        \\L_ENTRY:
        \\#loc "up.rs":14:7
        \\node = alloc 8
        \\return node
    ;
    var result = try flatten(std.testing.allocator, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), result.instructions.len);
    try std.testing.expect(result.instructions[0].upstream_loc != null);
    try std.testing.expectEqualStrings("up.rs", result.instructions[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 12), result.instructions[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 3), result.instructions[0].upstream_loc.?.col);
    try std.testing.expect(result.instructions[1].upstream_loc == null);
    try std.testing.expect(result.instructions[2].upstream_loc != null);
    try std.testing.expectEqualStrings("up.rs", result.instructions[2].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 14), result.instructions[2].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 7), result.instructions[2].upstream_loc.?.col);
    try std.testing.expect(result.instructions[3].upstream_loc == null);
    try std.testing.expectEqual(@as(usize, result.instructions.len), result.loc_table.len);
    try std.testing.expect(result.loc_table[0] == null);
    try std.testing.expect(result.loc_table[1] == null);
    try std.testing.expect(result.loc_table[2] != null);
    try std.testing.expectEqualStrings("up.rs", result.loc_table[2].?.file);
    try std.testing.expect(result.loc_table[3] == null);
    try std.testing.expectEqualStrings("up.rs", result.function_sigs[0].upstream_loc.?.file);
    try std.testing.expectEqual(@as(u32, 12), result.function_sigs[0].upstream_loc.?.line);
    try std.testing.expectEqual(@as(u32, 3), result.function_sigs[0].upstream_loc.?.col);
}

test "flattenFile expands relative @import files" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.makePath("sa_std/io");
    var iface = try tmp.dir.createFile("sa_std/io/print.saasm-iface", .{ .truncate = true });
    try iface.writeAll("@extern sa_print_bytes(&msg: ptr, len: u64) -> void\n");
    iface.close();

    var main_file = try tmp.dir.createFile("main.saasm", .{ .truncate = true });
    try main_file.writeAll(
        \\@import "sa_std/io/print.saasm-iface"
        \\@main() -> i32:
        \\L_ENTRY:
        \\    return 0
    );
    main_file.close();

    const source = try tmp.dir.readFileAlloc(std.testing.allocator, "main.saasm", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tmp.dir.realpathAlloc(std.testing.allocator, "main.saasm");
    defer std.testing.allocator.free(source_path);

    var result = try flattenFile(std.testing.allocator, source_path, source);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), result.function_sigs.len);
    try std.testing.expectEqual(FunctionKind.external, result.function_sigs[0].kind);
    try std.testing.expectEqualStrings("sa_print_bytes", result.function_sigs[0].name);
    try std.testing.expectEqual(FunctionKind.normal, result.function_sigs[1].kind);
    try std.testing.expectEqualStrings("main", result.function_sigs[1].name);
}

test "flattenFile rejects import cycles" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    var a_file = try tmp.dir.createFile("a.saasm", .{ .truncate = true });
    try a_file.writeAll("@import \"b.saasm\"\n");
    a_file.close();

    var b_file = try tmp.dir.createFile("b.saasm", .{ .truncate = true });
    try b_file.writeAll("@import \"a.saasm\"\n");
    b_file.close();

    const source = try tmp.dir.readFileAlloc(std.testing.allocator, "a.saasm", 4096);
    defer std.testing.allocator.free(source);

    const source_path = try tmp.dir.realpathAlloc(std.testing.allocator, "a.saasm");
    defer std.testing.allocator.free(source_path);

    try std.testing.expectError(error.ImportCycle, flattenFile(std.testing.allocator, source_path, source));
}

test "macro PBT expands nested macros and repeat bodies deterministically" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6A10);
    const random = prng.random();

    for (0..48) |iter| {
        var program = try buildMacroPbtProgram(std.testing.allocator, random, iter);
        defer program.deinit(std.testing.allocator);

        var result = try flatten(std.testing.allocator, program.source);
        defer result.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 1), result.function_sigs.len);
        try std.testing.expectEqual(@as(usize, 0), result.const_decls.len);
        try std.testing.expectEqual(@as(usize, 4) + program.count, result.instructions.len);

        const base_id = result.symbols.findId(program.base_name) orelse return error.TestUnexpectedResult;
        const acc_id = result.symbols.findId(program.acc_name) orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(program.base_name, result.symbols.lookupName(base_id).?);
        try std.testing.expectEqualStrings(program.acc_name, result.symbols.lookupName(acc_id).?);

        try std.testing.expectEqual(InstKind.func_decl, result.instructions[0].kind);
        try std.testing.expectEqual(InstKind.alloc, result.instructions[1].kind);
        try std.testing.expectEqual(InstKind.op, result.instructions[2].kind);
        try std.testing.expectEqual(common_instruction.OpKind.add, result.instructions[2].op_kind.?);
        try std.testing.expectEqual(InstKind.return_, result.instructions[result.instructions.len - 1].kind);

        var line_buf: [128]u8 = undefined;
        var tmp_buf: [32]u8 = undefined;

        const alloc_line = try std.fmt.bufPrint(&line_buf, "    {s} = alloc {d}", .{ program.base_name, program.alloc_size });
        try expectRawText(result.instructions[1], alloc_line);
        try expectOperandReg(result.instructions[1], 0, base_id);
        try expectOperandImmU64(result.instructions[1], 1, program.alloc_size);

        const seed_line = try std.fmt.bufPrint(&line_buf, "    {s} = add {s}, 0", .{ program.acc_name, program.base_name });
        try expectRawText(result.instructions[2], seed_line);
        try expectOperandReg(result.instructions[2], 0, acc_id);
        try expectOperandReg(result.instructions[2], 1, base_id);
        try expectOperandImmI64(result.instructions[2], 2, 0);

        for (0..program.count) |idx| {
            const tmp_name = try std.fmt.bufPrint(&tmp_buf, "tmp_{d}", .{idx});
            const tmp_id = result.symbols.findId(tmp_name) orelse return error.TestUnexpectedResult;
            const inst = result.instructions[3 + idx];
            const expected_text = try std.fmt.bufPrint(&line_buf, "        {s} = add {s}, {d}", .{ tmp_name, program.acc_name, idx });
            try expectRawText(inst, expected_text);
            try std.testing.expectEqual(InstKind.op, inst.kind);
            try std.testing.expectEqual(common_instruction.OpKind.add, inst.op_kind.?);
            try expectOperandReg(inst, 0, tmp_id);
            try expectOperandReg(inst, 1, acc_id);
            try expectOperandImmI64(inst, 2, @intCast(idx));
        }

        const return_line = try std.fmt.bufPrint(&line_buf, "    return {s}", .{program.acc_name});
        try expectRawText(result.instructions[result.instructions.len - 1], return_line);
        try expectOperandReg(result.instructions[result.instructions.len - 1], 0, acc_id);
    }
}

test "macro PBT rejects invalid definitions and invocations" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6A11);
    const random = prng.random();

    for (0..36) |iter| {
        const case_id = random.intRangeLessThan(u8, 0, 6);
        const ghost_name = try std.fmt.allocPrint(std.testing.allocator, "ghost_{d}_{d}", .{ iter, random.intRangeAtMost(u16, 0, 9999) });
        defer std.testing.allocator.free(ghost_name);

        const source = switch (case_id) {
            0 => try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\EXPAND {s} value
                \\return 0
            , .{ghost_name}),
            1 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] SINGLE %x
                \\    %x = add 1, 0
                \\[END_MACRO]
                \\
                \\@main() -> i32:
                \\    EXPAND SINGLE value, extra
                \\    return 0
            , .{}),
            2 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] DUP %x
                \\    %x = add 1, 0
                \\[END_MACRO]
                \\[MACRO] DUP %x
                \\    %x = add 2, 0
                \\[END_MACRO]
                \\
                \\@main() -> i32:
                \\    return 0
            , .{}),
            3 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] OPEN %x
                \\    %x = add 1, 0
                \\
                \\@main() -> i32:
                \\    return 0
            , .{}),
            4 => try std.fmt.allocPrint(std.testing.allocator,
                \\@main() -> i32:
                \\[REP 2]
                \\    return 0
                \\return 0
            , .{}),
            5 => try std.fmt.allocPrint(std.testing.allocator,
                \\[MACRO] LOOP %x
                \\    EXPAND LOOP %x
                \\[END_MACRO]
                \\
                \\@main() -> i32:
                \\    EXPAND LOOP value
                \\    return 0
            , .{}),
            else => unreachable,
        };
        defer std.testing.allocator.free(source);

        const expected_error = switch (case_id) {
            0, 1 => error.InvalidMacroInvocation,
            2 => error.DuplicateDef,
            3 => error.UnbalancedMacro,
            4 => error.UnbalancedRep,
            5 => error.MacroRecursionLimit,
            else => unreachable,
        };
        try std.testing.expectError(expected_error, flatten(std.testing.allocator, source));
    }
}

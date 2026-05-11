const std = @import("std");

const def_dict = @import("flattener/def_dict.zig");
const classifier = @import("flattener/line_classifier.zig");
const forbidden = @import("flattener/forbidden.zig");
const symbol = @import("flattener/symbol.zig");
const common_instruction = @import("common/instruction.zig");
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

pub const FlattenResult = struct {
    instructions: []Instruction,
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

fn consumePendingLoc(
    loc_table: *std.ArrayList(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
) !?common_upstream.UpstreamLoc {
    const loc = pending_loc.*;
    try loc_table.append(loc);
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
        .borrow => .borrow,
        .move_ => .move_,
        .release => .release,
        .op => .op,
        .jmp => .jmp,
        .br => .br,
        .br_null => .br_null,
        .call => .call,
        .call_indirect => .call_indirect,
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
    function_sigs: *std.ArrayList(FunctionSig),
    owned_text: *std.ArrayList([]const u8),
) !void {
    const classified = classifier.classifyLine(raw_line);
    switch (classified.kind) {
        .blank_or_comment => {},
        .loc_hint => {
            const line_no = try std.fmt.parseInt(u32, classified.parts[1], 10);
            const col_no = try std.fmt.parseInt(u32, classified.parts[2], 10);
            try setPendingLoc(allocator, pending_loc, classified.parts[0], line_no, col_no);
        },
        .def => try dict.putExpression(classified.parts[0], classified.parts[1]),
        .native => {
            const inst_loc = try consumePendingLoc(loc_table, pending_loc);
            const raw_copy = try ownText(allocator, owned_text, raw_line);
            var inst = common_instruction.makeInstruction(.native, source_line, @intCast(instructions.items.len), inst_loc, raw_copy);
            inst.operands[0] = .{ .native_text = classified.parts[0] };
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
            if (pending_loc.*) |loc| {
                const file_copy = try allocator.dupe(u8, loc.file);
                sig.upstream_file = file_copy;
                sig.upstream_loc = .{
                    .file = file_copy,
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
            var inst = common_instruction.makeInstruction(inst_kind, source_line, @intCast(instructions.items.len), null, raw_copy);
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
                    const lhs = try symbols.intern(classified.parts[2]);
                    const rhs = try symbols.intern(classified.parts[3]);
                    inst.operands[0] = .{ .reg = dst };
                    const opcode: common_instruction.OpCode = if (std.mem.eql(u8, op_name, "add")) .add else if (std.mem.eql(u8, op_name, "sub")) .sub else if (std.mem.eql(u8, op_name, "mul")) .mul else if (std.mem.eql(u8, op_name, "div")) .div else if (std.mem.eql(u8, op_name, "gt")) .gt else if (std.mem.eql(u8, op_name, "lt")) .lt else if (std.mem.eql(u8, op_name, "eq")) .eq else if (std.mem.eql(u8, op_name, "ne")) .ne else if (std.mem.eql(u8, op_name, "and")) .@"and" else if (std.mem.eql(u8, op_name, "or")) .@"or" else if (std.mem.eql(u8, op_name, "shl")) .shl else .shr;
                    inst.operands[1] = .{ .op_code = opcode };
                    inst.operands[2] = .{ .reg = lhs };
                    inst.operands[3] = .{ .reg = rhs };
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
                    inst.operands[1] = .{ .symbol = try symbols.intern(true_text) };
                    inst.operands[2] = .{ .label = try symbols.intern(true_text) };

                    const false_text = try dict.foldText(allocator, classified.parts[2]);
                    try owned_text.append(false_text);
                    inst.operands[3] = .{ .symbol = try symbols.intern(false_text) };
                },
                .br_null => {
                    const reg_text = try dict.foldText(allocator, classified.parts[0]);
                    try owned_text.append(reg_text);
                    inst.operands[0] = .{ .reg = try symbols.intern(reg_text) };

                    const null_text = try dict.foldText(allocator, classified.parts[1]);
                    try owned_text.append(null_text);
                    inst.operands[1] = .{ .symbol = try symbols.intern(null_text) };
                    inst.operands[2] = .{ .label = try symbols.intern(null_text) };

                    const not_null_text = try dict.foldText(allocator, classified.parts[2]);
                    try owned_text.append(not_null_text);
                    inst.operands[3] = .{ .symbol = try symbols.intern(not_null_text) };
                },
                .call, .call_indirect, .panic, .panic_msg, .return_ => {
                    if (classified.inst_form == .return_ and classified.part_count == 1) {
                        const folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[0]);
                        if (symbols.findId(folded)) |id| {
                            inst.operands[0] = .{ .reg = id };
                        } else {
                            inst.operands[0] = .{ .text = folded };
                        }
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
) !void {
    var idx: usize = 0;
    while (idx < lines.len) : (idx += 1) {
        const line = lines[idx];
        switch (line.classified.kind) {
            .blank_or_comment, .def, .loc_hint, .native, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .instruction, .unknown, .expand, .rep_start, .rep_end, .macro_end => {},
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
    function_sigs: *std.ArrayList(FunctionSig),
    owned_text: *std.ArrayList([]const u8),
) !void {
    if (depth > 256) return error.MacroRecursionLimit;

    var idx = start;
    while (idx < end) : (idx += 1) {
        const line = lines[idx];
        const source_line = source_line_override orelse line.line_no;

        switch (line.classified.kind) {
            .blank_or_comment => {},
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
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, rendered, source_line, instructions, function_sigs, owned_text);
                } else {
                    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, line.text, source_line, instructions, function_sigs, owned_text);
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
                        function_sigs,
                        owned_text,
                    );
                }

                idx = rep_end;
            },
            .rep_end => return error.UnbalancedRep,
            .expand => {
                const def = macros.get(line.classified.parts[0]) orelse return error.InvalidMacroInvocation;
                const args = try parseTokenList(allocator, line.classified.parts[1]);
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
                    function_sigs,
                    owned_text,
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
        try table.append(item.upstream_loc);
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

pub fn findFirstForbiddenLine(source: []const u8) ?ForbiddenLine {
    var iterator = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iterator.next()) |raw_line| : (line_no += 1) {
        const classified = classifier.classifyLine(raw_line);
        if (classified.kind == .native) continue;
        if (forbidden.findForbiddenSyntax(raw_line)) |hit| {
            return .{ .line_no = line_no, .hit = hit };
        }
    }
    return null;
}

pub fn flatten(allocator: std.mem.Allocator, source: []const u8) !FlattenResult {
    if (findFirstForbiddenLine(source)) |_| {
        return error.ForbiddenSyntax;
    }

    var dict = DefDict.init(allocator);
    errdefer dict.deinit();
    var symbols = SymbolTable.init(allocator);
    errdefer symbols.deinit();
    var instructions = std.ArrayList(Instruction).init(allocator);
    errdefer instructions.deinit();
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

    const lines = try scanSource(allocator, source);
    defer allocator.free(lines);

    try collectMacroDefinitions(allocator, lines, &macros);
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
        &function_sigs,
        &owned_text,
    );
    if (pending_loc) |loc| {
        allocator.free(loc.file);
        pending_loc = null;
    }

    return .{
        .instructions = try instructions.toOwnedSlice(),
        .function_sigs = try function_sigs.toOwnedSlice(),
        .def_dict = dict,
        .symbols = symbols,
        .loc_table = try loc_table.toOwnedSlice(),
        .owned_text = try owned_text.toOwnedSlice(),
        .trap = null,
    };
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
    try std.testing.expect(result.instructions[0].upstream_loc == null);
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

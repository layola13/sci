const std = @import("std");
const sio = @import("sio");
const classifier = @import("line_classifier.zig");
const common_instruction = @import("../common/instruction.zig");
const common_const_decl = @import("../common/const_decl.zig");
const atomic = @import("../common/atomic.zig");
const common_signature = @import("../common/signature.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const ConstDecl = @import("../common/const_decl.zig").ConstDecl;
const DefDict = @import("def_dict.zig").DefDict;
const FunctionKind = @import("../common/signature.zig").FunctionKind;
const FunctionSig = @import("../common/signature.zig").FunctionSig;
const InstKind = @import("../common/instruction.zig").InstKind;
const Instruction = @import("../common/instruction.zig").Instruction;
const SymbolTable = @import("symbol.zig").SymbolTable;
const ErrorContext = @import("importexpansion.zig").ErrorContext;
const MacroDef = @import("importexpansion.zig").MacroDef;
const SourceLine = @import("importexpansion.zig").SourceLine;
const appendNullLoc = @import("renderwithtokenreplacements.zig").appendNullLoc;
const cloneOwnedSourceLines = @import("appendexpandedimportcachehit.zig").cloneOwnedSourceLines;
const consumePendingLoc = @import("renderwithtokenreplacements.zig").consumePendingLoc;
const deinitOwnedSourceLines = @import("appendexpandedimportcachehit.zig").deinitOwnedSourceLines;
const findBlockEnd = @import("renderwithtokenreplacements.zig").findBlockEnd;
const mapInstKind = @import("renderwithtokenreplacements.zig").mapInstKind;
const max_expanded_instructions = @import("importexpansion.zig").max_expanded_instructions;
const ownFoldedText = @import("renderwithtokenreplacements.zig").ownFoldedText;
const ownText = @import("renderwithtokenreplacements.zig").ownText;
const parseFunctionSigForKind = @import("renderwithtokenreplacements.zig").parseFunctionSigForKind;
const parseIntAllowLeadingPlus = @import("renderwithtokenreplacements.zig").parseIntAllowLeadingPlus;
const parseLayoutOffset = @import("renderwithtokenreplacements.zig").parseLayoutOffset;
const parseMacroParams = @import("appendexpandedimportcachehit.zig").parseMacroParams;
const recordErrorLine = @import("importexpansion.zig").recordErrorLine;
const resolveOperandText = @import("renderwithtokenreplacements.zig").resolveOperandText;
const resolveSizeOperandText = @import("renderwithtokenreplacements.zig").resolveSizeOperandText;
const setPendingLoc = @import("renderwithtokenreplacements.zig").setPendingLoc;
const stripLeadingPlus = @import("renderwithtokenreplacements.zig").stripLeadingPlus;
const takePendingLoc = @import("renderwithtokenreplacements.zig").takePendingLoc;
const unquoteString = @import("expandprintorformat.zig").unquoteString;


pub fn emitParsedLine(
    allocator: std.mem.Allocator,
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    raw_line: []const u8,
    source_line: u32,
    instructions: *std.array_list.Managed(Instruction),
    const_decls: *std.array_list.Managed(ConstDecl),
    function_sigs: *std.array_list.Managed(FunctionSig),
    owned_text: *std.array_list.Managed([]const u8),
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
) !void {
    if (instructions.items.len >= max_expanded_instructions) return error.MacroExpansionBudget;
    const classified = classifier.classifyLine(raw_line);
    switch (classified.kind) {
        .blank_or_comment, .version => {},
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
        .npm_bind => try dict.putNpmBind(classified.parts[0], classified.parts[1]),
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
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
            const kind = switch (classified.kind) {
                .func_decl => FunctionKind.normal,
                .ffi_wrapper_decl => FunctionKind.ffi_wrapper,
                .extern_decl => FunctionKind.external,
                .export_decl => FunctionKind.exported,
                .test_decl => FunctionKind.test_func,
                .gpu_decl => FunctionKind.gpu,
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
                .test_func => .test_decl,
                .gpu => .gpu_decl,
            };
            try appendNullLoc(loc_table);
            const raw_copy = try ownFoldedText(allocator, dict, owned_text, raw_line);
            var inst = common_instruction.makeInstruction(inst_kind, source_line, @intCast(instructions.items.len), inst_loc, raw_copy);
            if (current_package_identity) |identity| {
                inst.package_identity = try allocator.dupe(u8, identity);
            }
            inst.package_source_sha256 = current_package_hash;
            inst.operands[0] = .{ .symbol = name_id };
            inst.operands[1] = .{ .func = name_id };
            try instructions.append(inst);
            try function_sigs.append(sig);
        },
        .instruction => {
            const inst_kind = mapInstKind(classified.inst_form.?);
            const inst_loc = try consumePendingLoc(loc_table, pending_loc);
            const raw_copy = try ownFoldedText(allocator, dict, owned_text, raw_line);
            var inst = common_instruction.makeInstruction(inst_kind, source_line, @intCast(instructions.items.len), inst_loc, raw_copy);
            if (current_package_identity) |identity| {
                inst.package_identity = try allocator.dupe(u8, identity);
            }
            inst.package_source_sha256 = current_package_hash;
            switch (classified.inst_form.?) {
                .alloc => {
                    const dst = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = try resolveSizeOperandText(allocator, dict, owned_text, symbols, classified.parts[1]);
                },
                .va_start => {
                    const dst = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = dst };
                },
                .va_arg => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const ap = try symbols.intern(classified.parts[1]);
                    const ty = common_signature.parsePrimType(classified.parts[2]) catch return error.InvalidSyntax;
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = ap };
                    inst.operands[2] = .{ .ty = @intFromEnum(ty) };
                },
                .va_end => {
                    const ap = try symbols.intern(classified.parts[0]);
                    inst.operands[0] = .{ .reg = ap };
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
                    inst.operands[2] = .{ .imm_u64 = try parseLayoutOffset(allocator, dict, owned_text, current_package_identity, offset_text) };
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
                    inst.operands[1] = .{ .imm_u64 = try parseIntAllowLeadingPlus(u64, offset_text) };
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
                    inst.operands[3] = .{ .imm_u64 = try parseLayoutOffset(allocator, dict, owned_text, current_package_identity, offset_text) };
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
                    inst.operands[2] = .{ .imm_u64 = try parseLayoutOffset(allocator, dict, owned_text, current_package_identity, offset_text) };
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
                    inst.operands[1] = try resolveSizeOperandText(allocator, dict, owned_text, symbols, classified.parts[1]);
                },
                .load, .take => {
                    const dst = try symbols.intern(classified.parts[0]);
                    const base = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = dst };
                    inst.operands[1] = .{ .reg = base };
                    const offset_text = try ownFoldedText(allocator, dict, owned_text, classified.parts[2]);
                    inst.operands[2] = .{ .imm_u64 = try parseLayoutOffset(allocator, dict, owned_text, current_package_identity, offset_text) };
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
                .transfer => {
                    const container = try symbols.intern(classified.parts[0]);
                    const value = try symbols.intern(classified.parts[1]);
                    inst.operands[0] = .{ .reg = container };
                    inst.operands[1] = .{ .reg = value };
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
                    inst.operands[1] = .{ .imm_u64 = try parseLayoutOffset(allocator, dict, owned_text, current_package_identity, offset_text) };
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
                    if (std.fmt.parseInt(i64, stripLeadingPlus(offset_text), 10)) |offset| {
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
                    } else if (classified.inst_form == .call_indirect and classified.has_carried_sig and classified.part_count == 3) {
                        // C2 sab_carried_indirect_sig (dst form): the
                        // carried fn-pointer signature rides operands[3].
                        const dst = try symbols.intern(classified.parts[0]);
                        inst.operands[0] = .{ .reg = dst };
                        const folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[1]);
                        inst.operands[1] = .{ .text = folded };
                        const sig_folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[2]);
                        inst.operands[3] = .{ .text = sig_folded };
                    } else if (classified.inst_form == .call_indirect and classified.has_carried_sig and classified.part_count == 2) {
                        // C2 sab_carried_indirect_sig (no-dst form):
                        // operands[0] is the body, operands[3] the sig.
                        const folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[0]);
                        inst.operands[0] = .{ .text = folded };
                        const sig_folded = try ownFoldedText(allocator, dict, owned_text, classified.parts[1]);
                        inst.operands[3] = .{ .text = sig_folded };
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
                .unknown => {
                    std.debug.print("\n=== INVALID SYNTAX: .unknown inst at line {d}: '{s}' ===\n", .{ source_line, raw_line });
                    return error.InvalidSyntax;
                },
            }
            try instructions.append(inst);
        },
        .unknown => {
            std.debug.print("\n=== INVALID SYNTAX: .unknown line kind at line {d}: '{s}' ===\n", .{ source_line, raw_line });
            return error.InvalidSyntax;
        },
        .macro_start, .macro_end, .rep_start, .rep_end, .if_start, .else_, .if_end, .expand => return error.InvalidSyntax,
    }
}

pub fn includeFileAsConst(
    allocator: std.mem.Allocator,
    kind: enum { str, bytes },
    args: []const u8,
    source_line: u32,
    source_path: ?[]const u8,
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    instructions: *std.array_list.Managed(Instruction),
    const_decls: *std.array_list.Managed(ConstDecl),
    function_sigs: *std.array_list.Managed(FunctionSig),
    owned_text: *std.array_list.Managed([]const u8),
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
) !void {
    const path_arg = std.mem.trim(u8, args, " \t\r\n");
    if (path_arg.len == 0) return error.InvalidMacroInvocation;

    const include_path_raw = try unquoteString(allocator, path_arg);
    defer allocator.free(include_path_raw);

    const resolved_path = if (std.fs.path.isAbsolute(include_path_raw))
        try allocator.dupe(u8, include_path_raw)
    else if (source_path) |sp| blk: {
        const base = std.fs.path.dirname(sp) orelse ".";
        break :blk try std.fs.path.join(allocator, &.{ base, include_path_raw });
    } else try allocator.dupe(u8, include_path_raw);
    defer allocator.free(resolved_path);

    const file = try sio.cwd().openFile(resolved_path, .{});
    defer file.close();
    const bytes = try file.readToEndAlloc(allocator, 1 << 20);
    defer allocator.free(bytes);

    const const_name = try std.fmt.allocPrint(allocator, "__INCLUDE_{d}_{d}", .{ source_line, const_decls.items.len });
    defer allocator.free(const_name);

    var hex: ?std.array_list.Managed(u8) = null;
    const literal_line = switch (kind) {
        .str => try std.fmt.allocPrint(allocator, "@const {s} = utf8:\"{s}\"", .{ const_name, bytes }),
        .bytes => blk: {
            hex = std.array_list.Managed(u8).init(allocator);
            try hex.?.appendSlice("hex:");
            for (bytes) |b| {
                var hex_byte_buf: [4]u8 = undefined;
                try hex.?.appendSlice(try std.fmt.bufPrint(&hex_byte_buf, "\\x{X:0>2}", .{b}));
            }
            break :blk try std.fmt.allocPrint(allocator, "@const {s} = {s}", .{ const_name, hex.?.items });
        },
    };
    defer allocator.free(literal_line);

    try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, literal_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
    if (hex) |*h| h.deinit();
}

fn utf8ConstLine(allocator: std.mem.Allocator, name: []const u8, bytes: []const u8) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    try aw.writer.print("@const {s} = utf8:", .{name});
    try std.json.Stringify.value(bytes, .{}, &aw.writer);
    return try aw.toOwnedSlice();
}

pub fn expandSourceLocationMacro(
    allocator: std.mem.Allocator,
    macro_name: []const u8,
    args_text: []const u8,
    source_line: u32,
    source_path: ?[]const u8,
    dict: *DefDict,
    symbols: *SymbolTable,
    loc_table: *std.array_list.Managed(?common_upstream.UpstreamLoc),
    pending_loc: *?common_upstream.UpstreamLoc,
    instructions: *std.array_list.Managed(Instruction),
    const_decls: *std.array_list.Managed(ConstDecl),
    function_sigs: *std.array_list.Managed(FunctionSig),
    owned_text: *std.array_list.Managed([]const u8),
    current_package_identity: ?[]const u8,
    current_package_hash: ?[32]u8,
) !void {
    const out_reg = std.mem.trim(u8, args_text, " \t\r\n");
    if (out_reg.len == 0) return error.InvalidMacroInvocation;

    const loc = if (pending_loc.*) |item|
        item
    else if (loc_table.items.len != 0) blk: {
        if (loc_table.items[loc_table.items.len - 1]) |item| break :blk item;
        if (source_path) |sp| {
            break :blk common_upstream.UpstreamLoc{ .file = sp, .line = source_line, .col = 1 };
        }
        break :blk common_upstream.UpstreamLoc{ .file = "<unknown>", .line = source_line, .col = 1 };
    } else if (source_path) |sp|
        common_upstream.UpstreamLoc{ .file = sp, .line = source_line, .col = 1 }
    else
        common_upstream.UpstreamLoc{ .file = "<unknown>", .line = source_line, .col = 1 };

    if (std.mem.eql(u8, macro_name, "LINE!")) {
        const line_line = try std.fmt.allocPrint(allocator, "{s} = add 0, {d}", .{ out_reg, loc.line });
        defer allocator.free(line_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, line_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
        return;
    }

    if (std.mem.eql(u8, macro_name, "COLUMN!")) {
        const col_line = try std.fmt.allocPrint(allocator, "{s} = add 0, {d}", .{ out_reg, loc.col });
        defer allocator.free(col_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, col_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
        return;
    }

    if (std.mem.eql(u8, macro_name, "FILE!")) {
        const const_name = try std.fmt.allocPrint(allocator, "__SOURCE_FILE_{d}_{d}", .{ source_line, const_decls.items.len });
        defer allocator.free(const_name);

        const file_text = source_path orelse loc.file;
        const const_line = try utf8ConstLine(allocator, const_name, file_text);
        defer allocator.free(const_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

        const ptr_line = try std.fmt.allocPrint(allocator, "{s} = add 0, 0", .{out_reg});
        defer allocator.free(ptr_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, ptr_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

        const assign_line = try std.fmt.allocPrint(allocator, "{s} = ^{s}", .{ out_reg, const_name });
        defer allocator.free(assign_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, assign_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
        return;
    }

    if (std.mem.eql(u8, macro_name, "MODULE_PATH!")) {
        const module_path = source_path orelse loc.file;
        const const_name = try std.fmt.allocPrint(allocator, "__MODULE_PATH_{d}_{d}", .{ source_line, const_decls.items.len });
        defer allocator.free(const_name);

        const const_line = try utf8ConstLine(allocator, const_name, module_path);
        defer allocator.free(const_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, const_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);

        const assign_line = try std.fmt.allocPrint(allocator, "{s} = ^{s}", .{ out_reg, const_name });
        defer allocator.free(assign_line);
        try emitParsedLine(allocator, dict, symbols, loc_table, pending_loc, assign_line, source_line, instructions, const_decls, function_sigs, owned_text, current_package_identity, current_package_hash);
        return;
    }

    return error.InvalidMacroInvocation;
}

pub fn collectMacroDefinitions(
    allocator: std.mem.Allocator,
    lines: []const SourceLine,
    macros: *std.StringHashMap(MacroDef),
    error_ctx: ?*ErrorContext,
) !void {
    var idx: usize = 0;
    while (idx < lines.len) : (idx += 1) {
        const line = lines[idx];
        recordErrorLine(error_ctx, line, line.line_no);
        switch (line.classified.kind) {
            .blank_or_comment, .def, .npm_bind, .const_decl, .import_decl, .version, .loc_hint, .native, .label, .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl, .instruction, .unknown, .expand, .rep_start, .rep_end, .if_start, .else_, .if_end, .macro_end => {},
            .macro_start => {
                const end = findBlockEnd(lines, idx + 1, .macro_end) orelse return error.UnbalancedMacro;
                const name = line.classified.parts[0];
                const parsed_params = try parseMacroParams(allocator, line.classified.parts[1]);
                errdefer allocator.free(parsed_params.params);
                if (macros.contains(name)) return error.DuplicateDef;
                const owned_body_lines = try cloneOwnedSourceLines(allocator, lines[idx + 1 .. end]);
                errdefer deinitOwnedSourceLines(allocator, owned_body_lines);
                try macros.put(name, .{
                    .params = parsed_params.params,
                    .variadic_param = parsed_params.variadic_param,
                    .body_start = idx + 1,
                    .body_end = end,
                    .owned_body_lines = owned_body_lines,
                });
                idx = end;
            },
        }
    }
}

pub fn isFunctionSigDeclared(sigs: []const FunctionSig, name: []const u8) bool {
    for (sigs) |sig| {
        if (std.mem.eql(u8, sig.name, name)) return true;
    }
    return false;
}

const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const call = @import("../referee/call.zig");
const cap = @import("../common/capability.zig");
const atomic = @import("../common/atomic.zig");
const gas = @import("../common/gas.zig");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const pkg_manifest = @import("../pkg/manifest.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const upstream = @import("../common/upstream_loc.zig");
const classifier = @import("../flattener/line_classifier.zig");
const symbol = @import("../flattener/symbol.zig");

const CollectResult = @import("reg_state_change.zig").CollectResult;
const InteriorContext = @import("reg_state_change.zig").InteriorContext;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const addScopeReg = @import("sax_trap_report.zig").addScopeReg;
const addTextReferencedConsts = @import("sax_trap_report.zig").addTextReferencedConsts;
const clearAllocSizeMeta = @import("snapshot_merge_state_in_scope.zig").clearAllocSizeMeta;
const clearBorrowCtx = @import("clear_borrow_ctx.zig").clearBorrowCtx;
const clearInteriorNode = @import("snapshot_merge_state_in_scope.zig").clearInteriorNode;
const clearInteriorOffsetMeta = @import("snapshot_merge_state_in_scope.zig").clearInteriorOffsetMeta;
const collectConstVtables = @import("const_trap.zig").collectConstVtables;
const constTrap = @import("const_trap.zig").constTrap;
const consumeInteriorValue = @import("snapshot_merge_state_in_scope.zig").consumeInteriorValue;
const finalizeFunctionScope = @import("sax_trap_report.zig").finalizeFunctionScope;
const freeSigs = @import("clear_borrow_ctx.zig").freeSigs;
const hasInteriorPtr = @import("const_trap.zig").hasInteriorPtr;
const hasInteriorTree = @import("const_trap.zig").hasInteriorTree;
const isConstData = @import("reg_state_change.zig").isConstData;
const isDecl = @import("const_trap.zig").isDecl;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const isImmutableConst = @import("reg_state_change.zig").isImmutableConst;
const maskOf = @import("reg_state_change.zig").maskOf;
const parseDeclKind = @import("sax_trap_report.zig").parseDeclKind;
const parseInstructionCallForVerifier = @import("sax_trap_report.zig").parseInstructionCallForVerifier;
const regFlagBranchCondition = @import("reg_state_change.zig").regFlagBranchCondition;
const regFlagEphemeralScalar = @import("reg_state_change.zig").regFlagEphemeralScalar;
const regFlagRawPointer = @import("reg_state_change.zig").regFlagRawPointer;
const regFlagStackAlloc = @import("reg_state_change.zig").regFlagStackAlloc;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;

pub fn collectMetadata(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    classified_lines: []const classifier.ClassifiedLine,
    const_decls: []const const_decl.ConstDecl,
) !CollectResult {
    std.debug.assert(classified_lines.len == instructions.len);
    var symbols = symbol.SymbolTable.init(allocator);
    errdefer symbols.deinit();

    var sigs = std.array_list.Managed(sig.FunctionSig).init(allocator);
    errdefer {
        for (sigs.items) |*item| item.deinit(allocator);
        sigs.deinit();
    }
    var sig_index_by_name = std.StringHashMap(usize).init(allocator);
    errdefer sig_index_by_name.deinit();
    var function_starts = std.array_list.Managed(usize).init(allocator);
    errdefer function_starts.deinit();
    var current_reg_ids = std.array_list.Managed(u32).init(allocator);
    defer current_reg_ids.deinit();
    var current_reg_seen = std.AutoHashMap(u32, void).init(allocator);
    defer current_reg_seen.deinit();
    var current_sig_index: usize = 0;

    // Demand-driven const scoping: const names, built once (never per
    // function -- rebuilding per function would reintroduce O(F x C)).
    var const_names = std.StringHashMap(void).init(allocator);
    defer const_names.deinit();
    for (const_decls) |decl| {
        if (decl.name.len != 0) try const_names.put(decl.name, {});
    }

    var const_idx: usize = 0;
    for (instructions, 0..) |item, inst_idx| {
        while (const_idx < const_decls.len and const_decls[const_idx].expanded_line <= item.expanded_line) {
            const decl = const_decls[const_idx];
            if (decl.name.len != 0) {
                _ = try symbols.intern(decl.name);
            }
            const_idx += 1;
        }

        const classified = classified_lines[inst_idx];

        if (isDecl(item.kind)) {
            const kind = parseDeclKind(item.kind).?;
            if (sigs.items.len != 0 and current_sig_index < sigs.items.len) {
                try finalizeFunctionScope(&sigs, &current_reg_ids);
            }
            current_reg_ids.clearRetainingCapacity();
            current_reg_seen.clearRetainingCapacity();
            var parsed = sig.parseFunctionHeader(allocator, item.raw_text, @intCast(sigs.items.len), item.expanded_line, kind) catch |err| {
                return switch (err) {
                    sig.ParseError.UnsupportedType => error.UnsupportedType,
                    else => error.InvalidFunctionSig,
                };
            };
            errdefer parsed.deinit(allocator);

            // Validate @test function signatures: must be () -> void
            if (kind == .test_func) {
                if (parsed.params.len != 0) {
                    return error.TestFuncSignatureMismatch;
                }
                if (parsed.return_ty != .void) {
                    return error.TestFuncSignatureMismatch;
                }
            }

            if (item.upstream_loc) |loc| {
                const file_copy = try allocator.dupe(u8, loc.file);
                errdefer allocator.free(file_copy);
                parsed.upstream_file = file_copy;
                parsed.upstream_loc = .{
                    .file = file_copy,
                    .line = loc.line,
                    .col = loc.col,
                };
            }
            if (parsed.params.len != 0) {
                const ids = try allocator.alloc(u32, parsed.params.len);
                errdefer allocator.free(ids);
                for (parsed.params, 0..) |param, idx| {
                    ids[idx] = try symbols.intern(param.name);
                    try addScopeReg(&current_reg_ids, &current_reg_seen, ids[idx]);
                }
                parsed.param_ids = ids;
            }
            _ = try symbols.intern(parsed.name);
            try sigs.append(parsed);
            const inserted_idx = sigs.items.len - 1;
            if (!sig_index_by_name.contains(parsed.name)) {
                try sig_index_by_name.put(parsed.name, inserted_idx);
            }
            try function_starts.append(inst_idx);
            current_sig_index = sigs.items.len - 1;
            continue;
        }

        for (item.operands) |operand| {
            if (operand == .reg) {
                try addScopeReg(&current_reg_ids, &current_reg_seen, operand.reg);
            }
        }
        try addTextReferencedConsts(item.raw_text, &const_names, &symbols, &current_reg_ids, &current_reg_seen);

        if (parseInstructionCallForVerifier(allocator, &symbols, item)) |parsed0| {
            var parsed = parsed0;
            defer parsed.deinit(allocator);
            if (parsed.dest) |dest| {
                if (isIdentLike(dest)) {
                    if (symbols.findId(dest)) |id| {
                        try addScopeReg(&current_reg_ids, &current_reg_seen, id);
                    }
                }
            }
        } else |_| {}

        switch (item.kind) {
            .label => {
                _ = try symbols.intern(classified.parts[0]);
            },
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => unreachable,
            .alloc, .stack_alloc => {
                _ = try symbols.intern(classified.parts[0]);
            },
            .va_start => {
                _ = try symbols.intern(classified.parts[0]);
            },
            .va_arg => {
                _ = try symbols.intern(classified.parts[0]);
                _ = try symbols.intern(classified.parts[1]);
            },
            .va_end => {
                _ = try symbols.intern(classified.parts[0]);
            },
            .move_, .release, .raw_cast, .assume_safe, .assume_borrow, .transfer => {
                _ = try symbols.intern(classified.parts[0]);
                if (classified.part_count > 1 and isIdentLike(classified.parts[1])) {
                    _ = try symbols.intern(classified.parts[1]);
                }
                if (classified.part_count > 2 and isIdentLike(classified.parts[2])) {
                    _ = try symbols.intern(classified.parts[2]);
                }
            },
            .assign => {
                _ = try symbols.intern(classified.parts[0]);
                if (item.operands[1] == .reg) {
                    _ = try symbols.intern(classified.parts[1]);
                }
            },
            .load, .take => {
                _ = try symbols.intern(classified.parts[0]);
                if (item.operands[1] == .reg) {
                    _ = try symbols.intern(classified.parts[1]);
                }
            },
            .ptr_add => {
                _ = try symbols.intern(classified.parts[0]);
                if (item.operands[1] == .reg) {
                    _ = try symbols.intern(classified.parts[1]);
                }
            },
            .atomic_load => {
                const parsed = try atomic.parseLoad(item.raw_text);
                _ = try symbols.intern(parsed.dst);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
            },
            .atomic_store => {
                const parsed = try atomic.parseStore(item.raw_text);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
            },
            .cmpxchg => {
                const parsed = try atomic.parseCmpxchg(item.raw_text);
                _ = try symbols.intern(parsed.dst);
                _ = try symbols.intern(parsed.ok);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
            },
            .atomic_rmw => {
                const parsed = try atomic.parseRmw(item.raw_text);
                _ = try symbols.intern(parsed.dst);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
            },
            .fence => {},
            .borrow => {
                _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
            },
            .store => {
                _ = try symbols.intern(classified.parts[0]);
                if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    _ = try symbols.intern(classified.parts[2]);
                }
            },
            .op => {
                _ = try symbols.intern(classified.parts[0]);
                inline for ([_]usize{ 1, 2, 3 }) |op_idx| {
                    if (op_idx >= item.operands.len) break;
                    const part_idx = op_idx + 1;
                    if (part_idx >= classified.part_count) break;
                    switch (item.operands[op_idx]) {
                        .reg => _ = try symbols.intern(classified.parts[part_idx]),
                        .text => |text| {
                            if (isIdentLike(text)) _ = try symbols.intern(classified.parts[part_idx]);
                        },
                        else => {},
                    }
                }
            },
            .jmp => {
                _ = try symbols.intern(classified.parts[0]);
            },
            .br, .br_null => {
                if (isIdentLike(classified.parts[0])) _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[1])) _ = try symbols.intern(classified.parts[1]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
            },
            .try_, .early_return => {
                if (classified.part_count > 0 and isIdentLike(classified.parts[0])) _ = try symbols.intern(classified.parts[0]);
                if (classified.part_count > 1 and isIdentLike(classified.parts[1])) _ = try symbols.intern(classified.parts[1]);
            },
            .call, .call_indirect, .panic, .panic_msg, .return_, .native => {
                if (parseInstructionCallForVerifier(allocator, &symbols, item)) |parsed0| {
                    var parsed = parsed0;
                    defer parsed.deinit(allocator);
                    if (parsed.dest) |dest| {
                        if (isIdentLike(dest)) _ = try symbols.intern(dest);
                    }
                } else |_| {}
            },
        }
    }

    while (const_idx < const_decls.len) {
        const decl = const_decls[const_idx];
        if (decl.name.len != 0) {
            _ = try symbols.intern(decl.name);
        }
        const_idx += 1;
    }

    if (sigs.items.len != 0) {
        try finalizeFunctionScope(&sigs, &current_reg_ids);
    }

    var const_ids = std.AutoHashMap(u32, void).init(allocator);
    errdefer const_ids.deinit();
    for (const_decls) |decl| {
        if (decl.name.len != 0) {
            const id = symbols.findId(decl.name) orelse try symbols.intern(decl.name);
            try const_ids.put(id, {});
        }
    }
    return .{
        .symbols = symbols,
        .sigs = sigs,
        .sig_index_by_name = sig_index_by_name,
        .const_vtables = try collectConstVtables(allocator, const_decls, sigs.items, &sig_index_by_name),
        .function_starts = function_starts,
        .const_ids = const_ids,
    };
}

pub fn clonePredecodedFunctionSig(allocator: std.mem.Allocator, source: sig.FunctionSig) !sig.FunctionSig {
    const name = try allocator.dupe(u8, source.name);
    errdefer allocator.free(name);

    const params = try allocator.alloc(sig.ParamSpec, source.params.len);
    errdefer allocator.free(params);
    var param_initialized: usize = 0;
    errdefer for (params[0..param_initialized]) |param| allocator.free(param.name);
    for (source.params, 0..) |param, idx| {
        params[idx] = .{
            .name = try allocator.dupe(u8, param.name),
            .ty = param.ty,
            .cap = param.cap,
        };
        param_initialized += 1;
    }

    const param_ids = if (source.param_ids.len == 0) &.{} else try allocator.dupe(u32, source.param_ids);
    errdefer if (param_ids.len != 0) allocator.free(param_ids);
    const reg_ids = if (source.reg_ids.len == 0) &.{} else try allocator.dupe(u32, source.reg_ids);
    errdefer if (reg_ids.len != 0) allocator.free(reg_ids);

    const upstream_file = if (source.upstream_file) |file| try allocator.dupe(u8, file) else null;
    errdefer if (upstream_file) |file| allocator.free(file);
    var upstream_loc: ?upstream.UpstreamLoc = null;
    errdefer if (upstream_loc) |loc| allocator.free(loc.file);
    if (source.upstream_loc) |loc| {
        upstream_loc = .{ .file = try allocator.dupe(u8, loc.file), .line = loc.line, .col = loc.col };
    }
    const llvm_name = if (source.llvm_name) |nm| try allocator.dupe(u8, nm) else null;
    errdefer if (llvm_name) |nm| allocator.free(nm);

    return .{
        .id = source.id,
        .name = name,
        .params = params,
        .kind = source.kind,
        .return_cap = source.return_cap,
        .return_ty = source.return_ty,
        .return_fallible = source.return_fallible,
        .entry_inst_idx = source.entry_inst_idx,
        .is_ffi_wrapper = source.is_ffi_wrapper,
        .param_ids = param_ids,
        .reg_ids = reg_ids,
        .upstream_file = upstream_file,
        .upstream_loc = upstream_loc,
        .llvm_name = llvm_name,
        .ignored = source.ignored,
        .should_panic = source.should_panic,
        .is_variadic = source.is_variadic,
    };
}

pub fn collectPredecodedMetadata(
    allocator: std.mem.Allocator,
    symbol_names: []const []const u8,
    function_sigs: []const sig.FunctionSig,
    const_decls: []const const_decl.ConstDecl,
) !CollectResult {
    var symbols = symbol.SymbolTable.init(allocator);
    errdefer symbols.deinit();
    for (symbol_names) |name| _ = try symbols.intern(name);

    var sigs = std.array_list.Managed(sig.FunctionSig).init(allocator);
    errdefer freeSigs(allocator, &sigs);
    var sig_index_by_name = std.StringHashMap(usize).init(allocator);
    errdefer sig_index_by_name.deinit();
    var function_starts = std.array_list.Managed(usize).init(allocator);
    errdefer function_starts.deinit();

    for (function_sigs) |source| {
        var cloned = try clonePredecodedFunctionSig(allocator, source);
        errdefer cloned.deinit(allocator);
        try sigs.append(cloned);
        const idx = sigs.items.len - 1;
        if (!sig_index_by_name.contains(cloned.name)) {
            try sig_index_by_name.put(cloned.name, idx);
        }
        try function_starts.append(cloned.entry_inst_idx);
    }

    var const_ids = std.AutoHashMap(u32, void).init(allocator);
    errdefer const_ids.deinit();
    for (const_decls) |decl| {
        if (decl.name.len != 0) {
            const id = symbols.findId(decl.name) orelse try symbols.intern(decl.name);
            try const_ids.put(id, {});
        }
    }
    return .{
        .symbols = symbols,
        .sigs = sigs,
        .sig_index_by_name = sig_index_by_name,
        .const_vtables = try collectConstVtables(allocator, const_decls, sigs.items, &sig_index_by_name),
        .function_starts = function_starts,
        .const_ids = const_ids,
    };
}

pub fn metadataTrapKind(err: anyerror) trap.Trap {
    return switch (err) {
        error.UnsupportedType => .unsupported_type,
        error.OutOfMemory => .arena_oom,
        error.TestFuncSignatureMismatch => .test_func_signature_mismatch,
        error.InvalidAtomicOrdering => .invalid_atomic_ordering,
        error.InvalidFunctionSig, error.InvalidAtomicSyntax => .forbidden_syntax,
        else => .import_resolution_failed,
    };
}

pub fn metadataTrapMessage(err: anyerror) []const u8 {
    return switch (err) {
        error.UnsupportedType => "unsupported type annotation while rebuilding metadata",
        error.OutOfMemory => "out of memory while rebuilding metadata",
        error.TestFuncSignatureMismatch => "@test function must have signature () -> void",
        error.InvalidAtomicOrdering => "invalid atomic ordering while rebuilding metadata",
        error.InvalidFunctionSig => "invalid function signature while rebuilding metadata",
        error.InvalidAtomicSyntax => "invalid atomic syntax while rebuilding metadata",
        else => "unclassified metadata rebuild error",
    };
}

pub fn metadataTrapHint(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.UnsupportedType => "check primitive type names in signatures and atomic suffixes",
        error.TestFuncSignatureMismatch => "test functions cannot have parameters and must return void",
        error.InvalidAtomicOrdering => "check success/failure ordering pairs and atomic ordering suffixes",
        error.InvalidFunctionSig => "check declaration spelling, parentheses, parameters, return arrow, and trailing colon",
        error.InvalidAtomicSyntax => "check atomic instruction spelling, destination registers, address, value, and ordering fields",
        error.OutOfMemory => null,
        else => "metadata collection returned an unclassified error; inspect the declaration or instruction at this source location",
    };
}

pub fn isStackAllocated(flags: []const u8, origins: []const ?u32, state: []const u16, id: u32) bool {
    const idx: usize = @intCast(id);
    if ((flags[idx] & regFlagStackAlloc) != 0) return true;
    if ((state[idx] & maskOf(.borrow_view)) != 0) {
        if (origins[idx]) |origin| {
            const origin_idx: usize = @intCast(origin);
            if (origin_idx >= flags.len) return false;
            return (flags[origin_idx] & regFlagStackAlloc) != 0;
        }
    }
    return false;
}

pub fn readCheck(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
) ?VerifyBodyResult {
    _ = flags;
    const idx: usize = @intCast(id);
    const current = state[idx];
    if (current == 0) return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
    if ((current & maskOf(.consumed)) != 0) return trapReport(.use_after_move, item, function_text, is_ffi_wrapper, name, maskOf(.consumed), current, "moved value is no longer usable", null);
    if ((current & maskOf(.locked_mut)) != 0 and (current & maskOf(.borrow_view)) == 0) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "borrow rules reject this access", null);
    }
    return null;
}

pub fn writeCheck(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
) ?VerifyBodyResult {
    const idx: usize = @intCast(id);
    const current = state[idx];
    if (current == 0) return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
    if ((current & maskOf(.consumed)) != 0) return trapReport(.use_after_move, item, function_text, is_ffi_wrapper, name, maskOf(.consumed), current, "moved value is no longer usable", null);
    if (isImmutableConst(state, flags, id)) {
        // An exclusive borrow grants write access to an immutable binding
        // (the Rust `&mut` grant); const data never receives that grant.
        const exclusive_borrow = (current & maskOf(.locked_mut)) != 0;
        if (!exclusive_borrow or isConstData(flags, id)) {
            return constTrap(item, function_text, is_ffi_wrapper, name, current, "immutable registers cannot be written, moved, or exclusively borrowed");
        }
    }
    if ((current & maskOf(.borrow_view)) != 0) {
        const origin_id = origins[idx] orelse return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "borrow rules reject this access", null);
        const origin_idx: usize = @intCast(origin_id);
        if (origin_idx >= locks.len) return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
        if (locks[origin_idx] > 1) {
            return trapReport(.read_write_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "cannot write through a shared borrow", null);
        }
    } else if ((current & maskOf(.locked_read)) != 0) {
        return trapReport(.read_write_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "cannot write through a shared borrow", null);
    }
    if ((current & maskOf(.locked_mut)) != 0 and (current & maskOf(.borrow_view)) == 0) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "borrow rules reject this access", null);
    }
    return null;
}

pub fn assignValueCtx(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    mask: u16,
    interior: *InteriorContext,
) ?VerifyBodyResult {
    const idx: usize = @intCast(id);
    if (idx >= state.len) {
        return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
    }
    const current = state[idx];
    if (current != 0 and (current & maskOf(.consumed)) == 0 and (current & maskOf(.untracked)) == 0 and (flags[idx] & regFlagEphemeralScalar) == 0 and (flags[idx] & regFlagRawPointer) == 0) {
        return trapReport(.register_redefinition, item, function_text, is_ffi_wrapper, name, null, null, "register is already live", null);
    }
    if (hasInteriorPtr(current) or interior.interior_first_child[idx] != null) {
        consumeInteriorValue(interior.state, interior.interior_parent, interior.interior_first_child, interior.interior_next_sibling, id);
    } else {
        clearInteriorNode(interior.state, interior.interior_parent, interior.interior_first_child, interior.interior_next_sibling, id);
    }
    clearInteriorOffsetMeta(interior, id);
    clearAllocSizeMeta(interior, id);
    state[idx] = mask;
    flags[idx] &= ~(regFlagBranchCondition | regFlagEphemeralScalar);
    return null;
}

pub fn assignValue(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    mask: u16,
    interior: *InteriorContext,
) ?VerifyBodyResult {
    return assignValueCtx(item, function_text, is_ffi_wrapper, name, id, state, flags, mask, interior);
}

pub fn consumeSourceValueCtx(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    allow_const_copy: bool,
    interior: *InteriorContext,
) ?VerifyBodyResult {
    const idx: usize = @intCast(id);
    if (allow_const_copy and isImmutableConst(state, flags, id)) return null;
    if (isConstData(flags, id)) {
        return constTrap(item, function_text, is_ffi_wrapper, name, state[idx], "immutable registers cannot be moved");
    }
    if (isStackAllocated(flags, origins, state, id)) {
        return trapReport(.stack_escape, item, function_text, is_ffi_wrapper, name, maskOf(.active), state[idx], "stack allocation cannot be moved out of its function", null);
    }
    if ((flags[idx] & regFlagRawPointer) != 0) return null;
    // VERIFIER-BFULL (G4): scalars are freely copyable — assigning,
    // moving or transferring a scalar must not consume the source
    // (`y = x; z = x` and `f(x); g(x)` stay legal). Untracked values
    // (op results, raw casts) carry no obligation either and are
    // equally copyable. Borrow views never carry the ephemeral flag
    // (setBorrowState clears flags), so this cannot swallow a borrow.
    if ((flags[idx] & regFlagEphemeralScalar) != 0) return null;
    if ((state[idx] & maskOf(.untracked)) != 0) return null;
    if ((state[idx] & maskOf(.borrow_view)) != 0) {
        clearBorrowCtx(state, flags, origins, locks, id, interior);
    } else {
        if (hasInteriorTree(state, interior_first_child, id)) {
            consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, id);
        } else {
            state[idx] = maskOf(.consumed);
        }
    }
    return null;
}

pub fn consumeSourceValue(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    allow_const_copy: bool,
    interior: *InteriorContext,
) ?VerifyBodyResult {
    return consumeSourceValueCtx(item, function_text, is_ffi_wrapper, name, id, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling, allow_const_copy, interior);
}

pub fn setBorrowState(state: []u16, flags: []u8, origins: []?u32, locks: []u16, dst: u32, src: u32, is_mut: bool, is_ffi: bool) void {
    const dst_idx: usize = @intCast(dst);
    const src_idx: usize = @intCast(src);
    state[dst_idx] = maskOf(.active) | maskOf(.borrow_view) | (if (is_ffi) (if (is_mut) maskOf(.locked_mut) else maskOf(.locked_read)) | maskOf(.ffi_borrow) else 0);
    flags[dst_idx] = if (is_ffi) 0x01 else 0x00;
    origins[dst_idx] = src;
    locks[src_idx] += 1;
    // The immutable bit survives the borrow: an immutable binding stays
    // immutable after the exclusive borrow is released. Const data keeps its
    // historic behaviour and is never locked by a borrow.
    const src_immutable = if (isConstData(flags, src)) 0 else (state[src_idx] & maskOf(.immutable));
    if (src_immutable == 0 and state[src_idx] != maskOf(.active)) return;
    state[src_idx] = (if (is_mut) maskOf(.locked_mut) else maskOf(.locked_read)) | src_immutable;
}

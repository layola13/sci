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

const FunctionRegScope = @import("reg_state_change.zig").FunctionRegScope;
const SaxValidationContext = @import("reg_state_change.zig").SaxValidationContext;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const collectMetadata = @import("collect_metadata.zig").collectMetadata;
const copyTextBuf = @import("reg_state_change.zig").copyTextBuf;
const isDecl = @import("const_trap.zig").isDecl;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const maskOf = @import("reg_state_change.zig").maskOf;
const operandDebugName = @import("reg_state_change.zig").operandDebugName;
const trapCode = @import("reg_state_change.zig").trapCode;
const trapReport = @import("snapshot_merge_state_in_scope.zig").trapReport;
const trimTrailingCr = @import("reg_state_change.zig").trimTrailingCr;
const verifyBody = @import("verify_body.zig").verifyBody;

pub fn saxTrapReport(
    kind: trap.Trap,
    item: inst.Instruction,
    component_name: []const u8,
    register: ?[]const u8,
    expected_mask: ?u16,
    actual_mask: ?u16,
    message: []const u8,
    hint: ?[]const u8,
) VerifyBodyResult {
    var report: trap.TrapReport = .{
        .trap = kind,
        .trap_code = trapCode(kind),
        .line = item.expanded_line + 1,
        .source_line = item.source_line,
        .source_text_buf = std.mem.zeroes([256]u8),
        .original_text_buf = std.mem.zeroes([256]u8),
        .source_text = null,
        .original_text = null,
        .register = null,
        .registers = &.{},
        .expected_mask = expected_mask,
        .actual_mask = actual_mask,
        .expected_mask_name = if (expected_mask) |v| cap.maskName(v) else null,
        .actual_mask_name = if (actual_mask) |v| cap.maskName(v) else null,
        .upstream_loc = item.upstream_loc,
        .upstream_file_buf = std.mem.zeroes([128]u8),
        .upstream_line = if (item.upstream_loc) |loc| loc.line else 0,
        .upstream_col = if (item.upstream_loc) |loc| loc.col else 0,
        .function = null,
        .is_ffi_wrapper = null,
        .message = message,
        .hint = hint,
    };
    copyTextBuf(&report.source_text_buf, trimTrailingCr(item.raw_text));
    copyTextBuf(&report.original_text_buf, trimTrailingCr(item.raw_text));
    copyTextBuf(&report.function_buf, component_name);
    if (register) |value| {
        const len = @min(report.register_buf.len, value.len);
        std.mem.copyForwards(u8, report.register_buf[0..len], value[0..len]);
    }
    if (report.upstream_loc) |loc| {
        const len = @min(report.upstream_file_buf.len, loc.file.len);
        std.mem.copyForwards(u8, report.upstream_file_buf[0..len], loc.file[0..len]);
        report.upstream_loc = null;
    }
    return .{ .trap = report };
}

pub fn saxReport(
    ctx: SaxValidationContext,
    kind: trap.Trap,
    item: inst.Instruction,
    register: ?[]const u8,
    expected_mask: ?u16,
    actual_mask: ?u16,
    message: []const u8,
    hint: ?[]const u8,
) VerifyBodyResult {
    return saxTrapReport(kind, item, ctx.component_name, register, expected_mask, actual_mask, message, hint);
}

pub fn trapReportFromText(
    kind: trap.Trap,
    line: u32,
    source_line: u32,
    raw_text: []const u8,
    message: []const u8,
    hint: ?[]const u8,
) trap.TrapReport {
    var report: trap.TrapReport = .{
        .trap = kind,
        .trap_code = trapCode(kind),
        .line = line,
        .source_line = source_line,
        .source_text_buf = std.mem.zeroes([256]u8),
        .original_text_buf = std.mem.zeroes([256]u8),
        .source_text = null,
        .original_text = null,
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = null,
        .expected_mask_name = null,
        .actual_mask_name = null,
        .upstream_loc = null,
        .upstream_file_buf = std.mem.zeroes([128]u8),
        .upstream_line = 0,
        .upstream_col = 0,
        .function = null,
        .is_ffi_wrapper = null,
        .message = message,
        .hint = hint,
    };
    const text = trimTrailingCr(raw_text);
    copyTextBuf(&report.source_text_buf, text);
    copyTextBuf(&report.original_text_buf, text);
    return report;
}

pub fn builtinArgSpec(name: []const u8) ?[]const inst.CapPrefix {
    if (std.mem.eql(u8, name, "panic")) return &.{.by_value};
    if (std.mem.eql(u8, name, "panic_msg")) return &.{ .by_value, .raw, .by_value };
    if (std.mem.eql(u8, name, "sys_print")) return &.{ .raw, .by_value };
    if (std.mem.eql(u8, name, "sys_read_file")) return &.{ .raw, .by_value, .raw };
    if (std.mem.eql(u8, name, "sys_write_file")) return &.{ .raw, .by_value, .raw, .by_value };
    if (std.mem.eql(u8, name, "sys_exit")) return &.{.by_value};
    if (std.mem.eql(u8, name, "sys_argv")) return &.{.by_value};
    if (std.mem.eql(u8, name, "sys_argc")) return &.{};
    return null;
}

pub fn builtinGrantRequirement(name: []const u8) ?pkg_manifest.Capability {
    if (std.mem.eql(u8, name, "sys_print")) return .io_write;
    if (std.mem.eql(u8, name, "sys_read_file")) return .io_read;
    if (std.mem.eql(u8, name, "sys_write_file")) return .io_write;
    if (std.mem.eql(u8, name, "sys_exit")) return .proc_exit;
    if (std.mem.eql(u8, name, "sys_argv")) return .proc_args;
    if (std.mem.eql(u8, name, "sys_argc")) return .proc_args;
    return null;
}

pub fn packageGrantEntry(
    package_identity: ?[]const u8,
    package_grants: []const pkg_manifest.RequireEntry,
) ?*const pkg_manifest.RequireEntry {
    const identity = package_identity orelse return null;
    for (package_grants, 0..) |entry, idx| {
        if (std.mem.eql(u8, entry.url, identity)) {
            return &package_grants[idx];
        }
    }
    return null;
}

pub fn packageGrantAllowsEntry(entry: *const pkg_manifest.RequireEntry, required: pkg_manifest.Capability) bool {
    for (entry.grants) |grant| {
        if (grant == required) return true;
    }
    return false;
}

pub fn packageGrantAllows(
    package_identity: ?[]const u8,
    required: pkg_manifest.Capability,
    package_grants: []const pkg_manifest.RequireEntry,
) bool {
    const entry = packageGrantEntry(package_identity, package_grants) orelse return true;
    return packageGrantAllowsEntry(entry, required);
}

pub fn builtinReturnCap(name: []const u8) ?inst.CapPrefix {
    if (std.mem.eql(u8, name, "panic")) return null;
    if (std.mem.eql(u8, name, "panic_msg")) return null;
    if (std.mem.eql(u8, name, "sys_read_file")) return .raw;
    if (std.mem.eql(u8, name, "sys_argv")) return .raw;
    if (std.mem.eql(u8, name, "sys_argc")) return .by_value;
    if (std.mem.eql(u8, name, "sys_exit")) return .by_value;
    if (std.mem.eql(u8, name, "sys_write_file")) return .by_value;
    if (std.mem.eql(u8, name, "sys_print")) return null;
    return null;
}

pub fn callTextForInstruction(
    allocator: std.mem.Allocator,
    symbols: *const symbol.SymbolTable,
    item: inst.Instruction,
) ![]u8 {
    _ = symbols;
    if (item.raw_text.len != 0) return try allocator.dupe(u8, item.raw_text);
    switch (item.kind) {
        .call, .call_indirect => {
            if (item.operands[0] == .reg and item.operands[1] == .text) {
                return try std.fmt.allocPrint(
                    allocator,
                    "{s} = {s} {s}",
                    .{ operandDebugName(item.operands[0]), if (item.kind == .call) "call" else "call_indirect", item.operands[1].text },
                );
            }
            if (item.operands[0] == .text) {
                return try std.fmt.allocPrint(
                    allocator,
                    "{s} {s}",
                    .{ if (item.kind == .call) "call" else "call_indirect", item.operands[0].text },
                );
            }
            if (item.operands[1] == .text) {
                return try std.fmt.allocPrint(
                    allocator,
                    "{s} {s}",
                    .{ if (item.kind == .call) "call" else "call_indirect", item.operands[1].text },
                );
            }
        },
        .panic, .panic_msg => {
            const callee = if (item.kind == .panic) "panic" else "panic_msg";
            if (item.kind == .panic_msg and item.operands[0] != .none and item.operands[1] != .none and item.operands[2] != .none) {
                return try std.fmt.allocPrint(
                    allocator,
                    "{s}({s}, {s}, {s})",
                    .{ callee, operandDebugName(item.operands[0]), operandDebugName(item.operands[1]), operandDebugName(item.operands[2]) },
                );
            }
            if (item.operands[0] == .text) {
                const arg = item.operands[0].text;
                if (arg.len >= 2 and arg[0] == '(' and arg[arg.len - 1] == ')') {
                    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ callee, arg });
                }
                return try std.fmt.allocPrint(allocator, "{s}({s})", .{ callee, arg });
            }
            if (item.operands[0] == .reg) {
                return try std.fmt.allocPrint(allocator, "{s}({s})", .{ callee, operandDebugName(item.operands[0]) });
            }
        },
        else => {},
    }
    return try allocator.dupe(u8, item.raw_text);
}

pub fn parseInstructionCallForVerifier(
    allocator: std.mem.Allocator,
    symbols: *const symbol.SymbolTable,
    item: inst.Instruction,
) !call.ParsedCall {
    return try call.parseInstructionCall(allocator, item, symbols);
}

pub const ScopedSymbolLookup = struct {
    symbols: *const symbol.SymbolTable,
    scope: *const FunctionRegScope,

    pub fn lookupName(self: ScopedSymbolLookup, id: u32) ?[]const u8 {
        return self.scope.nameOf(self.symbols, id) orelse self.symbols.lookupName(id);
    }
};

pub fn parseInstructionCallForLocalizedVerifier(
    allocator: std.mem.Allocator,
    symbols: *const symbol.SymbolTable,
    scope: ?*const FunctionRegScope,
    item: inst.Instruction,
) !call.ParsedCall {
    if (scope) |active_scope| {
        const lookup = ScopedSymbolLookup{ .symbols = symbols, .scope = active_scope };
        return try call.parseInstructionCall(allocator, item, lookup);
    }
    return try parseInstructionCallForVerifier(allocator, symbols, item);
}

pub const ScopedGlobalFirstSymbolLookup = struct {
    symbols: *const symbol.SymbolTable,
    scope: *const FunctionRegScope,

    pub fn lookupName(self: ScopedGlobalFirstSymbolLookup, id: u32) ?[]const u8 {
        return self.symbols.lookupName(id) orelse self.scope.nameOf(self.symbols, id);
    }
};

pub fn parseInstructionCallForFunctionScan(
    allocator: std.mem.Allocator,
    symbols: *const symbol.SymbolTable,
    scope: *const FunctionRegScope,
    item: inst.Instruction,
) !call.ParsedCall {
    const lookup = ScopedGlobalFirstSymbolLookup{ .symbols = symbols, .scope = scope };
    return try call.parseInstructionCall(allocator, item, lookup);
}

pub fn callPrefixMatchesParam(param: sig.ParamSpec, arg_prefix: inst.CapPrefix) bool {
    if (arg_prefix == param.cap) return true;
    if (param.cap != .by_value or param.ty != .ptr) return false;
    return switch (arg_prefix) {
        .borrow, .raw => true,
        else => false,
    };
}

pub fn isFallibleCall(
    sig_match: ?sig.FunctionSig,
    callee: []const u8,
) bool {
    if (sig_match) |resolved| {
        return resolved.return_fallible;
    }
    return std.mem.eql(u8, callee, "sys_read_file") or std.mem.eql(u8, callee, "sys_argv");
}

pub fn fallibleValueType(return_cap: ?inst.CapPrefix, return_ty: sig.PrimType) sig.PrimType {
    return sig.returnValueType(return_cap, return_ty);
}

pub fn fallibleResultMask() u16 {
    return maskOf(.fallible);
}

pub fn panicMsgAllowsRawArg(callee: []const u8, args_len: usize, idx: usize) bool {
    return std.mem.eql(u8, callee, "panic_msg") and args_len == 3 and idx == 1;
}

pub fn readCheckAllowRaw(
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

pub fn parseDeclKind(kind: inst.InstKind) ?sig.FunctionKind {
    return switch (kind) {
        .func_decl => .normal,
        .ffi_wrapper_decl => .ffi_wrapper,
        .extern_decl => .external,
        .export_decl => .exported,
        .test_decl => .test_func,
        .gpu_decl => .gpu,
        else => null,
    };
}

pub fn addScopeReg(
    reg_ids: *std.array_list.Managed(u32),
    seen: *std.AutoHashMap(u32, void),
    reg_id: u32,
) !void {
    if (seen.contains(reg_id)) return;
    try seen.put(reg_id, {});
    try reg_ids.append(reg_id);
}

/// Demand-driven const scoping (OPTIMIZE-IMPL-1): a const belongs to a
/// function's scope iff the function references it -- as a `.reg` operand
/// (handled by the per-instruction operand scan) or by NAME in the
/// instruction text (call args, `store` `.text` values, `.op` `.text`
/// operands -- none of which the operand scan sees). The old code added
/// EVERY const to EVERY function (`for (const_decls)`), inflating each
/// scope from ~10 regs to ~11k and making metadata + body quadratic.
/// The name set is built ONCE per top-level call (never per function);
/// the text scan is linear in the instruction text. False positives
/// (a const name inside a string literal) only add one harmless slot;
/// false negatives are impossible by construction: any name verifyBody
/// can resolve through the scope is textually present here, and any
/// id-based reference arrives as a `.reg` operand.
pub fn addTextReferencedConsts(
    raw_text: []const u8,
    const_names: *const std.StringHashMap(void),
    symbols: *const symbol.SymbolTable,
    reg_ids: *std.array_list.Managed(u32),
    reg_seen: *std.AutoHashMap(u32, void),
) !void {
    var i: usize = 0;
    while (i < raw_text.len) {
        const c = raw_text[i];
        if (std.ascii.isAlphabetic(c) or c == '_') {
            const start = i;
            while (i < raw_text.len and (std.ascii.isAlphanumeric(raw_text[i]) or raw_text[i] == '_')) : (i += 1) {}
            const token = raw_text[start..i];
            if (const_names.contains(token)) {
                // All @const decls precede function bodies in the .sa
                // stream, and the const walk interns each decl name before
                // any body instruction is scanned, so findId succeeds.
                if (symbols.findId(token)) |id| {
                    try addScopeReg(reg_ids, reg_seen, id);
                }
            }
        } else {
            i += 1;
        }
    }
}

pub fn finalizeFunctionScope(
    sigs: *std.array_list.Managed(sig.FunctionSig),
    reg_ids: *std.array_list.Managed(u32),
) !void {
    if (sigs.items.len == 0) {
        reg_ids.clearRetainingCapacity();
        return;
    }
    // No const loop: text-referenced consts were added by the
    // per-instruction scan in collectMetadata (see addTextReferencedConsts).
    const slice = try reg_ids.toOwnedSlice();
    sigs.items[sigs.items.len - 1].reg_ids = slice;
}

pub fn buildFunctionRegScope(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    param_ids: []const u32,
    const_decls: []const const_decl.ConstDecl,
    symbols: *const symbol.SymbolTable,
) !FunctionRegScope {
    var reg_ids = std.array_list.Managed(u32).init(allocator);
    errdefer reg_ids.deinit();
    var seen = std.AutoHashMap(u32, void).init(allocator);
    defer seen.deinit();

    var const_names = std.StringHashMap(void).init(allocator);
    defer const_names.deinit();
    for (const_decls) |decl| {
        if (decl.name.len != 0) try const_names.put(decl.name, {});
    }

    try reg_ids.ensureTotalCapacity(param_ids.len);
    try seen.ensureTotalCapacity(@intCast(param_ids.len));
    for (param_ids) |reg_id| {
        try addScopeReg(&reg_ids, &seen, reg_id);
    }

    for (instructions) |item| {
        for (item.operands) |operand| {
            if (operand == .reg) {
                try addScopeReg(&reg_ids, &seen, operand.reg);
            }
        }
        try addTextReferencedConsts(item.raw_text, &const_names, symbols, &reg_ids, &seen);

        switch (item.kind) {
            .call, .call_indirect, .panic, .panic_msg, .return_, .native => {
            if (parseInstructionCallForVerifier(allocator, &symbols, item)) |parsed0| {
                    var parsed = parsed0;
                    defer parsed.deinit(allocator);
                    if (parsed.dest) |dest| {
                        if (isIdentLike(dest)) {
                            if (symbols.findId(dest)) |id| {
                                try addScopeReg(&reg_ids, &seen, id);
                            }
                        }
                    }
                } else |_| {}
            },
            else => {},
        }
    }

    const slice = try reg_ids.toOwnedSlice();
    errdefer allocator.free(slice);
    return try FunctionRegScope.init(allocator, slice);
}

pub fn localizeInstructionRegs(
    item: *inst.Instruction,
    scope: *const FunctionRegScope,
    symbols: *const symbol.SymbolTable,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
) ?VerifyBodyResult {
    for (&item.operands) |*operand| {
        if (operand.* == .reg) {
            const slot = scope.slotOf(operand.reg) orelse {
                return trapReport(.unknown_register, item.*, function_text, is_ffi_wrapper, symbols.lookupName(operand.reg), null, null, "register is not declared in the current scope", null);
            };
            operand.* = .{ .reg = slot };
        }
    }
    return null;
}

pub fn resolveScopedRegId(
    scope: *const FunctionRegScope,
    symbols: *const symbol.SymbolTable,
    text: []const u8,
) ?u32 {
    const global_id = symbols.findId(text) orelse return null;
    return scope.slotOf(global_id);
}

/// Rebuild per-function register scopes for a trusted (previously verified)
/// instruction stream. The verdict-cache fast path reuses FlattenResult sigs
/// whose `reg_ids` were never finalized, which leaves every `regSlot`/`slotOf`
/// lookup in codegen failing with `InvalidOperand`. This mirrors the scope
/// collection order of `collectMetadata` (params, body `.reg` operands and
/// call dests interleaved per instruction, then const decl names), assigns
/// owned `reg_ids` on each sig, and localizes body `.reg` operands to slots
/// exactly like full verification output.
pub fn populateTrustedRegScopes(
    allocator: std.mem.Allocator,
    instructions: []inst.Instruction,
    const_decls: []const const_decl.ConstDecl,
    function_sigs: []sig.FunctionSig,
    symbols: *const symbol.SymbolTable,
) !void {
    var sig_index: usize = 0;
    var range_start: ?usize = null;
    var idx: usize = 0;
    var const_names = std.StringHashMap(void).init(allocator);
    defer const_names.deinit();
    for (const_decls) |decl| {
        if (decl.name.len != 0) try const_names.put(decl.name, {});
    }
    while (idx <= instructions.len) : (idx += 1) {
        const at_decl = idx < instructions.len and isDecl(instructions[idx].kind);
        if (idx == instructions.len or at_decl) {
            if (range_start) |start| {
                if (sig_index >= function_sigs.len) return error.InvalidTrustedScope;
                try populateTrustedFunctionScope(allocator, instructions[start..idx], &const_names, &function_sigs[sig_index], symbols);
                sig_index += 1;
            }
            if (idx < instructions.len) range_start = idx + 1;
        }
    }
    if (sig_index != function_sigs.len) return error.InvalidTrustedScope;
}

pub fn populateTrustedFunctionScope(
    allocator: std.mem.Allocator,
    body: []inst.Instruction,
    const_names: *const std.StringHashMap(void),
    function_sig: *sig.FunctionSig,
    symbols: *const symbol.SymbolTable,
) !void {
    var reg_ids = std.array_list.Managed(u32).init(allocator);
    errdefer reg_ids.deinit();
    var seen = std.AutoHashMap(u32, void).init(allocator);
    defer seen.deinit();

    for (function_sig.param_ids) |reg_id| {
        try addScopeReg(&reg_ids, &seen, reg_id);
    }
    for (body) |item| {
        for (item.operands) |operand| {
            if (operand == .reg) {
                try addScopeReg(&reg_ids, &seen, operand.reg);
            }
        }
        try addTextReferencedConsts(item.raw_text, const_names, symbols, &reg_ids, &seen);
        if (parseInstructionCallForVerifier(allocator, symbols, item)) |parsed0| {
            var parsed = parsed0;
            defer parsed.deinit(allocator);
            if (parsed.dest) |dest| {
                if (isIdentLike(dest)) {
                    if (symbols.findId(dest)) |id| {
                        try addScopeReg(&reg_ids, &seen, id);
                    }
                }
            }
        } else |_| {}
    }
    var scope = try FunctionRegScope.init(allocator, try reg_ids.toOwnedSlice());
    errdefer scope.deinit();
    for (body) |*item| {
        for (&item.operands) |*operand| {
            if (operand.* == .reg) {
                operand.* = .{ .reg = scope.slotOf(operand.reg) orelse return error.InvalidTrustedScope };
            }
        }
    }
    function_sig.reg_ids = scope.reg_ids;
    scope.owns_reg_ids = false;
    scope.deinit();
}

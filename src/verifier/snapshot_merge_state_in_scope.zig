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
const InteriorContext = @import("reg_state_change.zig").InteriorContext;
const LabelSnapshot = @import("reg_state_change.zig").LabelSnapshot;
const StateMismatch = @import("const_trap.zig").StateMismatch;
const VerifyBodyResult = @import("reg_state_change.zig").VerifyBodyResult;
const copyTextBuf = @import("reg_state_change.zig").copyTextBuf;
const hasInteriorPtr = @import("const_trap.zig").hasInteriorPtr;
const incrementTestConsumedScanCount = @import("reg_state_change.zig").incrementTestConsumedScanCount;
const isDecl = @import("const_trap.zig").isDecl;
const isIdentLike = @import("reg_state_change.zig").isIdentLike;
const maskOf = @import("reg_state_change.zig").maskOf;
const mergeJoinMask = @import("const_trap.zig").mergeJoinMask;
const parseInstructionCallForFunctionScan = @import("sax_trap_report.zig").parseInstructionCallForFunctionScan;
const snapshotMaskAt = @import("const_trap.zig").snapshotMaskAt;
const trapCode = @import("reg_state_change.zig").trapCode;
const trimTrailingCr = @import("reg_state_change.zig").trimTrailingCr;

pub fn snapshotMergeStateInScope(snapshot: *const LabelSnapshot, state: []const u16, scope: *const FunctionRegScope, symbols: *const symbol.SymbolTable) ?StateMismatch {
    for (state, 0..) |mask, idx| {
        const snap_mask = snapshotMaskAt(snapshot, @intCast(idx));
        if (snap_mask == mask) continue;
        if (mergeJoinMask(snap_mask, mask) != null) continue;
        const name = scope.nameOf(symbols, @intCast(idx)) orelse symbols.lookupName(@intCast(idx)) orelse continue;
        return .{ .name = name, .expected = mask, .actual = snap_mask };
    }
    return null;
}

pub fn callConsumesByValueArg(callee: []const u8) bool {
    return std.mem.eql(u8, callee, "pthread_drop") or
        std.mem.eql(u8, callee, "fd_close") or
        std.mem.eql(u8, callee, "dlclose") or
        std.mem.eql(u8, callee, "munmap") or
        std.mem.eql(u8, callee, "sqlite3_finalize") or
        std.mem.endsWith(u8, callee, "_close") or
        std.mem.endsWith(u8, callee, "_drop") or
        std.mem.endsWith(u8, callee, "_unmap") or
        std.mem.endsWith(u8, callee, "_finalize") or
        std.mem.endsWith(u8, callee, "_free") or
        std.mem.endsWith(u8, callee, "_destroy") or
        std.mem.endsWith(u8, callee, "_release");
}

pub fn markConsumedGlobalReg(scope: *const FunctionRegScope, global_reg: u32, consumed_in_function: []bool) void {
    const slot = scope.slotOf(global_reg) orelse return;
    consumed_in_function[@intCast(slot)] = true;
}

pub fn markCaretConsumedRegs(text: []const u8, symbols: *const symbol.SymbolTable, scope: *const FunctionRegScope, consumed_in_function: []bool) void {
    var search_start: usize = 0;
    while (search_start < text.len) {
        const caret_idx = std.mem.indexOfPos(u8, text, search_start, "^") orelse return;
        const name_start = caret_idx + 1;
        var name_end = name_start;
        while (name_end < text.len and (std.ascii.isAlphanumeric(text[name_end]) or text[name_end] == '_')) : (name_end += 1) {}
        if (name_end > name_start) {
            if (symbols.findId(text[name_start..name_end])) |global_reg| {
                markConsumedGlobalReg(scope, global_reg, consumed_in_function);
            }
        }
        search_start = caret_idx + 1;
    }
}

pub fn markCaretConsumedOperand(operand: inst.Operand, symbols: *const symbol.SymbolTable, scope: *const FunctionRegScope, consumed_in_function: []bool) void {
    switch (operand) {
        .text => |text| markCaretConsumedRegs(text, symbols, scope, consumed_in_function),
        .native_text => |text| markCaretConsumedRegs(text, symbols, scope, consumed_in_function),
        else => {},
    }
}

pub fn markConsumedScopedName(symbols: *const symbol.SymbolTable, scope: *const FunctionRegScope, name: []const u8, consumed_in_function: []bool) void {
    const global_reg = symbols.findId(name) orelse return;
    const slot = scope.slotOf(global_reg) orelse return;
    consumed_in_function[@intCast(slot)] = true;
}

pub fn markStructuredCallConsumedRegs(
    allocator: std.mem.Allocator,
    item: inst.Instruction,
    symbols: *const symbol.SymbolTable,
    scope: *const FunctionRegScope,
    consumed_in_function: []bool,
) void {
    switch (item.kind) {
        .call, .call_indirect, .panic, .panic_msg => {},
        else => return,
    }

    var parsed = parseInstructionCallForFunctionScan(allocator, symbols, scope, item) catch return;
    defer parsed.deinit(allocator);
    for (parsed.args) |arg| {
        if (arg.prefix != .move) continue;
        if (!isIdentLike(arg.text)) continue;
        markConsumedScopedName(symbols, scope, arg.text, consumed_in_function);
    }
}

pub fn markInstructionConsumedRegs(
    allocator: std.mem.Allocator,
    item: inst.Instruction,
    symbols: *const symbol.SymbolTable,
    scope: *const FunctionRegScope,
    consumed_in_function: []bool,
) void {
    switch (item.kind) {
        .move_, .release => if (item.operands[0] == .reg) markConsumedGlobalReg(scope, item.operands[0].reg, consumed_in_function),
        .assign => if (item.operands[1] == .reg) markConsumedGlobalReg(scope, item.operands[1].reg, consumed_in_function),
        .return_ => if (item.operands[0] == .reg) markConsumedGlobalReg(scope, item.operands[0].reg, consumed_in_function),
        .try_, .early_return => if (item.operands[1] == .reg) markConsumedGlobalReg(scope, item.operands[1].reg, consumed_in_function),
        else => {},
    }
    markStructuredCallConsumedRegs(allocator, item, symbols, scope, consumed_in_function);
    for (item.operands) |operand| {
        markCaretConsumedOperand(operand, symbols, scope, consumed_in_function);
    }
}

pub fn computeFunctionConsumedRegs(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    function_start_idx: usize,
    symbols: *const symbol.SymbolTable,
    scope: *const FunctionRegScope,
    consumed_in_function: []bool,
) void {
    @memset(consumed_in_function, false);
    var idx = function_start_idx + 1;
    while (idx < instructions.len) : (idx += 1) {
        const item = instructions[idx];
        if (isDecl(item.kind)) break;
        incrementTestConsumedScanCount();
        markInstructionConsumedRegs(allocator, item, symbols, scope, consumed_in_function);
    }
}

pub fn detachInteriorChild(
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    child_id: u32,
) void {
    _ = state;
    const child_idx: usize = @intCast(child_id);
    if (interior_parent[child_idx]) |parent_id| {
        const parent_idx: usize = @intCast(parent_id);
        var prev: ?u32 = null;
        var current = interior_first_child[parent_idx];
        while (current) |current_id| {
            if (current_id == child_id) {
                const next = interior_next_sibling[child_idx];
                if (prev) |prev_id| {
                    interior_next_sibling[@intCast(prev_id)] = next;
                } else {
                    interior_first_child[parent_idx] = next;
                }
                break;
            }
            prev = current_id;
            current = interior_next_sibling[@intCast(current_id)];
        }
    }
    interior_parent[child_idx] = null;
    interior_next_sibling[child_idx] = null;
}

pub fn attachInteriorChild(
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    parent_id: u32,
    child_id: u32,
) void {
    detachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, child_id);
    const parent_idx: usize = @intCast(parent_id);
    const child_idx: usize = @intCast(child_id);
    interior_parent[child_idx] = parent_id;
    interior_next_sibling[child_idx] = interior_first_child[parent_idx];
    interior_first_child[parent_idx] = child_id;
}

pub fn clearInteriorOffsetMeta(interior: *InteriorContext, id: u32) void {
    const idx: usize = @intCast(id);
    if (idx >= interior.interior_root.len) return;
    interior.interior_root[idx] = null;
    interior.interior_offset[idx] = 0;
    interior.interior_offset_known[idx] = false;
}

pub fn staticByteOffset(operand: inst.Operand) ?u64 {
    return switch (operand) {
        .imm_u64 => |value| value,
        .imm_i64 => |value| if (value >= 0) @as(u64, @intCast(value)) else null,
        else => null,
    };
}

pub fn parseAllocSizeOperand(operand: inst.Operand) ?u64 {
    return switch (operand) {
        .imm_u64 => |value| value,
        .imm_i64 => |value| if (value > 0) @as(u64, @intCast(value)) else null,
        .text => |t| std.fmt.parseInt(u64, std.mem.trim(u8, t, " \t\r\n"), 10) catch null,
        else => null,
    };
}

pub fn clearAllocSizeMeta(interior: *InteriorContext, id: u32) void {
    const idx: usize = @intCast(id);
    if (idx >= interior.alloc_size.len) return;
    interior.alloc_size[idx] = 0;
    interior.alloc_size_known[idx] = false;
}

pub fn recordAllocSize(interior: *InteriorContext, id: u32, maybe_size: ?u64) void {
    const idx: usize = @intCast(id);
    if (idx >= interior.alloc_size.len) return;
    if (maybe_size) |size| {
        interior.alloc_size[idx] = size;
        interior.alloc_size_known[idx] = true;
    } else {
        interior.alloc_size[idx] = 0;
        interior.alloc_size_known[idx] = false;
    }
}

/// Follow interior_root, then borrow origins, to the ultimate allocation.
/// Returns the allocation register id, or null when the chain is unknown.
pub fn resolveAllocRoot(
    interior: *const InteriorContext,
    origins: []const ?u32,
    id: u32,
) ?u32 {
    var current: u32 = id;
    var hops: usize = 0;
    while (hops < origins.len + 1) : (hops += 1) {
        const idx: usize = @intCast(current);
        if (idx >= interior.interior_root.len or idx >= origins.len) return null;
        if (interior.interior_root[idx]) |root| {
            if (root == current) break;
            current = root;
            continue;
        }
        if (origins[idx]) |origin| {
            if (origin == current) break;
            current = origin;
            continue;
        }
        break;
    }
    return current;
}

/// Total static byte offset of `id` relative to its allocation root, or null
/// when any step of the chain is dynamic/unknown.
/// A fresh borrow view or allocation root with no recorded offset counts as
/// zero and the walk continues through origins; a derived pointer
/// (interior_root set) with unknown offset denotes a dynamic offset and
/// stays permissive.
pub fn chainBaseOffset(
    interior: *const InteriorContext,
    origins: []const ?u32,
    id: u32,
) ?u64 {
    var total: u64 = 0;
    var current: u32 = id;
    var hops: usize = 0;
    const bound: usize = origins.len + 1;
    while (hops < bound) : (hops += 1) {
        const idx: usize = @intCast(current);
        if (idx >= interior.interior_offset_known.len or idx >= interior.interior_root.len or idx >= origins.len) return null;
        if (interior.interior_offset_known[idx]) {
            const sum = @addWithOverflow(total, interior.interior_offset[idx]);
            if (sum[1] != 0) return null;
            total = sum[0];
        } else if (interior.interior_root[idx] == null and origins[idx] == null) {
            // Allocation root (or plain value) with no offset: contributes 0.
        } else if (interior.interior_root[idx] == null and origins[idx] != null) {
            // Fresh borrow view directly on its source: contributes 0.
        } else {
            // Derived pointer with dynamic/unknown offset: permissive.
            return null;
        }
        if (interior.interior_root[idx]) |root| {
            if (root == current) {
                // Root link resolved; continue through borrow origins if any.
                if (origins[idx]) |origin| {
                    if (origin == current) break;
                    current = origin;
                    continue;
                }
                break;
            }
            current = root;
            continue;
        }
        if (origins[idx]) |origin| {
            if (origin == current) break;
            current = origin;
            continue;
        }
        break;
    }
    return total;
}

/// Total static byte offset of `id` relative to its allocation root, or null
/// when any step of the chain is dynamic/unknown.
pub fn totalStaticOffset(interior: *const InteriorContext, id: u32) ?u64 {
    const idx: usize = @intCast(id);
    if (idx >= interior.interior_offset_known.len) return null;
    if (!interior.interior_offset_known[idx]) return null;
    return interior.interior_offset[idx];
}

pub fn checkStaticOffsetInBounds(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    interior: *const InteriorContext,
    origins: []const ?u32,
    state: []const u16,
    id: u32,
    static_offset: ?u64,
) ?VerifyBodyResult {
    const off = static_offset orelse return null;
    const root = resolveAllocRoot(interior, origins, id) orelse return null;
    const root_idx: usize = @intCast(root);
    if (root_idx >= interior.alloc_size_known.len) return null;
    if (!interior.alloc_size_known[root_idx]) return null;
    const size = interior.alloc_size[root_idx];
    // Base offset accumulated along the interior/borrow chain (fresh views
    // count as zero; dynamic steps stay permissive).
    const base_off = chainBaseOffset(interior, origins, id) orelse return null;
    const sum = @addWithOverflow(base_off, off);
    if (sum[1] != 0) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), state[@intCast(id)], "pointer offset exceeds allocation size", "shrink the constant offset or widen the allocation");
    }
    const total = sum[0];
    // Offset equal to size is one-past-the-end: forming it is legal only if
    // never dereferenced, but our load/store/ptr_add use sites all denote an
    // actual access here, so require strict containment.
    if (total >= size) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), state[@intCast(id)], "pointer offset exceeds allocation size", "shrink the constant offset or widen the allocation");
    }
    return null;
}

pub fn setInteriorOffsetFromBase(interior: *InteriorContext, base_id: u32, child_id: u32, maybe_offset: ?u64) void {
    const base_idx: usize = @intCast(base_id);
    const child_idx: usize = @intCast(child_id);
    if (child_idx >= interior.interior_root.len or base_idx >= interior.interior_root.len) return;

    const root = interior.interior_root[base_idx] orelse base_id;
    interior.interior_root[child_idx] = root;
    if (maybe_offset) |offset| {
        if (interior.interior_offset_known[base_idx]) {
            const sum = @addWithOverflow(interior.interior_offset[base_idx], offset);
            if (sum[1] != 0) {
                interior.interior_offset[child_idx] = 0;
                interior.interior_offset_known[child_idx] = false;
                return;
            }
            interior.interior_offset[child_idx] = sum[0];
        } else {
            interior.interior_offset[child_idx] = offset;
        }
        interior.interior_offset_known[child_idx] = true;
    } else {
        interior.interior_offset[child_idx] = 0;
        interior.interior_offset_known[child_idx] = false;
    }
}

pub fn sameInteriorField(interior: *const InteriorContext, lhs: u32, rhs: u32) bool {
    const lhs_idx: usize = @intCast(lhs);
    const rhs_idx: usize = @intCast(rhs);
    if (lhs_idx >= interior.interior_root.len or rhs_idx >= interior.interior_root.len) return true;
    const lhs_root = interior.interior_root[lhs_idx] orelse lhs;
    const rhs_root = interior.interior_root[rhs_idx] orelse rhs;
    if (lhs_root != rhs_root) return false;
    if (!interior.interior_offset_known[lhs_idx] or !interior.interior_offset_known[rhs_idx]) return true;
    return interior.interior_offset[lhs_idx] == interior.interior_offset[rhs_idx];
}

pub fn hasOverlappingInteriorBorrow(interior: *const InteriorContext, locks: []const u16, source_id: u32) bool {
    const source_idx: usize = @intCast(source_id);
    if (source_idx >= interior.state.len) return true;
    for (locks, 0..) |lock, idx| {
        if (idx == source_idx or lock == 0) continue;
        const other_id: u32 = @intCast(idx);
        if (sameInteriorField(interior, source_id, other_id)) return true;
    }
    return false;
}

pub fn clearInteriorNode(
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    id: u32,
) void {
    const idx: usize = @intCast(id);
    var current = interior_first_child[idx];
    interior_first_child[idx] = null;
    while (current) |child_id| {
        const next = interior_next_sibling[@intCast(child_id)];
        detachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, child_id);
        current = next;
    }
}

pub fn consumeInteriorChildren(
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    id: u32,
) void {
    const idx: usize = @intCast(id);
    var current = interior_first_child[idx];
    interior_first_child[idx] = null;
    while (current) |child_id| {
        const child_idx: usize = @intCast(child_id);
        const next = interior_next_sibling[child_idx];
        detachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, child_id);
        if (hasInteriorPtr(state[child_idx]) or interior_first_child[child_idx] != null) {
            consumeInteriorChildren(state, interior_parent, interior_first_child, interior_next_sibling, child_id);
        }
        state[child_idx] = maskOf(.consumed);
        current = next;
    }
}

pub fn consumeInteriorValue(
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    id: u32,
) void {
    const idx: usize = @intCast(id);
    if ((state[idx] & maskOf(.interior_ptr)) == 0 and interior_first_child[idx] == null) return;
    detachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, id);
    consumeInteriorChildren(state, interior_parent, interior_first_child, interior_next_sibling, id);
    state[idx] = maskOf(.consumed);
}

pub fn trapReport(
    kind: trap.Trap,
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    register: ?[]const u8,
    expected_mask: ?u16,
    actual_mask: ?u16,
    message: []const u8,
    hint: ?[]const u8,
) VerifyBodyResult {
    const source_text = trimTrailingCr(item.raw_text);
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
        .is_ffi_wrapper = if (function_text != null) is_ffi_wrapper else null,
        .message = message,
        .hint = hint,
    };

    copyTextBuf(&report.source_text_buf, source_text);
    copyTextBuf(&report.original_text_buf, source_text);

    if (register) |value| {
        const len = @min(report.register_buf.len, value.len);
        std.mem.copyForwards(u8, report.register_buf[0..len], value[0..len]);
    }
    if (function_text) |value| {
        const len = @min(report.function_buf.len, value.len);
        std.mem.copyForwards(u8, report.function_buf[0..len], value[0..len]);
    }
    if (report.upstream_loc) |loc| {
        const len = @min(report.upstream_file_buf.len, loc.file.len);
        std.mem.copyForwards(u8, report.upstream_file_buf[0..len], loc.file[0..len]);
        report.upstream_loc = null;
    }

    return .{ .trap = report };
}

pub fn trapReportWithRegisters(
    kind: trap.Trap,
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    register: ?[]const u8,
    registers: []const []const u8,
    expected_mask: ?u16,
    actual_mask: ?u16,
    message: []const u8,
    hint: ?[]const u8,
) VerifyBodyResult {
    const result = trapReport(kind, item, function_text, is_ffi_wrapper, register, expected_mask, actual_mask, message, hint);
    _ = registers;
    return result;
}

pub fn phiStateConflictReport(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    target: u32,
    last_seen_label: ?u32,
    mismatch: ?StateMismatch,
    symbols: *const symbol.SymbolTable,
) VerifyBodyResult {
    const mismatch_name = if (mismatch) |m| m.name else "unknown";
    const expected_mask = if (mismatch) |m| m.expected else null;
    const actual_mask = if (mismatch) |m| m.actual else null;

    const target_name = symbols.lookupName(target) orelse "unknown";
    const current_block_name = if (last_seen_label) |l| symbols.lookupName(l) orelse "unknown" else "entry";

    const expected_name = if (expected_mask) |m| cap.maskName(m) else "Uninitialized";
    const actual_name = if (actual_mask) |m| cap.maskName(m) else "Uninitialized";

    var result = trapReportWithRegisters(
        .phi_state_conflict,
        item,
        function_text,
        is_ffi_wrapper,
        if (mismatch) |m| m.name else null,
        if (mismatch) |m| &[_][]const u8{m.name} else &.{},
        expected_mask,
        actual_mask,
        "incoming control-flow states do not agree",
        null,
    );

    var advice_buf: [256]u8 = std.mem.zeroes([256]u8);
    const advice = if (expected_mask != null or actual_mask != null) blk: {
        const m1 = expected_mask orelse 0;
        const m2 = actual_mask orelse 0;
        const active_mask = maskOf(.active);
        const consumed_mask = maskOf(.consumed);
        const is_borrow1 = (m1 & (maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.borrow_view) | maskOf(.ffi_borrow))) != 0;
        const is_borrow2 = (m2 & (maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.borrow_view) | maskOf(.ffi_borrow))) != 0;

        if (is_borrow1 or is_borrow2) {
            break :blk std.fmt.bufPrint(
                &advice_buf,
                "Release all active borrows of '{s}' before paths merge.",
                .{mismatch_name},
            ) catch "";
        } else if ((m1 == active_mask and (m2 == 0 or m2 == consumed_mask)) or
            (m2 == active_mask and (m1 == 0 or m1 == consumed_mask)))
        {
            break :blk std.fmt.bufPrint(
                &advice_buf,
                "Consume/release '{s}' on all paths (e.g. using '!{s}'), or don't consume it on any path.",
                .{ mismatch_name, mismatch_name },
            ) catch "";
        } else {
            break :blk std.fmt.bufPrint(
                &advice_buf,
                "Ensure '{s}' has matching capability states across all paths.",
                .{mismatch_name},
            ) catch "";
        }
    } else "";

    _ = std.fmt.bufPrint(
        &result.trap.hint_buf,
        "register '{s}' has mismatched path states:\n  - Path via '{s}': {s}\n  - Path via target '{s}': {s}\nSelf-repair hint: {s}",
        .{ mismatch_name, current_block_name, expected_name, target_name, actual_name, advice },
    ) catch |err| {
        // Diagnostic buffer formatting is best-effort; the trap kind and core message are already set.
        _ = @errorName(err);
    };

    return result;
}

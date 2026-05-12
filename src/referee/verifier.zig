const std = @import("std");

const call = @import("call.zig");
const cap = @import("../common/capability.zig");
const atomic = @import("../common/atomic.zig");
const gas = @import("../common/gas.zig");
const const_decl = @import("../common/const_decl.zig");
const inst = @import("../common/instruction.zig");
const sig = @import("../common/signature.zig");
const trap = @import("../common/trap.zig");
const classifier = @import("../flattener/line_classifier.zig");
const symbol = @import("../flattener/symbol.zig");

pub const AnnotatedInstruction = struct {
    base: inst.Instruction,
    entry_caps: []u16,
    exit_caps: []u16,
    gas_step_cost: u32,
};

pub const VerifyOk = struct {
    annotated: []AnnotatedInstruction,
    function_sigs: []sig.FunctionSig,
    symbols: symbol.SymbolTable,
    const_decls: []const const_decl.ConstDecl = &.{},
    gas: gas.GasReport,

    pub fn deinit(self: *VerifyOk, allocator: std.mem.Allocator) void {
        for (self.annotated) |item| {
            allocator.free(item.entry_caps);
            allocator.free(item.exit_caps);
        }
        allocator.free(self.annotated);
        for (self.const_decls) |*item| item.deinit(allocator);
        allocator.free(self.const_decls);
        for (self.function_sigs) |*item| item.deinit(allocator);
        allocator.free(self.function_sigs);
        self.symbols.deinit();
        self.* = undefined;
    }
};

pub const VerifyResult = union(enum) {
    ok: VerifyOk,
    trap: trap.TrapReport,
};

const CollectResult = struct {
    symbols: symbol.SymbolTable,
    sigs: std.ArrayList(sig.FunctionSig),
    const_vtables: std.ArrayList(ConstVTable),
    reg_count: usize,
};

const ConstVTableSlot = struct {
    slot_name: []const u8,
    function_name: []const u8,
    signature: sig.FunctionSig,
};

const ConstVTable = struct {
    name: []const u8,
    slots: []ConstVTableSlot,

    fn deinit(self: *ConstVTable, allocator: std.mem.Allocator) void {
        for (self.slots) |*slot| {
            slot.signature.deinit(allocator);
        }
        allocator.free(self.slots);
        allocator.free(self.name);
        self.* = undefined;
    }
};

const CallProvenance = struct {
    callee_name: []const u8,
    is_vtable_slot: bool = false,
    vtable_name: ?[]const u8 = null,
    slot_name: ?[]const u8 = null,
    slot_signature: ?sig.FunctionSig = null,
    const_name: ?[]const u8 = null,
};

const ValueProvenance = struct {
    const_decl_idx: ?u32 = null,
    const_offset: u64 = 0,
    indirect_sig_index: ?usize = null,
};

fn maskOf(tag: cap.CapabilityMask) u16 {
    return @intFromEnum(tag);
}

const regFlagRawPointer: u8 = 0x01;
const regFlagStackAlloc: u8 = 0x02;
const regFlagImmutable: u8 = 0x04;

const InteriorContext = struct {
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
};

var interior_ctx: ?InteriorContext = null;

fn isIdentLike(text: []const u8) bool {
    return text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
}

fn isImmutable(mask: u16) bool {
    return (mask & maskOf(.immutable)) != 0;
}

fn isImmutableConst(state: []const u16, flags: []const u8, id: u32) bool {
    const idx: usize = @intCast(id);
    return isImmutable(state[idx]) or (flags[idx] & regFlagImmutable) != 0;
}

fn isDecl(kind: inst.InstKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl => true,
        else => false,
    };
}

fn isTerminator(kind: inst.InstKind) bool {
    return switch (kind) {
        .jmp, .br, .br_null, .early_return, .return_, .panic, .panic_msg => true,
        else => false,
    };
}

fn isExecKind(kind: inst.InstKind) bool {
    return switch (kind) {
        .alloc, .stack_alloc, .load, .store, .atomic_load, .atomic_store, .cmpxchg, .atomic_rmw, .fence, .borrow, .move_, .release, .op, .ptr_add, .jmp, .br, .br_null, .call, .call_indirect, .try_, .early_return, .panic, .panic_msg, .return_, .take, .raw_cast, .assume_safe, .assume_borrow, .native => true,
        else => false,
    };
}

fn isConstDeclText(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    return std.mem.startsWith(u8, trimmed, "@const ");
}

fn parseConstDeclName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "@const ")) return null;
    const after = std.mem.trimLeft(u8, trimmed["@const ".len..], " \t\r");
    const eq = std.mem.indexOfScalar(u8, after, '=') orelse return null;
    const name = std.mem.trim(u8, after[0..eq], " \t\r");
    if (name.len == 0) return null;
    return name;
}

fn parseVtableSlotName(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r");
    if (!std.mem.startsWith(u8, trimmed, "vtable {")) return null;
    const open = std.mem.indexOfScalar(u8, trimmed, '{') orelse return null;
    const close = std.mem.lastIndexOfScalar(u8, trimmed, '}') orelse return null;
    if (close <= open) return null;
    const body = std.mem.trim(u8, trimmed[open + 1 .. close], " \t\r");
    const eq = std.mem.indexOfScalar(u8, body, '=') orelse return null;
    const slot = std.mem.trim(u8, body[0..eq], " \t\r");
    if (slot.len == 0) return null;
    return slot;
}

fn parseVtableSlots(allocator: std.mem.Allocator, literal: const_decl.VTableLiteral, sigs: []const sig.FunctionSig) ![]ConstVTableSlot {
    var slots = std.ArrayList(ConstVTableSlot).init(allocator);
    errdefer slots.deinit();
    for (literal.slots) |slot| {
        var sig_match: ?sig.FunctionSig = null;
        for (sigs) |item| {
            if (std.mem.eql(u8, item.name, slot.func_name)) {
                sig_match = item;
                break;
            }
        }
        const resolved = sig_match orelse return error.UnknownRegister;
        try slots.append(.{
            .slot_name = slot.name,
            .function_name = slot.func_name,
            .signature = resolved,
        });
    }
    return try slots.toOwnedSlice();
}

fn collectConstVtables(
    allocator: std.mem.Allocator,
    const_decls: []const const_decl.ConstDecl,
    sigs: []const sig.FunctionSig,
) !std.ArrayList(ConstVTable) {
    var out = std.ArrayList(ConstVTable).init(allocator);
    errdefer {
        for (out.items) |*item| item.deinit(allocator);
        out.deinit();
    }

    for (const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                const name_copy = try allocator.dupe(u8, decl.name);
                errdefer allocator.free(name_copy);
                const slots = try parseVtableSlots(allocator, literal, sigs);
                errdefer {
                    for (slots) |*slot| slot.signature.deinit(allocator);
                    allocator.free(slots);
                }
                try out.append(.{
                    .name = name_copy,
                    .slots = slots,
                });
            },
            else => {},
        }
    }
    return out;
}

fn findConstVtableByName(const_vtables: []const ConstVTable, name: []const u8) ?ConstVTable {
    for (const_vtables) |item| {
        if (std.mem.eql(u8, item.name, name)) return item;
    }
    return null;
}

fn parseCallProvenance(
    item: inst.Instruction,
    parsed: call.ParsedCall,
    symbols: *const symbol.SymbolTable,
    state: []const u16,
    const_vtables: []const ConstVTable,
    origins: []const ?u32,
    const_reg_names: []const ?[]const u8,
) ?CallProvenance {
    _ = item;
    if (!parsed.is_indirect) return null;
    const callee_id = symbols.findId(parsed.callee) orelse return null;
    const callee_idx: usize = @intCast(callee_id);
    const callee_mask = state[callee_idx];
    if ((callee_mask & maskOf(.untracked)) != 0) return null;

    const candidate_const_name = if (const_reg_names[callee_idx]) |name| name else blk: {
        if (origins[callee_idx]) |origin_id| {
            const origin_idx: usize = @intCast(origin_id);
            break :blk const_reg_names[origin_idx] orelse return null;
        }
        break :blk null;
    } orelse return null;

    const vt = findConstVtableByName(const_vtables, candidate_const_name) orelse return null;
    const slot_name = parsed.callee;
    for (vt.slots) |slot| {
        if (std.mem.eql(u8, slot.function_name, slot_name) or std.mem.eql(u8, slot.slot_name, slot_name)) {
            return .{
                .callee_name = parsed.callee,
                .is_vtable_slot = true,
                .vtable_name = vt.name,
                .slot_name = slot.slot_name,
                .slot_signature = slot.signature,
                .const_name = candidate_const_name,
            };
        }
    }
    return .{
        .callee_name = parsed.callee,
        .is_vtable_slot = true,
        .vtable_name = vt.name,
        .slot_name = parsed.callee,
        .slot_signature = null,
        .const_name = candidate_const_name,
    };
}

fn atomicKey(inst_: inst.Instruction) ?u64 {
    return switch (inst_.kind) {
        .cmpxchg => (@as(u64, inst_.operands[2].reg) << 32) | @as(u64, inst_.operands[3].imm_u64),
        .atomic_rmw => (@as(u64, inst_.operands[1].reg) << 32) | @as(u64, inst_.operands[2].imm_u64),
        else => null,
    };
}

fn atomicOrderingOf(inst_: inst.Instruction) atomic.AtomicOrdering {
    return switch (inst_.kind) {
        .cmpxchg => inst_.atomic_ordering orelse .seq_cst,
        .atomic_rmw => inst_.atomic_ordering orelse .seq_cst,
        else => .seq_cst,
    };
}

fn atomicSeenBit(ordering: atomic.AtomicOrdering) u8 {
    return switch (ordering) {
        .relaxed => 0x01,
        .acquire => 0x02,
        .release => 0x04,
        .acq_rel => 0x08,
        .seq_cst => 0x10,
    };
}

fn checkAtomicOrdering(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    seen: *std.AutoHashMap(u64, u8),
) ?VerifyResult {
    const key = atomicKey(item) orelse return null;
    const ordering = atomicOrderingOf(item);
    const current = seen.get(key) orelse 0;
    for ([_]atomic.AtomicOrdering{ .relaxed, .acquire, .release, .acq_rel, .seq_cst }) |prev| {
        const bit = atomicSeenBit(prev);
        if ((current & bit) == 0) continue;
        if (!atomic.sameAddressRmwCompatible(prev, ordering)) {
            return trapReport(.atomic_ordering_mismatch, item, function_text, is_ffi_wrapper, null, null, null, "same-address RMW ordering combination is not allowed", null);
        }
    }
    seen.put(key, current | atomicSeenBit(ordering)) catch {
        return trapReport(.arena_oom, item, function_text, is_ffi_wrapper, null, null, null, "unable to record atomic ordering history", null);
    };
    return null;
}

fn zeroed(comptime T: type, allocator: std.mem.Allocator, len: usize) ![]T {
    const out = try allocator.alloc(T, len);
    @memset(out, 0);
    return out;
}

fn copyToBuf(buf: []u8, text: []const u8) []const u8 {
    const len = @min(buf.len, text.len);
    std.mem.copyForwards(u8, buf[0..len], text[0..len]);
    return buf[0..len];
}

fn hasInteriorPtr(mask: u16) bool {
    return (mask & maskOf(.interior_ptr)) != 0;
}

fn hasInteriorTree(state: []const u16, interior_first_child: []const ?u32, id: u32) bool {
    const idx: usize = @intCast(id);
    return hasInteriorPtr(state[idx]) or interior_first_child[idx] != null;
}

fn detachInteriorChild(
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    child_id: u32,
) void {
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
    _ = state;
}

fn attachInteriorChild(
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

fn clearInteriorNode(
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

fn consumeInteriorChildren(
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

fn consumeInteriorValue(
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

fn trapReport(
    kind: trap.Trap,
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    register: ?[]const u8,
    expected_mask: ?u16,
    actual_mask: ?u16,
    message: []const u8,
    hint: ?[]const u8,
) VerifyResult {
    var report: trap.TrapReport = .{
        .trap = kind,
        .line = item.expanded_line + 1,
        .source_line = item.source_line,
        .register = null,
        .registers = &.{},
        .expected_mask = expected_mask,
        .actual_mask = actual_mask,
        .expected_mask_name = if (expected_mask) |v| cap.maskName(v) else null,
        .actual_mask_name = if (actual_mask) |v| cap.maskName(v) else null,
        .upstream_loc = item.upstream_loc,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = if (item.upstream_loc) |loc| loc.line else 0,
        .upstream_col = if (item.upstream_loc) |loc| loc.col else 0,
        .function = null,
        .is_ffi_wrapper = function_text != null and is_ffi_wrapper,
        .message = message,
        .hint = hint,
    };

    if (register) |value| {
        report.register = copyToBuf(&report.register_buf, value);
    }
    if (function_text) |value| {
        report.function = copyToBuf(&report.function_buf, value);
    }
    if (report.upstream_loc) |loc| {
        const file = copyToBuf(&report.upstream_file_buf, loc.file);
        report.upstream_loc = .{
            .file = file,
            .line = loc.line,
            .col = loc.col,
        };
    }

    return .{ .trap = report };
}

fn builtinArgSpec(name: []const u8) ?[]const inst.CapPrefix {
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

fn builtinReturnCap(name: []const u8) ?inst.CapPrefix {
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

fn isFallibleCall(
    sig_match: ?sig.FunctionSig,
    callee: []const u8,
) bool {
    if (sig_match) |resolved| {
        return resolved.return_fallible;
    }
    return std.mem.eql(u8, callee, "sys_read_file") or std.mem.eql(u8, callee, "sys_argv");
}

fn fallibleValueType(return_cap: ?inst.CapPrefix, return_ty: sig.PrimType) sig.PrimType {
    return sig.returnValueType(return_cap, return_ty);
}

fn fallibleResultMask() u16 {
    return maskOf(.fallible);
}

fn panicMsgAllowsRawArg(callee: []const u8, args_len: usize, idx: usize) bool {
    return std.mem.eql(u8, callee, "panic_msg") and args_len == 3 and idx == 1;
}

fn readCheckAllowRaw(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
) ?VerifyResult {
    const idx: usize = @intCast(id);
    const current = state[idx];
    if (current == 0) return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
    if ((current & maskOf(.consumed)) != 0) return trapReport(.use_after_move, item, function_text, is_ffi_wrapper, name, maskOf(.consumed), current, "moved value is no longer usable", null);
    if ((current & maskOf(.locked_mut)) != 0 and (current & maskOf(.borrow_view)) == 0) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "borrow rules reject this access", null);
    }
    if ((flags[idx] & 0x01) != 0 and !is_ffi_wrapper) {
        return trapReport(.illegal_unsafe_context, item, function_text, is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
    }
    return null;
}

fn parseDeclKind(kind: inst.InstKind) ?sig.FunctionKind {
    return switch (kind) {
        .func_decl => .normal,
        .ffi_wrapper_decl => .ffi_wrapper,
        .extern_decl => .external,
        .export_decl => .exported,
        else => null,
    };
}

fn collectMetadata(
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    const_decls: []const const_decl.ConstDecl,
) !CollectResult {
    var symbols = symbol.SymbolTable.init(allocator);
    errdefer symbols.deinit();

    var sigs = std.ArrayList(sig.FunctionSig).init(allocator);
    errdefer {
        for (sigs.items) |*item| item.deinit(allocator);
        sigs.deinit();
    }

    for (const_decls) |decl| {
        if (decl.name.len != 0) {
            _ = try symbols.intern(decl.name);
        }
    }

    for (instructions) |item| {
        const classified = classifier.classifyLine(item.raw_text);
        switch (item.kind) {
            .label => {
                _ = try symbols.intern(classified.parts[0]);
            },
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl => {
                const kind = parseDeclKind(item.kind).?;
                var parsed = sig.parseFunctionHeader(allocator, item.raw_text, @intCast(sigs.items.len), item.expanded_line, kind) catch |err| {
                    return switch (err) {
                        sig.ParseError.UnsupportedType => error.UnsupportedType,
                        else => error.InvalidFunctionSig,
                    };
                };
                errdefer parsed.deinit(allocator);
                if (parsed.params.len != 0) {
                    const ids = try allocator.alloc(u32, parsed.params.len);
                    errdefer allocator.free(ids);
                    for (parsed.params, 0..) |param, idx| {
                        ids[idx] = try symbols.intern(param.name);
                    }
                    parsed.param_ids = ids;
                }
                _ = try symbols.intern(parsed.name);
                try sigs.append(parsed);
            },
            else => {},
        }
    }

    for (instructions) |item| {
        const classified = classifier.classifyLine(item.raw_text);
        if (item.kind == .label or item.kind == .func_decl or item.kind == .ffi_wrapper_decl or item.kind == .extern_decl or item.kind == .export_decl) continue;
        switch (item.kind) {
            .alloc, .stack_alloc, .move_, .release, .raw_cast, .assume_safe, .assume_borrow => {
                _ = try symbols.intern(classified.parts[0]);
                if (classified.part_count > 1 and isIdentLike(classified.parts[1])) {
                    _ = try symbols.intern(classified.parts[1]);
                }
                if (classified.part_count > 2 and isIdentLike(classified.parts[2])) {
                    _ = try symbols.intern(classified.parts[2]);
                }
            },
            .load, .take => {
                _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[1])) _ = try symbols.intern(classified.parts[1]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
            },
            .ptr_add => {
                _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[1])) _ = try symbols.intern(classified.parts[1]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
            },
            .atomic_load => {
                const parsed = try atomic.parseLoad(item.raw_text);
                _ = try symbols.intern(parsed.dst);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
            },
            .atomic_store => {
                const parsed = try atomic.parseStore(item.raw_text);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
                if (isIdentLike(parsed.value)) _ = try symbols.intern(parsed.value);
            },
            .cmpxchg => {
                const parsed = try atomic.parseCmpxchg(item.raw_text);
                _ = try symbols.intern(parsed.dst);
                _ = try symbols.intern(parsed.ok);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
                if (isIdentLike(parsed.expected)) _ = try symbols.intern(parsed.expected);
                if (isIdentLike(parsed.new_value)) _ = try symbols.intern(parsed.new_value);
            },
            .atomic_rmw => {
                const parsed = try atomic.parseRmw(item.raw_text);
                _ = try symbols.intern(parsed.dst);
                if (isIdentLike(parsed.base)) _ = try symbols.intern(parsed.base);
                if (isIdentLike(parsed.value)) _ = try symbols.intern(parsed.value);
            },
            .fence => {},
            .borrow => {
                _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
            },
            .store => {
                _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
            },
            .op => {
                _ = try symbols.intern(classified.parts[0]);
                if (isIdentLike(classified.parts[2])) _ = try symbols.intern(classified.parts[2]);
                if (isIdentLike(classified.parts[3])) _ = try symbols.intern(classified.parts[3]);
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
                if (call.parseCall(allocator, item.raw_text)) |parsed0| {
                    var parsed = parsed0;
                    defer parsed.deinit(allocator);
                    if (parsed.dest) |dest| {
                        if (isIdentLike(dest)) _ = try symbols.intern(dest);
                    }
                    for (parsed.args) |arg| {
                        if (isIdentLike(arg.text)) _ = try symbols.intern(arg.text);
                    }
                } else |_| {}
            },
        }
    }

    return .{
        .symbols = symbols,
        .sigs = sigs,
        .const_vtables = try collectConstVtables(allocator, const_decls, sigs.items),
        .reg_count = symbols.names.items.len,
    };
}

fn isStackAllocated(flags: []const u8, origins: []const ?u32, state: []const u16, id: u32) bool {
    const idx: usize = @intCast(id);
    if ((flags[idx] & regFlagStackAlloc) != 0) return true;
    if ((state[idx] & maskOf(.borrow_view)) != 0) {
        if (origins[idx]) |origin| {
            const origin_idx: usize = @intCast(origin);
            return (flags[origin_idx] & regFlagStackAlloc) != 0;
        }
    }
    return false;
}

fn readCheck(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
) ?VerifyResult {
    const idx: usize = @intCast(id);
    const current = state[idx];
    if (current == 0) return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
    if ((current & maskOf(.consumed)) != 0) return trapReport(.use_after_move, item, function_text, is_ffi_wrapper, name, maskOf(.consumed), current, "moved value is no longer usable", null);
    if ((current & maskOf(.locked_mut)) != 0 and (current & maskOf(.borrow_view)) == 0) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "borrow rules reject this access", null);
    }
    if ((flags[idx] & 0x01) != 0 and !is_ffi_wrapper) {
        return trapReport(.illegal_unsafe_context, item, function_text, is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
    }
    return null;
}

fn writeCheck(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    flags: []u8,
) ?VerifyResult {
    const idx: usize = @intCast(id);
    const current = state[idx];
    if (current == 0) return trapReport(.unknown_register, item, function_text, is_ffi_wrapper, name, null, null, "register is not declared in the current scope", null);
    if ((current & maskOf(.consumed)) != 0) return trapReport(.use_after_move, item, function_text, is_ffi_wrapper, name, maskOf(.consumed), current, "moved value is no longer usable", null);
    if ((current & maskOf(.locked_read)) != 0 and (current & maskOf(.borrow_view)) == 0) {
        return trapReport(.read_write_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "cannot write through a shared borrow", null);
    }
    if ((current & maskOf(.locked_mut)) != 0 and (current & maskOf(.borrow_view)) == 0) {
        return trapReport(.borrow_conflict, item, function_text, is_ffi_wrapper, name, maskOf(.active), current, "borrow rules reject this access", null);
    }
    if ((flags[idx] & 0x01) != 0 and !is_ffi_wrapper) {
        return trapReport(.illegal_unsafe_context, item, function_text, is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
    }
    return null;
}

fn assignValue(
    item: inst.Instruction,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
    name: []const u8,
    id: u32,
    state: []u16,
    mask: u16,
) ?VerifyResult {
    const idx: usize = @intCast(id);
    const current = state[idx];
    if (current != 0 and (current & maskOf(.consumed)) == 0 and (current & maskOf(.untracked)) == 0) {
        return trapReport(.register_redefinition, item, function_text, is_ffi_wrapper, name, null, null, "register is already live", null);
    }
    if (interior_ctx) |ctx| {
        if (hasInteriorPtr(current) or ctx.interior_first_child[idx] != null) {
            consumeInteriorValue(ctx.state, ctx.interior_parent, ctx.interior_first_child, ctx.interior_next_sibling, id);
        } else {
            clearInteriorNode(ctx.state, ctx.interior_parent, ctx.interior_first_child, ctx.interior_next_sibling, id);
        }
    }
    state[idx] = mask;
    return null;
}

fn setBorrowState(state: []u16, flags: []u8, origins: []?u32, locks: []u16, dst: u32, src: u32, is_mut: bool, is_ffi: bool) void {
    const dst_idx: usize = @intCast(dst);
    const src_idx: usize = @intCast(src);
    state[dst_idx] = maskOf(.active) | maskOf(.borrow_view) | (if (is_mut) maskOf(.locked_mut) else maskOf(.locked_read)) | (if (is_ffi) maskOf(.ffi_borrow) else 0);
    flags[dst_idx] = if (is_ffi) 0x01 else 0x00;
    origins[dst_idx] = src;
    locks[src_idx] += 1;
    if (is_mut) {
        if (state[src_idx] == maskOf(.active)) state[src_idx] = maskOf(.locked_mut);
    } else {
        if (state[src_idx] == maskOf(.active)) state[src_idx] = maskOf(.locked_read);
    }
}

fn clearBorrow(
    state: []u16,
    flags: []u8,
    origins: []?u32,
    locks: []u16,
    id: u32,
) void {
    const idx: usize = @intCast(id);
    if ((state[idx] & maskOf(.borrow_view)) == 0) return;

    if (interior_ctx) |ctx| {
        if (hasInteriorPtr(state[idx])) {
            consumeInteriorValue(ctx.state, ctx.interior_parent, ctx.interior_first_child, ctx.interior_next_sibling, id);
        } else {
            consumeInteriorChildren(ctx.state, ctx.interior_parent, ctx.interior_first_child, ctx.interior_next_sibling, id);
        }
    }

    if ((flags[idx] & regFlagRawPointer) != 0) {
        state[idx] = 0;
        flags[idx] = 0;
        origins[idx] = null;
        return;
    }
    const origin = origins[idx] orelse {
        state[idx] = 0;
        flags[idx] = 0;
        return;
    };
    const origin_idx: usize = @intCast(origin);
    if (locks[origin_idx] > 0) {
        locks[origin_idx] -= 1;
        if (locks[origin_idx] == 0) {
            state[origin_idx] = maskOf(.active);
        }
    }
    state[idx] = 0;
    flags[idx] = 0;
    origins[idx] = null;
}

fn consumeAtContractBoundary(
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
) ?VerifyResult {
    if (readCheck(item, function_text, is_ffi_wrapper, name, id, state, flags)) |tr| return tr;

    const idx: usize = @intCast(id);
    if (isStackAllocated(flags, origins, state, id)) {
        return trapReport(.stack_escape, item, function_text, is_ffi_wrapper, name, maskOf(.active), state[idx], "stack allocation cannot cross a native escape boundary", null);
    }

    if ((state[idx] & maskOf(.borrow_view)) != 0) {
        clearBorrow(state, flags, origins, locks, id);
    } else if (hasInteriorTree(state, interior_first_child, id)) {
        consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, id);
    } else {
        state[idx] = maskOf(.consumed);
    }
    return null;
}

fn updateLabel(
    item: inst.Instruction,
    labels: *std.AutoHashMap(u32, []u16),
    state: []u16,
    allocator: std.mem.Allocator,
    function_text: ?[]const u8,
    is_ffi_wrapper: bool,
) ?VerifyResult {
    const label_id = item.operands[1].label;
    if (labels.getPtr(label_id)) |entry| {
        if (!std.mem.eql(u16, entry.*, state)) {
            return trapReport(.phi_state_conflict, item, function_text, is_ffi_wrapper, null, null, null, "incoming control-flow states do not agree", null);
        }
        return null;
    }
    const dup = allocator.dupe(u16, state) catch {
        return trapReport(.arena_oom, item, function_text, is_ffi_wrapper, null, null, null, "unable to record label state", null);
    };
    labels.put(label_id, dup) catch {
        allocator.free(dup);
        return trapReport(.arena_oom, item, function_text, is_ffi_wrapper, null, null, null, "unable to record label state", null);
    };
    return null;
}

fn freeSigs(allocator: std.mem.Allocator, sigs: *std.ArrayList(sig.FunctionSig)) void {
    for (sigs.items) |*item| item.deinit(allocator);
    sigs.deinit();
}

fn freeAnnotated(allocator: std.mem.Allocator, annotated: *std.ArrayList(AnnotatedInstruction)) void {
    for (annotated.items) |item| {
        allocator.free(item.entry_caps);
        allocator.free(item.exit_caps);
    }
    annotated.deinit();
}

fn resetLabels(allocator: std.mem.Allocator, labels: *std.AutoHashMap(u32, []u16)) void {
    var it = labels.iterator();
    while (it.next()) |entry| allocator.free(entry.value_ptr.*);
    labels.clearRetainingCapacity();
}

pub fn verify(allocator: std.mem.Allocator, instructions: []const inst.Instruction) !VerifyResult {
    if (instructions.len == 0) {
        const symbols = symbol.SymbolTable.init(allocator);
        return .{ .ok = .{
            .annotated = &.{},
            .function_sigs = &.{},
            .symbols = symbols,
            .gas = .{
                .max_alloc_bytes = 0,
                .max_instruction_steps = .{ .bounded = 0 },
                .call_depth = 0,
                .has_unbounded_loop = false,
            },
        } };
    }

    var metadata = collectMetadata(allocator, instructions) catch |err| {
        return .{ .trap = .{
            .trap = switch (err) {
                error.UnsupportedType => .unsupported_type,
                else => .forbidden_syntax,
            },
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "failed to rebuild metadata",
            .hint = null,
        } };
    };
    defer freeSigs(allocator, &metadata.sigs);
    var symbols_moved = false;
    defer if (!symbols_moved) metadata.symbols.deinit();

    const reg_count = metadata.reg_count;
    var state = zeroed(u16, allocator, reg_count) catch {
        return .{ .trap = .{
            .trap = .arena_oom,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "unable to allocate verifier state",
            .hint = null,
        } };
    };
    defer allocator.free(state);
    const flags = try zeroed(u8, allocator, reg_count);
    defer allocator.free(flags);
    const origins = try allocator.alloc(?u32, reg_count);
    defer allocator.free(origins);
    @memset(origins, null);
    const locks = try allocator.alloc(u16, reg_count);
    defer allocator.free(locks);
    @memset(locks, 0);
    const interior_parent = try allocator.alloc(?u32, reg_count);
    defer allocator.free(interior_parent);
    @memset(interior_parent, null);
    const interior_first_child = try allocator.alloc(?u32, reg_count);
    defer allocator.free(interior_first_child);
    @memset(interior_first_child, null);
    const interior_next_sibling = try allocator.alloc(?u32, reg_count);
    defer allocator.free(interior_next_sibling);
    @memset(interior_next_sibling, null);
    const previous_interior_ctx = interior_ctx;
    interior_ctx = .{
        .state = state,
        .interior_parent = interior_parent,
        .interior_first_child = interior_first_child,
        .interior_next_sibling = interior_next_sibling,
    };
    defer interior_ctx = previous_interior_ctx;
    var atomic_history = std.AutoHashMap(u64, u8).init(allocator);
    defer atomic_history.deinit();

    var labels = std.AutoHashMap(u32, []u16).init(allocator);
    defer {
        var it = labels.iterator();
        while (it.next()) |entry| allocator.free(entry.value_ptr.*);
        labels.deinit();
    }
    var defined_labels = std.AutoHashMap(u32, void).init(allocator);
    defer defined_labels.deinit();

    var annotated = std.ArrayList(AnnotatedInstruction).init(allocator);
    var completed = false;
    defer {
        if (!completed) {
            freeAnnotated(allocator, &annotated);
        }
    }

    var current_function_text: ?[]const u8 = null;
    var current_is_ffi_wrapper = false;
    var current_sig: ?sig.FunctionSig = null;
    var sig_index: usize = 0;
    var body_seen = false;
    var terminated = false;
    var fatal_terminated = false;
    var gas_alloc_bytes: u64 = 0;
    var gas_steps: u64 = 0;
    const call_depth: u16 = 0;
    var has_unbounded_loop = false;

    for (instructions) |item| {
        const classified = classifier.classifyLine(item.raw_text);

        if (isDecl(item.kind)) {
            if (body_seen and !terminated and current_function_text != null) {
                return trapReport(.fallthrough_forbidden, item, current_function_text, current_is_ffi_wrapper, null, null, null, "basic blocks must end with jmp, br, br_null, or return", "insert an explicit terminator before the next declaration");
            }

            current_function_text = item.raw_text;
            current_is_ffi_wrapper = item.kind == .ffi_wrapper_decl;
            terminated = false;
            body_seen = false;
            resetLabels(allocator, &labels);

            if (sig_index < metadata.sigs.items.len) {
                current_sig = metadata.sigs.items[sig_index];
                sig_index += 1;
            } else {
                current_sig = null;
            }

            @memset(state, 0);
            @memset(flags, 0);
            @memset(origins, null);
            @memset(locks, 0);
            @memset(interior_parent, null);
            @memset(interior_first_child, null);
            @memset(interior_next_sibling, null);
            atomic_history.clearRetainingCapacity();
            defined_labels.clearRetainingCapacity();

            if (current_sig) |decl_sig| {
                for (decl_sig.params, 0..) |param, pidx| {
                    const reg_id = decl_sig.param_ids[pidx];
                    const reg_idx: usize = @intCast(reg_id);
                    state[reg_idx] = switch (param.cap) {
                        .by_value, .move => maskOf(.active),
                        .borrow => maskOf(.active) | maskOf(.borrow_view) | maskOf(.locked_read),
                        .raw => maskOf(.untracked),
                    };
                    flags[reg_idx] = if (param.cap == .raw) regFlagRawPointer else 0;
                }
            }

            const snapshot = try allocator.dupe(u16, state);
            const snapshot2 = try allocator.dupe(u16, state);
            try annotated.append(.{
                .base = item,
                .entry_caps = snapshot,
                .exit_caps = snapshot2,
                .gas_step_cost = 0,
            });
            continue;
        }

        if (terminated) {
            if (!isDecl(item.kind) and item.kind != .label) {
                return trapReport(.fallthrough_forbidden, item, current_function_text, current_is_ffi_wrapper, null, null, null, "basic blocks must end with jmp, br, br_null, or return", "insert an explicit terminator before the next declaration");
            }
            if (!(fatal_terminated and item.kind == .label)) {
                terminated = false;
            }
        }

        if (item.kind == .label) {
            if (updateLabel(item, &labels, state, allocator, current_function_text, current_is_ffi_wrapper)) |tr| {
                return tr;
            }
            defined_labels.put(item.operands[1].label, {}) catch {
                return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label definition", null);
            };
            const snapshot = try allocator.dupe(u16, state);
            const snapshot2 = try allocator.dupe(u16, state);
            try annotated.append(.{
                .base = item,
                .entry_caps = snapshot,
                .exit_caps = snapshot2,
                .gas_step_cost = 0,
            });
            continue;
        }

        if (!isExecKind(item.kind)) {
            const snapshot = try allocator.dupe(u16, state);
            const snapshot2 = try allocator.dupe(u16, state);
            try annotated.append(.{
                .base = item,
                .entry_caps = snapshot,
                .exit_caps = snapshot2,
                .gas_step_cost = 0,
            });
            continue;
        }

        body_seen = true;
        gas_steps += 1;
        const snapshot_entry = try allocator.dupe(u16, state);
        var snapshot_entry_owned = true;
        defer if (snapshot_entry_owned) allocator.free(snapshot_entry);

        switch (item.kind) {
            .alloc => {
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
                gas_alloc_bytes += switch (item.operands[1]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch 0,
                    else => 0,
                };
            },
            .stack_alloc => {
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = regFlagStackAlloc;
                gas_alloc_bytes += switch (item.operands[1]) {
                    .imm_u64 => |v| v,
                    .imm_i64 => |v| if (v > 0) @as(u64, @intCast(v)) else 0,
                    .text => |t| std.fmt.parseInt(u64, t, 10) catch 0,
                    else => 0,
                };
            },
            .load, .take => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                const src_idx: usize = @intCast(item.operands[1].reg);
                const src_mask = state[src_idx];
                const loaded_ty: sig.PrimType = if (item.operands[3] == .ty) blk: {
                    break :blk sig.primTypeFromTag(item.operands[3].ty) orelse if (item.kind == .take) .ptr else .i64;
                } else if (item.kind == .take) .ptr else .i64;
                const source_is_tracked = (src_mask & (maskOf(.borrow_view) | maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.interior_ptr))) != 0;
                const new_mask = maskOf(.active) | if (item.kind == .take or (loaded_ty == .ptr and source_is_tracked)) maskOf(.interior_ptr) else 0;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, new_mask)) |tr| return tr;
                if (item.kind == .take or (loaded_ty == .ptr and source_is_tracked)) {
                    attachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[1].reg, item.operands[0].reg);
                }
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .store => {
                if (writeCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    if (metadata.symbols.findId(item.operands[2].text)) |value_id| {
                        if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[2].text, value_id, state, flags)) |tr| return tr;
                    }
                }
            },
            .atomic_load => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .atomic_store => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[0].reg, state, flags)) |tr| return tr;
                if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    if (metadata.symbols.findId(item.operands[2].text)) |value_id| {
                        if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[2].text, value_id, state, flags)) |tr| return tr;
                    }
                }
            },
            .cmpxchg => {
                if (checkAtomicOrdering(item, current_function_text, current_is_ffi_wrapper, &atomic_history)) |tr| return tr;
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[2].reg, state, flags)) |tr| return tr;
                if (item.operands[3] == .imm_u64) {
                    _ = item.operands[3].imm_u64;
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
                flags[@intCast(item.operands[1].reg)] = 0;
            },
            .atomic_rmw => {
                if (checkAtomicOrdering(item, current_function_text, current_is_ffi_wrapper, &atomic_history)) |tr| return tr;
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (item.operands[3] == .text and isIdentLike(item.operands[3].text)) {
                    if (metadata.symbols.findId(item.operands[3].text)) |value_id| {
                        if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[3].text, value_id, state, flags)) |tr| return tr;
                    }
                }
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .fence => {},
            .op => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[2], item.operands[2].reg, state, flags)) |tr| return tr;
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[3], item.operands[3].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .ptr_add => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (item.operands[2] == .reg) {
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[2], item.operands[2].reg, state, flags)) |tr| return tr;
                } else if (item.operands[2] == .text and isIdentLike(item.operands[2].text)) {
                    if (metadata.symbols.findId(item.operands[2].text)) |value_id| {
                        if (readCheck(item, current_function_text, current_is_ffi_wrapper, item.operands[2].text, value_id, state, flags)) |tr| return tr;
                    }
                }
                const src_idx: usize = @intCast(item.operands[1].reg);
                const tracked = (state[src_idx] & (maskOf(.borrow_view) | maskOf(.locked_read) | maskOf(.locked_mut) | maskOf(.interior_ptr))) != 0;
                const dst_mask: u16 = if (tracked) maskOf(.active) | maskOf(.interior_ptr) else maskOf(.active);
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, dst_mask)) |tr| return tr;
                if (tracked) {
                    attachInteriorChild(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[1].reg, item.operands[0].reg);
                }
                flags[@intCast(item.operands[0].reg)] = 0;
            },
            .borrow => {
                const source_reg: u32 = blk: {
                    if (item.operands[1] == .reg) break :blk item.operands[1].reg;
                    if (item.operands[2] == .reg) break :blk item.operands[2].reg;
                    return trapReport(.forbidden_syntax, item, current_function_text, current_is_ffi_wrapper, null, null, null, "invalid borrow syntax", null);
                };
                const mode_text: []const u8 = blk: {
                    if (item.operands[1] == .text) break :blk item.operands[1].text;
                    if (item.operands[2] == .text) break :blk item.operands[2].text;
                    return trapReport(.forbidden_syntax, item, current_function_text, current_is_ffi_wrapper, null, null, null, "invalid borrow syntax", null);
                };
                const is_mut = std.mem.eql(u8, mode_text, "mut");
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[2], source_reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active) | maskOf(.borrow_view))) |tr| return tr;
                setBorrowState(state, flags, origins, locks, item.operands[0].reg, source_reg, is_mut, false);
            },
            .move_ => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                const idx: usize = @intCast(item.operands[0].reg);
                if (isStackAllocated(flags, origins, state, item.operands[0].reg)) {
                    return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), state[idx], "stack allocation cannot be moved out of its function", null);
                }
                if ((flags[idx] & regFlagRawPointer) != 0) {
                    return trapReport(.ffi_ownership_violation, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.borrow_view) | maskOf(.ffi_borrow), state[idx], "FFI borrow views cannot be consumed", null);
                }
                if ((state[idx] & maskOf(.borrow_view)) != 0) {
                    clearBorrow(state, flags, origins, locks, item.operands[0].reg);
                } else {
                    if (hasInteriorTree(state, interior_first_child, item.operands[0].reg)) {
                        consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[0].reg);
                    } else {
                        state[idx] = maskOf(.consumed);
                    }
                }
            },
            .release => {
                const idx: usize = @intCast(item.operands[0].reg);
                if ((state[idx] & maskOf(.borrow_view)) != 0) {
                    clearBorrow(state, flags, origins, locks, item.operands[0].reg);
                } else {
                    if (isStackAllocated(flags, origins, state, item.operands[0].reg)) {
                        return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, classified.parts[0], maskOf(.active), state[idx], "stack allocation cannot be released explicitly", null);
                    }
                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                    if (hasInteriorTree(state, interior_first_child, item.operands[0].reg)) {
                        consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, item.operands[0].reg);
                    } else {
                        state[idx] = maskOf(.consumed);
                    }
                }
            },
            .raw_cast => {
                if (!current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.untracked))) |tr| return tr;
            },
            .assume_safe => {
                if (!current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active))) |tr| return tr;
            },
            .assume_borrow => {
                if (!current_is_ffi_wrapper) return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[1], item.operands[1].reg, state, flags)) |tr| return tr;
                const is_mut = item.operands[2] == .text and std.mem.eql(u8, item.operands[2].text, "mut");
                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, maskOf(.active) | maskOf(.borrow_view))) |tr| return tr;
                setBorrowState(state, flags, origins, locks, item.operands[0].reg, item.operands[1].reg, is_mut, true);
            },
            .native => {
                for (item.native_reg_names) |name| {
                    if (!isIdentLike(name)) continue;
                    if (metadata.symbols.findId(name)) |id| {
                        if (consumeAtContractBoundary(item, current_function_text, current_is_ffi_wrapper, name, id, state, flags, origins, locks, interior_parent, interior_first_child, interior_next_sibling)) |tr| return tr;
                    }
                }
            },
            .jmp => {
                const target = item.operands[1].label;
                if (defined_labels.contains(target)) has_unbounded_loop = true;
                if (labels.getPtr(target)) |entry| {
                    if (!std.mem.eql(u16, entry.*, state)) {
                        return trapReport(.phi_state_conflict, item, current_function_text, current_is_ffi_wrapper, null, null, null, "incoming control-flow states do not agree", null);
                    }
                } else {
                    labels.put(target, try allocator.dupe(u16, state)) catch {
                        return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                    };
                }
                terminated = true;
            },
            .br => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                for ([_]u32{ item.operands[1].label, item.operands[3].label }) |target| {
                    if (labels.getPtr(target)) |entry| {
                        if (!std.mem.eql(u16, entry.*, state)) {
                            return trapReport(.phi_state_conflict, item, current_function_text, current_is_ffi_wrapper, null, null, null, "incoming control-flow states do not agree", null);
                        }
                    } else {
                        labels.put(target, try allocator.dupe(u16, state)) catch {
                            return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                        };
                    }
                    if (defined_labels.contains(target)) has_unbounded_loop = true;
                }
                terminated = true;
            },
            .br_null => {
                if (readCheck(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], item.operands[0].reg, state, flags)) |tr| return tr;
                for ([_]u32{ item.operands[1].label, item.operands[3].label }) |target| {
                    if (labels.getPtr(target)) |entry| {
                        if (!std.mem.eql(u16, entry.*, state)) {
                            return trapReport(.phi_state_conflict, item, current_function_text, current_is_ffi_wrapper, null, null, null, "incoming control-flow states do not agree", null);
                        }
                    } else {
                        labels.put(target, try allocator.dupe(u16, state)) catch {
                            return trapReport(.arena_oom, item, current_function_text, current_is_ffi_wrapper, null, null, null, "unable to record label state", null);
                        };
                    }
                    if (defined_labels.contains(target)) has_unbounded_loop = true;
                }
                terminated = true;
            },
            .call, .call_indirect, .panic, .panic_msg => {
                var parsed = call.parseCall(allocator, item.raw_text) catch {
                    return trapReport(.forbidden_syntax, item, current_function_text, current_is_ffi_wrapper, null, null, null, "invalid call syntax", null);
                };
                defer parsed.deinit(allocator);

                const sig_match: ?sig.FunctionSig = blk: {
                    for (metadata.sigs.items) |one| {
                        if (std.mem.eql(u8, one.name, parsed.callee)) break :blk one;
                    }
                    break :blk null;
                };
                const builtin = builtinArgSpec(parsed.callee);

                if (!parsed.is_indirect and sig_match == null and builtin == null and !std.mem.startsWith(u8, parsed.callee, "sys_")) {
                    return trapReport(.unknown_register, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "callee is not declared", null);
                }

                if (!parsed.is_indirect and builtin == null and std.mem.startsWith(u8, parsed.callee, "sys_")) {
                    return trapReport(.unsupported_sys_intrinsic, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "target runtime does not support this @sys_* intrinsic", null);
                }

                if (!parsed.is_indirect) {
                    if (sig_match) |resolved| {
                        if (resolved.params.len != parsed.args.len) {
                            return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                        }
                        for (parsed.args, resolved.params) |arg, param| {
                            if (arg.prefix != param.cap) {
                                return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                            }
                        }
                    } else if (builtin) |spec| {
                        if (spec.len != parsed.args.len) {
                            return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                        }
                        for (parsed.args, spec) |arg, expected| {
                            if (arg.prefix != expected) {
                                return trapReport(.capability_mismatch, item, current_function_text, current_is_ffi_wrapper, parsed.dest, null, null, "call-site capability prefix does not match the callee contract", null);
                            }
                        }
                    }
                }

                for (parsed.args, 0..) |arg, arg_idx| {
                    if (arg.prefix == .raw and !current_is_ffi_wrapper and !panicMsgAllowsRawArg(parsed.callee, parsed.args.len, arg_idx)) {
                        return trapReport(.illegal_unsafe_context, item, current_function_text, current_is_ffi_wrapper, null, null, null, "raw pointer and assume_* instructions are only legal inside @ffi_wrapper", null);
                    }
                    if (isIdentLike(arg.text)) {
                        if (metadata.symbols.findId(arg.text)) |arg_id| {
                            if (sig_match) |resolved| {
                                if ((resolved.kind == .external or resolved.kind == .ffi_wrapper) and hasInteriorPtr(state[@intCast(arg_id)])) {
                                    return trapReport(.interior_ptr_escape, item, current_function_text, current_is_ffi_wrapper, arg.text, maskOf(.interior_ptr), state[@intCast(arg_id)], "interior pointers cannot cross FFI boundaries", null);
                                }
                            }
                            switch (arg.prefix) {
                                .borrow, .by_value => if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr,
                                .raw => if (panicMsgAllowsRawArg(parsed.callee, parsed.args.len, arg_idx)) {
                                    if (readCheckAllowRaw(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr;
                                } else {
                                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr;
                                },
                                .move => {
                                    if (readCheck(item, current_function_text, current_is_ffi_wrapper, arg.text, arg_id, state, flags)) |tr| return tr;
                                    if (isStackAllocated(flags, origins, state, arg_id)) {
                                        return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, arg.text, maskOf(.active), state[@intCast(arg_id)], "stack allocation cannot be passed by move", null);
                                    }
                                    const arg_reg_idx: usize = @intCast(arg_id);
                                if ((flags[arg_reg_idx] & 0x01) != 0) {
                                        return trapReport(.ffi_ownership_violation, item, current_function_text, current_is_ffi_wrapper, arg.text, maskOf(.borrow_view) | maskOf(.ffi_borrow), state[arg_reg_idx], "FFI borrow views cannot be consumed", null);
                                    }
                                    if ((state[arg_reg_idx] & maskOf(.borrow_view)) != 0) {
                                        clearBorrow(state, flags, origins, locks, arg_id);
                                    } else {
                                        if (hasInteriorTree(state, interior_first_child, arg_id)) {
                                            consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, arg_id);
                                        } else {
                                            state[arg_reg_idx] = maskOf(.consumed);
                                        }
                                    }
                                },
                            }
                        }
                    }
                }

                if (parsed.dest) |dest| {
                    if (isIdentLike(dest)) {
                        if (metadata.symbols.findId(dest)) |dest_id| {
                            const idx: usize = @intCast(dest_id);
                            if (state[idx] != 0 and (state[idx] & maskOf(.consumed)) == 0 and (state[idx] & maskOf(.untracked)) == 0) {
                                return trapReport(.register_redefinition, item, current_function_text, current_is_ffi_wrapper, dest, null, null, "register is already live", null);
                            }
                            const ret_cap = if (parsed.is_indirect) null else if (sig_match) |resolved| resolved.return_cap else builtinReturnCap(parsed.callee);
                            const ret_state = if (!parsed.is_indirect) blk: {
                                if (sig_match) |resolved| {
                                    if (resolved.return_fallible) break :blk maskOf(.fallible);
                                }
                                break :blk switch (ret_cap orelse .move) {
                                    .raw => maskOf(.untracked),
                                    .borrow => maskOf(.active) | maskOf(.borrow_view),
                                    .move, .by_value => maskOf(.active),
                                };
                            } else blk: {
                                break :blk switch (ret_cap orelse .move) {
                                    .raw => maskOf(.untracked),
                                    .borrow => maskOf(.active) | maskOf(.borrow_view),
                                    .move, .by_value => maskOf(.active),
                                };
                            };
                            state[idx] = ret_state;
                            flags[idx] = 0;
                        }
                    }
                }

                if (item.kind == .panic or item.kind == .panic_msg) {
                    terminated = true;
                    fatal_terminated = true;
                }
            },
            .try_, .early_return => {
                const src_id = item.operands[1].reg;
                const dst_id = item.operands[0].reg;
                const src_idx: usize = @intCast(src_id);
                const src_mask = state[src_idx];
                if ((src_mask & maskOf(.fallible)) == 0) {
                    return trapReport(.fallible_contract_mismatch, item, current_function_text, current_is_ffi_wrapper, metadata.symbols.lookupName(src_id), maskOf(.fallible), src_mask, "? can only be applied to fallible return values", null);
                }

                for (state, 0..) |mask, idx| {
                    if (idx == src_idx) continue;
                    if (mask == 0 or mask == maskOf(.consumed) or mask == maskOf(.untracked)) continue;
                    if ((mask & maskOf(.active)) == 0 and (mask & maskOf(.locked_read)) == 0 and (mask & maskOf(.locked_mut)) == 0) continue;
                    if (isStackAllocated(flags, origins, state, @intCast(idx))) continue;
                    return trapReport(.early_return_leak, item, current_function_text, current_is_ffi_wrapper, metadata.symbols.lookupName(src_id), maskOf(.fallible), src_mask, "early return would leak live registers", null);
                }

                if (assignValue(item, current_function_text, current_is_ffi_wrapper, classified.parts[0], dst_id, state, maskOf(.active))) |tr| return tr;
                flags[@intCast(dst_id)] = 0;
                if (hasInteriorTree(state, interior_first_child, src_id)) {
                    consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, src_id);
                } else {
                    state[src_idx] = maskOf(.consumed);
                }
            },
            .return_ => {
                if (item.operands[0] == .reg) {
                    const ret_id = item.operands[0].reg;
                    const ret_name = metadata.symbols.lookupName(ret_id);
                    const idx: usize = @intCast(ret_id);
                    if ((state[idx] & maskOf(.fallible)) != 0) {
                        if (current_sig == null or current_sig.?.return_fallible == false) {
                            return trapReport(.fallible_contract_mismatch, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.fallible), state[idx], "fallible values must be propagated with ? or returned from a fallible function", null);
                        }
                        if (hasInteriorTree(state, interior_first_child, ret_id)) {
                            consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                        } else {
                            state[idx] = maskOf(.consumed);
                        }
                    } else {
                        if (isStackAllocated(flags, origins, state, ret_id)) {
                            return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.active), state[idx], "stack allocation cannot be returned", null);
                        }
                        if ((flags[idx] & regFlagRawPointer) != 0) {
                            return trapReport(.ffi_ownership_violation, item, current_function_text, current_is_ffi_wrapper, ret_name, maskOf(.borrow_view) | maskOf(.ffi_borrow), state[idx], "FFI borrow views cannot be consumed", null);
                        }
                        if ((state[idx] & maskOf(.borrow_view)) != 0) {
                            clearBorrow(state, flags, origins, locks, ret_id);
                        } else if (hasInteriorTree(state, interior_first_child, ret_id)) {
                            consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                        } else if ((state[idx] & maskOf(.untracked)) == 0) {
                            state[idx] = maskOf(.consumed);
                        }
                    }
                } else if (item.operands[0] == .text and isIdentLike(item.operands[0].text)) {
                    if (metadata.symbols.findId(item.operands[0].text)) |ret_id| {
                        const idx: usize = @intCast(ret_id);
                        if ((state[idx] & maskOf(.fallible)) != 0) {
                            if (current_sig == null or current_sig.?.return_fallible == false) {
                                return trapReport(.fallible_contract_mismatch, item, current_function_text, current_is_ffi_wrapper, item.operands[0].text, maskOf(.fallible), state[idx], "fallible values must be propagated with ? or returned from a fallible function", null);
                            }
                            if (hasInteriorTree(state, interior_first_child, ret_id)) {
                                consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                            } else {
                                state[idx] = maskOf(.consumed);
                            }
                        } else {
                            if (isStackAllocated(flags, origins, state, ret_id)) {
                                return trapReport(.stack_escape, item, current_function_text, current_is_ffi_wrapper, item.operands[0].text, maskOf(.active), state[idx], "stack allocation cannot be returned", null);
                            }
                            if ((flags[idx] & regFlagRawPointer) != 0) {
                                return trapReport(.ffi_ownership_violation, item, current_function_text, current_is_ffi_wrapper, item.operands[0].text, maskOf(.borrow_view) | maskOf(.ffi_borrow), state[idx], "FFI borrow views cannot be consumed", null);
                            }
                            if ((state[idx] & maskOf(.borrow_view)) != 0) {
                                clearBorrow(state, flags, origins, locks, ret_id);
                            } else if (hasInteriorTree(state, interior_first_child, ret_id)) {
                                consumeInteriorValue(state, interior_parent, interior_first_child, interior_next_sibling, ret_id);
                            } else if ((state[idx] & maskOf(.untracked)) == 0) {
                                state[idx] = maskOf(.consumed);
                            }
                        }
                    }
                }
                terminated = true;
            },
            else => {},
        }

        const snapshot_exit = try allocator.dupe(u16, state);
        var snapshot_exit_owned = true;
        defer if (snapshot_exit_owned) allocator.free(snapshot_exit);
        try annotated.append(.{
            .base = item,
            .entry_caps = snapshot_entry,
            .exit_caps = snapshot_exit,
            .gas_step_cost = if (isExecKind(item.kind)) 1 else 0,
        });
        snapshot_entry_owned = false;
        snapshot_exit_owned = false;
    }

    if (body_seen and !terminated) {
        return trapReport(.fallthrough_forbidden, instructions[instructions.len - 1], current_function_text, current_is_ffi_wrapper, null, null, null, "function body ended without a terminator", "end the last block with jmp, br, br_null, or return");
    }

    if (!fatal_terminated) {
        for (state, 0..) |mask, idx| {
            if (mask == 0 or mask == maskOf(.consumed) or mask == maskOf(.untracked)) continue;
            if (isStackAllocated(flags, origins, state, @intCast(idx))) continue;
            return trapReport(.memory_leak, instructions[instructions.len - 1], current_function_text, current_is_ffi_wrapper, null, null, mask, "live registers remain at function exit", null);
        }
    } else if (body_seen and !terminated) {
        return trapReport(.fallthrough_forbidden, instructions[instructions.len - 1], current_function_text, current_is_ffi_wrapper, null, null, null, "function body ended without a terminator", "end the last block with jmp, br, br_null, return, or panic");
    }

    const annotated_slice = annotated.toOwnedSlice() catch {
        return .{ .trap = .{
            .trap = .arena_oom,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "unable to finalize annotations",
            .hint = null,
        } };
    };
    const sigs_slice = metadata.sigs.toOwnedSlice() catch {
        return .{ .trap = .{
            .trap = .arena_oom,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "unable to finalize function signatures",
            .hint = null,
        } };
    };
    completed = true;
    symbols_moved = true;

    return .{ .ok = .{
        .annotated = annotated_slice,
        .function_sigs = sigs_slice,
        .symbols = metadata.symbols,
        .gas = .{
            .max_alloc_bytes = gas_alloc_bytes,
            .max_instruction_steps = if (has_unbounded_loop) .{ .unbounded = .{ .bounded_prefix = gas_steps } } else .{ .bounded = gas_steps },
            .call_depth = call_depth,
            .has_unbounded_loop = has_unbounded_loop,
        },
    } };
}

test "panic terminates without forcing a leak trap" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 0 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "x = alloc 8",
        },
        .{
            .kind = .panic,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .text = "7" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "panic(7)",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "panic_msg is treated as a terminator" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 3 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "buf = alloc 3",
        },
        .{
            .kind = .panic_msg,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .text = "7" },
                .{ .text = "buf" },
                .{ .text = "2" },
                .{ .none = {} },
            },
            .raw_text = "panic_msg(7, *buf, 2)",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "stack_alloc is exempt from memory leak and rejects escape" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .stack_alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "tmp = stack_alloc 8",
        },
        .{
            .kind = .return_,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .reg = 0 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return 0",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 3), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "interior pointers are consumed when their parent borrow is released" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .alloc,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .reg = 1 },
                .{ .imm_u64 = 8 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "base = alloc 8",
        },
        .{
            .kind = .borrow,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .reg = 2 },
                .{ .text = "read" },
                .{ .reg = 1 },
                .{ .none = {} },
            },
            .raw_text = "view = & base",
        },
        .{
            .kind = .take,
            .source_line = 4,
            .expanded_line = 3,
            .operands = .{
                .{ .reg = 3 },
                .{ .reg = 2 },
                .{ .imm_u64 = 4 },
                .{ .none = {} },
            },
            .raw_text = "ip = take view+4",
        },
        .{
            .kind = .release,
            .source_line = 5,
            .expanded_line = 4,
            .operands = .{
                .{ .reg = 2 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "!view",
        },
        .{
            .kind = .return_,
            .source_line = 6,
            .expanded_line = 5,
            .operands = .{
                .{ .reg = 1 },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return base",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 6), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "interior pointers trap when passed to extern calls" {
    const source =
        \\@ffi_wrapper sink(*p: ptr) -> i32:
        \\return 0
        \\@ffi_wrapper wrap() -> i32:
        \\base = alloc 8
        \\view = & base
        \\ip = take view+4
        \\call @sink(*ip)
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions);
    switch (verified) {
        .trap => |report| {
            try std.testing.expectEqual(trap.Trap.interior_ptr_escape, report.trap);
        },
        .ok => return error.TestUnexpectedResult,
    }
}

test "assume_borrow marks ffi borrow state and release clears it without freeing" {
    const source =
        \\@ffi_wrapper wrap(*raw: ptr) -> i32:
        \\view = assume_borrow raw
        \\!view
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            var saw_assume = false;
            var saw_release = false;
            for (owned.annotated) |item| {
                if (item.base.kind == .assume_borrow) {
                    saw_assume = true;
                    const mask = item.exit_caps[item.base.operands[0].reg];
                    try std.testing.expect((mask & maskOf(.ffi_borrow)) != 0);
                    try std.testing.expect((mask & maskOf(.borrow_view)) != 0);
                } else if (item.base.kind == .release) {
                    saw_release = true;
                    try std.testing.expectEqual(@as(u16, 0), item.exit_caps[item.base.operands[0].reg]);
                }
            }
            try std.testing.expect(saw_assume);
            try std.testing.expect(saw_release);
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "ffi borrow views cannot be moved or returned" {
    const move_source =
        \\@ffi_wrapper wrap(*raw: ptr) -> i32:
        \\view = assume_borrow raw
        \\^view
        \\return 0
    ;
    var move_flat = try @import("../flattener.zig").flatten(std.testing.allocator, move_source);
    defer move_flat.deinit(std.testing.allocator);

    const moved = try verify(std.testing.allocator, move_flat.instructions);
    switch (moved) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.ffi_ownership_violation, report.trap),
        .ok => return error.TestUnexpectedResult,
    }

    const return_source =
        \\@ffi_wrapper wrap(*raw: ptr) -> &ptr:
        \\view = assume_borrow raw
        \\return view
    ;
    var return_flat = try @import("../flattener.zig").flatten(std.testing.allocator, return_source);
    defer return_flat.deinit(std.testing.allocator);

    const returned = try verify(std.testing.allocator, return_flat.instructions);
    switch (returned) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.ffi_ownership_violation, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "verifier rejects call-site capability prefix mismatches" {
    const source =
        \\@extern sink(&p: ptr, ^q: ptr) -> i32
        \\@main() -> i32:
        \\left = alloc 8
        \\right = alloc 8
        \\value = call @sink(^left, ^right)
        \\!left
        \\return value
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.capability_mismatch, report.trap),
        .ok => return error.TestUnexpectedResult,
    }
}

test "verifier call contract PBT traps on random prefix mismatches" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6121);
    const random = prng.random();
    const caps = [_]struct { text: []const u8, prefix: inst.CapPrefix }{
        .{ .text = "", .prefix = .by_value },
        .{ .text = "&", .prefix = .borrow },
        .{ .text = "^", .prefix = .move },
    };

    for (0..48) |iter| {
        const expected = caps[random.intRangeLessThan(usize, 0, caps.len)];
        var actual = caps[random.intRangeLessThan(usize, 0, caps.len)];
        if (actual.prefix == expected.prefix) {
            actual = caps[(random.intRangeLessThan(usize, 1, caps.len) + @intFromEnum(expected.prefix)) % caps.len];
            if (actual.prefix == expected.prefix) actual = caps[(@intFromEnum(expected.prefix) + 1) % caps.len];
        }

        const source = try std.fmt.allocPrint(
            std.testing.allocator,
            \\@extern sink({s}p: ptr) -> i32
            \\@main() -> i32:
            \\value = alloc 8
            \\ret = call @sink({s}value)
            \\!value
            \\return ret
        , .{ expected.text, actual.text });
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.capability_mismatch, report.trap),
            .ok => {
                _ = iter;
                return error.TestUnexpectedResult;
            },
        }
    }
}

test "native escape conservatively consumes referenced registers" {
    const source =
        \\@main() -> i32:
        \\value = alloc 8
        \\$touch value$
        \\probe = load value+0 as i8
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.use_after_move, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "native escape rejects stack allocations crossing the boundary" {
    const source =
        \\@main() -> i32:
        \\tmp = stack_alloc 8
        \\$touch tmp$
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions);
    switch (verified) {
        .trap => |report| try std.testing.expectEqual(trap.Trap.stack_escape, report.trap),
        .ok => |ok| {
            var owned = ok;
            owned.deinit(std.testing.allocator);
            return error.TestUnexpectedResult;
        },
    }
}

test "native escape PBT conservatively consumes random referenced registers" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6300);
    const random = prng.random();

    for (0..32) |_| {
        const size = random.intRangeAtMost(u64, 1, 64);
        const source = try std.fmt.allocPrint(
            std.testing.allocator,
            \\@main() -> i32:
            \\value = alloc {d}
            \\$touch value$
            \\probe = load value+0 as i8
            \\return 0
        , .{size});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.use_after_move, report.trap),
            .ok => |ok| {
                var owned = ok;
                owned.deinit(std.testing.allocator);
                return error.TestUnexpectedResult;
            },
        }
    }
}

test "early return leak PBT traps when random live allocations survive the fail edge" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6244);
    const random = prng.random();

    for (0..32) |_| {
        const extra_count = random.intRangeAtMost(usize, 1, 4);
        var source = std.ArrayList(u8).init(std.testing.allocator);
        defer source.deinit();

        try source.appendSlice(
            \\@fail() -> i32!:
            \\return 1
            \\@main() -> i32!:
            \\res = call @fail()
        );
        try source.append('\n');

        for (0..extra_count) |idx| {
            try source.writer().print("leak_{d} = alloc {d}\n", .{ idx, random.intRangeAtMost(u64, 1, 64) });
        }

        try source.appendSlice(
            \\ok = ? res
            \\return ok
        );
        try source.append('\n');

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source.items);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.early_return_leak, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "gas report stays bounded for forward jumps" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .jmp,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "jmp L_END",
        },
        .{
            .kind = .label,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "L_END:",
        },
        .{
            .kind = .return_,
            .source_line = 4,
            .expanded_line = 3,
            .operands = .{
                .{ .text = "0" },
                .{ .none = {} },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "return 0",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(u64, 0), owned.gas.max_alloc_bytes);
            try std.testing.expectEqual(false, owned.gas.has_unbounded_loop);
            switch (owned.gas.max_instruction_steps) {
                .bounded => |steps| try std.testing.expectEqual(@as(u64, 2), steps),
                .unbounded => return error.TestUnexpectedResult,
            }
        },
        .trap => return error.TestUnexpectedResult,
    }
}

test "gas report marks backward jumps as unbounded" {
    const program = [_]inst.Instruction{
        .{
            .kind = .func_decl,
            .source_line = 1,
            .expanded_line = 0,
            .operands = .{
                .{ .symbol = 0 },
                .{ .func = 0 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "@main() -> i32:",
        },
        .{
            .kind = .label,
            .source_line = 2,
            .expanded_line = 1,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "L_LOOP:",
        },
        .{
            .kind = .jmp,
            .source_line = 3,
            .expanded_line = 2,
            .operands = .{
                .{ .symbol = 1 },
                .{ .label = 1 },
                .{ .none = {} },
                .{ .none = {} },
            },
            .raw_text = "jmp L_LOOP",
        },
    };

    const verified = try verify(std.testing.allocator, program[0..]);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(true, owned.gas.has_unbounded_loop);
            switch (owned.gas.max_instruction_steps) {
                .unbounded => |info| try std.testing.expectEqual(@as(u64, 1), info.bounded_prefix),
                .bounded => return error.TestUnexpectedResult,
            }
        },
        .trap => return error.TestUnexpectedResult,
    }
}

const VerifyOkSnapshot = struct {
    annotated: []const AnnotatedInstruction,
    function_sigs: []const sig.FunctionSig,
    symbol_names: []const []const u8,
    gas: gas.GasReport,
};

const VerifySnapshot = union(enum) {
    ok: VerifyOkSnapshot,
    trap: trap.TrapReport,
};

const GasFixture = struct {
    instructions: []inst.Instruction,
    owned_texts: [][]u8,
    expected_alloc_bytes: u64,
    expected_steps: u64,
    has_unbounded_loop: bool,

    fn deinit(self: *GasFixture, allocator: std.mem.Allocator) void {
        for (self.owned_texts) |text| allocator.free(text);
        allocator.free(self.owned_texts);
        allocator.free(self.instructions);
        self.* = undefined;
    }
};

fn snapshotResult(result: VerifyResult) VerifySnapshot {
    return switch (result) {
        .ok => |ok| .{
            .ok = .{
                .annotated = ok.annotated,
                .function_sigs = ok.function_sigs,
                .symbol_names = ok.symbols.names.items,
                .gas = ok.gas,
            },
        },
        .trap => |report| .{ .trap = report },
    };
}

fn appendOwnedText(
    texts: *std.ArrayList([]u8),
    allocator: std.mem.Allocator,
    comptime fmt: []const u8,
    args: anytype,
) ![]const u8 {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(text);
    try texts.append(text);
    return text;
}

fn buildGasFixture(
    allocator: std.mem.Allocator,
    random: std.Random,
    bounded: bool,
) !GasFixture {
    var instructions = std.ArrayList(inst.Instruction).init(allocator);
    var instructions_moved = false;
    defer if (!instructions_moved) instructions.deinit();

    var owned_texts = std.ArrayList([]u8).init(allocator);
    var owned_texts_moved = false;
    defer if (!owned_texts_moved) {
        for (owned_texts.items) |text| allocator.free(text);
        owned_texts.deinit();
    };

    const size_choices = [_]u64{ 0, 1, 2, 8, 13, 21, 34, 55, 89, 144 };
    const size = size_choices[random.intRangeLessThan(usize, 0, size_choices.len)];
    const fence_count = random.intRangeAtMost(usize, 0, 4);
    const stack_text = try appendOwnedText(&owned_texts, allocator, "tmp = stack_alloc {d}", .{size});

    var item = inst.makeInstruction(.func_decl, 1, 0, null, "@main() -> i32:");
    item.operands[0] = .{ .symbol = 0 };
    item.operands[1] = .{ .func = 0 };
    try instructions.append(item);

    item = inst.makeInstruction(.stack_alloc, 2, 1, null, stack_text);
    item.operands[0] = .{ .reg = 1 };
    item.operands[1] = .{ .imm_u64 = size };
    try instructions.append(item);

    for (0..fence_count) |idx| {
        item = inst.makeInstruction(.fence, @intCast(3 + idx), @intCast(2 + idx), null, "fence seq_cst");
        try instructions.append(item);
    }

    const next_source_line: u32 = @intCast(3 + fence_count);
    const next_expanded_line: u32 = @intCast(2 + fence_count);

    if (bounded) {
        item = inst.makeInstruction(.jmp, next_source_line, next_expanded_line, null, "jmp L_END");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);

        item = inst.makeInstruction(.label, next_source_line + 1, next_expanded_line + 1, null, "L_END:");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);

        item = inst.makeInstruction(.return_, next_source_line + 2, next_expanded_line + 2, null, "return 0");
        item.operands[0] = .{ .text = "0" };
        try instructions.append(item);
    } else {
        item = inst.makeInstruction(.label, next_source_line, next_expanded_line, null, "L_LOOP:");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);

        item = inst.makeInstruction(.jmp, next_source_line + 1, next_expanded_line + 1, null, "jmp L_LOOP");
        item.operands[0] = .{ .symbol = 2 };
        item.operands[1] = .{ .label = 2 };
        try instructions.append(item);
    }

    const owned_instructions = try instructions.toOwnedSlice();
    instructions_moved = true;
    const owned_text_slice = try owned_texts.toOwnedSlice();
    owned_texts_moved = true;

    var step_count: usize = fence_count + 2;
    if (bounded) step_count += 1;

    return .{
        .instructions = owned_instructions,
        .owned_texts = owned_text_slice,
        .expected_alloc_bytes = size,
        .expected_steps = @intCast(step_count),
        .has_unbounded_loop = !bounded,
    };
}

fn verifyTwiceAndExpectEqual(allocator: std.mem.Allocator, program: []const inst.Instruction) !void {
    const first = try verify(allocator, program);
    defer switch (first) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(allocator);
        },
        .trap => {},
    };

    const second = try verify(allocator, program);
    defer switch (second) {
        .ok => |ok| {
            var owned = ok;
            owned.deinit(allocator);
        },
        .trap => {},
    };

    try std.testing.expectEqualDeep(snapshotResult(first), snapshotResult(second));
}

test "gas PBT stays bounded for random forward-jump programs" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6244);
    const random = prng.random();

    for (0..32) |_| {
        var fixture = try buildGasFixture(std.testing.allocator, random, true);
        defer fixture.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, fixture.instructions, &.{});
        switch (verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);

                try std.testing.expectEqual(fixture.expected_alloc_bytes, owned.gas.max_alloc_bytes);
                try std.testing.expectEqual(false, owned.gas.has_unbounded_loop);
                switch (owned.gas.max_instruction_steps) {
                    .bounded => |steps| try std.testing.expectEqual(fixture.expected_steps, steps),
                    .unbounded => return error.TestUnexpectedResult,
                }
            },
            .trap => return error.TestUnexpectedResult,
        }
    }
}

test "gas PBT marks random back-edge programs as unbounded" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6245);
    const random = prng.random();

    for (0..32) |_| {
        var fixture = try buildGasFixture(std.testing.allocator, random, false);
        defer fixture.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, fixture.instructions, &.{});
        switch (verified) {
            .ok => |ok| {
                var owned = ok;
                defer owned.deinit(std.testing.allocator);

                try std.testing.expectEqual(fixture.expected_alloc_bytes, owned.gas.max_alloc_bytes);
                try std.testing.expectEqual(true, owned.gas.has_unbounded_loop);
                switch (owned.gas.max_instruction_steps) {
                    .unbounded => |info| try std.testing.expectEqual(fixture.expected_steps, info.bounded_prefix),
                    .bounded => return error.TestUnexpectedResult,
                }
            },
            .trap => return error.TestUnexpectedResult,
        }
    }
}

test "referee determinism PBT stays stable across repeated verify runs" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6250);
    const random = prng.random();

    for (0..32) |idx| {
        var fixture = try buildGasFixture(std.testing.allocator, random, (idx & 1) == 0);
        defer fixture.deinit(std.testing.allocator);

        try verifyTwiceAndExpectEqual(std.testing.allocator, fixture.instructions);
    }
}

test "interior ptr PBT traps on use after releasing parent borrow" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6260);
    const random = prng.random();

    for (0..32) |_| {
        const offset: u64 = random.intRangeAtMost(u64, 0, 32);
        const source = try std.fmt.allocPrint(
            std.testing.allocator,
            \\@main() -> i32:
            \\base = alloc 64
            \\view = & base
            \\ip = take view+{d}
            \\!view
            \\value = load ip+0 as u8
            \\return value
        , .{offset});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.use_after_move, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "interior ptr PBT traps on ffi escape" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6261);
    const random = prng.random();

    for (0..32) |_| {
        const offset: u64 = random.intRangeAtMost(u64, 0, 32);
        const source = try std.fmt.allocPrint(
            std.testing.allocator,
            \\@extern sink(*p: ptr) -> i32
            \\@ffi_wrapper wrap(*raw: ptr) -> i32:
            \\safe = assume_safe raw
            \\view = & safe
            \\ip = take view+{d}
            \\value = call @sink(*ip)
            \\return value
            \\@main() -> i32:
            \\base = alloc 64
            \\return 0
        , .{offset});
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.interior_ptr_escape, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "ffi airlock isolation PBT rejects unsafe ops outside ffi wrapper" {
    var prng = std.Random.DefaultPrng.init(0x5A5A_6262);
    const random = prng.random();

    for (0..48) |_| {
        const case_id = random.intRangeLessThan(u8, 0, 3);
        const source = switch (case_id) {
            0 => try std.fmt.allocPrint(
                std.testing.allocator,
                \\@main() -> i32:
                \\node = alloc 8
                \\raw = *node
                \\return 0
            , .{}),
            1 => try std.fmt.allocPrint(
                std.testing.allocator,
                \\@extern grab() -> *ptr
                \\@main() -> i32:
                \\raw = call @grab()
                \\safe = assume_safe raw
                \\return 0
            , .{}),
            else => try std.fmt.allocPrint(
                std.testing.allocator,
                \\@extern grab() -> *ptr
                \\@main() -> i32:
                \\raw = call @grab()
                \\view = assume_borrow raw
                \\return 0
            , .{}),
        };
        defer std.testing.allocator.free(source);

        var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
        defer flat.deinit(std.testing.allocator);

        const verified = try verify(std.testing.allocator, flat.instructions);
        switch (verified) {
            .trap => |report| try std.testing.expectEqual(trap.Trap.illegal_unsafe_context, report.trap),
            .ok => return error.TestUnexpectedResult,
        }
    }
}

test "ffi wrapper allows raw params in branch control flow" {
    const source =
        \\@ffi_wrapper branch(*flag: i32) -> i32:
        \\br flag -> L_TRUE, L_FALSE
        \\L_TRUE:
        \\return 1
        \\L_FALSE:
        \\return 0
    ;
    var flat = try @import("../flattener.zig").flatten(std.testing.allocator, source);
    defer flat.deinit(std.testing.allocator);

    const verified = try verify(std.testing.allocator, flat.instructions);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 6), owned.annotated.len);
        },
        .trap => return error.TestUnexpectedResult,
    }
}
ult,
    }

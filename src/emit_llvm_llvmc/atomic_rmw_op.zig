const std = @import("std");
const call = @import("../referee/call.zig");
const referee = @import("../referee.zig");
const emit_options = @import("../emit_options.zig");
const flattener = @import("../flattener.zig");
const inst = @import("../common/instruction.zig");
const atomic = @import("../common/atomic.zig");
const sig = @import("../common/signature.zig");
const const_decl = @import("../common/const_decl.zig");
const upstream = @import("../common/upstream_loc.zig");
const sio = @import("sio");

const BuildState = @import("sa_llvmc_free.zig").BuildState;
const CAtomicRmwOp = @import("sa_llvmc_free.zig").CAtomicRmwOp;
const COp = @import("sa_llvmc_free.zig").COp;
const COperand = @import("sa_llvmc_free.zig").COperand;
const CType = @import("sa_llvmc_free.zig").CType;
const EmitOptions = @import("sa_llvmc_free.zig").EmitOptions;
const ParallelEmitTask = @import("assign_operand.zig").ParallelEmitTask;
const cType = @import("sa_llvmc_free.zig").cType;
const emitLlvmc = @import("emit_llvmc_internal.zig").emitLlvmc;
const emitWorker = @import("assign_operand.zig").emitWorker;
const emittedFunctionName = @import("sa_llvmc_free.zig").emittedFunctionName;

pub fn atomicRmwOp(op: ?atomic.AtomicRmwOp) !CAtomicRmwOp {
    return switch (op orelse return error.InvalidOperand) {
        .add => .add,
        .sub => .sub,
        .@"and" => .band,
        .@"or" => .bor,
        .xor => .xor,
        .xchg => .xchg,
        .min => .min,
        .max => .max,
        .umin => .umin,
        .umax => .umax,
    };
}

pub fn atomicValueType(base: inst.Instruction, fallback: sig.PrimType) sig.PrimType {
    if (base.atomic_value_ty) |tag| {
        return sig.primTypeFromTag(tag) orelse fallback;
    }
    return fallback;
}

pub fn findFunctionSigIndex(sigs: []const sig.FunctionSig, name: []const u8) ?usize {
    for (sigs, 0..) |candidate, idx| {
        if (std.mem.eql(u8, candidate.name, name)) return idx;
        if (candidate.llvm_name) |llvm_name| {
            if (std.mem.eql(u8, llvm_name, name)) return idx;
        }
        if (std.mem.eql(u8, emittedFunctionName(candidate), name)) return idx;
    }
    return null;
}

pub fn putFunctionSigAlias(index: *std.StringHashMap(usize), name: []const u8, sig_idx: usize) !void {
    const entry = try index.getOrPut(name);
    if (!entry.found_existing) entry.value_ptr.* = sig_idx;
}

pub fn buildFunctionSigIndex(allocator: std.mem.Allocator, sigs: []const sig.FunctionSig) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    const max_aliases = std.math.mul(usize, sigs.len, 3) catch sigs.len;
    try index.ensureTotalCapacity(@intCast(max_aliases));
    for (sigs, 0..) |candidate, idx| {
        try putFunctionSigAlias(&index, candidate.name, idx);
        if (candidate.llvm_name) |llvm_name| try putFunctionSigAlias(&index, llvm_name, idx);
        try putFunctionSigAlias(&index, emittedFunctionName(candidate), idx);
    }
    return index;
}

/// One resolved vtable-slot candidate for the prefix-filtered indirect
/// query: the declaring const name and the callee name (for the prefix
/// predicate), plus the resolved sig index / emitted position.
pub const IndirectSlotCandidate = struct {
    decl_name: []const u8,
    func_name: []const u8,
    sig_idx: usize,
    emitted_pos: usize,
};

/// Prep-built, read-only emit tables shared by every emitWorker.
///
/// This replaces two per-function string-keyed rebuilds that made codegen
/// superlinear (synth 100k: 11,111 tasks x 11,111 const_decls):
///   - BuildState.init rebuilt `const_names` (one StringHashMap put per
///     const decl) for every function: ~123M puts @100k.
///   - inferIndirectSigIndexFrom* rescanned every vtable const decl per
///     pointer load and hashed each matching func_name into the 33k-entry
///     `emitted_sig_index`.
/// The integer key is the function-sig index: `emitted_pos_by_sig` maps a
/// sig index to its emitted task position (maxInt(u32) = pruned/not
/// emitted), so an indirect query is O(1) integer indexing after one
/// prep-time resolution of each vtable slot's func_name. The three name
/// aliases (name / llvm_name / emitted name) all resolve through
/// function_sig_index to the same sig index, hence to the same task
/// position. All tables are built once per emitLlvmc* call, live in the
/// emit arena, and are only read by workers (concurrent reads are safe).
pub const SharedEmitTables = struct {
    const_names: std.StringHashMap(void),
    emitted_pos_by_sig: []const u32,
    indirect_by_slot: std.StringHashMap(?usize),
    indirect_slot_candidates: std.StringHashMap([]const IndirectSlotCandidate),
    indirect_by_offset: []const ?usize,
};

/// Index over EMITTED task order (not source order): DCE drops unreachable
/// functions from emission, so positions in the C function table only match
/// task order. Indirect-call inference must resolve through the integer
/// key (sig index -> task position), or a Zig-side index lands on the
/// wrong C function (e.g. a void ctor shadowing a closure) whenever
/// anything was pruned.
pub fn buildSharedEmitTables(
    allocator: std.mem.Allocator,
    verified: anytype,
    tasks: []const ParallelEmitTask,
    function_sig_index: *const std.StringHashMap(usize),
) !SharedEmitTables {
    // Shared const-name set (was rebuilt per function in BuildState.init).
    var const_names = std.StringHashMap(void).init(allocator);
    errdefer const_names.deinit();
    try const_names.ensureTotalCapacity(@intCast(verified.const_decls.len));
    for (verified.const_decls) |decl| try const_names.put(decl.name, {});

    // Integer-keyed emitted positions: sig index -> task position.
    const emitted_pos_by_sig = try allocator.alloc(u32, verified.function_sigs.len);
    @memset(emitted_pos_by_sig, std.math.maxInt(u32));
    for (tasks, 0..) |task, pos| {
        emitted_pos_by_sig[task.sig_idx] = @intCast(pos);
    }

    // Merge slot candidates over sig indices (shape comparison on the true
    // sigs). A null merge result is sticky: once a slot name is ambiguous
    // the old helper returned null at once, and no later candidate may
    // resurrect it.
    var slot_merge = std.StringHashMap(?usize).init(allocator);
    defer slot_merge.deinit();
    var slot_candidates = std.StringHashMap(std.array_list.Managed(IndirectSlotCandidate)).init(allocator);
    defer slot_candidates.deinit();
    var max_slots: usize = 0;
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                max_slots = @max(max_slots, literal.slots.len);
                for (literal.slots) |slot| {
                    const sig_idx = function_sig_index.get(slot.func_name) orelse continue;
                    const emitted_pos_u32 = emitted_pos_by_sig[sig_idx];
                    if (emitted_pos_u32 == std.math.maxInt(u32)) continue;
                    const emitted_pos: usize = @intCast(emitted_pos_u32);
                    const merge_entry = try slot_merge.getOrPut(slot.name);
                    if (!merge_entry.found_existing) {
                        merge_entry.value_ptr.* = sig_idx;
                    } else if (merge_entry.value_ptr.*) |existing| {
                        merge_entry.value_ptr.* = chooseIndirectSigIndex(verified.function_sigs, existing, sig_idx);
                    }
                    const cand_entry = try slot_candidates.getOrPut(slot.name);
                    if (!cand_entry.found_existing) cand_entry.value_ptr.* = std.array_list.Managed(IndirectSlotCandidate).init(allocator);
                    try cand_entry.value_ptr.append(.{ .decl_name = decl.name, .func_name = slot.func_name, .sig_idx = sig_idx, .emitted_pos = emitted_pos });
                }
            },
            else => {},
        }
    }

    var indirect_by_slot = std.StringHashMap(?usize).init(allocator);
    errdefer indirect_by_slot.deinit();
    var slot_it = slot_merge.iterator();
    while (slot_it.next()) |entry| {
        const resolved: ?usize = if (entry.value_ptr.*) |sig_idx| @intCast(emitted_pos_by_sig[sig_idx]) else null;
        try indirect_by_slot.put(entry.key_ptr.*, resolved);
    }

    var indirect_slot_candidates = std.StringHashMap([]const IndirectSlotCandidate).init(allocator);
    errdefer indirect_slot_candidates.deinit();
    var cand_it = slot_candidates.iterator();
    while (cand_it.next()) |entry| {
        try indirect_slot_candidates.put(entry.key_ptr.*, try entry.value_ptr.toOwnedSlice());
    }

    // The offset query is a pure function of the slot position: precompute
    // the merged resolution for every slot position once.
    const indirect_by_offset = try allocator.alloc(?usize, max_slots);
    for (indirect_by_offset, 0..) |*cell, slot_index| {
        var resolved: ?usize = null;
        var ambiguous = false;
        for (verified.const_decls) |decl| {
            switch (decl.value) {
                .vtable => |literal| {
                    if (slot_index >= literal.slots.len) continue;
                    const slot = literal.slots[slot_index];
                    const sig_idx = function_sig_index.get(slot.func_name) orelse continue;
                    if (emitted_pos_by_sig[sig_idx] == std.math.maxInt(u32)) continue;
                    resolved = chooseIndirectSigIndex(verified.function_sigs, resolved, sig_idx) orelse {
                        ambiguous = true;
                        break;
                    };
                },
                else => {},
            }
        }
        cell.* = if (ambiguous) null else if (resolved) |sig_idx| @as(usize, @intCast(emitted_pos_by_sig[sig_idx])) else null;
    }

    return .{
        .const_names = const_names,
        .emitted_pos_by_sig = emitted_pos_by_sig,
        .indirect_by_slot = indirect_by_slot,
        .indirect_slot_candidates = indirect_slot_candidates,
        .indirect_by_offset = indirect_by_offset,
    };
}

pub fn markReachableFunctionByName(reachable: *std.StringHashMap(void), sigs: []const sig.FunctionSig, sig_index: *const std.StringHashMap(usize), name: []const u8) !bool {
    const idx = sig_index.get(name) orelse return false;
    const canonical_name = sigs[idx].name;
    if (reachable.contains(canonical_name)) return false;
    try reachable.put(canonical_name, {});
    return true;
}

pub fn collectBodyDirectCallees(allocator: std.mem.Allocator, verified: anytype, sig_index: *const std.StringHashMap(usize), start_idx: usize, end_idx: usize, reachable: *std.StringHashMap(void)) !bool {
    var changed = false;
    for (verified.annotated[start_idx..end_idx]) |body_item| {
        const base = body_item.base;
        if (base.kind != .call and base.kind != .call_indirect) continue;

        var parsed = call.parseInstructionCall(allocator, base, &verified.symbols) catch |err| switch (err) {
            error.InvalidCallSyntax => continue,
            else => return err,
        };
        defer parsed.deinit(allocator);

        if (parsed.is_indirect) continue;
        changed = (try markReachableFunctionByName(reachable, verified.function_sigs, sig_index, parsed.callee)) or changed;
    }
    return changed;
}

pub fn collectNormalBuildReachability(allocator: std.mem.Allocator, verified: anytype, sig_index_by_name: *const std.StringHashMap(usize), reachable: *std.StringHashMap(void)) !void {
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                for (literal.slots) |slot| {
                    _ = try markReachableFunctionByName(reachable, verified.function_sigs, sig_index_by_name, slot.func_name);
                }
            },
            else => {},
        }
    }

    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                const fsig = verified.function_sigs[sig_index];
                sig_index += 1;

                const is_main = fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main") and fsig.params.len == 0;
                const is_public_entry = item.kind == .export_decl or item.kind == .ffi_wrapper_decl or item.kind == .extern_decl;
                if (is_main or is_public_entry) {
                    try reachable.put(fsig.name, {});
                }
            },
            else => {},
        }
    }

    var changed = true;
    while (changed) {
        changed = false;
        sig_index = 0;
        idx = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    const fsig = verified.function_sigs[sig_index];
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (reachable.contains(fsig.name)) {
                        changed = (try collectBodyDirectCallees(allocator, verified, sig_index_by_name, idx + 1, end, reachable)) or changed;
                    }
                    idx = end - 1;
                },
                else => {},
            }
        }
    }
}

pub fn collectSelectedTestReachability(allocator: std.mem.Allocator, verified: anytype, sig_index_by_name: *const std.StringHashMap(usize), selected_test_names: []const []const u8, reachable: *std.StringHashMap(void)) !void {
    for (verified.const_decls) |decl| {
        switch (decl.value) {
            .vtable => |literal| {
                for (literal.slots) |slot| {
                    _ = try markReachableFunctionByName(reachable, verified.function_sigs, sig_index_by_name, slot.func_name);
                }
            },
            else => {},
        }
    }

    for (selected_test_names) |name| {
        _ = try markReachableFunctionByName(reachable, verified.function_sigs, sig_index_by_name, name);
    }

    var changed = true;
    while (changed) {
        changed = false;
        var sig_index: usize = 0;
        var idx: usize = 0;
        while (idx < verified.annotated.len) : (idx += 1) {
            const item = verified.annotated[idx].base;
            switch (item.kind) {
                .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                    if (sig_index >= verified.function_sigs.len) return error.UnknownFunction;
                    const fsig = verified.function_sigs[sig_index];
                    sig_index += 1;
                    var end = idx + 1;
                    while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                        else => true,
                    }) : (end += 1) {}

                    if (reachable.contains(fsig.name)) {
                        changed = (try collectBodyDirectCallees(allocator, verified, sig_index_by_name, idx + 1, end, reachable)) or changed;
                    }
                    idx = end - 1;
                },
                else => {},
            }
        }
    }
}

pub fn isPathSepByte(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

pub fn trimTrailingPathSeps(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 0 and isPathSepByte(path[end - 1])) : (end -= 1) {}
    return path[0..end];
}

pub fn pathIsUnderRoot(path: []const u8, root_path: []const u8) bool {
    const root = trimTrailingPathSeps(root_path);
    if (root.len == 0) return false;
    if (std.mem.eql(u8, path, root)) return true;
    return path.len > root.len and std.mem.startsWith(u8, path, root) and isPathSepByte(path[root.len]);
}

pub fn pathHasSegment(path: []const u8, segment: []const u8) bool {
    var start: usize = 0;
    while (start <= path.len) {
        var end = start;
        while (end < path.len and !isPathSepByte(path[end])) : (end += 1) {}
        if (std.mem.eql(u8, path[start..end], segment)) return true;
        if (end == path.len) break;
        start = end + 1;
    }
    return false;
}

pub fn functionSourcePath(fsig: sig.FunctionSig, source_path: []const u8) []const u8 {
    if (fsig.upstream_loc) |loc| return loc.file;
    if (fsig.upstream_file) |file| return file;
    return source_path;
}

pub fn functionHasStdOrigin(fsig: sig.FunctionSig, source_path: []const u8, std_root: ?[]const u8) bool {
    const path = functionSourcePath(fsig, source_path);
    if (std_root) |root| {
        if (pathIsUnderRoot(path, root)) return true;
    }
    return pathHasSegment(path, "sa_std");
}

pub fn markStdDceUserRoots(reachable: *std.StringHashMap(void), sigs: []const sig.FunctionSig, source_path: []const u8, std_root: ?[]const u8) !void {
    for (sigs) |fsig| {
        if (!functionHasStdOrigin(fsig, source_path, std_root)) try reachable.put(fsig.name, {});
    }
}

pub fn collectDceReachability(allocator: std.mem.Allocator, verified: anytype, sig_index_by_name: *const std.StringHashMap(usize), source_path: []const u8, options: EmitOptions, reachable: *std.StringHashMap(void)) !void {
    if (options.dce == .std) {
        try markStdDceUserRoots(reachable, verified.function_sigs, source_path, options.std_root);
    }
    try collectNormalBuildReachability(allocator, verified, sig_index_by_name, reachable);
}

pub fn shouldPruneUnreachableFunction(options: EmitOptions, fsig: sig.FunctionSig, source_path: []const u8) bool {
    return switch (options.dce) {
        .no => false,
        .full => true,
        .std => functionHasStdOrigin(fsig, source_path, options.std_root),
    };
}

pub fn functionSigShapeEqual(lhs: sig.FunctionSig, rhs: sig.FunctionSig) bool {
    if (lhs.return_cap != rhs.return_cap or lhs.return_ty != rhs.return_ty or lhs.return_fallible != rhs.return_fallible) return false;
    if (lhs.params.len != rhs.params.len) return false;
    for (lhs.params, rhs.params) |lparam, rparam| {
        if (lparam.cap != rparam.cap or lparam.ty != rparam.ty) return false;
    }
    return true;
}

pub fn offsetFromOperand(op: inst.Operand) ?u64 {
    return switch (op) {
        .imm_u64 => |v| v,
        .imm_i64, .imm_int => |v| if (v >= 0) @intCast(v) else null,
        else => null,
    };
}

pub fn slotTokenFromLoadText(raw: []const u8) ?[]const u8 {
    const plus = std.mem.indexOfScalar(u8, raw, '+') orelse return null;
    const tail = std.mem.trim(u8, raw[plus + 1 ..], " \t\r");
    const as_idx = std.mem.indexOf(u8, tail, " as ") orelse tail.len;
    const token = std.mem.trim(u8, tail[0..as_idx], " \t\r");
    return if (token.len == 0) null else token;
}

pub fn slotNameFromToken(token: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, token, '_')) |idx| {
        return token[idx + 1 ..];
    }
    return token;
}

pub fn normalizeIdentInto(buf: []u8, text: []const u8) []const u8 {
    var len: usize = 0;
    for (text) |ch| {
        if (std.ascii.isAlphanumeric(ch)) {
            if (len >= buf.len) break;
            buf[len] = std.ascii.toLower(ch);
            len += 1;
        }
    }
    return buf[0..len];
}

pub fn stripKnownTypeSuffix(text: []const u8) []const u8 {
    if (std.mem.endsWith(u8, text, "vtable")) return text[0 .. text.len - "vtable".len];
    if (std.mem.endsWith(u8, text, "vt")) return text[0 .. text.len - "vt".len];
    if (std.mem.endsWith(u8, text, "fn")) return text[0 .. text.len - "fn".len];
    return text;
}

pub fn slotPrefixKeyFromToken(buf: []u8, token: []const u8) []const u8 {
    const prefix = if (std.mem.lastIndexOfScalar(u8, token, '_')) |idx| token[0..idx] else return &.{};
    const normalized = normalizeIdentInto(buf, prefix);
    return stripKnownTypeSuffix(normalized);
}

pub fn normalizedContainsKey(buf: []u8, text: []const u8, key: []const u8) bool {
    if (key.len == 0) return false;
    const normalized = normalizeIdentInto(buf, text);
    return std.mem.indexOf(u8, normalized, key) != null;
}

/// Merge two indirect-call candidates by function shape. Both indices are
/// SIG indices (not emitted positions): the old code indexed
/// function_sigs by emitted position, which only coincides with the sig
/// index while nothing was pruned -- under DCE pruning it compared the
/// wrong pair of signatures.
pub fn chooseIndirectSigIndex(function_sigs: []const sig.FunctionSig, current: ?usize, candidate: usize) ?usize {
    if (current) |existing| {
        if (existing == candidate) return existing;
        if (functionSigShapeEqual(function_sigs[existing], function_sigs[candidate])) return existing;
        return null;
    }
    return candidate;
}

pub fn inferIndirectSigIndexFromSlot(state: *BuildState, slot_name: []const u8) ?usize {
    // Prep-resolved merged answer for this slot name (null = no single
    // resolution: absent or ambiguous, exactly as the old full scan).
    return state.shared.indirect_by_slot.get(slot_name) orelse null;
}

pub fn inferIndirectSigIndexFromSlotWithPrefix(state: *BuildState, slot_name: []const u8, prefix_key: []const u8) ?usize {
    if (prefix_key.len == 0) return null;
    const candidates = state.shared.indirect_slot_candidates.get(slot_name) orelse return null;
    var resolved: ?usize = null;
    for (candidates) |cand| {
        var decl_buf: [256]u8 = undefined;
        const decl_match = normalizedContainsKey(&decl_buf, cand.decl_name, prefix_key);
        if (!decl_match) {
            var func_buf: [256]u8 = undefined;
            if (!normalizedContainsKey(&func_buf, cand.func_name, prefix_key)) continue;
        }
        resolved = chooseIndirectSigIndex(state.function_sigs, resolved, cand.sig_idx) orelse return null;
    }
    if (resolved) |sig_idx| {
        const pos = state.shared.emitted_pos_by_sig[sig_idx];
        if (pos == std.math.maxInt(u32)) return null;
        return @intCast(pos);
    }
    return null;
}

pub fn inferIndirectSigIndexFromOffset(state: *BuildState, offset: u64) ?usize {
    if (offset % 8 != 0) return null;
    const slot_index: usize = @intCast(offset / 8);
    if (slot_index >= state.shared.indirect_by_offset.len) return null;
    return state.shared.indirect_by_offset[slot_index];
}

pub fn inferIndirectSigIndexFromLoad(state: *BuildState, base: inst.Instruction) ?usize {
    if (base.raw_text.len != 0) if (slotTokenFromLoadText(base.raw_text)) |token| {
        const slot = slotNameFromToken(token);
        var prefix_buf: [256]u8 = undefined;
        const prefix_key = slotPrefixKeyFromToken(&prefix_buf, token);
        if (inferIndirectSigIndexFromSlotWithPrefix(state, slot, prefix_key)) |idx| return idx;
        if (inferIndirectSigIndexFromSlot(state, slot)) |idx| return idx;
    };
    if (offsetFromOperand(base.operands[2])) |offset| {
        return inferIndirectSigIndexFromOffset(state, offset);
    }
    return null;
}

pub fn builtinReturnType(name: []const u8) ?CType {
    if (std.mem.eql(u8, name, "sys_argc")) return .i32;
    if (std.mem.eql(u8, name, "sys_argv")) return .ptr;
    if (std.mem.eql(u8, name, "sys_read_file")) return .ptr;
    if (std.mem.eql(u8, name, "sys_write_file")) return .i32;
    if (std.mem.eql(u8, name, "sys_print")) return .void;
    if (std.mem.eql(u8, name, "sys_exit")) return .void;
    if (std.mem.eql(u8, name, "sa_print_bytes")) return .void;
    return null;
}

/// The cast target of an `as <type>` suffix lives only in the
/// instruction's raw text (the classifier splits it off the operand;
/// emit_c's castTargetType recovers it the same way). Returns the
/// parsed target type, or null when there is no parseable suffix.
pub fn assignTargetTy(base: inst.Instruction) ?CType {
    const text = std.mem.trim(u8, base.raw_text, " \t\r\n");
    const idx = std.mem.lastIndexOf(u8, text, " as ") orelse return null;
    var tail = std.mem.trim(u8, text[idx + 4 ..], " \t\r\n");
    if (tail.len == 0) return null;
    if (std.mem.indexOfAny(u8, tail, " \t\r\n")) |end| tail = tail[0..end];
    const prim = sig.parsePrimType(tail) catch return null;
    return cType(prim) catch null;
}

pub fn assignTy(base: inst.Instruction, value: COperand) CType {
    return switch (base.kind) {
        .raw_cast => .i64,
        .borrow, .assume_safe, .assume_borrow => .ptr,
        .assign => switch (value.kind) {
            .const_ptr => .ptr,
            // DEF-WASM32-PTR-REPR: an explicit `as ptr` materializes a
            // ptr-typed register. Without this the operand's suffix
            // type is dropped here, the shim records the register as
            // i64, and a negative literal (e.g. `-1 as ptr`) lands in
            // the 64-bit slot sign-extended — while an extern ptr
            // return lands zero-extended — so MAP_FAILED-style
            // sentinel equality never fires on wasm32.
            .imm_i64, .imm_u64, .reg => if (value.ty == .ptr or (assignTargetTy(base) orelse .void) == .ptr) .ptr else .void,
            .imm_f64 => value.ty,
            else => .void,
        },
        else => .void,
    };
}

pub fn isFloatOp(opcode: inst.OpKind) bool {
    return switch (opcode) {
        .fadd, .fsub, .fmul, .fdiv, .fneg, .fcmp_eq, .fcmp_ne, .fcmp_lt, .fcmp_le, .fcmp_gt, .fcmp_ge => true,
        else => false,
    };
}

/// DEF-12: `bitcast` is a bit-pattern reinterpretation, not a numeric
/// conversion. Routing it through `.assign` made the shim apply its
/// numeric `coerce` (fptosi/sitofp/...), so `bitcast 1.5 as u64`
/// compiled to 1 instead of the IEEE bits. bitcast therefore gets its
/// own op so the shim emits a true LLVM bitcast; every other
/// conversion keeps the assign+coerce path and its numeric semantics.
pub fn conversionOp(opcode: inst.OpKind) COp {
    return if (opcode == .bitcast) .bitcast else .assign;
}

pub fn opConversionTy(base: inst.Instruction) !CType {
    if (base.operands[2] != .ty) return error.InvalidOperand;
    return try cType(sig.primTypeFromTag(base.operands[2].ty) orelse return error.InvalidOperand);
}

pub fn localizedRegName(state: *BuildState, slot_or_id: u32) ?[]const u8 {
    return state.regName(slot_or_id);
}

pub fn functionUsesGlobalRegIds(fsig: sig.FunctionSig, body: []const referee.AnnotatedInstruction) bool {
    for (body) |body_item| {
        for (body_item.base.operands) |operand| {
            if (operand == .reg) {
                const raw = operand.reg;
                if (raw >= fsig.reg_ids.len and fsig.slotOf(raw) != null) return true;
            }
        }
    }
    return false;
}

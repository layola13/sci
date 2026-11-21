const std = @import("std");
const flattener = @import("../flattener.zig");
const common_upstream = @import("../common/upstream_loc.zig");
const SabFunctionRange = @import("types.zig").SabFunctionRange;
const referee_call = @import("../referee/call.zig");
const sio = @import("sio");

pub fn pruneSabFlatToSelectedTests(allocator: std.mem.Allocator, flat: *flattener.FlattenResult, selected_test_names: []const []const u8) !void {
    if (selected_test_names.len == 0 or flat.function_sigs.len == 0 or flat.instructions.len == 0) return;
    const original_function_count = flat.function_sigs.len;
    const original_test_count = flat.test_sigs.len;
    const original_instruction_count = flat.instructions.len;
    const original_const_count = flat.const_decls.len;

    const ranges = try buildSabFunctionRanges(allocator, flat.instructions);
    defer allocator.free(ranges);
    if (ranges.len == 0) return;

    var sig_index_by_name = try buildSabFunctionSigIndex(allocator, flat.function_sigs);
    defer sig_index_by_name.deinit();

    var const_index_by_name = try buildSabConstIndex(allocator, flat.const_decls);
    defer const_index_by_name.deinit();

    var reachable_vtable_consts = std.AutoHashMap(usize, void).init(allocator);
    defer reachable_vtable_consts.deinit();

    var reachable = try collectSabSelectedReachability(allocator, flat, ranges, &sig_index_by_name, &const_index_by_name, selected_test_names, &reachable_vtable_consts);
    defer reachable.deinit();
    if (reachable.count() == 0) return;

    var kept_sigs = std.array_list.Managed(flattener.FunctionSig).init(allocator);
    errdefer kept_sigs.deinit();
    var kept_test_sigs = std.array_list.Managed(flattener.FunctionSig).init(allocator);
    errdefer kept_test_sigs.deinit();
    var kept_instructions = std.array_list.Managed(flattener.Instruction).init(allocator);
    errdefer kept_instructions.deinit();
    var kept_loc_table = std.array_list.Managed(?common_upstream.UpstreamLoc).init(allocator);
    errdefer kept_loc_table.deinit();

    var keep_ranges = try allocator.alloc(bool, ranges.len);
    defer allocator.free(keep_ranges);
    @memset(keep_ranges, false);
    for (ranges, 0..) |range, range_idx| {
        if (range.sig_index >= flat.function_sigs.len) continue;
        if (!reachable.contains(range.sig_index)) continue;
        keep_ranges[range_idx] = true;

        const function_sig = flat.function_sigs[range.sig_index];
        try kept_sigs.append(function_sig);
        if (function_sig.kind == .test_func) try kept_test_sigs.append(function_sig);
        try kept_instructions.appendSlice(flat.instructions[range.start..range.end]);
        try kept_loc_table.appendSlice(flat.loc_table[range.start..range.end]);
    }
    if (kept_sigs.items.len == 0) return;

    const new_function_sigs = try kept_sigs.toOwnedSlice();
    errdefer allocator.free(new_function_sigs);
    const new_test_sigs = try kept_test_sigs.toOwnedSlice();
    errdefer allocator.free(new_test_sigs);
    const new_instructions = try kept_instructions.toOwnedSlice();
    errdefer allocator.free(new_instructions);
    const new_loc_table = try kept_loc_table.toOwnedSlice();
    errdefer allocator.free(new_loc_table);

    try pruneSabVtableConsts(allocator, flat, &reachable_vtable_consts);

    var range_index: usize = 0;
    var instruction_index: usize = 0;
    while (instruction_index < flat.instructions.len) {
        if (range_index < ranges.len and instruction_index == ranges[range_index].start) {
            const range = ranges[range_index];
            if (!keep_ranges[range_index]) {
                for (flat.instructions[range.start..range.end]) |item| freeFlatInstructionMetadata(allocator, item);
                for (flat.loc_table[range.start..range.end]) |entry| freeFlatLocEntry(allocator, entry);
            }
            instruction_index = range.end;
            range_index += 1;
            continue;
        }
        freeFlatInstructionMetadata(allocator, flat.instructions[instruction_index]);
        freeFlatLocEntry(allocator, flat.loc_table[instruction_index]);
        instruction_index += 1;
    }

    var sig_keep = try allocator.alloc(bool, flat.function_sigs.len);
    defer allocator.free(sig_keep);
    @memset(sig_keep, false);
    for (ranges, 0..) |range, range_idx| {
        if (range.sig_index < sig_keep.len and keep_ranges[range_idx]) sig_keep[range.sig_index] = true;
    }
    for (flat.function_sigs, 0..) |*function_sig, sig_index| {
        if (!sig_keep[sig_index]) function_sig.deinit(allocator);
    }

    allocator.free(flat.function_sigs);
    allocator.free(flat.test_sigs);
    allocator.free(flat.instructions);
    allocator.free(flat.loc_table);

    flat.function_sigs = new_function_sigs;
    flat.test_sigs = new_test_sigs;
    flat.instructions = new_instructions;
    flat.loc_table = new_loc_table;

    if (sabPruneDebugEnabled(allocator)) {
        std.debug.print(
            "sab prune: funcs {d}->{d}, tests {d}->{d}, inst {d}->{d}, consts {d}->{d}, vtables_kept {d}\n",
            .{
                original_function_count,
                flat.function_sigs.len,
                original_test_count,
                flat.test_sigs.len,
                original_instruction_count,
                flat.instructions.len,
                original_const_count,
                flat.const_decls.len,
                reachable_vtable_consts.count(),
            },
        );
    }
}

pub fn buildSabFunctionRanges(allocator: std.mem.Allocator, instructions: []const flattener.Instruction) ![]SabFunctionRange {
    var ranges = std.array_list.Managed(SabFunctionRange).init(allocator);
    errdefer ranges.deinit();

    var current_start: ?usize = null;
    var current_sig_index: usize = 0;
    var next_sig_index: usize = 0;
    for (instructions, 0..) |item, idx| {
        if (!isSabFunctionDecl(item.kind)) continue;
        if (current_start) |start| {
            try ranges.append(.{
                .sig_index = current_sig_index,
                .start = start,
                .end = idx,
            });
        }
        current_start = idx;
        current_sig_index = next_sig_index;
        next_sig_index += 1;
    }
    if (current_start) |start| {
        try ranges.append(.{
            .sig_index = current_sig_index,
            .start = start,
            .end = instructions.len,
        });
    }
    return try ranges.toOwnedSlice();
}

pub fn buildSabFunctionSigIndex(allocator: std.mem.Allocator, function_sigs: []const flattener.FunctionSig) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    const max_aliases = std.math.mul(usize, function_sigs.len, 2) catch function_sigs.len;
    try index.ensureTotalCapacity(@intCast(max_aliases));
    for (function_sigs, 0..) |function_sig, sig_index| {
        try putSabFunctionAlias(&index, function_sig.name, sig_index);
        if (function_sig.llvm_name) |llvm_name| try putSabFunctionAlias(&index, llvm_name, sig_index);
    }
    return index;
}

pub fn isSabFunctionDecl(kind: flattener.InstKind) bool {
    return switch (kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => true,
        else => false,
    };
}

pub fn buildSabConstIndex(allocator: std.mem.Allocator, const_decls: []const flattener.ConstDecl) !std.StringHashMap(usize) {
    var index = std.StringHashMap(usize).init(allocator);
    errdefer index.deinit();
    try index.ensureTotalCapacity(@intCast(const_decls.len));
    for (const_decls, 0..) |decl, const_index| {
        if (!index.contains(decl.name)) try index.put(decl.name, const_index);
    }
    return index;
}

pub fn putSabFunctionAlias(index: *std.StringHashMap(usize), name: []const u8, sig_index: usize) !void {
    if (name.len == 0 or index.contains(name)) return;
    try index.put(name, sig_index);
}

pub fn markSabReachableByName(
    reachable: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    name: []const u8,
) !bool {
    const sig_index = sig_index_by_name.get(name) orelse return false;
    if (reachable.contains(sig_index)) return false;
    try reachable.put(sig_index, {});
    return true;
}

pub fn markSabReachableVtableConstByName(
    reachable_functions: *std.AutoHashMap(usize, void),
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    const_decls: []const flattener.ConstDecl,
    name: []const u8,
) !bool {
    const normalized = sabReferenceName(name);
    if (normalized.len == 0) return false;
    const const_index = const_index_by_name.get(normalized) orelse return false;
    switch (const_decls[const_index].value) {
        .vtable => |literal| {
            var changed = false;
            if (!reachable_vtable_consts.contains(const_index)) {
                try reachable_vtable_consts.put(const_index, {});
                changed = true;
            }
            for (literal.slots) |slot| {
                changed = (try markSabReachableByName(reachable_functions, sig_index_by_name, slot.func_name)) or changed;
            }
            return changed;
        },
        else => return false,
    }
}

pub fn markSabReachableVtableConstFromOperand(
    reachable_functions: *std.AutoHashMap(usize, void),
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    flat: *const flattener.FlattenResult,
    operand: anytype,
) !bool {
    const text = switch (operand) {
        .reg => |id| flat.symbols.lookupName(id),
        .symbol => |id| flat.symbols.lookupName(id),
        .label => |id| flat.symbols.lookupName(id),
        .func => |id| flat.symbols.lookupName(id),
        .text => |value| value,
        .native_text => |value| value,
        else => null,
    } orelse return false;
    return try markSabReachableVtableConstByName(reachable_functions, reachable_vtable_consts, sig_index_by_name, const_index_by_name, flat.const_decls, text);
}

pub fn collectSabSelectedReachability(
    allocator: std.mem.Allocator,
    flat: *const flattener.FlattenResult,
    ranges: []const SabFunctionRange,
    sig_index_by_name: *const std.StringHashMap(usize),
    const_index_by_name: *const std.StringHashMap(usize),
    selected_test_names: []const []const u8,
    reachable_vtable_consts: *std.AutoHashMap(usize, void),
) !std.AutoHashMap(usize, void) {
    var reachable = std.AutoHashMap(usize, void).init(allocator);
    errdefer reachable.deinit();

    for (selected_test_names) |name| {
        _ = try markSabReachableByName(&reachable, sig_index_by_name, name);
    }

    var changed = true;
    while (changed) {
        changed = false;
        for (ranges) |range| {
            if (!reachable.contains(range.sig_index)) continue;
            for (flat.instructions[range.start..range.end]) |item| {
                if (item.kind != .call and item.kind != .call_indirect) continue;
                var parsed = referee_call.parseInstructionCall(allocator, item, &flat.symbols) catch |err| switch (err) {
                    error.InvalidCallSyntax => continue,
                    else => return err,
                };
                defer parsed.deinit(allocator);
                if (parsed.is_indirect) continue;
                changed = (try markSabReachableByName(&reachable, sig_index_by_name, parsed.callee)) or changed;
            }
            for (flat.instructions[range.start..range.end]) |item| {
                inline for (0..4) |operand_index| {
                    changed = (try markSabReachableVtableConstFromOperand(&reachable, reachable_vtable_consts, sig_index_by_name, const_index_by_name, flat, item.operands[operand_index])) or changed;
                }
            }
        }
    }

    return reachable;
}

pub fn sabReferenceName(text: []const u8) []const u8 {
    var trimmed = std.mem.trim(u8, text, " \t\r");
    while (trimmed.len != 0 and (trimmed[0] == '&' or trimmed[0] == '^' or trimmed[0] == '*')) {
        trimmed = std.mem.trim(u8, trimmed[1..], " \t\r");
    }
    return trimmed;
}

pub fn pruneSabVtableConsts(
    allocator: std.mem.Allocator,
    flat: *flattener.FlattenResult,
    reachable_vtable_consts: *const std.AutoHashMap(usize, void),
) !void {
    if (flat.const_decls.len == 0) return;

    var keep = try allocator.alloc(bool, flat.const_decls.len);
    defer allocator.free(keep);
    var pruned_any = false;
    var kept_count: usize = 0;
    for (flat.const_decls, 0..) |decl, const_index| {
        keep[const_index] = switch (decl.value) {
            .vtable => reachable_vtable_consts.contains(const_index),
            else => true,
        };
        if (keep[const_index]) {
            kept_count += 1;
        } else {
            pruned_any = true;
        }
    }
    if (!pruned_any) return;

    const new_const_decls = try allocator.alloc(flattener.ConstDecl, kept_count);
    var kept_index: usize = 0;
    for (flat.const_decls, 0..) |decl, const_index| {
        if (keep[const_index]) {
            new_const_decls[kept_index] = decl;
            kept_index += 1;
        } else {
            var dropped = decl;
            dropped.deinit(allocator);
        }
    }
    allocator.free(flat.const_decls);
    flat.const_decls = new_const_decls;
}

pub fn sabPruneDebugEnabled(allocator: std.mem.Allocator) bool {
    const value = sio.getEnvVarOwned(allocator, "SA_DEBUG_SAB_PRUNE") catch return false;
    defer allocator.free(value);
    return value.len != 0 and !std.mem.eql(u8, value, "0");
}

pub fn freeFlatInstructionMetadata(allocator: std.mem.Allocator, item: flattener.Instruction) void {
    if (item.package_identity) |identity| allocator.free(identity);
    if (item.upstream_loc) |loc| allocator.free(loc.file);
    if (item.native_reg_names.len != 0) allocator.free(item.native_reg_names);
}

pub fn freeFlatLocEntry(allocator: std.mem.Allocator, entry: ?common_upstream.UpstreamLoc) void {
    if (entry) |loc| allocator.free(loc.file);
}

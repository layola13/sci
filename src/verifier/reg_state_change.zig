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

const freeAnnotatedSlice = @import("free_annotated_slice.zig").freeAnnotatedSlice;
const verify = @import("free_annotated_slice.zig").verify;

pub const RegStateChange = struct {
    reg: u32,
    before: u16,
    after: u16,
};

pub const RegStateDelta = struct {
    changes: []RegStateChange,

    pub fn deinit(self: *RegStateDelta, allocator: std.mem.Allocator) void {
        if (self.changes.len != 0) allocator.free(self.changes);
        self.* = undefined;
    }
};

pub const empty_reg_state_changes: [0]RegStateChange = .{};

pub fn emptyRegStateDelta() RegStateDelta {
    return .{ .changes = @constCast(empty_reg_state_changes[0..]) };
}

pub const AnnotatedInstruction = struct {
    base: inst.Instruction,
    delta: RegStateDelta,
    gas_step_cost: u32,

    pub fn deinit(self: *AnnotatedInstruction, allocator: std.mem.Allocator) void {
        self.delta.deinit(allocator);
        self.* = undefined;
    }
};

pub const VerifyOk = struct {
    annotated: []AnnotatedInstruction,
    function_sigs: []sig.FunctionSig,
    symbols: symbol.SymbolTable,
    const_decls: []const const_decl.ConstDecl = &.{},
    gas: gas.GasReport,

    pub fn deinit(self: *VerifyOk, allocator: std.mem.Allocator) void {
        for (self.annotated) |item| {
            var owned = item;
            owned.deinit(allocator);
        }
        allocator.free(self.annotated);
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

pub const ParallelFunctionChunk = struct {
    start: usize,
    end: usize,
    sig_index: usize,
};

pub const VerifyOptions = struct {
    jobs: ?usize = null,
    package_grants: []const pkg_manifest.RequireEntry = &.{},
    sax_context: ?SaxValidationContext = null,
    stage_reporter: ?VerifyStageReporter = null,
    predecoded_symbol_names: []const []const u8 = &.{},
    predecoded_function_sigs: []const sig.FunctionSig = &.{},
    check_exit_leaks: bool = true,
    /// Rust-style mutability: an allocation binds an immutable value. Writing
    /// through it requires an explicit exclusive borrow (`x = &mut y`).
    default_immutable: bool = false,
};

pub const VerifyStageReporter = struct {
    context: *anyopaque,
    report_fn: *const fn (*anyopaque, []const u8, usize, usize) void,

    pub fn report(self: VerifyStageReporter, stage: []const u8, completed: usize, total: usize) void {
        self.report_fn(self.context, stage, completed, total);
    }
};

pub const SaxValidationContext = struct {
    component_name: []const u8,
};

pub const VerifyBodyOk = struct {
    annotated: []AnnotatedInstruction,
    gas: gas.GasReport,
    has_unbounded_loop: bool,
};

pub const VerifyBodyResult = union(enum) {
    ok: VerifyBodyOk,
    trap: trap.TrapReport,
};

pub fn appendRandomLocBlock(
    writer: anytype,
    random: std.Random,
    expected: *?upstream.UpstreamLoc,
    min_count: u8,
) !void {
    const count = if (min_count >= 3) 3 else random.intRangeAtMost(u8, min_count, 3);
    var idx: u8 = 0;
    while (idx < count) : (idx += 1) {
        const line = random.intRangeAtMost(u32, 1, 2000);
        const col = random.intRangeAtMost(u32, 1, 80);
        try writer.print("#loc \"pbt.rs\":{d}:{d}\n", .{ line, col });
        expected.* = .{ .file = "pbt.rs", .line = line, .col = col };
    }
}

pub fn expectOptionalUpstreamLoc(actual: ?upstream.UpstreamLoc, expected: ?upstream.UpstreamLoc) !void {
    if (expected) |exp| {
        const act = actual orelse return error.TestUnexpectedResult;
        try std.testing.expectEqualStrings(exp.file, act.file);
        try std.testing.expectEqual(exp.line, act.line);
        try std.testing.expectEqual(exp.col, act.col);
    } else {
        try std.testing.expect(actual == null);
    }
}

pub fn expectTrapReportUpstreamLoc(report: trap.TrapReport, expected: ?upstream.UpstreamLoc) !void {
    if (expected) |exp| {
        if (report.upstream_loc) |act| {
            try std.testing.expectEqualStrings(exp.file, act.file);
            try std.testing.expectEqual(exp.line, act.line);
            try std.testing.expectEqual(exp.col, act.col);
            return;
        }

        const file = std.mem.sliceTo(&report.upstream_file_buf, 0);
        try std.testing.expectEqualStrings(exp.file, file);
        try std.testing.expectEqual(exp.line, report.upstream_line);
        try std.testing.expectEqual(exp.col, report.upstream_col);
    } else {
        try std.testing.expect(report.upstream_loc == null);
        try std.testing.expect(std.mem.sliceTo(&report.upstream_file_buf, 0).len == 0);
        try std.testing.expectEqual(@as(u32, 0), report.upstream_line);
        try std.testing.expectEqual(@as(u32, 0), report.upstream_col);
    }
}

pub const ParallelVerifyJob = struct {
    result: ?VerifyBodyResult = null,
    err: ?anyerror = null,
    worker_index: usize = 0,
    /// Stream-merge publication state: 0 = pending, 1 = ok published,
    /// 2 = trap published, 3 = error, 4 = consumed by the merger.
    /// Written by the owning worker with .release after result/err are
    /// set; read by the merger with .acquire.
    state: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
};

pub const ParallelVerifyWorker = struct {
    // thread_safe: the stream merger frees a worker's published chunk
    // result from the merger thread while the worker is already
    // verifying its next chunk with the same allocator.
    gpa: std.heap.DebugAllocator(.{ .thread_safe = true }) = .{},

    pub fn allocator(self: *ParallelVerifyWorker) std.mem.Allocator {
        return self.gpa.allocator();
    }

    pub fn deinit(self: *ParallelVerifyWorker) void {
        _ = self.gpa.deinit();
        self.* = .{};
    }
};

pub fn cleanupParallelJobResults(jobs: []ParallelVerifyJob, workers: []ParallelVerifyWorker) void {
    for (jobs) |*job| {
        const result = job.result orelse continue;
        switch (result) {
            .ok => |ok| {
                const worker_index = job.worker_index;
                if (worker_index < workers.len) {
                    freeAnnotatedSlice(workers[worker_index].allocator(), ok.annotated);
                }
            },
            .trap => {},
        }
        job.result = null;
    }
}

pub const ParallelVerifyContext = struct {
    allocator: std.mem.Allocator,
    instructions: []const inst.Instruction,
    classified_lines: []const classifier.ClassifiedLine,
    const_decls: []const const_decl.ConstDecl,
    metadata: *const CollectResult,
    package_grants: []const pkg_manifest.RequireEntry,
    sax_context: ?SaxValidationContext,
    chunks: []const ParallelFunctionChunk,
    jobs: []ParallelVerifyJob,
    workers: []ParallelVerifyWorker,
    requested_jobs: ?usize,
    check_exit_leaks: bool,
    default_immutable: bool,
    next_chunk: std.atomic.Value(usize),
    workers_done: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
};

pub const CollectResult = struct {
    symbols: symbol.SymbolTable,
    sigs: std.array_list.Managed(sig.FunctionSig),
    sig_index_by_name: std.StringHashMap(usize),
    const_vtables: std.array_list.Managed(ConstVTable),
    function_starts: std.array_list.Managed(usize),
    // Const global ids, built once per verify call (OPTIMIZE-IMPL-1 step 2).
    const_ids: std.AutoHashMap(u32, void),
};

pub var test_classify_line_count: if (builtin.is_test) usize else void = if (builtin.is_test) 0 else {};
pub var test_consumed_scan_count: if (builtin.is_test) usize else void = if (builtin.is_test) 0 else {};

pub fn resetTestClassifyLineCount() void {
    if (builtin.is_test) test_classify_line_count = 0;
}

pub fn readTestClassifyLineCount() usize {
    return if (builtin.is_test) test_classify_line_count else 0;
}

pub fn resetTestConsumedScanCount() void {
    if (builtin.is_test) test_consumed_scan_count = 0;
}

pub fn readTestConsumedScanCount() usize {
    return if (builtin.is_test) test_consumed_scan_count else 0;
}

pub fn symbolName(symbol_names: []const []const u8, id: u32) []const u8 {
    const idx: usize = @intCast(id);
    if (idx >= symbol_names.len) return "";
    return symbol_names[idx];
}

pub fn operandName(symbol_names: []const []const u8, operand: inst.Operand) []const u8 {
    return switch (operand) {
        .reg => |id| symbolName(symbol_names, id),
        .symbol => |id| symbolName(symbol_names, id),
        .label => |id| symbolName(symbol_names, id),
        .func => |id| symbolName(symbol_names, id),
        .text => |text| text,
        .native_text => |text| text,
        else => "",
    };
}

pub fn operandDebugName(operand: inst.Operand) []const u8 {
    return switch (operand) {
        .reg => |id| switch (id) {
            0 => "r0",
            1 => "r1",
            2 => "r2",
            3 => "r3",
            4 => "r4",
            5 => "r5",
            6 => "r6",
            7 => "r7",
            8 => "r8",
            9 => "r9",
            else => "r",
        },
        .text => |text| text,
        .native_text => |text| text,
        else => "",
    };
}

pub fn structuredInstForm(kind: inst.InstKind) ?classifier.InstructionForm {
    return switch (kind) {
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
        .try_ => .try_,
        .panic => .panic,
        .panic_msg => .panic_msg,
        .return_ => .return_,
        .take => .take,
        .raw_cast => .raw_cast,
        .assume_safe => .assume_safe,
        .assume_borrow => .assume_borrow,
        .va_start => .va_start,
        .va_arg => .va_arg,
        .va_end => .va_end,
        .transfer => .transfer,
        else => null,
    };
}

pub fn structuredLineKind(kind: inst.InstKind) classifier.LineKind {
    return switch (kind) {
        .func_decl => .func_decl,
        .ffi_wrapper_decl => .ffi_wrapper_decl,
        .extern_decl => .extern_decl,
        .export_decl => .export_decl,
        .test_decl => .test_decl,
        .gpu_decl => .gpu_decl,
        .label => .label,
        .native => .native,
        else => if (structuredInstForm(kind) != null) .instruction else .unknown,
    };
}

pub fn addStructuredPart(line: *classifier.ClassifiedLine, idx: usize, value: []const u8) void {
    if (idx >= line.parts.len) return;
    line.parts[idx] = value;
    const count: u8 = @intCast(idx + 1);
    if (line.part_count < count) line.part_count = count;
}

pub fn classifyStructuredInstruction(item: inst.Instruction, symbol_names: []const []const u8) classifier.ClassifiedLine {
    var out = classifier.ClassifiedLine{
        .kind = structuredLineKind(item.kind),
        .inst_form = structuredInstForm(item.kind),
        .raw = item.raw_text,
        .trimmed = item.raw_text,
    };

    switch (item.kind) {
        .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
        },
        .label => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[1]));
        },
        .alloc, .stack_alloc, .assign, .atomic_load, .raw_cast, .assume_safe => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
        },
        .load, .take, .ptr_add => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
            addStructuredPart(&out, 2, operandName(symbol_names, item.operands[2]));
        },
        .store, .atomic_store => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
            addStructuredPart(&out, 2, operandName(symbol_names, item.operands[2]));
        },
        .cmpxchg, .atomic_rmw => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
            addStructuredPart(&out, 2, operandName(symbol_names, item.operands[2]));
            addStructuredPart(&out, 3, operandName(symbol_names, item.operands[3]));
        },
        .op => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            if (item.op_kind) |op| addStructuredPart(&out, 1, @tagName(op));
            addStructuredPart(&out, 2, operandName(symbol_names, item.operands[1]));
            addStructuredPart(&out, 3, operandName(symbol_names, item.operands[2]));
            addStructuredPart(&out, 4, operandName(symbol_names, item.operands[3]));
        },
        .borrow, .assume_borrow => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[2]));
            addStructuredPart(&out, 2, operandName(symbol_names, item.operands[1]));
        },
        .move_, .release, .return_, .panic, .panic_msg, .call_indirect, .try_, .transfer => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
        },
        .jmp => addStructuredPart(&out, 0, operandName(symbol_names, item.operands[1])),
        .br, .br_null => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
            addStructuredPart(&out, 2, operandName(symbol_names, item.operands[3]));
        },
        .call => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
        },
        .native => addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0])),
        .va_start => addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0])),
        .va_arg => {
            addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0]));
            addStructuredPart(&out, 1, operandName(symbol_names, item.operands[1]));
            if (item.operands[2] == .ty) {
                if (sig.primTypeFromTag(item.operands[2].ty)) |ty| addStructuredPart(&out, 2, sig.primTypeName(ty));
            }
        },
        .va_end => addStructuredPart(&out, 0, operandName(symbol_names, item.operands[0])),
        else => {},
    }
    return out;
}

pub fn classifyInstructions(allocator: std.mem.Allocator, instructions: []const inst.Instruction, symbol_names: []const []const u8) ![]classifier.ClassifiedLine {
    const classified_lines = try allocator.alloc(classifier.ClassifiedLine, instructions.len);
    errdefer allocator.free(classified_lines);
    for (instructions, 0..) |item, idx| {
        if (builtin.is_test) test_classify_line_count += 1;
        classified_lines[idx] = if (symbol_names.len != 0 and structuredLineKind(item.kind) != .unknown)
            classifyStructuredInstruction(item, symbol_names)
        else
            classifier.classifyLine(item.raw_text);
    }
    return classified_lines;
}

pub const FunctionRegScope = struct {
    allocator: std.mem.Allocator,
    reg_ids: []const u32,
    owns_reg_ids: bool = true,
    slot_by_id: std.AutoHashMap(u32, u32),

    pub fn init(allocator: std.mem.Allocator, reg_ids: []const u32) !FunctionRegScope {
        var slot_by_id = std.AutoHashMap(u32, u32).init(allocator);
        errdefer slot_by_id.deinit();
        try slot_by_id.ensureTotalCapacity(@intCast(reg_ids.len));
        for (reg_ids, 0..) |reg_id, idx| {
            _ = slot_by_id.putAssumeCapacity(reg_id, @intCast(idx));
        }
        return .{
            .allocator = allocator,
            .reg_ids = reg_ids,
            .owns_reg_ids = true,
            .slot_by_id = slot_by_id,
        };
    }

    pub fn initBorrowed(allocator: std.mem.Allocator, reg_ids: []const u32) !FunctionRegScope {
        var scope = try FunctionRegScope.init(allocator, reg_ids);
        scope.owns_reg_ids = false;
        return scope;
    }

    pub fn deinit(self: *FunctionRegScope) void {
        self.slot_by_id.deinit();
        if (self.owns_reg_ids and self.reg_ids.len != 0) self.allocator.free(self.reg_ids);
        self.* = undefined;
    }

    pub fn slotOf(self: *const FunctionRegScope, reg_id: u32) ?u32 {
        return self.slot_by_id.get(reg_id);
    }

    pub fn globalId(self: *const FunctionRegScope, slot: u32) u32 {
        return self.reg_ids[@intCast(slot)];
    }

    pub fn nameOf(self: *const FunctionRegScope, symbols: *const symbol.SymbolTable, slot: u32) ?[]const u8 {
        if (@as(usize, @intCast(slot)) >= self.reg_ids.len) return null;
        return symbols.lookupName(self.globalId(slot));
    }
};

pub const ConstVTableSlot = struct {
    slot_name: []const u8,
    function_name: []const u8,
    signature: sig.FunctionSig,
};

pub const ConstVTable = struct {
    name: []const u8,
    slots: []ConstVTableSlot,

    pub fn deinit(self: *ConstVTable, allocator: std.mem.Allocator) void {
        allocator.free(self.slots);
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const CallProvenance = struct {
    callee_name: []const u8,
    is_vtable_slot: bool = false,
    vtable_name: ?[]const u8 = null,
    slot_name: ?[]const u8 = null,
    slot_signature: ?sig.FunctionSig = null,
    const_name: ?[]const u8 = null,
};

pub const ValueProvenance = struct {
    const_decl_idx: ?u32 = null,
    const_offset: u64 = 0,
    indirect_sig_index: ?usize = null,
};

pub fn maskOf(tag: cap.CapabilityMask) u16 {
    return @intFromEnum(tag);
}

pub fn trapCode(kind: trap.Trap) u32 {
    return trap.trapCode(kind);
}

pub fn trimTrailingCr(text: []const u8) []const u8 {
    return std.mem.trimEnd(u8, text, "\r");
}

pub fn copyTextBuf(dest: []u8, text: []const u8) void {
    const len = @min(dest.len, text.len);
    std.mem.copyForwards(u8, dest[0..len], text[0..len]);
}

pub const regFlagRawPointer: u8 = 0x01;
pub const regFlagStackAlloc: u8 = 0x02;
pub const regFlagImmutable: u8 = 0x04;
pub const regFlagBranchCondition: u8 = 0x08;
pub const regFlagEphemeralScalar: u8 = 0x10;

pub const InteriorContext = struct {
    state: []u16,
    interior_parent: []?u32,
    interior_first_child: []?u32,
    interior_next_sibling: []?u32,
    interior_root: []?u32,
    interior_offset: []u64,
    interior_offset_known: []bool,
    alloc_size: []u64,
    alloc_size_known: []bool,
};

pub const LabelStateChange = struct {
    reg: u32,
    state: ?u16 = null,
    origins: ?u32 = null,
    locks: ?u16 = null,
    flags: ?u8 = null,
    interior_parent: ?u32 = null,
    interior_first_child: ?u32 = null,
    interior_next_sibling: ?u32 = null,
    interior_root: ?u32 = null,
    interior_offset: ?u64 = null,
    interior_offset_known: ?bool = null,
    alloc_size: ?u64 = null,
    alloc_size_known: ?bool = null,
};

pub const LabelSnapshot = struct {
    changes: []LabelStateChange,

    pub fn deinit(self: *LabelSnapshot, allocator: std.mem.Allocator) void {
        if (self.changes.len != 0) allocator.free(self.changes);
        self.* = undefined;
    }
};

pub fn isIdentLike(text: []const u8) bool {
    return text.len != 0 and (std.ascii.isAlphabetic(text[0]) or text[0] == '_');
}

pub fn isImmutable(mask: u16) bool {
    return (mask & maskOf(.immutable)) != 0;
}

pub fn isImmutableConst(state: []const u16, flags: []const u8, id: u32) bool {
    const idx: usize = @intCast(id);
    return isImmutable(state[idx]) or (flags[idx] & regFlagImmutable) != 0;
}

/// Const data (`@const`) is a hard constant: it can never be written, moved,
/// released, or exclusively borrowed. An immutable binding (the Rust-style
/// `let`) only forbids writing and overwriting; it can still be moved,
/// released, and mutably borrowed.
pub fn isConstData(flags: []const u8, id: u32) bool {
    const idx: usize = @intCast(id);
    return (flags[idx] & regFlagImmutable) != 0;
}

/// The mask a fresh allocation starts with. Rust-style mutability binds an
/// immutable value by default, so the caller has to take an exclusive borrow
/// before writing through it.
pub fn allocDefaultMask(default_immutable: bool) u16 {
    if (default_immutable) return maskOf(.active) | maskOf(.immutable);
    return maskOf(.active);
}

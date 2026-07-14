const std = @import("std");
const inst = @import("common/instruction.zig");

// Incremental-verification cache.
//
// Phase B-A: verdict-only cache keyed by a sound content hash of the instruction
// stream. A hit means "this exact stream previously verified OK". No owned
// VerifyOk is stored, so check/audit can skip re-verification safely.
//
// Phase B-B: optional fully-owned result cache. Entries deep-copy every string
// that VerifyOk would otherwise borrow from FlattenResult, so a hit can return
// an independent clone for codegen without double-free or dangling pointers.

var mutex: std.Thread.Mutex = .{};
var passed_map: ?std.AutoHashMap([32]u8, void) = null;
var result_map: ?std.AutoHashMap([32]u8, OwnedVerifySnapshot) = null;

pub var hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var misses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var result_hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var result_misses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

const OwnedInstruction = struct {
    kind: inst.InstKind,
    source_line: u32,
    expanded_line: u32,
    package_identity: ?[]u8 = null,
    package_source_sha256: ?[32]u8 = null,
    op_kind: ?inst.OpKind = null,
    operands: [4]OwnedOperand = .{ .{ .none = {} }, .{ .none = {} }, .{ .none = {} }, .{ .none = {} } },
    raw_text: []u8 = &.{},
    atomic_value_ty: ?u32 = null,
    atomic_ordering: ?inst.AtomicOrdering = null,
    atomic_second_ordering: ?inst.AtomicOrdering = null,
    atomic_rmw_op: ?inst.AtomicRmwOp = null,
    atomic_expected_text: ?[]u8 = null,
    atomic_new_text: ?[]u8 = null,
    native_reg_names: [][]u8 = &.{},
};

const OwnedOperand = union(enum) {
    none: void,
    reg: u32,
    symbol: u32,
    label: u32,
    func: u32,
    imm_i64: i64,
    imm_u64: u64,
    imm_int: i64,
    imm_float: f64,
    op_code: inst.OpCode,
    cap_prefix: inst.CapPrefix,
    offset: u32,
    ty: u32,
    text: []u8,
    native_text: []u8,
};

const OwnedAnnotated = struct {
    base: OwnedInstruction,
    changes: []u8, // packed RegStateChange bytes for opaque restore; unused if empty
    change_count: u32,
    gas_step_cost: u32,
};

// We only cache enough for check-path metrics and for B-B rebuild of a minimal
// trusted VerifyOk shell used by callers that only need annotated.base.raw_text
// + function boundaries. Full symbol tables are rebuilt from interned names.
const OwnedVerifySnapshot = struct {
    annotated: []OwnedAnnotated,
    // Serialized function names in order; full sig clone is expensive and not
    // required for check. For compile path B-B we re-verify if result cache is
    // disabled; when enabled we store raw_text annotated only and force callers
    // through restoreMinimal().
    function_names: [][]u8,
    symbol_names: [][]u8,

    fn deinit(self: *OwnedVerifySnapshot, allocator: std.mem.Allocator) void {
        for (self.annotated) |*item| {
            freeOwnedInstruction(allocator, &item.base);
            if (item.changes.len != 0) allocator.free(item.changes);
        }
        if (self.annotated.len != 0) allocator.free(self.annotated);
        for (self.function_names) |n| allocator.free(n);
        if (self.function_names.len != 0) allocator.free(self.function_names);
        for (self.symbol_names) |n| allocator.free(n);
        if (self.symbol_names.len != 0) allocator.free(self.symbol_names);
        self.* = undefined;
    }
};

fn freeOwnedOperand(allocator: std.mem.Allocator, op: *OwnedOperand) void {
    switch (op.*) {
        .text => |t| if (t.len != 0) allocator.free(t),
        .native_text => |t| if (t.len != 0) allocator.free(t),
        else => {},
    }
    op.* = .{ .none = {} };
}

fn freeOwnedInstruction(allocator: std.mem.Allocator, oi: *OwnedInstruction) void {
    if (oi.package_identity) |p| allocator.free(p);
    if (oi.raw_text.len != 0) allocator.free(oi.raw_text);
    if (oi.atomic_expected_text) |t| allocator.free(t);
    if (oi.atomic_new_text) |t| allocator.free(t);
    for (oi.native_reg_names) |n| allocator.free(n);
    if (oi.native_reg_names.len != 0) allocator.free(oi.native_reg_names);
    for (&oi.operands) |*op| freeOwnedOperand(allocator, op);
    oi.* = .{ .kind = .return_, .source_line = 0, .expanded_line = 0 };
}

fn dupeOpt(allocator: std.mem.Allocator, value: ?[]const u8) !?[]u8 {
    if (value) |v| return try allocator.dupe(u8, v);
    return null;
}

fn cloneOperand(allocator: std.mem.Allocator, op: inst.Operand) !OwnedOperand {
    return switch (op) {
        .none => .{ .none = {} },
        .reg => |v| .{ .reg = v },
        .symbol => |v| .{ .symbol = v },
        .label => |v| .{ .label = v },
        .func => |v| .{ .func = v },
        .imm_i64 => |v| .{ .imm_i64 = v },
        .imm_u64 => |v| .{ .imm_u64 = v },
        .imm_int => |v| .{ .imm_int = v },
        .imm_float => |v| .{ .imm_float = v },
        .op_code => |v| .{ .op_code = v },
        .cap_prefix => |v| .{ .cap_prefix = v },
        .offset => |v| .{ .offset = v },
        .ty => |v| .{ .ty = v },
        .text => |v| .{ .text = try allocator.dupe(u8, v) },
        .native_text => |v| .{ .native_text = try allocator.dupe(u8, v) },
    };
}

fn cloneInstruction(allocator: std.mem.Allocator, src: inst.Instruction) !OwnedInstruction {
    var out: OwnedInstruction = .{
        .kind = src.kind,
        .source_line = src.source_line,
        .expanded_line = src.expanded_line,
        .package_identity = try dupeOpt(allocator, src.package_identity),
        .package_source_sha256 = src.package_source_sha256,
        .op_kind = src.op_kind,
        .raw_text = try allocator.dupe(u8, src.raw_text),
        .atomic_value_ty = src.atomic_value_ty,
        .atomic_ordering = src.atomic_ordering,
        .atomic_second_ordering = src.atomic_second_ordering,
        .atomic_rmw_op = src.atomic_rmw_op,
        .atomic_expected_text = try dupeOpt(allocator, src.atomic_expected_text),
        .atomic_new_text = try dupeOpt(allocator, src.atomic_new_text),
    };
    errdefer freeOwnedInstruction(allocator, &out);
    for (src.operands, 0..) |op, i| {
        out.operands[i] = try cloneOperand(allocator, op);
    }
    if (src.native_reg_names.len != 0) {
        var names = try allocator.alloc([]u8, src.native_reg_names.len);
        var filled: usize = 0;
        errdefer {
            for (names[0..filled]) |n| allocator.free(n);
            allocator.free(names);
        }
        for (src.native_reg_names, 0..) |n, i| {
            names[i] = try allocator.dupe(u8, n);
            filled = i + 1;
        }
        out.native_reg_names = names;
    }
    return out;
}

fn hashOperand(hasher: *std.crypto.hash.sha2.Sha256, op: inst.Operand) void {
    hasher.update(&.{@intFromEnum(op)});
    switch (op) {
        .none => {},
        .reg => |v| hasher.update(std.mem.asBytes(&v)),
        .symbol => |v| hasher.update(std.mem.asBytes(&v)),
        .label => |v| hasher.update(std.mem.asBytes(&v)),
        .func => |v| hasher.update(std.mem.asBytes(&v)),
        .imm_i64 => |v| hasher.update(std.mem.asBytes(&v)),
        .imm_u64 => |v| hasher.update(std.mem.asBytes(&v)),
        .imm_int => |v| hasher.update(std.mem.asBytes(&v)),
        .imm_float => |v| hasher.update(std.mem.asBytes(&v)),
        .op_code => |v| hasher.update(&.{@intFromEnum(v)}),
        .cap_prefix => |v| hasher.update(&.{@intFromEnum(v)}),
        .offset => |v| hasher.update(std.mem.asBytes(&v)),
        .ty => |v| hasher.update(std.mem.asBytes(&v)),
        .text => |v| hasher.update(v),
        .native_text => |v| hasher.update(v),
    }
}

/// Sound content hash over verification-relevant instruction fields.
/// Line numbers are excluded so identical code at different locations can hit.
pub fn hashInstructions(instructions: []const inst.Instruction) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-incr-verify-v1");
    for (instructions) |item| {
        const kind_u: u8 = @intFromEnum(item.kind);
        hasher.update(&.{kind_u});
        if (item.op_kind) |ok| {
            hasher.update(&.{ 1, @intFromEnum(ok) });
        } else {
            hasher.update(&.{0});
        }
        for (item.operands) |op| hashOperand(&hasher, op);
        hasher.update(item.raw_text);
        if (item.package_identity) |id| {
            hasher.update(id);
        } else {
            hasher.update(&.{0});
        }
        if (item.package_source_sha256) |sha| {
            hasher.update(&sha);
        } else {
            hasher.update(&.{0});
        }
        if (item.atomic_value_ty) |ty| hasher.update(std.mem.asBytes(&ty));
        if (item.atomic_ordering) |ord| hasher.update(&.{@intFromEnum(ord)});
        if (item.atomic_second_ordering) |ord| hasher.update(&.{@intFromEnum(ord)});
        if (item.atomic_rmw_op) |op| hasher.update(&.{@intFromEnum(op)});
        if (item.atomic_expected_text) |t| hasher.update(t);
        if (item.atomic_new_text) |t| hasher.update(t);
        for (item.native_reg_names) |n| hasher.update(n);
        hasher.update(&.{0xff});
    }
    var out: [32]u8 = undefined;
    hasher.final(&out);
    return out;
}

pub fn hashStream(bytes: []const u8) [32]u8 {
    var h = std.crypto.hash.sha2.Sha256.init(.{});
    h.update(bytes);
    var out: [32]u8 = undefined;
    h.final(&out);
    return out;
}

fn verdictMap() *std.AutoHashMap([32]u8, void) {
    if (passed_map == null) {
        passed_map = std.AutoHashMap([32]u8, void).init(std.heap.page_allocator);
    }
    return &passed_map.?;
}

fn resultMap() *std.AutoHashMap([32]u8, OwnedVerifySnapshot) {
    if (result_map == null) {
        result_map = std.AutoHashMap([32]u8, OwnedVerifySnapshot).init(std.heap.page_allocator);
    }
    return &result_map.?;
}

pub fn isVerified(digest: [32]u8) bool {
    mutex.lock();
    defer mutex.unlock();
    const hit = verdictMap().contains(digest);
    if (hit) {
        _ = hits.fetchAdd(1, .monotonic);
    } else {
        _ = misses.fetchAdd(1, .monotonic);
    }
    return hit;
}

pub fn recordVerified(digest: [32]u8) void {
    mutex.lock();
    defer mutex.unlock();
    verdictMap().put(digest, {}) catch {};
}

pub fn hasResult(digest: [32]u8) bool {
    mutex.lock();
    defer mutex.unlock();
    return resultMap().contains(digest);
}

/// Store a fully-owned snapshot of instruction stream text for B-B reuse.
/// Stores annotated bases only (no live SymbolTable), sufficient to rebuild a
/// trusted shell when combined with the current FlattenResult's function_sigs.
pub fn recordResultFromInstructions(digest: [32]u8, instructions: []const inst.Instruction, function_names: []const []const u8) void {
    const allocator = std.heap.page_allocator;
    var annotated = allocator.alloc(OwnedAnnotated, instructions.len) catch return;
    var filled: usize = 0;
    errdefer {
        var i: usize = 0;
        while (i < filled) : (i += 1) {
            freeOwnedInstruction(allocator, &annotated[i].base);
            if (annotated[i].changes.len != 0) allocator.free(annotated[i].changes);
        }
        allocator.free(annotated);
    }
    for (instructions, 0..) |ins, i| {
        annotated[i] = .{
            .base = cloneInstruction(allocator, ins) catch {
                // best-effort; abandon snapshot
                var j: usize = 0;
                while (j < i) : (j += 1) {
                    freeOwnedInstruction(allocator, &annotated[j].base);
                }
                allocator.free(annotated);
                return;
            },
            .changes = &.{},
            .change_count = 0,
            .gas_step_cost = 0,
        };
        filled = i + 1;
    }
    var fn_names = allocator.alloc([]u8, function_names.len) catch {
        for (annotated) |*item| freeOwnedInstruction(allocator, &item.base);
        allocator.free(annotated);
        return;
    };
    for (function_names, 0..) |n, i| {
        fn_names[i] = allocator.dupe(u8, n) catch {
            var k: usize = 0;
            while (k < i) : (k += 1) allocator.free(fn_names[k]);
            allocator.free(fn_names);
            for (annotated) |*item| freeOwnedInstruction(allocator, &item.base);
            allocator.free(annotated);
            return;
        };
    }
    var snap: OwnedVerifySnapshot = .{
        .annotated = annotated,
        .function_names = fn_names,
        .symbol_names = &.{},
    };

    mutex.lock();
    defer mutex.unlock();
    const map = resultMap();
    if (map.fetchRemove(digest)) |old| {
        var owned = old.value;
        owned.deinit(allocator);
    }
    map.put(digest, snap) catch {
        snap.deinit(allocator);
    };
    verdictMap().put(digest, {}) catch {};
}

pub fn clear() void {
    mutex.lock();
    defer mutex.unlock();
    if (passed_map) |*m| m.clearRetainingCapacity();
    if (result_map) |*m| {
        var it = m.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit(std.heap.page_allocator);
        }
        m.clearRetainingCapacity();
    }
    hits.store(0, .monotonic);
    misses.store(0, .monotonic);
    result_hits.store(0, .monotonic);
    result_misses.store(0, .monotonic);
}

pub fn stats() struct { hits: u64, misses: u64, result_hits: u64, result_misses: u64 } {
    return .{
        .hits = hits.load(.monotonic),
        .misses = misses.load(.monotonic),
        .result_hits = result_hits.load(.monotonic),
        .result_misses = result_misses.load(.monotonic),
    };
}

test "verdict cache records and detects by content hash" {
    clear();
    const a = hashStream("instr-stream-A");
    const b = hashStream("instr-stream-B");
    try std.testing.expect(!isVerified(a));
    // isVerified counts miss
    recordVerified(a);
    try std.testing.expect(isVerified(a));
    try std.testing.expect(!isVerified(b));
    try std.testing.expect(isVerified(hashStream("instr-stream-A")));
}

test "hashStream is deterministic and change-sensitive" {
    const h1 = hashStream("x");
    const h2 = hashStream("x");
    const h3 = hashStream("y");
    try std.testing.expect(std.mem.eql(u8, &h1, &h2));
    try std.testing.expect(!std.mem.eql(u8, &h1, &h3));
}

test "hashInstructions ignores source lines and sees raw_text" {
    clear();
    const a = inst.makeInstruction(.return_, 1, 1, null, "return 0");
    const b = inst.makeInstruction(.return_, 99, 99, null, "return 0");
    const c = inst.makeInstruction(.return_, 1, 1, null, "return 1");
    const ha = hashInstructions(&.{a});
    const hb = hashInstructions(&.{b});
    const hc = hashInstructions(&.{c});
    try std.testing.expect(std.mem.eql(u8, &ha, &hb));
    try std.testing.expect(!std.mem.eql(u8, &ha, &hc));
}

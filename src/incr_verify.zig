const std = @import("std");
const inst = @import("common/instruction.zig");

// Incremental-verification cache.
//
// Phase B-A: verdict-only cache keyed by a sound content hash of the instruction
// stream. A hit means "this exact stream previously verified OK". No owned
// VerifyOk is stored, so check/audit can skip re-verification safely.
//
// Phase B-B (fully-owned result snapshot cache) has been removed: its writer
// lost its last callers at opt1 (LINE-OPT-INCR-SNAPSHOT-FIX) and no reader ever
// existed, so the verdict cache below is the only live cache.

var mutex: std.atomic.Mutex = .unlocked;
var passed_map: ?std.AutoHashMap([32]u8, void) = null;

pub var hits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);
pub var misses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0);

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
    return hashInstructionsMode(instructions, 0);
}

/// Same as `hashInstructions`, with the verification mode folded into the
/// digest. The mode changes what the verifier accepts (for example the
/// Rust-style immutable default), so verdicts must not be shared across modes.
pub fn hashInstructionsMode(instructions: []const inst.Instruction, mode: u8) [32]u8 {
    var hasher = std.crypto.hash.sha2.Sha256.init(.{});
    hasher.update("sa-incr-verify-v1");
    hasher.update(&.{mode});
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

pub fn isVerified(digest: [32]u8) bool {
    while (!mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
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
    while (!mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer mutex.unlock();
    verdictMap().put(digest, {}) catch {};
}

pub fn clear() void {
    while (!mutex.tryLock()) {
        std.Thread.yield() catch {};
    }
    defer mutex.unlock();
    if (passed_map) |*m| m.clearRetainingCapacity();
    hits.store(0, .monotonic);
    misses.store(0, .monotonic);
}

pub fn stats() struct { hits: u64, misses: u64 } {
    return .{
        .hits = hits.load(.monotonic),
        .misses = misses.load(.monotonic),
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

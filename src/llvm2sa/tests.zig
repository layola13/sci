// Tests for the llvm2sa translation (moved verbatim).
const std = @import("std");
const sio = @import("sio");
const translateIrSource = @import("translate.zig").translateIrSource;
const translateBitcodeFile = @import("translate.zig").translateBitcodeFile;
const llvmAs = @import("translate.zig").llvmAs;

test "bc2sa translates real llvm bitcode" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const tmp_dir: sio.Dir = .{ .inner = tmp.dir };
    try tmp_dir.writeFile(.{ .sub_path = "sample.ll", .data = 
        \\define i32 @main(i32 %lhs, i32 %rhs) {
        \\entry:
        \\  %0 = add i32 %lhs, %rhs
        \\  %1 = icmp sgt i32 %0, 2
        \\  br i1 %1, label %ok, label %err
        \\ok:
        \\  ret i32 %0
        \\err:
        \\  ret i32 0
        \\}
        \\
    });
    const ll_path = try tmp_dir.realpathAlloc(std.testing.allocator, "sample.ll");
    defer std.testing.allocator.free(ll_path);
    const tmp_path = try tmp_dir.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(tmp_path);
    const bc_path = try std.fs.path.join(std.testing.allocator, &.{ tmp_path, "sample.bc" });
    defer std.testing.allocator.free(bc_path);
    try llvmAs(std.testing.allocator, ll_path, bc_path);

    const out = try translateBitcodeFile(std.testing.allocator, bc_path);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "@export main(lhs: i32, rhs: i32) -> i32:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "L_entry:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "r0 = add lhs, rhs"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "r1 = sgt r0, 2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "br r1 -> L_ok, L_err"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "return r0"));
}

test "bc2sa rejects text llvm ir on bitcode-only path" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const tmp_dir: sio.Dir = .{ .inner = tmp.dir };
    try tmp_dir.writeFile(.{
        .sub_path = "sample.ll",
        .data = "define i32 @main() {\nentry:\n  ret i32 0\n}\n",
    });
    const sample_path = try tmp_dir.realpathAlloc(std.testing.allocator, "sample.ll");
    defer std.testing.allocator.free(sample_path);
    try std.testing.expectError(error.UnsupportedBitcodeInput, translateBitcodeFile(std.testing.allocator, sample_path));
}

test "bc2sa scales constant gep offsets by element size" {
    const ir =
        \\define i32 @main() {
        \\entry:
        \\  %arr = alloca [4 x i32], align 4
        \\  %slot = getelementptr inbounds [4 x i32], ptr %arr, i64 0, i64 2
        \\  ret i32 0
        \\}
        \\
    ;

    const out = try translateIrSource(std.testing.allocator, ir);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "slot = ptr_add arr, 8"));
}

test "bc2sa lowers scalar select through a stack slot" {
    const ir =
        \\define i32 @choose(i1 %cond, i32 %lhs, i32 %rhs) {
        \\entry:
        \\  %selected = select i1 %cond, i32 %lhs, i32 %rhs
        \\  ret i32 %selected
        \\}
        \\
    ;

    const out = try translateIrSource(std.testing.allocator, ir);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "bc2sa_select_slot_selected = stack_alloc 4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "br cond -> L_BC2SA_SELECT_TRUE_selected, L_BC2SA_SELECT_FALSE_selected"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "store bc2sa_select_slot_selected+0, lhs as i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "store bc2sa_select_slot_selected+0, rhs as i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "selected = load bc2sa_select_slot_selected+0 as i32"));
}

test "bc2sa lowers multiline switch into eq and branch chain" {
    const ir =
        \\define i32 @dispatch(i32 %value) {
        \\entry:
        \\  switch i32 %value, label %default [
        \\    i32 1, label %one
        \\    i32 2, label %two
        \\  ]
        \\one:
        \\  ret i32 10
        \\two:
        \\  ret i32 20
        \\default:
        \\  ret i32 0
        \\}
        \\
    ;

    const out = try translateIrSource(std.testing.allocator, ir);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "bc2sa_switch_cmp_0_0 = eq value, 1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "br bc2sa_switch_cmp_0_0 -> L_one, L_BC2SA_SWITCH_NEXT_0_0"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "bc2sa_switch_cmp_0_1 = eq value, 2"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "br bc2sa_switch_cmp_0_1 -> L_two, L_default"));
}

test "bc2sa accepts compact switch case lists" {
    const ir =
        \\define i32 @compact(i32 %value) {
        \\entry:
        \\  switch i32 %value, label %default [ i32 1, label %one, i32 2, label %two ]
        \\one:
        \\  ret i32 10
        \\two:
        \\  ret i32 20
        \\default:
        \\  ret i32 0
        \\}
        \\
    ;

    const out = try translateIrSource(std.testing.allocator, ir);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "bc2sa_switch_cmp_0_0 = eq value, 1"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "bc2sa_switch_cmp_0_1 = eq value, 2"));
}

test "bc2sa lowers scalar phi through a stack slot" {
    const ir =
        \\define i32 @loop(i1 %cond, i32 %lhs, i32 %rhs) {
        \\entry:
        \\  br i1 %cond, label %left, label %right
        \\left:
        \\  br label %join
        \\right:
        \\  br label %join
        \\join:
        \\  %value = phi i32 [ %lhs, %left ], [ %rhs, %right ]
        \\  ret i32 %value
        \\}
        \\
    ;

    const out = try translateIrSource(std.testing.allocator, ir);
    defer std.testing.allocator.free(out);
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "bc2sa_phi_slot_value = stack_alloc 4"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "store bc2sa_phi_slot_value+0, lhs as i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "store bc2sa_phi_slot_value+0, rhs as i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, out, 1, "value = load bc2sa_phi_slot_value+0 as i32"));
}

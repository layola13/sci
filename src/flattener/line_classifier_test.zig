const std = @import("std");
const common_instruction = @import("../common/instruction.zig");
const InstructionForm = @import("line_classifier.zig").InstructionForm;
const LineKind = @import("line_classifier.zig").LineKind;
const classifyLine = @import("line_classifier.zig").classifyLine;
const collectNativeRegisterNames = @import("line_classifier.zig").collectNativeRegisterNames;

test "classify representative line families" {
    const def = classifyLine("#def SIZE = 16");
    try std.testing.expectEqual(LineKind.def, def.kind);
    try std.testing.expectEqualStrings("SIZE", def.parts[0]);
    try std.testing.expectEqualStrings("16", def.parts[1]);

    const const_decl = classifyLine("@const HELLO = utf8:\"hello\"");
    try std.testing.expectEqual(LineKind.const_decl, const_decl.kind);
    try std.testing.expectEqualStrings("HELLO", const_decl.parts[0]);
    try std.testing.expectEqualStrings("utf8:\"hello\"", const_decl.parts[1]);

    const func = classifyLine("@sum(^list, t) -> i32:");
    try std.testing.expectEqual(LineKind.func_decl, func.kind);
    try std.testing.expectEqualStrings("sum", func.parts[0]);
    try std.testing.expectEqualStrings("^list, t", func.parts[1]);
    try std.testing.expectEqualStrings("i32", func.parts[2]);

    const ffi = classifyLine("@ffi_wrapper wrap(*ptr) -> ^ptr:");
    try std.testing.expectEqual(LineKind.ffi_wrapper_decl, ffi.kind);
    try std.testing.expectEqualStrings("wrap", ffi.parts[0]);

    const ext = classifyLine("@extern libc_malloc(size) -> *void");
    try std.testing.expectEqual(LineKind.extern_decl, ext.kind);
    try std.testing.expectEqualStrings("libc_malloc", ext.parts[0]);

    const test_decl = classifyLine("@test ignored should_panic \"panic path\"():");
    try std.testing.expectEqual(LineKind.test_decl, test_decl.kind);
    try std.testing.expectEqualStrings("\"panic path\"", test_decl.parts[0]);

    const label = classifyLine("L_LOOP:");
    try std.testing.expectEqual(LineKind.label, label.kind);
    try std.testing.expectEqualStrings("L_LOOP", label.parts[0]);

    const alloc = classifyLine("node = alloc 8");
    try std.testing.expectEqual(LineKind.instruction, alloc.kind);
    try std.testing.expectEqual(InstructionForm.alloc, alloc.inst_form.?);
    try std.testing.expectEqualStrings("node", alloc.parts[0]);
    try std.testing.expectEqualStrings("8", alloc.parts[1]);

    const loc = classifyLine("#loc \"main.rs\":42:7");
    try std.testing.expectEqual(LineKind.loc_hint, loc.kind);
    try std.testing.expectEqualStrings("main.rs", loc.parts[0]);
    try std.testing.expectEqualStrings("42", loc.parts[1]);
    try std.testing.expectEqualStrings("7", loc.parts[2]);

    const import = classifyLine("@import \"sa_std/io/print.sai\"");
    try std.testing.expectEqual(LineKind.import_decl, import.kind);
    try std.testing.expectEqualStrings("sa_std/io/print.sai", import.parts[0]);

    const raw = classifyLine("raw = *safe");
    try std.testing.expectEqual(InstructionForm.raw_cast, raw.inst_form.?);

    const assume = classifyLine("safe = assume_safe raw");
    try std.testing.expectEqual(InstructionForm.assume_safe, assume.inst_form.?);

    const typed_assign = classifyLine("map = 0 as ptr");
    try std.testing.expectEqual(InstructionForm.assign, typed_assign.inst_form.?);
    try std.testing.expectEqualStrings("0", typed_assign.parts[1]);

    const borrow = classifyLine("view = assume_borrow raw, mut");
    try std.testing.expectEqual(InstructionForm.assume_borrow, borrow.inst_form.?);

    const shared_borrow = classifyLine("view = &box");
    try std.testing.expectEqual(InstructionForm.borrow, shared_borrow.inst_form.?);
    try std.testing.expectEqualStrings("read", shared_borrow.parts[1]);
    try std.testing.expectEqualStrings("box", shared_borrow.parts[2]);

    const mut_borrow = classifyLine("view = &mut box");
    try std.testing.expectEqual(InstructionForm.borrow, mut_borrow.inst_form.?);
    try std.testing.expectEqualStrings("mut", mut_borrow.parts[1]);
    try std.testing.expectEqualStrings("box", mut_borrow.parts[2]);

    const panic = classifyLine("panic(7)");
    try std.testing.expectEqual(LineKind.instruction, panic.kind);
    try std.testing.expectEqual(InstructionForm.panic, panic.inst_form.?);

    const panic_msg = classifyLine("panic_msg(7, *msg, len)");
    try std.testing.expectEqual(LineKind.instruction, panic_msg.kind);
    try std.testing.expectEqual(InstructionForm.panic_msg, panic_msg.inst_form.?);

    const atomic_load = classifyLine("value = atomic_load ptr+0 acquire");
    try std.testing.expectEqual(InstructionForm.atomic_load, atomic_load.inst_form.?);

    const atomic_store = classifyLine("atomic_store ptr+0, value release");
    try std.testing.expectEqual(InstructionForm.atomic_store, atomic_store.inst_form.?);

    const sgt = classifyLine("cmp = sgt lhs, rhs");
    try std.testing.expectEqual(InstructionForm.op, sgt.inst_form.?);
    try std.testing.expectEqualStrings("sgt", sgt.parts[1]);

    const sle = classifyLine("cmp = sle lhs, rhs");
    try std.testing.expectEqual(InstructionForm.op, sle.inst_form.?);
    try std.testing.expectEqualStrings("sle", sle.parts[1]);

    const ult = classifyLine("cmp = ult lhs, rhs");
    try std.testing.expectEqual(InstructionForm.op, ult.inst_form.?);
    try std.testing.expectEqualStrings("ult", ult.parts[1]);

    const srem = classifyLine("rem = srem lhs, rhs");
    try std.testing.expectEqual(InstructionForm.op, srem.inst_form.?);
    try std.testing.expectEqualStrings("srem", srem.parts[1]);

    const zext = classifyLine("ret = zext ok");
    try std.testing.expectEqual(InstructionForm.op, zext.inst_form.?);
    try std.testing.expectEqualStrings("zext", zext.parts[1]);
    try std.testing.expectEqualStrings("ok", zext.parts[2]);

    const shuffle = classifyLine("out = shuffle_v128 a, b, mask");
    try std.testing.expectEqual(InstructionForm.op, shuffle.inst_form.?);
    try std.testing.expectEqualStrings("shuffle_v128", shuffle.parts[1]);
    try std.testing.expectEqualStrings("mask", shuffle.parts[4]);

    const cmpxchg = classifyLine("old, ok = cmpxchg ptr+0, expected, new acq_rel acquire");
    try std.testing.expectEqual(InstructionForm.cmpxchg, cmpxchg.inst_form.?);

    const rmw = classifyLine("old = atomic_rmw_add ptr+0, value seq_cst");
    try std.testing.expectEqual(InstructionForm.atomic_rmw, rmw.inst_form.?);

    const literal = classifyLine("i = 1");
    try std.testing.expectEqual(InstructionForm.assign, literal.inst_form.?);
    try std.testing.expectEqualStrings("i", literal.parts[0]);
    try std.testing.expectEqualStrings("1", literal.parts[1]);

    const rebinding = classifyLine("next = sum_next");
    try std.testing.expectEqual(InstructionForm.assign, rebinding.inst_form.?);
    try std.testing.expectEqualStrings("next", rebinding.parts[0]);
    try std.testing.expectEqualStrings("sum_next", rebinding.parts[1]);

    const fence = classifyLine("fence seq_cst");
    try std.testing.expectEqual(InstructionForm.fence, fence.inst_form.?);

    const store = classifyLine("store node+4, 0");
    try std.testing.expectEqual(LineKind.instruction, store.kind);
    try std.testing.expectEqual(InstructionForm.store, store.inst_form.?);
    try std.testing.expectEqualStrings("node", store.parts[0]);
    try std.testing.expectEqualStrings("4", store.parts[1]);
    try std.testing.expectEqualStrings("0", store.parts[2]);

    const typed_load = classifyLine("value = load node+8 as i64");
    try std.testing.expectEqual(InstructionForm.load, typed_load.inst_form.?);
    try std.testing.expectEqualStrings("i64", typed_load.parts[3]);

    const native = classifyLine("$const x = 1;$");
    try std.testing.expectEqual(LineKind.native, native.kind);
    try std.testing.expectEqualStrings("const x = 1;", native.parts[0]);

    const npm_bind = classifyLine("#npm_bind npm_totalmem \"node:os#totalmem\"");
    try std.testing.expectEqual(LineKind.npm_bind, npm_bind.kind);
    try std.testing.expectEqualStrings("npm_totalmem", npm_bind.parts[0]);
    try std.testing.expectEqualStrings("node:os#totalmem", npm_bind.parts[1]);

    const npm_scoped = classifyLine("#npm_bind npm_uuid \"uuid@9.0.0#v4\"");
    try std.testing.expectEqual(LineKind.npm_bind, npm_scoped.kind);
    try std.testing.expectEqualStrings("npm_uuid", npm_scoped.parts[0]);
    try std.testing.expectEqualStrings("uuid@9.0.0#v4", npm_scoped.parts[1]);

    const npm_no_hash = classifyLine("#npm_bind bad \"node:os\"");
    try std.testing.expectEqual(LineKind.unknown, npm_no_hash.kind);

    const npm_empty_export = classifyLine("#npm_bind bad \"node:os#\"");
    try std.testing.expectEqual(LineKind.unknown, npm_empty_export.kind);

    const npm_no_ident = classifyLine("#npm_bind \"node:os#totalmem\"");
    try std.testing.expectEqual(LineKind.unknown, npm_no_ident.kind);
}

test "native register extraction keeps bare identifiers and skips llvm sigils" {
    const names = try collectNativeRegisterNames(std.testing.allocator, "call side(ptr foo, i32 bar) ; @glob %tmp \"skip me\" foo");
    defer std.testing.allocator.free(names);

    try std.testing.expectEqual(@as(usize, 6), names.len);
    try std.testing.expectEqualStrings("call", names[0]);
    try std.testing.expectEqualStrings("side", names[1]);
    try std.testing.expectEqualStrings("ptr", names[2]);
    try std.testing.expectEqualStrings("foo", names[3]);
    try std.testing.expectEqualStrings("i32", names[4]);
    try std.testing.expectEqualStrings("bar", names[5]);
}

//! rust core helpers -- split from tests/std_smoke_core.zig (shared helpers: helpers.zig).
const std = @import("std");
const common = @import("../std_smoke_common.zig");
const sio = @import("sio");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std rust core helpers are concrete and verifiable" {
    const option_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/option/option.sal");
    defer std.testing.allocator.free(option_layout);
    try std.testing.expectEqualStrings(
        \\#def Option_SIZE = 16
        \\#def Option_tag = +0
        \\#def Option_value = +8
        \\#def Option_NONE = 0
        \\#def Option_SOME = 1
        \\
        \\
        \\#def OptionPairU64_SIZE = 24
        \\#def OptionPairU64_tag = +0
        \\#def OptionPairU64_value1 = +8
        \\#def OptionPairU64_value2 = +16
        \\
    ,
        option_layout,
    );

    const result_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/result/result.sal");
    defer std.testing.allocator.free(result_layout);
    try std.testing.expectEqualStrings(
        "#def Result_SIZE = 24\n#def Result_tag = +0\n#def Result_ok = +8\n#def Result_err = +16\n#def Result_OK = 0\n#def Result_ERR = 1\n",
        result_layout,
    );

    const iter_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter/iter.sal");
    defer std.testing.allocator.free(iter_layout);
    try std.testing.expectEqualStrings(
        "#def Iter_SIZE = 24\n#def Iter_ptr = +0\n#def Iter_len = +8\n#def Iter_index = +16\n",
        iter_layout,
    );

    const option_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/option/option.sa");
    defer std.testing.allocator.free(option_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_NEW_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_IS_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP_OR_RETURN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] TRY_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] TRY_OPTION_RETURN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_NONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_SET_SOME"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCHES_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] MATCH_OPTION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, option_src, 1, "[MACRO] OPTION_MATCH_SOME_NONE"));

    const result_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/result/result.sa");
    defer std.testing.allocator.free(result_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_NEW_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_IS_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_GET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_RETURN_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] TRY_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] TRY_RESULT_RETURN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_UNWRAP_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MAP_OR_ELSE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_OK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_SET_ERR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_BRANCH"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCH_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] MATCHES_RESULT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result_src, 1, "[MACRO] RESULT_MATCH_OK_ERR"));

    const stringify_src = try common.readFileAlloc(std.testing.allocator, "src/flattener/emitrange.zig");
    defer std.testing.allocator.free(stringify_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, stringify_src, 1, "STRINGIFY!"));

    const sa_core_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/sa_core.sa");
    defer std.testing.allocator.free(sa_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, sa_core_src, 1, "[MACRO] CFG"));

    const panic_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/panic/panic.sa");
    defer std.testing.allocator.free(panic_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC "));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] PANIC_MSG"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] TODO"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNIMPLEMENTED"));
    try std.testing.expect(std.mem.containsAtLeast(u8, panic_src, 1, "[MACRO] UNREACHABLE"));

    const iter_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter/iter.sa");
    defer std.testing.allocator.free(iter_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_FROM_SLICE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_HAS_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_REMAINING"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_PEEK_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, iter_src, 1, "[MACRO] ITER_NEXT_U64"));

    const loop_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/iter/loop.sa");
    defer std.testing.allocator.free(loop_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] WHILE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] WHILE_COND"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] FOR_RANGE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] INDEX_LOOP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] ARRAY_SCAN_MIN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, loop_src, 1, "[MACRO] ARRAY_SCAN_MAX"));

    const control_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/control/control.sa");
    defer std.testing.allocator.free(control_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] MATCH_BOOL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] ELIF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] WHILE_LET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] BREAK_IF"));
    try std.testing.expect(std.mem.containsAtLeast(u8, control_src, 1, "[MACRO] CONTINUE_IF"));

    const bit_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/num/bit.sa");
    defer std.testing.allocator.free(bit_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_MASK"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_GET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_CLEAR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_TEST"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_INDEX_BYTE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, bit_src, 1, "[MACRO] BIT_INDEX_BIT"));

    const hash_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/hash/probe.sa");
    defer std.testing.allocator.free(hash_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_MIX"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] HASH_MOD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] PROBE_START"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] PROBE_NEXT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] MAP_LOOKUP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, hash_src, 1, "[MACRO] MAP_INSERT_OR_UPDATE"));

    const cleanup_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/memory/cleanup.sa");
    defer std.testing.allocator.free(cleanup_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] DEFER"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] CLEANUP_ON_ERROR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] WITH_TEMP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] RETURN_CLEAN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cleanup_src, 1, "[MACRO] FREE_AND_RETURN"));

    const rust_core_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/rust_core.sa");
    defer std.testing.allocator.free(rust_core_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"option/option.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"result/result.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"panic/panic.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"iter/iter.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"cell/cell.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"cell/refcell.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"cell/rc.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"cell/weak.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"derive/derive.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"iter/loop.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"control/control.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"num/bit.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"hash/probe.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"memory/cleanup.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"../sync/rwlock/rwlock.sa\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, rust_core_src, 1, "@import \"types/ascii.sa\""));

    const ascii_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/types/ascii.sal");
    defer std.testing.allocator.free(ascii_layout);
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_layout, 1, "#def ASCII_CASE_MASK = 32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_layout, 1, "#def ASCII_MAX = 127"));

    const ascii_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/types/ascii.sa");
    defer std.testing.allocator.free(ascii_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_ASCII"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_ALPHABETIC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_ALPHANUMERIC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_DIGIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_OCTDIGIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_HEXDIGIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_PUNCTUATION"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_GRAPHIC"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_WHITESPACE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_IS_CONTROL"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_TO_UPPERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_TO_LOWERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_EQ_IGNORE_CASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_SLICE_MAKE_UPPERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_SLICE_MAKE_LOWERCASE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, ascii_src, 1, "[MACRO] ASCII_SLICE_EQ_IGNORE_CASE"));

    const cell_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/cell.sal");
    defer std.testing.allocator.free(cell_layout);
    try std.testing.expectEqualStrings(
        "#def Cell_SIZE = 4\n#def Cell_value = +0\n\n#def CellU64_SIZE = 8\n#def CellU64_value = +0\n",
        cell_layout,
    );

    const refcell_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/refcell.sal");
    defer std.testing.allocator.free(refcell_layout);
    try std.testing.expectEqualStrings(
        \\#def RefCell_SIZE = 8
        \\#def RefCell_value = +0
        \\#def RefCell_borrows = +4
        \\
        \\#def RefCellU64_SIZE = 16
        \\#def RefCellU64_value = +0
        \\#def RefCellU64_borrows = +8
        \\
        \\#def BorrowError_SIZE = 0
        \\#def BorrowError_ALIGN = 1
        \\
        \\#def BorrowMutError_SIZE = 0
        \\#def BorrowMutError_ALIGN = 1
        \\
    ,
        refcell_layout,
    );

    const rc_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/rc.sal");
    defer std.testing.allocator.free(rc_layout);
    try std.testing.expectEqualStrings("#def RcBox_SIZE = 24\n#def RcBox_strong = +0\n#def RcBox_weak = +8\n#def RcBox_data = +16\n", rc_layout);

    const weak_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/weak.sal");
    defer std.testing.allocator.free(weak_layout);
    try std.testing.expectEqualStrings("#def WeakBox_SIZE = 24\n#def WeakBox_strong = +0\n#def WeakBox_weak = +8\n#def WeakBox_data = +16\n", weak_layout);

    const cell_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/cell.sa");
    defer std.testing.allocator.free(cell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_SET"));
    try std.testing.expect(std.mem.containsAtLeast(u8, cell_src, 1, "[MACRO] CELL_REPLACE"));

    const refcell_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/refcell.sa");
    defer std.testing.allocator.free(refcell_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_BORROW_MUT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, refcell_src, 1, "[MACRO] REFCELL_RELEASE"));

    const derive_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/derive/derive.sa");
    defer std.testing.allocator.free(derive_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_COPY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ_FIELD"));
    try std.testing.expect(std.mem.containsAtLeast(u8, derive_src, 1, "[MACRO] STRUCT_EQ4"));

    const rc_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/rc.sa");
    defer std.testing.allocator.free(rc_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] RC_DOWNGRADE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_CLONE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_DROP"));
    try std.testing.expect(std.mem.containsAtLeast(u8, rc_src, 1, "[MACRO] WEAK_UPGRADE"));

    const weak_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/cell/weak.sa");
    defer std.testing.allocator.free(weak_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"weak.sal\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, weak_src, 1, "@import \"rc.sa\""));

    var option_flat = try flattenFixture(std.testing.allocator, "sa_std/core/option/option.sa", option_src);
    defer option_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), option_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), option_flat.function_sigs.len);

    var result_flat = try flattenFixture(std.testing.allocator, "sa_std/core/result/result.sa", result_src);
    defer result_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), result_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), result_flat.function_sigs.len);

    var panic_flat = try flattenFixture(std.testing.allocator, "sa_std/core/panic/panic.sa", panic_src);
    defer panic_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), panic_flat.function_sigs.len);

    var iter_flat = try flattenFixture(std.testing.allocator, "sa_std/core/iter/iter.sa", iter_src);
    defer iter_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), iter_flat.function_sigs.len);

    var ascii_flat = try flattenFixture(std.testing.allocator, "sa_std/core/types/ascii.sa", ascii_src);
    defer ascii_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), ascii_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), ascii_flat.function_sigs.len);

    var rust_core_flat = try flattenFixture(std.testing.allocator, "sa_std/core/rust_core.sa", rust_core_src);
    defer rust_core_flat.deinit(std.testing.allocator);
    try std.testing.expect(rust_core_flat.instructions.len > 0);
    try std.testing.expect(rust_core_flat.function_sigs.len > 0);
    try std.testing.expect(rust_core_flat.instructions.len >= 1);
}

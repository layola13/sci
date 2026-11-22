//! core primitives, package manifest, http2, io/process ABI -- split from tests/std_smoke_core.zig (shared helpers: helpers.zig).
const std = @import("std");
const common = @import("../std_smoke_common.zig");
const sio = @import("sio");
const saasm = common.saasm;
const flattenFixture = @import("helpers.zig").flattenFixture;

test "sa_std core primitives are concrete and verifiable" {
    const slice_layout = try common.readFileAlloc(std.testing.allocator, "sa_std/core/slice/slice.sal");
    defer std.testing.allocator.free(slice_layout);
    try std.testing.expectEqualStrings(
        \\#def Slice_SIZE = 16
        \\#def Slice_ptr  = +0
        \\#def Slice_len  = +8
        \\
        \\#def TryFromSliceError_SIZE = 8
        \\#def TryFromSliceError_code = +0
        \\#def TRY_FROM_SLICE_ERROR_LENGTH_MISMATCH = 0
        \\
    ,
        slice_layout,
    );

    const slice_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/slice/slice.sa");
    defer std.testing.allocator.free(slice_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_AS_PTR"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_LEN"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_IS_EMPTY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_GET_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_FIRST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_FIRST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_FIRST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_FIRST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_LAST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_LAST_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_LAST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_LAST_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_GET_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_GET_MUT_PTR_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_CONTAINS_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_STARTS_WITH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_ENDS_WITH_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_STRIP_PREFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_STRIP_SUFFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRIM_PREFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRIM_SUFFIX_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SPLIT_AT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SPLIT_AT_MUT_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_RANGE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_GET_RANGE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_SWAP_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_TRY_SWAP_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_CLONE_FROM_SLICE_U64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, slice_src, 1, "[MACRO] SLICE_COPY_WITHIN_U64"));

    var slice_flat = try saasm.flattener.flatten(std.testing.allocator, slice_src);
    defer slice_flat.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.instructions.len);
    try std.testing.expectEqual(@as(usize, 0), slice_flat.function_sigs.len);

    const slice_fixture =
        \\@import "sa_std/core/slice.sal"
        \\@import "sa_std/core/slice.sa"
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    data = alloc 24
        \\    store data+0, 11 as u64
        \\    store data+8, 22 as u64
        \\    store data+16, 33 as u64
        \\    slice = alloc Slice_SIZE
        \\    empty_slice = alloc Slice_SIZE
        \\    EXPAND SLICE_NEW slice, data, 3
        \\    EXPAND SLICE_NEW empty_slice, data, 0
        \\    EXPAND SLICE_AS_PTR ptr, slice
        \\    EXPAND SLICE_IS_EMPTY empty, slice
        \\    EXPAND SLICE_FIRST_U64 first, slice
        \\    EXPAND SLICE_LAST_U64 last, slice
        \\    EXPAND SLICE_TRY_FIRST_U64 first_try_ok, first_try, slice
        \\    EXPAND SLICE_TRY_LAST_U64 last_try_ok, last_try, slice
        \\    EXPAND SLICE_TRY_GET_U64 hit_ok, hit, slice, 1
        \\    EXPAND SLICE_TRY_GET_U64 miss_ok, miss, slice, 9
        \\    EXPAND SLICE_CONTAINS_U64 contains_22, slice, 22
        \\    EXPAND SLICE_CONTAINS_U64 contains_44, slice, 44
        \\    suffix_ptr = ptr_add data, 8
        \\    miss_prefix_data = alloc 16
        \\    store miss_prefix_data+0, 11 as u64
        \\    store miss_prefix_data+8, 44 as u64
        \\    prefix_slice = alloc Slice_SIZE
        \\    suffix_slice = alloc Slice_SIZE
        \\    miss_prefix_slice = alloc Slice_SIZE
        \\    EXPAND SLICE_NEW prefix_slice, data, 2
        \\    EXPAND SLICE_NEW suffix_slice, suffix_ptr, 2
        \\    EXPAND SLICE_NEW miss_prefix_slice, miss_prefix_data, 2
        \\    !suffix_ptr
        \\    EXPAND SLICE_TRY_STRIP_PREFIX_U64 strip_prefix_ok, strip_prefix_tail, slice, prefix_slice
        \\    EXPAND SLICE_TRY_STRIP_SUFFIX_U64 strip_suffix_ok, strip_suffix_head, slice, suffix_slice
        \\    EXPAND SLICE_TRY_STRIP_PREFIX_U64 strip_prefix_miss_ok, strip_prefix_miss, slice, miss_prefix_slice
        \\    EXPAND SLICE_GET_LEN strip_prefix_tail_len, strip_prefix_tail
        \\    EXPAND SLICE_FIRST_U64 strip_prefix_tail_first, strip_prefix_tail
        \\    EXPAND SLICE_GET_LEN strip_suffix_head_len, strip_suffix_head
        \\    EXPAND SLICE_FIRST_U64 strip_suffix_head_first, strip_suffix_head
        \\    EXPAND SLICE_IS_EMPTY strip_prefix_miss_empty, strip_prefix_miss
        \\    EXPAND SLICE_TRY_FIRST_U64 empty_first_ok, empty_first, empty_slice
        \\    EXPAND SLICE_TRY_LAST_U64 empty_last_ok, empty_last, empty_slice
        \\    ptr_ok = ne ptr, 0
        \\    empty_ok = eq empty, 0
        \\    first_ok = eq first, 11
        \\    last_ok = eq last, 33
        \\    first_try_flag_ok = eq first_try_ok, 1
        \\    first_try_value_ok = eq first_try, 11
        \\    last_try_flag_ok = eq last_try_ok, 1
        \\    last_try_value_ok = eq last_try, 33
        \\    hit_flag_ok = eq hit_ok, 1
        \\    hit_value_ok = eq hit, 22
        \\    miss_flag_ok = eq miss_ok, 0
        \\    miss_value_ok = eq miss, 0
        \\    contains_22_ok = eq contains_22, 1
        \\    contains_44_ok = eq contains_44, 0
        \\    strip_prefix_flag_ok = eq strip_prefix_ok, 1
        \\    strip_suffix_flag_ok = eq strip_suffix_ok, 1
        \\    strip_prefix_miss_flag_ok = eq strip_prefix_miss_ok, 0
        \\    strip_prefix_tail_len_ok = eq strip_prefix_tail_len, 1
        \\    strip_prefix_tail_first_ok = eq strip_prefix_tail_first, 33
        \\    strip_suffix_head_len_ok = eq strip_suffix_head_len, 1
        \\    strip_suffix_head_first_ok = eq strip_suffix_head_first, 11
        \\    strip_prefix_miss_empty_ok = eq strip_prefix_miss_empty, 1
        \\    empty_first_flag_ok = eq empty_first_ok, 0
        \\    empty_first_value_ok = eq empty_first, 0
        \\    empty_last_flag_ok = eq empty_last_ok, 0
        \\    empty_last_value_ok = eq empty_last, 0
        \\    ok01 = and ptr_ok, empty_ok
        \\    ok02 = and ok01, first_ok
        \\    ok03 = and ok02, last_ok
        \\    ok04 = and ok03, first_try_flag_ok
        \\    ok05 = and ok04, first_try_value_ok
        \\    ok06 = and ok05, last_try_flag_ok
        \\    ok07 = and ok06, last_try_value_ok
        \\    ok08 = and ok07, hit_flag_ok
        \\    ok09 = and ok08, hit_value_ok
        \\    ok10 = and ok09, miss_flag_ok
        \\    ok11 = and ok10, miss_value_ok
        \\    ok12 = and ok11, contains_22_ok
        \\    ok13 = and ok12, contains_44_ok
        \\    ok14 = and ok13, strip_prefix_flag_ok
        \\    ok15 = and ok14, strip_suffix_flag_ok
        \\    ok16 = and ok15, strip_prefix_miss_flag_ok
        \\    ok17 = and ok16, strip_prefix_tail_len_ok
        \\    ok18 = and ok17, strip_prefix_tail_first_ok
        \\    ok19 = and ok18, strip_suffix_head_len_ok
        \\    ok20 = and ok19, strip_suffix_head_first_ok
        \\    ok21 = and ok20, strip_prefix_miss_empty_ok
        \\    ok22 = and ok21, empty_first_flag_ok
        \\    ok23 = and ok22, empty_first_value_ok
        \\    ok24 = and ok23, empty_last_flag_ok
        \\    ok = and ok24, empty_last_value_ok
        \\    !ptr
        \\    !empty
        \\    !first
        \\    !last
        \\    !first_try_ok
        \\    !first_try
        \\    !last_try_ok
        \\    !last_try
        \\    !hit_ok
        \\    !hit
        \\    !miss_ok
        \\    !miss
        \\    !contains_22
        \\    !contains_44
        \\    !strip_prefix_ok
        \\    !strip_prefix_tail
        \\    !strip_suffix_ok
        \\    !strip_suffix_head
        \\    !strip_prefix_miss_ok
        \\    !strip_prefix_miss
        \\    !strip_prefix_tail_len
        \\    !strip_prefix_tail_first
        \\    !strip_suffix_head_len
        \\    !strip_suffix_head_first
        \\    !strip_prefix_miss_empty
        \\    !empty_first_ok
        \\    !empty_first
        \\    !empty_last_ok
        \\    !empty_last
        \\    !ptr_ok
        \\    !empty_ok
        \\    !first_ok
        \\    !last_ok
        \\    !first_try_flag_ok
        \\    !first_try_value_ok
        \\    !last_try_flag_ok
        \\    !last_try_value_ok
        \\    !hit_flag_ok
        \\    !hit_value_ok
        \\    !miss_flag_ok
        \\    !miss_value_ok
        \\    !contains_22_ok
        \\    !contains_44_ok
        \\    !strip_prefix_flag_ok
        \\    !strip_suffix_flag_ok
        \\    !strip_prefix_miss_flag_ok
        \\    !strip_prefix_tail_len_ok
        \\    !strip_prefix_tail_first_ok
        \\    !strip_suffix_head_len_ok
        \\    !strip_suffix_head_first_ok
        \\    !strip_prefix_miss_empty_ok
        \\    !empty_first_flag_ok
        \\    !empty_first_value_ok
        \\    !empty_last_flag_ok
        \\    !empty_last_value_ok
        \\    !ok01
        \\    !ok02
        \\    !ok03
        \\    !ok04
        \\    !ok05
        \\    !ok06
        \\    !ok07
        \\    !ok08
        \\    !ok09
        \\    !ok10
        \\    !ok11
        \\    !ok12
        \\    !ok13
        \\    !ok14
        \\    !ok15
        \\    !ok16
        \\    !ok17
        \\    !ok18
        \\    !ok19
        \\    !ok20
        \\    !ok21
        \\    !ok22
        \\    !ok23
        \\    !ok24
        \\    !miss_prefix_slice
        \\    !suffix_slice
        \\    !prefix_slice
        \\    !miss_prefix_data
        \\    !empty_slice
        \\    !slice
        \\    !data
        \\    br ok -> L_OK, L_ERR
        \\
        \\L_OK:
        \\    !ok
        \\    return 0
        \\
        \\L_ERR:
        \\    !ok
        \\    return 1
    ;
    var slice_fixture_flat = try flattenFixture(std.testing.allocator, "tests/slice_fixture.sa", slice_fixture);
    defer slice_fixture_flat.deinit(std.testing.allocator);
    const slice_fixture_verified = try saasm.referee.verify(std.testing.allocator, slice_fixture_flat.instructions, slice_fixture_flat.const_decls);
    switch (slice_fixture_verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            try std.testing.expectEqual(@as(usize, 1), owned.function_sigs.len);
        },
        .trap => |report| {
            std.debug.print("slice fixture verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }

    const mem_src = try common.readFileAlloc(std.testing.allocator, "sa_std/core/memory/raw.sa");
    defer std.testing.allocator.free(mem_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_copy"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "@export sa_mem_set"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "panic(1701)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "panic(1702)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "panic(1703)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "[MACRO] BOX_NEW"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "[MACRO] BOX_FREE"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "ptr_add"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "br done -> L_END, L_BODY"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "stack_alloc 8"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store offset_slot+0, 0 as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "store remaining_slot+0, count as u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, mem_src, 1, "next_remaining = sub remaining, one"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "inttoptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, mem_src, 1, "i = 0"));

    var mem_flat = try saasm.flattener.flatten(std.testing.allocator, mem_src);
    defer mem_flat.deinit(std.testing.allocator);
    const verified = try saasm.referee.verify(std.testing.allocator, mem_flat.instructions, mem_flat.const_decls);
    switch (verified) {
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(std.testing.allocator);
            // mem.sa sigs: sa_mem_copy + sa_mem_set + @extern memcpy +
            // sa_mem_copy_nonoverlapping (Class-A GAP-BULKAPPEND addition).
            try std.testing.expectEqual(@as(usize, 4), owned.function_sigs.len);
            try std.testing.expect(owned.annotated.len > 0);
        },
        .trap => |report| {
            std.debug.print("std smoke verifier trap: {s}\n", .{report.message});
            return error.TestUnexpectedResult;
        },
    }
}

test "sa_std package manifest declares the std package boundary" {
    const manifest_src = try common.readFileAlloc(std.testing.allocator, "sa_std/sa.mod");
    defer std.testing.allocator.free(manifest_src);

    var manifest_file = try saasm.pkg.manifest.parseManifestWithFile(std.testing.allocator, manifest_src, "sa_std/sa.mod");
    defer manifest_file.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 0), manifest_file.requires.len);
    try std.testing.expectEqual(@as(usize, 0), manifest_file.mirrors.len);
}

test "sa_std package manifest metadata grammar round trips" {
    const source =
        \\package {
        \\  name "sa_std"
        \\  version "0.1.0"
        \\  abi 7
        \\  features ["core", "windows"]
        \\}
    ;
    var manifest_file = try saasm.pkg.manifest.parseManifestWithFile(std.testing.allocator, source, "fixture/sa.mod");
    defer manifest_file.deinit(std.testing.allocator);
    try std.testing.expect(manifest_file.package_decl != null);
    try std.testing.expectEqualStrings("sa_std", manifest_file.package_decl.?.name);
    try std.testing.expectEqualStrings("0.1.0", manifest_file.package_decl.?.version.?);
    try std.testing.expectEqual(@as(?u32, 7), manifest_file.package_decl.?.abi);
    try std.testing.expectEqual(@as(usize, 2), manifest_file.package_decl.?.features.len);
}

test "sa_std http2 buffer accessors borrow handles before free" {
    const http2_src = try common.readFileAlloc(std.testing.allocator, "sa_std/http2.sa");
    defer std.testing.allocator.free(http2_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, http2_src, 1, "sa_std_http2_buffer_data(%buffer)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, http2_src, 1, "sa_std_http2_buffer_len(%buffer)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, http2_src, 1, "sa_std_http2_buffer_free(^%buffer)"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, http2_src, 1, "sa_std_http2_buffer_len(^%buffer)"));
}

test "sa_std io and process interfaces match native resource ABI" {
    const io_iface = try common.readFileAlloc(std.testing.allocator, "sa_std/io/io.sai");
    defer std.testing.allocator.free(io_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_stdin() -> u64"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_read(handle: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_write(handle: u64, &buf: ptr, len: u64, &out_written: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_close(handle: u64) -> i32"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_read(handle: ptr, &buf: ptr, cap: u64) -> u64!"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, io_iface, 1, "@extern sa_io_close(^handle: ptr) -> i32!"));

    const process_iface = try common.readFileAlloc(std.testing.allocator, "sa_std/os/process.sai");
    defer std.testing.allocator.free(process_iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_run(&argv: ptr, argv_len: u64, &out_handle: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_id() -> u32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_abort() -> void"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_child_id(handle: u64, &out_pid: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_wait(handle: u64, &out_code: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_try_wait(handle: u64, &out_ready: ptr, &out_code: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_kill(handle: u64) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_read_stdout(handle: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_read_stderr(handle: u64, &buf: ptr, cap: u64, &out_read: ptr) -> i32"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_iface, 1, "@extern sa_std_process_close(handle: u64) -> i32"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, process_iface, 1, "sa_std_process_wait(handle: ptr"));
    try std.testing.expect(!std.mem.containsAtLeast(u8, process_iface, 1, "sa_std_process_close(^handle: ptr"));

    const process_src = try common.readFileAlloc(std.testing.allocator, "sa_std/os/process.sa");
    defer std.testing.allocator.free(process_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, process_src, 1, "[MACRO] PROCESS_ABORT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_src, 1, "[MACRO] PROCESS_CHILD_ID %out_status, %out_pid, %process"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_src, 1, "[MACRO] PROCESS_TRY_WAIT"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_src, 1, "[MACRO] PROCESS_TRY_WAIT_EXIT_STATUS"));
    try std.testing.expect(std.mem.containsAtLeast(u8, process_src, 1, "[MACRO] PROCESS_KILL"));

    const io_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/prelude.sa");
    defer std.testing.allocator.free(io_src);
    // READ / WRITE_SOME moved out of the io aggregate into the stdin/stdout
    // modules it aggregates (Phase 1 modularization, 2026-11-22).
    const io_stdin_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/stdin/stdin.sa");
    defer std.testing.allocator.free(io_stdin_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_stdin_src, 1, "[MACRO] READ "));
    const io_stdout_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/stdout/stdout.sa");
    defer std.testing.allocator.free(io_stdout_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, io_stdout_src, 1, "[MACRO] WRITE_SOME"));
    var io_flat = try flattenFixture(std.testing.allocator, "sa_std/io/prelude.sa", io_src);
    defer io_flat.deinit(std.testing.allocator);
    try std.testing.expect(io_flat.function_sigs.len > 0);

    const buf_reader_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/buffer/buf_reader.sa");
    defer std.testing.allocator.free(buf_reader_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "call @sa_io_read(%handle, &%buf, %cap, &__buf_reader_read_slot)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_reader_src, 1, "call @sa_io_close(%handle)"));
    var buf_reader_flat = try flattenFixture(std.testing.allocator, "sa_std/io/buffer/buf_reader.sa", buf_reader_src);
    defer buf_reader_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_reader_flat.function_sigs.len > 0);

    const buf_writer_src = try common.readFileAlloc(std.testing.allocator, "sa_std/io/buffer/buf_writer.sa");
    defer std.testing.allocator.free(buf_writer_src);
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "call @sa_io_write(%handle, &%buf, %len, &__buf_writer_write_slot)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, buf_writer_src, 1, "call @sa_io_close(%handle)"));
    var buf_writer_flat = try flattenFixture(std.testing.allocator, "sa_std/io/buffer/buf_writer.sa", buf_writer_src);
    defer buf_writer_flat.deinit(std.testing.allocator);
    try std.testing.expect(buf_writer_flat.function_sigs.len > 0);
}

const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");

// JS backend equivalence matrix: `sa build-js` output executed with node
// must match the expected stdout of each demo (verified against native
// build-exe during development). Pure Zig backend: no LLVM required.

fn runJsWithNode(allocator: std.mem.Allocator, js_path: []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", js_path },
    });
}

fn elapsedMs(start_ns: i128) i128 {
    return @divTrunc(std.time.nanoTimestamp() - start_ns, std.time.ns_per_ms);
}

fn assertJsMatrixStdout(path: []const u8, expected_stdout: []const u8) !void {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = std.process.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .Exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    const demo_start = std.time.nanoTimestamp();
    std.debug.print("[js-matrix] START demo={s}\n", .{path});
    var demo_ended = false;
    errdefer {
        if (!demo_ended) std.debug.print("[js-matrix] FAIL demo={s}\n", .{path});
    }

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const base = std.fs.path.basename(path);
    const stem = std.fs.path.stem(base);
    const parent = std.fs.path.dirname(path) orelse ".";
    const tag = std.fs.path.basename(parent);
    const js_name = try std.fmt.allocPrint(std.testing.allocator, "{s}_{s}.mjs", .{ tag, stem });
    defer std.testing.allocator.free(js_name);

    const build_js_argv = [_][]const u8{ "sa", "build-js", source_path, "-o", js_name, "--project-root", repo_root };
    const build_js_code = saasm.cli.execute(std.testing.allocator, build_js_argv[0..]) catch |err| {
        std.debug.print("build-js errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    if (build_js_code != 0) std.debug.print("build-js failed: {s}\n", .{path});
    try std.testing.expectEqual(@as(u8, 0), build_js_code);

    const js_file = try tmp.dir.openFile(js_name, .{});
    defer js_file.close();
    const js_bytes = try js_file.readToEndAlloc(std.testing.allocator, 1 << 24);
    defer std.testing.allocator.free(js_bytes);
    try std.testing.expect(js_bytes.len > 64);

    const js_result = try runJsWithNode(std.testing.allocator, js_name);
    defer std.testing.allocator.free(js_result.stdout);
    defer std.testing.allocator.free(js_result.stderr);
    switch (js_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, js_result.stdout, expected_stdout) or js_result.stderr.len != 0) {
                std.debug.print("js demo failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, js_result.stdout, js_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings(expected_stdout, js_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), js_result.stderr.len);

    std.debug.print("[js-matrix] END   demo={s} elapsed={}ms\n", .{ path, elapsedMs(demo_start) });
    demo_ended = true;
}

test "js backend rosetta demos match expected output under node" {
    try assertJsMatrixStdout("demos/rosetta/01_hello_world/main.sa", "hello, saasm\n");
    try assertJsMatrixStdout("demos/rosetta/02_mutability/main.sa", "20\n");
    try assertJsMatrixStdout("demos/rosetta/03_if_else/main.sa", "20\n");
    try assertJsMatrixStdout("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertJsMatrixStdout("demos/rosetta/05_struct/main.sa", "(10,20)\n");
    try assertJsMatrixStdout("demos/rosetta/06_enum_and_match/main.sa", "30\n");
    try assertJsMatrixStdout("demos/rosetta/08_closures/main.sa", "15\n");
    try assertJsMatrixStdout("demos/rosetta/09_async_await/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/10_generics_monomorph/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/11_tuples/main.sa", "(3, 4)\n");
    try assertJsMatrixStdout("demos/rosetta/12_destructuring/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/13_array_sum/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/14_slice_window/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/15_string_bytes/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/16_methods/main.sa", "25\n");
    try assertJsMatrixStdout("demos/rosetta/17_associated_fn/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/18_option_map/main.sa", "8\n");
    try assertJsMatrixStdout("demos/rosetta/21_while_loop/main.sa", "15\n");
    try assertJsMatrixStdout("demos/rosetta/20_boxed_value/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/22_break_continue/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/23_nested_loops/main.sa", "18\n");
    try assertJsMatrixStdout("demos/rosetta/24_factorial/main.sa", "120\n");
    try assertJsMatrixStdout("demos/rosetta/25_fibonacci/main.sa", "21\n");
    try assertJsMatrixStdout("demos/rosetta/26_reference_return/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/27_move_semantics/main.sa", "11\n");
    try assertJsMatrixStdout("demos/rosetta/28_borrow_chains/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/29_const_data/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/30_manual_guard_branch/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/31_trait_static_dispatch/main.sa", "16\n");
    try assertJsMatrixStdout("demos/rosetta/33_iterator_map/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/34_iterator_filter/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/35_iterator_fold/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/36_tuple_struct/main.sa", "14\n");
    try assertJsMatrixStdout("demos/rosetta/37_newtype/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/38_generic_struct_i32/main.sa", "31\n");
    try assertJsMatrixStdout("demos/rosetta/39_generic_enum_i32/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/40_impl_block_state/main.sa", "15\n");
    try assertJsMatrixStdout("demos/rosetta/41_module_imports/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/42_export_visibility/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/44_slice_iteration/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/45_config_merge/main.sa", "4 3\n");
    try assertJsMatrixStdout("demos/rosetta/46_option_default/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/47_tuple_swap/main.sa", "8,3\n");
    try assertJsMatrixStdout("demos/rosetta/48_generic_pair/main.sa", "11,31\n");
    try assertJsMatrixStdout("demos/rosetta/49_pipeline_map/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/51_refcount/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/52_queue_rotate/main.sa", "2,3,1\n");
    try assertJsMatrixStdout("demos/rosetta/43_tagged_union/main.sa", "36\n");
    try assertJsMatrixStdout("demos/rosetta/53_cache_hits/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/54_mem_fill/main.sa", "7,7,7,7\n");
    try assertJsMatrixStdout("demos/rosetta/55_builder_pattern/main.sa", "POST /api\n");
    try assertJsMatrixStdout("demos/rosetta/56_state_machine/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/57_event_loop/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/58_borrow_update/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/59_method_counter/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/60_enum_branch/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/61_thread_pool/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/62_channel_pingpong/main.sa", "8\n");
    try assertJsMatrixStdout("demos/rosetta/63_router_table/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/64_file_manifest/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/65_job_scheduler/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/66_actor_mailbox/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/67_resource_pool/main.sa", "20\n");
    try assertJsMatrixStdout("demos/rosetta/68_parser_tokens/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/69_serializer/main.sa", "{\"id\":7}\n");
    try assertJsMatrixStdout("demos/rosetta/70_integration_service/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/71_pipeline_stage/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/72_graph_walk/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/73_scene_nodes/main.sa", "15\n");
    try assertJsMatrixStdout("demos/rosetta/74_component_store/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/75_async_bridge/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/76_lockfree_counter/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/77_http_route/main.sa", "/health\n");
    try assertJsMatrixStdout("demos/rosetta/78_cli_args/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/79_metrics/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/80_workflow/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/81_kv_store/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/82_sql_scan/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/83_blob_chunk/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/84_sync_gate/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/85_scheduler_tree/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/86_cache_eviction/main.sa", "20\n");
    try assertJsMatrixStdout("demos/rosetta/87_protocol_frame/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/88_text_index/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/89_job_queue/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/90_app_shell/main.sa", "app --mode demo\n");
    try assertJsMatrixStdout("demos/rosetta/91_db_session/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/92_query_plan/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/93_log_aggregator/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/94_graphql_router/main.sa", "query user\n");
    try assertJsMatrixStdout("demos/rosetta/95_repl_shell/main.sa", "sa> \n");
    try assertJsMatrixStdout("demos/rosetta/96_task_orchestrator/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/97_sync_service/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/98_build_pipeline/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/99_release_bundle/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/100_full_app/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/176_result_flattening/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/178_panic_hook_override/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/180_try_trait_v2/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/253_contract_callback_registration/main.sa", "253\n");
    try assertJsMatrixStdout("demos/rosetta/19_result_question/main.sa", "21\n");
    try assertJsMatrixStdout("demos/rosetta/50_error_chain/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/07_trait_vtable/main.sa", "77\n");
    try assertJsMatrixStdout("demos/rosetta/110_trait_super_vtable/main.sa", "15\n");
    try assertJsMatrixStdout("demos/rosetta/32_trait_object_vector/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/101_custom_drop/main.sa", "16\n");
    try assertJsMatrixStdout("demos/rosetta/102_raii_guard/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/103_labeled_break/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/104_if_let_chains/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/105_let_else/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/106_cell_interior_mut/main.sa", "30\n");
    try assertJsMatrixStdout("demos/rosetta/107_refcell_dynamic_borrow/main.sa", "7\n9\n");
    try assertJsMatrixStdout("demos/rosetta/108_atomic_spin_lock/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/109_atomic_fetch_add/main.sa", "13\n");
    try assertJsMatrixStdout("demos/rosetta/111_extern_c_abi/main.sa", "23\n");
    try assertJsMatrixStdout("demos/rosetta/112_raw_pointer_arithmetic/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/113_union_ffi_types/main.sa", "36\n");
    try assertJsMatrixStdout("demos/rosetta/114_callback_from_c/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/115_opaque_pointers/main.sa", "0\n");
    try assertJsMatrixStdout("demos/rosetta/116_va_list_variadic/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/117_inline_assembly/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/118_global_mutable_state/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/119_simd_intrinsics/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/120_volatile_memory_access/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/121_rwlock_reader_writer/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/122_condvar_wait_notify/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/123_barrier_sync/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/124_thread_local_storage/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/125_once_cell_lazy/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/126_mpmc_channel/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/127_hazard_pointers/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/128_rcu_read_copy_update/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/129_seqlock_optimistic/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/130_park_unpark_thread/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/131_waker_vtable_mechanics/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/132_pinning_and_unpin/main.sa", "8\n");
    try assertJsMatrixStdout("demos/rosetta/133_select_macro_race/main.sa", "11\n");
    try assertJsMatrixStdout("demos/rosetta/134_join_all_futures/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/135_async_streams/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/136_executor_task_queue/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/137_io_uring_submission/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/138_epoll_kqueue_event/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/139_cancellation_safety/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/140_yield_now_suspend/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/141_dynamically_sized_types/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/142_zero_sized_types/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/143_never_type_diverge/main.sa", "0\n");
    try assertJsMatrixStdout("demos/rosetta/144_phantom_data_marker/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/145_opaque_type_alias/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/146_never_type_fallback/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/147_custom_dst_pointers/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/148_transparent_repr/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/149_packed_repr/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/150_c_repr_alignment/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/151_global_alloc_trait/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/152_memory_layout_struct/main.sa", "12\n");
    try assertJsMatrixStdout("demos/rosetta/153_box_into_raw/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/154_box_from_raw/main.sa", "11\n");
    try assertJsMatrixStdout("demos/rosetta/155_arena_allocator_bump/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/156_slab_allocator_freelist/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/157_aligned_alloc_simd/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/158_custom_dst_alloc/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/159_mem_forget_leak/main.sa", "9\n");
    try assertJsMatrixStdout("demos/rosetta/160_manually_drop_union/main.sa", "11\n");
    try assertJsMatrixStdout("demos/rosetta/161_generic_associated_types/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/162_auto_traits_send_sync/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/163_object_safety_rules/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/164_trait_upcasting/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/165_blanket_impl_resolution/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/166_specialization_fallback/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/167_const_generics_expansion/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/168_type_alias_impl_trait/main.sa", "0\n");
    try assertJsMatrixStdout("demos/rosetta/169_negative_impls/main.sa", "0\n");
    try assertJsMatrixStdout("demos/rosetta/170_marker_traits/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/171_anyhow_dynamic_error/main.sa", "0\n");
    try assertJsMatrixStdout("demos/rosetta/172_eyre_color_eyre/main.sa", "7\n");
    try assertJsMatrixStdout("demos/rosetta/173_catch_unwind_panic/main.sa", "stop\n");
    try assertJsMatrixStdout("demos/rosetta/174_backtrace_capture/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/175_thiserror_macro_derive/main.sa", "oops\n");
    try assertJsMatrixStdout("demos/rosetta/177_unwrap_unwrap_err/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/179_assert_macro_expansion/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/181_file_descriptor_raii/main.sa", "3\n");
    try assertJsMatrixStdout("demos/rosetta/182_mmap_memory_mapping/main.sa", "4\n");
    try assertJsMatrixStdout("demos/rosetta/183_signal_handling_setup/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/184_pthread_spawn_join/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/185_dynamic_lib_dlopen/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/186_sqlite_c_api_binding/main.sa", "8\n");
    try assertJsMatrixStdout("demos/rosetta/187_opengl_context_swap/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/188_websocket_frame_parse/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/189_protobuf_varint_decode/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/190_base64_encode_simd/main.sa", "TWFu\n");
    try assertJsMatrixStdout("demos/rosetta/191_macro_rules_ast_emit/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/192_proc_macro_derive_ast/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/193_attribute_macro_rewrite/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/194_cfg_conditional_compilation/main.sa", "x86\n");
    try assertJsMatrixStdout("demos/support/sort_probe.sa", "sort ok\n");
    try assertJsMatrixStdout("demos/support/hashmap_probe.sa", "alpha\nbravo\nmap ok\n");
    try assertJsMatrixStdout("demos/support/hashset_probe.sa", "set ok\n");
    try assertJsMatrixStdout("demos/support/once_probe.sa", "once ok\n");
    try assertJsMatrixStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

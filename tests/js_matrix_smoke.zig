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
    try assertJsMatrixStdout("demos/rosetta/195_build_script_codegen/main.sa", "build output\n");
    try assertJsMatrixStdout("demos/rosetta/196_lto_link_time_opt/main.sa", "37\n");
    try assertJsMatrixStdout("demos/rosetta/197_profile_guided_opt/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/198_control_flow_guard_cfi/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/199_address_sanitizer_asan/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/200_sa_asm_quine/main.sa", "@import \"sa_std/io/print.sai\"\n\n@const RESULT_ERR = utf8:\"error\\n\"\n@const SOURCE = utf8:\"@import \\\"sa_std/io/print.sai\\\"\\n\\n@const RESULT_ERR = utf8:\\\"error\\\\n\\\"\\n@const SOURCE = utf8:\"\n\n@main() -> i32");
    try assertJsMatrixStdout("demos/rosetta/201_pkg_manifest_basic/main.sa", "201\n");
    try assertJsMatrixStdout("demos/rosetta/202_pkg_dependencies_local/main.sa", "202\n");
    try assertJsMatrixStdout("demos/rosetta/203_pkg_dependencies_git/main.sa", "203\n");
    try assertJsMatrixStdout("demos/rosetta/204_pkg_dependencies_registry/main.sa", "204\n");
    // NOTE: 205 (import cycle) and 207 (duplicate version symbols) are
    // intentional compile-failure demos per their readmes (no executable is
    // produced); they are covered by the compiler, not the JS matrix.
    try assertJsMatrixStdout("demos/rosetta/206_pkg_version_resolution/main.sa", "206\n");
    try assertJsMatrixStdout("demos/rosetta/208_pkg_dev_dependencies/main.sa", "208\n");
    try assertJsMatrixStdout("demos/rosetta/209_pkg_build_dependencies/main.sa", "209\n");
    try assertJsMatrixStdout("demos/rosetta/210_pkg_workspace_root/main.sa", "210\n");
    try assertJsMatrixStdout("demos/rosetta/211_pkg_workspace_inheritance/main.sa", "211\n");
    try assertJsMatrixStdout("demos/rosetta/212_pkg_feature_flags/main.sa", "212\n");
    try assertJsMatrixStdout("demos/rosetta/213_pkg_default_features/main.sa", "213\n");
    try assertJsMatrixStdout("demos/rosetta/214_pkg_target_specific_deps/main.sa", "214\n");
    try assertJsMatrixStdout("demos/rosetta/215_pkg_patch_override/main.sa", "215\n");
    try assertJsMatrixStdout("demos/rosetta/216_pkg_profile_release/main.sa", "216\n");
    // NOTE: 226 (import cycle) and 227 (duplicate #def) are intentional
    // compile-failure demos per their readmes, like 205/207 before them.
    try assertJsMatrixStdout("demos/rosetta/217_pkg_profile_debug/main.sa", "217\n");
    try assertJsMatrixStdout("demos/rosetta/218_pkg_metadata_custom/main.sa", "218\n");
    try assertJsMatrixStdout("demos/rosetta/219_pkg_bin_multiple/main.sa", "219\n");
    try assertJsMatrixStdout("demos/rosetta/220_pkg_lib_dynamic/main.sa", "220\n");
    try assertJsMatrixStdout("demos/rosetta/221_mod_relative_import/main.sa", "221\n");
    try assertJsMatrixStdout("demos/rosetta/222_mod_absolute_import/main.sa", "222\n");
    try assertJsMatrixStdout("demos/rosetta/223_mod_visibility_private/main.sa", "223\n");
    try assertJsMatrixStdout("demos/rosetta/224_mod_reexport_pub_use/main.sa", "224\n");
    try assertJsMatrixStdout("demos/rosetta/225_mod_namespace_prefix/main.sa", "225\n");
    try assertJsMatrixStdout("demos/rosetta/228_mod_iface_separation/main.sa", "228\n");
    try assertJsMatrixStdout("demos/rosetta/229_mod_layout_injection/main.sa", "229\n");
    try assertJsMatrixStdout("demos/rosetta/230_mod_std_prelude/main.sa", "230\n");
    try assertJsMatrixStdout("demos/rosetta/231_mod_directory_module/main.sa", "231\n");
    try assertJsMatrixStdout("demos/rosetta/232_mod_conditional_import/main.sa", "232\n");
    try assertJsMatrixStdout("demos/rosetta/233_mod_alias_import/main.sa", "233\n");
    try assertJsMatrixStdout("demos/rosetta/234_mod_unused_import_lint/main.sa", "234\n");
    try assertJsMatrixStdout("demos/rosetta/235_mod_transitive_dependency/main.sa", "235\n");
    try assertJsMatrixStdout("demos/rosetta/236_mod_extern_block_grouping/main.sa", "236\n");
    try assertJsMatrixStdout("demos/rosetta/237_mod_inline_submodule/main.sa", "237\n");
    try assertJsMatrixStdout("demos/rosetta/238_mod_path_resolution_order/main.sa", "238\n");
    try assertJsMatrixStdout("demos/rosetta/239_mod_version_suffix_isolation/main.sa", "239\n");
    try assertJsMatrixStdout("demos/rosetta/240_mod_entry_point_override/main.sa", "240\n");
    try assertJsMatrixStdout("demos/rosetta/241_contract_layout_stability/main.sa", "241\n");
    try assertJsMatrixStdout("demos/rosetta/242_contract_opaque_struct/main.sa", "242\n");
    // NOTE: 243 is an intentional CapabilityMismatch failure demo per its
    // readme (broken call site, no executable produced).
    try assertJsMatrixStdout("demos/rosetta/244_contract_vtable_export/main.sa", "244\n");
    try assertJsMatrixStdout("demos/rosetta/245_contract_generic_monomorph_share/main.sa", "245\n");
    try assertJsMatrixStdout("demos/rosetta/246_contract_semver_minor_update/main.sa", "246\n");
    try assertJsMatrixStdout("demos/rosetta/247_contract_semver_major_break/main.sa", "247\n");
    try assertJsMatrixStdout("demos/rosetta/248_contract_ffi_boundary_trust/main.sa", "248\n");
    try assertJsMatrixStdout("demos/rosetta/249_contract_macro_export/main.sa", "249\n");
    try assertJsMatrixStdout("demos/rosetta/250_contract_const_export/main.sa", "250\n");
    try assertJsMatrixStdout("demos/rosetta/251_contract_resource_ownership/main.sa", "251\n");
    try assertJsMatrixStdout("demos/rosetta/252_contract_error_code_mapping/main.sa", "252\n");
    try assertJsMatrixStdout("demos/rosetta/254_contract_plugin_system/main.sa", "254\n");
    try assertJsMatrixStdout("demos/rosetta/255_contract_memory_allocator_swap/main.sa", "255\n");
    try assertJsMatrixStdout("demos/rosetta/256_contract_panic_handler_propagate/main.sa", "256\n");
    try assertJsMatrixStdout("demos/rosetta/257_contract_log_facade/main.sa", "257\n");
    try assertJsMatrixStdout("demos/rosetta/258_contract_thread_local_isolation/main.sa", "258\n");
    try assertJsMatrixStdout("demos/rosetta/259_contract_static_init_order/main.sa", "259\n");
    try assertJsMatrixStdout("demos/rosetta/260_contract_deprecated_warning/main.sa", "260\n");
    try assertJsMatrixStdout("demos/rosetta/261_build_rs_codegen_saasm/main.sa", "261\n");
    try assertJsMatrixStdout("demos/rosetta/262_build_bindgen_c_header/main.sa", "262\n");
    try assertJsMatrixStdout("demos/rosetta/263_build_asset_bundling/main.sa", "263\n");
    try assertJsMatrixStdout("demos/rosetta/264_build_env_var_injection/main.sa", "264\n");
    try assertJsMatrixStdout("demos/rosetta/265_build_custom_linker_script/main.sa", "265\n");
    try assertJsMatrixStdout("demos/rosetta/266_build_pre_compile_hook/main.sa", "266\n");
    try assertJsMatrixStdout("demos/rosetta/267_build_post_compile_hook/main.sa", "267\n");
    try assertJsMatrixStdout("demos/rosetta/268_build_cross_compile_wasm/main.sa", "268\n");
    try assertJsMatrixStdout("demos/rosetta/269_build_cross_compile_windows/main.sa", "269\n");
    try assertJsMatrixStdout("demos/rosetta/270_build_sysroot_custom/main.sa", "270\n");
    try assertJsMatrixStdout("demos/rosetta/271_build_optimization_passes/main.sa", "271\n");
    try assertJsMatrixStdout("demos/rosetta/272_build_sanitizer_flags/main.sa", "272\n");
    try assertJsMatrixStdout("demos/rosetta/273_build_test_harness/main.sa", "273\n");
    try assertJsMatrixStdout("demos/rosetta/274_build_benchmark_runner/main.sa", "274\n");
    try assertJsMatrixStdout("demos/rosetta/275_build_doc_generator/main.sa", "275\n");
    try assertJsMatrixStdout("demos/rosetta/276_build_incremental_caching/main.sa", "276\n");
    try assertJsMatrixStdout("demos/rosetta/277_build_parallel_compilation/main.sa", "277\n");
    try assertJsMatrixStdout("demos/rosetta/278_build_reproducible_builds/main.sa", "278\n");
    try assertJsMatrixStdout("demos/rosetta/279_build_artifact_caching_remote/main.sa", "279\n");
    try assertJsMatrixStdout("demos/rosetta/280_build_ci_cd_integration/main.sa", "280\n");
    try assertJsMatrixStdout("demos/rosetta/281_ffi_link_system_libc/main.sa", "281\n");
    try assertJsMatrixStdout("demos/rosetta/282_ffi_link_static_c_lib/main.sa", "282\n");
    try assertJsMatrixStdout("demos/rosetta/283_ffi_link_dynamic_c_lib/main.sa", "283\n");
    try assertJsMatrixStdout("demos/rosetta/284_ffi_pkg_config_integration/main.sa", "284\n");
    try assertJsMatrixStdout("demos/rosetta/285_ffi_objective_c_framework/main.sa", "285\n");
    try assertJsMatrixStdout("demos/rosetta/286_ffi_rust_staticlib_integration/main.sa", "286\n");
    try assertJsMatrixStdout("demos/rosetta/287_ffi_zig_export_integration/main.sa", "287\n");
    try assertJsMatrixStdout("demos/rosetta/288_ffi_cxx_name_mangling/main.sa", "288\n");
    try assertJsMatrixStdout("demos/rosetta/289_ffi_opaque_handle_passing/main.sa", "289\n");
    try assertJsMatrixStdout("demos/rosetta/290_ffi_callback_thunk/main.sa", "290\n");
    try assertJsMatrixStdout("demos/rosetta/291_eco_wasm_host_imports/main.sa", "291\n");
    try assertJsMatrixStdout("demos/rosetta/292_eco_wasm_memory_export/main.sa", "292\n");
    try assertJsMatrixStdout("demos/rosetta/293_eco_embedded_no_os/main.sa", "293\n");
    try assertJsMatrixStdout("demos/rosetta/294_eco_os_kernel_module/main.sa", "294\n");
    try assertJsMatrixStdout("demos/rosetta/295_eco_bpf_ebpf_bytecode/main.sa", "295\n");
    try assertJsMatrixStdout("demos/rosetta/296_eco_gpu_ptx_shader/main.sa", "296\n");
    try assertJsMatrixStdout("demos/rosetta/297_eco_game_engine_ecs/main.sa", "297\n");
    try assertJsMatrixStdout("demos/rosetta/298_eco_cryptography_simd/main.sa", "298\n");
    try assertJsMatrixStdout("demos/rosetta/299_eco_language_server_protocol/main.sa", "299\n");
    try assertJsMatrixStdout("demos/rosetta/300_eco_sa_lang_registry_publish/main.sa", "300\n");
    // NOTE: 301 (http client) and 302 (http server) run on staged
    // in-heap oracle shims (echo response / canned /stream request), the
    // same single-threaded simulation waterline as the fd/sqlite shims;
    // native covers them with real 127.0.0.1 loopback instead.
    try assertJsMatrixStdout("demos/rosetta/301_http_client_saasm/main.sa", "ok\n");
    try assertJsMatrixStdout("demos/rosetta/302_http_server_saasm/main.sa", "ok\n");
    try assertJsMatrixStdout("demos/rosetta/303_match_guard_macro/main.sa", "negative,zero,small,large\n");
    try assertJsMatrixStdout("demos/rosetta/304_while_let_macro/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/305_range_pattern_macro/main.sa", "0,1,2,3,-1");
    try assertJsMatrixStdout("demos/rosetta/306_or_pattern_macro/main.sa", "2\n");
    try assertJsMatrixStdout("demos/rosetta/307_at_binding_macro/main.sa", "30,800,0");
    try assertJsMatrixStdout("demos/rosetta/308_rest_pattern_macro/main.sa", "30,10");
    try assertJsMatrixStdout("demos/rosetta/309_try_block_macro/main.sa", "30\n");
    try assertJsMatrixStdout("demos/rosetta/310_generator_yield_macro/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/311_cstring_literal_macro/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/312_dbg_macro/main.sa", "11\n");
    try assertJsMatrixStdout("demos/rosetta/313_matches_macro/main.sa", "1\n");
    try assertJsMatrixStdout("demos/rosetta/314_tail_call_become/main.sa", "3628800\n");
    try assertJsMatrixStdout("demos/rosetta/315_async_closure_macro/main.sa", "15\n");
    try assertJsMatrixStdout("demos/rosetta/316_select_with_patterns/main.sa", "10\n");
    try assertJsMatrixStdout("demos/rosetta/317_for_each_iter_macro/main.sa", "150\n");
    try assertJsMatrixStdout("demos/rosetta/318_vec_literal_macro/main.sa", "4,100\n");
    try assertJsMatrixStdout("demos/rosetta/319_default_trait_macro/main.sa", "1400\n");
    try assertJsMatrixStdout("demos/rosetta/320_from_into_conversion/main.sa", "212\n");
    try assertJsMatrixStdout("demos/rosetta/321_operator_overload_macro/main.sa", "4,6\n");
    try assertJsMatrixStdout("demos/rosetta/322_deref_coercion_macro/main.sa", "52\n");
    try assertJsMatrixStdout("demos/rosetta/323_index_trait_macro/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/324_drop_guard_macro/main.sa", "42\n");
    try assertJsMatrixStdout("demos/rosetta/325_loop_break_value_macro/main.sa", "25\n");
    try assertJsMatrixStdout("demos/rosetta/326_lazy_static_macro/main.sa", "84\n");
    try assertJsMatrixStdout("demos/rosetta/327_thread_local_macro/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/328_cfg_runtime_macro/main.sa", "x86_64\n");
    try assertJsMatrixStdout("demos/rosetta/329_assert_with_message/main.sa", "5\n");
    try assertJsMatrixStdout("demos/rosetta/330_closure_with_state_macro/main.sa", "6\n");
    try assertJsMatrixStdout("demos/rosetta/331_rc_shared_ownership/main.sa", "42,42\n");
    try assertJsMatrixStdout("demos/rosetta/332_cell_interior_mutability/main.sa", "100\n");
    try assertJsMatrixStdout("demos/rosetta/333_weak_cyclic_reference/main.sa", "upgraded\n");
    try assertJsMatrixStdout("demos/rosetta/334_indirect_import_shadow/main.sa", "334\n");
    try assertJsMatrixStdout("demos/rosetta/335_ts_slice_inverted_bounds/main.sa", "335\n");
    try assertJsMatrixStdout("demos/rosetta/336_ts_trunc_u64_to_i32/main.sa", "336\n");
    try assertJsMatrixStdout("demos/rosetta/337_u64_add_wrap64/main.sa", "337\n");
    try assertJsMatrixStdout("demos/rosetta/338_zext_i32_to_i64/main.sa", "338\n");
    try assertJsMatrixStdout("demos/rosetta/339_sext_i32_to_i64/main.sa", "339\n");
    try assertJsMatrixStdout("demos/rosetta/340_sitofp_fptosi_roundtrip/main.sa", "340\n");
    try assertJsMatrixStdout("demos/rosetta/341_fptosi_truncates_toward_zero/main.sa", "341\n");
    try assertJsMatrixStdout("demos/rosetta/342_uitofp_large_u64_roundtrip/main.sa", "342\n");
    try assertJsMatrixStdout("demos/rosetta/343_bitcast_i32_u32/main.sa", "343\n");
    try assertJsMatrixStdout("demos/rosetta/344_bitcast_u64_i64/main.sa", "344\n");
    try assertJsMatrixStdout("demos/rosetta/345_fptrunc_f32_rounding/main.sa", "345\n");
    try assertJsMatrixStdout("demos/rosetta/346_lshr_u64_high_bit/main.sa", "346\n");
    try assertJsMatrixStdout("demos/rosetta/347_lshr_u32_to_max/main.sa", "347\n");
    try assertJsMatrixStdout("demos/rosetta/348_udiv_u32_to_max/main.sa", "348\n");
    try assertJsMatrixStdout("demos/rosetta/349_ashr_i64_arithmetic/main.sa", "349\n");
    try assertJsMatrixStdout("demos/rosetta/350_shl_i64_large_shift/main.sa", "350\n");
    try assertJsMatrixStdout("demos/rosetta/351_divmod_family/main.sa", "351\n");
    try assertJsMatrixStdout("demos/rosetta/352_band_u64_high_bits/main.sa", "352\n");
    try assertJsMatrixStdout("demos/rosetta/353_ult_ugt_u64/main.sa", "353\n");
    try assertJsMatrixStdout("demos/rosetta/354_neg_not_i32/main.sa", "354\n");
    try assertJsMatrixStdout("demos/rosetta/355_and_or_xor_i32/main.sa", "355\n");
    try assertJsMatrixStdout("demos/rosetta/356_br_null_ptr/main.sa", "356\n");
    try assertJsMatrixStdout("demos/rosetta/357_br_null_nonnull/main.sa", "357\n");
    try assertJsMatrixStdout("demos/rosetta/358_br_null_computed_zero/main.sa", "358\n");
    try assertJsMatrixStdout("demos/rosetta/359_br_null_u64max/main.sa", "359\n");
    try assertJsMatrixStdout("demos/rosetta/360_br_null_i32_zero/main.sa", "360\n");
    try assertJsMatrixStdout("demos/rosetta/361_take_basic/main.sa", "361\n");
    try assertJsMatrixStdout("demos/rosetta/362_take_field/main.sa", "362\n");
    try assertJsMatrixStdout("demos/rosetta/363_fence_noop/main.sa", "363\n");
    try assertJsMatrixStdout("demos/rosetta/364_br_null_loaded/main.sa", "364\n");
    try assertJsMatrixStdout("demos/rosetta/365_br_null_chain/main.sa", "365\n");
    try assertJsMatrixStdout("demos/rosetta/366_try_unpack_const/main.sa", "366\n");
    try assertJsMatrixStdout("demos/rosetta/367_try_params_arith/main.sa", "367\n");
    try assertJsMatrixStdout("demos/rosetta/368_try_chained/main.sa", "368\n");
    try assertJsMatrixStdout("demos/rosetta/369_try_nested_fallible/main.sa", "369\n");
    try assertJsMatrixStdout("demos/rosetta/370_try_u64_payload/main.sa", "370\n");
    try assertJsMatrixStdout("demos/rosetta/371_try_in_loop/main.sa", "371\n");
    try assertJsMatrixStdout("demos/rosetta/372_try_br_null_combo/main.sa", "372\n");
    try assertJsMatrixStdout("demos/rosetta/373_try_mem_roundtrip/main.sa", "373\n");
    try assertJsMatrixStdout("demos/rosetta/374_try_f64_payload/main.sa", "374\n");
    try assertJsMatrixStdout("demos/rosetta/375_try_branchy_returns/main.sa", "375\n");
    try assertJsMatrixStdout("demos/rosetta/376_mem_i8_u8/main.sa", "376\n");
    try assertJsMatrixStdout("demos/rosetta/377_mem_i16_u16/main.sa", "377\n");
    try assertJsMatrixStdout("demos/rosetta/378_mem_u32_i32/main.sa", "378\n");
    try assertJsMatrixStdout("demos/rosetta/379_mem_f32_roundtrip/main.sa", "379\n");
    try assertJsMatrixStdout("demos/rosetta/380_mem_f64_roundtrip/main.sa", "380\n");
    try assertJsMatrixStdout("demos/rosetta/381_mem_ptr_roundtrip/main.sa", "381\n");
    try assertJsMatrixStdout("demos/rosetta/382_mem_i1_roundtrip/main.sa", "382\n");
    try assertJsMatrixStdout("demos/rosetta/383_zext_i8_load/main.sa", "383\n");
    try assertJsMatrixStdout("demos/rosetta/384_zext_i16_load/main.sa", "384\n");
    try assertJsMatrixStdout("demos/rosetta/385_sext_i8_load/main.sa", "385\n");
    try assertJsMatrixStdout("demos/rosetta/386_div_u64max_by_one/main.sa", "386\n");
    try assertJsMatrixStdout("demos/rosetta/387_div_i64_neg/main.sa", "387\n");
    try assertJsMatrixStdout("demos/rosetta/388_rem_u64max_loaded/main.sa", "388\n");
    try assertJsMatrixStdout("demos/rosetta/389_gt_u64_loaded/main.sa", "389\n");
    try assertJsMatrixStdout("demos/rosetta/390_shr_signed_unsigned/main.sa", "390\n");
    try assertJsMatrixStdout("demos/rosetta/391_div_i32_small/main.sa", "391\n");
    try assertJsMatrixStdout("demos/rosetta/392_rem_i32_neg/main.sa", "392\n");
    try assertJsMatrixStdout("demos/rosetta/393_gt_i32_signed/main.sa", "393\n");
    try assertJsMatrixStdout("demos/rosetta/394_div_and_chain/main.sa", "394\n");
    try assertJsMatrixStdout("demos/rosetta/395_div_mixed_sign/main.sa", "395\n");
    try assertJsMatrixStdout("demos/rosetta/396_trunc_narrow_family/main.sa", "396\n");
    try assertJsMatrixStdout("demos/rosetta/397_trunc_i64_u64/main.sa", "397\n");
    try assertJsMatrixStdout("demos/rosetta/398_bitcast_i64_ptr/main.sa", "398\n");
    try assertJsMatrixStdout("demos/rosetta/399_zext_narrow_targets/main.sa", "399\n");
    try assertJsMatrixStdout("demos/rosetta/400_sitofp_f32_bits/main.sa", "400\n");
    try assertJsMatrixStdout("demos/rosetta/401_fptosi_narrow/main.sa", "401\n");
    try assertJsMatrixStdout("demos/rosetta/402_bitcast_i32_f32/main.sa", "402\n");
    try assertJsMatrixStdout("demos/rosetta/403_bitcast_f32_i32/main.sa", "403\n");
    try assertJsMatrixStdout("demos/rosetta/404_bitcast_f64_roundtrip/main.sa", "404\n");
    try assertJsMatrixStdout("demos/rosetta/405_fneg_basic/main.sa", "405\n");
    try assertJsMatrixStdout("demos/rosetta/406_fadd_basic/main.sa", "406\n");
    try assertJsMatrixStdout("demos/rosetta/407_fsub_basic/main.sa", "407\n");
    try assertJsMatrixStdout("demos/rosetta/408_fmul_basic/main.sa", "408\n");
    try assertJsMatrixStdout("demos/rosetta/409_fdiv_basic/main.sa", "409\n");
    try assertJsMatrixStdout("demos/rosetta/410_fcmp_family/main.sa", "410\n");
    try assertJsMatrixStdout("demos/rosetta/411_float_chain/main.sa", "411\n");
    try assertJsMatrixStdout("demos/rosetta/412_fmul_by_zero/main.sa", "412\n");
    try assertJsMatrixStdout("demos/rosetta/413_fsub_self_zero/main.sa", "413\n");
    try assertJsMatrixStdout("demos/rosetta/414_fadd_loop_accum/main.sa", "414\n");
    try assertJsMatrixStdout("demos/rosetta/415_fneg_add_zero/main.sa", "415\n");
    try assertJsMatrixStdout("demos/rosetta/416_fallible_f64_const/main.sa", "416\n");
    try assertJsMatrixStdout("demos/rosetta/417_fallible_f64_param/main.sa", "417\n");
    try assertJsMatrixStdout("demos/rosetta/418_fallible_f64_nested/main.sa", "418\n");
    try assertJsMatrixStdout("demos/rosetta/419_fallible_f64_branchy/main.sa", "419\n");
    try assertJsMatrixStdout("demos/rosetta/420_fallible_f64_chain/main.sa", "420\n");
    try assertJsMatrixStdout("demos/rosetta/421_fallible_f32_basic/main.sa", "421\n");
    try assertJsMatrixStdout("demos/rosetta/422_fallible_float_loop/main.sa", "422\n");
    try assertJsMatrixStdout("demos/rosetta/423_fallible_mixed_int_float/main.sa", "423\n");
    try assertJsMatrixStdout("demos/rosetta/424_fallible_float_cmp/main.sa", "424\n");
    try assertJsMatrixStdout("demos/rosetta/425_fallible_f64_negate/main.sa", "425\n");
    try assertJsMatrixStdout("demos/rosetta/426_fallible_mem_f64/main.sa", "426\n");
    try assertJsMatrixStdout("demos/rosetta/427_fallible_mem_f32/main.sa", "427\n");
    try assertJsMatrixStdout("demos/rosetta/428_fallible_mem_arith/main.sa", "428\n");
    try assertJsMatrixStdout("demos/rosetta/429_fallible_mem_int/main.sa", "429\n");
    try assertJsMatrixStdout("demos/rosetta/430_fallible_mem_two_slots/main.sa", "430\n");
    try assertJsMatrixStdout("demos/rosetta/431_fallible_mem_param/main.sa", "431\n");
    try assertJsMatrixStdout("demos/rosetta/432_fallible_mem_nested/main.sa", "432\n");
    try assertJsMatrixStdout("demos/rosetta/433_fallible_mem_loop/main.sa", "433\n");
    try assertJsMatrixStdout("demos/rosetta/434_fallible_mem_branchy/main.sa", "434\n");
    try assertJsMatrixStdout("demos/rosetta/435_fallible_mem_overwrite/main.sa", "435\n");
    try assertJsMatrixStdout("demos/rosetta/436_u64_pow53_exact/main.sa", "436\n");
    try assertJsMatrixStdout("demos/rosetta/437_u64_pow53_plus1_even/main.sa", "437\n");
    try assertJsMatrixStdout("demos/rosetta/438_u64_pow53_plus3_even/main.sa", "438\n");
    try assertJsMatrixStdout("demos/rosetta/439_f32_round_half_even/main.sa", "439\n");
    try assertJsMatrixStdout("demos/rosetta/440_f32_eps_visible/main.sa", "440\n");
    try assertJsMatrixStdout("demos/rosetta/441_uitofp_max_u64/main.sa", "441\n");
    try assertJsMatrixStdout("demos/rosetta/442_sitofp_neg_large_exact/main.sa", "442\n");
    try assertJsMatrixStdout("demos/rosetta/443_fadd_absorption/main.sa", "443\n");
    try assertJsMatrixStdout("demos/rosetta/444_equiv_fractions_equal/main.sa", "444\n");
    try assertJsMatrixStdout("demos/rosetta/445_fneg_zero_eq/main.sa", "445\n");
    try assertJsMatrixStdout("demos/rosetta/446_struct_two_f64/main.sa", "446\n");
    try assertJsMatrixStdout("demos/rosetta/447_struct_tag_payload/main.sa", "447\n");
    try assertJsMatrixStdout("demos/rosetta/448_struct_field_independence/main.sa", "448\n");
    try assertJsMatrixStdout("demos/rosetta/449_array4_f64_sum/main.sa", "449\n");
    try assertJsMatrixStdout("demos/rosetta/450_array2_f64_scale/main.sa", "450\n");
    try assertJsMatrixStdout("demos/rosetta/451_nested_struct_sum/main.sa", "451\n");
    try assertJsMatrixStdout("demos/rosetta/452_struct_f32_pair/main.sa", "452\n");
    try assertJsMatrixStdout("demos/rosetta/453_struct_copy/main.sa", "453\n");
    try assertJsMatrixStdout("demos/rosetta/454_struct_mixed_three/main.sa", "454\n");
    try assertJsMatrixStdout("demos/rosetta/455_struct_swap_fields/main.sa", "455\n");
    try assertJsMatrixStdout("demos/rosetta/456_vtable_f64_const/main.sa", "456\n");
    try assertJsMatrixStdout("demos/rosetta/457_vtable_f64_scale/main.sa", "457\n");
    try assertJsMatrixStdout("demos/rosetta/458_vtable_two_impls/main.sa", "458\n");
    try assertJsMatrixStdout("demos/rosetta/459_vtable_struct_add/main.sa", "459\n");
    try assertJsMatrixStdout("demos/rosetta/460_vtable_mem_spill/main.sa", "460\n");
    try assertJsMatrixStdout("demos/rosetta/461_vtable_chain/main.sa", "461\n");
    try assertJsMatrixStdout("demos/rosetta/462_vtable_int_param/main.sa", "462\n");
    try assertJsMatrixStdout("demos/rosetta/463_vtable_branchy_pick/main.sa", "463\n");
    try assertJsMatrixStdout("demos/rosetta/464_vtable_fallible/main.sa", "464\n");
    try assertJsMatrixStdout("demos/rosetta/465_vtable_fneg/main.sa", "465\n");
    try assertJsMatrixStdout("demos/rosetta/466_callback_register_invoke/main.sa", "466\n");
    try assertJsMatrixStdout("demos/rosetta/467_callback_accum_loop/main.sa", "467\n");
    try assertJsMatrixStdout("demos/rosetta/468_callback_slot_write/main.sa", "468\n");
    try assertJsMatrixStdout("demos/rosetta/469_callback_chain/main.sa", "469\n");
    try assertJsMatrixStdout("demos/rosetta/470_callback_select/main.sa", "470\n");
    try assertJsMatrixStdout("demos/rosetta/471_callback_int_float/main.sa", "471\n");
    try assertJsMatrixStdout("demos/rosetta/472_callback_f32_double/main.sa", "472\n");
    try assertJsMatrixStdout("demos/rosetta/473_callback_nested_invoke/main.sa", "473\n");
    try assertJsMatrixStdout("demos/rosetta/474_callback_signed_branch/main.sa", "474\n");
    try assertJsMatrixStdout("demos/rosetta/475_callback_const_producer/main.sa", "475\n");
    try assertJsMatrixStdout("demos/rosetta/476_const_float/main.sa", "476\n");
    try assertJsMatrixStdout("demos/rosetta/477_error_map_float/main.sa", "477\n");
    try assertJsMatrixStdout("demos/rosetta/478_vtable_export_float/main.sa", "478\n");
    try assertJsMatrixStdout("demos/rosetta/479_ownership_float/main.sa", "479\n");
    try assertJsMatrixStdout("demos/rosetta/480_callback_reg_float/main.sa", "480\n");
    try assertJsMatrixStdout("demos/rosetta/481_opaque_float/main.sa", "481\n");
    try assertJsMatrixStdout("demos/rosetta/482_const_f32_float/main.sa", "482\n");
    try assertJsMatrixStdout("demos/rosetta/483_impl_arith_float/main.sa", "483\n");
    try assertJsMatrixStdout("demos/rosetta/484_error_fallback_float/main.sa", "484\n");
    try assertJsMatrixStdout("demos/rosetta/485_vtable_param_float/main.sa", "485\n");
    try assertJsMatrixStdout("demos/rosetta/486_diamond_shared_leaf/main.sa", "486\n");
    try assertJsMatrixStdout("demos/rosetta/487_four_level_chain/main.sa", "487\n");
    try assertJsMatrixStdout("demos/rosetta/488_sibling_cross_import/main.sa", "488\n");
    try assertJsMatrixStdout("demos/rosetta/489_same_basename_isolation/main.sa", "489\n");
    try assertJsMatrixStdout("demos/rosetta/490_barrel_three_leaves/main.sa", "490\n");
    try assertJsMatrixStdout("demos/rosetta/491_shared_layout_two_bridges/main.sa", "491\n");
    try assertJsMatrixStdout("demos/rosetta/492_stateful_shared_module/main.sa", "492\n");
    try assertJsMatrixStdout("demos/rosetta/493_float_deep_chain/main.sa", "493\n");
    try assertJsMatrixStdout("demos/rosetta/494_versioned_float_iface/main.sa", "494\n");
    try assertJsMatrixStdout("demos/rosetta/495_fanout_three_leaves/main.sa", "495\n");
    try assertJsMatrixStdout("demos/rosetta/496_npm_os_totalmem/main.sa", "496\n");
    try assertJsMatrixStdout("demos/rosetta/497_npm_os_parallelism/main.sa", "497\n");
    try assertJsMatrixStdout("demos/rosetta/498_npm_path_isabs/main.sa", "498\n");
    try assertJsMatrixStdout("demos/rosetta/499_npm_util_isequal/main.sa", "499\n");
    try assertJsMatrixStdout("demos/rosetta/500_npm_ns_isabs/main.sa", "500\n");
    try assertJsMatrixStdout("demos/rosetta/501_npm_ns_isequal/main.sa", "501\n");
    try assertJsMatrixStdout("demos/rosetta/503_macro_fadd_emit/main.sa", "503\n");
    try assertJsMatrixStdout("demos/rosetta/504_macro_fdiv_const/main.sa", "504\n");
    try assertJsMatrixStdout("demos/rosetta/505_macro_chain_float/main.sa", "505\n");
    try assertJsMatrixStdout("demos/rosetta/506_rep_fadd_accum/main.sa", "506\n");
    try assertJsMatrixStdout("demos/rosetta/507_macro_fcmp_guard/main.sa", "507\n");
    try assertJsMatrixStdout("demos/rosetta/508_macro_double_twice/main.sa", "508\n");
    try assertJsMatrixStdout("demos/rosetta/509_macro_f32_conv/main.sa", "509\n");
    try assertJsMatrixStdout("demos/rosetta/510_macro_branchy_float/main.sa", "510\n");
    try assertJsMatrixStdout("demos/rosetta/511_macro_mem_float/main.sa", "511\n");
    try assertJsMatrixStdout("demos/rosetta/512_chain3_int/main.sa", "512\n");
    try assertJsMatrixStdout("demos/rosetta/513_diamond_fallible/main.sa", "513\n");
    try assertJsMatrixStdout("demos/rosetta/514_barrel_fallible/main.sa", "514\n");
    try assertJsMatrixStdout("demos/rosetta/515_branchy_fallible/main.sa", "515\n");
    try assertJsMatrixStdout("demos/rosetta/516_loop_fallible/main.sa", "516\n");
    try assertJsMatrixStdout("demos/rosetta/517_code_map/main.sa", "517\n");
    try assertJsMatrixStdout("demos/rosetta/518_nested3_fallible/main.sa", "518\n");
    try assertJsMatrixStdout("demos/rosetta/519_vtable_fallible_split/main.sa", "519\n");
    try assertJsMatrixStdout("demos/rosetta/520_mem_fallible_split/main.sa", "520\n");
    try assertJsMatrixStdout("demos/rosetta/521_callback_fallible_split/main.sa", "521\n");
    try assertJsMatrixStdout("demos/rosetta/522_codeval_encode/main.sa", "522\n");
    try assertJsMatrixStdout("demos/rosetta/523_codeval_error/main.sa", "523\n");
    try assertJsMatrixStdout("demos/rosetta/524_codeval_chain3/main.sa", "524\n");
    try assertJsMatrixStdout("demos/rosetta/525_range_guard_code/main.sa", "525\n");
    try assertJsMatrixStdout("demos/rosetta/526_loop_code_check/main.sa", "526\n");
    try assertJsMatrixStdout("demos/rosetta/527_f32_codeval/main.sa", "527\n");
    try assertJsMatrixStdout("demos/rosetta/528_cmp_codes/main.sa", "528\n");
    try assertJsMatrixStdout("demos/rosetta/529_precision_code/main.sa", "529\n");
    try assertJsMatrixStdout("demos/rosetta/530_vtable_codeval/main.sa", "530\n");
    try assertJsMatrixStdout("demos/rosetta/531_branchy_codeval/main.sa", "531\n");
    try assertJsMatrixStdout("demos/rosetta/532_chain3_codeval/main.sa", "532\n");
    try assertJsMatrixStdout("demos/rosetta/533_diamond_codeval/main.sa", "533\n");
    try assertJsMatrixStdout("demos/rosetta/534_barrel_codeval/main.sa", "534\n");
    try assertJsMatrixStdout("demos/rosetta/535_branchy_int_code/main.sa", "535\n");
    try assertJsMatrixStdout("demos/rosetta/536_loop_accum_code/main.sa", "536\n");
    try assertJsMatrixStdout("demos/rosetta/537_struct_codeval/main.sa", "537\n");
    try assertJsMatrixStdout("demos/rosetta/538_vtable_pair_code/main.sa", "538\n");
    try assertJsMatrixStdout("demos/rosetta/539_callback_codeval/main.sa", "539\n");
    try assertJsMatrixStdout("demos/rosetta/540_mem_spill_codeval/main.sa", "540\n");
    try assertJsMatrixStdout("demos/rosetta/541_fallible_codeval/main.sa", "541\n");
    try assertJsMatrixStdout("demos/rosetta/542_int_add_code/main.sa", "542\n");
    try assertJsMatrixStdout("demos/rosetta/543_int_mul_code/main.sa", "543\n");
    try assertJsMatrixStdout("demos/rosetta/544_fcmp_lt_code/main.sa", "544\n");
    try assertJsMatrixStdout("demos/rosetta/545_fcmp_gt_code/main.sa", "545\n");
    try assertJsMatrixStdout("demos/rosetta/546_struct_triple_code/main.sa", "546\n");
    try assertJsMatrixStdout("demos/rosetta/547_loop_sum_code/main.sa", "547\n");
    try assertJsMatrixStdout("demos/rosetta/548_vtable_store_code/main.sa", "548\n");
    try assertJsMatrixStdout("demos/rosetta/549_callback_add_code/main.sa", "549\n");
    try assertJsMatrixStdout("demos/rosetta/550_mem_pair_code/main.sa", "550\n");
    try assertJsMatrixStdout("demos/rosetta/551_branchy_fallible_code/main.sa", "551\n");
    try assertJsMatrixStdout("demos/support/sort_probe.sa", "sort ok\n");
    try assertJsMatrixStdout("demos/support/hashmap_probe.sa", "alpha\nbravo\nmap ok\n");
    try assertJsMatrixStdout("demos/support/hashset_probe.sa", "set ok\n");
    try assertJsMatrixStdout("demos/support/once_probe.sa", "once ok\n");
    try assertJsMatrixStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

fn assertJsBuildRejects(path: []const u8) !void {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_js_argv = [_][]const u8{ "sa", "build-js", source_path, "-o", "rejected.mjs", "--project-root", repo_root };
    const build_js_code = saasm.cli.execute(std.testing.allocator, build_js_argv[0..]) catch |err| {
        // A hard CLI error also counts as a rejection.
        std.debug.print("[js-negative] rejected via error: {s}: {s}\n", .{ path, @errorName(err) });
        return;
    };
    std.debug.print("[js-negative] demo={s} exit={}\n", .{ path, build_js_code });
    try std.testing.expect(build_js_code != 0);
}

test "js backend rejects intentional-fail demos like the native backend" {
    // Mirrors the native negative coverage in cli_smoke.zig
    // ("package and module roadmap demos are rejected ..."): the JS backend
    // must trap these instead of emitting runnable modules.
    try assertJsBuildRejects("demos/rosetta/205_pkg_cyclic_dependency_reject/main.sa");
    try assertJsBuildRejects("demos/rosetta/207_pkg_multiple_versions_conflict/main.sa");
    try assertJsBuildRejects("demos/rosetta/226_mod_cyclic_import_detect/main.sa");
    try assertJsBuildRejects("demos/rosetta/227_mod_shadowing_prevention/main.sa");
    try assertJsBuildRejects("demos/rosetta/243_contract_sig_mismatch_link/main.sa");
    try assertJsBuildRejects("demos/rosetta/502_bare_crossdir_import_reject/main.sa");
}

fn assertJsRuntimeTrap(path: []const u8, expected_stderr_substr: []const u8) !void {
    // Counterpart of assertJsMatrixStdout for programs that must BUILD
    // cleanly but TRAP at runtime: node must exit nonzero and carry the
    // diagnostic on stderr. Probes live in demos/support (never rosetta,
    // so the native/wasm matrices that expect exit 0 stay untouched).
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

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const build_js_argv = [_][]const u8{ "sa", "build-js", source_path, "-o", "trap.mjs", "--project-root", repo_root };
    const build_js_code = saasm.cli.execute(std.testing.allocator, build_js_argv[0..]) catch |err| {
        std.debug.print("build-js errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    try std.testing.expectEqual(@as(u8, 0), build_js_code);

    const js_result = try runJsWithNode(std.testing.allocator, "trap.mjs");
    defer std.testing.allocator.free(js_result.stdout);
    defer std.testing.allocator.free(js_result.stderr);
    switch (js_result.term) {
        .Exited => |code| {
            std.debug.print("[js-trap] demo={s} exit={} stderr={s}\n", .{ path, code, js_result.stderr });
            try std.testing.expect(code != 0);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.indexOf(u8, js_result.stderr, expected_stderr_substr) != null);
}

test "js backend runtime traps surface through node with diagnostics" {
    try assertJsRuntimeTrap("demos/support/panic_code.sa", "[sa-panic] code=99");
    try assertJsRuntimeTrap("demos/support/panic_msg_probe.sa", "panic_msg");
}

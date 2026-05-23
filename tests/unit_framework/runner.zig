const std = @import("std");

const saasm = @import("saasm");

fn expectContains(text: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, text, needle) != null);
}

fn expectNotContains(text: []const u8, needle: []const u8) !void {
    try std.testing.expect(std.mem.indexOf(u8, text, needle) == null);
}

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

test "native unit framework suite covers the demo-derived feature matrix" {
    const suite_path = try std.fs.cwd().realpathAlloc(std.testing.allocator, "tests/unit_framework/feature_suite.sa");
    defer std.testing.allocator.free(suite_path);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const default_argv = [_][]const u8{ "sa", "test", suite_path, "--jobs", "1" };
    const default_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        default_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    if (default_code != 0) {
        std.debug.print("stdout: {s}\n", .{stdout_buffer.items});
        std.debug.print("stderr: {s}\n", .{stderr_buffer.items});
    }
    try std.testing.expectEqual(@as(u8, 0), default_code);
    try expectContains(stdout_buffer.items, "[PASS] 03_if_else branch path");
    try expectContains(stdout_buffer.items, "[PASS] 04_loop zero fill");
    try expectContains(stdout_buffer.items, "[PASS] 05_struct field layout");
    try expectContains(stdout_buffer.items, "[PASS] 06_enum_and_match tag dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 07_trait_vtable dynamic dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 08_closures captured environment");
    try expectContains(stdout_buffer.items, "[PASS] 10_generics_monomorph option unwrap_or");
    try expectContains(stdout_buffer.items, "[PASS] 11_tuples field access");
    try expectContains(stdout_buffer.items, "[PASS] 12_destructuring pair sum");
    try expectContains(stdout_buffer.items, "[PASS] 13_array_sum fixed array");
    try expectContains(stdout_buffer.items, "[PASS] 14_slice_window pointer window");
    try expectContains(stdout_buffer.items, "[PASS] 17_associated_fn constructor");
    try expectContains(stdout_buffer.items, "[PASS] 18_option_map map_or");
    try expectContains(stdout_buffer.items, "[PASS] 21_while_loop sum to fifteen");
    try expectContains(stdout_buffer.items, "[PASS] 24_factorial recursion");
    try expectContains(stdout_buffer.items, "[PASS] 25_fibonacci recursion");
    try expectContains(stdout_buffer.items, "[PASS] 28_borrow_chains repeated load");
    try expectContains(stdout_buffer.items, "[PASS] 30_manual_guard_branch option guard");
    try expectContains(stdout_buffer.items, "[PASS] 33_iterator_map arithmetic map");
    try expectContains(stdout_buffer.items, "[PASS] 34_iterator_filter selected sum");
    try expectContains(stdout_buffer.items, "[PASS] 35_iterator_fold slice fold");
    try expectContains(stdout_buffer.items, "[PASS] 37_newtype field load");
    try expectContains(stdout_buffer.items, "[PASS] 38_generic_struct_i32 wrapper");
    try expectContains(stdout_buffer.items, "[PASS] 39_generic_enum_i32 value branch");
    try expectContains(stdout_buffer.items, "[PASS] 40_impl_block_state deposit");
    try expectContains(stdout_buffer.items, "[PASS] 41_module_imports helper import");
    try expectContains(stdout_buffer.items, "[PASS] 42_export_visibility function pair");
    try expectContains(stdout_buffer.items, "[PASS] 45_config_merge override selection");
    try expectContains(stdout_buffer.items, "[PASS] 46_option_default fallback");
    try expectContains(stdout_buffer.items, "[PASS] 48_generic_pair sum");
    try expectContains(stdout_buffer.items, "[PASS] 53_cache_hits lookup");
    try expectContains(stdout_buffer.items, "[PASS] 54_mem_fill set bytes");
    try expectContains(stdout_buffer.items, "[PASS] 56_state_machine advance");
    try expectContains(stdout_buffer.items, "[PASS] 59_method_counter mut borrow");
    try expectContains(stdout_buffer.items, "[PASS] 60_enum_branch tag dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 63_router_table lookup");
    try expectContains(stdout_buffer.items, "[PASS] 68_parser_tokens count");
    try expectContains(stdout_buffer.items, "[PASS] 69_serializer id builder");
    try expectContains(stdout_buffer.items, "[PASS] 70_integration_service total");
    try expectContains(stdout_buffer.items, "[PASS] 71_pipeline_stage flow");
    try expectContains(stdout_buffer.items, "[PASS] 72_graph_walk total");
    try expectContains(stdout_buffer.items, "[PASS] 73_scene_nodes sum");
    try expectContains(stdout_buffer.items, "[PASS] 74_component_store count");
    try expectContains(stdout_buffer.items, "[PASS] 79_metrics collect");
    try expectContains(stdout_buffer.items, "[PASS] 80_workflow flow");
    try expectContains(stdout_buffer.items, "[PASS] 82_sql_scan rows");
    try expectContains(stdout_buffer.items, "[PASS] 83_blob_chunk count");
    try expectContains(stdout_buffer.items, "[PASS] 84_sync_gate ready");
    try expectContains(stdout_buffer.items, "[PASS] 85_scheduler_tree sum");
    try expectContains(stdout_buffer.items, "[PASS] 87_protocol_frame decode");
    try expectContains(stdout_buffer.items, "[PASS] 88_text_index words");
    try expectContains(stdout_buffer.items, "[PASS] 89_job_queue take jobs");
    try expectContains(stdout_buffer.items, "[PASS] 90_app_shell mode sum");
    try expectContains(stdout_buffer.items, "[PASS] 91_db_session open");
    try expectContains(stdout_buffer.items, "[PASS] 92_query_plan total");
    try expectContains(stdout_buffer.items, "[PASS] 93_log_aggregator total");
    try expectContains(stdout_buffer.items, "[PASS] 96_task_orchestrator total");
    try expectContains(stdout_buffer.items, "[PASS] 97_sync_service once");
    try expectContains(stdout_buffer.items, "[PASS] 98_build_pipeline stage");
    try expectContains(stdout_buffer.items, "[PASS] 99_release_bundle count");
    try expectContains(stdout_buffer.items, "[PASS] 100_full_app total");
    try expectContains(stdout_buffer.items, "[PASS] 101_custom_drop order");
    try expectContains(stdout_buffer.items, "[PASS] 102_raii_guard unlock");
    try expectContains(stdout_buffer.items, "[PASS] 103_labeled_break total");
    try expectContains(stdout_buffer.items, "[PASS] 104_if_let_chains sum");
    try expectContains(stdout_buffer.items, "[PASS] 105_let_else value");
    try expectContains(stdout_buffer.items, "[PASS] 106_cell_interior_mut total");
    try expectContains(stdout_buffer.items, "[PASS] 107_refcell_dynamic_borrow values");
    try expectContains(stdout_buffer.items, "[PASS] 108_atomic_spin_lock acquire");
    try expectContains(stdout_buffer.items, "[PASS] 109_atomic_fetch_add total");
    try expectContains(stdout_buffer.items, "[PASS] 110_trait_super_vtable dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 111_extern_c_abi exported add");
    try expectContains(stdout_buffer.items, "[PASS] 112_raw_pointer_arithmetic third lane");
    try expectContains(stdout_buffer.items, "[PASS] 113_union_ffi_types overlap");
    try expectContains(stdout_buffer.items, "[PASS] 114_callback_from_c indirect");
    try expectContains(stdout_buffer.items, "[PASS] 115_opaque_pointers value");
    try expectContains(stdout_buffer.items, "[PASS] 116_va_list_variadic slice sum");
    try expectContains(stdout_buffer.items, "[PASS] 118_global_mutable_state counter");
    try expectContains(stdout_buffer.items, "[PASS] 119_simd_intrinsics lane sum");
    try expectContains(stdout_buffer.items, "[PASS] 120_volatile_memory_access load");
    try expectContains(stdout_buffer.items, "[PASS] 121_rwlock_reader_writer total");
    try expectContains(stdout_buffer.items, "[PASS] 122_condvar_wait_notify ready");
    try expectContains(stdout_buffer.items, "[PASS] 123_barrier_sync total");
    try expectContains(stdout_buffer.items, "[PASS] 124_thread_local_storage value");
    try expectContains(stdout_buffer.items, "[PASS] 125_once_cell_lazy init");
    try expectContains(stdout_buffer.items, "[PASS] 126_mpmc_channel sum");
    try expectContains(stdout_buffer.items, "[PASS] 127_hazard_pointers retire");
    try expectContains(stdout_buffer.items, "[PASS] 128_rcu_read_copy_update value");
    try expectContains(stdout_buffer.items, "[PASS] 129_seqlock_optimistic stable");
    try expectContains(stdout_buffer.items, "[PASS] 130_park_unpark_thread wake");
    try expectContains(stdout_buffer.items, "[PASS] 131_waker_vtable_mechanics wake");
    try expectContains(stdout_buffer.items, "[PASS] 132_pinning_and_unpin value");
    try expectContains(stdout_buffer.items, "[PASS] 133_select_macro_race winner");
    try expectContains(stdout_buffer.items, "[PASS] 134_join_all_futures sum");
    try expectContains(stdout_buffer.items, "[PASS] 135_async_streams sequence");
    try expectContains(stdout_buffer.items, "[PASS] 136_executor_task_queue run");
    try expectContains(stdout_buffer.items, "[PASS] 137_io_uring_submission depth");
    try expectContains(stdout_buffer.items, "[PASS] 138_epoll_kqueue_event ready");
    try expectContains(stdout_buffer.items, "[PASS] 139_cancellation_safety value");
    try expectContains(stdout_buffer.items, "[PASS] 140_yield_now_suspend resume");
    try expectContains(stdout_buffer.items, "[PASS] 141_dynamically_sized_types len");
    try expectContains(stdout_buffer.items, "[PASS] 142_zero_sized_types erased");
    try expectContains(stdout_buffer.items, "[PASS] 143_never_type_diverge safe path");
    try expectContains(stdout_buffer.items, "[PASS] 144_phantom_data_marker value");
    try expectContains(stdout_buffer.items, "[PASS] 145_opaque_type_alias value");
    try expectContains(stdout_buffer.items, "[PASS] 146_never_type_fallback some");
    try expectContains(stdout_buffer.items, "[PASS] 147_custom_dst_pointers len");
    try expectContains(stdout_buffer.items, "[PASS] 148_transparent_repr value");
    try expectContains(stdout_buffer.items, "[PASS] 149_packed_repr sum");
    try expectContains(stdout_buffer.items, "[PASS] 150_c_repr_alignment sum");
    try expectContains(stdout_buffer.items, "[PASS] 151_global_alloc_trait value");
    try expectContains(stdout_buffer.items, "[PASS] 152_memory_layout_struct total");
    try expectContains(stdout_buffer.items, "[PASS] 153_box_into_raw value");
    try expectContains(stdout_buffer.items, "[PASS] 154_box_from_raw value");
    try expectContains(stdout_buffer.items, "[PASS] 155_arena_allocator_bump total");
    try expectContains(stdout_buffer.items, "[PASS] 156_slab_allocator_freelist total");
    try expectContains(stdout_buffer.items, "[PASS] 157_aligned_alloc_simd lanes");
    try expectContains(stdout_buffer.items, "[PASS] 158_custom_dst_alloc len");
    try expectContains(stdout_buffer.items, "[PASS] 159_mem_forget_leak raw handoff");
    try expectContains(stdout_buffer.items, "[PASS] 160_manually_drop_union value");
    try expectContains(stdout_buffer.items, "[PASS] 161_generic_associated_types borrowed get");
    try expectContains(stdout_buffer.items, "[PASS] 162_auto_traits_send_sync move");
    try expectContains(stdout_buffer.items, "[PASS] 163_object_safety_rules draw");
    try expectContains(stdout_buffer.items, "[PASS] 164_trait_upcasting vtable total");
    try expectContains(stdout_buffer.items, "[PASS] 165_blanket_impl_resolution len");
    try expectContains(stdout_buffer.items, "[PASS] 166_specialization_fallback dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 167_const_generics_expansion sum");
    try expectContains(stdout_buffer.items, "[PASS] 168_type_alias_impl_trait erased");
    try expectContains(stdout_buffer.items, "[PASS] 169_negative_impls no runtime cost");
    try expectContains(stdout_buffer.items, "[PASS] 170_marker_traits process");
    try expectContains(stdout_buffer.items, "[PASS] 171_anyhow_dynamic_error default");
    try expectContains(stdout_buffer.items, "[PASS] 172_eyre_color_eyre context");
    try expectContains(stdout_buffer.items, "[PASS] 173_catch_unwind_panic explicit result");
    try expectContains(stdout_buffer.items, "[PASS] 174_backtrace_capture depth");
    try expectContains(stdout_buffer.items, "[PASS] 175_thiserror_macro_derive format");
    try expectContains(stdout_buffer.items, "[PASS] 176_result_flattening value");
    try expectContains(stdout_buffer.items, "[PASS] 177_result unwrap and unwrap_err");
    try expectContains(stdout_buffer.items, "[PASS] 178_panic_hook_override count");
    try expectContains(stdout_buffer.items, "[PASS] 179_assert_macro_expansion pass");
    try expectContains(stdout_buffer.items, "[PASS] 180_try_trait_v2 combine");
    try expectContains(stdout_buffer.items, "[PASS] 181_file_descriptor_raii close");
    try expectContains(stdout_buffer.items, "[PASS] 182_mmap_memory_mapping lifecycle");
    try expectContains(stdout_buffer.items, "[PASS] 183_signal_handling_setup register");
    try expectContains(stdout_buffer.items, "[PASS] 184_pthread_spawn_join worker");
    try expectContains(stdout_buffer.items, "[PASS] 185_dynamic_lib_dlopen handles");
    try expectContains(stdout_buffer.items, "[PASS] 186_sqlite_c_api_binding row");
    try expectContains(stdout_buffer.items, "[PASS] 187_opengl_context_swap state");
    try expectContains(stdout_buffer.items, "[PASS] 188_websocket_frame_parse text");
    try expectContains(stdout_buffer.items, "[PASS] 189_protobuf_varint_decode value");
    try expectContains(stdout_buffer.items, "[PASS] 190_base64_encode_simd block");
    try expectContains(stdout_buffer.items, "[PASS] 191_macro_rules_ast_emit mirror");
    try expectContains(stdout_buffer.items, "[PASS] 192_proc_macro_derive_ast copy");
    try expectContains(stdout_buffer.items, "[PASS] 193_attribute_macro_rewrite value");
    try expectContains(stdout_buffer.items, "[PASS] 194_cfg_conditional_compilation arch");
    try expectContains(stdout_buffer.items, "[PASS] 195_build_script_codegen output");
    try expectContains(stdout_buffer.items, "[PASS] 196_lto_link_time_opt total");
    try expectContains(stdout_buffer.items, "[PASS] 197_profile_guided_opt total");
    try expectContains(stdout_buffer.items, "[PASS] 198_control_flow_guard_cfi indirect");
    try expectContains(stdout_buffer.items, "[PASS] 199_address_sanitizer_asan safe sum");
    try expectContains(stdout_buffer.items, "[PASS] 200_sa_asm_quine source");
    try expectContains(stdout_buffer.items, "[PASS] 201_pkg_manifest_basic value");
    try expectContains(stdout_buffer.items, "[PASS] 202_pkg_dependencies_local value");
    try expectContains(stdout_buffer.items, "[PASS] 203_pkg_dependencies_git value");
    try expectContains(stdout_buffer.items, "[PASS] 204_pkg_dependencies_registry value");
    try expectContains(stdout_buffer.items, "[PASS] 205_pkg_cyclic_dependency_reject diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 206_pkg_version_resolution value");
    try expectContains(stdout_buffer.items, "[PASS] 207_pkg_multiple_versions_conflict diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 208_pkg_dev_dependencies value");
    try expectContains(stdout_buffer.items, "[PASS] 209_pkg_build_dependencies value");
    try expectContains(stdout_buffer.items, "[PASS] 210_pkg_workspace_root total");
    try expectContains(stdout_buffer.items, "[PASS] 211_pkg_workspace_inheritance total");
    try expectContains(stdout_buffer.items, "[PASS] 212_pkg_feature_flags value");
    try expectContains(stdout_buffer.items, "[PASS] 213_pkg_default_features value");
    try expectContains(stdout_buffer.items, "[PASS] 214_pkg_target_specific_deps value");
    try expectContains(stdout_buffer.items, "[PASS] 215_pkg_patch_override value");
    try expectContains(stdout_buffer.items, "[PASS] 216_pkg_profile_release value");
    try expectContains(stdout_buffer.items, "[PASS] 217_pkg_profile_debug value");
    try expectContains(stdout_buffer.items, "[PASS] 218_pkg_metadata_custom value");
    try expectContains(stdout_buffer.items, "[PASS] 219_pkg_bin_multiple total");
    try expectContains(stdout_buffer.items, "[PASS] 220_pkg_lib_dynamic total");
    try expectContains(stdout_buffer.items, "[PASS] 221_mod_relative_import value");
    try expectContains(stdout_buffer.items, "[PASS] 222_mod_absolute_import value");
    try expectContains(stdout_buffer.items, "[PASS] 223_mod_visibility_private value");
    try expectContains(stdout_buffer.items, "[PASS] 224_mod_reexport_pub_use value");
    try expectContains(stdout_buffer.items, "[PASS] 225_mod_namespace_prefix value");
    try expectContains(stdout_buffer.items, "[PASS] 226_mod_cyclic_import_detect diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 227_mod_shadowing_prevention diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 228_mod_iface_separation value");
    try expectContains(stdout_buffer.items, "[PASS] 229_mod_layout_injection value");
    try expectContains(stdout_buffer.items, "[PASS] 230_mod_std_prelude value");
    try expectContains(stdout_buffer.items, "[PASS] 231_mod_directory_module value");
    try expectContains(stdout_buffer.items, "[PASS] 232_mod_conditional_import value");
    try expectContains(stdout_buffer.items, "[PASS] 233_mod_alias_import value");
    try expectContains(stdout_buffer.items, "[PASS] 234_mod_unused_import_lint value");
    try expectContains(stdout_buffer.items, "[PASS] 235_mod_transitive_dependency value");
    try expectContains(stdout_buffer.items, "[PASS] 236_mod_extern_block_grouping value");
    try expectContains(stdout_buffer.items, "[PASS] 237_mod_inline_submodule value");
    try expectContains(stdout_buffer.items, "[PASS] 238_mod_path_resolution_order value");
    try expectContains(stdout_buffer.items, "[PASS] 239_mod_version_suffix_isolation value");
    try expectContains(stdout_buffer.items, "[PASS] 240_mod_entry_point_override value");
    try expectContains(stdout_buffer.items, "[PASS] 241_contract_layout_stability value");
    try expectContains(stdout_buffer.items, "[PASS] 242_contract_opaque_struct value");
    try expectContains(stdout_buffer.items, "[PASS] 243_contract_sig_mismatch_link diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 244_contract_vtable_export value");
    try expectContains(stdout_buffer.items, "[PASS] 245_contract_generic_monomorph_share value");
    try expectContains(stdout_buffer.items, "[PASS] 246_contract_semver_minor_update value");
    try expectContains(stdout_buffer.items, "[PASS] 247_contract_semver_major_break value");
    try expectContains(stdout_buffer.items, "[PASS] 248_contract_ffi_boundary_trust value");
    try expectContains(stdout_buffer.items, "[PASS] 249_contract_macro_export value");
    try expectContains(stdout_buffer.items, "[PASS] 250_contract_const_export value");
    try expectContains(stdout_buffer.items, "[PASS] 251_contract_resource_ownership value");
    try expectContains(stdout_buffer.items, "[PASS] 252_contract_error_code_mapping value");
    try expectContains(stdout_buffer.items, "[PASS] 253_contract_callback_registration value");
    try expectContains(stdout_buffer.items, "[PASS] 254_contract_plugin_system value");
    try expectContains(stdout_buffer.items, "[PASS] 255_contract_memory_allocator_swap value");
    try expectContains(stdout_buffer.items, "[PASS] 256_contract_panic_handler_propagate value");
    try expectContains(stdout_buffer.items, "[PASS] 257_contract_log_facade value");
    try expectContains(stdout_buffer.items, "[PASS] 258_contract_thread_local_isolation value");
    try expectContains(stdout_buffer.items, "[PASS] 259_contract_static_init_order value");
    try expectContains(stdout_buffer.items, "[PASS] 260_contract_deprecated_warning value");
    try expectContains(stdout_buffer.items, "[PASS] 261_build_rs_codegen_saasm value");
    try expectContains(stdout_buffer.items, "[PASS] 262_build_bindgen_c_header value");
    try expectContains(stdout_buffer.items, "[PASS] 263_build_asset_bundling value");
    try expectContains(stdout_buffer.items, "[PASS] 264_build_env_var_injection value");
    try expectContains(stdout_buffer.items, "[PASS] 265_build_custom_linker_script value");
    try expectContains(stdout_buffer.items, "[PASS] 266_build_pre_compile_hook value");
    try expectContains(stdout_buffer.items, "[PASS] 267_build_post_compile_hook value");
    try expectContains(stdout_buffer.items, "[PASS] 268_build_cross_compile_wasm value");
    try expectContains(stdout_buffer.items, "[PASS] 269_build_cross_compile_windows value");
    try expectContains(stdout_buffer.items, "[PASS] 270_build_sysroot_custom value");
    try expectContains(stdout_buffer.items, "[PASS] 271_build_optimization_passes value");
    try expectContains(stdout_buffer.items, "[PASS] 272_build_sanitizer_flags value");
    try expectContains(stdout_buffer.items, "[PASS] 273_build_test_harness value");
    try expectContains(stdout_buffer.items, "[PASS] 274_build_benchmark_runner value");
    try expectContains(stdout_buffer.items, "[PASS] 275_build_doc_generator value");
    try expectContains(stdout_buffer.items, "[PASS] 276_build_incremental_caching value");
    try expectContains(stdout_buffer.items, "[PASS] 277_build_parallel_compilation value");
    try expectContains(stdout_buffer.items, "[PASS] 278_build_reproducible_builds value");
    try expectContains(stdout_buffer.items, "[PASS] 279_build_artifact_caching_remote value");
    try expectContains(stdout_buffer.items, "[PASS] 280_build_ci_cd_integration value");
    try expectContains(stdout_buffer.items, "[PASS] 281_ffi_link_system_libc gate");
    try expectContains(stdout_buffer.items, "[PASS] 282_ffi_link_static_c_lib gate");
    try expectContains(stdout_buffer.items, "[PASS] 283_ffi_link_dynamic_c_lib gate");
    try expectContains(stdout_buffer.items, "[PASS] 284_ffi_pkg_config_integration gate");
    try expectContains(stdout_buffer.items, "[PASS] 285_ffi_objective_c_framework gate");
    try expectContains(stdout_buffer.items, "[PASS] 286_ffi_rust_staticlib_integration gate");
    try expectContains(stdout_buffer.items, "[PASS] 287_ffi_zig_export_integration export");
    try expectContains(stdout_buffer.items, "[PASS] 288_ffi_cxx_name_mangling gate");
    try expectContains(stdout_buffer.items, "[PASS] 289_ffi_opaque_handle_passing gate");
    try expectContains(stdout_buffer.items, "[PASS] 290_ffi_callback_thunk vtable");
    try expectContains(stdout_buffer.items, "[PASS] 291_eco_wasm_host_imports guest");
    try expectContains(stdout_buffer.items, "[PASS] 292_eco_wasm_memory_export memory");
    try expectContains(stdout_buffer.items, "[PASS] 293_eco_embedded_no_os startup");
    try expectContains(stdout_buffer.items, "[PASS] 294_eco_os_kernel_module entry");
    try expectContains(stdout_buffer.items, "[PASS] 295_eco_bpf_ebpf_bytecode program");
    try expectContains(stdout_buffer.items, "[PASS] 296_eco_gpu_ptx_shader shader");
    try expectContains(stdout_buffer.items, "[PASS] 297_eco_game_engine_ecs step");
    try expectContains(stdout_buffer.items, "[PASS] 298_eco_cryptography_simd hash");
    try expectContains(stdout_buffer.items, "[PASS] 299_eco_language_server_protocol server");
    try expectContains(stdout_buffer.items, "[PASS] 300_eco_sa_lang_registry_publish publish");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json dom roundtrip");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json stream tokens");
    try expectContains(stdout_buffer.items, "[PASS] sa_std regex groups");
    try expectContains(stdout_buffer.items, "[PASS] 178 panic hook path");
    try expectNotContains(stdout_buffer.items, "[PASS] framework ignored case");
    try expectContains(stdout_buffer.items, "test result: ok. 270 passed; 0 failed; 0 skipped; 1 ignored");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const ignored_argv = [_][]const u8{ "sa", "test", suite_path, "--jobs", "1", "--ignored" };
    const ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        ignored_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), ignored_code);
    try expectContains(stdout_buffer.items, "[PASS] framework ignored case");
    try expectNotContains(stdout_buffer.items, "[PASS] 03_if_else branch path");
    try expectContains(stdout_buffer.items, "test result: ok. 1 passed; 0 failed; 270 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const include_ignored_argv = [_][]const u8{ "sa", "test", suite_path, "--jobs", "1", "--include-ignored" };
    const include_ignored_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        include_ignored_argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    try std.testing.expectEqual(@as(u8, 0), include_ignored_code);
    try expectContains(stdout_buffer.items, "[PASS] 03_if_else branch path");
    try expectContains(stdout_buffer.items, "[PASS] 04_loop zero fill");
    try expectContains(stdout_buffer.items, "[PASS] 05_struct field layout");
    try expectContains(stdout_buffer.items, "[PASS] 06_enum_and_match tag dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 07_trait_vtable dynamic dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 08_closures captured environment");
    try expectContains(stdout_buffer.items, "[PASS] 10_generics_monomorph option unwrap_or");
    try expectContains(stdout_buffer.items, "[PASS] 11_tuples field access");
    try expectContains(stdout_buffer.items, "[PASS] 12_destructuring pair sum");
    try expectContains(stdout_buffer.items, "[PASS] 13_array_sum fixed array");
    try expectContains(stdout_buffer.items, "[PASS] 14_slice_window pointer window");
    try expectContains(stdout_buffer.items, "[PASS] 17_associated_fn constructor");
    try expectContains(stdout_buffer.items, "[PASS] 18_option_map map_or");
    try expectContains(stdout_buffer.items, "[PASS] 21_while_loop sum to fifteen");
    try expectContains(stdout_buffer.items, "[PASS] 24_factorial recursion");
    try expectContains(stdout_buffer.items, "[PASS] 25_fibonacci recursion");
    try expectContains(stdout_buffer.items, "[PASS] 28_borrow_chains repeated load");
    try expectContains(stdout_buffer.items, "[PASS] 30_manual_guard_branch option guard");
    try expectContains(stdout_buffer.items, "[PASS] 33_iterator_map arithmetic map");
    try expectContains(stdout_buffer.items, "[PASS] 34_iterator_filter selected sum");
    try expectContains(stdout_buffer.items, "[PASS] 35_iterator_fold slice fold");
    try expectContains(stdout_buffer.items, "[PASS] 37_newtype field load");
    try expectContains(stdout_buffer.items, "[PASS] 38_generic_struct_i32 wrapper");
    try expectContains(stdout_buffer.items, "[PASS] 39_generic_enum_i32 value branch");
    try expectContains(stdout_buffer.items, "[PASS] 40_impl_block_state deposit");
    try expectContains(stdout_buffer.items, "[PASS] 41_module_imports helper import");
    try expectContains(stdout_buffer.items, "[PASS] 42_export_visibility function pair");
    try expectContains(stdout_buffer.items, "[PASS] 45_config_merge override selection");
    try expectContains(stdout_buffer.items, "[PASS] 46_option_default fallback");
    try expectContains(stdout_buffer.items, "[PASS] 48_generic_pair sum");
    try expectContains(stdout_buffer.items, "[PASS] 53_cache_hits lookup");
    try expectContains(stdout_buffer.items, "[PASS] 54_mem_fill set bytes");
    try expectContains(stdout_buffer.items, "[PASS] 56_state_machine advance");
    try expectContains(stdout_buffer.items, "[PASS] 59_method_counter mut borrow");
    try expectContains(stdout_buffer.items, "[PASS] 60_enum_branch tag dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 63_router_table lookup");
    try expectContains(stdout_buffer.items, "[PASS] 68_parser_tokens count");
    try expectContains(stdout_buffer.items, "[PASS] 69_serializer id builder");
    try expectContains(stdout_buffer.items, "[PASS] 70_integration_service total");
    try expectContains(stdout_buffer.items, "[PASS] 71_pipeline_stage flow");
    try expectContains(stdout_buffer.items, "[PASS] 72_graph_walk total");
    try expectContains(stdout_buffer.items, "[PASS] 73_scene_nodes sum");
    try expectContains(stdout_buffer.items, "[PASS] 74_component_store count");
    try expectContains(stdout_buffer.items, "[PASS] 79_metrics collect");
    try expectContains(stdout_buffer.items, "[PASS] 80_workflow flow");
    try expectContains(stdout_buffer.items, "[PASS] 82_sql_scan rows");
    try expectContains(stdout_buffer.items, "[PASS] 83_blob_chunk count");
    try expectContains(stdout_buffer.items, "[PASS] 84_sync_gate ready");
    try expectContains(stdout_buffer.items, "[PASS] 85_scheduler_tree sum");
    try expectContains(stdout_buffer.items, "[PASS] 87_protocol_frame decode");
    try expectContains(stdout_buffer.items, "[PASS] 88_text_index words");
    try expectContains(stdout_buffer.items, "[PASS] 89_job_queue take jobs");
    try expectContains(stdout_buffer.items, "[PASS] 90_app_shell mode sum");
    try expectContains(stdout_buffer.items, "[PASS] 91_db_session open");
    try expectContains(stdout_buffer.items, "[PASS] 92_query_plan total");
    try expectContains(stdout_buffer.items, "[PASS] 93_log_aggregator total");
    try expectContains(stdout_buffer.items, "[PASS] 96_task_orchestrator total");
    try expectContains(stdout_buffer.items, "[PASS] 97_sync_service once");
    try expectContains(stdout_buffer.items, "[PASS] 98_build_pipeline stage");
    try expectContains(stdout_buffer.items, "[PASS] 99_release_bundle count");
    try expectContains(stdout_buffer.items, "[PASS] 100_full_app total");
    try expectContains(stdout_buffer.items, "[PASS] 101_custom_drop order");
    try expectContains(stdout_buffer.items, "[PASS] 102_raii_guard unlock");
    try expectContains(stdout_buffer.items, "[PASS] 103_labeled_break total");
    try expectContains(stdout_buffer.items, "[PASS] 104_if_let_chains sum");
    try expectContains(stdout_buffer.items, "[PASS] 105_let_else value");
    try expectContains(stdout_buffer.items, "[PASS] 106_cell_interior_mut total");
    try expectContains(stdout_buffer.items, "[PASS] 107_refcell_dynamic_borrow values");
    try expectContains(stdout_buffer.items, "[PASS] 108_atomic_spin_lock acquire");
    try expectContains(stdout_buffer.items, "[PASS] 109_atomic_fetch_add total");
    try expectContains(stdout_buffer.items, "[PASS] 110_trait_super_vtable dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 111_extern_c_abi exported add");
    try expectContains(stdout_buffer.items, "[PASS] 112_raw_pointer_arithmetic third lane");
    try expectContains(stdout_buffer.items, "[PASS] 113_union_ffi_types overlap");
    try expectContains(stdout_buffer.items, "[PASS] 114_callback_from_c indirect");
    try expectContains(stdout_buffer.items, "[PASS] 115_opaque_pointers value");
    try expectContains(stdout_buffer.items, "[PASS] 116_va_list_variadic slice sum");
    try expectContains(stdout_buffer.items, "[PASS] 118_global_mutable_state counter");
    try expectContains(stdout_buffer.items, "[PASS] 119_simd_intrinsics lane sum");
    try expectContains(stdout_buffer.items, "[PASS] 120_volatile_memory_access load");
    try expectContains(stdout_buffer.items, "[PASS] 121_rwlock_reader_writer total");
    try expectContains(stdout_buffer.items, "[PASS] 122_condvar_wait_notify ready");
    try expectContains(stdout_buffer.items, "[PASS] 123_barrier_sync total");
    try expectContains(stdout_buffer.items, "[PASS] 124_thread_local_storage value");
    try expectContains(stdout_buffer.items, "[PASS] 125_once_cell_lazy init");
    try expectContains(stdout_buffer.items, "[PASS] 126_mpmc_channel sum");
    try expectContains(stdout_buffer.items, "[PASS] 127_hazard_pointers retire");
    try expectContains(stdout_buffer.items, "[PASS] 128_rcu_read_copy_update value");
    try expectContains(stdout_buffer.items, "[PASS] 129_seqlock_optimistic stable");
    try expectContains(stdout_buffer.items, "[PASS] 130_park_unpark_thread wake");
    try expectContains(stdout_buffer.items, "[PASS] 131_waker_vtable_mechanics wake");
    try expectContains(stdout_buffer.items, "[PASS] 132_pinning_and_unpin value");
    try expectContains(stdout_buffer.items, "[PASS] 133_select_macro_race winner");
    try expectContains(stdout_buffer.items, "[PASS] 134_join_all_futures sum");
    try expectContains(stdout_buffer.items, "[PASS] 135_async_streams sequence");
    try expectContains(stdout_buffer.items, "[PASS] 136_executor_task_queue run");
    try expectContains(stdout_buffer.items, "[PASS] 137_io_uring_submission depth");
    try expectContains(stdout_buffer.items, "[PASS] 138_epoll_kqueue_event ready");
    try expectContains(stdout_buffer.items, "[PASS] 139_cancellation_safety value");
    try expectContains(stdout_buffer.items, "[PASS] 140_yield_now_suspend resume");
    try expectContains(stdout_buffer.items, "[PASS] 141_dynamically_sized_types len");
    try expectContains(stdout_buffer.items, "[PASS] 142_zero_sized_types erased");
    try expectContains(stdout_buffer.items, "[PASS] 143_never_type_diverge safe path");
    try expectContains(stdout_buffer.items, "[PASS] 144_phantom_data_marker value");
    try expectContains(stdout_buffer.items, "[PASS] 145_opaque_type_alias value");
    try expectContains(stdout_buffer.items, "[PASS] 146_never_type_fallback some");
    try expectContains(stdout_buffer.items, "[PASS] 147_custom_dst_pointers len");
    try expectContains(stdout_buffer.items, "[PASS] 148_transparent_repr value");
    try expectContains(stdout_buffer.items, "[PASS] 149_packed_repr sum");
    try expectContains(stdout_buffer.items, "[PASS] 150_c_repr_alignment sum");
    try expectContains(stdout_buffer.items, "[PASS] 151_global_alloc_trait value");
    try expectContains(stdout_buffer.items, "[PASS] 152_memory_layout_struct total");
    try expectContains(stdout_buffer.items, "[PASS] 153_box_into_raw value");
    try expectContains(stdout_buffer.items, "[PASS] 154_box_from_raw value");
    try expectContains(stdout_buffer.items, "[PASS] 155_arena_allocator_bump total");
    try expectContains(stdout_buffer.items, "[PASS] 156_slab_allocator_freelist total");
    try expectContains(stdout_buffer.items, "[PASS] 157_aligned_alloc_simd lanes");
    try expectContains(stdout_buffer.items, "[PASS] 158_custom_dst_alloc len");
    try expectContains(stdout_buffer.items, "[PASS] 159_mem_forget_leak raw handoff");
    try expectContains(stdout_buffer.items, "[PASS] 160_manually_drop_union value");
    try expectContains(stdout_buffer.items, "[PASS] 161_generic_associated_types borrowed get");
    try expectContains(stdout_buffer.items, "[PASS] 162_auto_traits_send_sync move");
    try expectContains(stdout_buffer.items, "[PASS] 163_object_safety_rules draw");
    try expectContains(stdout_buffer.items, "[PASS] 164_trait_upcasting vtable total");
    try expectContains(stdout_buffer.items, "[PASS] 165_blanket_impl_resolution len");
    try expectContains(stdout_buffer.items, "[PASS] 166_specialization_fallback dispatch");
    try expectContains(stdout_buffer.items, "[PASS] 167_const_generics_expansion sum");
    try expectContains(stdout_buffer.items, "[PASS] 168_type_alias_impl_trait erased");
    try expectContains(stdout_buffer.items, "[PASS] 169_negative_impls no runtime cost");
    try expectContains(stdout_buffer.items, "[PASS] 170_marker_traits process");
    try expectContains(stdout_buffer.items, "[PASS] 171_anyhow_dynamic_error default");
    try expectContains(stdout_buffer.items, "[PASS] 172_eyre_color_eyre context");
    try expectContains(stdout_buffer.items, "[PASS] 173_catch_unwind_panic explicit result");
    try expectContains(stdout_buffer.items, "[PASS] 174_backtrace_capture depth");
    try expectContains(stdout_buffer.items, "[PASS] 175_thiserror_macro_derive format");
    try expectContains(stdout_buffer.items, "[PASS] 176_result_flattening value");
    try expectContains(stdout_buffer.items, "[PASS] 177_result unwrap and unwrap_err");
    try expectContains(stdout_buffer.items, "[PASS] 178_panic_hook_override count");
    try expectContains(stdout_buffer.items, "[PASS] 179_assert_macro_expansion pass");
    try expectContains(stdout_buffer.items, "[PASS] 180_try_trait_v2 combine");
    try expectContains(stdout_buffer.items, "[PASS] 181_file_descriptor_raii close");
    try expectContains(stdout_buffer.items, "[PASS] 182_mmap_memory_mapping lifecycle");
    try expectContains(stdout_buffer.items, "[PASS] 183_signal_handling_setup register");
    try expectContains(stdout_buffer.items, "[PASS] 184_pthread_spawn_join worker");
    try expectContains(stdout_buffer.items, "[PASS] 185_dynamic_lib_dlopen handles");
    try expectContains(stdout_buffer.items, "[PASS] 186_sqlite_c_api_binding row");
    try expectContains(stdout_buffer.items, "[PASS] 187_opengl_context_swap state");
    try expectContains(stdout_buffer.items, "[PASS] 188_websocket_frame_parse text");
    try expectContains(stdout_buffer.items, "[PASS] 189_protobuf_varint_decode value");
    try expectContains(stdout_buffer.items, "[PASS] 190_base64_encode_simd block");
    try expectContains(stdout_buffer.items, "[PASS] 191_macro_rules_ast_emit mirror");
    try expectContains(stdout_buffer.items, "[PASS] 192_proc_macro_derive_ast copy");
    try expectContains(stdout_buffer.items, "[PASS] 193_attribute_macro_rewrite value");
    try expectContains(stdout_buffer.items, "[PASS] 194_cfg_conditional_compilation arch");
    try expectContains(stdout_buffer.items, "[PASS] 195_build_script_codegen output");
    try expectContains(stdout_buffer.items, "[PASS] 196_lto_link_time_opt total");
    try expectContains(stdout_buffer.items, "[PASS] 197_profile_guided_opt total");
    try expectContains(stdout_buffer.items, "[PASS] 198_control_flow_guard_cfi indirect");
    try expectContains(stdout_buffer.items, "[PASS] 199_address_sanitizer_asan safe sum");
    try expectContains(stdout_buffer.items, "[PASS] 200_sa_asm_quine source");
    try expectContains(stdout_buffer.items, "[PASS] 201_pkg_manifest_basic value");
    try expectContains(stdout_buffer.items, "[PASS] 202_pkg_dependencies_local value");
    try expectContains(stdout_buffer.items, "[PASS] 203_pkg_dependencies_git value");
    try expectContains(stdout_buffer.items, "[PASS] 204_pkg_dependencies_registry value");
    try expectContains(stdout_buffer.items, "[PASS] 205_pkg_cyclic_dependency_reject diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 206_pkg_version_resolution value");
    try expectContains(stdout_buffer.items, "[PASS] 207_pkg_multiple_versions_conflict diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 208_pkg_dev_dependencies value");
    try expectContains(stdout_buffer.items, "[PASS] 209_pkg_build_dependencies value");
    try expectContains(stdout_buffer.items, "[PASS] 210_pkg_workspace_root total");
    try expectContains(stdout_buffer.items, "[PASS] 211_pkg_workspace_inheritance total");
    try expectContains(stdout_buffer.items, "[PASS] 212_pkg_feature_flags value");
    try expectContains(stdout_buffer.items, "[PASS] 213_pkg_default_features value");
    try expectContains(stdout_buffer.items, "[PASS] 214_pkg_target_specific_deps value");
    try expectContains(stdout_buffer.items, "[PASS] 215_pkg_patch_override value");
    try expectContains(stdout_buffer.items, "[PASS] 216_pkg_profile_release value");
    try expectContains(stdout_buffer.items, "[PASS] 217_pkg_profile_debug value");
    try expectContains(stdout_buffer.items, "[PASS] 218_pkg_metadata_custom value");
    try expectContains(stdout_buffer.items, "[PASS] 219_pkg_bin_multiple total");
    try expectContains(stdout_buffer.items, "[PASS] 220_pkg_lib_dynamic total");
    try expectContains(stdout_buffer.items, "[PASS] 221_mod_relative_import value");
    try expectContains(stdout_buffer.items, "[PASS] 222_mod_absolute_import value");
    try expectContains(stdout_buffer.items, "[PASS] 223_mod_visibility_private value");
    try expectContains(stdout_buffer.items, "[PASS] 224_mod_reexport_pub_use value");
    try expectContains(stdout_buffer.items, "[PASS] 225_mod_namespace_prefix value");
    try expectContains(stdout_buffer.items, "[PASS] 226_mod_cyclic_import_detect diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 227_mod_shadowing_prevention diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 228_mod_iface_separation value");
    try expectContains(stdout_buffer.items, "[PASS] 229_mod_layout_injection value");
    try expectContains(stdout_buffer.items, "[PASS] 230_mod_std_prelude value");
    try expectContains(stdout_buffer.items, "[PASS] 231_mod_directory_module value");
    try expectContains(stdout_buffer.items, "[PASS] 232_mod_conditional_import value");
    try expectContains(stdout_buffer.items, "[PASS] 233_mod_alias_import value");
    try expectContains(stdout_buffer.items, "[PASS] 234_mod_unused_import_lint value");
    try expectContains(stdout_buffer.items, "[PASS] 235_mod_transitive_dependency value");
    try expectContains(stdout_buffer.items, "[PASS] 236_mod_extern_block_grouping value");
    try expectContains(stdout_buffer.items, "[PASS] 237_mod_inline_submodule value");
    try expectContains(stdout_buffer.items, "[PASS] 238_mod_path_resolution_order value");
    try expectContains(stdout_buffer.items, "[PASS] 239_mod_version_suffix_isolation value");
    try expectContains(stdout_buffer.items, "[PASS] 240_mod_entry_point_override value");
    try expectContains(stdout_buffer.items, "[PASS] 241_contract_layout_stability value");
    try expectContains(stdout_buffer.items, "[PASS] 242_contract_opaque_struct value");
    try expectContains(stdout_buffer.items, "[PASS] 243_contract_sig_mismatch_link diagnostic");
    try expectContains(stdout_buffer.items, "[PASS] 244_contract_vtable_export value");
    try expectContains(stdout_buffer.items, "[PASS] 245_contract_generic_monomorph_share value");
    try expectContains(stdout_buffer.items, "[PASS] 246_contract_semver_minor_update value");
    try expectContains(stdout_buffer.items, "[PASS] 247_contract_semver_major_break value");
    try expectContains(stdout_buffer.items, "[PASS] 248_contract_ffi_boundary_trust value");
    try expectContains(stdout_buffer.items, "[PASS] 249_contract_macro_export value");
    try expectContains(stdout_buffer.items, "[PASS] 250_contract_const_export value");
    try expectContains(stdout_buffer.items, "[PASS] 251_contract_resource_ownership value");
    try expectContains(stdout_buffer.items, "[PASS] 252_contract_error_code_mapping value");
    try expectContains(stdout_buffer.items, "[PASS] 253_contract_callback_registration value");
    try expectContains(stdout_buffer.items, "[PASS] 254_contract_plugin_system value");
    try expectContains(stdout_buffer.items, "[PASS] 255_contract_memory_allocator_swap value");
    try expectContains(stdout_buffer.items, "[PASS] 256_contract_panic_handler_propagate value");
    try expectContains(stdout_buffer.items, "[PASS] 257_contract_log_facade value");
    try expectContains(stdout_buffer.items, "[PASS] 258_contract_thread_local_isolation value");
    try expectContains(stdout_buffer.items, "[PASS] 259_contract_static_init_order value");
    try expectContains(stdout_buffer.items, "[PASS] 260_contract_deprecated_warning value");
    try expectContains(stdout_buffer.items, "[PASS] 261_build_rs_codegen_saasm value");
    try expectContains(stdout_buffer.items, "[PASS] 262_build_bindgen_c_header value");
    try expectContains(stdout_buffer.items, "[PASS] 263_build_asset_bundling value");
    try expectContains(stdout_buffer.items, "[PASS] 264_build_env_var_injection value");
    try expectContains(stdout_buffer.items, "[PASS] 265_build_custom_linker_script value");
    try expectContains(stdout_buffer.items, "[PASS] 266_build_pre_compile_hook value");
    try expectContains(stdout_buffer.items, "[PASS] 267_build_post_compile_hook value");
    try expectContains(stdout_buffer.items, "[PASS] 268_build_cross_compile_wasm value");
    try expectContains(stdout_buffer.items, "[PASS] 269_build_cross_compile_windows value");
    try expectContains(stdout_buffer.items, "[PASS] 270_build_sysroot_custom value");
    try expectContains(stdout_buffer.items, "[PASS] 271_build_optimization_passes value");
    try expectContains(stdout_buffer.items, "[PASS] 272_build_sanitizer_flags value");
    try expectContains(stdout_buffer.items, "[PASS] 273_build_test_harness value");
    try expectContains(stdout_buffer.items, "[PASS] 274_build_benchmark_runner value");
    try expectContains(stdout_buffer.items, "[PASS] 275_build_doc_generator value");
    try expectContains(stdout_buffer.items, "[PASS] 276_build_incremental_caching value");
    try expectContains(stdout_buffer.items, "[PASS] 277_build_parallel_compilation value");
    try expectContains(stdout_buffer.items, "[PASS] 278_build_reproducible_builds value");
    try expectContains(stdout_buffer.items, "[PASS] 279_build_artifact_caching_remote value");
    try expectContains(stdout_buffer.items, "[PASS] 280_build_ci_cd_integration value");
    try expectContains(stdout_buffer.items, "[PASS] 281_ffi_link_system_libc gate");
    try expectContains(stdout_buffer.items, "[PASS] 282_ffi_link_static_c_lib gate");
    try expectContains(stdout_buffer.items, "[PASS] 283_ffi_link_dynamic_c_lib gate");
    try expectContains(stdout_buffer.items, "[PASS] 284_ffi_pkg_config_integration gate");
    try expectContains(stdout_buffer.items, "[PASS] 285_ffi_objective_c_framework gate");
    try expectContains(stdout_buffer.items, "[PASS] 286_ffi_rust_staticlib_integration gate");
    try expectContains(stdout_buffer.items, "[PASS] 287_ffi_zig_export_integration export");
    try expectContains(stdout_buffer.items, "[PASS] 288_ffi_cxx_name_mangling gate");
    try expectContains(stdout_buffer.items, "[PASS] 289_ffi_opaque_handle_passing gate");
    try expectContains(stdout_buffer.items, "[PASS] 290_ffi_callback_thunk vtable");
    try expectContains(stdout_buffer.items, "[PASS] 291_eco_wasm_host_imports guest");
    try expectContains(stdout_buffer.items, "[PASS] 292_eco_wasm_memory_export memory");
    try expectContains(stdout_buffer.items, "[PASS] 293_eco_embedded_no_os startup");
    try expectContains(stdout_buffer.items, "[PASS] 294_eco_os_kernel_module entry");
    try expectContains(stdout_buffer.items, "[PASS] 295_eco_bpf_ebpf_bytecode program");
    try expectContains(stdout_buffer.items, "[PASS] 296_eco_gpu_ptx_shader shader");
    try expectContains(stdout_buffer.items, "[PASS] 297_eco_game_engine_ecs step");
    try expectContains(stdout_buffer.items, "[PASS] 298_eco_cryptography_simd hash");
    try expectContains(stdout_buffer.items, "[PASS] 299_eco_language_server_protocol server");
    try expectContains(stdout_buffer.items, "[PASS] 300_eco_sa_lang_registry_publish publish");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json dom roundtrip");
    try expectContains(stdout_buffer.items, "[PASS] sa_std json stream tokens");
    try expectContains(stdout_buffer.items, "[PASS] sa_std regex groups");
    try expectContains(stdout_buffer.items, "[PASS] 178 panic hook path");
    try expectContains(stdout_buffer.items, "[PASS] framework ignored case");
    try expectContains(stdout_buffer.items, "test result: ok. 271 passed; 0 failed; 0 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

test "native unit assertions surface file line expected and got details" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const core_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/core/sa_core.sa");
    defer std.testing.allocator.free(core_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\
        \\@const ASSERT_FAIL_MSG = utf8:"tests/assert_diag.sa:7: expected 7, got 3"
        \\#def ASSERT_FAIL_MSG_LEN = 43
        \\
        \\@test "assert eq diagnostic"():
        \\L_ENTRY:
        \\    value = add 1, 2
        \\    EXPAND ASSERT_EQ_MSG assert_cond, value, 7, ASSERT_FAIL_MSG, ASSERT_FAIL_MSG_LEN
        \\    !value
        \\    !assert_cond
        \\    return
        \\
    , .{core_path});
    defer std.testing.allocator.free(source);
    try writeSource(tmp.dir, "assert_diag.sa", source);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const argv = [_][]const u8{ "sa", "test", "assert_diag.sa", "--jobs", "1" };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );

    try std.testing.expectEqual(@as(u8, 1), code);
    try expectContains(stdout_buffer.items, "[FAIL] assert eq diagnostic");
    try expectContains(stdout_buffer.items, "test result: FAILED. 0 passed; 1 failed; 0 skipped");
    try expectContains(stderr_buffer.items, "tests/assert_diag.sa:");
    try expectContains(stderr_buffer.items, "expected 7");
    try expectContains(stderr_buffer.items, "got 3");
}

test "native unit framework exposes standard mock io buffer" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    const mock_io_path = try original_cwd.realpathAlloc(std.testing.allocator, "sa_std/testing/mock_io.sa");
    defer std.testing.allocator.free(mock_io_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\@import "{s}"
        \\
        \\@const INPUT = utf8:"abcde"
        \\#def INPUT_LEN = 5
        \\
        \\@test "mock io buffer read write rewind"():
        \\L_ENTRY:
        \\    mock = alloc MockIo_SIZE
        \\    backing = alloc 4
        \\    EXPAND MOCK_IO_INIT mock, backing, 4
        \\    EXPAND MOCK_IO_WRITE written, mock, INPUT, INPUT_LEN
        \\    EXPAND MOCK_IO_LEN len0, mock
        \\    EXPAND MOCK_IO_REWIND mock
        \\    first = alloc 3
        \\    EXPAND MOCK_IO_READ read0, mock, first, 3
        \\    EXPAND MOCK_IO_POS pos0, mock
        \\    second = alloc 2
        \\    EXPAND MOCK_IO_READ read1, mock, second, 2
        \\    EXPAND MOCK_IO_POS pos1, mock
        \\    b0 = load first+0 as u8
        \\    b1 = load first+1 as u8
        \\    b2 = load first+2 as u8
        \\    b3 = load second+0 as u8
        \\    ok_written = eq written, 4
        \\    ok_len = eq len0, 4
        \\    ok_read0 = eq read0, 3
        \\    ok_pos0 = eq pos0, 3
        \\    ok_read1 = eq read1, 1
        \\    ok_pos1 = eq pos1, 4
        \\    ok_b0 = eq b0, 97
        \\    ok_b1 = eq b1, 98
        \\    ok_b2 = eq b2, 99
        \\    ok_b3 = eq b3, 100
        \\    ok01 = and ok_written, ok_len
        \\    ok02 = and ok01, ok_read0
        \\    ok03 = and ok02, ok_pos0
        \\    ok04 = and ok03, ok_read1
        \\    ok05 = and ok04, ok_pos1
        \\    ok06 = and ok05, ok_b0
        \\    ok07 = and ok06, ok_b1
        \\    ok08 = and ok07, ok_b2
        \\    ok = and ok08, ok_b3
        \\    !written
        \\    !len0
        \\    !read0
        \\    !pos0
        \\    !read1
        \\    !pos1
        \\    !b0
        \\    !b1
        \\    !b2
        \\    !b3
        \\    !ok_written
        \\    !ok_len
        \\    !ok_read0
        \\    !ok_pos0
        \\    !ok_read1
        \\    !ok_pos1
        \\    !ok_b0
        \\    !ok_b1
        \\    !ok_b2
        \\    !ok_b3
        \\    !ok01
        \\    !ok02
        \\    !ok03
        \\    !ok04
        \\    !ok05
        \\    !ok06
        \\    !ok07
        \\    !ok08
        \\    !mock
        \\    !backing
        \\    !first
        \\    !second
        \\    br ok -> L_OK, L_FAIL
        \\
        \\L_OK:
        \\    !ok
        \\    return
        \\
        \\L_FAIL:
        \\    !ok
        \\    panic(901)
        \\
    , .{mock_io_path});
    defer std.testing.allocator.free(source);
    try writeSource(tmp.dir, "mock_io_test.sa", source);

    var stdout_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const argv = [_][]const u8{ "sa", "test", "mock_io_test.sa", "--jobs", "1" };
    const code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        argv[0..],
        stdout_buffer.writer(),
        stderr_buffer.writer(),
    );
    if (code != 0) {
        std.debug.print("stdout: {s}\n", .{stdout_buffer.items});
        std.debug.print("stderr: {s}\n", .{stderr_buffer.items});
    }
    try std.testing.expectEqual(@as(u8, 0), code);
    try expectContains(stdout_buffer.items, "[PASS] mock io buffer read write rewind");
    try expectContains(stdout_buffer.items, "test result: ok. 1 passed; 0 failed; 0 skipped");
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);
}

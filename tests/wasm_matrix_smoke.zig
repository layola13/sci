const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");

fn writeSource(dir: std.fs.Dir, path: []const u8, source: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(source);
}

fn runCommandAnyExit(allocator: std.mem.Allocator, argv: []const []const u8) !std.process.Child.RunResult {
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
}

fn runWasmWithNode(allocator: std.mem.Allocator, wasm_path: []const u8, args: []const []const u8) !std.process.Child.RunResult {
    const args_json = try std.json.stringifyAlloc(allocator, args, .{});
    defer allocator.free(args_json);
    const wasm_json = try std.json.stringifyAlloc(allocator, wasm_path, .{});
    defer allocator.free(wasm_json);

    const script = try std.fmt.allocPrint(allocator,
        \\const fs = require('node:fs');
        \\const {{ WASI }} = require('node:wasi');
        \\const wasi = new WASI({{
        \\  version: 'preview1',
        \\  args: {s},
        \\  env: {{}},
        \\  preopens: {{ '/': '.' }},
        \\}});
        \\const wasm = fs.readFileSync({s});
        \\WebAssembly.instantiate(wasm, wasi.getImportObject()).then(({{ instance }}) => {{
        \\  process.exitCode = wasi.start(instance);
        \\}}).catch((err) => {{
        \\  console.error(err);
        \\  process.exit(1);
        \\}});
    , .{ args_json, wasm_json });
    defer allocator.free(script);

    const script_path = try std.fs.path.join(allocator, &.{ std.fs.path.dirname(wasm_path) orelse ".", "run_wasm.js" });
    defer allocator.free(script_path);
    try writeSource(std.fs.cwd(), script_path, script);
    return try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "node", "--no-warnings", script_path },
    });
}

fn artifactStem(allocator: std.mem.Allocator, path: []const u8) ![]const u8 {
    const base = std.fs.path.basename(path);
    const stem = std.fs.path.stem(base);
    if (!std.mem.eql(u8, stem, "main")) return try allocator.dupe(u8, stem);
    const parent = std.fs.path.dirname(path) orelse return try allocator.dupe(u8, stem);
    return try allocator.dupe(u8, std.fs.path.basename(parent));
}

fn assertBuildExeAndWasmStdout(path: []const u8, expected_stdout: []const u8) !void {
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
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try tmp.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const stem = try artifactStem(std.testing.allocator, path);
    defer std.testing.allocator.free(stem);
    const exe_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.out", .{stem});
    defer std.testing.allocator.free(exe_path);
    const wasm_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.wasm", .{stem});
    defer std.testing.allocator.free(wasm_path);

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", source_path, "-o", exe_path };
    const build_exe_code = saasm.cli.execute(std.testing.allocator, build_exe_argv[0..]) catch |err| {
        std.debug.print("build-exe errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    if (build_exe_code != 0) std.debug.print("build-exe failed: {s}\n", .{path});
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);

    const exe_run_path = try std.fmt.allocPrint(std.testing.allocator, "./{s}", .{exe_path});
    defer std.testing.allocator.free(exe_run_path);
    const exe_result = try runCommandAnyExit(std.testing.allocator, &[_][]const u8{exe_run_path});
    defer std.testing.allocator.free(exe_result.stdout);
    defer std.testing.allocator.free(exe_result.stderr);
    switch (exe_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, exe_result.stdout, expected_stdout) or exe_result.stderr.len != 0) {
                std.debug.print("native demo failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, exe_result.stdout, exe_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings(expected_stdout, exe_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), exe_result.stderr.len);

    const build_wasm_argv = [_][]const u8{ "sa", "build-wasm", source_path, "-o", wasm_path, "--target", "wasm32" };
    const build_wasm_code = saasm.cli.execute(std.testing.allocator, build_wasm_argv[0..]) catch |err| {
        std.debug.print("build-wasm errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    if (build_wasm_code != 0) std.debug.print("build-wasm failed: {s}\n", .{path});
    try std.testing.expectEqual(@as(u8, 0), build_wasm_code);

    const bc_path = try std.fmt.allocPrint(std.testing.allocator, "{s}.sa.bc", .{wasm_path});
    defer std.testing.allocator.free(bc_path);
    const bc_file = try tmp.dir.openFile(bc_path, .{});
    defer bc_file.close();
    const bc_bytes = try bc_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(bc_bytes);
    try std.testing.expect(bc_bytes.len > 0);

    const wasm_file = try tmp.dir.openFile(wasm_path, .{});
    defer wasm_file.close();
    const wasm_bytes = try wasm_file.readToEndAlloc(std.testing.allocator, 1 << 20);
    defer std.testing.allocator.free(wasm_bytes);
    try std.testing.expect(wasm_bytes.len > 8);
    try std.testing.expectEqualSlices(u8, &std.wasm.magic, wasm_bytes[0..4]);
    try std.testing.expectEqualSlices(u8, &std.wasm.version, wasm_bytes[4..8]);

    const wasm_result = try runWasmWithNode(std.testing.allocator, wasm_path, &.{ "sa", wasm_path });
    defer std.testing.allocator.free(wasm_result.stdout);
    defer std.testing.allocator.free(wasm_result.stderr);
    switch (wasm_result.term) {
        .Exited => |code| {
            if (code != 0 or !std.mem.eql(u8, wasm_result.stdout, expected_stdout) or wasm_result.stderr.len != 0) {
                std.debug.print("wasm demo failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, wasm_result.stdout, wasm_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings(expected_stdout, wasm_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), wasm_result.stderr.len);
}

test "llvmc wasm rosetta and support demos match native output" {
    try assertBuildExeAndWasmStdout("demos/rosetta/01_hello_world/main.sa", "hello, saasm\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/02_mutability/main.sa", "20\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/03_if_else/main.sa", "20\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/05_struct/main.sa", "(10,20)\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/06_enum_and_match/main.sa", "30\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/08_closures/main.sa", "15\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/09_async_await/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/10_generics_monomorph/main.sa", "42\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/11_tuples/main.sa", "(3, 4)\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/12_destructuring/main.sa", "7\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/13_array_sum/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/14_slice_window/main.sa", "5\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/15_string_bytes/main.sa", "4\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/16_methods/main.sa", "25\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/17_associated_fn/main.sa", "42\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/18_option_map/main.sa", "8\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/21_while_loop/main.sa", "15\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/20_boxed_value/main.sa", "9\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/22_break_continue/main.sa", "9\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/23_nested_loops/main.sa", "18\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/24_factorial/main.sa", "120\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/25_fibonacci/main.sa", "21\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/26_reference_return/main.sa", "9\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/27_move_semantics/main.sa", "11\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/28_borrow_chains/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/29_const_data/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/30_manual_guard_branch/main.sa", "5\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/31_trait_static_dispatch/main.sa", "16\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/33_iterator_map/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/34_iterator_filter/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/35_iterator_fold/main.sa", "7\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/36_tuple_struct/main.sa", "14\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/37_newtype/main.sa", "42\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/38_generic_struct_i32/main.sa", "31\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/39_generic_enum_i32/main.sa", "7\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/40_impl_block_state/main.sa", "15\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/41_module_imports/main.sa", "42\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/42_export_visibility/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/44_slice_iteration/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/45_config_merge/main.sa", "4 3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/46_option_default/main.sa", "9\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/47_tuple_swap/main.sa", "8,3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/48_generic_pair/main.sa", "11,31\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/49_pipeline_map/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/51_refcount/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/52_queue_rotate/main.sa", "2,3,1\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/43_tagged_union/main.sa", "36\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/53_cache_hits/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/54_mem_fill/main.sa", "7,7,7,7\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/55_builder_pattern/main.sa", "POST /api\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/56_state_machine/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/57_event_loop/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/58_borrow_update/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/59_method_counter/main.sa", "4\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/60_enum_branch/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/61_thread_pool/main.sa", "5\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/62_channel_pingpong/main.sa", "8\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/63_router_table/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/64_file_manifest/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/65_job_scheduler/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/66_actor_mailbox/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/67_resource_pool/main.sa", "20\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/68_parser_tokens/main.sa", "4\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/69_serializer/main.sa", "{\"id\":7}\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/70_integration_service/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/71_pipeline_stage/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/72_graph_walk/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/73_scene_nodes/main.sa", "15\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/74_component_store/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/75_async_bridge/main.sa", "5\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/76_lockfree_counter/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/77_http_route/main.sa", "/health\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/78_cli_args/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/79_metrics/main.sa", "4\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/80_workflow/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/81_kv_store/main.sa", "5\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/82_sql_scan/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/83_blob_chunk/main.sa", "4\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/84_sync_gate/main.sa", "1\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/85_scheduler_tree/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/86_cache_eviction/main.sa", "20\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/87_protocol_frame/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/88_text_index/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/89_job_queue/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/90_app_shell/main.sa", "app --mode demo\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/91_db_session/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/92_query_plan/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/93_log_aggregator/main.sa", "10\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/94_graphql_router/main.sa", "query user\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/95_repl_shell/main.sa", "sa> \n");
    try assertBuildExeAndWasmStdout("demos/rosetta/96_task_orchestrator/main.sa", "4\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/97_sync_service/main.sa", "1\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/98_build_pipeline/main.sa", "6\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/99_release_bundle/main.sa", "3\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/100_full_app/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/176_result_flattening/main.sa", "2\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/178_panic_hook_override/main.sa", "1\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/180_try_trait_v2/main.sa", "7\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/253_contract_callback_registration/main.sa", "253\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/19_result_question/main.sa", "21\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/50_error_chain/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/07_trait_vtable/main.sa", "77\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/110_trait_super_vtable/main.sa", "15\n");
    try assertBuildExeAndWasmStdout("demos/rosetta/32_trait_object_vector/main.sa", "12\n");
    try assertBuildExeAndWasmStdout("demos/support/sort_probe.sa", "sort ok\n");
    try assertBuildExeAndWasmStdout("demos/support/hashmap_probe.sa", "alpha\nbravo\nmap ok\n");
    try assertBuildExeAndWasmStdout("demos/support/hashset_probe.sa", "set ok\n");
    try assertBuildExeAndWasmStdout("demos/support/once_probe.sa", "once ok\n");
    try assertBuildExeAndWasmStdout("demos/support/mpsc_probe.sa", "mpsc ok\n");
}

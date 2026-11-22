const std = @import("std");
const saasm = @import("saasm");
const builtin = @import("builtin");
const sio = @import("sio");

const helpers = @import("helpers.zig");
const parseJsonValue = helpers.parseJsonValue;
const jsonObjectGet = helpers.jsonObjectGet;
const jsonObjectGetValue = helpers.jsonObjectGetValue;
const jsonArrayCount = helpers.jsonArrayCount;
const writeSource = helpers.writeSource;
const writeBytes = helpers.writeBytes;
const assertBuildExeStdout = helpers.assertBuildExeStdout;
const assertBuildExeStdoutPureBc = helpers.assertBuildExeStdoutPureBc;

test "build and run json diagnostics emit structured success metrics on stderr" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try writeSource(tmp.dir, "json_success.sa",
        \\@main() -> i32:
        \\return 7
    );

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const run_argv = [_][]const u8{ "sa", "run", "json_success.sa", "--json" };
    const run_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        run_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 7), run_code);
    try std.testing.expectEqualStrings("{\"status\":\"ok\",\"metrics\":{\"compile_tokens\":5,\"instruction_count\":2}}\n", stderr_buffer.items);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const build_exe_argv = [_][]const u8{ "sa", "build-exe", "json_success.sa", "-o", "json_success.out", "--json" };
    const build_exe_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_exe_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), build_exe_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"status\":\"ok\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "\"compile_tokens\":5"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const build_mem_argv = [_][]const u8{ "sa", "build-exe", "json_success.sa", "-o", "json_success_mem.out", "--json", "--mem-report", "--no-incremental" };
    const build_mem_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_mem_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), build_mem_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    var mem_json = try parseJsonValue(std.testing.allocator, stderr_buffer.items);
    defer mem_json.deinit();
    const mem_metrics = try jsonObjectGet(&mem_json, "metrics");
    const memory = try jsonObjectGetValue(mem_metrics, "memory");
    const rss = try jsonObjectGetValue(memory, "rss_bytes");
    _ = try jsonObjectGetValue(rss, "start");
    _ = try jsonObjectGetValue(rss, "after_load");
    _ = try jsonObjectGetValue(rss, "after_setup");
    _ = try jsonObjectGetValue(rss, "after_flatten");
    _ = try jsonObjectGetValue(rss, "after_verify");
    _ = try jsonObjectGetValue(rss, "after_emit");
    _ = try jsonObjectGetValue(rss, "after_link");
    _ = try jsonObjectGetValue(rss, "end");
    const verifier_rss = try jsonObjectGetValue(memory, "verifier_rss_bytes");
    _ = try jsonObjectGetValue(verifier_rss, "start");
    _ = try jsonObjectGetValue(verifier_rss, "after_classify");
    _ = try jsonObjectGetValue(verifier_rss, "after_metadata");
    _ = try jsonObjectGetValue(verifier_rss, "after_chunks");
    _ = try jsonObjectGetValue(verifier_rss, "after_finalize");
    _ = try jsonObjectGetValue(memory, "peak_rss_bytes");

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const build_mem_text_argv = [_][]const u8{ "sa", "build-exe", "json_success.sa", "-o", "json_success_mem_text.out", "--mem-report", "--no-incremental" };
    const build_mem_text_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        build_mem_text_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), build_mem_text_code);
    try std.testing.expectEqual(@as(usize, 0), stdout_buffer.items.len);
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "memory stage start"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "memory stage verifier.after_classify"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "memory report (RSS)"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "after_flatten"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stderr_buffer.items, 1, "peak"));
}

test "graph and size cli emit structured reports for a tiny project" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    try tmp.dir.createDirPath(std.testing.io, "src");
    try writeSource(tmp.dir, "src/main.sa",
        \\@helper(value: i32) -> i32:
        \\    return value
        \\@main() -> i32:
        \\    value = call @helper(7)
        \\    return value
    );

    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const graph_argv = [_][]const u8{ "sa", "graph", "--json" };
    const graph_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        graph_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), graph_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const graph_parsed = try parseJsonValue(std.testing.allocator, stdout_buffer.items);
    defer graph_parsed.deinit();
    const graph_root = try jsonObjectGet(&graph_parsed, "graph");

    const graph_value = switch (graph_root) {
        .object => |object| object,
        else => return error.TestUnexpectedResult,
    };
    const nodes_value = graph_value.get("nodes") orelse return error.TestUnexpectedResult;
    const edges_value = graph_value.get("edges") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), try jsonArrayCount(nodes_value));
    try std.testing.expectEqual(@as(usize, 1), try jsonArrayCount(edges_value));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"kind\":\"source_file\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"kind\":\"function\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"kind\":\"calls\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    const size_argv = [_][]const u8{ "sa", "size", "--json" };
    const size_code = try saasm.cli.executeWithWriters(
        std.testing.allocator,
        size_argv[0..],
        sio.managedWriter(&stdout_buffer),
        sio.managedWriter(&stderr_buffer),
    );
    try std.testing.expectEqual(@as(u8, 0), size_code);
    try std.testing.expectEqual(@as(usize, 0), stderr_buffer.items.len);

    const size_parsed = try parseJsonValue(std.testing.allocator, stdout_buffer.items);
    defer size_parsed.deinit();
    const size_graph = try jsonObjectGet(&size_parsed, "functions");
    try std.testing.expectEqual(@as(usize, 2), try jsonArrayCount(size_graph));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"name\":\"helper\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"name\":\"main\""));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"instruction_count\":"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"byte_count\":"));
}

test "llvmc backend compilation and verification on rosetta demos" {
    try assertBuildExeStdoutPureBc("demos/rosetta/01_hello_world/main.sa", "hello, saasm\n");
    try assertBuildExeStdoutPureBc("demos/rosetta/04_loop/main.sa", "[0,0,0,0]\n");
    try assertBuildExeStdout("demos/rosetta/21_while_loop/main.sa", "15\n");
}

test "agent capability: check verdict cache and affected help" {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    const help_argv = [_][]const u8{ "sa", "--help" };
    const help_code = try saasm.cli.executeWithWriters(std.testing.allocator, help_argv[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
    try std.testing.expectEqual(@as(u8, 0), help_code);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "check"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "daemon"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "--affected"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();

    // In-process check hit: same process reuses verdict cache.
    const check1 = [_][]const u8{ "sa", "check", "tests/agent_fixtures/check_ok.sa", "--json" };
    const c1 = try saasm.cli.executeWithWriters(std.testing.allocator, check1[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
    try std.testing.expectEqual(@as(u8, 0), c1);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"hit\":false") or std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"status\":\"ok\""));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const c2 = try saasm.cli.executeWithWriters(std.testing.allocator, check1[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
    try std.testing.expectEqual(@as(u8, 0), c2);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "\"hit\":true"));

    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const test_help = [_][]const u8{ "sa", "test", "--help" };
    const th = try saasm.cli.executeWithWriters(std.testing.allocator, test_help[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
    try std.testing.expectEqual(@as(u8, 0), th);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "--affected"));
}

test "agent capability: affected selects impacted tests" {
    var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stdout_buffer.deinit();
    var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
    defer stderr_buffer.deinit();

    // First run establishes baseline (no prior function hashes in this process).
    const first = [_][]const u8{ "sa", "test", "tests/agent_fixtures/affected_graph.sa", "--affected" };
    const code1 = try saasm.cli.executeWithWriters(std.testing.allocator, first[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
    try std.testing.expectEqual(@as(u8, 0), code1);
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "affected:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "baseline=no") or std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "selected_tests"));

    // Second identical run: source-pass-cache or no impacted tests.
    stdout_buffer.clearRetainingCapacity();
    stderr_buffer.clearRetainingCapacity();
    const code2 = try saasm.cli.executeWithWriters(std.testing.allocator, first[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
    try std.testing.expectEqual(@as(u8, 0), code2);
    try std.testing.expect(
        std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "skipped") or
            std.mem.containsAtLeast(u8, stdout_buffer.items, 1, "selected_tests=0"),
    );
}

test "sab with corrupted param_ids traps CorruptedSignature without panic or text fallback" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    // The program needs a function with parameters so param_ids is populated
    // in the encoded SAB. The by-value params must be released before
    // `return`: the verifier's function-exit MemoryLeak check (which since
    // the widened verifier runs at every function boundary, not only the
    // last function) traps on live param registers -- @add2 is not the
    // last function here, so the unreleased `a`/`b` used to be masked and
    // now fail the emit step below with MemoryLeak 1012 before the
    // corrupted-SAB cases ever run.
    const sa_source =
        \\@add2(a: u64, b: u64) -> u64:
        \\L_ENTRY:
        \\    c = add a, b
        \\    !a
        \\    !b
        \\    return c
        \\@main() -> i32:
        \\L_MAIN:
        \\    call @add2(20, 22)
        \\    return 0
    ;
    try writeSource(tmp.dir, "params.sa", sa_source);

    // Produce a valid SAB through the real `check --emit-sab` CLI path.
    // NOTE: use executeWithWriters (not execute): execute writes to the real
    // process stdout, which corrupts the `zig build` --listen test protocol
    // and hangs the run.
    const emit_argv = [_][]const u8{ "sa", "check", "params.sa", "--emit-sab", "params.sab" };
    var emit_stdout = std.array_list.Managed(u8).init(std.testing.allocator);
    defer emit_stdout.deinit();
    var emit_stderr = std.array_list.Managed(u8).init(std.testing.allocator);
    defer emit_stderr.deinit();
    const emit_code = try saasm.cli.executeWithWriters(std.testing.allocator, emit_argv[0..], sio.managedWriter(&emit_stdout), sio.managedWriter(&emit_stderr));
    try std.testing.expectEqual(@as(u8, 0), emit_code);

    const sab_file = try tmp.dir.openFile(std.testing.io, "params.sab", .{});
    const sab_bytes = try sio.readToEndAlloc(sab_file, std.testing.allocator, 1 << 20);
    sab_file.close(std.testing.io);
    defer std.testing.allocator.free(sab_bytes);
    try std.testing.expect(sab_bytes.len > 0);

    // Sanity: the encoded @add2 signature really carries params/param_ids.
    {
        var module = try saasm.sab.decodeModule(std.testing.allocator, sab_bytes);
        defer module.deinit(std.testing.allocator);
        const sig = for (module.function_sigs) |*fsig| {
            if (std.mem.eql(u8, fsig.name, "add2")) break fsig;
        } else return error.TestUnexpectedResult;
        try std.testing.expectEqual(@as(usize, 2), sig.params.len);
        try std.testing.expectEqual(@as(usize, 2), sig.param_ids.len);
    }

    // Corrupt param_ids through decode/mutate/re-encode. The corrupted file
    // stays a structurally valid SAB (magic and complete sections intact), so
    // the failure must surface as a verifier trap -- never a decode error and
    // never a silent text fallback. Before the fix, the bad param_id hit
    // `orelse unreachable` (panic) and the short param_ids indexed OOB.
    //
    // Each case runs the real CLI (`sa check <file>.sab`) and asserts:
    //   - explicit non-zero exit (1),
    //   - stderr names the CorruptedSignature trap with numeric code 1058
    //     and the "corrupted function signature" message,
    //   - stderr never contains "panic".
    const Case = enum { bad_reg_id, short_param_ids };
    for ([_]Case{ .bad_reg_id, .short_param_ids }) |case| {
        const bad_name = switch (case) {
            .bad_reg_id => "bad_param_id.sab",
            .short_param_ids => "short_param_ids.sab",
        };
        {
            var module = try saasm.sab.decodeModule(std.testing.allocator, sab_bytes);
            defer module.deinit(std.testing.allocator);
            const sig = for (module.function_sigs) |*fsig| {
                if (std.mem.eql(u8, fsig.name, "add2")) break fsig;
            } else return error.TestUnexpectedResult;
            switch (case) {
                .bad_reg_id => {
                    // param_id references a register id not declared in this
                    // function scope.
                    try std.testing.expectEqual(@as(usize, 2), sig.param_ids.len);
                    const mutable_ids: []u32 = @constCast(sig.param_ids);
                    mutable_ids[0] = std.math.maxInt(u32);
                },
                .short_param_ids => {
                    // param_ids shorter than params.
                    try std.testing.expect(sig.params.len == 2);
                    std.testing.allocator.free(sig.param_ids);
                    sig.param_ids = &.{};
                },
            }
            const bad_bytes = try saasm.sab.encodeProgramWithConsts(
                std.testing.allocator,
                module.symbols,
                module.const_decls,
                module.function_sigs,
                module.instructions,
            );
            defer std.testing.allocator.free(bad_bytes);
            try writeBytes(tmp.dir, bad_name, bad_bytes);
        }

        var stdout_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
        defer stdout_buffer.deinit();
        var stderr_buffer = std.array_list.Managed(u8).init(std.testing.allocator);
        defer stderr_buffer.deinit();
        const argv = [_][]const u8{ "sa", "check", bad_name };
        const code = try saasm.cli.executeWithWriters(std.testing.allocator, argv[0..], sio.managedWriter(&stdout_buffer), sio.managedWriter(&stderr_buffer));
        try std.testing.expectEqual(@as(u8, 1), code);
        try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "CorruptedSignature") != null);
        try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "corrupted function signature") != null);
        try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "\"trap_code\":1058") != null);
        try std.testing.expect(std.mem.indexOf(u8, stderr_buffer.items, "panic") == null);
    }
}

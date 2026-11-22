const std = @import("std");
const builtin = @import("builtin");
const saasm = @import("saasm");
const sio = @import("sio");
const elapsedMs = @import("helpers.zig").elapsedMs;
const jsMatrixShardSelected = @import("helpers.zig").jsMatrixShardSelected;
const runJsWithNode = @import("helpers.zig").runJsWithNode;

/// SAB-form variant of assertJsMatrixStdout: the demo source is first
/// encoded with `sa check --emit-sab` (the same SAB v4 encoding the SLA
/// plugin's build-js route feeds the emitter; SAB v4 stores no raw_text)
/// and the resulting .sab is then built with `sa build-js`. This is the
/// route that hit DEF-JS-BUILDJS-OPERAND: emitter analyses written for
/// the text form misread raw_text-less call instructions (call dest
/// names derived in the wrong id space, slot mentions hidden inside
/// composite call texts).
pub fn assertJsMatrixStdoutViaSab(path: []const u8, expected_stdout: []const u8) !void {
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    if (!jsMatrixShardSelected()) {
        std.debug.print("[js-matrix] SKIP  demo={s} reason=shard\n", .{path});
        return;
    }
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    const demo_start = sio.nanoTimestamp();
    std.debug.print("[js-matrix] START demo={s} (via-sab)\n", .{path});
    var demo_ended = false;
    errdefer {
        if (!demo_ended) std.debug.print("[js-matrix] FAIL demo={s} (via-sab)\n", .{path});
    }

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const base = std.fs.path.basename(path);
    const stem = std.fs.path.stem(base);
    const parent = std.fs.path.dirname(path) orelse ".";
    const tag = std.fs.path.basename(parent);
    const sab_name = try std.fmt.allocPrint(std.testing.allocator, "{s}_{s}.sab", .{ tag, stem });
    defer std.testing.allocator.free(sab_name);
    const js_name = try std.fmt.allocPrint(std.testing.allocator, "{s}_{s}.mjs", .{ tag, stem });
    defer std.testing.allocator.free(js_name);

    const check_argv = [_][]const u8{ "sa", "check", source_path, "--emit-sab", sab_name };
    // DEF-SUITE-LISTEN-STALL: executeWithWriters, not execute — execute
    // writes "check ok: ..." to the real stdout, which is the
    // std.zig.Server (--listen=-) protocol channel under `zig build`
    // and deadlocks the run. See emit_sab_inprocess_smoke.zig.
    var check_out = std.array_list.Managed(u8).init(std.testing.allocator);
    defer check_out.deinit();
    var check_err = std.array_list.Managed(u8).init(std.testing.allocator);
    defer check_err.deinit();
    const check_code = saasm.cli.executeWithWriters(std.testing.allocator, check_argv[0..], sio.managedWriter(&check_out), sio.managedWriter(&check_err)) catch |err| {
        std.debug.print("check --emit-sab errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    if (check_code != 0) std.debug.print("check --emit-sab failed: {s}\n", .{path});
    try std.testing.expectEqual(@as(u8, 0), check_code);

    const build_js_argv = [_][]const u8{ "sa", "build-js", sab_name, "-o", js_name, "--project-root", repo_root };
    const build_js_code = saasm.cli.execute(std.testing.allocator, build_js_argv[0..]) catch |err| {
        std.debug.print("build-js (sab) errored: {s}: {s}\n", .{ path, @errorName(err) });
        return err;
    };
    if (build_js_code != 0) std.debug.print("build-js (sab) failed: {s}\n", .{path});
    try std.testing.expectEqual(@as(u8, 0), build_js_code);

    const js_file = try tmp.dir.openFile(std.testing.io, js_name, .{});
    defer js_file.close(std.testing.io);
    var js_rbuf: [8192]u8 = undefined;
    var js_reader = js_file.reader(std.testing.io, &js_rbuf);
    const js_bytes = try js_reader.interface.allocRemaining(std.testing.allocator, .limited(1 << 24));
    defer std.testing.allocator.free(js_bytes);
    try std.testing.expect(js_bytes.len > 64);

    const js_result = try runJsWithNode(std.testing.allocator, js_name);
    defer std.testing.allocator.free(js_result.stdout);
    defer std.testing.allocator.free(js_result.stderr);
    switch (js_result.term) {
        .exited => |code| {
            if (code != 0 or !std.mem.eql(u8, js_result.stdout, expected_stdout) or js_result.stderr.len != 0) {
                std.debug.print("js demo (sab) failed: {s}\nstdout:\n{s}\nstderr:\n{s}\n", .{ path, js_result.stdout, js_result.stderr });
            }
            try std.testing.expectEqual(@as(u8, 0), code);
        },
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings(expected_stdout, js_result.stdout);
    try std.testing.expectEqual(@as(usize, 0), js_result.stderr.len);

    std.debug.print("[js-matrix] END   demo={s} (via-sab) elapsed={}ms\n", .{ path, elapsedMs(demo_start) });
    demo_ended = true;
}

test "js backend SAB-form demos match expected output under node" {
    // DEF-JS-BUILDJS-OPERAND: the plugin build-js route feeds the
    // emitter SAB (no raw_text), not SA text. 965 through this route
    // failed pre-fix with "InvalidOperand in print_u64" (call dest
    // resolved in the global symbol id space); 974 pins that shape,
    // 975 pins the globals shim + the slot-promotion escape scan (an
    // extern out-param slot mentioned only inside a composite call
    // text must not be promoted; pre-fix it read back the stale 0).
    // (965 itself is not repeated here: it is 974's source with a
    // different header, and a second in-process `check --emit-sab` on
    // a near-identical program traps with "SAB encode failed:
    // verification trap" — a pre-existing in-process CLI state defect,
    // registered separately; one-shot CLI processes are unaffected.)
    try assertJsMatrixStdoutViaSab("demos/js/974_sab_call_dest/main.sa", "42\n0\n");
    try assertJsMatrixStdoutViaSab("demos/js/975_sab_extern_outparam/main.sa", "5\n0\n");
}

pub fn assertJsBuildRejects(path: []const u8) !void {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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
    // JS value-handle binding misuse must be rejected at build time.
    try assertJsBuildRejects("demos/support/jsh_reject_method_nonhandle.sa");
    try assertJsBuildRejects("demos/support/jsh_reject_ctor_return.sa");
    try assertJsBuildRejects("demos/support/jsh_reject_unknown_keyword.sa");
    try assertJsBuildRejects("demos/support/jsh_reject_get_extra_args.sa");
    try assertJsBuildRejects("demos/support/jsh_reject_ctor_ns.sa");
}

pub fn assertJsRuntimeTrap(path: []const u8, expected_stderr_substr: []const u8) !void {
    // Counterpart of assertJsMatrixStdout for programs that must BUILD
    // cleanly but TRAP at runtime: node must exit nonzero and carry the
    // diagnostic on stderr. Probes live in demos/support (never rosetta,
    // so the native/wasm matrices that expect exit 0 stay untouched).
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);
    const source_path = try original_cwd.realpathAlloc(std.testing.allocator, path);
    defer std.testing.allocator.free(source_path);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
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
        .exited => |code| {
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
    // JS value-handle misuse must trap loudly at runtime.
    try assertJsRuntimeTrap("demos/support/jsh_use_after_release.sa", "stale or released handle");
    try assertJsRuntimeTrap("demos/support/jsh_double_release.sa", "stale or released handle");
    try assertJsRuntimeTrap("demos/support/jsh_invalid_handle.sa", "js handle: handle out of range");
    try assertJsRuntimeTrap("demos/support/jsh_make_callback_bad.sa", "not an SA function pointer");
    // Goroutine scheduler misuse must trap loudly, never hang: a
    // deadlocked program and a send on a closed channel.
    try assertJsRuntimeTrap("demos/support/jstask_deadlock_probe.sa", "sa_task: deadlock: no ready task and no pending timer");
    try assertJsRuntimeTrap("demos/support/jstask_send_on_closed_probe.sa", "send on closed channel");
    try assertJsRuntimeTrap("demos/support/jstask_mutex_deadlock_probe.sa", "sa_task: deadlock: no ready task and no pending timer");
}

test "js backend dce: unreferenced extern trap stubs are not emitted" {
    // dce=full for extern stubs: a module may declare a wide extern
    // surface (generated .sai files carry tens of thousands of entries)
    // while referencing almost none of it. Unreferenced, unbound externs
    // must not be materialized as `extern not linked` trap stubs in the
    // emitted JS; a referenced-but-unbound extern keeps its trap stub
    // verbatim and still traps loudly when called at runtime.
    if (builtin.os.tag != .linux) return error.SkipZigTest;
    const node_probe = sio.Child.run(.{
        .allocator = std.testing.allocator,
        .argv = &.{ "node", "--version" },
    }) catch return error.SkipZigTest;
    defer std.testing.allocator.free(node_probe.stdout);
    defer std.testing.allocator.free(node_probe.stderr);
    switch (node_probe.term) {
        .exited => |code| if (code != 0) return error.SkipZigTest,
        else => return error.SkipZigTest,
    }

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const source =
        \\@extern dce_used(x: i32) -> i32
        \\@extern dce_unused_a(x: i32) -> i32
        \\@extern dce_unused_b(x: i32) -> i32
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    r = call @dce_used(41)
        \\    return r
    ;
    {
        const f = try tmp.dir.createFile(std.testing.io, "dce_unit.sa", .{ .truncate = true });
        defer f.close(std.testing.io);
        var wbuf: [1024]u8 = undefined;
        var fw = f.writer(std.testing.io, &wbuf);
        try fw.interface.writeAll(source);
        try fw.interface.flush();
    }

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const build_js_argv = [_][]const u8{ "sa", "build-js", "dce_unit.sa", "-o", "dce_unit.mjs", "--project-root", repo_root };
    const build_js_code = try saasm.cli.execute(std.testing.allocator, build_js_argv[0..]);
    try std.testing.expectEqual(@as(u8, 0), build_js_code);

    const js_file = try tmp.dir.openFile(std.testing.io, "dce_unit.mjs", .{});
    defer js_file.close(std.testing.io);
    var js_rbuf: [8192]u8 = undefined;
    var js_reader = js_file.reader(std.testing.io, &js_rbuf);
    const js_bytes = try js_reader.interface.allocRemaining(std.testing.allocator, .limited(1 << 24));
    defer std.testing.allocator.free(js_bytes);

    // Referenced + unbound: trap stub retained verbatim.
    try std.testing.expect(std.mem.indexOf(u8, js_bytes, "function dce_used() { __sa_trap(\"extern not linked: dce_used\"); }") != null);
    // Unreferenced + unbound: no trace in the output at all.
    try std.testing.expect(std.mem.indexOf(u8, js_bytes, "dce_unused_a") == null);
    try std.testing.expect(std.mem.indexOf(u8, js_bytes, "dce_unused_b") == null);

    // Runtime: calling the referenced unbound extern traps with its name.
    const js_result = try runJsWithNode(std.testing.allocator, "dce_unit.mjs");
    defer std.testing.allocator.free(js_result.stdout);
    defer std.testing.allocator.free(js_result.stderr);
    switch (js_result.term) {
        .exited => |code| try std.testing.expect(code != 0),
        else => return error.TestUnexpectedResult,
    }
    try std.testing.expect(std.mem.indexOf(u8, js_result.stderr, "extern not linked: dce_used") != null);
}

/// Remove every occurrence of `needle` from `haystack`, returning an
/// owned slice. Test helper for the --dce byte-identity assertion.
pub fn removeSubstringAlloc(allocator: std.mem.Allocator, haystack: []const u8, needle: []const u8) ![]u8 {
    const count = std.mem.count(u8, haystack, needle);
    if (count == 0) return allocator.dupe(u8, haystack);
    const out = try allocator.alloc(u8, haystack.len);
    errdefer allocator.free(out);
    const n = std.mem.replace(u8, haystack, needle, "", out);
    if (n != count) return error.TestUnexpectedResult;
    return allocator.realloc(out, haystack.len - n * needle.len);
}

test "js backend dce: --dce no keeps unreferenced extern trap stubs" {
    // `--dce no` is the pre-DCE behavior kept for debugging: every
    // unbound extern materializes its trap stub, referenced or not.
    // The default output (stub DCE on) must be exactly the --dce no
    // output minus the two dropped stub lines, byte-for-byte, so the
    // modes can never drift apart in any other byte.
    if (builtin.os.tag != .linux) return error.SkipZigTest;

    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    const repo_root = try original_cwd.realpathAlloc(std.testing.allocator, ".");
    defer std.testing.allocator.free(repo_root);

    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const source =
        \\@extern dce_used(x: i32) -> i32
        \\@extern dce_unused_a(x: i32) -> i32
        \\@extern dce_unused_b(x: i32) -> i32
        \\
        \\@main() -> i32:
        \\L_ENTRY:
        \\    r = call @dce_used(41)
        \\    return r
    ;
    {
        const f = try tmp.dir.createFile(std.testing.io, "dce_unit.sa", .{ .truncate = true });
        defer f.close(std.testing.io);
        var wbuf: [1024]u8 = undefined;
        var fw = f.writer(std.testing.io, &wbuf);
        try fw.interface.writeAll(source);
        try fw.interface.flush();
    }

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const read_out = struct {
        fn read(allocator: std.mem.Allocator, dir: std.Io.Dir, name: []const u8) ![]u8 {
            const file = try dir.openFile(std.testing.io, name, .{});
            defer file.close(std.testing.io);
            var rbuf: [8192]u8 = undefined;
            var reader = file.reader(std.testing.io, &rbuf);
            return reader.interface.allocRemaining(allocator, .limited(1 << 24));
        }
    }.read;

    // Default build: current behavior (stub DCE on).
    const def_argv = [_][]const u8{ "sa", "build-js", "dce_unit.sa", "-o", "dce_def.mjs", "--project-root", repo_root };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, def_argv[0..]));
    const def_bytes = try read_out(std.testing.allocator, tmp.dir, "dce_def.mjs");
    defer std.testing.allocator.free(def_bytes);

    // --dce no build: every stub retained.
    const no_argv = [_][]const u8{ "sa", "build-js", "dce_unit.sa", "-o", "dce_no.mjs", "--dce", "no", "--project-root", repo_root };
    try std.testing.expectEqual(@as(u8, 0), try saasm.cli.execute(std.testing.allocator, no_argv[0..]));
    const no_bytes = try read_out(std.testing.allocator, tmp.dir, "dce_no.mjs");
    defer std.testing.allocator.free(no_bytes);

    const stub_a = "function dce_unused_a() { __sa_trap(\"extern not linked: dce_unused_a\"); }";
    const stub_b = "function dce_unused_b() { __sa_trap(\"extern not linked: dce_unused_b\"); }";
    // --dce no keeps both unreferenced stubs; the default drops them.
    try std.testing.expect(std.mem.indexOf(u8, no_bytes, stub_a) != null);
    try std.testing.expect(std.mem.indexOf(u8, no_bytes, stub_b) != null);
    try std.testing.expect(std.mem.indexOf(u8, def_bytes, "dce_unused_a") == null);
    try std.testing.expect(std.mem.indexOf(u8, def_bytes, "dce_unused_b") == null);

    // Removing exactly the two stub lines from the --dce no output
    // reproduces the default output byte-for-byte.
    const strip_a = try removeSubstringAlloc(std.testing.allocator, no_bytes, stub_a ++ "\n");
    defer std.testing.allocator.free(strip_a);
    const stripped = try removeSubstringAlloc(std.testing.allocator, strip_a, stub_b ++ "\n");
    defer std.testing.allocator.free(stripped);
    try std.testing.expectEqualStrings(def_bytes, stripped);
}

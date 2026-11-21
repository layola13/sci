const std = @import("std");
const builtin = @import("builtin");
const sio = @import("sio");
const CompileOptions = @import("types.zig").CompileOptions;
const TestCommandOptions = @import("types.zig").TestCommandOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const affected_tests = @import("../affected_tests.zig");
const loadSource = @import("compile.zig").loadSource;
const sab = @import("../sab.zig");
const test_meta = @import("../test_meta.zig");
const test_formatter = @import("../test_formatter.zig");
const compileSource = @import("compile.zig").compileSource;
const saStdArchivePath = @import("compile.zig").saStdArchivePath;
const printTrapReport = @import("errors.zig").printTrapReport;
const TmpWorkDir = @import("types.zig").TmpWorkDir;
const referee = @import("../referee.zig");
const projectRootFromSourcePath = @import("compile.zig").projectRootFromSourcePath;
const loadProjectContext = @import("compile.zig").loadProjectContext;
const referee_call = @import("../referee/call.zig");

pub fn executeTest(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    test_options: TestCommandOptions,
    stdout: anytype,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !u8 {
    if (!test_options.affected) return executeTestInner(allocator, source_path, compile_options, test_options, stdout, stderr, diagnostics_mode);

    // Level-1 whole-source pass cache (fast path for identical inputs).
    const src = sio.cwd().readFileAlloc(allocator, source_path, 1 << 24) catch {
        return executeTestInner(allocator, source_path, compile_options, test_options, stdout, stderr, diagnostics_mode);
    };
    defer allocator.free(src);
    const filt: ?[]const u8 = if (test_options.selection.include_filters.len > 0)
        test_options.selection.include_filters[0]
    else
        null;
    const digest = affected_tests.hashInput(src, filt);
    if (affected_tests.isCachedPass(digest)) {
        if (diagnostics_mode == .json) {
            try stdout.writeAll("{\"status\":\"ok\",\"affected\":{\"skipped\":true,\"reason\":\"source-pass-cache\"}}\n");
        } else {
            try stdout.writeAll("affected: unchanged since last pass; skipped\n");
        }
        return 0;
    }

    // Level-2: call-graph selective execution. Compile once to inspect functions,
    // compute changed set vs baseline, restrict selection.include_filters to
    // impacted tests, then run. On first baseline, run all selected tests.
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            var function_bodies = try collectFunctionBodyHashes(allocator, &owned.verified);
            defer freeFunctionBodyHashes(allocator, &function_bodies);

            var changed = std.array_list.Managed([]const u8).init(allocator);
            defer changed.deinit();
            const had_baseline = affected_tests.hasFunctionBaseline();
            var it = function_bodies.iterator();
            while (it.next()) |entry| {
                if (!had_baseline or affected_tests.functionChanged(entry.key_ptr.*, entry.value_ptr.*)) {
                    try changed.append(entry.key_ptr.*);
                }
            }

            // Build call edges from annotated stream.
            var callers = std.array_list.Managed([]const u8).init(allocator);
            defer callers.deinit();
            var callees = std.array_list.Managed([]const u8).init(allocator);
            defer {
                for (callees.items) |c| allocator.free(c);
                callees.deinit();
            }
            try collectCallEdges(allocator, &owned.verified, &callers, &callees);

            var rev = try affected_tests.buildReverseCallMap(allocator, callers.items, callees.items);
            defer {
                var rit = rev.iterator();
                while (rit.next()) |e| e.value_ptr.deinit();
                rev.deinit();
            }

            // Normalize changed names for reverse-graph lookup.
            var changed_norm = std.array_list.Managed([]const u8).init(allocator);
            defer changed_norm.deinit();
            for (changed.items) |c| try changed_norm.append(normalizeFnName(c));
            var impacted = try affected_tests.impactedFunctions(allocator, changed_norm.items, &rev);
            defer impacted.deinit();

            // Identify tests by function_sigs kind == test_func.
            var selected_names = std.array_list.Managed([]const u8).init(allocator);
            defer {
                for (selected_names.items) |n| allocator.free(n);
                selected_names.deinit();
            }
            var total_tests: usize = 0;
            for (owned.verified.function_sigs) |fs| {
                if (fs.kind != .test_func) continue;
                total_tests += 1;
                const display = common_signature.displayName(fs.kind, fs.name);
                const norm = normalizeFnName(fs.name);
                const keep = if (!had_baseline)
                    true
                else
                    impacted.contains(norm) or impacted.contains(display);
                if (keep) try selected_names.append(try allocator.dupe(u8, display));
            }

            if (diagnostics_mode == .json) {
                try stdout.writeAll("{\"status\":\"ok\",\"affected\":{");
                try stdout.print("\"had_baseline\":{s},\"changed_functions\":{d},\"selected_tests\":{d},\"total_tests\":{d}", .{
                    if (had_baseline) "true" else "false",
                    changed.items.len,
                    selected_names.items.len,
                    total_tests,
                });
                try stdout.writeAll("}}\n");
            } else {
                try stdout.print(
                    "affected: baseline={s} changed_fns={d} selected_tests={d}/{d}\n",
                    .{ if (had_baseline) "yes" else "no", changed.items.len, selected_names.items.len, total_tests },
                );
            }

            // Update baselines after analysis (whether or not tests pass, body hashes are current).
            var bit = function_bodies.iterator();
            while (bit.next()) |entry| {
                affected_tests.recordFunctionHash(entry.key_ptr.*, entry.value_ptr.*);
            }

            if (had_baseline and selected_names.items.len == 0) {
                affected_tests.recordPass(digest);
                if (diagnostics_mode != .json) try stdout.writeAll("affected: no impacted tests; skipped\n");
                return 0;
            }

            // Restrict filters to selected test names when we have a baseline.
            var effective = test_options;
            var owned_filters: []const []const u8 = &.{};
            defer if (owned_filters.len != 0) {
                for (owned_filters) |f| allocator.free(f);
                allocator.free(owned_filters);
            };
            if (had_baseline and selected_names.items.len > 0) {
                var filters = try allocator.alloc([]const u8, selected_names.items.len);
                for (selected_names.items, 0..) |n, idx| filters[idx] = try allocator.dupe(u8, n);
                owned_filters = filters;
                effective.selection.include_filters = owned_filters;
                effective.selection.exact = true;
            }

            const code = try executeTestInner(allocator, source_path, compile_options, effective, stdout, stderr, diagnostics_mode);
            if (code == 0) affected_tests.recordPass(digest);
            return code;
        },
    }
}

pub fn executeTestInner(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    test_options: TestCommandOptions,
    stdout: anytype,
    stderr: anytype,
    diagnostics_mode: DiagnosticsMode,
) !u8 {
    if (test_options.list and std.mem.endsWith(u8, source_path, ".sab")) {
        var test_list = try collectSabTestListFast(allocator, source_path);
        defer test_list.deinit(allocator);
        try test_formatter.writeList(stdout, test_list.tests, test_options.selection);
        return 0;
    }

    const std_archive_path = try saStdArchivePath(allocator);
    defer allocator.free(std_archive_path);

    var tmp = try TmpWorkDir.init();
    defer tmp.cleanup();

    const source_stem = sourceStem(source_path);
    const artifact_name = try std.fmt.allocPrint(allocator, "{s}.test.sa.bc", .{source_stem});
    defer allocator.free(artifact_name);
    const exe_name = try std.fmt.allocPrint(allocator, "{s}.test", .{source_stem});
    defer allocator.free(exe_name);

    const artifact_dir = try tmp.dir.realpathAlloc(allocator, ".");
    defer allocator.free(artifact_dir);

    const artifact_full_path = try std.fs.path.join(allocator, &.{ artifact_dir, artifact_name });
    defer allocator.free(artifact_full_path);
    const exe_full_path = try std.fs.path.join(allocator, &.{ artifact_dir, exe_name });
    defer allocator.free(exe_full_path);

    const project_root_owned = compile_options.project_root == null;
    const project_root = compile_options.project_root orelse try projectRootFromSourcePath(allocator, source_path);
    defer if (project_root_owned) allocator.free(project_root);
    var project_context = try loadProjectContext(allocator, project_root, compile_options.package_name);
    defer project_context.deinit(allocator);
    const cache_key: ?ProjectCacheKey = if (compile_options.incremental_cache)
        try computeProjectBuildKey(allocator, &project_context, project_root, source_path, "test", "", .test_cache, false, false, false, null, true, compile_options.offline, compile_options.dce, compile_options.default_immutable, compile_options.fast_math)
    else
        null;

    if (cache_key) |key| cached: {
        var cached_test_list = projectCacheReadTestMetadata(allocator, project_root, key) catch |err| {
            _ = @errorName(err);
            break :cached;
        };
        const hit = projectCacheHit(allocator, project_root, .test_cache, key, artifact_full_path, exe_full_path) catch |err| {
            cached_test_list.deinit(allocator);
            return err;
        };
        if (hit) {
            makeExecutable(exe_full_path) catch |err| {
                cached_test_list.deinit(allocator);
                return err;
            };
            if (test_options.list) {
                defer cached_test_list.deinit(allocator);
                try test_formatter.writeList(stdout, cached_test_list.tests, test_options.selection);
                return 0;
            }
            if (test_options.compile_only) {
                defer cached_test_list.deinit(allocator);
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(cached_test_list.tests),
                        cached_test_list.tests.len,
                    },
                );
                return 0;
            }
            var run_out_fw = sio.ForwardWriter(@TypeOf(stdout)).init(stdout);
            defer run_out_fw.writer().flush() catch {};
            var run_err_fw = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
            defer run_err_fw.writer().flush() catch {};
            return try test_runner.run(
                allocator,
                exe_full_path,
                tmp.dir,
                &cached_test_list,
                test_options.selection,
                test_options.trace_panic,
                compile_options.jobs,
                run_out_fw.writer(),
                run_err_fw.writer(),
            );
        }
        cached_test_list.deinit(allocator);
    }

    const test_total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    var effective_compile_options = compile_options;
    var sab_selected_test_list: ?test_meta.TestList = null;
    defer if (sab_selected_test_list) |*list| list.deinit(allocator);
    var selected_test_names: []const []const u8 = &.{};
    defer if (selected_test_names.len != 0) allocator.free(selected_test_names);

    if (std.mem.endsWith(u8, source_path, ".sab") and hasExplicitTestSelection(test_options.selection)) {
        sab_selected_test_list = try collectSabTestListFast(allocator, source_path);
        selected_test_names = try selectedTestNamesFromList(allocator, sab_selected_test_list.?, test_options.selection);
        effective_compile_options.sab_selected_test_names = selected_test_names;
        effective_compile_options.sab_skip_verify = test_options.compile_only;
    }

    const compile_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const compiled = try compileSource(allocator, source_path, effective_compile_options);
    const compile_ns = if (compile_start) |start| elapsedNs(start) else null;
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            rejectNpmBindsUnlessJs("sa test", &owned.flat, stderr) catch return 1;
            var compiled_test_list: ?test_meta.TestList = null;
            defer if (compiled_test_list) |*list| list.deinit(allocator);
            if (sab_selected_test_list == null) {
                compiled_test_list = try test_meta.collect(allocator, owned.verified.function_sigs);
            }
            const test_list = if (sab_selected_test_list) |*list| list else &compiled_test_list.?;
            if (test_options.list) {
                try test_formatter.writeList(stdout, test_list.tests, test_options.selection);
                return 0;
            }

            const has_explicit_test_selection = hasExplicitTestSelection(test_options.selection);
            if (selected_test_names.len == 0 and has_explicit_test_selection) {
                selected_test_names = try selectedTestNamesFromList(allocator, test_list.*, test_options.selection);
            }

            var link_inputs = std.array_list.Managed([]const u8).init(allocator);
            defer link_inputs.deinit();
            var owned_link_inputs = std.array_list.Managed([]const u8).init(allocator);
            defer {
                for (owned_link_inputs.items) |arg| allocator.free(arg);
                owned_link_inputs.deinit();
            }
            if (!try appendNativePluginLinkInputs(allocator, &link_inputs, &owned_link_inputs, &owned.verified, stderr)) return 1;

            const emit_std_root = try stdRootFromEnv(allocator);
            defer allocator.free(emit_std_root);
            const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            emit_llvm_llvmc.emitLlvmcToFile(allocator, owned.verified, &owned.flat.def_dict, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .jobs = compile_options.jobs, .test_mode = true, .dce = compile_options.dce, .fast_math = compile_options.fast_math, .std_root = emit_std_root, .selected_test_names = selected_test_names }, artifact_full_path) catch |err| {
                try printLlvmcEmitError(stderr, err, diagnostics_mode);
                return 1;
            };
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;

            const fast_sab_compile_only = test_options.compile_only and std.mem.endsWith(u8, source_path, ".sab") and has_explicit_test_selection;
            if (fast_sab_compile_only) {
                if (compile_options.profile) {
                    try stderr.print(
                        "profile test compile={d:.3}ms emit={d:.3}ms link=0.000ms total={d:.3}ms\n",
                        .{
                            @as(f64, @floatFromInt(compile_ns orelse 0)) / 1_000_000.0,
                            @as(f64, @floatFromInt(emit_ns orelse 0)) / 1_000_000.0,
                            @as(f64, @floatFromInt(if (test_total_start) |start| elapsedNs(start) else 0)) / 1_000_000.0,
                        },
                    );
                }
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(test_list.tests),
                        test_list.tests.len,
                    },
                );
                return 0;
            }

            const link_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            driver.compileExe(allocator, artifact_full_path, exe_full_path, test_options.optimization, std_archive_path, link_inputs.items, false, stderr, null) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            const link_ns = if (link_start) |start| elapsedNs(start) else null;
            if (compile_options.profile) {
                try stderr.print(
                    "profile test compile={d:.3}ms emit={d:.3}ms link={d:.3}ms total={d:.3}ms\n",
                    .{
                        @as(f64, @floatFromInt(compile_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(emit_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(link_ns orelse 0)) / 1_000_000.0,
                        @as(f64, @floatFromInt(if (test_total_start) |start| elapsedNs(start) else 0)) / 1_000_000.0,
                    },
                );
            }

            if (cache_key) |key| {
                if (!has_explicit_test_selection and link_inputs.items.len == 0) try projectCacheStoreTest(allocator, project_root, key, artifact_full_path, exe_full_path, test_list.*);
            }

            if (test_options.compile_only) {
                try stdout.print(
                    "compiled {d} selected tests ({d} discovered)\n",
                    .{
                        test_options.selection.countSelected(test_list.tests),
                        test_list.tests.len,
                    },
                );
                return 0;
            }

            if (sab_selected_test_list) |list| {
                var run_list = list;
                sab_selected_test_list = null;
                var run_out_fw = sio.ForwardWriter(@TypeOf(stdout)).init(stdout);
                defer run_out_fw.writer().flush() catch {};
                var run_err_fw = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
                defer run_err_fw.writer().flush() catch {};
                return try test_runner.run(
                    allocator,
                    exe_full_path,
                    tmp.dir,
                    &run_list,
                    test_options.selection,
                    test_options.trace_panic,
                    compile_options.jobs,
                    run_out_fw.writer(),
                    run_err_fw.writer(),
                );
            } else {
                var run_list = compiled_test_list.?;
                compiled_test_list = null;
                var run_out_fw = sio.ForwardWriter(@TypeOf(stdout)).init(stdout);
                defer run_out_fw.writer().flush() catch {};
                var run_err_fw = sio.ForwardWriter(@TypeOf(stderr)).init(stderr);
                defer run_err_fw.writer().flush() catch {};
                return try test_runner.run(
                    allocator,
                    exe_full_path,
                    tmp.dir,
                    &run_list,
                    test_options.selection,
                    test_options.trace_panic,
                    compile_options.jobs,
                    run_out_fw.writer(),
                    run_err_fw.writer(),
                );
            }
        },
    }
}

pub fn collectSabTestListFast(allocator: std.mem.Allocator, source_path: []const u8) !test_meta.TestList {
    const bytes = try loadSource(allocator, source_path);
    defer allocator.free(bytes);

    const function_sigs = try sab.decodeTestFunctionSigsOnly(allocator, bytes);
    defer {
        for (function_sigs) |*function_sig| function_sig.deinit(allocator);
        allocator.free(function_sigs);
    }

    return try test_meta.collect(allocator, function_sigs);
}

pub fn sourceStem(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, basename, '.') orelse return basename;
    return basename[0..dot];
}

pub fn collectFunctionBodyHashes(allocator: std.mem.Allocator, verified: *const referee.VerifyOk) !FunctionBodyHashMap {
    var map = FunctionBodyHashMap.init(allocator);
    errdefer freeFunctionBodyHashes(allocator, &map);
    var sig_index: usize = 0;
    var idx: usize = 0;
    while (idx < verified.annotated.len) : (idx += 1) {
        const item = verified.annotated[idx].base;
        switch (item.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                if (sig_index >= verified.function_sigs.len) break;
                const fs = verified.function_sigs[sig_index];
                sig_index += 1;
                var end = idx + 1;
                while (end < verified.annotated.len and switch (verified.annotated[end].base.kind) {
                    .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => false,
                    else => true,
                }) : (end += 1) {}
                var lines = std.array_list.Managed([]const u8).init(allocator);
                defer lines.deinit();
                var j = idx;
                while (j < end) : (j += 1) try lines.append(verified.annotated[j].base.raw_text);
                const digest = affected_tests.hashFunctionBody(fs.name, lines.items);
                const key = try allocator.dupe(u8, fs.name);
                try map.put(key, digest);
                idx = end - 1;
            },
            else => {},
        }
    }
    return map;
}

pub fn freeFunctionBodyHashes(allocator: std.mem.Allocator, map: *FunctionBodyHashMap) void {
    var it = map.keyIterator();
    while (it.next()) |k| allocator.free(k.*);
    map.deinit();
}

pub const FunctionBodyHashMap = std.StringHashMap([32]u8);

pub fn collectCallEdges(
    allocator: std.mem.Allocator,
    verified: *const referee.VerifyOk,
    callers: *std.array_list.Managed([]const u8),
    callees: *std.array_list.Managed([]const u8),
) !void {
    var current_fn: ?[]const u8 = null;
    var sig_index: usize = 0;
    for (verified.annotated) |item| {
        switch (item.base.kind) {
            .func_decl, .ffi_wrapper_decl, .extern_decl, .export_decl, .test_decl, .gpu_decl => {
                if (sig_index >= verified.function_sigs.len) break;
                current_fn = verified.function_sigs[sig_index].name;
                sig_index += 1;
            },
            .call, .call_indirect => {
                const caller = current_fn orelse continue;
                var parsed = referee_call.parseCall(allocator, item.base.raw_text) catch continue;
                defer parsed.deinit(allocator);
                try callers.append(normalizeFnName(caller));
                const callee_owned = try allocator.dupe(u8, normalizeFnName(parsed.callee));
                try callees.append(callee_owned);
            },
            else => {},
        }
    }
}

pub fn normalizeFnName(name: []const u8) []const u8 {
    var s = name;
    if (s.len > 0 and s[0] == '@') s = s[1..];
    // Strip signature tail: `@foo() -> i32:` / `foo():` -> foo / display text
    if (std.mem.indexOfScalar(u8, s, '(')) |paren| s = s[0..paren];
    if (std.mem.indexOfScalar(u8, s, '"')) |q1| {
        if (std.mem.indexOfScalar(u8, s[q1 + 1 ..], '"')) |q2| {
            return s[q1 + 1 .. q1 + 1 + q2];
        }
    }
    return s;
}

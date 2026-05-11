const std = @import("std");

const flattener = @import("flattener.zig");
const interp = @import("interp.zig");
const emit_llvm = @import("emit_llvm.zig");
const referee = @import("referee.zig");
const trap = @import("common/trap.zig");

const CompileOk = struct {
    flat: flattener.FlattenResult,
    verified: referee.VerifyOk,

    fn deinit(self: *CompileOk, allocator: std.mem.Allocator) void {
        self.verified.deinit(allocator);
        self.flat.deinit(allocator);
        self.* = undefined;
    }
};

const CompileResult = union(enum) {
    ok: CompileOk,
    trap: trap.TrapReport,
};

const Command = enum {
    run,
    build_exe,
    build_wasm,
    build_obj,
};

const WasmTarget = struct {
    triple: []const u8,
    no_entry: bool,
    size_bits: u16,
};

fn nativeSizeBits() u16 {
    return @as(u16, @bitSizeOf(usize));
}

fn commandName(cmd: Command) []const u8 {
    return switch (cmd) {
        .run => "run",
        .build_exe => "build-exe",
        .build_wasm => "build-wasm",
        .build_obj => "build-obj",
    };
}

fn printTrapReport(report: trap.TrapReport) !void {
    const stderr = std.io.getStdErr().writer();
    try trap.writeJson(stderr, report);
    try stderr.writeByte('\n');
}

fn trapFromFlattenError(source: []const u8, err: anyerror) trap.TrapReport {
    const forbidden = flattener.findFirstForbiddenLine(source);
    return switch (err) {
        error.ForbiddenSyntax => .{
            .trap = .forbidden_syntax,
            .line = if (forbidden) |hit| hit.line_no else 1,
            .source_line = if (forbidden) |hit| hit.line_no else 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "forbidden syntax detected during flattening",
            .hint = null,
        },
        error.DuplicateDef => .{
            .trap = .duplicate_def,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "duplicate definition detected during flattening",
            .hint = null,
        },
        error.MacroRecursionLimit => .{
            .trap = .macro_recursion_limit,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "macro recursion limit exceeded",
            .hint = null,
        },
        error.InvalidMacroInvocation, error.InvalidMacroDefinitionContext, error.UnbalancedMacro, error.UnbalancedRep, error.InvalidSyntax => .{
            .trap = .forbidden_syntax,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = null,
        },
        else => .{
            .trap = .forbidden_syntax,
            .line = 1,
            .source_line = 1,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = null,
        },
    };
}

fn loadSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn compileSource(allocator: std.mem.Allocator, source_path: []const u8) !CompileResult {
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);

    var flat = flattener.flatten(allocator, source) catch |err| {
        return .{ .trap = trapFromFlattenError(source, err) };
    };
    errdefer flat.deinit(allocator);

    const verified = try referee.verify(allocator, flat.instructions);
    return switch (verified) {
        .ok => |ok| .{ .ok = .{ .flat = flat, .verified = ok } },
        .trap => |report| {
            flat.deinit(allocator);
            return .{ .trap = report };
        },
    };
}

fn sourceStem(path: []const u8) []const u8 {
    const basename = std.fs.path.basename(path);
    const dot = std.mem.lastIndexOfScalar(u8, basename, '.') orelse return basename;
    return basename[0..dot];
}

fn deriveOutputPath(allocator: std.mem.Allocator, source_path: []const u8, suffix: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = sourceStem(source_path);
    if (dir) |parent| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ parent, stem, suffix });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeAllFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn runZigCc(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stdout);
    if (result.stderr.len != 0) {
        try std.io.getStdErr().writeAll(result.stderr);
    }
    if (result.term != .Exited or result.term.Exited != 0) {
        return error.ChildProcessFailed;
    }
    return try allocator.dupe(u8, "");
}

fn zigCcCompile(allocator: std.mem.Allocator, ll_path: []const u8, out_path: []const u8, is_object: bool) !void {
    const argv: []const []const u8 = if (is_object)
        &[_][]const u8{ "zig", "cc", "-O3", "-c", ll_path, "-o", out_path }
    else
        &[_][]const u8{ "zig", "cc", "-O3", ll_path, "-o", out_path };

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stderr.len != 0) {
        try std.io.getStdErr().writeAll(result.stderr);
    }

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.ChildProcessFailed;
        },
        else => return error.ChildProcessFailed,
    }
}

fn executeRun(allocator: std.mem.Allocator, source_path: []const u8, argv: []const []const u8) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            return interp.run(allocator, &owned.verified, argv) catch |err| switch (err) {
                error.UserExit => 0,
                else => {
                    const stderr = std.io.getStdErr().writer();
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                    return 1;
                },
            };
        },
    }
}

fn executeBuildExe(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, nativeSizeBits());
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            try zigCcCompile(allocator, ll_path, out_path, false);
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, nativeSizeBits());
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            try zigCcCompile(allocator, ll_path, out_path, true);
            return 0;
        },
    }
}

fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, target.size_bits);
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            try zigCcCompileTarget(allocator, ll_path, out_path, false, target);
            return 0;
        },
    }
}

fn zigCcCompileTarget(allocator: std.mem.Allocator, ll_path: []const u8, out_path: []const u8, is_object: bool, target: WasmTarget) !void {
    const argv = if (is_object)
        if (target.no_entry)
            &[_][]const u8{ "zig", "cc", "-target", target.triple, "-Wl,--no-entry", "-O3", "-c", ll_path, "-o", out_path }
        else
            &[_][]const u8{ "zig", "cc", "-target", target.triple, "-O3", "-c", ll_path, "-o", out_path }
    else if (target.no_entry)
        &[_][]const u8{ "zig", "cc", "-target", target.triple, "-Wl,--no-entry", "-O3", ll_path, "-o", out_path }
    else
        &[_][]const u8{ "zig", "cc", "-target", target.triple, "-O3", ll_path, "-o", out_path };

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = argv,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.stderr.len != 0) {
        try std.io.getStdErr().writeAll(result.stderr);
    }

    switch (result.term) {
        .Exited => |code| {
            if (code != 0) return error.ChildProcessFailed;
        },
        else => return error.ChildProcessFailed,
    }
}

fn parseTarget(text: []const u8) !WasmTarget {
    if (std.mem.eql(u8, text, "wasm32")) return .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
    if (std.mem.eql(u8, text, "wasm64")) return .{ .triple = "wasm64-freestanding", .no_entry = true, .size_bits = 64 };
    return error.InvalidTarget;
}

pub fn execute(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    if (argv.len < 2) {
        const stderr = std.io.getStdErr().writer();
        try stderr.print("usage: saasm <run|build-exe|build-wasm|build-obj> <file.saasm> [options]\n", .{});
        return 1;
    }

    const cmd: Command = blk: {
        if (std.mem.eql(u8, argv[1], commandName(.run))) break :blk .run;
        if (std.mem.eql(u8, argv[1], commandName(.build_exe))) break :blk .build_exe;
        if (std.mem.eql(u8, argv[1], commandName(.build_wasm))) break :blk .build_wasm;
        if (std.mem.eql(u8, argv[1], commandName(.build_obj))) break :blk .build_obj;
        return error.UnknownCommand;
    };

    if (argv.len < 3) return error.MissingSourcePath;
    const source_path = argv[2];

    switch (cmd) {
        .run => {
            return try executeRun(allocator, source_path, argv[3..]);
        },
        .build_exe => {
            var out_path: ?[]const u8 = null;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (std.mem.eql(u8, argv[i], "-o")) {
                    if (i + 1 >= argv.len) return error.MissingOutputPath;
                    out_path = argv[i + 1];
                    i += 1;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildExe(allocator, source_path, if (out_path) |p| p else owned_out);
        },
        .build_obj => {
            var out_path: ?[]const u8 = null;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (std.mem.eql(u8, argv[i], "-o")) {
                    if (i + 1 >= argv.len) return error.MissingOutputPath;
                    out_path = argv[i + 1];
                    i += 1;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, ".o");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildObj(allocator, source_path, if (out_path) |p| p else owned_out);
        },
        .build_wasm => {
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (std.mem.eql(u8, argv[i], "-o")) {
                    if (i + 1 >= argv.len) return error.MissingOutputPath;
                    out_path = argv[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--target")) {
                    if (i + 1 >= argv.len) return error.MissingTarget;
                    target = try parseTarget(argv[i + 1]);
                    i += 1;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, ".wasm");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildWasm(allocator, source_path, if (out_path) |p| p else owned_out, target);
        },
    }
}

const std = @import("std");

const flattener = @import("flattener.zig");
const interp = @import("interp.zig");
const driver = @import("driver/zigcc.zig");
const emit_llvm = @import("emit_llvm.zig");
const layout = @import("layout.zig");
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
    layout,
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
        .layout => "layout",
    };
}

fn printTrapReport(writer: anytype, report: trap.TrapReport) !void {
    try trap.writeJson(writer, report);
    try writer.writeByte('\n');
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll("usage: saasm <run|build-exe|build-wasm|build-obj|layout> ...\n");
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
        error.InvalidAtomicOrdering => .{
            .trap = .invalid_atomic_ordering,
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
            .message = "invalid atomic ordering",
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

    var flat = flattener.flattenFile(allocator, source_path, source) catch |err| {
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

fn executeRun(allocator: std.mem.Allocator, source_path: []const u8, argv: []const []const u8, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            return interp.run(allocator, &owned.verified, argv) catch |err| switch (err) {
                error.UserExit => 0,
                else => {
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                    return 1;
                },
            };
        },
    }
}

fn executeBuildExe(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            try driver.compileExe(allocator, ll_path, out_path, optimization);
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            try driver.compileObj(allocator, ll_path, out_path, optimization);
            return 0;
        },
    }
}

fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget, debug: bool, optimization: driver.Optimization, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            try driver.compileWasm(allocator, ll_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization);
            return 0;
        },
    }
}

fn executeLayout(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var name: ?[]const u8 = null;
    var fields: ?[]const u8 = null;
    var format: layout.LayoutFormat = .text;
    var target_bits: u16 = 64;

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--name")) {
            if (i + 1 >= args.len) return error.MissingLayoutName;
            name = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--fields")) {
            if (i + 1 >= args.len) return error.MissingLayoutFields;
            fields = args[i + 1];
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--format")) {
            if (i + 1 >= args.len) return error.MissingLayoutFormat;
            const value = args[i + 1];
            if (std.mem.eql(u8, value, "json")) {
                format = .json;
            } else if (std.mem.eql(u8, value, "text")) {
                format = .text;
            } else {
                return error.InvalidLayoutFormat;
            }
            i += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--target")) {
            if (i + 1 >= args.len) return error.MissingTarget;
            target_bits = try layout.parseTargetBits(args[i + 1]);
            i += 1;
            continue;
        }
        return error.UnexpectedArgument;
    }

    const layout_name = name orelse return error.MissingLayoutName;
    const layout_fields = fields orelse return error.MissingLayoutFields;
    var computed = try layout.compute(allocator, layout_name, layout_fields, target_bits);
    defer computed.deinit(allocator);

    switch (format) {
        .text => try layout.writeText(stdout, computed),
        .json => {
            try layout.writeJson(stdout, computed);
            try stdout.writeByte('\n');
        },
    }
    _ = stderr;
    return 0;
}

fn parseTarget(text: []const u8) !WasmTarget {
    if (std.mem.eql(u8, text, "wasm32")) return .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
    return error.InvalidTarget;
}

fn parseOptimizationFlag(arg: []const u8) ?driver.Optimization {
    if (std.mem.eql(u8, arg, "--release-fast")) return .release_fast;
    if (std.mem.eql(u8, arg, "--release-small")) return .release_small;
    return null;
}

pub fn executeWithWriters(allocator: std.mem.Allocator, argv: []const []const u8, stdout: anytype, stderr: anytype) !u8 {
    if (argv.len < 2) {
        try printUsage(stderr);
        return 1;
    }

    const cmd: Command = blk: {
        if (std.mem.eql(u8, argv[1], commandName(.run))) break :blk .run;
        if (std.mem.eql(u8, argv[1], commandName(.build_exe))) break :blk .build_exe;
        if (std.mem.eql(u8, argv[1], commandName(.build_wasm))) break :blk .build_wasm;
        if (std.mem.eql(u8, argv[1], commandName(.build_obj))) break :blk .build_obj;
        if (std.mem.eql(u8, argv[1], commandName(.layout))) break :blk .layout;
        return error.UnknownCommand;
    };

    switch (cmd) {
        .layout => {
            return try executeLayout(allocator, argv[2..], stdout, stderr);
        },
        .run => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            return try executeRun(allocator, source_path, argv[3..], stderr);
        },
        .build_exe => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (std.mem.eql(u8, argv[i], "-o")) {
                    if (i + 1 >= argv.len) return error.MissingOutputPath;
                    out_path = argv[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(argv[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, "");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildExe(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, stderr);
        },
        .build_obj => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (std.mem.eql(u8, argv[i], "-o")) {
                    if (i + 1 >= argv.len) return error.MissingOutputPath;
                    out_path = argv[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(argv[i])) |mode| {
                    optimization = mode;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const owned_out = if (out_path) |p| p else try deriveOutputPath(allocator, source_path, ".o");
            defer if (out_path == null) allocator.free(owned_out);
            return try executeBuildObj(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, stderr);
        },
        .build_wasm => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (std.mem.eql(u8, argv[i], "-o")) {
                    if (i + 1 >= argv.len) return error.MissingOutputPath;
                    out_path = argv[i + 1];
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "-g")) {
                    debug = true;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--no-debug")) {
                    debug = false;
                    continue;
                }
                if (parseOptimizationFlag(argv[i])) |mode| {
                    optimization = mode;
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
            return try executeBuildWasm(allocator, source_path, if (out_path) |p| p else owned_out, target, debug, optimization, stderr);
        },
    }
}

pub fn execute(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    return executeWithWriters(allocator, argv, std.io.getStdOut().writer(), std.io.getStdErr().writer());
}

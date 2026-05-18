const std = @import("std");
const builtin = @import("builtin");

const flattener = @import("flattener.zig");
const interp = @import("interp.zig");
const build_options = @import("build_options");
const driver = @import("driver/zigcc.zig");
const emit_llvm = @import("emit_llvm.zig");
const llvm2sa = @import("llvm2sa.zig");
const layout = @import("layout.zig");
const manifest = @import("pkg/manifest.zig");
const pkg_fetch = @import("pkg/fetch.zig");
const pkg_resolver = @import("pkg/resolver.zig");
const referee_call = @import("referee/call.zig");
const referee = @import("referee.zig");
const sax_cli = @import("sax/cli.zig");
const test_meta = @import("test_meta.zig");
const test_runner = @import("test_runner.zig");
const trap = @import("common/trap.zig");
const common_upstream = @import("common/upstream_loc.zig");
const db = @import("db/mod.zig");

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

const CompileOptions = struct {
    jobs: ?usize = null,
    offline: bool = false,
};

const Command = enum {
    run,
    build,
    build_exe,
    build_wasm,
    build_obj,
    llvm2sa,
    sax,
    audit,
    db,
    layout,
    fetch,
    test_cmd,
};

const ProjectTargetKind = enum {
    native,
    wasm32,
    wasm64,
};

const ProjectTarget = struct {
    kind: ProjectTargetKind,
    name: []const u8,
    output_suffix: []const u8,
    source_suffix: []const u8,
    wasm: ?WasmTarget = null,
    size_bits: u16,
};

const AuditHit = struct {
    capability: manifest.Capability,
    callee: []const u8,
    raw_text: []const u8,
    source_line: u32,
    upstream_loc: ?common_upstream.UpstreamLoc,
};

const PackageAudit = struct {
    identity: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    declared_grants: []const manifest.Capability,
    hits: std.ArrayList(AuditHit),
    requested_caps: std.ArrayList(manifest.Capability),
    risk_score: u8 = 100,
    approved_hash: ?[32]u8 = null,

    fn deinit(self: *PackageAudit, allocator: std.mem.Allocator) void {
        _ = allocator;
        self.hits.deinit();
        self.requested_caps.deinit();
        self.* = undefined;
    }
};

const AuditReport = struct {
    packages: std.ArrayList(PackageAudit),
    fn deinit(self: *AuditReport, allocator: std.mem.Allocator) void {
        for (self.packages.items) |*item| item.deinit(allocator);
        self.packages.deinit();
        self.* = undefined;
    }
};

const TemporaryApproval = struct {
    url: []const u8,
    ref: []const u8,
    source_sha256: [32]u8,
    grants: []const manifest.Capability,
};

const ProjectBuildOptions = struct {
    ci: bool = false,
    allow_unaudited_risks: bool = false,
    offline: bool = false,
    all_targets: bool = false,
    lock_only: bool = false,
    release_fast: bool = false,
    out_path: ?[]const u8 = null,
    jobs: ?usize = null,
};

const ProjectAuditOptions = struct {
    update_lock: bool = false,
    offline: bool = false,
    all_targets: bool = false,
    jobs: ?usize = null,
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
        .build => "build",
        .run => "run",
        .build_exe => "build-exe",
        .build_wasm => "build-wasm",
        .build_obj => "build-obj",
        .llvm2sa => "llvm2sa",
        .sax => "sax",
        .audit => "audit",
        .db => "db",
        .layout => "layout",
        .fetch => "fetch",
        .test_cmd => "test",
    };
}

fn printTrapReport(writer: anytype, report: trap.TrapReport) !void {
    const function_text = textOrBuf(report.function, report.function_buf[0..]);
    const register_text = textOrBuf(report.register, report.register_buf[0..]);
    var source_text_buf: [256]u8 = [_]u8{0} ** 256;
    copyTextBuf(&source_text_buf, reportText(report));
    const source_text = bufText(source_text_buf[0..]);
    try writer.print("error[{s}]: {s}\n", .{ trap.trapName(report.trap), report.message });
    if (function_text.len != 0) {
        try writer.print("  in function {s}\n", .{function_text});
    }
    try printUpstreamLocation(writer, report);
    if (source_text.len != 0) {
        if (report.source_line != 0) {
            if (report.line != 0 and report.line != report.source_line) {
                try writer.print("  line {d} (expanded {d}): {s}\n", .{ report.source_line, report.line, source_text });
            } else {
                try writer.print("  line {d}: {s}\n", .{ report.source_line, source_text });
            }
        } else {
            try writer.print("  source: {s}\n", .{source_text});
        }
    }
    if (register_text.len != 0) {
        try writer.print("  register: {s}\n", .{register_text});
    } else if (report.registers.len != 0) {
        try writer.writeAll("  registers:");
        for (report.registers) |name| {
            try writer.print(" {s}", .{name});
        }
        try writer.writeByte('\n');
    }
    try printMaskState(writer, report);
    if (report.hint) |hint| {
        try writer.print("  help: {s}\n", .{hint});
    }
    try trap.writeJson(writer, report);
    try writer.writeByte('\n');
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll("usage: saasm <run|build-exe|build-wasm|build-obj|llvm2sa|sax|layout|fetch|db|test> [--jobs auto|N] ...\n");
    try writer.writeAll("test flags: --filter <pattern> [--filter <pattern> ...] [--skip <pattern> ...] [--exact] [--ignored|--include-ignored]\n");
}

const TmpWorkDir = struct {
    dir: std.fs.Dir,
    parent_dir: std.fs.Dir,
    sub_path: [std.fs.base64_encoder.calcSize(12)]u8,

    fn init() !TmpWorkDir {
        var random_bytes: [12]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);

        var sub_path: [std.fs.base64_encoder.calcSize(12)]u8 = undefined;
        _ = std.fs.base64_encoder.encode(&sub_path, &random_bytes);

        const cwd = std.fs.cwd();
        var cache_dir = try cwd.makeOpenPath(".zig-cache", .{});
        defer cache_dir.close();
        var parent_dir = try cache_dir.makeOpenPath("tmp", .{});
        errdefer parent_dir.close();
        const dir = try parent_dir.makeOpenPath(&sub_path, .{});
        return .{ .dir = dir, .parent_dir = parent_dir, .sub_path = sub_path };
    }

    fn cleanup(self: *TmpWorkDir) void {
        self.dir.close();
        self.parent_dir.deleteTree(&self.sub_path) catch {};
        self.parent_dir.close();
        self.* = undefined;
    }
};

fn writeFile(dir: std.fs.Dir, path: []const u8, bytes: []const u8) !void {
    var file = try dir.createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn parseFetchArgs(
    allocator: std.mem.Allocator,
    args: []const []const u8,
) !struct { options: pkg_fetch.FetchOptions, identity: []const u8, ref: []const u8 } {
    var options: pkg_fetch.FetchOptions = .{};
    var identity: ?[]const u8 = null;
    var ref: []const u8 = "HEAD";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-g")) {
            options.global = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--offline")) {
            options.offline = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--ref")) {
            if (i + 1 >= args.len) return error.MissingRef;
            ref = args[i + 1];
            i += 1;
            continue;
        }
        if (identity == null) {
            identity = arg;
            continue;
        }
        return error.UnexpectedArgument;
    }

    const id = identity orelse return error.MissingSourcePath;
    _ = allocator;
    return .{ .options = options, .identity = id, .ref = ref };
}

fn forbiddenHint(hit: flattener.ForbiddenHit) []const u8 {
    return switch (hit.token) {
        .brace_open, .brace_close => "remove brace syntax and flatten the control flow into labels and jumps",
        .keyword_if, .keyword_else, .keyword_while, .keyword_for => "replace control-flow keywords with labels and jmp/br instructions",
        .property_chain => "replace dotted property access with explicit SSA registers or constant expansion",
    };
}

fn lineAt(source: []const u8, target_line: u32) ?[]const u8 {
    if (target_line == 0) return null;
    var iter = std.mem.splitScalar(u8, source, '\n');
    var line_no: u32 = 1;
    while (iter.next()) |line| : (line_no += 1) {
        if (line_no == target_line) return line;
    }
    return null;
}

fn sourceExcerpt(line: []const u8) []const u8 {
    return std.mem.trimRight(u8, line, "\r");
}

fn copyTextBuf(dest: []u8, text: []const u8) void {
    const len = @min(dest.len, text.len);
    std.mem.copyForwards(u8, dest[0..len], text[0..len]);
}

fn bufText(buf: []const u8) []const u8 {
    return buf[0..(std.mem.indexOfScalar(u8, buf, 0) orelse buf.len)];
}

fn textOrBuf(value: ?[]const u8, buf: []const u8) []const u8 {
    if (value) |text| return text;
    return bufText(buf);
}

fn reportText(report: trap.TrapReport) []const u8 {
    if (report.source_text) |text| return text;
    const source_fallback = bufText(report.source_text_buf[0..]);
    if (source_fallback.len != 0) return source_fallback;
    if (report.original_text) |text| return text;
    return bufText(report.original_text_buf[0..]);
}

fn printUpstreamLocation(writer: anytype, report: trap.TrapReport) !void {
    if (report.upstream_loc) |loc| {
        try writer.print("  upstream {s}:{d}:{d}\n", .{ loc.file, loc.line, loc.col });
        return;
    }

    const file = bufText(report.upstream_file_buf[0..]);
    if (file.len == 0) return;

    if (report.upstream_line != 0 and report.upstream_col != 0) {
        try writer.print("  upstream {s}:{d}:{d}\n", .{ file, report.upstream_line, report.upstream_col });
    } else if (report.upstream_line != 0) {
        try writer.print("  upstream {s}:{d}\n", .{ file, report.upstream_line });
    } else {
        try writer.print("  upstream {s}\n", .{file});
    }
}

fn printMaskState(writer: anytype, report: trap.TrapReport) !void {
    if (report.expected_mask_name) |expected| {
        if (report.actual_mask_name) |actual| {
            try writer.print("  state: expected {s}, actual {s}\n", .{ expected, actual });
            return;
        }
        try writer.print("  state: expected {s}\n", .{expected});
        return;
    }

    if (report.actual_mask_name) |actual| {
        try writer.print("  state: {s}\n", .{actual});
        return;
    }

    if (report.expected_mask) |expected| {
        if (report.actual_mask) |actual| {
            try writer.print("  state: expected {d}, actual {d}\n", .{ expected, actual });
            return;
        }
        try writer.print("  state: expected {d}\n", .{expected});
        return;
    }

    if (report.actual_mask) |actual| {
        try writer.print("  state: {d}\n", .{actual});
    }
}

fn trapFromFlattenError(source: []const u8, err: anyerror, last_line: ?u32) trap.TrapReport {
    const forbidden = flattener.findFirstForbiddenLine(source);
    const line_no = if (forbidden) |hit| hit.line_no else last_line orelse 1;
    const line_text = lineAt(source, line_no);
    const source_text_buf: [256]u8 = [_]u8{0} ** 256;
    const original_text_buf: [256]u8 = [_]u8{0} ** 256;
    var report: trap.TrapReport = switch (err) {
        error.ForbiddenSyntax => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "forbidden syntax detected during flattening",
            .hint = if (forbidden) |hit| forbiddenHint(hit.hit) else null,
        },
        error.UnsupportedType => .{
            .trap = .unsupported_type,
            .trap_code = trap.trapCode(.unsupported_type),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "unsupported type annotation during flattening",
            .hint = "check primitive type names in signatures and atomic suffixes",
        },
        error.OutOfMemory => .{
            .trap = .arena_oom,
            .trap_code = trap.trapCode(.arena_oom),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "out of memory while flattening",
            .hint = null,
        },
        error.ImportCycle => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = "import cycle detected during flattening",
            .hint = "break the cycle in imported files or inline the shared definitions",
        },
        error.DuplicateDef => .{
            .trap = .duplicate_def,
            .trap_code = trap.trapCode(.duplicate_def),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .trap_code = trap.trapCode(.macro_recursion_limit),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .trap_code = trap.trapCode(.invalid_atomic_ordering),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
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
            .trap_code = trap.trapCode(.forbidden_syntax),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = switch (err) {
                error.InvalidMacroInvocation => "check the macro name, argument count, and comma-separated expansion syntax",
                error.InvalidMacroDefinitionContext => "macro definitions are only allowed at top level",
                error.UnbalancedMacro => "make sure [MACRO] has a matching [END_MACRO]",
                error.UnbalancedRep => "make sure [REP] has a matching [END_REP]",
                error.InvalidSyntax => "check the flattened line syntax and operand ordering",
                else => null,
            },
        },
        else => .{
            .trap = .forbidden_syntax,
            .trap_code = trap.trapCode(.forbidden_syntax),
            .line = line_no,
            .source_line = line_no,
            .source_text_buf = source_text_buf,
            .original_text_buf = original_text_buf,
            .source_text = null,
            .original_text = null,
            .register = null,
            .registers = &.{},
            .expected_mask = null,
            .actual_mask = null,
            .expected_mask_name = null,
            .actual_mask_name = null,
            .function = null,
            .is_ffi_wrapper = null,
            .message = @errorName(err),
            .hint = "flattening failed before a public trap mapping was available",
        },
    };
    if (line_text) |line| {
        const excerpt = sourceExcerpt(line);
        copyTextBuf(&report.source_text_buf, excerpt);
        copyTextBuf(&report.original_text_buf, excerpt);
    }
    return report;
}

fn parseJobsValue(text: []const u8) !?usize {
    if (std.mem.eql(u8, text, "auto")) return null;
    const jobs = std.fmt.parseInt(usize, text, 10) catch return error.InvalidJobs;
    if (jobs == 0) return error.InvalidJobs;
    return jobs;
}

fn consumeJobsOption(arg: []const u8, args: []const []const u8, index: *usize, options: *CompileOptions) !bool {
    if (!std.mem.eql(u8, arg, "--jobs")) return false;
    if (index.* + 1 >= args.len) return error.MissingJobs;
    options.jobs = try parseJobsValue(args[index.* + 1]);
    index.* += 1;
    return true;
}

fn loadSource(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn projectRootFromSourcePath(source_path: []const u8) []const u8 {
    return std.fs.path.dirname(source_path) orelse ".";
}

fn readProjectManifest(allocator: std.mem.Allocator, source_path: []const u8) !?manifest.Manifest {
    const project_root = projectRootFromSourcePath(source_path);
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "sa.mod" });
    defer allocator.free(manifest_path);

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(source);
    return try manifest.parseManifestWithFile(allocator, source, manifest_path);
}

fn manifestDependencies(manifest_file: *const manifest.Manifest, allocator: std.mem.Allocator) ![]pkg_resolver.Dependency {
    var deps = std.ArrayList(pkg_resolver.Dependency).init(allocator);
    errdefer deps.deinit();

    for (manifest_file.requires) |entry| {
        try deps.append(.{
            .url = entry.url,
            .ref = entry.ref,
        });
    }

    return try deps.toOwnedSlice();
}

fn compileSource(allocator: std.mem.Allocator, source_path: []const u8, options: CompileOptions) !CompileResult {
    const source = try loadSource(allocator, source_path);
    defer allocator.free(source);

    var project_manifest = try readProjectManifest(allocator, source_path);
    defer if (project_manifest) |*m| m.deinit(allocator);

    var dependency_slice: []pkg_resolver.Dependency = &.{};
    defer if (dependency_slice.len != 0) allocator.free(dependency_slice);

    if (project_manifest) |*m| {
        dependency_slice = try manifestDependencies(m, allocator);
    }

    const package_grants: []const manifest.RequireEntry = if (project_manifest) |*m| m.requires else &.{};

    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .dependencies = dependency_slice,
        .options = .{
            .project_root = projectRootFromSourcePath(source_path),
        },
    };
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source, err, flattener.takeErrorSourceLine(&error_ctx)) };
    };
    errdefer flat.deinit(allocator);

    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .jobs = options.jobs, .package_grants = package_grants });
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

fn executeRun(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    argv: []const []const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            return interp.runWithWriters(allocator, &owned.verified, argv, stdout.any(), stderr.any()) catch |err| switch (err) {
                error.UserExit => 0,
                else => {
                    try stderr.print("error: {s}\n", .{@errorName(err)});
                    return 1;
                },
            };
        },
    }
}

fn executeBuildExe(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            driver.compileExe(allocator, ll_path, out_path, optimization, build_options.sa_std_archive_path, debug, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            return 0;
        },
    }
}

fn executeBuildObj(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, owned.flat.loc_table, source_path, nativeSizeBits(), .{ .debug = debug, .jobs = compile_options.jobs });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            driver.compileObj(allocator, ll_path, out_path, optimization, debug, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            return 0;
        },
    }
}

fn executeBuildWasm(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, target: WasmTarget, debug: bool, optimization: driver.Optimization, compile_options: CompileOptions, stderr: anytype) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            const ll = try emit_llvm.emitLlvm(allocator, owned.verified, owned.flat.loc_table, source_path, target.size_bits, .{ .debug = debug, .wasm_compat = true, .jobs = compile_options.jobs });
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);
            try writeAllFile(ll_path, ll);

            driver.compileWasm(allocator, ll_path, out_path, .{ .triple = target.triple, .no_entry = target.no_entry }, optimization, debug, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
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
    if (std.mem.eql(u8, text, "wasm64")) return .{ .triple = "wasm64-freestanding", .no_entry = true, .size_bits = 64 };
    return error.InvalidTarget;
}

fn parseOptimizationFlag(arg: []const u8) ?driver.Optimization {
    if (std.mem.eql(u8, arg, "--release-fast")) return .release_fast;
    if (std.mem.eql(u8, arg, "--release-small")) return .release_small;
    return null;
}

fn executeTest(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    compile_options: CompileOptions,
    selection: test_meta.TestSelection,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);

            const ll = try emit_llvm.emitLlvm(
                allocator,
                owned.verified,
                owned.flat.loc_table,
                source_path,
                nativeSizeBits(),
                .{ .jobs = compile_options.jobs, .test_mode = true },
            );
            defer allocator.free(ll);

            var tmp = try TmpWorkDir.init();
            defer tmp.cleanup();

            const source_stem = sourceStem(source_path);
            const ll_name = try std.fmt.allocPrint(allocator, "{s}.test.saasm.ll", .{source_stem});
            defer allocator.free(ll_name);
            const exe_name = try std.fmt.allocPrint(allocator, "{s}.test", .{source_stem});
            defer allocator.free(exe_name);

            const ll_path = try tmp.dir.realpathAlloc(allocator, ".");
            defer allocator.free(ll_path);

            const ll_full_path = try std.fs.path.join(allocator, &.{ ll_path, ll_name });
            defer allocator.free(ll_full_path);
            try writeFile(tmp.dir, ll_name, ll);

            const exe_full_path = try std.fs.path.join(allocator, &.{ ll_path, exe_name });
            defer allocator.free(exe_full_path);

            driver.compileExe(allocator, ll_full_path, exe_full_path, .release_small, build_options.sa_std_archive_path, false, stderr) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };

            var test_list = try test_meta.collect(allocator, owned.verified.function_sigs);
            return try test_runner.run(
                allocator,
                exe_full_path,
                tmp.dir,
                &test_list,
                selection,
                compile_options.jobs,
                stdout.any(),
                stderr.any(),
            );
        },
    }
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
        if (std.mem.eql(u8, argv[1], commandName(.llvm2sa))) break :blk .llvm2sa;
        if (std.mem.eql(u8, argv[1], commandName(.layout))) break :blk .layout;
        if (std.mem.eql(u8, argv[1], commandName(.fetch))) break :blk .fetch;
        if (std.mem.eql(u8, argv[1], "db")) break :blk .db;
        if (std.mem.eql(u8, argv[1], commandName(.test_cmd))) break :blk .test_cmd;
        return error.UnknownCommand;
    };

    switch (cmd) {
        .layout => {
            return try executeLayout(allocator, argv[2..], stdout, stderr);
        },
        .build => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (try consumeJobsOption(argv[i], argv, &i, &compile_options)) continue;
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
            return try executeBuildExe(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr);
        },
        .sax => {
            if (argv.len < 3) return error.MissingSourcePath;
            const sub = argv[2];
            if (sax_cli.parseSaxCommand(sub)) |sax_cmd| {
                switch (sax_cmd) {
                    .build => {
                        const sax_file = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxBuild(allocator, sax_file, null, stdout, stderr);
                    },
                    .check => {
                        const sax_file = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxCheck(allocator, sax_file, stdout, stderr);
                    },
                    .dev => {
                        const sax_file = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxDev(allocator, sax_file, 8080, stdout, stderr);
                    },
                    .new_project => {
                        const project_name = if (argv.len >= 4) argv[3] else return error.MissingSourcePath;
                        return try sax_cli.executeSaxNew(allocator, project_name, stdout, stderr);
                    },
                }
            }
            return error.UnknownCommand;
        },
        .fetch => {
            const parsed = try parseFetchArgs(allocator, argv[2..]);
            var result = try pkg_fetch.fetchPackage(allocator, parsed.identity, parsed.ref, parsed.options);
            defer result.deinit(allocator);
            try stdout.print("{s}\n", .{result.root});
            return 0;
        },
        .audit => {
            const audit_argv = argv[2..];
            if (audit_argv.len == 0) return error.MissingSourcePath;
            const source_path = audit_argv[0];
            const source = try loadSource(allocator, source_path);
            defer allocator.free(source);
            try stdout.print("audit: {s}\n", .{source_path});
            try stdout.print("size: {d}\n", .{source.len});
            return 0;
        },
        .db => {
            if (argv.len < 3) return error.UnknownCommand;
            const sub = argv[2];
            if (std.mem.eql(u8, sub, "init")) {
                if (argv.len < 4) return error.MissingSourcePath;
                const iface = try db.exec.compileSchema(allocator, argv[3]);
                defer allocator.free(iface);
                try stdout.writeAll(iface);
                return 0;
            }
            if (std.mem.eql(u8, sub, "register")) {
                if (argv.len < 4) return error.MissingSourcePath;
                const source_path = argv[3];
                const project_root = std.fs.path.dirname(source_path) orelse ".";
                var result = try db.exec.registerQuery(allocator, source_path, project_root);
                defer result.deinit(allocator);
                const hex = std.fmt.bytesToHex(result.hash, .lower);
                try stdout.print("Compiled: {s}\n", .{source_path});
                try stdout.print("Hash: {s}\n", .{hex[0..]});
                try stdout.print("Registered: {s}\n", .{std.fs.path.basename(result.qmod_path)});
                return 0;
            }
            if (std.mem.eql(u8, sub, "inspect")) {
                if (argv.len < 4) return error.MissingSourcePath;
                const report = try db.exec.inspectRegistry(allocator, ".", argv[3]);
                defer allocator.free(report);
                try stdout.writeAll(report);
                return 0;
            }
            if (std.mem.eql(u8, sub, "exec")) {
                if (argv.len < 4) return error.MissingSourcePath;
                var params_path: ?[]const u8 = null;
                var i: usize = 4;
                while (i < argv.len) : (i += 1) {
                    if (std.mem.eql(u8, argv[i], "--params")) {
                        if (i + 1 >= argv.len) return error.MissingSourcePath;
                        params_path = argv[i + 1];
                        i += 1;
                        continue;
                    }
                    if (params_path == null) {
                        params_path = argv[i];
                        continue;
                    }
                    return error.UnexpectedArgument;
                }
                const hash_hex = argv[3];
                const registry_info = db.exec.inspectRegistry(allocator, ".", hash_hex) catch |err| switch (err) {
                    error.FileNotFound => {
                        try printTrapReport(stderr, db.exec.trapUnknownHash());
                        return 1;
                    },
                    else => return err,
                };
                defer allocator.free(registry_info);
                if (params_path) |p| {
                    const params = try loadSource(allocator, p);
                    defer allocator.free(params);
                }
                try stdout.writeAll(registry_info);
                return 0;
            }
            return error.UnknownCommand;
        },
        .run => {
            if (argv.len < 3) return error.MissingSourcePath;
            var compile_options: CompileOptions = .{};
            var source_path: ?[]const u8 = null;
            var runtime_args = std.ArrayList([]const u8).init(allocator);
            defer runtime_args.deinit();

            var i: usize = 2;
            while (i < argv.len) : (i += 1) {
                if (try consumeJobsOption(argv[i], argv, &i, &compile_options)) continue;
                if (source_path == null) {
                    source_path = argv[i];
                    continue;
                }
                try runtime_args.append(argv[i]);
            }
            const source = source_path orelse return error.MissingSourcePath;
            return try executeRun(allocator, source, compile_options, runtime_args.items, stdout, stderr);
        },
        .build_exe => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (try consumeJobsOption(argv[i], argv, &i, &compile_options)) continue;
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
            return try executeBuildExe(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr);
        },
        .build_obj => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (try consumeJobsOption(argv[i], argv, &i, &compile_options)) continue;
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
            return try executeBuildObj(allocator, source_path, if (out_path) |p| p else owned_out, debug, optimization, compile_options, stderr);
        },
        .llvm2sa => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            const translated = try llvm2sa.translateFile(allocator, source_path);
            defer allocator.free(translated);
            try stdout.writeAll(translated);
            if (translated.len == 0 or translated[translated.len - 1] != '\n') try stdout.writeByte('\n');
            return 0;
        },
        .build_wasm => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var compile_options: CompileOptions = .{};
            var out_path: ?[]const u8 = null;
            var target: WasmTarget = .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
            var debug = false;
            var optimization: driver.Optimization = .release_small;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (try consumeJobsOption(argv[i], argv, &i, &compile_options)) continue;
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
            return try executeBuildWasm(allocator, source_path, if (out_path) |p| p else owned_out, target, debug, optimization, compile_options, stderr);
        },
        .test_cmd => {
            if (argv.len < 3) return error.MissingSourcePath;
            const source_path = argv[2];
            var compile_options: CompileOptions = .{};
            var include_filters = std.ArrayList([]const u8).init(allocator);
            defer include_filters.deinit();
            var skip_filters = std.ArrayList([]const u8).init(allocator);
            defer skip_filters.deinit();
            var exact = false;
            var run_ignored = test_meta.RunIgnored.normal;
            var i: usize = 3;
            while (i < argv.len) : (i += 1) {
                if (try consumeJobsOption(argv[i], argv, &i, &compile_options)) continue;
                if (std.mem.eql(u8, argv[i], "--filter")) {
                    if (i + 1 >= argv.len) return error.MissingFilterValue;
                    try include_filters.append(argv[i + 1]);
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--skip")) {
                    if (i + 1 >= argv.len) return error.MissingFilterValue;
                    try skip_filters.append(argv[i + 1]);
                    i += 1;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--exact")) {
                    exact = true;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--ignored")) {
                    run_ignored = .only;
                    continue;
                }
                if (std.mem.eql(u8, argv[i], "--include-ignored")) {
                    run_ignored = .include;
                    continue;
                }
                return error.UnexpectedArgument;
            }
            const selection = test_meta.TestSelection{
                .include_filters = include_filters.items,
                .skip_filters = skip_filters.items,
                .exact = exact,
                .ignored = run_ignored,
            };
            return try executeTest(allocator, source_path, compile_options, selection, stdout, stderr);
        },
    }
}

pub fn execute(allocator: std.mem.Allocator, argv: []const []const u8) !u8 {
    return executeWithWriters(allocator, argv, std.io.getStdOut().writer(), std.io.getStdErr().writer());
}

test "trap reports print a human summary and preserve json payload" {
    var list = std.ArrayList(u8).init(std.testing.allocator);
    defer list.deinit();

    var report = trap.TrapReport{
        .trap = .memory_leak,
        .trap_code = trap.trapCode(.memory_leak),
        .line = 12,
        .source_line = 9,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register_buf = [_]u8{0} ** 64,
        .register = null,
        .registers = &.{},
        .expected_mask = null,
        .actual_mask = 1,
        .expected_mask_name = null,
        .actual_mask_name = "Active",
        .upstream_loc = null,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = 42,
        .upstream_col = 7,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = false,
        .message = "live registers remain at function exit",
        .hint = "insert explicit release",
    };
    const source = "result = load node+0 as i32";
    std.mem.copyForwards(u8, report.source_text_buf[0..source.len], source);
    const register = "r1";
    std.mem.copyForwards(u8, report.register_buf[0..register.len], register);
    const upstream_file = "main.rs";
    std.mem.copyForwards(u8, report.upstream_file_buf[0..upstream_file.len], upstream_file);
    const function = "@main() -> i32:";
    std.mem.copyForwards(u8, report.function_buf[0..function.len], function);

    try printTrapReport(list.writer(), report);
    const output = list.items;

    try std.testing.expect(std.mem.indexOf(u8, output, "error[MemoryLeak]: live registers remain at function exit") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  in function @main() -> i32:") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  upstream main.rs:42:7") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  line 9 (expanded 12): result = load node+0 as i32") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  register: r1") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  state: Active") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "  help: insert explicit release") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"trap\":\"MemoryLeak\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"function\":\"@main() -> i32:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"register\":\"r1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, output, "\"hint\":\"insert explicit release\"") != null);
}

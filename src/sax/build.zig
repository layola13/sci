const std = @import("std");

const driver = @import("../driver/zigcc.zig");
const emit_llvm = @import("../emit_llvm.zig");
const flattener = @import("../flattener.zig");
const manifest = @import("../pkg/manifest.zig");
const pkg_resolver = @import("../pkg/resolver.zig");
const referee = @import("../referee.zig");
const trap = @import("../common/trap.zig");

pub const CompileOptions = struct {
    jobs: ?usize = null,
};

pub const CompileOk = struct {
    flat: flattener.FlattenResult,
    verified: referee.VerifyOk,

    pub fn deinit(self: *CompileOk, allocator: std.mem.Allocator) void {
        self.verified.deinit(allocator);
        self.flat.deinit(allocator);
        self.* = undefined;
    }
};

pub const CompileResult = union(enum) {
    ok: CompileOk,
    trap: trap.TrapReport,
};

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

pub fn printTrapReport(writer: anytype, report: trap.TrapReport) !void {
    try writer.print("error[{s}]: {s}\n", .{ trap.trapName(report.trap), report.message });
    if (report.source_line != 0) {
        const source_text = bufText(report.source_text_buf[0..]);
        if (source_text.len != 0) {
            try writer.print("  line {d}: {s}\n", .{ report.source_line, source_text });
        } else {
            try writer.print("  line {d}\n", .{report.source_line});
        }
    }
    if (report.hint) |hint| {
        try writer.print("  help: {s}\n", .{hint});
    }
    try trap.writeJson(writer, report);
    try writer.writeByte('\n');
}

fn trapFromFlattenError(source: []const u8, err: anyerror, last_line: ?u32) trap.TrapReport {
    const line_no = last_line orelse 1;
    const line_text = lineAt(source, line_no);
    const source_text_buf: [256]u8 = [_]u8{0} ** 256;
    const original_text_buf: [256]u8 = [_]u8{0} ** 256;
    var report: trap.TrapReport = .{
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
        .upstream_loc = null,
        .upstream_file_buf = [_]u8{0} ** 128,
        .upstream_line = 0,
        .upstream_col = 0,
        .function_buf = [_]u8{0} ** 64,
        .function = null,
        .is_ffi_wrapper = null,
        .message = @errorName(err),
        .hint = null,
    };
    if (line_text) |line| {
        const excerpt = sourceExcerpt(line);
        copyTextBuf(&report.source_text_buf, excerpt);
        copyTextBuf(&report.original_text_buf, excerpt);
    }
    return report;
}

pub fn compileSourceText(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_text: []const u8,
    options: CompileOptions,
) !CompileResult {
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
    var flat = flattener.flattenFileWithContextAndPackages(allocator, source_path, source_text, &error_ctx, resolve_ctx) catch |err| {
        return .{ .trap = trapFromFlattenError(source_text, err, flattener.takeErrorSourceLine(&error_ctx)) };
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

pub fn buildBrowserWasmFromSourceText(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source_text: []const u8,
    out_path: []const u8,
    debug: bool,
    optimization: driver.Optimization,
    options: CompileOptions,
    stderr: anytype,
) !u8 {
    const compiled = try compileSourceText(allocator, source_path, source_text, options);
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
                32,
                .{ .debug = debug, .wasm_compat = true, .jobs = options.jobs },
            );
            defer allocator.free(ll);

            const ll_path = try std.fmt.allocPrint(allocator, "{s}.saasm.ll", .{out_path});
            defer allocator.free(ll_path);

            try ensureParentDir(ll_path);
            try writeAllFile(ll_path, ll);

            driver.compileWasm(
                allocator,
                ll_path,
                out_path,
                .{ .triple = "wasm32-freestanding", .no_entry = true },
                optimization,
                debug,
                stderr,
            ) catch |err| switch (err) {
                error.ChildProcessFailed => return 1,
                else => return err,
            };
            return 0;
        },
    }
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

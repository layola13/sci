const std = @import("std");
const flattener = @import("../flattener.zig");
const qmod = @import("qmod.zig");
const schema = @import("schema.zig");
const referee = @import("../referee.zig");
const interp = @import("../interp.zig");
const referee_db = @import("referee_db.zig");
const trap = @import("common/trap.zig");
const dbtrap = @import("trap_db.zig");
const root = @import("root");
const has_pkg_manifest = @hasDecl(root, "pkg_manifest");
const RealPkgManifest = @import("../pkg/manifest.zig");
const PkgManifest = if (has_pkg_manifest) @import("../pkg/manifest.zig") else struct {
    pub const Capability = enum(u8) {
        mem_alloc,
        mem_slice,
        io_read,
        io_write,
        net_tx,
        net_rx,
        proc_spawn,
        proc_exit,
        proc_args,
        time_now,
        rand_get,
    };

    pub const RequireEntry = struct {
        url: []const u8 = "",
        ref: []const u8 = "",
        source_sha256: [32]u8 = [_]u8{0} ** 32,
        grants: []const Capability = &.{},
        upstream_loc: struct {
            file: []const u8 = "",
            line: u32 = 0,
            col: u32 = 0,
        } = .{},
    };

    pub const Manifest = struct {
        requires: []RequireEntry = &.{},
        mirrors: []void = &.{},

        pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
            _ = allocator;
            self.* = undefined;
        }
    };

    pub fn parseManifestWithFile(_: std.mem.Allocator, _: []const u8, _: []const u8) !Manifest {
        return .{};
    }
};
const PkgResolver = @import("../pkg/resolver.zig");

pub const ExecError = error{
    OutOfMemory,
    InvalidFormat,
    InvalidPath,
    NotFound,
    DuplicateRegister,
};

pub const ExecResult = struct {
    hash: [32]u8,
    qmod_path: []u8,
    iface_path: []u8,
    registry_path: []u8,
    source_path: []u8,

    pub fn deinit(self: *ExecResult, allocator: std.mem.Allocator) void {
        allocator.free(self.qmod_path);
        allocator.free(self.iface_path);
        allocator.free(self.registry_path);
        allocator.free(self.source_path);
        self.* = undefined;
    }
};

pub const ExecRunResult = struct {
    code: u8,
    function_name: []u8,
    hash: [32]u8,

    pub fn deinit(self: *ExecRunResult, allocator: std.mem.Allocator) void {
        allocator.free(self.function_name);
        self.* = undefined;
    }
};

pub const ExecRun = union(enum) {
    ok: ExecRunResult,
    trap: trap.TrapReport,

    pub fn deinit(self: *ExecRun, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .ok => |*ok| ok.deinit(allocator),
            .trap => {},
        }
        self.* = undefined;
    }
};

fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, max_bytes);
}

fn ensureParentDir(path: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
}

fn writeFile(path: []const u8, bytes: []const u8) !void {
    try ensureParentDir(path);
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn loadBinaryFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
}

fn readProjectManifest(allocator: std.mem.Allocator, project_root: []const u8) !?PkgManifest.Manifest {
    if (!has_pkg_manifest) return null;
    const manifest_path = try std.fs.path.join(allocator, &.{ project_root, "sa.mod" });
    defer allocator.free(manifest_path);

    const file = std.fs.cwd().openFile(manifest_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 16 * 1024 * 1024);
    defer allocator.free(source);
    return try PkgManifest.parseManifestWithFile(allocator, source, manifest_path);
}

fn manifestDependencies(manifest_file: *const PkgManifest.Manifest, allocator: std.mem.Allocator) ![]PkgResolver.Dependency {
    var deps = std.ArrayList(PkgResolver.Dependency).init(allocator);
    errdefer deps.deinit();

    for (manifest_file.requires) |entry| {
        try deps.append(.{
            .url = entry.url,
            .ref = entry.ref,
        });
    }

    return try deps.toOwnedSlice();
}

pub fn compileSchema(
    allocator: std.mem.Allocator,
    source_path: []const u8,
) ![]u8 {
    const source = try readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var compiled = try schema.compile(allocator, source, source_path);
    defer compiled.deinit();

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try schema.writeIface(out.writer(), compiled);
    return try out.toOwnedSlice();
}

fn buildQmodArtifact(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    source: []const u8,
    project_root: []const u8,
) !qmod.Qmod {
    return try qmod.compileFromSource(allocator, source, source_path, project_root);
}

pub fn registerQuery(
    allocator: std.mem.Allocator,
    source_path: []const u8,
    project_root: []const u8,
) !ExecResult {
    const source = try readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var compiled = try buildQmodArtifact(allocator, source_path, source, project_root);
    defer compiled.deinit();

    const registry_path = try qmod.registryFilePath(allocator, project_root, compiled.hash);
    const iface_path = try qmod.ifaceFilePath(allocator, source_path);
    const qmod_path = try allocator.dupe(u8, registry_path);
    const source_copy = try allocator.dupe(u8, source_path);

    var qmod_bytes = std.ArrayList(u8).init(allocator);
    defer qmod_bytes.deinit();
    try qmod.writeQmod(qmod_bytes.writer(), compiled);
    try writeFile(registry_path, qmod_bytes.items);

    var iface = std.ArrayList(u8).init(allocator);
    defer iface.deinit();
    try qmod.writeQueryIface(iface.writer(), compiled);
    try writeFile(iface_path, iface.items);

    return .{
        .hash = compiled.hash,
        .qmod_path = qmod_path,
        .iface_path = iface_path,
        .registry_path = registry_path,
        .source_path = source_copy,
    };
}

pub fn inspectRegistry(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    hash_hex: []const u8,
) ![]u8 {
    const hash = try qmod.parseSha256Hex(hash_hex);
    const registry_path = try qmod.registryFilePath(allocator, root_dir, hash);
    defer allocator.free(registry_path);
    const source = try readFileAlloc(allocator, registry_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    var loaded = try qmod.parseLoadedQmod(allocator, source);
    defer loaded.deinit();

    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    const hex = std.fmt.bytesToHex(hash, .lower);
    try out.writer().print("registry: {s}\n", .{registry_path});
    try out.writer().print("hash: {s}\n", .{hex[0..]});
    try out.writer().print("source_path: {s}\n", .{loaded.source_path});
    try out.writer().print("project_root: {s}\n", .{loaded.project_root});
    try out.writer().print("imports: {d}\n", .{loaded.imports.len});
    try out.writer().print("grants: {d}\n", .{loaded.grants.len});
    try out.writer().print("bytes: {d}\n", .{source.len});
    return try out.toOwnedSlice();
}

fn readRegistryEntry(allocator: std.mem.Allocator, root_dir: []const u8, hash_hex: []const u8) !qmod.LoadedQmod {
    const hash = try qmod.parseSha256Hex(hash_hex);
    const registry_path = try qmod.registryFilePath(allocator, root_dir, hash);
    defer allocator.free(registry_path);
    const source = try readFileAlloc(allocator, registry_path, 16 * 1024 * 1024);
    defer allocator.free(source);
    return try qmod.parseLoadedQmod(allocator, source);
}

fn qmodFunctionIndex(program: *const referee.VerifyOk) ?usize {
    for (program.function_sigs, 0..) |fsig, idx| {
        if (fsig.kind == .normal and std.mem.eql(u8, fsig.name, "main")) return idx;
    }
    for (program.function_sigs, 0..) |fsig, idx| {
        if (fsig.kind == .normal) return idx;
    }
    return null;
}

fn convertDbGrants(allocator: std.mem.Allocator, grants: []const qmod.Grant) ![]referee_db.Grant {
    const out = try allocator.alloc(referee_db.Grant, grants.len);
    errdefer allocator.free(out);
    for (grants, 0..) |grant, idx| {
        out[idx] = .{
            .kind = @enumFromInt(@intFromEnum(grant.kind)),
            .target = grant.target,
        };
    }
    return out;
}

fn convertPackageGrants(allocator: std.mem.Allocator, manifest: *const PkgManifest.Manifest) ![]RealPkgManifest.RequireEntry {
    var grants = std.ArrayList(RealPkgManifest.RequireEntry).init(allocator);
    errdefer grants.deinit();
    for (manifest.requires) |entry| {
        var entry_grants = try allocator.alloc(RealPkgManifest.Capability, entry.grants.len);
        errdefer allocator.free(entry_grants);
        for (entry.grants, 0..) |grant, idx| {
            entry_grants[idx] = @enumFromInt(@intFromEnum(grant));
        }
        try grants.append(.{
            .url = entry.url,
            .ref = entry.ref,
            .source_sha256 = entry.source_sha256,
            .grants = entry_grants,
            .upstream_loc = .{
                .file = entry.upstream_loc.file,
                .line = entry.upstream_loc.line,
                .col = entry.upstream_loc.col,
            },
        });
    }
    return try grants.toOwnedSlice();
}

fn emptyDbTrap(kind: dbtrap.DbTrap) trap.TrapReport {
    const info = dbtrap.dbTrapInfo(kind);
    return .{
        .trap = info.trap,
        .trap_code = info.code,
        .line = 1,
        .source_line = 1,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register_buf = [_]u8{0} ** 64,
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
        .message = info.default_message,
        .hint = null,
    };
}

fn copyTrapReport(report: anytype) trap.TrapReport {
    return .{
        .trap = @as(trap.Trap, @enumFromInt(@intFromEnum(report.trap))),
        .trap_code = report.trap_code,
        .line = report.line,
        .source_line = report.source_line,
        .source_text_buf = report.source_text_buf,
        .original_text_buf = report.original_text_buf,
        .source_text = report.source_text,
        .original_text = report.original_text,
        .register_buf = report.register_buf,
        .register = report.register,
        .registers = report.registers,
        .expected_mask = report.expected_mask,
        .actual_mask = report.actual_mask,
        .expected_mask_name = report.expected_mask_name,
        .actual_mask_name = report.actual_mask_name,
        .upstream_loc = if (report.upstream_loc) |loc| .{
            .file = loc.file,
            .line = loc.line,
            .col = loc.col,
        } else null,
        .upstream_file_buf = report.upstream_file_buf,
        .upstream_line = report.upstream_line,
        .upstream_col = report.upstream_col,
        .function_buf = report.function_buf,
        .function = report.function,
        .is_ffi_wrapper = report.is_ffi_wrapper,
        .repair_action = report.repair_action,
        .repair_hint = report.repair_hint,
        .repair_confidence = report.repair_confidence,
        .message = report.message,
        .hint = report.hint,
    };
}

pub fn execQuery(
    allocator: std.mem.Allocator,
    root_dir: []const u8,
    hash_hex: []const u8,
    params_path: ?[]const u8,
    stdout: std.io.AnyWriter,
    stderr: std.io.AnyWriter,
) !ExecRun {
    var loaded = readRegistryEntry(allocator, root_dir, hash_hex) catch |err| switch (err) {
        error.FileNotFound, error.InvalidSha256 => return .{ .trap = trapUnknownHash() },
        error.InvalidFormat => return .{ .trap = emptyDbTrap(.snapshot_corrupted) },
        else => return err,
    };
    defer loaded.deinit();
    std.debug.print("db exec loaded source={s} root={s}\n", .{ loaded.source_path, loaded.project_root });

    const project_root = if (loaded.project_root.len != 0) loaded.project_root else root_dir;
    var project_manifest = try readProjectManifest(allocator, project_root);
    defer if (project_manifest) |*m| m.deinit(allocator);

    var dependency_slice: []PkgResolver.Dependency = &.{};
    defer if (dependency_slice.len != 0) allocator.free(dependency_slice);
    if (project_manifest) |*m| {
        dependency_slice = try manifestDependencies(m, allocator);
    }

    const package_grants: []const RealPkgManifest.RequireEntry = if (project_manifest) |*m| try convertPackageGrants(allocator, m) else &.{};
    defer if (package_grants.len != 0) allocator.free(package_grants);

    var error_ctx: flattener.ErrorContext = .{};
    const resolve_ctx = flattener.ResolveContext{
        .dependencies = dependency_slice,
        .options = .{ .project_root = project_root },
    };
    var flat = try flattener.flattenFileWithContextAndPackages(allocator, loaded.source_path, loaded.stripped_source, &error_ctx, resolve_ctx);
    defer flat.deinit(allocator);
    std.debug.print("db exec flatten ok instructions={d} consts={d}\n", .{ flat.instructions.len, flat.const_decls.len });

    const verified = try referee.verifyWithOptions(allocator, flat.instructions, flat.const_decls, .{ .package_grants = package_grants });
    switch (verified) {
        .trap => |report| return .{ .trap = copyTrapReport(report) },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            std.debug.print("db exec verify ok functions={d}\n", .{ owned.function_sigs.len });

            const db_grants = try convertDbGrants(allocator, loaded.grants);
            defer allocator.free(db_grants);
            if (referee_db.scanForTrap(flat.instructions[0..], db_grants)) |report| {
                return .{ .trap = report };
            }
            std.debug.print("db exec db grant scan ok grants={d}\n", .{ db_grants.len });

            const entry_index = qmodFunctionIndex(&owned) orelse return .{ .trap = emptyDbTrap(.schema_mismatch) };
            const params_blob = if (params_path) |path| try loadBinaryFile(allocator, path) else try allocator.alloc(u8, 0);
            defer allocator.free(params_blob);
            std.debug.print("db exec entry_index={d} params={d}\n", .{ entry_index, params_blob.len });

            const code = interp.runFunctionAtIndexWithBinaryArgs(allocator, &owned, entry_index, params_blob, stdout, stderr) catch |err| switch (err) {
                error.InvalidOperand, error.InvalidFunction, error.UnknownFunction, error.MissingIndirectCallProvenance, error.UnsupportedInstruction, error.UnsupportedSysIntrinsic => return .{ .trap = emptyDbTrap(.schema_mismatch) },
                error.InvalidAddress => return .{ .trap = emptyDbTrap(.memory_guard_violation) },
                else => return err,
            };
            std.debug.print("db exec interp code={d}\n", .{code});
            const function_name = try allocator.dupe(u8, owned.function_sigs[entry_index].name);
            return .{ .ok = .{ .code = code, .function_name = function_name, .hash = loaded.hash } };
        },
    }
}

pub fn trapUnknownHash() trap.TrapReport {
    return .{
        .trap = .db_query_hash_unknown,
        .trap_code = trap.trapCode(.db_query_hash_unknown),
        .line = 1,
        .source_line = 1,
        .source_text_buf = [_]u8{0} ** 256,
        .original_text_buf = [_]u8{0} ** 256,
        .source_text = null,
        .original_text = null,
        .register_buf = [_]u8{0} ** 64,
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
        .message = dbtrap.dbTrapInfo(.query_hash_unknown).default_message,
        .hint = null,
    };
}

test "db exec can write schema and qmod artifacts" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    try tmp_dir.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const schema_path = "flash_sale.sadb-schema";
    const qmod_path = "heavy_users.query.sa";

    const schema_source =
        \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8
        \\#def TABLE_ROW_BYTES = 8
    ;
    try writeFile(schema_path, schema_source);
    const iface = try compileSchema(std.testing.allocator, schema_path);
    defer std.testing.allocator.free(iface);
    try std.testing.expect(std.mem.containsAtLeast(u8, iface, 1, "TABLE_ROW_BYTES"));

    const qmod_source =
        \\@import "flash_sale.sadb-schema"
        \\grants [db_read:flash_sale]
        \\@main() -> i32:
        \\L_ENTRY:
        \\return 0
    ;
    try writeFile(qmod_path, qmod_source);
    var result = try registerQuery(std.testing.allocator, qmod_path, ".");
    defer result.deinit(std.testing.allocator);
    try std.testing.expect(result.hash[0] != 0);
    try std.testing.expect(std.mem.endsWith(u8, result.qmod_path, ".qmod"));
    try std.testing.expect(std.mem.containsAtLeast(u8, result.registry_path, 1, ".sa/db/"));

    const registry_hex = std.fmt.bytesToHex(result.hash, .lower);
    const inspected = try inspectRegistry(std.testing.allocator, ".", registry_hex[0..]);
    defer std.testing.allocator.free(inspected);
    try std.testing.expect(std.mem.containsAtLeast(u8, inspected, 1, "grants: 1"));
}

test "db exec can run a registered query with binary params" {
    var original_cwd = try std.fs.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp_dir = std.testing.tmpDir(.{ .iterate = true });
    defer tmp_dir.cleanup();

    try tmp_dir.dir.setAsCwd();
    defer original_cwd.setAsCwd() catch {};

    const schema_path = "flash_sale.sadb-schema";
    const qmod_path = "heavy_users.query.sa";
    const params_path = "params.bin";

    try writeFile(schema_path, \\#def MAX_ROWS = 10
        \\#def COL_ID_STRIDE = 8
        \\#def COL_PRICE_STRIDE = 4
    );

    try writeFile(qmod_path,
        \\@import "flash_sale.sadb-schema"
        \\grants [db_read:flash_sale]
        \\@main(id: u64, factor: u64) -> u64:
        \\L_ENTRY:
        \\total = add id, factor
        \\!id
        \\!factor
        \\return total
    );

    var result = try registerQuery(std.testing.allocator, qmod_path, ".");
    defer result.deinit(std.testing.allocator);

    var params = std.ArrayList(u8).init(std.testing.allocator);
    defer params.deinit();
    try params.writer().writeInt(u64, 7, .little);
    try params.writer().writeInt(u64, 5, .little);
    try writeFile(params_path, params.items);

    var stdout_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stdout_buf.deinit();
    var stderr_buf = std.ArrayList(u8).init(std.testing.allocator);
    defer stderr_buf.deinit();

    const hex = std.fmt.bytesToHex(result.hash, .lower);
    var exec_result = try execQuery(std.testing.allocator, ".", hex[0..], params_path, stdout_buf.writer().any(), stderr_buf.writer().any());
    defer exec_result.deinit(std.testing.allocator);
    switch (exec_result) {
        .ok => |ok| {
            try std.testing.expectEqual(@as(u8, 12), ok.code);
            try std.testing.expectEqualStrings("main", ok.function_name);
        },
        .trap => return error.TestUnexpectedResult,
    }
    try std.testing.expectEqualStrings("", stdout_buf.items);
    try std.testing.expectEqualStrings("", stderr_buf.items);
}

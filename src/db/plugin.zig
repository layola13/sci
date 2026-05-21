const std = @import("std");
const db_exec = if (@hasDecl(@import("root"), "pkg_manifest")) @import("exec.zig") else @import("db_stub.zig");
const db_schema = @import("schema.zig");
const db_table = @import("table.zig");
const plugin_api = @import("plugin_api.zig");
const trap = @import("common/trap.zig");

const db_skills = [_]plugin_api.SkillSection{
    .{
        .name = "database",
        .summary = "Schema compilation, registry management, and query execution",
        .items = &.{
            "db init <schema>",
            "db register <query>",
            "db inspect <hash>",
            "db exec <hash> [--params <file>]",
        },
    },
};

const StreamCtx = struct {
    stream: plugin_api.HostStream,
};

const using_pkg_manifest = @hasDecl(@import("root"), "pkg_manifest");

fn writeTextFile(path: []const u8, bytes: []const u8) !void {
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

fn printTrapReport(writer: anytype, report: trap.TrapReport) !void {
    try writer.print("error[{s}]: {s}\n", .{ trap.trapName(report.trap), report.message });
    if (report.function) |fn_name| {
        try writer.print("  in function {s}\n", .{fn_name});
    }
    if (report.source_text) |source_text| {
        try writer.print("  line {d} (expanded {d}): {s}\n", .{ report.source_line, report.line, source_text });
    }
    if (report.hint) |hint| {
        try writer.print("  help: {s}\n", .{hint});
    }
    try trap.writeJson(writer, report);
    try writer.writeByte('\n');
}

fn printCliError(writer: anytype, err: anyerror, json_mode: bool) !void {
    const mode = if (json_mode) "json" else "human";
    _ = mode;
    try writer.print("error: {}\n", .{err});
}

fn printUnsupportedDbCommand(stderr: anytype, command: []const u8) !void {
    if (using_pkg_manifest) return;
    try stderr.print("error: db {s} is unavailable in this build because pkg_manifest was not provided; the plugin is running against db_stub.zig\n", .{command});
}

fn cArgvToSlice(argv: [*]const [*:0]const u8, argv_len: usize, allocator: std.mem.Allocator) ![]const []const u8 {
    const slice = argv[0..argv_len];
    var out = try allocator.alloc([]const u8, slice.len);
    errdefer allocator.free(out);
    for (slice, 0..) |arg, idx| {
        out[idx] = std.mem.span(arg);
    }
    return out;
}

fn writeAll(ctx: *const anyopaque, bytes: []const u8) anyerror!usize {
    const self = @as(*const StreamCtx, @ptrCast(@alignCast(ctx)));
    const write_all = self.stream.write_all orelse return error.WriteFailed;
    if (write_all(self.stream.ctx, bytes.ptr, bytes.len) != @intFromEnum(plugin_api.AbiStatus.ok)) return error.WriteFailed;
    return bytes.len;
}

fn makeAnyWriter(stream: plugin_api.HostStream, storage: *StreamCtx) ?std.io.AnyWriter {
    storage.* = .{ .stream = stream };
    if (storage.stream.write_all == null) return null;
    if (storage.stream.ctx == null) return null;
    return .{ .context = storage, .writeFn = writeAll };
}

fn runDbCommandImpl(ctx: *const plugin_api.Context, argv: []const []const u8, stdout: std.io.AnyWriter, stderr: std.io.AnyWriter) anyerror!?u8 {
    if (argv.len < 2) return null;
    if (!std.mem.eql(u8, argv[1], "db")) return null;
    if (argv.len < 3) return error.UnknownCommand;

    const json_mode = ctx.json_mode;
    const sub = argv[2];
    if (std.mem.eql(u8, sub, "init")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const iface = db_exec.compileSchema(ctx.allocator, argv[3]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "init");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        defer ctx.allocator.free(iface);
        const iface_path = db_schema.ifaceFilePath(ctx.allocator, argv[3]) catch |err| {
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        defer ctx.allocator.free(iface_path);
        try writeTextFile(iface_path, iface);
        try stdout.print("{s}\n", .{iface_path});
        return 0;
    }
    if (std.mem.eql(u8, sub, "register")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const source_path = argv[3];
        const project_root = std.fs.path.dirname(source_path) orelse ".";
        var result = db_exec.registerQuery(ctx.allocator, source_path, project_root) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "register");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        defer result.deinit(ctx.allocator);
        const hex = std.fmt.bytesToHex(result.hash, .lower);
        try stdout.print("Compiled: {s}\n", .{source_path});
        try stdout.print("Hash: {s}\n", .{hex[0..]});
        try stdout.print("Registered: {s}\n", .{std.fs.path.basename(result.qmod_path)});
        return 0;
    }
    if (std.mem.eql(u8, sub, "inspect")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const report = db_exec.inspectRegistry(ctx.allocator, ".", argv[3]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "inspect");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        defer ctx.allocator.free(report);
        try stdout.writeAll(report);
        return 0;
    }
    if (std.mem.eql(u8, sub, "ingest")) {
        if (argv.len < 5) return error.MissingSourcePath;
        const info = db_table.ingestTable(ctx.allocator, ".", argv[3], argv[4]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "ingest");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        try stdout.print("row_count: {d}\nsegment_count: {d}\nepoch: {d}\nlocked: {s}\n", .{ info.row_count, info.segment_count, info.epoch, if (info.locked) "true" else "false" });
        return 0;
    }
    if (std.mem.eql(u8, sub, "snapshot")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const info = db_table.snapshotTable(ctx.allocator, ".", argv[3]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "snapshot");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        try stdout.print("row_count: {d}\nsegment_count: {d}\nepoch: {d}\nlocked: {s}\n", .{ info.row_count, info.segment_count, info.epoch, if (info.locked) "true" else "false" });
        return 0;
    }
    if (std.mem.eql(u8, sub, "restore")) {
        if (argv.len < 5) return error.MissingSourcePath;
        const epoch = std.fmt.parseInt(u64, argv[4], 10) catch return error.InvalidPath;
        const info = db_table.restoreTable(ctx.allocator, ".", argv[3], epoch) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "restore");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        try stdout.print("row_count: {d}\nsegment_count: {d}\nepoch: {d}\nlocked: {s}\n", .{ info.row_count, info.segment_count, info.epoch, if (info.locked) "true" else "false" });
        return 0;
    }
    if (std.mem.eql(u8, sub, "verify")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const info = db_table.verifyTable(ctx.allocator, ".", argv[3]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "verify");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        try stdout.print("row_count: {d}\nsegment_count: {d}\nepoch: {d}\nlocked: {s}\n", .{ info.row_count, info.segment_count, info.epoch, if (info.locked) "true" else "false" });
        return 0;
    }
    if (std.mem.eql(u8, sub, "lock")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const info = db_table.lockTable(ctx.allocator, ".", argv[3]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "lock");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        try stdout.print("row_count: {d}\nsegment_count: {d}\nepoch: {d}\nlocked: {s}\n", .{ info.row_count, info.segment_count, info.epoch, if (info.locked) "true" else "false" });
        return 0;
    }
    if (std.mem.eql(u8, sub, "compact")) {
        if (argv.len < 4) return error.MissingSourcePath;
        const info = db_table.compactTable(ctx.allocator, ".", argv[3]) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "compact");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        try stdout.print("row_count: {d}\nsegment_count: {d}\nepoch: {d}\nlocked: {s}\n", .{ info.row_count, info.segment_count, info.epoch, if (info.locked) "true" else "false" });
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
        var exec_result = db_exec.execQuery(ctx.allocator, ".", argv[3], params_path, stdout, stderr) catch |err| {
            if (err == error.UnsupportedOperation) {
                try printUnsupportedDbCommand(stderr, "exec");
                return 1;
            }
            try printCliError(stderr, err, json_mode);
            return 1;
        };
        defer exec_result.deinit(ctx.allocator);
        switch (exec_result) {
            .trap => |report| {
                try printTrapReport(stderr, report);
                return 1;
            },
            .ok => |result| return result.code,
        }
    }
    return error.UnknownCommand;
}

fn runDbCommandAbi(ctx: *const plugin_api.Context, argv: [*]const [*:0]const u8, argv_len: usize, stdout: plugin_api.HostStream, stderr: plugin_api.HostStream, out_code: *u8) callconv(.c) u32 {
    out_code.* = 0;
    const args = cArgvToSlice(argv, argv_len, ctx.allocator) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    defer ctx.allocator.free(args);
    var stdout_ctx = StreamCtx{ .stream = stdout };
    var stderr_ctx = StreamCtx{ .stream = stderr };
    const stdout_writer = makeAnyWriter(stdout, &stdout_ctx) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const stderr_writer = makeAnyWriter(stderr, &stderr_ctx) orelse return @intFromEnum(plugin_api.AbiStatus.failed);
    const result = runDbCommandImpl(ctx, args, stdout_writer, stderr_writer) catch return @intFromEnum(plugin_api.AbiStatus.failed);
    if (result) |code| {
        out_code.* = code;
        return @intFromEnum(plugin_api.AbiStatus.ok);
    }
    return @intFromEnum(plugin_api.AbiStatus.unknown_command);
}

pub const descriptor = plugin_api.PluginDescriptor{
    .abi_version = plugin_api.abi_version,
    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_api.PluginDescriptor))),
    .name = "db",
    .init = null,
    .prebuild = null,
    .postbuild = null,
    .handle_command = runDbCommandAbi,
    .skills_ptr = db_skills[0..].ptr,
    .skills_len = db_skills.len,
};

test "db plugin exports runtime descriptor" {
    const exported = &descriptor;
    try std.testing.expectEqual(plugin_api.abi_version, exported.abi_version);
    try std.testing.expectEqualStrings("db", std.mem.span(exported.name));
    try std.testing.expectEqual(@as(usize, 1), exported.skills_len);
    try std.testing.expectEqualStrings("database", exported.skills_ptr[0].name);
    try std.testing.expectEqualStrings("db init <schema>", exported.skills_ptr[0].items[0]);
    try std.testing.expectEqualStrings("db exec <hash> [--params <file>]", exported.skills_ptr[0].items[3]);
}

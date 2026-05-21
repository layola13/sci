const std = @import("std");
const trap = @import("common/trap.zig");
const db_table = @import("db/table.zig");

pub const DiagnosticsMode = enum {
    human,
    json,
};

fn writeJsonString(writer: anytype, text: []const u8) !void {
    try writer.writeByte('"');
    for (text) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{X:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
    try writer.writeByte('"');
}

fn writeMaybeJsonString(writer: anytype, value: ?[]const u8) !void {
    if (value) |text| {
        try writeJsonString(writer, text);
    } else {
        try writer.writeAll("null");
    }
}

const CliErrorInfo = struct {
    code: ?[]const u8,
    message: []const u8,
    hint: ?[]const u8,
};

fn cliErrorInfo(err: anyerror) CliErrorInfo {
    return switch (err) {
        error.MissingSourcePath => .{ .code = "SA-CLI-001", .message = "missing required positional argument", .hint = "pass the source file, project path, or required operand after the command" },
        error.MissingOutputPath => .{ .code = "SA-CLI-002", .message = "missing output path after -o", .hint = "add a path after -o or omit -o to use the default output name" },
        error.MissingJobs => .{ .code = "SA-CLI-003", .message = "missing job count after --jobs", .hint = "use --jobs auto or --jobs <positive integer>" },
        error.InvalidJobs => .{ .code = "SA-CLI-004", .message = "invalid job count", .hint = "use --jobs auto or a positive integer" },
        error.MissingTarget => .{ .code = "SA-CLI-005", .message = "missing target after --target", .hint = "use wasm32 or wasm64 after --target" },
        error.InvalidTarget => .{ .code = "SA-CLI-006", .message = "invalid target", .hint = "use wasm32 or wasm64 after --target" },
        error.MissingFilterValue => .{ .code = "SA-CLI-007", .message = "missing filter pattern", .hint = "pass a pattern after --filter or --skip" },
        error.MissingLayoutName => .{ .code = "SA-CLI-008", .message = "missing layout name", .hint = "pass --name <TypeName>" },
        error.MissingLayoutFields => .{ .code = "SA-CLI-009", .message = "missing layout fields", .hint = "pass --fields <name:ty,...>" },
        error.MissingLayoutFormat => .{ .code = "SA-CLI-010", .message = "missing layout format", .hint = "use --format text or --format json" },
        error.InvalidLayoutFormat => .{ .code = "SA-CLI-011", .message = "invalid layout format", .hint = "use --format text or --format json" },
        error.UnknownCommand => .{ .code = "SA-CLI-012", .message = "unknown command", .hint = "use build, run, build-exe, build-wasm, build-obj, audit, graph, layout, size, test, explain, fix, skills, sax, db, fetch, llvm2sa, help, or version" },
        error.UnexpectedArgument => .{ .code = "SA-CLI-013", .message = "unexpected argument", .hint = "check option order and remove unsupported flags" },
        error.InvalidPath => .{ .code = "SA-CLI-014", .message = "invalid path", .hint = "check the filesystem path and project root" },
        error.MissingRef => .{ .code = "SA-CLI-015", .message = "missing package ref", .hint = "pass a ref value after --ref" },
        else => .{ .code = null, .message = @errorName(err), .hint = null },
    };
}

pub fn printCliError(writer: anytype, err: anyerror, mode: DiagnosticsMode) !void {
    const info = cliErrorInfo(err);
    switch (mode) {
        .human => {
            if (info.code) |code| {
                try writer.print("error[{s}]: {s}\n", .{ code, info.message });
            } else {
                try writer.print("error: {s}\n", .{info.message});
            }
            if (info.hint) |hint| {
                try writer.print("  help: {s}\n", .{hint});
            }
        },
        .json => {
            try writer.writeAll("{\"status\":\"error\",\"error\":{");
            try writer.writeAll("\"name\":");
            try writeJsonString(writer, @errorName(err));
            try writer.writeAll(",\"code\":");
            try writeMaybeJsonString(writer, info.code);
            try writer.writeAll(",\"message\":");
            try writeJsonString(writer, info.message);
            try writer.writeAll(",\"hint\":");
            try writeMaybeJsonString(writer, info.hint);
            try writer.writeAll("}}\n");
        },
    }
}

pub fn printTrapReport(writer: anytype, report: trap.TrapReport, mode: DiagnosticsMode) !void {
    switch (mode) {
        .human => {
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
        },
        .json => {
            try writer.writeAll("{\"status\":\"error\",\"diagnostics\":[");
            try trap.writeJson(writer, report);
            try writer.writeAll("]}\n");
        },
    }
}

pub fn writeTextFile(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !void {
    _ = allocator;
    if (std.fs.path.dirname(path)) |dir| {
        if (dir.len != 0) try std.fs.cwd().makePath(dir);
    }
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();
    try file.writeAll(bytes);
}

pub fn printTableInfo(writer: anytype, info: db_table.TableInfo) !void {
    try writer.print("row_count: {d}\n", .{info.row_count});
    try writer.print("segment_count: {d}\n", .{info.segment_count});
    try writer.print("epoch: {d}\n", .{info.epoch});
    try writer.print("locked: {s}\n", .{if (info.locked) "true" else "false"});
}

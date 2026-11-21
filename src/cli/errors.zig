const std = @import("std");
const trap = @import("../common/trap.zig");
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const CliErrorInfo = @import("types.zig").CliErrorInfo;
const writeJsonString = @import("json.zig").writeJsonString;

pub fn printTrapReport(writer: anytype, report: trap.TrapReport, mode: DiagnosticsMode) !void {
    switch (mode) {
        .human => {
            const function_text = textOrBuf(report.function, report.function_buf[0..]);
            const register_text = textOrBuf(report.register, report.register_buf[0..]);
            var source_text_buf: [256]u8 = std.mem.zeroes([256]u8);
            copyTextBuf(&source_text_buf, reportText(&report));
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
            if (report.repair_action) |action| {
                try writer.print("  repair: {s}\n", .{action});
                if (report.repair_hint) |hint| {
                    try writer.print("    hint: {s}\n", .{hint});
                }
                if (report.repair_confidence) |confidence| {
                    try writer.print("    confidence: {s}\n", .{confidence});
                }
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

pub fn cliErrorInfo(err: anyerror) CliErrorInfo {
    return switch (err) {
        error.MissingSourcePath => .{
            .code = "SA-CLI-001",
            .message = "missing required positional argument",
            .hint = "pass the source file, project path, or required operand after the command",
        },
        error.MissingOutputPath => .{
            .code = "SA-CLI-002",
            .message = "missing output path after -o",
            .hint = "add a path after -o or omit -o to use the default output name",
        },
        error.MissingJobs => .{
            .code = "SA-CLI-003",
            .message = "missing job count after --jobs",
            .hint = "use --jobs auto or --jobs <positive integer>",
        },
        error.InvalidJobs => .{
            .code = "SA-CLI-004",
            .message = "invalid job count",
            .hint = "use --jobs auto or a positive integer",
        },
        error.MissingDceMode => .{
            .code = "SA-CLI-020",
            .message = "missing DCE mode after --dce",
            .hint = "use --dce no, --dce std, or --dce full",
        },
        error.InvalidDceMode => .{
            .code = "SA-CLI-021",
            .message = "invalid DCE mode",
            .hint = "use --dce no, --dce std, or --dce full",
        },
        error.MissingTarget => .{
            .code = "SA-CLI-005",
            .message = "missing target after --target",
            .hint = "use wasm32 or wasm64 after --target",
        },
        error.InvalidTarget => .{
            .code = "SA-CLI-006",
            .message = "invalid target",
            .hint = "use wasm32 or wasm64 after --target",
        },
        error.MissingFilterValue => .{
            .code = "SA-CLI-007",
            .message = "missing filter pattern",
            .hint = "pass a pattern after --filter or --skip",
        },
        error.MissingLayoutName => .{
            .code = "SA-CLI-008",
            .message = "missing layout name",
            .hint = "pass --name <TypeName>",
        },
        error.MissingLayoutFields => .{
            .code = "SA-CLI-009",
            .message = "missing layout fields",
            .hint = "pass --fields <name:ty,...>",
        },
        error.MissingLayoutFormat => .{
            .code = "SA-CLI-010",
            .message = "missing layout format",
            .hint = "use --format text, --format json, --format debug, or --format dict",
        },
        error.InvalidLayoutFormat => .{
            .code = "SA-CLI-011",
            .message = "invalid layout format",
            .hint = "use --format text, --format json, --format debug, or --format dict",
        },
        error.UnsupportedBitcodeInput => .{
            .code = "SA-CLI-012",
            .message = "unsupported bitcode input",
            .hint = "bc2sa expects real LLVM bitcode (.bc); text LLVM IR and non-bitcode files are rejected",
        },
        error.LlvmDisNotFound => .{
            .code = "SA-CLI-016",
            .message = "LLVM bitcode disassembler not found",
            .hint = "install llvm-dis-14/llvm-dis or clang and make one of them available on PATH before running bc2sa",
        },
        error.LlvmDisFailed => .{
            .code = "SA-CLI-017",
            .message = "llvm-dis failed",
            .hint = "verify the input is valid LLVM bitcode for the installed LLVM toolchain",
        },
        error.UnsupportedInstruction => .{
            .code = "SA-CLI-018",
            .message = "unsupported LLVM instruction",
            .hint = "bc2sa currently supports a conservative scalar/load-store/branch subset and rejects unsupported IR instead of emitting invalid SA",
        },
        error.StaticMemoryOverflow => .{
            .code = "SA-CLI-019",
            .message = "static memory overflow detected in LLVM bitcode",
            .hint = "reduce the constant GEP/index offset or widen the fixed-size array before translating",
        },
        error.UnknownCommand => .{
            .code = "SA-CLI-013",
            .message = "unknown command",
            .hint = "use build, build-workspace, run, build-exe, build-wasm, build-js, build-c, build-obj, build-lib, pkg, cache, graph, layout, size, test, check, encode-fragment, explain, fix, skills, bc2sa, help, or version",
        },
        error.SabFragmentNotAProgram => .{
            .code = "SA-CLI-022",
            .message = "input is a SAB fragment (.safrag), not a program",
            .hint = "fragments are compiler building blocks produced by `sa encode-fragment`; assemble the fragment into a module with the calling frontend instead of building, running, or checking it directly",
        },
        error.UnexpectedArgument => .{
            .code = "SA-CLI-014",
            .message = "unexpected argument",
            .hint = "check option order and remove unsupported flags",
        },
        error.InvalidPath => .{
            .code = "SA-CLI-014",
            .message = "invalid path",
            .hint = "check the filesystem path and project root",
        },
        error.MissingRef => .{
            .code = "SA-CLI-015",
            .message = "missing package ref",
            .hint = "pass a ref value after --ref",
        },
        else => .{
            .code = null,
            .message = @errorName(err),
            .hint = null,
        },
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

pub fn printLlvmcEmitError(writer: anytype, err: anyerror, mode: DiagnosticsMode) !void {
    if (err == error.Failed) {
        if (emit_llvm_llvmc.lastErrorMessage()) |message| {
            switch (mode) {
                .human => try writer.print("error[LLVMBackend]: {s}\n", .{message}),
                .json => {
                    try writer.writeAll("{\"status\":\"error\",\"error\":{");
                    try writer.writeAll("\"name\":\"LLVMBackend\",\"code\":\"SA-LLVM-001\",\"message\":");
                    try writeJsonString(writer, message);
                    try writer.writeAll(",\"hint\":\"configure LLVM-C support or rebuild with -Dllvm=true and valid LLVM paths\"}}\n");
                },
            }
            return;
        }
    }
    try printCliError(writer, err, mode);
}

pub fn printUpstreamLocation(writer: anytype, report: trap.TrapReport) !void {
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

pub fn printMaskState(writer: anytype, report: trap.TrapReport) !void {
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

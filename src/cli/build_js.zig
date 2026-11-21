const std = @import("std");
const CompileOptions = @import("types.zig").CompileOptions;
const DiagnosticsMode = @import("types.zig").DiagnosticsMode;
const WasmTarget = @import("types.zig").WasmTarget;
const LibTargetFamily = @import("types.zig").LibTargetFamily;
const driver = @import("../driver/zigcc.zig");
const emit_js = @import("../emit_js.zig");
const sio = @import("sio");
const tripleIsWindows = @import("compile.zig").tripleIsWindows;
const attachBackendIrMetrics = @import("compile.zig").attachBackendIrMetrics;
const compileSource = @import("compile.zig").compileSource;
const elapsedNs = @import("compile.zig").elapsedNs;
const emit_js_types = @import("../emit_js/types.zig");
const ensureParentDir = @import("compile.zig").ensureParentDir;
const finishProfileMetrics = @import("types.zig").finishProfileMetrics;
const memoryEndPrevious = @import("types.zig").memoryEndPrevious;
const printTrapReport = @import("errors.zig").printTrapReport;
const recordMetricMemoryAfterEmit = @import("compile.zig").recordMetricMemoryAfterEmit;
const recordMetricMemoryEnd = @import("compile.zig").recordMetricMemoryEnd;
const sizeBitsForTriple = @import("compile.zig").sizeBitsForTriple;
const sourceStem = @import("test_cmd.zig").sourceStem;
const writeMemoryStageSampleForOptions = @import("compile.zig").writeMemoryStageSampleForOptions;
const writeSuccessDiagnostics = @import("errors.zig").writeSuccessDiagnostics;

pub fn executeBuildJs(allocator: std.mem.Allocator, source_path: []const u8, out_path: []const u8, js_format: emit_js.JsFormat, debug: bool, emit_dts: bool, compile_options: CompileOptions, stderr: anytype, diagnostics_mode: DiagnosticsMode) !u8 {
    const total_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
    const compiled = try compileSource(allocator, source_path, compile_options);
    switch (compiled) {
        .trap => |report| {
            try printTrapReport(stderr, report, diagnostics_mode);
            return 1;
        },
        .ok => |ok| {
            var owned = ok;
            defer owned.deinit(allocator);
            try ensureParentDir(out_path);
            const emit_start = if (compile_options.profile) std.Io.Clock.awake.now(sio.io()) else null;
            const size_bits = sizeBitsForTriple(compile_options.target_triple);
            emit_js.emitJsToFile(allocator, owned.verified, source_path, size_bits, .{ .format = js_format, .debug_comments = debug, .dce = compile_options.dce, .emit_dts = emit_dts }, &owned.flat.def_dict.npm_binds, out_path) catch |err| {
                try stderr.print("error: JS backend emit failed: {s}", .{@errorName(err)});
                if (emit_js_types.last_js_func.len != 0) try stderr.print(" in {s}", .{emit_js_types.last_js_func});
                if (emit_js_types.last_js_inst.len != 0) try stderr.print(": {s}", .{std.mem.trim(u8, emit_js_types.last_js_inst, " \t\r\n")});
                try stderr.writeAll("\n");
                return 1;
            };
            const emit_ns = if (emit_start) |start| elapsedNs(start) else null;
            recordMetricMemoryAfterEmit(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "after_emit", memory.after_emit_rss_bytes, memory.after_verify_rss_bytes);
            recordMetricMemoryEnd(&owned.metrics);
            if (owned.metrics.memory) |memory| try writeMemoryStageSampleForOptions(compile_options, "end", memory.end_rss_bytes, memoryEndPrevious(memory));
            finishProfileMetrics(&owned.metrics, emit_ns, null, if (total_start) |start| elapsedNs(start) else null);
            attachBackendIrMetrics(&owned.metrics, &owned.verified, debug);
            try writeSuccessDiagnostics(stderr, owned.metrics, diagnostics_mode);
            return 0;
        },
    }
}

pub fn parseTarget(text: []const u8) !WasmTarget {
    if (std.mem.eql(u8, text, "wasm32")) return .{ .triple = "wasm32-wasi", .no_entry = false, .size_bits = 32 };
    if (std.mem.eql(u8, text, "wasm64")) return .{ .triple = "wasm64-freestanding", .no_entry = true, .size_bits = 64 };
    return error.InvalidTarget;
}

pub fn libSharedSuffix(family: LibTargetFamily) []const u8 {
    return switch (family) {
        .elf => ".so",
        .pe => ".dll",
        .mach_o => ".dylib",
    };
}

pub fn libStaticSuffix(family: LibTargetFamily) []const u8 {
    return switch (family) {
        .elf, .mach_o => ".a",
        .pe => "_static.lib",
    };
}

pub fn executableSuffixForTriple(triple: ?[]const u8) []const u8 {
    return if (tripleIsWindows(triple)) ".exe" else "";
}

pub fn deriveOutputPath(allocator: std.mem.Allocator, source_path: []const u8, suffix: []const u8) ![]const u8 {
    const dir = std.fs.path.dirname(source_path);
    const stem = sourceStem(source_path);
    if (dir) |parent| {
        return try std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ parent, stem, suffix });
    }
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ stem, suffix });
}

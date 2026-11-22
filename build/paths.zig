const std = @import("std");
const builtin = @import("builtin");

/// Default parallel file jobs for the native SA unit framework suites:
/// host CPU count capped at 8 (each job spawns an external `sa` process).
pub fn defaultUnitFileJobs() u32 {
    const cpu = std.Thread.getCpuCount() catch 4;
    return @intCast(@min(cpu, 8));
}

/// NOTE(Zig 0.17): `Build.pathFromRoot` was removed. Equivalent helper:
/// resolve `sub_path` against the directory containing build.zig.
pub fn pathFromRoot(b: *std.Build, sub_path: []const u8) []u8 {
    const root_path = b.root.root_dir.path orelse ".";
    return std.fs.path.resolveAlloc(b.allocator, &.{ root_path, sub_path }) catch @panic("OOM");
}

/// NOTE(Zig 0.17): `std.fs.Dir` was replaced by `std.Io.Dir`; every
/// filesystem operation now takes an explicit `Io`.
pub fn pathExists(io: std.Io, path: []const u8) bool {
    if (std.fs.path.isAbsolute(path)) {
        std.Io.Dir.accessAbsolute(io, path, .{}) catch return false;
    } else {
        std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    }
    return true;
}

pub fn targetSaStdArchivePath(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "artifacts/sa_std/sa_std.lib",
        else => "artifacts/sa_std/libsa_std.a",
    };
}

/// Destination of the in-tree sa_std archive copy. Host-target builds
/// (plain or with an explicit host -Dtarget) publish to
/// artifacts/sa_std/ as always; cross builds publish to
/// artifacts/sa_std/<triple>/ -- the layout the CLI's per-target
/// archive lookup resolves -- instead of clobbering the host archive.
pub fn targetSaStdSyncPath(b: *std.Build, target: std.Build.ResolvedTarget) []const u8 {
    const is_host = target.result.cpu.arch == builtin.target.cpu.arch and
        target.result.os.tag == builtin.target.os.tag and
        target.result.abi == builtin.target.abi;
    if (is_host) return targetSaStdArchivePath(target.result.os.tag);
    const archive_name: []const u8 = if (target.result.os.tag == .windows) "sa_std.lib" else "libsa_std.a";
    // The CLI's canonical target names omit the ABI for wasi (its
    // default libc is musl): parseTarget maps to "wasm32-wasi",
    // never "wasm32-wasi-musl", so the sync layout must match.
    const abi_suffix: []const u8 = if (target.result.abi == .none or target.result.os.tag == .wasi) "" else b.fmt("-{s}", .{@tagName(target.result.abi)});
    return b.fmt("artifacts/sa_std/{s}-{s}{s}/{s}", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag), abi_suffix, archive_name });
}

pub fn targetSaStdRoot(os_tag: std.Target.Os.Tag) []const u8 {
    return switch (os_tag) {
        .windows => "src/runtime/sa_std_windows.zig",
        else => "src/runtime/sa_std.zig",
    };
}

const std = @import("std");
const sio = @import("sio");
const copyRuntimeArchiveToCwd = @import("helpers.zig").copyRuntimeArchiveToCwd;
const expectSuccess = @import("helpers.zig").expectSuccess;
const icu_demo_link_args = @import("helpers.zig").icu_demo_link_args;
const runCommand = @import("helpers.zig").runCommand;
const writeSource = @import("helpers.zig").writeSource;

test "sa_std dynamic loading helpers are usable from C" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const plugin_source =
        \\pub const plugin_descriptor = extern struct {
        \\    abi_version: u32,
        \\    descriptor_size: u32,
        \\    name: [*:0]const u8,
        \\};
        \\pub export var saasm_plugin_descriptor_v1: plugin_descriptor = .{
        \\    .abi_version = 1,
        \\    .descriptor_size = @as(u32, @intCast(@sizeOf(plugin_descriptor))),
        \\    .name = "plugin_smoke",
        \\};
    ;
    try writeSource(tmp.dir, "plugin_smoke.zig", plugin_source);

    const build_plugin_argv = [_][]const u8{ "zig", "build-lib", "plugin_smoke.zig", "-dynamic", "-O", "Debug", "-femit-bin=libplugin_smoke.so" };
    const build_plugin_result = try runCommand(std.testing.allocator, build_plugin_argv[0..]);
    defer std.testing.allocator.free(build_plugin_result.stdout);
    defer std.testing.allocator.free(build_plugin_result.stderr);
    try expectSuccess(build_plugin_result);

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\
        \\int main(void) {
        \\    const uint8_t path[] = "./libplugin_smoke.so";
        \\    const uint8_t symbol[] = "saasm_plugin_descriptor_v1";
        \\    uint64_t handle = 0;
        \\    void *ptr = 0;
        \\    if (sa_dl_open(path, sizeof(path) - 1, &handle) != SA_STD_OK) return 2;
        \\    if (handle == 0) return 3;
        \\    if (sa_dl_sym(handle, symbol, sizeof(symbol) - 1, &ptr) != SA_STD_OK) return 4;
        \\    if (ptr == 0) return 5;
        \\    if (sa_dl_close(handle) != SA_STD_OK) return 6;
        \\    return 0;
        \\}
    ;
    try writeSource(tmp.dir, "dl_smoke.c", c_source);

    const lib_dir = try original_cwd.realpathAlloc(std.testing.allocator, "zig-out/lib");
    defer std.testing.allocator.free(lib_dir);
    const rpath = try std.fmt.allocPrint(std.testing.allocator, "-Wl,-rpath,{s}", .{lib_dir});
    defer std.testing.allocator.free(rpath);
    const build_demo_argv = [_][]const u8{ "zig", "cc", "-I", include_dir, "dl_smoke.c", "-L", lib_dir, "-lsa_std", rpath, "-o", "sa_std_dl_demo" };
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_dl_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
}

test "sa_std static library exposes a usable C ABI" {
    var original_cwd = try sio.cwd().openDir(".", .{});
    defer original_cwd.close();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    const runtime_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_std.zig");
    defer std.testing.allocator.free(runtime_source);
    const pthread_host_source = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime/sa_pthread_host.c");
    defer std.testing.allocator.free(pthread_host_source);
    const include_dir = try original_cwd.realpathAlloc(std.testing.allocator, "src/runtime");
    defer std.testing.allocator.free(include_dir);

    try std.process.setCurrentDir(std.testing.io, tmp.dir);
    defer original_cwd.setAsCwd() catch {};

    const c_source =
        \\#include "sa_std.h"
        \\
        \\#include <stdint.h>
        \\#include <stdio.h>
        \\#include <string.h>
        \\
        \\int main(void) {
        \\    const uint8_t *path = (const uint8_t *)"abi.txt";
        \\    const uint8_t *data = (const uint8_t *)"hello";
        \\    uint64_t handle = 0;
        \\    uint64_t count = 0;
        \\    uint8_t buffer[16] = {0};
        \\
        \\    if (sa_std_version() != SA_STD_ABI_VERSION) return 2;
        \\    if (sa_std_fs_open_write(path, 7, 1, &handle) != SA_STD_OK) return 3;
        \\    if (sa_std_write(handle, data, 5, &count) != SA_STD_OK || count != 5) return 4;
        \\    if (sa_std_close(handle) != SA_STD_OK) return 5;
        \\
        \\    count = 0;
        \\    if (sa_std_fs_len(path, 7, &count) != SA_STD_OK || count != 5) return 6;
        \\    if (sa_std_fs_open_read(path, 7, &handle) != SA_STD_OK) return 7;
        \\    if (sa_std_read(handle, buffer, sizeof(buffer), &count) != SA_STD_OK || count != 5) return 8;
        \\    if (memcmp(buffer, data, 5) != 0) return 9;
        \\    if (sa_std_close(handle) != SA_STD_OK) return 10;
        \\
        \\    count = 0;
        \\    if (sa_std_error_name(SA_STD_ERR_NOT_FOUND, buffer, sizeof(buffer), &count) != SA_STD_OK) return 11;
        \\    if (count != 9 || memcmp(buffer, "not_found", 9) != 0) return 12;
        \\    if (sa_std_fs_remove(path, 7) != SA_STD_OK) return 13;
        \\
        \\    puts("sa_std abi ok");
        \\    return 0;
        \\}
        \\
    ;
    try writeSource(tmp.dir, "main.c", c_source);

    try copyRuntimeArchiveToCwd();

    const build_demo_argv = [_][]const u8{
        "zig",
        "cc",
        "-I",
        include_dir,
        "main.c",
        "libsa_std.a",
        "-lc",
        "-o",
        "sa_std_c_demo",
    } ++ icu_demo_link_args;
    const build_demo_result = try runCommand(std.testing.allocator, build_demo_argv[0..]);
    defer std.testing.allocator.free(build_demo_result.stdout);
    defer std.testing.allocator.free(build_demo_result.stderr);
    try expectSuccess(build_demo_result);

    const run_result = try runCommand(std.testing.allocator, &.{"./sa_std_c_demo"});
    defer std.testing.allocator.free(run_result.stdout);
    defer std.testing.allocator.free(run_result.stderr);
    try expectSuccess(run_result);
    try std.testing.expectEqualStrings("sa_std abi ok\n", run_result.stdout);
}

const std = @import("std");

const max_source_size = 2 * 1024 * 1024;

fn readSource(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, max_source_size);
}

fn expectContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) == null) {
        std.debug.print("missing Linux CI contract fragment: {s}\n", .{needle});
        return error.TestExpectedEqual;
    }
}

fn expectNotContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) != null) {
        std.debug.print("forbidden Linux CI contract fragment: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}

fn expectInOrder(source: []const u8, needles: []const []const u8) !void {
    var cursor: usize = 0;
    for (needles) |needle| {
        const relative_index = std.mem.indexOf(u8, source[cursor..], needle) orelse {
            std.debug.print("missing or out-of-order Linux CI contract fragment: {s}\n", .{needle});
            return error.TestExpectedEqual;
        };
        cursor += relative_index + needle.len;
    }
}

test "Linux native workflow runs the PAL and NetX runtime gates" {
    const workflow = try readSource(".github/workflows/linux-native.yml");
    defer std.testing.allocator.free(workflow);

    const required = [_][]const u8{
        "pull_request:",
        "workflow_dispatch:",
        "Linux Native Runtime",
        "runs-on: ubuntu-24.04",
        "EXPECTED_ARCH: x86_64",
        "actual_arch=$(uname -m)",
        "Runner architecture mismatch",
        "version: 0.14.1",
        "zig build linux-ci-contract --summary all",
        "zig build test-runtime-basic -Doptimize=ReleaseSafe",
        "zig build test-runtime-pal -Doptimize=ReleaseSafe",
        "zig build test-runtime-netx -Doptimize=ReleaseSafe",
        "zig build sa-std-abi -Doptimize=ReleaseSafe",
        "zig build sa-std-static -Doptimize=ReleaseSafe --prefix \"$static_root\"",
        "zig build sa-std-shared -Doptimize=ReleaseSafe --prefix \"$shared_root\"",
        "lib/libsa_std.a",
        "lib/libsa_std.so",
        "include/sa_std.h",
        "shared_info=$(file \"$shared_root/lib/libsa_std.so\")",
        "grep -F \"x86-64\"",
        "Shared runtime architecture mismatch",
        "git status --porcelain=v1 --untracked-files=all",
        "git diff --exit-code -- artifacts/sa_std",
    };
    for (required) |fragment| try expectContains(workflow, fragment);

    try expectInOrder(workflow, &.{
        "zig build linux-ci-contract --summary all",
        "zig build test-runtime-basic -Doptimize=ReleaseSafe",
        "zig build test-runtime-pal -Doptimize=ReleaseSafe",
        "zig build test-runtime-netx -Doptimize=ReleaseSafe",
        "zig build sa-std-abi -Doptimize=ReleaseSafe",
    });

    const forbidden = [_][]const u8{
        "zig build ci",
        "zig build test ",
        "zig build sa-net-uring-test",
        "zig build sa-cli",
        "LLVM_CONFIG",
        "llvm-config",
        "apt install",
    };
    for (forbidden) |fragment| try expectNotContains(workflow, fragment);
}

test "build graph exposes the Linux native CI contract entry point" {
    const build_source = try readSource("build.zig");
    defer std.testing.allocator.free(build_source);

    try expectContains(build_source, "b.step(\"linux-ci-contract\"");
    try expectContains(build_source, "tests/linux_native_ci_contract.zig");
    try expectContains(build_source, "b.step(\"test-runtime-basic\"");
    try expectContains(build_source, "b.step(\"test-runtime-pal\"");
    try expectContains(build_source, "b.step(\"test-runtime-netx\"");
    try expectContains(build_source, "test-runtime-basic requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "test-runtime-pal requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "test-runtime-netx requires a native Linux, macOS, or Windows host and target");
}

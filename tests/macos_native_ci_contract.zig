const std = @import("std");

const max_source_size = 2 * 1024 * 1024;

fn readSource(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, max_source_size);
}

fn expectContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) == null) {
        std.debug.print("missing macOS CI contract fragment: {s}\n", .{needle});
        return error.TestExpectedEqual;
    }
}

fn expectNotContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) != null) {
        std.debug.print("forbidden macOS CI contract fragment: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}

fn expectInOrder(source: []const u8, needles: []const []const u8) !void {
    var cursor: usize = 0;
    for (needles) |needle| {
        const relative_index = std.mem.indexOf(u8, source[cursor..], needle) orelse {
            std.debug.print("missing or out-of-order macOS CI contract fragment: {s}\n", .{needle});
            return error.TestExpectedEqual;
        };
        cursor += relative_index + needle.len;
    }
}

fn sourceBetween(source: []const u8, start: []const u8, end: []const u8) ![]const u8 {
    const start_index = std.mem.indexOf(u8, source, start) orelse {
        std.debug.print("missing macOS CI contract block start: {s}\n", .{start});
        return error.TestExpectedEqual;
    };
    const tail = source[start_index..];
    const end_index = std.mem.indexOf(u8, tail, end) orelse {
        std.debug.print("missing macOS CI contract block end: {s}\n", .{end});
        return error.TestExpectedEqual;
    };
    return tail[0..end_index];
}

test "macOS native workflow covers both architectures without Linux-only aggregates" {
    const workflow = try readSource(".github/workflows/macos-native.yml");
    defer std.testing.allocator.free(workflow);

    const required = [_][]const u8{
        "pull_request:",
        "workflow_dispatch:",
        "macOS Native L0-L1",
        "          - runner: macos-15-intel\n            expected_arch: x86_64\n            zig_target: x86_64-macos",
        "bottle_tag: sonoma",
        "88ef0c0f3a9876fe2831f1b7f38aee95b43fadd816b6622b76583461d685bbae",
        "          - runner: macos-15\n            expected_arch: arm64\n            zig_target: aarch64-macos",
        "bottle_tag: arm64_sonoma",
        "1b081d8bd775b69b5c95e98df2689844a3c44a77509bfd9adc1f169e9502c6a7",
        "runs-on: ${{ matrix.runner }}",
        "EXPECTED_ARCH: ${{ matrix.expected_arch }}",
        "ZIG_TARGET: ${{ matrix.zig_target }}",
        "actual_arch=$(uname -m)",
        "version: 0.14.1",
        "brew info --json=v2 llvm@14",
        "declared_bottle_sha",
        "brew install --force-bottle llvm@14",
        "llvm_config=\"$llvm_prefix/bin/llvm-config\"",
        "14.0.6",
        "--shared-mode",
        "llvm-c/Core.h",
        "--link-shared --libfiles",
        "LLVM_CONFIG=%s",
        "LLVM_PREFIX=%s",
        "zig build macos-ci-contract --summary all",
        "zig build portability-check -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-portable -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-basic -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-darwin -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-darwin-socket -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build sa-cli -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe --prefix \"$compiler_root\"",
        "zig build sa-std-static -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe --prefix \"$static_root\"",
        "lib/libsa_std.a",
        "/usr/bin/lipo -archs",
        "/usr/bin/otool -L",
        "grep -F \"$LLVM_PREFIX/lib/libLLVM\"",
        "/bin/bash tools/ci/macos_native_smoke.sh",
        "git status --porcelain=v1 --untracked-files=all",
        "git diff --exit-code -- artifacts/sa_std",
    };
    for (required) |fragment| try expectContains(workflow, fragment);
    try expectInOrder(workflow, &.{
        "zig build macos-ci-contract --summary all",
        "zig build portability-check -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-portable -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-basic -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-darwin -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-darwin-socket -Dtarget=\"$ZIG_TARGET\"",
    });

    const forbidden = [_][]const u8{
        "L2",
        "zig build test ",
        "zig build std",
        "zig build ci",
        "sa-std-unit",
        "sa-std-runtime",
        "sa-net-uring",
        "sa-term-runtime",
        "native-sys-runtime",
        "plugin-host-smoke",
        "sa-std-artifact-abi",
        "sa-std-shared",
        "libsa_std.dylib",
        "DYLD_LIBRARY_PATH",
        "/opt/homebrew",
        "/usr/local",
        "LLVM_LIB_NAME=",
    };
    for (forbidden) |fragment| try expectNotContains(workflow, fragment);
}

test "macOS compiler smoke stages native and wasm outputs in an isolated path" {
    const smoke = try readSource("tools/ci/macos_native_smoke.sh");
    defer std.testing.allocator.free(smoke);

    const required = [_][]const u8{
        "#!/bin/bash",
        "set -euo pipefail",
        "sa macOS smoke",
        "release payload",
        "cp -R \"$source_std_root/.\" \"$std_root/\"",
        "libsa_std.a",
        "sa_std.h",
        "HOME",
        "USERPROFILE",
        "TMPDIR",
        "TEMP",
        "TMP",
        "SA_PLUGINS_HOME",
        "SA_STD_DIR",
        "unset SA_DAEMON_SOCKET",
        "staged_std_probe_dir=\"$std_root/ci_smoke\"",
        "staged_std_iface=\"$staged_std_probe_dir/staged_only.sai\"",
        "printf '%s\\n' '@import \"sa_std/ci_smoke/staged_only.sai\"'",
        "cat \"$source_demo\"",
        "else\n        status=$?\n    fi\n    printf '%s failed",
        "assert_macho",
        "/usr/bin/file -b",
        "/usr/bin/lipo -archs",
        "staged sa version",
        "staged sa help",
        "staged sa check",
        "staged sa build-exe",
        "hello, saasm",
        "staged sa build-wasm",
        "--target wasm32",
        "/usr/bin/od -An -tx1 -N4",
        "0061736d",
        "capture_success \"offline package install\" \"$sa\" pkg install --offline github.com/example/pkg",
        "rm -rf -- \"$package_project_root/github.com\"",
        "capture_success \"offline package resolve\" \"$sa\" check \"$package_main\" --offline",
        "if missing_output=$(\"$sa\" pkg install --offline github.com/example/missing --json 2>&1); then",
        "if [ \"$missing_status\" -ne 1 ]; then",
        "SourceNotFound",
        "trap cleanup EXIT",
        "trap 'exit 129' HUP",
        "trap 'exit 130' INT",
        "trap 'exit 143' TERM",
    };
    for (required) |fragment| try expectContains(smoke, fragment);
    try expectInOrder(smoke, &.{
        "printf '%s\\n' '// This file exists only in the staged SA_STD_DIR.' > \"$staged_std_iface\"",
        "printf '%s\\n' '@import \"sa_std/ci_smoke/staged_only.sai\"'",
        "export SA_STD_DIR=\"$std_root\"",
        "capture_success \"staged sa check\"",
        "capture_success \"staged sa build-exe\"",
        "capture_success \"staged sa build-wasm\"",
    });
    try expectInOrder(smoke, &.{
        "capture_success \"offline package install\"",
        "rm -rf -- \"$package_project_root/github.com\"",
        "capture_success \"offline package resolve\"",
        "if missing_output=$(\"$sa\" pkg install --offline",
    });

    const forbidden = [_][]const u8{
        "readlink -f",
        "stat -c",
        "grep -P",
        "sed -r",
        "timeout ",
        "sha256sum",
        "cp -a",
        "mapfile",
        "readarray",
        "DYLD_LIBRARY_PATH",
        "trap cleanup EXIT HUP",
        "cp \"$source_demo\" \"$temp_demo\"",
    };
    for (forbidden) |fragment| try expectNotContains(smoke, fragment);

    const repo_probe: ?std.fs.File = std.fs.cwd().openFile("sa_std/ci_smoke/staged_only.sai", .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (repo_probe) |file| {
        file.close();
        return error.TestUnexpectedResult;
    }
}

test "build graph exposes macOS dual-architecture portability entry points" {
    const build_source = try readSource("build.zig");
    defer std.testing.allocator.free(build_source);

    try expectContains(build_source, "b.step(\"macos-ci-contract\"");
    try expectContains(build_source, "tests/macos_native_ci_contract.zig");
    try expectContains(build_source, "b.step(\"portable-runtime-typecheck\"");
    try expectContains(build_source, "b.step(\"portability-check\"");
    try expectContains(build_source, "b.step(\"test-runtime-basic\"");
    try expectContains(build_source, "b.step(\"test-runtime-darwin\"");
    try expectContains(build_source, "b.step(\"test-runtime-darwin-socket\"");
    try expectContains(build_source, "tests/runtime_basic_contract.c");
    try expectContains(build_source, "tests/runtime_darwin_contract.c");
    try expectContains(build_source, "tests/runtime_darwin_socket_contract.c");
    try expectContains(build_source, "tests/runtime_contract_fixture.c");
    try expectContains(build_source, "test-runtime-darwin requires a native macOS x86_64 or aarch64 host and target");
    try expectContains(build_source, "test-runtime-darwin-socket requires a native macOS x86_64 or aarch64 host and target");
    try expectContains(build_source, "\"x86_64-macos\", \"aarch64-macos\"");
    try expectContains(build_source, "src/runtime/sa_pthread_host_darwin.c");
    try expectContains(build_source, "const portable_targets = [_][]const u8{ \"x86_64-macos\", \"aarch64-macos\", \"x86_64-windows-gnu\" };");

    const portability_block = try sourceBetween(
        build_source,
        "const portability_check_step = b.step(\"portability-check\"",
        "const lib_root_smoke_module = b.createModule",
    );
    const required_dependencies = [_][]const u8{
        "portability_check_step.dependOn(portable_host_typecheck);",
        "portability_check_step.dependOn(portable_runtime_typecheck);",
        "portability_check_step.dependOn(sa_std_abi_step);",
    };
    for (required_dependencies) |fragment| try expectContains(portability_block, fragment);

    const forbidden_dependencies = [_][]const u8{
        "test_step",
        "std_step",
        "ci_step",
        "sa_std_runtime_step",
        "sa_net_uring_step",
        "sa_term_runtime_step",
        "native_sys_runtime_step",
        "plugin_host_smoke_step",
    };
    for (forbidden_dependencies) |fragment| try expectNotContains(portability_block, fragment);
}

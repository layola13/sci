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
        "zig_version=$(zig version)",
        "Expected Zig 0.14.1",
        "--shared-mode",
        "llvm-c/Core.h",
        "--link-shared --libfiles",
        "LLVM_CONFIG=%s",
        "LLVM_PREFIX=%s",
        "LLVM_VERSION=%s",
        "ZIG_VERSION=%s",
        "zig build macos-ci-contract --summary all",
        "zig build portability-check -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-portable -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build plugin-host-smoke -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build daemon-smoke -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-basic -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-pal -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-netx -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-darwin -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-darwin-socket -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "zig build test-runtime-darwin-pty -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe",
        "runtime_evidence_path=\"$RUNNER_TEMP/macos-runtime-gates-$EXPECTED_ARCH.json\"",
        "\"evidence_schema_version\": 1",
        "\"runtime_evidence\": \"passed\"",
        "\"zig_version\": os.environ[\"ZIG_VERSION\"]",
        "\"llvm_version\": os.environ[\"LLVM_VERSION\"]",
        "\"passed_gates\": [",
        "\"plugin-host-smoke\"",
        "\"daemon-smoke\"",
        "\"test-runtime-darwin-socket\"",
        "\"test-runtime-darwin-pty\"",
        "\"github_sha\": os.environ[\"GITHUB_SHA\"]",
        "Validate native runtime evidence",
        "zig run tools/ci/validate_native_evidence.zig --",
        "--kind runtime",
        "--platform macos",
        "--target \"$ZIG_TARGET\"",
        "--zig-version \"$ZIG_VERSION\"",
        "--llvm-version \"$LLVM_VERSION\"",
        "--github-sha \"${{ github.sha }}\"",
        "Upload native runtime evidence",
        "name: macos-native-runtime-${{ matrix.expected_arch }}",
        "path: ${{ runner.temp }}/macos-runtime-gates-${{ matrix.expected_arch }}.json",
        "zig build sa-cli -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe --prefix \"$compiler_root\"",
        "zig build sa-std-static -Dtarget=\"$ZIG_TARGET\" -Doptimize=ReleaseSafe --prefix \"$static_root\"",
        "lib/libsa_std.a",
        "/usr/bin/lipo -archs",
        "/usr/bin/otool -L",
        "grep -F \"$LLVM_PREFIX/lib/libLLVM\"",
        "/bin/bash tools/ci/macos_native_smoke.sh",
        "--evidence-path \"$RUNNER_TEMP/macos-native-smoke-$EXPECTED_ARCH.json\"",
        "Validate native smoke evidence",
        "zig run tools/ci/validate_native_evidence.zig --",
        "--kind smoke",
        "--platform macos",
        "--github-run-id \"${{ github.run_id }}\"",
        "Upload native smoke evidence",
        "uses: actions/upload-artifact@v4",
        "name: macos-native-smoke-${{ matrix.expected_arch }}",
        "if-no-files-found: warn",
        "path: ${{ runner.temp }}/macos-native-smoke-${{ matrix.expected_arch }}.json",
        "git status --porcelain=v1 --untracked-files=all",
        "git diff --exit-code -- artifacts/sa_std",
    };
    for (required) |fragment| try expectContains(workflow, fragment);
    try expectInOrder(workflow, &.{
        "zig build macos-ci-contract --summary all",
        "zig build portability-check -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-portable -Dtarget=\"$ZIG_TARGET\"",
        "zig build plugin-host-smoke -Dtarget=\"$ZIG_TARGET\"",
        "zig build daemon-smoke -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-basic -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-pal -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-netx -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-darwin -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-darwin-socket -Dtarget=\"$ZIG_TARGET\"",
        "zig build test-runtime-darwin-pty -Dtarget=\"$ZIG_TARGET\"",
    });
    try expectInOrder(workflow, &.{
        "Run compiler and release-layout smoke",
        "Validate native smoke evidence",
        "Upload native smoke evidence",
        "Check source artifact cleanliness",
    });
    try expectInOrder(workflow, &.{
        "Run portability contracts",
        "runtime_evidence_path=\"$RUNNER_TEMP/macos-runtime-gates-$EXPECTED_ARCH.json\"",
        "Validate native runtime evidence",
        "Upload native runtime evidence",
        "Build isolated native compiler and runtime artifacts",
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
        "[--evidence-path PATH]",
        "evidence_path=${SA_NATIVE_SMOKE_EVIDENCE:-}",
        "resolve_zig_version()",
        "if [ -n \"${ZIG_VERSION:-}\" ]; then",
        "zig version",
        "resolve_llvm_version()",
        "elif [ -n \"${LLVM_CONFIG:-}\" ] && [ -x \"$LLVM_CONFIG\" ]; then",
        "\"$LLVM_CONFIG\" --version",
        "zig_version=$(resolve_zig_version)",
        "llvm_version=$(resolve_llvm_version)",
        "--evidence-path)",
        "sa macOS smoke",
        "release payload",
        "archive_payload_name=\"sa-macos-$expected_arch\"",
        "installer_release_root=$(mktemp -d \"$temp_parent/sa_installer_release.XXXXXX\")",
        "archive_path=\"$temp_root/$archive_payload_name.tar.gz\"",
        "archive_extract_root=\"$temp_root/archive extracted\"",
        "installer_root=\"$temp_root/installed via install.sh\"",
        "http_installer_root=\"$temp_root/installed via install.sh http\"",
        "http_port_file=\"$temp_root/release_http_port\"",
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
        "(cd \"$temp_root\" && tar -czf \"$archive_path\" \"$archive_payload_name\")",
        "tar -tzf \"$archive_path\" >/dev/null",
        "cp \"$archive_path\" \"$installer_release_root/$archive_payload_name.tar.gz\"",
        "shasum -a 256 \"$archive_payload_name.tar.gz\" > \"$archive_payload_name.tar.gz.sha256\"",
        "tar -xzf \"$archive_path\" -C \"$archive_extract_root\"",
        "release_root=\"$archive_extract_root/$archive_payload_name\"",
        "Extracted native archive is missing",
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
        "capture_success \"install.sh local release archive\" env",
        "SA_RELEASE_URL=\"file://$installer_release_root\"",
        "sh \"$repo_root/tools/install.sh\" --dir \"$installer_root\" --no-shell",
        "python3 - \"$installer_release_root\" \"$http_port_file\"",
        "http_server_pid=$!",
        "release_http_url=\"http://127.0.0.1:$(cat \"$http_port_file\")\"",
        "capture_success \"install.sh HTTP release archive\" env",
        "SA_RELEASE_URL=\"$release_http_url\"",
        "sh \"$repo_root/tools/install.sh\" --dir \"$http_installer_root\" --no-shell",
        "HTTP installed sa version",
        "http_installed_version_output=$captured_output",
        "HTTP installed sa check",
        "installed_sa=\"$installer_root/bin/sa\"",
        "installed_std_root=\"$installer_root/std\"",
        "$installed_std_root/libsa_std.a",
        "$installer_root/bin/saasm",
        "capture_success \"installed sa version\"",
        "capture_success \"installed sa check\" env SA_STD_DIR=\"$installed_std_root\"",
        "staged_version_output=$captured_output",
        "installed_version_output=$captured_output",
        "if [ -n \"$evidence_path\" ]; then",
        "mkdir -p \"$evidence_dir\"",
        "\"evidence_schema_version\": 1",
        "\"platform\": \"macos\"",
        "\"archive\": \"%s.tar.gz\"",
        "\"github_sha\": \"%s\"",
        "\"github_run_id\": \"%s\"",
        "\"github_run_attempt\": \"%s\"",
        "\"zig_version\": \"%s\"",
        "\"llvm_version\": \"%s\"",
        "\"installer_transports\": [\"file\", \"http\"]",
        "\"staged_version\": \"%s\"",
        "\"installed_version\": \"%s\"",
        "\"http_installed_version\": \"%s\"",
        "\"wasm_magic\": \"%s\"",
        "\"native_smoke\": \"passed\"",
        "trap cleanup EXIT",
        "trap 'exit 129' HUP",
        "trap 'exit 130' INT",
        "trap 'exit 143' TERM",
    };
    for (required) |fragment| try expectContains(smoke, fragment);
    try expectInOrder(smoke, &.{
        "printf '%s\\n' '// This file exists only in the staged SA_STD_DIR.' > \"$staged_std_iface\"",
        "printf '%s\\n' '@import \"sa_std/ci_smoke/staged_only.sai\"'",
        "tar -xzf \"$archive_path\" -C \"$archive_extract_root\"",
        "release_root=\"$archive_extract_root/$archive_payload_name\"",
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
        "capture_success \"install.sh local release archive\"",
        "capture_success \"installed sa version\"",
        "capture_success \"installed sa check\"",
        "capture_success \"install.sh HTTP release archive\"",
        "capture_success \"HTTP installed sa version\"",
        "capture_success \"HTTP installed sa check\"",
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
    const plugin_source = try readSource("src/plugins.zig");
    defer std.testing.allocator.free(plugin_source);

    try expectContains(build_source, "b.step(\"macos-ci-contract\"");
    try expectContains(build_source, "tests/macos_native_ci_contract.zig");
    try expectContains(build_source, "b.step(\"native-evidence-validator\"");
    try expectContains(build_source, "tools/ci/validate_native_evidence.zig");
    try expectContains(build_source, "macos_ci_contract_step.dependOn(&native_evidence_validator_tests.step);");
    try expectContains(build_source, "b.step(\"portable-runtime-typecheck\"");
    try expectContains(build_source, "b.step(\"portability-check\"");
    try expectContains(build_source, "b.step(\"test-runtime-basic\"");
    try expectContains(build_source, "b.step(\"test-runtime-pal\"");
    try expectContains(build_source, "b.step(\"test-runtime-netx\"");
    try expectContains(build_source, "b.step(\"plugin-host-smoke\"");
    try expectContains(build_source, "b.step(\"test-runtime-darwin\"");
    try expectContains(build_source, "b.step(\"test-runtime-darwin-socket\"");
    try expectContains(build_source, "b.step(\"runtime-darwin-pty-link\"");
    try expectContains(build_source, "b.step(\"test-runtime-darwin-pty\"");
    try expectContains(build_source, "tests/runtime_basic_contract.c");
    try expectContains(build_source, "tests/runtime_darwin_contract.c");
    try expectContains(build_source, "tests/runtime_darwin_socket_contract.c");
    try expectContains(build_source, "tests/runtime_darwin_pty_contract.c");
    try expectContains(build_source, "tests/runtime_contract_fixture.c");
    try expectContains(plugin_source, "tool, \"-u\", artifact_abs");
    try expectContains(plugin_source, "tool, \"--undefined-only\", artifact_abs");
    try expectContains(plugin_source, "builtin.os.tag == .macos");
    try expectContains(plugin_source, "fn normalizeUndefinedImportSymbolFor");
    try expectContains(plugin_source, "normalized = normalized[1..]");
    try expectContains(plugin_source, "symbol = normalizeUndefinedImportSymbolFor(builtin.os.tag, symbol)");
    try expectContains(plugin_source, "normalizeUndefinedImportSymbolFor(.macos, \"_connect\")");
    const evidence_validator_source = try readSource("tools/ci/validate_native_evidence.zig");
    defer std.testing.allocator.free(evidence_validator_source);
    try expectContains(evidence_validator_source, "const EvidenceKind = enum");
    try expectContains(evidence_validator_source, "const evidence_schema_version: i64 = 1;");
    try expectContains(evidence_validator_source, "try expectInteger(root, \"evidence_schema_version\", evidence_schema_version);");
    try expectContains(evidence_validator_source, "fn expectedRuntimeGates");
    try expectContains(evidence_validator_source, "fn validateInstallerTransports");
    try expectContains(evidence_validator_source, "fn validateRequiredEvidenceArgument");
    try expectContains(evidence_validator_source, "fn validateGitHubSha");
    try expectContains(evidence_validator_source, "fn validateGitHubRunNumber");
    try expectContains(evidence_validator_source, "fn expectedRuntimeTarget");
    try expectContains(evidence_validator_source, "fn validatePlatformArchTarget");
    try expectContains(evidence_validator_source, "error.InvalidEvidenceArgument");
    try expectContains(evidence_validator_source, "try validateRequiredEvidenceArgument(\"zig_version\", options.zig_version);");
    try expectContains(evidence_validator_source, "try validateRequiredEvidenceArgument(\"llvm_version\", options.llvm_version);");
    try expectContains(evidence_validator_source, "try validateRequiredEvidenceArgument(\"github_sha\", options.github_sha);");
    try expectContains(evidence_validator_source, "try validateRequiredEvidenceArgument(\"github_run_id\", options.github_run_id);");
    try expectContains(evidence_validator_source, "try validateRequiredEvidenceArgument(\"github_run_attempt\", options.github_run_attempt);");
    try expectContains(evidence_validator_source, "try validateGitHubSha(options.github_sha);");
    try expectContains(evidence_validator_source, "try validateGitHubRunNumber(\"github_run_id\", options.github_run_id);");
    try expectContains(evidence_validator_source, "try validateGitHubRunNumber(\"github_run_attempt\", options.github_run_attempt);");
    try expectContains(evidence_validator_source, "try validatePlatformArchTarget(options);");
    try expectContains(evidence_validator_source, "return \"x86_64-macos\";");
    try expectContains(evidence_validator_source, "return \"aarch64-macos\";");
    try expectContains(evidence_validator_source, "--zig-version");
    try expectContains(evidence_validator_source, "--llvm-version");
    try expectContains(evidence_validator_source, "try expectString(root, \"zig_version\", options.zig_version);");
    try expectContains(evidence_validator_source, "try expectString(root, \"llvm_version\", options.llvm_version);");
    try expectContains(evidence_validator_source, "\"plugin-host-smoke\"");
    try expectContains(evidence_validator_source, "\"daemon-smoke\"");
    try expectContains(evidence_validator_source, "\"test-runtime-darwin-socket\"");
    try expectContains(evidence_validator_source, "\"sa-macos-arm64.tar.gz\"");
    try expectContains(build_source, "test-runtime-darwin requires a native macOS x86_64 or aarch64 host and target");
    try expectContains(build_source, "test-runtime-pal requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "test-runtime-netx requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "test-runtime-darwin-socket requires a native macOS x86_64 or aarch64 host and target");
    try expectContains(build_source, "runtime-darwin-pty-link requires a macOS x86_64 or aarch64 target");
    try expectContains(build_source, "test-runtime-darwin-pty requires a native macOS x86_64 or aarch64 host and target");
    try expectContains(build_source, "runtime_darwin_pty_contract_module.linkLibrary(sa_std_static);");
    try expectContains(build_source, "runtime_darwin_pty_contract-{s}.o");
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

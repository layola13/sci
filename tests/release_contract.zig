const std = @import("std");

const max_source_size = 2 * 1024 * 1024;

fn readSource(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, max_source_size);
}

fn expectContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) == null) {
        std.debug.print("missing release contract fragment: {s}\n", .{needle});
        return error.TestExpectedEqual;
    }
}

fn expectNotContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) != null) {
        std.debug.print("obsolete release contract fragment remains: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}

fn sourceSection(source: []const u8, start_marker: []const u8, end_marker: []const u8) ![]const u8 {
    const start = std.mem.indexOf(u8, source, start_marker) orelse return error.TestExpectedEqual;
    const relative_end = std.mem.indexOf(u8, source[start + start_marker.len ..], end_marker) orelse
        return error.TestExpectedEqual;
    return source[start .. start + start_marker.len + relative_end];
}

test "installers use the canonical repository and platform artifact names" {
    const shell_installer = try readSource("tools/install.sh");
    defer std.testing.allocator.free(shell_installer);
    const powershell_installer = try readSource("tools/install.ps1");
    defer std.testing.allocator.free(powershell_installer);
    const remote_installer = try readSource("tools/install_remote.sh");
    defer std.testing.allocator.free(remote_installer);

    try expectContains(shell_installer, "https://github.com/layola13/sci/releases");
    try expectContains(powershell_installer, "https://github.com/layola13/sci/releases");
    try expectContains(remote_installer, "GITHUB_ORG=\"layola13\"");
    try expectContains(remote_installer, "SA_REPO=\"sci\"");
    try expectNotContains(shell_installer, "https://github.com/sci/sa/releases");
    try expectNotContains(powershell_installer, "https://github.com/sci/sa/releases");

    try expectContains(shell_installer, "sa-${OS}-${ARCH}.tar.gz");
    try expectContains(shell_installer, "EXTRACTED_DIR=\"$TEMP_DIR/sa-${OS}-${ARCH}\"");
    try expectNotContains(shell_installer, "find \"$TEMP_DIR\" -maxdepth");
    try expectContains(remote_installer, "Darwin) OS=\"macos\"");
    try expectContains(remote_installer, "sa-${OS}-${ARCH}.tar.gz");
    try expectContains(remote_installer, "EXTRACTED_ROOT=\"$TMP_DIR/sa-${OS}-${ARCH}\"");
    try expectContains(powershell_installer, "sa-windows-$arch.zip");
    try expectNotContains(remote_installer, "-name \"sa_std\"");
    try expectNotContains(remote_installer, "find \"$TMP_DIR\"");
}

test "release packager fixes archive roots and required payload files" {
    const release_script = try readSource("tools/release.sh");
    defer std.testing.allocator.free(release_script);

    const target_rows = [_][]const u8{
        "linux;x86_64;x86_64-linux-gnu;tar.gz",
        "macos;x86_64;x86_64-macos;tar.gz",
        "macos;aarch64;aarch64-macos;tar.gz",
        "windows;x86_64;x86_64-windows-gnu;zip",
        "windows;aarch64;aarch64-windows-gnu;zip",
    };
    for (target_rows) |target_row| try expectContains(release_script, target_row);

    const payload_paths = [_][]const u8{
        "bin/$EXE_FILE",
        "std/$LIB_FILE",
        "std/sa_std.h",
        "std/io/print.sai",
        "std/core/sa_core.sa",
        "std/core/result.sa",
        "std/core/option.sa",
    };
    for (payload_paths) |payload_path| try expectContains(release_script, payload_path);

    try expectContains(release_script, "TARGET_NAME=\"sa-${OS}-${ARCH}\"");
    try expectContains(release_script, "zig build release-artifacts --prefix \"$BUILD_DIR\"");
    try expectContains(release_script, "cat \"$BUILD_LOG\" >&2");
    try expectNotContains(release_script, "rm -rf \"$REPO_ROOT/.zig-cache\"");
    try expectNotContains(release_script, "rm -rf \"$REPO_ROOT/zig-out\"");
    try expectContains(release_script, "verify_archive_payload");
    try expectContains(release_script, "tar -tzf");
    try expectContains(release_script, "unzip -tqq");
    try expectContains(release_script, "\"$DIST_DIR\"/sa-*.tar.gz");
    try expectContains(release_script, "\"$DIST_DIR\"/sa-*.zip");
    try expectNotContains(release_script, "find \"$DIST_DIR\" -maxdepth");
    try expectNotContains(release_script, "artifacts/sa_std/libsa_std.a");
    try expectContains(release_script, "verify_checksum_sidecar");
    try expectContains(release_script, "verify_checksum_manifest");
    try expectContains(release_script, "No release archives were generated");
    try expectNotContains(release_script, "skipped (no shasum tool found)");
}

test "release workflow aggregates and publishes archives with checksums" {
    const workflow = try readSource(".github/workflows/release.yml");
    defer std.testing.allocator.free(workflow);

    try expectContains(workflow, "SA_VERSION=%s\\n' \"$GITHUB_REF_NAME\"");
    try expectContains(workflow, "dist/${{ matrix.artifact }}.sha256");
    try expectContains(workflow, "merge-multiple: true");
    try expectContains(workflow, "archives=(sa-*.tar.gz sa-*.zip)");
    try expectContains(workflow, "sha256sum --check --strict \"$sidecar\"");
    try expectContains(workflow, "sha256sum -- \"${archives[@]}\"");

    const release_files = [_][]const u8{
        "dist/sa-*.tar.gz",
        "dist/sa-*.tar.gz.sha256",
        "dist/sa-*.zip",
        "dist/sa-*.zip.sha256",
        "dist/sha256sums.txt",
    };
    for (release_files) |release_file| try expectContains(workflow, release_file);

    const download_section = try sourceSection(
        workflow,
        "- name: Download archives",
        "- name: Verify sidecars and generate combined checksums",
    );
    try expectNotContains(download_section, "name: linux-x86_64");
    try expectNotContains(workflow, "sha256sum sa-* > sha256sums.txt");
}

test "release workflow keeps non-Linux archives disabled pending native evidence" {
    const workflow = try readSource(".github/workflows/release.yml");
    defer std.testing.allocator.free(workflow);

    const matrix = try sourceSection(
        workflow,
        "      matrix:\n        include:\n",
        "    steps:",
    );

    try expectContains(matrix, "Non-Linux release archives stay disabled until the native macOS/Windows");
    try expectContains(matrix, "# workflows have recorded successful compiler, runtime, installer, and");
    try expectContains(matrix, "# archive smoke evidence for the matching target.");
    try expectContains(matrix, "\n          - name: linux-x86_64");
    try expectContains(matrix, "\n          - name: linux-aarch64");

    const disabled_rows = [_][]const u8{
        "# - name: macos-x86_64",
        "# - name: macos-aarch64",
        "# - name: windows-x86_64",
        "# - name: windows-aarch64",
        "#   runner: macos-15-intel",
        "#   runner: macos-15",
        "#   runner: windows-2025",
        "#   runner: windows-11-arm",
    };
    for (disabled_rows) |row| try expectContains(matrix, row);

    const forbidden_active_rows = [_][]const u8{
        "\n          - name: macos-x86_64",
        "\n          - name: macos-aarch64",
        "\n          - name: windows-x86_64",
        "\n          - name: windows-aarch64",
        "\n            runner: macos-15-intel",
        "\n            runner: macos-15",
        "\n            runner: windows-2025",
        "\n            runner: windows-11-arm",
    };
    for (forbidden_active_rows) |row| try expectNotContains(matrix, row);
}

test "release contract is gated by native evidence validation" {
    const build_source = try readSource("build.zig");
    defer std.testing.allocator.free(build_source);
    const evidence_validator_source = try readSource("tools/ci/validate_native_evidence.zig");
    defer std.testing.allocator.free(evidence_validator_source);

    try expectContains(build_source, "b.step(\"release-contract\"");
    try expectContains(build_source, "b.step(\"native-evidence-validator\"");
    try expectContains(build_source, "tools/ci/validate_native_evidence.zig");
    try expectContains(build_source, "release_contract_step.dependOn(&native_evidence_validator_tests.step);");
    try expectContains(evidence_validator_source, "const EvidenceKind = enum");
    try expectContains(evidence_validator_source, "fn validateEvidence");
    try expectContains(evidence_validator_source, "fn validateEvidenceSource");
    try expectContains(evidence_validator_source, "fn expectedRuntimeGates");
}

test "compiler release checksum verification is mandatory" {
    const shell_installer = try readSource("tools/install.sh");
    defer std.testing.allocator.free(shell_installer);
    const powershell_installer = try readSource("tools/install.ps1");
    defer std.testing.allocator.free(powershell_installer);
    const remote_installer = try readSource("tools/install_remote.sh");
    defer std.testing.allocator.free(remote_installer);

    try expectNotContains(shell_installer, "skipping verification");
    try expectNotContains(powershell_installer, "skipping verification");
    try expectNotContains(remote_installer, "sha256sums.txt not available");
    try expectContains(shell_installer, "Checksum file");
    try expectContains(powershell_installer, "Checksum");
    try expectContains(remote_installer, "refusing to install an unverified release");
}

test "PowerShell installer can consume local file release artifacts" {
    const powershell_installer = try readSource("tools/install.ps1");
    defer std.testing.allocator.free(powershell_installer);

    try expectContains(powershell_installer, "function Get-LocalPathFromFileUri");
    try expectContains(powershell_installer, "function Save-ReleaseFile");
    try expectContains(powershell_installer, "function Read-ReleaseText");
    try expectContains(powershell_installer, "Copy-Item -LiteralPath $localPath -Destination $OutFile -Force");
    try expectContains(powershell_installer, "Get-Content -LiteralPath $localPath -Raw");
    try expectContains(powershell_installer, "Save-ReleaseFile -UriText $downloadUrl -OutFile $tempZip");
    try expectContains(powershell_installer, "$checksumContent = Read-ReleaseText -UriText $checksumUrl");
}

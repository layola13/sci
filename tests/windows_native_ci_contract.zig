const std = @import("std");

const max_source_size = 2 * 1024 * 1024;

fn readSource(path: []const u8) ![]u8 {
    return std.fs.cwd().readFileAlloc(std.testing.allocator, path, max_source_size);
}

fn expectContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) == null) {
        std.debug.print("missing Windows CI contract fragment: {s}\n", .{needle});
        return error.TestExpectedEqual;
    }
}

fn expectNotContains(source: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, source, needle) != null) {
        std.debug.print("forbidden Windows CI contract fragment: {s}\n", .{needle});
        return error.TestUnexpectedResult;
    }
}

test "Windows native workflow pins toolchains and runs only the reviewed subset" {
    const workflow = try readSource(".github/workflows/windows-native.yml");
    defer std.testing.allocator.free(workflow);

    const required = [_][]const u8{
        "pull_request:",
        "workflow_dispatch:",
        "runs-on: windows-2025",
        "Windows x86_64 native L0/L1 + L2 subset",
        "EXPECTED_ARCH: X64",
        "[System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()",
        "Runner architecture mismatch",
        "version: 0.14.1",
        "Install pinned LLVM 14 runtime and headers",
        "LLVM-14.0.6-win64.exe",
        "e8dbb2f7de8e37915273d65c1c2f2d96844b96bb8e8035f62c5182475e80b9fc",
        "llvm-14.0.6.src.tar.xz",
        "050922ecaaca5781fdf6631ea92bc715183f202f9d2f15147226f023414f619a",
        "& tar.exe -xf $sourceArchive -C $sourceExtractRoot",
        "-G \"Visual Studio 17 2022\" -A x64",
        "LLVM_TARGETS_TO_BUILD=X86",
        "llvm-14.0.6-header-build",
        "include\\llvm-c",
        "include\\llvm\\Config",
        "llvm\\Config\\llvm-config.h",
        "llvm\\Config\\Targets.def",
        "Copy-Item -LiteralPath (Join-Path $llvmSourceRoot \"include\\llvm-c\") -Destination $llvmCIncludeDir -Recurse -Force",
        "Copy-Item -LiteralPath (Join-Path $headerBuildRoot \"include\\llvm\\Config\") -Destination $llvmConfigIncludeDir -Recurse -Force",
        "& $clang -fsyntax-only \"-I$includeDir\" src\\emit_llvm_llvmc_shim.c",
        "LLVM-C shim header syntax check failed",
        "LLVM-C.dll",
        "LLVM_LIB_NAME=LLVM-C",
        "zig build sa-cli -Doptimize=ReleaseSafe",
        "zig build test-portable -Doptimize=ReleaseSafe",
        "zig build plugin-host-smoke -Doptimize=ReleaseSafe",
        "zig build test-runtime-basic -Doptimize=ReleaseSafe",
        "zig build test-runtime-pal -Doptimize=ReleaseSafe",
        "zig build test-runtime-netx -Doptimize=ReleaseSafe",
        "zig build test-runtime-windows -Doptimize=ReleaseSafe",
        "windows-runtime-gates-x86_64.json",
        "runtime_evidence = \"passed\"",
        "passed_gates = @(",
        "\"test-runtime-basic\"",
        "\"test-runtime-windows\"",
        "Validate native runtime evidence",
        "native runtime evidence mismatch",
        "native runtime evidence gate mismatch",
        "Upload native runtime evidence",
        "name: windows-native-runtime-x86_64",
        "path: ${{ runner.temp }}\\windows-runtime-gates-x86_64.json",
        "zig build sa-std-static -Doptimize=ReleaseSafe --prefix",
        "zig build sa-std-shared -Doptimize=ReleaseSafe --prefix",
        "function Get-PeMachine([string]$Path)",
        "$sharedDll = Join-Path $sharedRoot \"bin\\sa_std.dll\"",
        "$sharedMachine = Get-PeMachine $sharedDll",
        "expected 0x8664",
        "Shared runtime architecture mismatch",
        "zig build sa-std-abi -Doptimize=ReleaseSafe",
        ".\\tools\\ci\\windows_native_smoke.ps1 -RuntimeRoot $env:SA_STATIC_ROOT -EvidencePath",
        "windows-native-smoke-x86_64.json",
        "Validate native smoke evidence",
        "Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json",
        "platform = \"windows\"",
        "archive = \"sa-windows-x86_64.zip\"",
        "native_smoke = \"passed\"",
        "wasm_magic = \"0061736d\"",
        "github_sha = \"${{ github.sha }}\"",
        "github_run_id = \"${{ github.run_id }}\"",
        "github_run_attempt = \"${{ github.run_attempt }}\"",
        "native smoke evidence mismatch",
        "native smoke evidence has invalid",
        "Upload native smoke evidence",
        "uses: actions/upload-artifact@v4",
        "name: windows-native-smoke-x86_64",
        "if-no-files-found: warn",
        "path: ${{ runner.temp }}\\windows-native-smoke-x86_64.json",
        "git status --porcelain=v1 --untracked-files=all",
        "git diff --exit-code -- artifacts/sa_std",
    };
    for (required) |fragment| try expectContains(workflow, fragment);

    const forbidden = [_][]const u8{
        "choco install llvm",
        "zig build ci",
        "zig build test ",
        "zig build sa-std-unit",
        "zig build pkg-core-test",
        "sa-std-runtime",
        "sa-net-uring",
        "test-runtime-darwin",
    };
    for (forbidden) |fragment| try expectNotContains(workflow, fragment);
}

test "Windows compiler smoke exercises native and wasm outputs in a portable path" {
    const smoke = try readSource("tools/ci/windows_native_smoke.ps1");
    defer std.testing.allocator.free(smoke);

    const required = [_][]const u8{
        "staged sa.exe version",
        "Invoke-NativeCapture",
        "[string]$EvidencePath = $env:SA_NATIVE_SMOKE_EVIDENCE",
        "$archivePayloadName = \"sa-windows-$archiveArch\"",
        "$archivePath = Join-Path $tempRoot \"$archivePayloadName.zip\"",
        "$installerReleaseRoot = Join-Path $tempRoot \"installer release\"",
        "$installerRoot = Join-Path $tempRoot \"installed via install.ps1\"",
        "Compress-Archive -LiteralPath $archivePayloadRoot -DestinationPath $archivePath -Force",
        "Copy-Item -LiteralPath $archivePath -Destination $installerArchive -Force",
        "Get-FileHash -LiteralPath $installerArchive -Algorithm SHA256",
        "$archivePayloadName.zip.sha256",
        "Expand-Archive -LiteralPath $archivePath -DestinationPath $archiveExtractRoot -Force",
        "$releaseRoot = Join-Path $archiveExtractRoot $archivePayloadName",
        "Extracted native archive is missing",
        "Copy-Item -LiteralPath $sourceSa -Destination $sa",
        "Copy-Item -LiteralPath $runtimeArchive -Destination (Join-Path $stdRoot \"sa_std.lib\")",
        "include\\sa_std.h",
        "SetEnvironmentVariable(\"SA_STD_DIR\", $stdRoot, \"Process\")",
        "HOME",
        "USERPROFILE",
        "TEMP",
        "TMP",
        "SA_PLUGINS_HOME",
        "Push-Location -LiteralPath $packageProjectRoot",
        "Pop-Location",
        "[char]0x6D4B",
        "sa windows smoke",
        "@(\"build-exe\", $tempDemo, \"-o\", $nativeOutput)",
        "generated hello.exe",
        "hello, saasm",
        "build-wasm",
        "--target",
        "wasm32",
        "$wasmBytes[0] -ne 0x00",
        "pkg",
        "install",
        "--offline",
        "offline package resolve",
        "SourceNotFound",
        "$installerReleaseRootUri = ([Uri]((Resolve-Path -LiteralPath $installerReleaseRoot).Path + [IO.Path]::DirectorySeparatorChar)).AbsoluteUri.TrimEnd(\"/\")",
        "SetEnvironmentVariable(\"SA_RELEASE_URL\", $installerReleaseRootUri, \"Process\")",
        "tools\\install.ps1\") -Dir $installerRoot -NoShell",
        "$installedSa = Join-Path $installerRoot \"bin\\sa.exe\"",
        "$installedStdRoot = Join-Path $installerRoot \"std\"",
        "install.ps1 local release install is missing",
        "installed sa.exe version",
        "installed sa.exe check",
        "ConvertTo-Json -Depth 4",
        "Set-Content -LiteralPath $EvidencePath",
        "platform = \"windows\"",
        "archive = \"$archivePayloadName.zip\"",
        "github_sha = $env:GITHUB_SHA",
        "github_run_id = $env:GITHUB_RUN_ID",
        "github_run_attempt = $env:GITHUB_RUN_ATTEMPT",
        "staged_version = $versionResult.Output",
        "installed_version = $installedVersion.Output",
        "native_smoke = \"passed\"",
        "try {",
        "finally {",
    };
    for (required) |fragment| try expectContains(smoke, fragment);
}

test "Windows PowerShell installer supports local file release artifacts" {
    const installer = try readSource("tools/install.ps1");
    defer std.testing.allocator.free(installer);

    try expectContains(installer, "function Get-LocalPathFromFileUri");
    try expectContains(installer, "if ($uri.IsFile)");
    try expectContains(installer, "return $uri.LocalPath");
    try expectContains(installer, "function Save-ReleaseFile");
    try expectContains(installer, "Copy-Item -LiteralPath $localPath -Destination $OutFile -Force");
    try expectContains(installer, "function Read-ReleaseText");
    try expectContains(installer, "Get-Content -LiteralPath $localPath -Raw");
    try expectContains(installer, "Save-ReleaseFile -UriText $downloadUrl -OutFile $tempZip");
    try expectContains(installer, "$checksumContent = Read-ReleaseText -UriText $checksumUrl");
    try expectContains(installer, "Invoke-WebRequest -Uri $UriText -OutFile $OutFile -UseBasicParsing");
}

test "build graph exposes focused Windows CI entry points" {
    const build_source = try readSource("build.zig");
    defer std.testing.allocator.free(build_source);
    const driver_source = try readSource("src/driver/zigcc.zig");
    defer std.testing.allocator.free(driver_source);
    const plugin_source = try readSource("tests/plugin_host_smoke.zig");
    defer std.testing.allocator.free(plugin_source);
    const plugins_runtime_source = try readSource("src/plugins.zig");
    defer std.testing.allocator.free(plugins_runtime_source);

    try expectContains(build_source, "b.step(\"sa-cli\"");
    try expectContains(build_source, "b.step(\"test-portable\"");
    try expectContains(build_source, "b.step(\"test-runtime-basic\"");
    try expectContains(build_source, "b.step(\"test-runtime-pal\"");
    try expectContains(build_source, "b.step(\"test-runtime-netx\"");
    try expectContains(build_source, "b.step(\"plugin-host-smoke\"");
    try expectContains(build_source, "b.step(\"test-runtime-windows\"");
    try expectContains(build_source, "test-runtime-basic requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "test-runtime-pal requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "test-runtime-netx requires a native Linux, macOS, or Windows host and target");
    try expectContains(build_source, "tests/runtime_basic_contract.c");
    try expectContains(build_source, "tests/runtime_contract_fixture.c");
    try expectContains(build_source, "tests/plugin_host_smoke.zig");
    try expectContains(build_source, "linkSystemLibrary(\"ws2_32\"");
    try expectContains(build_source, "linkSystemLibrary(\"mswsock\"");
    try expectContains(build_source, "linkSystemLibrary(\"iphlpapi\"");
    try expectContains(driver_source, "try argv.items.append(\"-lws2_32\");");
    try expectContains(driver_source, "try argv.items.append(\"-lmswsock\");");
    try expectContains(driver_source, "try argv.items.append(\"-liphlpapi\");");
    try expectContains(plugin_source, "SetEnvironmentVariableW");
    try expectContains(plugin_source, "writeBrokerRunnerAlloc");
    try expectContains(plugin_source, "nativeExecutableNameAlloc");
    try expectContains(plugin_source, "denied_runner_abs");
    try expectContains(plugin_source, "windows-x86_64");
    try expectContains(plugin_source, ".dll");
    try expectContains(plugins_runtime_source, "builtin.os.tag == .windows");
    try expectContains(plugins_runtime_source, "__imp_");
    try expectContains(plugins_runtime_source, "normalizeUndefinedImportSymbolFor");
    try expectContains(plugins_runtime_source, "--undefined-only");
    try expectContains(build_source, "requires a native Windows x86_64 host and target");
    try expectContains(build_source, "windows process spawn failure leaves no live child handle");
    try expectContains(build_source, "b.step(\"windows-ci-contract\"");
    try expectContains(build_source, "tests/windows_native_ci_contract.zig");
}

test "cache cleanup avoids the Zig 0.14.1 Windows File.tryLock type error" {
    const cli_source = try readSource("src/cli.zig");
    defer std.testing.allocator.free(cli_source);

    try expectContains(cli_source, "fn tryLockProjectCacheFileExclusive");
    try expectContains(cli_source, "windows.LockFile(");
    try expectContains(cli_source, "error.WouldBlock => return false");
    try expectContains(cli_source, "try tryLockProjectCacheFileExclusive(file)");
    try expectNotContains(cli_source, "try file.tryLock(.exclusive)");
}

[CmdletBinding()]
param(
    [string]$SaPath = "zig-out\bin\sa.exe",
    [string]$RuntimeRoot = $env:SA_STATIC_ROOT,
    [string]$DemoPath = "demos\rosetta\01_hello_world\main.sa",
    [string]$EvidencePath = $env:SA_NATIVE_SMOKE_EVIDENCE
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-InputPath {
    param(
        [string]$BasePath,
        [string]$InputPath
    )

    $candidate = if ([IO.Path]::IsPathRooted($InputPath)) {
        $InputPath
    } else {
        Join-Path $BasePath $InputPath
    }
    return (Resolve-Path -LiteralPath $candidate).Path
}

function Invoke-NativeCapture {
    param(
        [string]$FilePath,
        [string[]]$Arguments = @()
    )

    $outputLines = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    $outputText = ($outputLines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $outputText.Trim()
    }
}

function Assert-Success {
    param(
        [string]$Action,
        [pscustomobject]$Result
    )

    if ($Result.ExitCode -ne 0) {
        throw "$Action failed with exit code $($Result.ExitCode).`n$($Result.Output)"
    }
}

function Start-ReleaseHttpServer {
    param(
        [string]$Root,
        [string]$PortFile
    )

    if (Test-Path -LiteralPath $PortFile) {
        Remove-Item -LiteralPath $PortFile -Force
    }
    $serverJob = Start-Job -ScriptBlock {
        param(
            [string]$Root,
            [string]$PortFile
        )

        $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $listener.Start()
        [IO.File]::WriteAllText($PortFile, [string]$listener.LocalEndpoint.Port, [Text.Encoding]::ASCII)
        try {
            while ($true) {
                $client = $listener.AcceptTcpClient()
                try {
                    $stream = $client.GetStream()
                    $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
                    $requestLine = $reader.ReadLine()
                    while ($true) {
                        $line = $reader.ReadLine()
                        if ($null -eq $line -or $line.Length -eq 0) {
                            break
                        }
                    }
                    if ($requestLine -notmatch '^GET\s+([^ ]+)\s+HTTP/') {
                        $response = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 400 Bad Request`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                        $stream.Write($response, 0, $response.Length)
                        continue
                    }
                    $relativePath = [Uri]::UnescapeDataString($Matches[1].TrimStart("/"))
                    if ($relativePath.Contains("/") -or $relativePath.Contains("\") -or $relativePath.Contains("..")) {
                        $response = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                        $stream.Write($response, 0, $response.Length)
                        continue
                    }
                    $filePath = Join-Path $Root $relativePath
                    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
                        $response = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 404 Not Found`r`nContent-Length: 0`r`nConnection: close`r`n`r`n")
                        $stream.Write($response, 0, $response.Length)
                        continue
                    }
                    $bytes = [IO.File]::ReadAllBytes($filePath)
                    $header = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n")
                    $stream.Write($header, 0, $header.Length)
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $client.Close()
                }
            }
        } finally {
            $listener.Stop()
        }
    } -ArgumentList $Root, $PortFile

    for ($i = 0; $i -lt 100 -and -not (Test-Path -LiteralPath $PortFile -PathType Leaf); $i += 1) {
        if ($serverJob.State -ne "Running") {
            throw "release HTTP server exited before writing its port: $(Receive-Job -Job $serverJob)"
        }
        Start-Sleep -Milliseconds 100
    }
    if (-not (Test-Path -LiteralPath $PortFile -PathType Leaf)) {
        throw "release HTTP server did not report a port"
    }
    $port = [IO.File]::ReadAllText($PortFile).Trim()
    return [pscustomobject]@{
        Job = $serverJob
        Url = "http://127.0.0.1:$port"
    }
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..\..")).Path
if ([string]::IsNullOrWhiteSpace($RuntimeRoot)) {
    $RuntimeRoot = "zig-out"
}

$sourceSa = Resolve-InputPath -BasePath $repoRoot -InputPath $SaPath
$demo = Resolve-InputPath -BasePath $repoRoot -InputPath $DemoPath
$runtimeRootPath = Resolve-InputPath -BasePath $repoRoot -InputPath $RuntimeRoot
$runtimeArchive = (Resolve-Path -LiteralPath (Join-Path $runtimeRootPath "lib\sa_std.lib")).Path
$runtimeHeader = (Resolve-Path -LiteralPath (Join-Path $runtimeRootPath "include\sa_std.h")).Path
$sourceStdRoot = (Resolve-Path -LiteralPath (Join-Path $repoRoot "sa_std")).Path

$archiveArch = switch ([Runtime.InteropServices.RuntimeInformation]::OSArchitecture) {
    "X64" { "x86_64" }
    "Arm64" { "aarch64" }
    default { throw "Unsupported Windows architecture for archive smoke: $([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)" }
}
$unicodeWord = -join @([char]0x6D4B, [char]0x8BD5)
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("sa windows smoke {0} {1}" -f $unicodeWord, [guid]::NewGuid().ToString("N"))
$archivePayloadName = "sa-windows-$archiveArch"
$releaseRoot = Join-Path $tempRoot "release payload"
$binRoot = Join-Path $releaseRoot "bin"
$stdRoot = Join-Path $releaseRoot "std"
$sa = Join-Path $binRoot "sa.exe"
$archivePayloadRoot = Join-Path $tempRoot $archivePayloadName
$archivePath = Join-Path $tempRoot "$archivePayloadName.zip"
$archiveExtractRoot = Join-Path $tempRoot "archive extracted"
$installerReleaseRoot = Join-Path $tempRoot "installer release"
$installerRoot = Join-Path $tempRoot "installed via install.ps1"
$httpInstallerRoot = Join-Path $tempRoot "installed via install.ps1 http"
$httpPortFile = Join-Path $tempRoot "release-http-port.txt"
$releaseHttpJob = $null
$tempDemo = Join-Path $tempRoot "hello main.sa"
$nativeOutput = Join-Path $tempRoot "hello output.exe"
$wasmOutput = Join-Path $tempRoot "hello output.wasm"
$homeRoot = Join-Path $tempRoot "isolated home"
$processTempRoot = Join-Path $tempRoot "isolated temp"
$pluginsRoot = Join-Path $tempRoot "isolated plugins"
$packageProjectRoot = Join-Path $tempRoot "offline package project"
$packageSourceRoot = Join-Path $packageProjectRoot "github.com\example\pkg"
$packageSource = Join-Path $packageSourceRoot "index.sa"
$packageMain = Join-Path $packageProjectRoot "main.sa"
$vendorPackage = Join-Path $packageProjectRoot "sa_vendor\github.com\example\pkg\index.sa"
$utf8NoBom = New-Object Text.UTF8Encoding($false)
$environmentNames = @("HOME", "USERPROFILE", "TEMP", "TMP", "SA_PLUGINS_HOME", "SA_STD_DIR", "SA_RELEASE_URL")
$savedEnvironment = @{}
$locationPushed = $false

foreach ($name in $environmentNames) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
}

try {
    foreach ($path in @($binRoot, $stdRoot, $installerReleaseRoot, $homeRoot, $processTempRoot, $pluginsRoot, $packageSourceRoot)) {
        [void][IO.Directory]::CreateDirectory($path)
    }

    Copy-Item -LiteralPath $sourceSa -Destination $sa -Force
    Get-ChildItem -LiteralPath $sourceStdRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $stdRoot -Recurse -Force
    }
    Copy-Item -LiteralPath $runtimeArchive -Destination (Join-Path $stdRoot "sa_std.lib") -Force
    Copy-Item -LiteralPath $runtimeHeader -Destination (Join-Path $stdRoot "sa_std.h") -Force
    Copy-Item -LiteralPath $demo -Destination $tempDemo -Force

    [IO.File]::WriteAllText(
        $packageSource,
        "@pkg_value() -> i32:`nreturn 42`n",
        $utf8NoBom
    )
    [IO.File]::WriteAllText(
        $packageMain,
        "@import `"github.com/example/pkg`"`n@main() -> i32:`nreturn 0`n",
        $utf8NoBom
    )

    [void][IO.Directory]::CreateDirectory($archivePayloadRoot)
    [void][IO.Directory]::CreateDirectory($archiveExtractRoot)
    Get-ChildItem -LiteralPath $releaseRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $archivePayloadRoot -Recurse -Force
    }
    Compress-Archive -LiteralPath $archivePayloadRoot -DestinationPath $archivePath -Force
    if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
        throw "Native archive was not created: $archivePath"
    }
    $installerArchive = Join-Path $installerReleaseRoot "$archivePayloadName.zip"
    Copy-Item -LiteralPath $archivePath -Destination $installerArchive -Force
    $installerArchiveHash = (Get-FileHash -LiteralPath $installerArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        (Join-Path $installerReleaseRoot "$archivePayloadName.zip.sha256"),
        "$installerArchiveHash  $archivePayloadName.zip`n",
        $utf8NoBom
    )
    Expand-Archive -LiteralPath $archivePath -DestinationPath $archiveExtractRoot -Force
    $releaseRoot = Join-Path $archiveExtractRoot $archivePayloadName
    $binRoot = Join-Path $releaseRoot "bin"
    $stdRoot = Join-Path $releaseRoot "std"
    $sa = Join-Path $binRoot "sa.exe"
    foreach ($requiredPath in @(
        $sa,
        (Join-Path $stdRoot "sa_std.lib"),
        (Join-Path $stdRoot "sa_std.h"),
        (Join-Path $stdRoot "io\print.sai"))) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Extracted native archive is missing $requiredPath"
        }
    }

    [Environment]::SetEnvironmentVariable("HOME", $homeRoot, "Process")
    [Environment]::SetEnvironmentVariable("USERPROFILE", $homeRoot, "Process")
    [Environment]::SetEnvironmentVariable("TEMP", $processTempRoot, "Process")
    [Environment]::SetEnvironmentVariable("TMP", $processTempRoot, "Process")
    [Environment]::SetEnvironmentVariable("SA_PLUGINS_HOME", $pluginsRoot, "Process")
    [Environment]::SetEnvironmentVariable("SA_STD_DIR", $stdRoot, "Process")

    Push-Location -LiteralPath $packageProjectRoot
    $locationPushed = $true

    $versionResult = Invoke-NativeCapture -FilePath $sa -Arguments @("version")
    Assert-Success -Action "staged sa.exe version" -Result $versionResult
    if ($versionResult.Output -notmatch '^sa\s+\S+$') {
        throw "Unexpected version output: $($versionResult.Output)"
    }

    $helpResult = Invoke-NativeCapture -FilePath $sa -Arguments @("help")
    Assert-Success -Action "staged sa.exe help" -Result $helpResult
    if ($helpResult.Output -notmatch 'usage:\s+sa') {
        throw "Unexpected help output: $($helpResult.Output)"
    }

    $checkResult = Invoke-NativeCapture -FilePath $sa -Arguments @("check", $tempDemo)
    Assert-Success -Action "staged sa.exe check" -Result $checkResult

    $buildResult = Invoke-NativeCapture -FilePath $sa -Arguments @("build-exe", $tempDemo, "-o", $nativeOutput)
    Assert-Success -Action "staged sa.exe build-exe" -Result $buildResult
    if (-not (Test-Path -LiteralPath $nativeOutput -PathType Leaf)) {
        throw "sa.exe build-exe did not create $nativeOutput"
    }

    $programResult = Invoke-NativeCapture -FilePath $nativeOutput
    Assert-Success -Action "generated hello.exe" -Result $programResult
    if ($programResult.Output -ne "hello, saasm") {
        throw "Unexpected generated program output: $($programResult.Output)"
    }

    $wasmResult = Invoke-NativeCapture -FilePath $sa -Arguments @("build-wasm", $tempDemo, "-o", $wasmOutput, "--target", "wasm32")
    Assert-Success -Action "staged sa.exe build-wasm" -Result $wasmResult
    if (-not (Test-Path -LiteralPath $wasmOutput -PathType Leaf)) {
        throw "sa.exe build-wasm did not create $wasmOutput"
    }
    $wasmBytes = [IO.File]::ReadAllBytes($wasmOutput)
    if ($wasmBytes.Length -lt 4 -or
        $wasmBytes[0] -ne 0x00 -or
        $wasmBytes[1] -ne 0x61 -or
        $wasmBytes[2] -ne 0x73 -or
        $wasmBytes[3] -ne 0x6D) {
        throw "sa.exe build-wasm did not create a WebAssembly module"
    }

    $installResult = Invoke-NativeCapture -FilePath $sa -Arguments @("pkg", "install", "--offline", "github.com/example/pkg")
    Assert-Success -Action "offline package install" -Result $installResult
    if (-not (Test-Path -LiteralPath $vendorPackage -PathType Leaf)) {
        throw "offline package install did not create $vendorPackage"
    }

    Remove-Item -LiteralPath (Join-Path $packageProjectRoot "github.com") -Recurse -Force
    $offlineCheckResult = Invoke-NativeCapture -FilePath $sa -Arguments @("check", $packageMain, "--offline")
    Assert-Success -Action "offline package resolve" -Result $offlineCheckResult

    $missingResult = Invoke-NativeCapture -FilePath $sa -Arguments @("pkg", "install", "--offline", "github.com/example/missing", "--json")
    if ($missingResult.ExitCode -ne 1) {
        throw "missing offline package returned $($missingResult.ExitCode), expected 1.`n$($missingResult.Output)"
    }
    if ($missingResult.Output -notmatch '"name"\s*:\s*"SourceNotFound"') {
        throw "missing offline package did not report SourceNotFound.`n$($missingResult.Output)"
    }

    $installerReleaseRootUri = ([Uri]((Resolve-Path -LiteralPath $installerReleaseRoot).Path + [IO.Path]::DirectorySeparatorChar)).AbsoluteUri.TrimEnd("/")
    [Environment]::SetEnvironmentVariable("SA_RELEASE_URL", $installerReleaseRootUri, "Process")
    Write-Host "Running install.ps1 against local release archive $installerReleaseRootUri"
    & (Join-Path $repoRoot "tools\install.ps1") -Dir $installerRoot -NoShell
    $installedSa = Join-Path $installerRoot "bin\sa.exe"
    $installedStdRoot = Join-Path $installerRoot "std"
    foreach ($requiredPath in @(
        $installedSa,
        (Join-Path $installedStdRoot "sa_std.lib"),
        (Join-Path $installedStdRoot "sa_std.h"),
        (Join-Path $installedStdRoot "io\print.sai"))) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "install.ps1 local release install is missing $requiredPath"
        }
    }
    $installedVersion = Invoke-NativeCapture -FilePath $installedSa -Arguments @("version")
    Assert-Success -Action "installed sa.exe version" -Result $installedVersion
    if ($installedVersion.Output -notmatch '^sa\s+\S+$') {
        throw "Unexpected installed version output: $($installedVersion.Output)"
    }
    [Environment]::SetEnvironmentVariable("SA_STD_DIR", $installedStdRoot, "Process")
    $installedCheck = Invoke-NativeCapture -FilePath $installedSa -Arguments @("check", $tempDemo)
    Assert-Success -Action "installed sa.exe check" -Result $installedCheck

    $releaseHttp = Start-ReleaseHttpServer -Root $installerReleaseRoot -PortFile $httpPortFile
    $releaseHttpJob = $releaseHttp.Job
    [Environment]::SetEnvironmentVariable("SA_RELEASE_URL", $releaseHttp.Url, "Process")
    Write-Host "Running install.ps1 against HTTP release archive $($releaseHttp.Url)"
    & (Join-Path $repoRoot "tools\install.ps1") -Dir $httpInstallerRoot -NoShell
    $httpInstalledSa = Join-Path $httpInstallerRoot "bin\sa.exe"
    $httpInstalledStdRoot = Join-Path $httpInstallerRoot "std"
    foreach ($requiredPath in @(
        $httpInstalledSa,
        (Join-Path $httpInstalledStdRoot "sa_std.lib"),
        (Join-Path $httpInstalledStdRoot "sa_std.h"),
        (Join-Path $httpInstalledStdRoot "io\print.sai"))) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "install.ps1 HTTP release install is missing $requiredPath"
        }
    }
    $httpInstalledVersion = Invoke-NativeCapture -FilePath $httpInstalledSa -Arguments @("version")
    Assert-Success -Action "HTTP installed sa.exe version" -Result $httpInstalledVersion
    [Environment]::SetEnvironmentVariable("SA_STD_DIR", $httpInstalledStdRoot, "Process")
    $httpInstalledCheck = Invoke-NativeCapture -FilePath $httpInstalledSa -Arguments @("check", $tempDemo)
    Assert-Success -Action "HTTP installed sa.exe check" -Result $httpInstalledCheck

    if (-not [string]::IsNullOrWhiteSpace($EvidencePath)) {
        $evidenceParent = Split-Path -Parent $EvidencePath
        if (-not [string]::IsNullOrWhiteSpace($evidenceParent)) {
            [void][IO.Directory]::CreateDirectory($evidenceParent)
        }
        [pscustomobject]@{
            platform = "windows"
            arch = $archiveArch
            archive = "$archivePayloadName.zip"
            github_sha = $env:GITHUB_SHA
            github_run_id = $env:GITHUB_RUN_ID
            github_run_attempt = $env:GITHUB_RUN_ATTEMPT
            installer_transports = @("file", "http")
            staged_version = $versionResult.Output
            installed_version = $installedVersion.Output
            wasm_magic = "0061736d"
            native_smoke = "passed"
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $EvidencePath -Encoding utf8
    }
} finally {
    if ($null -ne $releaseHttpJob) {
        Stop-Job -Job $releaseHttpJob -ErrorAction SilentlyContinue
        Remove-Job -Job $releaseHttpJob -Force -ErrorAction SilentlyContinue
    }
    if ($locationPushed) {
        Pop-Location
    }
    foreach ($name in $environmentNames) {
        [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], "Process")
    }
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "Windows native compiler smoke passed."

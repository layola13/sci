#Requires-Version 7.0
<#
.SYNOPSIS
  Fetch prebuilt `sa` binaries from a GitHub Release into the platform
  package dirs (Windows publisher flow: no rebuild needed).
.DESCRIPTION
  Binaries are intentionally NOT committed to git (~95MB); the GitHub
  Release is the binary store. Rebuilding instead? See
  tools/stage-binaries.sh and the sala "多平台编译" chapter.
.EXAMPLE
  powershell tools/fetch-binaries.ps1
  powershell tools/fetch-binaries.ps1 -Version 0.1.2
#>
param(
    [string]$Version = "0.1.2"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent
$Base = "https://github.com/layola13/sci/releases/download/$Version"

# asset suffix -> package suffix -> binary name
$Map = @(
    @("linux-x86_64", "linux-x64", "sa"),
    @("arm-aarch64", "linux-arm64", "sa"),
    @("mac-aarch64", "darwin-arm64", "sa"),
    @("mac-x86_64", "darwin-x64", "sa"),
    @("windows-x86_64", "win32-x64", "sa.exe"),
    @("freebsd-x86_64", "freebsd-x64", "sa")
)

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) "sa-fetch-$Version"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

foreach ($m in $Map) {
    $Url = "$Base/sa-$Version-$($m[0]).zip"
    $Zip = Join-Path $Tmp "sa-$Version-$($m[0]).zip"
    $DestDir = Join-Path $Root "packages/sa-$($m[1])/bin"
    Write-Host "[i] $Url"
    Invoke-WebRequest -Uri $Url -OutFile $Zip
    # Expand only the wanted binary (skip hubproxy/pdb).
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Fs = [System.IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        foreach ($e in $Fs.Entries) {
            if ($e.Name -eq $m[2]) {
                $Dest = Join-Path $DestDir $m[2]
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($e, $Dest, $true)
            }
        }
    }
    finally { $Fs.Dispose() }
    Write-Host "[ok] sa-$($m[1]) <= sa-$Version-$($m[0]).zip"
}

Remove-Item -Recurse -Force $Tmp
Write-Host "[✓] all platform binaries staged under npm/packages/*/bin"

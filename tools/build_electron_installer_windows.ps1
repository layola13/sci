[CmdletBinding()]
param(
  [string]$Output='dist/SCI-windows-x64-full.zip',
  [string]$LlvmBin='D:\LLVM-14.0.6\bin',
  [int]$TimeoutSeconds=900,
  [switch]$SkipBundle
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$installer=Join-Path $repo 'tools/electron-installer'
if(-not $SkipBundle){
  & (Join-Path $repo 'tools/package_windows.ps1') -Output $Output -LlvmBin $LlvmBin -TimeoutSeconds $TimeoutSeconds
  if($LASTEXITCODE -ne 0){throw "bundle generation failed: $LASTEXITCODE"}
}
if(-not (Test-Path -LiteralPath (Join-Path $repo $Output) -PathType Leaf)){throw "bundle not found: $Output"}
Push-Location $installer
try {
  if(-not (Test-Path -LiteralPath 'node_modules')) {
    npm install --no-audit --no-fund
    if($LASTEXITCODE -ne 0){throw "npm install failed: $LASTEXITCODE"}
  }
  npm run dist
  if($LASTEXITCODE -ne 0){throw "electron-builder failed: $LASTEXITCODE"}
} finally { Pop-Location }

#Requires -Version 7.0
<#
.SYNOPSIS
  Publish all @salang/sa packages in dependency order (Windows flow).
.DESCRIPTION
  Platform packages first, meta package last. Extra args forwarded to
  `npm publish` (e.g. -WhatIf style check via --dry-run).
.EXAMPLE
  powershell tools/publish-all.ps1 --dry-run
  powershell tools/publish-all.ps1
#>
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$NpmArgs
)

$ErrorActionPreference = "Stop"
$Root = Split-Path $PSScriptRoot -Parent

@(
    "sa-linux-x64", "sa-linux-arm64", "sa-darwin-arm64",
    "sa-darwin-x64", "sa-win32-x64", "sa-freebsd-x64"
) | ForEach-Object {
    Write-Host "=== publishing @salang/$_"
    Push-Location (Join-Path $Root "packages/$_")
    try {
        npm publish --access public @NpmArgs
        if ($LASTEXITCODE -ne 0) { throw "npm publish failed for $_" }
    }
    finally { Pop-Location }
}

Write-Host "=== publishing @salang/sa"
Push-Location (Join-Path $Root "packages/sa")
try {
    npm publish --access public @NpmArgs
    if ($LASTEXITCODE -ne 0) { throw "npm publish failed for sa" }
}
finally { Pop-Location }

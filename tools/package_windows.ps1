[CmdletBinding()]
param(
  [string]$Workspace=(Split-Path -Parent (Split-Path -Parent $PSScriptRoot)),
  [string]$Output='', [switch]$Include3D, [switch]$SkipBuild,
  [string]$Zig='D:\zig-x86_64-windows-0.14.1\zig.exe', [string]$LlvmBin='D:\LLVM-14.0.6\bin', [int]$TimeoutSeconds=900
)
$ErrorActionPreference='Stop'
$workspaceRoot=(Resolve-Path -LiteralPath $Workspace).Path
$sciRoot=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputPath=if($Output){[IO.Path]::GetFullPath($Output)}else{Join-Path $sciRoot 'dist\SCI-windows-x64-full.zip'}
$stage=Join-Path $sciRoot '.dist_stage_full'
function Invoke-Bounded([string]$File,[string[]]$Args,[string]$Cwd,[int]$Seconds){
  $p=Start-Process -FilePath $File -ArgumentList $Args -WorkingDirectory $Cwd -PassThru -WindowStyle Hidden
  if(-not $p.WaitForExit($Seconds*1000)){$p.Kill();throw "Timed out: $File"}
  if($p.ExitCode -ne 0){throw "Command failed ($($p.ExitCode)): $File"}
}
function Copy-Required([string]$Source,[string]$Destination){
  if(-not(Test-Path -LiteralPath $Source -PathType Leaf)){throw "Missing required file: $Source"}
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination)|Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination -Force
}
function Copy-FileRelative([string]$Root,[string]$Relative,[string]$DestinationRoot){
  if([string]::IsNullOrWhiteSpace($Relative)){return}
  $source=Join-Path $Root $Relative
  if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw "Missing runtime file: $source"}
  $destination=Join-Path $DestinationRoot $Relative
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
  Copy-Item -LiteralPath $source -Destination $destination -Force
}
function Copy-ManifestPaths([string]$Root,[object]$Value,[string]$DestinationRoot){
  if($null -eq $Value -or $Value -is [string]){return}
  if($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]){
    foreach($item in $Value){Copy-ManifestPaths $Root $item $DestinationRoot}
    return
  }
  foreach($property in $Value.psobject.Properties){
    if($property.Name -eq 'path' -and $property.Value -is [string]){Copy-FileRelative $Root ([string]$property.Value) $DestinationRoot}
    elseif($property.Name -notin @('dependencies','source','artifacts')){Copy-ManifestPaths $Root $property.Value $DestinationRoot}
  }
}
function Copy-SourceDirectory([string]$Root,[string]$Relative,[string]$DestinationRoot){
  $source=Join-Path $Root $Relative
  if(-not(Test-Path -LiteralPath $source -PathType Container)){return}
  $excludedDirs=@('.git','.sa_cache','.zig-cache','.zig-global-cache','node_modules','zig-out','bin','target','build')
  $excludedExtensions=@('.exe','.dll','.pdb','.lib','.obj','.o','.a','.so','.dylib','.bc','.wasm','.log','.tmp')
  Get-ChildItem -LiteralPath $source -Recurse -File | ForEach-Object {
    $relativePath=$_.FullName.Substring($source.Length).TrimStart('\','/')
    $parts=$relativePath -split '[\\/]'
    if($parts | Where-Object {$_ -in $excludedDirs}){return}
    if($_.Extension.ToLowerInvariant() -in $excludedExtensions){return}
    $destination=Join-Path (Join-Path $DestinationRoot $Relative) $relativePath
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination)|Out-Null
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
  }
}
function New-PackagedPluginLocks([string]$PluginRoot,[string]$PluginName,[string]$Artifact,[string]$SaPath,[string]$Destination){
  $reviewOut=Join-Path $env:TEMP "sa_package_review_$PluginName.log"
  $reviewErr=Join-Path $env:TEMP "sa_package_review_$PluginName.err.log"
  $p=Start-Process -FilePath $SaPath -ArgumentList @('plugin','install','--review',$PluginRoot) -PassThru -WindowStyle Hidden -RedirectStandardOutput $reviewOut -RedirectStandardError $reviewErr -Wait
  if($p.ExitCode -ne 0){$details=if(Test-Path -LiteralPath $reviewErr){Get-Content -LiteralPath $reviewErr -Raw -Encoding UTF8}else{''};throw "Failed generating packaged lock for $PluginName (exit code $($p.ExitCode)): $details"}
  $perm=Get-Content -LiteralPath $reviewOut -Raw -Encoding UTF8
  $perm=[regex]::Replace($perm,'(?m)^confirmed=.*$','confirmed=true')
  $perm=[regex]::Replace($perm,'(?m)^dev_install=.*$','dev_install=false')
  $perm=[regex]::Replace($perm,'(?m)^sandbox_enforced=.*$','sandbox_enforced=true')
  $perm=$perm.TrimEnd()+[Environment]::NewLine
  $permDigest=([regex]::Match($perm,'(?m)^permissions_sha256=([^`r`n]+)').Groups[1].Value)
  $graphDigest=([regex]::Match($perm,'(?m)^dependency_graph_sha256=([^`r`n]+)').Groups[1].Value)
  $manifest=Get-Content -LiteralPath (Join-Path $PluginRoot 'sap.json') -Raw -Encoding UTF8|ConvertFrom-Json
  $hash=(Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash.ToLowerInvariant()
  $lock="name=$($manifest.name)`nversion=$($manifest.version)`nartifact=$([IO.Path]::GetFileName($Artifact))`nsha256=$hash`npermissions_sha256=$permDigest`ndependency_graph_sha256=$graphDigest`ndependencies=0`n"
  $lock|Set-Content -LiteralPath (Join-Path $Destination 'sap.lock') -Encoding UTF8
  $perm|Set-Content -LiteralPath (Join-Path $Destination 'permissions.lock') -Encoding UTF8
}
if(-not $SkipBuild){
  if(-not(Test-Path -LiteralPath $Zig -PathType Leaf)){$z=Get-Command zig.exe -ErrorAction SilentlyContinue;if($null -eq $z){throw 'zig.exe not found; pass -Zig or use -SkipBuild.'};$Zig=$z.Source}
  Invoke-Bounded $Zig @('build','install','-Dllvm=true','-Dllvm-include-dir=D:\LLVM-14.0.6\include','-Dllvm-lib-dir=D:\LLVM-14.0.6\lib','-Dllvm-lib-name=LLVM-C','--summary','all') $sciRoot $TimeoutSeconds
}
if(Test-Path -LiteralPath $stage){Remove-Item -LiteralPath $stage -Recurse -Force}
New-Item -ItemType Directory -Force -Path $stage|Out-Null
foreach($d in @('bin','include','std','plugins')){New-Item -ItemType Directory -Force -Path (Join-Path $stage $d)|Out-Null}
Copy-Required (Join-Path $sciRoot 'zig-out\bin\sa.exe') (Join-Path $stage 'bin\sa.exe')
foreach($n in @('sa.pdb','LLVM-C.dll','hubproxy.exe','hubproxy.pdb')){$s=Join-Path $sciRoot "zig-out\bin\$n";if(Test-Path -LiteralPath $s -PathType Leaf){Copy-Item -LiteralPath $s -Destination (Join-Path $stage "bin\$n") -Force}}
Copy-Required (Join-Path $sciRoot 'zig-out\include\sa_std.h') (Join-Path $stage 'include\sa_std.h')
Copy-Item -LiteralPath (Join-Path $sciRoot 'sa_std') -Destination (Join-Path $stage 'std') -Recurse -Force
$stdLib=Join-Path $sciRoot 'zig-out\lib\sa_std.lib';if(Test-Path -LiteralPath $stdLib -PathType Leaf){Copy-Item -LiteralPath $stdLib -Destination (Join-Path $stage 'std\sa_std.lib') -Force}
$llvmRuntimeNames=@('LLVM-C.dll','Remarks.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','ucrtbase.dll','libomp.dll')
foreach($n in $llvmRuntimeNames){$s=Join-Path $LlvmBin $n;if(Test-Path -LiteralPath $s -PathType Leaf){Copy-Item -LiteralPath $s -Destination (Join-Path $stage "bin\$n") -Force}}
$llvmToolFound=$false
foreach($n in @('llvm-dis-14.exe','llvm-dis.exe','llvm-as-14.exe','llvm-as.exe')){$s=Join-Path $LlvmBin $n;if(Test-Path -LiteralPath $s -PathType Leaf){Copy-Item -LiteralPath $s -Destination (Join-Path $stage "bin\$n") -Force;$llvmToolFound=$true}}
if(-not $llvmToolFound){Write-Warning "No llvm-dis/llvm-as Windows tool found under $LlvmBin; bc2sa bitcode translation will require a separately installed LLVM tool."}
$slaRoot=Join-Path $workspaceRoot 'sa_plugin_sla';Copy-Required (Join-Path $slaRoot 'zig-out\bin\sla.exe') (Join-Path $stage 'bin\sla.exe')
foreach($n in @('sla.pdb','sla.dll')){$s=Join-Path $slaRoot "zig-out\bin\$n";if(Test-Path -LiteralPath $s -PathType Leaf){Copy-Item -LiteralPath $s -Destination (Join-Path $stage "bin\$n") -Force}}
$roots=@(Get-ChildItem -LiteralPath $workspaceRoot -Directory -Filter 'sa_plugin_*');if($Include3D){$roots+=@(Get-ChildItem -LiteralPath (Join-Path $workspaceRoot 'sa_plugin_3dengines') -Directory -Filter 'sa_plugin_3d_*')}
$excludedPluginRoots=@('sa_plugin_3dengines','sa_plugin_ts')
$seen=@{}
foreach($root in $roots){
  if($root.Name -in $excludedPluginRoots){continue}
  $mp=Join-Path $root.FullName 'sap.json';if(-not(Test-Path -LiteralPath $mp -PathType Leaf)){continue}
  $m=Get-Content -LiteralPath $mp -Raw -Encoding UTF8|ConvertFrom-Json;$name=[string]$m.name;if($seen.ContainsKey($name)){continue}
  $artifact=$m.artifacts.'windows-x86_64'.path;if([string]::IsNullOrWhiteSpace($artifact)){throw "No Windows artifact: $mp"}
  $ap=Join-Path $root.FullName $artifact;if(-not(Test-Path -LiteralPath $ap -PathType Leaf)){throw "Missing artifact for $name`: $ap"}
  $destination=Join-Path $stage "plugins\$($root.Name)";New-Item -ItemType Directory -Force -Path $destination|Out-Null
  Copy-Item -LiteralPath $mp -Destination (Join-Path $destination 'sap.json') -Force
  Copy-FileRelative $root.FullName $artifact $destination
  Copy-ManifestPaths $root.FullName $m.interfaces $destination
  Copy-ManifestPaths $root.FullName $m.assets $destination
  Copy-SourceDirectory $root.FullName 'demos' $destination
  Copy-SourceDirectory $root.FullName 'examples' $destination
  New-PackagedPluginLocks $root.FullName $name $ap (Join-Path $stage 'bin\sa.exe') $destination
  $seen[$name]=$root.Name
}
$meta=[ordered]@{schema='sa.bundle/1';platform='windows-x86_64';generated_utc=(Get-Date).ToUniversalTime().ToString('o');compiler='bin/sa.exe';sla='bin/sla.exe';llvm_tools_present=$llvmToolFound;plugins=@($seen.Keys|Sort-Object)}
$meta|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $stage 'bundle.json') -Encoding UTF8
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outputPath)|Out-Null
if(Test-Path -LiteralPath $outputPath){Remove-Item -LiteralPath $outputPath -Force}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $outputPath -Force
Remove-Item -LiteralPath $stage -Recurse -Force
Write-Host "Created full Windows bundle: $outputPath" -ForegroundColor Green
Write-Host ("Plugins: {0}" -f (($seen.Keys|Sort-Object)-join ', '))

[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Bundle,
  [string]$InstallRoot=(Join-Path $env:LOCALAPPDATA 'Programs\SCI\current'),
  [string]$PluginHome=(Join-Path $env:LOCALAPPDATA 'sa_plugins'),
  [int]$TimeoutSeconds=300, [switch]$NoPath, [switch]$EnablePluginDevMode
)
$ErrorActionPreference='Stop'
function Get-ManifestEntries([object]$Value){
  if($null -eq $Value -or $Value -is [string]){return}
  if($Value -is [System.Collections.IEnumerable] -and $Value -isnot [System.Collections.IDictionary]){foreach($item in $Value){Get-ManifestEntries $item};return}
  $pathProp=$Value.psobject.Properties['path']
  if($null -ne $pathProp -and $pathProp.Value -is [string]){
    $targetProp=$Value.psobject.Properties['target']
    [pscustomobject]@{Path=[string]$pathProp.Value;Target=if($null -ne $targetProp){[string]$targetProp.Value}else{''}}
    return
  }
  foreach($property in $Value.psobject.Properties){Get-ManifestEntries $property.Value}
}
function Write-PluginLayout([string]$PluginRoot,[string]$PluginName,[string]$PluginHome,[string]$SaPath,[int]$Timeout){
  $manifestPath=Join-Path $PluginRoot 'sap.json'
  $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8|ConvertFrom-Json
  $version=[string]$manifest.version
  $base=Join-Path $PluginHome "installed\$PluginName"
  $current=Join-Path $base 'current';$versionDir=Join-Path $base $version
  foreach($dir in @($current,$versionDir)){if(Test-Path -LiteralPath $dir){Remove-Item -LiteralPath $dir -Recurse -Force};New-Item -ItemType Directory -Force -Path $dir|Out-Null}
  $artifactRel=[string]$manifest.artifacts.'windows-x86_64'.path
  $artifact=Join-Path $PluginRoot $artifactRel
  if(-not(Test-Path -LiteralPath $artifact -PathType Leaf)){throw "Missing packaged artifact for $PluginName`: $artifact"}
  foreach($dest in @($current,$versionDir)){Copy-Item -LiteralPath $artifact -Destination (Join-Path $dest ([IO.Path]::GetFileName($artifact))) -Force;Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $dest 'sap.json') -Force}
  foreach($entry in @(Get-ManifestEntries $manifest.interfaces)){
    $src=Join-Path $PluginRoot $entry.Path
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Missing packaged interface: $src"}
    foreach($dest in @($current,$versionDir)){ $saDir=Join-Path $dest 'sa';New-Item -ItemType Directory -Force -Path $saDir|Out-Null;Copy-Item -LiteralPath $src -Destination (Join-Path $saDir ([IO.Path]::GetFileName($entry.Path))) -Force }
  }
  foreach($entry in @(Get-ManifestEntries $manifest.assets)){
    $src=Join-Path $PluginRoot $entry.Path
    if(-not(Test-Path -LiteralPath $src -PathType Leaf)){throw "Missing packaged asset: $src"}
    $target=if([string]::IsNullOrWhiteSpace($entry.Target)){[IO.Path]::GetFileName($entry.Path)}else{$entry.Target}
    foreach($dest in @($current,$versionDir)){ $assetDest=Join-Path (Join-Path $dest 'share') $target;New-Item -ItemType Directory -Force -Path (Split-Path -Parent $assetDest)|Out-Null;Copy-Item -LiteralPath $src -Destination $assetDest -Force }
  }
  foreach($sourceDir in @('demos','examples')){ $srcDir=Join-Path $PluginRoot $sourceDir;if(Test-Path -LiteralPath $srcDir -PathType Container){foreach($dest in @($current,$versionDir)){Copy-Item -LiteralPath $srcDir -Destination (Join-Path $dest $sourceDir) -Recurse -Force}} }
  $packagedLock=Join-Path $PluginRoot 'sap.lock';$packagedPermissions=Join-Path $PluginRoot 'permissions.lock'
  if((Test-Path -LiteralPath $packagedLock -PathType Leaf) -and (Test-Path -LiteralPath $packagedPermissions -PathType Leaf)){
    foreach($dest in @($current,$versionDir)){Copy-Item -LiteralPath $packagedLock -Destination (Join-Path $dest 'sap.lock') -Force;Copy-Item -LiteralPath $packagedPermissions -Destination (Join-Path $dest 'permissions.lock') -Force}
    return
  }
  $reviewOut=Join-Path $env:TEMP "sa_review_$PluginName.log";$reviewErr=Join-Path $env:TEMP "sa_review_$PluginName.err.log"
  $psi=New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName=$SaPath
  $quotedRoot='"'+$PluginRoot.Replace('"','\"')+'"'
  $psi.Arguments="plugin install --review $quotedRoot"
  $psi.WorkingDirectory=$PluginRoot
  $psi.UseShellExecute=$false
  $psi.CreateNoWindow=$true
  $psi.RedirectStandardOutput=$true
  $psi.RedirectStandardError=$true
  $process=New-Object System.Diagnostics.Process
  $process.StartInfo=$psi
  [void]$process.Start()
  $stdoutTask=$process.StandardOutput.ReadToEndAsync()
  $stderrTask=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($Timeout*1000)){
    try{$process.Kill()}catch{}
    $process.Dispose()
    throw "Timed out generating lock for $PluginName"
  }
  $process.WaitForExit()
  $exitCode=$process.ExitCode
  $review=$stdoutTask.GetAwaiter().GetResult()
  $details=$stderrTask.GetAwaiter().GetResult()
  $process.Dispose()
  $review|Set-Content -LiteralPath $reviewOut -Encoding UTF8
  $details|Set-Content -LiteralPath $reviewErr -Encoding UTF8
  if($exitCode -ne 0){throw "Failed generating lock for $PluginName (exit code $exitCode): $details"}
  $perm=$review
  $perm=[regex]::Replace($perm,'(?m)^confirmed=.*$','confirmed=true')
  $perm=[regex]::Replace($perm,'(?m)^dev_install=.*$','dev_install=false')
  $perm=[regex]::Replace($perm,'(?m)^sandbox_enforced=.*$','sandbox_enforced=true')
  $perm=$perm.TrimEnd()+[Environment]::NewLine
  $permDigest=([regex]::Match($perm,'(?m)^permissions_sha256=([^`r`n]+)').Groups[1].Value)
  $graphDigest=([regex]::Match($perm,'(?m)^dependency_graph_sha256=([^`r`n]+)').Groups[1].Value)
  $hash=(Get-FileHash -LiteralPath $artifact -Algorithm SHA256).Hash.ToLowerInvariant();$artifactName=[IO.Path]::GetFileName($artifact)
  $lock="name=$PluginName`nversion=$version`nartifact=$artifactName`nsha256=$hash`npermissions_sha256=$permDigest`ndependency_graph_sha256=$graphDigest`ndependencies=0`n"
  foreach($dest in @($current,$versionDir)){$lock|Set-Content -LiteralPath (Join-Path $dest 'sap.lock') -Encoding UTF8;$perm|Set-Content -LiteralPath (Join-Path $dest 'permissions.lock') -Encoding UTF8}
}
$bundlePath=(Resolve-Path -LiteralPath $Bundle).Path
$temp=Join-Path $env:TEMP ("sa_bundle_{0}" -f [guid]::NewGuid().ToString('N'))
$stage=Join-Path $temp 'payload';$installTemp="$InstallRoot.__new";$backup="$InstallRoot.__old";$replaced=$false
New-Item -ItemType Directory -Force -Path $stage|Out-Null
try{
  Expand-Archive -LiteralPath $bundlePath -DestinationPath $stage -Force
  $payload=$stage;$nested=@(Get-ChildItem -LiteralPath $stage -Directory)
  if($nested.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $nested[0].FullName 'bundle.json'))){$payload=$nested[0].FullName}
  $metaPath=Join-Path $payload 'bundle.json';if(-not(Test-Path -LiteralPath $metaPath -PathType Leaf)){throw 'Invalid bundle: bundle.json is missing.'}
  $meta=Get-Content -LiteralPath $metaPath -Raw -Encoding UTF8|ConvertFrom-Json
  if($meta.schema -ne 'sa.bundle/1' -or $meta.platform -ne 'windows-x86_64'){throw 'Unsupported bundle schema or platform.'}
  foreach($r in @('bin\sa.exe','bin\sla.exe','std')){if(-not(Test-Path -LiteralPath (Join-Path $payload $r))){throw "Invalid bundle: missing $r"}}
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $InstallRoot)|Out-Null
  if(Test-Path -LiteralPath $installTemp){Remove-Item -LiteralPath $installTemp -Recurse -Force};New-Item -ItemType Directory -Force -Path $installTemp|Out-Null
  foreach($d in @('bin','include','std')){Copy-Item -LiteralPath (Join-Path $payload $d) -Destination $installTemp -Recurse -Force}
  if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Recurse -Force};if(Test-Path -LiteralPath $InstallRoot){Move-Item -LiteralPath $InstallRoot -Destination $backup -Force};Move-Item -LiteralPath $installTemp -Destination $InstallRoot -Force;$replaced=$true
  $sa=Join-Path $InstallRoot 'bin\sa.exe';$oldPluginHome=$env:SA_PLUGINS_HOME;$env:SA_PLUGINS_HOME=$PluginHome;New-Item -ItemType Directory -Force -Path $PluginHome|Out-Null
  $pluginDirs=Get-ChildItem -LiteralPath (Join-Path $payload 'plugins') -Directory
  foreach($plugin in $meta.plugins){
    $root=$pluginDirs|Where-Object{$p=Join-Path $_.FullName 'sap.json';(Test-Path -LiteralPath $p -PathType Leaf) -and ((Get-Content -LiteralPath $p -Raw -Encoding UTF8|ConvertFrom-Json).name -eq $plugin)}|Select-Object -First 1
    if($null -eq $root){throw "Bundle metadata references missing plugin: $plugin"}
    Write-PluginLayout $root.FullName $plugin $PluginHome $sa $TimeoutSeconds
  }
  if(-not $NoPath){$userPath=[Environment]::GetEnvironmentVariable('Path','User');$bin=Join-Path $InstallRoot 'bin';if($userPath -notlike "*$bin*"){[Environment]::SetEnvironmentVariable('Path',($userPath.TrimEnd(';')+';'+$bin),'User')}[Environment]::SetEnvironmentVariable('SA_STD_DIR',(Join-Path $InstallRoot 'std'),'User');[Environment]::SetEnvironmentVariable('SA_PLUGINS_HOME',$PluginHome,'User');if($EnablePluginDevMode){[Environment]::SetEnvironmentVariable('SA_PLUGIN_DEV','1','User')}}
  & (Join-Path $InstallRoot 'bin\sa.exe') --version;& (Join-Path $InstallRoot 'bin\sla.exe') --version
  if(Test-Path -LiteralPath $backup){Remove-Item -LiteralPath $backup -Recurse -Force};Write-Host "Installed SA bundle to $InstallRoot" -ForegroundColor Green
}catch{
  if($replaced -and (Test-Path -LiteralPath $InstallRoot)){Remove-Item -LiteralPath $InstallRoot -Recurse -Force};if(Test-Path -LiteralPath $backup){Move-Item -LiteralPath $backup -Destination $InstallRoot -Force};throw
}finally{if(Test-Path -LiteralPath $installTemp){Remove-Item -LiteralPath $installTemp -Recurse -Force -ErrorAction SilentlyContinue};if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}}

[CmdletBinding()]
param(
    [ValidateSet('vdd','vmouse','all')][string]$Component = 'all',
    [Parameter(Mandatory)][string]$OutputDirectory
)
# Package existing signed drivers and build the optional HDR tools; no Core/GUI build or installation.
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Choose a fresh output directory; existing files are never overwritten.' }
. (Join-Path $root 'src_assets/windows/misc/verify-driver-certificate.ps1')
$components = if ($Component -eq 'all') { @('vdd','vmouse') } else { @($Component) }
foreach ($name in $components) {
    $driver = if ($name -eq 'vdd') { 'VDD' } else { 'VirtualMouse' }
    Assert-DriverCertificate $driver (Join-Path $root "src_assets/windows/drivers/$name")
}
[void][IO.Directory]::CreateDirectory($output)
# Share Lite's pin so the external-tool update workflow updates both packages.
$cmakePins = Get-Content (Join-Path $root 'cmake/packaging/FetchDriverDeps.cmake') -Raw
$nefconVersion = [regex]::Match($cmakePins, 'set\(NEFCON_VERSION "(v[0-9]+\.[0-9]+\.[0-9]+)"').Groups[1].Value
$nefconHash = [regex]::Match($cmakePins, 'set\(NEFCON_SHA256 "([a-fA-F0-9]{64})"').Groups[1].Value
if (-not $nefconHash) {
    $pinName = '_NEFCON_SHA256_' + $nefconVersion.ToUpperInvariant().Replace('.','_')
    $nefconHash = [regex]::Match($cmakePins, ('set\(' + $pinName + ' "([a-fA-F0-9]{64})"')).Groups[1].Value
}
if (-not $nefconVersion -or -not $nefconHash) { throw 'Cannot resolve Lite nefcon version/hash pin.' }
$dependency = Join-Path $output "nefcon-$nefconVersion.zip"
Invoke-WebRequest -Uri "https://github.com/nefarius/nefcon/releases/download/$nefconVersion/nefcon_$nefconVersion.zip" -OutFile $dependency
if ((Get-FileHash -LiteralPath $dependency -Algorithm SHA256).Hash -ine $nefconHash) {
    throw 'nefcon archive integrity mismatch.'
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($dependency)
try {
    $entry = $archive.GetEntry('x64/nefconw.exe')
    if (-not $entry) { throw 'Missing x64 nefcon executable.' }
    $nefconBytes = [IO.MemoryStream]::new()
    $stream = $entry.Open()
    try { $stream.CopyTo($nefconBytes) } finally { $stream.Dispose() }
    $nefcon = $nefconBytes.ToArray(); $nefconBytes.Dispose()
} finally { $archive.Dispose() }
$bridgeOutput = $null
if ($components -contains 'vdd') {
    $bridgeBuild = Join-Path $output 'vulkan-hdr-build'
    & cmake -S (Join-Path $root 'third-party/zako-vulkan-hdr') -B $bridgeBuild -DCMAKE_BUILD_TYPE=Release
    if ($LASTEXITCODE -ne 0) { throw 'Vulkan HDR tools configure failed.' }
    & cmake --build $bridgeBuild --config Release --parallel 2
    if ($LASTEXITCODE -ne 0) { throw 'Vulkan HDR tools build failed.' }
    $bridgeOutput = Join-Path $bridgeBuild 'bin'
}
foreach ($name in $components) {
    $source = Join-Path $root "src_assets/windows/drivers/$name"
    $manifest = Get-Content (Join-Path $source 'package.json') -Raw | ConvertFrom-Json
    $stage = Join-Path $output "Foundation-$name-$($manifest.version)"
    $scripts = Join-Path $stage 'scripts'
    $tools = Join-Path $stage 'tools'
    [void][IO.Directory]::CreateDirectory($scripts)
    [void][IO.Directory]::CreateDirectory($tools)
    [IO.File]::WriteAllBytes((Join-Path $tools 'nefconw.exe'),$nefcon)
    Copy-Item -LiteralPath (Join-Path $root 'src_assets/windows/misc/verify-driver-certificate.ps1') -Destination $scripts
    Copy-Item -LiteralPath (Join-Path $root 'src_assets/windows/misc/manage-driver.ps1') -Destination $stage
    if ($name -eq 'vdd') {
        $bridgeDestination = Join-Path $tools 'vulkan_hdr'
        [void][IO.Directory]::CreateDirectory($bridgeDestination)
        foreach ($file in @('zako_vulkan_hdr_bridge.dll','vulkan_hdr_probe.exe','VkLayer_zako_virtual_hdr.json','LICENSE','source.json')) {
            Copy-Item -LiteralPath (Join-Path $bridgeOutput $file) -Destination $bridgeDestination
        }
        $payload = Join-Path $scripts 'driver/latest'
        [void][IO.Directory]::CreateDirectory($payload)
        foreach ($file in @('install-vdd.bat','uninstall-vdd.bat','vdd-device-helper.ps1')) {
            Copy-Item -LiteralPath (Join-Path $root "src_assets/windows/misc/vdd/$file") -Destination $scripts
        }
        Copy-Item -LiteralPath (Join-Path $root 'src_assets/windows/misc/vdd/driver/vdd_settings.xml') -Destination (Join-Path $scripts 'driver')
    } else {
        $payload = Join-Path $scripts 'vmouse/driver'
        [void][IO.Directory]::CreateDirectory($payload)
        foreach ($file in @('install-vmouse.bat','uninstall-vmouse.bat','vmouse-device-helper.ps1','device-access.cs')) {
            Copy-Item -LiteralPath (Join-Path $root "src_assets/windows/misc/vmouse/$file") -Destination (Join-Path $scripts 'vmouse')
        }
    }
    foreach ($file in Get-ChildItem -LiteralPath $source -File) { Copy-Item -LiteralPath $file.FullName -Destination $payload }
    foreach ($action in @('Install','Uninstall')) {
        $cmd = '@echo off' + "`r`n" + 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0manage-driver.ps1" -Component ' + $name + ' -Action ' + $action + "`r`n" + 'exit /b %ERRORLEVEL%' + "`r`n"
        [IO.File]::WriteAllText((Join-Path $stage "$action.cmd"),$cmd,[Text.Encoding]::ASCII)
    }
    $inventory = foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File) {
        [ordered]@{path=$file.FullName.Substring($stage.Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
    }
    [ordered]@{schema=1;component=$name;version=$manifest.version;source_commit=$manifest.source_commit;files=@($inventory)} |
        ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $stage 'bundle.json') -Encoding utf8
    $zip = "$stage.zip"
    Compress-Archive -LiteralPath $stage -DestinationPath $zip
    Write-Output "$zip SHA256=$((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash)"
}

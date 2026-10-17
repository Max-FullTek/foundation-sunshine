param(
    [Parameter(Mandatory)][string]$CoreDirectory,
    [Parameter(Mandatory)][string]$WebUiDirectory,
    [Parameter(Mandatory)][string]$GuiDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/build-inputs.ps1"
$root = (Resolve-Path '.').Path
$core = (Resolve-Path $CoreDirectory).Path
$web = (Resolve-Path $WebUiDirectory).Path
$gui = (Resolve-Path $GuiDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'UI packaging requires a fresh output directory' }
$manifest = Get-Content (Join-Path $core 'core-build.json') -Raw | ConvertFrom-Json
if ($manifest.schema -ne 1 -or $manifest.inputs -ne (Get-BuildInputFingerprint)) {
    throw 'Core inputs changed. Run the full build; this core cannot be reused.'
}
foreach ($item in @(@('core-runtime.zip', $manifest.archive_sha256), @('installer.iss', $manifest.installer_sha256))) {
    if ($item[1] -notmatch '^[0-9a-f]{64}$' -or
        (Get-FileHash (Join-Path $core $item[0]) -Algorithm SHA256).Hash -ne $item[1]) {
        throw "Core integrity check failed: $($item[0])"
    }
}
foreach ($page in @('index', 'apps', 'config', 'password', 'pin', 'troubleshooting', 'welcome')) {
    if (-not (Test-Path -LiteralPath (Join-Path $web "$page.html") -PathType Leaf)) {
        throw "Incomplete WebUI: $page.html"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $gui 'sunshine-gui.exe') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $gui 'paired-build.json') -PathType Leaf)) {
    throw 'A verified complete GUI bundle is required'
}
New-Item -ItemType Directory -Path $output | Out-Null
Expand-Archive -LiteralPath (Join-Path $core 'core-runtime.zip') -DestinationPath $output
$stage = Join-Path $output 'runtime'
if ((Get-FileHash (Join-Path $stage 'sunshine.exe') -Algorithm SHA256).Hash -ne $manifest.executable_sha256) {
    throw 'Reused core executable checksum mismatch'
}
foreach ($name in @('web', 'gui')) {
    if (Test-Path -LiteralPath (Join-Path $stage "assets/$name")) {
        throw "Core-only artifact unexpectedly contains $name"
    }
}
Copy-Item -LiteralPath $web -Destination (Join-Path $stage 'assets/web') -Recurse
Copy-Item -LiteralPath $gui -Destination (Join-Path $stage 'assets/gui') -Recurse
$iss = Get-Content (Join-Path $core 'installer.iss') -Raw
$iss = $iss.Replace('@STAGING_ROOT@', $stage).Replace('@SOURCE_ROOT@', $root).Replace('@OUTPUT_ROOT@', $output)
if ($iss -match '@(?:STAGING|SOURCE|OUTPUT)_ROOT@') { throw 'Unresolved installer paths' }
[IO.File]::WriteAllText((Join-Path $output 'installer.iss'), $iss)
$panel = git rev-parse HEAD:src_assets/common/sunshine-control-panel
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve the pinned Panel' }
$manifest | Add-Member -NotePropertyName panel_commit -NotePropertyValue $panel
$manifest | Add-Member -NotePropertyName package_commit -NotePropertyValue (git rev-parse HEAD)
$manifest | ConvertTo-Json | Set-Content (Join-Path $stage 'assets/ui-package.json') -Encoding utf8
# Preserve the full build's portable ZIP layout, including its Sunshine/ root.
Add-Type -AssemblyName System.IO.Compression
$portable = [IO.Compression.ZipFile]::Open((Join-Path $output 'Sunshine.Portable-x64.zip'), 'Create')
try {
    foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\', '/')
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($portable, $file.FullName, "Sunshine/$relative", 'Optimal') | Out-Null
    }
} finally { $portable.Dispose() }
Write-Output "Reused core $($manifest.commit); SHA-256 $($manifest.executable_sha256)"

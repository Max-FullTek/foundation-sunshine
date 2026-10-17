param(
    [Parameter(Mandatory)][string]$StagingDirectory,
    [Parameter(Mandatory)][string]$InstallerScript,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/build-inputs.ps1"
$root = (Resolve-Path '.').Path
$stage = (Resolve-Path $StagingDirectory).Path
$output = [IO.Path]::GetFullPath($OutputDirectory)
if (Test-Path -LiteralPath $output) { throw 'Core export needs a fresh output directory' }
New-Item -ItemType Directory -Path $output | Out-Null
Add-Type -AssemblyName System.IO.Compression
$archive = Join-Path $output 'core-runtime.zip'
$zip = [IO.Compression.ZipFile]::Open($archive, 'Create')
try {
    foreach ($file in Get-ChildItem -LiteralPath $stage -Recurse -File) {
        $relative = [IO.Path]::GetRelativePath($stage, $file.FullName).Replace('\', '/')
        if ($relative -match '^assets/(web|gui)/') { continue }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, "runtime/$relative", 'Optimal') | Out-Null
    }
} finally { $zip.Dispose() }
$iss = Get-Content -LiteralPath $InstallerScript -Raw
# Configure-time paths belong to the old runner. Rebind only these known roots.
foreach ($old in @($stage, $stage.Replace('\', '/'))) { $iss = $iss.Replace($old, '@STAGING_ROOT@') }
foreach ($old in @($root, $root.Replace('\', '/'))) { $iss = $iss.Replace($old, '@SOURCE_ROOT@') }
$iss = $iss -replace '(?m)^OutputDir=.*$', 'OutputDir=@OUTPUT_ROOT@'
$issPath = Join-Path $output 'installer.iss'
[IO.File]::WriteAllText($issPath, $iss)
$commit = git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve core commit' }
@{
    schema = 1; repository = $env:GITHUB_REPOSITORY; commit = $commit
    run_id = $env:GITHUB_RUN_ID; inputs = Get-BuildInputFingerprint
    archive_sha256 = (Get-FileHash $archive -Algorithm SHA256).Hash.ToLowerInvariant()
    installer_sha256 = (Get-FileHash $issPath -Algorithm SHA256).Hash.ToLowerInvariant()
    executable_sha256 = (Get-FileHash (Join-Path $stage 'sunshine.exe') -Algorithm SHA256).Hash.ToLowerInvariant()
} | ConvertTo-Json | Set-Content (Join-Path $output 'core-build.json') -Encoding utf8

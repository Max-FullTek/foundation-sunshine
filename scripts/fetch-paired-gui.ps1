param(
    [ValidatePattern('^[0-9]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$Destination
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/build-inputs.ps1"
$panelDirectory = Join-Path (git rev-parse --show-toplevel) 'src_assets/common/sunshine-control-panel'
$panelUrl = git config -f .gitmodules --get submodule.src_assets/common/sunshine-control-panel.url
if ($LASTEXITCODE -ne 0 -or $panelUrl -notmatch '^https://github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+?)(?:\.git)?$') {
    throw 'Panel must use an explicit GitHub repository URL in .gitmodules'
}
$repository = $Matches[1]
$entry = git ls-tree HEAD src_assets/common/sunshine-control-panel
if ($LASTEXITCODE -ne 0 -or $entry -notmatch '^160000 commit ([0-9a-f]{40})\s') {
    throw 'Unable to resolve the committed Panel submodule'
}
$expectedCommit = $Matches[1]
$expectedInputs = Get-BuildInputFingerprint -Repository $panelDirectory -Commit $expectedCommit -Panel
function Test-GuiInputs([string]$Commit) {
    if ($Commit -notmatch '^[0-9a-f]{40}$') { return $false }
    git -C $panelDirectory cat-file -e "$Commit^{commit}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        git -C $panelDirectory fetch --no-tags "https://github.com/$repository.git" $Commit 2>$null
        if ($LASTEXITCODE -ne 0) { return $false }
    }
    return (Get-BuildInputFingerprint -Repository $panelDirectory -Commit $Commit -Panel) -eq $expectedInputs
}
if (-not $RunId) {
    # A WebUI-only commit may reuse the native bundle only when every native
    # input (including shared renderer code, dependencies and CI) is identical.
    $runsJson = gh api "repos/$repository/actions/workflows/build.yml/runs?status=success&per_page=100"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to discover paired Panel builds' }
    foreach ($candidate in ($runsJson | ConvertFrom-Json).workflow_runs) {
        if (-not (Test-GuiInputs $candidate.head_sha)) { continue }
        $artifactsJson = gh api "repos/$repository/actions/runs/$($candidate.id)/artifacts?per_page=100"
        if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect paired Panel artifacts' }
        $available = ($artifactsJson | ConvertFrom-Json).artifacts |
            Where-Object { $_.name -eq 'sunshine-gui-windows-x64' -and -not $_.expired }
        if ($available) { $RunId = [string]$candidate.id; break }
    }
    if (-not $RunId) {
        throw "No successful, unexpired GUI artifact for Panel $expectedCommit. Build that Panel commit before packaging this release."
    }
}
$runJson = gh api "repos/$repository/actions/runs/$RunId"
if ($LASTEXITCODE -ne 0) { throw 'Unable to read the Panel workflow run' }
$run = $runJson | ConvertFrom-Json
if ($run.conclusion -ne 'success' -or -not (Test-GuiInputs $run.head_sha) -or
    $run.path -ne '.github/workflows/build.yml') {
    throw "Panel run must be a successful build.yml run at $expectedCommit"
}

# Keep the executable and its native plugin on one build boundary. Never use
# individual files from another release to fill gaps in this bundle.
if (Test-Path -LiteralPath $Destination) {
    throw 'Choose a fresh destination for the paired GUI bundle'
}
$download = Join-Path ([IO.Path]::GetTempPath()) ('paired-gui-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $download | Out-Null
gh run download $RunId --repo $repository --name sunshine-gui-windows-x64 --dir $download
if ($LASTEXITCODE -ne 0) { throw "Unable to download Panel artifact; diagnostic files: $download" }
$archive = Join-Path $download 'sunshine-gui-windows-x64.zip'
$manifest = Get-Content -LiteralPath (Join-Path $download 'gui-build.json') -Raw | ConvertFrom-Json
if ($manifest.repository -ne $repository -or $manifest.commit -ne $run.head_sha -or
    [string]$manifest.run_id -ne [string]$RunId -or $manifest.sha256 -notmatch '^[0-9a-fA-F]{64}$') {
    throw 'GUI build provenance does not match the selected repository, commit and run'
}
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
if ($archiveHash -ne $manifest.sha256) {
    throw 'GUI bundle checksum mismatch'
}
Expand-Archive -LiteralPath $archive -DestinationPath $Destination
foreach ($name in @('sunshine-gui.exe')) {
    $file = Get-Item -LiteralPath (Join-Path $Destination $name)
    if ($file.Length -eq 0) { throw "Empty required GUI file: $name" }
}
@{ repository = $repository; run_id = $RunId; commit = $expectedCommit; binary_commit = $run.head_sha; native_inputs = $expectedInputs; sha256 = $archiveHash.ToLowerInvariant() } |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $Destination 'paired-build.json') -Encoding utf8
Write-Output "Paired GUI bundle verified at $expectedCommit in $Destination"

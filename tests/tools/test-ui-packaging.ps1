$ErrorActionPreference = 'Stop'
$source = (Resolve-Path "$PSScriptRoot/../..").Path
. "$source/scripts/build-inputs.ps1"
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('sunshine-ui-package-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert-Equal($actual, $expected, [string]$message) {
    if ($actual -ne $expected) { throw $message }
}
function Commit-Fixture {
    git add .
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    if ($LASTEXITCODE -ne 0) { throw 'Fixture commit failed' }
}
function Assert-Rejected([scriptblock]$action, [string]$message) {
    $rejected = $false
    try { & $action } catch { $rejected = $true }
    if (-not $rejected) { throw $message }
}
Push-Location $fixture
try {
    git init -q
    'core source' | Set-Content core.cpp
    New-Item -ItemType Directory -Path webui | Out-Null
    'page' | Set-Content webui/index.html
    Commit-Fixture
    $native = Get-BuildInputFingerprint -Panel
    'changed page' | Set-Content webui/index.html
    Commit-Fixture
    Assert-Equal (Get-BuildInputFingerprint -Panel) $native 'WebUI changes invalidated native GUI reuse'
    'changed native source' | Set-Content core.cpp
    Commit-Fixture
    if ((Get-BuildInputFingerprint -Panel) -eq $native) { throw 'Native changes were not detected' }

    # Exercise core export and composition with actual ZIPs and byte hashes.
    $sha = git rev-parse HEAD
    git update-index --add --cacheinfo "160000,$sha,src_assets/common/sunshine-control-panel"
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm gitlink
    $inputs = Get-BuildInputFingerprint
    git update-index --cacheinfo "160000,$('1' * 40),src_assets/common/sunshine-control-panel"
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm gitlink-only
    Assert-Equal (Get-BuildInputFingerprint) $inputs 'Panel gitlink changes invalidated core reuse'

    $work = Join-Path $fixture 'untracked'
    New-Item -ItemType Directory -Path "$work/stage/assets/web", "$work/stage/assets/gui", "$work/web", "$work/gui" | Out-Null
    'unchanged executable bytes' | Set-Content "$work/stage/sunshine.exe"
    'old UI must not enter the core artifact' | Set-Content "$work/stage/assets/web/old.html"
    'old GUI must not enter the core artifact' | Set-Content "$work/stage/assets/gui/old.exe"
    "#define MySourceDir `"$work\stage`"`n#define MyLicenseFile `"$fixture\LICENSE`"`nOutputDir=old" | Set-Content "$work/installer.iss"
    & "$source/scripts/export-core-runtime.ps1" -StagingDirectory "$work/stage" -InstallerScript "$work/installer.iss" -OutputDirectory "$work/core"
    foreach ($page in @('index', 'apps', 'config', 'password', 'pin', 'troubleshooting', 'welcome')) {
        'new page' | Set-Content "$work/web/$page.html"
    }
    'native GUI' | Set-Content "$work/gui/sunshine-gui.exe"
    '{}' | Set-Content "$work/gui/paired-build.json"
    $arguments = @{ CoreDirectory = "$work/core"; WebUiDirectory = "$work/web"; GuiDirectory = "$work/gui" }
    & "$source/scripts/repackage-ui.ps1" @arguments -OutputDirectory "$work/package"
    Assert-Equal (Get-FileHash "$work/package/runtime/sunshine.exe").Hash (Get-FileHash "$work/stage/sunshine.exe").Hash 'Core executable changed'
    Assert-Equal (Get-Content "$work/package/runtime/assets/web/index.html") 'new page' 'New WebUI was not installed'
    if (Test-Path "$work/package/runtime/assets/web/old.html") { throw 'Old WebUI leaked into the package' }
    if ((Get-Content "$work/package/installer.iss" -Raw) -match '@(?:STAGING|SOURCE|OUTPUT)_ROOT@') { throw 'Installer roots were not rebound' }
    $portable = [IO.Compression.ZipFile]::OpenRead("$work/package/Sunshine.Portable-x64.zip")
    try {
        if ('Sunshine/sunshine.exe' -notin $portable.Entries.FullName -or
            'Sunshine/assets/ui-package.json' -notin $portable.Entries.FullName) { throw 'Portable layout or provenance is missing' }
    } finally { $portable.Dispose() }

    'tamper' | Add-Content "$work/core/core-runtime.zip"
    Assert-Rejected { & "$source/scripts/repackage-ui.ps1" @arguments -OutputDirectory "$work/tampered" } 'Tampered core was accepted'
    'incompatible core' | Set-Content core.cpp
    git add core.cpp
    git -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm incompatible
    Assert-Rejected { & "$source/scripts/repackage-ui.ps1" @arguments -OutputDirectory "$work/incompatible" } 'Changed core inputs were accepted'
    Write-Output 'PASS: UI/core isolation, native-input detection, composition, unchanged executable, tamper and incompatible-core rejection'
} finally {
    Pop-Location
    Write-Output "Fixture retained at $fixture"
}

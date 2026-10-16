param()
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $project '.local'
$tools = Join-Path $localRoot 'tools'
$downloads = Join-Path $localRoot 'downloads'
New-Item -ItemType Directory -Force -Path $tools, $downloads | Out-Null

function Get-VerifiedFile($Url, $File, $Sha256) {
    if (-not (Test-Path -LiteralPath $File)) {
        & curl.exe --silent --show-error --fail --location --retry 2 --output $File $Url
        if ($LASTEXITCODE -ne 0) { throw "Download failed: $Url" }
    }
    if ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Sha256) {
        throw "Checksum mismatch: $File. Preserved for inspection."
    }
}

# Prefer an existing nvm version without switching its machine-wide symlink.
$nodeVersion = (Get-Content -LiteralPath (Join-Path $project '.node-version') -Raw).Trim()
if ($nodeVersion -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid .node-version' }
$nvmRoot = $env:NVM_HOME
if (-not $nvmRoot) { $nvmRoot = Join-Path $env:APPDATA 'nvm' }
$nodeDir = Join-Path $nvmRoot "v$nodeVersion"
if (-not (Test-Path -LiteralPath (Join-Path $nodeDir 'node.exe'))) {
    $nodeDir = Join-Path $tools "node-v$nodeVersion-win-x64"
    if (-not (Test-Path -LiteralPath (Join-Path $nodeDir 'node.exe'))) {
        $name = "node-v$nodeVersion-win-x64.zip"
        $checksums = Invoke-RestMethod -Uri "https://nodejs.org/dist/v$nodeVersion/SHASUMS256.txt"
        $line = ($checksums -split "`n") | Where-Object { $_.Trim().EndsWith("  $name") }
        if (@($line).Count -ne 1 -or $line -notmatch '^([0-9a-f]{64})\s+') { throw 'Node checksum unavailable' }
        $archive = Join-Path $downloads $name
        Get-VerifiedFile "https://nodejs.org/dist/v$nodeVersion/$name" $archive $Matches[1]
        Expand-Archive -LiteralPath $archive -DestinationPath $tools
    }
}

# Pinned official archive: no installer, shortcuts, registry or global PATH changes.
$msys = Join-Path $tools 'msys64'
if (-not (Test-Path -LiteralPath (Join-Path $msys 'usr\bin\bash.exe'))) {
    $archive = Join-Path $downloads 'msys2-base-x86_64-20260927.tar.xz'
    Get-VerifiedFile 'https://github.com/msys2/msys2-installer/releases/download/2026-09-27/msys2-base-x86_64-20260927.tar.xz' $archive 'ea2f31a0b6ade63914ce441ffb022f0f6aa96982bfefa2326460a26d5fb01322'
    & tar.exe -xf $archive -C $tools
    if ($LASTEXITCODE -ne 0) { throw 'MSYS2 extraction failed; preserve files for inspection' }
}

# Start a child shell with an explicit environment; leave the caller unchanged.
function Invoke-LocalShell([string]$Command) {
    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = Join-Path $msys 'usr\bin\bash.exe'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.WorkingDirectory = $project
    $start.EnvironmentVariables['MSYSTEM'] = 'UCRT64'
    $start.EnvironmentVariables['CHERE_INVOKING'] = '1'
    $start.EnvironmentVariables['MSYS2_PATH_TYPE'] = 'minimal'
    $start.Arguments = '--login -c "' + $Command.Replace('"', '\"') + '"'
    $process = [Diagnostics.Process]::Start($start)
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "MSYS2 step failed ($($process.ExitCode))" }
}

# A runtime upgrade can finish its first pass by closing the shell. Run setup
# again if that happens; other errors stop without an automatic repair attempt.
Invoke-LocalShell 'pacman -Syu --noconfirm'
Invoke-LocalShell 'pacman -S --needed --noconfirm git mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-ccache mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-lld mingw-w64-ucrt-x86_64-cppwinrt mingw-w64-ucrt-x86_64-curl-winssl mingw-w64-ucrt-x86_64-MinHook mingw-w64-ucrt-x86_64-miniupnpc mingw-w64-ucrt-x86_64-nlohmann-json mingw-w64-ucrt-x86_64-onevpl mingw-w64-ucrt-x86_64-openssl mingw-w64-ucrt-x86_64-opus'

@{ node = $nodeDir; msys = $msys } | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $localRoot 'tool-paths.json') -Encoding UTF8
Invoke-LocalShell 'gcc --version; cmake --version; ninja --version'
& (Join-Path $nodeDir 'node.exe') --version
if ($LASTEXITCODE -ne 0) { throw 'Node verification failed' }
Push-Location $project
try {
    & git -c core.longpaths=true submodule update --init --recursive --depth 1 `
        third-party/AMF third-party/ViGEmClient third-party/build-deps `
        third-party/googletest third-party/nanors third-party/nvapi `
        third-party/nvenc-headers/1100 third-party/nvenc-headers/1200 `
        third-party/nvenc-headers/1300 third-party/nvenc-headers/1301 `
        third-party/tray third-party/moonlight-common-c third-party/pyrowave
    if ($LASTEXITCODE -ne 0) { throw 'Submodule preparation failed; existing checkouts preserved' }
} finally { Pop-Location }
Write-Host "Local tools ready: $localRoot"
exit 0

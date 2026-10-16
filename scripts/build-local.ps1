param(
    [ValidateSet('Configure', 'Build', 'Test', 'WebUI')]
    [string]$Task = 'Build',
    [ValidateRange(1, 32)][int]$Jobs = 2,
    [string]$GuiDirectory
)
$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $project '.local'
$paths = Get-Content -LiteralPath (Join-Path $localRoot 'tool-paths.json') -Raw | ConvertFrom-Json
$nodeVersion = (Get-Content -LiteralPath (Join-Path $project '.node-version') -Raw).Trim()
$nvmRoot = $env:NVM_HOME
if (-not $nvmRoot) { $nvmRoot = Join-Path $env:APPDATA 'nvm' }
$nvmNode = Join-Path $nvmRoot "v$nodeVersion"
if (Test-Path -LiteralPath (Join-Path $nvmNode 'node.exe')) { $paths.node = $nvmNode }
$gui = Join-Path $localRoot 'staging\gui'
if ($GuiDirectory) { $gui = [IO.Path]::GetFullPath($GuiDirectory) }
if ($Task -eq 'Configure') {
    $expected = (& git -C $project ls-tree HEAD src_assets/common/sunshine-control-panel) -split '\s+'
    if ($LASTEXITCODE -ne 0 -or $expected.Count -lt 3) { throw 'Unable to read pinned GUI commit' }
    if (Test-Path -LiteralPath $gui) {
        $paired = Get-Content -LiteralPath (Join-Path $gui 'paired-build.json') -Raw | ConvertFrom-Json
        if ($paired.commit -ne $expected[2]) {
            throw 'Local GUI belongs to another commit. Preserve it and select a fresh staging directory.'
        }
    } else {
        $tempDir = Join-Path $localRoot 'tmp'
        New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
        $fetch = New-Object Diagnostics.ProcessStartInfo
        $fetch.FileName = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
        $fetch.UseShellExecute = $false
        $fetch.CreateNoWindow = $true
        $fetch.WorkingDirectory = $project
        $fetch.EnvironmentVariables['TEMP'] = $tempDir
        $fetch.EnvironmentVariables['TMP'] = $tempDir
        $fetch.Arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'fetch-paired-gui.ps1') + '" -Destination "' + $gui + '"'
        $fetchProcess = [Diagnostics.Process]::Start($fetch)
        $fetchProcess.WaitForExit()
        if ($fetchProcess.ExitCode -ne 0) { throw 'Paired GUI preparation failed; downloads preserved' }
    }
}
$commands = @{
    Configure = @'
cmake -S . -B .local/build/sunshine -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_DOCS=OFF -DBUILD_TESTS=ON \
  -DBUILD_TRAY_TESTS=ON -DBUILD_WEB_UI=OFF -DSUNSHINE_RTX_HDR=OFF \
  -DFETCH_DRIVER_DEPS=OFF -DDRIVER_DEPS_REQUIRED=OFF -DFETCH_GUI=OFF \
  -DSUNSHINE_PREFER_LOCAL_GUI=OFF -DGUI_DIR="$(cygpath -m "$FOUNDATION_GUI")" \
  -DSUNSHINE_ASSETS_DIR=assets \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
'@
    Build = 'cmake --build .local/build/sunshine --target sunshine --parallel "$FOUNDATION_JOBS"; ccache --show-stats'
    # Keep live capture and network listeners in CI. Even loopback test servers
    # can trigger Windows firewall prompts on the user's normal workstation.
    Test = 'cmake --build .local/build/sunshine --parallel "$FOUNDATION_JOBS"; ctest --test-dir .local/build/sunshine --output-on-failure --parallel "$FOUNDATION_JOBS" -E "^(test_sunshine|beast_http_unit_tests|webhook_transport_tests|controller_handoff_probe)$"'
    WebUI = @'
export PATH="$(cygpath -u "$FOUNDATION_NODE"):$PATH"
export npm_config_cache="$(cygpath -m "$FOUNDATION_ROOT")/.local/cache/npm"
export SUNSHINE_ASSETS_DIR="$(cygpath -m "$FOUNDATION_ROOT")/.local/build/sunshine"
npm run lint:webui
npm run test:webui
npm run build
'@
}
$command = @'
set -euo pipefail
cd "$(cygpath -u "$FOUNDATION_ROOT")"
export CCACHE_DIR="$(cygpath -m "$FOUNDATION_ROOT")/.local/cache/ccache"
export CCACHE_MAXSIZE=2G
export CCACHE_COMPILERCHECK=content
'@ + "`n" + $commands[$Task] + "`n"
$logs = Join-Path $localRoot 'logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null
$tempDir = Join-Path $localRoot 'tmp'
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$scriptName = "run-$Task.sh"
$scriptPath = Join-Path $localRoot $scriptName
[IO.File]::WriteAllText($scriptPath, $command.Replace("`r`n", "`n"), (New-Object Text.UTF8Encoding($false)))
$start = New-Object Diagnostics.ProcessStartInfo
$start.FileName = Join-Path $paths.msys 'usr\bin\bash.exe'
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.WorkingDirectory = $project
$start.EnvironmentVariables['MSYSTEM'] = 'UCRT64'
$start.EnvironmentVariables['CHERE_INVOKING'] = '1'
$start.EnvironmentVariables['MSYS2_PATH_TYPE'] = 'minimal'
$start.EnvironmentVariables['FOUNDATION_ROOT'] = $project
$start.EnvironmentVariables['FOUNDATION_NODE'] = $paths.node
$start.EnvironmentVariables['FOUNDATION_GUI'] = $gui
$start.EnvironmentVariables['FOUNDATION_JOBS'] = [string]$Jobs
$start.EnvironmentVariables['TEMP'] = $tempDir
$start.EnvironmentVariables['TMP'] = $tempDir
$start.Arguments = "--login .local/$scriptName"
$process = [Diagnostics.Process]::Start($start)
$outputTask = $process.StandardOutput.ReadToEndAsync()
$errorTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
[Console]::Out.Write($outputTask.GetAwaiter().GetResult())
[Console]::Error.Write($errorTask.GetAwaiter().GetResult())
if ($process.ExitCode -ne 0) { throw "Local $Task failed ($($process.ExitCode)); outputs preserved" }
exit 0

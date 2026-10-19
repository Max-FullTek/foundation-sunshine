param([string]$HelperScript = (Join-Path $PSScriptRoot 'vdd-device-helper.ps1'))
$ErrorActionPreference = 'Stop'
. $HelperScript
$selectionRoot = Join-Path ([IO.Path]::GetTempPath()) ('foundation-vdd-selection-' + [guid]::NewGuid().ToString('N'))
$latest = Join-Path $selectionRoot 'driver/latest'
[void][IO.Directory]::CreateDirectory($latest)
Set-Content (Join-Path $latest 'ZakoVDD.inf') 'fixture'
Set-Content (Join-Path $selectionRoot 'driver/vdd_settings.xml') '<settings />'
foreach ($build in @('22000','26100','26200')) {
    $payload = Resolve-VddPayload $selectionRoot $build
    if ($payload.DriverDir -ne $latest) { throw "Unexpected payload for build $build" }
}
foreach ($build in @('19045','banana')) {
    $rejected = $false
    try { Resolve-VddPayload $selectionRoot $build | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { throw "Unsupported or unknown OS accepted: $build" }
}
Write-Output 'Windows 11 payload selection and unsupported-host rejection passed.'

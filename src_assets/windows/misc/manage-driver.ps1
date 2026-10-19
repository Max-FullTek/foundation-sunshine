[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('vdd','vmouse')][string]$Component,
    [ValidateSet('Install','Uninstall')][string]$Action = 'Install',
    [switch]$AcceptCertificateTrust
)
$ErrorActionPreference = 'Stop'
try {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run Install.cmd/Uninstall.cmd as administrator.'
    }
    if ($Action -eq 'Install') {
        . (Join-Path $PSScriptRoot 'scripts/verify-driver-certificate.ps1')
        $driver = if ($Component -eq 'vdd') { 'VDD' } else { 'VirtualMouse' }
        $payload = if ($Component -eq 'vdd') { 'scripts/driver/latest' } else { 'scripts/vmouse/driver' }
        Assert-DriverCertificate $driver (Join-Path $PSScriptRoot $payload)
        if (-not $AcceptCertificateTrust) {
            Write-Host 'This package uses Foundation local signing (not Microsoft WHQL/attestation).'
            Write-Host 'Installation trusts certificate 78983DA4728FBB6B57779A60F6B1A2F071C84F07 in the machine certificate stores.'
            if ((Read-Host 'Type INSTALL to continue') -cne 'INSTALL') { throw 'Installation cancelled.' }
        }
    }
    $service = Get-Service SunshineService -ErrorAction SilentlyContinue
    $restart = $service -and $service.Status -eq 'Running'
    if ($restart) { Stop-Service SunshineService; $service.WaitForStatus('Stopped',[TimeSpan]::FromSeconds(30)) }
    if (Get-Process sunshine -ErrorAction SilentlyContinue) { throw 'Close Sunshine before updating its driver.' }
    # An independent VDD update retains the installed Lite configuration location.
    if ($Component -eq 'vdd') {
        $key = Get-ItemProperty 'HKLM:\SOFTWARE\AlkaidLab\Sunshine' -ErrorAction SilentlyContinue
        if ($key -and $key.InstallDir -and (Test-Path -LiteralPath (Join-Path $key.InstallDir 'config'))) {
            $configDirectory = Join-Path $key.InstallDir 'config'
        }
    }
    $script = if ($Component -eq 'vdd') { 'scripts/vdd-device-helper.ps1' } else { 'scripts/vmouse/vmouse-device-helper.ps1' }
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot $script),'-Action',$Action)
    if ($Component -eq 'vdd' -and $Action -eq 'Install') { $arguments += '-PreserveHealthyExisting' }
    if ($configDirectory) { $arguments += @('-ConfigDirectory',$configDirectory) }
    & (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') @arguments
    $result = $LASTEXITCODE
    if ($Action -eq 'Install' -and $result -in @(0,3010) -and $Component -eq 'vdd' -and $key -and $key.InstallDir) {
        # Update the optional user-mode tools alongside an independent VDD
        # update. Copying files does not register or enable the Vulkan layer.
        $bridgeSource = Join-Path $PSScriptRoot 'tools/vulkan_hdr'
        $bridgeTarget = Join-Path $key.InstallDir 'tools/vulkan_hdr'
        [void][IO.Directory]::CreateDirectory($bridgeTarget)
        foreach ($file in @('zako_vulkan_hdr_bridge.dll','vulkan_hdr_probe.exe','VkLayer_zako_virtual_hdr.json','LICENSE','source.json')) {
            Copy-Item -LiteralPath (Join-Path $bridgeSource $file) -Destination $bridgeTarget -Force
        }
    }
    if ($result -eq 0 -and $restart) { Start-Service SunshineService }
    if ($result -eq 3010) { Write-Host 'Windows reports that a restart is required. No restart was performed.' }
    exit $result
} catch { Write-Error $_ -ErrorAction Continue; exit 1 }

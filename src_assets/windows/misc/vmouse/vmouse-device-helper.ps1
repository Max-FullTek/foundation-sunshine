[CmdletBinding()]
param(
    [ValidateSet('Install','Uninstall','Inspect')][string]$Action = 'Inspect',
    [string]$PackageDirectory = (Join-Path $PSScriptRoot 'driver')
)
# Installs only the Foundation root and its mandatory access-policy companion.
# Never changes boot policy, reboots, or removes unrelated HID devices.
$ErrorActionPreference = 'Stop'
$rootHardware = 'Root\FoundationVirtualMousePrototype'
$childHardware = 'HID\FoundationVirtualMousePrototype'
$skipBaseUpdate = $false
$rootId = $null
$rootDirectory = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$nefcon = Join-Path $rootDirectory 'tools\nefconw.exe'
$pnputil = Join-Path $env:SystemRoot 'System32\pnputil.exe'
function Property($instance, $key) {
    (Get-PnpDeviceProperty -InstanceId $instance -KeyName $key -ErrorAction Stop).Data
}
function Roots {
    @(Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue | Where-Object {
        $_.InstanceId.StartsWith('ROOT\', [StringComparison]::OrdinalIgnoreCase) -and
        (Property $_.InstanceId 'DEVPKEY_Device_HardwareIds') -contains $rootHardware
    })
}
function Children($root) {
    @(Get-PnpDevice -PresentOnly -Class Mouse -ErrorAction SilentlyContinue | Where-Object {
        (Property $_.InstanceId 'DEVPKEY_Device_HardwareIds') -contains $childHardware -and
        (Property $_.InstanceId 'DEVPKEY_Device_Parent') -eq $root.InstanceId
    })
}
function Native($exe, [string[]]$arguments) {
    & $exe @arguments | Out-Host
    if ($LASTEXITCODE -eq 3010) { throw 'RESTART_REQUIRED' }
    if ($LASTEXITCODE -ne 0) { throw "$exe failed ($LASTEXITCODE)." }
}
function Assert-Access($root) {
    if ($root.Status -ne 'OK' -or (Property $root.InstanceId 'DEVPKEY_Device_ProblemCode') -ne 0) {
        throw 'Foundation root is not ready.'
    }
    $children = @(Children $root)
    if ($children.Count -ne 1 -or $children[0].Status -ne 'OK') { throw 'Expected one ready Foundation mouse child.' }
    $paths = @([FoundationDeviceAccess]::HidPaths($children[0].InstanceId))
    if ($paths.Count -ne 1) { throw 'Expected exactly one Foundation HID interface.' }
    $sddl = [FoundationDeviceAccess]::ReadSecurity($paths[0])
    $security = [Security.AccessControl.RawSecurityDescriptor]::new($sddl)
    if (($security.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -eq 0 -or
        $security.DiscretionaryAcl.Count -ne 2) { throw 'The mandatory mouse access policy is not active.' }
    $allowed = @()
    foreach ($ace in $security.DiscretionaryAcl) {
        if ($ace -isnot [Security.AccessControl.CommonAce] -or
            $ace.AceFlags -ne [Security.AccessControl.AceFlags]::None -or
            $ace.AceType -ne [Security.AccessControl.AceType]::AccessAllowed -or
            $ace.AccessMask -ne 0x1f01ff) { throw 'Unexpected mouse access permissions.' }
        $allowed += $ace.SecurityIdentifier.Value
    }
    if (@(Compare-Object @('S-1-5-18','S-1-5-32-544') ($allowed | Sort-Object -Unique)).Count) {
        throw 'Mouse injection must be restricted to SYSTEM and administrators.'
    }
    Write-Output "Foundation Virtual Mouse ready; access policy: $sddl"
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$administrator = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
try {
    $build = [int](Get-ItemPropertyValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' CurrentBuildNumber)
    if ($build -lt 22000 -or -not [Environment]::Is64BitOperatingSystem) { throw 'Windows 11 x64 is required.' }
    if ($Action -eq 'Inspect') { Roots | Select-Object Status,InstanceId; exit 0 }
    if (-not $administrator) { throw 'Run this installer as administrator.' }
    Add-Type -Path (Join-Path $PSScriptRoot 'device-access.cs')
    $roots = @(Roots)
    if ($roots.Count -gt 1) { throw 'Multiple Foundation roots found; refusing an ambiguous update.' }
    if ($Action -eq 'Install') {
        . (Join-Path $PSScriptRoot '..\verify-driver-certificate.ps1')
        Assert-DriverCertificate VirtualMouse $PackageDirectory
        $manifest = Get-Content (Join-Path $PackageDirectory 'package.json') -Raw | ConvertFrom-Json
        if (-not (Test-Path -LiteralPath $nefcon)) { throw 'Bundled nefconw.exe is missing.' }
        if ($roots.Count -eq 1 -and [version](Property $roots[0].InstanceId 'DEVPKEY_Device_DriverVersion') -ge [version]$manifest.version) {
            $skipBaseUpdate = $true
            Write-Output 'Keeping the same-or-newer Foundation base driver; reconciling its access policy.'
        }
    }
    $service = Get-Service SunshineService -ErrorAction SilentlyContinue
    $restartService = $service -and $service.Status -eq 'Running'
    if ($restartService) {
        Stop-Service SunshineService -ErrorAction Stop
        $service.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    if (Get-Process sunshine -ErrorAction SilentlyContinue) { throw 'Close Sunshine before changing its input driver.' }
    if ($Action -eq 'Uninstall') {
        foreach ($root in $roots) { Native $pnputil @('/remove-device', $root.InstanceId) }
        # Match original package names, not descriptions or arbitrary OEM text.
        $packages = @(Get-WindowsDriver -Online -All | Where-Object {
            [IO.Path]::GetFileName($_.OriginalFileName) -in @('FoundationVirtualMousePrototype.inf','FoundationVirtualMouseAccess.inf')
        })
        foreach ($package in $packages) { Native $pnputil @('/delete-driver', $package.Driver, '/uninstall') }
        Write-Output 'Foundation Virtual Mouse and its access-policy package removed.'
    } else {
        $certificate = Join-Path $PackageDirectory 'FoundationVirtualMouse.cer'
        foreach ($store in @('Root','TrustedPublisher')) {
            Native (Join-Path $env:SystemRoot 'System32\certutil.exe') @('-addstore','-f',$store,$certificate)
        }
        # Stage the companion before any new root/HID collection is enumerated.
        Native $pnputil @('/add-driver',(Join-Path $PackageDirectory 'FoundationVirtualMouseAccess.inf'),'/install')
        if ($roots.Count -eq 0) {
            Native $nefcon @('--create-device-node','--hardware-id',$rootHardware,'--class-name','HIDClass','--class-guid','745a17a0-74d3-11d0-b6fe-00a0c90f57da')
            $roots = @(Roots)
            if ($roots.Count -ne 1) { throw 'Foundation root creation did not produce exactly one device.' }
        }
        $rootId = $roots[0].InstanceId
        Disable-PnpDevice -InstanceId $rootId -Confirm:$false
        if (-not $skipBaseUpdate) { Native $nefcon @('--install-driver','--inf-path',(Join-Path $PackageDirectory 'FoundationVirtualMousePrototype.inf')) }
        Enable-PnpDevice -InstanceId $rootId -Confirm:$false
        $ready = $false
        $lastFailure = ''
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            try {
                $current = @(Roots)
                if ($current.Count -ne 1) { throw 'Foundation root is missing or ambiguous.' }
                if ([version](Property $rootId 'DEVPKEY_Device_DriverVersion') -lt [version]$manifest.version) { throw 'New driver version is not bound.' }
                Assert-Access $current[0]
                $ready = $true; break
            } catch { $lastFailure = $_.Exception.Message; Start-Sleep -Milliseconds 500 }
        }
        if (-not $ready) { throw "Mouse verification failed: $lastFailure" }
        # Only after the replacement is ready, retire the exact old product.
        $legacy = @(Get-PnpDevice -Class HIDClass -ErrorAction SilentlyContinue | Where-Object {
            $_.InstanceId.StartsWith('ROOT\', [StringComparison]::OrdinalIgnoreCase) -and
            (Property $_.InstanceId 'DEVPKEY_Device_HardwareIds') -contains 'Root\ZakoVirtualMouse'
        })
        foreach ($device in $legacy) { Native $pnputil @('/remove-device',$device.InstanceId) }
        $legacyPackages = @(Get-WindowsDriver -Online -All | Where-Object {
            [IO.Path]::GetFileName($_.OriginalFileName) -ieq 'ZakoVirtualMouse.inf'
        })
        foreach ($package in $legacyPackages) { Native $pnputil @('/delete-driver',$package.Driver) }
    }
    if ($restartService) { Start-Service SunshineService }
    exit 0
} catch {
    # Fail closed; keep DriverStore packages for recovery, and do not start
    # Sunshine when the mandatory child ACL cannot be verified.
    if ($rootId) { Disable-PnpDevice -InstanceId $rootId -Confirm:$false -ErrorAction SilentlyContinue }
    Write-Error $_ -ErrorAction Continue
    if ($_.Exception.Message -eq 'RESTART_REQUIRED') { exit 3010 }
    exit 1
}

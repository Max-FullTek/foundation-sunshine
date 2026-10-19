[CmdletBinding()]
param(
    [ValidateSet('VDD', 'VirtualMouse')][string] $Driver,
    [string] $Directory
)

# The public certificate is pinned independently of package metadata. It is a
# locally issued signing certificate, not Microsoft WHQL/attestation signing.
function Assert-DriverCertificate([string] $Driver, [string] $Directory) {
    $ErrorActionPreference = 'Stop'
    $expectedCertificate = 'CC4B72FF897D8EF7A4F53C24E928A7316FD43A380353B3D255157600BD5B6564'
    $expectedSigner = '78983DA4728FBB6B57779A60F6B1A2F071C84F07'
    switch ($Driver) {
        'VDD' {
            $component = 'vdd'
            $certificateName = 'ZakoVDD.cer'
            $catalogs = @('zakovdd.cat')
            $baseInf = 'ZakoVDD.inf'
            $required = @('ZakoVDD.inf', 'ZakoVDD.dll', 'zakovdd.cat', 'ZakoVDD.cer', 'LICENSE')
            $repository = 'https://github.com/Max-FullTek/zako-vdd'
        }
        'VirtualMouse' {
            $component = 'vmouse'
            $certificateName = 'FoundationVirtualMouse.cer'
            $catalogs = @('foundationvirtualmouseprototype.cat', 'foundationvirtualmouseaccess.cat')
            $baseInf = 'FoundationVirtualMousePrototype.inf'
            $required = @('FoundationVirtualMousePrototype.inf', 'FoundationVirtualMousePrototype.dll',
                'foundationvirtualmouseprototype.cat', 'FoundationVirtualMouseAccess.inf',
                'foundationvirtualmouseaccess.cat', 'FoundationVirtualMouse.cer', 'LICENSE')
            $repository = 'https://github.com/Max-FullTek/foundation-virtual-mouse'
        }
        default { throw "Unsupported driver: $Driver" }
    }
    $manifest = Get-Content -LiteralPath (Join-Path $Directory 'package.json') -Raw | ConvertFrom-Json
    if ($manifest.schema -ne 1 -or $manifest.component -ne $component -or
        $manifest.source_repository -ne $repository -or $manifest.source_commit -notmatch '^[0-9a-f]{40}$' -or
        $manifest.signer_thumbprint -ine $expectedSigner -or $manifest.architecture -ne 'amd64' -or
        $manifest.minimum_windows_build -lt 22000) { throw 'Invalid driver package provenance.' }
    [void][version]$manifest.version
    foreach ($name in $required) {
        if (-not $manifest.files.PSObject.Properties[$name]) { throw "Missing required package member: $name" }
    }
    foreach ($file in $manifest.files.PSObject.Properties) {
        if ($file.Name -notmatch '^[a-zA-Z0-9_.-]+$' -or $file.Value -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'Invalid package member name/hash.'
        }
        if ((Get-FileHash -LiteralPath (Join-Path $Directory $file.Name) -Algorithm SHA256).Hash -ine $file.Value) {
            throw "Driver package integrity mismatch: $($file.Name)"
        }
    }
    $driverVersion = [regex]::Match((Get-Content -LiteralPath (Join-Path $Directory $baseInf) -Raw), '(?im)^DriverVer\s*=\s*[^,\r\n]+,\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*$').Groups[1].Value
    if (-not $driverVersion -or [version]$driverVersion -ne [version]$manifest.version) {
        throw 'Package version does not match the signed INF DriverVer.'
    }
    if ($Driver -eq 'VirtualMouse') {
        $accessVersion = [regex]::Match((Get-Content -LiteralPath (Join-Path $Directory 'FoundationVirtualMouseAccess.inf') -Raw), '(?im)^DriverVer\s*=\s*[^,\r\n]+,\s*([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\s*$').Groups[1].Value
        if (-not $accessVersion -or [version]$accessVersion -ne [version]$manifest.access_version) {
            throw 'Access-policy version does not match its signed INF DriverVer.'
        }
    }
    $certificatePath = Join-Path $Directory $certificateName
    if ((Get-FileHash -LiteralPath $certificatePath -Algorithm SHA256).Hash -ine $expectedCertificate) {
        throw 'Driver certificate does not match the pinned Foundation signing certificate.'
    }
    Add-Type -AssemblyName System.Security
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new([IO.File]::ReadAllBytes($certificatePath))
    try {
        if ([DateTime]::Now -lt $certificate.NotBefore -or [DateTime]::Now -gt $certificate.NotAfter) {
            throw 'Driver signing certificate is outside its validity period; renew and re-pin before packaging.'
        }
        foreach ($name in $catalogs) {
            $catalog = [Security.Cryptography.Pkcs.SignedCms]::new()
            $catalog.Decode([IO.File]::ReadAllBytes((Join-Path $Directory $name)))
            $catalog.CheckSignature($true)
            if ($catalog.SignerInfos.Count -ne 1 -or
                $catalog.SignerInfos[0].Certificate.GetRawCertDataString() -ne $certificate.GetRawCertDataString()) {
                throw "Unexpected driver catalog signer: $name"
            }
        }
    } finally { $certificate.Dispose() }
}
if ($MyInvocation.InvocationName -ne '.') {
    try { Assert-DriverCertificate $Driver $Directory; Write-Output "$Driver package hashes and catalog signatures verified."; exit 0 }
    catch { Write-Error $_ -ErrorAction Continue; exit 1 }
}

[CmdletBinding()]
param(
    [ValidateSet('VDD', 'VirtualMouse')]
    [string] $Driver,
    [string] $Directory
)

# Pins identify the upstream test-signing certificates, not a public CA trust
# chain. Never import a certificate merely because it arrived beside a driver.
# Sources: qiin2333/zako-vdd v0.17.5 / v0.15.10 and
# AlkaidLab/zako-vmouse-release v1.3.2 (GitHub release digests).
function Assert-DriverCertificate([string] $Driver, [string] $Directory) {
    $ErrorActionPreference = 'Stop'
    switch ($Driver) {
        'VDD' {
            $name = 'ZakoVDD'
            $expected = '2868b93cef7a36889acee210ceeec48fa2e874d8f209dd666b74b78208bcce8b'
        }
        'VirtualMouse' {
            $name = 'ZakoVirtualMouse'
            $expected = '5345f6ee35a9907c84e96e5f4575e8950a498513b35685f1811185f8b44868b7'
        }
        default { throw "Unsupported driver certificate: $Driver" }
    }
    $certificatePath = Join-Path $Directory "$name.cer"
    $catalogPath = Join-Path $Directory "$name.cat"
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try {
        $actual = [BitConverter]::ToString(
            $sha256.ComputeHash([IO.File]::ReadAllBytes($certificatePath))).Replace('-', '')
    }
    finally {
        $sha256.Dispose()
    }
    if ($actual -ine $expected) {
        throw "$Driver certificate SHA-256 does not match the pinned upstream certificate."
    }

    Add-Type -AssemblyName System.Security
    $certificate = [Security.Cryptography.X509Certificates.X509Certificate2]::new(
        [IO.File]::ReadAllBytes($certificatePath))
    try {
        if ([DateTime]::Now -lt $certificate.NotBefore -or [DateTime]::Now -gt $certificate.NotAfter) {
            throw "$Driver certificate is outside its validity period."
        }
        $catalog = [Security.Cryptography.Pkcs.SignedCms]::new()
        $catalog.Decode([IO.File]::ReadAllBytes($catalogPath))
        # Verify the signature cryptographically without importing its root or
        # requiring that this machine already trusts the test certificate.
        $catalog.CheckSignature($true)
        if ($catalog.SignerInfos.Count -ne 1 -or
            $catalog.SignerInfos[0].Certificate.GetRawCertDataString() -ne $certificate.GetRawCertDataString()) {
            throw "$Driver catalog signer does not match the pinned certificate."
        }
    }
    finally {
        $certificate.Dispose()
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Assert-DriverCertificate $Driver $Directory
        Write-Output "$Driver certificate and catalog signature verified."
        exit 0
    }
    catch {
        Write-Error $_ -ErrorAction Continue
        exit 1
    }
}

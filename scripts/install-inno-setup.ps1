# Download a pinned official installer and verify it before execution.
param(
    [switch]$VerifyDownloadOnly
)

$ErrorActionPreference = 'Stop'
$version = '6.7.3'
$expectedHash = '9c73c3bae7ed48d44112a0f48e66742c00090bdb5bef71d9d3c056c66e97b732'
$url = "https://github.com/jrsoftware/issrc/releases/download/is-6_7_3/innosetup-$version.exe"
$installer = Join-Path ([System.IO.Path]::GetTempPath()) "innosetup-$version.exe"

Invoke-WebRequest -Uri $url -OutFile $installer
$actualHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) {
    throw "Inno Setup $version checksum mismatch: $actualHash"
}
$signature = Get-AuthenticodeSignature -LiteralPath $installer
if ($signature.Status -ne 'Valid') {
    throw "Inno Setup $version signature verification failed: $($signature.Status)"
}
Write-Host "Verified Inno Setup $version SHA256 and Authenticode signature."

if ($VerifyDownloadOnly) {
    return
}

$process = Start-Process -FilePath $installer -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "Inno Setup installer failed with exit code $($process.ExitCode)"
}
$compiler = Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'
if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw "Inno Setup compiler was not installed at $compiler"
}

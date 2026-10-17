# Compare committed inputs, not timestamps or branch names. Any core change
# invalidates reuse; only the separately built Panel gitlink is omitted.
function Get-BuildInputFingerprint {
    param([string]$Repository = '.', [string]$Commit = 'HEAD', [switch]$Panel)
    $entries = & git -C $Repository ls-tree -r --full-tree $Commit
    if ($LASTEXITCODE -ne 0) { throw "Cannot read build inputs at $Commit" }
    $filtered = foreach ($entry in $entries) {
        $path = ($entry -split "`t", 2)[1]
        if ($Panel) {
            if ($path -match '^(webui/|scripts/webui/|eslint\.webui\.config\.js$|\.github/crowdin\.yml$)') { continue }
        } elseif ($path -eq 'src_assets/common/sunshine-control-panel') { continue }
        $entry
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes(($filtered -join "`n") + "`n")
    [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

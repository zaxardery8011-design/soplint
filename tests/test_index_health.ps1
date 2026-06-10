#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repoRoot 'checks/index_health.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "soplint_index_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $index = Join-Path $tmp 'MEMORY.md'
    $config = Join-Path $tmp 'config.json'
    @{ index_file = $index; index_max_kb = 50 } | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding utf8NoBOM

    @'
# Memory Index

- [one](one.md)
- [one again](one.md)
'@ | Set-Content -LiteralPath $index -Encoding utf8NoBOM
    $null = & pwsh -NoProfile -File $check -Config $config 2>&1
    if ($LASTEXITCODE -ne 1) { throw "expected duplicate link to fail, got $LASTEXITCODE" }

    @'
# Memory Index

- [one](one.md)
- [two](two.md)
'@ | Set-Content -LiteralPath $index -Encoding utf8NoBOM
    $null = & pwsh -NoProfile -File $check -Config $config 2>&1
    if ($LASTEXITCODE -ne 0) { throw "expected healthy index to pass, got $LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}

Write-Host 'PASS test_index_health (fail+pass)' -ForegroundColor Green
exit 0

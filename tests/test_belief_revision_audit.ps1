#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repoRoot 'checks/belief_revision_audit.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "soplint_belief_audit_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $log = Join-Path $tmp 'beliefs.jsonl'
    $config = Join-Path $tmp 'config.json'
    @{ beliefs_log = $log; belief_revision_days = 30 } | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding utf8NoBOM

    $null = & pwsh -NoProfile -File $check -Config $config 2>&1
    if ($LASTEXITCODE -ne 1) { throw "expected missing log to fail, got $LASTEXITCODE" }

    '{"id":"one","ts":"2026-01-01T00:00:00Z"}' | Set-Content -LiteralPath $log -Encoding utf8NoBOM
    (Get-Item -LiteralPath $log).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
    $null = & pwsh -NoProfile -File $check -Config $config 2>&1
    if ($LASTEXITCODE -ne 0) { throw "expected fresh log to pass, got $LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}

Write-Host 'PASS test_belief_revision_audit (fail+pass)' -ForegroundColor Green
exit 0

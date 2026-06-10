#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$module = Join-Path $repoRoot 'lib/BeliefLog.psm1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "soplint_belief_log_$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $tmp -Force | Out-Null

try {
    $log = Join-Path $tmp 'beliefs.jsonl'
    $config = Join-Path $tmp 'config.json'
    @{ beliefs_log = $log } | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding utf8NoBOM

    Import-Module $module -Force
    $added = Add-BeliefRevision -From 'old' -To 'new' -Trigger user_calibration -ConfidenceShift 'low to high' -Config $config
    if (-not $added.ok) { throw 'expected Add-BeliefRevision to return ok' }
    if (-not (Test-Path -LiteralPath $log)) { throw 'expected log file to exist' }

    $records = @(Get-BeliefRevisions -Last 1 -Config $config)
    if ($records.Count -ne 1) { throw "expected one record, got $($records.Count)" }
    if ($records[0].trigger -ne 'user_calibration') { throw 'expected trigger to round trip' }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}

Write-Host 'PASS test_belief_log (append+read)' -ForegroundColor Green
exit 0

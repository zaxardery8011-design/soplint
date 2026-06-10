#requires -Version 7.0
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Config
)

$ErrorActionPreference = 'Stop'

function Resolve-ConfigPathValue {
    param([string]$BaseDir, [string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $BaseDir $PathValue)
}

$configPath = (Resolve-Path -LiteralPath $Config).Path
$configDir = Split-Path -Parent $configPath
$cfg = Get-Content -Raw -LiteralPath $configPath -Encoding utf8 | ConvertFrom-Json
$logPath = Resolve-ConfigPathValue -BaseDir $configDir -PathValue $cfg.beliefs_log
$maxAgeDays = if ($cfg.PSObject.Properties.Name -contains 'belief_revision_days') { [int]$cfg.belief_revision_days } else { 14 }
$violations = @()

if (-not $logPath) {
    $violations += 'beliefs_log is not configured'
} elseif (-not (Test-Path -LiteralPath $logPath)) {
    $violations += "beliefs log not found: $logPath"
} else {
    $item = Get-Item -LiteralPath $logPath
    if ($item.Length -le 0) {
        $violations += "beliefs log is empty: $logPath"
    }
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $maxAgeDays)
    if ($item.LastWriteTimeUtc -lt $cutoff) {
        $violations += "beliefs log has no writes in the last $maxAgeDays days: $logPath"
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Host "FAIL [belief-revision-audit] $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS belief-revision-audit (log present and fresh within $maxAgeDays days)" -ForegroundColor Green
exit 0

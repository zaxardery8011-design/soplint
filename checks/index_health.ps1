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
$indexPath = Resolve-ConfigPathValue -BaseDir $configDir -PathValue $cfg.index_file
$maxIndexKB = if ($cfg.PSObject.Properties.Name -contains 'index_max_kb') { [int]$cfg.index_max_kb } else { 50 }
$violations = @()

if (-not $indexPath) {
    $violations += 'index_file is not configured'
} elseif (-not (Test-Path -LiteralPath $indexPath)) {
    $violations += "index file not found: $indexPath"
} else {
    $kb = [math]::Round((Get-Item -LiteralPath $indexPath).Length / 1KB, 1)
    if ($kb -gt $maxIndexKB) {
        $violations += "index file is ${kb}KB, above the ${maxIndexKB}KB limit"
    }

    $links = @(
        Get-Content -LiteralPath $indexPath -Encoding utf8 |
        ForEach-Object { [regex]::Matches($_, '\]\(([^)]+\.md)\)') } |
        ForEach-Object { $_.Groups[1].Value }
    )
    $duplicates = @($links | Group-Object | Where-Object { $_.Count -gt 1 })
    foreach ($dup in $duplicates) {
        $violations += "duplicate index link x$($dup.Count): $($dup.Name)"
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object { Write-Host "FAIL [index-health] $_" -ForegroundColor Red }
    exit 1
}

Write-Host "PASS index-health (index ${kb}KB, no duplicate links)" -ForegroundColor Green
exit 0

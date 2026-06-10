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
$memoryDir = Resolve-ConfigPathValue -BaseDir $configDir -PathValue $cfg.memory_dir
$policyPath = Resolve-ConfigPathValue -BaseDir $configDir -PathValue $cfg.claude_md_path
$violations = @()

if (-not $memoryDir -or -not (Test-Path -LiteralPath $memoryDir)) {
    $violations += [pscustomobject]@{ file = '<config>'; msg = 'memory_dir not found or not configured' }
}
if (-not $policyPath -or -not (Test-Path -LiteralPath $policyPath)) {
    $violations += [pscustomobject]@{ file = '<config>'; msg = 'claude_md_path not found or not configured' }
}

if ($violations.Count -eq 0) {
    $policyText = Get-Content -Raw -LiteralPath $policyPath -Encoding utf8
    $files = @(Get-ChildItem -LiteralPath $memoryDir -Filter '*.md' -File | Where-Object { $_.Name -ne 'MEMORY.md' })
    foreach ($file in $files) {
        $body = Get-Content -Raw -LiteralPath $file.FullName -Encoding utf8
        $tokens = @(
            [regex]::Matches($body, '(?im)\b(?:default|policy)\b[^`\r\n]{0,12}`([^`\r\n]{2,80})`') |
            ForEach-Object { $_.Groups[1].Value.Trim() } |
            Where-Object { $_ } |
            Select-Object -Unique
        )
        foreach ($token in $tokens) {
            if ($policyText -notmatch [regex]::Escape($token)) {
                $violations += [pscustomobject]@{
                    file = $file.FullName
                    msg = "decision token '$token' appears in memory but not in the policy file"
                }
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object {
        Write-Host "FAIL [decision-propagation] $($_.file) - $($_.msg)" -ForegroundColor Red
    }
    exit 1
}

Write-Host "PASS decision-propagation (memory decisions are present in the policy file)" -ForegroundColor Green
exit 0

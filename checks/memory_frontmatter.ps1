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
$violations = @()

if (-not $memoryDir) {
    $violations += [pscustomobject]@{ file = '<config>'; line = 0; msg = 'memory_dir is not configured' }
} elseif (-not (Test-Path -LiteralPath $memoryDir)) {
    $violations += [pscustomobject]@{ file = $memoryDir; line = 0; msg = 'memory_dir not found' }
} else {
    $files = @(Get-ChildItem -LiteralPath $memoryDir -Filter '*.md' -File | Where-Object { $_.Name -ne 'MEMORY.md' })
    foreach ($file in $files) {
        $lines = @(Get-Content -LiteralPath $file.FullName -Encoding utf8)
        $hasFrontmatter = $lines.Count -gt 0 -and $lines[0] -match '^\s*---'
        $missing = @()
        if (-not $hasFrontmatter) { $missing += 'frontmatter-block' }
        if (-not ($lines | Where-Object { $_ -match '^name:\s*\S' })) { $missing += 'name' }
        if (-not ($lines | Where-Object { $_ -match '^description:\s*\S' })) { $missing += 'description' }
        if (-not ($lines | Where-Object { $_ -match '^\s*type:\s*\S' })) { $missing += 'type' }

        if ($missing.Count -gt 0) {
            $violations += [pscustomobject]@{
                file = $file.FullName
                line = 1
                msg = "missing: $($missing -join ', ')"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    $violations | ForEach-Object {
        Write-Host "FAIL [memory-frontmatter] $($_.file):$($_.line) - $($_.msg)" -ForegroundColor Red
    }
    exit 1
}

Write-Host "PASS memory-frontmatter ($($files.Count) memory files scanned)" -ForegroundColor Green
exit 0

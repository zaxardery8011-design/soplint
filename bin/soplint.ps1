#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Config = (Join-Path (Get-Location) 'soplint.config.json')
)

$ErrorActionPreference = 'Continue'
$repoRoot = Split-Path -Parent $PSScriptRoot
$checksDir = Join-Path $repoRoot 'checks'

try {
    $configPath = (Resolve-Path -LiteralPath $Config -ErrorAction Stop).Path
} catch {
    Write-Host "FAIL config file not found: $Config" -ForegroundColor Red
    exit 1
}

$scripts = @(Get-ChildItem -LiteralPath $checksDir -Filter '*.ps1' -File | Sort-Object Name)
if ($scripts.Count -ne 4) {
    Write-Host "FAIL runner expected 4 check scripts but found $($scripts.Count)" -ForegroundColor Red
    foreach ($s in $scripts) { Write-Host "  $($s.Name)" -ForegroundColor DarkRed }
    exit 1
}

$pass = 0
$fail = 0
$started = Get-Date

foreach ($script in $scripts) {
    $out = & pwsh -NoProfile -File $script.FullName -Config $configPath 2>&1
    $rc = $LASTEXITCODE
    $line = ($out | Select-String -Pattern '^(PASS|FAIL|SKIP|WARN)' | Select-Object -First 1).Line
    if (-not $line) { $line = ($out | Select-Object -Last 1) }

    if ($rc -eq 0) {
        $pass++
        Write-Host "[OK ] $($script.Name) - $line" -ForegroundColor Green
    } else {
        $fail++
        Write-Host "[FAIL] $($script.Name) (exit=$rc)" -ForegroundColor Red
        $out | ForEach-Object { Write-Host "       $_" -ForegroundColor DarkRed }
    }
}

$elapsed = [math]::Round(((Get-Date) - $started).TotalSeconds, 2)
Write-Host ''
Write-Host ('=' * 60)
if ($fail -eq 0) {
    Write-Host "SOPLINT: $pass pass / 0 fail (${elapsed}s)" -ForegroundColor Green
    exit 0
}

Write-Host "SOPLINT: $pass pass / $fail fail (${elapsed}s)" -ForegroundColor Red
exit 1

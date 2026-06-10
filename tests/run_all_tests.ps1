#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
$scripts = @(Get-ChildItem -LiteralPath $PSScriptRoot -Filter 'test_*.ps1' -File | Sort-Object Name)
$pass = 0
$fail = 0
$started = Get-Date

foreach ($script in $scripts) {
    $out = & pwsh -NoProfile -File $script.FullName 2>&1
    $rc = $LASTEXITCODE
    $line = ($out | Select-String -Pattern '^(PASS|FAIL)' | Select-Object -First 1).Line
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
    Write-Host "TESTS: $pass pass / 0 fail (${elapsed}s)" -ForegroundColor Green
    exit 0
}

Write-Host "TESTS: $pass pass / $fail fail (${elapsed}s)" -ForegroundColor Red
exit 1

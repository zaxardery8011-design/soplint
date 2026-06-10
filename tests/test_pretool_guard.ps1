#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$guard = Join-Path $repoRoot 'hooks/pretool-guard.ps1'
$rules = Join-Path $repoRoot 'rules/guard-rules.example.json'

$safePayload = @{
    tool_name = 'Shell'
    tool_input = @{ command = 'Get-ChildItem -Path .' }
} | ConvertTo-Json -Depth 5 -Compress

$blockedPayload = @{
    tool_name = 'Shell'
    tool_input = @{ command = 'Stop-Process daemon' }
} | ConvertTo-Json -Depth 5 -Compress

$safePayload | & pwsh -NoProfile -File $guard -Rules $rules 2>$null
if ($LASTEXITCODE -ne 0) { throw "expected safe payload to pass, got $LASTEXITCODE" }

$blockedPayload | & pwsh -NoProfile -File $guard -Rules $rules 2>$null
if ($LASTEXITCODE -ne 2) { throw "expected denied payload to exit 2, got $LASTEXITCODE" }

Write-Host 'PASS test_pretool_guard (pass+block)' -ForegroundColor Green
exit 0

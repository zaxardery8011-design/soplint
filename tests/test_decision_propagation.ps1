#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repoRoot 'checks/decision_propagation.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "soplint_decision_$([guid]::NewGuid().ToString('N'))"
$mem = Join-Path $tmp 'memory'
New-Item -ItemType Directory -Path $mem -Force | Out-Null

try {
    @'
---
name: default-tool
description: default tool fixture
metadata:
  type: policy
---

The default is `ask_research`.
'@ | Set-Content -LiteralPath (Join-Path $mem 'default_tool.md') -Encoding utf8NoBOM

    $badPolicy = Join-Path $tmp 'bad.md'
    $goodPolicy = Join-Path $tmp 'good.md'
    'No matching token here.' | Set-Content -LiteralPath $badPolicy -Encoding utf8NoBOM
    'The configured token is `ask_research`.' | Set-Content -LiteralPath $goodPolicy -Encoding utf8NoBOM

    $badConfig = Join-Path $tmp 'bad_config.json'
    @{ memory_dir = $mem; claude_md_path = $badPolicy } | ConvertTo-Json | Set-Content -LiteralPath $badConfig -Encoding utf8NoBOM
    $null = & pwsh -NoProfile -File $check -Config $badConfig 2>&1
    if ($LASTEXITCODE -ne 1) { throw "expected missing propagation to fail, got $LASTEXITCODE" }

    $goodConfig = Join-Path $tmp 'good_config.json'
    @{ memory_dir = $mem; claude_md_path = $goodPolicy } | ConvertTo-Json | Set-Content -LiteralPath $goodConfig -Encoding utf8NoBOM
    $null = & pwsh -NoProfile -File $check -Config $goodConfig 2>&1
    if ($LASTEXITCODE -ne 0) { throw "expected propagated token to pass, got $LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}

Write-Host 'PASS test_decision_propagation (fail+pass)' -ForegroundColor Green
exit 0

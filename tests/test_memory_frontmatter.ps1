#requires -Version 7.0
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$check = Join-Path $repoRoot 'checks/memory_frontmatter.ps1'
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) "soplint_frontmatter_$([guid]::NewGuid().ToString('N'))"
$mem = Join-Path $tmp 'memory'
New-Item -ItemType Directory -Path $mem -Force | Out-Null

try {
    $config = Join-Path $tmp 'config.json'
    @{ memory_dir = $mem } | ConvertTo-Json | Set-Content -LiteralPath $config -Encoding utf8NoBOM

    @'
---
name: missing-type
description: fixture
---

body
'@ | Set-Content -LiteralPath (Join-Path $mem 'bad.md') -Encoding utf8NoBOM
    $null = & pwsh -NoProfile -File $check -Config $config 2>&1
    if ($LASTEXITCODE -ne 1) { throw "expected missing type to fail, got $LASTEXITCODE" }

    Remove-Item -LiteralPath (Join-Path $mem 'bad.md') -Force
    @'
---
name: good
description: fixture
metadata:
  type: policy
---

body
'@ | Set-Content -LiteralPath (Join-Path $mem 'good.md') -Encoding utf8NoBOM
    $null = & pwsh -NoProfile -File $check -Config $config 2>&1
    if ($LASTEXITCODE -ne 0) { throw "expected full frontmatter to pass, got $LASTEXITCODE" }
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force }
}

Write-Host 'PASS test_memory_frontmatter (fail+pass)' -ForegroundColor Green
exit 0

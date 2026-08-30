#requires -Version 7.0
[CmdletBinding()]
param()

# Refresh mtime of the bundled pass-fixture beliefs log.
# checks/belief_revision_audit.ps1 reads LastWriteTimeUtc (not jsonl `ts`).
# The committed fixture content is static; without this bump, the example
# config Quickstart goes red 30 days after the last checkout/touch.

$ErrorActionPreference = 'Stop'
$log = Join-Path $PSScriptRoot 'fixtures/pass/beliefs.jsonl'
if (-not (Test-Path -LiteralPath $log)) {
    Write-Host "FAIL pass fixture missing: $log" -ForegroundColor Red
    exit 1
}

(Get-Item -LiteralPath $log).LastWriteTimeUtc = (Get-Date).ToUniversalTime()
exit 0

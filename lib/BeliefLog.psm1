#requires -Version 7.0

function Resolve-SoplintPath {
    param([string]$BaseDir, [string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $null }
    if ([System.IO.Path]::IsPathRooted($PathValue)) { return $PathValue }
    return (Join-Path $BaseDir $PathValue)
}

function Get-SoplintBeliefsLogPath {
    param([string]$Config = (Join-Path (Get-Location) 'soplint.config.json'))
    $configPath = (Resolve-Path -LiteralPath $Config -ErrorAction Stop).Path
    $configDir = Split-Path -Parent $configPath
    $cfg = Get-Content -Raw -LiteralPath $configPath -Encoding utf8 | ConvertFrom-Json
    $path = Resolve-SoplintPath -BaseDir $configDir -PathValue $cfg.beliefs_log
    if (-not $path) { throw 'beliefs_log is not configured' }
    return $path
}

function Add-BeliefRevision {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$From,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$To,
        [Parameter(Mandatory)]
        [ValidateSet('agent_review','worker_completed','user_calibration','specification_review','multi_perspective','estimate_correction','memory_conflict','other')]
        [string]$Trigger,
        [string]$ConfidenceShift = '',
        [string]$Config = (Join-Path (Get-Location) 'soplint.config.json')
    )

    $logPath = Get-SoplintBeliefsLogPath -Config $Config
    $dir = Split-Path -Parent $logPath
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $now = (Get-Date).ToUniversalTime()
    $record = [ordered]@{
        id = "belief_$($now.ToString('yyyyMMddHHmmssfff'))_$([guid]::NewGuid().ToString('N').Substring(0, 8))"
        ts = $now.ToString('o')
        from_belief = $From
        to_belief = $To
        trigger = $Trigger
        confidence_shift = $ConfidenceShift
    }

    $json = ($record | ConvertTo-Json -Compress -Depth 5)
    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::AppendAllText($logPath, $json + [Environment]::NewLine, $encoding)

    return [pscustomobject]@{
        ok = $true
        path = $logPath
        id = $record.id
    }
}

function Get-BeliefRevisions {
    [CmdletBinding()]
    param(
        [int]$Last = 20,
        [string]$Config = (Join-Path (Get-Location) 'soplint.config.json')
    )

    $logPath = Get-SoplintBeliefsLogPath -Config $Config
    if (-not (Test-Path -LiteralPath $logPath)) { return @() }

    $records = @(
        Get-Content -LiteralPath $logPath -Encoding utf8 |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_ | ConvertFrom-Json }
    )

    if ($Last -gt 0) {
        return @($records | Select-Object -Last $Last)
    }
    return $records
}

Export-ModuleMember -Function Add-BeliefRevision, Get-BeliefRevisions

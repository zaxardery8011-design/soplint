#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$Rules = (Join-Path (Split-Path -Parent $PSScriptRoot) 'rules/guard-rules.json')
)

$ErrorActionPreference = 'Stop'

function Get-AstCommandSignatures {
    param([string]$ScriptText)
    if ([string]::IsNullOrWhiteSpace($ScriptText)) { return @() }

    $tokens = $null
    $errors = $null
    $ast = $null
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptText, [ref]$tokens, [ref]$errors)
    } catch {
        return $null
    }
    if ($null -eq $ast) { return $null }

    $commandAsts = $ast.FindAll({
        param($node) $node -is [System.Management.Automation.Language.CommandAst]
    }, $true)

    $signatures = @()
    foreach ($command in $commandAsts) {
        $parts = @()
        foreach ($element in $command.CommandElements) {
            if ($element -is [System.Management.Automation.Language.CommandParameterAst]) {
                $parts += '-' + $element.ParameterName
            } elseif ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                if ($element.StringConstantType -eq [System.Management.Automation.Language.StringConstantType]::BareWord) {
                    $parts += $element.Value
                }
            }
        }
        if ($parts.Count -gt 0) { $signatures += ($parts -join ' ') }
    }
    return ,$signatures
}

function Get-GuardRules {
    param([string]$RulesPath)
    $repoRoot = Split-Path -Parent $PSScriptRoot
    $examplePath = Join-Path $repoRoot 'rules/guard-rules.example.json'
    $path = if (Test-Path -LiteralPath $RulesPath) { $RulesPath } else { $examplePath }
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    return @((Get-Content -Raw -LiteralPath $path -Encoding utf8 | ConvertFrom-Json).rules)
}

function Find-RuleHit {
    param([string]$Text, [object[]]$RuleSet)
    if ([string]::IsNullOrWhiteSpace($Text)) { return $null }
    if ($Text -match '(?i)\bskip-guard\b') { return $null }

    foreach ($rule in $RuleSet) {
        if ($rule.kind -eq 'deny' -and $Text -match $rule.pattern) { return $rule }
        if ($rule.kind -eq 'novelty_gate' -and $Text -match $rule.pattern) {
            $ack = if ($rule.ack_pattern) { [string]$rule.ack_pattern } else { 'novelty-checked' }
            if ($Text -notmatch $ack) { return $rule }
        }
    }
    return $null
}

$raw = ''
try {
    $raw = [Console]::In.ReadToEnd()
    $ruleSet = Get-GuardRules -RulesPath $Rules
    $payload = $null
    try { $payload = $raw | ConvertFrom-Json } catch { $payload = $null }

    if ($null -eq $payload) {
        $hit = Find-RuleHit -Text $raw -RuleSet $ruleSet
        if ($hit) {
            [Console]::Error.WriteLine("[pretool-guard] BLOCKED (raw scan) by $($hit.id): $($hit.reason)")
            exit 2
        }
        exit 0
    }

    $inputObject = $payload.tool_input
    $parts = @()

    if ($inputObject.command) {
        $signatures = Get-AstCommandSignatures -ScriptText ([string]$inputObject.command)
        if ($null -eq $signatures) {
            $stripped = [string]$inputObject.command
            $stripped = $stripped -replace '"[^"]*"', '' -replace "'[^']*'", '' -replace '`[^`]*`', ''
            $parts += $stripped
        } else {
            $parts += $signatures
        }
    }

    foreach ($field in @('file_path', 'content', 'new_string')) {
        if ($inputObject.$field) {
            $text = [string]$inputObject.$field
            if ($text.Length -gt 4000) { $text = $text.Substring(0, 4000) }
            $text = $text -replace '"[^"]*"', '' -replace "'[^']*'", '' -replace '`[^`]*`', ''
            $parts += $text
        }
    }

    $haystack = ($parts -join ' ')
    $hit = Find-RuleHit -Text $haystack -RuleSet $ruleSet
    if ($hit) {
        [Console]::Error.WriteLine("[pretool-guard] BLOCKED by $($hit.id): $($hit.reason)")
        exit 2
    }
    exit 0
} catch {
    try {
        $ruleSet = Get-GuardRules -RulesPath $Rules
        $hit = Find-RuleHit -Text $raw -RuleSet $ruleSet
        if ($hit) {
            [Console]::Error.WriteLine("[pretool-guard] BLOCKED (error-path raw scan) by $($hit.id)")
            exit 2
        }
    } catch {}
    exit 0
}

# preToolUse guard for the ticket workflow agents (Copilot harness contract).
# stdin: {"toolName": ..., "toolArgs": ...}; stdout: one decision object, or {} for no decision.
# Errors exit non-zero, which the Copilot harness treats as deny. Timeouts fail open.
# Defense in depth only: regexes can be bypassed; rely on branch protection and sandboxing.
$ErrorActionPreference = 'Stop'

$payload = [Console]::In.ReadToEnd() | ConvertFrom-Json
if ($null -eq $payload -or $payload.toolName -isnot [string]) {
    [Console]::Error.WriteLine('agent-guard: expected a Copilot preToolUse payload with a string toolName.')
    exit 1
}
$toolName = $payload.toolName

$toolArgs = $payload.toolArgs
if ($toolArgs -is [string]) {
    try { $toolArgs = $toolArgs | ConvertFrom-Json } catch { }
}

# Match against raw string values so JSON escaping (\\, \u003e) can't hide anything.
function Get-Strings($value) {
    if ($null -eq $value) { return }
    if ($value -is [string]) { return $value }
    if ($value -is [System.Management.Automation.PSCustomObject]) {
        foreach ($p in $value.PSObject.Properties) { Get-Strings $p.Value }
        return
    }
    if ($value -is [System.Collections.IEnumerable]) { foreach ($v in $value) { Get-Strings $v } }
}
$argText = @(Get-Strings $toolArgs) -join "`n"

function Send-Decision([string]$decision, [string]$reason) {
    [Console]::Out.Write((@{ permissionDecision = $decision; permissionDecisionReason = $reason } | ConvertTo-Json -Compress))
    exit 0
}

$isShell = $toolName -match 'bash|powershell|shell|terminal|execute|run_in'
$isEdit  = $toolName -match 'edit|create|apply_patch|str_replace|write|replace'

# Agents must not modify their own guardrails.
$protectedPath = 'agent-guard\.ps1|\.agent\.md|SKILL\.md|plugin\.json|hooks\.json|com\.github\.copilot[\\/]|[\\/]\.copilot[\\/]|[\\/]\.github[\\/](agents|hooks|skills|copilot)[\\/]'
$writeVerb     = 'Set-Content|Add-Content|Out-File|Copy-Item|Move-Item|Remove-Item|New-Item|Rename-Item|WriteAll|\b(sc|ac|cp|copy|mv|move|rm|del|ren|tee|sed)\b|>'
if ($argText -match $protectedPath -and ($isEdit -or ($isShell -and $argText -match $writeVerb))) {
    Send-Decision 'deny' 'Agents may not modify agent definitions, plugin files or hook scripts.'
}

if ($isShell) {
    $denyPatterns = @(
        '\bgit\b[^;&|\n]*\bpush\b',
        '\bgit\b[^;&|\n]*\breset\b[^;&|\n]*--hard',
        '\bgit\b[^;&|\n]*\bclean\b[^;&|\n]*\s-\w*f',
        '\bgit\b[^;&|\n]*\bbranch\b[^;&|\n]*\s(-d|--delete)\b',
        '--force\b', '--no-verify\b',
        '\b(Remove-Item|ri|rm|rmdir|rd|del|erase)\b[^;&|\n]*\s(-r\w*|-fr|/s)\b',
        '-Recurse\b[^\n]*\|\s*(Remove-Item|ri|rm|del)\b',
        'Directory\]::Delete\(', '\bFormat-Volume\b',
        '\bnuget(\.exe)?\s+push\b', 'gradlew(\.bat)?\b[^;&|\n]*\bpublish', '\bnpm\s+publish\b',
        '\baz\b[^;&|\n]*\bdelete\b', '\bkubectl\b[^;&|\n]*\bdelete\b', '\bdotnet\s+ef\s+database\s+drop\b',
        '\b(powershell|pwsh)(\.exe)?\b[^;&|\n]*\s-(e|ec|en|enc|encodedcommand)\b', '\b(Invoke-Expression|iex)\b'
    )
    foreach ($p in $denyPatterns) {
        if ($argText -match $p) { Send-Decision 'deny' "Blocked by agent-guard: matches '$p'." }
    }
}

# Jira/Confluence write operations always need human confirmation.
if ($toolName -match 'addComment|addOrEdit|addWorklog|transitionJira|editJira|createJira|createIssueLink|createConfluence|updateConfluence|uploadAttachment|createCompass|delete') {
    Send-Decision 'ask' "Write operation to Atlassian ($toolName) requires approval."
}

if ($isShell) {
    $askPatterns = @(
        '\bgit\b[^;&|\n]*\b(commit|merge|rebase|checkout|switch|stash|tag|cherry-pick|revert|restore)\b',
        '\bdotnet\s+ef\s+database\s+update\b'
    )
    foreach ($p in $askPatterns) {
        if ($argText -match $p) { Send-Decision 'ask' "Needs approval: matches '$p'." }
    }
}

[Console]::Out.Write('{}')
exit 0

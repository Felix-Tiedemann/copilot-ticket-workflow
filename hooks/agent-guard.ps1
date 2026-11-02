# PreToolUse guard for the ticket workflow agents.
# Reads the hook payload from stdin; prints a permission decision (deny/ask) or nothing (allow).
$ErrorActionPreference = 'Stop'

$raw = [Console]::In.ReadToEnd()
try { $payload = $raw | ConvertFrom-Json } catch { exit 0 }

$toolName  = [string]$payload.tool_name
$toolInput = if ($null -ne $payload.tool_input) { $payload.tool_input | ConvertTo-Json -Depth 10 -Compress } else { '' }

function Send-Decision([string]$decision, [string]$reason) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = $decision
            permissionDecisionReason = $reason
        }
    } | ConvertTo-Json -Depth 5 -Compress
    exit 0
}

# Jira/Confluence write operations always need human confirmation.
if ($toolName -match 'addComment|addOrEdit|addWorklog|transitionJira|editJira|createJira|createIssueLink|createConfluence|updateConfluence|uploadAttachment|createCompass|delete') {
    Send-Decision 'ask' "Write operation to Atlassian ($toolName) requires approval."
}

# Agents must not modify their own guardrails.
if ($toolName -match 'edit|create_file|replace|write' -and $toolInput -match 'agent-guard\.ps1|\.agent\.md|\.prompt\.md') {
    Send-Decision 'deny' 'Agents may not modify agent definitions or hook scripts.'
}

if ($toolName -match 'terminal|execute|run_in') {
    $denyPatterns = @(
        'git\s+push', 'git\s+reset\s+--hard', 'git\s+clean\s+-\w*f', 'git\s+branch\s+-D',
        '--force\b', '--no-verify',
        'rm\s+-rf', 'Remove-Item\b.*-Recurse', 'rmdir\s+/s', 'del\s+/s', 'Format-Volume',
        'dotnet\s+nuget\s+push', 'gradlew(\.bat)?\b.*\bpublish', 'npm\s+publish',
        'az\s+.*\bdelete\b', 'kubectl\s+delete', 'dotnet\s+ef\s+database\s+drop'
    )
    foreach ($p in $denyPatterns) {
        if ($toolInput -match $p) { Send-Decision 'deny' "Blocked by agent-guard: matches '$p'." }
    }

    $askPatterns = @(
        'git\s+(commit|merge|rebase|checkout|switch|stash|tag|cherry-pick|revert)',
        'dotnet\s+ef\s+database\s+update'
    )
    foreach ($p in $askPatterns) {
        if ($toolInput -match $p) { Send-Decision 'ask' "Needs approval: matches '$p'." }
    }
}

exit 0

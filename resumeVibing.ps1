#requires -Version 5.1
<#
    resumeVibing.ps1 — post-reboot one-shot resume for the IPChanger 4.0 project.
    Prints where things stand, then drops you back into the Claude Code session.
        powershell.exe -ExecutionPolicy Bypass -File .\resumeVibing.ps1
        powershell.exe -ExecutionPolicy Bypass -File .\resumeVibing.ps1 -JustDoIt
    Switches:
        -JustDoIt    Resume Claude with --dangerously-skip-permissions (no approval prompts).
        -NoLaunch    Just print the orientation; don't launch Claude.
        -SessionId   Claude session to resume. If omitted, falls back to
                     $env:CLAUDE_RESUME_SESSION, then the .resume-session file.
#>
[CmdletBinding()]
param(
    [string]$SessionId,
    [switch]$JustDoIt,
    [switch]$NoLaunch
)

# Project root = wherever this script lives (portable; no hardcoded path).
$ProjectDir = $PSScriptRoot
Set-Location $ProjectDir

# Resolve the session id: -SessionId  >  env var  >  local .resume-session file.
if (-not $SessionId) { $SessionId = $env:CLAUDE_RESUME_SESSION }
if (-not $SessionId) {
    $sessionFile = Join-Path $ProjectDir '.resume-session'
    if (Test-Path $sessionFile) { $SessionId = (Get-Content $sessionFile -Raw).Trim() }
}

Write-Host ''
Write-Host '================ IPChanger 4.0 — resume ================' -ForegroundColor Cyan
Write-Host "Project: $ProjectDir"
Write-Host ''

# --- Git state -------------------------------------------------------------
Write-Host '--- Git ---' -ForegroundColor Yellow
Write-Host "Branch:      $(git rev-parse --abbrev-ref HEAD 2>$null)"
Write-Host "Last commit: $(git log --oneline -1 2>$null)"
Write-Host "Remote:      $(git remote get-url origin 2>$null)"
$upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
if ($upstream) {
    Write-Host "Upstream:    $upstream"
} else {
    Write-Host "Upstream:    (none - committed locally, NOT pushed to GitHub yet)" -ForegroundColor Red
}
Write-Host ''
Write-Host 'Working tree:'
$status = git status --short
if ($status) { $status | ForEach-Object { "  $_" } } else { Write-Host '  clean' -ForegroundColor Green }
Write-Host ''

# --- Files -----------------------------------------------------------------
Write-Host '--- Files ---' -ForegroundColor Yellow
Get-ChildItem -File | Select-Object Name, Length, LastWriteTime | Format-Table -Auto

# --- Where we left off / next steps ---------------------------------------
Write-Host '--- Next steps (as of 2026-05-26) ---' -ForegroundColor Yellow
@(
    '1. TEST the merged app:  .\Set-NetworkConfig.ps1   (self-elevates via UAC)',
    '     - adapter list = all physical adapters, no Wi-Fi / WWAN',
    '     - try DHCP toggle + Apply on a test adapter',
    '2. BUILD the exe:        .\build.ps1               (add -Sign to sign with your cert)',
    '3. TEST the installer:   .\SetNet-Install.ps1 -Action Install',
    '     - lands in C:\Program Files\IPChanger + Desktop/Start Menu shortcuts',
    '4. RENAME to IPChanger.exe once verified: flip the two # TODO markers in',
    '     build.ps1 (-OutputExe) and SetNet-Install.ps1 ($ExeName)',
    '5. PUSH when ready:      git push -u origin main',
    '     - if the GitHub repo already has commits:',
    '       git pull --allow-unrelated-histories origin main   (then push)'
) | ForEach-Object { Write-Host "  $_" }
Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host ''

# --- Relaunch the Claude Code session -------------------------------------
if (-not $SessionId) {
    Write-Warning 'No session id found. Set one via -SessionId, $env:CLAUDE_RESUME_SESSION, or a .resume-session file.'
    return
}

$manualCmd = "claude --resume $SessionId" + $(if ($JustDoIt) { ' --dangerously-skip-permissions' } else { '' })

if ($NoLaunch) {
    Write-Host 'Skipping launch (-NoLaunch). To resume manually:' -ForegroundColor DarkGray
    Write-Host "  $manualCmd" -ForegroundColor DarkGray
    return
}

if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
    Write-Warning "'claude' not found on PATH. Resume manually with:"
    Write-Host "  $manualCmd"
    return
}

$claudeArgs = @('--resume', $SessionId)
if ($JustDoIt) {
    $claudeArgs += '--dangerously-skip-permissions'
    Write-Host 'Resuming Claude WITHOUT permission prompts (-JustDoIt).' -ForegroundColor Yellow
}
else {
    Write-Host 'Resuming Claude (normal permission prompts). Add -JustDoIt to skip them.' -ForegroundColor Green
}
Write-Host "  $manualCmd" -ForegroundColor DarkGray
Write-Host ''

claude @claudeArgs

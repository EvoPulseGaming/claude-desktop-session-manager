<#
.SYNOPSIS
    Consolidate Claude Desktop "Claude Code" sessions from every signed-in account
    into your CURRENTLY LOGGED-IN account, so they all appear in the session list.

.DESCRIPTION
    Claude Desktop stores each account's local session list on disk at:
        <store>\claude-code-sessions\<accountUuid>\<orgUuid>\local_*.json
    The app only shows the account you're currently logged in as. This script copies
    the session files from every OTHER account into your current account's active
    workspace folder, so switching accounts no longer hides them.

    Notes established by investigation:
      * Claude Desktop is a packaged (MSIX) app whose AppData\{Local,LocalLow,Roaming}
        IS virtualized. The REAL, always-reachable physical store is
        %LOCALAPPDATA%\Packages\Claude_*\LocalCache\Roaming\Claude\claude-code-sessions .
        The %AppData%\Roaming\Claude path only exists inside the app's container view
        (so Explorer / a plain PowerShell can't see it); this script resolves the
        physical package path so it works from either context.
      * The actual transcripts live in %USERPROFILE%\.claude\projects and are NOT
        account-scoped, so migrated sessions stay fully resumable. This script does not
        need to touch them.
      * "Current account" = config.json -> lastKnownAccountUuid.
      * "Active workspace" = the current account's org subfolder with the newest session.

.PARAMETER List
    Only list accounts and session counts. Makes no changes.

.PARAMETER Move
    Move files out of the other accounts instead of copying. Default is copy (safer).

.PARAMETER NoOverwrite
    Do not touch sessions that already exist in the current account. By default the
    script refreshes an existing copy only when the OTHER account's copy is newer
    (newest-wins, by lastActivityAt); -NoOverwrite disables that and leaves existing
    copies untouched (pure copy-once).

.PARAMETER DryRun
    Show what would be copied/moved without changing anything.

.PARAMETER NoBackup
    Skip the timestamped backup (not recommended).

.PARAMETER RestartDesktop
    After migrating, fully restart Claude Desktop so it re-scans the store.
    WARNING: this kills all claude.exe processes. Do NOT use this flag if you are
    running the script from inside a Claude Desktop session/terminal - it would kill
    your own session. Run it from a plain PowerShell window (Win+R -> powershell) instead.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$HOME\.claude\Consolidate-ClaudeSessions.ps1" -List
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$HOME\.claude\Consolidate-ClaudeSessions.ps1"
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File "$HOME\.claude\Consolidate-ClaudeSessions.ps1" -DryRun
#>
[CmdletBinding()]
param(
    [switch]$List,
    [switch]$Move,
    [switch]$NoOverwrite,
    [switch]$DryRun,
    [switch]$NoBackup,
    [switch]$RestartDesktop
)

$ErrorActionPreference = 'Stop'

function Write-Head($t) { Write-Host "`n$t" -ForegroundColor Cyan }

# Locate the Claude Desktop data folder.
# Claude Desktop is a packaged (MSIX) app; its data lives at:
#   %LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Roaming\Claude
# <PackageFamilyName> = "Claude_<publisherHash>". That hash is a DETERMINISTIC hash of
# Anthropic's code-signing identity: identical on every machine and stable across app
# updates (changing it would strand every user's local data, so it effectively never
# changes). We therefore hardcode it as the primary path, keeping a tiny content-based
# fallback only for the rare rename / non-packaged / in-container case.
$KnownPackageFamily = 'Claude_pzs8sxrjxfjjc'

function Resolve-ClaudeDir {
    # Primary: the known, hardcoded package location.
    $known = Join-Path $env:LOCALAPPDATA "Packages\$KnownPackageFamily\LocalCache\Roaming\Claude"
    if (Test-Path (Join-Path $known 'claude-code-sessions')) { return $known }

    # Fallback (only if the hardcoded name ever stops matching): find the store by content.
    $cands = New-Object System.Collections.Generic.List[string]
    Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Packages') -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { $cands.Add((Join-Path $_.FullName 'LocalCache\Roaming\Claude')) }
    $cands.Add((Join-Path $env:APPDATA 'Claude'))   # non-packaged install / in-container view
    return $cands | Select-Object -Unique |
        Where-Object { Test-Path (Join-Path $_ 'claude-code-sessions') } |
        Sort-Object { (Get-Item (Join-Path $_ 'claude-code-sessions')).LastWriteTime } -Descending |
        Select-Object -First 1
}
$claudeDir = Resolve-ClaudeDir
if (-not $claudeDir) {
    throw "Could not locate the Claude session store. Looked via Get-AppxPackage, every %LOCALAPPDATA%\Packages\*\LocalCache\Roaming\Claude, and %APPDATA%\Claude. Is Claude Desktop installed and has it been run at least once?"
}
$root       = Join-Path $claudeDir 'claude-code-sessions'
$configPath = Join-Path $claudeDir 'config.json'
Write-Host "Using store: $root" -ForegroundColor DarkGray

if (-not (Test-Path -LiteralPath $root))       { throw "Session store not found: $root" }
if (-not (Test-Path -LiteralPath $configPath)) { throw "config.json not found: $configPath" }

# --- Identify the current (logged-in) account -----------------------------------
$current = (Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json).lastKnownAccountUuid
if (-not $current) { throw "Could not read 'lastKnownAccountUuid' from config.json" }

# --- Inventory every account -----------------------------------------------------
Write-Head "Accounts found in $root :"
$accounts = Get-ChildItem -LiteralPath $root -Directory
foreach ($a in $accounts) {
    $count = (Get-ChildItem -LiteralPath $a.FullName -Recurse -Filter 'local_*.json' -ErrorAction SilentlyContinue).Count
    $tag = if ($a.Name -eq $current) { '  <-- CURRENT (logged in)' } else { '' }
    Write-Host ("  {0}  ({1} sessions){2}" -f $a.Name, $count, $tag)
}

if ($List) { Write-Host "`n(-List only: no changes made)" -ForegroundColor DarkGray; return }

# --- Determine target: current account's active workspace (newest org) -----------
$currentDir = Join-Path $root $current
$targetOrg = Get-ChildItem -LiteralPath $currentDir -Directory |
    Sort-Object { (Get-ChildItem -LiteralPath $_.FullName -Filter 'local_*.json' -ErrorAction SilentlyContinue |
                   Measure-Object LastWriteTime -Maximum).Maximum } -Descending |
    Select-Object -First 1
if (-not $targetOrg) {
    throw "Current account ($current) has no workspace folder yet. Open Claude Desktop on this account once, then re-run."
}
$dest = $targetOrg.FullName
Write-Head "Target (current account's active workspace):"
Write-Host "  $dest"

# --- Backup ----------------------------------------------------------------------
if (-not $NoBackup -and -not $DryRun) {
    $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $claudeDir "claude-code-sessions.backup-$stamp"
    Copy-Item -LiteralPath $root -Destination $backup -Recurse
    Write-Host "`nBackup: $backup" -ForegroundColor DarkGray
}

# --- Migrate every OTHER account's sessions into the target ----------------------
# Conflict handling (newest-wins): a session that already exists in the current account
# is refreshed only when the OTHER account's copy is strictly newer (by lastActivityAt).
# That keeps the list metadata (title, last-active time, turn count, archived state)
# current after you continue a shared session on the other account, without ever
# regressing a copy you advanced here. -NoOverwrite forces pure copy-once.
# NOTE: the conversation transcript lives in %USERPROFILE%\.claude\projects and is shared
# across accounts, so opening a session always loads the current conversation regardless.
$new = 0; $refreshed = 0; $kept = 0; $bad = 0
foreach ($a in ($accounts | Where-Object { $_.Name -ne $current })) {
    foreach ($f in (Get-ChildItem -LiteralPath $a.FullName -Recurse -Filter 'local_*.json')) {
        try { $srcJson = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json }
        catch { Write-Warning "Invalid JSON, skipping: $($f.FullName)"; $bad++; continue }

        $targetPath = Join-Path $dest $f.Name
        $action = 'new'
        if (Test-Path -LiteralPath $targetPath) {
            if ($NoOverwrite) { $kept++; continue }
            $tgtJson = try { Get-Content -LiteralPath $targetPath -Raw | ConvertFrom-Json } catch { $null }
            $sA = [double]($srcJson.lastActivityAt); $tA = [double]($tgtJson.lastActivityAt)
            $srcNewer = if ($sA -and $tA) { $sA -gt $tA }
                        else { (Get-Item -LiteralPath $f.FullName).LastWriteTime -gt (Get-Item -LiteralPath $targetPath).LastWriteTime }
            if (-not $srcNewer) { $kept++; continue }
            $action = 'refresh'
        }

        if ($DryRun) {
            Write-Host ("  [dry-run] {0,-7} {1}  <- {2}" -f $action, $f.Name, $a.Name.Substring(0,8))
        } elseif ($Move) {
            Move-Item -LiteralPath $f.FullName -Destination $targetPath -Force
        } else {
            Copy-Item -LiteralPath $f.FullName -Destination $targetPath -Force
        }
        if ($action -eq 'refresh') { $refreshed++ } else { $new++ }
    }
}

Write-Head "Result:"
Write-Host ("  New: {0}   Refreshed (newer on other account): {1}   Kept (unchanged): {2}   Invalid: {3}" -f `
    $new, $refreshed, $kept, $bad) -ForegroundColor Green
if (-not $DryRun) {
    $total = (Get-ChildItem -LiteralPath $dest -Filter 'local_*.json').Count
    Write-Host "  Current account now lists $total sessions."
}

# --- Restart Claude Desktop (optional) ------------------------------------------
if ($RestartDesktop -and -not $DryRun) {
    Write-Host "`nRestarting Claude Desktop..." -ForegroundColor Yellow
    $app = Get-StartApps | Where-Object { $_.Name -match 'Claude' } | Select-Object -First 1
    Get-Process claude -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 2
    if ($app) { Start-Process "shell:AppsFolder\$($app.AppID)" }
    else { Write-Warning "Couldn't resolve the Claude app id; relaunch it manually." }
} elseif (-not $DryRun) {
    Write-Host "`nNext: FULLY quit Claude Desktop (tray icon -> Quit) and reopen it to see the sessions." -ForegroundColor Yellow
}

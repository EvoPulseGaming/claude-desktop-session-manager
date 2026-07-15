<#
.SYNOPSIS
    List or launch additional, fully isolated Claude Desktop instances - each with its
    own login (account), config, MCP servers, and session store.

.DESCRIPTION
    Claude Desktop honors Electron's --user-data-dir flag. Launching the app with a
    different data directory bypasses the per-directory single-instance lock, so you can
    run several Claude Desktops side by side, each signed into a different account.

    Convention: instance profiles live under %USERPROFILE%\ClaudeInstances\<name>.
    The Session Manager GUI (Session-Manager.ps1) automatically discovers every
    instance there and lets you copy/move sessions between instances and accounts.

.PARAMETER List
    Show all instances (main + every profile under the instance root), whether each is
    running, and how many sessions it holds. This is the default when no -Launch given.

.PARAMETER Launch
    Name of the instance to launch. Created on first use (fresh login screen - sign
    into whichever account you want this instance to hold). Names: letters, digits,
    dot, dash, underscore.

.PARAMETER Root
    Instance profiles root. Default: %USERPROFILE%\ClaudeInstances

.EXAMPLE
    .\Claude-Instances.ps1                    # list instances
.EXAMPLE
    .\Claude-Instances.ps1 -Launch account2   # launch (or create + launch) 'account2'
#>
[CmdletBinding()]
param(
    [switch]$List,
    [string]$Launch,
    [string]$Root = (Join-Path $env:USERPROFILE 'ClaudeInstances')
)

$ErrorActionPreference = 'Stop'

function Resolve-ClaudeExe {
    # Authoritative: ask Windows for the installed package (survives version bumps).
    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue |
           Where-Object { $_.PackageFamilyName -like 'Claude_*' } | Select-Object -First 1
    if ($pkg) {
        $exe = Join-Path $pkg.InstallLocation 'app\Claude.exe'
        if (Test-Path -LiteralPath $exe) { return $exe }
    }
    # Fallback: direct glob (works when Get-AppxPackage is unavailable).
    try {
        $cand = Get-ChildItem "$env:ProgramFiles\WindowsApps" -Directory -Filter 'Claude_*' -ErrorAction Stop |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'app\Claude.exe' } |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($cand) { return $cand }
    } catch { }
    throw "Claude Desktop package not found. Is it installed?"
}

function Get-RunningDataDirs {
    # user-data-dir of every running claude.exe (empty string = main instance).
    # Skip processes with unreadable command lines, and only attribute a process to
    # 'main' when it is really the packaged Desktop app (WindowsApps path) - the
    # Claude Code CLI also runs as claude.exe and must not count.
    $dirs = @{}
    Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue | ForEach-Object {
        if (-not $_.CommandLine) { return }
        if ($_.CommandLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))') {
            $d = if ($Matches[1]) { $Matches[1] } else { $Matches[2] }
            $dirs[$d.TrimEnd('\').ToLower()] = $true
        } elseif ($_.ExecutablePath -and $_.ExecutablePath -like '*\WindowsApps\*') {
            $dirs[''] = $true
        }
    }
    return $dirs
}

if ($Launch) {
    # Must start alphanumeric and not be all dots - blocks '.', '..' and hidden-ish
    # names that would escape (or become) the instance root itself.
    if ($Launch -notmatch '^(?!\.+$)[A-Za-z0-9][A-Za-z0-9._-]*$') { throw "Instance name '$Launch' is invalid. Start with a letter/digit; letters, digits, dot, dash, underscore only." }
    if ($Launch -eq 'main') { throw "'main' is the normal Claude Desktop install - launch it from the Start menu / taskbar as usual." }
    $exe = Resolve-ClaudeExe
    $dir = Join-Path $Root $Launch
    $isNew = -not (Test-Path -LiteralPath $dir)
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Start-Process -FilePath $exe -ArgumentList "--user-data-dir=`"$dir`""
    Write-Host "Launched instance '$Launch'  (profile: $dir)"
    if ($isNew) { Write-Host "New instance: a fresh login screen will appear - sign into the account you want this instance to hold." }
    Write-Host "Note: claude:// login deep-links go to the most recently registered instance; if a browser login bounces to the wrong window, close the other instance during login."
    return
}

# ---- List (default) ----
$exeOk = try { Resolve-ClaudeExe } catch { $null }
$running = Get-RunningDataDirs
Write-Host ("{0,-14} {1,-9} {2,9}  {3}" -f 'INSTANCE','RUNNING','SESSIONS','PROFILE')
# main
$mainStore = Join-Path $env:LOCALAPPDATA 'Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude\claude-code-sessions'
$mainCount = if (Test-Path $mainStore) { @(Get-ChildItem $mainStore -Recurse -Filter 'local_*.json' -EA SilentlyContinue).Count } else { 0 }
Write-Host ("{0,-14} {1,-9} {2,9}  {3}" -f 'main', $(if ($running.ContainsKey('')) {'yes'} else {'no'}), $mainCount, '(MSIX LocalCache store)')
# instances
if (Test-Path -LiteralPath $Root) {
    foreach ($d in (Get-ChildItem -LiteralPath $Root -Directory | Sort-Object Name)) {
        $store = Join-Path $d.FullName 'claude-code-sessions'
        $count = if (Test-Path $store) { @(Get-ChildItem $store -Recurse -Filter 'local_*.json' -EA SilentlyContinue).Count } else { 0 }
        $run = $running.ContainsKey($d.FullName.TrimEnd('\').ToLower())
        Write-Host ("{0,-14} {1,-9} {2,9}  {3}" -f $d.Name, $(if ($run) {'yes'} else {'no'}), $count, $d.FullName)
    }
} else {
    Write-Host "(no instance profiles yet under $Root)"
}
Write-Host ""
Write-Host "Launch or create one:  .\Claude-Instances.ps1 -Launch <name>"
if (-not $exeOk) { Write-Warning "Claude Desktop package not found - launching will fail." }

---
description: Consolidate Claude Desktop session lists across your accounts (preview by default; 'run' to migrate, 'move' to migrate by moving)
argument-hint: "[run|move]"
allowed-tools: [Bash]
---

# Consolidate Claude Desktop Sessions

Claude Desktop stores each signed-in account's Claude Code session list separately on disk and only shows the account you are currently logged in as. This command runs the bundled PowerShell script that copies every OTHER account's session files into your current account's active workspace so they all show up in one list.

The user invoked this command with argument: `$ARGUMENTS`

## Script location

Always invoke the bundled script by its plugin-root path:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/Consolidate-ClaudeSessions.ps1"
```

Run it via the `Bash` tool using the Windows `powershell` executable, e.g.:

```
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Consolidate-ClaudeSessions.ps1" <flags>
```

## Behavior by argument

Parse `$ARGUMENTS` (trim whitespace, lowercase):

- **empty / anything not below (DEFAULT = preview only, makes NO changes):**
  1. Run the script with `-List` and show the accounts and their session counts.
  2. Then run the script with `-DryRun` and show exactly what WOULD be copied.
  3. Summarize for the user: which account is current, how many session files from other accounts would be merged in, and that nothing has changed yet.
  4. STOP and ask the user to confirm. Tell them explicitly:
     - Reply / run `/claude-desktop-session-manager:consolidate run` to perform the real migration (safe COPY, keeps a timestamped backup).
     - Or `/claude-desktop-session-manager:consolidate move` to MOVE the files instead of copying (removes them from the other accounts).
  Do NOT run the real migration in this default mode under any circumstance.

- **`run` (perform the real migration, COPY):**
  1. Run the script with NO flags:
     ```
     powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Consolidate-ClaudeSessions.ps1"
     ```
  2. The script takes a timestamped backup automatically and copies (does not move) each other account's session files. Conflict handling is **newest-wins**: a session that already exists in the current account is only refreshed when the OTHER account's copy is newer (by last-activity time); it never regresses a copy you advanced here. Safe to re-run any time to re-sync.
  3. Report what was new vs refreshed vs kept.

- **`move` (perform the real migration, MOVE):**
  1. Run the script with `-Move`:
     ```
     powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Consolidate-ClaudeSessions.ps1" -Move
     ```
  2. Report what was moved.

## After a real migration (run or move)

Tell the user they must FULLY restart Claude Desktop (quit completely, including any tray/background process, then reopen) so it re-scans the session store and the merged sessions appear.

Do NOT pass `-RestartDesktop` from inside this session: this command runs inside Claude Desktop, and that flag kills all claude.exe processes, which would terminate the very session you are running in. Ask the user to restart the app manually instead.

## Safety notes

- Default mode is strictly read-only (`-List` + `-DryRun`).
- The real migration keeps a timestamped backup unless the user explicitly asks otherwise.
- Prefer COPY (`run`) over MOVE unless the user specifically wants the files removed from the other accounts.

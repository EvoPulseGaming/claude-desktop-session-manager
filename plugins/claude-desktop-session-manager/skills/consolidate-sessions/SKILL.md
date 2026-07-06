---
name: consolidate-sessions
description: Use this skill when the user wants to consolidate, merge, or combine their Claude Desktop / Claude Code sessions across multiple accounts, or reports that sessions from another account are missing or not showing, or that switching accounts hides their sessions (e.g. "merge my Claude sessions across accounts", "my other account's sessions aren't showing up", "I switched accounts and my sessions are gone", "combine session lists from both my logins").
version: 0.1.0
---

# Consolidate Claude Desktop Sessions

## The situation

Claude Desktop stores each signed-in account's Claude Code session list separately on disk and only displays the account you are currently logged in as. So sessions created under a different account seem to "disappear" when you switch accounts. The fix is to copy every OTHER account's session files into the current account's active workspace so they all appear in one list. (The actual transcripts under `%USERPROFILE%\.claude\projects` are not account-scoped, so merged sessions stay fully resumable.)

This is Windows / Claude Desktop (MSIX) specific.

## What to do

Use the bundled PowerShell script. Always reference it by its plugin-root path and run it via the `Bash` tool with the Windows `powershell` executable:

```
powershell -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Consolidate-ClaudeSessions.ps1" <flags>
```

Follow this order:

1. **Preview first (no changes).** Run with `-List` to show accounts and session counts, then `-DryRun` to show exactly what would be merged. Summarize which account is current and how many session files from other accounts would come in.
2. **Ask the user to confirm** before making any changes. Offer:
   - Real migration by COPY (default, safest): run the script with NO flags.
   - Real migration by MOVE: run the script with `-Move` (removes files from the other accounts).
3. **Migrate** only after confirmation. The script takes a timestamped backup automatically and validates JSON. Conflict handling is **newest-wins**: a session already present in the current account is refreshed only when the other account's copy is newer (by last-activity time), never regressing one advanced here — so it is safe to re-run any time to re-sync after working under the other account.

If the user is clearly already asking to just do it, still run the preview once and confirm before the destructive step.

## After migrating

Tell the user to FULLY restart Claude Desktop (quit completely, including any tray/background process, then reopen) so it re-scans the session store and shows the merged sessions.

Do NOT use the script's `-RestartDesktop` flag from within this session — it kills all claude.exe processes and would terminate the running Claude Desktop session. Ask the user to restart the app manually.

The `/consolidate-sessions` slash command wraps this same flow (`/consolidate-sessions` for preview, `run` to copy, `move` to move).

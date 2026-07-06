# Claude Desktop Session Manager

Consolidate your Claude Desktop **Claude Code** session lists across multiple signed-in accounts, from inside Claude.

## What it does

Claude Desktop stores each account's session list separately on disk and only shows the account you're currently logged in as, so sessions created under another account appear to vanish when you switch. This plugin runs a bundled, validated PowerShell script that copies every OTHER account's session files into your current account's active workspace, so they all appear in one list. The actual transcripts live under `%USERPROFILE%\.claude\projects` and are not account-scoped, so merged sessions stay fully resumable.

Windows + Claude Desktop (MSIX) only.

## Install (Claude Desktop / Claude Code)

From GitHub:

1. Add the repo as a marketplace:
   ```
   /plugin marketplace add EvoPulseGaming/claude-desktop-session-manager
   ```
2. Install the plugin:
   ```
   /plugin install claude-desktop-session-manager@claude-desktop-session-manager
   ```
3. If prompted, restart / reload so the new commands and skill load.

Or from a local clone — point the marketplace at the repo's root folder (the one containing `.claude-plugin/marketplace.json`):
```
/plugin marketplace add C:\path\to\claude-desktop-session-manager
```

## How to invoke

**GUI (Session Manager):**
- `/session-manager` — opens a native window listing every session across all accounts with checkboxes, an account filter, a copy/move **target** picker, and **Copy / Move / Remove** buttons. You can also double-click `Claude Session Manager.cmd` on the Desktop, or run `scripts/Session-Manager.ps1` directly (`powershell -STA -ExecutionPolicy Bypass -File ...`).
  - **Copy / Move** use newest-wins. **Remove** deletes only the list entry (the shared transcript is kept). A timestamped backup is taken before the first change.

**Scripted (no GUI):**
- `/consolidate-sessions` — **preview only** (default). Lists accounts and session counts, dry-runs the merge, and shows what would change. Makes no changes; asks you to confirm.
- `/consolidate-sessions run` — perform the real migration by **copying** (keeps a timestamped backup).
- `/consolidate-sessions move` — perform the real migration by **moving** files out of the other accounts.

You can also just ask in natural language, e.g. "merge my Claude sessions across accounts" or "my other account's sessions aren't showing up" — the bundled skill triggers the same flow.

After a real migration, **fully restart Claude Desktop** (quit completely, including any tray/background process, then reopen) so it re-scans the store and shows the merged sessions.

## Safety model

- **Preview by default.** The default command mode runs only `-List` and `-DryRun` and changes nothing.
- **Copy, not move, by default.** `run` copies files (originals stay in the other accounts); `move` is opt-in.
- **Newest-wins re-sync.** Only the small session *list* entries are copied; the actual conversation transcripts live in `%USERPROFILE%\.claude\projects` and are shared across accounts, so conversations never conflict or revert. On a re-run, a session already present in the current account is refreshed only when the other account's copy is *newer* (by last-activity time) — never regressing one you advanced here. So if you continue a session under the other account, just re-run to bring the updated title/timestamp/turn-count across. Use `-NoOverwrite` for pure copy-once.
- **Timestamped backup.** The real migration backs up the current store before changing anything (the script's `-NoBackup` is not used by this plugin).
- **Confirmation gate.** Claude previews and asks you to confirm before any destructive step.
- **No self-kill.** The plugin never passes `-RestartDesktop` from inside Claude Desktop (that flag kills all `claude.exe` processes, including your running session). You restart the app manually.

## Layout

```
claude-desktop-session-manager/                     <- add THIS folder as a marketplace
  .claude-plugin/marketplace.json
  plugins/claude-desktop-session-manager/           <- the plugin (CLAUDE_PLUGIN_ROOT)
    .claude-plugin/plugin.json
    commands/consolidate-sessions.md
    commands/session-manager.md
    skills/consolidate-sessions/SKILL.md
    scripts/Consolidate-ClaudeSessions.ps1
    scripts/Session-Manager.ps1
    README.md
```

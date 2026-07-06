# Claude Desktop Session Manager

A Claude Code plugin marketplace for managing **Claude Desktop "Claude Code" sessions across multiple signed-in accounts** on Windows.

Claude Desktop stores each account's session list separately and only shows the account you're currently logged in as — so sessions created under another account seem to vanish when you switch. This plugin fixes that.

## Features

- **`/session-manager`** — native GUI: every session across all accounts in a checkbox grid, with account filter, target picker, and **Copy / Move / Remove** buttons.
- **`/consolidate-sessions`** — scripted flow: preview (default), `run` to copy everything across, `move` to move.
- **Natural-language trigger** — just say "my other account's sessions aren't showing" and the bundled skill handles it.
- **Safe by design** — newest-wins conflict handling (never regresses a session you advanced), timestamped backup before any change, copy-not-move by default, remove deletes only the list entry (conversation transcripts are shared across accounts and untouched).

## Install

```
/plugin marketplace add EvoPulseGaming/claude-desktop-session-manager
/plugin install claude-desktop-session-manager@claude-desktop-session-manager
```

See [plugins/claude-desktop-session-manager/README.md](plugins/claude-desktop-session-manager/README.md) for full usage, the safety model, and how the session store works.

## Requirements

- Windows + Claude Desktop (MSIX packaged app)
- PowerShell (built into Windows; the GUI uses WinForms, no extra dependencies)

## License

[Unlicense](LICENSE) — public domain.

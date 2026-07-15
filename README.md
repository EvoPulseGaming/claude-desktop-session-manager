# Claude Desktop Session Manager

A Claude Code plugin for Windows that puts **every Claude Desktop "Claude Code" session — from every signed-in account and every isolated instance — into one list**, where you can copy, move, or remove them. It can also **launch additional, fully isolated Claude Desktop instances**, so you can run several accounts side by side and shuttle sessions between them.

Claude Desktop normally hides all of this from you: each account's session list is stored separately and only the currently logged-in account's list is shown — so sessions created under another account seem to vanish when you switch — and the app only runs one instance (one account) at a time. This plugin fixes both.

## Features

- **`/claude-desktop-session-manager:gui`** — native GUI: every session across all accounts **and all isolated instances** in a checkbox grid, with instance/account filter, target picker, and **Copy / Move / Remove** buttons.
- **`/claude-desktop-session-manager:consolidate`** — scripted flow: preview (default), `run` to copy everything across, `move` to move.
- **`/claude-desktop-session-manager:instance`** — list or launch additional fully isolated Claude Desktop instances (each with its own account login, config, MCP servers, and session store); the GUI sees them all.
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

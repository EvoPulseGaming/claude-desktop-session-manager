---
description: List or launch additional isolated Claude Desktop instances (each with its own account login)
argument-hint: "[name]"
allowed-tools: [Bash]
---

# Claude Desktop Instances

Claude Desktop honors `--user-data-dir`, so multiple fully isolated instances can run side by side — each with its own account login, config, MCP servers, and session store. Instance profiles live under `%USERPROFILE%\ClaudeInstances\<name>`, and the Session Manager GUI (`/claude-desktop-session-manager:gui`) sees all of them and can copy/move sessions between instances.

The user invoked this command with argument: `$ARGUMENTS`

## Behavior by argument

Parse `$ARGUMENTS` (trim whitespace):

- **empty (DEFAULT = list):** run the bundled script with no arguments via the `Bash` tool:
  ```
  powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Claude-Instances.ps1"
  ```
  Show the user the table (instance, running, session count, profile path) and tell them they can launch or create one with `/claude-desktop-session-manager:instance <name>`.

- **a name (e.g. `account2`, `work`):** launch (creating on first use):
  ```
  powershell -NoProfile -ExecutionPolicy Bypass -File "${CLAUDE_PLUGIN_ROOT}/scripts/Claude-Instances.ps1" -Launch "<name>"
  ```
  Then tell the user:
  - A new Claude Desktop window is opening. If this is a brand-new instance it shows a fresh login screen — sign into whichever account this instance should hold.
  - `claude://` login deep-links route to the most recently registered instance; if a browser login bounces to the wrong window, close the other instance during that login, then relaunch it.
  - Their sessions in this instance will appear in `/claude-desktop-session-manager:gui` alongside the main install's.

Names must start with a letter or digit and contain only letters, digits, dot, dash, underscore (the script rejects anything else, including `.` / `..`). `main` is reserved (that's the normal install — launched from the Start menu as usual).

## Notes

- Each instance keeps its own caches (expect a couple of GB each).
- This is Windows + Claude Desktop (MSIX) specific; the script resolves the packaged exe dynamically so app updates don't break it.

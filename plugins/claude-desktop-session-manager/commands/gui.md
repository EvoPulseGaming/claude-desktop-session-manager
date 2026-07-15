---
description: Open the Claude Session Manager GUI - checkbox-select sessions and copy / move / remove them across accounts and instances
allowed-tools: [Bash]
---

# Open Claude Session Manager

Launch the native GUI that lists every Claude Desktop session across all signed-in accounts AND all isolated instances (profiles under `%USERPROFILE%\ClaudeInstances\`, see `/claude-desktop-session-manager:instance`) with checkboxes, an instance/account filter, a copy/move target picker, and copy / move / remove buttons.

Run it **detached** (via `Start-Process`) so the blocking GUI window does not stall this session. Use the `Bash` tool:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell.exe -ArgumentList '-STA','-NoProfile','-ExecutionPolicy','Bypass','-File','${CLAUDE_PLUGIN_ROOT}/scripts/Session-Manager.ps1'"
```

After running it, tell the user:
- The Session Manager window should now be open on their desktop.
- **Copy / Move** use newest-wins (an existing entry in the target is only refreshed when the source is newer; never regresses). **Remove** deletes only the list entry — the conversation transcript in `%USERPROFILE%\.claude\projects` is shared across accounts and is NOT deleted.
- A timestamped backup is taken automatically before the first change.
- After making changes, they must FULLY restart the affected Claude Desktop instance(s) to see them.

If they'd prefer a non-GUI, scripted flow instead, point them at `/claude-desktop-session-manager:consolidate`. To launch or list extra isolated instances, point them at `/claude-desktop-session-manager:instance`.

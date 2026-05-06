---
name: teamx-context
description: "Quick local status check — reads .teamx/state.json without any MCP calls."
---

## Input

```text
$ARGUMENTS
```

No arguments required.

---

## Purpose

Fast status snapshot from local state only. Zero MCP calls, zero network. Use when you need to know where you are before doing anything else.

---

## Process

1. Check `.teamx/state.json` exists. If missing: `✗ No .teamx/state.json found — run /teamx-dev <project_code> first.`
2. Read the file with `jq` (≤10 lines of output):

```bash
jq -r '
  "Gate:         " + (.current_gate // "IDLE"),
  "Project:      " + (.project_code // "—"),
  "Branch:       " + (.current_task.branch // "—"),
  "Work type:    " + (.current_task.work_type // "—"),
  "Last updated: " + (.last_sync // .gate_entered_at // "—")
' .teamx/state.json
```

3. Display the result as-is. No interpretation, no MCP calls, no state changes.

---

## Rules

- Read-only — does NOT modify state
- No MCP calls — not even `teamx_get_project_detail`
- If `state.json` is malformed JSON, show the raw parse error and stop

# TeamX Context — Quick Status

**Trigger**: user types `$teamx-context`, or asks "what gate am I at", "dónde estoy", "show state".

## Process

1. Check `.teamx/state.json` exists. If missing: `✗ No .teamx/state.json found — run $teamx-dev <project_code> first.`
2. Read with `jq` and display:

```bash
jq -r '
  "Gate:         " + (.current_gate // "IDLE"),
  "Project:      " + (.project_code // "—"),
  "Branch:       " + (.current_task.branch // "—"),
  "Work type:    " + (.current_task.work_type // "—"),
  "Last updated: " + (.last_sync // .gate_entered_at // "—")
' .teamx/state.json
```

## Rules

- Read-only — does NOT modify state
- No MCP calls — not even `teamx_get_project_detail`
- If `state.json` is malformed: show raw parse error and stop

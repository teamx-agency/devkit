---
name: teamx-handoff
description: "Generate or resume a context handoff for mid-task transitions."
level: 2
---

## Input

```text
$ARGUMENTS
```

- `/teamx-handoff` — Generate handoff for current task
- `/teamx-handoff resume` — Resume from existing handoff

---

## Generate Handoff (default)

1. Verify `.teamx/state.json` exists with current task
2. Run: `bash .teamx/lib/handoff.sh`
3. Read generated `.teamx/handoff.md`
4. Enrich with: decisions made (and WHY), open risks
5. Present using Handoff message type from `voice.md`

## Resume from Handoff

1. Check `.teamx/handoff.md` exists
2. Read handoff + state via `source .teamx/lib/state.sh && print_status`
3. Present context: task, gate, what was done, decisions, risks, files changed
4. On confirmation: `source .teamx/lib/state.sh && clear_handoff`, continue from current gate

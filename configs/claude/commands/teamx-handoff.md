---
description: "Generate or resume a context handoff for mid-task transitions between devs or sessions."
---

## Input

```text
$ARGUMENTS
```

Usage:
- `/teamx-handoff` — Generate handoff for current task
- `/teamx-handoff resume` — Resume from existing handoff

---

## Generate Handoff (default)

When a dev is pausing work or another dev/agent will pick up:

1. Verify `.teamx/state.json` exists and has a current task
2. Run: `bash .teamx/lib/handoff.sh`
3. Read the generated `.teamx/handoff.md`
4. **Enrich the handoff** — the script generates the structural data, but YOU must fill in:
   - **Decisions Made:** what architectural or implementation decisions were made and WHY
   - **Open Risks:** what could break, what's uncertain, what needs attention
   - Write these sections back into `.teamx/handoff.md`
5. Present the complete handoff to the dev using the Handoff message type from `voice.md`
6. Confirm: "Handoff saved. Next dev can resume with `/teamx-handoff resume`."

---

## Resume from Handoff

When picking up work from a previous session:

1. Check if `.teamx/handoff.md` exists
   - If not, inform: "No handoff found. Use `/teamx-dev <PROJECT>` to check state."
2. Read `.teamx/handoff.md` completely
3. Read `.teamx/state.json` via `source .teamx/lib/state.sh && print_status`
4. Present the handoff context:
   - Task and current gate
   - What was done, what remains
   - Decisions made and their rationale
   - Open risks
   - Files changed
5. Ask: "Ready to continue from [gate]? Any questions about the context?"
6. On confirmation:
   - Clear handoff: `source .teamx/lib/state.sh && clear_handoff`
   - Continue from the current gate in the state machine

---

## Communication

Use the **Handoff** message type (voice.md type H):
- Structured, complete, no assumptions
- Include gate, files touched, decisions with rationale, risks

---

## Integration with /teamx-dev

The `/teamx-dev` INIT flow automatically checks for handoff.md and presents it.
This command is a standalone shortcut for explicit handoff generation and resumption.

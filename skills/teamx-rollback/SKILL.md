---
name: teamx-rollback
description: "Structured rollback flow — three-option decision (revert / reset / abort) with mandatory postmortem."
---

## Input

```text
$ARGUMENTS
```

Format: `<project_code> <sha>`

Examples:
- `/teamx-rollback PRJ-005 a3f8c12`
- `/teamx-rollback PRJ-005 a3f8c12d9e1b4567`

Both arguments are **required**. If either is missing, abort:
> ✗ Usage: `/teamx-rollback <project_code> <sha>`

---

## Purpose

Structured decision flow for rolling back a problematic commit or merge. Forces an explicit choice between safe (auditable) and destructive paths, with mandatory postmortem documentation.

---

## Step 1 — Pre-check

1. Verify `.teamx/state.json` exists. If missing: abort → `✗ .teamx/ not initialized. Run /teamx-dev <project_code> first.`
2. Verify `<sha>` exists in the local git history: `git cat-file -t <sha>`. If not found: abort → `✗ SHA <sha> not found in local git history. Fetch first?`
3. Show the commit being rolled back:
   ```bash
   git log --oneline -1 <sha>
   ```
4. `teamx_post_project_update(project_code, "🚨 ROLLBACK requested for <sha>: <commit title>", "incident")`

---

## Step 2 — Decision

Present the three options clearly, then register a structured pause:

```
Rollback options for <sha>:

  [A] git revert -m 1 <sha>
      Safe. Creates a new revert commit. Auditable history. Recommended.
      Does NOT require force-push. Can proceed without re-confirmation.

  [B] git reset --hard <sha> + force push
      Destructive. Rewrites remote history. Requires explicit re-confirmation
      typed in chat before executing. Use only when revert is not viable.

  [C] Abort — do nothing.
```

```bash
bash .teamx/lib/state.sh pause_for_decision "manual-review-required" \
  "Rollback of <sha> requires explicit option selection" \
  "[A] git revert (safe, auditable) | [B] git reset --hard + force push (destructive) | [C] Abort"
```

Wait for the user's choice. Do NOT proceed until an option is explicitly selected.

---

## Step 3 — Execute chosen option

### Option A — Safe revert

```bash
git revert -m 1 <sha>
```

- No re-confirmation needed — Option A is always safe to proceed.
- Persist to state:
  ```bash
  jq '.last_rollback = {sha: "<sha>", action: "revert", executed_at: (now | todate)}' \
    .teamx/state.json > .teamx/state.json.tmp && mv .teamx/state.json.tmp .teamx/state.json
  ```
- Proceed to Step 4 (postmortem).

### Option B — Destructive reset

1. **Require explicit re-confirmation typed in chat.** Show:
   > ⚠ This is destructive and will rewrite remote history. Type exactly:
   > `CONFIRM RESET <sha>`
   > to proceed, or anything else to abort.
2. Wait for the user's next message. If it does not match `CONFIRM RESET <sha>` exactly: abort → `✗ Confirmation not matched — rollback aborted.`
3. Execute only after exact confirmation:
   ```bash
   git reset --hard <sha>
   git push --force-with-lease origin <current_branch>
   ```
4. Persist to state:
   ```bash
   jq '.last_rollback = {sha: "<sha>", action: "reset_hard", executed_at: (now | todate)}' \
     .teamx/state.json > .teamx/state.json.tmp && mv .teamx/state.json.tmp .teamx/state.json
   ```
5. Proceed to Step 4 (postmortem).

### Option C — Abort

```
✗ Rollback aborted — no changes made.
```

Stop. Do NOT call postmortem. Do NOT modify state.

---

## Step 4 — Mandatory postmortem (Options A and B only)

Call `teamx_post_project_update` with `update_type: "gate_transition"` documenting the rollback:

```
teamx_post_project_update(
  project_code,
  "ROLLBACK completed — action=<revert|reset_hard>, sha=<sha>\n\nWhat broke: <describe>\nWhy rolled back: <describe>\nAction taken: <Option A/B>\nNext steps: <describe>",
  "gate_transition"
)
```

The postmortem fields **must be filled in** — do not send placeholder text. If context is unknown, ask the user to provide "what broke" and "why rolled back" before calling.

---

## Rules

- Option A can proceed without re-confirmation — it is safe and auditable
- Option B requires the exact confirmation string typed in chat — no exceptions
- Option C skips postmortem entirely
- `last_rollback` is persisted in `state.json` for audit purposes regardless of which option was chosen (only A or B reach this point)
- Read CURRENT branch from `git branch --show-current` before any push

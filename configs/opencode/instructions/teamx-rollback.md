# TeamX Rollback — Structured Rollback

**Trigger**: user types `$teamx-rollback <project_code> <sha>`.

Both arguments required. If missing: `✗ Usage: $teamx-rollback <project_code> <sha>`

## Step 1 — Pre-check

1. Verify `.teamx/state.json` exists. If missing: abort.
2. Verify SHA: `git cat-file -t <sha>`. If not found: `✗ SHA not found — fetch first?`
3. Show commit: `git log --oneline -1 <sha>`
4. `teamx_post_project_update(project_code, "🚨 ROLLBACK requested for <sha>: <title>", "incident")`

## Step 2 — Decision (structured pause — wait for user choice)

```
Rollback options for <sha>:

  [A] git revert -m 1 <sha>
      Safe. Auditable history. No re-confirmation needed.

  [B] git reset --hard <sha> + force push
      Destructive. Requires typing CONFIRM RESET <sha> in chat exactly.

  [C] Abort — no changes.
```

## Step 3 — Execute

**A**: `git revert -m 1 <sha>` → no confirmation needed → Step 4.

**B**: Show `⚠ Type exactly: CONFIRM RESET <sha>` → wait for user message → if not exact match: `✗ Confirmation not matched — aborted.` → if exact: `git reset --hard <sha> && git push --force-with-lease origin <current_branch>` → Step 4.

**C**: `✗ Rollback aborted — no changes made.` Stop.

After A or B: persist to state:
```bash
jq '.last_rollback = {sha: "<sha>", action: "<revert|reset_hard>", executed_at: (now | todate)}' \
  .teamx/state.json > .teamx/state.json.tmp && mv .teamx/state.json.tmp .teamx/state.json
```

## Step 4 — Mandatory postmortem (A and B only)

```
teamx_post_project_update(
  project_code,
  "ROLLBACK completed — action=<revert|reset_hard>, sha=<sha>\n\nWhat broke: <fill>\nWhy: <fill>\nAction: <A|B>\nNext steps: <fill>",
  "gate_transition"
)
```

Ask user for "what broke" and "why" if unknown — do not send placeholder text.

## Rules

- Option A: always safe, never requires re-confirmation
- Option B: exact string match required, no exceptions
- Option C: no postmortem, no state change
- Use `git branch --show-current` to get current branch before any push

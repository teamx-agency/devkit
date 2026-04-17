---
name: teamx-analyze
description: "Read-only cross-artifact analysis for a TeamX project — flags ambiguity, duplication, and coverage gaps before IMPLEMENT starts."
---

## Input

```text
$ARGUMENTS
```

Accepts:
- First argument: project code (e.g., `PRJ-005`). If empty, read from `.teamx/state.json`. If still empty, call `teamx_list_projects` and ask.
- Flag `--strict` (anywhere in $ARGUMENTS): on CRITICAL findings, register `pause_for_decision` so the DevKit workflow stops. Default is advisory-only.

---

## When to run

- After `teamx_approve_sdd`, before SELECT/CLASSIFY on the first task.
- Whenever the SDD is edited (post-approval amendments).
- Ad-hoc, when the human smells drift.

This skill never mutates state — it is safe to run as often as you want.

---

## Process

1. Resolve `project_code`:
   - from first argument, or
   - from `.teamx/state.json` (`source .teamx/lib/state.sh && read_project_code`), or
   - ask via `teamx_list_projects` + AskUserQuestion.

2. Call `mcp__teamx__teamx_analyze_project(project_code=<code>)`.

3. Render the report:
   - Header with metrics: `total_tasks / tasks_with_criteria / coverage_pct / total_user_stories / critical_findings / high_findings`
   - Table of findings ordered by severity DESC, then category: `id | category | severity | location | summary | recommendation`
   - Truncate `summary` / `recommendation` to fit a reasonable column width; full text stays in the raw response.

4. If `--strict` is present AND `metrics.critical_findings > 0` AND a `current_task` is active in `.teamx/state.json`:
   - Register:
     ```bash
     source .teamx/lib/state.sh && pause_for_decision "blocking-architectural-choice" "<N> CRITICAL findings en análisis del proyecto" "[A] fix findings | [B] override and continue | [C] abort task"
     ```
   - Stop here; the workflow will not advance until `resolve_pause` is called.

5. If no findings: say `✓ No drift detected. Metrics: coverage_pct=X%, stories=N, tasks=M.` — one line, nothing more.

---

## Categories you will see

- **ambiguity** — criteria with vague adjectives ("fast", "secure", "robusto") and no nearby metric. Fix: attach a number.
- **duplication** — the same criterion text appears on multiple tasks. Fix: refine each to be task-specific.
- **coverage** — user stories without tasks, P1 stories without `independent_test`, tasks without `user_story_id`.

Each finding carries a `recommendation` that is already actionable — prefer quoting it over paraphrasing.

---

## Rules

1. Read-only. Never propose edits — you **surface** problems, the human decides.
2. In advisory mode (default), do not register pauses even for CRITICAL. The user may run `--strict` when they want enforcement.
3. Keep output compact. If there are >20 findings, group by category and show totals + top 3 per category; link to the raw JSON for the rest.
4. Respond in the user's language. Quote `summary`/`recommendation` verbatim when they are already in Spanish.

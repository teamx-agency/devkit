---
description: "Audit operational health of a TeamX project — tasks, pipelines, branches, milestones."
---

## Input

```text
$ARGUMENTS
```

First argument: project code (e.g., `PRJ-001`).
If empty, read from `.teamx/state.json` or call `teamx_list_projects` and ask.

---

## Process

### 1. Gather data (parallel MCP calls)

- `teamx_list_project_tasks(project_code)` — all tasks, all statuses
- `teamx_get_workflow_state(project_code)` — workflow state, blockers
- `gitlab_list_pipelines(project_code)` — recent pipelines (last 10)

### 2. Run local checks

If `.teamx/` exists in the current repo:
- `bash .teamx/lib/health.sh` — state staleness, journal gaps, CI profile

### 3. Analyze and report

#### Task Health
- Tasks without acceptance criteria → **WARN** (not implementable)
- Tasks `in_progress` > 3 days → **WARN** (might be stuck)
- Tasks `blocked` > 1 day → **CRITICAL** (delivery risk)
- Tasks with no assignee in `in_progress` → **WARN** (orphaned work)

#### Pipeline Health
- Last 5 pipelines: calculate pass rate
- Currently failing pipeline → **CRITICAL**
- Pass rate < 80% → **WARN** (CI instability)

#### Milestone Health
- Current milestone progress vs time elapsed
- If progress significantly behind schedule → **WARN**
- Overdue milestones → **CRITICAL**

#### Branch Health (if repo is local)
- Branches with no commits > 7 days → **INFO** (stale)
- Branches without associated MR → **WARN** (abandoned work?)

### 4. Overall Score

- **GREEN** — no critical issues, minor warnings acceptable
- **YELLOW** — warnings present, delivery at risk if not addressed
- **RED** — critical issues, delivery blocked or severely degraded

### 5. Output Format

```
# Project Health: [PROJECT-CODE]
Score: [GREEN/YELLOW/RED]

## CRITICAL (N)
- [issue description + recommended action]

## WARN (N)
- [issue description + recommended action]

## INFO (N)
- [issue description]

## Summary
[1-2 sentence assessment of project health]
[Recommended next action if score is not GREEN]
```

---

## Severity Levels

- **CRITICAL** — blocks delivery. Must address immediately.
- **WARN** — risk to delivery. Should address this sprint.
- **INFO** — hygiene. Address when convenient.

---

## Communication

This command should feel like a **health dashboard**, not a blame report.
State facts, recommend actions, don't dramatize.
If the project is healthy, say so briefly — don't manufacture concerns.

---

## Relationship to State Machine

This command operates **independently** from `/teamx-dev`.
It does NOT modify `.teamx/state.json`. It is a read-only diagnostic.

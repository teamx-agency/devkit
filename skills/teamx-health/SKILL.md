---
name: teamx-health
description: "Audit operational health of a TeamX project — tasks, pipelines, branches, milestones."
level: 2
---

## Input

```text
$ARGUMENTS
```

First argument: project code. If empty, read from `.teamx/state.json` or ask.

---

## Process

1. **Gather data** (parallel MCP calls):
   - `teamx_list_project_tasks(project_code)` — all tasks
   - `teamx_get_workflow_state(project_code)` — workflow state
   - `gitlab_list_pipelines(project_code)` — recent pipelines

2. **Local checks** (if `.teamx/` exists): `bash .teamx/lib/health.sh`

3. **Analyze:**
   - Tasks without criteria → WARN
   - Tasks in_progress > 3 days → WARN
   - Tasks blocked > 1 day → CRITICAL
   - Pipeline pass rate < 80% → WARN
   - Currently failing pipeline → CRITICAL
   - Milestone behind schedule → WARN

4. **Score:** GREEN / YELLOW / RED

5. **Output:** Score, then CRITICAL items, WARN items, INFO items, summary

## Communication

Health dashboard, not blame report. State facts, recommend actions.
Read-only — does NOT modify state.

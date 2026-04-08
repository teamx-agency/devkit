---
name: teamx-status
description: "Project status dashboard — quick overview of all projects or detailed view of one."
---

## Input

```text
$ARGUMENTS
```

Usage: `/teamx-status` (global) or `/teamx-status PRJ-001` (project detail)

---

## Without PROJECT-ID — Global View

1. Call `teamx_list_projects` for all active projects
2. For each (max 5), call `teamx_list_project_tasks(project_code, status: "in_progress")`
3. Present dashboard with status indicators

## With PROJECT-ID — Detailed View

1. Call `teamx_get_project_detail` and `teamx_get_workflow_state` in parallel
2. Call `gitlab_list_pipelines` for CI/CD state
3. Present detailed summary with milestones, tasks, pipelines

## Notes

- Use indicators: GREEN (on track), YELLOW (at risk), RED (blocked)
- If no active projects, indicate all completed or paused
- Read-only — does NOT modify state

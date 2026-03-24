---
description: State-machine autonomous dev cycle with persistent state, quality gates, and context-optimized execution.
---

## Input

```text
$ARGUMENTS
```

First argument MUST be a project code (e.g., `PRJ-001`). If empty, call `teamx_list_projects` and ask.

---

## State Machine

This command uses `.teamx/state.json` in the **delivery repo** as source of truth.

**Bootstrap:** If `.teamx/` doesn't exist in the current repo, run INIT to create it.

**Resume:** Run `source .teamx/lib/state.sh && print_status` to see where you are.

**Gates (execute in order, advance one at a time):**

```
IDLE → INIT → SELECT → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → MERGE → EVIDENCE → DONE → SELECT
```

---

## INIT (first run only)

1. Parse project code from `$ARGUMENTS`
2. Call `teamx_get_project_detail(project_code)` and `teamx_get_workflow_state(project_code)`
3. Call `gitlab_get_repo_context(project_code)` — get repo URL, confirm local clone path
4. If `.teamx/` doesn't exist in the repo:
   - Create `.teamx/lib/`, `.teamx/journal/`
   - Download state scripts: `curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/state.sh -o .teamx/lib/state.sh`
   - Download verify script: `curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/verify.sh -o .teamx/lib/verify.sh`
   - Download init script: `curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/init.sh -o .teamx/lib/init.sh`
   - `chmod +x .teamx/lib/*.sh`
   - Add `.teamx/` to `.gitignore` if not already there
5. Run: `bash .teamx/lib/init.sh <repo_path>` — parses `.gitlab-ci.yml` into `ci-profile.json`
6. Call `teamx_list_sdd_sessions` → if completed, `teamx_read_sdd_session` → extract 200-word tech summary
7. Write `.teamx/state.json` with project info, milestone, SDD summary, gate=SELECT
8. Advance to SELECT

## SELECT

1. Call `teamx_get_workflow_state(project_code)` — get available tasks
2. Pick highest priority available task
3. Call `teamx_transition_task(uuid, "in_progress")`
4. Create branch: `git checkout main && git pull && git checkout -b feat/<slug>`
5. Update state: `source .teamx/lib/state.sh && set_current_task "<uuid>" "<title>" "<issue_iid>" "feat/<slug>"`
6. Advance to IMPLEMENT

## IMPLEMENT

1. Read task from state.json (title, acceptance criteria)
2. Read SDD summary from state.json for tech context
3. **Do the work** — write code, create files, modify templates
4. When done: `source .teamx/lib/state.sh && set_gate "VERIFY"`

## VERIFY (HARD GATE — fully deterministic)

**Run:** `bash .teamx/lib/verify.sh <repo_path>`

This script runs each CI check from `ci-profile.json`, captures pass/fail, writes to state.json.
- ALL pass → gate advances to COMMIT automatically
- ANY fail → fix the code, then re-run the script

**You MUST NOT skip this gate or advance manually.**

## COMMIT

1. `git add <specific-files>` (never `-A`)
2. Commit: `feat: <title>\n\nTask: <uuid>\nCloses #<iid>\n\nCo-Authored-By: TeamX Dev <hola@teamx.agency>`
3. `source .teamx/lib/state.sh && set_git_committed "$(git rev-parse HEAD)" && set_gate "PUSH"`

## PUSH

1. `git push -u origin <branch>`
2. `source .teamx/lib/state.sh && set_git_pushed && set_gate "MR"`

## MR

1. Call `gitlab_create_merge_request(project_code, branch, title)`
2. `source .teamx/lib/state.sh && set_mr_created "<mr_iid>" && set_gate "PIPELINE"`
3. Call `gitlab_merge(project_code, mr_iid, merge_when_pipeline_succeeds=true)`

## PIPELINE

1. Call `gitlab_list_pipelines(project_code, ref=branch)`
2. Running → wait or tell user to re-invoke later
3. Success → `source .teamx/lib/state.sh && set_pipeline_status "<id>" "success" && set_gate "MERGE"`
4. Failed → read job log, set gate back to VERIFY

## MERGE

1. Check if MR is merged via `gitlab_get_merge_request`
2. If merged → `source .teamx/lib/state.sh && set_merged && set_gate "EVIDENCE"`
3. If not → `gitlab_merge(project_code, mr_iid)`, handle conflicts

## EVIDENCE

1. Map acceptance criteria to implementation evidence
2. Call `teamx_transition_task(uuid, "done", criteria_evidence={...})`
3. Close GitLab issue via API
4. `source .teamx/lib/state.sh && write_journal && complete_current_task`
5. Gate is now SELECT — loop to next task

---

## Rules

1. **State file is source of truth** — read it, don't rely on conversation memory
2. **VERIFY is a HARD gate** — the bash script enforces it, not you
3. **Never transition to done without merged MR**
4. **One gate per invocation is fine** — quality over speed
5. **If context resets:** `source .teamx/lib/state.sh && print_status`

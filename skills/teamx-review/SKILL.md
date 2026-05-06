---
name: teamx-review
description: "Structured code review for a GitLab MR with criteria mapping and risk assessment."
---

## Input

```text
$ARGUMENTS
```

First argument: MR IID (optional if `state.json` has one). Optional second: project code.

---

## Process

1. Determine MR IID:
   - If `.teamx/state.json` exists, read `mr_iid` from it:
     ```bash
     jq -r '.current_task.git.mr_iid // empty' .teamx/state.json
     ```
   - If found in state: use it as the default. Show: `↳ Auto-detected MR !<mr_iid> from .teamx/state.json`
   - If `$ARGUMENTS` provides an explicit MR IID: that overrides the state value.
   - If neither state nor argument provides an MR IID: ask for it.
2. Determine project context (argument, state.json, or ask)
3. Call `gitlab_get_merge_request(project_code, mr_iid)` for diff and status
4. Find associated task via `teamx_list_project_tasks` — match by branch/title
5. Structured review:
   - **Criteria Coverage**: for each acceptance criterion, assess covered/partial/missing
   - **Code Quality**: architecture alignment, error handling, tests, naming, complexity
   - **Risk Assessment**: breaking changes, performance, security, backward compat
   - **Verdict**: APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION
6. Output: verdict first, then criteria table, specific findings with file:line, risk summary

## Communication

- Review mode: thorough but not verbose, findings linked to risk
- Every finding must answer "so what?"
- Don't flag style issues unless they affect readability
- If MR is clean, say so briefly
- Read-only — does NOT modify state

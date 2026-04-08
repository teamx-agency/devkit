---
name: teamx-review
description: "Structured code review for a GitLab MR with criteria mapping and risk assessment."
---

## Input

```text
$ARGUMENTS
```

First argument: MR IID. Optional second: project code. If not provided, read from `.teamx/state.json`.

---

## Process

1. Determine project context (argument, state.json, or ask)
2. Call `gitlab_get_merge_request(project_code, mr_iid)` for diff and status
3. Find associated task via `teamx_list_project_tasks` — match by branch/title
4. Structured review:
   - **Criteria Coverage**: for each acceptance criterion, assess covered/partial/missing
   - **Code Quality**: architecture alignment, error handling, tests, naming, complexity
   - **Risk Assessment**: breaking changes, performance, security, backward compat
   - **Verdict**: APPROVE / REQUEST_CHANGES / NEEDS_DISCUSSION
5. Output: verdict first, then criteria table, specific findings with file:line, risk summary

## Communication

- Review mode: thorough but not verbose, findings linked to risk
- Every finding must answer "so what?"
- Don't flag style issues unless they affect readability
- If MR is clean, say so briefly
- Read-only — does NOT modify state

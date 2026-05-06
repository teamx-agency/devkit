---
name: teamx-hotfix
description: "Standalone hotfix skill — compressed delivery flow for production incidents with mandatory postmortem."
---

## Input

```text
$ARGUMENTS
```

Format: `<project_code> "<incident description>"`

Examples:
- `/teamx-hotfix PRJ-005 "login returns 500 for all users"`
- `/teamx-hotfix PRJ-012 "payment webhook silently dropping events"`

Both arguments are **required**. If either is missing, abort:
> ✗ Usage: `/teamx-hotfix <PROJECT_CODE> "<incident description>"`

---

## Purpose

Dedicated hotfix skill for production incidents. Skips INIT and SELECT entirely.
Assumes `.teamx/` is already initialized in the repo (run `/teamx-dev <code>` first if not).

**Flow: CLASSIFY → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → MERGE → EVIDENCE → RETROSPECTIVE (postmortem obligatorio)**

---

## Step 1 — Pre-check

1. Verify `.teamx/state.json` exists in the current repo directory.
   - If missing: abort → `✗ .teamx/ not initialized. Run /teamx-dev <project_code> first to complete INIT.`
2. Read base branch: `bash .teamx/lib/state.sh read_base_branch` (defaults to `origin/main` if not set).
3. Check for active hotfix branches: `git branch --list "hotfix/*"` — warn if one already exists.
4. Check current state: `bash .teamx/lib/state.sh print_status` — show current gate before overriding.

---

## Step 2 — Set up incident context

1. Record incident description (from `$ARGUMENTS`) as the working title.
2. Ask ONE focused question: **"Is production currently down / actively impacted, or is this a degradation?"**
   — This sets urgency. `down` → skip all optional steps. `degraded` → normal compressed flow.
3. Call `teamx_get_project_detail(project_code)` to confirm project exists and get stack context.

---

## Step 3 — Surface shared lessons

Call `teamx_get_shared_lessons(project_code, topics: ["hotfix"], limit: 5)`.

If lessons are returned, display them as a compact list before starting work:

```
⚡ HOTFIX LESSONS — patterns from past incidents on this project:
  1. [signal] — [suggested_action] (seen N times)
  2. ...
```

If no lessons exist yet: proceed silently (no empty state message needed).

---

## Step 4 — Branch creation

1. `git fetch origin`
2. Build slug: incident description → lowercase, spaces → hyphens, max 40 chars, alphanumeric + hyphens only.
   Example: `"login returns 500 for all users"` → `login-returns-500-for-all-users`
3. `git checkout -b hotfix/<slug> <base_branch>`
4. `bash .teamx/lib/state.sh register_feature_branch hotfix/<slug>`
5. `bash .teamx/lib/state.sh set_work_type hotfix`
6. `bash .teamx/lib/state.sh set_gate CLASSIFY`

Announce:
```
⚡ HOTFIX — branch hotfix/<slug> ready.
   Incident: <description>
   Base: <base_branch>
   Gate: CLASSIFY — production is impacted, move fast.
```

---

## CLASSIFY

Classify the incident type. Skip the work_type question — it is already `hotfix`.

Questions to answer (all in ONE exchange if possible):
1. **Root cause hypothesis** — what do you think broke? (gather from user or analyze codebase)
2. **Scope** — which files/services are affected?
3. **Blast radius** — how many users / what % of traffic?

Set classification: `bash .teamx/lib/state.sh set_gate IMPLEMENT`

> Skip PLAN gate entirely (compressed flow).

---

## IMPLEMENT

Apply the fix. Follow standard IMPLEMENT rules from the delivery OS:
- Make minimal, targeted changes (surgical diff — no refactors)
- Run existing tests that cover the affected path
- Verify the fix locally before proceeding

`bash .teamx/lib/state.sh set_gate VERIFY`

---

## VERIFY

Run verify script: `bash .teamx/lib/verify.sh`

For hotfixes, the verify threshold is **tighter**:
- Failing tests → block, do not proceed
- Static analysis errors in changed files → block
- Security scanner findings in changed files → block

`bash .teamx/lib/state.sh set_gate COMMIT`

---

## COMMIT → PUSH → MR

Follow standard COMMIT / PUSH / MR gates. For hotfixes:
- Commit message MUST include `fix(<scope>): <description>` format
- MR title MUST start with `[HOTFIX]`
- MR description MUST include: **Incident**, **Root Cause**, **Fix**, **Verified by**
- Request at least one reviewer if `autonomy.review.required_reviewers > 0` in config

`bash .teamx/lib/state.sh set_gate PUSH` → `MR` → `PIPELINE` → `REVIEW` → `MERGE`

---

## EVIDENCE

After merge, document evidence:
1. Timestamp of merge to production
2. Link to the MR
3. Confirmation that the incident symptom is resolved (manual verification note)

`bash .teamx/lib/state.sh set_gate RETROSPECTIVE`

---

## RETROSPECTIVE — Postmortem obligatorio

**This gate is NOT optional for hotfixes.** Do not close the cycle without completing it.

Call `teamx_post_project_update` with update_type `gate_transition` announcing postmortem start.

Produce a postmortem with these sections:

```markdown
## Postmortem — <incident description>
**Date:** <merge date>
**Severity:** <down | degraded>
**Duration:** <from first report to fix merged>

### Timeline
- <time> — incident detected
- <time> — diagnosis started
- <time> — fix deployed

### Root Cause
<1-3 sentences. Mechanical cause, not blame.>

### Contributing Factors
- <factor 1>
- <factor 2>

### What we did right
- <at least 1 item>

### What broke down
- <at least 1 item>

### Action items
| Action | Owner | Deadline |
|--------|-------|----------|
| <preventive measure> | <role> | <date> |

### Signal for shared lessons
<signal>: <pattern observed>
Suggested action: <what to do next time>
Severity: high | critical
```

After the postmortem is drafted, call `teamx_push_lessons` to publish the signal so the next hotfix on this project sees it.

`bash .teamx/lib/state.sh set_gate SELECT`

---

## Identity

You are **AgenteX** operating in `serious_mode` for this hotfix. No sarcasm, no catchphrases. Direct, focused, fast. Production is impacted — every word counts.

The mission: fix it, ship it, learn from it. In that order.

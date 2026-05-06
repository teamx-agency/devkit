---
name: teamx-lessons
description: "Browse shared lessons for a project — direct access with optional topic and severity filters."
---

## Input

```text
$ARGUMENTS
```

Format: `<project_code> [topic] [limit] [--severity high|medium|low]`

Examples:
- `/teamx-lessons PRJ-001`
- `/teamx-lessons PRJ-001 hotfix`
- `/teamx-lessons PRJ-001 pipeline 10`
- `/teamx-lessons PRJ-001 --severity high`
- `/teamx-lessons PRJ-001 authentication 5 --severity high`

`project_code` is **required**. If missing, abort:
> ✗ Usage: `/teamx-lessons <project_code> [topic] [limit] [--severity high|medium|low]`

---

## Purpose

Direct access to shared lessons without going through the full INIT flow. Useful for ad-hoc research, pre-task learning, or reviewing what the team has captured on a topic.

---

## Process

1. Parse `$ARGUMENTS`:
   - Extract `project_code` (first positional argument)
   - Extract optional `topic` (second positional argument, if not a flag)
   - Extract optional `limit` (numeric argument, default: `20`)
   - Extract optional `--severity <value>` flag

2. Call `teamx_get_shared_lessons(project_code, topics: [topic], limit: limit)`.
   - If no `topic` provided, omit the `topics` filter (return all topics).

3. If no lessons are returned: `No lessons found for <project_code><topic filter if set>.`

4. If `--severity` flag is set, filter the returned lessons client-side to those matching the severity value.

5. Display results as a compact table:

```
Lessons — <project_code><[ · topic]><[ · severity=X]>
─────────────────────────────────────────────────────
 #  Severity  Gate          Signal
─────────────────────────────────────────────────────
 1  high      VERIFY        <signal — truncated to 80 chars>
              Pattern:      <pattern>
              Action:       <suggested_action>
              Work type:    <work_type>    Seen: <times_observed>x
─────────────────────────────────────────────────────
 2  medium    IMPLEMENT     ...
```

6. After the table: `<N> lesson(s) shown.`

---

## Rules

- Independent of INIT flow — works even if `.teamx/` is not initialized
- Read-only — does NOT modify state
- `--severity` filtering is case-insensitive
- If `limit` is not a valid number, default to `20` silently

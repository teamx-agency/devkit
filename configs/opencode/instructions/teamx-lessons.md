# TeamX Lessons — Browse Shared Lessons

**Trigger**: user types `$teamx-lessons <project_code> [topic] [limit] [--severity high|medium|low]`.

## Process

1. Parse arguments: `project_code` (required), optional `topic`, optional `limit` (default 20), optional `--severity` flag.
2. If `project_code` missing: `✗ Usage: $teamx-lessons <project_code> [topic] [limit] [--severity high|medium|low]`
3. Call `teamx_get_shared_lessons(project_code, topics: [topic], limit: limit)`. Omit `topics` filter if no topic given.
4. If no lessons: `No lessons found for <project_code><topic filter if set>.`
5. If `--severity` set: filter client-side to matching severity.
6. Display as compact table:

```
Lessons — <project_code><[ · topic]><[ · severity=X]>
─────────────────────────────────────────────────────
 #  Severity  Gate          Signal
─────────────────────────────────────────────────────
 1  high      VERIFY        <signal — max 80 chars>
              Pattern:      <pattern>
              Action:       <suggested_action>
              Work type:    <work_type>    Seen: <times_observed>x
```

7. Footer: `<N> lesson(s) shown.`

## Rules

- Works independently of INIT — `.teamx/` not required
- Read-only
- `--severity` filtering is case-insensitive
- Invalid `limit` → default to 20 silently

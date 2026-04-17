---
name: teamx-constitution
description: "Read-only view of the active TeamX Constitution. Lists articles, version, and source file. Flags project-specific overrides."
---

## Input

```text
$ARGUMENTS
```

Optional flag:
- `--articles`: print only the article headings (one per line).
- `--raw`: print the full markdown as-is.

Default: print a compact rendering with version, source file, and one-line
summaries per article.

---

## Resolution order

1. **Project override** (highest priority): `.teamx/constitution.md` in the
   current working directory. Used when a project needs additional rules on
   top of the agency baseline.
2. **Agency baseline**: `$CLAUDE_PLUGIN_ROOT/teamx-lib/constitution.md`
   (shipped with the devkit) or the local install path
   `~/.claude/teamx-devkit/teamx-lib/constitution.md`.

If both files exist, both are displayed with their scope (`project` vs `agency`).

---

## Process

1. Read the frontmatter (`version`, `ratified`, `scope`) from the resolved
   file(s).

2. For each file found, iterate `## Article ...` headings and extract:
   - The number and title (e.g., `Article I — Type Safety`).
   - The first sentence of the body as summary.
   - Any `MUST` / `MUST NOT` / `SHOULD` counts under that article.

3. Render based on flags:
   - Default: table with `version | article | summary | MUSTs | SHOULDs`.
   - `--articles`: bullet list of article titles.
   - `--raw`: unmodified markdown.

4. If overriding: show both frontmatters side by side so the reader can see
   project adds on top of agency.

---

## Rules

1. **Read-only.** This skill never edits the constitution. Amendments follow
   the procedure documented in the constitution itself.
2. Fail silently (empty output) if no constitution file is found — do not
   invent rules.
3. Keep output compact. For full rationale, the human reads the markdown.
4. Respond in the user's language, but quote article titles verbatim.

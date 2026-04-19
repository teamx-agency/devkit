---
version: 1.1.0
ratified: 2026-04-18
scope: agency
source: devkit/teamx-lib/constitution.md
---

# TeamX Agency Constitution

These principles are load-bearing. Every SDD, every task, every commit must be
compatible with them. Violations are flagged by `/teamx-analyze` and surface as
`qa_warnings` on SessionStart. When a decision conflicts with an article, the
decision changes — not the article.

A project-specific override file may live at `.teamx/constitution.md`. When
present, it **extends** (never weakens) the agency rules. Extensions add new
articles; they cannot downgrade MUST → SHOULD.

---

## Article I — Type Safety

**MUST**: Every PHP source file in `plugins/**/*.php` and `src/**/*.php` starts with
`declare(strict_types=1);` on the line immediately after the opening `<?php` tag.

**Why**: Silent coercion has caused 3 production incidents in the past. Strict
typing catches them at parse time, not in prod.

---

## Article II — Quality Gates

**MUST**: PHPStan level 6 clean on the edited paths before COMMIT.
**MUST**: `composer audit` passes before MERGE.
**SHOULD**: PHPUnit green on the affected test suite.

A VERIFY gate that skips these checks without `ci-profile.json` overrides is a
broken gate, not a valid fast-path.

---

## Article III — Criteria Format

**MUST**: Every acceptance criterion uses Given/When/Then form or another
declarative grammar with a concrete pass/fail condition.

**MUST NOT**: Criteria use vague adjectives (`fast`, `secure`, `robust`, `clean`)
without an attached metric.

**Why**: Criteria without a falsifiable condition cannot be used as evidence —
they turn the EVIDENCE gate into theater.

---

## Article IV — User Story Independence

**MUST**: Every SDD carries at least one `P1` User Story with a non-empty
`independent_test` field.

**SHOULD**: Each story's tasks can be implemented, deployed, and verified
without waiting on another story.

**Why**: Independence is what makes MVP thinking real. Coupled stories lead to
all-or-nothing releases.

---

## Article V — Evidence Is Non-Negotiable

**MUST**: `teamx_log_time_entry` is called in EVIDENCE before
`teamx_transition_task(uuid, "done")`.
**MUST**: Every acceptance criterion is satisfied via
`teamx_satisfy_acceptance_criterion` with evidence (commit SHA, test name, or
verifiable artifact) before a task closes.

---

## Article VI — Commit Discipline

**MUST**: `git add <specific-files>`. Never `-A`.
**MUST NOT**: `--no-verify`, `--amend` on pushed commits, or force-push to `main`.
**MUST**: Commit messages follow the prefix + issue link format defined in the
DevKit commit template.

---

## Article VII — Candor

**MUST**: When a criterion is ambiguous, a plan deviates from the SDD, or a
hotfix is growing in scope, the agent **stops** and raises a
`pause_for_decision` with a reserved category. It does not paper over
uncertainty with fluent language.

---

## Article VIII — Internal vs Client Projects

**MUST**: A project without a client must carry `is_internal=true`.
**MUST**: An external project (`is_internal=false`) must have a client assigned
before an SDD session starts.

---

## Article IX — Secrets Hygiene

**MUST NOT**: Stage, commit, or push any of the following paths under any
circumstance, in any repository, on any branch:

- `.mcp.json` and `**/.mcp.json` — MCP server configs frequently contain bearer
  tokens, API keys, or remote URLs with embedded credentials.
- `.teamx/` and `**/.teamx/` — agent state, handoff notes, lessons, and
  workflow snapshots may include task descriptions, customer data, or
  credentials pasted by the user.
- `.claude/` and `**/.claude/` — Claude Code local settings, hooks, allow-lists,
  and permission overrides. Often holds machine-specific paths and tokens.
- `.opencode/` and `**/.opencode/` — OpenCode local config and plugin state.
- `.env`, `.env.*`, `**/.env`, `**/.env.*` — environment files.
- `secrets/`, `tokens/`, `credentials*.json`, `service-account*.json`.
- Private key material: `*.pem`, `*.key`, `id_rsa`, `id_ed25519`, `*.p12`, `*.pfx`.

**MUST**: On `INIT`, the agent ensures the project `.gitignore` covers every
path above. If `.gitignore` is missing or incomplete, the agent appends the
missing entries before any other gate work.

**MUST**: At `COMMIT`, before invoking `git commit`, the agent runs
`bash .teamx/lib/state.sh check_no_secrets_staged`. If the helper exits
non-zero, the commit is aborted and the offending paths are unstaged via
`git restore --staged <path>`. The agent then registers
`pause_for_decision "security-risk-detected"` if the file appeared via
`git add` of a directory or wildcard — this signals a process bug, not a
typo.

**MUST NOT**: Bypass this check with `--no-verify`, by editing
`check_no_secrets_staged` to return `0`, or by force-pushing a branch that
already contains a forbidden path. If a forbidden path was already pushed,
treat it as a credential-leak incident:

1. Rotate the leaked credential **first** — assume it is compromised.
2. Then rewrite history (`git filter-repo` or BFG) and force-push **only
   after the credential is rotated**.
3. Open a postmortem under `.teamx/journal/` documenting blast radius and
   prevention.

**Why**: A single committed `.mcp.json` with a live token gives any reader of
the repo (including forks, mirrors, and CI logs) full access to the MCP
backend. Removing the file from the working tree does not remove it from git
history. The cost of one accidental commit dwarfs the cost of always
gitignoring these paths from day one.

---

## Amendment Procedure

Articles are versioned via the frontmatter. Raising a MUST to a MUST NOT, or
adding a new article, requires:

1. A proposal in the `delivery-*` channel referencing the article number.
2. Consensus from the delivery PM + at least one senior engineer.
3. Version bump (semver MAJOR for breaking rule changes, MINOR for added
   articles, PATCH for clarifications).
4. Update of `ratified` date.

Downstream projects import the new version on their next `INIT`.

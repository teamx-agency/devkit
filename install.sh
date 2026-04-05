#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════╗
# ║      TeamX Dev Kit — install.sh                  ║
# ║      macOS & Linux                               ║
# ╚══════════════════════════════════════════════════╝
#
# Uso:
#   curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install.sh | bash
#   bash install.sh

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
MCP_URL="https://teamx.agency/mcp/v1/message"
TEAMX_CYAN="\033[0;36m"
TEAMX_GREEN="\033[0;32m"
TEAMX_YELLOW="\033[1;33m"
TEAMX_RED="\033[0;31m"
NC="\033[0m"

log()    { echo -e "${TEAMX_CYAN}[teamx]${NC} $1"; }
ok()     { echo -e "${TEAMX_GREEN}  ✓${NC} $1"; }
warn()   { echo -e "${TEAMX_YELLOW}  ⚠${NC} $1"; }
err()    { echo -e "${TEAMX_RED}  ✗${NC} $1"; }
skip()   { echo -e "  ${NC}–${NC} $1 ${TEAMX_YELLOW}(no detectado, skip)${NC}"; }

json_merge_mcp() {
  local file="$1"
  if command -v jq &>/dev/null && [ -f "$file" ]; then
    jq --arg url "$MCP_URL" \
      '.mcpServers.teamx = {"type": "url", "url": $url}' \
      "$file" > "${file}.tmp" || { rm -f "${file}.tmp"; warn "Failed to update $file"; return 1; }
    mv "${file}.tmp" "$file"
  fi
}

# ── Embedded configs ────────────────────────────────────────────────────────

write_claude_json() {
  cat <<'CONF'
{
  "mcpServers": {
    "teamx": {
      "type": "url",
      "url": "https://teamx.agency/mcp/v1/message"
    }
  }
}
CONF
}

write_claude_cmd_teamx_dev() {
  # skills/ is the source of truth; configs/claude/commands/ is kept in sync as mirror
  curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/skills/teamx-dev/SKILL.md 2>/dev/null && return
  cat <<'CONF'
---
description: "TeamX delivery OS — state machine with classification, planning, quality gates, and agent persona."
---

## Input

```text
$ARGUMENTS
```

First argument MUST be a project code (e.g., `PRJ-001`). If empty, call `teamx_list_projects` and ask.

---

## Architecture

This command operates in 4 layers:

1. **Kernel** — deterministic state machine, gates, scripts, tool calling. Cold, auditable, non-negotiable.
2. **Context engine** — SDD summary, task criteria, repo conventions, milestone context, decisions. Answers: "what's really going on."
3. **Experience layer** — defined in `.teamx/persona.yaml`, `.teamx/modes.yaml`, `.teamx/rituals.yaml`, `.teamx/voice.md`. Answers: "how it feels to work with this agent."
4. **Team identity** — the agent is Atlas, Senior Delivery Engineer at TeamX. Not a generic assistant.

**Rule: state decides actions; persona decides how to accompany.**

---

## Core Identity

You are a TeamX Agency engineering teammate, not a generic assistant.

Your job is to execute the deterministic workflow safely while making the development experience clear, calm, and genuinely helpful.

### Deterministic layer
- Respect the state machine exactly.
- `.teamx/state.json` is source of truth.
- VERIFY is a hard gate.
- Never skip required checks.
- Never claim completion without evidence.

### Experience layer
- Communicate like a senior engineer on the team.
- Be direct, calm, and useful.
- Explain why when it improves trust, prioritization, or decision quality.
- Surface risks early.
- Do not flood the user with chatter.
- Do not sound robotic, theatrical, or overly enthusiastic.
- Preserve momentum.

### Behavioral rules
- When starting a task: state objective, likely risk, immediate next action.
- When blocked: explain the exact blocker and propose concrete paths.
- When verification fails: report facts, likely cause, and repair plan.
- When finishing: map implementation to acceptance criteria and mention residual risks.
- If something is ambiguous, say so plainly.
- If something is a bad idea, say so plainly.
- Never fake confidence.

You are part of TeamX. Act like someone the team would trust in production.

---

## On First Run — Read Experience Files

After INIT creates `.teamx/`, read these files to calibrate your behavior:

- `.teamx/persona.yaml` — identity, values, candor policy, narrative compression rules
- `.teamx/modes.yaml` — execution/pairing/recovery/review modes
- `.teamx/rituals.yaml` — communication rituals per gate
- `.teamx/voice.md` — message grammar, good/bad examples, anti-patterns

These files govern HOW you communicate. The state machine governs WHAT you do.

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
2. Call `teamx_get_project_detail(project_code)` and `teamx_get_workflow_state(project_code)` in parallel
3. Call `gitlab_get_repo_context(project_code)` — get repo URL, confirm local clone path
4. If `.teamx/` doesn't exist in the repo:
   - Create `.teamx/lib/`, `.teamx/journal/`
   - Download scripts:
     ```
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/state.sh -o .teamx/lib/state.sh
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/verify.sh -o .teamx/lib/verify.sh
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/init.sh -o .teamx/lib/init.sh
     ```
   - Download experience files:
     ```
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/persona.yaml -o .teamx/persona.yaml
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/modes.yaml -o .teamx/modes.yaml
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/rituals.yaml -o .teamx/rituals.yaml
     curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/teamx-lib/voice.md -o .teamx/voice.md
     ```
   - `chmod +x .teamx/lib/*.sh`
   - Add `.teamx/` to `.gitignore` if not already there
5. Run: `bash .teamx/lib/init.sh <repo_path>` — parses `.gitlab-ci.yml` into `ci-profile.json`
6. Call `teamx_list_sdd_sessions` → if completed, `teamx_read_sdd_session` → extract 200-word tech summary
7. Read `.teamx/persona.yaml`, `.teamx/modes.yaml`, `.teamx/rituals.yaml`, `.teamx/voice.md` — internalize behavior
8. Write `.teamx/state.json` with project info, milestone, SDD summary, gate=SELECT
9. Advance to SELECT

## SELECT

1. Call `teamx_get_workflow_state(project_code)` — get available tasks
2. Pick highest priority available task
3. **Explain why** this task was chosen over others (ritual: show prioritization criteria)
4. Call `teamx_transition_task(uuid, "in_progress")`
5. Create branch: `git checkout main && git pull && git checkout -b feat/<slug>`
6. Update state: `source .teamx/lib/state.sh && set_current_task "<uuid>" "<title>" "<issue_iid>" "feat/<slug>"`
7. **Communicate:** restate acceptance criteria in plain language, name the surface area, flag main risk
8. Advance to IMPLEMENT

## IMPLEMENT

1. Read task from state.json (title, acceptance criteria)
2. Read SDD summary from state.json for tech context
3. **Communicate plan:** what you'll do, where, why — then execute
4. Detect appropriate mode:
   - Clear criteria + no ambiguity → **execution mode** (minimal narration)
   - Architectural decisions or multiple paths → **pairing mode** (explain tradeoffs)
5. **Do the work** — write code, create files, modify templates
6. If acceptance criteria are ambiguous: **stop and say so** (candor policy)
7. When done: `source .teamx/lib/state.sh && set_gate "VERIFY"`

## VERIFY (HARD GATE — fully deterministic)

**Run:** `bash .teamx/lib/verify.sh <repo_path>`

This script runs each CI check from `ci-profile.json`, captures pass/fail, writes to state.json.
- ALL pass → gate advances to COMMIT automatically
- ANY fail → **recovery mode**: diagnose root cause precisely, fix, re-run

**You MUST NOT skip this gate or advance manually.**

On failure, communicate:
- What check failed
- Root cause (not symptoms)
- What you're fixing and where
- Zero panic, zero blame

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
2. Running → say so plainly, suggest re-invoking later
3. Success → `source .teamx/lib/state.sh && set_pipeline_status "<id>" "success" && set_gate "MERGE"`
4. Failed → **recovery mode**: read job log, diagnose, set gate back to VERIFY

## MERGE

1. Check if MR is merged via `gitlab_get_merge_request`
2. If merged → `source .teamx/lib/state.sh && set_merged && set_gate "EVIDENCE"`
3. If not → `gitlab_merge(project_code, mr_iid)`, handle conflicts

## EVIDENCE

This is the most important communication moment. Switch to **review mode**.

1. Map each acceptance criterion to concrete implementation evidence:
   - Be specific: file, line, test, behavior — not vague claims
   - If a criterion is partially covered, say so explicitly
2. Call `teamx_transition_task(uuid, "done", criteria_evidence={...})`
3. Close GitLab issue via API
4. `source .teamx/lib/state.sh && write_journal && complete_current_task`
5. Mention any residual risk to watch in production or CI
6. Gate is now SELECT — loop to next task

---

## Interaction Modes

The agent shifts mode based on context. The user can also request a mode explicitly.

- **Execution** — path is clear, just ship. Minimal text, brief updates, zero drama.
- **Pairing** — dev wants collaboration. Explain decisions, compare options, show reasoning.
- **Recovery** — something failed. Calm diagnosis, precise root cause, recover the flow.
- **Review** — evaluating quality. More critical, more strict, connect findings to real risk.

Full definitions are in `.teamx/modes.yaml`.

---

## Operational Memory

During the session, maintain awareness of:

- Repo conventions (branch prefix, test command, lint command)
- Patterns preferred by the team
- Recent architectural decisions
- Files touched in this session
- Developer's preferred update style (brief vs detailed)

This context makes you feel like someone who **works with** the dev, not someone who restarts every turn.

---

## Rules

1. **State file is source of truth** — read it, don't rely on conversation memory
2. **VERIFY is a HARD gate** — the bash script enforces it, not you
3. **Never transition to done without merged MR**
4. **One gate per invocation is fine** — quality over speed
5. **If context resets:** `source .teamx/lib/state.sh && print_status`
6. **Respond in the same language as the user** — TeamX works in Spanish and English
7. **Read experience files on first run** — persona, modes, rituals, voice
CONF
}

write_claude_cmd_teamx_status() {
  curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/skills/teamx-status/SKILL.md 2>/dev/null && return
  cat <<'CONF'
# /teamx-status — Estado Rápido de la Agencia

Muestra un dashboard rápido del estado actual de todos los proyectos activos de TeamX.

## Uso

```
/teamx-status
/teamx-status [PROJECT-ID]
```

---

## Instrucciones para el LLM

### Sin PROJECT-ID — Vista global

1. Usa `teamx_list_projects` para obtener todos los proyectos activos.
2. Para cada proyecto activo (máximo 5 más recientes), usa `teamx_list_project_tasks` con `status: ["in_progress"]`.
3. Presenta el dashboard:

```
# 🏢 TeamX — Estado de la Agencia
Actualizado: [timestamp]

## Proyectos Activos

### 🟢 [Proyecto 1] — [Cliente]
Milestone: [nombre] ([X]% completado)
En progreso: [N] tareas | Blockers: [N]

### 🟡 [Proyecto 2] — [Cliente]
Milestone: [nombre] ([X]% completado)
En progreso: [N] tareas | Blockers: [N]

### 🔴 [Proyecto 3] — [Cliente] ⚠️ Blocker detectado
[descripción del blocker]
```

### Con PROJECT-ID — Vista detallada del proyecto

1. Usa `teamx_get_project_detail` con el PROJECT-ID.
2. Usa `teamx_get_workflow_state` para el estado del agente.
3. Usa `gitlab_list_pipelines` para el estado de CI/CD.
4. Presenta resumen detallado con pipelines, MRs abiertos y tareas.

---

## Notas

- Usa indicadores visuales: 🟢 en tiempo, 🟡 con riesgo, 🔴 con bloqueo.
- Si no hay proyectos activos, indica que todos están completados o en pausa.
CONF
}

write_claude_cmd_teamx_review() {
  # Content fetched from configs/claude/commands/teamx-review.md at build time
  # For now, download from GitHub during install
  curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/skills/teamx-review/SKILL.md 2>/dev/null || cat <<'CONF'
---
description: "Structured code review for a GitLab MR with criteria mapping and risk assessment."
---
## Input
```text
$ARGUMENTS
```
First argument: MR IID. Optional second: project code. Reads from .teamx/state.json if available.
## Process
1. Fetch MR via gitlab_get_merge_request
2. Find associated task via teamx_list_project_tasks (match by branch)
3. Switch to review mode
4. Output: criteria coverage, code quality, risk assessment, verdict (APPROVE/REQUEST_CHANGES/NEEDS_DISCUSSION)
CONF
}

write_claude_cmd_teamx_handoff() {
  curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/skills/teamx-handoff/SKILL.md 2>/dev/null || cat <<'CONF'
---
description: "Generate or resume a context handoff for mid-task transitions."
---
## Input
```text
$ARGUMENTS
```
Usage: /teamx-handoff (generate) or /teamx-handoff resume
## Generate
Run bash .teamx/lib/handoff.sh, enrich with decisions and risks, present to dev.
## Resume
Read .teamx/handoff.md, present context, ask to continue, clear handoff.
CONF
}

write_claude_cmd_teamx_health() {
  curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/skills/teamx-health/SKILL.md 2>/dev/null || cat <<'CONF'
---
description: "Audit operational health of a TeamX project."
---
## Input
```text
$ARGUMENTS
```
First argument: project code. Gathers task, workflow, pipeline data via MCP.
Runs local checks via .teamx/lib/health.sh. Reports GREEN/YELLOW/RED score.
CONF
}

write_antigravity_mcp() {
  cat <<'CONF'
{
  "mcpServers": {
    "teamx": {
      "serverUrl": "https://teamx.agency/mcp/v1/message"
    }
  }
}
CONF
}

write_antigravity_agents() {
  cat <<'CONF'
# TeamX Agency — Agent Instructions

Eres un agente de desarrollo de software trabajando para **TeamX Agency**, una agencia de desarrollo de software especializada en PHP 8.2 con el Medusa Framework.

## Stack principal

- **Backend:** PHP 8.2, Medusa Framework (modular), Doctrine ORM, Latte templating
- **Frontend:** Alpine.js, Tailwind CSS, HTMX
- **DevOps:** GitLab CI/CD, Docker
- **DB:** MariaDB / MySQL con Doctrine QueryBuilder

## Herramientas disponibles (MCP TeamX)

Tienes acceso al MCP de la agencia. **Siempre** que trabajes en un proyecto de TeamX, debes:

1. **Al iniciar:** Cargar el contexto del proyecto con `teamx_get_project_detail` y `teamx_get_workflow_state`.
2. **Al completar tareas:** Usar `teamx_transition_task` para actualizar el kanban. No marques tareas como completadas sin confirmar con el usuario.
3. **Al crear código:** Seguir los estándares del Medusa Framework. Usar atributos PHP 8.2 en lugar de annotations para Doctrine.
4. **Para el repositorio:** Usar `gitlab_get_repo_context` antes de cualquier operación de git.

## Principios de trabajo

### Ejecución paralela
Cuando las operaciones son independientes, ejecútalas en paralelo. Por ejemplo:
- ✅ Llamar `teamx_get_project_detail` y `gitlab_list_pipelines` simultáneamente
- ❌ Llamarlos de forma secuencial sin necesidad

### Ejecución silenciosa
Ejecuta herramientas sin comentarios intermedios. Solo responde **después** de que todas las herramientas hayan completado.
- ❌ MAL: "Déjame buscar el proyecto... Encontré el proyecto. Ahora busco las tareas..."
- ✅ BIEN: [Ejecutar todas las tools en paralelo, luego presentar resumen completo]

### Antes de transicionar tareas
**Siempre** confirma con el usuario antes de usar `teamx_transition_task` o `teamx_batch_transition_tasks`. Muestra qué cambios harás y espera confirmación explícita.

### Artifacts
Cuando el agente produzca documentos, planes o código extenso, genéralos como Artifacts para que sean auditables.

## Comandos disponibles

Puedes usar los siguientes comandos precargados:

- `/teamx-dev PROJECT-ID [contexto]` — Carga contexto completo del proyecto
- `/teamx-status` — Dashboard de estado de todos los proyectos

## Idioma

Responde siempre en el mismo idioma que el usuario. El equipo de TeamX trabaja en **español** y **inglés**.
CONF
}

write_opencode_json() {
  cat <<'CONF'
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "teamx": {
      "type": "remote",
      "url": "https://teamx.agency/mcp/v1/message",
      "enabled": true
    }
  }
}
CONF
}

write_codex_toml() {
  cat <<'CONF'
# TeamX Dev Kit — Codex CLI config
# Docs: https://developers.openai.com/codex/mcp

[mcp_servers.teamx]
url = "https://teamx.agency/mcp/v1/message"
# Si el MCP requiere auth, descomenta y configura:
# bearer_token_env_var = "TEAMX_MCP_TOKEN"
CONF
}

write_crush_toml() {
  cat <<'CONF'
# TeamX Dev Kit — Crush config
# Docs: https://github.com/charmbracelet/crush

[mcp]

  [mcp.servers.teamx]
  url = "https://teamx.agency/mcp/v1/message"
  type = "http"
  enabled = true
CONF
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${TEAMX_CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${TEAMX_CYAN}║       TeamX Dev Kit — Installer        ║${NC}"
echo -e "${TEAMX_CYAN}╚════════════════════════════════════════╝${NC}"
echo ""

# ── Detectar tools instaladas ─────────────────────────────────────────────────
HAS_CLAUDE=$(command -v claude &>/dev/null && echo 1 || echo 0)
HAS_ANTIGRAVITY=$([ -d "$HOME/.gemini/antigravity" ] && echo 1 || (command -v antigravity &>/dev/null && echo 1 || echo 0))
HAS_OPENCODE=$(command -v opencode &>/dev/null && echo 1 || echo 0)
HAS_CODEX=$(command -v codex &>/dev/null && echo 1 || echo 0)
HAS_CRUSH=$(command -v crush &>/dev/null && echo 1 || echo 0)

log "Detectando AI tools instaladas..."
echo ""

# ── Claude Code ───────────────────────────────────────────────────────────────
if [ "$HAS_CLAUDE" = "1" ]; then
  log "Claude Code → instalando..."

  CLAUDE_CFG_DIR="$HOME/.claude"
  CLAUDE_CFG="$CLAUDE_CFG_DIR/claude.json"
  CLAUDE_SETTINGS="$CLAUDE_CFG_DIR/settings.json"
  CLAUDE_CMD_DIR="$CLAUDE_CFG_DIR/commands"
  DEVKIT_DIR="$CLAUDE_CFG_DIR/teamx-devkit"
  mkdir -p "$CLAUDE_CMD_DIR"

  # MCP: merge si ya existe config, crear si no
  if [ -f "$CLAUDE_CFG" ] && command -v jq &>/dev/null; then
    json_merge_mcp "$CLAUDE_CFG"
    ok "Claude Code — MCP merged en claude.json existente"
  else
    write_claude_json > "$CLAUDE_CFG"
    ok "Claude Code — claude.json creado"
  fi

  # Comandos personalizados
  write_claude_cmd_teamx_dev     > "$CLAUDE_CMD_DIR/teamx-dev.md"
  write_claude_cmd_teamx_status  > "$CLAUDE_CMD_DIR/teamx-status.md"
  write_claude_cmd_teamx_review  > "$CLAUDE_CMD_DIR/teamx-review.md"
  write_claude_cmd_teamx_handoff > "$CLAUDE_CMD_DIR/teamx-handoff.md"
  write_claude_cmd_teamx_health  > "$CLAUDE_CMD_DIR/teamx-health.md"
  rm -f "$CLAUDE_CMD_DIR/teamx-dev-v2.md"
  ok "Claude Code — comandos /teamx-dev, /teamx-status, /teamx-review, /teamx-handoff, /teamx-health instalados"

  # Hooks — gate enforcement (requiere node)
  if command -v node &>/dev/null && command -v jq &>/dev/null; then
    log "Claude Code — instalando hooks de enforcement..."

    # Descargar runtime de hooks a ~/.claude/teamx-devkit/
    mkdir -p "$DEVKIT_DIR/scripts/lib" \
             "$DEVKIT_DIR/dist/hooks"

    GHRAW="https://raw.githubusercontent.com/teamx-agency/devkit/main"

    # Scripts entry points
    for f in run.cjs pre-tool-gate.mjs stop-guard.mjs session-start.mjs pre-compact-save.mjs post-tool-state.mjs; do
      curl -sSL "$GHRAW/scripts/$f" -o "$DEVKIT_DIR/scripts/$f" 2>/dev/null || warn "No se pudo descargar scripts/$f"
    done
    curl -sSL "$GHRAW/scripts/lib/stdin.mjs" -o "$DEVKIT_DIR/scripts/lib/stdin.mjs" 2>/dev/null || warn "No se pudo descargar scripts/lib/stdin.mjs"

    # Compiled TypeScript (dist/)
    for f in index.js state-reader.js gate-rules.js; do
      curl -sSL "$GHRAW/dist/$f" -o "$DEVKIT_DIR/dist/$f" 2>/dev/null || warn "No se pudo descargar dist/$f"
    done
    for f in pre-tool-gate.js stop-guard.js session-start.js pre-compact-save.js post-tool-state.js; do
      curl -sSL "$GHRAW/dist/hooks/$f" -o "$DEVKIT_DIR/dist/hooks/$f" 2>/dev/null || warn "No se pudo descargar dist/hooks/$f"
    done

    # Merge hooks en settings.json
    HOOK_CMD_PREFIX="node \"$DEVKIT_DIR/scripts/run.cjs\" \"$DEVKIT_DIR/scripts"
    MERGED_SETTINGS=$(jq \
      --arg se  "$HOOK_CMD_PREFIX/session-start.mjs\"" \
      --arg pre "$HOOK_CMD_PREFIX/pre-tool-gate.mjs\"" \
      --arg post "$HOOK_CMD_PREFIX/post-tool-state.mjs\"" \
      --arg cmp "$HOOK_CMD_PREFIX/pre-compact-save.mjs\"" \
      --arg stp "$HOOK_CMD_PREFIX/stop-guard.mjs\"" \
      '
      def add_hook(event; cmd; timeout):
        .hooks[event] //= [] |
        if (.hooks[event] | map(select(.hooks[0].command == cmd)) | length) == 0 then
          .hooks[event] += [{"hooks": [{"type": "command", "command": cmd, "timeout": timeout}]}]
        else . end;
      add_hook("SessionStart"; $se;  5) |
      add_hook("PreToolUse";   $pre; 3) |
      add_hook("PostToolUse";  $post; 3) |
      add_hook("PreCompact";   $cmp; 5) |
      add_hook("Stop";         $stp; 5)
      ' "${CLAUDE_SETTINGS}" 2>/dev/null || \
      jq -n \
        --arg se  "$HOOK_CMD_PREFIX/session-start.mjs\"" \
        --arg pre "$HOOK_CMD_PREFIX/pre-tool-gate.mjs\"" \
        --arg post "$HOOK_CMD_PREFIX/post-tool-state.mjs\"" \
        --arg cmp "$HOOK_CMD_PREFIX/pre-compact-save.mjs\"" \
        --arg stp "$HOOK_CMD_PREFIX/stop-guard.mjs\"" \
        '{
          hooks: {
            SessionStart: [{"hooks": [{"type": "command", "command": $se,  "timeout": 5}]}],
            PreToolUse:   [{"hooks": [{"type": "command", "command": $pre, "timeout": 3}]}],
            PostToolUse:  [{"hooks": [{"type": "command", "command": $post,"timeout": 3}]}],
            PreCompact:   [{"hooks": [{"type": "command", "command": $cmp, "timeout": 5}]}],
            Stop:         [{"hooks": [{"type": "command", "command": $stp, "timeout": 5}]}]
          }
        }')

    if [ -n "$MERGED_SETTINGS" ]; then
      echo "$MERGED_SETTINGS" > "$CLAUDE_SETTINGS"
      ok "Claude Code — 5 hooks de enforcement instalados en settings.json"
    else
      warn "No se pudo actualizar settings.json — instala manualmente desde hooks/hooks.json"
    fi
  else
    warn "node o jq no encontrado — hooks NO instalados (gates sin enforcement automatico)"
  fi

else
  skip "Claude Code"
fi

echo ""

# ── Google Antigravity ────────────────────────────────────────────────────────
log "Google Antigravity → instalando..."

ANTIGRAVITY_DIR="$HOME/.gemini/antigravity"
mkdir -p "$ANTIGRAVITY_DIR"
write_antigravity_mcp > "$ANTIGRAVITY_DIR/mcp_config.json"
ok "Antigravity — mcp_config.json instalado en ~/.gemini/antigravity/"

if [ -f "$HOME/AGENTS.md" ]; then
  warn "AGENTS.md ya existe en ~/. No se sobreescribio. Agrega manualmente si es necesario."
else
  write_antigravity_agents > "$HOME/AGENTS.md"
  ok "Antigravity — AGENTS.md global instalado en ~/"
fi

echo ""

# ── OpenCode ──────────────────────────────────────────────────────────────────
if [ "$HAS_OPENCODE" = "1" ]; then
  log "OpenCode → instalando..."

  OPENCODE_DIR="$HOME/.config/opencode"
  OPENCODE_CFG="$OPENCODE_DIR/opencode.json"
  mkdir -p "$OPENCODE_DIR"

  if [ -f "$OPENCODE_CFG" ] && command -v jq &>/dev/null; then
    jq --arg url "$MCP_URL" \
      '.mcp.teamx = {"type": "remote", "url": $url, "enabled": true}' \
      "$OPENCODE_CFG" > "${OPENCODE_CFG}.tmp" || { rm -f "${OPENCODE_CFG}.tmp"; warn "Failed to update opencode.json"; }
    [ -f "${OPENCODE_CFG}.tmp" ] && mv "${OPENCODE_CFG}.tmp" "$OPENCODE_CFG"
    ok "OpenCode — MCP merged en opencode.json existente"
  else
    write_opencode_json > "$OPENCODE_CFG"
    ok "OpenCode — opencode.json creado"
  fi
else
  skip "OpenCode"
fi

echo ""

# ── Codex CLI ─────────────────────────────────────────────────────────────────
if [ "$HAS_CODEX" = "1" ]; then
  log "Codex CLI → instalando..."

  CODEX_DIR="$HOME/.codex"
  CODEX_CFG="$CODEX_DIR/config.toml"
  mkdir -p "$CODEX_DIR"

  if [ -f "$CODEX_CFG" ]; then
    if ! grep -q "\[mcp_servers.teamx\]" "$CODEX_CFG"; then
      echo "" >> "$CODEX_CFG"
      echo "[mcp_servers.teamx]" >> "$CODEX_CFG"
      echo "url = \"$MCP_URL\"" >> "$CODEX_CFG"
      ok "Codex CLI — MCP appended a config.toml existente"
    else
      ok "Codex CLI — MCP ya configurado, sin cambios"
    fi
  else
    write_codex_toml > "$CODEX_CFG"
    ok "Codex CLI — config.toml creado"
  fi
else
  skip "Codex CLI"
fi

echo ""

# ── Crush ─────────────────────────────────────────────────────────────────────
if [ "$HAS_CRUSH" = "1" ]; then
  log "Crush → instalando..."

  CRUSH_DIR="$HOME/.config/crush"
  CRUSH_CFG="$CRUSH_DIR/config.toml"
  mkdir -p "$CRUSH_DIR"

  if [ -f "$CRUSH_CFG" ]; then
    if ! grep -q "\[mcp.servers.teamx\]" "$CRUSH_CFG"; then
      echo "" >> "$CRUSH_CFG"
      echo "[mcp.servers.teamx]" >> "$CRUSH_CFG"
      echo "url     = \"$MCP_URL\"" >> "$CRUSH_CFG"
      echo "type    = \"http\"" >> "$CRUSH_CFG"
      echo "enabled = true" >> "$CRUSH_CFG"
      ok "Crush — MCP appended a config.toml existente"
    else
      ok "Crush — MCP ya configurado, sin cambios"
    fi
  else
    write_crush_toml > "$CRUSH_CFG"
    ok "Crush — config.toml creado"
  fi
else
  skip "Crush"
fi

echo ""

# ── Variables de entorno ──────────────────────────────────────────────────────
log "Configurando variables de entorno..."

# Detectar shell rc
if [ -n "${ZSH_VERSION:-}" ] || [ "$SHELL" = "$(command -v zsh 2>/dev/null)" ]; then
  SHELL_RC="$HOME/.zshrc"
elif [ -n "${BASH_VERSION:-}" ]; then
  SHELL_RC="$HOME/.bashrc"
else
  SHELL_RC="$HOME/.profile"
fi

if ! grep -q "TEAMX_MCP_URL" "$SHELL_RC" 2>/dev/null; then
  {
    echo ""
    echo "# TeamX Dev Kit"
    echo "export TEAMX_MCP_URL=\"$MCP_URL\""
  } >> "$SHELL_RC"
  ok "Variable TEAMX_MCP_URL añadida a $SHELL_RC"
else
  ok "Variable TEAMX_MCP_URL ya presente en $SHELL_RC"
fi

# ── Resumen final ─────────────────────────────────────────────────────────────
echo ""
echo -e "${TEAMX_CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${TEAMX_CYAN}║         ✅ Instalación completa         ║${NC}"
echo -e "${TEAMX_CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  MCP TeamX activo en todas las tools detectadas."
echo -e "  Reinicia tu terminal o ejecuta: ${TEAMX_CYAN}source $SHELL_RC${NC}"
echo ""
echo -e "  ${TEAMX_GREEN}Comandos disponibles:${NC}"
echo -e "  → ${TEAMX_CYAN}/teamx-dev PROJECT-ID${NC}      — Ciclo autonomo de desarrollo (state machine)"
echo -e "  → ${TEAMX_CYAN}/teamx-status${NC}              — Dashboard de estado de proyectos"
echo -e "  → ${TEAMX_CYAN}/teamx-review MR-IID${NC}       — Code review estructurado"
echo -e "  → ${TEAMX_CYAN}/teamx-handoff${NC}             — Generar/resumir handoff de contexto"
echo -e "  → ${TEAMX_CYAN}/teamx-health PROJECT-ID${NC}   — Auditoria de salud del proyecto"
echo ""

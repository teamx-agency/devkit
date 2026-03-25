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
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
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
  cat <<'CONF'
# /teamx-dev — TeamX Project Context Loader

Carga el contexto completo de un proyecto de la agencia y prepara el entorno de trabajo.

## Uso

```
/teamx-dev <PROJECT-ID> [contexto adicional]
```

**Ejemplos:**
```
/teamx-dev TX-42
/teamx-dev TX-42 Trabajando en el módulo de pagos, sprint 3
/teamx-dev TX-42 Implementar CLABE validation según criterios del milestone 2
```

---

## Instrucciones para el LLM

Cuando este comando sea invocado con un PROJECT-ID, debes ejecutar las siguientes acciones **en orden** usando las herramientas del MCP de TeamX:

### 1. Cargar contexto del proyecto
Usa `teamx_get_project_detail` con el PROJECT-ID proporcionado para obtener:
- Nombre y descripción del proyecto
- Cliente y stack tecnológico
- Milestones activos y su progreso
- Equipo asignado

### 2. Obtener estado del workflow
Usa `teamx_get_workflow_state` para conocer:
- Tareas en progreso actualmente
- Blockers o dependencias pendientes
- Último estado registrado del agente

### 3. Listar tareas del sprint activo
Usa `teamx_list_project_tasks` con filtro `status: ["in_progress", "todo"]` para mostrar:
- Tareas prioritarias pendientes
- Criterios de éxito de cada tarea
- Asignaciones actuales

### 4. Obtener contexto del repositorio
Usa `gitlab_get_repo_context` para obtener:
- URL del repositorio
- Branch principal y branches activos
- Último pipeline y su estado

### 5. Presentar resumen
Presenta un resumen estructurado con:

```
## 📋 Proyecto: [Nombre]
**Cliente:** [Cliente] | **Stack:** [Stack]

## 🎯 Sprint Activo — Milestone: [Milestone Name]
Progreso: [X/Y tareas completadas]

## ⚡ En Progreso
- [ ] TX-XX: [Tarea] (Criterio: [criterio de éxito])
- [ ] TX-XX: [Tarea]

## 📥 Próximas (Todo)
- [ ] TX-XX: [Tarea] — Prioridad: [Alta/Media/Baja]

## 🔀 Repositorio
Branch activo: [branch] | Pipeline: [status]

## 🤖 Estado del Agente
[Último estado del workflow]
```

### 6. Preguntar al usuario
Después del resumen, pregunta:

> ¿En qué tarea quieres que me enfoque? Puedo cargar el detalle completo, los criterios de éxito, y el historial del repositorio para esa tarea específica.

---

## Comportamiento esperado

- Si el PROJECT-ID no existe, informa al usuario y lista los proyectos disponibles con `teamx_list_projects`.
- Si hay contexto adicional en el comando, úsalo para pre-filtrar las tareas relevantes.
- Mantén el contexto del proyecto cargado durante toda la sesión para no repetir llamadas al MCP innecesariamente.
- Al transicionar tareas, usa siempre `teamx_transition_task` o `teamx_batch_transition_tasks` y confirma con el usuario antes de ejecutar.
CONF
}

write_claude_cmd_teamx_dev_v2() {
  cat <<'CONF'
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
CONF
}

write_claude_cmd_teamx_status() {
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
  CLAUDE_CMD_DIR="$CLAUDE_CFG_DIR/commands"
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
  write_claude_cmd_teamx_dev    > "$CLAUDE_CMD_DIR/teamx-dev.md"
  write_claude_cmd_teamx_dev_v2 > "$CLAUDE_CMD_DIR/teamx-dev-v2.md"
  write_claude_cmd_teamx_status > "$CLAUDE_CMD_DIR/teamx-status.md"
  ok "Claude Code — comandos /teamx-dev, /teamx-dev-v2, /teamx-status instalados"
else
  skip "Claude Code"
fi

echo ""

# ── Google Antigravity ────────────────────────────────────────────────────────
log "Google Antigravity → instalando..."

ANTIGRAVITY_DIR="$HOME/.gemini/antigravity"
mkdir -p "$ANTIGRAVITY_DIR"
write_antigravity_mcp    > "$ANTIGRAVITY_DIR/mcp_config.json"
ok "Antigravity — mcp_config.json instalado en ~/.gemini/antigravity/"

write_antigravity_agents > "$HOME/AGENTS.md"
ok "Antigravity — AGENTS.md global instalado en ~/"

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
      "$OPENCODE_CFG" > "${OPENCODE_CFG}.tmp" && mv "${OPENCODE_CFG}.tmp" "$OPENCODE_CFG"
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
echo -e "  → En Claude Code / OpenCode: ${TEAMX_CYAN}/teamx-dev PROJECT-ID${NC}"
echo -e "  → En Claude Code / OpenCode: ${TEAMX_CYAN}/teamx-status${NC}"
echo ""

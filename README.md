# TeamX Dev Kit

Setup en **< 2 minutos** para cualquier dev que se una a TeamX. Instala el delivery OS con enforcement automatico de gates, MCP de la agencia y sistema de experiencia del agente.

---

## Instalacion

### Opcion A — Script (Claude Code + otros tools)

**macOS / Linux:**
```bash
curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/teamx-agency/devkit/main/install.ps1 | iex
```

El script detecta automaticamente las herramientas instaladas y configura:
- **Skills** — `/teamx-dev`, `/teamx-status`, `/teamx-review`, `/teamx-handoff`, `/teamx-health`
- **Hooks** — 5 hooks de enforcement descargados a `~/.claude/teamx-devkit/` y registrados en `settings.json` (requiere `node` y `jq`)
- **MCP TeamX** — agrega `teamx` a Claude Code, Gemini CLI, OpenCode, Codex CLI y Crush si estan instalados
- **Variable de entorno** — `TEAMX_MCP_URL` en `.bashrc` / `.zshrc`

### Opcion B — Plugin marketplace (Claude Code)

Desde Claude Code, abre el plugin manager con `/plugin`:

1. Tab **Marketplaces** → agrega: `https://github.com/teamx-agency/devkit`
2. Tab **Discover** → busca `devkit` → instala

> Si el repo es privado o esta opcion falla, usa la Opcion A.

### Verificar instalacion

```
/teamx-status
```

Si responde con el dashboard de proyectos, la instalacion fue exitosa.

---

## Como funciona

El devkit opera en 4 capas:

```
+---------------------------------------------------------------+
|  4. Team Identity   — quien es el agente dentro de TeamX      |
+---------------------------------------------------------------+
|  3. Experience      — persona, modos, rituales, voz           |
+---------------------------------------------------------------+
|  2. Context Engine  — SDD, tareas, criterios, decisiones      |
+---------------------------------------------------------------+
|  1. Kernel          — state machine, gates, hooks, scripts    |
+---------------------------------------------------------------+
```

**Regla fundamental:** el state machine decide las acciones; la persona decide como acompanar.

### Gate enforcement — 5 hooks TypeScript

Los hooks leen `.teamx/state.json` y bloquean herramientas fuera del gate correcto. El agente no puede ignorarlos.

| Hook | Evento Claude Code | Que hace |
|------|--------------------|----------|
| `pre-tool-gate` | PreToolUse | Bloquea Edit/Write fuera de IMPLEMENT, git commit fuera de COMMIT, MCP tools en gates incorrectos |
| `stop-guard` | Stop | Bloquea parar con trabajo en curso (safety valve a los 5 bloqueos) |
| `session-start` | SessionStart | Restaura estado + handoff + shared lessons al iniciar sesion |
| `pre-compact-save` | PreCompact | Preserva estado antes de compactacion de contexto |
| `post-tool-state` | PostToolUse | Re-inyecta estado tras llamadas MCP; advierte si faltan criterios |

Los hooks **solo leen** `state.json`. Los bash scripts (state.sh, verify.sh) son el backend determinista que escribe.

```
LLM llama state.sh → state.sh escribe state.json → hook lee state.json → enforce
```

### State machine — 14 gates

```
IDLE → INIT → SELECT → CLASSIFY → [PLAN] → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → MERGE → EVIDENCE → [RETROSPECTIVE] → SELECT
```

**Flow variants** — determinados en CLASSIFY segun el tipo de trabajo:

| Tipo | Branch | Commit | Flow | Diferencia |
|------|--------|--------|------|------------|
| feature | `feat/` | `feat:` | standard | Flujo completo |
| bugfix | `fix/` | `fix:` | standard | Flujo completo |
| hotfix | `hotfix/` | `fix:` | compressed | Salta PLAN, EVIDENCE minimo |
| refactor | `refactor/` | `refactor:` | standard | Flujo completo |
| chore | `chore/` | `chore:` | standard | Flujo completo |
| discovery | `spike/` | `docs:` | discovery | Salta VERIFY→MERGE, produce findings |

### Formato de commit

```
<commit_prefix> <task-title>

Closes #<gitlab_issue_iid>   ← solo si tiene issue vinculado

Co-Authored-By: DevKit <hola@teamx.agency>
```

### Formato de MR

```markdown
## What
<que cambio y por que>

## Acceptance Criteria
- [ ] criterio 1
- [ ] criterio 2

Closes #<issue>
```

---

## Skills disponibles

### `/teamx-dev PROJECT-ID` — Ciclo de desarrollo

Carga contexto del proyecto, selecciona la tarea de mayor prioridad y ejecuta el ciclo completo: CLASSIFY → PLAN → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → MERGE → EVIDENCE → RETROSPECTIVE.

```
/teamx-dev PRJ-001
```

En INIT (primera vez) el agente:
1. Carga proyecto y workflow del MCP
2. Clona o ubica el repo local
3. Descarga scripts y archivos de experiencia a `.teamx/`
4. Extrae CI checks del `.gitlab-ci.yml` (stack-agnostic) → `ci-profile.json`
5. Lee el SDD aprobado (si existe) → `sdd-summary.json`
6. Carga shared lessons del equipo → `shared-lessons.json`

### `/teamx-status` — Dashboard de proyectos

Vista rapida del estado de todos los proyectos activos: milestone, tareas en curso, blockers.

### `/teamx-review MR-IID` — Code review

Review estructurado con mapeo de criterios de aceptacion y evaluacion de riesgo.

### `/teamx-handoff` — Handoff de contexto

Genera o retoma un documento de transferencia de contexto entre sesiones.

### `/teamx-health PROJECT-ID` — Auditoria de salud

Revisa tareas, pipelines, branches y milestones. Score: GREEN / YELLOW / RED.

---

## MCP TeamX — herramientas disponibles

| Categoria | Herramientas |
|-----------|-------------|
| Proyectos | `teamx_list_projects`, `teamx_get_project_detail`, `teamx_post_project_update` |
| Tareas | `teamx_list_project_tasks`, `teamx_get_task_detail`, `teamx_transition_task`, `teamx_batch_transition_tasks`, `teamx_satisfy_acceptance_criterion` |
| Workflow | `teamx_get_workflow_state`, `teamx_log_time_entry` |
| SDD | `teamx_list_sdd_sessions`, `teamx_read_sdd_session`, `teamx_start_sdd_session`, `teamx_send_sdd_message`, `teamx_approve_sdd` |
| Lecciones | `teamx_get_shared_lessons`, `teamx_push_lessons` |
| GitLab | `gitlab_get_repo_context`, `gitlab_list_pipelines`, `gitlab_get_merge_request`, `gitlab_create_merge_request`, `gitlab_merge`, `gitlab_get_job_log`, `gitlab_retry_job` |

---

## Archivos de experiencia

Se descargan en INIT al directorio `.teamx/` del proyecto (no se commitean):

| Archivo | Proposito |
|---------|-----------|
| `persona.yaml` | Identidad de AgenteX: valores, candor policy |
| `modes.yaml` | 4 modos de interaccion: execution, pairing, recovery, review |
| `rituals.yaml` | Rituales de comunicacion por gate |
| `voice.md` | Gramatica de mensajes, ejemplos, anti-patterns |
| `work_types.yaml` | Tipos de trabajo: prefixes, flow variants |

---

## Estructura del repo

```
teamx-devkit/
├── .claude-plugin/          <- Plugin manifest para Claude Code
│   ├── plugin.json
│   └── marketplace.json
├── hooks/
│   └── hooks.json           <- Configuracion de los 5 hooks
├── scripts/                 <- Entry points de los hooks (Node.js)
│   ├── run.cjs              <- Runner cross-platform
│   ├── lib/stdin.mjs
│   ├── pre-tool-gate.mjs
│   ├── stop-guard.mjs
│   ├── session-start.mjs
│   ├── pre-compact-save.mjs
│   └── post-tool-state.mjs
├── src/                     <- TypeScript source (compilado a dist/)
│   ├── state-reader.ts      <- Lee .teamx/state.json (read-only)
│   ├── gate-rules.ts        <- Mapeo tool → gates permitidos
│   └── hooks/               <- Logica de cada hook
├── dist/                    <- TypeScript compilado
├── skills/                  <- Skills de Claude Code (fuente de verdad)
│   ├── teamx-dev/SKILL.md
│   ├── teamx-status/SKILL.md
│   ├── teamx-review/SKILL.md
│   ├── teamx-handoff/SKILL.md
│   └── teamx-health/SKILL.md
├── teamx-lib/               <- Kernel bash scripts + archivos de experiencia
│   ├── state.sh             <- State machine (fuente de verdad del estado)
│   ├── verify.sh            <- Ejecuta CI checks del ci-profile.json
│   ├── init.sh              <- Extrae CI profile del .gitlab-ci.yml
│   ├── handoff.sh           <- Genera documento de handoff
│   ├── health.sh            <- Auditoria de salud local
│   ├── lessons.sh           <- Extrae patrones de journals
│   └── persona.yaml, modes.yaml, rituals.yaml, voice.md, work_types.yaml
├── configs/                 <- MCP configs para otros tools (mirror de skills/)
├── install.sh               <- Installer macOS/Linux
├── install.ps1              <- Installer Windows
├── package.json
└── tsconfig.json
```

---

## Desarrollo local

```bash
npm install       # instalar dependencias
npm run build     # compilar TypeScript → dist/
```

Despues de editar cualquier skill: sincronizar `configs/claude/commands/`:
```bash
cp skills/teamx-dev/SKILL.md configs/claude/commands/teamx-dev.md
```

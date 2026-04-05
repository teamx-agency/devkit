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
| `pre-tool-gate` | PreToolUse | Bloquea Edit/Write fuera de IMPLEMENT; git commit/push/merge en gates incorrectos; git reset/rebase/clean/restore fuera de CLASSIFY/IMPLEMENT (rebase bloqueado siempre); MCP tools en gates incorrectos |
| `stop-guard` | Stop | Bloquea parar con trabajo en curso (safety valve a los 5 bloqueos — escribe `.teamx/handoff.md` automaticamente antes de aprobar) |
| `session-start` | SessionStart | Restaura estado + handoff + shared lessons al iniciar sesion |
| `pre-compact-save` | PreCompact | Preserva estado antes de compactacion; inyecta reminder de llamar `teamx_get_task_detail` para restaurar criterios |
| `post-tool-state` | PostToolUse | Re-inyecta estado tras llamadas MCP; lee `qa_warnings` del server (criterios duplicados); valida respuesta de `satisfy_acceptance_criterion`; advierte si faltan criterios; muestra progreso de criterios post `get_task_detail` |

Los hooks **solo leen** `state.json`. Los bash scripts (`state.sh`, `verify.sh`) son el backend determinista que escribe.

```
LLM llama state.sh → state.sh escribe state.json → hook lee state.json → enforce
```

### State machine — 15 gates

```
IDLE → INIT → SELECT → CLASSIFY → [PLAN] → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → REVIEW → MERGE → EVIDENCE → RETROSPECTIVE → SELECT
```

> **REVIEW** es el gate de QA entre pipeline y merge. El agente **no puede auto-aprobarlo**: requiere que un humano ejecute `approve_qa_review` en la terminal. Ver seccion _Gate REVIEW_.

> **RETROSPECTIVE** es obligatorio. No es opcional. El agente debe extraer al menos 1 insight y llamar `teamx_push_lessons` antes de avanzar a SELECT.

**Flow variants** — determinados en CLASSIFY segun el tipo de trabajo:

| Tipo | Branch | Commit | Flow | Diferencia |
|------|--------|--------|------|------------|
| feature | `feat/` | `feat:` | standard | Flujo completo |
| bugfix | `fix/` | `fix:` | standard | Flujo completo |
| hotfix | `hotfix/` | `fix:` | compressed | Salta PLAN, EVIDENCE minimo |
| refactor | `refactor/` | `refactor:` | standard | Flujo completo |
| chore | `chore/` | `chore:` | standard | Flujo completo |
| discovery | `spike/` | `docs:` | discovery | Salta VERIFY→MERGE (incluyendo REVIEW), produce findings |

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

## Gate REVIEW — QA obligatorio antes de merge

El gate REVIEW se activa automaticamente cuando el pipeline pasa. **El agente queda bloqueado**: no puede llamar `gitlab_merge` hasta que QA apruebe manualmente.

### Flujo

```
pipeline: success
    ↓
advance_to_review()     ← agente corre esto al ver pipeline verde
    ↓
REVIEW gate             ← agente presenta MR + criterios satisfechos
                           QA revisa el MR en GitLab de forma independiente
    ↓
approve_qa_review()     ← QA/humano corre esto en la terminal
    ↓
MERGE gate              ← agente puede mergear
```

### Comandos bash

```bash
source .teamx/lib/state.sh

# Agente: avanzar a REVIEW cuando pipeline pase
advance_to_review

# QA/humano: aprobar y abrir MERGE
approve_qa_review

# Ver estado actual
print_status
```

### Por que no se puede auto-aprobar

El REVIEW gate existe para romper el ciclo donde el mismo agente que implemento tambien valida. La herramienta `gitlab_merge` solo esta permitida en el gate MERGE, y solo QA/humano puede transicionar de REVIEW a MERGE.

---

## QA enforcement — criterios y calidad

### Deteccion de criterios duplicados (server-side)

El MCP server computa `qa_warnings` en cada llamada a `teamx_get_workflow_state`. Si dos o mas tareas del milestone activo comparten el mismo criterio de aceptacion (texto identico), aparece un warning:

```
[QA] Criterio duplicado en 3 tareas: "board.matchGame() retorna instancia..."
     Compartido por: "Tarea A", "Tarea B", "Tarea C"
     Los criterios no especificos por tarea generan ambiguedad en validacion QA.
```

Este warning viene del backend con acceso completo a BD — no es una estimacion del cliente. El devkit tambien tiene deteccion client-side como fallback para versiones anteriores del server.

### Validacion de ci-profile

`verify.sh` valida el `ci-profile.json` antes de correr checks:

- **< 2 checks**: warning — minimo recomendado es lint + tests
- **Sin check con `test` en stage/nombre**: warning — codigo sin tests puede llegar a MERGE

La ejecucion continua con los checks existentes, pero el warning queda registrado para que QA lo considere al revisar el VERIFY gate.

### Criterios en state summary

`print_status` y los summaries de contexto muestran el progreso de criterios:

```
Criteria: 2/4 satisfied — 2 PENDING
```

Para persistir este conteo en `state.json` despues de llamar `teamx_get_task_detail`:

```bash
source .teamx/lib/state.sh
set_criteria_progress <total> <satisfied>
# Ejemplo: set_criteria_progress 4 2
```

El hook `post-tool-state` inyecta este comando automaticamente despues de cada `teamx_get_task_detail` para que el agente lo ejecute.

### Safety valve con handoff automatico

Si el agente queda atascado y activa la valvula de seguridad (5 bloques consecutivos del stop-guard), el devkit escribe `.teamx/handoff.md` automaticamente antes de aprobar el stop. El archivo captura gate, branch, estado git y criterios pendientes.

Reanudar:
```
/teamx-handoff resume
```

---

## Operaciones git bloqueadas por gate

El gate guard bloquea comandos git fuera del contexto correcto para prevenir perdida de trabajo:

| Comando | Gates permitidos | Razon |
|---------|-----------------|-------|
| `git commit` | COMMIT | Solo cuando los checks CI pasaron |
| `git push` | PUSH | Solo despues de commit verificado |
| `git merge` | MERGE | Solo despues de QA approval (REVIEW → MERGE) |
| `git checkout -b` / `git switch -c` | CLASSIFY | Solo al crear la branch de la tarea |
| `git reset` | CLASSIFY, IMPLEMENT | Fuera de implementacion activa puede perder trabajo commitado |
| `git clean` | CLASSIFY, IMPLEMENT | Fuera de implementacion activa puede limpiar archivos no commitados |
| `git restore` | CLASSIFY, IMPLEMENT | Fuera de implementacion activa puede descartar cambios no staged |
| `git rebase` | _ninguno_ | Bloqueado siempre — reescribe historial compartido |
| `verify.sh` | VERIFY | Solo en el gate correcto |

---

## Skills disponibles

### `/teamx-dev PROJECT-ID` — Ciclo de desarrollo

Carga contexto del proyecto, selecciona la tarea de mayor prioridad y ejecuta el ciclo completo: CLASSIFY → PLAN → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → REVIEW → MERGE → EVIDENCE → RETROSPECTIVE.

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

Review estructurado con mapeo de criterios de aceptacion y evaluacion de riesgo. Uso tipico: en el gate REVIEW antes de llamar `approve_qa_review`.

### `/teamx-handoff` — Handoff de contexto

Genera o retoma un documento de transferencia de contexto entre sesiones. El stop-guard genera handoffs automaticos en safety valve.

### `/teamx-health PROJECT-ID` — Auditoria de salud

Revisa tareas, pipelines, branches y milestones. Score: GREEN / YELLOW / RED.

---

## MCP TeamX — herramientas disponibles

| Categoria | Herramientas |
|-----------|-------------|
| Proyectos | `teamx_list_projects`, `teamx_get_project_detail`, `teamx_post_project_update` |
| Tareas | `teamx_list_project_tasks`, `teamx_get_task_detail`, `teamx_transition_task`, `teamx_batch_transition_tasks`, `teamx_satisfy_acceptance_criterion` |
| Workflow | `teamx_get_workflow_state` _(incluye `qa_warnings` server-side)_, `teamx_log_time_entry` |
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
| `rituals.yaml` | Rituales de comunicacion por gate (incluye REVIEW y RETROSPECTIVE obligatorio) |
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
│   ├── state-reader.ts      <- Lee .teamx/state.json (read-only); gate REVIEW incluido
│   ├── gate-rules.ts        <- Mapeo tool → gates; git destructivo bloqueado
│   └── hooks/               <- Logica de cada hook
│       ├── pre-tool-gate.ts
│       ├── stop-guard.ts    <- Safety valve escribe handoff.md automatico
│       ├── session-start.ts
│       ├── pre-compact-save.ts  <- Reminder de criterios post-compaction
│       └── post-tool-state.ts   <- qa_warnings server + validacion API + criterios
├── dist/                    <- TypeScript compilado
├── skills/                  <- Skills de Claude Code (fuente de verdad)
│   ├── teamx-dev/SKILL.md
│   ├── teamx-status/SKILL.md
│   ├── teamx-review/SKILL.md
│   ├── teamx-handoff/SKILL.md
│   └── teamx-health/SKILL.md
├── teamx-lib/               <- Kernel bash scripts + archivos de experiencia
│   ├── state.sh             <- State machine; advance_to_review, approve_qa_review, set_criteria_progress
│   ├── verify.sh            <- CI checks + validacion minima de ci-profile
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

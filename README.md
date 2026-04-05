# TeamX Dev Kit

Setup en **< 2 minutos** para cualquier dev que se una a TeamX. Instala el delivery OS con enforcement automatico de gates, MCP de la agencia y sistema de experiencia del agente.

## Instalacion

### Opcion A — Script (recomendado, Claude Code + otros tools)

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

Desde Claude Code, abre el plugin manager con `/plugin` y:

1. Ve a la tab **Marketplaces** → agrega el marketplace de TeamX:
   ```
   https://github.com/teamx-agency/devkit
   ```
2. Ve a la tab **Discover** → busca `devkit` → instala

> Si el repo es privado o la Opcion B falla, usa la Opcion A — es equivalente.

### Verificar instalacion

Tras instalar, abre Claude Code y ejecuta:
```
/teamx-status
```

Si responde con el dashboard de proyectos activos, la instalacion fue exitosa.

---

## Que hay de nuevo en v2

| v1 (anterior) | v2 (actual) |
|---------------|-------------|
| 365 lineas de instrucciones que el agente "debia" seguir | **5 hooks programaticos** que enforcement gates automaticamente |
| Agente olvidaba gates, leia mal tareas | PreToolUse bloquea herramientas en gates incorrectos |
| Se detenia con trabajo pendiente | Stop hook bloquea parar hasta completar el gate |
| Perdia contexto tras compactacion | PreCompact preserva estado automaticamente |
| Solo instrucciones markdown | Plugin system con TypeScript compilado |
| `install.sh` copiaba archivos | `/plugin install devkit` |

---

## Arquitectura

El devkit opera en 4 capas como un **delivery operating system**:

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

### Hook-based enforcement (nuevo en v2)

5 hooks de Claude Code que leen `.teamx/state.json` y enforcement gates programaticamente:

| Hook | Evento | Que hace |
|------|--------|----------|
| `pre-tool-gate` | PreToolUse | Bloquea Edit/Write fuera de IMPLEMENT, git commit fuera de COMMIT, etc. |
| `stop-guard` | Stop | Bloquea parar con trabajo pendiente (safety valve a los 5 bloqueos) |
| `session-start` | SessionStart | Restaura estado + handoff + lessons al iniciar sesion |
| `pre-compact-save` | PreCompact | Preserva estado antes de compactacion de contexto |
| `post-tool-state` | PostToolUse | Re-inyecta estado tras llamadas MCP, advierte criterios faltantes |

Los hooks **solo leen** `state.json` — nunca escriben. Los bash scripts (state.sh, verify.sh) siguen siendo el backend determinista.

```
LLM llama state.sh -> state.sh escribe state.json -> hook lee state.json -> enforce
```

---

## Estructura del repo

```
teamx-devkit/
├── .claude-plugin/                      <- Plugin manifest
│   ├── plugin.json
│   └── marketplace.json
├── hooks/
│   └── hooks.json                       <- 5 hooks de Claude Code
├── scripts/
│   ├── run.cjs                          <- Cross-platform hook runner
│   ├── lib/stdin.mjs                    <- Stdin reader con timeout
│   ├── pre-tool-gate.mjs               <- Entry: gate enforcement
│   ├── stop-guard.mjs                  <- Entry: completion guard
│   ├── session-start.mjs               <- Entry: state restoration
│   ├── pre-compact-save.mjs            <- Entry: context preservation
│   └── post-tool-state.mjs             <- Entry: state tracking
├── src/                                 <- TypeScript source
│   ├── state-reader.ts                  <- Lee .teamx/state.json
│   ├── gate-rules.ts                    <- Mapeo tool -> gates permitidos
│   └── hooks/                           <- Logica de cada hook
├── skills/                              <- Skills del plugin
│   ├── teamx-dev/SKILL.md              <- /teamx-dev (delivery OS)
│   ├── teamx-status/SKILL.md           <- /teamx-status (dashboard)
│   ├── teamx-review/SKILL.md           <- /teamx-review (code review)
│   ├── teamx-handoff/SKILL.md          <- /teamx-handoff (context transfer)
│   └── teamx-health/SKILL.md           <- /teamx-health (project audit)
├── teamx-lib/                           <- Kernel bash scripts + experiencia
│   ├── state.sh                         <- State machine v3
│   ├── verify.sh                        <- VERIFY gate (CI checks)
│   ├── init.sh                          <- Parsea .gitlab-ci.yml
│   ├── handoff.sh, health.sh, lessons.sh
│   ├── persona.yaml, modes.yaml, rituals.yaml
│   ├── voice.md, work_types.yaml
├── configs/                             <- MCP configs para otros tools
├── project-templates/                   <- Templates per-project
├── install.sh                           <- Fallback installer
├── package.json                         <- Node project
└── tsconfig.json                        <- TypeScript config
```

---

## Skills (antes "Comandos")

### `/teamx-dev PROJECT-ID` — Delivery OS

Ciclo autonomo de desarrollo con state machine, clasificacion, quality gates y experiencia de 4 capas.

```
/teamx-dev PRJ-001
```

#### State machine (v3)

```
IDLE -> INIT -> SELECT -> CLASSIFY -> [PLAN] -> IMPLEMENT -> VERIFY -> COMMIT -> PUSH -> MR -> PIPELINE -> MERGE -> EVIDENCE -> [RETROSPECTIVE] -> SELECT
```

#### Gate enforcement (automatico)

| Herramienta | Gate requerido |
|-------------|---------------|
| Edit, Write | IMPLEMENT |
| `git commit` | COMMIT |
| `git push` | PUSH |
| `git checkout -b` | CLASSIFY |
| `verify.sh` | VERIFY |
| `transition_task` | SELECT, EVIDENCE |
| `satisfy_acceptance_criterion` | EVIDENCE |

Si el agente intenta usar una herramienta en un gate incorrecto, el hook la bloquea con un mensaje explicando que gate necesita.

#### Tipos de trabajo

| Tipo | Branch | Commit | Flow |
|------|--------|--------|------|
| feature | `feat/` | `feat:` | standard |
| bugfix | `fix/` | `fix:` | standard |
| hotfix | `hotfix/` | `fix:` | compressed |
| refactor | `refactor/` | `refactor:` | standard |
| chore | `chore/` | `chore:` | standard |
| discovery | `spike/` | `docs:` | discovery |

#### Modos de interaccion

| Modo | Cuando | Comportamiento |
|------|--------|---------------|
| **Execution** | Path claro | Minimo texto, updates en transiciones |
| **Pairing** | Decisiones arquitectonicas | Explica tradeoffs, compara alternativas |
| **Recovery** | Check falla, pipeline roto | Diagnostico preciso, zero panico |
| **Review** | Evidencia, evaluacion | Mas critico, conecta hallazgos con riesgo |

---

### `/teamx-review MR-IID` — Code Review

Review estructurado con mapeo de criterios y evaluacion de riesgo.

### `/teamx-handoff` — Context Handoff

Genera o resume handoff de contexto entre sesiones.

### `/teamx-health PROJECT-ID` — Project Health

Auditoria de salud: tareas, pipelines, branches, milestones. Score: GREEN / YELLOW / RED.

### `/teamx-status` — Quick Status

Dashboard rapido de proyectos activos.

---

## MCP TeamX — herramientas disponibles

- **Proyectos** — listar, detalle, estado
- **Tareas** — listar, detalle individual, transicionar, satisfacer criterios
- **Workflow** — kanban, batch transitions, estado del agente
- **GitLab** — repos, pipelines, MRs, job logs
- **SDD** — Solution Design Documents
- **Time** — log de horas trabajadas

---

## Archivos de experiencia

Se descargan durante INIT al `.teamx/` del proyecto:

| Archivo | Proposito |
|---------|-----------|
| `work_types.yaml` | Tipos de trabajo: prefixes, variantes de flujo |
| `persona.yaml` | Identidad de AgenteX: valores, candor policy |
| `modes.yaml` | 4 modos de interaccion |
| `rituals.yaml` | Rituales de comunicacion por gate |
| `voice.md` | Gramatica de mensajes, ejemplos, anti-patterns |

---

## Desarrollo

```bash
npm install          # Instalar dependencias
npm run build        # Compilar TypeScript -> dist/
```

---

## Backward compatibility

- State machine v3 es backward-compatible con v2
- `migrate_state()` en state.sh llena defaults para campos nuevos
- Directorios `.teamx/` existentes siguen funcionando
- `install.sh` sigue disponible como fallback

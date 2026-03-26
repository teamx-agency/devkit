# TeamX Dev Kit

Setup en **< 2 minutos** para cualquier dev que se una a TeamX. Instala el MCP de la agencia, los comandos del delivery OS y el sistema de experiencia del agente en todos los AI coding tools compatibles.

## Instalacion rapida

**macOS / Linux:**
```bash
curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/teamx-agency/devkit/main/install.ps1 | iex
```

---

## Arquitectura

El devkit opera en 4 capas como un **delivery operating system**, no un runner de tareas:

```
+---------------------------------------------------------------+
|  4. Team Identity   — quien es el agente dentro de TeamX      |
+---------------------------------------------------------------+
|  3. Experience      — persona, modos, rituales, voz           |
+---------------------------------------------------------------+
|  2. Context Engine  — SDD, tareas, criterios, decisiones      |
+---------------------------------------------------------------+
|  1. Kernel          — state machine, gates, scripts, tools    |
+---------------------------------------------------------------+
```

**Regla fundamental:** el state machine decide las acciones; la persona decide como acompanar.

### Kernel determinista (capa 1)

State machine, `.teamx/state.json`, gates duros, verify scripts, clasificacion de trabajo, readiness checks, flow variants, politicas de commit/MR/pipeline/evidencia.

### Context engine (capa 2)

SDD summary, tarea actual, acceptance criteria, decisiones previas, convenciones del repo, contexto de milestone, riesgos conocidos, constraints tecnicos, lessons de tareas anteriores.

### Experience layer (capa 3)

Modos de interaccion (execution/pairing/recovery/review), rituales por gate, gramatica de mensajes, narrative compression, candor policy.

### Team identity (capa 4)

AgenteX, Senior Delivery Engineer. Valores, forma de colaborar, estandares de honestidad, forma de escalar riesgos.

---

## Tools soportadas

| Tool | MCP | Comandos | Config path |
|------|-----|----------|-------------|
| Claude Code | ✅ | ✅ 5 comandos | `~/.claude/claude.json` |
| Google Antigravity | ✅ | ✅ `AGENTS.md` | `~/.gemini/antigravity/mcp_config.json` |
| OpenCode | ✅ | ✅ `.opencode/commands/` | `~/.config/opencode/opencode.json` |
| Codex CLI | ✅ | — | `~/.codex/config.toml` |
| Crush | ✅ | — | `~/.config/crush/config.toml` |

---

## Estructura del repo

```
teamx-devkit/
├── install.sh                        <- Entry point macOS/Linux
├── install.ps1                       <- Entry point Windows
├── configs/
│   ├── claude/
│   │   ├── claude.json               <- MCP global para Claude Code
│   │   └── commands/
│   │       ├── teamx-dev.md          <- /teamx-dev (delivery OS)
│   │       ├── teamx-status.md       <- /teamx-status (dashboard)
│   │       ├── teamx-review.md       <- /teamx-review (code review)
│   │       ├── teamx-handoff.md      <- /teamx-handoff (context transfer)
│   │       └── teamx-health.md       <- /teamx-health (project audit)
│   ├── antigravity/
│   │   ├── mcp_config.json           <- MCP para Antigravity
│   │   └── AGENTS.md                 <- Instrucciones de agente globales
│   ├── opencode/
│   │   └── opencode.json             <- MCP + comandos para OpenCode
│   ├── codex/
│   │   └── config.toml               <- MCP para Codex CLI
│   └── crush/
│       └── config.toml               <- MCP para Crush
├── teamx-lib/                        <- Kernel + experiencia (per-project)
│   ├── state.sh                      <- State machine v3 (clasificacion, plan, handoff)
│   ├── verify.sh                     <- VERIFY gate (CI checks sin LLM)
│   ├── init.sh                       <- Parsea .gitlab-ci.yml -> ci-profile.json
│   ├── handoff.sh                    <- Generador de context handoff
│   ├── health.sh                     <- Health checks locales
│   ├── lessons.sh                    <- Extraccion de aprendizaje de journals
│   ├── work_types.yaml               <- Registro de tipos de trabajo
│   ├── persona.yaml                  <- Identidad del agente (AgenteX)
│   ├── modes.yaml                    <- Modos de interaccion
│   ├── rituals.yaml                  <- Rituales de comunicacion por gate
│   └── voice.md                      <- Gramatica de mensajes y ejemplos
└── project-templates/
    ├── .mcp.json                     <- MCP a nivel proyecto (Claude Code)
    ├── opencode.json                 <- MCP a nivel proyecto (OpenCode)
    └── AGENTS.md                     <- Instrucciones proyecto (Antigravity)
```

---

## Comandos

### `/teamx-dev PROJECT-ID` — Delivery OS

Ciclo autonomo de desarrollo con state machine persistente, clasificacion de trabajo, quality gates deterministas y sistema de experiencia de 4 capas.

```
/teamx-dev PRJ-001
```

#### State machine (v3)

```
IDLE -> INIT -> SELECT -> CLASSIFY -> [PLAN] -> IMPLEMENT -> VERIFY -> COMMIT -> PUSH -> MR -> PIPELINE -> MERGE -> EVIDENCE -> [RETROSPECTIVE] -> SELECT
```

#### Nuevos gates

| Gate | Tipo | Proposito |
|------|------|-----------|
| **CLASSIFY** | Obligatorio | Clasifica tipo de trabajo, verifica readiness, crea branch con prefix correcto |
| **PLAN** | Opcional | Pre-planificacion para tareas complejas (>5 archivos, cross-layer, riesgo alto) |
| **RETROSPECTIVE** | Opcional | Extrae aprendizaje despues de EVIDENCE |

#### Tipos de trabajo

| Tipo | Branch | Commit | Flow |
|------|--------|--------|------|
| feature | `feat/` | `feat:` | standard |
| bugfix | `fix/` | `fix:` | standard |
| hotfix | `hotfix/` | `fix:` | compressed (sin PLAN, postmortem obligatorio) |
| refactor | `refactor/` | `refactor:` | standard |
| chore | `chore/` | `chore:` | standard |
| discovery | `spike/` | `docs:` | discovery (sin VERIFY->MERGE, produce documento) |

#### Task readiness

Antes de que una tarea entre a IMPLEMENT, CLASSIFY verifica:
- Tiene acceptance criteria? (si no -> NEEDS_REFINEMENT, no avanza)
- Son claros y no ambiguos? (candor policy)
- Dependencias resueltas?
- Contexto SDD suficiente?

#### Modos de interaccion

| Modo | Cuando | Comportamiento |
|------|--------|---------------|
| **Execution** | Path claro, sin ambiguedad | Minimo texto, updates en transiciones |
| **Pairing** | Decisiones arquitectonicas | Explica tradeoffs, compara alternativas |
| **Recovery** | Check falla, pipeline roto | Diagnostico preciso, zero panico |
| **Review** | Evidencia, evaluacion de calidad | Mas critico, conecta hallazgos con riesgo |

---

### `/teamx-review MR-IID` — Code Review

Review estructurado de un MR de GitLab con mapeo de criterios y evaluacion de riesgo.

```
/teamx-review 42
/teamx-review 42 PRJ-001
```

Output: criteria coverage, code quality, risk assessment, verdict (APPROVE/REQUEST_CHANGES/NEEDS_DISCUSSION).

Flujo independiente — no modifica el state machine.

---

### `/teamx-handoff` — Context Handoff

Genera o resume un handoff de contexto cuando un dev para a mitad de tarea o otro retoma.

```
/teamx-handoff           # Generar handoff
/teamx-handoff resume    # Resumir desde handoff existente
```

Captura: gate actual, archivos tocados, decisiones con rationale, riesgos abiertos.

---

### `/teamx-health PROJECT-ID` — Project Health

Auditoria de salud operativa del proyecto.

```
/teamx-health PRJ-001
```

Checks: tareas sin criteria, branches stale, pipelines rotos, milestones vencidos, tareas in_progress demasiado tiempo.

Score: GREEN / YELLOW / RED.

---

### `/teamx-status` — Quick Status

Dashboard rapido del estado de proyectos activos.

```
/teamx-status              # Vista global
/teamx-status PRJ-001      # Vista detallada
```

---

## Setup manual (sin script)

### Claude Code
```bash
mkdir -p ~/.claude/commands
cp configs/claude/claude.json ~/.claude/claude.json
cp configs/claude/commands/*.md ~/.claude/commands/
```

### Google Antigravity
```bash
mkdir -p ~/.gemini/antigravity
cp configs/antigravity/mcp_config.json ~/.gemini/antigravity/mcp_config.json
```

### OpenCode
```bash
mkdir -p ~/.config/opencode
cp configs/opencode/opencode.json ~/.config/opencode/opencode.json
```

### Codex CLI
```bash
mkdir -p ~/.codex
cp configs/codex/config.toml ~/.codex/config.toml
```

### Crush
```bash
mkdir -p ~/.config/crush
cp configs/crush/config.toml ~/.config/crush/config.toml
```

---

## Por proyecto (recomendado para Claude Code y OpenCode)

```bash
cp project-templates/.mcp.json .          # Claude Code
cp project-templates/opencode.json .       # OpenCode
cp project-templates/AGENTS.md .          # Antigravity
```

---

## MCP TeamX — herramientas disponibles

- **Proyectos** — listar, obtener detalle, estado actual
- **Milestones** — ver progreso, fechas, criterios de exito
- **Tareas** — listar, filtrar por status/milestone/prioridad, transicionar
- **Repositorio** — acceso a GitLab, branches, pipelines, MRs
- **Workflow** — kanban board, batch transitions, estado del agente
- **SDD Sessions** — Solution Design Documents del proyecto

---

## Archivos de experiencia

Se descargan durante INIT al `.teamx/` del proyecto. Modificables por proyecto sin tocar el kernel.

| Archivo | Proposito |
|---------|-----------|
| `work_types.yaml` | Registro de tipos de trabajo: prefixes, variantes de flujo, requerimientos de evidencia |
| `persona.yaml` | Identidad de AgenteX: valores, candor policy, narrative compression, social rules |
| `modes.yaml` | 4 modos de interaccion con triggers, comportamiento y ejemplos |
| `rituals.yaml` | Rituales de comunicacion por cada gate (incluyendo CLASSIFY, PLAN, RETROSPECTIVE) |
| `voice.md` | 8 tipos de mensaje, ejemplos buenos/malos, anti-patterns |

---

## Backward compatibility

State machine v3 es backward-compatible con v2:
- `migrate_state()` en state.sh llena defaults para campos nuevos
- Directorios `.teamx/` existentes siguen funcionando
- CLASSIFY solo se aplica a tareas nuevas, no a tareas en progreso
- Scripts nuevos (handoff.sh, health.sh, lessons.sh) fallan gracefully si no estan presentes

---

## Contribuir al devkit

PRs bienvenidos en `https://github.com/teamx-agency/devkit`.

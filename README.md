# TeamX Dev Kit

Setup en **< 2 minutos** para cualquier dev que se una a TeamX. Instala el MCP de la agencia y los comandos personalizados en todos los AI coding tools compatibles.

## Instalación rápida

**macOS / Linux:**
```bash
curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/teamx-agency/devkit/main/install.ps1 | iex
```

---

## Tools soportadas

| Tool | MCP | Comandos personalizados | Config path |
|------|-----|------------------------|-------------|
| Claude Code | ✅ | ✅ `/teamx-dev` | `~/.claude/claude.json` |
| Google Antigravity | ✅ | ✅ `AGENTS.md` | `~/.gemini/antigravity/mcp_config.json` |
| OpenCode | ✅ | ✅ `.opencode/commands/` | `~/.config/opencode/opencode.json` |
| Codex CLI | ✅ | — | `~/.codex/config.toml` |
| Crush | ✅ | — | `~/.config/crush/config.toml` |

---

## Estructura del repo

```
teamx-devkit/
├── install.sh                        ← Entry point macOS/Linux
├── install.ps1                       ← Entry point Windows
├── configs/
│   ├── claude/
│   │   ├── claude.json               ← MCP global para Claude Code
│   │   └── commands/
│   │       ├── teamx-dev.md          ← Comando /teamx-dev (context loader)
│   │       ├── teamx-dev-v2.md       ← Comando /teamx-dev-v2 (state machine)
│   │       └── teamx-status.md       ← Comando /teamx-status
│   ├── antigravity/
│   │   ├── mcp_config.json           ← MCP para Antigravity
│   │   └── AGENTS.md                 ← Instrucciones de agente globales
│   ├── opencode/
│   │   └── opencode.json             ← MCP + comandos para OpenCode
│   ├── codex/
│   │   └── config.toml               ← MCP para Codex CLI
│   └── crush/
│       └── config.toml               ← MCP para Crush
├── teamx-lib/                        ← Scripts para state machine (per-project)
│   ├── state.sh                      ← Funciones de estado determinísticas
│   ├── verify.sh                     ← VERIFY gate (corre CI checks sin LLM)
│   └── init.sh                       ← Parsea .gitlab-ci.yml → ci-profile.json
└── project-templates/
    ├── .mcp.json                     ← MCP a nivel proyecto (Claude Code)
    ├── opencode.json                 ← MCP a nivel proyecto (OpenCode)
    └── AGENTS.md                     ← Instrucciones proyecto (Antigravity)
```

---

## Setup manual (sin script)

Si prefieres hacerlo a mano, copia el archivo correspondiente a tu tool:

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

Agrega los templates al root del repo del proyecto para que el MCP se active automáticamente:

```bash
cp project-templates/.mcp.json .          # Claude Code
cp project-templates/opencode.json .       # OpenCode
cp project-templates/AGENTS.md .          # Antigravity
```

Estos archivos ya están en el `.gitignore` de cada template de proyecto TeamX.

---

## Comandos disponibles

### `/teamx-dev` — Context Loader
Carga el contexto de un proyecto y muestra resumen para que elijas qué trabajar.

```
/teamx-dev PRJ-001
```

### `/teamx-dev-v2` — State Machine (recomendado)
Ciclo autónomo con **state machine persistente** y **quality gates** determinísticos.

```
/teamx-dev-v2 PRJ-001
```

**Características:**
- Estado persistente en `.teamx/state.json` — sobrevive resets de contexto
- VERIFY gate determinístico — bash script corre CI checks sin LLM
- Quality gates HARD — no puede commitear sin verificación
- Resume automático — lee el state file y continúa donde quedó
- Journal de evidencia — `.teamx/journal/task-{uuid}.json`

**Primera ejecución:** Crea `.teamx/` en el repo del proyecto con scripts y state.
**Ejecuciones siguientes:** Lee state, ejecuta el gate actual, avanza.

**Gates:**
```
INIT → SELECT → IMPLEMENT → VERIFY → COMMIT → PUSH → MR → PIPELINE → MERGE → EVIDENCE → SELECT
```

### `/teamx-status` — Quick Status
Muestra estado rápido del proyecto sin modificar nada.

---

## MCP TeamX — herramientas disponibles

El MCP de la agencia expone las siguientes herramientas al LLM:

- **Proyectos** — listar, obtener detalle, estado actual
- **Milestones** — ver progreso, fechas, criterios de éxito  
- **Tareas** — listar, filtrar por status/milestone/prioridad, transicionar
- **Repositorio** — acceso a GitLab, branches, pipelines, MRs
- **Workflow** — kanban board, batch transitions, estado del agente
- **SDD Sessions** — Solution Design Documents del proyecto

---

## Contribuir al devkit

PRs bienvenidos en `https://github.com/teamx-agency/devkit`.  
Para actualizar el MCP URL o agregar un tool nuevo, edita `configs/shared/mcp-url.txt` y corre `./scripts/sync-configs.sh`.

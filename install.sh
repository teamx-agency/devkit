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
DEVKIT_BASE="https://raw.githubusercontent.com/teamx-agency/devkit/main"
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

fetch() {
  local url="$1" dest="$2"
  if command -v curl &>/dev/null; then
    curl -sSL "$url" -o "$dest"
  elif command -v wget &>/dev/null; then
    wget -qO "$dest" "$url"
  else
    err "curl o wget requeridos"
    exit 1
  fi
}

json_merge_mcp() {
  # Agrega o actualiza el MCP de TeamX en un JSON existente de forma segura
  local file="$1"
  if command -v jq &>/dev/null && [ -f "$file" ]; then
    jq --arg url "$MCP_URL" \
      '.mcpServers.teamx = {"type": "url", "url": $url}' \
      "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
  fi
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
    fetch "$DEVKIT_BASE/configs/claude/claude.json" "$CLAUDE_CFG"
    ok "Claude Code — claude.json creado"
  fi

  # Comandos personalizados
  fetch "$DEVKIT_BASE/configs/claude/commands/teamx-dev.md"    "$CLAUDE_CMD_DIR/teamx-dev.md"
  fetch "$DEVKIT_BASE/configs/claude/commands/teamx-dev-v2.md" "$CLAUDE_CMD_DIR/teamx-dev-v2.md"
  fetch "$DEVKIT_BASE/configs/claude/commands/teamx-status.md" "$CLAUDE_CMD_DIR/teamx-status.md"
  ok "Claude Code — comandos /teamx-dev, /teamx-dev-v2, /teamx-status instalados"
else
  skip "Claude Code"
fi

echo ""

# ── Google Antigravity ────────────────────────────────────────────────────────
# Antigravity crea ~/.gemini/antigravity/ al primer lanzamiento.
# Si el directorio no existe aún, lo creamos igualmente para pre-configurar.
log "Google Antigravity → instalando..."

ANTIGRAVITY_DIR="$HOME/.gemini/antigravity"
mkdir -p "$ANTIGRAVITY_DIR"
fetch "$DEVKIT_BASE/configs/antigravity/mcp_config.json" "$ANTIGRAVITY_DIR/mcp_config.json"
ok "Antigravity — mcp_config.json instalado en ~/.gemini/antigravity/"

# AGENTS.md global (home dir, leído automáticamente por Antigravity)
fetch "$DEVKIT_BASE/configs/antigravity/AGENTS.md" "$HOME/AGENTS.md"
ok "Antigravity — AGENTS.md global instalado en ~/"

echo ""

# ── OpenCode ──────────────────────────────────────────────────────────────────
if [ "$HAS_OPENCODE" = "1" ]; then
  log "OpenCode → instalando..."

  OPENCODE_DIR="$HOME/.config/opencode"
  OPENCODE_CFG="$OPENCODE_DIR/opencode.json"
  mkdir -p "$OPENCODE_DIR"

  if [ -f "$OPENCODE_CFG" ] && command -v jq &>/dev/null; then
    # Merge del MCP respetando config existente
    jq --arg url "$MCP_URL" \
      '.mcp.teamx = {"type": "remote", "url": $url, "enabled": true}' \
      "$OPENCODE_CFG" > "${OPENCODE_CFG}.tmp" && mv "${OPENCODE_CFG}.tmp" "$OPENCODE_CFG"
    ok "OpenCode — MCP merged en opencode.json existente"
  else
    fetch "$DEVKIT_BASE/configs/opencode/opencode.json" "$OPENCODE_CFG"
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
    # Evitar duplicar si ya existe la entrada
    if ! grep -q "\[mcp_servers.teamx\]" "$CODEX_CFG"; then
      echo "" >> "$CODEX_CFG"
      echo "[mcp_servers.teamx]" >> "$CODEX_CFG"
      echo "url = \"$MCP_URL\"" >> "$CODEX_CFG"
      ok "Codex CLI — MCP appended a config.toml existente"
    else
      ok "Codex CLI — MCP ya configurado, sin cambios"
    fi
  else
    fetch "$DEVKIT_BASE/configs/codex/config.toml" "$CODEX_CFG"
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
    fetch "$DEVKIT_BASE/configs/crush/config.toml" "$CRUSH_CFG"
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
echo -e "  ${TEAMX_YELLOW}¿Primer proyecto?${NC} Agrega al root del repo:"
echo -e "  ${TEAMX_CYAN}cp ~/.claude/commands/../project-templates/.mcp.json .${NC}"
echo ""

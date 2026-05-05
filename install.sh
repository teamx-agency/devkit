#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════╗
# ║      TeamX Dev Kit — install.sh                  ║
# ║      MCP para Antigravity, OpenCode, Crush       ║
# ║                                                  ║
# ║  Para Claude Code: instala via plugin manager    ║
# ║  /plugin → Marketplaces → teamx-agency/devkit    ║
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

# ── Embedded configs ──────────────────────────────────────────────────────────

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
2. **Al completar tareas:** Usar `teamx_transition_task` para actualizar el kanban.
3. **Al crear código:** Seguir los estándares del Medusa Framework.
4. **Para el repositorio:** Usar `gitlab_get_repo_context` antes de cualquier operación de git.

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

write_crush_toml() {
  cat <<'CONF'
# TeamX Dev Kit — Crush config

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
echo -e "${TEAMX_CYAN}║       TeamX Dev Kit — MCP Installer    ║${NC}"
echo -e "${TEAMX_CYAN}╚════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${TEAMX_YELLOW}Claude Code:${NC} instala via plugin manager"
echo -e "  /plugin → Marketplaces → https://github.com/teamx-agency/devkit"
echo ""

# ── Detectar tools instaladas ─────────────────────────────────────────────────
HAS_OPENCODE=$(command -v opencode &>/dev/null && echo 1 || echo 0)
HAS_CODEX=$(command -v codex &>/dev/null && echo 1 || echo 0)
HAS_CRUSH=$(command -v crush &>/dev/null && echo 1 || echo 0)

log "Detectando AI tools instaladas..."
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
  warn "Codex CLI detectado — usa install-codex.sh para MCP + hooks + skills:"
  echo -e "  ${TEAMX_CYAN}curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install-codex.sh | bash${NC}"
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
echo -e "  MCP TeamX activo en las tools detectadas."
echo -e "  Reinicia tu terminal o ejecuta: ${TEAMX_CYAN}source $SHELL_RC${NC}"
echo ""
echo -e "  ${TEAMX_YELLOW}Claude Code:${NC} instala el devkit completo (skills + hooks) via:"
echo -e "  /plugin → Marketplaces → ${TEAMX_CYAN}https://github.com/teamx-agency/devkit${NC}"
echo ""

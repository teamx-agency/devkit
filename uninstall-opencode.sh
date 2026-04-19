#!/usr/bin/env bash
# TeamX DevKit — OpenCode uninstaller
# Usage:
#   bash uninstall-opencode.sh            # conserva .teamx/ (config del proyecto)
#   bash uninstall-opencode.sh --purge    # elimina también .teamx/

set -e

PKG="teamx-devkit"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

TEAMX_CYAN="\033[0;36m"
TEAMX_GREEN="\033[0;32m"
TEAMX_YELLOW="\033[1;33m"
NC="\033[0m"
log()  { echo -e "${TEAMX_CYAN}[teamx]${NC} $1"; }
ok()   { echo -e "${TEAMX_GREEN}  ✓${NC} $1"; }
warn() { echo -e "${TEAMX_YELLOW}  ⚠${NC} $1"; }
skip() { echo -e "  – $1"; }

echo ""
log "TeamX DevKit — OpenCode uninstall"
[ "$PURGE" = "1" ] && log "modo: --purge (elimina .teamx/)"
echo ""

# 1. Quitar el paquete npm
log "Paquete $PKG..."
if [ -f package.json ] && grep -q "\"$PKG\"" package.json; then
  if command -v bun &>/dev/null; then
    bun remove "$PKG" >/dev/null 2>&1 && ok "bun remove $PKG" || warn "bun remove falló"
  elif command -v npm &>/dev/null; then
    npm uninstall "$PKG" >/dev/null 2>&1 && ok "npm uninstall $PKG" || warn "npm uninstall falló"
  else
    warn "bun/npm no detectado — elimina $PKG de package.json manualmente"
  fi
else
  skip "$PKG no está en package.json"
fi

# 2. Limpiar entradas del DevKit en .opencode/opencode.json
OC_CFG=".opencode/opencode.json"
if [ -f "$OC_CFG" ]; then
  if command -v jq &>/dev/null; then
    TMP="${OC_CFG}.uninstall.tmp"
    jq '
      .
      | (if has("plugin") then .plugin |= map(select(. != "teamx-devkit/opencode-plugin")) else . end)
      | (if has("plugin") and (.plugin | length == 0) then del(.plugin) else . end)
      | (if has("instructions") then .instructions |= map(select(. != ".opencode/instructions/teamx-dev.md")) else . end)
      | (if has("instructions") and (.instructions | length == 0) then del(.instructions) else . end)
      | (if has("mcp") then del(.mcp.teamx) else . end)
      | (if has("mcp") and (.mcp | length == 0) then del(.mcp) else . end)
    ' "$OC_CFG" > "$TMP" && mv "$TMP" "$OC_CFG"

    # Si sólo queda $schema, eliminar el archivo
    REMAINING=$(jq 'del(."$schema") | length' "$OC_CFG" 2>/dev/null || echo "1")
    if [ "$REMAINING" = "0" ]; then
      rm -f "$OC_CFG"
      ok "$OC_CFG quedó vacío — eliminado"
    else
      ok "entradas DevKit removidas de $OC_CFG"
    fi
  else
    warn "jq no instalado — edita $OC_CFG manualmente:"
    warn "  quitar \"teamx-devkit/opencode-plugin\" de \"plugin\""
    warn "  quitar \".opencode/instructions/teamx-dev.md\" de \"instructions\""
    warn "  quitar la clave \"mcp.teamx\""
  fi
else
  skip "$OC_CFG no existe"
fi

# 3. Eliminar instrucción teamx-dev.md
if [ -f .opencode/instructions/teamx-dev.md ]; then
  rm -f .opencode/instructions/teamx-dev.md
  ok "removido .opencode/instructions/teamx-dev.md"
fi

# 4. Quitar directorios vacíos
[ -d .opencode/instructions ] && rmdir .opencode/instructions 2>/dev/null && ok "removido .opencode/instructions/" || true
[ -d .opencode ] && rmdir .opencode 2>/dev/null && ok "removido .opencode/ (vacío)" || true

# 5. .teamx/
if [ "$PURGE" = "1" ]; then
  if [ -d .teamx ]; then
    rm -rf .teamx
    ok "purged .teamx/"
  else
    skip ".teamx/ no existe"
  fi
else
  [ -d .teamx ] && log "Conservando .teamx/ (datos del proyecto). Usa --purge para eliminarlo."
fi

echo ""
log "Desinstalación completa."

#!/usr/bin/env bash
# TeamX DevKit — Codex uninstaller
# Usage:
#   bash uninstall-codex.sh
#   bash uninstall-codex.sh --keep-package

set -euo pipefail

PKG="teamx-devkit"
KEEP_PACKAGE=0
[ "${1:-}" = "--keep-package" ] && KEEP_PACKAGE=1

TEAMX_CYAN="\033[0;36m"
TEAMX_GREEN="\033[0;32m"
TEAMX_YELLOW="\033[1;33m"
NC="\033[0m"

log()  { echo -e "${TEAMX_CYAN}[teamx]${NC} $1"; }
ok()   { echo -e "${TEAMX_GREEN}  ✓${NC} $1"; }
warn() { echo -e "${TEAMX_YELLOW}  ⚠${NC} $1"; }
skip() { echo -e "  – $1"; }

CODEX_DIR="$HOME/.codex"
CODEX_CFG="$CODEX_DIR/config.toml"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
SKILLS_DIR="$HOME/.agents/skills"
MANIFEST="$CODEX_DIR/teamx-devkit-install.json"

echo ""
log "TeamX DevKit — Codex uninstall"
echo ""

if [ -f "$CODEX_HOOKS" ]; then
  cp "$CODEX_HOOKS" "$CODEX_HOOKS.bak.$(date +%Y%m%d%H%M%S)"
  CODEX_HOOKS="$CODEX_HOOKS" node <<'NODE'
const fs = require('fs');
const hooksPath = process.env.CODEX_HOOKS;
let data;
try {
  data = JSON.parse(fs.readFileSync(hooksPath, 'utf8'));
} catch {
  process.exit(0);
}
data.hooks = data.hooks || {};
const isTeamXHook = (hook) => {
  const cmd = String(hook?.command || '');
  return cmd.includes('teamx-devkit') ||
    cmd.includes('/scripts/pre-tool-gate.mjs') ||
    cmd.includes('/scripts/post-tool-state.mjs') ||
    cmd.includes('/scripts/session-start.mjs') ||
    cmd.includes('/scripts/stop-guard.mjs');
};
for (const event of Object.keys(data.hooks)) {
  data.hooks[event] = (data.hooks[event] || [])
    .map(group => ({ ...group, hooks: (group.hooks || []).filter(h => !isTeamXHook(h)) }))
    .filter(group => (group.hooks || []).length > 0);
  if (data.hooks[event].length === 0) delete data.hooks[event];
}
fs.writeFileSync(hooksPath, JSON.stringify(data, null, 2) + '\n');
NODE
  ok "hooks TeamX removidos de $CODEX_HOOKS"
else
  skip "$CODEX_HOOKS no existe"
fi

if [ -d "$SKILLS_DIR" ]; then
  found=0
  for skill in "$SKILLS_DIR"/teamx-*; do
    [ -e "$skill" ] || continue
    found=1
    rm -rf "$skill"
    ok "Skill removida: $(basename "$skill")"
  done
  [ "$found" = "0" ] && skip "no hay skills TeamX en $SKILLS_DIR"
else
  skip "$SKILLS_DIR no existe"
fi

if [ -f "$CODEX_CFG" ]; then
  cp "$CODEX_CFG" "$CODEX_CFG.bak.$(date +%Y%m%d%H%M%S)"
  CODEX_CFG="$CODEX_CFG" MANIFEST="$MANIFEST" node <<'NODE'
const fs = require('fs');
const cfg = process.env.CODEX_CFG;
const manifestPath = process.env.MANIFEST;
let text = fs.readFileSync(cfg, 'utf8');
let manifest = {};
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
} catch {}

const lines = text.split(/\r?\n/);
const out = [];
let skippingTeamx = false;
for (const line of lines) {
  if (/^\[mcp_servers\.teamx\]\s*$/.test(line)) {
    skippingTeamx = true;
    continue;
  }
  if (skippingTeamx && /^\[.+\]\s*$/.test(line)) {
    skippingTeamx = false;
  }
  if (skippingTeamx) continue;
  if (manifest?.added?.codex_hooks === true && /^\s*codex_hooks\s*=\s*true\s*$/.test(line)) {
    continue;
  }
  out.push(line);
}
text = out.join('\n').replace(/\n{3,}/g, '\n\n').trimEnd() + '\n';
fs.writeFileSync(cfg, text);
NODE
  ok "config TeamX removida de $CODEX_CFG"
else
  skip "$CODEX_CFG no existe"
fi

rm -f "$MANIFEST"

if [ "$KEEP_PACKAGE" = "0" ]; then
  if command -v npm >/dev/null 2>&1 && npm list -g "$PKG" >/dev/null 2>&1; then
    npm uninstall -g "$PKG" >/dev/null 2>&1 && ok "npm uninstall -g $PKG" || warn "npm uninstall -g $PKG falló"
  else
    skip "$PKG global no detectado por npm"
  fi
else
  log "Conservando paquete global por --keep-package"
fi

echo ""
ok "Codex limpio. Puedes reinstalar con install-codex.sh."

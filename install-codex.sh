#!/usr/bin/env bash
# TeamX DevKit — Codex installer
# Usage:
#   curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install-codex.sh | bash
#   bash install-codex.sh

set -euo pipefail

PKG="teamx-devkit"
MCP_URL="https://teamx.agency/mcp/v1/message"
TEAMX_CYAN="\033[0;36m"
TEAMX_GREEN="\033[0;32m"
TEAMX_YELLOW="\033[1;33m"
TEAMX_RED="\033[0;31m"
NC="\033[0m"

log()  { echo -e "${TEAMX_CYAN}[teamx]${NC} $1"; }
ok()   { echo -e "${TEAMX_GREEN}  ✓${NC} $1"; }
warn() { echo -e "${TEAMX_YELLOW}  ⚠${NC} $1"; }
err()  { echo -e "${TEAMX_RED}  ✗${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_DIR="$HOME/.codex"
CODEX_CFG="$CODEX_DIR/config.toml"
CODEX_HOOKS="$CODEX_DIR/hooks.json"
SKILLS_DIR="$HOME/.agents/skills"
MANIFEST="$CODEX_DIR/teamx-devkit-install.json"

echo ""
log "TeamX DevKit — Codex setup"
echo ""

if ! command -v codex >/dev/null 2>&1; then
  warn "Codex CLI no detectado. Se instalará la configuración para cuando Codex esté disponible."
fi

if [ -z "${TEAMX_DEVKIT_ROOT:-}" ]; then
  if [ -f "$SCRIPT_DIR/package.json" ] && grep -q '"name": "teamx-devkit"' "$SCRIPT_DIR/package.json"; then
    TEAMX_DEVKIT_ROOT="$SCRIPT_DIR"
  else
    if command -v npm >/dev/null 2>&1; then
      log "Instalando/actualizando $PKG globalmente con npm..."
      npm install -g "$PKG"
      TEAMX_DEVKIT_ROOT="$(npm root -g)/$PKG"
    elif command -v bun >/dev/null 2>&1; then
      log "Instalando/actualizando $PKG globalmente con bun..."
      bun add -g "$PKG"
      TEAMX_DEVKIT_ROOT="${BUN_INSTALL:-$HOME/.bun}/install/global/node_modules/$PKG"
    else
      err "npm o bun requerido para instalar $PKG"
      exit 1
    fi
  fi
fi

if [ ! -d "$TEAMX_DEVKIT_ROOT" ]; then
  err "No pude resolver TEAMX_DEVKIT_ROOT: $TEAMX_DEVKIT_ROOT"
  exit 1
fi
ok "DevKit root: $TEAMX_DEVKIT_ROOT"

mkdir -p "$CODEX_DIR" "$SKILLS_DIR"

if [ -f "$CODEX_CFG" ]; then
  cp "$CODEX_CFG" "$CODEX_CFG.bak.$(date +%Y%m%d%H%M%S)"
fi
if [ -f "$CODEX_HOOKS" ]; then
  cp "$CODEX_HOOKS" "$CODEX_HOOKS.bak.$(date +%Y%m%d%H%M%S)"
fi

TEAMX_DEVKIT_ROOT="$TEAMX_DEVKIT_ROOT" MCP_URL="$MCP_URL" CODEX_CFG="$CODEX_CFG" MANIFEST="$MANIFEST" node <<'NODE'
const fs = require('fs');
const cfg = process.env.CODEX_CFG;
const manifestPath = process.env.MANIFEST;
const mcpUrl = process.env.MCP_URL;
let text = fs.existsSync(cfg) ? fs.readFileSync(cfg, 'utf8') : '';
let previous = {};
try {
  previous = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
} catch {}
const added = { codex_hooks: false, mcp_teamx: false };

if (!/^\[features\]\s*$/m.test(text)) {
  text = text.trimEnd() + (text.trim() ? '\n\n' : '') + '[features]\ncodex_hooks = true\n';
  added.codex_hooks = true;
} else if (!/^\s*codex_hooks\s*=\s*true\s*$/m.test(text)) {
  text = text.replace(/^\[features\]\s*$/m, '[features]\ncodex_hooks = true');
  added.codex_hooks = true;
}

if (!/^\[mcp_servers\.teamx\]\s*$/m.test(text)) {
  text = text.trimEnd() + `\n\n[mcp_servers.teamx]\nurl = "${mcpUrl}"\n`;
  added.mcp_teamx = true;
}

fs.writeFileSync(cfg, text.trimEnd() + '\n');
fs.writeFileSync(manifestPath, JSON.stringify({
  installed_at: new Date().toISOString(),
  teamx_devkit_root: process.env.TEAMX_DEVKIT_ROOT,
  added: {
    codex_hooks: previous?.added?.codex_hooks === true || added.codex_hooks,
    mcp_teamx: previous?.added?.mcp_teamx === true || added.mcp_teamx,
  },
}, null, 2) + '\n');
NODE
ok "Codex config actualizado: $CODEX_CFG"

TEAMX_DEVKIT_ROOT="$TEAMX_DEVKIT_ROOT" CODEX_HOOKS="$CODEX_HOOKS" node <<'NODE'
const fs = require('fs');
const hooksPath = process.env.CODEX_HOOKS;
const root = process.env.TEAMX_DEVKIT_ROOT;
let data = { hooks: {} };
if (fs.existsSync(hooksPath)) {
  try {
    data = JSON.parse(fs.readFileSync(hooksPath, 'utf8'));
  } catch {
    data = { hooks: {} };
  }
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

const command = (script) => `node "${root}/scripts/run.cjs" "${root}/scripts/${script}"`;
const add = (event, matcher, script, statusMessage, timeout) => {
  data.hooks[event] = data.hooks[event] || [];
  data.hooks[event].push({
    matcher,
    hooks: [{ type: 'command', command: command(script), timeout, statusMessage }],
  });
};

add('SessionStart', 'startup|resume|clear', 'session-start.mjs', 'Restoring TeamX state', 5);
add('PreToolUse', '*', 'pre-tool-gate.mjs', 'Checking TeamX gate', 3);
add('PostToolUse', '*', 'post-tool-state.mjs', 'Refreshing TeamX state', 3);
add('Stop', '*', 'stop-guard.mjs', 'Checking TeamX handoff', 5);

fs.writeFileSync(hooksPath, JSON.stringify(data, null, 2) + '\n');
NODE
ok "Codex hooks actualizados: $CODEX_HOOKS"

for skill in "$TEAMX_DEVKIT_ROOT"/skills/teamx-*; do
  [ -d "$skill" ] || continue
  name="$(basename "$skill")"
  target="$SKILLS_DIR/$name"
  rm -rf "$target"
  if ln -s "$skill" "$target" 2>/dev/null; then
    ok "Skill instalada: $name → $skill"
  else
    mkdir -p "$target"
    cp -R "$skill"/. "$target"/
    ok "Skill copiada: $name"
  fi
done

CODEX_AGENTS="$CODEX_DIR/AGENTS.md"
AGENTS_SRC="$TEAMX_DEVKIT_ROOT/configs/codex/AGENTS.md"
if [ -f "$AGENTS_SRC" ]; then
  cp "$AGENTS_SRC" "$CODEX_AGENTS"
  ok "Codex baseline: $CODEX_AGENTS"
fi

echo ""
ok "Codex listo. Reinicia Codex y usa \$teamx-status o \$teamx-dev PRJ-XXX."

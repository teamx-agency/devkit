#!/usr/bin/env bash
# TeamX DevKit — OpenCode installer
# Usage: curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install-opencode.sh | bash

set -e

BASE="https://raw.githubusercontent.com/teamx-agency/devkit/main"
PKG="teamx-devkit"

echo "TeamX DevKit — OpenCode setup (v2.2+)"

# Install package (brings teamx-lib/, skills/, configs/ into node_modules/$PKG).
if command -v bun &>/dev/null; then
  bun add "$PKG"
elif command -v npm &>/dev/null; then
  npm install "$PKG"
else
  echo "Error: bun or npm required" && exit 1
fi

# OpenCode workspace
mkdir -p .opencode/instructions

curl -sSL "$BASE/configs/opencode/opencode.json" -o .opencode/opencode.json
curl -sSL "$BASE/configs/opencode/instructions/teamx-dev.md" -o .opencode/instructions/teamx-dev.md

# TeamX workspace — the OpenCode session hook expects .teamx/ to exist in the
# target project. We seed examples so the dev sees where to customize.
mkdir -p .teamx

if [ ! -f .teamx/config.json ] && [ -f node_modules/$PKG/teamx-lib/config.example.json ]; then
  cp node_modules/$PKG/teamx-lib/config.example.json .teamx/config.example.json
  echo "  seeded .teamx/config.example.json (copy to .teamx/config.json to enable branch_strategy=per-feature)"
fi

if [ ! -f .teamx/constitution.md ] && [ -f node_modules/$PKG/teamx-lib/constitution.md ]; then
  # Ship as example only — the session hook auto-loads the agency baseline
  # from node_modules when no project override is present. Rename to
  # constitution.md in this directory to introduce project-specific articles.
  cp node_modules/$PKG/teamx-lib/constitution.md .teamx/constitution.example.md
  echo "  seeded .teamx/constitution.example.md (rename to .teamx/constitution.md to extend the agency baseline)"
fi

VERSION=$(grep '"version"' node_modules/$PKG/package.json 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)".*/\1/')
echo ""
echo "Installed teamx-devkit ${VERSION:-?}"
echo "Next: run 'opencode' — the DevKit plugin loads automatically via teamx-devkit/opencode-plugin."

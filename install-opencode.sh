#!/usr/bin/env bash
# TeamX DevKit — OpenCode installer
# Usage: curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install-opencode.sh | bash

set -e

BASE="https://raw.githubusercontent.com/teamx-agency/devkit/main"
PKG="teamx-devkit"

echo "TeamX DevKit — OpenCode setup"

# Install package
if command -v bun &>/dev/null; then
  bun add "$PKG"
elif command -v npm &>/dev/null; then
  npm install "$PKG"
else
  echo "Error: bun or npm required" && exit 1
fi

# Create dirs
mkdir -p .opencode/instructions

# Download config files
curl -sSL "$BASE/configs/opencode/opencode.json" -o .opencode/opencode.json
curl -sSL "$BASE/configs/opencode/instructions/teamx-dev.md" -o .opencode/instructions/teamx-dev.md

echo "Done. Run: opencode"

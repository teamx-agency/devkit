#!/usr/bin/env bash
# TeamX DevKit — OpenCode installer
# Usage: curl -sSL https://raw.githubusercontent.com/teamx-agency/devkit/main/install-opencode.sh | bash

set -e

BASE="https://raw.githubusercontent.com/teamx-agency/devkit/513c8dc376127b134088e98b78ad9b2188ea87fb"
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
EXPECTED_SHA="2d6d2fbf6282f2782f0d94bad316c3d000873f032bfd98f0f88fd7eb63f3d022"
ACTUAL_SHA=$(sha256sum .opencode/opencode.json | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ERROR: Checksum verification failed for opencode.json — aborting"
  exit 1
fi

curl -sSL "$BASE/configs/opencode/instructions/teamx-dev.md" -o .opencode/instructions/teamx-dev.md
EXPECTED_SHA="a1b291611556675b50ba21a3d6ffd28b5d0d4c67433529d69df7e67723400350"
ACTUAL_SHA=$(sha256sum .opencode/instructions/teamx-dev.md | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ERROR: Checksum verification failed for teamx-dev.md — aborting"
  exit 1
fi

curl -sSL "$BASE/configs/opencode/instructions/teamx-context.md" -o .opencode/instructions/teamx-context.md
EXPECTED_SHA="f4e0f72dcd0782a05ca3be4614877bacddb323e7bbb36427dcb8d2775986e1cc"
ACTUAL_SHA=$(sha256sum .opencode/instructions/teamx-context.md | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ERROR: Checksum verification failed for teamx-context.md — aborting"
  exit 1
fi

curl -sSL "$BASE/configs/opencode/instructions/teamx-lessons.md" -o .opencode/instructions/teamx-lessons.md
EXPECTED_SHA="40204a1a930d3a1a2c3326c816013da0143a4f17c5aebbc533b8edc06d9a4747"
ACTUAL_SHA=$(sha256sum .opencode/instructions/teamx-lessons.md | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ERROR: Checksum verification failed for teamx-lessons.md — aborting"
  exit 1
fi

curl -sSL "$BASE/configs/opencode/instructions/teamx-rollback.md" -o .opencode/instructions/teamx-rollback.md
EXPECTED_SHA="ca658f6b57bb9ec5f66e510450346c4eaa677957ba783325a03133219bb624a8"
ACTUAL_SHA=$(sha256sum .opencode/instructions/teamx-rollback.md | cut -d' ' -f1)
if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
  echo "ERROR: Checksum verification failed for teamx-rollback.md — aborting"
  exit 1
fi

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

#!/bin/bash
# =============================================================================
# TeamX Dev — INIT Gate (Parse CI profile from .gitlab-ci.yml)
# =============================================================================
# Extracts CI check commands from the project's .gitlab-ci.yml and writes
# ci-profile.json. This is deterministic and doesn't need the LLM.
#
# Usage: bash .teamx/lib/init.sh <repo_path>
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEAMX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CI_PROFILE="${TEAMX_DIR}/ci-profile.json"

REPO_PATH="${1:?Usage: init.sh <repo_path>}"

if [ ! -d "$REPO_PATH" ]; then
    echo "ERROR: Repository not found at $REPO_PATH"
    exit 1
fi

CI_FILE="${REPO_PATH}/.gitlab-ci.yml"

echo "═══════════════════════════════════════════════════════"
echo "  INIT — Parsing CI profile"
echo "═══════════════════════════════════════════════════════"

if [ ! -f "$CI_FILE" ]; then
    echo "WARNING: No .gitlab-ci.yml found. Creating minimal CI profile."
    cat > "$CI_PROFILE" << 'EOF'
{
  "generated_from": "none",
  "generated_at": "",
  "checks": []
}
EOF
    echo "  CI profile: $CI_PROFILE (empty)"
    exit 0
fi

# Parse CI checks using pattern matching on common CI patterns.
# This is intentionally simple and handles the most common cases.
# For complex CI configs, the LLM can manually adjust ci-profile.json.

CHECKS="[]"

# Detect PHP CS Fixer
if grep -q "php-cs-fixer" "$CI_FILE"; then
    CMD=$(grep -oP 'vendor/bin/php-cs-fixer\s+fix[^\n]*' "$CI_FILE" | head -1 | xargs)
    [ -z "$CMD" ] && CMD="vendor/bin/php-cs-fixer fix --dry-run --diff"
    CHECKS=$(echo "$CHECKS" | jq --arg cmd "$CMD" '. + [{"name": "php-cs-fixer", "command": $cmd, "stage": "lint"}]')
fi

# Detect PHPStan
if grep -q "phpstan" "$CI_FILE"; then
    CMD=$(grep -oP 'vendor/bin/phpstan\s+analyse[^\n]*' "$CI_FILE" | head -1 | xargs)
    [ -z "$CMD" ] && CMD="vendor/bin/phpstan analyse --no-progress --memory-limit=512M"
    CHECKS=$(echo "$CHECKS" | jq --arg cmd "$CMD" '. + [{"name": "phpstan", "command": $cmd, "stage": "analyse"}]')
fi

# Detect PHPUnit
if grep -q "phpunit" "$CI_FILE"; then
    CHECKS=$(echo "$CHECKS" | jq '. + [{"name": "phpunit", "command": "vendor/bin/phpunit", "stage": "test"}]')
fi

# Detect npm build
if grep -q "npm run build" "$CI_FILE"; then
    CHECKS=$(echo "$CHECKS" | jq '. + [{"name": "npm-build", "command": "npm run build", "stage": "build"}]')
fi

# Detect npm lint
if grep -q "npm run lint" "$CI_FILE"; then
    CHECKS=$(echo "$CHECKS" | jq '. + [{"name": "npm-lint", "command": "npm run lint", "stage": "lint"}]')
fi

# Detect npm test
if grep -q "npm run test" "$CI_FILE" && ! grep -q "npm run test" <<< "$(echo "$CHECKS" | jq -r '.[].command')"; then
    CHECKS=$(echo "$CHECKS" | jq '. + [{"name": "npm-test", "command": "npm run test", "stage": "test"}]')
fi

# Detect composer audit
if grep -q "composer audit" "$CI_FILE"; then
    CHECKS=$(echo "$CHECKS" | jq '. + [{"name": "composer-audit", "command": "composer audit || true", "stage": "build"}]')
fi

# Write ci-profile.json
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq -n --arg src ".gitlab-ci.yml" --arg at "$GENERATED_AT" --argjson checks "$CHECKS" '{
    generated_from: $src,
    generated_at: $at,
    checks: $checks
}' > "$CI_PROFILE"

echo ""
echo "  CI profile written: $CI_PROFILE"
echo "  Checks detected: $(echo "$CHECKS" | jq length)"
echo "$CHECKS" | jq -r '.[] | "    [\(.stage)] \(.name): \(.command)"'
echo ""
echo "═══════════════════════════════════════════════════════"

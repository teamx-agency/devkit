#!/bin/bash
# =============================================================================
# TeamX Dev — INIT Gate (Parse CI profile from .gitlab-ci.yml)
# =============================================================================
# Extracts runnable CI check commands from the project's .gitlab-ci.yml.
# Stack-agnostic: works with PHP, Node.js, Python, Go, Rust, Ruby, Docker, etc.
#
# Strategy:
#   1. Extract all `script:` lines from every job in the YAML
#   2. Filter to commands that represent checks (lint, test, build, audit, etc.)
#   3. Exclude infrastructure/deploy commands (docker push, kubectl apply, etc.)
#   4. Write ci-profile.json — agent reviews and adjusts if needed
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
echo "  INIT — Parsing CI profile (stack-agnostic)"
echo "═══════════════════════════════════════════════════════"

if [ ! -f "$CI_FILE" ]; then
    echo "  WARNING: No .gitlab-ci.yml found. Creating empty CI profile."
    jq -n '{
        generated_from: "none",
        generated_at: "",
        stack_hints: [],
        checks: []
    }' > "$CI_PROFILE"
    echo "  CI profile: $CI_PROFILE (empty — agent will populate manually)"
    exit 0
fi

# =============================================================================
# Step 1: Extract all script: lines from the YAML
# =============================================================================
# Handles both inline (script: command) and list (- command) forms.
# Strips leading whitespace, dashes, and quotes.

ALL_SCRIPTS=$(grep -E '^\s*(script:|[-]\s+)' "$CI_FILE" \
    | grep -v '^\s*script:\s*$' \
    | sed 's/^\s*script:\s*//; s/^\s*-\s*//; s/^["'"'"']//; s/["'"'"']$//' \
    | sed 's/^\s*//; s/\s*$//' \
    | grep -v '^\s*$' \
    | sort -u \
    || true)

# =============================================================================
# Step 2: Classify into CHECK commands vs SKIP commands
# =============================================================================
# CHECK patterns: anything that verifies quality (lint, test, build, audit, etc.)
CHECK_PATTERNS='lint|test|spec|check|audit|analyse|analyze|format|typecheck|type-check|tsc|phpstan|phpunit|php-cs-fixer|rspec|rubocop|mypy|flake8|ruff|black|pylint|pytest|cargo\s+test|cargo\s+clippy|go\s+test|go\s+vet|golangci|vitest|jest|mocha|cypress|playwright|npm\s+run\s+(build|lint|test|check)|yarn\s+(build|lint|test|check)|pnpm\s+(build|lint|test|check)|make\s+(test|lint|build|check)|composer\s+audit|npm\s+audit|yarn\s+audit|snyk'

# SKIP patterns: deploy, infrastructure, notifications, artifacts
SKIP_PATTERNS='docker\s+push|kubectl|helm\s+upgrade|helm\s+install|git\s+push|ssh\s+|scp\s+|rsync\s+|curl\s+.*https?://|wget\s+|slack|notify|telegram|deploy|release|publish|upload|registry|ecr|gcr\.io|\.azurecr\.|apt-get|apk\s+add|yum\s+install|pip\s+install|npm\s+install|yarn\s+install|pnpm\s+install|composer\s+install|bundle\s+install|go\s+mod\s+download|cargo\s+fetch|echo\s+|mkdir\s+|cp\s+|mv\s+|rm\s+|chmod\s+|chown\s+'

CHECKS="[]"

while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Skip lines matching deploy/infra patterns
    if echo "$line" | grep -qiE "$SKIP_PATTERNS"; then
        continue
    fi

    # Include lines matching check patterns
    if echo "$line" | grep -qiE "$CHECK_PATTERNS"; then
        # Derive name from first meaningful token
        NAME=$(echo "$line" | grep -oiE '(php-cs-fixer|phpstan|phpunit|phpcs|jest|vitest|mocha|pytest|rspec|rubocop|mypy|flake8|ruff|black|pylint|golangci|cargo\s+(test|clippy)|go\s+(test|vet)|tsc|eslint|prettier|stylelint|npm\s+run\s+\S+|yarn\s+\S+|pnpm\s+\S+|make\s+\S+|composer\s+audit|npm\s+audit)' \
            | head -1 \
            | tr '[:upper:]' '[:lower:]' \
            | sed 's/\s\+/-/g' \
            | sed 's/vendor\/bin\///' \
            | sed 's/run-//' \
            || true)
        [ -z "$NAME" ] && NAME=$(echo "$line" | awk '{print $1}' | sed 's/.*\///')

        # Derive stage
        STAGE="check"
        echo "$line" | grep -qiE 'lint|format|cs-fixer|phpcs|eslint|stylelint|rubocop|flake8|ruff|black|pylint|clippy|vet|golangci' && STAGE="lint" || true
        echo "$line" | grep -qiE 'test|spec|jest|vitest|mocha|pytest|rspec|phpunit|cypress|playwright|cargo\s+test|go\s+test' && STAGE="test" || true
        echo "$line" | grep -qiE 'build|tsc|compile' && STAGE="build" || true
        echo "$line" | grep -qiE 'audit|snyk|analyse|analyze|phpstan|mypy' && STAGE="analyse" || true

        CHECKS=$(echo "$CHECKS" | jq \
            --arg name "$NAME" \
            --arg cmd  "$line" \
            --arg stage "$STAGE" \
            '. + [{"name": $name, "command": $cmd, "stage": $stage}]')
    fi
done <<< "$ALL_SCRIPTS"

# =============================================================================
# Step 3: Detect stack hints (for agent context)
# =============================================================================
STACK_HINTS="[]"

grep -qiE 'php|composer|laravel|symfony|medusa' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["php"]') || true
grep -qiE 'node|npm|yarn|pnpm|javascript|typescript|next|nuxt|vite' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["node"]') || true
grep -qiE 'python|pip|pytest|django|flask|fastapi' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["python"]') || true
grep -qiE '\bgo\b|golang|golangci' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["go"]') || true
grep -qiE 'rust|cargo' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["rust"]') || true
grep -qiE 'ruby|gem|rspec|rubocop|bundle' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["ruby"]') || true
grep -qiE 'docker' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["docker"]') || true
grep -qiE 'redis' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["redis"]') || true
grep -qiE 'mysql|mariadb|postgres|mongodb' "$CI_FILE" && \
    STACK_HINTS=$(echo "$STACK_HINTS" | jq '. + ["database"]') || true

# =============================================================================
# Step 4: Write ci-profile.json
# =============================================================================
GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date +"%Y-%m-%dT%H:%M:%SZ")

jq -n \
    --arg src ".gitlab-ci.yml" \
    --arg at  "$GENERATED_AT" \
    --argjson stack "$STACK_HINTS" \
    --argjson checks "$CHECKS" \
    '{
        generated_from: $src,
        generated_at: $at,
        stack_hints: $stack,
        checks: $checks,
        note: "Auto-generated. Agent should review and adjust commands if needed."
    }' > "$CI_PROFILE"

COUNT=$(echo "$CHECKS" | jq 'length')

echo ""
echo "  Stack detected:    $(echo "$STACK_HINTS" | jq -r 'join(", ")')"
echo "  Checks extracted:  $COUNT"
echo ""
echo "$CHECKS" | jq -r '.[] | "  [\(.stage)] \(.name)"'
echo ""

if [ "$COUNT" -eq 0 ]; then
    echo "  WARNING: No check commands detected."
    echo "  Review .gitlab-ci.yml and add entries to ci-profile.json manually,"
    echo "  or ask the agent to populate it based on the project stack."
fi

echo "  CI profile: $CI_PROFILE"
echo "═══════════════════════════════════════════════════════"

#!/bin/bash
# =============================================================================
# TeamX Dev — VERIFY Gate (Fully Deterministic)
# =============================================================================
# Runs all CI checks from ci-profile.json, captures results, writes to state.
# Returns 0 if ALL pass, 1 if ANY fail.
# NO LLM involvement — pure bash.
#
# Usage: bash .teamx/lib/verify.sh [repo_path]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/state.sh"

REPO_PATH="${1:-$(read_repo_path)}"

if [ -z "$REPO_PATH" ] || [ ! -d "$REPO_PATH" ]; then
    echo "ERROR: Repository path not found: $REPO_PATH"
    exit 1
fi

if [ ! -f "$CI_PROFILE" ]; then
    echo "ERROR: CI profile not found at $CI_PROFILE"
    echo "Run INIT gate first."
    exit 1
fi

cd "$REPO_PATH"

echo "═══════════════════════════════════════════════════════"
echo "  VERIFY GATE — Running CI checks locally"
echo "═══════════════════════════════════════════════════════"
echo ""

ALL_PASS=true
RESULTS=""

# Read each check from ci-profile.json
while IFS= read -r check; do
    name=$(echo "$check" | jq -r '.name')
    command=$(echo "$check" | jq -r '.command')
    stage=$(echo "$check" | jq -r '.stage')

    echo "──────────────────────────────────────────────────────"
    echo "  [$stage] $name"
    echo "  $ $command"
    echo "──────────────────────────────────────────────────────"

    # Run the command, capture output and exit code
    set +e
    OUTPUT=$(eval "$command" 2>&1)
    EXIT_CODE=$?
    set -e

    # Extract summary (last meaningful line)
    SUMMARY=$(echo "$OUTPUT" | grep -E "OK|error|Error|FAIL|fail|success|compiled|written|Found [0-9]" | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | xargs)
    [ -z "$SUMMARY" ] && SUMMARY=$(echo "$OUTPUT" | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | xargs)

    if [ $EXIT_CODE -eq 0 ]; then
        STATUS="pass"
        echo "  ✓ PASS — $SUMMARY"
    else
        STATUS="fail"
        ALL_PASS=false
        echo "  ✗ FAIL (exit $EXIT_CODE) — $SUMMARY"
    fi

    # Write result to state.json
    set_verification "$name" "$STATUS" "$SUMMARY"

    echo ""
done < <(jq -c '.checks[]' "$CI_PROFILE")

echo "═══════════════════════════════════════════════════════"
if $ALL_PASS; then
    echo "  ✓ ALL CHECKS PASSED — Ready to commit"
    set_gate "COMMIT"
    exit 0
else
    echo "  ✗ VERIFICATION FAILED — Fix issues and re-run"
    echo "  Gate stays at VERIFY"
    exit 1
fi

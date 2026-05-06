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

# =============================================================================
# Gap #3 — Validate ci-profile minimum quality before running
# =============================================================================

CI_CHECK_COUNT=$(jq '.checks | length' "$CI_PROFILE" 2>/dev/null || echo 0)
HAS_TEST_CHECK=$(jq -r '[.checks[] | select(.stage | test("test"; "i")) or (.name | test("test"; "i"))] | length' "$CI_PROFILE" 2>/dev/null || echo 0)

echo "═══════════════════════════════════════════════════════"
echo "  VERIFY GATE — Running CI checks locally"
echo "═══════════════════════════════════════════════════════"

# Fatal: empty ci-profile must not pass VERIFY
if [ "$CI_CHECK_COUNT" -eq 0 ]; then
    echo ""
    echo "  FATAL: ci-profile has no checks. VERIFY cannot pass with an empty profile."
    echo "  Fix: run init.sh again after adding .gitlab-ci.yml, or inject a bootstrap template."
    exit 1
fi

# Warn if ci-profile doesn't meet minimum quality standards
CI_PROFILE_WARNINGS=false
if [ "$CI_CHECK_COUNT" -lt 2 ]; then
    echo ""
    echo "  ⚠ QA WARNING: ci-profile has only ${CI_CHECK_COUNT} check(s)."
    echo "    Minimum recommended: 2 checks (lint + tests)."
    echo "    A trivial ci-profile can make all VERIFY gates pass with no real validation."
    CI_PROFILE_WARNINGS=true
fi
if [ "$HAS_TEST_CHECK" -eq 0 ]; then
    echo ""
    echo "  ⚠ QA WARNING: ci-profile has no check with stage/name containing 'test'."
    echo "    Add at least one test check to prevent untested code from reaching MERGE."
    CI_PROFILE_WARNINGS=true
fi
if $CI_PROFILE_WARNINGS; then
    echo ""
    echo "  Proceeding with existing checks — fix ci-profile to eliminate this warning."
fi
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
    SUMMARY=$(echo "$OUTPUT" | grep -E "OK|error|Error|FAIL|fail|success|compiled|written|Found [0-9]|pass|Pass|suites" | tail -1 | sed 's/\x1b\[[0-9;]*m//g' | xargs || true)
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

#!/bin/bash
# =============================================================================
# TeamX Dev — Project Health Check (Local)
# =============================================================================
# Runs local health checks from state.json and journal data.
# MCP-based checks (pipelines, tasks without criteria) are done by the LLM.
# This script handles what can be checked deterministically.
#
# Usage: bash .teamx/lib/health.sh
# Output: JSON report to stdout
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/state.sh"

if ! state_exists; then
    echo '{"error": "No state.json found"}'
    exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo "  HEALTH CHECK — Local diagnostics"
echo "═══════════════════════════════════════════════════════"
echo ""

ISSUES="[]"
SEVERITY_CRITICAL=0
SEVERITY_WARN=0
SEVERITY_INFO=0

# Check 1: State staleness
LAST_SYNC=$(jq -r '.last_sync // ""' "$STATE_FILE")
if [ -n "$LAST_SYNC" ]; then
    SYNC_EPOCH=$(date -d "$LAST_SYNC" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_SYNC" +%s 2>/dev/null || echo 0)
    NOW_EPOCH=$(date +%s)
    DAYS_STALE=$(( (NOW_EPOCH - SYNC_EPOCH) / 86400 ))
    if [ "$DAYS_STALE" -gt 7 ]; then
        ISSUES=$(echo "$ISSUES" | jq --arg d "$DAYS_STALE" '. + [{"severity": "WARN", "check": "state_staleness", "message": "State last synced \($d) days ago"}]')
        SEVERITY_WARN=$((SEVERITY_WARN + 1))
    fi
fi

# Check 2: Task in progress too long
if [ "$(read_current_task_uuid)" != "" ]; then
    STARTED=$(jq -r '.current_task.started_at // ""' "$STATE_FILE")
    if [ -n "$STARTED" ]; then
        START_EPOCH=$(date -d "$STARTED" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED" +%s 2>/dev/null || echo 0)
        NOW_EPOCH=$(date +%s)
        DAYS_IN_PROGRESS=$(( (NOW_EPOCH - START_EPOCH) / 86400 ))
        if [ "$DAYS_IN_PROGRESS" -gt 3 ]; then
            ISSUES=$(echo "$ISSUES" | jq --arg d "$DAYS_IN_PROGRESS" --arg t "$(read_current_task_title)" '. + [{"severity": "WARN", "check": "task_duration", "message": "Task \"\($t)\" in progress for \($d) days"}]')
            SEVERITY_WARN=$((SEVERITY_WARN + 1))
        fi
    fi
fi

# Check 3: Handoff pending
if handoff_exists; then
    ISSUES=$(echo "$ISSUES" | jq '. + [{"severity": "INFO", "check": "pending_handoff", "message": "Handoff document exists — previous session was interrupted"}]')
    SEVERITY_INFO=$((SEVERITY_INFO + 1))
fi

# Check 4: Journal completeness
COMPLETED_COUNT=$(jq '.completed_tasks | length' "$STATE_FILE")
JOURNAL_COUNT=$(find "$JOURNAL_DIR" -name "task-*.json" 2>/dev/null | wc -l | tr -d ' ')
if [ "$COMPLETED_COUNT" -gt "$JOURNAL_COUNT" ]; then
    MISSING=$((COMPLETED_COUNT - JOURNAL_COUNT))
    ISSUES=$(echo "$ISSUES" | jq --arg m "$MISSING" '. + [{"severity": "WARN", "check": "journal_gaps", "message": "\($m) completed tasks missing journal entries"}]')
    SEVERITY_WARN=$((SEVERITY_WARN + 1))
fi

# Check 5: CI profile exists
if [ ! -f "$CI_PROFILE" ]; then
    ISSUES=$(echo "$ISSUES" | jq '. + [{"severity": "CRITICAL", "check": "no_ci_profile", "message": "No ci-profile.json — VERIFY gate cannot function"}]')
    SEVERITY_CRITICAL=$((SEVERITY_CRITICAL + 1))
elif [ "$(jq '.checks | length' "$CI_PROFILE")" -eq 0 ]; then
    ISSUES=$(echo "$ISSUES" | jq '. + [{"severity": "WARN", "check": "empty_ci_profile", "message": "ci-profile.json has no checks defined"}]')
    SEVERITY_WARN=$((SEVERITY_WARN + 1))
fi

# Check 6: State version
CURRENT_VERSION=$(jq -r '.state_version // 2' "$STATE_FILE")
if [ "$CURRENT_VERSION" -lt "$STATE_VERSION" ]; then
    ISSUES=$(echo "$ISSUES" | jq --arg v "$CURRENT_VERSION" --arg t "$STATE_VERSION" '. + [{"severity": "INFO", "check": "state_version", "message": "State is v\($v), current is v\($t) — run migrate_state"}]')
    SEVERITY_INFO=$((SEVERITY_INFO + 1))
fi

# Determine overall score
SCORE="GREEN"
[ "$SEVERITY_WARN" -gt 0 ] && SCORE="YELLOW"
[ "$SEVERITY_CRITICAL" -gt 0 ] && SCORE="RED"

# Output report
REPORT=$(jq -n \
    --arg score "$SCORE" \
    --argjson critical "$SEVERITY_CRITICAL" \
    --argjson warn "$SEVERITY_WARN" \
    --argjson info "$SEVERITY_INFO" \
    --argjson issues "$ISSUES" \
    --arg project "$(read_project_code)" \
    --arg gate "$(read_gate)" \
    '{
        project: $project,
        current_gate: $gate,
        score: $score,
        summary: {critical: $critical, warn: $warn, info: $info},
        issues: $issues
    }')

echo "$REPORT" | jq .

echo ""
echo "  Score: $SCORE (critical=$SEVERITY_CRITICAL warn=$SEVERITY_WARN info=$SEVERITY_INFO)"
echo "═══════════════════════════════════════════════════════"

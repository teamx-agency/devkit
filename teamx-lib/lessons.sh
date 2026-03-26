#!/bin/bash
# =============================================================================
# TeamX Dev — Lessons Extraction
# =============================================================================
# Analyzes journal data from completed tasks to extract operational patterns.
# Writes lessons.json for the agent to read during INIT.
#
# Usage: bash .teamx/lib/lessons.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/state.sh"

LESSONS_FILE="${TEAMX_DIR}/lessons.json"

echo "═══════════════════════════════════════════════════════"
echo "  LESSONS — Analyzing journal data"
echo "═══════════════════════════════════════════════════════"
echo ""

JOURNAL_FILES=$(find "$JOURNAL_DIR" -name "task-*.json" 2>/dev/null | sort)
TASK_COUNT=$(echo "$JOURNAL_FILES" | grep -c "task-" 2>/dev/null || echo 0)

if [ "$TASK_COUNT" -eq 0 ]; then
    echo "  No journal entries found. Nothing to analyze."
    jq -n '{
        analyzed_at: (now | todate),
        task_count: 0,
        patterns: []
    }' > "$LESSONS_FILE"
    exit 0
fi

echo "  Analyzing $TASK_COUNT journal entries..."

# Aggregate all journal files into a single array
ALL_JOURNALS=$(jq -s '.' $JOURNAL_FILES)

# Extract most-failed checks
FAILED_CHECKS=$(echo "$ALL_JOURNALS" | jq '
    [.[].verification | to_entries[]? | select(.value.status == "fail")] |
    group_by(.key) |
    map({name: .[0].key, fail_count: length}) |
    sort_by(-.fail_count) |
    .[0:5]
')

# Extract work type distribution
TYPE_DISTRIBUTION=$(echo "$ALL_JOURNALS" | jq '
    group_by(.work_type // "feature") |
    map({type: .[0].work_type // "feature", count: length}) |
    sort_by(-.count)
')

# Extract hot files (most changed across tasks)
HOT_FILES=$(echo "$ALL_JOURNALS" | jq '
    [.[].branch // empty] |
    if length > 0 then
        "Branches: " + (length | tostring) + " tasks analyzed"
    else
        "No branch data available"
    end
' -r)

# Calculate average task duration (if timestamps available)
AVG_DURATION=$(echo "$ALL_JOURNALS" | jq '
    [.[] | select(.started_at != null and .completed_at != null) |
        (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601)
    ] |
    if length > 0 then
        (add / length / 3600) | floor | tostring + " hours"
    else
        "unknown"
    end
' -r)

# Build lessons.json
jq -n \
    --argjson failed_checks "$FAILED_CHECKS" \
    --argjson type_distribution "$TYPE_DISTRIBUTION" \
    --arg avg_duration "$AVG_DURATION" \
    --argjson task_count "$TASK_COUNT" \
    '{
        analyzed_at: (now | todate),
        task_count: $task_count,
        avg_task_duration: $avg_duration,
        most_failed_checks: $failed_checks,
        work_type_distribution: $type_distribution,
        patterns: [
            if ($failed_checks | length) > 0 then
                "Most failed check: " + $failed_checks[0].name + " (" + ($failed_checks[0].fail_count | tostring) + " failures)"
            else empty end,
            "Average task duration: " + $avg_duration,
            "Tasks analyzed: " + ($task_count | tostring)
        ]
    }' > "$LESSONS_FILE"

echo ""
echo "  Lessons written: $LESSONS_FILE"
echo "  Most failed checks: $(echo "$FAILED_CHECKS" | jq -r 'map(.name + "(" + (.fail_count|tostring) + ")") | join(", ")')"
echo "  Avg task duration: $AVG_DURATION"
echo "  Work types: $(echo "$TYPE_DISTRIBUTION" | jq -r 'map(.type + "=" + (.count|tostring)) | join(", ")')"
echo ""
echo "═══════════════════════════════════════════════════════"

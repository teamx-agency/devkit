#!/bin/bash
# =============================================================================
# TeamX Dev — Lessons Extraction v2
# =============================================================================
# Analyzes journal data from completed tasks to extract operational patterns,
# detect gate bottlenecks, and generate SDD quality signals.
#
# Writes lessons.json (v2) for the agent to read during INIT.
# The agent should then call teamx_push_lessons() to share with the team.
#
# Usage: bash .teamx/lib/lessons.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/state.sh"

LESSONS_FILE="${TEAMX_DIR}/lessons.json"
PROJECT_CODE=$(read_project_code 2>/dev/null || echo "")

echo "═══════════════════════════════════════════════════════"
echo "  LESSONS v2 — Analyzing journal data"
echo "═══════════════════════════════════════════════════════"
echo ""

readarray -t JOURNAL_ARRAY < <(find "$JOURNAL_DIR" -name "task-*.json" 2>/dev/null | sort)
TASK_COUNT=${#JOURNAL_ARRAY[@]}

if [ "$TASK_COUNT" -eq 0 ]; then
    echo "  No journal entries found. Nothing to analyze."
    jq -n '{
        version: 2,
        project_code: $pc,
        analyzed_at: (now | todate),
        task_count: 0,
        bottlenecks: [],
        sdd_quality_signals: [],
        most_failed_checks: [],
        work_type_distribution: [],
        patterns: []
    }' --arg pc "$PROJECT_CODE" > "$LESSONS_FILE"
    exit 0
fi

echo "  Analyzing $TASK_COUNT journal entries..."

# Aggregate all journal files into a single array
ALL_JOURNALS=$(jq -s '.' "${JOURNAL_ARRAY[@]}")

# ─── Standard metrics (v1 compat) ────────────────────────────────────────────

FAILED_CHECKS=$(echo "$ALL_JOURNALS" | jq '
    [.[].verification | to_entries[]? | select(.value.status == "fail")] |
    group_by(.key) |
    map({name: .[0].key, fail_count: length}) |
    sort_by(-.fail_count) |
    .[0:5]
')

TYPE_DISTRIBUTION=$(echo "$ALL_JOURNALS" | jq '
    group_by(.work_type // "feature") |
    map({type: .[0].work_type // "feature", count: length}) |
    sort_by(-.count)
')

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

# ─── Bottleneck detection (v2 new) ───────────────────────────────────────────
# Reads gate_timestamps from journal if available.
# Thresholds (minutes): PLAN > 90, VERIFY_FAIL > 2 runs, SCOPE_CREEP > 3 unplanned files.

BOTTLENECKS=$(echo "$ALL_JOURNALS" | jq '
    # --- PLAN overtime per work_type ---
    [.[] |
        select(
            (.gate_times // []) |
            map(select(.gate == "PLAN" and .duration_minutes != null)) |
            length > 0
        ) |
        {
            work_type: (.work_type // "feature"),
            plan_minutes: (
                (.gate_times | map(select(.gate == "PLAN" and .duration_minutes != null)) | .[0].duration_minutes) // 0
            )
        }
    ] |
    group_by(.work_type) |
    map(
        {
            work_type: .[0].work_type,
            avg_minutes: ([.[].plan_minutes] | add / length | floor),
            count: length
        } |
        select(.avg_minutes > 90)
    ) |
    map({
        gate: "PLAN",
        work_type: .work_type,
        avg_time_hours: (.avg_minutes / 60 * 10 | floor / 10),
        threshold_hours: 1.5,
        occurrence_count: .count,
        signal: ("PLAN_OVERTIME_" + (.work_type | ascii_upcase)),
        pattern: ("SDD not specific enough for " + .work_type + " tasks — PLAN gate took avg " + (.avg_minutes | tostring) + " min"),
        suggested_sdd_action: ("Add data contracts and explicit API boundaries in SDD for " + .work_type + " tasks"),
        severity: (if .avg_minutes > 180 then "high" elif .avg_minutes > 120 then "medium" else "low" end)
    })
')

# ─── SDD quality signals (derived from bottlenecks + failed checks) ──────────

SDD_SIGNALS=$(echo "$ALL_JOURNALS" | jq --argjson bottlenecks "$BOTTLENECKS" '
    $bottlenecks | map({
        signal: .pattern,
        work_type: .work_type,
        gate: .gate,
        pattern: .signal,
        suggested_action: .suggested_sdd_action,
        severity: .severity,
        frequency: .occurrence_count,
        interpretation: ("SDD improvement needed: " + .suggested_sdd_action)
    })
')

# Also add VERIFY_MULTI_FAIL signal if applicable
VERIFY_SIGNAL=$(echo "$ALL_JOURNALS" | jq '
    [.[] | select(.verification_runs != null) | .verification_runs] |
    if length > 0 then
        (add / length) as $avg |
        if $avg > 2 then [{
            signal: "VERIFY_MULTI_FAIL",
            work_type: "all",
            gate: "VERIFY",
            pattern: ("CI checks fail multiple times per task (avg " + ($avg * 10 | floor / 10 | tostring) + " runs)"),
            suggested_action: "Add explicit edge case scenarios (Given/When/Then) in SDD acceptance criteria",
            severity: "medium",
            frequency: length,
            interpretation: "Tasks require multiple fix cycles before passing CI"
        }] else [] end
    else [] end
')

SDD_SIGNALS=$(echo "$SDD_SIGNALS $VERIFY_SIGNAL" | jq -s 'add // []')

# ─── Improvement #3: Gate cycle time analysis ────────────────────────────────
# Reads gate_times arrays from journal and detects which gates are slowest.

GATE_CYCLE_TIMES=$(echo "$ALL_JOURNALS" | jq '
    [.[].gate_times[]? | select(.duration_minutes != null)] |
    group_by(.gate) |
    map({
        gate: .[0].gate,
        avg_minutes: ([.[].duration_minutes] | add / length | floor),
        max_minutes: ([.[].duration_minutes] | max),
        count: length
    }) |
    sort_by(-.avg_minutes)
')

GATE_BOTTLENECKS=$(echo "$GATE_CYCLE_TIMES" | jq '
    map(select(
        (.gate == "PLAN" and .avg_minutes > 90) or
        (.gate == "IMPLEMENT" and .avg_minutes > 240) or
        (.gate == "VERIFY" and .avg_minutes > 60) or
        (.gate == "REVIEW" and .avg_minutes > 1440)
    )) |
    map({
        gate: .gate,
        avg_minutes: .avg_minutes,
        max_minutes: .max_minutes,
        occurrence_count: .count,
        signal: ("SLOW_GATE_" + .gate),
        pattern: ("Gate " + .gate + " avg " + (.avg_minutes | tostring) + "min — above threshold"),
        suggested_sdd_action: (
            if .gate == "PLAN" then "SDD lacks enough detail — PLAN should not be longer than IMPLEMENT"
            elif .gate == "IMPLEMENT" then "Task scope too large — split into smaller tasks"
            elif .gate == "VERIFY" then "CI failures are frequent — review acceptance criteria clarity"
            elif .gate == "REVIEW" then "QA review is blocking — consider async review protocol"
            else "Review gate process"
            end
        ),
        severity: (if .avg_minutes > 480 then "high" elif .avg_minutes > 180 then "medium" else "low" end)
    })
')

BOTTLENECKS=$(echo "$BOTTLENECKS $GATE_BOTTLENECKS" | jq -s 'add // []')

# ─── Build patterns array ─────────────────────────────────────────────────────

PATTERNS=$(jq -n \
    --argjson failed_checks "$FAILED_CHECKS" \
    --argjson bottlenecks "$BOTTLENECKS" \
    --arg avg_duration "$AVG_DURATION" \
    --argjson task_count "$TASK_COUNT" \
    '[
        if ($failed_checks | length) > 0 then
            "Most failed check: " + $failed_checks[0].name + " (" + ($failed_checks[0].fail_count | tostring) + " failures)"
        else empty end,
        if ($bottlenecks | length) > 0 then
            "BOTTLENECK: " + $bottlenecks[0].work_type + " tasks stall in " + $bottlenecks[0].gate + " (avg " + ($bottlenecks[0].avg_time_hours | tostring) + "h) → " + $bottlenecks[0].suggested_sdd_action
        else empty end,
        "Average task duration: " + $avg_duration,
        "Tasks analyzed: " + ($task_count | tostring)
    ]'
)

# ─── Write lessons.json v2 ────────────────────────────────────────────────────

jq -n \
    --arg version "2" \
    --arg project_code "$PROJECT_CODE" \
    --argjson failed_checks "$FAILED_CHECKS" \
    --argjson type_distribution "$TYPE_DISTRIBUTION" \
    --arg avg_duration "$AVG_DURATION" \
    --argjson task_count "$TASK_COUNT" \
    --argjson bottlenecks "$BOTTLENECKS" \
    --argjson sdd_signals "$SDD_SIGNALS" \
    --argjson patterns "$PATTERNS" \
    --argjson gate_cycle_times "$GATE_CYCLE_TIMES" \
    '{
        version: ($version | tonumber),
        project_code: $project_code,
        analyzed_at: (now | todate),
        task_count: $task_count,
        avg_task_duration: $avg_duration,
        bottlenecks: $bottlenecks,
        sdd_quality_signals: $sdd_signals,
        most_failed_checks: $failed_checks,
        work_type_distribution: $type_distribution,
        gate_cycle_times: $gate_cycle_times,
        patterns: $patterns
    }' > "$LESSONS_FILE"

echo ""
echo "  Lessons written: $LESSONS_FILE"
echo "  Bottlenecks detected: $(echo "$BOTTLENECKS" | jq 'length')"
echo "  SDD quality signals: $(echo "$SDD_SIGNALS" | jq 'length')"
echo "  Most failed checks: $(echo "$FAILED_CHECKS" | jq -r 'map(.name + "(" + (.fail_count|tostring) + ")") | join(", ")')"
echo "  Avg task duration: $AVG_DURATION"
echo "  Work types: $(echo "$TYPE_DISTRIBUTION" | jq -r 'map(.type + "=" + (.count|tostring)) | join(", ")')"
echo "  Gate cycle times: $(echo "$GATE_CYCLE_TIMES" | jq -r 'map(.gate + "=" + (.avg_minutes|tostring) + "m") | join(", ")')"
echo ""
echo "  → Call teamx_push_lessons() to share these patterns with the team."
echo "═══════════════════════════════════════════════════════"

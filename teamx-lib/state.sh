#!/bin/bash
# =============================================================================
# TeamX Dev State Machine — Deterministic State Operations
# =============================================================================
# These functions manipulate .teamx/state.json without LLM involvement.
# They are the source of truth for gate transitions and quality enforcement.
#
# Usage: source .teamx/lib/state.sh
# =============================================================================

set -euo pipefail

# Resolve paths relative to the repo root where .teamx/ lives
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "$0" ] 2>/dev/null; then
    TEAMX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
elif [ -d ".teamx" ]; then
    TEAMX_DIR="$(pwd)/.teamx"
else
    TEAMX_DIR="${TEAMX_DIR:-$(pwd)/.teamx}"
fi
STATE_FILE="${TEAMX_DIR}/state.json"
CI_PROFILE="${TEAMX_DIR}/ci-profile.json"
JOURNAL_DIR="${TEAMX_DIR}/journal"

# =============================================================================
# State reading
# =============================================================================

state_exists() {
    [ -f "$STATE_FILE" ]
}

read_gate() {
    jq -r '.current_gate // "IDLE"' "$STATE_FILE"
}

read_project_code() {
    jq -r '.project_code // ""' "$STATE_FILE"
}

read_current_task_uuid() {
    jq -r '.current_task.uuid // ""' "$STATE_FILE"
}

read_current_task_title() {
    jq -r '.current_task.title // ""' "$STATE_FILE"
}

read_current_branch() {
    jq -r '.current_task.branch // ""' "$STATE_FILE"
}

read_mr_iid() {
    jq -r '.current_task.git.mr_iid // ""' "$STATE_FILE"
}

read_repo_path() {
    jq -r '.repo_path // ""' "$STATE_FILE"
}

# Returns full state as compact JSON (for LLM context injection)
read_state_summary() {
    jq -c '{
        project: .project_code,
        gate: .current_gate,
        milestone: .active_milestone.title,
        milestone_progress: "\(.active_milestone.done_tasks)/\(.active_milestone.total_tasks)",
        task: .current_task.title,
        task_uuid: .current_task.uuid,
        branch: .current_task.branch,
        verification: (.current_task.verification // {}),
        git: (.current_task.git // {}),
        completed: (.completed_tasks | length),
        total: .overall_progress.total
    }' "$STATE_FILE" 2>/dev/null || echo '{"gate":"IDLE"}'
}

# =============================================================================
# State writing
# =============================================================================

set_gate() {
    local gate="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg g "$gate" '.current_gate = $g' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "GATE → $gate"
}

set_last_sync() {
    local tmp
    tmp=$(mktemp)
    jq '.last_sync = (now | todate)' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_current_task() {
    local uuid="$1" title="$2" issue_iid="$3" branch="$4"
    local tmp
    tmp=$(mktemp)
    jq --arg u "$uuid" --arg t "$title" --arg i "$issue_iid" --arg b "$branch" '
        .current_task = {
            uuid: $u,
            title: $t,
            gitlab_issue_iid: ($i | tonumber? // 0),
            branch: $b,
            started_at: (now | todate),
            acceptance_criteria: [],
            verification: {},
            git: {
                committed: false,
                commit_sha: null,
                pushed: false,
                mr_iid: null,
                pipeline_id: null,
                pipeline_status: null,
                merged: false
            }
        } | .current_gate = "IMPLEMENT"
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_verification() {
    local name="$1" status="$2" summary="$3"
    local tmp
    tmp=$(mktemp)
    jq --arg n "$name" --arg s "$status" --arg sum "$summary" '
        .current_task.verification[$n] = {
            status: $s,
            summary: $sum,
            ran_at: (now | todate)
        }
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_git_committed() {
    local sha="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg s "$sha" '
        .current_task.git.committed = true |
        .current_task.git.commit_sha = $s
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_git_pushed() {
    local tmp
    tmp=$(mktemp)
    jq '.current_task.git.pushed = true' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_mr_created() {
    local mr_iid="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg m "$mr_iid" '
        .current_task.git.mr_iid = ($m | tonumber)
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_pipeline_status() {
    local pipeline_id="$1" status="$2"
    local tmp
    tmp=$(mktemp)
    jq --arg p "$pipeline_id" --arg s "$status" '
        .current_task.git.pipeline_id = ($p | tonumber) |
        .current_task.git.pipeline_status = $s
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

set_merged() {
    local tmp
    tmp=$(mktemp)
    jq '.current_task.git.merged = true' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

complete_current_task() {
    local tmp
    tmp=$(mktemp)
    jq '
        .completed_tasks += [.current_task.uuid] |
        .active_milestone.done_tasks += 1 |
        .overall_progress.done += 1 |
        .current_task = null |
        .current_gate = "SELECT"
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# =============================================================================
# Quality gates (deterministic checks)
# =============================================================================

all_checks_pass() {
    # Returns 0 (true) if ALL verification entries have status "pass"
    local ci_checks
    ci_checks=$(jq -r '.checks[].name' "$CI_PROFILE" 2>/dev/null)

    if [ -z "$ci_checks" ]; then
        echo "ERROR: No CI checks defined in $CI_PROFILE"
        return 1
    fi

    local all_pass=true
    while IFS= read -r check_name; do
        local check_status
        check_status=$(jq -r --arg n "$check_name" '.current_task.verification[$n].status // "pending"' "$STATE_FILE")
        if [ "$check_status" != "pass" ]; then
            all_pass=false
            echo "BLOCKED: $check_name = $check_status"
        fi
    done <<< "$ci_checks"

    $all_pass
}

can_advance_to_commit() {
    all_checks_pass && \
    jq -e '.current_task.git.committed == false' "$STATE_FILE" > /dev/null 2>&1
}

can_advance_to_push() {
    jq -e '.current_task.git.committed == true and .current_task.git.pushed == false' "$STATE_FILE" > /dev/null 2>&1
}

can_advance_to_merge() {
    jq -e '.current_task.git.pipeline_status == "success" and .current_task.git.merged == false' "$STATE_FILE" > /dev/null 2>&1
}

# =============================================================================
# Journal operations
# =============================================================================

write_journal() {
    local uuid
    uuid=$(read_current_task_uuid)
    [ -z "$uuid" ] && return 1

    jq '{
        task_uuid: .current_task.uuid,
        title: .current_task.title,
        started_at: .current_task.started_at,
        completed_at: (now | todate),
        branch: .current_task.branch,
        verification: .current_task.verification,
        git: .current_task.git,
        acceptance_criteria: .current_task.acceptance_criteria
    }' "$STATE_FILE" > "${JOURNAL_DIR}/task-${uuid}.json"

    echo "Journal written: task-${uuid}.json"
}

# =============================================================================
# Display helpers
# =============================================================================

print_status() {
    echo "═══════════════════════════════════════════════════════"
    echo "  TeamX Dev State Machine"
    echo "═══════════════════════════════════════════════════════"
    echo "  Project:    $(jq -r '.project_code + " — " + .project_name' "$STATE_FILE")"
    echo "  Gate:       $(read_gate)"
    echo "  Milestone:  $(jq -r '.active_milestone.title + " (" + (.active_milestone.done_tasks|tostring) + "/" + (.active_milestone.total_tasks|tostring) + ")"' "$STATE_FILE")"
    if [ "$(read_current_task_uuid)" != "" ]; then
        echo "  Task:       $(read_current_task_title)"
        echo "  Branch:     $(read_current_branch)"
        echo "  Verify:     $(jq -r '[.current_task.verification | to_entries[] | .key + "=" + .value.status] | join(", ")' "$STATE_FILE" 2>/dev/null || echo "pending")"
        echo "  Git:        committed=$(jq -r '.current_task.git.committed' "$STATE_FILE") pushed=$(jq -r '.current_task.git.pushed' "$STATE_FILE") merged=$(jq -r '.current_task.git.merged' "$STATE_FILE")"
    fi
    echo "  Progress:   $(jq -r '(.overall_progress.done|tostring) + "/" + (.overall_progress.total|tostring)' "$STATE_FILE")"
    echo "═══════════════════════════════════════════════════════"
}

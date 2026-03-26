#!/bin/bash
# =============================================================================
# TeamX Dev State Machine — Deterministic State Operations (v3)
# =============================================================================
# These functions manipulate .teamx/state.json without LLM involvement.
# They are the source of truth for gate transitions and quality enforcement.
#
# Usage: source .teamx/lib/state.sh
#
# State machine:
# IDLE → INIT → SELECT → CLASSIFY → [PLAN] → IMPLEMENT → VERIFY →
# COMMIT → PUSH → MR → PIPELINE → MERGE → EVIDENCE → [RETROSPECTIVE] → SELECT
# =============================================================================

set -euo pipefail

STATE_VERSION=3

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
LESSONS_FILE="${TEAMX_DIR}/lessons.json"
HANDOFF_FILE="${TEAMX_DIR}/handoff.md"

# =============================================================================
# State reading — core
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

# =============================================================================
# State reading — classification
# =============================================================================

read_work_type() {
    jq -r '.current_task.work_type // ""' "$STATE_FILE"
}

read_readiness() {
    jq -r '.current_task.readiness // ""' "$STATE_FILE"
}

read_flow_variant() {
    jq -r '.current_task.flow_variant // "standard"' "$STATE_FILE"
}

read_branch_prefix() {
    jq -r '.current_task.branch_prefix // "feat/"' "$STATE_FILE"
}

read_commit_prefix() {
    jq -r '.current_task.commit_prefix // "feat:"' "$STATE_FILE"
}

# =============================================================================
# State reading — plan
# =============================================================================

read_plan() {
    jq -c '.current_task.plan // null' "$STATE_FILE"
}

# =============================================================================
# State reading — handoff
# =============================================================================

read_handoff() {
    jq -c '.handoff // null' "$STATE_FILE"
}

handoff_exists() {
    [ -f "$HANDOFF_FILE" ]
}

# =============================================================================
# State reading — lessons
# =============================================================================

read_lessons() {
    if [ -f "$LESSONS_FILE" ]; then
        jq -c '.' "$LESSONS_FILE"
    else
        echo 'null'
    fi
}

# =============================================================================
# State reading — summary (for LLM context injection)
# =============================================================================

read_state_summary() {
    jq -c '{
        project: .project_code,
        gate: .current_gate,
        state_version: (.state_version // 2),
        milestone: .active_milestone.title,
        milestone_progress: "\(.active_milestone.done_tasks)/\(.active_milestone.total_tasks)",
        task: .current_task.title,
        task_uuid: .current_task.uuid,
        work_type: (.current_task.work_type // null),
        readiness: (.current_task.readiness // null),
        flow_variant: (.current_task.flow_variant // "standard"),
        branch: .current_task.branch,
        plan_approved: (.current_task.plan.approved // null),
        verification: (.current_task.verification // {}),
        git: (.current_task.git // {}),
        handoff: (.handoff // null),
        completed: (.completed_tasks | length),
        total: .overall_progress.total
    }' "$STATE_FILE" 2>/dev/null || echo '{"gate":"IDLE"}'
}

# =============================================================================
# State writing — core
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

# Select a task — branch is NOT set here, it's set after CLASSIFY
set_current_task() {
    local uuid="$1" title="$2" issue_iid="$3"
    local tmp
    tmp=$(mktemp)
    jq --arg u "$uuid" --arg t "$title" --arg i "$issue_iid" '
        .current_task = {
            uuid: $u,
            title: $t,
            gitlab_issue_iid: ($i | tonumber? // 0),
            branch: null,
            work_type: null,
            readiness: null,
            flow_variant: null,
            branch_prefix: null,
            commit_prefix: null,
            started_at: (now | todate),
            acceptance_criteria: [],
            plan: null,
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
        } | .current_gate = "CLASSIFY"
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "GATE → CLASSIFY"
}

# Set branch after CLASSIFY determines the correct prefix
set_task_branch() {
    local branch="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg b "$branch" '.current_task.branch = $b' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# =============================================================================
# State writing — classification
# =============================================================================

# Resolve work type and set prefix/variant (hardcoded mapping — YAML in bash is impractical)
set_work_type() {
    local type="$1"
    local prefix variant commit_prefix
    case "$type" in
        feature)
            prefix="feat/"
            commit_prefix="feat:"
            variant="standard"
            ;;
        bugfix)
            prefix="fix/"
            commit_prefix="fix:"
            variant="standard"
            ;;
        hotfix)
            prefix="hotfix/"
            commit_prefix="fix:"
            variant="compressed"
            ;;
        refactor)
            prefix="refactor/"
            commit_prefix="refactor:"
            variant="standard"
            ;;
        chore)
            prefix="chore/"
            commit_prefix="chore:"
            variant="standard"
            ;;
        discovery)
            prefix="spike/"
            commit_prefix="docs:"
            variant="discovery"
            ;;
        *)
            echo "ERROR: Unknown work type: $type"
            echo "Valid types: feature, bugfix, hotfix, refactor, chore, discovery"
            return 1
            ;;
    esac

    local tmp
    tmp=$(mktemp)
    jq --arg t "$type" --arg p "$prefix" --arg cp "$commit_prefix" --arg v "$variant" '
        .current_task.work_type = $t |
        .current_task.branch_prefix = $p |
        .current_task.commit_prefix = $cp |
        .current_task.flow_variant = $v
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "TYPE → $type ($prefix, $commit_prefix, variant=$variant)"
}

set_readiness() {
    local status="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg s "$status" '.current_task.readiness = $s' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "READINESS → $status"
}

# =============================================================================
# State writing — plan
# =============================================================================

set_plan() {
    local proposed_files="$1" risks="$2" architecture_notes="$3"
    local tmp
    tmp=$(mktemp)
    jq --argjson files "$proposed_files" --arg risks "$risks" --arg notes "$architecture_notes" '
        .current_task.plan = {
            proposed_files: $files,
            risks: $risks,
            architecture_notes: $notes,
            created_at: (now | todate),
            approved: false
        }
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

approve_plan() {
    local tmp
    tmp=$(mktemp)
    jq '.current_task.plan.approved = true' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "PLAN → approved"
}

# =============================================================================
# State writing — handoff
# =============================================================================

set_handoff() {
    local uuid="$1"
    local tmp
    tmp=$(mktemp)
    jq --arg u "$uuid" '
        .handoff = {
            task_uuid: $u,
            created_at: (now | todate),
            gate_at_handoff: .current_gate,
            context_summary: (
                "Task: " + (.current_task.title // "none") +
                " | Gate: " + (.current_gate // "IDLE") +
                " | Branch: " + (.current_task.branch // "none") +
                " | Type: " + (.current_task.work_type // "unknown")
            )
        }
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    echo "HANDOFF created for task $uuid"
}

clear_handoff() {
    local tmp
    tmp=$(mktemp)
    jq 'del(.handoff)' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
    [ -f "$HANDOFF_FILE" ] && rm -f "$HANDOFF_FILE"
    echo "HANDOFF cleared"
}

# =============================================================================
# State writing — verification & git (unchanged from v2)
# =============================================================================

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
        .completed_tasks += [{
            uuid: .current_task.uuid,
            work_type: (.current_task.work_type // "feature"),
            completed_at: (now | todate)
        }] |
        .active_milestone.done_tasks += 1 |
        .overall_progress.done += 1 |
        .current_task = null |
        .current_gate = "SELECT"
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# =============================================================================
# Quality gates (deterministic checks)
# =============================================================================

check_readiness() {
    jq -e '.current_task.readiness == "ready"' "$STATE_FILE" > /dev/null 2>&1
}

can_advance_to_implement() {
    jq -e '
        .current_task.readiness == "ready" and
        .current_task.work_type != null and
        .current_task.branch != null
    ' "$STATE_FILE" > /dev/null 2>&1
}

can_advance_from_plan() {
    jq -e '.current_task.plan.approved == true' "$STATE_FILE" > /dev/null 2>&1
}

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
# Flow variant helpers
# =============================================================================

is_compressed_flow() {
    local variant
    variant=$(jq -r '.current_task.flow_variant // "standard"' "$STATE_FILE")
    [ "$variant" = "compressed" ]
}

is_discovery_flow() {
    local variant
    variant=$(jq -r '.current_task.flow_variant // "standard"' "$STATE_FILE")
    [ "$variant" = "discovery" ]
}

# Returns 0 if the given gate should be skipped for the current flow variant
should_skip_gate() {
    local gate="$1"
    local variant
    variant=$(read_flow_variant)
    case "$variant" in
        compressed)
            # Hotfix: skip PLAN
            [ "$gate" = "PLAN" ] && return 0
            ;;
        discovery)
            # Discovery: skip VERIFY through MERGE (produces document, not merged code)
            case "$gate" in VERIFY|COMMIT|PUSH|MR|PIPELINE|MERGE) return 0 ;; esac
            ;;
    esac
    return 1
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
        work_type: (.current_task.work_type // "feature"),
        flow_variant: (.current_task.flow_variant // "standard"),
        started_at: .current_task.started_at,
        completed_at: (now | todate),
        branch: .current_task.branch,
        plan: (.current_task.plan // null),
        verification: .current_task.verification,
        git: .current_task.git,
        acceptance_criteria: .current_task.acceptance_criteria
    }' "$STATE_FILE" > "${JOURNAL_DIR}/task-${uuid}.json"

    echo "Journal written: task-${uuid}.json"
}

# =============================================================================
# Migration (backward compatibility)
# =============================================================================

migrate_state() {
    local current_version
    current_version=$(jq -r '.state_version // 2' "$STATE_FILE")

    if [ "$current_version" -ge "$STATE_VERSION" ]; then
        return 0
    fi

    echo "Migrating state from v${current_version} to v${STATE_VERSION}..."

    local tmp
    tmp=$(mktemp)
    jq --argjson v "$STATE_VERSION" '
        .state_version = $v |
        # Fill defaults for v3 fields on existing current_task
        if .current_task != null then
            .current_task.work_type //= "feature" |
            .current_task.readiness //= "ready" |
            .current_task.flow_variant //= "standard" |
            .current_task.branch_prefix //= "feat/" |
            .current_task.commit_prefix //= "feat:" |
            .current_task.plan //= null
        else . end |
        # Migrate completed_tasks from UUID strings to objects
        .completed_tasks = [.completed_tasks[]? |
            if type == "string" then {uuid: ., work_type: "feature", completed_at: null}
            else . end
        ]
    ' "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"

    echo "Migration complete → v${STATE_VERSION}"
}

# =============================================================================
# Display helpers
# =============================================================================

print_status() {
    echo "═══════════════════════════════════════════════════════"
    echo "  TeamX Dev State Machine (v${STATE_VERSION})"
    echo "═══════════════════════════════════════════════════════"
    echo "  Project:    $(jq -r '.project_code + " — " + .project_name' "$STATE_FILE")"
    echo "  Gate:       $(read_gate)"
    echo "  Milestone:  $(jq -r '.active_milestone.title + " (" + (.active_milestone.done_tasks|tostring) + "/" + (.active_milestone.total_tasks|tostring) + ")"' "$STATE_FILE")"
    if [ "$(read_current_task_uuid)" != "" ]; then
        echo "  Task:       $(read_current_task_title)"
        local wt
        wt=$(read_work_type)
        [ -n "$wt" ] && echo "  Type:       $wt ($(read_flow_variant))"
        local rd
        rd=$(read_readiness)
        [ -n "$rd" ] && echo "  Readiness:  $rd"
        echo "  Branch:     $(read_current_branch)"
        local plan_status
        plan_status=$(jq -r '.current_task.plan.approved // empty' "$STATE_FILE" 2>/dev/null)
        [ -n "$plan_status" ] && echo "  Plan:       approved=$plan_status"
        echo "  Verify:     $(jq -r '[.current_task.verification | to_entries[] | .key + "=" + .value.status] | join(", ")' "$STATE_FILE" 2>/dev/null || echo "pending")"
        echo "  Git:        committed=$(jq -r '.current_task.git.committed' "$STATE_FILE") pushed=$(jq -r '.current_task.git.pushed' "$STATE_FILE") merged=$(jq -r '.current_task.git.merged' "$STATE_FILE")"
    fi
    local handoff
    handoff=$(read_handoff)
    [ "$handoff" != "null" ] && echo "  Handoff:    $(jq -r '.handoff.context_summary' "$STATE_FILE")"
    echo "  Progress:   $(jq -r '(.overall_progress.done|tostring) + "/" + (.overall_progress.total|tostring)' "$STATE_FILE")"
    echo "═══════════════════════════════════════════════════════"
}

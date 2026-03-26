#!/bin/bash
# =============================================================================
# TeamX Dev — Context Handoff Generator
# =============================================================================
# Generates a structured handoff document from current state.
# Use when pausing work mid-task or transferring to another dev/agent.
# NO LLM involvement — pure state extraction.
#
# Usage: bash .teamx/lib/handoff.sh [repo_path]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/state.sh"

REPO_PATH="${1:-$(read_repo_path)}"
HANDOFF_FILE="${TEAMX_DIR}/handoff.md"

if ! state_exists; then
    echo "ERROR: No state.json found. Nothing to hand off."
    exit 1
fi

GATE=$(read_gate)
TASK_UUID=$(read_current_task_uuid)
TASK_TITLE=$(read_current_task_title)
BRANCH=$(read_current_branch)
WORK_TYPE=$(read_work_type)
PROJECT=$(read_project_code)

if [ -z "$TASK_UUID" ]; then
    echo "ERROR: No current task. Nothing to hand off."
    exit 1
fi

echo "═══════════════════════════════════════════════════════"
echo "  HANDOFF — Generating context transfer"
echo "═══════════════════════════════════════════════════════"

# Extract verification status
VERIFY_STATUS=$(jq -r '
    if .current_task.verification | length > 0 then
        [.current_task.verification | to_entries[] | .key + "=" + .value.status] | join(", ")
    else
        "not run yet"
    end
' "$STATE_FILE")

# Extract git status
GIT_STATUS=$(jq -r '
    "committed=" + (.current_task.git.committed | tostring) +
    " pushed=" + (.current_task.git.pushed | tostring) +
    " merged=" + (.current_task.git.merged | tostring) +
    if .current_task.git.mr_iid then " mr=!" + (.current_task.git.mr_iid | tostring) else "" end
' "$STATE_FILE")

# Extract acceptance criteria
CRITERIA=$(jq -r '
    if .current_task.acceptance_criteria | length > 0 then
        [.current_task.acceptance_criteria[] | "- " + .] | join("\n")
    else
        "- (not captured in state)"
    end
' "$STATE_FILE")

# Extract plan if exists
PLAN_INFO=$(jq -r '
    if .current_task.plan != null then
        "Proposed files: " + (.current_task.plan.proposed_files | join(", ")) +
        "\nRisks: " + .current_task.plan.risks +
        "\nApproved: " + (.current_task.plan.approved | tostring)
    else
        "No plan created"
    end
' "$STATE_FILE")

# Get files changed in the branch (if branch exists and repo is accessible)
FILES_CHANGED="(unable to determine)"
if [ -n "$BRANCH" ] && [ -d "$REPO_PATH" ]; then
    FILES_CHANGED=$(cd "$REPO_PATH" && git diff --name-only main..."$BRANCH" 2>/dev/null || echo "(unable to determine)")
    [ -z "$FILES_CHANGED" ] && FILES_CHANGED=$(cd "$REPO_PATH" && git diff --name-only HEAD 2>/dev/null || echo "(unable to determine)")
fi

# Write handoff document
cat > "$HANDOFF_FILE" << EOF
# Context Handoff

Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")

## Project
- Code: $PROJECT
- Task: $TASK_TITLE
- UUID: $TASK_UUID
- Type: ${WORK_TYPE:-unknown}

## Current State
- Gate: $GATE
- Branch: ${BRANCH:-not created}
- Verification: $VERIFY_STATUS
- Git: $GIT_STATUS

## Acceptance Criteria
$CRITERIA

## Plan
$PLAN_INFO

## Files Changed
$FILES_CHANGED

## Decisions Made
<!-- The LLM should fill this section with decisions and rationale -->
(To be filled by the agent with decisions made during this session)

## Open Risks
<!-- The LLM should fill this section with known risks -->
(To be filled by the agent with identified risks)

## Next Steps
Resume from gate: $GATE
Run: source .teamx/lib/state.sh && print_status
EOF

# Update state with handoff metadata
set_handoff "$TASK_UUID"

echo ""
echo "  Handoff written: $HANDOFF_FILE"
echo "  State updated with handoff metadata"
echo ""
echo "═══════════════════════════════════════════════════════"

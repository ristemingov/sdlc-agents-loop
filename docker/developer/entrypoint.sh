#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
PLAN_DIR="/workspace/plan"
CODE_DIR="/workspace/code"
REVIEW_DIR="/workspace/review"
LOG_DIR="/workspace/logs"
AGENT="developer"
POLL_INTERVAL=30

log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [${AGENT}] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/${AGENT}.log"
}

run_agent() {
    local trigger_context="$1"
    local feature_name feature_slug

    feature_name=$(cat "${STATE_DIR}/current-feature" 2>/dev/null || echo "unknown-feature")
    feature_slug="${feature_name%.md}"
    feature_slug="${feature_slug%.txt}"

    local prd_content tasks_content arch_content review_feedback revision_section

    prd_content=$(cat "${PLAN_DIR}/prds/prd-${feature_slug}.md" 2>/dev/null || echo "(PRD not found)")
    tasks_content=$(cat "${PLAN_DIR}/tasks/tasks-${feature_slug}.md" 2>/dev/null || echo "(task list not found)")
    arch_content=$(cat "${PLAN_DIR}/architecture/architecture-${feature_slug}.md" 2>/dev/null || echo "(architecture not yet defined)")

    revision_section=""
    if [[ "${trigger_context}" == "revision-requested" ]]; then
        review_feedback=$(cat "${REVIEW_DIR}/review-${feature_slug}.md" 2>/dev/null || echo "(no review feedback found)")
        revision_section="
## Code Review Feedback — YOU MUST ADDRESS ALL BLOCKERS

${review_feedback}

Address every 🔴 Blocker before marking tasks complete.
Address 🟡 Suggestions where practical.
Document any intentional decisions not to apply a suggestion in IMPLEMENTATION_NOTES.md.
"
    fi

    local AGENT_SYSTEM
    AGENT_SYSTEM=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm' /agents/engineering/engineering-senior-developer.md 2>/dev/null || echo "You are a senior software developer.")

    local PROMPT
    PROMPT="$(cat <<PROMPT_EOF
${AGENT_SYSTEM}

---

## Automated SDLC Pipeline — Your Task

Implement the feature described in the planning documents below.
${revision_section}
**PRD Summary**:
${prd_content}

**Task List** (implement every task, mark each complete):
${tasks_content}

**Architecture** (follow this design exactly, document any deviations):
${arch_content}

## Instructions

1. Read ALL planning documents above carefully
2. Implement the feature by creating/modifying files in: ${CODE_DIR}/
3. Follow the architecture design — if you must deviate, document the reason
4. Complete every task in the task list
5. Write clean, readable, maintainable code with appropriate error handling
6. Create/update ${CODE_DIR}/IMPLEMENTATION_NOTES.md documenting:
   - What was implemented
   - File structure created/modified
   - Any deviations from the architecture and why
   - Known limitations or follow-up items
7. After completing all tasks, write the completion signal:
   ${STATE_DIR}/done-developer
   Content: "Implementation complete in ${CODE_DIR}"

IMPORTANT CONSTRAINTS:
- Write ALL code to ${CODE_DIR}/ — never write to ${PLAN_DIR}/ (it is read-only for you)
- Do not start servers or background processes
- Write self-contained, testable code

Implement the feature now.
PROMPT_EOF
)"

    log "INFO" "Running (context: ${trigger_context:-fresh}) for feature: ${feature_name}"
    claude --dangerously-skip-permissions -p "${PROMPT}"

    if [[ ! -f "${STATE_DIR}/done-${AGENT}" ]]; then
        echo "Implementation complete in ${CODE_DIR}" > "${STATE_DIR}/done-${AGENT}"
    fi
    log "INFO" "Completed"
}

mkdir -p "${LOG_DIR}"
log "INFO" "Starting — polling every ${POLL_INTERVAL}s for trigger"

while true; do
    if [[ -f "${STATE_DIR}/trigger-${AGENT}" ]]; then
        log "INFO" "Trigger detected"
        trigger_context=$(cat "${STATE_DIR}/trigger-${AGENT}" 2>/dev/null || echo "")
        rm -f "${STATE_DIR}/trigger-${AGENT}"
        run_agent "${trigger_context}"
    fi
    sleep "${POLL_INTERVAL}"
done

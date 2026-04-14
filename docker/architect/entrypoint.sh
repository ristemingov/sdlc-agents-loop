#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
PLAN_DIR="/workspace/plan"
LOG_DIR="/workspace/logs"
AGENT="architect"
POLL_INTERVAL=30

log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [${AGENT}] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/${AGENT}.log"
}

run_agent() {
    local feature_name feature_slug prd_content tasks_content arch_output

    feature_name=$(cat "${STATE_DIR}/current-feature" 2>/dev/null || echo "unknown-feature")
    feature_slug="${feature_name%.md}"
    feature_slug="${feature_slug%.txt}"

    prd_content=$(cat "${PLAN_DIR}/prds/prd-${feature_slug}.md" 2>/dev/null \
        || find "${PLAN_DIR}/prds" -name "*.md" | xargs cat 2>/dev/null \
        || echo "(no PRD found)")

    tasks_content=$(cat "${PLAN_DIR}/tasks/tasks-${feature_slug}.md" 2>/dev/null \
        || find "${PLAN_DIR}/tasks" -name "*.md" | xargs cat 2>/dev/null \
        || echo "(no task list found)")

    arch_output="${PLAN_DIR}/architecture/architecture-${feature_slug}.md"
    mkdir -p "${PLAN_DIR}/architecture"

    local AGENT_SYSTEM
    AGENT_SYSTEM=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm' /agents/engineering/engineering-software-architect.md 2>/dev/null || echo "You are a software architect.")

    local PROMPT
    PROMPT="$(cat <<PROMPT_EOF
${AGENT_SYSTEM}

---

## Automated SDLC Pipeline — Your Task

Design the technical architecture for the feature described in the PRD and task list below.

**PRD**:
${prd_content}

**Task List**:
${tasks_content}

## Instructions

1. Analyze the PRD and task list carefully
2. Design a complete technical architecture including:
   - System components and their responsibilities
   - Data models and schema design
   - API endpoint design (if applicable)
   - Integration points and external dependencies
   - Technology stack recommendations with justifications
   - At least 2 Architectural Decision Records (ADRs) using your ADR template
   - Sequence diagrams in Mermaid or ASCII notation
   - Quality attribute considerations (scalability, security, maintainability)
3. Name every trade-off explicitly — what you gain and what you give up
4. Write the architecture document to: ${arch_output}
5. Also append any architecture-derived tasks to: ${PLAN_DIR}/tasks/tasks-${feature_slug}.md
   (add an "Architecture Notes" section at the bottom without removing existing tasks)
6. After writing, write the completion signal:
   ${STATE_DIR}/done-architect
   Content: "Architecture written to ${arch_output}"

IMPORTANT: Do NOT write to /workspace/code/ — only to /workspace/plan/.
Focus on practical, implementable architecture.

Write the architecture document now.
PROMPT_EOF
)"

    log "INFO" "Running for feature: ${feature_name}"
    claude --dangerously-skip-permissions -p "${PROMPT}"

    if [[ ! -f "${STATE_DIR}/done-${AGENT}" ]]; then
        echo "Architecture written to ${arch_output}" > "${STATE_DIR}/done-${AGENT}"
    fi
    log "INFO" "Completed"
}

mkdir -p "${LOG_DIR}"
log "INFO" "Starting — polling every ${POLL_INTERVAL}s for trigger"

while true; do
    if [[ -f "${STATE_DIR}/trigger-${AGENT}" ]]; then
        log "INFO" "Trigger detected"
        rm -f "${STATE_DIR}/trigger-${AGENT}"
        run_agent
    fi
    sleep "${POLL_INTERVAL}"
done

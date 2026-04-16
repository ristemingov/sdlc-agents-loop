#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
PLAN_DIR="/workspace/plan"
LOG_DIR="/workspace/logs"
AGENT="project-manager"
POLL_INTERVAL=30

log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [${AGENT}] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/${AGENT}.log"
}

run_agent() {
    local feature_name feature_slug prd_file prd_content tasks_output

    feature_name=$(cat "${STATE_DIR}/current-feature" 2>/dev/null || echo "unknown-feature")
    feature_slug="${feature_name%.md}"
    feature_slug="${feature_slug%.txt}"

    # Find the latest PRD
    prd_file="${PLAN_DIR}/prds/prd-${feature_slug}.md"
    if [[ ! -f "${prd_file}" ]]; then
        prd_file=$(find "${PLAN_DIR}/prds" -name "*.md" -type f 2>/dev/null | sort | tail -n1 || echo "")
    fi

    prd_content=$(cat "${prd_file}" 2>/dev/null || echo "(no PRD found in ${PLAN_DIR}/prds/)")

    local arch_file arch_content
    arch_file="${PLAN_DIR}/architecture/architecture-${feature_slug}.md"
    arch_content=$(cat "${arch_file}" 2>/dev/null \
        || find "${PLAN_DIR}/architecture" -name "*.md" -type f 2>/dev/null | sort | tail -n1 | xargs cat 2>/dev/null \
        || echo "(no architecture document found)")

    tasks_output="${PLAN_DIR}/tasks/tasks-${feature_slug}.md"
    mkdir -p "${PLAN_DIR}/tasks"

    local AGENT_SYSTEM
    AGENT_SYSTEM=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm' /agents/project-management/project-manager-senior.md 2>/dev/null || echo "You are a senior project manager.")

    local PROMPT
    PROMPT="$(cat <<PROMPT_EOF
${AGENT_SYSTEM}

---

## Automated SDLC Pipeline — Your Task

Convert the Product Requirements Document and Architecture Design below into a structured development task list.

**PRD File**: ${prd_file}
**PRD Content**:
${prd_content}

**Architecture Document**:
${arch_content}

## Instructions

1. Read the PRD and architecture document thoroughly
2. Break the work into specific, actionable development tasks anchored to the architectural components, where each task:
   - Can be implemented in 30-60 minutes by a developer
   - Has clear acceptance criteria
   - Notes which files need to be created or modified
   - Has a complexity estimate: XS (<30min), S (30-60min), M (1-2h), L (2-4h)
3. Order tasks by dependency (foundation first)
4. Note any dependencies between tasks
5. Write the complete task list to: ${tasks_output}
6. The task list must include:
   - Specification summary section
   - Ordered task list with acceptance criteria
   - Quality requirements checklist
   - Technical notes
7. After writing, write the completion signal:
   ${STATE_DIR}/done-project-manager
   Content: "Task list written to ${tasks_output}"

IMPORTANT: Do NOT write to /workspace/code/ — only to /workspace/plan/.

Write the task list now.
PROMPT_EOF
)"

    log "INFO" "Running for feature: ${feature_name}"
    claude --dangerously-skip-permissions -p "${PROMPT}"

    if [[ ! -f "${STATE_DIR}/done-${AGENT}" ]]; then
        echo "Task list written to ${tasks_output}" > "${STATE_DIR}/done-${AGENT}"
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

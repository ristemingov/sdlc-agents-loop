#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
INPUT_DIR="/workspace/user-input"
PLAN_DIR="/workspace/plan"
LOG_DIR="/workspace/logs"
AGENT="product-manager"
POLL_INTERVAL=30

log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [${AGENT}] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/${AGENT}.log"
}

run_agent() {
    local feature_name="$1"
    local feature_file="${INPUT_DIR}/${feature_name}"
    local feature_slug="${feature_name%.md}"
    feature_slug="${feature_slug%.txt}"
    local prd_output="${PLAN_DIR}/prds/prd-${feature_slug}.md"
    mkdir -p "${PLAN_DIR}/prds"

    local feature_content
    feature_content=$(cat "${feature_file}" 2>/dev/null || echo "(feature file not found: ${feature_file})")

    local AGENT_SYSTEM
    AGENT_SYSTEM=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm' /agents/product/product-manager.md 2>/dev/null || echo "You are a product manager.")

    local PROMPT
    PROMPT="$(cat <<PROMPT_EOF
${AGENT_SYSTEM}

---

## Automated SDLC Pipeline — Your Task

A new feature request has been submitted. You must convert it into a Product Requirements Document (PRD).

**Feature Request File**: ${feature_file}
**Feature Request Content**:
${feature_content}

## Instructions

1. Read the feature request content above
2. Write a complete PRD following your PRD template to: ${prd_output}
3. The PRD must include:
   - Problem Statement (synthesize evidence from the request)
   - Goals and Success Metrics (specific, measurable)
   - Non-Goals (at least 2 explicit exclusions)
   - User Personas and User Stories with acceptance criteria
   - Solution Overview
   - Technical Considerations
   - Launch Plan
4. After writing the PRD, write the completion signal file:
   ${STATE_DIR}/done-product-manager
   Content: "PRD written to ${prd_output}"

IMPORTANT: Do NOT write to /workspace/code/ — that is strictly the developer's domain.

Write the PRD now.
PROMPT_EOF
)"

    log "INFO" "Running for feature: ${feature_name}"
    claude --dangerously-skip-permissions -p "${PROMPT}"

    if [[ ! -f "${STATE_DIR}/done-${AGENT}" ]]; then
        echo "PRD written to ${prd_output}" > "${STATE_DIR}/done-${AGENT}"
    fi
    log "INFO" "Completed"
}

mkdir -p "${LOG_DIR}"
log "INFO" "Starting — polling every ${POLL_INTERVAL}s for trigger"

while true; do
    if [[ -f "${STATE_DIR}/trigger-${AGENT}" ]]; then
        log "INFO" "Trigger detected"
        feature_name=$(cat "${STATE_DIR}/trigger-${AGENT}")
        rm -f "${STATE_DIR}/trigger-${AGENT}"
        run_agent "${feature_name}"
    fi
    sleep "${POLL_INTERVAL}"
done

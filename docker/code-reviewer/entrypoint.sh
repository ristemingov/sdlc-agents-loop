#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
PLAN_DIR="/workspace/plan"
CODE_DIR="/workspace/code"
REVIEW_DIR="/workspace/review"
LOG_DIR="/workspace/logs"
AGENT="code-reviewer"
POLL_INTERVAL=30

log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [${AGENT}] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/${AGENT}.log"
}

run_agent() {
    local feature_name feature_slug tasks_content arch_content code_listing review_output

    feature_name=$(cat "${STATE_DIR}/current-feature" 2>/dev/null || echo "unknown-feature")
    feature_slug="${feature_name%.md}"
    feature_slug="${feature_slug%.txt}"

    tasks_content=$(cat "${PLAN_DIR}/tasks/tasks-${feature_slug}.md" 2>/dev/null || echo "(task list not found)")
    arch_content=$(cat "${PLAN_DIR}/architecture/architecture-${feature_slug}.md" 2>/dev/null || echo "(architecture not found)")
    code_listing=$(find "${CODE_DIR}" -type f ! -name ".gitkeep" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | sort | head -200 || true)

    review_output="${REVIEW_DIR}/review-${feature_slug}.md"
    mkdir -p "${REVIEW_DIR}"

    local AGENT_SYSTEM
    AGENT_SYSTEM=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm' /agents/engineering/engineering-code-reviewer.md 2>/dev/null || echo "You are a code reviewer.")

    local PROMPT
    PROMPT="$(cat <<PROMPT_EOF
${AGENT_SYSTEM}

---

## Automated SDLC Pipeline — Your Task

Review the implementation of the feature against its task list and architecture.

**Task List** (acceptance criteria to verify):
${tasks_content}

**Architecture** (intended design to verify against):
${arch_content}

**Code to Review** — files in ${CODE_DIR}/:
${code_listing}

## Instructions

1. Read ALL files in ${CODE_DIR}/ using your file reading capabilities
2. Review the code against:
   - Every task acceptance criterion (is each one met?)
   - Architecture decisions (does the implementation match the design?)
   - Correctness, security, maintainability, and performance
3. Write a complete code review to: ${review_output}
   Structure it as:
   - Opening summary (2-3 sentences on overall quality)
   - Findings using 🔴 Blocker / 🟡 Suggestion / 💭 Nit markers
   - Each finding includes: file name, issue, why it matters, suggested fix
   - Closing verdict: **APPROVED** or **NEEDS_REVISION**
4. Write ONLY the verdict to: ${STATE_DIR}/review-result
   Must be exactly one of:
     APPROVED
     NEEDS_REVISION
   (A review is APPROVED if there are ZERO 🔴 Blockers)
5. Write the completion signal:
   ${STATE_DIR}/done-code-reviewer
   Content: "Review written to ${review_output}"

Write the code review now.
PROMPT_EOF
)"

    log "INFO" "Running for feature: ${feature_name}"
    claude --dangerously-skip-permissions -p "${PROMPT}"

    # Safety net: ensure verdict and done files exist
    if [[ ! -f "${STATE_DIR}/review-result" ]]; then
        log "WARN" "review-result not written by claude — defaulting to NEEDS_REVISION"
        echo "NEEDS_REVISION" > "${STATE_DIR}/review-result"
    fi
    if [[ ! -f "${STATE_DIR}/done-${AGENT}" ]]; then
        verdict=$(cat "${STATE_DIR}/review-result")
        echo "Review written to ${review_output}, verdict: ${verdict}" > "${STATE_DIR}/done-${AGENT}"
    fi
    log "INFO" "Completed — verdict: $(cat "${STATE_DIR}/review-result")"
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

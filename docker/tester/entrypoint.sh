#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
PLAN_DIR="/workspace/plan"
CODE_DIR="/workspace/code"
REVIEW_DIR="/workspace/review"
REPORTS_DIR="/workspace/reports"
LOG_DIR="/workspace/logs"
AGENT="tester"
POLL_INTERVAL=30

log() {
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [${AGENT}] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/${AGENT}.log"
}

run_agent() {
    local feature_name feature_slug prd_content tasks_content review_content code_listing report_output

    feature_name=$(cat "${STATE_DIR}/current-feature" 2>/dev/null || echo "unknown-feature")
    feature_slug="${feature_name%.md}"
    feature_slug="${feature_slug%.txt}"
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)

    prd_content=$(cat "${PLAN_DIR}/prds/prd-${feature_slug}.md" 2>/dev/null || echo "(PRD not found)")
    tasks_content=$(cat "${PLAN_DIR}/tasks/tasks-${feature_slug}.md" 2>/dev/null || echo "(task list not found)")
    review_content=$(cat "${REVIEW_DIR}/review-${feature_slug}.md" 2>/dev/null || echo "(no review found)")
    code_listing=$(find "${CODE_DIR}" -type f ! -name ".gitkeep" ! -path "*/node_modules/*" ! -path "*/.git/*" 2>/dev/null | sort | head -200 || true)

    report_output="${REPORTS_DIR}/test-report-${feature_slug}-${timestamp}.md"
    mkdir -p "${REPORTS_DIR}"

    local AGENT_SYSTEM
    AGENT_SYSTEM=$(awk 'NR==1 && /^---$/{in_fm=1; next} in_fm && /^---$/{in_fm=0; next} !in_fm' /agents/testing/testing-api-tester.md 2>/dev/null || echo "You are a QA engineer.")

    local PROMPT
    PROMPT="$(cat <<PROMPT_EOF
${AGENT_SYSTEM}

---

## Automated SDLC Pipeline — Your Task

Perform comprehensive testing of the implemented feature. The code has already passed code review.

**PRD** (defines success criteria and acceptance):
${prd_content}

**Task List** (acceptance criteria to validate):
${tasks_content}

**Code Review** (passed — issues were resolved):
${review_content}

**Code to Test** — files in ${CODE_DIR}/:
${code_listing}

## Instructions

1. Read ALL files in ${CODE_DIR}/ using your file reading capabilities
2. For each testable component, assess:
   - Functional correctness against every acceptance criterion
   - Edge cases and boundary conditions
   - Error handling and input validation
   - Security considerations (injection, auth, data exposure)
   - Performance characteristics
3. Write a comprehensive test report to: ${report_output}
   Structure:
   - Executive Summary
   - Test Coverage Analysis (Functional / Security / Performance / Integration)
   - Acceptance Criteria Validation (pass/fail per criterion)
   - Issues Found (severity: Critical / High / Medium / Low)
   - Recommendations
   - Go/No-Go Recommendation
4. Write ONLY the test result to: ${STATE_DIR}/test-result
   Must be exactly one of:
     PASS
     FAIL
   (Use PASS only if ALL acceptance criteria are met and zero Critical issues found)
5. Write the completion signal:
   ${STATE_DIR}/done-tester
   Content: "Test report written to ${report_output}, result: <PASS|FAIL>"

Write the test report now.
PROMPT_EOF
)"

    log "INFO" "Running for feature: ${feature_name}"
    claude --dangerously-skip-permissions -p "${PROMPT}"

    # Safety net
    if [[ ! -f "${STATE_DIR}/test-result" ]]; then
        log "WARN" "test-result not written by claude — defaulting to FAIL"
        echo "FAIL" > "${STATE_DIR}/test-result"
    fi
    if [[ ! -f "${STATE_DIR}/done-${AGENT}" ]]; then
        result=$(cat "${STATE_DIR}/test-result")
        echo "Test report written to ${report_output}, result: ${result}" > "${STATE_DIR}/done-${AGENT}"
    fi
    log "INFO" "Completed — result: $(cat "${STATE_DIR}/test-result")"
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

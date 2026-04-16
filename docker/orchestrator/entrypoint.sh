#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/workspace/state"
LOG_DIR="/workspace/logs"
INPUT_DIR="/workspace/user-input"
ARCHIVE_DIR="/workspace/archive"
HEARTBEAT="${HEARTBEAT_INTERVAL:-300}"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-1800}"

# ── Logging ───────────────────────────────────────────────────────────────────

log() {
    local level="$1"
    shift
    local msg="[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] [$level] $*"
    echo "$msg"
    echo "$msg" >> "${LOG_DIR}/orchestrator.log"
}

# ── State helpers ─────────────────────────────────────────────────────────────

read_state() {
    cat "${STATE_DIR}/current-state" 2>/dev/null || echo "WAITING_INPUT"
}

write_state() {
    echo "$1" > "${STATE_DIR}/current-state"
    log "INFO" "State → $1"
}

trigger_agent() {
    local agent="$1"
    local context="${2:-}"
    echo "${context}" > "${STATE_DIR}/trigger-${agent}"
    date +%s > "${STATE_DIR}/phase-start-time"
    log "INFO" "Triggered: ${agent}"
}

done_exists() {
    [[ -f "${STATE_DIR}/done-$1" ]]
}

ack_agent() {
    local agent="$1"
    rm -f "${STATE_DIR}/done-${agent}"
    log "INFO" "Acknowledged: ${agent}"
}

check_timeout() {
    local agent="$1"
    if [[ ! -f "${STATE_DIR}/phase-start-time" ]]; then return 0; fi
    local start now elapsed
    start=$(cat "${STATE_DIR}/phase-start-time")
    now=$(date +%s)
    elapsed=$(( now - start ))
    if (( elapsed > AGENT_TIMEOUT )); then
        log "ERROR" "Agent '${agent}' timed out after ${elapsed}s (limit: ${AGENT_TIMEOUT}s)"
        echo "Timeout: '${agent}' did not complete within ${AGENT_TIMEOUT}s" \
            > "${STATE_DIR}/error-message"
        write_state "ERROR"
        return 1
    fi
    log "DEBUG" "Agent '${agent}' running for ${elapsed}s / ${AGENT_TIMEOUT}s"
    return 0
}

get_next_feature() {
    # Return oldest .md or .txt file in user-input/, or empty string
    find "${INPUT_DIR}" -maxdepth 1 \( -name "*.md" -o -name "*.txt" \) -type f 2>/dev/null \
        | sort | head -n1
}

get_review_result() {
    cat "${STATE_DIR}/review-result" 2>/dev/null || echo "NEEDS_REVISION"
}

get_test_result() {
    cat "${STATE_DIR}/test-result" 2>/dev/null || echo "FAIL"
}

archive_feature() {
    local feature timestamp archive_path feature_file
    feature=$(cat "${STATE_DIR}/current-feature" 2>/dev/null || echo "unknown")
    timestamp=$(date +%Y%m%d-%H%M%S)
    archive_path="${ARCHIVE_DIR}/${timestamp}-${feature}"
    mkdir -p "${archive_path}"
    feature_file="${INPUT_DIR}/${feature}"
    [[ -f "${feature_file}" ]] && mv "${feature_file}" "${archive_path}/" || true
    log "INFO" "Archived '${feature}' → ${archive_path}"
}

reset_state_files() {
    rm -f "${STATE_DIR}"/trigger-* \
          "${STATE_DIR}"/done-* \
          "${STATE_DIR}"/ack-* \
          "${STATE_DIR}/phase-start-time" \
          "${STATE_DIR}/review-result" \
          "${STATE_DIR}/test-result" \
          "${STATE_DIR}/error-message" \
          2>/dev/null || true
}

# ── State machine tick ────────────────────────────────────────────────────────

tick() {
    local state
    state=$(read_state)
    log "INFO" "Heartbeat — state: ${state}"

    case "${state}" in

        WAITING_INPUT)
            local feature_file feature_name
            feature_file=$(get_next_feature)
            if [[ -n "${feature_file}" ]]; then
                feature_name=$(basename "${feature_file}")
                echo "${feature_name}" > "${STATE_DIR}/current-feature"
                log "INFO" "New feature request: ${feature_name}"
                reset_state_files
                write_state "PRODUCT_PLANNING"
                trigger_agent "product-manager" "${feature_name}"
            else
                log "INFO" "No pending feature requests — idling"
            fi
            ;;

        PRODUCT_PLANNING)
            if done_exists "product-manager"; then
                ack_agent "product-manager"
                write_state "ARCHITECTURE"
                trigger_agent "architect"
            else
                check_timeout "product-manager" || true
            fi
            ;;

        ARCHITECTURE)
            if done_exists "architect"; then
                ack_agent "architect"
                write_state "PROJECT_PLANNING"
                trigger_agent "project-manager"
            else
                check_timeout "architect" || true
            fi
            ;;

        PROJECT_PLANNING)
            if done_exists "project-manager"; then
                ack_agent "project-manager"
                write_state "DEVELOPMENT"
                trigger_agent "developer"
            else
                check_timeout "project-manager" || true
            fi
            ;;

        DEVELOPMENT)
            if done_exists "developer"; then
                ack_agent "developer"
                write_state "CODE_REVIEW"
                trigger_agent "code-reviewer"
            else
                check_timeout "developer" || true
            fi
            ;;

        CODE_REVIEW)
            if done_exists "code-reviewer"; then
                ack_agent "code-reviewer"
                local result
                result=$(get_review_result)
                log "INFO" "Review verdict: ${result}"
                if [[ "${result}" == "APPROVED" ]]; then
                    write_state "TESTING"
                    trigger_agent "tester"
                else
                    log "INFO" "Revision requested — returning to DEVELOPMENT"
                    write_state "DEVELOPMENT"
                    trigger_agent "developer" "revision-requested"
                fi
            else
                check_timeout "code-reviewer" || true
            fi
            ;;

        TESTING)
            if done_exists "tester"; then
                ack_agent "tester"
                local result
                result=$(get_test_result)
                log "INFO" "Test result: ${result}"
                archive_feature
                log "INFO" "=== Feature cycle complete. Result: ${result} ==="
                sleep 3
                reset_state_files
                write_state "WAITING_INPUT"
            else
                check_timeout "tester" || true
            fi
            ;;

        DONE)
            # Transient — should have been cleared in TESTING handler
            reset_state_files
            write_state "WAITING_INPUT"
            ;;

        ERROR)
            local err
            err=$(cat "${STATE_DIR}/error-message" 2>/dev/null || echo "Unknown error")
            log "ERROR" "Pipeline in ERROR state: ${err}"
            log "ERROR" "Manual intervention required. Fix the issue, then: echo WAITING_INPUT > /workspace/state/current-state"
            ;;

        *)
            log "WARN" "Unknown state '${state}' — resetting to WAITING_INPUT"
            reset_state_files
            write_state "WAITING_INPUT"
            ;;
    esac
}

# ── Startup ───────────────────────────────────────────────────────────────────

mkdir -p "${STATE_DIR}" "${LOG_DIR}" "${INPUT_DIR}" "${ARCHIVE_DIR}"
log "INFO" "Orchestrator starting (heartbeat: ${HEARTBEAT}s, timeout: ${AGENT_TIMEOUT}s)"

if [[ ! -f "${STATE_DIR}/current-state" ]]; then
    log "INFO" "Initializing state to WAITING_INPUT"
    write_state "WAITING_INPUT"
fi

log "INFO" "Entering main loop"

# ── Main loop ─────────────────────────────────────────────────────────────────

while true; do
    tick
    log "INFO" "Sleeping ${HEARTBEAT}s"
    sleep "${HEARTBEAT}"
done

#!/usr/bin/env bash
set -euo pipefail

INTERVAL="${INTERVAL:-3600}"
AGENT_TIMEOUT="${AGENT_TIMEOUT:-3500}"

# Clean up any stale signals left from a previous run
rm -f /signals/run_pm /signals/pm_done /signals/run_dev /signals/dev_done

echo "[HEARTBEAT] Started. Cycle interval: ${INTERVAL}s, agent timeout: ${AGENT_TIMEOUT}s"

wait_for_signal() {
    local signal_file="$1"
    local label="$2"
    local elapsed=0

    while [ ! -f "$signal_file" ]; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ "$elapsed" -ge "$AGENT_TIMEOUT" ]; then
            echo "[HEARTBEAT] ERROR: ${label} did not finish within ${AGENT_TIMEOUT}s. Skipping."
            return 1
        fi
    done
    return 0
}

while true; do
    echo "[HEARTBEAT] ===== Cycle start: $(date -u '+%Y-%m-%dT%H:%M:%SZ') ====="

    # ── PM turn ─────────────────────────────────────────────────────────────
    echo "[HEARTBEAT] Triggering PM agent..."
    rm -f /signals/pm_done
    touch /signals/run_pm

    if wait_for_signal /signals/pm_done "PM"; then
        rm -f /signals/pm_done
        echo "[HEARTBEAT] PM agent finished."
    fi

    # ── DEV turn ────────────────────────────────────────────────────────────
    echo "[HEARTBEAT] Triggering DEV agent..."
    rm -f /signals/dev_done
    touch /signals/run_dev

    if wait_for_signal /signals/dev_done "DEV"; then
        rm -f /signals/dev_done
        echo "[HEARTBEAT] DEV agent finished."
    fi

    echo "[HEARTBEAT] ===== Cycle done. Sleeping ${INTERVAL}s... ====="
    sleep "$INTERVAL"
done

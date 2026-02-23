#!/bin/bash
set -euo pipefail

# Clean up any stale trigger from a previous crash
rm -f /signals/run_dev

echo "[DEV] Ready. Waiting for heartbeat trigger..."

while true; do
    # Wait for the run signal
    while [ ! -f /signals/run_dev ]; do
        sleep 2
    done
    rm -f /signals/run_dev

    echo "[DEV] $(date -u '+%Y-%m-%dT%H:%M:%SZ') — triggered, running DEV agent..."

    PROMPT="$(cat /project/instructions/dev_agent.md)"

    set +e
    claude --dangerously-skip-permissions -p "$PROMPT"
    EXIT_CODE=$?
    set -e

    if [ $EXIT_CODE -ne 0 ]; then
        echo "[DEV] Agent exited with code $EXIT_CODE"
    else
        echo "[DEV] Agent finished successfully."
    fi

    touch /signals/dev_done
    echo "[DEV] Signalled done."
done

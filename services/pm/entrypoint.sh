#!/bin/bash
set -euo pipefail

# Clean up any stale trigger from a previous crash
rm -f /signals/run_pm

echo "[PM] Ready. Waiting for heartbeat trigger..."

while true; do
    # Wait for the run signal
    while [ ! -f /signals/run_pm ]; do
        sleep 2
    done
    rm -f /signals/run_pm

    echo "[PM] $(date -u '+%Y-%m-%dT%H:%M:%SZ') — triggered, running PM agent..."

    PROMPT="$(cat /project/instructions/pm_agent.md)"

    set +e
    codex -a never -s workspace-write exec "$PROMPT"
    EXIT_CODE=$?
    set -e

    if [ $EXIT_CODE -ne 0 ]; then
        echo "[PM] Agent exited with code $EXIT_CODE"
    else
        echo "[PM] Agent finished successfully."
    fi

    touch /signals/pm_done
    echo "[PM] Signalled done."
done

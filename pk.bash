#!/bin/bash

# Exit codes: 3=binary not found, 4=start failed

# Check binary exists
sudo test -x "${SPLUNK_HOME}/bin/splunk" || { 
    echo "ERROR: Splunk binary not found" >&2
    sudo rm -f "${SCRIPT_PATH}" || true
    exit 3
}

# Function to start via binary
start_binary() {
    sudo "${SPLUNK_HOME}/bin/splunk" status >/dev/null 2>&1 && { echo "Splunk already running."; return 0; }
    echo "Starting Splunk via binary..."
    sudo "${SPLUNK_HOME}/bin/splunk" start --accept-license --answer-yes --no-prompt >/dev/null 2>&1 || {
        echo "ERROR: Binary start failed" >&2
        sudo tail -n 50 "${SPLUNK_HOME}/var/log/splunk/splunkd.log" 2>/dev/null
        return 1
    }
    echo "Splunk started successfully."
}

# Find systemd unit if available
FOUND_UNIT=""
if command -v systemctl >/dev/null 2>&1; then
    for unit in SplunkForwarder.service splunk.service splunk; do
        sudo systemctl list-unit-files 2>/dev/null | grep -qx "$unit" && { FOUND_UNIT="$unit"; break; }
    done
    
    # Retry with daemon-reload if not found
    if [[ -z "$FOUND_UNIT" ]]; then
        sudo systemctl daemon-reload 2>/dev/null && sleep 2
        for unit in SplunkForwarder.service splunk.service splunk; do
            sudo systemctl list-unit-files 2>/dev/null | grep -qx "$unit" && { FOUND_UNIT="$unit"; break; }
        done
    fi
fi

# Start using systemd or fallback to binary
if [[ -n "$FOUND_UNIT" ]]; then
    echo "Using systemd unit: $FOUND_UNIT"
    sudo systemctl is-active --quiet "$FOUND_UNIT" && { echo "Service already active."; exit 0; }
    
    sudo systemctl enable "$FOUND_UNIT" 2>/dev/null
    sudo systemctl start "$FOUND_UNIT" || {
        echo "Systemd start failed, trying binary..." >&2
        sudo journalctl -u "$FOUND_UNIT" -n 50 --no-pager 2>/dev/null
        start_binary || { sudo rm -f "${SCRIPT_PATH}" || true; exit 4; }
    }
    echo "Service started via systemd."
else
    echo "No systemd unit found, using binary..."
    start_binary || { sudo rm -f "${SCRIPT_PATH}" || true; exit 4; }
fi

echo "Splunk startup completed."
exit 0

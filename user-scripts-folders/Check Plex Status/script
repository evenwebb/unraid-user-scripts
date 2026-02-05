#!/bin/bash
#
# check-plex-status.sh
# Monitors Plex Docker container and web UI, restarts container if UI is unreachable
#
# Description:
#   Checks if the Plex Docker container is running and if the web UI is accessible.
#   If the container is running but the UI does not respond, restarts the container.
#   Optional: send a Pushover notification when a restart occurs.
#
# Usage:
#   ./check-plex-status.sh
#
# Configuration:
#   - PLEX_CONTAINER_NAME: Docker container name for Plex
#   - PLEX_WEB_UI: Full URL to Plex web UI (used for connectivity check)
#   - Optional: set PUSHOVER_USER_KEY and PUSHOVER_APP_TOKEN to enable notifications
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Docker container name for Plex - EDIT FOR YOUR SETUP
PLEX_CONTAINER_NAME="plex"

# Plex web UI URL (used to verify the service is responding) - EDIT FOR YOUR SETUP
PLEX_WEB_UI="http://localhost:32400/web/index.html"

# Optional: Pushover notification (leave empty to disable)
PUSHOVER_USER_KEY=""
PUSHOVER_APP_TOKEN=""

# Timeout in seconds for web UI check
CONNECT_TIMEOUT=15
MAX_TIME=30

# Check dependencies
if ! command -v curl >/dev/null 2>&1; then
    echo "Error: curl is required but not installed. Install with: apt-get install curl" >&2
    exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
    echo "Error: docker is required but not installed." >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

send_pushover_notification() {
    local message="$1"
    [[ -z "$PUSHOVER_APP_TOKEN" || -z "$PUSHOVER_USER_KEY" ]] && return 0
    if ! command -v curl >/dev/null 2>&1; then
        log "Warning: curl not found, Pushover notification skipped"
        return 0
    fi
    curl -s -F "token=$PUSHOVER_APP_TOKEN" -F "user=$PUSHOVER_USER_KEY" -F "message=$message" \
        https://api.pushover.net/1/messages.json >/dev/null 2>&1 || true
}

main() {
    # Validate Pushover configuration (both or neither)
    if [[ -n "$PUSHOVER_APP_TOKEN" ]] && [[ -z "$PUSHOVER_USER_KEY" ]]; then
        log "Warning: PUSHOVER_APP_TOKEN is set but PUSHOVER_USER_KEY is missing. Notifications disabled."
        PUSHOVER_APP_TOKEN=""
    elif [[ -z "$PUSHOVER_APP_TOKEN" ]] && [[ -n "$PUSHOVER_USER_KEY" ]]; then
        log "Warning: PUSHOVER_USER_KEY is set but PUSHOVER_APP_TOKEN is missing. Notifications disabled."
        PUSHOVER_USER_KEY=""
    fi
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$PLEX_CONTAINER_NAME"; then
        log "Plex container is not running. No action taken."
        return 0
    fi

    log "Plex container is running. Checking web UI..."

    if curl -s --head --fail --connect-timeout "$CONNECT_TIMEOUT" -m "$MAX_TIME" "$PLEX_WEB_UI" >/dev/null 2>&1; then
        log "Plex web UI is accessible. No action needed."
        return 0
    fi

    log "Plex web UI is not accessible. Restarting container..."
    docker restart "$PLEX_CONTAINER_NAME"
    send_pushover_notification "Plex Docker container was restarted because the web UI was not accessible."
    log "Plex container restarted."
}

main "$@"

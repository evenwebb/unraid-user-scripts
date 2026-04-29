#!/bin/bash
#
# check-plex-status.sh
# Monitors Plex Docker container and web UI, restarts container if UI is unreachable
#
# Description:
#   Checks if the Plex Docker container is running and if the web UI is accessible.
#   If the container is running but the UI does not respond, restarts the container.
#   Optional: send an Unraid notification when a restart occurs (Settings → Notifications).
#
# Usage:
#   ./check-plex-status.sh
#
# Configuration:
#   - PLEX_CONTAINER_NAME: Docker container name for Plex
#   - PLEX_WEB_UI: Full URL to Plex web UI (used for connectivity check)
#   - NOTIFY_SCRIPT: Optional path to dynamix notify (empty = no notification on restart)
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#   - RESTART_ONLY_IF_AUTOSTART: 1 = only restart if container has restart policy always/unless-stopped (skips when policy is "no")
#   - CONNECT_TIMEOUT: Seconds to wait when checking Plex web UI
#   - MAX_TIME: Max seconds for Plex web UI check request
#
# Note: Output goes to stdout; Unraid User Scripts captures it in the GUI.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Docker container name for Plex
PLEX_CONTAINER_NAME="plex"

# Plex web UI URL (used to verify the service is responding)
PLEX_WEB_UI="http://localhost:32400/web/index.html"

# Optional: Unraid dynamix notify (empty = no notification when container is restarted)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Optional: only restart if container has restart policy "always" or "unless-stopped"
# When 1: skips restart if policy is "no" (container may be intentionally stopped)
# When 0: always restart when UI is unreachable (default)
RESTART_ONLY_IF_AUTOSTART=0

# Timeout in seconds for web UI check
CONNECT_TIMEOUT=15
MAX_TIME=30

###############################################################################

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi

###############################################################################

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg" >&2
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

# Check dependencies
if ! command -v curl &>/dev/null; then
    log_err "curl is required but not installed. Install with: apt-get install curl"
    exit 1
fi
if ! command -v docker &>/dev/null; then
    log_err "docker is required but not installed."
    exit 1
fi
if ! docker info >/dev/null 2>&1; then
    log_err "Docker daemon not available (is Docker started in Unraid?)."
    exit 1
fi

is_safe_notify_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'\n'* ]] && return 1
    return 0
}

# -e event, -s subject (title), -d description (body), -i importance: normal|warning|alert
send_unraid_notify() {
    local event="$1" subject="$2" description="$3" importance="${4:-warning}"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    is_safe_notify_path "$NOTIFY_SCRIPT" || return 0
    "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "$importance" 2>/dev/null || true
}

main() {
    if [[ -z "$PLEX_CONTAINER_NAME" ]]; then
        log_err "PLEX_CONTAINER_NAME is empty."
        return 1
    fi
    if [[ -z "$PLEX_WEB_UI" || ! "$PLEX_WEB_UI" =~ ^https?:// ]]; then
        log_err "PLEX_WEB_UI must be a valid http(s) URL."
        return 1
    fi

    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$PLEX_CONTAINER_NAME"; then
        log "Plex container is not running. No action taken."
        return 0
    fi

    log "Plex container is running. Checking web UI..."

    local http_code="000"
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" -m "$MAX_TIME" "$PLEX_WEB_UI" 2>/dev/null || echo "000")

    # Plex may not support HEAD reliably and may return 401/403 without an auth token.
    # If we can get any valid HTTP response code (including 3xx redirects or auth-required),
    # treat the service as reachable to avoid false restarts.
    case "$http_code" in
        2??|3??|401|403|405)
            log "Plex web UI responded (HTTP $http_code). No action needed."
            return 0
            ;;
    esac
    log "Plex web UI check failed (HTTP $http_code)."

    if [[ "$RESTART_ONLY_IF_AUTOSTART" == "1" ]]; then
        local policy
        policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$PLEX_CONTAINER_NAME" 2>/dev/null || echo "no")
        if [[ "$policy" != "always" && "$policy" != "unless-stopped" ]]; then
            log "Plex web UI is not accessible but container has restart policy '$policy'. Skipping restart (may be intentionally stopped)."
            return 0
        fi
    fi

    log "Plex web UI is not accessible. Restarting container..."
    if ! docker restart "$PLEX_CONTAINER_NAME"; then
        log_err "docker restart failed for $PLEX_CONTAINER_NAME"
        return 1
    fi

    send_unraid_notify "Check Plex Status" "Plex container restarted" \
        "Plex Docker container was restarted because the web UI was not accessible." "warning"
    log "Plex container restarted."
}

main "$@"

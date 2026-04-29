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

# Plex web UI URL (used to verify the service is responding).
# Prefer http://127.0.0.1:32400/... or your Unraid LAN IP — "localhost" often fails from the host
# when Plex only binds certain interfaces (bridge/custom Docker networking).
PLEX_WEB_UI="http://127.0.0.1:32400/web/index.html"

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

# True if HTTP status means Plex is listening (auth/challenge/redirect still mean "up").
is_plex_http_ok() {
    case "$1" in
        2??|3??|401|403|405) return 0 ;;
        *) return 1 ;;
    esac
}

# GET URL → prints HTTP code or 000
curl_http_code() {
    local url="$1"
    curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" -m "$MAX_TIME" "$url" 2>/dev/null || echo "000"
}

# Path component of URL (e.g. /web/index.html), default /
plex_path_from_url() {
    local u="$1"
    if [[ "$u" =~ ^https?://[^/]+(/.*)$ ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '/'
    fi
}

# Port from URL or 32400
plex_port_from_url() {
    local u="$1"
    if [[ "$u" =~ :([0-9]+)(/|$) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    else
        printf '32400'
    fi
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

    local http_code primary_code inner_code
    local path port loopback_url inner_url

    path="$(plex_path_from_url "$PLEX_WEB_UI")"
    port="$(plex_port_from_url "$PLEX_WEB_UI")"
    loopback_url="http://127.0.0.1:${port}${path}"
    inner_url="http://127.0.0.1:${port}${path}"

    primary_code="$(curl_http_code "$PLEX_WEB_UI")"
    http_code="$primary_code"

    if is_plex_http_ok "$http_code"; then
        log "Plex web UI responded (HTTP $http_code). No action needed."
        return 0
    fi

    # Host often cannot reach Plex via "localhost" or a LAN IP (binding/firewall); try numeric loopback on the server.
    if [[ "$PLEX_WEB_UI" != "$loopback_url" ]]; then
        http_code="$(curl_http_code "$loopback_url")"
        if is_plex_http_ok "$http_code"; then
            log "Plex web UI responded via loopback $loopback_url (HTTP $http_code). No action needed."
            return 0
        fi
    fi

    # Last resort: curl from inside the container (Plex listens on 127.0.0.1 there even when host routing fails).
    inner_code=$(docker exec \
        -e "INNER=$inner_url" \
        -e "CT=$CONNECT_TIMEOUT" \
        -e "MT=$MAX_TIME" \
        "$PLEX_CONTAINER_NAME" \
        sh -c 'command -v curl >/dev/null 2>&1 || { echo 000; exit 0; }
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CT" -m "$MT" "$INNER" 2>/dev/null || echo 000' \
        2>/dev/null) || inner_code="000"
    inner_code="${inner_code//$'\r'/}"
    inner_code="${inner_code//$'\n'/}"

    if is_plex_http_ok "$inner_code"; then
        log "Plex web UI responded from inside the container (HTTP $inner_code). Host checks had failed (primary HTTP $primary_code); no restart."
        return 0
    fi

    log "Plex web UI check failed (primary HTTP $primary_code, loopback HTTP ${http_code:-n/a}, in-container HTTP ${inner_code:-000})."

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

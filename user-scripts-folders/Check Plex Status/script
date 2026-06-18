#!/bin/bash
#
# check-plex-status.sh
# Check Plex container and web UI; restart if the UI is down.
#
# Description:
#   Restarts the Plex Docker container when it runs but the web UI does not respond.
#
# Usage:
#   ./check-plex-status.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - PLEX_CONTAINER_NAME: Docker container name
#   - PLEX_WEB_UI: URL for health check
#   - NOTIFY_SCRIPT: dynamix notify path (default set; empty = disabled)
#   - LOG_FILE: optional log file (empty = stdout only)
#   - RESTART_ONLY_IF_AUTOSTART: 1 = skip restart unless policy is always or unless-stopped
#   - NOTIFY_ON_RECOVERY: 1 = notify when Plex recovers
#   - MAX_RESTARTS_PER_DAY: daily restart cap (0 = unlimited)
#   - CONNECT_TIMEOUT / MAX_TIME: curl timeouts for UI check
#
# Note: Progress and errors print to stdout; Unraid User Scripts shows that in the run window. Optional LOG_FILE also appends a copy to disk.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0

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

# Unraid Dynamix notify script (empty = disabled)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# 0 = restart when UI is unreachable (default); 1 = skip unless policy is always or unless-stopped
RESTART_ONLY_IF_AUTOSTART="0"

# Curl timeouts in seconds
CONNECT_TIMEOUT="15"  # Connect timeout
MAX_TIME="30"           # Total timeout for web UI check

# 1 = notify when Plex recovers after being down (requires state file)
NOTIFY_ON_RECOVERY="1"

# Maximum container restarts per calendar day (0 = unlimited)
MAX_RESTARTS_PER_DAY="5"

# State file for cross-run tracking (empty = default beside script)
STATE_FILE=""

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/plex-status.state"
unset _SCRIPT_DIR

###############################################################################

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi
if [[ -n "$STATE_FILE" ]] && [[ "$STATE_FILE" == *".."* || "$STATE_FILE" == "-"* ]]; then
    _ui_msg="Error: STATE_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
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
    echo "$msg"
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
    if ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed. Check NOTIFY_SCRIPT in this script."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "$importance"; then
        log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
        return 1
    fi
}

# True if HTTP status means Plex is listening (auth/challenge/redirect still mean "up").
is_plex_http_ok() {
    case "$1" in
        2??|3??|401|403|405) return 0 ;;
        *) return 1 ;;
    esac
}

_friendly_curl_err() {
    local msg="$1"
    msg="${msg#curl: }"
    if [[ "$msg" == *"Could not resolve host"* ]]; then
        echo "The server name could not be found — check PLEX_WEB_UI in this script."
    elif [[ "$msg" == *"Connection refused"* ]]; then
        echo "Connection refused — is Plex running and is the port in PLEX_WEB_UI correct?"
    elif [[ "$msg" == *"Failed to connect"* ]]; then
        echo "Could not connect — check that Plex is running and PLEX_WEB_UI is correct."
    elif [[ "$msg" == *"timed out"* ]] || [[ "$msg" == *"Timeout"* ]]; then
        echo "The connection timed out — check PLEX_WEB_UI and network."
    else
        echo "$msg"
    fi
}

# GET URL -> prints HTTP code or 000 (curl uses 000 when the connection fails).
curl_http_code() {
    local url="$1" code curl_err
    curl_err=$(mktemp) || { echo "000"; return 0; }
    code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$CONNECT_TIMEOUT" -m "$MAX_TIME" "$url" 2>"$curl_err") || code="000"
    if [[ "$code" == "000" && -s "$curl_err" ]]; then
        log_err "Could not reach Plex at ${url} while checking the web UI. $(_friendly_curl_err "$(tr '\n' ' ' <"$curl_err")")"
    fi
    rm -f "$curl_err"
    echo "$code"
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

# Read state file key=value pairs
read_plex_state() {
    local f="$1"
    [[ ! -f "$f" || ! -r "$f" ]] && return 0
    tr -d '\r' < "$f" 2>/dev/null || true
}

# Write key=value state to file (atomic via temp file)
write_plex_state() {
    local f="$1" dir state_tmp
    dir=$(dirname "$f")
    [[ ! -d "$dir" || ! -w "$dir" ]] && return 1
    state_tmp="${f}.tmp.$$"
    shift
    printf '%s\n' "$@" > "$state_tmp" 2>/dev/null || { rm -f "$state_tmp" 2>/dev/null; return 1; }
    mv -f "$state_tmp" "$f" 2>/dev/null || { rm -f "$state_tmp" 2>/dev/null || true; return 1; }
}

# Get a single key from state file, or default
get_plex_state_key() {
    local f="$1" key="$2" default="$3" val
    val=$(read_plex_state "$f" | grep "^${key}=" | head -n1 | sed 's/^[^=]*=//')
    [[ -z "$val" ]] && echo "$default" || echo "$val"
}

main() {
    if [[ -z "$PLEX_CONTAINER_NAME" ]]; then
        log_err "PLEX_CONTAINER_NAME is empty. Set it to your Plex Docker container name in this script."
        return 1
    fi
    if [[ -z "$PLEX_WEB_UI" || ! "$PLEX_WEB_UI" =~ ^https?:// ]]; then
        log_err "PLEX_WEB_UI must be a full web address starting with http:// or https:// (you entered: ${PLEX_WEB_UI:-empty})"
        return 1
    fi

    if [[ -n "$NOTIFY_SCRIPT" ]] && ! is_safe_notify_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path invalid."
        return 1
    fi

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qxF "$PLEX_CONTAINER_NAME"; then
        log "Plex container '$PLEX_CONTAINER_NAME' is not running. No action taken."
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
        if [[ "$NOTIFY_ON_RECOVERY" == "1" ]]; then
            local was_down
            was_down=$(get_plex_state_key "$STATE_FILE" "was_down" "0")
            if [[ "$was_down" == "1" ]]; then
                log "Plex has recovered! Was unreachable on the previous check."
                send_unraid_notify "Check Plex Status" "Plex container recovered" \
                    "Plex web UI is responding again after being unreachable." "normal"
                write_plex_state "$STATE_FILE" "was_down=0" "consecutive_restarts=0"
            fi
        fi
        log "Plex web UI responded (HTTP $http_code). No action needed."
        return 0
    fi

    # Host often cannot reach Plex via "localhost" or a LAN IP (binding/firewall); try numeric loopback on the server.
    if [[ "$PLEX_WEB_UI" != "$loopback_url" ]]; then
        http_code="$(curl_http_code "$loopback_url")"
        if is_plex_http_ok "$http_code"; then
            if [[ "$NOTIFY_ON_RECOVERY" == "1" ]]; then
                local was_down2
                was_down2=$(get_plex_state_key "$STATE_FILE" "was_down" "0")
                if [[ "$was_down2" == "1" ]]; then
                    log "Plex has recovered (loopback). Was unreachable on the previous check."
                    send_unraid_notify "Check Plex Status" "Plex container recovered" \
                        "Plex web UI is responding again (loopback) after being unreachable." "normal"
                    write_plex_state "$STATE_FILE" "was_down=0" "consecutive_restarts=0"
                fi
            fi
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
        if [[ "$NOTIFY_ON_RECOVERY" == "1" ]]; then
            local was_down3
            was_down3=$(get_plex_state_key "$STATE_FILE" "was_down" "0")
            if [[ "$was_down3" == "1" ]]; then
                log "Plex has recovered (in-container check). Was unreachable on the previous check."
                send_unraid_notify "Check Plex Status" "Plex container recovered" \
                    "Plex web UI is responding again (in-container) after being unreachable." "normal"
                write_plex_state "$STATE_FILE" "was_down=0" "consecutive_restarts=0"
            fi
        fi
        log "Plex web UI responded from inside the container (HTTP $inner_code). Host checks had failed (primary HTTP $primary_code); no restart."
        return 0
    fi

    log "Plex web UI check failed (primary HTTP $primary_code, loopback HTTP ${http_code:-n/a}, in-container HTTP ${inner_code:-000}). Check PLEX_WEB_UI and PLEX_CONTAINER_NAME in this script."

    if [[ "$RESTART_ONLY_IF_AUTOSTART" == "1" ]]; then
        local policy
        policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$PLEX_CONTAINER_NAME" 2>/dev/null || echo "no")
        if [[ "$policy" != "always" && "$policy" != "unless-stopped" ]]; then
            log "Plex web UI is not accessible but container has restart policy '$policy'. Skipping restart (may be intentionally stopped)."
            return 0
        fi
    fi

    # --- Restart backoff: check daily limit ---
    if [[ "$MAX_RESTARTS_PER_DAY" -gt 0 ]]; then
        local today restarts_today last_date
        today=$(date '+%Y-%m-%d')
        last_date=$(get_plex_state_key "$STATE_FILE" "last_restart_date" "")
        restarts_today=$(get_plex_state_key "$STATE_FILE" "restarts_today" "0")
        if [[ "$last_date" != "$today" ]]; then
            restarts_today=0
        fi
        if [[ "$restarts_today" -ge "$MAX_RESTARTS_PER_DAY" ]]; then
            log_err "Daily restart limit reached ($MAX_RESTARTS_PER_DAY). Skipping restart."
            send_unraid_notify "Check Plex Status" "Plex restart limit reached" \
                "Plex web UI is unreachable but $MAX_RESTARTS_PER_DAY restarts already performed today. Manual intervention required." "alert"
            write_plex_state "$STATE_FILE" "was_down=1"
            return 1
        fi
        restarts_today=$((restarts_today + 1))
    fi

    # Record that Plex is down before restarting
    if [[ "$NOTIFY_ON_RECOVERY" == "1" || "$MAX_RESTARTS_PER_DAY" -gt 0 ]]; then
        write_plex_state "$STATE_FILE" "was_down=1" "last_restart_date=${today:-}" "restarts_today=${restarts_today:-0}"
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

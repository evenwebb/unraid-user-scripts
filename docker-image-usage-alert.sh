#!/bin/bash
#
# docker-image-usage-alert.sh
# Alert when docker.img usage crosses warning or critical thresholds.
#
# Description:
#   Notifies once per threshold crossing; resets when usage drops.
#
# Usage:
#   ./docker-image-usage-alert.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - DOCKER_PATH: docker.img mount path
#   - WARNING_THRESHOLD_PCT / CRITICAL_THRESHOLD_PCT: alert levels
#   - SHOW_LARGEST_CONTAINERS / LARGEST_COUNT: optional container breakdown
#   - NOTIFY_SCRIPT: dynamix notify path
#   - LOG_FILE / STATE_FILE: optional logging and state
#
# Note: Output goes to stdout; Unraid User Scripts shows it in the run window.
#
# Author: https://github.com/evenwebb
# Project: https://github.com/evenwebb/unraid-user-scripts
# License: GPL-3.0 · https://github.com/evenwebb/unraid-user-scripts

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Path to Docker data directory (Unraid default: /var/lib/docker)
DOCKER_PATH="/var/lib/docker"

# Usage thresholds in percent
WARNING_THRESHOLD_PCT="70"
CRITICAL_THRESHOLD_PCT="85"

# 1 = show largest containers in notification, 0 = skip
SHOW_LARGEST_CONTAINERS="1"

# Number of containers to list
LARGEST_COUNT="5"

# Unraid dynamix notify script
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# State file for threshold escalation tracking
STATE_FILE=""

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/docker-usage.state"
unset _SCRIPT_DIR

###############################################################################

# Validate paths
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi
if [[ -n "$NOTIFY_SCRIPT" ]] && [[ "$NOTIFY_SCRIPT" == *".."* || "$NOTIFY_SCRIPT" == "-"* ]]; then
    echo "Error: NOTIFY_SCRIPT path invalid." >&2
    exit 1
fi
if [[ -n "$STATE_FILE" ]] && [[ "$STATE_FILE" == *".."* || "$STATE_FILE" == "-"* ]]; then
    echo "Error: STATE_FILE path invalid." >&2
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

is_safe_path() {
    local p="$1"
    [[ -z "$p" ]] && return 1
    [[ "$p" == *".."* || "$p" == "-"* || "$p" == *$'"'"'
'"'"'* ]] && return 1
    return 0
}

# Read last-reported threshold level (0=none, 1=warning, 2=critical)
read_state_level() {
    local f="$1" line
    [[ ! -f "$f" || ! -r "$f" ]] && { echo 0; return 0; }
    IFS= read -r line < "$f" || true
    line="${line//$'\r'/}"
    line="${line//[^0-9]/}"
    case "$line" in
        0|1|2) echo "$line" ;;
        *) echo 0 ;;
    esac
}

write_state_level() {
    local f="$1" val="$2" dir state_tmp
    dir=$(dirname "$f")
    if [[ ! -d "$dir" || ! -w "$dir" ]]; then
        log_err "Cannot write state directory: $dir"
        return 1
    fi
    state_tmp="${f}.tmp.$$"
    printf '%s\n' "$val" > "$state_tmp" 2>/dev/null || { log_err "Cannot write state temp file"; return 1; }
    mv -f "$state_tmp" "$f" 2>/dev/null || { rm -f "$state_tmp" 2>/dev/null || true; log_err "Cannot commit state file: $f"; return 1; }
}

# Get filesystem usage percentage for a path
get_usage_pct() {
    local path="$1"
    df "$path" 2>/dev/null | awk 'NR==2 {gsub(/%/,""); print $(NF-1)}' || echo "0"
}

# Get human-readable usage (used / total)
get_usage_human() {
    local path="$1"
    local used total
    used=$(df -h "$path" 2>/dev/null | awk 'NR==2 {print $3}' || echo "N/A")
    total=$(df -h "$path" 2>/dev/null | awk 'NR==2 {print $2}' || echo "N/A")
    echo "${used} / ${total}"
}

# List largest containers by size (requires docker)
list_largest_containers() {
    local count="$1"
    docker ps --format '{{.Names}}' 2>/dev/null | while IFS= read -r cname; do
        [[ -z "$cname" ]] && continue
        local size
        size=$(docker ps -s --format '{{.Size}}' --filter "name=^${cname}$" 2>/dev/null | awk '{print $NF}' | sed 's/)$//' || echo "0B")
        [[ -z "$size" ]] && size="0B"
        echo "${size} ${cname}"
    done | sort -rh | head -n "$count"
}

# Trigger Unraid notification
send_unraid_notify() {
    local event="$1" subject="$2" description="$3" importance="${4:-normal}"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    is_safe_path "$NOTIFY_SCRIPT" || return 0
    "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "$importance" 2>/dev/null || true
}

main() {
    if [[ ! "$WARNING_THRESHOLD_PCT" =~ ^[0-9]+$ ]] || [[ ! "$CRITICAL_THRESHOLD_PCT" =~ ^[0-9]+$ ]]; then
        log_err "WARNING_THRESHOLD_PCT and CRITICAL_THRESHOLD_PCT must be integers."
        return 1
    fi
    if [[ "$WARNING_THRESHOLD_PCT" -ge "$CRITICAL_THRESHOLD_PCT" ]]; then
        log_err "WARNING_THRESHOLD_PCT ($WARNING_THRESHOLD_PCT) must be less than CRITICAL_THRESHOLD_PCT ($CRITICAL_THRESHOLD_PCT)."
        return 1
    fi
    if ! is_safe_path "$DOCKER_PATH"; then
        log_err "DOCKER_PATH invalid."
        return 1
    fi
    if [[ ! -d "$DOCKER_PATH" ]]; then
        log_err "DOCKER_PATH not found: $DOCKER_PATH"
        return 1
    fi

    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log_err "Docker daemon not available (is Docker started in Unraid?)."
        return 1
    fi

    local usage_pct usage_human prev_level current_level
    usage_pct=$(get_usage_pct "$DOCKER_PATH")
    usage_human=$(get_usage_human "$DOCKER_PATH")
    prev_level=$(read_state_level "$STATE_FILE")

    log "Docker image usage: ${usage_pct}% (${usage_human})"

    # Determine current threshold level
    current_level=0
    if [[ "$usage_pct" -ge "$CRITICAL_THRESHOLD_PCT" ]]; then
        current_level=2
    elif [[ "$usage_pct" -ge "$WARNING_THRESHOLD_PCT" ]]; then
        current_level=1
    fi

    # Build container size info
    local container_info=""
    if [[ "$SHOW_LARGEST_CONTAINERS" == "1" ]] && [[ "$LARGEST_COUNT" =~ ^[0-9]+$ ]] && [[ "$LARGEST_COUNT" -gt 0 ]]; then
        local c_list
        c_list=$(list_largest_containers "$LARGEST_COUNT")
        if [[ -n "$c_list" ]]; then
            container_info=$'\n'"Largest containers:"$'\n'"$c_list"
        fi
    fi

    if [[ "$current_level" -eq 2 && "$prev_level" -lt 2 ]]; then
        log "CRITICAL: Docker image at ${usage_pct}% (threshold: ${CRITICAL_THRESHOLD_PCT}%)."
        send_unraid_notify "critical" "Docker Image Critical" \
            "Docker image critically full" \
            "Docker image usage is ${usage_pct}% (${usage_human}). Containers may fail if it fills completely.${container_info}" \
            "alert"
        write_state_level "$STATE_FILE" 2 || true
    elif [[ "$current_level" -eq 1 && "$prev_level" -lt 1 ]]; then
        log "WARNING: Docker image at ${usage_pct}% (threshold: ${WARNING_THRESHOLD_PCT}%)."
        send_unraid_notify "warning" "Docker Image Warning" \
            "Docker image usage warning" \
            "Docker image usage is ${usage_pct}% (${usage_human}). Consider cleaning up unused images/volumes.${container_info}" \
            "warning"
        write_state_level "$STATE_FILE" 1 || true
    elif [[ "$current_level" -eq 0 && "$prev_level" -gt 0 ]]; then
        log "Docker image usage dropped to ${usage_pct}% — below all thresholds. Resetting state."
        write_state_level "$STATE_FILE" 0 || true
    else
        log "Usage is at level ${current_level} (previous: ${prev_level}); no new alert needed."
    fi

    return 0
}

main "$@"

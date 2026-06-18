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
#   - LOG_FILE / STATE_FILE / LOCK_FILE: optional logging, state, and run lock
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

# Path to Docker data directory (Unraid default: /var/lib/docker)
DOCKER_PATH="/var/lib/docker"

# Usage thresholds in percent
WARNING_THRESHOLD_PCT="70"
CRITICAL_THRESHOLD_PCT="85"

# 1 = show largest containers in notification, 0 = skip
SHOW_LARGEST_CONTAINERS="1"

# Number of containers to list
LARGEST_COUNT="5"

# Unraid Dynamix notify script (empty = disabled)
NOTIFY_SCRIPT="/usr/local/emhttp/plugins/dynamix/scripts/notify"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Alert escalation state (empty = docker-usage.state beside this script)
STATE_FILE=""

# Prevent concurrent runs (empty = disabled; e.g. /tmp/docker-image-usage-alert.lock)
LOCK_FILE=""

# Default state file: same dir as this script
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$STATE_FILE" ]] && STATE_FILE="${_SCRIPT_DIR}/docker-usage.state"
unset _SCRIPT_DIR

###############################################################################

# Validate paths
if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi
if [[ -n "$NOTIFY_SCRIPT" ]] && [[ "$NOTIFY_SCRIPT" == *".."* || "$NOTIFY_SCRIPT" == "-"* ]]; then
    _ui_msg="Error: NOTIFY_SCRIPT path invalid."
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
if [[ -n "$LOCK_FILE" ]] && [[ "$LOCK_FILE" == *".."* || "$LOCK_FILE" == "-"* ]]; then
    _ui_msg="Error: LOCK_FILE path invalid."
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

# List largest containers by writable layer size (single docker call; fallback to container dir du)
list_largest_containers() {
    local count="$1"
    if docker ps -s --format '{{.Size}}\t{{.Names}}' 2>/dev/null | grep -q .; then
        docker ps -s --format '{{.Size}}\t{{.Names}}' 2>/dev/null | while IFS=$'\t' read -r size name; do
            [[ -z "$name" ]] && continue
            echo "${size%% *} ${name}"
        done | sort -rh | head -n "$count"
        return 0
    fi
    local containers_dir="${DOCKER_PATH}/containers"
    [[ -d "$containers_dir" ]] || return 0
    du -sk "$containers_dir"/* 2>/dev/null | sort -rn | head -n "$count" | while read -r kb dir; do
        local cid cname
        cid=$(basename "$dir")
        cname=$(docker inspect -f '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||')
        echo "${kb}K ${cname:-$cid}"
    done
}

# Trigger Unraid notification
send_unraid_notify() {
    local event="$1" subject="$2" description="$3" importance="${4:-normal}"
    [[ -z "$NOTIFY_SCRIPT" || ! -x "$NOTIFY_SCRIPT" ]] && return 0
    if ! is_safe_path "$NOTIFY_SCRIPT"; then
        log_err "NOTIFY_SCRIPT path is not allowed. Check NOTIFY_SCRIPT in this script."
        return 1
    fi
    if ! "$NOTIFY_SCRIPT" -e "$event" -s "$subject" -d "$description" -i "$importance"; then
        log_err "Unraid notification could not be sent. Check NOTIFY_SCRIPT in this script (currently: $NOTIFY_SCRIPT)."
        return 1
    fi
}

main() {
    local lock_dir
    if [[ -n "$LOCK_FILE" ]]; then
        if ! command -v flock &>/dev/null; then
            log_err "LOCK_FILE is set but flock is not available."
            return 1
        fi
        lock_dir=$(dirname "$LOCK_FILE")
        if [[ -n "$lock_dir" && "$lock_dir" != "." && ! -d "$lock_dir" ]]; then
            log_err "LOCK_FILE directory does not exist: $lock_dir"
            return 1
        fi
        exec 200>"$LOCK_FILE"
        if ! flock -n 200; then
            log_err "Another copy is already running (lock: $LOCK_FILE)."
            return 1
        fi
    elif command -v flock &>/dev/null && [[ -n "$STATE_FILE" ]]; then
        lock_dir=$(dirname "$STATE_FILE")
        [[ -d "$lock_dir" ]] || mkdir -p "$lock_dir" 2>/dev/null || true
        exec 201>>"$STATE_FILE"
        flock -w 30 201 || { log_err "Could not lock state file: $STATE_FILE"; return 1; }
    fi

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
    if [[ ! "$usage_pct" =~ ^[0-9]+$ ]]; then
        log_err "Could not read docker.img usage from $DOCKER_PATH. Check DOCKER_PATH in this script."
        return 1
    fi
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
        send_unraid_notify "Docker Image Critical" "Docker image critically full" \
            "Docker image usage is ${usage_pct}% (${usage_human}). Containers may fail if it fills completely.${container_info}" \
            "alert"
        write_state_level "$STATE_FILE" 2 || true
    elif [[ "$current_level" -eq 1 && "$prev_level" -lt 1 ]]; then
        log "WARNING: Docker image at ${usage_pct}% (threshold: ${WARNING_THRESHOLD_PCT}%)."
        send_unraid_notify "Docker Image Warning" "Docker image usage warning" \
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

main "$@" || exit 1

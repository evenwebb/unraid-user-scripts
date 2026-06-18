#!/bin/bash
#
# clean-docker-log-size.sh
# Truncate Docker container logs to free space in docker.img.
#
# Description:
#   Shows before/after sizes. Safe for running containers.
#
# Usage:
#   ./clean-docker-log-size.sh
#   Edit variables in EDIT FOR YOUR SETUP below.
#
# Configuration (edit script variables below):
#   - DOCKER_CONTAINERS_PATH: path to container log directory
#   - LOG_FILE: optional log file
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

# Docker container logs (Unraid default path)
DOCKER_CONTAINERS_PATH="/var/lib/docker/containers"

LOG_FILE=""                  # Append output here (empty = stdout only)
HEAD_COUNT="60"              # Largest containers to list before/after truncation

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    _ui_msg="Error: LOG_FILE path invalid."
    echo "$_ui_msg"
    echo "$_ui_msg" >&2
    exit 1
fi
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    exec > >(tee -a "$LOG_FILE") 2>&1
fi

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
}

# Human-readable size from du -k kilobyte count.
_format_size() {
    local kb="$1"
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec --suffix=B "$((kb * 1024))" 2>/dev/null && return
    fi
    if [[ "$kb" -ge 1048576 ]]; then
        printf '%.1fG' "$(awk "BEGIN {print $kb/1048576}")"
    elif [[ "$kb" -ge 1024 ]]; then
        printf '%.1fM' "$(awk "BEGIN {print $kb/1024}")"
    else
        printf '%sK' "$kb"
    fi
}

_container_name() {
    local cid="$1"
    docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||' || echo "${cid:0:12}"
}

# Print log listing; sets _log_list_count and _log_list_total_kb.
_log_list_count=0
_log_list_total_kb=0
list_docker_log_sizes() {
    local tmp logfile cid cname kb count total_kb
    tmp=$(mktemp)

    while IFS= read -r -d '' logfile; do
        kb=$(du -k "$logfile" 2>/dev/null | awk '{print $1}')
        [[ -z "$kb" ]] && kb=0
        cid=$(echo "$logfile" | grep -oE '[a-f0-9]{64}' | head -n1)
        if [[ -n "$cid" ]]; then
            cname=$(_container_name "$cid")
        else
            cname=$(basename "$(dirname "$logfile")")
        fi
        printf '%s\t%s\n' "$kb" "$cname" >> "$tmp"
    done < <(find "$DOCKER_CONTAINERS_PATH" -type f -name '*.log' -print0 2>/dev/null)

    count=$(wc -l < "$tmp" | tr -d ' ')
    total_kb=$(awk -F'\t' '{s+=$1} END {print s+0}' "$tmp")
    _log_list_count=$count
    _log_list_total_kb=$total_kb

    if [[ "$count" -eq 0 ]]; then
        echo "  (no log files found)"
        rm -f "$tmp"
        return
    fi

    printf '%8s  %s\n' 'SIZE' 'CONTAINER'
    printf '%8s  %s\n' '----' '---------'
    sort -t$'\t' -k1 -rn "$tmp" | head -n "$HEAD_COUNT" | while IFS=$'\t' read -r kb cname; do
        printf '%8s  %s\n' "$(_format_size "$kb")" "$cname"
    done
    rm -f "$tmp"

    echo ""
    if [[ "$count" -gt "$HEAD_COUNT" ]]; then
        printf 'Total: %s across %d log files (showing largest %d)\n' \
            "$(_format_size "$total_kb")" "$count" "$HEAD_COUNT"
    else
        printf 'Total: %s across %d log file(s)\n' "$(_format_size "$total_kb")" "$count"
    fi
}

print_log_section() {
    local title="$1"
    echo ""
    echo "$title"
    echo "----------------------------------------"
    list_docker_log_sizes
}

main() {
    if ! command -v docker &>/dev/null; then
        log_err "Docker not found or not in PATH."
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_err "Docker daemon not available (is Docker started in Unraid?)."
        return 1
    fi

    if [[ "$DOCKER_CONTAINERS_PATH" == *".."* || "$DOCKER_CONTAINERS_PATH" == "-"* ]]; then
        log_err "DOCKER_CONTAINERS_PATH invalid."
        return 1
    fi
    if [[ -z "$DOCKER_CONTAINERS_PATH" ]]; then
        log_err "DOCKER_CONTAINERS_PATH is empty."
        return 1
    fi
    if [[ ! "$HEAD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        log_err "HEAD_COUNT must be a positive integer, got: $HEAD_COUNT"
        return 1
    fi
    if [[ "$DOCKER_CONTAINERS_PATH" == /var/lib/docker* ]] && [[ $EUID -ne 0 ]]; then
        log_err "This script must be run as root when using /var/lib/docker."
        return 1
    fi
    if [[ ! -d "$DOCKER_CONTAINERS_PATH" ]]; then
        log_err "Directory not found: $DOCKER_CONTAINERS_PATH"
        return 1
    fi

    local before_kb after_kb freed_kb log_count trunc_fail

    print_log_section "Before:"
    before_kb=$_log_list_total_kb
    log_count=$_log_list_count

    log "Truncating $log_count container log file(s)..."
    trunc_fail=0
    while IFS= read -r -d '' logfile; do
        if [[ -f "$logfile" ]]; then
            if ! : > "$logfile" 2>/dev/null; then
                log_err "Could not truncate log file: $logfile"
                trunc_fail=1
            fi
        fi
    done < <(find "$DOCKER_CONTAINERS_PATH" -name '*.log' -print0 2>/dev/null)
    if [[ "$trunc_fail" -ne 0 ]]; then
        log_err "One or more log files could not be truncated."
        return 1
    fi
    sleep 2

    print_log_section "After:"
    after_kb=$_log_list_total_kb
    freed_kb=$((before_kb - after_kb))
    if [[ "$freed_kb" -lt 0 ]]; then
        freed_kb=0
    fi

    echo ""
    log "Freed $(_format_size "$freed_kb") (was $(_format_size "$before_kb"), now $(_format_size "$after_kb"))."
    echo ""
}

main "$@"

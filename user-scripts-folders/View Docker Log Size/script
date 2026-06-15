#!/bin/bash
#
# view-docker-log-size.sh
# Displays sizes of Docker container log files to diagnose docker.img growth
#
# Description:
#   Lists Docker container log files sorted by size. Use to see if runaway
#   logging is filling docker.img before running clean-docker-log-size.sh.
#
# Usage:
#   ./view-docker-log-size.sh
#
# Configuration (edit script variables below):
#   - DOCKER_CONTAINERS_PATH: Path to Docker container data (default Unraid)
#   - HEAD_COUNT: Number of lines to show (default 60)
#
# Output goes to stdout; Unraid User Scripts captures it in the GUI.
##   - PER_CONTAINER_BREAKDOWN: 1 = group log sizes by container name, 0 = raw file list
#   - SHOW_TREND: 1 = show size deltas from previous run (requires TREND_FILE)

# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u
set -o pipefail

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Docker containers directory - default Unraid location
DOCKER_CONTAINERS_PATH="/var/lib/docker/containers"

# Number of log entries to display
HEAD_COUNT="60"

# 1 = group by container name (uses docker inspect for readable names)
PER_CONTAINER_BREAKDOWN="1"

# Optional state file to track size trends across runs (empty = no trend tracking)
TREND_FILE=""

# 1 = show size deltas from previous run (requires TREND_FILE)
SHOW_TREND="0"

###############################################################################

# Default trend file
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[[ -z "$TREND_FILE" ]] && [[ "$SHOW_TREND" == "1" ]] && TREND_FILE="${_SCRIPT_DIR}/docker-log-sizes.trend"
unset _SCRIPT_DIR

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

# Map container ID to container name via docker inspect
_container_name() {
    local cid="$1"
    docker inspect --format '{{.Name}}' "$cid" 2>/dev/null | sed 's|^/||' || echo "$cid"
}

list_docker_log_sizes() {
    if [[ "$PER_CONTAINER_BREAKDOWN" == "1" ]]; then
        # Group by container: show total log size per container with readable names
        local tmp cid cname log_sum
        tmp=$(mktemp)
        while IFS= read -r -d '' logfile; do
            cid=$(echo "$logfile" | grep -oE '[a-f0-9]{64}' | head -n1)
            if [[ -n "$cid" ]]; then
                cname=$(_container_name "$cid")
            else
                cname="unknown"
            fi
            size=$(du -k "$logfile" 2>/dev/null | awk '{print $1}')
            [[ -z "$size" ]] && size=0
            echo "$cname $size"
        done < <(find "$DOCKER_CONTAINERS_PATH" -xdev -type f -name "*.log" -print0 2>/dev/null)
        # Aggregate by name
        awk '{sum[$1]+=$2} END {for (c in sum) printf "%d\t%s\n", sum[c], c}' > "$tmp"
        sort -t$'\t' -k1 -rn "$tmp" | head -n "$HEAD_COUNT" | while IFS=$'\t' read -r kb name; do
            printf '%s\t%s\n' "$(numfmt --to=iec --suffix=B "$((kb * 1024))" 2>/dev/null || echo "${kb}K")" "$name"
        done
        rm -f "$tmp"
    else
        du -ah "$DOCKER_CONTAINERS_PATH/" 2>/dev/null | grep "\.log$" | sort -rh | head -n "$HEAD_COUNT" || true
    fi
}

# Read/write trend state
read_trend_state() {
    local f="$1"
    [[ ! -f "$f" || ! -r "$f" ]] && return 0
    tr -d '\r' < "$f" 2>/dev/null || true
}

write_trend_state() {
    local f="$1" dir state_tmp
    dir=$(dirname "$f")
    [[ ! -d "$dir" || ! -w "$dir" ]] && return 1
    state_tmp="${f}.tmp.$$"
    # Write current du output
    du -k "$DOCKER_CONTAINERS_PATH" 2>/dev/null | sort -k2 > "$state_tmp"
    mv -f "$state_tmp" "$f" 2>/dev/null || { rm -f "$state_tmp" 2>/dev/null || true; return 1; }
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

    if [[ -z "$DOCKER_CONTAINERS_PATH" ]]; then
        log_err "DOCKER_CONTAINERS_PATH must be set."
        return 1
    fi
    if [[ ! "$HEAD_COUNT" =~ ^[1-9][0-9]*$ ]]; then
        log_err "HEAD_COUNT must be a positive integer, got: $HEAD_COUNT"
        return 1
    fi
    if [[ ! -d "$DOCKER_CONTAINERS_PATH" ]]; then
        log_err "Directory not found: $DOCKER_CONTAINERS_PATH"
        return 1
    fi

    log "Docker container log sizes (largest first):"
    list_docker_log_sizes

    if [[ "$SHOW_TREND" == "1" && -n "$TREND_FILE" ]]; then
        if [[ -f "$TREND_FILE" ]]; then
            log ""
            log "Size deltas from previous run:"
            local total_now total_prev delta
            total_now=$(du -k "$DOCKER_CONTAINERS_PATH" 2>/dev/null | awk '{s+=$1}END{print s}')
            total_now="${total_now:-0}"
            total_prev=$(read_trend_state "$TREND_FILE" | awk '{s+=$1}END{print s}')
            total_prev="${total_prev:-0}"
            delta=$((total_now - total_prev))
            if [[ $delta -gt 0 ]]; then
                log "  Total log growth: +$(numfmt --to=iec --suffix=B "$((delta * 1024))" 2>/dev/null || echo "${delta}K")"
            elif [[ $delta -lt 0 ]]; then
                log "  Total log shrinkage: $(numfmt --to=iec --suffix=B "$((delta * -1024))" 2>/dev/null || echo "${delta}K")"
            else
                log "  No change in total log size"
            fi
        fi
        write_trend_state "$TREND_FILE"
    fi
}

main "$@"

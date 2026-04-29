#!/bin/bash
#
# clean-docker-log-size.sh
# Truncates Docker container log files to free space in docker.img
#
# Description:
#   Finds all .log files under Docker's container directory, shows sizes before
#   cleanup, truncates them to zero, then shows sizes after. Useful when
#   docker.img is filling up due to runaway container logging.
#
# Usage:
#   ./clean-docker-log-size.sh
#
# Configuration:
#   - DOCKER_CONTAINERS_PATH: Path to Docker container data (default Unraid location)
#   - LOG_FILE: Optional; when set, append logs here (empty = stdout only)
#   - HEAD_COUNT: Number of log entries to show in before/after listing
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

# Docker containers directory - default Unraid location
DOCKER_CONTAINERS_PATH="/var/lib/docker/containers"

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Number of log entries to show in before/after listing
HEAD_COUNT="60"

if [[ -n "$LOG_FILE" ]] && [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* ]]; then
    echo "Error: LOG_FILE path invalid." >&2
    exit 1
fi
if [[ -n "$LOG_FILE" ]]; then
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    exec > >(tee -a "$LOG_FILE")
fi

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

list_docker_log_sizes() {
    du -ah "$DOCKER_CONTAINERS_PATH/" 2>/dev/null | grep -v "/$" | sort -rh | head -n "$HEAD_COUNT" | grep -F '.log' || true
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

    echo ""
    echo "Before:"
    echo "====================================================================================================================================================================================="
    list_docker_log_sizes
    echo "====================================================================================================================================================================================="
    log "Truncating container logs..."
    while IFS= read -r -d '' logfile; do
        [[ -f "$logfile" ]] && : > "$logfile"
    done < <(find "$DOCKER_CONTAINERS_PATH" -name '*.log' -print0 2>/dev/null)
    sleep 2
    log "Cleaning complete."
    echo ""
    echo "After:"
    echo "====================================================================================================================================================================================="
    list_docker_log_sizes
    echo ""
}

main "$@"

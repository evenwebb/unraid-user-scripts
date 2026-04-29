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
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

###############################################################################
# EDIT FOR YOUR SETUP
###############################################################################

# Docker containers directory - default Unraid location
DOCKER_CONTAINERS_PATH="/var/lib/docker/containers"

# Number of log entries to display
HEAD_COUNT="60"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

list_docker_log_sizes() {
    # Filter for .log files first, then sort by size, then limit output
    du -ah "$DOCKER_CONTAINERS_PATH/" 2>/dev/null | grep "\.log$" | sort -rh | head -n "$HEAD_COUNT" || true
}

main() {
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
}

main "$@"

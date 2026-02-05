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
# Configuration:
#   - DOCKER_CONTAINERS_PATH: Path to Docker container data (default Unraid)
#   - HEAD_COUNT: Number of lines to show (default 60)
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Docker containers directory - default Unraid location
DOCKER_CONTAINERS_PATH="/var/lib/docker/containers"

# Number of log entries to display
HEAD_COUNT="60"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

list_docker_log_sizes() {
    du -ah "$DOCKER_CONTAINERS_PATH/" 2>/dev/null | grep -v "/$" | sort -rh | head -n "$HEAD_COUNT" | grep .log || true
}

main() {
    if [[ ! -d "$DOCKER_CONTAINERS_PATH" ]]; then
        log "Directory not found: $DOCKER_CONTAINERS_PATH"
        return 1
    fi
    log "Docker container log sizes (largest first):"
    list_docker_log_sizes
}

main "$@"

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
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

# Docker containers directory - default Unraid location
DOCKER_CONTAINERS_PATH="/var/lib/docker/containers"

# Number of log entries to show in before/after listing
HEAD_COUNT="60"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

list_docker_log_sizes() {
    du -ah "$DOCKER_CONTAINERS_PATH/" 2>/dev/null | grep -v "/$" | sort -rh | head -n "$HEAD_COUNT" | grep -F '.log' || true
}

main() {
    if [[ ! -d "$DOCKER_CONTAINERS_PATH" ]]; then
        log "Directory not found: $DOCKER_CONTAINERS_PATH"
        return 1
    fi

    echo ""
    echo "Before:"
    echo "====================================================================================================================================================================================="
    list_docker_log_sizes
    echo "====================================================================================================================================================================================="
    log "Truncating container logs..."
    while IFS= read -r -d '' logfile; do
        [[ -f "$logfile" ]] && cat /dev/null > "$logfile"
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

#!/bin/bash
#
# delete-dangling-images.sh
# Removes Docker images that are untagged (dangling) to free space in docker.img
#
# Description:
#   Deletes all Docker images with no tag (intermediate or leftover build images).
#   Reduces docker.img size. Safe to run; only removes unreferenced images.
#
# Usage:
#   ./delete-dangling-images.sh
#
# Configuration:
#   None required.
#
# Author: https://github.com/evenwebb
# License: GPL-3.0
#

set -u

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

main() {
    if ! command -v docker &>/dev/null; then
        log "Docker not found or not in PATH."
        return 1
    fi
    log "Removing dangling Docker images..."
    removed=$(docker images --quiet --filter "dangling=true" 2>/dev/null)
    if [[ -z "$removed" ]]; then
        log "No dangling images found."
        return 0
    fi
    while IFS= read -r id; do
        [[ -n "$id" ]] && docker rmi "$id" 2>/dev/null || true
    done <<< "$removed"
    log "Finished. If errors appeared above, some images may have been in use."
}

main "$@"

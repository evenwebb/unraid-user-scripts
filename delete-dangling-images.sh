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

###############################################################################

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
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

    log "Removing dangling Docker images..."
    local removed
    removed="$(docker images --quiet --filter "dangling=true" 2>/dev/null || true)"
    if [[ -z "$removed" ]]; then
        log "No dangling images found."
        return 0
    fi

    local count=0
    while IFS= read -r id; do
        if [[ -n "$id" ]]; then
            if docker rmi "$id"; then
                ((count++)) || true
            fi
        fi
    done <<< "$removed"

    log "Removed $count dangling image(s)."
}

main "$@"

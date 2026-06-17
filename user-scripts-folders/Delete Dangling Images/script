#!/bin/bash
#
# delete-dangling-images.sh
# Remove untagged (dangling) Docker images to free docker.img space.
#
# Description:
#   Only removes dangling images — not images in use by containers.
#
# Usage:
#   ./delete-dangling-images.sh
#
# Configuration (edit script variables below):
#   - No user settings — runs docker rmi on dangling images
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

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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
    echo "$msg" >&2
}

main() {
    if ! command -v docker &>/dev/null; then
        log_err "Docker not found or not in PATH."
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_err "Docker daemon not available — is Docker enabled in Unraid? (Settings → Docker → Enable Docker)"
        return 1
    fi

    log "Removing dangling Docker images..."
    local removed list_err
    list_err=$(mktemp) || { log_err "Could not create temp file."; return 1; }
    if ! removed="$(docker images --quiet --filter "dangling=true" 2>"$list_err")"; then
        log_err "Could not list dangling Docker images: $(tr '\n' ' ' <"$list_err")"
        rm -f "$list_err"
        return 1
    fi
    rm -f "$list_err"
    if [[ -z "$removed" ]]; then
        log "No dangling images found."
        return 0
    fi

    local count=0 failures=0
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        if docker rmi "$id" >/dev/null 2>&1; then
            ((count++)) || true
        else
            log_err "Could not remove dangling image ${id} (it may still be referenced)."
            ((failures++)) || true
        fi
    done <<< "$removed"

    log "Removed $count dangling image(s)."
    if [[ "$failures" -gt 0 ]]; then
        log_err "$failures dangling image(s) could not be removed."
        return 1
    fi
}

main "$@"

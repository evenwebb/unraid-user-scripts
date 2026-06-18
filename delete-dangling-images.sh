#!/bin/bash
#
# delete-dangling-images.sh
# Remove untagged (dangling) Docker images to free docker.img space.
#
# Description:
#   Only removes dangling images - not images in use by containers.
#
# Usage:
#   ./delete-dangling-images.sh
#
# Configuration (edit script variables below):
#   - LOG_FILE: optional log file (empty = stdout only)
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

# Optional: append logs to file (empty = stdout only)
LOG_FILE=""

# Uses `docker image prune -f --filter dangling=true` - removes untagged images only,
# not images referenced by stopped containers or tags.

###############################################################################

# Validate LOG_FILE path (reject path traversal, option-like paths, newlines)
if [[ -n "$LOG_FILE" ]]; then
    if [[ "$LOG_FILE" == *".."* || "$LOG_FILE" == "-"* || "$LOG_FILE" == *$'\n'* ]]; then
        _ui_msg="Error: LOG_FILE path invalid (reject .., - prefix, or newlines)."
        echo "$_ui_msg"
        echo "$_ui_msg" >&2
        exit 1
    fi
fi

# --- No further user configuration below ---

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}
log_err() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*"
    echo "$msg"
    [[ -n "$LOG_FILE" ]] && echo "$msg" >> "$LOG_FILE"
}

main() {
    if ! command -v docker &>/dev/null; then
        log_err "Docker not found or not in PATH."
        return 1
    fi
    if ! docker info >/dev/null 2>&1; then
        log_err "Docker daemon not available - is Docker enabled in Unraid? (Settings → Docker → Enable Docker)"
        return 1
    fi

    log "Removing dangling Docker images..."
    local prune_output prune_ec
    prune_output=$(docker image prune -f --filter dangling=true 2>&1) || prune_ec=$?
    prune_ec=${prune_ec:-0}

    if [[ $prune_ec -ne 0 ]]; then
        log_err "docker image prune failed: $prune_output"
        return 1
    fi

    if [[ -n "$prune_output" ]]; then
        log "$prune_output"
    else
        log "No dangling images found."
    fi
}

main "$@"
